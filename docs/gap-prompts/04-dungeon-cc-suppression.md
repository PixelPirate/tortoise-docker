# Agent prompt: Suppress crowd control in 5-man dungeons

You are working in the TortoiseBots module checkout at
`/Users/pho/Turtle/New/TortoiseBots` (branch `main`, pinned upstream commit
`76a0a13d`). The image repo consuming your work is
`/Users/pho/Turtle/New/tortoise-docker` — read `docs/SPEC.md` for conventions.

## Problem

AzerothCore's mod-playerbots merged PR #2648 ("fix(dungeons): stop the
generic `cc` strategy from firing in 5-man dungeons") **after** the commit
TortoiseBots was ported from (`5397110`), so TortoiseBots inherited the bug
the PR fixes: in non-raid dungeons, bots cast their generic crowd-control
spells on trash — Polymorph, Shackle Undead, Turn Undead, Scare Beast,
Hibernate, Freezing Trap, Sap, Entangling Roots, Banish, Fear — which breaks
pulls (a CC'd mob aggroes everything when it breaks; sap/polymorph pull
guards) and wipes groups. This is one of the most group-breaking behaviors a
bot can exhibit.

The AC fix introduced a `Strategy::IsSuppressed()` mechanism: the Engine
skips a suppressed strategy in `Engine::Init()`. Per-dungeon instance
strategies keep their own *named* CC (a specific boss script may still want
Shackle), and open-world/raid/BG play is unchanged. The same PR moved
Dragon's Breath and Blast Wave out of `MageCcStrategy` into the Fire/Frostfire
strategies as "panic buttons" — **skip that part**: both spells are TBC-era
and do not exist in Vanilla/Tortoise.

## Task

1. Port the `Strategy::IsSuppressed()` mechanism:
   - Add the virtual to `ai/playerbot/strategy/Strategy.h` (default: not
     suppressed).
   - Skip suppressed strategies in `ai/playerbot/strategy/Engine.cpp` init
     (mirror AC PR #2648's `Engine::Init()` change; read it at
     https://github.com/mod-playerbots/mod-playerbots/pull/2648/files).
2. Mark the generic CC strategies as suppressed in dungeons. The dungeon
   context needs to be discoverable from the strategy — find how TortoiseBots
   knows it is in a dungeon (the DungeonStrategy family /
   `DungeonActions.cpp`; there is likely a map/instance check) and gate on
   it. Suppression applies to **non-raid instances** only; open world,
   raids, and battlegrounds keep generic CC.
   Vanilla spell audit for the suppression list — include only spells that
   exist in Tortoise: Polymorph, Shackle Undead, Turn Undead, Scare Beast,
   Hibernate, Freezing Trap (trap launcher semantics differ from WotLK —
   check), Sap, Entangling Roots, Banish, Fear. Drop Cyclone,
   Dragon's Breath, Blast Wave (not Vanilla spells).
3. Keep per-dungeon named CC working: if an instance strategy registers its
   own CC triggers they must not be suppressed (the AC mechanism suppresses
   the *generic* strategy only).

## Constraints

- Vanilla spell IDs only; verify each suppressed spell exists in Tortoise
  data (core `sql/base/` or DBC) before adding it to the list.
- The mechanism must be config-visible if the project wants to re-enable:
  follow the donor (no config by default) but document the behavior in
  `ai/playerbot/aiplayerbot.conf.dist.in` as a comment near the CC settings.
- No gameplay-competence claims in comments — house style is
  "implementation-verified, gameplay-untested".

## Deliverable

1. Working changes in the TortoiseBots checkout.
2. Patch `docker/penqle/patches/00N-dungeon-cc-suppression.patch` (image
   repo), `git apply --check` clean against pin `76a0a13d...`.
3. Ledger row `M-BG-LFG` (or a new row) updated to record the mechanism.
4. No env/compose changes needed (no new config key) unless you add one —
   then wire `render-config.sh` + `.env.example.penqle` + compose + README.

## Verify

- `git apply --check` on the patch.
- Host contract script passes: `bash tools/verify_penqle_host_contract.sh
  --core /Users/pho/Turtle/New/tortoise-wow`.
- `tools/verify_action_trigger_wiring.py` shows no new live-missing entries.
- Reasoning checks: (a) a mage bot in a Stockades pull does not Polymorph
  trash; (b) the same bot still Polymorphs in open-world groups; (c) a
  dungeon-specific strategy's CC still fires.
