# Homepage (Dashboard)

Zentrale Startseite für die Dienste auf dem VPS – Kacheln mit HTTP-Monitor und
Container-Status, dazu Lese-Zugriff auf den Docker-Socket.

## Deployment

```bash
cp .env.example .env    # Werte eintragen, NPM_PASS/DASH_PASS nicht ins Repo
chmod 600 .env
mkdir -p config
docker compose up -d
curl -sI http://127.0.0.1:3000     # 200
```

Die Dateien unter `config/` (`settings.yaml`, `services.yaml`, `bookmarks.yaml`,
`docker.yaml`) liegen auf dem Server und **nicht** im Repo, weil sie pro Host
unterschiedlich sind.

## Warum kein eigenes Netz

NPM hängt im Netz `homeserver_default`. Homepage tritt demselben Netz bei
(`external: true`) und wird von NPM über den Container-Namen `homepage:3000`
erreicht. Ein zweites Netz wäre eine zweite Brücke – genau das, was beim
Recreate der Stack-Compose schon einmal verloren ging.

Den Container-Namen statt der Container-IP als `forward_host` zu nehmen ist
Absicht: Die IP wechselt bei jedem Recreate, der Name nicht.

## Zugriff

NPM-Proxy-Host `dash.<DEINE_DOMAIN>` → `homepage:3000`, Access List
`dash-auth` (Basic Auth), Let's-Encrypt-Zertifikat, Force SSL, HTTP/2.
Port 3000 selbst ist nur an `127.0.0.1` gebunden.

## Einrichtung über die NPM-API

```bash
TOKEN=$(curl -s -X POST "$NPM_URL/api/tokens" -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$NPM_USER\",\"secret\":\"$NPM_PASS\"}" | jq -r .token)
```

Danach `POST /api/nginx/access-lists`, `POST /api/nginx/certificates` und
`POST /api/nginx/proxy-hosts`. Zwei Eigenheiten der API v2:

- Das Zertifikat akzeptiert in `meta` **kein** `letsencrypt_agree` – nur
  `dns_challenge: false`. Ein zusätzliches Feld gibt `400 additional properties`.
- `access-list_id` und `certificate_id` müssen vor dem Proxy-Host existieren;
  die IDs kommen aus den Antworten der vorherigen Aufrufe.
