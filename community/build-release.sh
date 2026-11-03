#!/usr/bin/env bash
# Build the community @nemi-fi/bb.js release tarball from this tree.
#
# usage: community/build-release.sh native <platform>   # amd64-linux | arm64-linux | amd64-macos | arm64-macos
#        community/build-release.sh wasm <preset>       # wasm-threads | wasm
#        community/build-release.sh pack <n>            # -> $OUT/nemi-fi-bb.js-<upstream-version>-optimise.<n>.tgz
#        community/build-release.sh all <n>             # every native platform, both wasm builds, then pack
#
# `native` and `wasm` write to $OUT/native/<platform>/ and $OUT/wasm/<preset>/; `pack` reads both, so the builds can
# run as separate CI jobs and be gathered into $OUT before packing.
#   - native: avm-transpiler for the platform (stock bb links it), then bb + nodejs_module with the zig 0.15.1 release
#     preset, stripped, version-stamped and (Mach-O) re-signed ad hoc as upstream's finalize_bb_binary does.
#   - wasm: barretenberg.wasm.gz, checked against the initial memory bb.js allocates.
#   - pack: the TS package, laid over the stock @aztec-foundation/bb.js tarball of the same version: the stock
#     package.json is kept (only name and version change), and every stock file must be present.
#
# env:   OUT (default community/out), REPOSITORY (default nemi-fi/aztec-packages), JOBS (default nproc), UPSTREAM_VERSION (default community/UPSTREAM_VERSION)
# needs: zig 0.15.1, rustup + cargo-zigbuild, cmake, ninja, /opt/wasi-sdk (wasi-sdk 27), llvm-strip(-20),
#        ldid or rcodesign, node 22+ with corepack (yarn 4), npm, python3, clang-format-20 (constants codegen).
#        The upstream build image aztecprotocol/build:3.0 has all of them except ldid and cargo-zigbuild.
set -euo pipefail

CMD=${1:?usage: build-release.sh native <platform> | wasm <preset> | pack <n> | all <n>}
ARG=${2:?usage: build-release.sh native <platform> | wasm <preset> | pack <n> | all <n>}
ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
UPSTREAM_VERSION=${UPSTREAM_VERSION:-$(cat "$ROOT/community/UPSTREAM_VERSION")}
NAME=@nemi-fi/bb.js
REPOSITORY=${REPOSITORY:-nemi-fi/aztec-packages}
OUT=${OUT:-$ROOT/community/out}
OUT=$(mkdir -p "$OUT" && cd "$OUT" && pwd)
JOBS=${JOBS:-$(nproc)}
CPP=$ROOT/barretenberg/cpp
TS=$ROOT/barretenberg/ts
NATIVE=$OUT/native
WASM=$OUT/wasm
PLATFORMS=(amd64-linux arm64-linux amd64-macos arm64-macos)
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

log() { echo "==> $*" >&2; }
die() { echo "$*" >&2; exit 1; }

# The ts bootstrap scripts source ci3/source_bootstrap; without it they call each other without end.
test -f "$ROOT/ci3/source_bootstrap" || die "ci3/ is missing: build-release.sh needs a full checkout"
command -v cmake >/dev/null
command -v ninja >/dev/null

# platform -> cmake preset, build dir, rust target (empty: the host build of avm-transpiler).
preset_of() {
  case "$1" in
    amd64-linux) echo "clang20 build x86_64-unknown-linux-gnu" ;;
    arm64-linux) echo "arm64-linux build-arm64-linux aarch64-unknown-linux-gnu" ;;
    amd64-macos) echo "amd64-macos build-amd64-macos x86_64-apple-darwin" ;;
    arm64-macos) echo "arm64-macos build-arm64-macos aarch64-apple-darwin" ;;
    *) die "unknown platform $1" ;;
  esac
}

# Finalise like barretenberg/cpp/bootstrap.sh finalize_bb_binary: strip, stamp the version after the sentinel,
# re-sign Mach-O ad hoc (stamping invalidates the signature; macOS refuses to run unsigned arm64 code).
stamp_version() {
  local binary=$1 sentinel=BARRETENBERG_VERSION_SENTINEL offset
  offset=$(grep -aobF "$sentinel" "$binary" | head -n 1 | cut -d: -f1)
  [[ -n "$offset" ]] || die "version sentinel not found in $binary"
  printf '%s\0' "$UPSTREAM_VERSION" | dd of="$binary" bs=1 seek=$((offset + ${#sentinel})) conv=notrunc 2>/dev/null
}
sign_macho() {
  local signer
  signer=$(command -v ldid || command -v rcodesign)
  case "$signer" in
    *ldid) "$signer" -S "$1" ;;
    *rcodesign) "$signer" sign "$1" >/dev/null ;;
  esac
}

build_native() {
  local platform=$1 preset build_dir rust_target
  read -r preset build_dir rust_target <<<"$(preset_of "$platform")"
  [[ "$(zig version)" == "0.15.1" ]] || die "zig 0.15.1 required (got $(zig version))"
  local strip
  strip=$(command -v llvm-strip-20 || command -v llvm-strip)
  command -v clang-format-20 >/dev/null
  if [[ "$platform" == *-macos ]]; then
    command -v ldid >/dev/null || command -v rcodesign >/dev/null
  fi

  test -f "$ROOT/noir/noir-repo/Cargo.toml" || git -C "$ROOT" submodule update --init --depth 1 noir/noir-repo

  log "avm-transpiler $rust_target"
  cd "$ROOT/avm-transpiler"
  if [[ "$platform" == amd64-linux ]]; then
    cargo build --release --lib
  else
    command -v cargo-zigbuild >/dev/null
    rustup target add --toolchain "$(sed -n 's/^channel = "\(.*\)"/\1/p' rust-toolchain.toml)" "$rust_target"
    cargo zigbuild --release --lib --target "$rust_target"
  fi

  log "native $platform ($preset)"
  (cd "$CPP/src/barretenberg/nodejs_module" && yarn install --immutable)
  cd "$CPP"
  cmake --preset "$preset"
  cmake --build "$build_dir" --target bb nodejs_module -j "$JOBS"
  rm -rf "${NATIVE:?}/$platform"
  mkdir -p "$NATIVE/$platform"
  cp "$build_dir/bin/bb" "$build_dir/lib/nodejs_module.node" "$NATIVE/$platform/"
  "$strip" "$NATIVE/$platform/bb"
  stamp_version "$NATIVE/$platform/bb"
  if [[ "$platform" == *-macos ]]; then
    sign_macho "$NATIVE/$platform/bb"
    sign_macho "$NATIVE/$platform/nodejs_module.node"
  fi
  if [[ "$platform" == amd64-linux && "$(uname -m)" == x86_64 ]]; then
    [[ "$("$NATIVE/$platform/bb" --version)" == "$UPSTREAM_VERSION" ]] || die "bb --version is not $UPSTREAM_VERSION"
  fi
}

# bb.js creates the imported wasm memory itself; it must be at least the size the module declares.
check_wasm_memory() {
  local wasm_gz=$1 js_min wasm_min
  js_min=$(sed -n 's/.*static MIN_INITIAL_MEMORY_PAGES = \([0-9]*\);.*/\1/p' \
    "$TS/bb.js/src/barretenberg_wasm/barretenberg_wasm_main/index.ts")
  [[ -n "$js_min" ]] || die "MIN_INITIAL_MEMORY_PAGES not found in bb.js"
  wasm_min=$(node "$ROOT/community/scripts/wasm_memory_min.cjs" "$wasm_gz")
  (( wasm_min <= js_min )) || die "$wasm_gz declares $wasm_min initial pages > bb.js MIN_INITIAL_MEMORY_PAGES=$js_min"
}

build_wasm() {
  local preset=$1
  [[ "$preset" == wasm-threads || "$preset" == wasm ]] || die "unknown wasm preset $preset"
  test -x /opt/wasi-sdk/bin/clang
  command -v clang-format-20 >/dev/null
  log "wasm $preset"
  cd "$CPP"
  cmake --preset "$preset"
  cmake --build "build-$preset" --target barretenberg.wasm.gz -j "$JOBS"
  check_wasm_memory "build-$preset/bin/barretenberg.wasm.gz"
  rm -rf "${WASM:?}/$preset"
  mkdir -p "$WASM/$preset"
  cp "build-$preset/bin/barretenberg.wasm.gz" "$WASM/$preset/"
}

pack() {
  local n=$1 version stock tgz platform preset missing
  version="$UPSTREAM_VERSION-optimise.$n"
  for platform in "${PLATFORMS[@]}"; do
    test -f "$NATIVE/$platform/bb" || die "missing $NATIVE/$platform/bb: run 'native $platform' first"
    test -f "$NATIVE/$platform/nodejs_module.node" || die "missing $NATIVE/$platform/nodejs_module.node"
  done
  for preset in wasm-threads wasm; do
    test -f "$WASM/$preset/barretenberg.wasm.gz" || die "missing $WASM/$preset/barretenberg.wasm.gz: run 'wasm $preset' first"
    check_wasm_memory "$WASM/$preset/barretenberg.wasm.gz"
    # bb.js's copy_wasm.sh reads the wasm from the cpp build directories.
    mkdir -p "$CPP/build-$preset/bin"
    cp "$WASM/$preset/barretenberg.wasm.gz" "$CPP/build-$preset/bin/barretenberg.wasm.gz"
  done
  # Release artifacts may lose the executable bit when moved between CI jobs.
  chmod +x "$NATIVE"/*/bb

  log "stock @aztec-foundation/bb.js@$UPSTREAM_VERSION"
  stock=$OUT/stock
  rm -rf "$stock" && mkdir -p "$stock"
  (cd "$stock" && npm pack "@aztec-foundation/bb.js@$UPSTREAM_VERSION" >/dev/null)
  tar -xzf "$stock/aztec-foundation-bb.js-$UPSTREAM_VERSION.tgz" -C "$stock"

  log "bb.js $version"
  cd "$TS"
  ./bootstrap.sh generate_packages
  yarn install --immutable
  cd bb.js
  yarn clean
  # The cbind codegen asks bb for its msgpack schema.
  BB_BINARY_PATH=$NATIVE/amd64-linux/bb yarn generate
  yarn build:wasm
  rm -rf build
  mkdir -p build
  cp -r "$NATIVE"/. build/
  yarn build:esm
  yarn build:cjs
  yarn build:browser
  shopt -s globstar nullglob
  local snapshot_dir dest_dir file
  for snapshot_dir in src/**/__snapshots__; do
    dest_dir="${snapshot_dir/src\//dest\/node\/}"
    rm -rf "$dest_dir"
    cp -r "$snapshot_dir" "$dest_dir"
    for file in "$dest_dir"/*.test.ts.snap; do mv "$file" "${file/.test.ts.snap/.test.js.snap}"; done
  done
  shopt -u globstar nullglob

  # Pack with the stock package.json (identical exports, files, dependencies), renamed and re-versioned. The repository
  # points at this fork: npm trusted publishing requires it to match the repository the package is published from.
  cp package.json "$OUT/package.json.source"
  node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(process.argv[1]));
p.name = process.argv[2];
p.version = process.argv[3];
p.repository.url = "git+https://github.com/" + process.argv[4] + ".git";
fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");' "$stock/package/package.json" "$NAME" "$version" "$REPOSITORY"
  tgz=$OUT/nemi-fi-bb.js-$version.tgz
  rm -f "$tgz"
  npm pack --pack-destination "$OUT" >/dev/null
  cp "$OUT/package.json.source" package.json

  # Every file of the stock package must be in ours.
  tar -tzf "$stock/aztec-foundation-bb.js-$UPSTREAM_VERSION.tgz" | sort > "$OUT/stock_files.txt"
  tar -tzf "$tgz" | sort > "$OUT/package_files.txt"
  missing=$(comm -23 "$OUT/stock_files.txt" "$OUT/package_files.txt")
  [[ -z "$missing" ]] || die "files missing from the package:"$'\n'"$missing"
  comm -13 "$OUT/stock_files.txt" "$OUT/package_files.txt" > "$OUT/extra_files.txt"

  (cd "$OUT" && sha256sum "$(basename "$tgz")" | tee "$(basename "$tgz").sha256")
  (cd "$NATIVE" && sha256sum */bb */nodejs_module.node > "$OUT/native_sha256.txt")
  log "done: $tgz"
}

case "$CMD" in
  native) build_native "$ARG" ;;
  wasm) build_wasm "$ARG" ;;
  pack) pack "$ARG" ;;
  all)
    for platform in "${PLATFORMS[@]}"; do build_native "$platform"; done
    build_wasm wasm-threads
    build_wasm wasm
    pack "$ARG"
    ;;
  *) die "unknown command $CMD" ;;
esac
