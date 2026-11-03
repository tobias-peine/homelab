#!/usr/bin/env bash
# Spielt die letzte Sicherung in ein separates Compose-Projekt zurück und prüft sie.
#
#   ./scripts/restore-test.sh
#   PORT=2371 PROJECT=homelabrestore2 SOURCE_MYSQL=kisium-mysql ./scripts/restore-test.sh
#   KEEP=1 ./scripts/restore-test.sh          # Testumgebung nach dem Lauf stehen lassen
#
# Das Skript fasst die Produktion nicht an: eigenes Projekt, eigenes Netz, eigene
# Volumes, eigener Port. Es bricht ab, wenn PROJECT "kisium" ist oder der Port belegt.
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/compose/docker-compose.yml}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
PROJECT="${PROJECT:-homelabrestore}"
PORT="${PORT:-2370}"
SOURCE_MYSQL="${SOURCE_MYSQL:-kisium-mysql}"
KEEP="${KEEP:-0}"
GHOST_UID="${GHOST_UID:-1000}"

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
die() { log "FEHLER: $*" >&2; exit 1; }
trap 'die "abgebrochen in Zeile $LINENO"' ERR

[ "$PROJECT" != "kisium" ] || die "PROJECT darf nicht 'kisium' sein – das ist die Produktion"
[[ "$PROJECT" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "PROJECT enthält ungültige Zeichen"
[ -f "$COMPOSE_FILE" ] || die "Compose-Datei fehlt: $COMPOSE_FILE"
for cmd in docker curl openssl; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd fehlt"
done

DUMP="${DUMP:-$(ls -t "$BACKUP_DIR"/ghost-db-*.sql.gz 2>/dev/null | head -1 || true)}"
CONTENT="${CONTENT:-$(ls -t "$BACKUP_DIR"/ghost-content-*.tar.gz 2>/dev/null | head -1 || true)}"
[ -n "$DUMP" ] && [ -f "$DUMP" ] || die "kein Dump gefunden (DUMP=... setzen)"
[ -n "$CONTENT" ] && [ -f "$CONTENT" ] || die "kein Content-Archiv gefunden (CONTENT=... setzen)"

# Port belegt? (ss ist auf Debian/Ubuntu vorhanden; sonst überspringen)
if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$PORT" 2>/dev/null | grep -q LISTEN; then
  die "Port $PORT ist bereits belegt – PORT=... setzen"
fi

# Prüfsummen, falls vorhanden
STAMP="$(basename "$DUMP" | sed -E 's/^ghost-db-(.*)\.sql\.gz$/\1/')"
SUM="$BACKUP_DIR/sha256-$STAMP.txt"
if [ -f "$SUM" ]; then
  ( cd "$BACKUP_DIR" && sha256sum -c "$(basename "$SUM")" ) >/dev/null \
    || die "Prüfsummen passen nicht – Sicherung ist beschädigt"
  log "Prüfsummen ok"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/restore-test.XXXXXX")"
TEST_COMPOSE="$TMP_DIR/docker-compose.yml"
TEST_OVERRIDE="$TMP_DIR/docker-compose.override.yml"
TEST_ENV="$TMP_DIR/.env"

cleanup() {
  if [ "$KEEP" = "1" ]; then
    log "KEEP=1 – Testumgebung bleibt stehen: docker compose -p $PROJECT down -v"
    return
  fi
  docker compose -p "$PROJECT" -f "$TEST_COMPOSE" -f "$TEST_OVERRIDE" --env-file "$TEST_ENV" down -v >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Test-Compose: kein fester Projektname, kein festes Netz, keine Container-Namen,
# kein Port 2368. Der Healthcheck bleibt unangetastet – er prüft im Container.
sed -e '/^name:/d' \
    -e '/name: kisium-net/d' \
    -e '/^    container_name:/d' \
    -e '/^    ports:/,+1d' \
    "$COMPOSE_FILE" > "$TEST_COMPOSE"

cat > "$TEST_OVERRIDE" <<YAML
services:
  ghost:
    ports:
      - "127.0.0.1:$PORT:2368"
YAML

cat > "$TEST_ENV" <<EOF
GHOST_URL=http://localhost:$PORT
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 16)
MYSQL_PASSWORD=$(openssl rand -hex 16)
MAIL_HOST=smtp.example.invalid
MAIL_PORT=587
MAIL_SECURE=false
MAIL_USER=
MAIL_PASSWORD=
MAIL_FROM=Restore Test <restore@example.invalid>
EOF

dc() {
  docker compose -p "$PROJECT" -f "$TEST_COMPOSE" -f "$TEST_OVERRIDE" --env-file "$TEST_ENV" "$@"
}

# Alte Testreste entfernen, damit der Lauf reproduzierbar ist.
dc down -v >/dev/null 2>&1 || true
docker volume rm "${PROJECT}_ghost_content" >/dev/null 2>&1 || true

wait_healthy() {
  local svc="$1" id state i
  for i in $(seq 1 60); do
    id="$(dc ps -q "$svc" 2>/dev/null || true)"
    if [ -n "$id" ]; then
      state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)"
      [ "$state" = "healthy" ] && { log "$svc: healthy"; return 0; }
      [ "$state" = "exited" ] && { dc logs --tail=40 "$svc" >&2 || true; die "$svc ist beendet"; }
    fi
    sleep 3
  done
  dc logs --tail=60 "$svc" >&2 || true
  die "$svc wurde nicht healthy"
}

query_counts() {
  local container="$1"
  docker exec "$container" sh -c \
    'exec mysql -N -uroot -p"$MYSQL_ROOT_PASSWORD" ghost \
     -e "SELECT COUNT(*) FROM posts; SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM settings;"' \
    2>/dev/null | tr -d '\r'
}

log "Start – Projekt $PROJECT, Port $PORT"
START=$SECONDS

# --- 1) Datenbank -----------------------------------------------------------
dc up -d mysql >/dev/null
wait_healthy mysql

# --- 2) Import --------------------------------------------------------------
log "Importiere $(basename "$DUMP")"
zcat "$DUMP" | dc exec -T mysql sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ghost'

# --- 3) Content-Volume ------------------------------------------------------
log "Spiele $(basename "$CONTENT") zurück"
dc stop ghost >/dev/null 2>&1 || true
docker volume create "${PROJECT}_ghost_content" >/dev/null
docker run --rm -v "${PROJECT}_ghost_content:/data" alpine:3.20 \
  sh -c "chown $GHOST_UID:$GHOST_UID /data"
docker run --rm --user "$GHOST_UID:$GHOST_UID" \
  -v "${PROJECT}_ghost_content:/data" \
  -v "$BACKUP_DIR":/backup \
  alpine:3.20 sh -c "cd /data && tar xzf /backup/$(basename "$CONTENT")"

# --- 4) Ghost ---------------------------------------------------------------
dc up -d ghost >/dev/null
wait_healthy ghost

# --- 5) Prüfungen -----------------------------------------------------------
CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" || true)"
[ "$CODE" = "200" ] || die "Startseite antwortet mit $CODE statt 200"
log "Startseite: HTTP 200"

mapfile -t TEST < <(query_counts "$(dc ps -q mysql)")
[ "${#TEST[@]}" -eq 3 ] || die "Testdatenbank liefert keine Zähler"

if docker inspect "$SOURCE_MYSQL" >/dev/null 2>&1; then
  mapfile -t SRC < <(query_counts "$SOURCE_MYSQL")
  log "Quelle: posts=${SRC[0]} users=${SRC[1]} settings=${SRC[2]}"
  log "Restore: posts=${TEST[0]} users=${TEST[1]} settings=${TEST[2]}"
  [ "${SRC[0]}" = "${TEST[0]}" ] || die "Beitragszahl weicht ab: ${SRC[0]} vs. ${TEST[0]}"
  [ "${SRC[1]}" = "${TEST[1]}" ] || die "Benutzerzahl weicht ab: ${SRC[1]} vs. ${TEST[1]}"
  # settings können durch Migrationen wachsen, wenn die Ghost-Version abweicht
  [ "${SRC[2]}" = "${TEST[2]}" ] || log "Hinweis: settings-Zahl abweichend (Migration?)"
else
  log "Quelle $SOURCE_MYSQL nicht gefunden – nur Restore-Zähler: posts=${TEST[0]} users=${TEST[1]} settings=${TEST[2]}"
fi

log "Restore-Test erfolgreich in $((SECONDS - START)) Sekunden"
