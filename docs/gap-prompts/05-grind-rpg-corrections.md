# Agent prompt: Port Shyalya's grind/RPG behavior corrections

You are working in the TortoiseBots module checkout at
`/Users/pho/Turtle/New/TortoiseBots` (branch `main`, pinned upstream commit
`3003220`). The image repo consuming your work is
`/Users/pho/Turtle/New/tortoise-docker` — read `docs/SPEC.md` for conventions.

## Problem

TortoiseBots' grind/RPG engine (the code that makes idle bots roam, pick
grind spots, travel, and patrol — the "world feels alive" behavior) was
copied from Shyalya's fork at commit `1f9497e` and has **not** received
Shyalya's later corrections. The capability ledger row `F04-RPG` records
four specific divergences, queued but unbuilt:

1. **Crowd tally** — Shyalya's newer crowd-size accounting for grind-spot
   eligibility (how many mobs/players are already at a spot) is not ported;
   TortoiseBots can stack bots on the same busy spot.
2. **RNG source** — Shyalya fixed a random-source divergence (dedicated RNG
   vs shared/global rand) in the RPG destination/choice logic; TortoiseBots
   still uses the old source, which skews bot choice and makes behavior
   harder to reproduce/test.
3. **Patrol pause** — a patrol pacing fix (bots pausing correctly between
   patrol legs instead of chaining) is missing.
4. **Taxi-cheat exclusion** — Shyalya excludes certain taxi usage that would
   be "cheating" (bots using flight paths a real player at that level/reputation
   could not use); the exclusion list/logic is not ported.

The ledger also notes two adjacent gaps in the same area that are NOT in
scope here (avoid-creature: see `02-avoid-creature.md`; spell-click: absent
because the Tortoise core lacks support).

## Task

1. Diff the donor files against TortoiseBots' copies. Donor:
   https://github.com/Shyalya/tortoise-wow/blob/playerbots-integration-gh/modules/mod-playerbots/src/playerbot/
   Focus on the grind/RPG/travel area: `strategy/actions/` (GrindStrategy,
   Rpg/RpgActions, travel/patrol actions, taxi actions) and the value files
   they read. Identify exactly where the four corrections live upstream
   (they postdate `1f9497e`; Shyalya's branch tip is the current donor).
2. Port each correction individually as an isolated commit-equivalent inside
   your patch, in ledger order (crowd tally, RNG source, patrol pause,
   taxi-cheat exclusion). If a correction turns out to depend on core APIs
   Tortoise lacks, document that and skip it (fail-closed, house style) —
   update the ledger row accordingly.
3. Verify level gates still hold: TortoiseBots gates bots below level 5 out
   of RPG travel (`runtime/BotManager.cpp` ~line 70) — do not weaken that
   gate while porting.

## Constraints

- Donor is Shyalya's branch (same ike3 codebase, MaNGOS-zero compatible);
  do NOT substitute AC mod-playerbots code here — the RPG/grind code differs
  structurally between the two donors.
- Keep TortoiseBots' own adaptations intact where it diverged deliberately
  (e.g. GenericRpg destination cache with persisted `ai_playerbot_zone_level`
  — see comments in `runtime/BotManager.cpp` ~line 88). The corrections must
  land on top of TortoiseBots' current logic, not revert it.
- Behavior-only: no config keys expected. If you must add one, wire it
  through `docker/penqle/render-config.sh` + `.env.example.penqle` +
  compose + README.

## Deliverable

1. Working changes in the TortoiseBots checkout.
2. Patch `docker/penqle/patches/00N-grind-rpg-corrections.patch` (image
   repo), `git apply --check` clean against pin `3003220...`.
3. Ledger row `F04-RPG` updated per correction (ported / skipped+why).

## Verify

- `git apply --check` on the patch.
- Host contract script passes: `bash tools/verify_penqle_host_contract.sh
  --core /Users/pho/Turtle/New/tortoise-wow`.
- `tools/verify_action_trigger_wiring.py` shows no new live-missing entries.
- Reasoning checks: (a) two idle bots no longer deterministically pick the
  same grind spot (RNG + crowd tally); (b) a bot cannot board a flight path
  it does not satisfy the requirements for; (c) patrol legs are separated by
  the donor's pause behavior.
