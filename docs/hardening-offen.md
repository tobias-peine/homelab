# Hardening – offene Punkte

Stand 03.11.2026. Diese Punkte sind geprüft, aber nicht umgesetzt. Sie sind `TODO`, bis
der Nachweis vorliegt – kein Soll-Zustand, der als Ist-Zustand ausgegeben wird.

## Container-Härtung

**Status:** `no-new-privileges:true` ist seit 03.11. für alle zehn Container gesetzt.
`CapDrop` ist weiterhin überall `[]`; fast alle Dienste laufen als root (`open-webui`
sogar explizit `0:0`). Nur `n8n` läuft als `node`.

**Warum es zählt:** `no-new-privileges` verhindert das Gewinnen neuer Rechte, aber nicht
die Rechte, die der Prozess beim Start schon hat. Ein root-Prozess mit den
Docker-Default-Capabilities kann weiterhin viel: `CHOWN`, `DAC_OVERRIDE`, `SETUID`,
`SETGID`, `NET_RAW` und andere.

**Prüfen:**

```bash
for c in $(docker ps -q); do
  docker inspect "$c" --format \
    '{{.Name}} user={{if .Config.User}}{{.Config.User}}{{else}}(root){{end}} capdrop={{.HostConfig.CapDrop}} secopt={{.HostConfig.SecurityOpt}}'
done
```

**Soll-Zustand (dienstweise, nicht blind):**

| Dienst | Braucht | Vorschlag |
|---|---|---|
| `npm` | Port 80/443 | `cap_drop: [ALL]` + `cap_add: [NET_BIND_SERVICE, SETUID, SETGID, CHOWN]` |
| `kisium-ghost` | Drop auf node, Content schreiben | `SETUID`, `SETGID`, `CHOWN`, `DAC_OVERRIDE` |
| `kisium-mysql` / `paperless-db` | Initialisierung, Drop auf DB-User | `CHOWN`, `DAC_OVERRIDE`, `SETUID`, `SETGID`, `FOWNER` |
| `paperless`, `searxng` | Drop auf Dienst-User | `SETUID`, `SETGID`, `CHOWN` |
| `ollama`, `n8n`, `open-webui`, `paperless-broker` | keine privilegierten Ports | `cap_drop: [ALL]` testen |

Ein pauschales `cap_drop: ALL` bricht mindestens NPM (Port 80/443) und die
Entrypoints, die per `gosu`/`su-exec` den Benutzer wechseln. Deshalb: ein Dienst pro
Änderung, `docker compose up -d <dienst>`, Health prüfen, bei Fehler zurück.

**Risiko ohne:** Ein Fehler in einem exponierten Dienst trifft einen root-Prozess mit
Default-Capabilities. `no-new-privileges` reduziert das, beseitigt es aber nicht.

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
sich aus. Die Umstellung selbst ist ein Ein-Zeilen-Schritt, aber ohne getesteten
zweiten Zugang nicht verantwortbar.

**Risiko ohne:** Der Root-Key ist ein Single Point of Failure; jede Aktion ist nur als
root möglich, ohne saubere Zuordnung.

## Vorgehen

1. Ist-Wert mit dem Befehl oben auslesen.
2. Ergebnis mit Datum hier eintragen.
3. Abweichung entscheiden: ändern oder bewusst akzeptieren – beides mit Grund.
4. Erst dann wandert der Punkt nach [hardening.md](hardening.md).
