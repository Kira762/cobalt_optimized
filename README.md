# Cobalt Optimized

Cobalt is a modular Luau remote inspector. `src/` is the source of truth and
`cobalt.luau` is the generated, self-contained bundle used by the executor.

Runtime loading is self-contained after the bundle is fetched:

- `assets/` contains the UI PNGs used by the local asset resolver.
- External asset/module downloads were removed. Missing local images fall back to
  the packaged Roblox asset ids and fonts use their packaged font ids.
- `loader.luau` downloads the latest generated bundle from this repository and
  refreshes the local cache, falling back to a local/cached `cobalt.luau` only
  when the download is unavailable (set `getgenv().CobaltPreferLocal = true`
  to keep a deliberately local build).
- Teleport relaunch reuses the lightweight loader so one-line loadstring users
  do not need to copy the large bundle by hand.

## Structure

```
loader.luau          # lightweight local-or-remote executor loader
cobalt.luau          # generated single-file bundle
assets/              # repository-owned logo, class markers, and icon atlas
src/                 # editable Luau modules
  init.luau          # runtime setup and cleanup
  Utils/Log.luau     # bounded capture, spam admission, and UI notifications
  Utils/Ratelimiter.luau
  Window/            # low-cost UI and views
lib/                 # bundle inputs and the virtual module tree
tools/bundle.py      # regenerates closures and serialized actor/HTML values
tools/modulecheck.py # emits the Luau module-load harness
tools/logpolicy.py   # emits/runs the Log capture-policy unit test
tools/hotpath_bench.py# emits/runs the hot-path micro-benchmark (bounded clone)
tools/build_assets.py# regenerates assets/ artwork from the lucide sheets
tools/gen_icons.py   # regenerates Icons.luau from the generated atlas
verify.sh            # structural + execution + policy verification
```

## Run locally

Run the lightweight remote loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/loader.luau"))()
```

The loader downloads the generated bundle from GitHub first and caches it as
`cobalt.luau` when `writefile` is available, so a stale cache can never pin you
to an old build. The local copy is only used when the download fails. You can still read `cobalt.luau` directly with
the executor's local file API if you want a fully local setup.

The bundle does not need the source tree at runtime, but the local assets are
used when the executor supports `getcustomasset`. If they are unavailable the
interface still loads without decorative icons.

## Capture safeguards

The hot capture path rejects work before deep-cloning arguments, and the
rejection policy is pinned by `tools/logpolicy.py`:

- a per-remote valve (500 captures / one-second window) and a global valve
  (2500 / window) *drop* excess captures and count them in
  `Log.SuppressedCalls` - they never mark a remote as ignored, so a burst can
  no longer empty the inspector;
- `Auto-ignore High-frequency Calls` is opt-in (off by default). When enabled,
  only a remote that overflows its *own* per-remote valve for two consecutive
  windows is ignored, and a toast explains why;
- a bounded, per-remote-coalesced notification queue;
- bounded GUI render jobs so stale call rows cannot grow without limit;
- per-remote call retention remains configurable (Settings -> Capture) and
  defaults to a finite cap.

`./verify.sh` runs both the policy test and the hot-path micro-benchmark
whenever `LUAU` points at a Luau CLI.

The argument clone itself is budgeted too: DeepClone stops descending past a
depth/field budget and shares the game's tables beyond it, so one hostile
payload can no longer stall the hook (and the frame) for seconds - ordinary
argument packs still clone field-for-field, and the bound is pinned by
`tools/hotpath_bench.py`. On the hook side, `getcallingscript()` is resolved
lazily (only when a verdict or a first-time log entry actually needs the
caller), the incoming connection listing is cached for half a second per
remote, and caller info is resolved in a single `debug.info` pass - in the
main state and in the actor environment alike.

## Interface

The window keeps the upstream dark theme but ships complete artwork and
motion instead of placeholders:

- the lucide icon atlas, class markers and the Cobalt logo are real local
  PNGs (`assets/`), with packaged Roblox asset ids as an offline fallback;
- interface animations are on by default (Settings -> Interface Animations
  switches them off); tweens are de-duplicated per object/property so hovering
  or recycling rows never stacks tweens;
- decorative outlines are back on static chrome (window edge, menus, dialogs,
  dropdowns, toasts) while pooled call rows stay cheap: a row's blocked /
  highlighted state is a single recycled `UIStroke` plus a background tint;
- the window is centered and ignores the Roblox top inset.

## Build and verify

```bash
python3 tools/bundle.py
python3 tools/bundle.py --check
./verify.sh
```

`tools/bundle.py` regenerates the closures and `LineOffsets` from `src/`, keeps
the serialized session template and actor environment in sync, and re-inlines
`lib/config.luau` + `lib/wax_runtime.luau` as the bundle tail, so the runtime
(`LoadScript`, `FormatError`, the virtual instance tree) cannot drift from
`lib/`.  The actor environment chunk is synced wholesale from
`src/Spy/Hooks/Luau/Actors/Environment.luau` (its Log include comes from
`src/Utils/Log.luau`), which makes that file the single source of truth for
the actor state instead of a hint the build used to patch around.

If a Luau CLI is available, set `LUAU` before running `verify.sh` to execute the
bundle's module-load harness as well. The harness intentionally stubs Roblox
APIs; failures that require a live executor are reported separately from bundle
and module-structure errors. It fails the build when a module calls an
identifier that no environment provides, when `Utils.Log` does not load, when a
nested module error loses its deepest module/line attribution, when the
generated actor environment does not compile, or when that actor environment
calls `require()` outside a `wax.shared.X or require(...)` guard (the actor chunk
runs standalone and has no wax `require`).

## Improved maintenance prompt

> Optimize Cobalt for games where a remote can fire continuously. Keep runtime
> execution offline: move every file-backed asset into `assets/`, remove runtime
> HTTP/module downloads, and provide safe local or packaged fallbacks. Protect
> the hot hook path with bounded per-remote and global capture budgets, bounded
> notification and GUI queues, finite call retention, and early dropping before
> argument cloning. Reduce unnecessary UI work by disabling decorative outlines
> and animations by default, reusing rows where practical, and keeping the main
> window centered and usable on small viewports. Preserve blocking, filtering,
> cleanup, logging, and plugin APIs. Put shared behavior in focused modules,
> regenerate the bundle, and run structural plus Luau verification before
> delivering the change.
