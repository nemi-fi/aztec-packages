#!/usr/bin/env bash
# CI entry point, run inside the build image aztecprotocol/build:3.0 from the repository root.
# usage: community/scripts/ci_build.sh native <platform> | wasm <preset> | pack <n>
set -euo pipefail

KIND=${1:?usage: ci_build.sh native <platform> | wasm <preset> | pack <n>}
TARGET=${2:?usage: ci_build.sh native <platform> | wasm <preset> | pack <n>}

git config --global --add safe.directory "*"

# As upstream: ldid signs the Mach-O binaries, and avm-transpiler/bootstrap.sh installs cargo-zigbuild. Neither is in
# the build image.
if [[ "$KIND" == native && "$TARGET" == *-macos ]]; then
  curl -fsSL https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64 \
    -o /usr/local/bin/ldid
  chmod +x /usr/local/bin/ldid
fi
if [[ "$KIND" == native && "$TARGET" != amd64-linux ]]; then
  # From avm-transpiler/ so rustup uses its pinned toolchain: the image's default rustc is too old for cargo-zigbuild.
  (cd avm-transpiler && cargo install --locked cargo-zigbuild@0.24.0)
fi

exec community/build-release.sh "$KIND" "$TARGET"
