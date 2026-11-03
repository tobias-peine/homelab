# Hardening – offene Punkte

Stand 03.11.2026. Diese Punkte sind geprüft, aber nicht abgeschlossen. Sie sind `TODO`,
bis der Nachweis vorliegt.

## Non-root

**Status:** `no-new-privileges`, `cap_drop: [ALL]` und Fail2ban sind umgesetzt. Offen
ist der Benutzer: `open-webui` läuft explizit als `0:0`, `npm` und `ollama` als root.
Die übrigen Container starten als root, ihre Entrypoints wechseln aber zu `node`,
`mysql`, `postgres`, `paperless`, `searxng` oder `redis`.

**Warum es zählt:** Ein root-Prozess im Container ist root für alles, was in den
Container gereicht wird. `no-new-privileges` und `cap_drop` reduzieren die Folgen, aber
ein Ausbruch trifft weiterhin einen root-Prozess.

**Prüfen:**

```bash
for c in $(docker ps -q); do
  docker inspect "$c" --format \
    '{{.Name}} config_user={{if .Config.User}}{{.Config.User}}{{else}}(root){{end}}'
  docker top "$c" -eo user,comm | head -3
done
```

**Soll-Zustand (dienstweise):**

| Dienst | Problem | Vorschlag |
|---|---|---|
| `open-webui` | explizit `0:0` | Volume auf uid 1000 chownen, `user: "1000:1000"` setzen, Schreibzugriff testen |
| `npm` | root für Port 80/443 | Rootless-NPM mit hohen Ports und Redirect davor – größerer Umbau |
| `ollama` | root | eigenes Home/Volume für einen non-root-User, `user:` setzen |
| `n8n` | bereits `node` | nichts zu tun |

**Risiko ohne:** Ein Fehler in einem exponierten Dienst (Open WebUI, NPM) trifft einen
root-Prozess; die Container-Grenze ist die einzige verbleibende Schicht.

## Tailscale

**Status:** Installiert, `tailscaled` ist aktiv, UFW erlaubt `tailscale0`. Der Dienst ist
aber **`Logged out`** – `tailscale up` wurde nicht ausgeführt.

**Warum es zählt:** Ohne Login gibt es kein Tailnet und keinen privaten Admin-Zugang.
SSH bleibt öffentlich auf Port 22 (Key-only, Fail2ban, UFW).

**Prüfen:**

```bash
systemctl is-active tailscaled
tailscale status
```

**Soll-Zustand:** `tailscale up` mit deinem Account oder einem Auth-Key; danach
`tailscale status` prüfen und SSH testweise über die Tailnet-IP aufrufen. Erst wenn das
läuft, kann Port 22 für das öffentliche Netz geschlossen werden.

**Risiko ohne:** Der Admin-Zugang bleibt im öffentlichen Netz. Das ist mit Key-only,
Fail2ban und UFW vertretbar, aber nicht die im Auftrag genannte Lösung.

## Vorgehen

1. Ist-Wert mit dem Befehl oben auslesen.
2. Ergebnis mit Datum hier eintragen.
3. Abweichung entscheiden: ändern oder bewusst akzeptieren – beides mit Grund.
4. Erst dann wandert der Punkt nach [hardening.md](hardening.md).
