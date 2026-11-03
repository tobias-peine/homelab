#!/usr/bin/env bash
# Offsite-Pull auf den Linux-Rechner.
#
#   ./scripts/pull-backups.sh
#   SERVER=<TAILSCALE_IP> ./scripts/pull-backups.sh
#   KEEP=7 DEST=/srv/backups ./scripts/pull-backups.sh
#
# Holt Paperless- und Ghost-Backups als ein Tar vom Server, prüft das Alter des
# Ghost-Backups, verschlüsselt lokal mit age und räumt alte Archive auf.
# Der Rechner zieht – der Server braucht keinen Zugang hierher.
set -Eeuo pipefail
umask 077

SERVER="${SERVER:-vps2662496.fastwebserver.de}"
REMOTE_USER="${REMOTE_USER:-admin}"
OFFSITE_DIR="${OFFSITE_DIR:-$HOME/dsh-spielwiese/.offsite}"
DEST="${DEST:-$OFFSITE_DIR/backups}"
KEY="${SSH_KEY:-$OFFSITE_DIR/id_ed25519}"
AGE_BIN="${AGE_BIN:-$OFFSITE_DIR/bin/age}"
AGE_KEYGEN="${AGE_KEYGEN:-$(dirname "$AGE_BIN")/age-keygen}"
AGE_KEY="${AGE_KEY:-$OFFSITE_DIR/age.key}"
AGE_PUB="${AGE_PUB:-$OFFSITE_DIR/age.pub}"
KEEP="${KEEP:-14}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
TAR="$DEST/homelab-$STAMP.tgz"
REMOTE="/tmp/homelab-backup-$STAMP.tgz"
NTFY=""
[ -f "$OFFSITE_DIR/ntfy.topic" ] && NTFY="$(tr -d '[:space:]' < "$OFFSITE_DIR/ntfy.topic")"

mkdir -p "$DEST" "$OFFSITE_DIR"
LOG="$OFFSITE_DIR/pull.log"
log() { printf '%s  %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
notify() {
  [ -n "$NTFY" ] || return 0
  curl -fsS --max-time 15 -d "$*" "https://ntfy.sh/$NTFY" >/dev/null 2>&1 || true
}
die() { log "FEHLER: $*"; notify "Homelab-Backup fehlgeschlagen: $*"; exit 1; }
trap 'die "abgebrochen in Zeile $LINENO"' ERR

[ -f "$KEY" ] || die "SSH-Key fehlt: $KEY"
[ -x "$AGE_BIN" ] || die "age fehlt: $AGE_BIN"
[ -x "$AGE_KEYGEN" ] || die "age-keygen fehlt: $AGE_KEYGEN"
[ -f "$AGE_KEY" ] || die "age-Key fehlt: $AGE_KEY"
[ -f "$AGE_PUB" ] || "$AGE_KEYGEN" -y "$AGE_KEY" > "$AGE_PUB"

SSH=(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes)
SCP=(scp -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes)

log "Start – $REMOTE_USER@$SERVER"

"${SSH[@]}" "$REMOTE_USER@$SERVER" \
  "sudo tar czf $REMOTE -C /opt/backups paperless -C /opt/kisium backups \
   && sudo chown $REMOTE_USER:$REMOTE_USER $REMOTE"

log "Hole Archiv ..."
"${SCP[@]}" "$REMOTE_USER@$SERVER:$REMOTE" "$TAR"
"${SSH[@]}" "$REMOTE_USER@$SERVER" "rm -f $REMOTE" >/dev/null

SIZE="$(stat -c %s "$TAR")"
[ "$SIZE" -ge 1024 ] || die "Archiv zu klein: $SIZE Bytes"
log "Archiv: $((SIZE / 1024 / 1024)) MB"

tar -tzf "$TAR" >/dev/null || die "Archiv ist kein gültiges tar.gz"
GHOST_STAMP="$(tar -tzf "$TAR" \
  | sed -n 's|.*ghost-db-\([0-9]\{8\}\)-\([0-9]\{6\}\)\.sql\.gz$|\1\2|p' \
  | sort | tail -n 1)"
[ -n "$GHOST_STAMP" ] || die "kein Ghost-Backup im Archiv"
GHOST_TS="$(date -u -d "${GHOST_STAMP:0:8} ${GHOST_STAMP:8:2}:${GHOST_STAMP:10:2}:${GHOST_STAMP:12:2}" +%s)"
AGE_H=$(( ( $(date +%s) - GHOST_TS ) / 3600 ))
log "Ghost-Backup: $GHOST_STAMP (${AGE_H} h alt)"
[ "$AGE_H" -le 26 ] || die "Ghost-Backup zu alt: ${AGE_H} h"

AGE_PUB_VALUE="$(cat "$AGE_PUB")"
"$AGE_BIN" -r "$AGE_PUB_VALUE" -o "$TAR.age" "$TAR"
rm -f "$TAR"
log "Verschlüsselt: $(basename "$TAR.age")"

find "$DEST" -maxdepth 1 -type f -name 'homelab-*' -printf '%T@ %p\n' \
  | sort -nr | tail -n +$((KEEP + 1)) | cut -d' ' -f2- \
  | while read -r old; do log "entferne alt: $(basename "$old")"; rm -f "$old"; done

log "OK"
