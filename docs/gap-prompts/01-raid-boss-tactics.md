# Agent prompt: Port vanilla-applicable raid/dungeon boss tactics

You are working in the TortoiseBots module checkout at
`/Users/pho/Turtle/New/TortoiseBots` (branch `main`, pinned upstream commit
`76a0a13d`). The image repo that consumes your work is
`/Users/pho/Turtle/New/tortoise-docker` — read `docs/SPEC.md` first for
conventions (patch format, vanilla constraints, pin handling).

## Problem

TortoiseBots' own capability audit (`docs/migration/CAPABILITIES.tsv`, rows
`F24-RAID`, `S-DUNGEON-FAMILY`, `M-BG-LFG`; and
`docs/migration/KNOWN_LIMITATIONS.md`) records that boss-fight competence is
shallow: **8 of 13+ bosses per raid have zero tactics**, the Onyxia fight
body is empty, void-zone creators are missing, MC douse is a GO/item mismatch,
BWL suppression is rogue-only partial. The AzerothCore donor
([mod-playerbots](https://github.com/mod-playerbots/mod-playerbots)) has deep,
actively-improved per-boss strategies: recently Heigan safety-dance on a fight
clock (PR #2671), Thaddius feign-dead phase fix (#2669), Golemagg /
Majordomo / Ragnaros lava-escape / Shazzrah MC rework (#2573), BWL
fire-resist coverage for Broodlord/Firemaw/Flamegor (#2631).

## Task

Port per-boss tactics from the AC donor's `src/Ai/Raid/` (MC, BWL, Onyxia,
Naxxramas directories) into TortoiseBots' dungeon-strategy family
(`ai/playerbot/strategy/generic/DungeonStrategy*`, the MC/BWL/Onyxia/Naxx
files under `ai/playerbot/strategy/generic/`).

Order of work (highest value first):

1. Onyxia: write the fight body (the file exists but is empty). AC donor:
   `src/Ai/Raid/Ony/`.
2. MC: port the #2573 improvements (Golemagg Core-Rager exclusion, Majordomo
   add-focused target selection, Ragnaros lava escape, Shazzrah spread gate).
3. BWL: fire-resistance triggers for Broodlord/Firemaw/Flamegor (#2631).
4. Naxx: Heigan dance (#2671) and Thaddius feign-dead (#2669) — port the
   *logic* with Tortoise spell/aura/GO IDs.
5. Add the missing void-zone creators (see ledger row F24).

## Hard constraints

- **IDs are NOT portable.** AC is WotLK 3.3.5; Tortoise is Vanilla 1.12
  (Turtle 1.18.1). Every creature/GO/spell/aura ID must be verified against
  Tortoise data (`tortoise-wow` core checkout at
  `/Users/pho/Turtle/New/tortoise-wow`, its `sql/base/` dumps, or DBC).
  The capability ledger's `denylist` note (KARAZHAN/DEATHKNIGHT/GLYPH/VEHICLE/
  ARENA in `TortoiseBots.cmake:179`) stays.
- Port *behavior*, not files: TortoiseBots' strategy engine is the ike3
  lineage (merged strategy files), not AC's one-file-per-action layout.
  Express boss logic as triggers/actions wired in the existing
  DungeonStrategy family.
- Naxx exists in both eras but with different IDs and tuning; the AC Heigan
  fight-clock *concept* ports, the constants must be re-derived from
  Tortoise's encounter data.
- Do not claim gameplay competence in comments/docs — mark ported tactics as
  "implementation-verified, gameplay-untested" (house style, see
  `KNOWN_LIMITATIONS.md`).

## Deliverable

1. Changes made in the TortoiseBots checkout (compile-clean if you can run a
   build; at minimum self-consistent).
2. A patch file `docker/penqle/patches/00N-raid-boss-tactics.patch` in the
   image repo (`git diff` output), verified with `git apply --check` against
   the pinned `BOTS_COMMIT` `76a0a13d...` (bump the pin in
   `Dockerfile.penqle` + `.github/workflows/publish.yml` only if the patch
   needs newer upstream code, and note that in the patch README).
3. A summary row appended to the capability ledger style (what was ported,
   what remains zero-tactics).
4. No README/env changes unless you add a config key — if you do, also wire
   `docker/penqle/render-config.sh`, `.env.example.penqle`,
   `docker-compose.penqle.yml`, and the image README.

## Verify

- `git apply --check` passes on the patch.
- `bash tools/verify_penqle_host_contract.sh --core /Users/pho/Turtle/New/tortoise-wow`
  still passes.
- `python3 tools/verify_action_trigger_wiring.py` (or equivalent) reports no
  new live-missing triggers/actions.
- No WotLK-only spell IDs referenced anywhere.
