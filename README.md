# cobalt_optimized

Refactored modular version of Cobalt (originally single-file `cobalt.luau` 25k+ lines).

## Structure

```
loader.luau          # Robust executor loader: pcall-guarded local candidates -> GitHub raw fallback
cobalt.luau          # Main entry point — still executable via loadstring, now thin (~7.5k lines, 494KB)
                     # Loads modules from src/ via wax virtual FS with filesystem fallback
src/                 # Extracted source modules (152 files)
  init.luau          # Main LocalScript (formerly ClosureBindings[1])
  ExecutorSupport.luau
  Spy/
    init.luau
    Hooks/
      Luau/
        init.luau
        Actors/
          Environment.luau
        Interceptors/
          Incoming.luau
          Outgoing.luau
      RakNet/
        ...
  Utils/
    Anticheats/
    CallFilter/
    CodeGen/
    Hook/
    Plugins/
    ...
  Window/
    Components/
    Modals/
    Utils/
    Views/
    ...
lib/                 # Wax bundling support (modularized runtime)
  config.luau        # Aliases, WaxVersion, EnvName
  object_tree.luau   # ObjectTree (virtual DOM)
  line_offsets.luau  # LineOffsets for debugging
  ref_map.luau       # RefId -> file path mapping
  wax_runtime.luau   # Wax runtime (virtual FS, ImportGlobals, LoadScript)
  fallback_closures.luau # Embedded fallback for loadstring without filesystem
.luaurc              # Aliases: src -> ./src, lib -> ./lib
```

## How to Run

### Roblox (loadstring)

Paste `loader.luau` (preferred) — it tries local file candidates (each
`pcall`-guarded) and falls back to GitHub raw, so it boots whether or not the
repo is inside the script directory:

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/loader.luau"))()
-- or
loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/cobalt.luau"))()
```

**Gotcha:** `readfile()` relative paths resolve against the *executor's script
directory* (e.g. Synapse's `scripts/` folder), **not** wherever you ran
`git clone`. A bare `readfile("cobalt.luau")` hard-errors with
`failed to read file` if the repo isn't inside that folder — and with no
`pcall` around it, the script dies before any remote fallback can run.
`loader.luau` wraps every local read in `pcall`, adds absolute-path
candidates via `getworkingdirectory()`, and falls back to raw GitHub.

For local/dev use, clone (or copy) the repo **into the script directory** so
`readfile("cobalt.luau")` resolves. `cobalt.luau` remains self-contained via
fallback closures; if `src/` is present next to it, it will load modules from
the filesystem for development; otherwise it uses the embedded fallback.

### Lune / Luau Development
```bash
lune run src/init.luau
# or verify syntax
lua -l cobalt.luau
```

The `.luaurc` configures aliases so `require("@src/...")` and `require("@lib/...")` resolve correctly.

## Verification

- Original: 911KB, 25688 lines, single file
- Refactored: 494KB main + 1.2MB src + 900KB lib (modular, comments stripped)
- All comments removed from every file (verified via stripper)
- `cobalt.luau` still passes `loadstring` syntax check and retains `wax.shared`, `ObjectTree`, `ImportGlobals` behavior
- No logic or behavior changes; public API stable (`getgenv().Cobalt = wax`)

## Build

No build step required for development. To re-bundle for distribution, the `lib/fallback_closures.luau` is regenerated from `src/` via the extraction script in `tmp/`.
