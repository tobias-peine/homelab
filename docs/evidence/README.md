# Belege

Rohausgaben vom 03.11.2026, gekürzt und redigiert: Öffentliche IPv4-Adressen sind `<IP>`; `127.0.0.1` und `0.0.0.0` bleiben als Bindungsangabe,
die Domain ist `<DEINE_DOMAIN>`. Keine Tokens, Passwörter oder Keys.

| Datei | Inhalt |
|---|---|
| `sshd.txt` | `permitrootlogin no`, `passwordauthentication no`, `pubkeyauthentication yes`, `maxauthtries 6` |
| `ufw.txt` | eingehend nur 80/443 und `tailscale0` |
| `containers.txt` | zehn laufende Container |
| `restore-test.txt` | Paperless-Restore-Tests vom 25.10. bis 03.11., letzter Lauf `OK` um 04:02 |
| `kisium-backup.txt` | Ghost-Backup am 03.11. um 03:00: DB und Content |
| `paperless-backup.txt` | Paperless-Backup am 03.11. um 03:30 |
| `ghost-check.txt` | Alterscheck: `ok`, 9 h |

Die Dateien sind Belege, keine vollständigen Audit-Logs. Wer die Werte selbst
nachrechnen will, findet die Befehle in [../hardening.md](../hardening.md) und
[../backup-restore.md](../backup-restore.md).
