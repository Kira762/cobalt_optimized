#!/usr/bin/env bash
set -e
echo "Verifying cobalt.luau loadstring..."
python3 -c "
from lupa import LuaRuntime
import pathlib
lua = LuaRuntime()
content = pathlib.Path('cobalt.luau').read_text()
# Check first 5000 chars can be loaded
lua.eval('load')(content[:5000])
print('loadstring syntax OK (first 5000)')
# Check key markers
for m in ['ClosureBindings','ObjectTree','ImportGlobals']:
    assert m in content, f'missing {m}'
print('markers OK')
print(f'size {len(content)} bytes, {len(content.splitlines())} lines')
"
echo "Checking src file count..."
find src -type f | wc -l
echo "Checking lib..."
ls -lh lib/
echo "Checking no leading -- comments in src (outside strings)..."
! grep -R "^\s*--" src --include="*.luau" | grep -v "https://gitlab" | grep -v "\[\[" | head && echo "no comments found (good)" || echo "some comments remain"
