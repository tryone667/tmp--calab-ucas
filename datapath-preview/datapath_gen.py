# -*- coding: utf-8 -*-
"""数据通路收束图生成器（带端口版）。

用法：python -X utf8 datapath_gen.py
输出：viz-exp/<expN>/datapath.html  —— 每个模块按连接数画出"进/出"引脚，
      表格与"入/出"计数全部由连接表自动生成，保证图文一致。
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = """
  body{margin:0;background:#f4f6f8;color:#263238;font-family:"Segoe UI","Microsoft YaHei",sans-serif;}
  .wrap{max-width:1680px;margin:0 auto;padding:18px 22px 44px;}
  h1{font-size:21px;margin:6px 0 4px;}
  h3{font-size:15px;margin:2px 0 10px;}
  .sub{font-size:13px;color:#607d8b;line-height:1.7;}
  .card{background:#fff;border:1px solid #e0e6ea;border-radius:10px;padding:14px 16px;margin-top:14px;box-shadow:0 1px 3px rgba(0,0,0,.04);}
  .legend{display:flex;gap:20px;flex-wrap:wrap;font-size:12.5px;color:#455a64;margin:2px 0 10px;}
  .legend i{display:inline-block;width:26px;border-top:3px solid #37474f;vertical-align:middle;margin-right:6px;}
  .legend .c i{border-top-color:#1565c0;}
  .legend .r i{border-top-color:#c62828;}
  .legend .d i{border-top-color:#c62828;border-top-style:dashed;}
  table{border-collapse:collapse;width:100%;font-size:12.8px;}
  th,td{border:1px solid #e3e9ee;padding:6px 9px;text-align:left;vertical-align:top;}
  th{background:#f7fafc;color:#37474f;font-weight:600;}
  td:first-child{white-space:nowrap;font-weight:600;}
  td.num{text-align:center;white-space:nowrap;}
  code{background:#f2f5f7;padding:0 4px;border-radius:3px;font-family:Consolas,monospace;font-size:12px;}
  ol{font-size:13.2px;color:#37474f;line-height:1.85;margin:6px 0 4px;padding-left:22px;}
  a{color:#1565c0;}
  svg{width:100%;height:auto;display:block;}
  text{font-family:Consolas,"Microsoft YaHei",monospace;}
  .bxbox{fill:#f5f7fa;stroke:#90a4ae;stroke-width:1.4;}
  .ram{fill:#fff3e0;stroke:#ef6c00;}
  .rf{fill:#e8f5e9;stroke:#43a047;}
  .pipe{fill:#e3f2fd;stroke:#1e88e5;}
  .ctrlbox{fill:#fff8e1;stroke:#f9a825;}
  .bname{font-size:14px;fill:#263238;font-weight:600;}
  .bio{font-size:12px;fill:#546e7a;}
  .bnote{font-size:10px;fill:#90a4ae;}
  .wire{stroke:#37474f;stroke-width:1.6;fill:none;}
  .ctl{stroke:#1565c0;stroke-width:1.2;fill:none;}
  .redw{stroke:#c62828;stroke-width:1.4;fill:none;}
  .redd{stroke:#c62828;stroke-width:1.4;fill:none;stroke-dasharray:6 4;}
  .lbl{font-size:11px;fill:#455a64;}
  .lblr{font-size:11px;fill:#c62828;}
  .lblb{font-size:11px;fill:#1565c0;}
  .lblg{font-size:11px;fill:#2e7d32;}
  .lbl,.lblr,.lblb,.lblg{paint-order:stroke;stroke:#ffffff;stroke-width:3px;stroke-linejoin:round;}
  .bandname{font-size:13px;fill:#78909c;font-weight:600;}
  .box:hover rect{stroke:#e91e63;stroke-width:2.4;}
  .box:hover .bname{fill:#c2185b;}
"""

PALETTE = {'wire': ('#37474f', 'ar'), 'ctl': ('#1565c0', 'arb'),
           'redw': ('#c62828', 'arr'), 'redd': ('#c62828', 'arr')}


def esc(s):
    """转义 XML 特殊字符，防止提示/标签里的 < > & 破坏内联 SVG。"""
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def edge(b, side, pos):
    if side == 'l':
        return (b['x'], pos)
    if side == 'r':
        return (b['x'] + b['w'], pos)
    if side == 't':
        return (pos, b['y'])
    return (pos, b['y'] + b['h'])


def build_svg(sp):
    blocks = {b['id']: b for b in sp['blocks']}
    out = []

    for (x, w, fill, label) in sp['bands']:
        out.append('<rect x="%d" y="118" width="%d" height="120" rx="8" fill="%s" opacity="0.5"/>' % (x, w, fill))
        out.append('<text class="bandname" x="%d" y="112" text-anchor="middle">%s</text>' % (x + w / 2, esc(label)))

    pins = []
    for c in sp['conns']:
        p1 = edge(blocks[c['fr'][0]], c['fr'][1], c['fr'][2])
        p2 = edge(blocks[c['to'][0]], c['to'][1], c['to'][2])
        pts = [p1] + [tuple(p) for p in c.get('pts', [])] + [p2]
        d = 'M' + ' L'.join('%g,%g' % (x, y) for (x, y) in pts)
        cls = c.get('cls', 'wire')
        col, mk = PALETTE[cls]
        out.append('<path class="%s" d="%s" marker-end="url(#%s)"/>' % (cls, d, mk))
        pins.append((p1[0], p1[1], col))
        pins.append((p2[0], p2[1], col))

    for b in sp['blocks']:
        ins = [c for c in sp['conns'] if c['to'][0] == b['id']]
        outs = [c for c in sp['conns'] if c['fr'][0] == b['id']]
        badge = '入 %d · 出 %d' % (len(ins), len(outs))
        ny = b['y'] + (31 if b['h'] >= 76 else 29)
        by = ny + 20
        parts = ['<g class="box"><title>%s</title>' % esc(b.get('tip', ''))]
        parts.append('<rect class="%s" x="%d" y="%d" width="%d" height="%d" rx="10"/>' % (b['cls'], b['x'], b['y'], b['w'], b['h']))
        parts.append('<text class="bname" x="%d" y="%d" text-anchor="middle">%s</text>' % (b['x'] + b['w'] / 2, ny, esc(b['name'])))
        parts.append('<text class="bio" x="%d" y="%d" text-anchor="middle">%s</text>' % (b['x'] + b['w'] / 2, by, badge))
        if b.get('note'):
            parts.append('<text class="bnote" x="%d" y="%d" text-anchor="middle">%s</text>' % (b['x'] + b['w'] / 2, by + 16, esc(b['note'])))
        parts.append('</g>')
        out.append(''.join(parts))

    for (x, y, col) in pins:
        out.append('<rect x="%g" y="%g" width="6" height="6" rx="1.5" fill="%s"/>' % (x - 3, y - 3, col))

    for l in sp.get('labels', []):
        anchor = l.get('anchor', 'start')
        out.append('<text class="%s" x="%d" y="%d" text-anchor="%s">%s</text>' % (l.get('cls', 'lbl'), l['x'], l['y'], anchor, esc(l['t'])))

    return '\n'.join(out)


def build_table(sp):
    rows = []
    for b in sp['blocks']:
        ins = [c for c in sp['conns'] if c['to'][0] == b['id']]
        outs = [c for c in sp['conns'] if c['fr'][0] == b['id']]
        det = '入：' + '；'.join(esc(c['sig']) for c in ins) + '。' if ins else '入：—。'
        det += '出：' + '；'.join(esc(c['sig']) for c in outs) + '。' if outs else '出：—。'
        note = '<br><span class="sub">%s</span>' % esc(b['note']) if b.get('note') else ''
        rows.append('<tr><td>%s%s</td><td class="num">%d</td><td class="num">%d</td><td>%s</td></tr>'
                    % (esc(b['name']), note, len(ins), len(outs), det))
    return '\n'.join(rows)


PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<title>{title}</title>
<link rel="icon" href="data:,"/>
<style>{css}</style>
</head>
<body>
<div class="wrap">
<h1>{title}</h1>
<div class="sub">{subtitle}</div>
<div class="card">
<div class="legend">
  <span><i></i>数据主干</span>
  <span class="c"><i></i>控制 / 地址配置</span>
  <span class="r"><i></i>分支冲刷（cancel / 改道）</span>
  <span class="d"><i></i>停顿反压（id_stall → allowin 链）</span>
</div>
<svg viewBox="0 0 1620 780" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <marker id="ar" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#37474f"/></marker>
    <marker id="arb" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#1565c0"/></marker>
    <marker id="arr" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#c62828"/></marker>
  </defs>
{svg}
</svg>
</div>
<div class="card">
<h3>模块端口明细（自动对照图上连接）</h3>
<table>
<tr><th>模块</th><th>入</th><th>出</th><th>图上接口明细（每条连接携带的信号）</th></tr>
{table}
</table>
<p class="sub" style="margin-top:8px;">口径：入/出 = 图上画出的引脚数（一条连接 = 一个端口）；clk / resetn 全局省略；位宽只标主要总线。</p>
</div>
<div class="card">
<h3>怎么看</h3>
{notes}
</div>
</div>
</body>
</html>
"""


def page(sp):
    return PAGE.format(title=sp['title'], css=CSS, subtitle=sp['subtitle'],
                       svg=build_svg(sp), table=build_table(sp), notes=sp['notes'])


# ============================ 布线版（可拖动） ============================
MARKERS = """<marker id="ar" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#37474f"/></marker>
    <marker id="arb" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#1565c0"/></marker>
    <marker id="arr" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#c62828"/></marker>"""

DRAG_TMPL = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<title>__TITLE__</title>
<link rel="icon" href="data:,"/>
<style>__CSS__
  #cv{width:100%;height:72vh;display:block;background:#fbfcfe;border-radius:8px;border:1px solid #e3e9ee;touch-action:none;}
  .blk{cursor:grab;}
  .blk:active{cursor:grabbing;}
  .conn{fill:none;}
  .conn.hl{stroke:#e91e63 !important;stroke-width:2.6 !important;}
  .toolbar{display:flex;justify-content:space-between;align-items:center;gap:12px;margin:2px 0 10px;flex-wrap:wrap;}
  .toolbar button{padding:4px 12px;margin-left:6px;cursor:pointer;border:1px solid #c9d4dd;background:#fff;border-radius:6px;font-size:13px;}
  .toolbar button:hover{background:#f1f6fa;}
</style>
</head>
<body>
<div class="wrap">
<div class="toolbar">
  <div><h1 style="margin:0 0 2px;">__TITLE__</h1><div class="sub">__SUB__</div></div>
  <div><span class="sub">拖动模块 / 滚轮缩放 / 空白拖动平移 / 悬停高亮连线（连线悬停看信号）</span>
       <button id="route">线型：直角</button>
       <button id="fit">适配视图</button><button id="reset">复位布局</button></div>
</div>
<div class="card" style="padding:10px;">
<div class="legend">
  <span><i></i>数据主干</span>
  <span class="c"><i></i>控制 / 地址配置</span>
  <span class="r"><i></i>分支冲刷（cancel / 改道）</span>
  <span class="d"><i></i>停顿反压（id_stall → allowin 链）</span>
</div>
<svg id="cv">
  <defs>__MARKERS__</defs>
  <g id="world"></g>
</svg>
</div>
<div class="card">
<h3>模块端口明细（自动对照图上连接）</h3>
<table>
<tr><th>模块</th><th>入</th><th>出</th><th>图上接口明细（每条连接携带的信号）</th></tr>
__TABLE__
</table>
<p class="sub" style="margin-top:8px;">口径：入/出 = 图上画出的引脚数（一条连接 = 一个端口）；clk / resetn 全局省略；位宽只标主要总线。</p>
</div>
<div class="card">
<h3>怎么看</h3>
__NOTES__
</div>
<script>
const BLOCKS = __BLOCKS__;
const CONNS = __CONNS__;
__JS__
</script>
</div>
</body>
</html>
"""

DRAG_JS = """
const NS = 'http://www.w3.org/2000/svg';
const svg = document.getElementById('cv');
const world = document.getElementById('world');
const blkMap = {}, wireList = [];
const INIT = BLOCKS.map(function(b){ return {id: b.id, x: b.x, y: b.y}; });
let view = {tx: 0, ty: 0, k: 1};
let drag = null;
let roundMode = false;

function dir(side){ return side === 'r' ? [1,0] : side === 'l' ? [-1,0] : side === 't' ? [0,-1] : [0,1]; }
function portPos(b, side, off){
  if (side === 'r') return [b.x + b.w, b.y + off];
  if (side === 'l') return [b.x, b.y + off];
  if (side === 't') return [b.x + off, b.y];
  return [b.x + off, b.y + b.h];
}
const G = 12;    // 布线网格尺寸
const PAD = 6;   // 模块框外扩的安全边距
let O = null;    // 障碍网格（每次重算前重建）
function buildObstacles(){
  let minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9;
  BLOCKS.forEach(function(b){
    minx = Math.min(minx, b.x); miny = Math.min(miny, b.y);
    maxx = Math.max(maxx, b.x + b.w); maxy = Math.max(maxy, b.y + b.h);
  });
  O = {minx: minx - 96, miny: miny - 96, maxx: maxx + 96, maxy: maxy + 96};
  O.cols = Math.ceil((O.maxx - O.minx) / G);
  O.rows = Math.ceil((O.maxy - O.miny) / G);
  O.blocked = new Uint8Array(O.cols * O.rows);
  BLOCKS.forEach(function(b){
    const c0 = Math.max(0, Math.floor((b.x - PAD - O.minx) / G));
    const c1 = Math.min(O.cols - 1, Math.ceil((b.x + b.w + PAD - O.minx) / G));
    const r0 = Math.max(0, Math.floor((b.y - PAD - O.miny) / G));
    const r1 = Math.min(O.rows - 1, Math.ceil((b.y + b.h + PAD - O.miny) / G));
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        const cx = O.minx + (c + 0.5) * G, cy = O.miny + (r + 0.5) * G;
        if (cx > b.x - PAD && cx < b.x + b.w + PAD && cy > b.y - PAD && cy < b.y + b.h + PAD) {
          O.blocked[r * O.cols + c] = 1;
        }
      }
    }
  });
}
function cellOf(p){
  let c = Math.floor((p[0] - O.minx) / G), r = Math.floor((p[1] - O.miny) / G);
  c = Math.max(0, Math.min(O.cols - 1, c)); r = Math.max(0, Math.min(O.rows - 1, r));
  return r * O.cols + c;
}
function routeCore(A, B){
  const cols = O.cols, rows = O.rows, blocked = O.blocked;
  const s = cellOf(A), t = cellOf(B);
  blocked[s] = 0; blocked[t] = 0;
  const ncell = cols * rows;
  const NS = ncell * 4;              // 状态 = (格子, 方向)，转弯代价按方向变化计
  const g = new Float32Array(NS); g.fill(Infinity);
  const from = new Int32Array(NS); from.fill(-1);
  const dirs = [[1,0],[-1,0],[0,1],[0,-1]];
  const heap = [];
  function push(f, id){
    heap.push([f, id]);
    let i = heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (heap[p][0] <= heap[i][0]) break;
      const tmp = heap[p]; heap[p] = heap[i]; heap[i] = tmp; i = p;
    }
  }
  function pop(){
    const top = heap[0], last = heap.pop();
    if (heap.length) {
      heap[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i;
        if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
        if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
        if (m === i) break;
        const tmp = heap[m]; heap[m] = heap[i]; heap[i] = tmp; i = m;
      }
    }
    return top;
  }
  const tc = t % cols, tr = (t - tc) / cols;
  function hh(id){
    const cell = id >> 2;
    const c = cell % cols, r = (cell - c) / cols;
    return Math.abs(c - tc) + Math.abs(r - tr);
  }
  for (let d = 0; d < 4; d++) {
    const st = s * 4 + d;
    g[st] = 0;
    push(hh(st), st);
  }
  let best = -1;
  let guard = NS * 4;
  while (heap.length && guard-- > 0) {
    const cur = pop(), sid = cur[1];
    if (cur[0] > g[sid] + hh(sid) + 0.001) continue;
    const cell = sid >> 2, d = sid & 3;
    if (cell === t) { best = sid; break; }
    const c = cell % cols, r = (cell - c) / cols;
    for (let e = 0; e < 4; e++) {
      const nc = c + dirs[e][0], nr = r + dirs[e][1];
      if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
      const ncell2 = nr * cols + nc;
      if (blocked[ncell2]) continue;
      const nst = ncell2 * 4 + e;
      const ng = g[sid] + 1 + (e !== d ? 2.5 : 0);
      if (ng < g[nst] - 1e-6) {
        g[nst] = ng; from[nst] = sid;
        push(ng + hh(nst), nst);
      }
    }
  }
  if (best < 0) return null;
  const cells = [];
  let sid2 = best;
  while (sid2 >= 0) {
    const cell = sid2 >> 2;
    cells.push(cell);
    if (cell === s) break;
    sid2 = from[sid2];
  }
  cells.reverse();
  return cells.map(function(cell){
    const c = cell % cols, r = (cell - c) / cols;
    return [O.minx + (c + 0.5) * G, O.miny + (r + 0.5) * G];
  });
}
function orthoFix(pts){
  const out = [pts[0]];
  for (let i = 1; i < pts.length; i++) {
    const p = out[out.length - 1], q = pts[i];
    if (Math.abs(p[0] - q[0]) > 0.01 && Math.abs(p[1] - q[1]) > 0.01) out.push([p[0], q[1]]);
    out.push(q);
  }
  return out;
}
function simplify(pts){
  const out = [];
  pts.forEach(function(p){
    const q = out[out.length - 1];
    if (!q || Math.abs(p[0] - q[0]) > 0.01 || Math.abs(p[1] - q[1]) > 0.01) out.push(p);
  });
  if (out.length < 3) return out;
  const o2 = [out[0]];
  for (let i = 1; i < out.length - 1; i++) {
    const a = o2[o2.length - 1], b = out[i], d = out[i + 1];
    const sameX = Math.abs(a[0] - b[0]) < 0.01 && Math.abs(b[0] - d[0]) < 0.01;
    const sameY = Math.abs(a[1] - b[1]) < 0.01 && Math.abs(b[1] - d[1]) < 0.01;
    if (!(sameX || sameY)) o2.push(b);
  }
  o2.push(out[out.length - 1]);
  return o2;
}
function routePts(c){
  const A = portPos(blkMap[c.a[0]], c.a[1], c.a[2]);
  const B = portPos(blkMap[c.b[0]], c.b[1], c.b[2]);
  const da = dir(c.a[1]), db = dir(c.b[1]);
  const S = 16;
  const A1 = [A[0] + da[0] * S, A[1] + da[1] * S];
  const B1 = [B[0] + db[0] * S, B[1] + db[1] * S];
  const core = routeCore(A1, B1);
  let pts;
  if (core) pts = [A, A1].concat(core, [B1, B]);
  else pts = [A, A1, [B1[0], A1[1]], B1, B];
  return simplify(orthoFix(pts));
}
function dFromPts(pts, round){
  if (!round) return 'M' + pts.map(function(p){ return p[0] + ',' + p[1]; }).join(' L');
  let d = 'M' + pts[0][0] + ',' + pts[0][1];
  const R = 8;
  for (let i = 1; i < pts.length - 1; i++) {
    const p0 = pts[i - 1], p1 = pts[i], p2 = pts[i + 1];
    const v1 = [p1[0] - p0[0], p1[1] - p0[1]], v2 = [p2[0] - p1[0], p2[1] - p1[1]];
    const l1 = Math.hypot(v1[0], v1[1]) || 1, l2 = Math.hypot(v2[0], v2[1]) || 1;
    const r = Math.min(R, l1 / 2, l2 / 2);
    const a = [p1[0] - v1[0] / l1 * r, p1[1] - v1[1] / l1 * r];
    const b = [p1[0] + v2[0] / l2 * r, p1[1] + v2[1] / l2 * r];
    d += ' L' + a[0] + ',' + a[1] + ' Q' + p1[0] + ',' + p1[1] + ' ' + b[0] + ',' + b[1];
  }
  const last = pts[pts.length - 1];
  d += ' L' + last[0] + ',' + last[1];
  return d;
}
function renderWire(w){ w.el.setAttribute('d', dFromPts(w.pts, roundMode)); }
function routeWire(w){ w.pts = routePts(w.c); renderWire(w); }
function pathHitsRect(w, moved){
  if (!w.pts) return true;
  const x0 = moved.x - 6, y0 = moved.y - 6, x1 = moved.x + moved.w + 6, y1 = moved.y + moved.h + 6;
  for (let i = 1; i < w.pts.length; i++) {
    const a = w.pts[i - 1], b = w.pts[i];
    if (Math.abs(a[1] - b[1]) < 0.01) {
      if (a[1] >= y0 && a[1] <= y1 && Math.max(a[0], b[0]) >= x0 && Math.min(a[0], b[0]) <= x1) return true;
    } else if (Math.abs(a[0] - b[0]) < 0.01) {
      if (a[0] >= x0 && a[0] <= x1 && Math.max(a[1], b[1]) >= y0 && Math.min(a[1], b[1]) <= y1) return true;
    } else {
      return true;
    }
  }
  return false;
}
function updWires(all, moved){
  buildObstacles();
  wireList.forEach(function(w){
    let need = !!all;
    if (!need && moved) need = (w.c.a[0] === moved.id || w.c.b[0] === moved.id) || pathHitsRect(w, moved);
    if (need) routeWire(w);
  });
}
function applyView(){ world.setAttribute('transform', 'translate(' + view.tx + ',' + view.ty + ') scale(' + view.k + ')'); }
function fit(){
  const xs = BLOCKS.map(function(b){ return b.x; }), ys = BLOCKS.map(function(b){ return b.y; });
  const minx = Math.min.apply(null, xs) - 30, miny = Math.min.apply(null, ys) - 50;
  const maxx = Math.max.apply(null, BLOCKS.map(function(b){ return b.x + b.w; })) + 30;
  const maxy = Math.max.apply(null, BLOCKS.map(function(b){ return b.y + b.h; })) + 30;
  const r = svg.getBoundingClientRect();
  const k = Math.min(r.width / (maxx - minx), r.height / (maxy - miny)) * 0.96;
  view.k = k;
  view.tx = (r.width - (maxx - minx) * k) / 2 - minx * k;
  view.ty = (r.height - (maxy - miny) * k) / 2 - miny * k;
  applyView();
}
function build(){
  CONNS.forEach(function(c){
    const p = document.createElementNS(NS, 'path');
    p.setAttribute('class', 'conn ' + c.cls);
    p.setAttribute('marker-end', 'url(#' + c.mk + ')');
    const tt = document.createElementNS(NS, 'title'); tt.textContent = c.sig; p.appendChild(tt);
    p.addEventListener('mouseenter', function(){ p.classList.add('hl'); });
    p.addEventListener('mouseleave', function(){ p.classList.remove('hl'); });
    world.appendChild(p);
    wireList.push({c: c, el: p});
  });
  BLOCKS.forEach(function(b){
    blkMap[b.id] = b;
    const g = document.createElementNS(NS, 'g');
    g.setAttribute('class', 'blk');
    g.setAttribute('transform', 'translate(' + b.x + ',' + b.y + ')');
    const tip = document.createElementNS(NS, 'title'); tip.textContent = b.tip; g.appendChild(tip);
    const rect = document.createElementNS(NS, 'rect');
    rect.setAttribute('class', b.cls);
    rect.setAttribute('x', 0); rect.setAttribute('y', 0);
    rect.setAttribute('width', b.w); rect.setAttribute('height', b.h);
    rect.setAttribute('rx', 10);
    g.appendChild(rect);
    const t1 = document.createElementNS(NS, 'text');
    t1.setAttribute('class', 'bname'); t1.setAttribute('text-anchor', 'middle');
    t1.setAttribute('x', b.w / 2); t1.setAttribute('y', b.h >= 76 ? 31 : 29);
    t1.textContent = b.name; g.appendChild(t1);
    const t2 = document.createElementNS(NS, 'text');
    t2.setAttribute('class', 'bio'); t2.setAttribute('text-anchor', 'middle');
    t2.setAttribute('x', b.w / 2); t2.setAttribute('y', b.h >= 76 ? 51 : 49);
    t2.textContent = b.badge; g.appendChild(t2);
    if (b.note) {
      const t3 = document.createElementNS(NS, 'text');
      t3.setAttribute('class', 'bnote'); t3.setAttribute('text-anchor', 'middle');
      t3.setAttribute('x', b.w / 2); t3.setAttribute('y', b.h >= 76 ? 67 : 65);
      t3.textContent = b.note; g.appendChild(t3);
    }
    g.addEventListener('mouseenter', function(){
      wireList.forEach(function(w){ if (w.c.a[0] === b.id || w.c.b[0] === b.id) w.el.classList.add('hl'); });
    });
    g.addEventListener('mouseleave', function(){
      wireList.forEach(function(w){ if (w.c.a[0] === b.id || w.c.b[0] === b.id) w.el.classList.remove('hl'); });
    });
    g.addEventListener('pointerdown', function(ev){
      ev.stopPropagation();
      drag = {mode: 'blk', b: b, sx: ev.clientX, sy: ev.clientY, x0: b.x, y0: b.y};
      world.appendChild(g);
    });
    world.appendChild(g);
    b.el = g;
  });
  const seen = {};
  CONNS.forEach(function(c){
    [c.a, c.b].forEach(function(p){
      const key = p[0] + '|' + p[1] + '|' + p[2];
      if (seen[key]) return; seen[key] = 1;
      const bb = blkMap[p[0]];
      const pp = portPos(bb, p[1], p[2]);
      const pin = document.createElementNS(NS, 'rect');
      pin.setAttribute('x', pp[0] - bb.x - 3);
      pin.setAttribute('y', pp[1] - bb.y - 3);
      pin.setAttribute('width', 6); pin.setAttribute('height', 6);
      pin.setAttribute('rx', 1.5);
      pin.setAttribute('fill', c.col);
      bb.el.appendChild(pin);
    });
  });
}
svg.addEventListener('pointerdown', function(ev){
  drag = {mode: 'pan', sx: ev.clientX, sy: ev.clientY, tx0: view.tx, ty0: view.ty};
});
window.addEventListener('pointermove', function(ev){
  if (!drag) return;
  if (drag.mode === 'blk') {
    const b = drag.b;
    b.x = drag.x0 + (ev.clientX - drag.sx) / view.k;
    b.y = drag.y0 + (ev.clientY - drag.sy) / view.k;
    b.el.setAttribute('transform', 'translate(' + b.x + ',' + b.y + ')');
    updWires(false, b);
  } else {
    view.tx = drag.tx0 + (ev.clientX - drag.sx);
    view.ty = drag.ty0 + (ev.clientY - drag.sy);
    applyView();
  }
});
window.addEventListener('pointerup', function(){ const d = drag; drag = null; if (d && d.mode === 'blk') updWires(true); });
svg.addEventListener('wheel', function(ev){
  ev.preventDefault();
  const r = svg.getBoundingClientRect();
  const cx = ev.clientX - r.left, cy = ev.clientY - r.top;
  const f = ev.deltaY < 0 ? 1.1 : 1 / 1.1;
  const k2 = Math.max(0.2, Math.min(3.5, view.k * f));
  view.tx = cx - (cx - view.tx) * (k2 / view.k);
  view.ty = cy - (cy - view.ty) * (k2 / view.k);
  view.k = k2; applyView();
}, {passive: false});
document.getElementById('fit').onclick = fit;
document.getElementById('route').onclick = function(){
  roundMode = !roundMode;
  this.textContent = '线型：' + (roundMode ? '圆角' : '直角');
  wireList.forEach(renderWire);
};
document.getElementById('reset').onclick = function(){
  INIT.forEach(function(p){
    const b = blkMap[p.id];
    b.x = p.x; b.y = p.y;
    b.el.setAttribute('transform', 'translate(' + p.x + ',' + p.y + ')');
  });
  updWires(true); fit();
};
build(); updWires(true); fit();
window.blkMap = blkMap; window.wireList = wireList; window.view = view; window.fit = fit;
window.routeCore = routeCore; window.routePts = routePts; window.Oget = function(){ return O; };
"""


def _off(side, pos, b):
    return pos - (b['y'] if side in ('l', 'r') else b['x'])


def build_drag_data(sp):
    blocks = []
    for b in sp['blocks']:
        ins = sum(1 for c in sp['conns'] if c['to'][0] == b['id'])
        outs = sum(1 for c in sp['conns'] if c['fr'][0] == b['id'])
        blocks.append(dict(id=b['id'], x=b['x'], y=b['y'], w=b['w'], h=b['h'], cls=b['cls'],
                           name=b['name'], note=b.get('note', ''), tip=b.get('tip', ''),
                           badge='入 %d · 出 %d' % (ins, outs)))
    conns = []
    bmap = {b['id']: b for b in sp['blocks']}
    for c in sp['conns']:
        cls = c.get('cls', 'wire')
        conns.append(dict(a=[c['fr'][0], c['fr'][1], _off(c['fr'][1], c['fr'][2], bmap[c['fr'][0]])],
                          b=[c['to'][0], c['to'][1], _off(c['to'][1], c['to'][2], bmap[c['to'][0]])],
                          cls=cls, mk=PALETTE[cls][1], col=PALETTE[cls][0], sig=c['sig']))
    return blocks, conns


def page_drag(sp):
    import json
    blocks, conns = build_drag_data(sp)
    html = DRAG_TMPL
    html = html.replace('__TITLE__', sp['title'].replace('带端口', '布线可拖版'))
    html = html.replace('__SUB__', '可拖动布线图：模块随手拖，连线自动避让模块框（不穿过框图）、实时重算；表格与计数依旧自动生成。（版本三）')
    html = html.replace('__CSS__', CSS)
    html = html.replace('__MARKERS__', MARKERS)
    html = html.replace('__TABLE__', build_table(sp))
    html = html.replace('__NOTES__', sp['notes'])
    html = html.replace('__BLOCKS__', json.dumps(blocks, ensure_ascii=False).replace('</', '<\\/'))
    html = html.replace('__CONNS__', json.dumps(conns, ensure_ascii=False).replace('</', '<\\/'))
    html = html.replace('__JS__', DRAG_JS)
    return html


# ============================ exp8 ============================
SPEC8 = {
    'file': 'exp8/datapath.html',
    'title': 'exp8 数据通路（收束版 · 带端口）',
    'subtitle': 'cancel + 阻塞 · 每个模块的端口按数量画出（几个进/出引脚就是几条连接）；悬停看明细，下表逐端口对照。'
                '黑=数据主干，蓝=控制/地址，红实线=分支冲刷，红虚线=停顿反压。',
    'bands': [
        (24, 506, '#e3f2fd', '取指（preIF / IF）'),
        (530, 350, '#e8f5e9', '译码 / 读寄存器'),
        (880, 270, '#fff8e1', '执行'),
        (1150, 320, '#fce4ec', '访存'),
        (1470, 126, '#f3e5f5', '写回'),
    ],
    'blocks': [
        dict(id='preif', x=30, y=150, w=140, h=76, cls='bxbox', name='pre_if · PC 生成',
             tip='pre_if：PC 生成。入 2：pre_if_allowin（反压）；br_taken + br_target（④ 改道）。出 2：pc[32]+valid → if_req；en+addr[32] → 指令 RAM。复位入口 0x1BFFFFFC（entry−4）'),
        dict(id='ifreq', x=200, y=150, w=140, h=76, cls='bxbox', name='if_req · 取指缓冲',
             tip='if_req：缓存"请求已发出"的 PC，与 1 拍后回来的 rdata 配对。入 3：pre_if 的 pc/valid；br_taken（cancel ①②）；if_req_allowin。出 1：if_req_pc+valid → IF。br_taken 时 ① 不接收新请求 ② 不锁存 PC'),
        dict(id='ifr', x=370, y=150, w=140, h=76, cls='bxbox', name='IF 寄存器',
             tip='IF 寄存器：在 if_req_pc 与 rdata 配对的当拍锁存指令。入 4：rdata[32]；if_req_pc[32]；if_req_valid（经 ③ 门）；if_allowin + br_taken。出 3：if_inst[32] → ID；if_pc[32] → 分支判定 / 操作数选择；if_valid'),
        dict(id='id', x=540, y=150, w=140, h=76, cls='bxbox', name='ID 译码（组合）',
             tip='ID 译码：从 if_inst 展开全部控制信号（alu_op[12] / imm / 偏移 / 读口 / 写口 / 指令类型），内部是几十条译码与门。入 1 出 5'),
        dict(id='opsel', x=710, y=150, w=150, h=76, cls='bxbox', name='操作数选择', note='src1=PC|rj；src2=imm|rkd',
             tip='操作数选择：src1 = PC（jirl/bl）| rj；src2 = imm | rkd；store 数据直通。exp8 无前递——操作数直接来自寄存器堆（exp9 这里会插三路前递 mux）'),
        dict(id='idex', x=890, y=150, w=120, h=76, cls='pipe', name='ID/EX 寄存器', note='10 字段',
             tip='ID/EX：寄存 10 字段（valid / pc / alu_op / src1 / src2 / rkd / gr_we / mem_we / res_from_mem / dest）'),
        dict(id='alu', x=1040, y=150, w=100, h=76, cls='bxbox', name='ALU',
             tip='ALU：单周期组合。exp8 只有 12 种 op（加减/比较/逻辑/移位/lui），没有乘除法'),
        dict(id='exmem', x=1170, y=150, w=120, h=76, cls='pipe', name='EX/MEM 寄存器', note='6 字段',
             tip='EX/MEM：寄存 6 字段（valid / pc / alu_result / gr_we / res_from_mem / dest）'),
        dict(id='memsel', x=1320, y=150, w=130, h=76, cls='bxbox', name='MEM 取值',
             tip='MEM 取值：mem_value = res_from_mem ? data_sram_rdata : mem_alu_result'),
        dict(id='memwb', x=1480, y=150, w=118, h=76, cls='pipe', name='MEM/WB 寄存器', note='5 字段',
             tip='MEM/WB：寄存 5 字段（valid / pc / gr_we / dest / value）；输出写回口与 debug_wb_* 探针'),
        dict(id='instram', x=60, y=384, w=180, h=72, cls='ram', name='指令 RAM（外部）', note='1 拍延迟',
             tip='指令 RAM（soc_bram 同步 RAM）：请求后 1 拍出数据；本设计只读（we 恒 0）'),
        dict(id='brbr', x=360, y=384, w=140, h=72, cls='ctrlbox', name='分支判定（ID）',
             tip='分支判定：beq/bne 比较 rj==rd；jirl/bl/b 恒 taken；br_target = if_pc+offs 或 rj+jirl_offs；受 if_valid 与 ~id_stall 门控。出 3 根 → 前端 ④改道 / ①②③取消'),
        dict(id='haz', x=760, y=500, w=140, h=72, cls='ctrlbox', name='冒险检测（停摆）',
             tip='冒险检测：EX/MEM/WB 三路在途写目标（dest≠0、gr_we、valid）分别与 ID 源寄存器号（rj 与 rd|rk）比较撞车。入 4：ID 源号+使用位；EX / MEM / WB 各一路。出 4：id_stall → 反压 3 处 + 门控 1 处。EX 撞停 3 拍、MEM 2 拍、WB 1 拍'),
        dict(id='rf', x=560, y=560, w=140, h=72, cls='rf', name='寄存器堆', note='2R1W',
             tip='寄存器堆：2 读 1 写；写口在 WB 拍末生效（所以 WB 撞车也要停 1 拍）'),
        dict(id='dram', x=1080, y=384, w=180, h=72, cls='ram', name='数据 RAM（外部）', note='1 拍延迟',
             tip='数据 RAM：EX 阶段发请求（st 写 / ld 读），数据在 MEM 拍回来'),
    ],
    'conns': [
        dict(fr=('preif', 'r', 188), to=('ifreq', 'l', 188), cls='wire', sig='pre_if_pc + pre_if_valid'),
        dict(fr=('ifreq', 'r', 188), to=('ifr', 'l', 188), cls='wire', sig='if_req_pc + if_req_valid'),
        dict(fr=('ifr', 'r', 188), to=('id', 'l', 188), cls='wire', sig='if_inst[32]'),
        dict(fr=('id', 'r', 188), to=('opsel', 'l', 188), cls='wire', sig='imm[32]'),
        dict(fr=('id', 'b', 640), to=('idex', 'b', 950), pts=[(640, 276), (950, 276)], cls='ctl', sig='alu_op[12] + 控制位 + dest[5]'),
        dict(fr=('opsel', 'r', 188), to=('idex', 'l', 188), cls='wire', sig='alu_src1/2 + 存储数据'),
        dict(fr=('idex', 'r', 188), to=('alu', 'l', 188), cls='wire', sig='alu_op + src1 + src2'),
        dict(fr=('alu', 'r', 188), to=('exmem', 'l', 188), cls='wire', sig='alu_result[32]'),
        dict(fr=('exmem', 'r', 188), to=('memsel', 'l', 188), cls='wire', sig='mem_alu_result'),
        dict(fr=('memsel', 'r', 188), to=('memwb', 'l', 188), cls='wire', sig='mem_value[32]'),
        dict(fr=('preif', 'b', 100), to=('instram', 't', 100), cls='wire', sig='en + addr[32]'),
        dict(fr=('instram', 'r', 410), to=('ifr', 'b', 460), pts=[(460, 410)], cls='wire', sig='rdata[32]（1 拍）'),
        dict(fr=('ifr', 'b', 450), to=('brbr', 't', 450), cls='wire', sig='if_pc[32]'),
        dict(fr=('ifr', 'b', 495), to=('opsel', 'b', 830), pts=[(495, 300), (830, 300)], cls='wire', sig='if_pc[32]（jirl/bl 作 src1）'),
        dict(fr=('id', 'b', 600), to=('rf', 't', 600), cls='ctl', sig='读口地址 ×2'),
        dict(fr=('id', 'b', 590), to=('brbr', 't', 410), pts=[(590, 340), (410, 340)], cls='ctl', sig='指令类型 + 偏移'),
        dict(fr=('id', 'b', 660), to=('haz', 't', 790), pts=[(660, 480), (790, 480)], cls='ctl', sig='源寄存器号 + 使用位'),
        dict(fr=('rf', 't', 580), to=('opsel', 'b', 740), pts=[(580, 268), (740, 268)], cls='wire', sig='rdata1 / rdata2'),
        dict(fr=('rf', 'l', 598), to=('brbr', 'b', 470), pts=[(470, 598)], cls='wire', sig='rj / rkd 值'),
        dict(fr=('memwb', 'b', 1552), to=('rf', 'r', 598), pts=[(1552, 690), (724, 690), (724, 598)], cls='wire', sig='写回 we / waddr / wdata'),
        dict(fr=('alu', 'b', 1090), to=('dram', 't', 1090), cls='ctl', sig='addr[32]（ALU 结果）'),
        dict(fr=('idex', 'b', 910), to=('dram', 't', 1140), pts=[(910, 340), (1140, 340)], cls='ctl', sig='store 数据 + 访存控制'),
        dict(fr=('dram', 'r', 420), to=('memsel', 'b', 1385), pts=[(1385, 420)], cls='wire', sig='rdata[32]（1 拍）'),
        dict(fr=('brbr', 'l', 400), to=('preif', 't', 100), pts=[(348, 400), (348, 96), (100, 96)], cls='redw', sig='br_taken + br_target（④ 改道）'),
        dict(fr=('brbr', 'l', 418), to=('ifreq', 't', 270), pts=[(355, 418), (355, 88), (270, 88)], cls='redw', sig='（①② 取消请求 / PC）'),
        dict(fr=('brbr', 't', 365), to=('ifr', 't', 440), pts=[(365, 80), (440, 80)], cls='redw', sig='（③ 拦住进 IF）'),
        dict(fr=('haz', 'l', 522), to=('preif', 'l', 205), pts=[(40, 522), (40, 205)], cls='redd', sig='id_stall 反压'),
        dict(fr=('haz', 'l', 536), to=('ifreq', 'l', 205), pts=[(255, 536), (255, 205)], cls='redd', sig='id_stall 反压'),
        dict(fr=('haz', 'l', 550), to=('ifr', 'l', 205), pts=[(515, 550), (515, 205)], cls='redd', sig='id_stall 反压'),
        dict(fr=('haz', 'l', 510), to=('brbr', 'r', 420), pts=[(730, 510), (730, 420)], cls='redd', sig='~id_stall 门控（停顿期间不判分支）'),
        dict(fr=('idex', 'b', 970), to=('haz', 't', 820), pts=[(970, 470), (820, 470)], cls='redw', sig='ex 写目标 + valid'),
        dict(fr=('exmem', 'b', 1285), to=('haz', 't', 855), pts=[(1285, 482), (855, 482)], cls='redw', sig='mem 写目标 + valid'),
        dict(fr=('memwb', 'b', 1500), to=('haz', 't', 880), pts=[(1500, 494), (880, 494)], cls='redw', sig='wb 写目标 + valid'),
    ],
    'labels': [
        dict(x=185, y=182, t='pc/valid', anchor='middle'),
        dict(x=525, y=182, t='inst[32]', anchor='middle'),
        dict(x=695, y=182, t='imm', anchor='middle'),
        dict(x=875, y=182, t='操作数', anchor='middle'),
        dict(x=1155, y=182, t='结果', anchor='middle'),
        dict(x=1465, y=182, t='mem_value', anchor='middle'),
        dict(x=106, y=300, t='en + addr[32]'),
        dict(x=250, y=402, t='rdata[32]（1 拍）'),
        dict(x=486, y=310, t='if_pc[32]'),
        dict(x=500, y=356, t='类型 + 偏移', cls='lblb', anchor='end'),
        dict(x=660, y=270, t='alu_op[12] + 控制位 + dest', cls='lblb'),
        dict(x=606, y=330, t='读口地址 ×2', cls='lblb'),
        dict(x=668, y=472, t='源寄存器号 + 使用位', cls='lblb'),
        dict(x=545, y=262, t='rdata1/rdata2', anchor='end'),
        dict(x=478, y=520, t='rj/rkd 值'),
        dict(x=900, y=682, t='写回 we / waddr[5] / wdata[32]'),
        dict(x=1096, y=300, t='addr[32]（ALU 结果）', cls='lblb'),
        dict(x=925, y=334, t='store 数据 + 访存控制', cls='lblb'),
        dict(x=1268, y=352, t='rdata[32]（1 拍）'),
        dict(x=95, y=90, t='④', cls='lblr', anchor='middle'),
        dict(x=265, y=90, t='①②', cls='lblr', anchor='middle'),
        dict(x=435, y=90, t='③', cls='lblr', anchor='middle'),
        dict(x=430, y=556, t='停顿反压链（id_stall → allowin）', cls='lblr', anchor='middle'),
        dict(x=660, y=414, t='门控分支判定（~id_stall）', cls='lblr', anchor='end'),
        dict(x=1150, y=668, t='EX / MEM / WB 写目标 + valid（撞车检测）', cls='lblr', anchor='middle'),
    ],
    'notes': """
<ol>
<li><b>无前递</b>：操作数直接来自寄存器堆（id_rj_value = rf_rdata1）——exp9 会在"操作数选择"处多插三路前递 mux。</li>
<li><b>停摆（红虚线）</b>：ID 源寄存器号与 EX / MEM / WB 三路在途写目标撞车 → id_stall 冻结前段（EX 撞停 3 拍、MEM 2 拍、WB 1 拍）；停顿期间分支判定被门控（~id_stall）。三路撞车就是"冒险检测"顶上那三根红线。</li>
<li><b>冲刷（红实线）</b>：taken 分支作废两条错路——① 不接收正发出的请求、② 不锁存错路 PC、③ 拦住进 IF；再 ④ 改道到 br_target。exp7 只有 ④。</li>
</ol>
<p class="sub">更细颗粒度：<a href="web/viewer.html">DigitalJS 全量图（可钻模块 / 悬停高亮）</a>。本页隐藏了：译码与门阵列（收成"ID 译码"一块）、alu_op 的 one-hot 展开、全部 debug_* 探针；每个模块的"入/出"= 画出的引脚数。</p>
""",
}

def derive(base, **updates):
    sp = dict(base)
    sp['blocks'] = [dict(b) for b in base['blocks']]
    sp['conns'] = [dict(c) for c in base['conns']]
    sp['labels'] = [dict(l) for l in base['labels']]
    sp.update(updates)
    return sp


def setblock(sp, bid, **kw):
    for b in sp['blocks']:
        if b['id'] == bid:
            b.update(kw)


def delconn(sp, pred):
    sp['conns'] = [c for c in sp['conns'] if not pred(c)]


def addconn(sp, *cs):
    sp['conns'].extend(cs)


# ============================ exp9 ============================
SPEC9 = derive(SPEC8,
    file='exp9/datapath.html',
    title='exp9 数据通路（收束版 · 带端口）',
    subtitle='前递取代阻塞 · exp8→exp9 的改动：EX / MEM / WB 三路结果前递回“操作数选择”（取最新），停摆只剩 load-use 一种。',
    notes="""
<ol>
<li><b>三路前递（exp8→exp9 的核心改动）</b>：EX / MEM / WB 的结果直接送进“操作数选择”，取最新的（EX 优先，其次 MEM，最后 WB）；操作数不再等寄存器堆写回——就是“操作数选择”底部三根回到 ID 的长线。</li>
<li><b>停摆只剩一种</b>：EX 里是 load（数据要 MEM 才回来、没法前递）且被 ID 消费 → 停 1 拍；其余数据冒险全部由前递吃掉，前段不再冻结。</li>
<li><b>冲刷不变</b>：taken 分支仍为 ①②③ 取消 + ④ 改道。</li>
</ol>
<p class="sub">更细颗粒度：<a href="web/viewer.html">DigitalJS 全量图（可钻模块 / 悬停高亮）</a>。口径：入/出 = 图上引脚数；clk / resetn 全局省略。</p>
""")
setblock(SPEC9, 'opsel', name='操作数选择（三路前递）', note='EX/MEM/WB 前递优先，其次寄存器堆',
         tip='操作数选择：src1 = PC（jirl/bl）| rj；src2 = imm | rkd。rj/rkd 先过三路前递 mux（EX 优先，其次 MEM，最后 WB；EX 是 load 时不可前递，改由停顿处理）。出 1：alu_src1/2 + 存储数据')
setblock(SPEC9, 'haz', name='冒险检测（load-use）',
         tip='冒险检测（只剩 load-use）：EX 里是 load（res_from_mem 且 dest≠0）且被 ID 消费 → id_stall 停 1 拍；其余数据冒险全部由前递解决。入 2：ID 源号+使用位；EX 条件。出 4：反压 3 + 门控 1')
delconn(SPEC9, lambda c: c['fr'][0] == 'exmem' and c['to'][0] == 'haz')
delconn(SPEC9, lambda c: c['fr'][0] == 'memwb' and c['to'][0] == 'haz')
delconn(SPEC9, lambda c: c['fr'][0] == 'idex' and c['to'][0] == 'haz')
addconn(SPEC9,
    dict(fr=('idex', 'b', 970), to=('haz', 't', 820), pts=[(970, 470), (820, 470)], cls='redw',
         sig='ex 写目标 + res_from_mem（load-use 检查）'),
    dict(fr=('alu', 'b', 1060), to=('opsel', 'b', 812), pts=[(1060, 252), (812, 252)], cls='wire',
         sig='前递 EX（ex_alu_result）'),
    dict(fr=('memsel', 'b', 1345), to=('opsel', 'b', 784), pts=[(1345, 264), (784, 264)], cls='wire',
         sig='前递 MEM（mem_value）'),
    dict(fr=('memwb', 'b', 1508), to=('opsel', 'b', 756), pts=[(1508, 284), (756, 284)], cls='wire',
         sig='前递 WB（wb_result）'),
)
SPEC9['labels'] = [
    dict(x=185, y=182, t='pc/valid', anchor='middle'),
    dict(x=525, y=182, t='inst[32]', anchor='middle'),
    dict(x=695, y=182, t='imm', anchor='middle'),
    dict(x=875, y=182, t='操作数', anchor='middle'),
    dict(x=1155, y=182, t='结果', anchor='middle'),
    dict(x=1465, y=182, t='mem_value', anchor='middle'),
    dict(x=106, y=300, t='en + addr[32]'),
    dict(x=250, y=402, t='rdata[32]（1 拍）'),
    dict(x=486, y=310, t='if_pc[32]'),
    dict(x=500, y=356, t='类型 + 偏移', cls='lblb', anchor='end'),
    dict(x=660, y=270, t='alu_op[12] + 控制位 + dest', cls='lblb'),
    dict(x=606, y=330, t='读口地址 ×2', cls='lblb'),
    dict(x=668, y=472, t='源寄存器号 + 使用位', cls='lblb'),
    dict(x=545, y=262, t='rdata1/rdata2', anchor='end'),
    dict(x=478, y=520, t='rj/rkd 值'),
    dict(x=900, y=682, t='写回 we / waddr[5] / wdata[32]'),
    dict(x=1096, y=300, t='addr[32]（ALU 结果）', cls='lblb'),
    dict(x=925, y=334, t='store 数据 + 访存控制', cls='lblb'),
    dict(x=1268, y=352, t='rdata[32]（1 拍）'),
    dict(x=95, y=90, t='④', cls='lblr', anchor='middle'),
    dict(x=265, y=90, t='①②', cls='lblr', anchor='middle'),
    dict(x=435, y=90, t='③', cls='lblr', anchor='middle'),
    dict(x=430, y=556, t='停顿反压链（id_stall → allowin）', cls='lblr', anchor='middle'),
    dict(x=660, y=414, t='门控分支判定（~id_stall）', cls='lblr', anchor='end'),
    dict(x=935, y=464, t='load-use 检查（EX）', cls='lblr', anchor='middle'),
    dict(x=1050, y=246, t='前递 EX', cls='lbl', anchor='end'),
    dict(x=1332, y=258, t='前递 MEM', cls='lbl', anchor='end'),
    dict(x=1496, y=278, t='前递 WB', cls='lbl', anchor='end'),
]

# ============================ exp10 ============================
SPEC10 = derive(SPEC9,
    file='exp10/datapath.html',
    title='exp10 数据通路（收束版 · 带端口）',
    subtitle='运算指令扩展 · ALU 增加组合乘法；EX 增加 32 拍除法器；停摆新增一类：EX 里未算完的 div/mod 被 ID 消费。',
    notes="""
<ol>
<li><b>运算指令扩展</b>：新增 16 条（slti/sltui、andi/ori/xori、sll/srl/sra、mul/mulh/mulh.wu、div/mod/div.wu/mod.wu、pcaddu12i）；mul/mulh 在 ALU 里是组合乘法（单周期）。</li>
<li><b>除法器（新块）</b>：恢复余数法 32 拍——先取绝对值记符号，每拍“余数左移比较减、商移位”，busy 期间 EX 顶住不前进；q/r 二选一后与 ALU 结果汇合进 EX/MEM。</li>
<li><b>停摆新增一类</b>：① EX 是 load 且被 ID 消费 → 停 1 拍；② EX 是未算完的 div/mod 且被 ID 消费 → 等它离开 EX（结果经 MEM/WB 前递）。其余照旧前递。</li>
<li><b>冲刷不变</b>：taken 分支仍为 ①②③ 取消 + ④ 改道。</li>
</ol>
<p class="sub">更细颗粒度：<a href="web/viewer.html">DigitalJS 全量图（可钻模块 / 悬停高亮）</a>。口径：入/出 = 图上引脚数；clk / resetn 全局省略。</p>
""")
setblock(SPEC10, 'alu', tip='ALU：单周期组合，22 种 op——新增 sll/srl/sra、mul/mulh/mulh.wu（三个组合乘法：取积低 32 位 / 有符号高 32 / 无符号高 32）；div/mod 不在 ALU，走 EX 的除法器')
setblock(SPEC10, 'idex', tip='ID/EX：寄存 10 字段；遇到 div/mod 时同时启动下方除法器（32 拍），期间 ex_ready_go=~busy 让 EX 不前进')
setblock(SPEC10, 'exmem', tip='EX/MEM：寄存 6 字段；输入结果 = ALU 结果 或 除法器 q/r（二选一）')
setblock(SPEC10, 'haz', name='冒险检测（load-use / div）',
         tip='冒险检测：① EX 里是 load 且被 ID 消费 → 停 1 拍；② EX 里是未算完的 div/mod 且被 ID 消费 → 等它离开 EX（结果经 MEM/WB 前递）。入 3：ID 源号+使用位；EX 条件；除法器 busy。出 4：反压 3 + 门控 1')
SPEC10['blocks'].append(dict(id='div', x=700, y=384, w=160, h=72, cls='bxbox', name='除法器（32 拍）', note='div / mod',
    tip='恢复余数法除法器（EX 内）：{余数,商} 每拍左移、比较减除数；先取绝对值并记符号，32 拍后回正输出 q/r。busy 期间 EX 不前进'))
addconn(SPEC10,
    dict(fr=('idex', 'b', 890), to=('div', 'r', 420), pts=[(890, 420)], cls='ctl', sig='div/mod 指令 + 操作数'),
    dict(fr=('div', 't', 780), to=('exmem', 'b', 1200), pts=[(780, 356), (1200, 356)], cls='wire', sig='div/mod 结果（q / r）'),
    dict(fr=('div', 'l', 430), to=('haz', 't', 855), pts=[(680, 430), (680, 490), (855, 490)], cls='redw', sig='busy（div 未算完）'),
)
SPEC10['labels'] = SPEC9['labels'] + [
    dict(x=896, y=414, t='div/mod 指令 + 操作数', cls='lblb'),
    dict(x=1005, y=348, t='div 结果（q / r）'),
    dict(x=674, y=422, t='busy → 停 EX', cls='lblr', anchor='end'),
]

# ============================ exp11 ============================
SPEC11 = derive(SPEC10,
    file='exp11/datapath.html',
    title='exp11 数据通路（收束版 · 带端口）',
    subtitle='比较转移 + 字节/半字访存 · 新增 blt/bge/bltu/bgeu 与 ld.b/ld.h/ld.bu/ld.hu/st.b/st.h；ls_type[4] 随流水线走，其余（前递 / 停摆 / 冲刷）同 exp10。',
    notes="""
<ol>
<li><b>比较转移（+4 条）</b>：blt/bge/bltu/bgeu 都在 ID 判定——有符号用 $signed 比较、无符号直接比（新增 rj_lt_rd_s / rj_lt_rd_u 两个比较器），和 beq/bne 共用同一套 cancel 冲刷。</li>
<li><b>字节/半字访存（+6 条）</b>：ld.b/ld.h/ld.bu/ld.hu/st.b/st.h——写侧用“移位掩码 + 复制数据”（st.b：0001 按 addr[1:0] 移位；st.h：0011 按 addr[1] 移位；wdata 复制填满总线），读侧在 MEM 拍按地址选字节/半字并做符号/零扩展。</li>
<li><b>ls_type[4] 随流水线</b>：0 无 / 1 st.b / 2 st.h / 3 st.w / 4 ld.b / 5 ld.h / 6 ld.w / 7 ld.bu / 8 ld.hu——替代原来的单个 mem_we，从 ID 一路带到 MEM。</li>
<li>其余同 exp10：三路前递、load-use / div 停摆、①②③④ 冲刷。</li>
</ol>
<p class="sub">更细颗粒度：<a href="web/viewer.html">DigitalJS 全量图（可钻模块 / 悬停高亮）</a>。口径：入/出 = 图上引脚数；clk / resetn 全局省略。</p>
""")
setblock(SPEC11, 'brbr', name='分支判定（ID · 含比较）',
         tip='分支判定：beq/bne 判相等；新增 blt/bge/bltu/bgeu 判大小（有符号 $signed、无符号直接比）；br_target = if_pc+offs 或 rj+jirl_offs；受 if_valid 与 ~id_stall 门控。出 3 根 → 前端 ④改道 / ①②③取消')
setblock(SPEC11, 'dram', tip='数据 RAM：EX 发请求。写侧新增字节/半字：we 用“移位掩码”（st.b：0001<<addr[1:0]；st.h：0011<<{addr[1],0}），wdata 复制填满总线；ld 数据在 MEM 拍回来')
setblock(SPEC11, 'memsel', name='MEM 取值 / 载入选择', note='ls_type 选字节/半字',
         tip='按 mem_ls_type 从 32 位读回值里选：byte 用 addr[1:0] 移位、half 看 addr[1] 选高/低 16 位；ld.b/ld.h 符号扩展、ld.bu/ld.hu 零扩展、ld.w 全字')
setblock(SPEC11, 'idex', note='10 字段 + ls_type[4]',
         tip='ID/EX：寄存 10 字段 + ls_type[4]（访存类型码，随流水线带到 MEM 供载入选择）；遇到 div/mod 仍会启动除法器')
setblock(SPEC11, 'exmem', note='6 字段 + ls_type[4]',
         tip='EX/MEM：寄存 6 字段 + ls_type[4]；输入结果 = ALU 结果 或 除法器 q/r（二选一）')
SPEC11['labels'] = SPEC10['labels'] + [
    dict(x=548, y=378, t='＋ blt / bge / bltu / bgeu', cls='lblg'),
    dict(x=1096, y=372, t='＋ 6 条字节/半字访存', cls='lblg'),
]

# ============================ exp7 ============================
SPEC7 = derive(SPEC8,
    file='exp7/datapath.html',
    title='exp7 数据通路（收束版 · 带端口）',
    subtitle='五级流水骨架：分支只在 ID 改 PC（④ 改道，不 cancel）、数据冒险不处理（id_stall ≡ 0，靠镜像插 NOP）——拿来和 exp8 对照，红色差分就是 exp8 新加的两块处理。',
    notes="""
<ol>
<li><b>本版只解决"能跑"</b>：五级流水 + 同步 RAM 模型成型；分支在 ID 判定、<b>只改 PC（④ 改道）</b>，不撤销错路指令——因为测试镜像里错路位置都插了 NOP。</li>
<li><b>数据冒险不处理</b>：没有检测比较器、没有停顿（id_stall ≡ 0），相关指令之间靠镜像插 NOP 拉开距离。</li>
<li><b>和 exp8 对着看</b>：exp8 图多出"冒险检测"一小块 + 三根红色撞车线 + 三根虚线反压，前端还多 ①②③ 三处 cancel 门控；本图这些都没有——这就是 exp8 的增量。</li>
</ol>
<p class="sub">对照：<a href="../exp8/datapath.html">exp8 收束图</a>、<a href="../exp8/datapath_drag.html">exp8 布线可拖版</a>。口径：入/出 = 图上引脚数；clk / resetn 全局省略。</p>
""")
SPEC7['blocks'] = [b for b in SPEC7['blocks'] if b['id'] != 'haz']
delconn(SPEC7, lambda c: 'haz' in (c['fr'][0], c['to'][0]))
delconn(SPEC7, lambda c: c['fr'][0] == 'brbr' and c['to'][0] in ('ifreq', 'ifr'))
setblock(SPEC7, 'preif',
         tip='pre_if：PC 生成。入 1：br_taken + br_target（④ 改道）。出 2：pc[32]+valid → if_req；en+addr[32] → 指令 RAM。复位入口 0x1BFFFFFC（entry−4）')
setblock(SPEC7, 'ifreq',
         tip='if_req：缓存"请求已发出"的 PC，与 1 拍后回来的 rdata 配对。入 1：pre_if 的 pc/valid。出 1：if_req_pc+valid → IF。本版无 cancel 门控（对比 exp8 的 ①②）')
setblock(SPEC7, 'ifr',
         tip='IF 寄存器：在 if_req_pc 与 rdata 配对的当拍锁存指令。入 2：rdata[32]；if_req_pc+valid（直通，无 ③ 拦截）。出 3：if_inst[32]；if_pc[32]；if_valid')
setblock(SPEC7, 'brbr',
         tip='分支判定：beq/bne 比较 rj==rd；jirl/bl/b 恒 taken；br_target = if_pc+offs 或 rj+jirl_offs。出 1 → 前端 ④ 改道（本版无 cancel、无 id_stall 门控）')
setblock(SPEC7, 'opsel',
         tip='操作数选择：src1 = PC（jirl/bl）| rj；src2 = imm | rkd；store 数据直通。本版无前递（exp9 才加），相关指令靠镜像 NOP 拉开')
setblock(SPEC7, 'rf', tip='寄存器堆：2 读 1 写；写口在 WB 拍末生效')
SPEC7['labels'] = [l for l in SPEC8['labels'] if l['t'] not in (
    '停顿反压链（id_stall → allowin）', '门控分支判定（~id_stall）',
    'EX / MEM / WB 写目标 + valid（撞车检测）', '①②', '③', '源寄存器号 + 使用位')]
SPEC7['labels'] += [
    dict(x=270, y=90, t='（本版只有 ④ 改道，无 ①②③ cancel）', cls='lblr', anchor='middle'),
    dict(x=830, y=524, t='⚠ 本版没有冒险检测单元', cls='lblr', anchor='middle'),
    dict(x=830, y=544, t='数据冒险靠镜像插 NOP 回避（id_stall ≡ 0）', cls='lbl', anchor='middle'),
]

SPECS = [SPEC8, SPEC9, SPEC10, SPEC11, SPEC7]


def main():
    for sp in SPECS:
        html = page(sp)
        out = os.path.join(HERE, sp['file'])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, 'w', encoding='utf-8') as fh:
            fh.write(html)
        print('WROTE %s (%d bytes)' % (out, len(html)))
        html2 = page_drag(sp)
        out2 = out.replace('datapath.html', 'datapath_drag.html')
        with open(out2, 'w', encoding='utf-8') as fh:
            fh.write(html2)
        print('WROTE %s (%d bytes)' % (out2, len(html2)))


if __name__ == '__main__':
    main()
