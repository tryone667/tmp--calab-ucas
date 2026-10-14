# -*- coding: utf-8 -*-
"""离线仿真结果分析器（零联网、纯确定性）
用法: python analyze.py <sim_dir> [--json out.json] [--card out.md] [--emit-web <webdir>]

输入（<sim_dir> 内）: run.log / inst_ram.mif / dump.vcd
输出: sim_result.json（结构化）、sim_card.md（人读卡片）、可选 sim_data.js（给 viewer 用）
"""
import re, sys, os, json, argparse

# ---------- 1) 解析 run.log ----------
def parse_log(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    res = {"status": "UNKNOWN", "test_points": [], "errors": []}
    for m in re.finditer(r"----\[\s*(\d+) ns\] Number 8'd(\d+) Functional Test Point (PASS|Error)!!!", text):
        res["test_points"].append({"num": int(m.group(2)), "time_ns": int(m.group(1)), "result": m.group(3)})
    for m in re.finditer(
        r"\[\s*(\d+) ns\] Error!!!\s*\n\s*reference: PC = 0x([0-9a-fA-F]+), wb_rf_wnum = 0x([0-9a-fA-F]+), wb_rf_wdata = 0x([0-9a-fA-F]+)\s*\n\s*mycpu\s*: PC = 0x([0-9a-fA-F]+), wb_rf_wnum = 0x([0-9a-fA-F]+), wb_rf_wdata = 0x([0-9a-fA-F]+)", text):
        res["errors"].append({
            "kind": "wb_mismatch",
            "time_ns": int(m.group(1)),
            "ref": {"pc": int(m.group(2), 16), "wnum": int(m.group(3), 16), "wdata": int(m.group(4), 16)},
            "got": {"pc": int(m.group(5), 16), "wnum": int(m.group(6), 16), "wdata": int(m.group(7), 16)},
        })
    for m in re.finditer(r"\[\s*(\d+) ns\] Error\((\d+)\)!!! Occurred in number 8'd(\d+) Functional Test Point!", text):
        res["errors"].append({"kind": "func_point", "time_ns": int(m.group(1)), "point": int(m.group(3))})
    if "----PASS!!!" in text:
        res["status"] = "PASS"
    elif res["errors"] or "Fail!!!Total" in text:
        res["status"] = "FAIL"
    m = re.search(r"Fail!!!Total (\d+) errors!", text)
    if m:
        res["total_errors"] = int(m.group(1))
    return res

# ---------- 2) 指令提取（PC -> mif 行 -> 译码） ----------
def load_mif_words(path):
    words = []
    for line in open(path, encoding='utf-8', errors='replace'):
        s = line.strip()
        if s:
            words.append(int(s, 2))
    return words

OPS = [
    ("add.w",  lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x00),
    ("sub.w",  lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x02),
    ("slt",    lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x04),
    ("sltu",   lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x05),
    ("nor",    lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x08),
    ("and",    lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x09),
    ("or",     lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x0a),
    ("xor",    lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0 and op3 == 1 and op4 == 0x0b),
    ("slli.w", lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x1 and op3 == 0 and op4 == 0x01),
    ("srli.w", lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x1 and op3 == 0 and op4 == 0x09),
    ("srai.w", lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x1 and op3 == 0 and op4 == 0x11),
    ("addi.w", lambda op, op2, op3, op4, op25: op == 0x00 and op2 == 0x0a),
    ("ld.w",   lambda op, op2, op3, op4, op25: op == 0x0a and op2 == 0x2),
    ("st.w",   lambda op, op2, op3, op4, op25: op == 0x0a and op2 == 0x6),
    ("jirl",   lambda op, op2, op3, op4, op25: op == 0x13),
    ("b",      lambda op, op2, op3, op4, op25: op == 0x14),
    ("bl",     lambda op, op2, op3, op4, op25: op == 0x15),
    ("beq",    lambda op, op2, op3, op4, op25: op == 0x16),
    ("bne",    lambda op, op2, op3, op4, op25: op == 0x17),
    ("lu12i.w",lambda op, op2, op3, op4, op25: op == 0x05 and op25 == 0),
]

def decode_instr(w):
    op = (w >> 26) & 0x3F; op2 = (w >> 22) & 0xF; op3 = (w >> 20) & 0x3; op4 = (w >> 15) & 0x1F; op25 = (w >> 25) & 1
    name = None
    for nm, cond in OPS:
        if cond(op, op2, op3, op4, op25):
            name = nm; break
    return {
        "word": "0x%08X" % w, "name": name,
        "rj": (w >> 5) & 0x1F, "rk": (w >> 10) & 0x1F, "rd": w & 0x1F,
        "imm12": w & 0xFFF,
    }

# ---------- 3) VCD 切片（取错误时刻的寄存器值） ----------
def vcd_snapshot(path, t_target):
    wanted = {}      # id -> reg number
    latest = {}
    time_now = 0
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('$var'):
                m = re.match(r"\$var\s+\w+\s+\d+\s+(\S+)\s+\\?rf\[(\d+)\]", line)
                if m:
                    wanted[m.group(1)] = int(m.group(2))
                continue
            if not line or line.startswith('$'):
                continue
            if line.startswith('#'):
                time_now = int(line[1:])
                if time_now > t_target:
                    break
                continue
            if line[0] in '01xXzZ':
                vid, val = line[1:], line[0]
            elif line[0] == 'b':
                parts = line.split()
                if len(parts) != 2:
                    continue
                valid, vid = parts[0][1:], parts[1]
                val = valid
            else:
                continue
            if vid in wanted:
                latest[wanted[vid]] = val
    return latest  # reg号 -> 位串

def parse_probe_snapshot(text):
    """解析 tb 打印探针的寄存器快照块。"""
    m = re.search(r"===BW-RF-SNAPSHOT===\s*\n"
                  r"BW_TIME\s+(\d+)(?:\s*ns)?\s*\n"
                  r"BW_PC\s+(\S+)\s+BW_WNUM\s+(\S+)\s+BW_WDATA\s+(\S+)\s*\n"
                  r"((?:BW_R\d+\s+\S+\s*\n)+)"
                  r"===BW-RF-END===", text)
    if not m:
        return None
    regs = {}
    for rm in re.finditer(r"BW_R(\d+)\s+(\S+)", m.group(5)):
        regs[int(rm.group(1))] = rm.group(2)
    return {"time_ns": int(m.group(1)), "pc": m.group(2), "wnum": m.group(3), "wdata": m.group(4), "regs": regs}


def bitstr_to_hex(s):
    if any(c in s for c in 'xXzZ'):
        return None
    return int(s, 2)

# ---------- 4) 主流程 ----------
def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument('sim_dir')
    ap.add_argument('--emit-web')
    a = ap.parse_args()
    d = a.sim_dir
    res = parse_log(os.path.join(d, 'run.log'))
    result = {"status": res["status"], "test_points": res["test_points"], "errors": res["errors"]}
    if "total_errors" in res:
        result["total_errors"] = res["total_errors"]

    card_lines = []
    if res["status"] == "PASS":
        tp = len(res["test_points"])
        card_lines.append("✅ PASS ｜ %d/%d 个功能测试点全过" % (tp, tp))
    elif res["status"] == "FAIL" and res["errors"]:
        err = res["errors"][0]
        if err["kind"] == "wb_mismatch":
            pc = err["ref"]["pc"]; t = err["time_ns"]
            log_text = open(os.path.join(d, 'run.log'), encoding='utf-8', errors='replace').read()
            idx = (pc >> 2) & 0x3FFFF
            words = load_mif_words(os.path.join(d, 'inst_ram.mif')) if os.path.exists(os.path.join(d, 'inst_ram.mif')) else []
            instr = decode_instr(words[idx]) if idx < len(words) else {"name": "?", "word": "?"}
            snap = parse_probe_snapshot(log_text)
            reghex = {}
            if snap:
                result["probe_snapshot"] = {"time_ns": snap["time_ns"], "pc": snap["pc"], "wnum": snap["wnum"], "wdata": snap["wdata"]}
                for i, hv in snap["regs"].items():
                    reghex[i] = None if re.search(r'[xXzZ]', hv) else int(hv, 16)
            elif os.path.exists(os.path.join(d, 'dump.vcd')):
                for i, bs in vcd_snapshot(os.path.join(d, 'dump.vcd'), t).items():
                    reghex[i] = bitstr_to_hex(bs)
            rj, rk, rd = instr.get("rj"), instr.get("rk"), instr.get("rd")
            rjv = reghex.get(rj)
            rkv = reghex.get(rk)
            rdv = reghex.get(rd)
            result["instruction"] = {"pc": "0x%08X" % pc, "mif_line": idx, **instr}
            result["registers_at_error"] = {"r%d" % k: ("0x%08X" % v if v is not None else "x") for k, v in sorted(reghex.items())}
            result["operands"] = {"r%d" % rj: rjv, "r%d" % rk: rkv}
            # 自动校验（or/and 都算上，看哪个对得上期望）
            check = {}
            if rjv is not None and rkv is not None:
                check["rj|rk"] = "0x%08X" % (rjv | rkv)
                check["rj&rk"] = "0x%08X" % (rjv & rkv)
                check["rj^rk"] = "0x%08X" % (rjv ^ rkv)
            result["auto_check"] = check
            card_lines.append("❌ FAIL ｜ 出错时刻 t = %d ns" % t)
            card_lines.append("报错指令：%s  r%d, r%d → r%d   （PC=0x%08X，inst_ram.mif 第 %d 行，指令字 %s）"
                              % (instr.get("name") or "?", rj, rk, rd, pc, idx, instr.get("word")))
            card_lines.append("期望写回：r%d ← 0x%08X" % (err["ref"]["wnum"], err["ref"]["wdata"]))
            card_lines.append("实际写回：r%d ← 0x%08X" % (err["got"]["wnum"], err["got"]["wdata"]))
            fmtv = lambda v: ("0x%08X" % v) if v is not None else "?(未知)"
            card_lines.append("操作数（错误时刻快照）：r%d = %s，r%d = %s，r%d = %s" % (rj, fmtv(rjv), rk, fmtv(rkv), rd, fmtv(rdv)))
            if check:
                row = "，".join("%s = %s" % (k, v) for k, v in check.items())
                card_lines.append("自动校验：%s（期望 = %s）" % (row, "0x%08X" % err["ref"]["wdata"]))
        else:
            card_lines.append("❌ FAIL ｜ 功能测试点错误 @ t=%d ns" % err.get("time_ns", -1))
    else:
        card_lines.append("⚠️ 无法判定（没有 PASS/Error 标志）")

    print("\n".join(card_lines))
    json.dump(result, open(os.path.join(d, 'sim_result.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    open(os.path.join(d, 'sim_card.md'), 'w', encoding='utf-8').write("\n".join(card_lines) + "\n")
    if a.emit_web:
        open(os.path.join(a.emit_web, 'sim_data.js'), 'w', encoding='utf-8').write(
            'window.SIM_RESULT = ' + json.dumps(result, ensure_ascii=False) + ';')
        print("[web] sim_data.js ->", a.emit_web)
    print("[json]", os.path.join(d, 'sim_result.json'))

if __name__ == '__main__':
    main()
