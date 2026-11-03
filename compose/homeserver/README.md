# Homeserver-Stack

Acht Container: Nginx Proxy Manager, n8n, Open WebUI, SearXNG, Paperless
(App, PostgreSQL, Redis) und Ollama. Zusammen mit dem Ghost/MySQL-Stack aus
`../docker-compose.yml` sind das die zehn Container aus dem README.

Die Dateien sind aus dem laufenden Server übernommen und sanitisiert:

- Hostnamen sind Platzhalter (`<DEINE_DOMAIN>`) bzw. Umgebungsvariablen.
- Passwörter und Keys stehen nur in `.env`, nicht in der Compose.
- Die Images sind auf Digests gepinnt; `open-webui` wird lokal gebaut.

## Start

```bash
# 1. Netzwerk für NPM und Ghost
docker network create kisium-net 2>/dev/null || true

# 2. Open-WebUI-Image bauen (non-root)
docker build -t open-webui:nonroot-20261103 ../openwebui

# 3. Konfiguration
cp .env.example .env
$EDITOR .env

# 4. Starten
docker compose up -d
docker compose ps
```

NPM bekommt Port 80/443 und hängt zusätzlich in `kisium-net`, damit es
`ghost:2368` erreicht. Die fünf Proxy-Hosts werden in der NPM-Oberfläche
(`127.0.0.1:81`) angelegt; Routen und HSTS stehen in
[`../../nginx/README.md`](../../nginx/README.md).

## Dienste

| Dienst | Intern | Zweck |
|---|---|---|
| `npm` | 80/443, Admin 81 lokal | Reverse Proxy, TLS |
| `n8n` | 5678 | Automation |
| `open-webui` | 8080 | Chat-UI für Ollama |
| `searxng` | 8080 | Metasuchmaschine |
| `paperless` | 8000 | Dokumentenarchiv |
| `paperless-db` | 5432 | PostgreSQL |
| `paperless-broker` | 6379 | Redis |
| `ollama` | 11434 | LLM-Runtime |

## Grenzen

- Die NPM-Konfiguration (Proxy-Hosts, Zertifikate) ist nicht als Code im Repo;
  sie liegt im NPM-Volume. Die Routen sind dokumentiert, nicht automatisiert.
- `PAPERLESS_URL`, `N8N_HOST`, `SEARXNG_BASE_URL` und `CORS_ALLOW_ORIGIN` müssen
  zur eigenen Domain passen.
- Die Compose ersetzt kein Backup; siehe [`../../docs/backup-restore.md`](../../docs/backup-restore.md).
