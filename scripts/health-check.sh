#!/usr/bin/env bash
# Prüft den laufenden Stack: Container, HTTP, Platte, Zombies, Swap.
#
#   ./scripts/health-check.sh
#
# Exit 0 = alles in Ordnung. Exit 1 = harte Fehler (Container aus, HTTP nicht 200).
# Warnungen (Platte voll, Zombies, Swap) setzen den Exit-Code nicht.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/compose/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/compose/.env}"
GHOST_CONTAINER="${GHOST_CONTAINER:-kisium-ghost}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-kisium-mysql}"
HTTP_URL="${HTTP_URL:-http://127.0.0.1:2368/}"

fail=0
warn=0

ok()   { printf '  OK    %s\n' "$*"; }
bad()  { printf '  FEHLER %s\n' "$*"; fail=1; }
note() { printf '  WARN  %s\n' "$*"; warn=1; }

echo "=== Health-Check $(date '+%F %T') ==="

# --- Container --------------------------------------------------------------
for c in "$GHOST_CONTAINER" "$MYSQL_CONTAINER"; do
  if docker inspect "$c" >/dev/null 2>&1; then
    state="$(docker inspect "$c" --format '{{.State.Status}}')"
    health="$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}')"
    if [ "$state" = "running" ]; then ok "$c: running (health: $health)"; else bad "$c: $state"; fi
  else
    bad "$c: Container nicht gefunden"
  fi
done

# --- HTTP -------------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$HTTP_URL" || true)"
  if [ "$code" = "200" ]; then ok "HTTP $HTTP_URL → 200"; else bad "HTTP $HTTP_URL → ${code:-keine Antwort}"; fi
else
  note "curl fehlt – HTTP-Prüfung übersprungen"
fi

# --- Platte -----------------------------------------------------------------
use="$(df -P "$ROOT_DIR" | awk 'NR==2 {gsub("%","",$5); print $5}')"
if [ "${use:-0}" -ge 90 ]; then bad "Platte zu ${use}% belegt"; elif [ "${use:-0}" -ge 80 ]; then note "Platte zu ${use}% belegt"; else ok "Platte zu ${use}% belegt"; fi

# --- Zombies ----------------------------------------------------------------
zombies="$(ps -eo stat= 2>/dev/null | grep -c '^Z' || true)"
if [ "${zombies:-0}" -gt 0 ]; then note "$zombies Zombie-Prozesse"; else ok "keine Zombies"; fi

# --- Swap -------------------------------------------------------------------
if command -v free >/dev/null 2>&1; then
  # LC_ALL=C: sonst heißt die Zeile je nach Locale "Auslager:" statt "Swap:".
  swap="$(LC_ALL=C free | awk '/^Swap:/ {if ($2>0) printf "%d", $3*100/$2; else print 0}')"
  if [ "${swap:-0}" -ge 50 ]; then note "Swap zu ${swap}% belegt"; else ok "Swap zu ${swap:-0}% belegt"; fi
fi

echo
if [ "$fail" -ne 0 ]; then echo "ERGEBNIS: FEHLER"; exit 1; fi
if [ "$warn" -ne 0 ]; then echo "ERGEBNIS: OK mit Warnungen"; exit 0; fi
echo "ERGEBNIS: OK"
