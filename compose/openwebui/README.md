# Open WebUI als non-root

Das Upstream-Image läuft als root. Der Versuch, es direkt mit `user: "1000:1000"`
zu starten, scheitert:

```
Permission denied: '/app/backend/open_webui/static/favicon.png'
```

Der Entrypoint schreibt in `static/`, und diese Dateien gehören im Image root.
Das Daten-Volume (`/app/backend/data`) war bereits uid 1000 – es lag also nicht daran.

## Lösung

Ein minimales Derived Image übergibt nur dieses Verzeichnis:

```dockerfile
FROM ghcr.io/open-webui/open-webui@sha256:0b399a8ba34558e181d316750455f2a95376a38cd60a61b9c942e138898944bd
USER root
RUN chown -R 1000:1000 /app/backend/open_webui/static
USER 1000:1000
```

Bauen:

```bash
docker build -t open-webui:nonroot-20261103 compose/openwebui
```

Im Compose:

```yaml
open-webui:
  image: open-webui:nonroot-20261103
  user: "1000:1000"
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
```

## Ergebnis

- `Config.User` = `1000:1000`
- `cap_drop: [ALL]`, `no-new-privileges`
- Container `healthy`, `/` antwortet mit `200`
- Daten-Volume bleibt uid 1000

## Update

Der Basis-Digest steht im Dockerfile. Bei einem Update:

1. neuen Digest eintragen,
2. `docker build -t open-webui:nonroot-<datum> compose/openwebui`,
3. Tag im Compose anpassen,
4. `docker compose up -d open-webui`,
5. Health und Login prüfen.

Das Static-Verzeichnis ist Teil des Images, nicht des Volumes. Deshalb bleibt es
beim Rebuild aktuell – anders als bei einem gemounteten Static-Volume.

## Grenze

Das ist ein bewusst kleiner Patch, kein Fork. Wenn Upstream das Verzeichnis später
anders behandelt, zuerst prüfen, ob der Patch noch nötig ist.
