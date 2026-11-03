# Derived Image: Open WebUI als non-root
#
# Upstream schreibt beim Start in /app/backend/open_webui/static. Diese Dateien
# gehören im Original-Image root; als uid 1000 gibt es "Permission denied".
# Dieses Image übergibt genau dieses Verzeichnis und läuft danach als uid 1000.
#
# Build:
#   docker build -t open-webui:nonroot-20261103 compose/openwebui
#
# Basis-Digest bewusst gepinnt. Bei einem Update den Digest hier ersetzen und
# neu bauen; das Tag im Compose mitziehen.

FROM ghcr.io/open-webui/open-webui@sha256:0b399a8ba34558e181d316750455f2a95376a38cd60a61b9c942e138898944bd

USER root
RUN chown -R 1000:1000 /app/backend/open_webui/static
USER 1000:1000
