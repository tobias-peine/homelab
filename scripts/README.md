# Skripte

| Skript | Aufgabe | Stand |
|---|---|---|
| [`backup.sh`](backup.sh) | MySQL-Dump und Content-Volume sichern, prüfen, aufbewahren | getestet 03.11.2026 |
| [`restore-test.sh`](restore-test.sh) | Sicherung in ein Wegwerf-Projekt zurückspielen und vergleichen | getestet 03.11.2026, 43 s |
| [`health-check.sh`](health-check.sh) | Container, HTTP, Platte, Zombies, Swap prüfen | getestet 03.11.2026 |

## backup.sh

```bash
./scripts/backup.sh
BACKUP_DIR=/srv/backups RETENTION_DAYS=30 ./scripts/backup.sh
```

Sichert `ghost` per `mysqldump --single-transaction` und das Content-Volume per
`tar`. Schreibt zuerst in `.tmp`, prüft gzip und `CREATE TABLE`, benennt erst dann um.
Legt eine SHA-256-Datei ab und entfernt Sicherungen, die älter als `RETENTION_DAYS`
sind (Default 14).

Beim Test: 29 KB Dump, 3,7 KB Content, Prüfsummen ok. Die Content-Datei gehörte
zunächst `nobody` – behoben mit `--user "$(id -u):$(id -g)"`.

## restore-test.sh

```bash
./scripts/restore-test.sh
PORT=2371 PROJECT=homelabrestore2 SOURCE_MYSQL=kisium-mysql ./scripts/restore-test.sh
KEEP=1 ./scripts/restore-test.sh     # Testumgebung stehen lassen
```

Spielt die neueste Sicherung in ein eigenes Compose-Projekt: eigenes Netz, eigene
Volumes, eigener Port. Entfernt dafür `name: kisium-net`, `container_name` und den
Produktions-Port aus der Compose-Datei. Bricht ab, wenn `PROJECT=kisium` gesetzt ist,
der Port belegt ist oder die Prüfsummen nicht passen. Vergleicht am Ende
Beitrags- und Benutzerzahl mit der Quelle und räumt auf.

Beim Test: 43 Sekunden, HTTP 200, posts 2 = 2, users 1 = 1, settings 129 = 129.

**Wichtig:** Das ist ein Test gegen eine Wegwerf-Instanz, kein Produktions-Restore.

## health-check.sh

```bash
./scripts/health-check.sh
HTTP_URL=http://127.0.0.1:2368/ ./scripts/health-check.sh
```

Prüft Container-Status und Health, HTTP-Code, Plattenbelegung, Zombie-Prozesse und
Swap. Exit 0 = ok (auch mit Warnungen), Exit 1 = harter Fehler (Container aus, HTTP
nicht 200).

Beim Test: beide Container healthy, HTTP 200, Platte 23 %, keine Zombies, Swap 0 %.
Die Swap-Zeile heißt je nach Locale „Auslager:“ – deshalb `LC_ALL=C` im Skript.

## Anforderungen

- `set -Eeuo pipefail` – ein Fehler beendet den Lauf.
- Zugangsdaten nur aus der Umgebung oder `.env`, nie als Argument.
- Prüfungen im selben Skript, nicht in der Erinnerung.
- Exit-Code 0 nur, wenn die harten Prüfungen bestanden sind.
- `shellcheck -S warning` ohne Befund (v0.10.0).

## Offen

- [ ] Zeitplan (cron oder systemd-Timer) und Ablage festlegen
- [ ] Benachrichtigung bei Fehlschlag
- [ ] Verschlüsselung der Sicherungen
