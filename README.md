# Cobalt Optimized

Cobalt is a modular Luau remote inspector. `src/` is the source of truth and
`cobalt.luau` is the generated, self-contained bundle used by the executor.

Runtime loading is self-contained after the bundle is fetched:

- `assets/` contains the UI PNGs used by the local asset resolver.
- External asset/module downloads were removed. Missing local images fall back to
  the packaged Roblox asset ids and fonts use their packaged font ids.
- `loader.luau` prefers a local/cached `cobalt.luau`, then falls back to
  downloading the generated bundle from this repository.
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
verify.sh            # structural verification
```

## Run locally

Run the lightweight remote loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/loader.luau"))()
```

The loader prefers `cobalt.luau` from the executor's script directory when it is
already present, then downloads the generated bundle from GitHub and caches it
when `writefile` is available. You can still read `cobalt.luau` directly with
the executor's local file API if you want a fully local setup.

The bundle does not need the source tree at runtime, but the local assets are
used when the executor supports `getcustomasset`. If they are unavailable the
interface still loads without decorative icons.

## Performance safeguards

The hot capture path now rejects work before deep-cloning arguments:

- at most 120 captures per remote per one-second window;
- at most 600 captures across all remotes per one-second window;
- a bounded, per-remote-coalesced notification queue;
- bounded GUI render jobs so stale call rows cannot grow without limit;
- per-remote call retention remains configurable and defaults to a finite cap;
- animations are off by default and decorative `UIStroke` outlines are skipped;
- the Cobalt window is centered and ignores the Roblox top inset.

The high-frequency auto-ignore setting is enabled by default. Turn it off only
when a complete high-volume trace is intentional; the hard capture budgets
remain in place so tracing cannot freeze the game.

## Build and verify

```bash
python3 tools/bundle.py
python3 tools/bundle.py --check
./verify.sh
```

If a Luau CLI is available, set `LUAU` before running `verify.sh` to execute the
bundle's module-load harness as well. The harness intentionally stubs Roblox
APIs; failures that require a live executor are reported separately from bundle
and module-structure errors.

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
