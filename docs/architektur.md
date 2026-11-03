# Architektur

Ein VPS, zwei Compose-Projekte, zehn Container. NPM ist die einzige Brücke zwischen
beiden Netzen. Diese Datei trennt belegte Fakten von offenen Fragen.

## Überblick

```mermaid
flowchart TB
    U[Browser] -->|"443/TLS"| NPM["NPM<br/>nginx-proxy-manager"]

    subgraph HS["homeserver_default"]
        N8N["n8n:5678"]
        OWUI["open-webui:8080"]
        SX["searxng:8080"]
        PL["paperless:8000"]
        PG[(postgres:5432)]
        RD[(redis:6379)]
        OL["ollama:11434"]
    end

    subgraph KI["kisium-net"]
        G["kisium-ghost:2368"]
        MY[(kisium-mysql:3306)]
    end

    NPM -->|"kisium.de"| G
    NPM -->|"n8n.<domain>"| N8N
    NPM -->|"chat.<domain>"| OWUI
    NPM -->|"search.<domain>"| SX
    NPM -->|"paperless.<domain>"| PL
    G --> MY
    PL --> PG
    PL --> RD
    OWUI --> OL
```

NPM ist Mitglied beider Netze (`homeserver_default` und `kisium-net`). Deshalb erreicht
der Proxy sowohl `kisium-ghost` als auch `n8n`, `open-webui`, `searxng` und `paperless`
über deren Container-Namen. Die Verbindung zu `kisium-net` ist in der Stack-Compose als
`external: true` hinterlegt – sie war vorher manuell per `docker network connect`
gesetzt und ging beim Recreate verloren.

## Komponenten

| Container | Image | Zweck | Netz | Als root? |
|---|---|---|---|---|
| `npm` | `jc21/nginx-proxy-manager` (Digest) | TLS, Routing | beide | ja (80/443) |
| `kisium-ghost` | `ghost:6-alpine` | Blog | `kisium-net` | ja (Entrypoint wechselt zu uid 1000) |
| `kisium-mysql` | `mysql:8.4` | Blog-DB | `kisium-net` | ja |
| `n8n` | `docker.n8n.io/n8nio/n8n` (Digest) | Automatisierung | `homeserver_default` | nein (`node`) |
| `open-webui` | `open-webui:nonroot-20261103` (Derived) | Chat | `homeserver_default` | nein (1000) |
| `searxng` | `searxng/searxng` (Digest) | Metasuche | `homeserver_default` | ja |
| `paperless` | `ghcr.io/paperless-ngx/paperless-ngx` (Digest) | Dokumente | `homeserver_default` | ja |
| `paperless-db` | `postgres:16` | Paperless-DB | `homeserver_default` | ja |
| `paperless-broker` | `redis:7` | Paperless-Queue | `homeserver_default` | ja |
| `ollama` | `ollama/ollama` (Digest) | lokale Modelle | `homeserver_default` | nein (1000) |

Die Root-Spalte ist ein Befund, kein Entwurf. Open WebUI (über ein Derived Image) und
Ollama laufen als uid 1000, `n8n` als `node`; NPM bleibt als Proxy root, weil es 80/443
bindet. Die übrigen Container starten als root und wechseln im Entrypoint den Benutzer.
Alle Container laufen mit `no-new-privileges` und `cap_drop: ALL`; nur die für den
Entrypoint nötigen Capabilities sind zurückgegeben. Die `latest`-Images sind auf die am
03.11.2026 laufenden Digests gepinnt. Details: [hardening.md](hardening.md).

## Netze und Ports

| Port | Dienst | Bindung | Von außen |
|---|---|---|---|
| 80 | NPM | `0.0.0.0` | ja, `301` auf HTTPS |
| 443 | NPM | `0.0.0.0` | ja, TLS |
| 81 | NPM-Admin | `127.0.0.1` | nein |
| 2368 | Ghost | `127.0.0.1` | nein |
| 5678 | n8n | `127.0.0.1` | nein |
| 8080 | Open WebUI | `127.0.0.1` | nein |
| 8888 → 8080 | SearXNG | `127.0.0.1` | nein |
| 8000 | Paperless | nur Netz | nein |
| 3306 / 5432 / 6379 / 11434 | MySQL / Postgres / Redis / Ollama | nur Netz | nein |

UFW lässt eingehend ausschließlich 22, 80 und 443 zu. Alle anderen Dienste sind nur über
den Proxy oder lokal erreichbar.

## Routen im Proxy

| Host | Upstream | Port |
|---|---|---|
| `kisium.de` | `kisium-ghost` | 2368 |
| `n8n.<DEINE_DOMAIN>` | `n8n` | 5678 |
| `chat.<DEINE_DOMAIN>` | `open-webui` | 8080 |
| `search.<DEINE_DOMAIN>` | `searxng` | 8080 |
| `paperless.<DEINE_DOMAIN>` | `paperless` | 8000 |

Quelle: die fünf `proxy_host/*.conf` im NPM-Container. Die Domains sind hier durch
Platzhalter ersetzt; im Repo steht keine echte Domain außer dem öffentlichen Blog-Link.

## Request-Pfad

1. DNS löst die Domain auf die Server-IP auf.
2. Port 80 antwortet mit `301` auf HTTPS.
3. NPM terminiert TLS (Let's Encrypt) und setzt die Proxy-Header.
4. NPM leitet an den Container-Namen weiter, z. B. `kisium-ghost:2368`.
5. Ghost liest aus `kisium-mysql:3306`; Paperless aus Postgres/Redis; Open WebUI aus Ollama.
6. Antwort zurück über NPM.

## Speicher

| Volume | Inhalt |
|---|---|
| `kisium_ghost_content` | Theme, Bilder, Uploads |
| `kisium_mysql_data` | Blog-Datenbank |
| `homeserver_paperless_data` / `_media` / `_pgdata` / `_redisdata` | Paperless |
| `homeserver_webui` | Open-WebUI-Daten |
| `homeserver_ollama` | Modelle |
| `homeserver_searxng_cache` | Such-Cache |
| `homeserver_n8n` | n8n-Daten |

## Host

| | |
|---|---|
| Hoster | Webtropia (myLoc), KVM |
| CPU / RAM / Disk | 4 vCores / 8 GB / 193 GB (26 % belegt) |
| OS | Ubuntu 24.04.5 LTS, Kernel 6.8.0-147-generic |
| Uptime | 14 Tage (03.11.2026) |
| RAM / Swap | 4,6 GB belegt, 3,3 GB verfügbar / 2 GB Swap, 50 % belegt |
| Docker | 29.9.2, Compose v2 |

## Belege

| Fakt | Beleg |
|---|---|
| Container, Images, Ports | `docker ps`, `docker inspect` |
| Netze und Routen | `docker network inspect`, NPM `proxy_host/*.conf` |
| SSH-Konfiguration | `sshd -T` |
| Firewall | `ufw status verbose` |
| Updates | `systemctl is-active/is-enabled unattended-upgrades` |
| OS/Kernel | `hostnamectl`, `uname -r` |
| Restore-Tests | `/var/log/restore-test.log`, eigener Lauf am 03.11.2026 |

## Offene Punkte

- [ ] Tailscale: Server ist eingeloggt (`<TAILSCALE_IP>`); der Windows-Client fehlt noch.
- [ ] NPM läuft als root für 80/443; Open WebUI und Ollama sind non-root.
- [ ] Offsite-Backup und Verschlüsselung der Sicherungen
      (siehe [backup-restore.md](backup-restore.md)).
- [ ] Monitoring-Ping für das Ghost-Backup.
