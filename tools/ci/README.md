# CI checks

Four jobs run on every push to `master` and every pull request.

| Job | Blocks merge | Catches |
|---|---|---|
| Roblox invariants | yes | Script returns, protected property writes, if-expression as call argument, missing modules, bad Rojo paths, BOM, config typos, duplicate names |
| Luau syntax | yes | Parse errors in files under `src/` and `tools/` |
| Rojo build | yes | Project structure that cannot produce a place file |
| StyLua | no | Formatting drift, advisory only |

## Why custom rules

Generic Luau syntax checks cannot identify Roblox runtime restrictions. A Script
returning a value parses but fails at load. Writing protected Lighting
properties also parses but throws at runtime. These are hard gates.

## Run locally

```sh
python tools/ci/roblox_rules.py
```

Exit code 1 means at least one invariant is violated. Add `--github` for
GitHub Actions annotations.
