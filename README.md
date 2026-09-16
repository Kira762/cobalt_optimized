# cobalt_optimized

Refactored modular version of Cobalt (originally single-file `cobalt.luau` 25k+ lines).

## Structure

```
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
```luau
loadstring(readfile("cobalt.luau"))()
-- or
loadstring(game:HttpGet("https://.../cobalt.luau"))()
```
`cobalt.luau` remains self-contained via fallback closures. If `src/` is present, it will load from filesystem for development; otherwise it uses embedded fallback.

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
