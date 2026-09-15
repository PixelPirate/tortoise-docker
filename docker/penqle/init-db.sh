#!/usr/bin/env bash
set -euo pipefail

MARKER_DIR="${INIT_MARKER_DIR:-/var/lib/turtle-init}"
MARKER_FILE="${MARKER_DIR}/initialized"
SQL_ROOT="${SQL_DIR:-/opt/turtle/sql}"
MODULE_SQL="/opt/turtle/modules/TortoiseBots/data/sql"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
DB_USER="${DB_USER:-mangos}"
DB_PASSWORD="${DB_PASSWORD:-mangos}"
DB_LOGIN="${DB_LOGIN:-tw_logon}"
DB_WORLD="${DB_WORLD:-tw_world}"
DB_CHAR="${DB_CHAR:-tw_char}"
DB_LOGS="${DB_LOGS:-tw_logs}"

REALM_NAME="${REALM_NAME:-TurtleWoW}"
REALM_ADDRESS="${REALM_ADDRESS:-127.0.0.1}"
WORLD_PORT="${WORLD_PORT:-8090}"
REALM_ID="${REALM_ID:-1}"

if [[ -z "${DB_ROOT_PASSWORD}" ]]; then
  echo "DB_ROOT_PASSWORD (or MYSQL_ROOT_PASSWORD) is required." >&2
  exit 1
fi

mysql_root() {
  mysql -h"${DB_HOST}" -P"${DB_PORT}" -uroot -p"${DB_ROOT_PASSWORD}" --protocol=TCP "$@"
}

echo "Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
for i in $(seq 1 90); do
  if mysql_root -e "SELECT 1" &>/dev/null; then
    break
  fi
  if [[ "${i}" -eq 90 ]]; then
    echo "MariaDB did not become ready in time." >&2
    exit 1
  fi
  sleep 2
done
echo "MariaDB is ready."

if [[ -f "${MARKER_FILE}" ]]; then
  echo "Init marker found (${MARKER_FILE}); skipping database import."
  exit 0
fi

if [[ ! -f "${SQL_ROOT}/create_databases.sql" ]]; then
  echo "Missing ${SQL_ROOT}/create_databases.sql" >&2
  exit 1
fi

echo "Creating databases and base schemas..."
mysql_root < "${SQL_ROOT}/create_databases.sql"

# BackupCharacterInventory (ObjectMgr.cpp) copies rows with INSERT ... SELECT *
# and therefore requires a structurally identical snapshot table in the
# character database. The table definition ships with this image, not with the
# core's SQL.
character_inventory_copy_sql="${SQL_ROOT}/character-inventory-copy.sql"
if [[ ! -f "${character_inventory_copy_sql}" ]]; then
  echo "Missing ${character_inventory_copy_sql}" >&2
  exit 1
fi
echo "Ensuring character_inventory_copy exists..."
mysql_root "${DB_CHAR}" < "${character_inventory_copy_sql}"

# TortoiseBots' BattlegroundQueueService joins `account` on the character-DB
# connection (runtime/BattlegroundQueueService.cpp) while the table lives in
# the login DB. Expose a read-only compatibility view so those queries resolve.
echo "Ensuring ${DB_CHAR}.account compatibility view..."
mysql_root <<SQL
CREATE OR REPLACE VIEW ${DB_CHAR}.account AS
SELECT id, username FROM ${DB_LOGIN}.account;
SQL

echo "Creating application user '${DB_USER}' and grants..."
mysql_root <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_LOGIN}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_WORLD}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_CHAR}\`.* TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_LOGS}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "Importing world content from sql/base (this can take several minutes)..."
shopt -s nullglob
base_files=("${SQL_ROOT}"/base/*.sql)
if [[ "${#base_files[@]}" -eq 0 ]]; then
  echo "No SQL files found under ${SQL_ROOT}/base" >&2
  exit 1
fi
for f in "${base_files[@]}"; do
  echo "  -> $(basename "${f}")"
  mysql_root "${DB_WORLD}" < "${f}"
done

# Upstream ships placeholder playercreateinfo rows for Turtle's custom races
# (9=goblin -> zone 5536 on map 1, 10=high elf -> zone 5225 on map 0). Those
# zones do not exist on the vanilla maps this image ships map/vmap data for,
# and bots spawned there crash the world server. Pin both races to the same
# valid start positions the reference image hardcodes in its bot factory.
echo "Fixing custom-race playercreateinfo rows..."
mysql_root <<SQL
UPDATE ${DB_WORLD}.playercreateinfo SET map=0, zone=12, position_x=-8949.95, position_y=-132.493, position_z=83.5312, orientation=0 WHERE race=10;
UPDATE ${DB_WORLD}.playercreateinfo SET map=1, zone=14, position_x=-618.518, position_y=-4251.67, position_z=38.718, orientation=0 WHERE race=9;
SQL

# Core database_updates are NOT applied here. The core AutoUpdater applies them
# on first mangosd start (Database.AutoUpdate.Path) and records proper SHA1
# hashes in each database's `migrations` table — the mechanism the old Shyalya
# init tried to replicate by hand and got wrong.

# TortoiseBots module migrations: the runtime AutoUpdater cannot see the
# build-time module source path, so we apply them here instead. Schema-only,
# idempotent (CREATE TABLE IF NOT EXISTS).
if [[ -d "${MODULE_SQL}/world" ]]; then
  echo "Applying TortoiseBots world module SQL..."
  for f in "${MODULE_SQL}"/world/*.sql; do
    echo "  -> $(basename "${f}")"
    mysql_root "${DB_WORLD}" < "${f}"
  done
fi
# Upstream named the character-side dir `character` at the pinned commit
# (older checkouts used `char`); accept either so the schema never lags.
for CHAR_DIR in char character; do
  if [[ -d "${MODULE_SQL}/${CHAR_DIR}" ]]; then
    echo "Applying TortoiseBots character module SQL (${CHAR_DIR}/)..."
    for f in "${MODULE_SQL}/${CHAR_DIR}"/*.sql; do
      echo "  -> $(basename "${f}")"
      mysql_root "${DB_CHAR}" < "${f}"
    done
  fi
done

echo "Inserting realmlist row..."
mysql_root <<SQL
DELETE FROM ${DB_LOGIN}.realmlist;
INSERT INTO ${DB_LOGIN}.realmlist
  (id, name, address, port, icon, realmflags, timezone, allowedSecurityLevel, realmbuilds)
VALUES
  (${REALM_ID}, '${REALM_NAME}', '${REALM_ADDRESS}', ${WORLD_PORT}, 0, 0, 1, 0, '7272');
SQL

mkdir -p "${MARKER_DIR}"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER_FILE}"
echo "Database init complete."
