# Offsite auf den Linux-Rechner

Der Linux-Rechner **zieht** die Sicherungen; der Server braucht keinen Zugang hierher.
Ein Lauf holt Paperless- und Ghost-Backups als ein Tar, prüft das Ghost-Alter,
verschlüsselt lokal mit `age` und räumt alte Archive auf.

## Was übertragen wird

| Quelle auf dem Server | Inhalt |
|---|---|
| `/opt/backups/paperless` | Paperless-Tarballs (DB, Data, Media, Export, `.env`) |
| `/opt/kisium/backups` | Ghost-DB-Dump und Content-Archiv |

Der Server packt beide Verzeichnisse mit `sudo tar` nach `/tmp`, `scp` holt das Archiv,
danach wird die temporäre Datei gelöscht.

## Einmal einrichten

1. **SSH-Key** liegt unter `~/dsh-spielwiese/.offsite/id_ed25519` (ohne Passphrase).
   Den öffentlichen Teil in `admin` auf dem Server eintragen:

   ```bash
   echo 'restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVk/kp8Bv39c30TKMBkq+hnAJmN/hCGKpBpUPwSXRR5 homelab-offsite-2026-11-03' >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

2. **age** liegt als statisches Binary unter `~/dsh-spielwiese/.offsite/bin/age`;
   der private Schlüssel unter `.offsite/age.key`. Diesen Schlüssel **sofort in den
   Passwortmanager** kopieren:

   ```bash
   cat ~/dsh-spielwiese/.offsite/age.key
   ```

   Geht er verloren, sind die verschlüsselten Offsite-Backups nicht mehr lesbar.

3. **ntfy-Thema** (optional, für Fehlermeldungen): frei erfundenen String in
   `~/dsh-spielwiese/.offsite/ntfy.topic` schreiben, z. B. `homelab-ghost-7f3a9c`.
   Bei ntfy.sh abonnieren: `https://ntfy.sh/<thema>`.

4. **Einmal manuell laufen lassen:**

   ```bash
   ~/dsh-spielwiese/homelab/scripts/pull-backups.sh
   ```

## Prüfen

```bash
ls -lh ~/dsh-spielwiese/.offsite/backups
tail -20 ~/dsh-spielwiese/.offsite/pull.log
```

Erwartet: `homelab-<datum>.tgz.age`, Größe im Bereich der Server-Backups, im Log `OK`.

## Verschlüsselung

- `age` verschlüsselt das Tar lokal; der private Key bleibt auf diesem Rechner.
- Der Server sieht den privaten Key nie.
- Die Server-Kopien unter `/opt/backups` und `/opt/kisium/backups` bleiben unverschlüsselt,
  aber root-only.

## Wiederherstellen

```bash
age -d -i ~/dsh-spielwiese/.offsite/age.key \
  -o /tmp/homelab.tgz \
  ~/dsh-spielwiese/.offsite/backups/homelab-<datum>.tgz.age
tar -xzf /tmp/homelab.tgz -C /tmp/restore
```

Danach liegen `paperless/` und `backups/` unter `/tmp/restore`. Der eigentliche
Paperless-Restore-Test läuft auf dem Server (siehe [backup-restore.md](backup-restore.md));
diese Kopie ist die kalte Offsite-Kopie.

## Automatisieren

Cron auf dem Linux-Rechner (als `tobi`):

```cron
30 5 * * * /home/tobi/dsh-spielwiese/homelab/scripts/pull-backups.sh >> /home/tobi/dsh-spielwiese/.offsite/cron.log 2>&1
```

Der Rechner muss laufen. Ist er aus, wird nicht gezogen und nicht alarmiert.

## Grenzen

- **Kein serverseitiger Ping.** Die Alterprüfung läuft im Pull-Skript; sie kann nur
  alarmieren, wenn der Rechner läuft.
- **Der private age-Key ist ein Single Point of Failure.** Passwortmanager + ein
  zweiter sicherer Ort.
- **Kein inkrementelles Backup.** Jeder Lauf zieht ein vollständiges Tar; bei ~150 MB
  Paperless ist das vertretbar.
- **Port 22 muss offen bleiben**, solange dieser Rechner nicht im Tailnet ist. Der
  Pull nutzt SSH über die öffentliche Adresse. Erst wenn der Linux-Rechner selbst
  Tailscale nutzt, kann `SERVER=<TAILSCALE_IP>` gesetzt und Port 22 geschlossen werden.
