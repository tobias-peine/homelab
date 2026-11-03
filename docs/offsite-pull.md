# Offsite auf den PC

Der PC **zieht** die Sicherungen; der Server braucht keinen Zugang zum PC. Ein Lauf holt
Paperless- und Ghost-Backups als ein Tar, verschlüsselt es lokal mit `age` und prüft, ob
das Ghost-Backup zu alt ist.

## Was übertragen wird

| Quelle auf dem Server | Inhalt |
|---|---|
| `/opt/backups/paperless` | Paperless-Tarballs (DB, Data, Media, Export, `.env`) |
| `/opt/kisium/backups` | Ghost-DB-Dump und Content-Archiv |

Der Server packt beide Verzeichnisse mit `sudo tar` in `/tmp`, `scp` holt das Archiv,
danach wird die temporäre Datei gelöscht.

## Voraussetzungen

- OpenSSH-Client unter Windows (`ssh`, `scp`, `tar` sind ab Windows 10 vorhanden)
- [`age`](https://github.com/FiloSottile/age): `winget install FiloSottile.age`
- Dein SSH-Key liegt in `%USERPROFILE%\.ssh\id_ed25519` und ist in
  `/home/admin/.ssh/authorized_keys` eingetragen
- `admin` hat NOPASSWD-sudo (für `tar`/`chown` auf dem Server)

## Einmal einrichten

1. Skript nach `C:\Tools\pull-backups.ps1` kopieren.
2. Zielordner anlegen, z. B. `D:\Backups\homelab`.
3. ntfy-Thema wählen (frei erfundener String, z. B. `homelab-ghost-7f3a9c`) und in
   `D:\Backups\homelab\ntfy.topic` speichern. Bei ntfy.sh abonnieren:
   `https://ntfy.sh/<thema>` (App oder Browser).
4. Einmal manuell laufen lassen:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Tools\pull-backups.ps1 `
  -Server vps2662496.fastwebserver.de
```

Beim ersten Lauf entsteht `D:\Backups\homelab\age.key`. Diesen privaten Schlüssel
**sofort in den Passwortmanager** legen. Geht er verloren, sind die verschlüsselten
Offsite-Backups nicht mehr lesbar.

## Prüfen

```powershell
Get-ChildItem D:\Backups\homelab
Get-Content D:\Backups\homelab\pull.log -Tail 20
```

Erwartet: `homelab-<datum>.tgz.age`, eine Größe im Bereich der Server-Backups und im Log
`OK`.

## Verschlüsselung

- `age` verschlüsselt das Tar auf dem PC; der private Key bleibt auf dem PC.
- Der Server sieht den privaten Key nie.
- Die Server-Kopien unter `/opt/backups` und `/opt/kisium/backups` bleiben unverschlüsselt,
  aber root-only. Wer sie verschlüsseln will, muss den Backup-Skripten `age` beibringen –
  dann liegt der private Key aber nicht mehr nur auf dem PC.

## Wiederherstellen

```powershell
age -d -i D:\Backups\homelab\age.key -o D:\restore\homelab.tgz D:\Backups\homelab\homelab-<datum>.tgz.age
tar -xzf D:\restore\homelab.tgz -C D:\restore
```

Danach liegen `paperless/` und `backups/` unter `D:\restore`. Der eigentliche
Paperless-Restore-Test läuft auf dem Server (siehe [backup-restore.md](backup-restore.md));
die PC-Kopie ist die kalte Offsite-Kopie.

## Automatisieren

Task Scheduler, täglich, als dein Benutzer (der Key liegt in deinem Profil):

```powershell
schtasks /Create /SC DAILY /ST 05:30 /TN "Homelab Backup Pull" `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Tools\pull-backups.ps1 -Server vps2662496.fastwebserver.de"
```

Der Task läuft nur, wenn dein Key ohne Passphrase nutzbar ist (ssh-agent oder eigener
Key). Bei einer passphrase-geschützten Datei bleibt der Task sonst hängen.

## Grenzen

- **Der PC muss laufen.** Ist er aus, wird nicht gezogen und nicht alarmiert. Ein
  serverseitiger Healthchecks-Ping wäre die robustere Variante.
- **Der private age-Key ist ein Single Point of Failure.** Passwortmanager + ein
  zweiter sicherer Ort.
- **Kein inkrementelles Backup.** Jeder Lauf zieht ein vollständiges Tar; bei 148 MB
  Paperless ist das vertretbar.
- **Kein Restore-Test auf dem PC.** Die Prüfung „Tar lesbar, Ghost-Backup nicht zu alt“
  ersetzt keinen echten Restore.
