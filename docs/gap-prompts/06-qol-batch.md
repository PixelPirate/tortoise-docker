# Agent prompt: QoL batch — ready-check rebuff, trade fixes, taxi fixes, interrupt rework, rogue fixes

You are working in the TortoiseBots module checkout at
`/Users/pho/Turtle/New/TortoiseBots` (branch `main`, pinned upstream commit
`76a0a13d`). The image repo consuming your work is
`/Users/pho/Turtle/New/tortoise-docker` — read `docs/SPEC.md` for conventions.

This is a batch of five small, independent behavior fixes, all ported from
AzerothCore's mod-playerbots **after** the commit TortoiseBots was ported
from (`5397110`). Each is independently valuable; implement them in order
and stop if one turns out to depend on core APIs Tortoise lacks (document
and skip, house fail-closed style). Ship each as its own patch file so they
can be dropped individually if one breaks.

## 1. Force rebuff on ready check (donor PR #2571)

When a ready check fires, bots currently reply ready regardless of buff
state. Port the donor behavior: on ready check, bots whisper their readiness
and **top up missing/expiring buffs before confirming ready** (out-of-reagent
bots report not-ready); a new `rebuff` chat command runs the same pass
manually; the donor gates it behind `AiPlayerbot.ForceRebuffOnReadyCheck`
(default off — keep that default, then expose it as env var
`AI_FORCE_REBUFF_ON_READY_CHECK` through the image: `render-config.sh`,
`.env.example.penqle`, compose, README table). Verify the ready-check
opcode/handler exists in the Tortoise core
(`/Users/pho/Turtle/New/tortoise-wow/src/game`, search `readycheck`) — if the
handler surface differs from WotLK, adapt to it; the 2-minute staleness
ceiling from the donor is a policy constant, keep it.

## 2. Trade fixes (donor PR #2651)

Port the selfbot/randombot trade hardening: (a) trades with refused/cancelled
outcome must send the cancel packet so the bot does not sit in a phantom
open-trade state; (b) randombots must refuse trades from selfbots the way
they refuse players (no "offer an apple, take their item" exploits). Find the
trade handling in the Tortoise core (`src/game/Handlers/` or `TradeHandler`)
and the module's trade actions; adapt the donor logic. Selfbot itself is
blocked upstream in TortoiseBots (ledger F18) — port only the parts that
affect normal player↔bot trades and packet hygiene.

## 3. Taxi fixes (donor PR #2668)

Two bugs ported together: (a) the flight-path BFS treated all taxi nodes as
bidirectional — one-way nodes route bots into dead ends (bots piling up
outside Stormwind/IF); (b) cross-map (continent) taxi flights were never
completed because the client packet that triggers the map change mid-flight
was never sent. Find TortoiseBots' taxi graph (`TravelMgr`/`TravelNode`
files under `ai/playerbot/`) and the donor's diff, port both fixes. Verify
the graph data comes from Tortoise's `TaxiNodes`/`TaxiPath` DB
(the core's `sql/base` world dump) — Vanilla's node graph differs from
WotLK's.

## 4. Interrupt rework (donor PR #2680)

AC replaced every `InterruptNonMeleeSpells(true)` /
`PlayerbotAI::InterruptSpell()` call with `Unit::CastStop()`: bots no longer
cancel in-flight projectiles or queued melee swings (impossible for a human),
fake spell-failure packets are gone, and dead guards (e.g. a
BattlegroundTactics interrupt guard whose args excluded everything, so
interrupts never ran) are deleted. Grep TortoiseBots for the same call
sites; check the Tortoise core's `Unit` API for the equivalent of
`CastStop` (`/Users/pho/Turtle/New/tortoise-wow/src/game/Unit.cpp` — if a
direct equivalent does not exist, use the closest safe primitive and
document the divergence). Port the call-site rework, including removing
always-false guards of the same shape.

## 5. Rogue fixes (donor PRs #2616, #2684)

Both spells are Vanilla-valid: (a) **Riposte** — add
`RiposteAvailableTrigger` (CAN_CAST pattern, mirroring warrior
overpower/revenge triggers) to the combat-rogue DPS strategy so Riposte
fires on parry; (b) **Blade Flurry** — the donor's trigger key was misspelled
(`BladeFuryTrigger` vs registered `blade flurry` wiring) so it never fired;
check TortoiseBots' rogue strategy for the same key mismatch, fix it, and
wire Blade Flurry into the AOE strategy at high priority + boss-fight
cooldown use. Verify both spell IDs against Tortoise data.

## Deliverables

1. Working changes in the TortoiseBots checkout.
2. One patch file per fix in the image repo:
   `docker/penqle/patches/00N-<fix-name>.patch`, each `git apply --check`
   clean against pin `76a0a13d...` **independently** (they must be droppable
   without breaking the others).
3. Ledger note per fix (ported / skipped + reason).
4. Env/compose/README wiring only for the ready-check config key (item 1);
   the others need none.

## Verify

- `git apply --check` on every patch file.
- Host contract script passes: `bash tools/verify_penqle_host_contract.sh
  --core /Users/pho/Turtle/New/tortoise-wow`.
- `tools/verify_action_trigger_wiring.py` shows no new live-missing entries
  (especially for the two new rogue triggers).
- No WotLK-only spell IDs introduced; ready-check and trade packet usage
  matches the Tortoise core's handlers.
