#!/usr/bin/env bash
# Prove every flow in FLOWS with the candidate bb using real randomness, verify each proof with the STOCK bb
# (`bb verify --scheme chonk`) against the hiding-kernel VK from the inputs, and check that a one-byte-tampered copy is
# rejected.
#   FLOWS=<dir of <flow>/ivc-inputs.msgpack> verify_with_stock.sh <candidate bb> <stock bb>
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CAND=$1
STOCK=$2
PY=${PYTHON:-python3}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
fail=0
for d in "$FLOWS"/*/; do
  flow=$(basename "$d")
  o=$OUT/$flow
  mkdir -p "$o"
  env -u BB_DETERMINISTIC_PROVING "$CAND" prove --scheme chonk --ivc_inputs_path "$d/ivc-inputs.msgpack" -o "$o" > "$o/prove.log" 2>&1
  "$PY" "$HERE/extract_hiding.py" "$d/ivc-inputs.msgpack" "$o"
  v=0; "$STOCK" verify --scheme chonk -p "$o/proof" -k "$o/vk" > "$o/verify.log" 2>&1 || v=$?
  "$PY" -c "import sys;b=bytearray(open(sys.argv[1],'rb').read());b[len(b)//2]^=1;open(sys.argv[2],'wb').write(b)" "$o/proof" "$o/proof.tampered"
  t=0; "$STOCK" verify --scheme chonk -p "$o/proof.tampered" -k "$o/vk" > "$o/verify_t.log" 2>&1 || t=$?
  st=PASS
  [[ $v == 0 && $t != 0 ]] || { st=FAIL; fail=1; }
  echo "$flow verify_rc=$v tampered_rc=$t $st"
done
exit $fail
