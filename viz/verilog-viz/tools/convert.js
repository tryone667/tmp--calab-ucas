const c = require('yosys2digitaljs/core');
const fs = require('fs');
const fn = c.yosys2digitaljs || c.default;
const inp = process.argv[2], outp = process.argv[3];
const j = JSON.parse(fs.readFileSync(inp, 'utf8'));
Promise.resolve(fn(j)).then(r => {
  const out = r.output || r;
  fs.writeFileSync(outp, JSON.stringify(out));
  console.log('convert OK | top devices:', Object.keys(out.devices).length, '| connectors:', (out.connectors || []).length, '| subcircuits:', Object.keys(out.subcircuits || {}).length);
  console.log('top:', Object.entries(out.devices).map(([k, v]) => v.type + (v.label ? '(' + v.label + ')' : '')).slice(0, 14).join(', '));
}).catch(e => { console.error('CONVERT ERR:', e.message); process.exit(1); });
