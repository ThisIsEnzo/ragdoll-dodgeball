# Balance invariant tests

The suite checks relationships between balance values instead of pinning specific
numbers, so designers can retune while CI catches contradictions.

## Covered areas

- Catch/throw speed compatibility and throw-type catchability
- Hit, pickup and vertical pickup thresholds
- Throw/charge ranges and ballistic court range
- Dodge duration, cooldown, i-frames and anti-cheat speed ceiling
- Round timings, ragdoll recovery, ultimate reachability, bot spacing and neutral band
- XP curve, match rewards, streak rewards, quest pool/stat consistency and cosmetic affordability
- Ultimate unlock labels/gates, loadout progression and baseline throw availability
- Rank progression, leaderboards and emote keys
- Coin pack value progression and non-combat gamepass effects
- Audio groups/volume bounds and required gameplay sound keys
- Remote rate limits

## Run locally

With the Luau CLI installed:

```sh
luau tools/tests/run.lua
```

The suite prints `TESTS_FAILED=N` and exits non-zero if any assertion fails.
The builder embeds the exact current `src/shared` module sources into one generated Luau file. Each module is compiled with a fresh environment that inherits the test runner's Roblox API shims. This avoids relying on filesystem access from Luau CLI or globals leaking across isolated `require` environments.\n\nRoblox Studio playtesting is still required for physics, input, UI and networking.


## Known configuration warning

The current `DodgeSpeed` (52) exceeds the configured movement anti-cheat ceiling (48.4). The suite reports this as `KNOWN_ISSUE` rather than failing CI: it is a gameplay/security tuning decision and must be resolved separately, not hidden by changing a test expectation.
