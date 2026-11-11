# @nemi-fi/bb.js: faster Aztec client-side proving

A community build of [`@aztec-foundation/bb.js`](https://www.npmjs.com/package/@aztec-foundation/bb.js) with a faster
Chonk prover. It is a drop-in replacement: the same API and the same proofs, about a third faster.

Aztec packages depend on `@aztec-foundation/bb.js`, so swap it in with your package manager's overrides. Your code
and its imports stay the same.

npm, in `package.json`:

```json
"overrides": { "@aztec-foundation/bb.js": "npm:@nemi-fi/bb.js@6.0.0-optimise.0" }
```

yarn, in `package.json`:

```json
"resolutions": { "@aztec-foundation/bb.js": "npm:@nemi-fi/bb.js@6.0.0-optimise.0" }
```

pnpm, in `pnpm-workspace.yaml` (pnpm no longer reads the `pnpm` field of `package.json`):

```yaml
overrides:
  "@aztec-foundation/bb.js": "npm:@nemi-fi/bb.js@6.0.0-optimise.0"
```

Then reinstall. With npm, if your app also depends on `@aztec-foundation/bb.js` directly, alias that dependency
instead and point the override at it:

```json
"dependencies": { "@aztec-foundation/bb.js": "npm:@nemi-fi/bb.js@6.0.0-optimise.0" },
"overrides": { "@aztec-foundation/bb.js": "$@aztec-foundation/bb.js" }
```

## What you get

- **Faster proving.** On a 4-core x86 machine, a private token transfer proves in 4.31 s instead of 6.48 s (0.665×)
  with 8% less peak memory. CPUs with AVX-512 IFMA get extra kernels, picked at runtime.
- **Same API.** Built from the upstream TypeScript sources, with the stock `package.json`.
- **Same proofs.** Only prover code changes. Proofs and verification keys are byte-identical to upstream's under
  deterministic randomness, and the stock verifier accepts them. Verifier code is not touched.
- **Every platform.** Native `bb` and Node addon for linux and macOS on amd64 and arm64, plus both WASM builds.

Versions follow upstream: `@nemi-fi/bb.js@<version>-optimise.<n>` is built on aztec-packages `v<version>`. Use the
version that matches the `@aztec-foundation/bb.js` version your Aztec stack expects.

## How it is built

This repository is a fork of [AztecProtocol/aztec-packages](https://github.com/AztecProtocol/aztec-packages). The
`community/v6` branch is the latest upstream v6 release with the optimisations as separate commits on top. Every
release is built and checked in GitHub Actions before it is published with npm provenance:

- the stock `bb verify` must accept real-randomness proofs and reject tampered ones on upstream's pinned test flows;
- the packed package must prove with its native and WASM backends and verify with stock bb.js.

See [`community/README.md`](community/README.md) for the release process, local builds and validation.

## Upstream

The rest of this tree is upstream aztec-packages, unchanged: see [`CONTRIBUTING.md`](CONTRIBUTING.md) and the
[Aztec docs](https://docs.aztec.network). This is not an official Aztec release; report issues with this build here,
not upstream.
