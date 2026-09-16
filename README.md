# cobalt_optimized

Modular source tree for Cobalt (upstream ships it as a single 25k-line `cobalt.luau`).

`src/` is where you edit. `cobalt.luau` is the **generated** single-file bundle you
actually execute — regenerate it with `python3 tools/bundle.py` after changing `src/`.

## Structure

```
loader.luau          # Optional executor loader: pcall-guarded local read -> GitHub raw fallback
cobalt.luau          # GENERATED bundle, ~960KB / ~28.5k lines. Fully self-contained:
                     #   ClosureBindings  - one closure per module, body inlined from src/
                     #   ObjectTree       - virtual Instance tree the closures hang off
                     #   LineOffsets      - bundle line -> module line, for error messages
                     #   wax runtime      - ImportGlobals / LoadScript / virtual require
src/                 # Source of truth: 152 .luau modules
  init.luau          # Main LocalScript
  ExecutorSupport.luau
  Spy/               # Luau + RakNet hooks, interceptors, invocation tracking
  Utils/             # Anticheats, CallFilter, CodeGen, Hook, Plugins, UI helpers
  Window/            # Components, Modals, Utils, Views
lib/                 # Bundle inputs / dev artifacts
  ref_map.luau       # RefId -> src path; drives the bundler
  object_tree.luau   # ObjectTree source
  line_offsets.luau  # LineOffsets source
  wax_runtime.luau   # Wax runtime source
  config.luau        # Aliases, WaxVersion, EnvName
tools/
  bundle.py          # src/ -> cobalt.luau (also `--check` for CI)
  modulecheck.py     # Emits a Luau harness that executes every module in the bundle
.luaurc              # Aliases: src -> ./src, lib -> ./lib
verify.sh            # Structural checks; set LUAU=... to also execute the bundle
```

## How to Run

`cobalt.luau` is self-contained — one request, no local files needed:

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/cobalt.luau"))()
```

Or paste `loader.luau`, which prefers a local copy of `cobalt.luau` when the repo
sits inside the executor's script directory and falls back to raw GitHub:

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/loader.luau"))()
```

**Gotcha:** `readfile()` relative paths resolve against the *executor's script
directory* (e.g. Synapse's `scripts/` folder), **not** wherever you ran
`git clone`. A bare `readfile("cobalt.luau")` hard-errors with
`failed to read file` if the repo isn't inside that folder — and with no
`pcall` around it, the script dies before any remote fallback can run.
`loader.luau` wraps every local read in `pcall`, adds absolute-path
candidates via `getworkingdirectory()`, and falls back to raw GitHub.

## Build

```bash
python3 tools/bundle.py            # regenerate cobalt.luau from src/
python3 tools/bundle.py --check    # fail if cobalt.luau is stale
```

Every `ClosureBindings[N]` is emitted from `lib/ref_map.luau` as:

```luau
[N] = function(...) local wax,script,require=ImportGlobals(N) local ImportGlobals return (function(...)
<body of ref_map[N], verbatim>
end)(...) end,
```

The trailing `(...)` is what runs the module. `LoadScript()` treats a closure's
return values as the module's return values, so a closure that merely *returns*
the inner function reports success while the module body never executes — the UI
never appears and nothing errors. `tools/bundle.py --check` and `verify.sh` both
assert the invocating form is present.

## Verification

```bash
./verify.sh                        # structural: bundle freshness, closure/LineOffsets alignment
LUAU=/path/to/luau ./verify.sh     # + executes the bundle and loads every ModuleScript
```

Build the Luau CLI once with
`git clone --depth 1 https://github.com/luau-lang/luau && cd luau && make -j config=release luau`.

The executed check runs `loadstring(cobalt.luau)()` with `readfile` wired to fail
and `require` wired to reject strings — i.e. the remote-load configuration — then
drives the bundle's real `LoadScript()` over every ModuleScript. A healthy bundle
reports a mix of `table` and `function` first-return-values (the 5 modules that
legitimately `return` a function); the remaining errors are missing executor APIs
in the stub environment, not load failures.

- Bundle: ~960KB, ~28.5k lines, 151 module closures
- `cobalt.luau` compiles under Luau and runs to the point of touching real Roblox APIs
- Public API stable: `getgenv().Cobalt = wax`
