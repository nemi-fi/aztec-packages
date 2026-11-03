# @nemi-fi/bb.js

`community/v6` is the latest upstream aztec-packages v6 release plus a series of prover optimisations to
barretenberg. It is published to npm as `@nemi-fi/bb.js`, a drop-in replacement for `@aztec-foundation/bb.js` of
the same upstream version:

- **Same API.** The package is built from the same sources, with the stock `package.json` (only `name` and
  `version` differ).
- **Same proofs.** Only prover code changes. Proofs and VKs are byte-identical to the upstream prover's under
  deterministic randomness, and the stock verifier accepts them. Verifier code is not touched.
- **Faster.** Native `bb` / `nodejs_module.node` for {amd64,arm64}-{linux,macos} and both WASM builds. On x86 CPUs
  with AVX-512 IFMA, IFMA kernels are selected at runtime.

```bash
npm install @nemi-fi/bb.js@6.0.0-optimise.0
```

Versions are `<upstream-version>-optimise.<n>`: `<n>` starts at 0 for each upstream version and goes up with each
re-release. The binaries report the upstream version (`bb --version` → `6.0.0`). The newest release is `latest`.

The optimisations are the commits on this branch that upstream does not have: `git log --no-merges v$(cat community/UPSTREAM_VERSION)..community/v6`.

## Speed

Stock `bb` 6.0.0 against this build on `ecdsar1+transfer_0_recursions+sponsored_fpc` (4 cores, AVX-512 IFMA), 5
interleaved runs, min wall time:

| | Stock | This build | Ratio |
|---|---|---|---|
| Prove | 6.48 s | 4.31 s | 0.665 |
| Prove, IFMA off | 6.77 s | 4.83 s | 0.714 |
| Peak RSS | 249 MiB | 230 MiB | 0.923 |

## Releasing

Every merge into `community/v6` publishes a release. To move to a new upstream v6 release:

1. `community/update-upstream.sh v6.X.Y` creates `community/update-v6.X.Y` and merges the upstream tag into it.
   It removes upstream's GitHub workflows during the merge and records the version in `community/UPSTREAM_VERSION`.
2. If it stops on conflicts, keep upstream's version and re-apply only the part of the optimisation that is still
   missing. If upstream already has the change, take upstream's side. Then `git commit` and run the script again.
3. Check byte-identical proofs (see [Validating](#validating)).
4. Push the branch and open a PR into `community/v6`. CI builds the package and checks it.
5. Merge with a **merge commit**, not a squash, so the next upstream merge starts from this one.

`.github/workflows/community-release.yml` runs on every PR into `community/v6` and every push to it, in about
50 minutes:

| Job | |
|---|---|
| `version` | `<n>` = 1 + the highest published `optimise.<n>` for the upstream version, or 0 |
| `build` | 4 native platforms and 2 WASM builds in parallel, in upstream's release image `aztecprotocol/build:3.0` |
| `pack` | Packs the tarball, then runs the stock-verifier check and the package smoke test |
| `publish-npm` | Pushes only: `npm publish --tag latest` with npm trusted publishing (environment `npm-publish`) |

## Building locally

```bash
community/build-release.sh all 0   # -> community/out/nemi-fi-bb.js-<upstream-version>-optimise.0.tgz
```

`native <platform>`, `wasm <preset>` and `pack <n>` run one part each. It needs a full checkout (including `ci3/`)
and the tools of `aztecprotocol/build:3.0`, plus `ldid` (or `rcodesign`) and `cargo-zigbuild`;
`community/scripts/ci_build.sh` installs both inside that image.

## Validating

Scripts are in `community/scripts/`; they need python3 with `msgpack`. The flows are upstream's pinned Chonk inputs:
`https://aztec-ci-artifacts.s3.us-east-2.amazonaws.com/protocol/bb-chonk-inputs-<hash>.tar.gz`, with `<hash>` from
`barretenberg/cpp/scripts/chonk-inputs.hash`.

1. **Byte-identical proofs and VKs.** Build `bb` (`cmake --preset default -DAVM=OFF && ninja bb`) twice, from the
   upstream tag and from this branch, both with the deterministic-randomness harness applied on top: patches
   0001–0002 of `bb-chonk-prover-opt` in `olehmisar/playground`. Then:
   ```bash
   FLOWS=<flows> check_identical.sh <upstream bb> > ref.txt
   FLOWS=<flows> REF=ref.txt check_identical.sh <this branch's bb>
   ```
2. **Stock verifier** (CI): `FLOWS=<flows> verify_with_stock.sh <release bb> <stock bb>`. The stock `bb verify` must
   accept each real-randomness proof and reject a tampered copy.
3. **Package smoke test** (CI): with the tarball, `@aztec-foundation/bb.js@<upstream-version>`, `msgpackr` and
   `pako` installed,
   `FLOWS_DIR=<flows> PROVER_PKG=@nemi-fi/bb.js [PROVER_BACKEND=Wasm] node stock_bbjs_verify.mjs <flow>`.
4. **Speed:** `FLOWS=<flows> ab.sh <stock bb> <release bb> 5 <flow-regex>`.
