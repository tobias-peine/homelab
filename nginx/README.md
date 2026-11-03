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

NPM hängt über ein externes Netz (`kisium-net`) auch am Blog-Stack. Die Verbindung steht
in der Stack-Compose als `external: true`; sie war vorher manuell per
`docker network connect` gesetzt und ging beim Recreate verloren.

## HSTS

Seit 03.11.2026 gesetzt – in `/data/nginx/custom/server_proxy.conf`, das in jeden
Proxy-Host eingebunden wird:

```nginx
more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains";
```

`add_header` auf Server-Ebene reichte nicht: `location /` bindet
`conf.d/include/proxy.conf` ein, dort steht `add_header X-Served-By $host;`. Ein eigenes
`add_header` in der Location bricht die Vererbung von der Server-Ebene. headers-more
(im NPM-Image enthalten) setzt den Header unabhängig davon.

Nachweis:

```bash
curl -sSI https://<DEINE_DOMAIN> | grep -i strict-transport
```

## Export

Die vollständigen Configs liegen im Container unter `/data/nginx/proxy_host/*.conf`
(Hosts) und `/data/nginx/custom/*.conf` (eigene Includes). Vor dem Einchecken redigieren:
`server_name`, `proxy_pass`, Zertifikatspfade.

## TODO

- [ ] Eine sanitisierte `proxy-host.conf` als Beispiel ablegen (bisher nur die Tabelle)
- [ ] Prüfen, ob die `map $scheme $hsts_header`-Zeile im generierten Config noch
      gebraucht wird – HSTS kommt jetzt aus `server_proxy.conf`
