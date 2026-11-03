# Hardening – offene Punkte

Stand 03.11.2026. Diese Punkte sind geprüft, aber nicht umgesetzt. Sie sind `TODO`, bis
der Nachweis vorliegt – kein Soll-Zustand, der als Ist-Zustand ausgegeben wird.

## Container-Härtung

**Status:** `docker inspect` zeigt für fast alle Container ein leeres `Config.User`
(= root), für `open-webui` explizit `0:0`. `CapDrop` ist überall `[]`,
`SecurityOpt` ist überall `[]`. Nur `n8n` läuft als `node`.

**Warum es zählt:** Ein Prozess als root im Container ist root für alles, was in den
Container gereicht wird. Ohne `no-new-privileges` kann ein gesetztes Setuid-Binary
Rechte eskalieren; ohne `cap_drop` behält der Container die Docker-Default-Capabilities.

**Prüfen:**

```bash
for c in $(sudo docker ps -q); do
  sudo docker inspect "$c" --format \
    '{{.Name}} user={{if .Config.User}}{{.Config.User}}{{else}}(root){{end}} capdrop={{.HostConfig.CapDrop}} secopt={{.HostConfig.SecurityOpt}}'
done
```

**Soll-Zustand (schrittweise, nicht blind):** `security_opt: ["no-new-privileges:true"]`
für alle Dienste; `cap_drop: [ALL]` dort, wo der Dienst keine Capability braucht;
non-root-User, wo das Image es unterstützt. NPM braucht Port 80/443 – `cap_drop: ALL`
würde das ohne weitere Anpassung brechen.

**Risiko ohne:** Ein Fehler in einem exponierten Dienst (n8n, Open WebUI, Paperless)
trifft einen root-Prozess mit Default-Capabilities.

## HSTS fehlt

**Status:** Die NPM-Konfiguration enthält eine `map $scheme $hsts_header`, aber kein
`add_header Strict-Transport-Security`. Die HTTPS-Antwort vom 03.11.2026 enthält den
Header nicht.

**Warum es zählt:** Ohne HSTS kann ein Angreifer den ersten Aufruf über HTTP abfangen,
bevor der `301` greift (SSL-Stripping).

**Prüfen:**

```bash
curl -sSI https://<DEINE_DOMAIN> | grep -i strict-transport
```

**Soll-Zustand:** `add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;`
global in NPM (Custom Config) oder pro Proxy Host unter „Advanced“.

**Risiko ohne:** Der erste Request ist angreifbar; der Browser merkt sich HTTPS nicht.

## Fail2ban

**Status:** `systemctl is-active fail2ban` → `inactive`; nicht installiert.

**Warum es zählt:** SSH ist Key-only, deshalb ist der Nutzen gering. Für NPM oder
Anwendungen mit Login (n8n, Open WebUI, Paperless) wäre ein Fail2ban-Jail ein zusätzlicher
Schutz – aber nur, wenn die Logs sauber geparst werden.

**Prüfen:**

```bash
systemctl is-active fail2ban; command -v fail2ban-client
```

**Soll-Zustand:** Entscheiden, ob überhaupt nötig. Wenn ja: ein Jail für SSH und ggf.
NPM, mit `ignoreip` für die eigene Admin-IP.

**Risiko ohne:** Langsame Brute-Force-Versuche gegen Login-Oberflächen bleiben
unbemerkt; bei Key-only-SSH ist das Risiko klein.

## Tailscale

**Status:** `command -v tailscale` ist leer, `tailscaled` ist inactive. Der Auftrag
nannte Tailscale als Admin-Zugang; auf dem Server ist es nicht vorhanden.

**Warum es zählt:** Tailscale würde SSH und Admin-Oberflächen aus dem öffentlichen Netz
nehmen. Es ist aber ein zusätzlicher Dienst mit eigener Angriffsfläche und einem
Drittanbieter im Trust-Pfad.

**Prüfen:**

```bash
command -v tailscale; systemctl is-active tailscaled
```

**Soll-Zustand:** Entweder installieren und SSH auf das Tailnet beschränken – oder
Tailscale aus der Beschreibung streichen. Beides ist ehrlicher als „läuft“ zu behaupten.

**Risiko ohne:** SSH bleibt öffentlich erreichbar (Port 22). Bei Key-only und UFW ist
das vertretbar, aber nicht dasselbe wie ein privater Zugang.

## Image-Versionen

**Status:** `npm`, `n8n`, `open-webui`, `searxng`, `paperless` und `ollama` laufen auf
`latest`. Nur `ghost:6-alpine` und `mysql:8.4` sind gepinnt.

**Warum es zählt:** Ein `docker compose pull` kann eine neue Major-Version ziehen, die
Datenbank-Migrationen oder Breaking Changes mitbringt. Ohne gepinnte Version gibt es
keinen reproduzierbaren Rücksprung.

**Prüfen:**

```bash
sudo docker ps --format '{{.Names}} {{.Image}}'
```

**Soll-Zustand:** Konkrete Tags oder Digests, Update bewusst und mit Backup. Für NPM
und Paperless besonders relevant, weil sie Datenbanken mitbringen.

**Risiko ohne:** Ungeplanter Ausfall nach einem Pull; Rollback nur über ein älteres
Image, das nicht dokumentiert ist.

## Root-Login

**Status:** `permitrootlogin without-password` – Root darf sich per Key anmelden.
Ein dauerhafter Admin-Benutzer mit sudo fehlt noch.

**Warum es zählt:** Root per Key ist deutlich besser als Root per Passwort, aber ein
eigener Admin-Benutzer mit sudo hinterlässt eine Spur in `auth.log` und lässt sich
einzeln sperren.

**Prüfen:**

```bash
sshd -T | grep -E 'permitrootlogin|passwordauthentication'
```

**Soll-Zustand:** `PermitRootLogin no`, ein dauerhafter Admin-Benutzer mit sudo und
eigener `authorized_keys`. Vorher in einer zweiten Sitzung testen, sonst sperrt man
sich aus.

**Risiko ohne:** Der Root-Key ist ein Single Point of Failure; jede Aktion ist nur als
root möglich, ohne saubere Zuordnung.

## Vorgehen

1. Ist-Wert mit dem Befehl oben auslesen.
2. Ergebnis mit Datum hier eintragen.
3. Abweichung entscheiden: ändern oder bewusst akzeptieren – beides mit Grund.
4. Erst dann wandert der Punkt nach [hardening.md](hardening.md).
