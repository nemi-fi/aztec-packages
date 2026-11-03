#!/usr/bin/env bash
# Usage: [FLOWS=<flows dir>] ab.sh <bin-A> <bin-B> <reps> <flow-regex>
# Interleaved A/B benchmark of chonk proving. For every run records wall time and peak RSS (max resident set size of
# the bb process, via getrusage). Prints min/median wall time and min/median peak RSS per flow for each binary.
set -u
A=$1; B=$2; REPS=$3; FILTER=$4
FLOWS=${FLOWS:-${WORK:-$HOME/bbwork}/flows}
TMP=$(mktemp -d)
for f in $(ls -d $FLOWS/*/ | xargs -n1 basename | sort | grep -E "$FILTER"); do
  for r in $(seq $REPS); do
    for which in A B; do
      bin=$A; [ $which = B ] && bin=$B
      python3 - "$bin" "$FLOWS/$f/ivc-inputs.msgpack" "$TMP" "$f" "$which" >> $TMP/t.txt <<'PY'
import os, resource, subprocess, sys, time
bb, inputs, out, flow, which = sys.argv[1:]
env = dict(os.environ, BB_DETERMINISTIC_PROVING="42")
t0 = time.monotonic()
subprocess.run([bb, "prove", "--scheme", "chonk", "--ivc_inputs_path", inputs, "-o", out],
               env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
wall = time.monotonic() - t0
peak_kib = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
print(flow, which, f"{wall:.3f}", peak_kib)
PY
    done
  done
done
python3 - "$TMP/t.txt" <<'PY'
import sys, collections, statistics
t = collections.defaultdict(list); m = collections.defaultdict(list)
for l in open(sys.argv[1]):
    f, w, wall, rss = l.split(); t[(f, w)].append(float(wall)); m[(f, w)].append(int(rss) / 1024)
flows = sorted({k[0] for k in t})
ta = tb = ma = mb = 0
for f in flows:
    a, b, ra, rb = t[(f, 'A')], t[(f, 'B')], m[(f, 'A')], m[(f, 'B')]
    ta += min(a); tb += min(b); ma += max(ra); mb += max(rb)
    print(f"{f[:52]:52s} time A {min(a):6.2f}/{statistics.median(a):6.2f} B {min(b):6.2f}/{statistics.median(b):6.2f} "
          f"B/A {min(b)/min(a):.3f} | peakRSS MiB A {max(ra):7.1f} B {max(rb):7.1f} B/A {max(rb)/max(ra):.3f}")
print(f"TOTAL time(min) A {ta:.2f} B {tb:.2f} ratio {tb/ta:.3f} | peakRSS(sum of per-flow max) A {ma:.0f} B {mb:.0f} MiB ratio {mb/ma:.3f}")
PY
rm -rf $TMP
