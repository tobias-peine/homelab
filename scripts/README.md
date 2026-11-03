# Skripte

| Skript | Aufgabe | Stand |
|---|---|---|
| [`backup.sh`](backup.sh) | MySQL-Dump und Content-Volume sichern, prüfen, aufbewahren | getestet 03.11.2026 |
| [`restore-test.sh`](restore-test.sh) | Sicherung in ein Wegwerf-Projekt zurückspielen und vergleichen | getestet 03.11.2026, 47 s |
| [`health-check.sh`](health-check.sh) | Container, HTTP, Platte, Zombies, Swap prüfen | getestet 03.11.2026 |
| [`pull-backups.sh`](pull-backups.sh) | Offsite-Pull auf den Linux-Rechner, age, Ghost-Alter prüfen | getestet 03.11.2026, 957 MB |
| [`check-backup-age.sh`](check-backup-age.sh) | Ghost-Backup-Alter prüfen, bei > 26 h per ntfy alarmieren | getestet 03.11.2026 |

## In der Produktion

| Skript | Ort | Zeit | Zweck |
|---|---|---|---|
| Ghost-Backup | `/opt/kisium/backup.sh` | täglich 03:00 | MySQL-Dump + `ghost_content` |
| Paperless-Backup | `/opt/backups/paperless-backup.sh` | täglich 03:30 | Postgres, Data, Media, Export, `.env` |
| Paperless-Restore-Test | `/opt/backups/run-restore-test.sh` | täglich 04:00 | Backup in isoliertes Projekt, Prüfungen, Healthchecks-Ping |
| Ghost-Alterscheck | `/opt/backups/check-ghost-backup.sh` | täglich 05:00 | Backup-Alter, ntfy bei > 26 h |
| Ghost-Restore-Test | `scripts/restore-test.sh` | manuell | echte Sicherung in isoliertes Projekt |

Die Produktionsskripte sind älter und einfacher als die Repo-Fassung. Der Ghost-Backup
dort prüft den Dump nicht; [`backup.sh`](backup.sh) hier prüft gzip, `CREATE TABLE` und
schreibt SHA-256.

## Testergebnisse

**Ghost, 03.11.2026** – echtes Backup vom Server, isoliertes Projekt, Port 2370:

```
Quelle:  posts=10 users=1 settings=129
Restore: posts=10 users=1 settings=129
Startseite: HTTP 200
Restore-Test erfolgreich in 47 Sekunden
```

**Paperless, 03.11.2026** – täglicher Lauf um 04:00:

```
Dokumente: 150
Benutzer:  3
Tags:      56
Media:     443
Webserver: HTTP 302
Restore-Test OK, Monitoring-Ping OK
```

## backup.sh

```bash
./scripts/backup.sh
BACKUP_DIR=/srv/backups RETENTION_DAYS=30 ./scripts/backup.sh
```

Sichert `ghost` per `mysqldump --single-transaction` und das Content-Volume per `tar`.
Schreibt zuerst in `.tmp`, prüft gzip und `CREATE TABLE`, benennt erst dann um, legt eine
SHA-256-Datei ab und entfernt Sicherungen, die älter als `RETENTION_DAYS` sind (Default
14). Der Tar-Container läuft mit `--user`, damit die Datei nicht `nobody` gehört.

## restore-test.sh

```bash
./scripts/restore-test.sh
PORT=2371 PROJECT=homelabrestore2 SOURCE_MYSQL=kisium-mysql ./scripts/restore-test.sh
KEEP=1 ./scripts/restore-test.sh     # Testumgebung stehen lassen
```

Entfernt aus der Compose-Datei den festen Projektnamen, `name: kisium-net`,
`container_name` und den Produktions-Port. Bricht ab, wenn `PROJECT=kisium` gesetzt ist,
der Port belegt ist oder die Prüfsummen nicht passen. Vergleicht am Ende Beitrags- und
Benutzerzahl mit der Quelle und räumt auf.

Der Healthcheck bleibt unangetastet. Genau hier lag der Fehler beim ersten manuellen
Versuch: Ein zu breites `sed` löschte die Zeile mit `127.0.0.1:2368` – und damit den
Healthcheck. Das Skript löscht nur den `ports:`-Block.

## health-check.sh

```bash
./scripts/health-check.sh
HTTP_URL=http://127.0.0.1:2368/ ./scripts/health-check.sh
```

Prüft Container-Status und Health, HTTP-Code, Plattenbelegung, Zombie-Prozesse und Swap.
Exit 0 = ok (auch mit Warnungen), Exit 1 = harter Fehler. `LC_ALL=C` ist nötig, weil die
Swap-Zeile je nach Locale „Auslager:“ heißt.

## pull-backups.sh (Linux)

```bash
./scripts/pull-backups.sh
SERVER=<TAILSCALE_IP> ./scripts/pull-backups.sh
```

Zieht Paperless- und Ghost-Backups als ein Tar auf den Linux-Rechner, prüft das Alter des
Ghost-Backups, verschlüsselt lokal mit `age` und schickt bei Fehlern einen ntfy-Ping.
Der Rechner zieht – der Server braucht keinen Zugang hierher. Erster Lauf 03.11.2026:
957 MB, Ghost-Backup 8 h alt, verschlüsselt und wieder entschlüsselt. Details:
[docs/offsite-pull.md](../docs/offsite-pull.md).

Automatisieren mit den Units unter [`systemd/`](systemd/):

```bash
mkdir -p ~/.config/systemd/user
cp ~/dsh-spielwiese/homelab/scripts/systemd/homelab-backup.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now homelab-backup.timer
```

## check-backup-age.sh

```bash
./scripts/check-backup-age.sh
BACKUP_DIR=/opt/kisium/backups MAX_AGE_H=26 ./scripts/check-backup-age.sh
```

Prüft das neueste `ghost-db-*.sql.gz`; bei mehr als 26 Stunden oder fehlendem Backup
sendet es eine ntfy-Nachricht und endet mit 1. Auf dem Server liegt es als
`/opt/backups/check-ghost-backup.sh`, Cron 05:00. Test am 03.11.: normal `ok (8h)`,
künstlich 72 h → Alarm.

## Anforderungen

- `set -Eeuo pipefail` – ein Fehler beendet den Lauf.
- Zugangsdaten nur aus der Umgebung oder `.env`, nie als Argument.
- Prüfungen im selben Skript, nicht in der Erinnerung.
- Exit-Code 0 nur, wenn die harten Prüfungen bestanden sind.
- `shellcheck -S warning` ohne Befund (v0.10.0).

## Offen

- [ ] systemd-Timer auf dem Linux-Rechner installieren
- [ ] `age`-Private-Key zusätzlich in den Passwortmanager legen
- [ ] Paperless-Restore-Test gegen eine gepinnte Image-Version
