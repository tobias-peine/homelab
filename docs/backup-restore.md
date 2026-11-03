# Backup und Restore

## Strategie

Gesichert werden zwei Dinge: die MySQL-Datenbank als logischer Dump und das
Ghost-Content-Volume als Archiv. Beides zusammen reicht, um den Blog auf einer leeren
Maschine wieder aufzubauen – der Dump enthält Beiträge, Einstellungen und Mitglieder,
das Volume Themes, Bilder und Uploads. Ein Backup zählt erst, wenn der Restore
mindestens einmal auf einem separaten Ziel durchgespielt wurde.

## Stand

| Punkt | Stand |
|---|---|
| Backup-Skript | [`scripts/backup.sh`](../scripts/backup.sh) – getestet am 03.11.2026 |
| Restore-Test | [`scripts/restore-test.sh`](../scripts/restore-test.sh) – 03.11.2026, 43 s, lokale Testinstanz |
| Zeitplan | `TODO` (manuell? cron? systemd-Timer?) |
| Ziel / Ablage | `TODO` (lokal? zweiter Host? Object Storage?) |
| Aufbewahrung | 14 Tage als Skript-Default (`RETENTION_DAYS`), Entscheidung offen |
| Verschlüsselung | `TODO` |
| Überwachung | `TODO` (wer merkt, dass ein Backup fehlgeschlagen ist?) |
| Produktions-Restore | `TODO` – bisher nur gegen eine lokale Testinstanz gelaufen |
| RPO / RTO | `TODO` (wie viel Datenverlust ist akzeptabel, wie lange darf die Wiederherstellung dauern?) |

## Automatisierter Restore-Test

```bash
./scripts/restore-test.sh
```

Das Skript spielt die neueste Sicherung in ein **eigenes Compose-Projekt** zurück:
eigenes Netz, eigene Volumes, eigener Port, keine Container-Namen aus der Produktion.
Es bricht ab, wenn `PROJECT=kisium` gesetzt ist, der Port belegt ist oder die
Prüfsummen nicht passen. Am Ende vergleicht es Beitrags-, Benutzer- und
Einstellungszahl mit der Quelle und räumt die Testumgebung wieder ab.

```bash
# Anderer Port / anderes Projekt / andere Quelle
PORT=2371 PROJECT=homelabrestore2 SOURCE_MYSQL=kisium-mysql ./scripts/restore-test.sh

# Testumgebung zur Fehlersuche stehen lassen
KEEP=1 ./scripts/restore-test.sh
```

Erwartete Ausgabe (gekürzt):

```
Prüfsummen ok
mysql: healthy
Importiere ghost-db-….sql.gz
Spiele ghost-content-….tar.gz zurück
ghost: healthy
Startseite: HTTP 200
Quelle:  posts=2 users=1 settings=129
Restore: posts=2 users=1 settings=129
Restore-Test erfolgreich in 43 Sekunden
```

## Testergebnis vom 03.11.2026

| | |
|---|---|
| Umgebung | lokaler Docker-Host, dieselbe Compose-Datei, Ghost 6.73.0, MySQL 8.4.13 |
| Quelle | Testinstanz mit 2 Beiträgen, 1 Benutzer, 129 Einstellungen |
| Sicherung | 29 KB Datenbank-Dump, 3,7 KB Content-Archiv |
| Dauer | 43 Sekunden (MySQL-Start, Import, Content, Ghost-Start, Prüfungen) |
| Startseite | HTTP 200 |
| Datenvergleich | posts 2 = 2, users 1 = 1, settings 129 = 129 |
| Prüfsummen | ok |
| Aufräumen | `docker compose … down -v`, keine Reste |

**Einschränkung:** Das war eine lokale Wegwerf-Instanz, nicht die Produktion. Der
Ablauf ist damit belegt, die Wiederherstellung der echten Daten steht noch aus. Der
Test beweist nicht, dass das Produktions-Backup vollständig ist – nur, dass das
Verfahren funktioniert und die Prüfungen anschlagen.

## Manueller Ablauf

Falls das Skript nicht läuft oder ein Schritt nachvollzogen werden soll:

1. **Test-Compose erzeugen.** Projektname, Netzname (`kisium-net`), `container_name`
   und Port-Mapping entfernen. Der Healthcheck bleibt – er prüft im Container auf
   `127.0.0.1:2368`.
2. **Test-Umgebung anlegen.** Eigenes `.env` mit `GHOST_URL=http://localhost:<PORT>`
   und neuen Datenbank-Passwörtern.
3. **MySQL starten und warten.** `docker compose -p <projekt> up -d mysql`, dann auf
   `healthy` warten – nicht auf gut Glück `sleep`.
4. **Dump importieren.** `zcat <dump>.sql.gz | docker compose … exec -T mysql sh -c
   'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ghost'`.
5. **Content zurückspielen.** Volume `<projekt>_ghost_content` anlegen, auf die
   Ghost-UID chownen (1000 im offiziellen Image), als diese UID entpacken.
6. **Ghost starten und prüfen.** `up -d ghost`, auf `healthy` warten, dann HTTP 200,
   Beitrags-/Benutzerzahl und ein Bild prüfen.
7. **Aufräumen.** `docker compose -p <projekt> down -v`. Der Dump enthält
   personenbezogene Daten – Testdateien löschen.

| Prüfung | Erwartung |
|---|---|
| Container | `healthy`, nicht nur `running` |
| Startseite | `200` |
| Beitragsanzahl | gleich der Quelle |
| Benutzerzahl | gleich der Quelle |
| Content | Theme und Bilder vorhanden, ein Bild lädt |
| Login | `/ghost/` erreichbar |

## Was schiefging

**1. `zgrep -q` unter `pipefail`.**
Die Prüfung „enthält der Dump eine `CREATE TABLE`?“ schlug fehl, obwohl 101 Tabellen im
Dump standen. `grep -q` beendet die Pipe nach dem ersten Treffer, `zcat` bekommt
SIGPIPE, und `pipefail` wertet die Pipe als Fehler. Behoben mit `grep -c` (liest bis
zum Ende) und einer Zählung.

**2. Ein zu breites `sed` löschte den Healthcheck.**
Der Ghost-Healthcheck enthält die Zeile `http://127.0.0.1:2368/`. Ein `sed`, das alle
Zeilen mit `127.0.0.1:2368` entfernte, nahm den Healthcheck mit – der Container lief,
meldete aber nie `healthy`. Das Skript löscht jetzt nur den `ports:`-Block.

**3. `Permission denied` beim Zurückspielen des Content-Volumes.**
Das frisch angelegte Volume gehört root; das Entpacken als uid 1000 scheiterte. Lösung:
Volume-Root auf die Ghost-UID chownen und als diese UID entpacken. Auf dem Server läuft
der Admin als root – dort wäre der Fehler nicht aufgetreten, was ihn besonders tückisch
macht.

**4. Das Testprojekt wäre im Produktionsnetz gelandet.**
Die Compose-Datei setzt `name: kisium-net` fest. Ein zweites Projekt mit derselben Datei
hängt damit im selben Netz wie die Produktion – Docker warnt, verhindert es aber nicht.
Das Test-Compose entfernt die Zeile; das Projekt bekommt `<projekt>_kisium`.

**5. Der Content-Tar gehörte `nobody`.**
Ohne `--user` schrieb der Alpine-Container die Datei als `nobody:nogroup`. Mit
`--user "$(id -u):$(id -g)"` gehört sie dem aufrufenden Benutzer.

## Offene Punkte

- [ ] Restore einmal gegen die echte Produktion durchführen und hier protokollieren
- [ ] Zeitplan und Ablage festlegen
- [ ] Aufbewahrung entscheiden (Skript-Default: 14 Tage)
- [ ] Verschlüsselung der Sicherungen
- [ ] Warnung, wenn das letzte Backup älter als 48 Stunden ist
- [ ] Prüfen, ob der Dump ohne das Content-Volume vollständig ist (und umgekehrt)
