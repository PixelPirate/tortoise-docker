#!/usr/bin/env bash
set -euo pipefail

ETC="${TURTLE_HOME:-/opt/turtle}/etc"
# Baked into the image at build time, separate from ETC so a CONFIG_PATH bind
# mount over ETC (see docker-compose.penqle.yml) can't hide the .dist templates.
ETC_DIST="${TURTLE_HOME:-/opt/turtle}/etc.dist"
DATA_DIR="${DATA_DIR:-/opt/turtle/data}"
LOGS_DIR="${LOGS_DIR:-/opt/turtle/logs}"
SQL_DIR="${SQL_DIR:-/opt/turtle/sql}"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-mangos}"
DB_PASSWORD="${DB_PASSWORD:-mangos}"
DB_LOGIN="${DB_LOGIN:-tw_logon}"
DB_WORLD="${DB_WORLD:-tw_world}"
DB_CHAR="${DB_CHAR:-tw_char}"
DB_LOGS="${DB_LOGS:-tw_logs}"

WORLD_PORT="${WORLD_PORT:-8090}"
REALM_PORT="${REALM_PORT:-3724}"
REALM_ID="${REALM_ID:-1}"
BIND_IP="${BIND_IP:-0.0.0.0}"

LOG_SQL="${LOG_SQL:-0}"
AUTO_UPDATE="${DATABASE_AUTOUPDATE_ENABLED:-1}"

AI_PLAYERBOT_ENABLED="${AI_PLAYERBOT_ENABLED:-1}"
AI_MIN_RANDOM_BOTS="${AI_MIN_RANDOM_BOTS:-10}"
AI_MAX_RANDOM_BOTS="${AI_MAX_RANDOM_BOTS:-10}"
AI_RANDOM_BOT_LOGIN_WITH_PLAYER="${AI_RANDOM_BOT_LOGIN_WITH_PLAYER:-1}"
AI_SUMMON_WHEN_GROUP="${AI_SUMMON_WHEN_GROUP:-1}"
AI_DISABLE_RANDOM_LEVELS="${AI_DISABLE_RANDOM_LEVELS:-0}"
AI_RANDOM_BOT_STARTING_LEVEL="${AI_RANDOM_BOT_STARTING_LEVEL:-1}"
AI_RANDOM_BOT_MAX_LEVEL="${AI_RANDOM_BOT_MAX_LEVEL:-60}"
# Fresh pool bots get a random level in [MIN, MAX] once, on their first login
# (played time == 0), then level normally. Upstream default is 1 / 60 (fresh
# bots spread over every level); 1 / 1 keeps the historic level-1 start.
AI_RANDOM_BOT_START_LEVEL_MIN="${AI_RANDOM_BOT_START_LEVEL_MIN:-1}"
AI_RANDOM_BOT_START_LEVEL_MAX="${AI_RANDOM_BOT_START_LEVEL_MAX:-60}"
# Level ladder: choose the next bot to log in by level band so every band has a
# share of the online target, instead of round-robin over the whole pool.
AI_LEVEL_LADDER="${AI_LEVEL_LADDER:-1}"
# Share of the online target held for level 60 (a hard cap); the rest stay offline.
AI_LEVEL_LADDER_MAX_LEVEL_SHARE="${AI_LEVEL_LADDER_MAX_LEVEL_SHARE:-10}"
# Bot XP multiplier (server XP rate * this). Upstream default is 3.
AI_XPRATE="${AI_XPRATE:-3}"
AI_RANDOM_BOT_AUTOLOGIN="${AI_RANDOM_BOT_AUTOLOGIN:-0}"
AI_RANDOM_BOT_AUTO_CREATE="${AI_RANDOM_BOT_AUTO_CREATE:-0}"
AI_ENABLE_RANDOM_TELEPORTS="${AI_ENABLE_RANDOM_TELEPORTS:-0}"
AI_RANDOM_BOT_LFT_ENABLED="${AI_RANDOM_BOT_LFT_ENABLED:-0}"
AI_AH_MARKET_ENABLED="${AI_AH_MARKET_ENABLED:-0}"
AI_FORCE_REBUFF_ON_READY_CHECK="${AI_FORCE_REBUFF_ON_READY_CHECK:-0}"
AI_FAILED_ACTION_RETRY_BASE="${AI_FAILED_ACTION_RETRY_BASE:-250}"
AI_FAILED_ACTION_RETRY_MAX="${AI_FAILED_ACTION_RETRY_MAX:-2000}"
# 1 (upstream default) = every bot runs a full AI tick every world tick.
# 0 = bots far from any player (and in maps/zones with no players) share a
# rotating activity budget instead, so the per-tick bot cost stops scaling 1:1
# with the population. Bots near, visible to, grouped with, or fighting near a
# player stay fully active either way. See README "World tick budget".
AI_DISABLE_ACTIVITY_PRIORITIES="${AI_DISABLE_ACTIVITY_PRIORITIES:-1}"
# Bot AI ticks per world tick divisor: 1 (default) = every eligible bot gets a
# full AI tick every tick; >1 staggers bots that no real player is involved
# with (see BotManager::ShouldStaggerAiThisTick) so the world tick cost stops
# scaling 1:1 with the bot pool. Needs the 012-bot-ai-tick-divisor patch.
AI_BOT_AI_TICK_DIVISOR="${AI_BOT_AI_TICK_DIVISOR:-1}"
# Cost-adaptive scheduling (needs the 013 patch in the image): a single bot AI
# update that costs at least this many microseconds is logged as HEAVYBOT
# (rate-limited to one line per bot per 30 s) and, when
# AI_BOT_ADAPTIVE_BACKOFF_MAX is above AI_BOT_AI_TICK_DIVISOR, is staggered
# more often. 0 disables both. See README "World tick budget".
AI_BOT_UPDATE_WARN_US="${AI_BOT_UPDATE_WARN_US:-20000}"
# Upper bound (1-60) on the cost-adaptive stagger divisor for persistently
# expensive bots. Must be above AI_BOT_AI_TICK_DIVISOR to have any effect.
AI_BOT_ADAPTIVE_BACKOFF_MAX="${AI_BOT_ADAPTIVE_BACKOFF_MAX:-10}"
# Upstream budgets the random-pool AI pass (PoolTickBudgetUs of work per tick,
# but only once the previous world tick ran longer than
# PoolBudgetWhenTickOverMs). With the tick divisor above the full staggered pass
# is already cheap, so upstream's 150 ms gate makes the budget starve the pool
# for almost no tick gain; the default here raises the gate to 250 ms so a
# healthy tick always gets the full pass and the budget only caps a genuinely
# long tick. Set AI_POOL_TICK_BUDGET_US=0 to disable the budget entirely.
AI_POOL_TICK_BUDGET_US="${AI_POOL_TICK_BUDGET_US:-10000}"
AI_POOL_BUDGET_WHEN_TICK_OVER_MS="${AI_POOL_BUDGET_WHEN_TICK_OVER_MS:-250}"

# Continents (Kalimdor/Eastern Kingdoms) update their active cells and unit
# motion on per-map pools. Upstream ships both at 1, which leaves zero extra
# workers, so every marked cell and every moving unit in a continent is
# processed on one thread; at random-bot scale that pushes the world tick to
# hundreds of milliseconds or seconds. See README "World tick budget".
MAPUPDATE_MTCELLS_THREADS="${MAPUPDATE_MTCELLS_THREADS:-6}"
MAPUPDATE_MOTIONUPDATE_THREADS="${MAPUPDATE_MOTIONUPDATE_THREADS:-4}"
# Core patch 001 (headless-bot-visibility-elision): skip create/out-of-range
# blocks and movement-broadcast subscriptions between two bot sessions. Bots
# have no client, so those packets are dropped at the send path anyway; in a
# crowded zone the per-(bot,bot) pair cost grows with the square of the local
# population. Real players keep full visibility in both directions. 0 reverts
# to upstream behavior. Needs the patch in the image; restart to change.
HEADLESS_BOT_VISIBILITY_ELISION="${HEADLESS_BOT_VISIBILITY_ELISION:-1}"

DB_INFO() {
  local db="$1"
  printf '%s;%s;%s;%s;%s' "${DB_HOST}" "${DB_PORT}" "${DB_USER}" "${DB_PASSWORD}" "${db}"
}

set_conf() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "${file}"
  else
    printf '\n%s = %s\n' "${key}" "${value}" >> "${file}"
  fi
}

ensure_conf() {
  local dist="$1" conf="$2"
  if [[ ! -f "${conf}" ]]; then
    if [[ ! -f "${dist}" ]]; then
      echo "Missing config template: ${dist}" >&2
      exit 1
    fi
    cp "${dist}" "${conf}"
  fi
}

mkdir -p "${ETC}/modules"

# Core configs
ensure_conf "${ETC_DIST}/mangosd.conf.dist" "${ETC}/mangosd.conf"
ensure_conf "${ETC_DIST}/realmd.conf.dist" "${ETC}/realmd.conf"

# TortoiseBots module configs (templates baked from the module clone)
ensure_conf "${ETC_DIST}/modules/aiplayerbot.conf" "${ETC}/modules/aiplayerbot.conf"
ensure_conf "${ETC_DIST}/modules/tortoise_bots.conf" "${ETC}/modules/tortoise_bots.conf"
ensure_conf "${ETC_DIST}/modules/mod_dungeon_clear.conf" "${ETC}/modules/mod_dungeon_clear.conf"

# mangosd (key names per Penqle's mangosd.conf.dist)
set_conf "${ETC}/mangosd.conf" "LoginDatabase.Info" "\"$(DB_INFO "${DB_LOGIN}")\""
set_conf "${ETC}/mangosd.conf" "WorldDatabase.Info" "\"$(DB_INFO "${DB_WORLD}")\""
set_conf "${ETC}/mangosd.conf" "CharacterDatabase.Info" "\"$(DB_INFO "${DB_CHAR}")\""
set_conf "${ETC}/mangosd.conf" "LogsDatabase.Info" "\"$(DB_INFO "${DB_LOGS}")\""
set_conf "${ETC}/mangosd.conf" "DataDir" "\"${DATA_DIR}\""
set_conf "${ETC}/mangosd.conf" "LogsDir" "\"${LOGS_DIR}\""
set_conf "${ETC}/mangosd.conf" "WorldServerPort" "${WORLD_PORT}"
set_conf "${ETC}/mangosd.conf" "BindIP" "\"${BIND_IP}\""
set_conf "${ETC}/mangosd.conf" "RealmID" "${REALM_ID}"
set_conf "${ETC}/mangosd.conf" "LogSQL" "${LOG_SQL}"
set_conf "${ETC}/mangosd.conf" "Database.AutoUpdate.Enabled" "${AUTO_UPDATE}"
set_conf "${ETC}/mangosd.conf" "Database.AutoUpdate.Path" "\"${SQL_DIR}/database_updates/\""

# Core map-update threading (keys verified against mangosd.conf.dist).
# MTCells.Threads is a worker count plus the caller: 1 => no worker threads.
set_conf "${ETC}/mangosd.conf" "MapUpdate.Continents.MTCells.Threads" "${MAPUPDATE_MTCELLS_THREADS}"
set_conf "${ETC}/mangosd.conf" "Continents.MotionUpdate.Threads" "${MAPUPDATE_MOTIONUPDATE_THREADS}"
set_conf "${ETC}/mangosd.conf" "Headless.BotVisibilityElision" "${HEADLESS_BOT_VISIBILITY_ELISION}"

# realmd (note: key name has no dots between LoginDatabase and Info)
set_conf "${ETC}/realmd.conf" "LoginDatabaseInfo" "\"$(DB_INFO "${DB_LOGIN}")\""
set_conf "${ETC}/realmd.conf" "RealmServerPort" "${REALM_PORT}"
set_conf "${ETC}/realmd.conf" "BindIP" "\"${BIND_IP}\""

# TortoiseBots — all bot services default OFF upstream; .env opts in.
AI_CONF="${ETC}/modules/aiplayerbot.conf"
# The module resolves its config next to mangosd.conf (or via this override);
# without it it falls back to compiled-in defaults (Enabled=0) and switches off.
set_conf "${ETC}/mangosd.conf" "AiPlayerbot.ConfigFile" "${AI_CONF}"
set_conf "${AI_CONF}" "AiPlayerbot.Enabled" "${AI_PLAYERBOT_ENABLED}"
set_conf "${AI_CONF}" "AiPlayerbot.MinRandomBots" "${AI_MIN_RANDOM_BOTS}"
set_conf "${AI_CONF}" "AiPlayerbot.MaxRandomBots" "${AI_MAX_RANDOM_BOTS}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotAutoCreate" "${AI_RANDOM_BOT_AUTO_CREATE}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotAutologin" "${AI_RANDOM_BOT_AUTOLOGIN}"
# The new service gates its pool start-up on RandomBotLoginAtStartup
# (RandomBotService m_started); Autologin alone is the legacy key.
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotLoginAtStartup" "${AI_RANDOM_BOT_AUTOLOGIN}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotLoginWithPlayer" "${AI_RANDOM_BOT_LOGIN_WITH_PLAYER}"
set_conf "${AI_CONF}" "AiPlayerbot.EnableRandomTeleports" "${AI_ENABLE_RANDOM_TELEPORTS}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotLftEnabled" "${AI_RANDOM_BOT_LFT_ENABLED}"
set_conf "${AI_CONF}" "AiPlayerbot.AhMarketEnabled" "${AI_AH_MARKET_ENABLED}"
set_conf "${AI_CONF}" "AiPlayerbot.DisableActivityPriorities" "${AI_DISABLE_ACTIVITY_PRIORITIES}"
set_conf "${AI_CONF}" "AiPlayerbot.BotAiTickDivisor" "${AI_BOT_AI_TICK_DIVISOR}"
set_conf "${AI_CONF}" "AiPlayerbot.BotUpdateWarnUs" "${AI_BOT_UPDATE_WARN_US}"
set_conf "${AI_CONF}" "AiPlayerbot.BotAdaptiveBackoffMax" "${AI_BOT_ADAPTIVE_BACKOFF_MAX}"
set_conf "${AI_CONF}" "AiPlayerbot.PoolTickBudgetUs" "${AI_POOL_TICK_BUDGET_US}"
set_conf "${AI_CONF}" "AiPlayerbot.PoolBudgetWhenTickOverMs" "${AI_POOL_BUDGET_WHEN_TICK_OVER_MS}"
set_conf "${AI_CONF}" "AiPlayerbot.ForceRebuffOnReadyCheck" "${AI_FORCE_REBUFF_ON_READY_CHECK}"
set_conf "${AI_CONF}" "AiPlayerbot.FailedActionRetryBase" "${AI_FAILED_ACTION_RETRY_BASE}"
set_conf "${AI_CONF}" "AiPlayerbot.FailedActionRetryMax" "${AI_FAILED_ACTION_RETRY_MAX}"
set_conf "${AI_CONF}" "AiPlayerbot.SummonWhenGroup" "${AI_SUMMON_WHEN_GROUP}"
set_conf "${AI_CONF}" "AiPlayerbot.DisableRandomLevels" "${AI_DISABLE_RANDOM_LEVELS}"

# mod-dungeon-clear (vendored): only keys that exist in the module's .dist.
# Master toggle, default OFF (house rule: autonomous background services are
# opt-in). The rest of the module's DungeonClear.* keys stay at their conf.dist
# defaults; edit the rendered file directly for those.
DC_CONF="${ETC}/modules/mod_dungeon_clear.conf"
DUNGEON_CLEAR_ENABLED="${DUNGEON_CLEAR_ENABLED:-0}"
set_conf "${DC_CONF}" "DungeonClear.Enabled" "${DUNGEON_CLEAR_ENABLED}"
set_conf "${AI_CONF}" "AiPlayerbot.randombotStartingLevel" "${AI_RANDOM_BOT_STARTING_LEVEL}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotMaxLevel" "${AI_RANDOM_BOT_MAX_LEVEL}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotStartLevelMin" "${AI_RANDOM_BOT_START_LEVEL_MIN}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotStartLevelMax" "${AI_RANDOM_BOT_START_LEVEL_MAX}"
set_conf "${AI_CONF}" "AiPlayerbot.LevelLadder" "${AI_LEVEL_LADDER}"
set_conf "${AI_CONF}" "AiPlayerbot.LevelLadderMaxLevelShare" "${AI_LEVEL_LADDER_MAX_LEVEL_SHARE}"
set_conf "${AI_CONF}" "AiPlayerbot.XPRate" "${AI_XPRATE}"

mkdir -p "${LOGS_DIR}"
# Writable for the turtle user (configs may be regenerated each start).
chown -R turtle:turtle "${ETC}" "${LOGS_DIR}" 2>/dev/null || true

echo "Configs rendered under ${ETC}"
