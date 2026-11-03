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
und verschlüsselt sie mit `age`. Das Skript liegt bereit; der erste Lauf auf dem PC steht
noch aus. Details: [offsite-pull.md](offsite-pull.md).

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

## Skripte im Repo

Die Skripte in [`scripts/`](../scripts/) sind die portable, getestete Fassung:

| Skript | Unterschied zur Produktion |
|---|---|
| `backup.sh` | prüft gzip und `CREATE TABLE`, schreibt SHA-256, nutzt `--user` für den Tar |
| `restore-test.sh` | isoliertes Projekt, Datenvergleich mit der Quelle, Aufräumen |
| `health-check.sh` | Container, HTTP, Platte, Zombies, Swap |

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

## Offene Punkte

- [ ] Offsite-Pull auf dem PC einrichten und einmal laufen lassen
- [ ] `age`-Key auf dem PC erzeugen; privaten Key in den Passwortmanager
- [ ] Monitoring für das Ghost-Backup: ntfy im Pull-Skript, serverseitiger Ping fehlt
- [ ] RPO/RTO festlegen: wie viel Datenverlust ist akzeptabel, wie lange darf der Restore dauern?
- [ ] Restore auf einem **anderen** Host testen, nicht nur auf demselben
- [ ] Paperless-Restore-Test gegen eine gepinnte Image-Version laufen lassen, nicht `latest`
- [ ] Aufbewahrung als Policy dokumentieren (7+4 Wochen, 14 Tage)
