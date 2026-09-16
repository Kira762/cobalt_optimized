#!/usr/bin/env python3
"""Bundle src/ into the single-file, loadstring-ready cobalt.luau.

cobalt.luau is a wax bundle: a virtual Instance tree (ObjectTree), a table of
per-module closures (ClosureBindings) and a small runtime that wires them
together.  Each ClosureBindings entry must *execute* its module body and return
the module's results, because LoadScript() treats the closure's return values as
the module's return values.

Every entry is generated here from src/ using the ref ids in lib/ref_map.luau:

    [N] = function(...) local wax,script,require=ImportGlobals(N) local ImportGlobals return (function(...)
    <verbatim source of ref_map[N]>
    end)(...) end,

The trailing `(...)` is what actually runs the module; without it the closure
merely *returns* a function and LoadScript() reports success while the module
body never executes.

LineOffsets is regenerated in the same pass so that FormatError() can translate
an absolute line number in the bundle back to a line inside the offending module.

Usage:  python3 tools/bundle.py [--check]
  --check   regenerate in memory and fail if cobalt.luau on disk is stale
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
COBALT = ROOT / "cobalt.luau"
REF_MAP = ROOT / "lib" / "ref_map.luau"

CLOSURE_START = "local ClosureBindings = {"
OBJECT_TREE_START = "local ObjectTree = {"
LINE_OFFSETS_START = "local LineOffsets = {"
LINE_OFFSETS_END = "\n}\n"


def read_ref_map() -> dict[int, str]:
    text = REF_MAP.read_text()
    return {int(a): b for a, b in re.findall(r"\[(\d+)\]\s*=\s*\"([^\"]+)\"", text)}


def file_refs(ref_map: dict[int, str]) -> list[int]:
    return sorted(k for k, v in ref_map.items() if v.endswith(".luau"))


def read_source(path: str) -> str:
    text = (ROOT / path).read_text().replace("\r\n", "\n")
    # Trim blank lines at both ends so the body starts exactly one line below the
    # closure header and the closing `end)(...) end,` stays on its own line.
    return text.strip("\n")


def build_closures(ref_map: dict[int, str], closure_start_line: int) -> tuple[str, dict[int, int]]:
    """Return the ClosureBindings block plus {ref_id: 0-based index of first body line}.

    `closure_start_line` is the 1-based line number of `local ClosureBindings = {`
    in the final file, i.e. everything the bundle keeps above the closures.
    """
    out: list[str] = [CLOSURE_START]
    line_index = closure_start_line  # 0-based index of the line that will be appended next
    starts: dict[int, int] = {}

    for ref_id in file_refs(ref_map):
        out.append(
            "    [%d] = function(...) local wax,script,require=ImportGlobals(%d) "
            "local ImportGlobals return (function(...)" % (ref_id, ref_id)
        )
        line_index += 1
        starts[ref_id] = line_index
        body = read_source(ref_map[ref_id])
        out.append(body)
        line_index += body.count("\n") + 1
        out.append("    end)(...) end,")
        line_index += 1

    return "\n".join(out), starts


def build_line_offsets(starts: dict[int, int]) -> str:
    """One `[N] = line,` per ref that owns a closure, ascending.  Fixed line count."""
    lines = [LINE_OFFSETS_START]
    for ref_id in sorted(starts):
        lines.append("    [%d] = %d," % (ref_id, starts[ref_id] + 1))  # Lua lines are 1-based
    return "\n".join(lines)


def swap_closures(cobalt: str, closures: str) -> str:
    head, _, rest = cobalt.partition(CLOSURE_START)
    sep, _, tail = rest.partition(OBJECT_TREE_START)
    # `sep` is the old table body; it must start with an entry and end with the closing brace.
    assert sep.startswith("\n    [") and sep.rstrip().endswith("}"), (
        "unexpected text between ClosureBindings and ObjectTree: %r...%r" % (sep[:40], sep[-40:])
    )
    return head + closures + "\n}\n\n" + OBJECT_TREE_START + tail


def swap_line_offsets(cobalt: str, line_offsets: str) -> str:
    head, _, rest = cobalt.partition(LINE_OFFSETS_START)
    _, sep, tail = rest.partition(LINE_OFFSETS_END)
    assert sep == LINE_OFFSETS_END, "LineOffsets table not terminated as expected"
    return head + line_offsets + LINE_OFFSETS_END + tail


def bundle(cobalt: str) -> str:
    ref_map = read_ref_map()

    closure_start_line = cobalt.partition(CLOSURE_START)[0].count("\n") + 1
    closures, starts = build_closures(ref_map, closure_start_line)
    # Pass 1: zero-filled offsets give the block its final line count.
    staged = swap_line_offsets(swap_closures(cobalt, closures), build_line_offsets({k: 0 for k in starts}))
    # Pass 2: now that the shape is final, the real offsets are stable.
    return swap_line_offsets(staged, build_line_offsets(starts))


def verify(text: str) -> None:
    """Sanity-check the generated bundle without needing a Roblox runtime."""
    n_entries = len(re.findall(r"^    \[\d+\] = function\(\.\.\.\) local wax,script,require=ImportGlobals", text, re.M))
    n_closers = len(re.findall(r"^    end\)\(\.\.\.\) end,$", text, re.M))
    assert n_entries == n_closers, f"entry/closer mismatch: {n_entries} vs {n_closers}"

    ref_map = read_ref_map()
    expected = len(file_refs(ref_map))
    assert n_entries == expected, f"expected {expected} closures, generated {n_entries}"

    for stale in ('require, "@lib/ref_map"', 'require, "@lib/fallback_closures"', "Failed to load module"):
        assert stale not in text, f"stale dynamic loader still present: {stale}"

    window = text[text.index(LINE_OFFSETS_START) :]
    window = window[: window.index(LINE_OFFSETS_END)]
    offsets = {int(a): int(b) for a, b in re.findall(r"^    \[(\d+)\] = (\d+),$", window, re.M)}
    ids = {int(m) for m in re.findall(r"^    \[(\d+)\] = function\(\.\.\.\)", text, re.M)}
    assert ids == set(offsets), "LineOffsets and ClosureBindings disagree"

    lines = text.split("\n")
    for ref_id, line in offsets.items():
        # the line above the recorded offset must be this module's closure header
        header = lines[line - 2]
        assert re.match(r"^    \[%d\] = function" % ref_id, header), (
            f"LineOffsets[{ref_id}]={line} does not point just past its header: {header!r}"
        )
        assert "ImportGlobals(%d)" % ref_id in header, f"LineOffsets[{ref_id}] points at the wrong closure"

    print(f"bundle OK: {n_entries} closures, {len(text)} bytes, {len(lines)} lines")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if cobalt.luau is out of date")
    args = ap.parse_args()

    current = COBALT.read_text()
    new = bundle(current)
    verify(new)

    if args.check:
        if new != current:
            print("cobalt.luau is stale - run: python3 tools/bundle.py", file=sys.stderr)
            return 1
        print("cobalt.luau is up to date")
        return 0

    COBALT.write_text(new)
    print(f"wrote {COBALT} ({len(new)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
