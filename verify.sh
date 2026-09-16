#!/usr/bin/env bash
# Verify the bundle.
#
#   ./verify.sh                # structural checks (python3 only)
#   LUAU=/path/to/luau ./verify.sh   # + actually execute the bundle
#
# Point LUAU at a locally built Luau CLI to run the optional execution check.
set -e
cd "$(dirname "$0")"

echo "== 1. cobalt.luau is in sync with src/ =="
python3 tools/bundle.py --check

echo
echo "== 2. closure / LineOffsets structure =="
python3 - <<'PY'
import pathlib
import re

text = pathlib.Path("cobalt.luau").read_text()
entries = re.findall(r"^    \[(\d+)\] = function\(\.\.\.\) local wax,script,require=ImportGlobals\((\d+)\)", text, re.M)
assert entries, "no ClosureBindings entries found"
for ref, passed in entries:
    assert ref == passed, f"entry [{ref}] passes ref {passed} to ImportGlobals"
closers = len(re.findall(r"^    end\)\(\.\.\.\) end,$", text, re.M))
assert len(entries) == closers, f"{len(entries)} entries but {closers} invocating closers"

for stale in ('require, "@lib/ref_map"', 'require, "@lib/fallback_closures"', "Failed to load module"):
    assert stale not in text, f"stale dynamic loader still present: {stale}"

lo = text[text.index("local LineOffsets = {"):]
lo = lo[: lo.index("\n}\n")]
offsets = {int(a): int(b) for a, b in re.findall(r"^    \[(\d+)\] = (\d+),$", lo, re.M)}
ids = {int(r) for r, _ in entries}
assert ids == set(offsets), "LineOffsets and ClosureBindings cover different ref ids"

lines = text.split("\n")
for ref, line in offsets.items():
    assert re.match(r"^    \[%d\] = function" % ref, lines[line - 2]), f"LineOffsets[{ref}] misaligned"

print(f"{len(entries)} closures, {len(offsets)} line offsets, {len(text)} bytes, {len(lines)} lines")
PY

echo
echo "== 3. src/ tree =="
echo "src files: $(find src -type f -name '*.luau' | wc -l)"
echo "ref_map entries: $(grep -cE '^\s*\[[0-9]+\] = "' lib/ref_map.luau)"

if grep -RInE 'https?://|game:HttpGet\(|request[[:space:]]*\(' --exclude-dir=.git .; then
    echo "offline runtime-link check failed" >&2
    exit 1
fi
echo "== 4. offline runtime-link check =="
echo "no external runtime links found"

if [ -z "${LUAU:-}" ]; then
    echo
    echo "== 5. skipped: set LUAU=/path/to/luau to execute the bundle =="
    exit 0
fi

echo
echo "== 5. execute the self-contained bundle (no readfile, Roblox require) =="
OUT="$(mktemp -t cobalt_modulecheck.XXXXXX.luau)"
trap 'rm -f "$OUT"' EXIT
python3 tools/modulecheck.py cobalt.luau "$OUT"
"$LUAU" "$OUT" | grep -vE '^  env ' 
