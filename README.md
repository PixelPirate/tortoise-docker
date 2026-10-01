# Tortoise WoW (canonical core + TortoiseBots) — Docker

Run a private [Turtle WoW](https://turtle-wow.org/) server with Docker, built
from the canonical [tortoise-wow/tortoise-wow](https://github.com/tortoise-wow/tortoise-wow)
core (`main` branch, formerly `Penqle/tortoise-wow`) with the
[Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots) playerbot
module compiled in.

This stack is a drop-in replacement for the older
[Nescabir/tortoise-docker](https://github.com/Nescabir/tortoise-docker)
(Shyalya-based) setup: same services, same `.env` workflow, same client data.
Design notes and background: [docs/SPEC.md](docs/SPEC.md).

## What you need

- Docker Desktop (or Docker Engine with Compose v2)
- A Turtle WoW **1.18.1** client (**build 7272**)
- Client data folders: `dbc`, `maps`, `vmaps`, `mmaps`
- Several GB of free disk space

The images do not include client data. You extract that data from your game
client (see the old project's README or the TortoiseBots docs for how).

## Quick start

### 1. Build the image (or pull a published one)

```bash
docker build -f Dockerfile.penqle -t tortoise-docker:penqle-bots .
```

On ARM hosts (e.g. Apple Silicon) add `--build-arg CPU_TARGET=armv8-a`; the
default `x86-64-v2` is not a valid GCC `-march` value there and the build
fails during CMake's compiler check.

The build compiles the C++ server (expect 1–6 hours depending on your CPU).
If a prebuilt image is published, you can skip this and set
`TURTLE_IMAGE=ghcr.io/<owner>/tortoise-docker:penqle-bots` in `.env`.

### 2. Create your settings file

```bash
cp .env.example.penqle .env
```

Edit `.env`:

1. Set strong values for `DB_ROOT_PASSWORD` and `DB_PASSWORD`.
2. Set `REALM_ADDRESS` to an address your game client can reach.
3. Set `DATA_PATH` if your client data is not in `./data`.

Use `127.0.0.1` for `REALM_ADDRESS` only when the client runs on the same
machine. For another PC on your LAN, use your host LAN IP **and** set
`GAME_BIND_IP=0.0.0.0` in `.env` — by default the game ports are only
published on `127.0.0.1`, so other machines cannot reach them even if
`REALM_ADDRESS` points at your LAN IP.

### 3. Add client data

Put the extracted folders here (or under your `DATA_PATH`):

```text
data/
  dbc/
  maps/
  vmaps/
  mmaps/
```

### 4. Start with Compose

```bash
docker compose -f docker-compose.penqle.yml up -d
```

The first start imports the world database (several minutes), then applies
core schema updates and bot migrations automatically on the first `mangosd`
start. Watch the world server:

```bash
docker compose -f docker-compose.penqle.yml logs -f mangosd
```

Wait until the log shows the world server is ready before creating accounts.

### 5. Create a game account and bots

Create your player account:

```bash
docker compose -f docker-compose.penqle.yml exec -u turtle mangosd bash -c \
  'echo "account create myuser mypass" > /opt/turtle/run/mangosd.in'
```

TortoiseBots does **not** auto-create random bot characters. Bots need
existing accounts/characters with the `RNDBOT` prefix (configurable via
`AiPlayerbot.RandomBotAccountPrefix`). Create them the same way, or with the
module's `.bot` commands and the companion in-game addon
([TortoiseBotsManager](https://github.com/Sagiroth/TortoiseBotsManager)) once
logged in. See the [TortoiseBots README](https://github.com/Sagiroth/TortoiseBots)
for the exact recipe.

### 6. Connect with the client

Edit `realmlist.wtf` in your Turtle WoW client:

```text
set realmlist 127.0.0.1
```

Use the same host as `REALM_ADDRESS` in `.env`. Then log in with the account
you created.

## Useful settings

| Setting | Default | Meaning |
|---|---|---|
| `REALM_ADDRESS` | `127.0.0.1` | Host the client uses to reach the world server |
| `REALM_NAME` | `TurtleWoW` | Name of the realm in the client list |
| `DATA_PATH` | `./data` | Folder with `dbc`, `maps`, `vmaps`, `mmaps` |
| `TURTLE_IMAGE` | local build | Full image reference override |
| `AI_PLAYERBOT_ENABLED` | `1` | Master switch for the bot module |
| `AI_MIN_RANDOM_BOTS` / `AI_MAX_RANDOM_BOTS` | `10` / `10` | Random bots kept online |
| `AI_RANDOM_BOT_AUTOLOGIN` | `0` | Log bots in automatically after restarts; also controls `RandomBotLoginAtStartup` (the pool start-up gate) |
| `AI_RANDOM_BOT_AUTO_CREATE` | `0` | Auto-create RNDBOT accounts/characters toward the Min/Max target, throttled to ~1 character per update interval |
| `AI_ENABLE_RANDOM_TELEPORTS` | `0` | Bots roam/teleport the world on their own |
| `AI_RANDOM_BOT_LFT_ENABLED` | `0` | Bots fill empty LFG/dungeon queues |
| `AI_AH_MARKET_ENABLED` | `0` | Bots run a native auction-house market |
| `AI_DISABLE_ACTIVITY_PRIORITIES` | `1` | `1` (upstream) = every bot runs a full AI tick every world tick; `0` = bots away from players share a rotating ~10% activity budget. Measured slower here — prefer `AI_BOT_AI_TICK_DIVISOR` |
| `AI_BOT_AI_TICK_DIVISOR` | `1` | Bot AI ticks per world tick (1-60, via the `012-bot-ai-tick-divisor` patch). `1` = every eligible bot every tick; `5`-`10` staggers bots no real player owns/groups/fights beside/can see, which is what makes a large pool affordable — see "World tick budget" |
| `AI_POOL_TICK_BUDGET_US` | `10000` | Upstream's per-tick work budget for the random-pool AI pass. `0` disables it (the pool always gets the full pass). With `AI_BOT_AI_TICK_DIVISOR` set the full staggered pass is already cheap, so `0` costs no tick time and keeps every bot moving — see "World tick budget" |
| `AI_POOL_BUDGET_WHEN_TICK_OVER_MS` | `250` | The pool budget only engages once the previous world tick ran longer than this (upstream ships `150`). Raised here so a healthy staggered tick always gets the full pass; lower it to cap a long tick harder |
| `AI_SUMMON_WHEN_GROUP` | `1` | Bot teleports to you when it accepts a group invite |
| `AI_FORCE_REBUFF_ON_READY_CHECK` | `0` | On a ready check, bots top up missing/expiring buffs before reporting ready (out-of-reagent bots report not-ready) |
| `AI_RANDOM_BOT_LOGIN_WITH_PLAYER` | `1` | Random bots only online while humans are (login on first human, logout when last leaves) |
| `AI_DISABLE_RANDOM_LEVELS` | `0` | `1` = all bots start at `AI_RANDOM_BOT_STARTING_LEVEL` |
| `AI_RANDOM_BOT_STARTING_LEVEL` | `1` | Starting level when `AI_DISABLE_RANDOM_LEVELS=1` |
| `AI_RANDOM_BOT_MAX_LEVEL` | `60` | Upper level bound for random-bot gear/tuning |
| `AI_RANDOM_BOT_START_LEVEL_MIN` / `AI_RANDOM_BOT_START_LEVEL_MAX` | `1` / `60` | Fresh pool bots are seeded with a random level in this range once, on their first login, then level normally. Upstream default `1`/`60` spreads fresh bots over every level; `1`/`1` restores the historic level-1 start. Existing characters are never re-leveled |
| `AI_LEVEL_LADDER` | `1` | `1` = pick the next bot to log in by level band so every band keeps a share of the online target; `0` = round-robin over the whole pool |
| `AI_LEVEL_LADDER_MAX_LEVEL_SHARE` | `10` | Percent of the online target held for level 60 (a hard cap; the rest stay offline) |
| `AI_XPRATE` | `3` | Bot XP multiplier (server XP rate * this) |
| `AI_FAILED_ACTION_RETRY_BASE` / `AI_FAILED_ACTION_RETRY_MAX` | `250` / `2000` | Failure backoff (ms) for bot background actions: a repeatedly failing action is skipped for base ms, doubling up to max, instead of being retried every tick; `0` disables |
| `DUNGEON_CLEAR_ENABLED` | `0` | Master switch for the vendored dungeon-clear module (autonomous 5-man dungeon clearing). `1` lets the party tank drive a run: `.dc on` in party chat (or the `dc on` keyword), `.dc status|bosses|skip|pull|off` to control it; requires navmesh data of good quality (see "Dungeon clearing" below) |
| `MAPUPDATE_MTCELLS_THREADS` | `6` | Workers for the continent cell/object update pass, plus one (so `6` = 5 workers, one per-map pool). Upstream ships `1`, which means no workers at all. Raise with the bot population — see "World tick budget" |
| `MAPUPDATE_MOTIONUPDATE_THREADS` | `4` | Workers for continent unit-motion updates (a plain worker count). Upstream ships `1`, which leaves the moving-unit pass single-threaded; raise with the bot population |

All bot services ship **off** upstream; the `.env` values opt them in.
Raise bot counts cautiously — TortoiseBots is young and unsoaked at scale.
The world server targets a 50 ms tick; a large bot population spends it
mostly in continent cell updates, so budget for `MAPUPDATE_MTCELLS_THREADS`
(see "World tick budget").

## Dungeon clearing

`DUNGEON_CLEAR_ENABLED=1` enables the vendored dungeon-clear module
(autonomous 5-man dungeon runs). The party tank drives the run:

- `.dc on|off|pause|skip|status|bosses|pull|config|spectate` in party chat
  (or the bare keywords `dc on` / `dungeon clear on` from the master).
- On dungeon entry the tank asks `Ready to go?`; the master's `go` in party
  chat (or the master simply starting a fight) starts the run.

Notes and caveats:

- Requires navmesh (mmaps) data of **good quality** — routes are built on the
  core's mmaps, so regenerate them from your client data if you see
  off-mesh/recovery-hop log spam.
- Content beyond vanilla 1.12 (TBC/Turtle-custom event tables the Penqle core
  has no map for) degrades to skipped steps; it never fakes progress.
- The module compiles clean and is wiring-verified, but is **gameplay-untested**
  — expect rough edges and report logs from the `playerbots.dungeonclear`
  channel.

## Grouping with bots

When you invite a bot to your party and it accepts, it is **teleported to
you** (enabled by default via `AI_SUMMON_WHEN_GROUP=1` — the same behavior
AzerothCore's bots have, ported to TortoiseBots in this image). The teleport
only happens when the bot is beyond sight range or on another map; a failed
teleport (e.g. no safe spot) falls back to the bot travelling normally.

To restrict group-summoning to GMs only, set `AI_SUMMON_WHEN_GROUP=0`; the
upstream config key is `AiPlayerbot.SummonWhenGroup` in
`config/modules/aiplayerbot.conf`.

## Bot levels

A bot's level comes from its character; there is no random roll on creation,
but there is a one-time seed for fresh pool bots. The level range is
controlled in one of three ways:

1. **Set the level when creating the character** (per-bot control). With a GM
   account, after creating the RNDBOT character: `.character level <name> <n>`
   — or in-game via the TortoiseBotsManager addon.
2. **Random starting level for fresh bots** (server-wide, upstream default).
   `AI_RANDOM_BOT_START_LEVEL_MIN` / `AI_RANDOM_BOT_START_LEVEL_MAX` (default
   `1`/`60`) seed a fresh pool bot with a random level on its first login
   (played time 0); it levels normally from there. `1`/`1` keeps the historic
   level-1 start. Existing characters are never re-leveled, so changing this
   only affects bots that have not logged in yet.
3. **Fixed starting level for everyone**. Set `AI_DISABLE_RANDOM_LEVELS=1`;
   every bot is raised to `AI_RANDOM_BOT_STARTING_LEVEL` on first login and
   levels up through normal gameplay while the realm runs. Keep the starting
   level at 5+ (bots below level 5 are gated out of some travel behaviors).

`AI_LEVEL_LADDER` (default `1`) decides *which* bots log in: levels are cut
into bands and every band keeps a share of the online target (highest level
first inside a band), so no band sits empty. Level 60 is capped at
`AI_LEVEL_LADDER_MAX_LEVEL_SHARE` percent of the online target. `0` restores
round-robin over the whole pool.

Related knobs:

- `AI_XPRATE` (default `3`) — bot XP multiplier (server XP rate * this).
- `AI_RANDOM_BOT_MAX_LEVEL` (default `60`) — caps the level random bots are
  geared/tuned for. It does **not** de-level existing characters.
- `AiPlayerbot.SyncLevelWithPlayers = 1` (edit
  `config/modules/aiplayerbot.conf` directly; not env-mapped) — instead of a
  fixed start, bots sync their level to online players (±
  `AiPlayerbot.SyncLevelMaxAbove`). Good for making the world feel alive
  around your own level.

## Editing server configs

`mangosd.conf`, `realmd.conf`, `modules/aiplayerbot.conf`, and
`modules/tortoise_bots.conf` are written to `./config` (or `CONFIG_PATH`)
on the host the first time the stack starts.

Edit any setting there directly. Settings that also have an `.env` variable
(table above) get overwritten from that variable on every start; everything
else you edit is left as-is. After editing, restart the affected service:

```bash
docker compose -f docker-compose.penqle.yml up -d mangosd realmd
```

## World tick budget

The world server aims for a 50 ms tick. `logs/perf.log` (container path
`/opt/turtle/logs/perf.log`, threshold keys `PerformanceLog.*` in
`mangosd.conf`) records every map update that runs long, with the split:

```
Update single map 0 inst 0: 11623ms [sess 2ms|players 25ms|cells 11189ms|sendObjUpdates 172ms|relocations 108ms|players2 127ms|wait 0 0ms]
```

Two console commands report live numbers (they work in the mangosd console,
and through the FIFO used by `docker exec ... echo "perf cpu" > /opt/turtle/run/mangosd.in`):

- `.perf cpu` — current tick, session/map split, per-map update times.
- `.perf resources` — loaded objects and players.

With a large random-bot population the dominant term is `cells` (the
marked-cell object update pass, plus the wait for continent unit-motion
updates); bot AI shows up as `players` and is comparatively small. Budget for
`MAPUPDATE_MTCELLS_THREADS` accordingly — each continent gets
`value - 1` workers, so `6` is 5 workers per continent. Cells closer than
`MapUpdate.Continents.MTCells.SafeDistance` always stay on one worker, so very
dense bot clusters parallelize less.

Measured before/after numbers and the remaining overhead are in
`docs/SPEC.md` §3.5.

The world-tick balance above is the *map* side. Bot AI is the other side: every
bot gets a full AI tick every world tick, so at 1000 bots the tick settled at
~0.5 s with the map side only ~10 % of it. `AI_BOT_AI_TICK_DIVISOR` (patch
`012-bot-ai-tick-divisor`) staggers the bot AI loop for bots no real player is
involved with; `1` is the historical behavior.

The same patch batches the real-player scan the stagger gate runs (one
session-map walk per pass instead of one per bot), and the image raises
upstream's pool-budget gate (`AI_POOL_BUDGET_WHEN_TICK_OVER_MS`) to `250` so a
healthy staggered tick gets the full pool pass instead of the budget cutting it
to a few percent of the bots.

## Common commands

View logs:

```bash
docker compose -f docker-compose.penqle.yml logs -f realmd
docker compose -f docker-compose.penqle.yml logs -f mangosd
```

Stop the stack:

```bash
docker compose -f docker-compose.penqle.yml down
```

Start again (keeps your database):

```bash
docker compose -f docker-compose.penqle.yml up -d
```

Reset the database (deletes characters and accounts):

```bash
docker compose -f docker-compose.penqle.yml down
docker volume ls
docker volume rm tortoise-docker_db-data tortoise-docker_init-marker
docker compose -f docker-compose.penqle.yml up -d
```

Volume names can include your Compose project name. Use `docker volume ls`
to confirm the names.

## Server console commands

The world server reads console commands from a FIFO inside the container:

```bash
echo "account create user pass" > /opt/turtle/run/mangosd.in   # from inside the container
```

Bot-specific commands (`.bot add`, `.bot summon`, …) work in-game and are
documented by TortoiseBots. `AiPlayerbot.NonGmFreeSummon` in
`modules/aiplayerbot.conf` controls whether non-GM players may summon bots.

## Troubleshooting

| Problem | What to do |
|---|---|
| Empty world / no NPCs | First database import failed; check `docker compose -f docker-compose.penqle.yml logs db-init` |
| Realm list is empty or offline | Check `docker compose -f docker-compose.penqle.yml ps`; world port is `8090` |
| LAN client can't reach the realm | Set `GAME_BIND_IP=0.0.0.0` in `.env`, then `docker compose -f docker-compose.penqle.yml up -d` |
| No bots online | Create `RNDBOT` accounts/characters first (§5 above); check `AI_PLAYERBOT_ENABLED=1` |
| Bot SQL errors on startup | Check `logs mangosd` for AutoUpdater output; module SQL is applied by `db-init`, core updates by AutoUpdater |
| Client crash: interface corrupt | Use an unmodified Turtle WoW 1.18.1 client; do not strip Turtle addons |

## Known limitations (upstream, as of 2026-09)

TortoiseBots is a young project with **no runtime gameplay verification**
yet (see its `docs/migration/KNOWN_LIMITATIONS.md`): class strategies are
implementation-verified but not play-tested, raid boss tactics are mostly
empty, and background services are default-off for a reason. Expect rough
edges; report gameplay issues to
[Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots/issues).

## Credits

- Server core: [tortoise-wow/tortoise-wow](https://github.com/tortoise-wow/tortoise-wow) (AGPL-3.0, formerly `Penqle/tortoise-wow`)
- Bot module: [Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots)
- Prior art: [Nescabir/tortoise-docker](https://github.com/Nescabir/tortoise-docker),
  [Shyalya/tortoise-wow](https://github.com/Shyalya/tortoise-wow)
