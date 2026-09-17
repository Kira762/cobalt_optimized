#!/usr/bin/env bash
# Verify the bundle.
#
#   ./verify.sh                # structural checks (python3 only)
#   LUAU=/path/to/luau ./verify.sh   # + actually execute the bundle
#
# Point LUAU at a locally built Luau CLI to run the optional execution check.
set -e
set -o pipefail
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

echo "== 4. runtime-link allowlist check =="
python3 - <<'PY'
import pathlib
import re

allowed = {
    "https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/cobalt.luau",
    "https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/loader.luau",
}
violations = []
# Only *executable* links matter: a URL inside a Luau string literal is a
# runtime fetch, while the same URL in a comment, a doc page or a maintainer
# script is attribution.  Non-Luau files are never executed by the game.
QUOTE_CHARS = '"' + chr(39) + chr(96)
LINK_IN_LITERAL = re.compile("[" + QUOTE_CHARS + "]" + "\s*(https?://[^\s" + QUOTE_CHARS + "]+)")
for path in pathlib.Path('.').rglob('*'):
    if path.is_dir() or '.git' in path.parts:
        continue
    if path.suffix not in ('.luau', '.lua'):
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    for match in LINK_IN_LITERAL.finditer(text):
        url = match.group(1)
        if url not in allowed:
            line = text.count(chr(10), 0, match.start()) + 1
            violations.append(f"{path}:{line}: unexpected runtime URL {url}")
    if re.search(r"\brequest\s*\(", text):
        violations.append(f"{path}: unexpected request() usage")

if violations:
    print('\n'.join(violations))
    raise SystemExit(1)
print("only the Cobalt GitHub loader/bundle URLs are present")
PY

if [ -z "${LUAU:-}" ]; then
    echo
    echo "== 5. skipped: set LUAU=/path/to/luau to execute the bundle =="
    echo "== 6. skipped: set LUAU=/path/to/luau to run the Log policy unit test =="
    echo "== 7. skipped: set LUAU=/path/to/luau to run the hot-path micro-benchmark =="
    exit 0
fi

echo
echo "== 5. execute the self-contained bundle (no readfile, Roblox require) =="
OUT="$(mktemp -t cobalt_modulecheck.XXXXXX.luau)"
trap 'rm -f "$OUT"' EXIT
python3 tools/modulecheck.py cobalt.luau "$OUT"
"$LUAU" "$OUT" | grep -vE '^  env '

echo
echo "== 6. Log capture-policy unit test =="
python3 tools/logpolicy.py --run

echo
echo "== 7. hot-path micro-benchmark =="
python3 tools/hotpath_bench.py --run
