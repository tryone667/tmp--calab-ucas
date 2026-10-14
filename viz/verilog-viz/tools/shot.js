const http = require('http');
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const dir = path.resolve(process.argv[2]);
const png = process.argv[3] || 'shot.png';
const probe = process.argv.includes('--probe');

const mime = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent((req.url || '/').split('?')[0]);
  if (p === '/') p = '/viewer.html';
  const f = path.join(dir, p);
  fs.readFile(f, (e, d) => {
    if (e) { res.writeHead(404); res.end('nf'); return; }
    res.writeHead(200, { 'Content-Type': mime[path.extname(f)] || 'application/octet-stream' });
    res.end(d);
  });
});

server.listen(8126, async () => {
  try {
    const browser = await puppeteer.launch({
      executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
      headless: true,
      args: ['--no-sandbox', '--disable-gpu', '--no-first-run', '--no-default-browser-check']
    });
    const page = await browser.newPage();
    await page.setViewport({ width: 1680, height: 1050 });
    const errors = [];
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 160)); });
    page.on('pageerror', e => errors.push('PAGEERROR: ' + String(e.message).slice(0, 160)));
    await page.goto('http://127.0.0.1:8126/viewer.html', { waitUntil: 'networkidle0', timeout: 90000 });
    await new Promise(r => setTimeout(r, 3000));

    if (probe) {
      const result = await page.evaluate(async () => {
        try {
          const out = {};
          const c = window.circuit;
          if (!c) return 'no circuit';
          out.updateGates = typeof c.updateGates;
          out.tick0 = c.tick;
          const clk = c.getInputCells().find(x => String(x.get('label') || x.get('net') || '').toLowerCase().includes('clk'));
          out.clkFound = !!clk;
          const cur = clk && clk.get('outputSignals') && clk.get('outputSignals').out;
          out.clkValue0 = cur ? String(cur) : 'none';
          const V = cur ? cur.constructor : null;
          out.hasFromBool = (V && typeof V.fromBool === 'function') ? 'yes' : 'no';
          out.hasToggleInput = clk ? typeof clk.toggleInput : 'n/a';
          const settle = async () => { let i = 0; while (c.hasPendingEvents && i < 5000) { await c.updateGates(); i++; } return i; };
          const dffs = c._graph.getCells().filter(x => String(x.get('type') || '').toLowerCase().includes('dff'));
          out.dffCount = dffs.length;
          out.dffLabels = dffs.slice(0, 6).map(d => String(d.get('label') || '?').slice(0, 42));
          const snap = () => dffs.map(d => String(d.get('outputSignals') && d.get('outputSignals').out));
          if (clk && V && typeof V.fromBool === 'function' && typeof clk.toggleInput === 'function') {
            clk.setInput(V.fromBool(false));
            await settle();
            const before = snap();
            let events = 0;
            for (let n = 0; n < 8; n++) { clk.toggleInput(); events += await settle(); }
            const after = snap();
            out.settleEvents = events;
            out.dffChanged = before.map((v, i) => v !== after[i]).filter(Boolean).length;
            out.beforeSample = before.slice(0, 4);
            out.afterSample = after.slice(0, 4);
            out.clkValueEnd = String(clk.get('outputSignals').out);
          } else {
            out.skip = 'missing api';
          }
          out.tick1 = c.tick;
          return JSON.stringify(out);
        } catch (e) { return 'EVAL-ERR: ' + String(e.message).slice(0, 200); }
      });
      console.log('PROBE:', result);
    }

    const moduleArg = (process.argv.find(x => x.startsWith('--module=')) || '').split('=')[1] || '';
    if (moduleArg) {
      await page.select('#modsel', moduleArg);
      await new Promise(r => setTimeout(r, 2500));
    }
    await page.screenshot({ path: png });
    console.log('shot saved:', png);
    console.log('console errors:', errors.length ? errors.slice(0, 6).join(' || ') : 'none');
    await browser.close();
  } catch (e) {
    console.error('FAILED:', e.message);
  }
  server.close();
});
