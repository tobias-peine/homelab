#!/usr/bin/env bash
# Prüft das Alter des neuesten Ghost-Backups und alarmiert per ntfy.
#
#   ./scripts/check-backup-age.sh
#   BACKUP_DIR=/opt/kisium/backups MAX_AGE_H=26 ./scripts/check-backup-age.sh
#
# Cron auf dem Server:
#   0 5 * * * root /opt/backups/check-ghost-backup.sh >> /var/log/ghost-backup-check.log 2>&1
#
# Exit 0 = frisch, Exit 1 = fehlt/zu alt (und ntfy-Nachricht).
set -Eeuo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/kisium/backups}"
TOPIC_FILE="${TOPIC_FILE:-/opt/backups/.ntfy-topic}"
MAX_AGE_H="${MAX_AGE_H:-26}"

[ -r "$TOPIC_FILE" ] || { echo "FEHLER: $TOPIC_FILE fehlt"; exit 1; }
TOPIC="$(tr -d '[:space:]' < "$TOPIC_FILE")"
[ -n "$TOPIC" ] || { echo "FEHLER: ntfy-Thema leer"; exit 1; }

LATEST="$(ls -1t "$BACKUP_DIR"/ghost-db-*.sql.gz 2>/dev/null | head -n 1 || true)"
if [ -z "$LATEST" ]; then
  curl -fsS --max-time 15 -d "Homelab: kein Ghost-Backup gefunden" "https://ntfy.sh/$TOPIC" >/dev/null || true
  echo "FEHLER: kein Ghost-Backup in $BACKUP_DIR"
  exit 1
fi

AGE_H=$(( ( $(date +%s) - $(stat -c %Y "$LATEST") ) / 3600 ))
if [ "$AGE_H" -gt "$MAX_AGE_H" ]; then
  curl -fsS --max-time 15 -d "Homelab: Ghost-Backup ist ${AGE_H}h alt" "https://ntfy.sh/$TOPIC" >/dev/null || true
  echo "FEHLER: Ghost-Backup zu alt: ${AGE_H}h ($LATEST)"
  exit 1
fi

echo "ok: $(basename "$LATEST") (${AGE_H}h)"
