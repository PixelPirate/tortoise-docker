# Agent prompt: Implement the avoid-creature system

You are working in the TortoiseBots module checkout at
`/Users/pho/Turtle/New/TortoiseBots` (branch `main`, pinned upstream commit
`76a0a13d`). The image repo consuming your work is
`/Users/pho/Turtle/New/tortoise-docker` — read `docs/SPEC.md` for conventions.

## Problem

TortoiseBots has **no working avoid-creature system**. Its capability ledger
(rows `S-AVOID-CREATURE`, `T-AVOID-ABSENT`) records:

- `AvoidMobsStrategy` is registered but **inert**: `ai/playerbot/AiFactory.cpp`
  (~line 278) deliberately declines to install the mature strategy whose
  `setArea()` calls would hit unsupported core APIs.
- `ai/playerbot/strategy/actions/SetAvoidAreaAction.cpp` (lines ~10-21) is
  fail-closed: it declines every request.
- The Shyalya donor's full implementation
  (`actions/AvoidCreatureListAction.h/.cpp`,
  `values/AvoidCreatureListValue.h`, `CreatureIdValue.h/.cpp`, wired into
  ChatActionContext `'avoid creature'`, ValueContext list/id, StrategyContext
  `'avoid specific creatures'`, ChatCommandHandler, and consumed by
  `DungeonActions.cpp:228` / `DungeonTriggers.cpp:311`) is absent.

Player-visible effect: bots stand in obviously dangerous creatures/bosses
because nothing tells them which creatures to avoid and by how far.

## Task

1. Read the Shyalya donor implementation:
   https://github.com/Shyalya/tortoise-wow/blob/playerbots-integration-gh/modules/mod-playerbots/src/playerbot/strategy/actions/AvoidCreatureListAction.h
   (and `.cpp`, plus `values/AvoidCreatureListValue.h`, `values/CreatureIdValue.h`).
2. Port it into TortoiseBots following its own file layout:
   - `ai/playerbot/strategy/actions/AvoidCreatureListAction.{h,cpp}`
   - `ai/playerbot/strategy/values/AvoidCreatureListValue.h`
   - `ai/playerbot/strategy/values/CreatureIdValue.{h,cpp}` (if not present)
   - Wire into `ChatActionContext.h` (`avoid creature` chat shortcut),
     `ValueContext.h` (list/id values), `StrategyContext.h`
     (`avoid specific creatures` strategy), and the chat command handler's
     supported-command list.
3. Make the existing consumers work: `DungeonActions.cpp` and
   `DungeonTriggers.cpp` in the Shyalya donor consume the avoid list when
   positioning and choosing targets — mirror that consumption.
4. Resolve `SetAvoidAreaAction` and `AvoidMobsStrategy`: either complete the
   implementation using only APIs the Tortoise core actually provides
   (check `/Users/pho/Turtle/New/tortoise-wow/src/game` for movement/
   nuisance-area support), or keep them explicitly disabled with a comment
   pointing at the ledger row. Do not leave silently-dead registration.

## Constraints

- Creature IDs the *strategy* is seeded with must be Tortoise/Vanilla IDs —
  verify against the core's `sql/base/` world dump.
- The Shyalya donor is the behavior spec; AC's mod-playerbots has the same
  feature and may be consulted, but Shyalya's is the closer codebase.
- Keep the fail-closed posture for anything you cannot support (house rule:
  no silent no-ops).

## Deliverable

1. Working changes in the TortoiseBots checkout.
2. Patch `docker/penqle/patches/00N-avoid-creature.patch` (image repo),
   `git apply --check` clean against pin `76a0a13d...`.
3. If you add a config key (e.g. default avoid distance), wire it through
   `docker/penqle/render-config.sh` + `.env.example.penqle` +
   `docker-compose.penqle.yml` + image README; otherwise none.
4. Update the ledger rows (`S-AVOID-CREATURE`, `T-AVOID-ABSENT`) to reflect
   implementation state.

## Verify

- `git apply --check` on the patch.
- `bash tools/verify_penqle_host_contract.sh --core /Users/pho/Turtle/New/tortoise-wow` passes.
- Trigger/action wiring check (`tools/verify_action_trigger_wiring.py`) shows
  no new live-missing entries.
- Manual reasoning check: a bot told "avoid creature <id>" neither targets it
  nor paths into melee range of it.
