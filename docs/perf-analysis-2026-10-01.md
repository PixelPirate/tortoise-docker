# Performance analysis and improvement plan (measured 2026-10-01)

Live-server analysis of the "unplayable lag" report at a 1000-bot pool on the
current image (core `d94947b0`, module `153b85c`, `AI_BOT_AI_TICK_DIVISOR=5`,
`MapUpdate.Continents.MTCells.Threads=6`, MotionUpdate threads=4).

Method follows SPEC §3.5/§3.6: `.perf cpu` console samples through the FIFO,
`logs/perf.log` slow-pass records, the module's own BOTPERF line, and a thread
snapshot inside the container.

## 1. Me baseline now vs the last good baselines

| Metric | SPEC §3.6 (2026-09-25, pre-stagger) | SPEC §3.7 (2026-09-30, pin 959fc579) | Now (2026-10-01, pin 153b85c) |
|---|---|---|---|
| Mean tick | 515-577 ms | ~144 ms | **1,291-1,840 ms** |
| Module bot pass (BOTPERF) | ~450 ms (divisor=1) | ~65 ms avg, p90 82 ms | **avg 176-210 ms, max 1.09-4.2 s** |
| MapManager share of tick | 8-11 % | ~13 % | 5-59 % (max single map pass 25.5 s) |
| Worst world tick | 47.9 s (login ramp) | 0.23 s | **55.2 s** |
| Slow map passes (perf.log) | 3.6/min, mean 351 ms | n/a | **nearly every pass 200-680 ms, cells 100-520 ms on both continents** |

Three independent facts from the live samples:

1. The single-threaded bot pass nearly **tripled in mean cost** at the same
   pool size and divisor (65 ms -> 176-210 ms) and now produces multi-second
   spikes (`poolProcessed=2 budgetHit=1 maxUs=4221765` means one pass ran 4.2 s
   and the pool budget starved everyone after 2 bots).
2. Map cell work regressed to near the pre-threading profile: passes over
   200 ms are now routine on **both** continents, dominated by `cells`,
   `sendObjUpdates` and `relocations`.
3. Up to ~1 s per tick sits in the un-instrumented remainder of
   `World::Update` (module tick, `sTerrainMgr.Update`, AH/LFT, async query
   results). Only `UpdateSession` and `MapManager` are timed by `.perf cpu`.

Thread snapshot: world update thread ~44 % of a core, main session thread
~38 %, two more World (map) threads 19-25 %. Memory is fine (7 GiB).

## 2. Regression window

The image rebuild history (`git log -p -- Dockerfile.penqle`) shows the only
pin that moved for the current image is the module: `959fc579 -> 153b85c`.
**The core is unchanged**, so every new suspect lives in these 18 upstream
commits (`git log 959fc57..153b85c`), almost all merged 2026-09-30:

| PR | Change | Perf relevance |
|---|---|---|
| #375 | `fix(grind): refuse targets the bot cannot path to` | Adds `WorldPosition(bot).canPathTo(WorldPosition(result), bot)` on the winning grind pick in `GrindTargetValue::FindTargetForGrinding`, plus an `IsEvadeBecauseTargetNotReachable` early-drop in `InvalidTargetValue`. A main-thread Detour/mmap pathfind per pick, inside the single-threaded bot loop. **Prime suspect.** |
| #373 | `feat(pool): spread new random bots evenly over the starting zones` | `AiPlayerbot.RandomBotEvenStartZones = 1` compiled default (dist line 174). Distributes 1000 bots across ~12 zones on **both** continents instead of concentrating them; perf.log shows both map 0 and map 1 cell passes heavy again. |
| #374 | `fix(grind): beginners walk to the grind field` | Far more bot movement + far more target re-seeking per second (grind targets churn during the walk), which multiplies how often the #375 pathfind runs. |
| #370 | `fix(grind): pool bots find grind targets again` | Pool bots grind-evaluate at all (more GrindTargetValue calls than before). |
| #376 | `feat(observability): XP, activity, grinding and server panels` | Per-bot activity tracking + snapshot string building. Emitter is **off** (`AiPlayerbot.Observability` compiled default 0, not mapped), so most cost is inactive; the cheap member-read tracking still runs at snapshot cadence only. Minor. |
| #369/#371/#372 | login/chat/pool-grouping fixes | Small diffs; #371 (pool bots stop grouping) actually *helps* the stagger gate. |

Why "a few days ago it was wonderful": the previous image ran pin 959fc579,
which had none of #369-#376. SPEC §3.7 verified that image as not-worse. The
regression is real and post-dates that verification.

## 3. Ranked hypotheses (each falsifiable)

1. **H1 - grind-pick pathfind on the main thread (#375, amplified by #370/#374).**
   Prediction: reverting/gating the `canPathTo` hunk drops BOTPERF maxUs from
   seconds to tens of ms and the avg back toward ~65 ms. Worst-case Detour
   full-graph failure (no path exists) is exactly the multi-second spike shape
   observed.
2. **H2 - even start-zone spread (#373) rebalanced the pool across both
   continents**, re-inflating active-cell counts, relocations and
   sendObjUpdates. Prediction: `RandomBotEvenStartZones = 0` shrinks
   perf.log `cells` medians on the idle continent without touching walk
   behavior of already-created bots (they keep their home zone; only new
   creations cluster again). Note: reversal only affects newly created bots,
   so verify over hours, or pair with a pool reset.
3. **H3 - un-instrumented remainder (terrain updates for 1000 spread-out
   players, AH market, LFT, async callbacks).** Prediction: adding timers
   there attributes the missing ~0.5-1.0 s; if H1+H2 land and lag persists,
   this becomes the main target. Cannot be fixed blind.
4. **H4 - spike sources, not mean cost:** mmap tile loads during the login
   ramp (MapManager max 25.5 s, once), honor/`character_pvp_currency` write
   spam (4-45 ms statements, continuous). Prediction: pre-warming and moving
   honor maintenance off the world thread removes stalls, not the mean.

## 4. Immediate mitigations (no rebuild, minutes)

Ordered by expected gain per risk. Each is an `.env` edit + `mangosd` restart
(except where noted); re-measure per §7 after each single change.

1. **`AI_BOT_AI_TICK_DIVISOR=10`** (was 5). The stagger gate is proven; the
   module pass scales ~1/divisor for eligible bots. Expected: -40-50 % of the
   176-210 ms pass. No behavior change for anything the player interacts with.
2. **Keep `AI_AH_MARKET_ENABLED=1` and `AI_RANDOM_BOT_LFT_ENABLED=1`.** Both
   services are interval-gated with per-tick early-out (AH: one pass every
   `AhMarketInterval`=120 s, batch capped at 1, hard cap 5, no DB scan, no AH
   scan; LFT: one pass every `RandomBotLftUpdateInterval`=15 s, at most one
   group fill, and only when someone is queued). Measured steady-state cost is
   effectively zero and neither scales with the bot count, so they are not
   lag suspects. Earlier advice to disable them as a hedge was over-cautious;
   keep both features. (Their only real cost is the occasional teleport/post,
   which is bounded and intentional.)
3. **New mapping `AI_RANDOM_BOT_EVEN_START_ZONES=0`.** The key exists in the
   upstream dist (`aiplayerbot.conf.dist.in:174`), so a `set_conf` line in
   `render-config.sh` is contract-safe. Expected: cells median down over the
   next pool-creation cycles. (Add env var to `.env.example.penqle` + README
   table when doing this.)
4. **Blunt lever: `AI_MIN/MAX_RANDOM_BOTS=600-700`.** Tick cost is linear in
   pool size; the lag disappears proportionally. Not a fix, but instantly
   restores playability while Phase 1 builds.

Do not change `PoolTickBudgetUs`/`PoolBudgetWhenTickOverMs`: the gate is
already at the retuned 250 ms and starving it further makes bots dumber
without fixing the spike sources.

## 5. Phase 1 - targeted module patch (hours + one rebuild)

Land as `docker/penqle/patches/013-*.patch` per `docs/bot-patch-refresh.md`,
mirrored into the local TortoiseBots checkout, and proposed upstream:

- **013a - replace the synchronous grind-pick pathfind** with a tiered check:
  (a) trust the core's own `IsEvadeBecauseTargetNotReachable` flag (already in
  #375, zero cost), (b) do the real `canPathTo` **lazily** - only when the
  first move order to that target actually fails, blacklisting the guid via the
  existing reach-give-up path, and (c) if an eager check is kept, cache the
  verdict per (map, source-cell, dest-cell) for ~60 s and bound the path
  length. Same anti-behavior, off the hot loop.
- **013b - per-bot cost measurement + cost-adaptive backoff (implemented as
  `013-cost-adaptive-bot-scheduling.patch`):** every AI update is timed, an
  EWMA of per-bot cost is kept, and a bot over `AiPlayerbot.BotUpdateWarnUs`
  (default 20 ms) is (i) named in a rate-limited `HEAVYBOT` log line and (ii)
  staggered up to `AiPlayerbot.BotAdaptiveBackoffMax` (default 10) times less
  often, inside the already-eligible set only. A true mid-update truncation is
  not possible without a cooperative AI (the adapter cannot be preempted), so
  the pass bounds the spike by backoff + visibility instead of by aborting the
  call; the `HEAVYBOT` line is what turns "maxUs: 4.2 s" into a named bot.
- **013c - adaptive divisor, tick-driven (still open):** the controller above
  reacts to per-bot cost; the next step is a window-level controller that
  nudges the *global* divisor from the measured world tick toward the 50 ms
  target, so the knob self-tunes instead of being set by hand.

Expected combined result: mean tick back to ~150-250 ms at 1000 bots, worst
tick under ~0.5 s outside the login ramp.

## 6. Phase 2/3 - the structural ("groundbreaking") work

1. **Instrument the dark matter (days, mostly upstream PRs).**
   - Core PR: extend `PerfMonitor`/`World.cpp:2535` with children of
     `WorldTick` for module tick, `sTerrainMgr.Update`, auction/LFT updates
     and async-result processing, printed by `.perf cpu`. Trivially small,
     ends all future guessing about the non-map 60-80 % of the tick.
   - Module patch: per-category timing inside `UpdateBots` (AI update vs pool
     service vs emitter vs SQL), and a per-bot worst-offender log line
     (top-5 guids by mean update cost per window).
2. **Threaded bot AI (weeks, the actual population-curve killer).**
   Today every pool bot's `PlayerbotAIAdapter::Update` runs serialized on the
   world thread, so the tick scales 1:1 with bot count. Split the pass:
   - Eligibility = the stagger set (no owner/group/combat/nearby real player),
     i.e. bots nobody can observe this tick.
   - Worker pool (size = a new `AiPlayerbot.AiWorkerThreads`, default cores/2)
     runs the AI decision pass for eligible bots against a read snapshot
     (position/target/combat state), producing a cheap action list.
   - The world thread then **commits** actions serially (movement orders,
     spell starts) with a validity recheck (bot still in world, target still
     alive) - the same check the AI would do mid-tick anyway.
   - Unsafe/opaque actions stay on the main thread in pass 1; start by
     offloading the pure thinking (value recomputation, target selection,
     pathfind checks - which also removes H1 permanently).
   Payoff: world tick returns toward the 50 ms target and stays **flat in
   population**; 1000 bots stop costing the player anything unless they are
   on-screen. This is the design to propose upstream once 013 proves the
   budget/snapshot mechanics.
3. **Crowd culling: bot-to-bot visibility elision (core PR; the crowded-zone
   win).** The core itself documents the cost at `Map.cpp:2762` - "VERY HEAVY
   LOAD in case of a lot of players at the same place, ~2ms / object if 500
   players in the visible area around". Every bot is a full `Player` session,
   so in a crowded zone the server pays O(N^2) visibility work that no human
   client ever consumes: for each bot viewer, `Player::UpdateVisibilityOf`
   (`Objects/Player.cpp:20872`) serializes a create/out-of-range block per
   nearby object into the shared `UpdateData` (`Map.cpp:1609`,
   `Map::SendObjectUpdates` at `Map.cpp:2760`), and
   `AddBroadcastListener` (`Player.cpp:20850`) subscribes every bot to every
   nearby bot's movement broadcaster.
   Design: for a **bot viewer and a bot target** (neither a network session),
   keep the cheap `m_visibleGUIDs` bookkeeping (it preserves group visibility
   at `Group/Group.cpp:1463`, stealth detection at `Units/Unit.cpp:7091` and
   emote targeting at `Objects/Object.cpp:1931`) but skip (a) the
   `BuildCreateUpdateBlockForPlayer` block building and (b) the broadcast
   listener registration. Real players keep full visibility in both
   directions, so the crowd stays on screen; only bot-to-bot chatter
   disappears. Safe for AI: the module never reads `m_visibleGUIDs` /
   `GetVisibleUnits` (verified - no hits in `ai/playerbot` or `runtime`), and
   bot targeting uses grid searchers, not the client object list.
   **Implemented as `docker/penqle/core-patches/001-headless-bot-visibility-elision.patch`**,
   gated by `Headless.BotVisibilityElision` in `mangosd.conf` (default on,
   read once at startup; a restart is needed to flip it). The module cannot
   reach this code, so it ships as a core patch and should be proposed upstream
   to tortoise-wow/tortoise-wow; delete it here once a `CORE_COMMIT` bump
   includes it. Expected: removes most of the `sendObjUpdates` + `relocations`
   share of `perf.log` in dense zones, which is the component that grows with
   the crowd the user wants to keep.
4. **Map-side follow-ups (after measurement says they matter):** mmap tile
   pre-warm at module init for the six start zones (kills the 25.5 s ramp
   stall); revisit `MapUpdate.Continents.MTCells.Threads` 6 -> 8 only if
   perf.log `cells` medians stay >150 ms after H2 lands.

## 7. Measurement protocol (tight loop for every step)

Same three commands before and after each change, 5 minutes apart, pool full:

```bash
docker exec tortoise-penqle-mangosd-1 sh -c 'echo ".perf cpu" > /opt/turtle/run/mangosd.in'
docker logs --since 2m tortoise-penqle-mangosd-1 2>&1 | grep -E 'Tick:|BOTPERF'
docker exec tortoise-penqle-mangosd-1 sh -c 'tail -50 /opt/turtle/logs/perf.log'
```

Pass/fail targets: mean tick, BOTPERF avg/maxUs, count of perf.log passes
>200 ms per minute. A step is only "done" when its prediction moves; anything
else is reverted and the next hypothesis is tested. One variable at a time.

## 8. Rollback

Every mitigation here is config or a single patch file; the pre-regression
state is recoverable by re-pinning `BOTS_COMMIT=959fc579...` (drops features
#369-#376) or by `AI_RANDOM_BOT_AUTO_CREATE=0` + pool pruning if data must be
preserved. No schema changes are involved in any phase.

## 9. Implemented artifacts

Two changes are written, verified against the pins, and wired into the build.
Both need a `docker build` (1-6 h) to take effect; neither is live yet.

| Artifact | Scope | Gate |
|---|---|---|
| `docker/penqle/core-patches/001-headless-bot-visibility-elision.patch` | core `Player.cpp` + `mangosd.conf.dist.in` | `Headless.BotVisibilityElision` (mangosd.conf, default on) |
| `docker/penqle/patches/013-cost-adaptive-bot-scheduling.patch` | module `BotManager.{h,cpp}`, `PlayerbotAIConfig.{h,cpp}`, `aiplayerbot.conf.dist.in` | `AI_BOT_UPDATE_WARN_US`, `AI_BOT_ADAPTIVE_BACKOFF_MAX` (defaults 20000 / 10) |

Verification performed: core patch `git apply --check` clean against
`CORE_COMMIT d94947b0`; module patch `git apply --check` clean against
`BOTS_COMMIT 153b85c` with 001-012 applied (and against the local
`TortoiseBots` `enhancements` checkout, so the mirror step is one command).
Wiring: `Dockerfile.penqle` applies `core-patches/` before `patches/`;
`render-config.sh`, `docker-compose.penqle.yml`, `.env.example.penqle` and the
README settings table carry both new knobs. `AGENTS.md` documents the
`core-patches/` convention.

After the rebuild, the first thing to watch is the `HEAVYBOT` line in the
mangosd log: it names the bots that made `BOTPERF maxUs` multi-second, which
tells us whether H1 (grind-pick pathfind) is still the dominant per-bot cost
and therefore whether `013a` (lazy/cached `canPathTo`) is still needed.

## 10. Measured result (2026-10-01, rebuilt image in production)

Both patches live, pool full at 1000 bots, `AI_BOT_AI_TICK_DIVISOR=10`,
`BotUpdateWarnUs=20000`, `BotAdaptiveBackoffMax=10`,
`Headless.BotVisibilityElision=1` (verified in the container env, the rendered
`mangosd.conf`/`aiplayerbot.conf`, and as strings in the running binary):

| Metric | Pre-fix (§1, pin 153b85c, divisor 5) | Now |
|---|---|---|
| Mean tick | 1,291-1,840 ms | **94-222 ms** |
| Module pass (BOTPERF avg) | 176-210 ms | **42-61 ms** |
| BOTPERF maxUs (steady windows) | 1.09-4.2 s | **80-164 ms** |
| MapManager per tick | 66-1,081 ms | **15-25 ms** |
| World max tick | 55.2 s | 22.0 s (login-ramp residual) |

`HEAVYBOT` works as designed: 9 lines in the first 15 minutes, each a distinct
bot, worst single AI update 178 ms (guid 20989 `Thorbralsha`). That is the
per-bot pathology the spike bound was built for; if it persists it is the case
for `013a`.

Operational note discovered during the swap: the shell this project is driven
from exports nearly every `.env` key (`AI_*`, `DB_*`, `MAPUPDATE_*`, ...), and
Compose prefers the shell environment over `.env` - so `.env` edits silently
do not apply to `docker compose` runs from that shell. The stack was
recreated with the shadowed variables stripped so `.env` is authoritative.
