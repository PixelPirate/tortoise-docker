# Tortoise WoW (Penqle + TortoiseBots) — Docker

Run a private [Turtle WoW](https://turtle-wow.org/) server with Docker, built
from the canonical [Penqle/tortoise-wow](https://github.com/Penqle/tortoise-wow)
core (`bot-helpers` branch) with the
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
| `AI_RANDOM_BOT_AUTOLOGIN` | `0` | Log bots in automatically after restarts |
| `AI_ENABLE_RANDOM_TELEPORTS` | `0` | Bots roam/teleport the world on their own |
| `AI_RANDOM_BOT_LFT_ENABLED` | `0` | Bots fill empty LFG/dungeon queues |
| `AI_AH_MARKET_ENABLED` | `0` | Bots run a native auction-house market |
| `AI_SUMMON_WHEN_GROUP` | `1` | Bot teleports to you when it accepts a group invite |
| `AI_DISABLE_RANDOM_LEVELS` | `0` | `1` = all bots start at `AI_RANDOM_BOT_STARTING_LEVEL` |
| `AI_RANDOM_BOT_STARTING_LEVEL` | `1` | Starting level when `AI_DISABLE_RANDOM_LEVELS=1` |
| `AI_RANDOM_BOT_MAX_LEVEL` | `60` | Upper level bound for random-bot gear/tuning |

All bot services ship **off** upstream; the `.env` values opt them in.
Raise bot counts cautiously — TortoiseBots is young and unsoaked at scale.

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

A bot's level comes from its character — TortoiseBots does not roll a random
level on creation, so you control the range in one of two ways:

1. **Set the level when creating the character** (per-bot control). With a GM
   account, after creating the RNDBOT character: `.character level <name> <n>`
   — or in-game via the TortoiseBotsManager addon.
2. **Fixed starting level for everyone** (server-wide). Set
   `AI_DISABLE_RANDOM_LEVELS=1`; every bot is raised to
   `AI_RANDOM_BOT_STARTING_LEVEL` on first login and levels up through normal
   gameplay while the realm runs. Keep the starting level at 5+ (bots below
   level 5 are gated out of some travel behaviors).

Related knobs:

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

- Server core: [Penqle/tortoise-wow](https://github.com/Penqle/tortoise-wow) (AGPL-3.0)
- Bot module: [Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots)
- Prior art: [Nescabir/tortoise-docker](https://github.com/Nescabir/tortoise-docker),
  [Shyalya/tortoise-wow](https://github.com/Shyalya/tortoise-wow)
