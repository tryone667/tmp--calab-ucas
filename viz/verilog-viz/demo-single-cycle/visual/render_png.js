const { Resvg } = require('@resvg/resvg-js');
const fs = require('fs');
const svg = fs.readFileSync(process.argv[2]);
const width = process.argv[4] ? parseInt(process.argv[4]) : 1800;
const r = new Resvg(svg, { fitTo: { mode: 'width', value: width } });
fs.writeFileSync(process.argv[3], r.render().asPng());
console.log('rendered', process.argv[3]);
