// Verify proofs from the optimised prover with bb.js (BBJS_PKG, default STOCK @aztec-foundation/bb.js) from npm (no local builds of bb.js or its backends).
//
//   cd <dir with `npm install @aztec-foundation/bb.js@<upstream-version> msgpackr pako`>
//   FLOWS_DIR=<pinned flows> PROVER_BB=<optimised bb> [REF_DIR=<dir with <flow>/vk>] node stock_bbjs_verify.mjs [flow-substring]
//
// Proving: stock bb.js AztecClientBackend driving the optimised `bb` binary over its native socket backend, with real
// (non-deterministic) randomness. Verifying: a separate stock bb.js instance using its default backend (the bb that
// ships inside the npm package), which never sees the optimised binary. A one-byte-tampered copy of every proof must be
// rejected; with REF_DIR the returned VK must equal the unmodified prover's VK byte-for-byte.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const require = createRequire(join(process.cwd(), 'package.json'));
const PKG = process.env.BBJS_PKG ?? '@aztec-foundation/bb.js';
const { AztecClientBackend, BackendType, Barretenberg } = await import(require.resolve(PKG));
// PROVER_PKG: prove with another installed bb.js package (e.g. @nemi-fi/bb.js) while still verifying with PKG.
const PROVER_PKG = process.env.PROVER_PKG ?? PKG;
const P = await import(require.resolve(PROVER_PKG));
const { Decoder, Encoder } = require('msgpackr');
const { ungzip } = require('pako');
const bbjsVersion = JSON.parse(readFileSync(join(process.cwd(), 'node_modules', PKG, 'package.json'))).version;

const flowsDir = process.env.FLOWS_DIR;
const filter = process.argv[2] ?? '';
const flows = readdirSync(flowsDir)
  .filter(f => existsSync(join(flowsDir, f, 'ivc-inputs.msgpack')) && f.includes(filter))
  .sort();

function loadFlow(dir) {
  const steps = new Decoder({ useRecords: false }).unpack(readFileSync(join(dir, 'ivc-inputs.msgpack')));
  return {
    bytecodes: steps.map(s => ungzip(s.bytecode)),
    witnesses: steps.map(s => ungzip(s.witness)),
    vks: steps.map(s => new Uint8Array(s.vk)),
    names: steps.map(s => s.functionName),
    kinds: steps.map(s => s.kind),
  };
}

console.log(`verifier ${PKG} ${bbjsVersion}; prover pkg ${PROVER_PKG}: ${process.env.PROVER_BB ?? process.env.PROVER_BACKEND ?? 'default backend'}`);
const proofs = [];
// PROVER_BB: drive that bb binary over the native socket. Otherwise PROVER_BACKEND (a BackendType name, e.g. Wasm) or
// the package's default backend selection (used for the smoke test of the packaged bb.js).
const prover = await P.Barretenberg.new(
  process.env.PROVER_BB
    ? { backend: P.BackendType.NativeUnixSocket, bbPath: process.env.PROVER_BB, threads: 4 }
    : { threads: 4, ...(process.env.PROVER_BACKEND ? { backend: P.BackendType[process.env.PROVER_BACKEND] } : {}) },
);
for (const flow of flows) {
  const { bytecodes, witnesses, vks, names, kinds } = loadFlow(join(flowsDir, flow));
  const t0 = Date.now();
  const { proof, vk } = await new P.AztecClientBackend(bytecodes, prover, names, kinds).prove(witnesses, vks);
  proofs.push({ flow, proof, vk, ms: Date.now() - t0 });
}
await prover.destroy();

const verifierApi = await Barretenberg.new({ threads: 4 }); // stock default backend selection
const verifier = new AztecClientBackend([], verifierApi);
let failures = 0;
for (const { flow, proof, vk, ms } of proofs) {
  const ok = await verifier.verify(proof, vk);
  const decoded = new Decoder({ useRecords: false }).decode(proof);
  const seg = decoded[Object.keys(decoded).at(-1)];
  const tamperedField = new Uint8Array(seg[seg.length - 1]);
  tamperedField[31] ^= 1;
  seg[seg.length - 1] = tamperedField;
  let tamperedOk;
  try {
    tamperedOk = await verifier.verify(new Encoder({ useRecords: false }).encode(decoded), vk);
  } catch {
    tamperedOk = false;
  }
  let vkMatches = true;
  if (process.env.REF_DIR) {
    vkMatches = Buffer.compare(Buffer.from(vk), readFileSync(join(process.env.REF_DIR, flow, 'vk'))) === 0;
  }
  const pass = ok === true && tamperedOk === false && vkMatches;
  if (!pass) failures++;
  console.log(`${pass ? 'PASS' : 'FAIL'} ${flow}: verify=${ok} tampered=${tamperedOk} vk_matches_ref=${vkMatches} (prove ${ms} ms)`);
}
await verifierApi.destroy();
console.log(failures === 0 ? `ALL ${proofs.length} FLOWS VERIFIED` : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
