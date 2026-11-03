# Reverse Proxy (NPM)

Der Proxy ist ein Container (`jc21/nginx-proxy-manager`), kein Host-Prozess. Er hängt in
beiden Netzen – `homeserver_default` und `kisium-net` – und ist damit die einzige Brücke
zwischen den Compose-Projekten.

## Routen

| Host | Upstream | Port | Netz |
|---|---|---|---|
| `kisium.de` | `kisium-ghost` | 2368 | `kisium-net` |
| `n8n.<DEINE_DOMAIN>` | `n8n` | 5678 | `homeserver_default` |
| `chat.<DEINE_DOMAIN>` | `open-webui` | 8080 | `homeserver_default` |
| `search.<DEINE_DOMAIN>` | `searxng` | 8080 | `homeserver_default` |
| `paperless.<DEINE_DOMAIN>` | `paperless` | 8000 | `homeserver_default` |

Quelle: fünf `proxy_host/*.conf` im Container. Die Domains sind hier durch Platzhalter
ersetzt.

## Was der Proxy macht

- TLS-Terminierung mit Let's Encrypt (Zertifikat gültig bis 30.01.2027)
- `301` von HTTP auf HTTPS
- WebSocket-Header für n8n und Open WebUI (`Upgrade`, `Connection`)
- Weiterleitung an Container-Namen, nicht an Host-Ports

## HSTS: definiert, aber nicht gesendet

Die generierten Configs enthalten:

```nginx
map $scheme $hsts_header {
    https   "max-age=63072000; preload";
}
```

Ein `add_header Strict-Transport-Security …` fehlt jedoch. `curl -sSI` am 03.11.2026
zeigt keinen HSTS-Header. Der `map`-Block ist damit toter Code.

**Vorschlag (nicht produktiv):** in NPM unter „Advanced“ pro Host oder global in einer
Custom Config:

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

## Export

Die vollständigen Configs liegen im Container unter `/data/nginx/proxy_host/*.conf`
(Hosts) und `/data/nginx/custom/*.conf` (eigene Includes). Vor dem Einchecken redigieren:
`server_name`, `proxy_pass`, Zertifikatspfade.

## TODO

- [ ] Eine sanitisierte `proxy-host.conf` als Beispiel ablegen (bisher nur die Tabelle)
- [ ] HSTS ergänzen und mit `curl -sSI` nachweisen
- [ ] NPM-Image pinnen (`latest` → konkreter Tag)
- [ ] Prüfen, ob die `map`-Zeile nach einem HSTS-Update noch gebraucht wird
