const http = require('http');
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');
const root = path.join(__dirname, 'web');
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent((req.url || '/').split('?')[0]);
  if (p === '/') p = '/viewer.html';
  const f = path.join(root, p);
  fs.readFile(f, (e, d) => {
    if (e) { res.writeHead(404); res.end('nf'); return; }
    res.writeHead(200, { 'Content-Type': mime[path.extname(f)] || 'application/octet-stream' });
    res.end(d);
  });
});
server.listen(8123, async () => {
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
    await page.goto('http://127.0.0.1:8123/viewer.html', { waitUntil: 'networkidle0', timeout: 90000 });
    await new Promise(r => setTimeout(r, 3000));
    await page.screenshot({ path: 'digitaljs_top.png' });
    await page.select('#modsel', 'datapath');
    await new Promise(r => setTimeout(r, 2500));
    await page.screenshot({ path: 'digitaljs_datapath.png' });
    await page.select('#modsel', 'alu');
    await new Promise(r => setTimeout(r, 2500));
    await page.screenshot({ path: 'digitaljs_alu.png' });
    console.log('done. console errors:', errors.length ? errors.slice(0, 6).join(' || ') : 'none');
    await browser.close();
  } catch (e) {
    console.error('FAILED:', e.message);
  }
  server.close();
});
