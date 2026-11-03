# Skripte

Backup, Restore-Test und Health-Check – hier ist noch keins davon. Dieser Ordner
beschreibt, was hinein gehört und welche Bedingungen ein Skript erfüllen muss, bevor es
als „funktioniert“ gilt.

## Geplant

| Skript | Aufgabe | Status |
|---|---|---|
| `backup.sh` | MySQL-Dump und Content-Volume sichern, prüfen, ablegen | `TODO` |
| `restore-test.sh` | Sicherung in ein Wegwerf-Projekt zurückspielen und prüfen | `TODO` |
| `health-check.sh` | Container-Status, HTTP-Status, Plattenplatz, Zombies | `TODO` |

## Anforderungen

- `set -euo pipefail` – ein Fehler muss den Lauf beenden, nicht überspringen.
- Zugangsdaten nur aus Umgebungsvariablen oder einer Datei mit `chmod 600`, nie als
  Argument (Argumente stehen in der Prozessliste und im Shell-Verlauf).
- Jeder Lauf schreibt eine Zeile mit Zeitstempel, Ergebnis und Dauer in ein Log.
- Exit-Code 0 nur, wenn alle Prüfungen bestanden sind.
- Wiederholbar: ein zweiter Lauf darf nichts kaputt machen.
- Nach dem Backup: prüfen, dass die Datei nicht leer ist und der Dump lesbar ist.

## Warum das nicht schnell hingeschrieben ist

Ein Backup-Skript, das nur `mysqldump` aufruft, sieht richtig aus und ist es oft nicht:
Fehlt der Dump wegen eines falschen Passworts, ist die Datei trotzdem da – nur leer.
Deshalb gehört die Kontrolle in dasselbe Skript, nicht in die Erinnerung.

## TODO

- [ ] `backup.sh` schreiben und gegen die laufende Instanz testen
- [ ] `restore-test.sh` schreiben (Ablauf: [docs/backup-restore.md](../docs/backup-restore.md))
- [ ] `health-check.sh` schreiben (Zombies, Swap, HTTP-Status)
- [ ] Zeitplan festlegen (cron oder systemd-Timer) und dokumentieren
- [ ] Benachrichtigung bei Fehlschlag einbauen
