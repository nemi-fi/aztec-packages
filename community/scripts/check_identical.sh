#!/usr/bin/env bash
# Prove every flow in FLOWS with BB_DETERMINISTIC_PROVING=42 and print sha256 of the proof and of the hiding-kernel VK
# computed by `bb write_vk --scheme chonk --circuit_kind hiding`. Needs a bb built with the harness patches.
#   FLOWS=<dir of <flow>/ivc-inputs.msgpack> check_identical.sh <bb> > hashes.txt          (make a reference)
#   FLOWS=... REF=hashes.txt check_identical.sh <bb>                                        (compare; exit 1 on diff)
# Output lines: <proof sha256> <vk sha256> <flow>
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BB=$1
PY=${PYTHON:-python3}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
fail=0
for d in "$FLOWS"/*/; do
  flow=$(basename "$d")
  o=$OUT/$flow
  mkdir -p "$o"
  BB_DETERMINISTIC_PROVING=42 "$BB" prove --scheme chonk --ivc_inputs_path "$d/ivc-inputs.msgpack" -o "$o" > "$o/prove.log" 2>&1
  "$PY" "$HERE/extract_hiding.py" "$d/ivc-inputs.msgpack" "$o/in"
  "$BB" write_vk --scheme chonk --circuit_kind hiding -b "$o/in/hiding_bytecode" -o "$o/vkout" > "$o/vk.log" 2>&1
  line="$(sha256sum < "$o/proof" | cut -c1-64) $(sha256sum < "$o/vkout/vk" | cut -c1-64) $flow"
  status=""
  [[ -z "${REF:-}" ]] || status=$(grep -qxF "$line" "$REF" && echo " IDENTICAL" || echo " DIFFERENT")
  [[ "$status" != " DIFFERENT" ]] || fail=1
  echo "$line$status"
done
exit $fail
