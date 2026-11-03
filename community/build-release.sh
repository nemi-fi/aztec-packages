#!/usr/bin/env bash
# Build the community @nemi-fi/bb.js release tarball from this tree, end to end:
#   - avm-transpiler for the 4 release platforms (cargo / cargo-zigbuild),
#   - native bb + nodejs_module for {amd64,arm64}-{linux,macos} with the zig 0.15.1 release presets,
#     stripped, version-stamped and (Mach-O) re-signed ad hoc like the stock release,
#   - both WASM targets (wasm-threads, wasm),
#   - the TS package, laid over the stock @aztec-foundation/bb.js tarball of the same version:
#     the stock package.json is kept (only name and version change), and every stock file must be present.
#
# usage: community/build-release.sh <n>        -> @nemi-fi/bb.js@<upstream-version>-optimise.<n>
# env:   OUT (default community/out), JOBS (default nproc), UPSTREAM_VERSION (default community/UPSTREAM_VERSION)
# needs: zig 0.15.1, rustup + cargo-zigbuild, cmake, ninja, /opt/wasi-sdk (wasi-sdk 27), llvm-strip,
#        rcodesign or ldid, node 22+ with corepack (yarn 4), npm, python3, clang-format-20 (constants codegen).
set -euo pipefail

N=${1:?usage: build-release.sh <optimise-number>}
ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
UPSTREAM_VERSION=${UPSTREAM_VERSION:-$(cat "$ROOT/community/UPSTREAM_VERSION")}
VERSION="$UPSTREAM_VERSION-optimise.$N"
NAME=@nemi-fi/bb.js
OUT=${OUT:-$ROOT/community/out}
JOBS=${JOBS:-$(nproc)}
CPP=$ROOT/barretenberg/cpp
TS=$ROOT/barretenberg/ts
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

log() { echo "==> $*" >&2; }

# --- toolchain checks (fail before spending hours on a build) ---
[[ "$(zig version)" == "0.15.1" ]] || { echo "zig 0.15.1 required (got $(zig version))" >&2; exit 1; }
command -v cargo-zigbuild >/dev/null
command -v cmake >/dev/null
command -v ninja >/dev/null
command -v llvm-strip >/dev/null
command -v clang-format-20 >/dev/null
test -x /opt/wasi-sdk/bin/clang
SIGNER=$(command -v ldid || command -v rcodesign)
mkdir -p "$OUT"

# --- stock tarball of the same upstream version ---
STOCK=$OUT/stock
rm -rf "$STOCK" && mkdir -p "$STOCK"
(cd "$STOCK" && npm pack "@aztec-foundation/bb.js@$UPSTREAM_VERSION" >/dev/null)
tar -xzf "$STOCK/aztec-foundation-bb.js-$UPSTREAM_VERSION.tgz" -C "$STOCK"

# --- noir sources (avm-transpiler depends on them) ---
test -f "$ROOT/noir/noir-repo/Cargo.toml" || git -C "$ROOT" submodule update --init --depth 1 noir/noir-repo

# --- avm-transpiler for every release platform ---
log "avm-transpiler"
cd "$ROOT/avm-transpiler"
TOOLCHAIN=$(sed -n 's/^channel = "\(.*\)"/\1/p' rust-toolchain.toml)
rustup target add --toolchain "$TOOLCHAIN" aarch64-unknown-linux-gnu x86_64-apple-darwin aarch64-apple-darwin
cargo build --release --lib
for target in aarch64-unknown-linux-gnu x86_64-apple-darwin aarch64-apple-darwin; do
  cargo zigbuild --release --lib --target "$target"
done

# --- native bb + nodejs_module ---
(cd "$CPP/src/barretenberg/nodejs_module" && yarn install --immutable)
cd "$CPP"
# platform=preset:build-dir. amd64-linux uses the clang20 preset (zig cc, glibc 2.35) as the stock release does.
PLATFORMS=(amd64-linux=clang20:build arm64-linux=arm64-linux:build-arm64-linux
           amd64-macos=amd64-macos:build-amd64-macos arm64-macos=arm64-macos:build-arm64-macos)
NATIVE=$OUT/native
rm -rf "$NATIVE"
for entry in "${PLATFORMS[@]}"; do
  platform=${entry%%=*}; rest=${entry#*=}; preset=${rest%%:*}; build_dir=${rest#*:}
  log "native $platform ($preset)"
  cmake --preset "$preset"
  cmake --build "$build_dir" --target bb nodejs_module -j "$JOBS"
  mkdir -p "$NATIVE/$platform"
  cp "$build_dir/bin/bb" "$build_dir/lib/nodejs_module.node" "$NATIVE/$platform/"
done

# Finalise like barretenberg/cpp/bootstrap.sh finalize_bb_binary: strip, stamp the version after the sentinel,
# re-sign Mach-O ad hoc (stamping invalidates the signature; macOS refuses to run unsigned arm64 code).
stamp_version() {
  local binary=$1 sentinel=BARRETENBERG_VERSION_SENTINEL offset
  offset=$(grep -aobF "$sentinel" "$binary" | head -n 1 | cut -d: -f1)
  [[ -n "$offset" ]] || { echo "version sentinel not found in $binary" >&2; exit 1; }
  printf '%s\0' "$UPSTREAM_VERSION" | dd of="$binary" bs=1 seek=$((offset + ${#sentinel})) conv=notrunc 2>/dev/null
}
sign_macho() {
  case "$SIGNER" in
    *ldid) "$SIGNER" -S "$1" ;;
    *rcodesign) "$SIGNER" sign "$1" >/dev/null ;;
  esac
}
for platform in amd64-linux arm64-linux amd64-macos arm64-macos; do
  llvm-strip "$NATIVE/$platform/bb"
  stamp_version "$NATIVE/$platform/bb"
done
for platform in amd64-macos arm64-macos; do
  sign_macho "$NATIVE/$platform/bb"
  sign_macho "$NATIVE/$platform/nodejs_module.node"
done
[[ "$("$NATIVE/amd64-linux/bb" --version)" == "$UPSTREAM_VERSION" ]]

# --- WASM ---
for preset in wasm-threads wasm; do
  log "wasm $preset"
  cmake --preset "$preset"
  cmake --build "build-$preset" --target barretenberg.wasm.gz -j "$JOBS"
done

# --- TS package ---
log "bb.js"
cd "$TS"
./bootstrap.sh generate_packages
yarn install --immutable
cd bb.js
yarn clean
yarn generate
yarn build:wasm
rm -rf build
mkdir -p build
cp -r "$NATIVE"/. build/
yarn build:esm
yarn build:cjs
yarn build:browser
shopt -s globstar nullglob
for snapshot_dir in src/**/__snapshots__; do
  dest_dir="${snapshot_dir/src\//dest\/node\/}"
  rm -rf "$dest_dir"
  cp -r "$snapshot_dir" "$dest_dir"
  for file in "$dest_dir"/*.test.ts.snap; do mv "$file" "${file/.test.ts.snap/.test.js.snap}"; done
done
shopt -u globstar nullglob

# Pack with the stock package.json (identical exports, files, dependencies, repository), renamed and re-versioned.
cp package.json "$OUT/package.json.source"
node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(process.argv[1]));
p.name = process.argv[2];
p.version = process.argv[3];
fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");' "$STOCK/package/package.json" "$NAME" "$VERSION"
TGZ=$OUT/nemi-fi-bb.js-$VERSION.tgz
rm -f "$TGZ"
npm pack --pack-destination "$OUT" >/dev/null
cp "$OUT/package.json.source" package.json

# Every file of the stock package must be in ours.
tar -tzf "$STOCK/aztec-foundation-bb.js-$UPSTREAM_VERSION.tgz" | sort > "$OUT/stock_files.txt"
tar -tzf "$TGZ" | sort > "$OUT/package_files.txt"
MISSING=$(comm -23 "$OUT/stock_files.txt" "$OUT/package_files.txt")
[[ -z "$MISSING" ]] || { echo "files missing from the package:" >&2; echo "$MISSING" >&2; exit 1; }
comm -13 "$OUT/stock_files.txt" "$OUT/package_files.txt" > "$OUT/extra_files.txt"

(cd "$OUT" && sha256sum "$(basename "$TGZ")" | tee "$(basename "$TGZ").sha256")
(cd "$NATIVE" && sha256sum */bb */nodejs_module.node > "$OUT/native_sha256.txt")
log "done: $TGZ"
