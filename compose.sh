#!/bin/sh
# Wrapper around docker compose that gives .env authority over exported
# variables with the same names. Compose prefers the process environment, so a
# shell that exports AI_* / DB_* / MAPUPDATE_* keys silently overrides .env
# edits (observed 2026-10-01: AI_BOT_AI_TICK_DIVISOR stayed 5 after .env said
# 10). Every variable defined in .env is dropped from the environment before
# handing off to docker compose.
set -e
cd "$(dirname "$0")"
for key in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | cut -d= -f1 | sort -u); do
    unset "$key"
done
exec docker compose -f docker-compose.penqle.yml "$@"
