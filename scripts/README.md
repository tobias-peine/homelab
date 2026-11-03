# Skripte

| Skript | Aufgabe | Stand |
|---|---|---|
| [`backup.sh`](backup.sh) | MySQL-Dump und Content-Volume sichern, prüfen, aufbewahren | getestet 03.11.2026 |
| [`restore-test.sh`](restore-test.sh) | Sicherung in ein Wegwerf-Projekt zurückspielen und vergleichen | getestet 03.11.2026, 47 s |
| [`health-check.sh`](health-check.sh) | Container, HTTP, Platte, Zombies, Swap prüfen | getestet 03.11.2026 |
| [`pull-backups.ps1`](pull-backups.ps1) | Offsite-Pull auf den PC, age-Verschlüsselung, Ghost-Alter prüfen | Skript fertig, Lauf offen |

## In der Produktion

| Skript | Ort | Zeit | Zweck |
|---|---|---|---|
| Ghost-Backup | `/opt/kisium/backup.sh` | täglich 03:00 | MySQL-Dump + `ghost_content` |
| Paperless-Backup | `/opt/backups/paperless-backup.sh` | täglich 03:30 | Postgres, Data, Media, Export, `.env` |
| Paperless-Restore-Test | `/opt/backups/run-restore-test.sh` | täglich 04:00 | Backup in isoliertes Projekt, Prüfungen, Healthchecks-Ping |
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

## pull-backups.ps1 (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File .\pull-backups.ps1 -Server <host>
```

Zieht Paperless- und Ghost-Backups als ein Tar auf den PC, prüft das Alter des
Ghost-Backups, verschlüsselt lokal mit `age` und schickt bei Fehlern einen ntfy-Ping.
Der PC zieht – der Server braucht keinen Zugang zum PC. Details:
[docs/offsite-pull.md](../docs/offsite-pull.md).

## Anforderungen

- `set -Eeuo pipefail` – ein Fehler beendet den Lauf.
- Zugangsdaten nur aus der Umgebung oder `.env`, nie als Argument.
- Prüfungen im selben Skript, nicht in der Erinnerung.
- Exit-Code 0 nur, wenn die harten Prüfungen bestanden sind.
- `shellcheck -S warning` ohne Befund (v0.10.0).

## Offen

- [ ] Offsite-Pull auf dem PC einrichten und einmal laufen lassen
- [ ] `age`-Key auf dem PC erzeugen, privaten Key in den Passwortmanager
- [ ] Ghost-Monitoring serverseitig (ntfy im Pull-Skript vorhanden)
- [ ] Paperless-Restore-Test gegen eine gepinnte Image-Version
