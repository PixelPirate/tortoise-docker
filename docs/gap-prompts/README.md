# Gap prompts — agent-ready implementation tasks

One markdown document per known bot-behavior gap vs the AzerothCore donor
(mod-playerbots). Each file is a **self-contained agent prompt**: an agent
with fresh context can pick one up and implement it without further
briefing.

Shared context every prompt assumes — do not repeat it in chat:

- Module checkout: `/Users/pho/Turtle/New/TortoiseBots` (pin `76a0a13d`)
- Image repo (consumes the work): this repo; conventions in `../SPEC.md`
- Core reference: `/Users/pho/Turtle/New/tortoise-wow` (`1181dev`, `010cdb6d`)
- Deliverable format: numbered patches in `docker/penqle/patches/`
  (rules in that folder's README), `git apply --check` clean against the pin
- House rules: Vanilla 1.12 IDs only, fail-closed, no silent no-ops,
  no gameplay-competence claims, ledger row updates required
  (`TortoiseBots/docs/migration/CAPABILITIES.tsv`)

| # | File | Gap | Donor reference | Ledger row |
|---|---|---|---|---|
| 1 | `01-raid-boss-tactics.md` | Per-boss raid/dungeon tactics thin or empty (Onyxia empty, 8/13+ bosses zero tactics) | mod-playerbots `src/Ai/Raid/`, PRs #2573 #2631 #2669 #2671 | F24-RAID, S-DUNGEON-FAMILY |
| 2 | `02-avoid-creature.md` | Avoid-creature system absent; AvoidMobsStrategy inert | Shyalya `AvoidCreatureList*` | S-AVOID-CREATURE, T-AVOID-ABSENT |
| 3 | `03-engine-robustness.md` | No failure backoff, no arbitration, restart queue orphans | Shyalya engine budgets, AC operations queue | F25-SCHED |
| 4 | `04-dungeon-cc-suppression.md` | Generic CC fires in 5-man dungeons, wipes pulls | mod-playerbots PR #2648 | M-BG-LFG |
| 5 | `05-grind-rpg-corrections.md` | Crowd tally, RNG source, patrol pause, taxi-cheat exclusions missing | Shyalya branch post-`1f9497e` | F04-RPG |
| 6 | `06-qol-batch.md` | Ready-check rebuff, trade hardening, taxi graph fixes, interrupt rework, rogue Riposte/Blade Flurry | mod-playerbots PRs #2571 #2651 #2668 #2680 #2616 #2684 | various |
| 7 | `07-dungeon-clear-port.md` | Full port of Shyalya's `mod-dungeon-clear` (autonomous 5-man dungeon clearing: routing, pull modes, scripted events, run logistics, addon) — reverses the `S-DUNGEON-CLEAR-EXCLUDE` decision | Shyalya `modules/mod-dungeon-clear/` (upstream: jrad7/mod-dungeon-clear) | S-DUNGEON-CLEAR-EXCLUDE |

Recommended order: 4 (smallest, prevents group wipes) → 2 → 6 → 5 → 3 → 1 →
7 (7 is by far the largest: ~85k lines of module code + ~21k lines of test
harness; budget accordingly).
