# AGENTS.md

Guide for AI agents working in this repository.

## What this repo is

This repo contains **no application source code**. It is a Docker packaging
project: `Dockerfile.penqle` builds a Turtle WoW private-server image by
cloning and compiling two external C++ projects at pinned commit SHAs:

- **Core**: [Penqle/tortoise-wow](https://github.com/Penqle/tortoise-wow), branch `bot-helpers`
- **Bot module**: [Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots), cloned into the core as `modules/TortoiseBots`

Everything else is Compose orchestration, shell scripts run inside the image,
build-time patches to the bot module, and documentation. `docs/SPEC.md` is the
authoritative design document — read it before making non-trivial changes.

There is no traditional test suite. Verification = a successful
`docker build -f Dockerfile.penqle` plus the bring-up checklist in
`docs/SPEC.md` §5.

## Commands

```bash
# Build the image (1–6 hours; compiles the C++ core)
docker build -f Dockerfile.penqle -t tortoise-docker:penqle-bots .

# Run the stack (always needs -f; there is no default compose file)
docker compose -f docker-compose.penqle.yml up -d
docker compose -f docker-compose.penqle.yml logs -f mangosd
docker compose -f docker-compose.penqle.yml down
```

Runtime requires a `.env` (copy from `.env.example.penqle` with strong
`DB_ROOT_PASSWORD`/`DB_PASSWORD`) and client data (`dbc/`, `maps/`, `vmaps/`,
`mmaps/`) under `DATA_PATH`. CI (`ci.yml`) builds the image on PRs with a
360-minute timeout; `publish.yml` pushes to GHCR on push to main/master.

## Source pinning and patches (the core workflow)

Both upstreams are pinned by SHA via `CORE_COMMIT` / `BOTS_COMMIT` build args
in `Dockerfile.penqle`. Local reference checkouts live on this machine (see
`docs/SPEC.md` §0): core at `/Users/pho/Turtle/New/tortoise-wow`,
module at `/Users/pho/Turtle/New/TortoiseBots`. Read those for C++ context;
do not modify them.

Bot-behavior changes are delivered as **build-time patches**, not forks:

- Patches live in `docker/penqle/patches/`, named `NNN-description.patch`,
  one feature per patch. Rules are in that folder's README.
- Each must apply cleanly with `git apply --check` against the pinned
  `BOTS_COMMIT` or the Docker build fails.
- When bumping `BOTS_COMMIT`, re-verify every patch and rebase as needed.
- Mirror the same change in the local TortoiseBots checkout for reference;
  delete a patch from here once upstream includes it in the pin.
- New agent-authored feature work comes from `docs/gap-prompts/` —
  self-contained prompts whose shared context (house rules: vanilla 1.12 IDs
  only, fail-closed, no silent no-ops, ledger row updates in
  `TortoiseBots/docs/migration/CAPABILITIES.tsv`) applies to any patch work.

## Dockerfile.penqle gotchas

- The clone `RUN` and the `CORE_COMMIT`/`BOTS_COMMIT` ARG declarations are
  deliberately adjacent — declaring pins right before the clone busts the
  layer cache only when a pin actually moves. Preserve that ordering.
- The `-march=native` sed + grep guard exists because upstream hardcodes it;
  published images must not depend on the build host's CPU. If the guard's
  grep fails the build, upstream changed its CMakeLists — fix the sed, don't
  delete the guard.
- The module's host-contract check
  (`tools/verify_penqle_host_contract.sh --core .`) runs before compilation on
  purpose: it fails in minutes instead of after an hour of building.
- Module `.dist` config templates are copied to `/opt/turtle/etc.dist/` so a
  `CONFIG_PATH` bind mount over `/opt/turtle/etc` can never hide them (the
  "etc.dist" pattern). Keep that separation.
- No Boost and no readline: the Penqle core needs ACE, MySQL client, OpenSSL,
  ZLIB (plus optional curl). Runtime shared libs must match the builder's
  link set. Exact runtime lib names were best-guesses (e.g. `libace-7.0.6`) —
  verify with `ldd` on first successful build (SPEC §6.1).

## Compose / env contract

- All Compose files and env files carry a `.penqle` suffix
  (`docker-compose.penqle.yml`, `.env.example.penqle`) to stay side-by-side
  with the older Shyalya-based stack this project supersedes. Every compose
  command needs the explicit `-f` flag.
- `db-init` is a one-shot service gated by a marker file on the
  `init-marker` volume; it skips itself when re-run. Core `database_updates/`
  are intentionally **not** applied there — the core AutoUpdater applies them
  on first `mangosd` start and records proper SHA1 migration hashes. Module
  SQL, however, **is** applied by db-init because the runtime AutoUpdater
  can't see the build-time module path (`docker/penqle/init-db.sh`).
- `docker/character-inventory-copy.sql` ships with the image (not from the
  core) because `ObjectMgr::BackupCharacterInventory()` needs a structurally
  identical snapshot table. Keep it.
- `GAME_BIND_IP` (host-side port publish, default `127.0.0.1`) and
  `REALM_ADDRESS` (what the game client dials, written into the `realmlist`
  DB row) are orthogonal: LAN play needs both changed. Port 3724 = realmd,
  8090 = world.

## Config rendering (`docker/penqle/render-config.sh`)

- Configs are written to `CONFIG_PATH` on first start, then re-rendered on
  **every** start. Any setting with a mapped env var (the `AI_*` family, DB
  settings, ports) is overwritten from `.env` each start; all other user
  edits to the rendered `.conf` files are preserved.
- `set_conf` **appends** keys that don't exist in the template. Never add a
  `set_conf` line for a key that doesn't exist in the upstream `.dist` —
  unknown keys can confuse the module's config parser. Verify key names
  against the core/module `.dist` templates first.
- Key-name quirk: mangosd uses dotted keys (`LoginDatabase.Info`) while
  realmd uses `LoginDatabaseInfo` (no dots). Both are correct; don't
  "normalize" them.
- Bot env vars are 1:1 mapped to `AiPlayerbot.*` keys; all bot background
  services ship default-**off** upstream and `.env` opts in. Keep that
  direction.

## Runtime architecture

One image, four services: `db` (MariaDB 11.8, digest-pinned) → one-shot
`db-init` → `realmd` → `mangosd` (depends_on chains via health check and
`service_completed_successfully`). The entrypoint takes a role argument
(`db-init|realmd|mangosd`).

- `mangosd` runs as the `turtle` user (uid/gid 1000) via `gosu` under `tini`.
- Server console commands go through a FIFO at
  `/opt/turtle/run/mangosd.in` (the core reads stdin via `fgets`). The FIFO
  is created and opened **as the turtle user** inside a `gosu` shell because
  creating it as root in a sticky-dir then chowning fails when
  `fs.protected_fifos=1`. Don't "simplify" this back to root.
- `stop_grace_period: 2m` on mangosd gives the world server time to save.

## Documentation conventions

- `README.md` is user-facing (setup, settings table, troubleshooting). When
  adding an env var or changing runtime behavior, update the settings table
  there — it is the single source users rely on.
- `docs/SPEC.md` records verified facts and decisions with dates. Update it
  when a §6 open question resolves or a §3 fact changes.
- Commit messages in this repo are plain descriptive sentences
  (e.g. "Add bot teleport to player on invite.").
