# Spec: canonical core + TortoiseBots Docker Image

Status: implemented, build not yet run. Local checkouts exist; see §3.4.
Repo: this spec lives in the new repo (`tortoise-docker`).

> **Re-pin 2026-09-23.** The image now builds from the canonical core on
> `1181dev` (`tortoise-wow/tortoise-wow`, the renamed `Penqle/tortoise-wow`),
> pinned to `010cdb6d`, with the module pinned to upstream `main` `76a0a13d`
> plus the patches in `docker/penqle/patches/` (see §3.1). The `bot-helpers`
> core branch is no longer used: every seam TortoiseBots needs is merged
> upstream and the module records `1181dev` as its canonical target. §0, §1,
> §3.1, §3.4 and §4.1 below carry the current values; other sections describe
> the original 2026-09-09 bring-up and stay as written.

## 0. Local context (paths on this machine)

An agent working here has these existing checkouts/projects:

| Path | What it is |
|---|---|
| `/Users/pho/Turtle/New/tortoise-docker` | **This repo.** All deliverables in §1 are built here. |
| `/Users/pho/Turtle/tortoise-docker` | The **old image this project supersedes**: the working Shyalya-based setup ([Nescabir/tortoise-docker](https://github.com/Nescabir/tortoise-docker)). **Reference implementation AND parity target** — its `Dockerfile`, `docker-compose.yml`, and `docker/*.sh` scripts are the templates to adapt (see §4). Do not modify it. |
| `/Users/pho/Turtle/TortoiseCompiledNew` | A Windows-native build/play setup of the current Shyalya stack (compile scripts `compile-tortoise-wow.{ps1,bat}`, compiled server binaries, live config files incl. `aiplayerbot.conf`). Useful as a config example and as proof of the user's client-side setup; not part of the Docker pipeline. |
| `/Users/pho/Turtle/New/tortoise-wow` | Local clone of the canonical core (`tortoise-wow/tortoise-wow`); the image pins it at `1181dev` `010cdb6d`. |
| `/Users/pho/Turtle/New/TortoiseBots` | Local clone of the bot module; local `main` tracks upstream, the custom work lives on branch `bot-helpers`, and the image pins upstream `main` `76a0a13d` plus the patches in `docker/penqle/patches/`. |

Both upstream projects are cloned locally (see §0); the clones above are the
reference for reading code and re-running the host-contract verify script.
The Docker build itself clones from the pinned URLs/SHAs (§4.1).

**Implementation status**: all deliverables exist in this repo
(`Dockerfile.penqle`, `docker/penqle/*`, `docker-compose.penqle.yml`,
`.env.example.penqle`, `README.md`, workflows). Remaining §6 items are
docker-build-time confirmations only.

## 1. Goal

**Supersede** the old setup at `/Users/pho/Turtle/tortoise-docker` (Shyalya
branch `playerbots-integration-gh`, archived upstream 2026-09-30) with a
drop-in replacement: the **same user experience and packaging**, but built
on the new core and bot implementation. Feature parity with the old stack is
the bar — anything the old stack does, this one must do too.

A Docker image, packaged like the old one, that runs:

- **Core**: [tortoise-wow/tortoise-wow](https://github.com/tortoise-wow/tortoise-wow)
  (the renamed `Penqle/tortoise-wow`), branch **`1181dev`**, pinned to a commit
  SHA (`010cdb6d`, the branch tip whose seams the module's host-contract gate
  accepts).
- **Bot module**: [Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots),
  cloned into the core checkout as `modules/TortoiseBots`, pinned to a commit SHA.
- Same Compose stack shape as today: `db` (MariaDB) + one-shot `db-init` +
  `realmd` + `mangosd`, same volume/config handling, same client data contract
  (`dbc/`, `maps/`, `vmaps/`, `mmaps/` under `DATA_PATH`).

Deliverables in **this repo**:

1. `Dockerfile.penqle` — builder + runtime, mirroring the reference
   `Dockerfile` in `/Users/pho/Turtle/tortoise-docker`.
2. Adapted copies of the reference `docker/entrypoint.sh`,
   `docker/render-config.sh`, `docker/init-db.sh` under `docker/penqle/`
   in this repo (the Shyalya originals in the reference repo are not touched).
3. `docker-compose.penqle.yml` (or a `COMPOSE_FILE` profile) with its own
   env contract in `.env.example.penqle`.
4. CI: a build workflow (PR + publish) mirroring the reference
   `.github/workflows/*.yml`, image tag variant e.g.
   `ghcr.io/<owner>/tortoise-docker:penqle-bots`.

## 2. Why

- Shyalya's fork (the current image source in the reference repo) is
  discontinued on 2026-09-30.
- TortoiseBots is the actively maintained bot module for the canonical core:
  created 2026-08-20, daily commits, built on Shyalya's translated
  `playerbot/` tree plus forward-ported modern behavior from AzerothCore's
  `mod-playerbots` (all 9 vanilla classes, 28 spec profiles, native AH market
  read model, BG auto-queue, LFT fill).
- End user goal unchanged from the current stack: bots roaming, leveling,
  grouping; plus the summon-on-group-invite behavior known from AzerothCore
  videos (TortoiseBots forward-ported the relevant modern strategies — verify
  at runtime).

## 3. Verified facts (as of 2026-09-09)

### 3.1 Core branch compatibility

- The image pins core `1181dev` at `010cdb6d`. The module records `1181dev` as
  its canonical target in `CHANGELOG.md` (#162); its `docs/HOST_API.md` still
  names the older `main` `5fafe43b` ("Merging headless session and module API
  expansion") baseline.
- Penqle PRs **#411** and **#416** were closed unmerged on 2026-09-02, but
  their surface landed on `main` through **#438** (transport plus `World`
  Headless lifecycle, and the generic participant primitives), with **#469**
  (module script hooks), **#475** (headless sessions drain synthesized client
  packets), **#476** (hardened chat hooks) and **#493**
  (`PlayerScript::OnChatYell`) alongside. The earlier `bot-helpers` pin is no
  longer needed.
- The module's `tools/verify_penqle_host_contract.sh --core <checkout>`
  **PASSES** against `010cdb6d` and runs as a build gate in `Dockerfile.penqle`
  (checks `SessionTransport::Headless`, `HeadlessSessionMgr`,
  `WorldSession::InitHeadlessSession/IsHeadless`, `World::Start/Stop/
  GetHeadlessSessionState`, `CharacterCreation::CreateCharacter`, LFT/BG
  queue primitives, and asserts no legacy `PlayerBotMgr` coupling). No core
  patch is needed.

### 3.2 TortoiseBots build contract (from its README / EVIDENCE.md)

- Install as `modules/TortoiseBots` inside the core checkout.
- CMake: `-DMODULES=static -DMODULE_TORTOISEBOTS=static`.
  `-DMODULES=disabled` (or `-DMODULE_TORTOISEBOTS=disabled`) must produce a
  binary with zero bot symbols — useful as a build-matrix sanity check.
- A Docker build of module ON + disabled is documented as verified in the
  module's `docs/migration/EVIDENCE.md`.
- Config files installed at runtime: `tortoise_bots.conf` (module toggles,
  logging) and `aiplayerbot.conf` (AI strategies). All background services
  (random bots, LFT fill, AH market, BG queue) are **default off**.
- Module-owned SQL lives under `data/sql/` in the module (not the core's
  `sql/` tree) — db-init must pick this up; see §4.3.
- No Docker reference implementation is public:
  `Sagiroth/tortoise-docker-penqle` is 404 (private/deleted). We write the
  builder from scratch based on our existing Dockerfile.

### 3.3 Runtime caveats to document for users

- Zero runtime gameplay verification exists upstream (all acceptance scenarios
  pending); expect rough edges.
- Random-bot characters are NOT auto-created. Users pre-create accounts/
  characters with the `RNDBOT` prefix (see module README/RUNBOOK).
- Dungeon-clearing autonomous guide (`.dc`) IS present since 2026-09-10: the
  donor `mod-dungeon-clear` is vendored into TortoiseBots as
  `ai/dungeonclear/` (patches `010-dungeon-clear`), master toggle
  `DUNGEON_CLEAR_ENABLED` default off. The vendored tree compiles clean
  against the pinned core (module target builds; residual per-TU compile debt
  closed 2026-09-10); still gameplay-untested. No DK/glyphs/vehicles (not in
  vanilla anyway); raid boss tactics largely empty (non-raid dungeons are
  covered by the port).

### 3.4 Pre-flight findings (resolved from local checkouts, 2026-09-09)

Local clones exist at `/Users/pho/Turtle/New/tortoise-wow` (core,
`010cdb6d`) and `/Users/pho/Turtle/New/TortoiseBots` (module, `76a0a13d`).
Facts established by reading them:

1. **`-march=native` IS present** in Penqle's `CMakeLists.txt:457` → keep
   the sed + grep guard from the reference Dockerfile unchanged.
2. **No Boost dependency** — unlike Shyalya's build. Core find_package list:
   ACE, MySQL, OpenSSL, ZLIB (required); CURL and TBB (optional). Builder
   needs `libace-dev default-libmysqlclient-dev libssl-dev zlib1g-dev
   pkg-config cmake git` (+ curl lib if enabled); runtime needs the matching
   shared libs (`libace-7.0.6`, `libmysqlclient21`/mariadb equivalent,
   `libssl3`, `zlib1g` on Ubuntu 22.04) — confirm exact names at first build.
3. **Module discovery is automatic**: the core's module system (AC-derived
   `cmake/ConfigureModules.cmake`) globs `modules/*/src`; the
   `MODULE_TORTOISEBOTS` flag is auto-derived from the directory name.
   Cloning the module into `modules/TortoiseBots` and passing
   `-DMODULES=static` is sufficient; `-DMODULE_TORTOISEBOTS=<off/static>`
   toggles it.
4. **Config install paths**: module conf templates install into
   `${CMAKE_INSTALL_PREFIX}/etc` alongside `mangosd.conf.dist` (as
   `aiplayerbot.conf` and `tortoise_bots.conf`, via `CopyModuleConfig`).
   The etc.dist hard-copy mechanism from the reference image applies as-is.
5. **Module SQL is applied by db-init, not the runtime AutoUpdater**
   (corrected 2026-09-23 against core `010cdb6d`): TortoiseBots' migrations
   (`data/sql/world/`, `data/sql/char/`) install to
   `${prefix}/modules/TortoiseBots/data/sql/{world,character}`, but
   `AutoUpdater::ProcessUpdates` only scans `TW_SOURCE_MODULES_DIR`
   (`CMakeLists.txt:593` → `${CMAKE_SOURCE_DIR}/modules`, the build tree) or a
   CWD-relative `modules` — neither exists in the runtime image, so it logs
   "Module update path ... does not exist, skipped". `docker/penqle/init-db.sh`
   applies them instead, behind its init marker. Consequence: a module pin
   bump that adds migrations does **not** reach an existing database; apply
   the new files under
   `/opt/turtle/modules/TortoiseBots/data/sql/{world,character}` manually
   after rebuilding (or re-init the database). Note: Penqle's
   `database_updates/` has `world/` AND `character/` subfolders (Shyalya's
   had world-only).
6. **`character_inventory_copy` is still needed**: Penqle's core has
   `ObjectMgr::BackupCharacterInventory()` which TRUNCATEs/INSERTs into
   `character_inventory_copy` (`BackupCharacterInventory = 1` in
   mangosd.conf.dist). Keep the copy-SQL step from the reference init-db.
7. **Console FIFO works**: `src/mangosd/CliRunnable.cpp` reads commands via
   `fgets(stdin)` — the reference FIFO pattern carries over unchanged.

## 4. Implementation plan

### 4.1 `Dockerfile.penqle`

Model on the reference `Dockerfile` at
`/Users/pho/Turtle/tortoise-docker/Dockerfile`. Key changes:

- Build args: `CORE_REPO` (default `https://github.com/tortoise-wow/tortoise-wow.git`),
  `CORE_REF` (default `1181dev`), `CORE_COMMIT` (pin, currently `010cdb6d`),
  `BOTS_REPO` (default `https://github.com/Sagiroth/TortoiseBots.git`),
  `BOTS_COMMIT` (pin, currently `76a0a13d`), `CPU_TARGET=x86-64-v2`,
  `BUILD_JOBS`.
- Clone core at pinned SHA (cache-bust pattern from the existing Dockerfile:
  declare the SHA right before the clone `RUN`), then clone TortoiseBots into
  `modules/TortoiseBots` at its pinned SHA.
- Keep the `-march=native` → `-march=${CPU_TARGET}` sed + grep guard; check
  `/Users/pho/Turtle/New/tortoise-wow/CMakeLists.txt` (local checkout) for
  whether Penqle still contains `-march=native` and re-apply the same
  portable-target hardening if so.
- CMake: `-DMODULES=static -DMODULE_TORTOISEBOTS=static`, Release,
  `-DCMAKE_INSTALL_PREFIX=/opt/turtle`.
- Run `tools/verify_penqle_host_contract.sh --core ../tortoise-wow` (from the
  module checkout) before compiling; fail the build on contract violation.
- Builder step 1 (first bring-up): compile the disabled variant once to catch
  contract errors cheaply, or skip if build time is a concern — decide during
  implementation.
- Install: binary + `etc.dist` templates (expect `mangosd.conf.dist`,
  `realmd.conf.dist`, and module-provided `tortoise_bots.conf.dist` /
  `aiplayerbot.conf.dist.in` → check exact install paths after first build),
  plus ALL SQL the module needs (core `sql/` + `modules/TortoiseBots/data/sql`)
  under `/opt/turtle/sql`.
- Runtime stage: same package set as today minus/plus version drift for
  Ubuntu 22.04 libs (verify `libace` / boost versions against Penqle's
  requirements — Penqle is MaNGOS Zero lineage, may need different libs than
  Shyalya's build; check its README/INSTALL docs during implementation).
- Same user/permissions scheme (`turtle` uid/gid 1000, `tini`, `gosu`),
  same `EXPOSE 3724 8090`.

### 4.2 `docker/penqle/entrypoint.sh`

Start from the reference `docker/entrypoint.sh`. Expected to need minimal
change: roles `db-init|realmd|mangosd` and the mangosd console FIFO pattern
carry over. Verify mangosd's console/stdin behavior on the Penqle core
(`PlayerBotMgr`-era cores accept the same FIFO trick; confirm during first
run).

### 4.3 `docker/penqle/init-db.sh`

Start from the reference `docker/init-db.sh`. Changes:

- Import the core's `create_databases.sql` + `sql/base` + `database_updates`
  as before (verify Penqle uses the same layout — it is MaNGOS Zero lineage;
  confirm paths from the local checkout of the core).
- **Replace** the Shyalya playerbot SQL import with TortoiseBots' module-owned
  migrations from `modules/TortoiseBots/data/sql/` (check whether they are
  full-schema or incremental, and whether the module expects its own DB names).
- Re-evaluate the migration-hash recording block: the existing script's
  `update_files` loop is known-broken (variable never populated); either fix
  it in the penqle copy or drop it if TortoiseBots manages its own migrations.
- Keep the `character_inventory_copy` step only if upstream still needs it —
  verify against Penqle's code before including.

### 4.4 `docker/penqle/render-config.sh`

Start from the reference `docker/render-config.sh`. Changes:

- Render `tortoise_bots.conf` and `aiplayerbot.conf` from the module's
  `.dist` templates (same `ensure_conf`/`set_conf` pattern; templates must be
  baked into the image at a path a `CONFIG_PATH` bind mount can't shadow —
  keep the `etc.dist` mechanism).
- New env vars to map (minimum; extend after reading the module's conf dist):
  `AI_PLAYERBOT_ENABLED`, `AI_MIN_RANDOM_BOTS`, `AI_MAX_RANDOM_BOTS`,
  plus module toggles for LFT fill / AH market / BG queue (all default off
  upstream — expose them but keep them off unless the user opts in).
- Keep every Shyalya-specific key (`LFT_BOTFILL_ENABLE`, `LEECH_ENABLE`,
  `SOLO_DUNGEON_REPOP_ALIVE_ENABLE`, etc.) OUT of the penqle renderer unless
  the keys exist there too — do not write unknown keys blindly; `set_conf`
  appends unknown keys, which may confuse the module's config parser.

### 4.5 `docker-compose.penqle.yml` + `.env.example.penqle`

- Copy the reference `docker-compose.yml`; point the image anchor at
  `ghcr.io/<owner>/tortoise-docker:${TAG:-penqle-bots}` and reference the
  `docker/penqle/` scripts (they are bind-mounted or baked into the image —
  prefer baked-in, matching the current design).
- Same volumes: `db-data`, `init-marker`, `mangosd-logs`, `${DATA_PATH}`,
  `${CONFIG_PATH}`.
- Env contract: secrets + realm settings identical; bot settings per §4.4.
  Document `GAME_BIND_IP` LAN behavior identically (it is orthogonal to the
  core).

### 4.6 CI

- Extend the reference `.github/workflows/publish.yml` matrix with a
  `penqle-bots` entry instead of a separate workflow (shares GHCR login and
  metadata logic). Include a `SOURCE_RESOLVE` step for both pins
  (`CORE_COMMIT`, `BOTS_COMMIT`) via `git ls-remote`.

## 5. Verification checklist (definition of done)

1. `docker build -f Dockerfile.penqle` completes; host-contract verify passes
   inside the build.
2. `docker compose -f docker-compose.penqle.yml up -d` with a fresh `.env`
   and existing `./data` client data: db-init completes, realmd + mangosd
   start, log shows the world-server-ready line.
3. `tortoise_bots.conf` + `aiplayerbot.conf` appear in `./config`; editing a
   non-env-mapped key and restarting preserves it (the etc.dist mechanism).
4. Module migrations apply automatically on first mangosd start (AutoUpdater
   logs in `docker compose logs mangosd`); random bots appear in world only
   after RNDBOT characters are created (document this); bot toggles in
   `.env` take effect after restart.
5. An existing Shyalya deployment on the same host is unaffected
   (separate compose project / volumes).
6. Client (Turtle WoW 1.18.1 build 7272) can log in and see bots.
7. **Parity audit vs the old stack**: walk through the old repo's README
   (setup steps, settings table, troubleshooting table, common commands) and
   confirm each capability has an equivalent here — `.env` contract, config
   editing behavior, DB reset procedure, account creation via the mangosd
   console, logs workflow.

## 6. Open questions

Resolved by pre-flight (§3.4): IWorldUpdateListener (no), -march=native
(yes, keep guard), install paths (§3.4.4), runtime deps (§3.4.2), console
FIFO (works, §3.4.7), module SQL handling (AutoUpdater, §3.4.5).

Remaining:

1. **Exact runtime shared-library names** on Ubuntu 22.04 for the Penqle
   build (especially ACE version and MySQL client lib flavor) — the
   Dockerfile pins best-guess values (`libace-7.0.6`, `libmysqlclient21`);
   confirm via `ldd` on first successful build and adjust if needed.
2. **db-init strategy (decided)**: db-init imports `create_databases.sql`,
   `sql/base/`, the module SQL, and `character_inventory_copy`; core
   `database_updates/` are left to the AutoUpdater on first mangosd start,
   which records proper SHA1 migration hashes (§3.4.5). The old Shyalya
   repo's hand-rolled update application (and its broken `update_files`
   hash-recording loop) is intentionally not carried over.
3. **Pin bump cadence** for `CORE_COMMIT`/`BOTS_COMMIT` (suggest: manual
   `workflow_dispatch` inputs like the reference publish workflow's
   `source_ref`).

## 7. Non-goals

- Modifying the reference Shyalya image pipeline at
  `/Users/pho/Turtle/tortoise-docker` (stays as-is until the fork archives).
- Gameplay fixes to TortoiseBots itself (upstream concerns).
- Automating runtime gameplay verification (manual playtest per §5.6).
