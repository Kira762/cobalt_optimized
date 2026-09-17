# Local Cobalt assets

These files are shipped with the repository so the interface never downloads
artwork while it starts. When a local file is unavailable (for example when
someone runs only the single Luau bundle), Cobalt falls back to the packaged
Roblox asset ids declared in `src/Utils/UI/Assets/Registry.luau`.

| File | Contents |
| --- | --- |
| `ui-icons.png` | 192x144 atlas, 8 columns of 24px cells, one per icon the built-in UI uses. Cell order is listed in `_icon_atlas_map.txt` and mirrored by `IconCells` in `src/Utils/UI/Assets/Icons.luau`. |
| `cobalt-logo.png` | The Cobalt mark, 128x128, used by the top bar and the launcher button. |
| `remote-event.png`, `unreliable-remote-event.png`, `remote-function.png`, `bindable-event.png`, `bindable-function.png` | 32x32 class markers shown next to captured remotes. |

## Provenance & regeneration

* The icon artwork is Lucide (ISC license) taken from the sprite sheets of
  [mstudio45/lucide-roblox-direct](https://github.com/mstudio45/lucide-roblox-direct)
  (MIT), the same sheets the upstream icon module streamed at runtime. The
  class markers are Lucide glyphs chosen to match each remote class
  (`radio-tower`, `satellite`, `square-function`, `link-2`, `braces`).
* `cobalt-logo.png` is the upstream Cobalt logo, downscaled with area
  averaging.
* Everything here is regenerated offline by the maintainer script
  `tools/build_assets.py` (not part of the runtime bundle); the generated
  `_icon_atlas_map.txt` documents the atlas cell order.

No runtime code path fetches any of these files over the network.
