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
| Backup-Skript | nicht im Repo (`TODO`: [scripts/](../scripts/)) |
| Zeitplan | `TODO` (manuell? cron? systemd-Timer?) |
| Ziel / Ablage | `TODO` (lokal? zweiter Host? Object Storage?) |
| Aufbewahrung | `TODO` (wie viele Tage, wie viele Generationen?) |
| Verschlüsselung | `TODO` |
| Überwachung | `TODO` (wer merkt, dass ein Backup fehlgeschlagen ist?) |
| Letzter Restore-Test | `TODO` (Datum, Dauer, Ergebnis) |
| RPO / RTO | `TODO` (wie viel Datenverlust ist akzeptabel, wie lange darf die Wiederherstellung dauern?) |

Solange diese Tabelle Lücken hat, ist der Betrieb nicht belegt. Die folgenden Befehle
sind der Ablauf, mit dem die Lücken geschlossen werden – keine Behauptung, dass er
bereits protokolliert wurde.

## Backup erzeugen

```bash
# 1) Datenbank – logischer Dump, konsistent ohne Schreibsperre
docker exec kisium-mysql sh -c \
  'exec mysqldump --single-transaction --routines --triggers \
   -uroot -p"$MYSQL_ROOT_PASSWORD" ghost' \
  > "ghost-db-$(date +%F).sql"

# 2) Content-Volume – Themes, Bilder, Uploads
docker run --rm \
  -v kisium_ghost_content:/data:ro \
  -v "$PWD":/backup \
  alpine tar czf "/backup/ghost-content-$(date +%F).tar.gz" -C /data .

# 3) Kontrolle: Dateien nicht leer, Dump lesbar
ls -lh ghost-db-*.sql ghost-content-*.tar.gz
grep -c 'CREATE TABLE' ghost-db-*.sql
```

Erwartung: beide Dateien existieren, der Dump enthält `CREATE TABLE`-Zeilen, das Archiv
lässt sich mit `tar tzf` auflisten. Ein Backup ohne diese Kontrolle ist nur eine Datei.

## Restore-Test

Ziel: den Blog aus den Sicherungen auf einem **separaten** Compose-Projekt
wiederherstellen, ohne den laufenden Betrieb anzufassen. Der Test läuft auf demselben
Host, aber mit eigenem Projektnamen, eigenen Containern und einem anderen Port.

### 1. Wegwerf-Umgebung vorbereiten

```bash
mkdir -p /tmp/restore-test && cd /tmp/restore-test
cp /pfad/zu/compose/docker-compose.yml .
cp /pfad/zu/compose/.env.example .env
```

In `.env` eintragen: `GHOST_URL=http://localhost:2369`, dazu dieselben
Datenbank-Passwörter wie in der Produktion (der Dump wird sonst nicht importierbar).

`docker-compose.override.yml` daneben legen, damit nichts kollidiert:

```yaml
services:
  ghost:
    container_name: restore-ghost
    ports:
      - "127.0.0.1:2369:2368"
  mysql:
    container_name: restore-mysql
```

### 2. Nur die Datenbank starten

```bash
docker compose -p restore-test up -d mysql
docker compose -p restore-test ps
```

Erwartung: `restore-mysql` ist `running (healthy)`. Auf `healthy` warten, nicht raten.

### 3. Dump importieren

```bash
docker exec -i restore-mysql sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ghost' \
  < /pfad/zu/ghost-db-2026-11-03.sql
```

Erwartung: kein Fehler, Exit-Code 0. Bei „Table already exists“ ist die Datenbank nicht
leer – dann Umgebung neu aufsetzen, nicht den Import erzwingen.

### 4. Content-Volume zurückspielen

```bash
docker run --rm \
  -v restore-test_ghost_content:/data \
  -v /tmp/restore-test:/backup \
  alpine sh -c 'cd /data && tar xzf /backup/ghost-content-2026-11-03.tar.gz'
```

Erwartung: Exit-Code 0, danach liegt unter `/data` u. a. `images/` und `themes/`.

### 5. Ghost starten und prüfen

```bash
docker compose -p restore-test up -d ghost
docker compose -p restore-test logs --tail=50 ghost
```

| Prüfung | Befehl | Erwartung |
|---|---|---|
| Startet Ghost? | `docker compose -p restore-test ps` | `restore-ghost` running, health `healthy` |
| Startseite | `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:2369/` | `200` |
| Beitragsanzahl | `SELECT COUNT(*) FROM posts WHERE status='published';` im Test | gleich der Produktion |
| Bild lädt | eine Bild-URL aus der Produktion auf Port 2369 aufrufen | `200`, sichtbares Bild |
| Login | `http://127.0.0.1:2369/ghost/` im Browser | Login möglich, Beiträge sichtbar |
| Dauer | `time` um Schritt 2–5 | notieren – Referenzwert fehlt noch |

Die Beitragsanzahl vergleichen, nicht schätzen:

```bash
docker exec restore-mysql sh -c \
  'exec mysql -N -uroot -p"$MYSQL_ROOT_PASSWORD" ghost \
   -e "SELECT COUNT(*) FROM posts WHERE status=\"published\";"'
```

### 6. Aufräumen

```bash
docker compose -p restore-test down -v
rm -rf /tmp/restore-test
```

Der Dump enthält personenbezogene Daten (Mitglieder, Kommentare). Nach dem Test löschen,
nicht liegen lassen.

## Was schiefging

Der erste „Backup-Test“ war kein technischer Fehler, sondern ein Denkfehler: Es gab ein
Skript, das jede Nacht ohne Fehlermeldung durchlief – und deshalb für Sicherheit gehalten
wurde. Zurückgespielt wurde nie etwas. Die Erkenntnis steht im Blogartikel
[Mein Homelab – drei teure Fehler](https://kisium.de/mein-homelab/).

Konkrete Fehlermeldungen aus einem späteren, protokollierten Lauf sind nicht dokumentiert.
Dieser Abschnitt bleibt offen, bis der Test mit Datum und Messwerten durchgeführt ist.

| Lauf | Datum | Dauer | Ergebnis | Auffälligkeit |
|---|---|---|---|---|
| 1 | `TODO` | `TODO` | `TODO` | `TODO` |

## Offene Punkte

- [ ] Backup-Skript mit `set -euo pipefail`, Logging und Exit-Code schreiben
- [ ] Zeitplan und Ablage festlegen, inklusive Aufbewahrung
- [ ] Restore-Test einmal vollständig durchführen und die Tabelle oben füllen
- [ ] Prüfen, ob der Dump ohne das Content-Volume vollständig ist (und umgekehrt)
- [ ] Warnung einbauen, wenn ein Backup älter als 48 Stunden ist
