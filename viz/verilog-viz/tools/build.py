# -*- coding: utf-8 -*-
"""一键构建：Verilog 源码目录 -> 框图网页。
用法:
  python build.py --src <源码目录> --top <顶层模块名> --out <输出目录> [--sv] [--files a.v b.v] [--keep-tests]
"""
import argparse, os, shutil, subprocess, sys, json

YOSYS = os.path.expandvars(r'%APPDATA%\Python\Python310\Scripts\yowasp-yosys.exe')
HERE = os.path.dirname(os.path.abspath(__file__))

p = argparse.ArgumentParser()
p.add_argument('--src', required=True)
p.add_argument('--top', required=True)
p.add_argument('--out', required=True)
p.add_argument('--sv', action='store_true')
p.add_argument('--files', nargs='*')
p.add_argument('--keep-tests', action='store_true')
p.add_argument('--chparam', nargs='*', default=[], help='hierarchy 模块参数，如 SIMULATION=1')
a = p.parse_args()

src = os.path.abspath(a.src)
out = os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)

if a.files:
    files = a.files
else:
    files = sorted(f for f in os.listdir(src) if f.lower().endswith(('.v', '.sv')))
    if not a.keep_tests:
        files = [f for f in files if 'tb' not in f.lower() and 'test' not in f.lower()]
if not files:
    print('没有找到 Verilog 文件'); sys.exit(1)
print('输入文件:', ', '.join(files))

rtl = os.path.join(out, 'rtl.json')
hier = 'hierarchy -top ' + a.top
for kv in a.chparam:
    if '=' in kv:
        k, v = kv.split('=', 1)
        hier += ' -chparam %s %s' % (k, v)
ys = '; '.join([
    'read_verilog ' + ('-sv ' if a.sv else '') + ' '.join('"%s"' % f if ' ' in f else f for f in files),
    hier,
    'proc',
    'memory_collect',
    'write_json ' + rtl.replace('\\', '/'),
])
r = subprocess.run([YOSYS, '-p', ys], cwd=src, capture_output=True, text=True, errors='replace')
log = (r.stdout or '') + '\n' + (r.stderr or '')
open(os.path.join(out, 'yosys.log'), 'w', encoding='utf-8').write(log)
if not os.path.exists(rtl):
    print('!! Yosys 失败，看日志:', os.path.join(out, 'yosys.log'))
    # 打印含 error 的行
    for line in log.split('\n'):
        if 'error' in line.lower() or 'ERROR' in line:
            print('   ', line.strip()[:150])
    sys.exit(1)
print('Yosys OK ->', rtl)

dij = os.path.join(out, 'digitaljs.json')
r2 = subprocess.run(['node', os.path.join(HERE, 'convert.js'), rtl, dij], capture_output=True, text=True, errors='replace')
print((r2.stdout or '').strip())
if r2.returncode != 0:
    print('!! 转换失败:', (r2.stderr or '')[:1500])
    sys.exit(1)

web = os.path.join(out, 'web')
os.makedirs(web, exist_ok=True)
shutil.copy(os.path.join(HERE, 'assets', 'main.js'), web)
data = open(dij, encoding='utf-8').read()
open(os.path.join(web, 'circuit_data.js'), 'w', encoding='utf-8').write('window.CIRCUIT_JSON = ' + data + ';')
shutil.copy(os.path.join(HERE, 'viewer_template.html'), os.path.join(web, 'viewer.html'))
print('网页已生成:', os.path.join(web, 'viewer.html'))
