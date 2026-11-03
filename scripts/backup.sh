#!/usr/bin/env bash
# Sichert die Ghost-Datenbank und das Content-Volume.
#
#   ./scripts/backup.sh
#   BACKUP_DIR=/srv/backups RETENTION_DAYS=30 ./scripts/backup.sh
#
# Das Skript bricht ab, wenn Docker, Compose-Datei, .env oder ein Container fehlt.
# Es schreibt erst in eine temporäre Datei und benennt sie am Ende um – ein
# abgebrochener Lauf hinterlässt so keine halbe Sicherung, die wie eine ganze aussieht.
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/compose/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/compose/.env}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
GHOST_CONTAINER="${GHOST_CONTAINER:-kisium-ghost}"
MYSQL_SERVICE="${MYSQL_SERVICE:-mysql}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"

DB_FILE="$BACKUP_DIR/ghost-db-$STAMP.sql.gz"
CONTENT_FILE="$BACKUP_DIR/ghost-content-$STAMP.tar.gz"
SUM_FILE="$BACKUP_DIR/sha256-$STAMP.txt"

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
die() { log "FEHLER: $*" >&2; exit 1; }
trap 'rm -f "$DB_FILE.tmp"; die "abgebrochen in Zeile $LINENO"' ERR

command -v docker >/dev/null 2>&1 || die "docker fehlt im PATH"
[ -f "$COMPOSE_FILE" ] || die "Compose-Datei fehlt: $COMPOSE_FILE"
[ -f "$ENV_FILE" ] || die ".env fehlt: $ENV_FILE (cp compose/.env.example compose/.env)"
docker inspect "$GHOST_CONTAINER" >/dev/null 2>&1 || die "Container fehlt: $GHOST_CONTAINER"

dc() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

dc ps --status running --services 2>/dev/null | grep -qx "$MYSQL_SERVICE" \
  || die "Service '$MYSQL_SERVICE' läuft nicht"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# --- Datenbank --------------------------------------------------------------
log "Sichere Datenbank nach $DB_FILE"
# shellcheck disable=SC2016  # $MYSQL_ROOT_PASSWORD expandiert im Container, nicht auf dem Host
dc exec -T "$MYSQL_SERVICE" sh -c \
  'exec mysqldump --single-transaction --routines --triggers \
   -uroot -p"$MYSQL_ROOT_PASSWORD" ghost' \
  | gzip -9 > "$DB_FILE.tmp"

gzip -t "$DB_FILE.tmp" 2>/dev/null || die "Dump ist kein gültiges gzip"
# grep -c statt grep -q: -q beendet die Pipe früh, zcat bekommt SIGPIPE und
# die Pipe schlägt unter `pipefail` fehl, obwohl der Treffer da ist.
TABLES="$(zcat "$DB_FILE.tmp" | grep -c 'CREATE TABLE' || true)"
[ "${TABLES:-0}" -gt 0 ] || die "Dump enthält keine CREATE TABLE (0 Tabellen)"
mv "$DB_FILE.tmp" "$DB_FILE"

# --- Content-Volume ---------------------------------------------------------
log "Sichere Content-Volume nach $CONTENT_FILE"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volumes-from "$GHOST_CONTAINER:ro" \
  -v "$BACKUP_DIR":/backup \
  alpine:3.20 tar czf "/backup/$(basename "$CONTENT_FILE")" \
  -C /var/lib/ghost/content . >/dev/null

tar tzf "$CONTENT_FILE" >/dev/null || die "Content-Archiv ist defekt"

# --- Prüfsummen -------------------------------------------------------------
( cd "$BACKUP_DIR" && sha256sum "$(basename "$DB_FILE")" "$(basename "$CONTENT_FILE")" > "$SUM_FILE" )
log "Prüfsummen: $SUM_FILE"

# --- Aufbewahrung -----------------------------------------------------------
find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name 'ghost-db-*.sql.gz' -o -name 'ghost-content-*.tar.gz' -o -name 'sha256-*.txt' \) \
  -mtime +"$RETENTION_DAYS" -print -delete | while read -r old; do
    log "entfernt (älter als ${RETENTION_DAYS} Tage): $old"
  done

# --- Ergebnis ---------------------------------------------------------------
DB_SIZE="$(du -h "$DB_FILE" | cut -f1)"
CONTENT_SIZE="$(du -h "$CONTENT_FILE" | cut -f1)"
log "fertig: DB $DB_SIZE, Content $CONTENT_SIZE"
log "Restore-Test: docs/backup-restore.md"
