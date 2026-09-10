# Agent prompt: Port `mod-dungeon-clear` in full (autonomous dungeon-clearing)

You are working in the TortoiseBots module checkout at
`/Users/pho/Turtle/New/TortoiseBots` (branch `main`, pinned upstream commit
`3003220`). The image repo that consumes your work is
`/Users/pho/Turtle/New/tortoise-docker` — read `docs/SPEC.md` first for
conventions (patch format, vanilla constraints, pin handling).

**Scope bar: this is a full port. No MVP, no phased delivery, no "core first,
rest later", no stubs.** Every feature the donor module has must arrive in
this port, the result must compile and behave, and the module's own test
harness must come over with it. If you cannot port a feature completely, you
have not done the task.

## Problem

TortoiseBots has **no dungeon intelligence at all for vanilla 5-man
instances**. A 5-man is just "open world with walls": no routing, no pull
discipline, no scripted-event handling, no run logistics. The generic
survival layer (flee/kite/CC/avoid-creature) is all a player gets. The
capability ledger deliberately recorded this as an exclusion:
`docs/migration/CAPABILITIES.tsv` row `S-DUNGEON-CLEAR-EXCLUDE`
("Must NOT exist in T — explicit product exclusion (plan §10)"),
`docs/migration/KNOWN_LIMITATIONS.md` line ~42, and `docs/SPEC.md` §3.3
("No dungeon-clearing autonomous guide (.dc)").

This prompt **reverses that product decision**: the donor's dungeon-clearing
system is the single best piece of vanilla-5-man bot engineering that exists
in any of our sources, it is already proven on the same core lineage, and the
user wants it. Your ledger and doc updates flip the exclusion to "ported".

## The donor

Primary donor (working copy to port **from**):

- **Shyalya tree**: <https://github.com/Shyalya/tortoise-wow>, branch
  `playerbots-integration-gh`, path `modules/mod-dungeon-clear/`
  (shallow-clone it: `git clone --depth 1 --branch playerbots-integration-gh
  https://github.com/Shyalya/tortoise-wow.git`). The local copy at `/tmp/shy2`
  from earlier sessions is ephemeral — do not rely on it.
- Upstream origin (for provenance and wiki references only):
  <https://github.com/jrad7/mod-dungeon-clear> (AGPL-3.0, AzerothCore).

**Why the Shyalya copy and not upstream**: upstream targets AzerothCore 3.3.5
+ mod-playerbots. Shyalya's copy is already ported onto Penqle's 1.12 core
(ike3/cmangos bot lineage) — exactly our core family. Its
`src/AcCompat.h` documents the surface: 23 of the 26 `PlayerbotAI` methods
the module calls exist on this lineage already; the shim force-included via
`mod-dungeon-clear.cmake` closes the core-side naming gap, and the include
order there is load-bearing (it mirrors `botpch.h`:
core headers → `cmangos-compat-shim.h`-equivalents → bot headers). Do not
"clean it up".

Scale you are porting (measured on the donor):

| Part | Size |
|---|---|
| `src/` (module code) | ~85,000 lines |
| `t/` (test harness) | ~21,000 lines |
| Config keys (`DungeonClear.*`) | ~83 keys, 207-line conf.dist |
| Route files (`src/Routes/`) | ~200 files (generated data + fallbacks) |
| Dungeon event tables (`Data/Events/`) | 30 files: 12+ classic dungeons + TBC + Turtle-custom |
| Client addon | `addon/DungeonClear-1.12/` (already a working 1.12 Lua port) |

## Feature checklist — everything on this list must land

Vendored subsystems (from `src/Ai/Dungeon/DungeonClear/`):

- **Run driver**: `Strategy/DungeonClearStrategy` (strategies
  `"dungeon clear"` non-combat + `"dungeon clear combat"`),
  `Action/DcAdvanceAction` (run-state machine), `DcRunState` /
  `DcApproachState` / `DcPullContext` value keys.
- **Pull system**: `Action/DcPullActions.cpp` + `Util/DcPullPlanner`,
  `DcPullDecision{,Io}`, `DcPullBrake`, `DcEngageGeometry`, `DcTankForm`,
  `DcFormGate` — with **all three pull modes** (Leeroy, Advanced camp-pull,
  Dynamic per-pack verdict with `PullDynamicMaxLeeroyMobs`-style tuning) and
  the live pull-mode value.
- **Routing/pathing**: `Util/{LongRangePathfinder, ChunkedPathfinder,
  StridedPathfinder, NavmeshSnap, SwimPathfinder, DcPathWorker (async),
  DungeonPathFollower, CorridorCenter, DcZoneLine, DcDoorIndex,
  DcDoorPolicy}`, `Value/DungeonClearLongPathValue`, and the generated route
  data in `src/Routes/` **plus** the `.route`/`.fallback` data files.
- **Scripted events**: `Data/Events/*.cpp` — every table: Deadmines, SFK,
  Wailing Caverns, Blackfathom Deeps (incl. the 85s door-deadline brazier
  logic), Uldaman, Sunken Temple, Razorfen Downs, Scarlet Monastery (all
  wings), Zul'Farrak, Blackrock Depths, Scholomance, Stratholme, Dire Maul,
  **and the Turtle-custom content** (e.g. `DragonmawEvents.cpp`), plus the
  TBC tables. TBC/Turtle-custom tables must all be ported; where the Penqle
  core lacks a map or spawn, the table stays and degrades per its own
  gating — never delete a table to fix a build.
- **Events/overrides registry**: `Overrides/{BossRosterRegistry,
  ObjectiveHookRegistry, BlackMorassDriver}`, `Data/DcBossEntries1121.h`
  (the curated 1.12 boss list + per-dungeon `DC_BOSS_ORDER_1121` orders and
  door bosses), `DungeonWingRegistry`.
- **Hazards**: `Value/DungeonClear{Hazards,GroundHazards,TrapHazards}Value`
  (unit / DynamicObject ground pools / GO-trap resolvers — Scholomance
  Cloud of Disease, Shattered Halls flame gauntlet class hazards).
- **Logistics**: smart rest (`DcSmartRest*`), loot policy + quality floor
  (`DcLootPolicy`, `BetterLootRollAction`), regroup (`DcRegroupDecision`),
  death recovery (`DcRezRecovery`, `DcRezDecision`, `StayDeadAction`),
  stranded recovery (`DcStrandedRecovery`), progress watchdog, wipe verdicts
  (`DcWipeContext`), post-combat rez (`DungeonClear.PostCombatRez`).
- **Party roles**: follower lifecycle (`DcFollowerLifecycle`,
  `Action/DcFollowerActions`), party-tank/heal-target values, healer
  line-of-sight repositioning, `DcPartyState`, `DcSocialQuarantine`,
  `DcFirstContact` (pull-origin recording), `DcTargeting`.
- **Control surface**: `.dc on|off|pause|skip|pull|status|bosses|go|config|
  spectate` slash commands (`DungeonClearCommand.cpp`,
  `dungeon_clear_command_script` AllCommandScript) **and** the chat keyword
  aliases (`dc on` / `dungeon clear on`), the addon protocol hook
  (`DungeonClearAddonHook.cpp`, `DcStatusPublisher`, `DcLeaderSignal`) and
  the **1.12 addon** (`addon/DungeonClear-1.12/`) with its panel, boss list,
  live settings overrides — **plus the two UX extensions of task 7
  ("Ready to go?" handshake and auto-start on master combat), which are this
  port's own additions on top of the donor.**
- **Settings**: `Settings/DcSettings*` per-run registry + live overrides
  (`.reload config` honoured), all ~83 `DungeonClear.*` keys with their
  defaults and `.Heroic` variants (heroics don't exist in vanilla; carry the
  keys, they simply never fire).
- **Diagnostics**: `DcDecisionJson`, `DcBreadcrumb`, `DcTickMemo`,
  `DcDiagSnapshot`, run recording/verdict (`TestRun/DcTestRun*` runtime
  side), spectator mode (`Util/DcSpectator`, `DcWatchHop`).
- **Misc**: `DcCombatFlag`, `DcEncounterMask`, `DcRouteFilter/Recorder`,
  `DcHazard`, blocking-door/far-targets/room-trash/bosses values,
  `LiveMapTicker`, `DcPlayerbotCompat.h`, `DungeonClearTuning.h` constants.
- **Tests and tools**: the whole `t/` harness (replay-decisions,
  replay-pull, nav fixtures, determinism checks, roster/plan/verdict tests)
  and `tools/` (meshprobe, aggro-audit, config-read checks, MSVC portability
  checks — port the checks even where MSVC itself is irrelevant here).

## Task

1. **Audit before porting.** Diff the donor's playerbots-facing surface
   (the 26 `PlayerbotAI` methods from `AcCompat.h`, the Strategy/Action/
   Trigger/Value/Multiplier base classes, `AI_VALUE*` macros, `NextAction`,
   `Event`, engine names, `sConfigMgr`-equivalent config access, command
   script hooks) against `/Users/pho/Turtle/New/TortoiseBots`' actual
   headers. TortoiseBots is the successor of the same translated tree, so
   drift is small but real (style: `getClass` → `GetClass`,
   `GetOwner`/`getParam` spellings, `TellPlayer` overloads). Write the
   mapping down first; fix at the mapping layer, not by weakening callers.
2. **Vendor the module** into the TortoiseBots checkout, preserving its
   internal layout, as `ai/dungeonclear/` (sibling of `ai/playerbot/`).
   - Register the sources in `TortoiseBots.cmake` (extend the explicit
     list/GLOBs; the core's module build links it into the same static
     module as the bot code, so playerbots subclasses link directly).
   - Carry the force-include compat prelude: adapt
     `mod-dungeon-clear.cmake`'s mechanism into `TortoiseBots.cmake`
     (target-level `COMPILE_OPTIONS`/force-include), preserving the include
     order documented in `AcCompat.h`. Rename shim files to match our tree
     (`AcCompat.h` may stay the name; document it).
   - Keep AGPL-3.0 headers intact; record the donor provenance (repo,
     branch, path, upstream origin, commit) in
     `docs/PROVENANCE.md` following that file's existing format.
   - Install `conf/mod_dungeon_clear.conf.dist` next to the module's other
     conf templates (same `CopyModuleConfig` mechanism as
     `tortoise_bots.conf.dist`).
3. **Wire the AI surface**: register the DC strategy/value/trigger/action
   contexts wherever the donor hooks them (`AiObjectContextAccess.h`
   documents the seams), keep strategy names `dungeon clear` /
   `dungeon clear combat` intact (chat keywords depend on them), and make
   sure `python3 tools/verify_action_trigger_wiring.py` recognises the new
   contexts (no new live-missing entries).
4. **Config plumbing (image repo)**:
   - Add a master enable key, default **off** (house rule: opt-in), e.g.
     `DungeonClear.Enabled` in the conf.dist plus env mapping
     `DUNGEON_CLEAR_ENABLED` — wire it through
     `docker/penqle/render-config.sh` (new `mod_dungeon_clear.conf`
     `ensure_conf`/`set_conf` block), `.env.example.penqle`,
     `docker-compose.penqle.yml`, and the image `README.md` settings table.
     Map only keys the renderer can set safely; unknown-key appends are
     forbidden (see SPEC §4.4).
   - Note in the image README: runtime requires navmesh data of sufficient
     quality — DC's routes depend on the core's map extractor settings
     (the donor rebuilt map 33's mesh with stair-merging settings; check
     what `/Users/pho/Turtle/New/tortoise-wow`'s extractors produce and
     document any regenerated-mmaps requirement for users).
5. **Reverse the exclusion everywhere it is written**:
   - `TortoiseBots/docs/migration/CAPABILITIES.tsv`: flip
     `S-DUNGEON-CLEAR-EXCLUDE` to ported state and add/flip the `T-` row
     (`T-DC-PORT` or reuse `S-DUNGEON-CLEAR-EXCLUDE`'s `T` companion row)
     with registration/activation facts.
   - `TortoiseBots/docs/migration/KNOWN_LIMITATIONS.md`: remove/reword the
     `.dc` absence bullet into an implementation-state bullet.
   - `docs/SPEC.md` §3.3 (runtime caveats) and the image `README.md`
     caveat/troubleshooting tables: replace "No dungeon-clearing
     autonomous guide" with usage documentation.
   - `docs/gap-prompts/README.md`: add row 7 (this task) to the table.
6. **Tests**: port `t/` and make its harness runnable in our build (the
   harness builds against the module + core; wire it as a build target or
   script under `tools/`, mirroring the donor's `t/run_tests.sh` flow).
   Record in the ledger which tests ran green and which need the Docker
   build environment.
7. **Requested UX extensions (new behavior on top of the donor — these are
   user-mandated features, not donor parity; implement both completely,
   config-gated, default ON per user intent, each individually disableable):**

   a. **"Ready to go?" handshake.** When a run becomes eligible (bot tank is
      the dungeon-clear leader, party is inside a dungeon, no active run,
      master toggle on), the tank announces `"Ready to go?"` in party chat
      (exact string configurable, e.g. `DungeonClear.ReadyPrompt`), once per
      dungeon entry (no spam; re-arm on map change). While the prompt window
      is live (configurable timeout, e.g. `DungeonClear.ReadyPromptTimeout`
      seconds, default ~45s), a reply of `"go"` (case-insensitive, trimmed)
      in party chat from an authorized human (same authorization model as
      the donor's `DcOnAction::IsAuthorized`) is treated **exactly as
      `dc on`** — same action, same fan-out, same refusal messages. The
      handshake rides the donor's existing party-chat keyword machinery
      (`DungeonClearChatActions.cpp:230` — it already parses master party
      chat and fans `dc on` out to all bots); the new keyword is scoped to
      the live prompt: **no live prompt → `"go"` is not a DC command**
      (fail-closed; avoids colliding with the donor's `dc go` and generic
      chat keywords). An expired/timed-out prompt is announced once
      (`"Say 'ready' to ask again"`-style) and re-armed on the next
      `"ready"` from the master (which re-sends the prompt). Log the
      handshake decision at the existing `playerbots.dungeonclear` channel.

   b. **Auto-start on master combat.** While eligible (as above) and no run
      is active, the first time the **human** master starts combat with a
      creature inside the dungeon, the run auto-starts (`dc on` semantics,
      identical fan-out and announcements). Watch the master's attack start
      via the existing `masterIncomingPacketHandlers` relay (donor already
      uses it for human-master observation; see `TestRun/DcTestAreaTriggers.h`)
      — `CMSG_ATTACKSWING` — with a fallback poll of the master's combat
      state in the DC tick for cases the packet path misses (spells, pet
      pulls). Guards, all fail-closed: bots' own combat never triggers it;
      combat the master did not initiate (being pulled onto while AFK, AoE
      from trash walking by) does NOT start a run unless the master lands an
      attack; a deliberately-disabled run (`dc off`) is **not** auto-restarted
      by combat until the party leaves and re-enters a dungeon or the master
      re-arms via `"ready"`; and a per-entry cooldown prevents
      off/on oscillation from accidental swings. The ready-prompt (a) still
      fires on entry when this is enabled — the prompt text should reflect
      that attacking works too, e.g. `"Ready to go? (say 'go' or start a
      fight)"` — but combat during the prompt window skips the handshake and
      starts the run directly.

   Both features get their own conf keys (`DungeonClear.ReadyPrompt`,
   `DungeonClear.ReadyPromptTimeout`, `DungeonClear.ReadyPromptEnable`,
   `DungeonClear.AutoStartOnMasterCombat`), full conf.dist documentation,
   and test coverage in the ported harness (handshake accept/expiry/timeout,
   auto-start accept + all guard rejections).

## Hard constraints

- **Vanilla/Turtle IDs.** The donor's data is already 1.12/Turtle
  (`DC_BOSS_ORDER_1121`, Turtle-custom bosses like Velthelaxx 62530).
  Verify every creature/GO/spell ID against the Penqle core checkout
  (`/Users/pho/Turtle/New/tortoise-wow`, `sql/base/` dumps and instance
  scripts). If a Turtle-custom entry does not exist on the Penqle core,
  keep the data row, mark it inert with a comment — fail-closed, no
  deletion.
- **No stubs, no dead registrations.** If a donor feature depends on an API
  TortoiseBots lacks, extend the compat shim or the module API — do not
  comment the feature out. Every strategy/trigger/action/value the port
  registers must resolve (wiring checker must stay clean).
- **Fail-closed posture**: an unsupported event stalls/skips per the
  module's own policy (that IS the donor behavior — keep it); never fake
  success.
- **No gameplay-competence claims**: mark the port
  "implementation-verified, gameplay-untested" (house style,
  `KNOWN_LIMITATIONS.md`).
- **Do not modify** the Shyalya upstream or the old reference image at
  `/Users/pho/Turtle/tortoise-docker`.

## Deliverable

1. Full port in the TortoiseBots checkout (vendored module + wiring + tests
   + docs), committed as work-in-progress on `main` or delivered as a
   working tree — patches are generated from it.
2. Patch(es) in the image repo: `docker/penqle/patches/004-dungeon-clear.patch`
   (a small ordered series `004…00N` split by subsystem is acceptable if a
   single diff is unwieldy — each patch must apply cleanly in sequence),
   `git apply --check` clean against pin `3003220...` with patches
   001–003 applied before it (and against the bare pin if the series is
   ordered so).
3. Config wiring: `render-config.sh` + `.env.example.penqle` +
   `docker-compose.penqle.yml` + image `README.md` (master toggle + any
   keys the renderer sets), `docker/penqle/patches/README.md` entry for the
   new patch(es).
4. Ledger/doc updates per task 5, plus `docs/gap-prompts/README.md` row.

## Verify

- `git apply --check` on the patch(es), in order, against the pin.
- `bash tools/verify_penqle_host_contract.sh --core /Users/pho/Turtle/New/tortoise-wow`
  passes.
- `python3 tools/verify_action_trigger_wiring.py`: no new live-missing
  entries (DC's own contexts resolve).
- Module test harness: as many of the donor's `t/` tests as the local
  environment permits run green; the rest are listed with their build-time
  blockers (nav fixtures need generated mapdata — document, don't skip
  silently).
- Manual reasoning checks (document in the ledger/patch README):
  a) `.dc on` in a stocked dungeon with a bot tank drives boss order per
     `DC_BOSS_ORDER_1121` (Stockade: Targorr → Dextren → Kam → Hamhock →
     Bazil Thredd);
  b) Blackfathom Deeps: braziers lit one at a time, wave killed between
     lights, party moved into the portal within the 85s window;
  c) `.dc off` / group disband / map exit leaves zero residual run state
     (the `DcStrategyGate` teardown contracts hold);
  d) ready-prompt handshake: tank announces on entry; master `"go"` inside
     the window starts the run; `"go"` with no live prompt does nothing;
     an expired prompt requires `"ready"` to re-arm;
  e) auto-start: master's first attack in the dungeon starts the run; a bot
     pull or the master merely being aggroed does not; after an explicit
     `dc off`, combat does not silently restart the run.
- Feature-count sanity: every item in the checklist above exists in the
  port (list file paths next to each checklist item in the patch README).
