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

**Ergebnis 03.11.2026:** 957 MB geholt, Ghost-Backup 8 h alt, mit `age` verschlüsselt
(959 MB), mit dem Key wieder entschlüsselt und per `tar tzf` geprüft. Enthält alle
Paperless-Tarballs und den Ghost-Dump.

**Ergebnis über Tailscale (03.11.2026):** 957 MB in 5:51 Minuten über
`<TAILSCALE_IP>`, Ghost-Backup 8 h alt, verschlüsselt, `OK`.

**Archivtest 03.11.2026:** Ghost-Content (`apps/`, `data/`, `settings/`) und Ghost-DB
(101 `CREATE TABLE`) aus dem Offsite-Archiv gelesen; Paperless-Tar lesbar. Kein
vollständiger Service-Restore aus der Kopie – die Server-Restore-Tests decken das
Verfahren ab.

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

Systemd-Timer auf dem Linux-Rechner (als `tobi`):

```bash
./scripts/install-offsite-timer.sh
```

Der Installer kopiert die Units nach `~/.config/systemd/user`, lädt den User-Daemon und
aktiviert den Timer. Im dsh-Container bricht er bewusst ab, weil dort kein user-systemd
läuft.

Der Timer läuft täglich um 05:30 mit `Persistent=true`: War der Rechner aus, wird der
Lauf nach dem nächsten Login nachgeholt. Der Service liest `SERVER` aus
`~/.offsite/backup.env` und setzt `KEEP=7` (sieben Archive, ca. 6,7 GB). Die Datei
einmal anlegen:

```bash
printf 'SERVER=%s\n' '<TAILSCALE_IP>' > ~/dsh-spielwiese/.offsite/backup.env
chmod 600 ~/dsh-spielwiese/.offsite/backup.env
```

Wenn der Timer auch ohne Login laufen soll:

```bash
sudo loginctl enable-linger tobi
```

Alternativ per Cron:

```cron
30 5 * * * /home/tobi/dsh-spielwiese/homelab/scripts/pull-backups.sh >> /home/tobi/dsh-spielwiese/.offsite/cron.log 2>&1
```

Der Rechner muss laufen. Ist er aus, wird nicht gezogen und nicht alarmiert.

## Grenzen

- **Serverseitiger Check läuft.** `/opt/backups/check-ghost-backup.sh` prüft täglich um
  05:00 das Ghost-Backup-Alter und alarmiert per ntfy. Der Pull prüft zusätzlich.
- **Der private age-Key ist ein Single Point of Failure.** Passwortmanager + ein
  zweiter sicherer Ort.
- **Kein inkrementelles Backup.** Jeder Lauf zieht ein vollständiges Tar; bei ~150 MB
  Paperless ist das vertretbar.
- **Port 22:** Der Linux-Host ist im Tailnet; der Pull läuft über `<TAILSCALE_IP>`.
  Port 22 kann geschlossen werden. Der öffentliche Hostname ist nur noch Fallback,
  solange 22 offen ist.
