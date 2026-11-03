# Reverse Proxy (NPM)

Die sanitisierte Proxy-Konfiguration gehört hierher. Sie liegt noch nicht vor – dieser
Ordner ist ein Platzhalter mit dem, was bekannt ist, und dem Weg zum Export.

## Bekannt

| Punkt | Wert | Beleg |
|---|---|---|
| Software | openresty | HTTP-Header `Server: openresty` |
| Produkt | Nginx Proxy Manager | Blogartikel |
| Ports | 80, 443 | von außen erreichbar |
| TLS | Let's Encrypt, gültig bis 30.01.2027 | `openssl s_client` |
| HTTP | `301` auf HTTPS | `curl -sSI http://…` |
| Betriebsart | Host oder Container? | **nicht belegt** |

## Fehlt

- Proxy-Host für die Domain: `server_name`, `upstream`, TLS-Zertifikatspfade
- Advanced Config: HSTS, Security-Header, `client_max_body_size`, WebSocket-Header
- Rate-Limits, falls konfiguriert
- Zugriffs- und Fehler-Logs (Pfad, Rotation)
- Ob der Proxy im selben Docker-Netz hängt oder auf dem Host läuft

## Export

**Variante A – NPM-Oberfläche:** Hosts → Proxy Hosts → Eintrag bearbeiten → Reiter
„Advanced“. Inhalt kopieren.

**Variante B – Dateisystem:** Im NPM-Container liegen die Hosts unter
`/data/nginx/proxy_host/*.conf`, eigene Includes unter `/data/nginx/custom/*.conf`.

Vor dem Einchecken redigieren:

- `server_name` → `<DEINE_DOMAIN>`
- `proxy_pass` → `<INTERNE_ADRESSE>:<PORT>`
- Zertifikatspfade → `<PFAD>`
- alles, was nach Token, Passwort oder API-Key aussieht

## TODO

- [ ] Proxy-Host exportieren und als `nginx/proxy-host.conf` ablegen
- [ ] Advanced Config separat als `nginx/advanced.conf` ablegen
- [ ] Betriebsart (Host/Container) dokumentieren
- [ ] Logpfade und Rotation ergänzen
