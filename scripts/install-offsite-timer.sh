#!/usr/bin/env bash
# Installiert den systemd-User-Timer für den Offsite-Pull auf dem Linux-Host.
#
#   ./scripts/install-offsite-timer.sh
#
# Nicht im dsh-Container ausführen: dort gibt es kein user-systemd.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! timeout 5 systemctl --user show-environment >/dev/null 2>&1; then
  echo "FEHLER: user-systemd nicht erreichbar."
  echo "Auf dem Linux-Host ausführen, nicht im dsh-Container."
  exit 1
fi

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"
cp "$SCRIPT_DIR/systemd/homelab-backup.service" "$SCRIPT_DIR/systemd/homelab-backup.timer" "$UNIT_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now homelab-backup.timer
systemctl --user list-timers homelab-backup.timer --no-pager

echo
echo "age-Key:  $HOME/dsh-spielwiese/.offsite/age.key  -> Passwortmanager"
if [ -f "$HOME/dsh-spielwiese/.offsite/ntfy.topic" ]; then
  echo "ntfy:     https://ntfy.sh/$(tr -d '[:space:]' < "$HOME/dsh-spielwiese/.offsite/ntfy.topic")"
fi
echo "Ohne Login:  sudo loginctl enable-linger $USER"
