# Backup und Restore

Zwei Stacks, zwei Sicherungen, zwei Wiederherstellungswege. Beide wurden am 03.11.2026
gegen eine Wegwerf-Instanz getestet – nicht gegen die Produktion.

## Überblick

| Sicherung | Zeit | Inhalt | Aufbewahrung | Restore-Test |
|---|---|---|---|---|
| Paperless | täglich 03:30 | PostgreSQL-Dump, Data-/Media-Volume, Export, `.env`, Compose | 7 Tage + 4 Wochen | täglich 04:00 |
| Ghost | täglich 03:00 | MySQL-Dump, `ghost_content` | 14 Tage | manuell / `scripts/restore-test.sh` |

Beide Sicherungen liegen lokal unter `/opt/backups/paperless` bzw. `/opt/kisium/backups`.
Für Offsite zieht der Linux-Rechner die Archive per [`scripts/pull-backups.sh`](../scripts/pull-backups.sh)
und verschlüsselt sie mit `age`. Erster Lauf am 03.11.2026: 957 MB, Ghost-Backup 8 h alt,
verschlüsselt (959 MB) und mit dem Key wieder entschlüsselt. Zweiter Lauf über Tailscale
(Port 22 öffentlich zu): 957 MB in 5:51. Details: [offsite-pull.md](offsite-pull.md).

## Paperless

**Skript:** `/opt/backups/paperless-backup.sh`, Cron `30 3 * * *`.

Es sichert:

- PostgreSQL mit `pg_dump -Fc`
- die Volumes `homeserver_paperless_data` und `_media`
- den Export-Ordner `/opt/paperless/export`
- `.env` und beide Compose-Dateien
- alles als ein Tarball, `chmod 600` (enthält Zugangsdaten)

Rotation: sieben Tages-Backups, sonntags zusätzlich ein Wochen-Backup, vier Wochen
Aufbewahrung. Ein Lauf erzeugt etwa 148 MB und dauert rund 20 Sekunden.

**Restore-Test:** `/opt/backups/restore-test.sh`, aufgerufen vom Wrapper
`/opt/backups/run-restore-test.sh` um 04:00.

Der Test entpackt das Tarball nach `/tmp/pl-restore-test`, startet ein eigenes
Compose-Projekt `pl-restore-test` (Postgres, Redis, Paperless) auf Port 8001, spielt
den Dump ein und prüft:

- Dokumente, Benutzer und Tags in der Datenbank
- Anzahl der Media-Dateien
- HTTP-Antwort des Webservers

Danach wird das Projekt mit `down -v` entfernt. Bei Erfolg sendet der Wrapper einen Ping
an Healthchecks.io; bei Fehler bewusst **keinen**, damit der Check in den Grace-Modus
läuft und alarmiert.

**Ergebnis 03.11.2026:**

```
Dokumente: 150
Benutzer:  3
Tags:      56
Media:     443
Webserver: HTTP 302
Restore-Test OK, Monitoring-Ping OK
```

## Ghost

**Skript:** `/opt/kisium/backup.sh`, Cron `0 3 * * *` (seit 03.11.2026).

Es sichert:

- MySQL mit `mysqldump --single-transaction --quick --routines --events`
- das Volume `kisium_ghost_content` per `tar`
- Aufbewahrung: 14 Tage (`KEEP_DAYS`)

Ein Lauf am 03.11.2026 ergab 249 KB Datenbank-Dump und 4,6 MB Content-Archiv.

**Restore-Test:** Das Skript im Repo, [`scripts/restore-test.sh`](../scripts/restore-test.sh),
gegen das echte Backup auf dem Server:

```bash
sudo env COMPOSE_FILE=/opt/kisium/docker-compose.yml \
  BACKUP_DIR=/opt/kisium/backups SOURCE_MYSQL=kisium-mysql \
  PROJECT=ghostrestoretest PORT=2370 bash restore-test.sh
```

Das Skript entfernt aus der Compose-Datei den festen Projektnamen, das feste Netz
`kisium-net`, die `container_name`-Einträge und das Port-Mapping. Es erzeugt ein eigenes
Netz, eigene Volumes und einen eigenen Port. Der Healthcheck bleibt unangetastet – er
prüft im Container auf `127.0.0.1:2368`.

**Ergebnis 03.11.2026:**

```
mysql: healthy
Importiere ghost-db-20261103-011345.sql.gz
Spiele ghost-content-20261103-011345.tar.gz zurück
ghost: healthy
Startseite: HTTP 200
Quelle:  posts=10 users=1 settings=129
Restore: posts=10 users=1 settings=129
Restore-Test erfolgreich in 47 Sekunden
```

Keine Reste: keine Testcontainer, -volumes oder -netze nach dem Lauf.

**Monitoring:** `/opt/backups/check-ghost-backup.sh` läuft täglich um 05:00. Es prüft
DB-Dump und Content-Archiv: fehlt eines, ist der Content älter als der DB-Dump oder ist
das Backup älter als 26 Stunden, kommt eine ntfy-Nachricht. Test am 03.11.: normal `ok`,
ohne Content und mit zu altem Content jeweils Alarm.

## Skripte im Repo

Die Skripte in [`scripts/`](../scripts/) sind die portable, getestete Fassung:

| Skript | Unterschied zur Produktion |
|---|---|
| `backup.sh` | prüft gzip und `CREATE TABLE`, schreibt SHA-256, nutzt `--user` für den Tar |
| `restore-test.sh` | isoliertes Projekt, Datenvergleich mit der Quelle, Aufräumen |
| `health-check.sh` | Container, HTTP, Platte, Zombies, Swap |
| `check-backup-age.sh` | prüft das Ghost-Backup-Alter, ntfy bei > 26 h |

Die Produktionsskripte unter `/opt/` sind älter und einfacher. Der Ghost-Backup dort
prüft den Dump nicht – das Repo-Skript schon.

## Was schiefging

**1. Der Restore-Test hat zwei Tage lang nichts getestet.**
`run-restore-test.sh` ermittelte das neueste Backup, übergab den Pfad aber nicht an
`restore-test.sh`. Das Skript fiel auf seinen hart codierten Default zurück – ein am
25.10. gelöschtes Backup. Seit dem 01.11. stand im Log „Backup nicht gefunden“, der
Healthchecks-Ping blieb aus. Behoben am 03.11. durch Übergabe von `"$LATEST"`.

**2. Das Ghost-Backup war nicht eingeplant.**
`/opt/kisium/backup.sh` existierte, lief aber in keinem Cron. Der Blog wäre im
Fehlerfall ohne Sicherung dagestanden. Seit 03.11. läuft es täglich um 03:00.

**3. Der Ghost-Healthcheck erzeugte Zombies.**
`wget --spider` folgte dem `301` auf `https://127.0.0.1:2368` und sprach TLS mit einem
HTTP-Port. Jeder Fehlversuch hinterließ einen `ssl_client`-Zombie; nach elf Stunden
waren es 1.354. `nc -z` und `init: true` haben beides behoben (0 Zombies).

**4. Ein `sed`-Ersatz mit `&` hat die getestete Datei zerstört.**
Beim Korrigieren des Wrappers wurde `&` in der Ersetzung als „der ganze Treffer“
interpretiert. Die Zeile wurde unbrauchbar, und ein Folgelauf hat `restore-test.sh`
überschrieben. Die Datei wurde aus `.bak-20261025` wiederhergestellt (Hash identisch mit
`/opt/restore-test/restore-test.sh`). Lehre: `&` in sed-Ersetzungen escapen (`\&`) und
vor dem Editieren eine Kopie ziehen.

## RPO, RTO und Aufbewahrung

| | Paperless | Ghost | Offsite |
|---|---|---|---|
| RPO (Ziel) | 24 h | 24 h | 24 h (Pull 05:30) |
| RTO technisch | 43 s (gemessen) | 47 s (gemessen) | Download + Entschlüsselung, ~6 min (gemessen) |
| Aufbewahrung | 7 täglich + 4 wöchentlich | 14 täglich | 7 Archive (Service) |
| Ablage | `/opt/backups/paperless` | `/opt/kisium/backups` | `~/dsh-spielwiese/.offsite/backups` |

- **RPO** = maximaler Datenverlust. Gesichert wird täglich 03:00/03:30; ein Ausfall kurz
  vor dem Lauf kostet bis zu 24 Stunden.
- **RTO** = technische Wiederherstellung. 43 s und 47 s sind die gemessenen
  Restore-Tests. Erkennung und Entscheidung sind nicht gemessen; realistisch sind
  30–60 Minuten bis zur bewussten Wiederherstellung.
- **Offsite-RPO** hängt am Linux-Host: Ist er aus, wird der Pull beim nächsten Start
  nachgeholt (`Persistent=true`), der Offsite-Stand ist dann älter.
- **Aufbewahrung:** Paperless 7 Tage + 4 Wochen, Ghost 14 Tage, Offsite 7 Archive.
  Jedes Offsite-Archiv enthält alle Server-Backups und ist deshalb ~1 GB.
- **Nicht abgedeckt:** Änderungen zwischen zwei Backups, Totalverlust des Linux-Hosts
  ohne age-Key, Restore auf fremder Hardware.

## Offene Punkte

- [x] systemd-Timer auf dem Linux-Rechner einrichten (03.11.2026)
- [x] `age`-Private-Key zusätzlich in den Passwortmanager kopieren (03.11.2026)
- [x] RPO/RTO festlegen (Werte im Abschnitt „RPO, RTO und Aufbewahrung“)
- [ ] Restore auf einem **anderen** Host testen, nicht nur auf demselben
- [ ] Paperless-Restore-Test gegen eine gepinnte Image-Version laufen lassen, nicht `latest`
- [x] Aufbewahrung als Policy dokumentieren (7+4 Wochen, 14 Tage, 7 Offsite-Archive)
- [ ] Dritte Kopie (3-2-1): VPS und Linux-Host sind zwei Kopien
