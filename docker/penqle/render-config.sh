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
AI_RANDOM_BOT_AUTOLOGIN="${AI_RANDOM_BOT_AUTOLOGIN:-0}"
AI_ENABLE_RANDOM_TELEPORTS="${AI_ENABLE_RANDOM_TELEPORTS:-0}"
AI_RANDOM_BOT_LFT_ENABLED="${AI_RANDOM_BOT_LFT_ENABLED:-0}"
AI_AH_MARKET_ENABLED="${AI_AH_MARKET_ENABLED:-0}"
AI_FORCE_REBUFF_ON_READY_CHECK="${AI_FORCE_REBUFF_ON_READY_CHECK:-0}"
AI_FAILED_ACTION_RETRY_BASE="${AI_FAILED_ACTION_RETRY_BASE:-250}"
AI_FAILED_ACTION_RETRY_MAX="${AI_FAILED_ACTION_RETRY_MAX:-2000}"

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

# realmd (note: key name has no dots between LoginDatabase and Info)
set_conf "${ETC}/realmd.conf" "LoginDatabaseInfo" "\"$(DB_INFO "${DB_LOGIN}")\""
set_conf "${ETC}/realmd.conf" "RealmServerPort" "${REALM_PORT}"
set_conf "${ETC}/realmd.conf" "BindIP" "\"${BIND_IP}\""

# TortoiseBots — all bot services default OFF upstream; .env opts in.
AI_CONF="${ETC}/modules/aiplayerbot.conf"
set_conf "${AI_CONF}" "AiPlayerbot.Enabled" "${AI_PLAYERBOT_ENABLED}"
set_conf "${AI_CONF}" "AiPlayerbot.MinRandomBots" "${AI_MIN_RANDOM_BOTS}"
set_conf "${AI_CONF}" "AiPlayerbot.MaxRandomBots" "${AI_MAX_RANDOM_BOTS}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotAutoCreate" "0"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotAutologin" "${AI_RANDOM_BOT_AUTOLOGIN}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotLoginWithPlayer" "${AI_RANDOM_BOT_LOGIN_WITH_PLAYER}"
set_conf "${AI_CONF}" "AiPlayerbot.EnableRandomTeleports" "${AI_ENABLE_RANDOM_TELEPORTS}"
set_conf "${AI_CONF}" "AiPlayerbot.RandomBotLftEnabled" "${AI_RANDOM_BOT_LFT_ENABLED}"
set_conf "${AI_CONF}" "AiPlayerbot.AhMarketEnabled" "${AI_AH_MARKET_ENABLED}"
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

mkdir -p "${LOGS_DIR}"
# Writable for the turtle user (configs may be regenerated each start).
chown -R turtle:turtle "${ETC}" "${LOGS_DIR}" 2>/dev/null || true

echo "Configs rendered under ${ETC}"
