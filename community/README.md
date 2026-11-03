# Community build of bb.js: optimised Chonk prover

This branch (`community/v6`) is upstream aztec-packages **v6.0.0** with a series of prover-only optimisations to
barretenberg. It is published to npm as **`@nemi-fi/bb.js`** and is a drop-in replacement for
`@aztec-foundation/bb.js` of the same upstream version:

- **Same API.** The TS package is built from the same sources, and its `package.json` is the stock one with only
  `name` and `version` changed.
- **Same proofs.** Every change is on the prover side. With the deterministic-randomness test harness, proofs and
  VKs are byte-identical to the unmodified upstream prover's, and the stock verifier (`bb verify` /
  `@aztec-foundation/bb.js`) accepts real-randomness proofs. Verifier code is not touched.

Faster native `bb` / `nodejs_module.node` for {amd64,arm64}-{linux,macos}, and faster WASM, single- and
multi-threaded. On x86 CPUs with AVX-512 IFMA, extra IFMA kernels are selected at runtime through CPUID.

## npm naming

`@nemi-fi/bb.js@<upstream-version>-optimise.<n>`, for example `@nemi-fi/bb.js@6.0.0-optimise.1`. `<n>` starts at 1
for each upstream version and goes up for each re-release on the same base. The binaries report the upstream version
(`bb --version` → `6.0.0`), as stock does. The newest release has the `latest` dist-tag.

## The series

Base: tag `v6.0.0` (`0219f11d81`). One commit per optimisation, in this order, followed by the commit that adds this
directory. They come from `bb-chonk-prover-opt` patches 0003–0077, ported first to v6.0.0-rc.1, then to rc.6, and now
to v6.0.0. Patches 0001–0002 are the deterministic-randomness test harness (`BB_DETERMINISTIC_PROVING`). They are not
on this branch and are only applied for validation (below).

### Applied (69)

| # | Commit |
|---|---|
| 0003 | perf: single-limb fast path in uint256 divmod; chunked keccak normalize_sparse |
| 0004 | perf(msm): fused scalar batch-affine drain for native Stage 6a |
| 0005 | perf(translator): fetch only grand-product columns per row |
| 0006 | perf(sumcheck): skip fold multiply for bit-identical neighbour pairs |
| 0007 | perf(ecc): batched variable-time divsteps in Bernstein-Yang inverse |
| 0008 | perf(sumcheck): fold subrelation separators into Poseidon2 quad relations on the prover — rebased: test-file conflict: kept both upstream's and patch's new tests |
| 0009 | perf(sumcheck): skip databus lookup rows of other bus columns — rebased: conflict: kept upstream's value check, re-applied per-column selector part |
| 0010 | perf(dsl): move decoded ACIR enum variants instead of copying; string_view field names |
| 0011 | perf(dsl): stream msgpack-compact ACIR program and witness decoding |
| 0012 | perf(uintx): skip multiplications by zero halves |
| 0013 | perf(field): compile-time one() and neg_one() |
| 0015 | perf(threading): lock-free parallel_for pool with bounded spin before sleeping |
| 0016 | perf(poseidon2): shorter critical path in native permutation rounds |
| 0017 | perf(sha256): x86 SHA extensions and streaming input for native sha256 |
| 0018 | perf(polynomials): tile add_scaled_batch and skip zero source coefficients |
| 0019 | perf(oink): parallel, range-limited log-derivative inverse computation |
| 0020 | perf(honk): fill only the permutation columns of the grand-product row |
| 0021 | perf(polynomials): Horner per thread chunk in polynomial evaluate |
| 0022 | perf(sumcheck): drop memory relation terms of gate types absent from the edge on the prover |
| 0023 | perf(keccak): divide by multi-limb powers of 11 via chained single-limb divisions — rebased: context-only conflict: upstream dropped an unused 'multiplicand' line |
| 0024 | perf(bigfield): compute fixed CRT bounds once; 512-bit borrow factor in subtraction |
| 0025 | perf(keccak): runtime slice loop in normalize_and_rotate |
| 0026 | perf(field_t): compile-time Montgomery 1 and -1 |
| 0027 | perf(joint): fold both circuits' sumcheck tables in one largest-first parallel region |
| 0028 | perf(pcs): parallel batched linear quotients for Shplonk and KZG |
| 0029 | perf(gemini): single pass for the partially evaluated batch polynomials — rebased: conflict: upstream only added std::move to the return the patch replaces |
| 0030 | perf(multilinear_batching): batched merge in compute_new_claim |
| 0031 | perf(msm): AVX-512 IFMA batch-affine drain for native Stage 6a |
| 0033 | perf(poseidon2): interleaved S-box layer and shorter internal-matrix chain in round helpers |
| 0034 | perf(eccvm): narrow rows and zero-tail extension for grand product and log-derivative inverses |
| 0035 | perf(eccvm): parallelise transcript scalar muls and MSM trace construction |
| 0036 | perf(field): lower-latency ADX Montgomery mul and split-reduction squaring |
| 0037 | perf(msm): run native Stage 6b batched adds on the IFMA drain |
| 0038 | test(msm): IFMA drain edge cases |
| 0039 | perf(pcs): overlap independent recurrences in batched linear quotients |
| 0040 | perf(gemini): build A0 = F + G/X in one pass |
| 0041 | perf(gemini): skip zero-initialising the fold polynomials |
| 0042 | perf(polynomials): work-balanced thread split in add_scaled_batch |
| 0043 | perf(polynomials): no multiplication for unit scalars in add_scaled_batch |
| 0044 | perf(polynomials): two interleaved Horner chains in polynomial_arithmetic::evaluate |
| 0045 | perf(bigfield): avoid wide divisions on bounds and reduced values |
| 0046 | perf(bigfield): combine and split limbs with 256-bit shifts |
| 0047 | perf(sumcheck): prover fast path for arithmetic gates with q_arith == 1 |
| 0048 | perf(sumcheck): drop absent read/table terms in the log-derivative lookup prover path |
| 0049 | perf(sumcheck): batch the delta-range subrelations on the prover |
| 0050 | test(sumcheck): prover relation paths on edges with gate-like selector values |
| 0051 | perf(trace): chunked gate tile storage |
| 0052 | perf(wasm): build release wasm with -O3 -fno-vectorize instead of -Oz |
| 0053 | perf(wasm): skip packed fold for blocks of identical neighbour pairs |
| 0054 | perf(wasm): packed batch_two_round_fold (IPA SRS fold) — rebased: upstream moved batch_mul_with_endomorphism out of element_impl.hpp; hunks re-applied at offset |
| 0055 | perf(bbapi): reference request blobs in place when unpacking msgpack commands |
| 0056 | perf(ipc): free large socket receive buffers once their message is handled |
| 0057 | perf(honk): parallel lookup read counts with integer accumulation |
| 0058 | perf(trace): parallel copy-cycle counting and fill |
| 0059 | perf(databus): compute log-derivative inverse terms from the four columns |
| 0060 | perf(honk): grand product as a running product of per-row ratios — rebased: upstream changed surrounding comments/ZK prelude; hunks re-applied by hand |
| 0061 | perf(sumcheck): AVX-512 IFMA kernel for the stride-2 fold |
| 0062 | perf(polynomials): AVX-512 IFMA tiles in add_scaled_batch |
| 0063 | perf(polynomials): AVX-512 IFMA Horner chains in polynomial_arithmetic::evaluate |
| 0064 | perf(ipa): AVX-512 IFMA replay of the two-round SRS fold |
| 0065 | perf(sumcheck): AVX-512 IFMA element-wise products of short univariates |
| 0066 | perf(dsl): decode common ACIR opcodes straight from msgpack-compact bytes |
| 0067 | perf(transcript): allocate origin tag debug IDs in per-thread blocks |
| 0068 | perf(dsl): skip zero-scaled terms in the AssertZero gate satisfiability check |
| 0069 | perf(sumcheck): back partially evaluated tables on the folded support only |
| 0074 | perf(sumcheck): materialize the partially evaluated tables after two rounds |
| 0075 | perf(ultra_honk): let Chonk's prover instances free the circuit data they have copied — rebased: chonk.cpp hunks re-applied by hand: upstream reworded free_construction_data comments |
| 0076 | fix(ecc): add evex512 to the AVX-512 IFMA target attributes |
| 0077 | fix(ecc): detect AVX-512 IFMA with CPUID/XGETBV instead of __builtin_cpu_supports |

### Already upstream in v6.0.0 (6, skipped)

| # | Commit | Why skipped |
|---|---|---|
| 0014 | perf(chonk): move step bytecode and witness into ChonkLoad/ChonkAccumulate; write the hiding-kernel VK from the IVC | upstream moves bytecode/witness into ChonkLoad/ChonkAccumulate; write_vk-in-prove path removed upstream |
| 0032 | perf(chonk): free a step's constraint system and witness before accumulating it | upstream frees step.program before accumulating, same change |
| 0070 | perf(chonk): release the circuit-construction data once the prover instance is built | free_construction_data merged upstream in a broader form |
| 0071 | perf(api): decompress each Chonk step just before it is loaded | upstream decompresses each step just before ChonkLoad |
| 0072 | perf(hypernova): move the in-place batched polynomial out instead of copying it | upstream already returns std::move(polynomials_to_batch[0]) |
| 0073 | perf(chonk): release the translator circuit builder and the final accumulator's polynomials early | git am: "No changes -- Patch already applied" |

Dropped: none.

### Fix needed by the series (1)

| Commit | Why |
|---|---|
| fix(bb.js): raise the wasm initial memory to the module's declared minimum | The series adds about 18 KB of static data, so the multithreaded wasm declares 38 initial memory pages instead of 37. bb.js creates that memory itself, with a hard-coded 37 pages, and instantiation failed with `LinkError: memory import has 37 pages which is smaller than the declared initial of 38`. bb.js now uses at least `MIN_INITIAL_MEMORY_PAGES` (38), including when a caller passes a smaller `memory.initial`, so the API stays the same. `build-release.sh` fails if a wasm build ever declares more pages than that constant. |

## Updating to a new upstream v6 release

The optimisations are ordinary commits on this branch. Each upstream release is merged in, so `community/v6` is
always the latest upstream v6 release plus the series:

1. `community/update-upstream.sh v6.X.Y` fetches the upstream tag, creates `community/update-v6.X.Y` from
   `community/v6`, merges the tag and records it in `community/UPSTREAM_VERSION`. It refuses a tag without a
   matching `@aztec-foundation/bb.js` on npm.
2. On conflicts it stops with the merge in progress. For each conflict:
   - **Upstream already has the change:** take upstream's side and move the row to "Already upstream".
   - **Partial overlap:** keep upstream's version and re-apply only the part that is still missing. If upstream
     tightened a condition the patch also edits (for example a relation `skip()`), keep upstream's extra checks.

   Then `git commit` and run the script again with the same tag.
3. Check that proofs are byte-identical (step 1 of "Validating"; the harness patches are not on this branch), and
   update the tables above.
4. Push the branch and open a PR into `community/v6`. Its CI builds the package and runs checks 2 and 3 of
   "Validating".
5. Merge the PR **with a merge commit**, not a squash. A squash drops upstream's history, and the next update would
   conflict on every upstream change again. The push to `community/v6` publishes the release (below).

## Releasing from GitHub

`.github/workflows/community-release.yml` runs on every PR into `community/v6` and on every push to it:

| Job | What it does |
|---|---|
| `version` | `<n>` = 1 + the highest published `<upstream-version>-optimise.<n>` |
| `build` (6 parallel jobs) | `build-release.sh native <platform>` for the 4 platforms and `build-release.sh wasm <preset>` for both WASM builds, in upstream's release image `aztecprotocol/build:3.0` |
| `pack` | `build-release.sh pack <n>`, then the stock-verifier check and the package smoke test (native and WASM) |
| `publish-npm` | only on a push to `community/v6`: `npm publish --tag latest` with npm trusted publishing |

Every merged PR is a release. As in upstream's `publish-npm` job, the workflow's OIDC token is the only credential,
and npm adds provenance on its own. On npmjs.com, `@nemi-fi/bb.js` trusts GitHub Actions with repository
`nemi-fi/aztec-packages`, workflow `community-release.yml` and environment `npm-publish`.

On GitHub, Actions must be enabled for the fork. The `npm-publish` environment can require a reviewer before
publishing. Upstream's workflows need AztecProtocol's infrastructure, so this branch keeps only
`community-release.yml`. `update-upstream.sh` deletes the others again in each merge, including new ones, before
reporting conflicts.

## Building a release

```bash
community/build-release.sh all 1     # -> community/out/nemi-fi-bb.js-<upstream>-optimise.1.tgz (+ .sha256)
```

`native <platform>`, `wasm <preset>` and `pack <n>` run one part each; CI runs them as separate jobs. The script is
fail-fast and runs the whole documented release process:

- avm-transpiler (stock `bb` links it):
  - `cargo build` for linux-amd64;
  - `cargo zigbuild` for aarch64-linux, x86_64-darwin and aarch64-darwin.
- Native `bb` + `nodejs_module`:
  - built with the zig 0.15.1 release presets (`clang20` for amd64-linux; `arm64-linux`, `amd64-macos` and
    `arm64-macos` for the others);
  - then finalised as upstream's `finalize_bb_binary` does: `llvm-strip`, the version written after
    `BARRETENBERG_VERSION_SENTINEL`, and the Mach-O files re-signed ad hoc (`ldid -S`, or `rcodesign sign`).
- Both WASM builds (`wasm-threads`, `wasm`).
- bb.js, built as `barretenberg/ts/bb.js/bootstrap.sh` does:
  - the `bb-avm-sim` / `cdb` workspaces are generated before `yarn install --immutable`;
  - the native binaries go into `build/<platform>/`;
  - packed with the stock `package.json` (renamed, re-versioned);
  - the build fails if any file of the stock tarball is missing.

Toolchain (as upstream's `build-images`, plus `ldid` and `cargo-zigbuild`, which upstream also installs separately):
- zig 0.15.1;
- wasi-sdk 27 at `/opt/wasi-sdk`;
- rustup + `cargo-zigbuild`;
- cmake, ninja, `llvm-strip`, `ldid` or `rcodesign`;
- node 22+ with corepack (yarn 4), npm, python3;
- `clang-format-20`, for the `aztec_constants.hpp` codegen. `pip install clang-format==20.1.8` works.

It needs a full checkout of this branch, including the `noir/noir-repo` submodule (the script initialises it). A
sparse checkout without `ci3/` breaks the bb.js step: `barretenberg/ts/bootstrap.sh` sources
`ci3/source_bootstrap`, and without it the bootstrap scripts call each other without end.

## Validating

`community/scripts/` holds the checks. A **harness build** is this branch with harness patches 0001–0002 on top.
The **upstream reference** is the base tag with the same two patches. Both are built with
`cmake --preset default -DAVM=OFF && ninja bb`. The flows are upstream's pinned Chonk inputs for the base
(`barretenberg/cpp/scripts/chonk-inputs.hash`, from
`https://aztec-ci-artifacts.s3.us-east-2.amazonaws.com/protocol/bb-chonk-inputs-<hash>.tar.gz`). The scripts need
python3 with `msgpack`.

1. **Byte-identical proofs and VKs:**
   `FLOWS=<flows> check_identical.sh <reference bb> > ref.txt`, then
   `FLOWS=<flows> REF=ref.txt check_identical.sh <harness bb>`. Both run with `BB_DETERMINISTIC_PROVING=42`. The
   proof comes from `bb prove`, and the VK from `bb write_vk --scheme chonk --circuit_kind hiding` on the hiding
   kernel. Always regenerate `ref.txt` for a new base.
2. **Stock verifier:** `FLOWS=<flows> verify_with_stock.sh <release bb> <stock bb>`. It uses real randomness: the
   stock `bb verify` must accept every proof and reject a one-byte-tampered copy. The stock bb is
   `package/build/amd64-linux/bb` from `npm pack @aztec-foundation/bb.js@<version>`.
3. **Package smoke test:** in a directory with the tarball, `@aztec-foundation/bb.js@<version>`, `msgpackr` and
   `pako` installed, run
   `FLOWS_DIR=<flows> PROVER_PKG=@nemi-fi/bb.js [PROVER_BACKEND=Wasm] node stock_bbjs_verify.mjs <flow>`. It proves
   with the package's native (default) or WASM backend and verifies with stock bb.js.
4. **Speed:** `FLOWS=<flows> ab.sh <stock bb> <release bb> 5 <flow-regex>` runs stock and release interleaved and
   reports wall time and peak RSS.

## Results for 6.0.0-optimise.1

Tarball: `nemi-fi-bb.js-6.0.0-optimise.1.tgz`, built by `community/build-release.sh 1` from `780416c6`,
sha256 `941cb7779a59fd736230c44e009678803e4e092c3382946983494f22ad563bfd`.
The published package is built by CI from the same commits; its sha256 is in the `community-release` run summary.

Checked on amd64-linux (4 cores, AVX-512 IFMA), against the 11 pinned v6.0.0 Chonk flows (`chonk-inputs.hash`
`afe8389cb7f21295`):

1. **Byte-identical:** 11/11 proofs and VKs identical to the upstream reference, and 11/11 again with IFMA forced off
   (`BB_FIELD_NO_IFMA=1 BB_MSM_NO_IFMA=1`).
2. **Stock verifier:** for 11/11 flows, stock `bb verify` 6.0.0 accepts the release `bb`'s real-randomness proof
   and rejects the tampered copy.
3. **Package smoke test** on `ecdsar1+transfer_0_recursions+sponsored_fpc`: the native default and WASM backends
   both prove, stock `@aztec-foundation/bb.js@6.0.0` verifies and rejects the tampered proof, and the VK matches
   the reference.
4. **Speed**, stock `bb` 6.0.0 against the release `bb`, 5 interleaved reps, min/median wall time:

   | Flow | Stock | Release | Release/stock | Peak RSS release/stock |
   |---|---|---|---|---|
   | `ecdsar1+transfer_0_recursions+sponsored_fpc` | 6.48 / 6.86 s | 4.31 / 4.77 s | 0.665 | 0.923 (230 vs 249 MiB) |
   | same, release with IFMA forced off | 6.77 s | 4.83 s | 0.714 | 0.924 |

   On this CPU the IFMA kernels account for about 11% of the release time. Stock bb has no IFMA switch, so its two
   timings differ only by noise.

Not used: the aztec-standards app flows captured for v6.0.0-rc.1. They do not match v6.0.0: stock bb 6.0.0 reports a
VK mismatch on `private_kernel_init_3`.
