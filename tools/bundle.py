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

The bundle tail (everything from `local Aliases = {` on) is likewise rebuilt
from lib/config.luau + lib/wax_runtime.luau, and the serialized session template
and actor environment are re-synced from their sources (the actor chunk is
carried wholesale, with only its Log include regenerated), so no part of the
bundle can drift from the files you edit.

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
SESSION_TEMPLATE = ROOT / "src" / "Utils" / "CodeGen" / "Templates" / "SessionHTMLView.html"
SESSION_MARKER = '"SessionHTMLView",\n'
ACTOR_LOG_SOURCE = ROOT / "src" / "Utils" / "Log.luau"
ACTOR_ENVIRONMENT_SOURCE = ROOT / "src" / "Spy" / "Hooks" / "Luau" / "Actors" / "Environment.luau"
ACTOR_ENVIRONMENT_MARKER = '"Environment",\n'
CONFIG_SOURCE = ROOT / "lib" / "config.luau"
WAX_RUNTIME_SOURCE = ROOT / "lib" / "wax_runtime.luau"

CLOSURE_START = "local ClosureBindings = {"
OBJECT_TREE_START = "local ObjectTree = {"
LINE_OFFSETS_START = "local LineOffsets = {"
LINE_OFFSETS_END = "\n}\n"
RUNTIME_START = "\nlocal Aliases = {"
CONFIG_LAST_LOCAL = "local EnvName ="


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


def lua_quote(value: str, chunk_size: int = 12000) -> str:
    """Quote UTF-8 text as a Luau string expression.

    ObjectTree stores generated text values directly instead of reading extra
    files at runtime. Decimal byte escapes keep the generated object tree
    portable across executors with different source encodings. Large values are
    emitted as concatenated string chunks because Luau rejects extremely long
    single-line string literals as malformed.
    """
    escaped: list[str] = []
    for byte in value.encode("utf-8"):
        if byte == 10:
            escaped.append("\\n")
        elif byte == 13:
            escaped.append("\\r")
        elif byte == 9:
            escaped.append("\\t")
        elif byte == 92:
            escaped.append("\\\\")
        elif byte == 34:
            escaped.append('\\"')
        elif 32 <= byte <= 126:
            escaped.append(chr(byte))
        else:
            escaped.append("\\%03d" % byte)

    chunks: list[str] = []
    current: list[str] = []
    current_len = 0
    for part in escaped:
        if current and current_len + len(part) > chunk_size:
            chunks.append('"' + "".join(current) + '"')
            current = []
            current_len = 0
        current.append(part)
        current_len += len(part)
    chunks.append('"' + "".join(current) + '"')

    if len(chunks) == 1:
        return chunks[0]
    return "(\n" + " ..\n".join("                                            " + chunk for chunk in chunks) + "\n                                        )"


def find_value_span(object_tree: str, marker: str) -> tuple[int, int]:
    """Return the content span of a serialized `Value = "..."` field."""
    # ObjectTree also contains an enum entry named Environment; the serialized
    # ModuleScript is the last matching node and is the one with a Value field.
    marker_index = object_tree.rfind(marker)
    if marker_index < 0:
        raise AssertionError(f"object-tree marker is missing: {marker!r}")

    prefix = 'Value = "'
    value_start = object_tree.find(prefix, marker_index) + len(prefix)
    if value_start < len(prefix):
        raise AssertionError(f"Value field is missing after {marker!r}")

    escaped = False
    index = value_start
    # Recover from an early synchronizer version that emitted a second opening
    # quote for the session template.
    if object_tree.startswith('"<!DOCTYPE html>', value_start):
        index += 1
    while index < len(object_tree):
        char = object_tree[index]
        if char == '"' and not escaped:
            # Repair a historical bad SessionHTMLView sync that left two quoted
            # strings back-to-back (Value = "...""<!DOCTYPE html>...").  Treat
            # both quoted strings as the old value span so regeneration emits a
            # single valid Luau string again.
            if object_tree.startswith('"<!DOCTYPE html>', index + 1):
                second_index = index + 2
                second_escaped = False
                while second_index < len(object_tree):
                    second_char = object_tree[second_index]
                    if second_char == '"' and not second_escaped:
                        return value_start, second_index
                    if second_char == "\\" and not second_escaped:
                        second_escaped = True
                    else:
                        second_escaped = False
                    second_index += 1
            return value_start, index
        if char == "\\" and not escaped:
            escaped = True
        else:
            escaped = False
        index += 1

    raise AssertionError(f"serialized Value field is unterminated after {marker!r}")


def replace_serialized_value(object_tree: str, marker: str, value: str, *, chunk_size: int = 12000) -> str:
    marker_index = object_tree.rfind(marker)
    if marker_index < 0:
        raise AssertionError(f"object-tree marker is missing: {marker!r}")

    prefix = "Value = "
    expr_start = object_tree.find(prefix, marker_index) + len(prefix)
    if expr_start < len(prefix):
        raise AssertionError(f"Value field is missing after {marker!r}")

    quoted = lua_quote(value, chunk_size=chunk_size)

    if object_tree[expr_start] == '"':
        start, end = find_value_span(object_tree, marker)
        # Replace the whole quoted literal, not just its contents, so large values
        # can become parenthesized concatenation expressions.
        return object_tree[: start - 1] + quoted + object_tree[end + 1 :]

    if object_tree[expr_start] == "(":
        # Repair/rewrite a chunked expression emitted by this bundler.  The
        # generated closing parenthesis is intentionally indented to the Value
        # field, which gives us a stable terminator without having to parse
        # arbitrary JavaScript inside the string chunks.
        terminator = "\n                                        )"
        expr_end = object_tree.find(terminator, expr_start)
        if expr_end < 0:
            raise AssertionError(f"chunked Value field is unterminated after {marker!r}")
        expr_end += len(terminator)
        if expr_end < len(object_tree) and object_tree[expr_end] == '"':
            # Recover from an intermediate generator that left the old closing
            # quote after a parenthesized chunk expression.
            expr_end += 1
        return object_tree[:expr_start] + quoted + object_tree[expr_end:]

    raise AssertionError(f"unsupported Value expression after {marker!r}")


def sync_session_template(object_tree: str) -> str:
    """Keep the serialized SessionHTMLView in sync with its editable template."""
    template = SESSION_TEMPLATE.read_text().replace("\r\n", "\n")
    return replace_serialized_value(object_tree, SESSION_MARKER, template)


def sync_actor_environment(object_tree: str) -> str:
    """Rebuild the serialized actor environment from its editable source.

    Actors execute the `Environment.Value` stored in ObjectTree, never the
    ModuleScript closure, so src/Spy/Hooks/Luau/Actors/Environment.luau must
    reach that string as a whole.  The old build only carried a few surgical
    patches over the previously embedded copy, which let the source file and
    the shipped actor chunk drift apart (the file kept a stale Log module
    copy and different descendant scans).  Syncing wholesale makes the
    source file the truth again: every edit propagates, and `--check` fails
    if the two ever diverge.

    The one generated region inside the chunk is the Log module: the `do
    local Log = {} ... wax.shared.Log = Log end` block in the source (a
    placeholder there) is replaced with src/Utils/Log.luau, indented one
    level and with its trailing `return Log` rewritten to publish the module
    on `wax.shared` - the same text the main state loads as a module.
    """
    embedded = ACTOR_ENVIRONMENT_SOURCE.read_text().replace("\r\n", "\n").strip("\n")

    log_source = ACTOR_LOG_SOURCE.read_text().replace("\r\n", "\n").strip("\n")
    if not log_source.endswith("return Log"):
        raise AssertionError("actor Log source must end with `return Log`")
    log_source = log_source[: -len("return Log")] + "wax.shared.Log = Log"

    log_start = embedded.find("do\n\tlocal Log = {}")
    log_end = embedded.find("\n\twax.shared.Log = Log\nend", log_start)
    if log_start < 0 or log_end < 0:
        raise AssertionError("actor environment Log region markers are missing")
    log_end += len("\n\twax.shared.Log = Log\nend")

    indented_log = "\n".join("\t" + line if line else "" for line in log_source.split("\n"))
    embedded = embedded[:log_start] + "do\n" + indented_log + "\nend" + embedded[log_end:]

    return replace_serialized_value(object_tree, ACTOR_ENVIRONMENT_MARKER, embedded, chunk_size=1_000_000_000)


def sync_runtime(cobalt: str) -> str:
    """Rebuild the bundle tail from lib/config.luau + lib/wax_runtime.luau.

    Everything from `local Aliases = {` to end of file is the wax runtime, and
    `lib/` is its source of truth.  Regenerating it here means an edit to
    LoadScript()/FormatError() cannot be left behind in the bundle, and
    `--check` reports the drift instead of silently shipping the old runtime.

    config.luau is a module that returns a table; the bundle inlines only its
    locals (Aliases, WaxVersion, EnvName), so copy up to the last `local`.
    """
    index = cobalt.rindex(RUNTIME_START)

    config = CONFIG_SOURCE.read_text().replace("\r\n", "\n").split("\n")
    locals_ = [i for i, line in enumerate(config) if line.startswith(CONFIG_LAST_LOCAL)]
    if not locals_:
        raise AssertionError(f"{CONFIG_LAST_LOCAL!r} not found in {CONFIG_SOURCE.name}")
    runtime = WAX_RUNTIME_SOURCE.read_text().replace("\r\n", "\n").split("\n")

    return cobalt[: index + 1] + "\n".join(config[: locals_[-1] + 1] + [""] + runtime)


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
    synced = sync_actor_environment(current)
    synced = sync_session_template(synced)
    synced = sync_runtime(synced)
    new = bundle(synced)
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
