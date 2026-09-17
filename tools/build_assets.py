#!/usr/bin/env python3
"""Rebuild Cobalt's local UI artwork from the upstream lucide spritesheets.

Needs a checkout of https://github.com/mstudio45/lucide-roblox-direct (point
LUCIDE_DIR at it) and, for the logo, any Cobalt Logo.png (COBALT_LOGO_SOURCE).
Run from a maintainer machine; the runtime never executes this.

Outputs (written into <repo>/assets):
  ui-icons.png          24px-cell atlas of every icon the interface uses
  cobalt-logo.png       the official Cobalt logo, downscaled to 128x128
  <class>-<name>.png    per-class marker glyphs, 32x32 (24px glyph centered)
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import png

LUCIDE = pathlib.Path(__import__("os").environ.get("LUCIDE_DIR", "/tmp/lucide_direct"))
REPO = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/home/user/cobalt_optimized")
ASSETS = REPO / "assets"

src = (LUCIDE / "source.lua").read_text()
i = src.index("local icons = {{")
j = src.index("},{", i)
names = src[i + len("local icons = {{") : j].split('","')
names[0] = names[0].lstrip('"')
names[-1] = names[-1].rstrip('"')
index_of = {n: k + 1 for k, n in enumerate(names)}

reg_start = src.index("{[48]={{", j) + len("{[48]=")
depth = 0
k = reg_start
while True:
    c = src[k]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            break
    k += 1
reg_body = src[reg_start : k + 1]
entries = re.findall(r"\{(\d+),\{(\d+),(\d+)\},\{(\d+),(\d+)\}\}", reg_body)
print(f"{len(names)} icons, {len(entries)} registry cells")

sheets = {1: png.read(LUCIDE / "spritesheets/1.png"), 2: png.read(LUCIDE / "spritesheets/2.png")}
print("sheets:", {k: (v[0], v[1]) for k, v in sheets.items()})

UI_ICONS = [
    "align-vertical-distribute-center", "ban", "blocks", "bug", "check",
    "chevron-down", "circle-alert", "circle-fading-arrow-up", "code", "copy",
    "ellipsis", "eye", "file", "file-clock", "file-search", "file-text",
    "forward", "gamepad-2", "globe", "list-filter", "lock", "lock-open",
    "minus", "network", "package-search", "parentheses", "pencil", "play",
    "plus", "scroll-text", "search", "settings", "shield-alert", "terminal",
    "trash", "triangle-alert", "x",
]
CLASS_ICONS = {
    "remote-event": "radio-tower",
    "unreliable-remote-event": "satellite",
    "remote-function": "square-function",
    "bindable-event": "link-2",
    "bindable-function": "braces",
}

CELL = 24
COLS = 8
all_icons = UI_ICONS + list(CLASS_ICONS.values())
missing = [n for n in all_icons if n not in index_of]
assert not missing, missing
ROWS = (len(all_icons) + COLS - 1) // COLS

atlas = bytearray(COLS * CELL * ROWS * CELL * 4)
mapping = {}
for pos, name in enumerate(all_icons):
    sheet_idx, w, h, x, y = (int(v) for v in entries[index_of[name] - 1])
    sw, sh, srgba = sheets[sheet_idx]
    cell = png.crop((sw, sh, srgba), x, y, CELL, CELL)
    cx, cy = (pos % COLS) * CELL, (pos // COLS) * CELL
    for ry in range(CELL):
        for rx in range(CELL):
            si = (ry * CELL + rx) * 4
            di = ((cy + ry) * COLS * CELL + (cx + rx)) * 4
            atlas[di : di + 4] = cell[2][si : si + 4]
    mapping[name] = pos + 1

png.write(ASSETS / "ui-icons.png", COLS * CELL, ROWS * CELL, atlas)
print(f"ui-icons.png: {COLS*CELL}x{ROWS*CELL}, {len(all_icons)} cells")

# per-class marker PNGs: 32x32 canvas with the 24px glyph centered
for file_name, icon in CLASS_ICONS.items():
    sheet_idx, w, h, x, y = (int(v) for v in entries[index_of[icon] - 1])
    sw, sh, srgba = sheets[sheet_idx]
    cell = png.crop((sw, sh, srgba), x, y, CELL, CELL)
    canvas = bytearray(32 * 32 * 4)
    off = (32 - CELL) // 2
    for ry in range(CELL):
        for rx in range(CELL):
            si = (ry * CELL + rx) * 4
            di = ((ry + off) * 32 + (rx + off)) * 4
            canvas[di : di + 4] = cell[2][si : si + 4]
    png.write(ASSETS / f"{file_name}.png", 32, 32, canvas)
    print(f"{file_name}.png written")

# logo: area-average downscale of the official 420x420 logo to 128x128
LOGO_SOURCE = pathlib.Path(__import__("os").environ.get("COBALT_LOGO_SOURCE", "/tmp/cobalt_mirror/Assets/Logo.png"))
lw, lh, lrgba = png.read(LOGO_SOURCE)
TW = TH = 128
out = bytearray(TW * TH * 4)
for ty in range(TH):
    for tx in range(TW):
        sy0, sy1 = ty * lh // TH, (ty + 1) * lh // TH
        sx0, sx1 = tx * lw // TW, (tx + 1) * lw // TW
        acc = [0, 0, 0, 0]
        n = 0
        for sy in range(sy0, max(sy1, sy0 + 1)):
            for sx in range(sx0, max(sx1, sx0 + 1)):
                si = (sy * lw + sx) * 4
                for c in range(4):
                    acc[c] += lrgba[si + c]
                n += 1
        di = (ty * TW + tx) * 4
        out[di : di + 4] = bytes(min(255, acc[c] // n) for c in range(4))
png.write(ASSETS / "cobalt-logo.png", TW, TH, out)
print("cobalt-logo.png written (128x128)")

(REPO / "assets" / "_icon_atlas_map.txt").write_text(
    "\n".join(f"{pos}\t{name}" for name, pos in sorted(mapping.items(), key=lambda kv: kv[1])) + "\n"
)
print("atlas map written")
