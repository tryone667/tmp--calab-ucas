const http = require('http');
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const dir = path.resolve(process.argv[2]);
const png1 = process.argv[3] || 'ui1.png';
const png2 = process.argv[4] || 'ui2.png';

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

server.listen(8127, async () => {
  try {
    const browser = await puppeteer.launch({
      executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
      headless: true,
      args: ['--no-sandbox', '--disable-gpu', '--no-first-run', '--no-default-browser-check']
    });
    const page = await browser.newPage();
    await page.setViewport({ width: 1680, height: 1000 });
    const errors = [];
    page.on('console', m => { if (m.type() === 'error') errors.push('ERR ' + m.text().slice(0, 140)); if (m.type() === 'warning') errors.push('WARN ' + m.text().slice(0, 140)); });
    page.on('pageerror', e => errors.push('PAGEERROR: ' + String(e.message).slice(0, 140)));
    await page.goto('http://127.0.0.1:8127/viewer.html', { waitUntil: 'networkidle0', timeout: 90000 });
    await new Promise(r => setTimeout(r, 4200));

    const readState = () => page.evaluate(() => JSON.stringify({
      scale: window.paper.scale().sx,
      translate: window.paper.translate(),
      collapsed: $('body').hasClass('collapsed'),
      sidebarW: $('#sidebar').outerWidth(),
    }));
    console.log('after auto-fit:', await readState());

    await page.click('#fitbtn');
    await new Promise(r => setTimeout(r, 300));
    console.log('after fit click:', await readState());
    await page.screenshot({ path: png1 });

    await page.click('#zoomin');
    await new Promise(r => setTimeout(r, 200));
    console.log('after zoom+:', await readState());
    await page.mouse.move(700, 400);
    await page.mouse.wheel({ deltaY: -400 });
    await new Promise(r => setTimeout(r, 200));
    console.log('after wheel zoom:', await readState());
    await page.click('#fitbtn');
    await new Promise(r => setTimeout(r, 300));

    await page.click('#collapsebtn');
    await new Promise(r => setTimeout(r, 700));
    console.log('after collapse:', await readState());
    await page.screenshot({ path: png2 });

    console.log('console msgs:', errors.length ? errors.slice(0, 8).join(' || ') : 'none');
    await browser.close();
  } catch (e) {
    console.error('FAILED:', e.message);
  }
  server.close();
});
