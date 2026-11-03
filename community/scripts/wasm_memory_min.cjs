// Print the minimum page count a wasm module declares for its imported memory.
// usage: node wasm_memory_min.cjs <module.wasm | module.wasm.gz>
const fs = require('fs');
const zlib = require('zlib');

const file = process.argv[2];
let b = fs.readFileSync(file);
if (file.endsWith('.gz')) b = zlib.gunzipSync(b);
let p = 8;
const uleb = () => {
  let r = 0, s = 0, c;
  do { c = b[p++]; r += (c & 0x7f) * 2 ** s; s += 7; } while (c & 0x80);
  return r;
};
const skipName = () => { const n = uleb(); p += n; };
const skipLimits = () => { const flags = uleb(); uleb(); if (flags & 1) uleb(); };

while (p < b.length) {
  const id = b[p++];
  const end = uleb() + p;
  if (id === 2) {
    for (let n = uleb(); n > 0; n--) {
      skipName();
      skipName();
      const kind = b[p++];
      if (kind === 0) uleb();
      else if (kind === 1) { p++; skipLimits(); }
      else if (kind === 2) { uleb(); console.log(uleb()); process.exit(0); }
      else if (kind === 3) p += 2;
      else throw new Error(`unsupported import kind ${kind} in ${file}`);
    }
  }
  p = end;
}
throw new Error(`no imported memory in ${file}`);
