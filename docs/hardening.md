# Hardening

Jede Maßnahme mit Begründung, Umsetzung und dem Risiko, wenn sie fehlt. Diese Datei
enthält nur, was durch Compose-Datei oder HTTP-Header belegt ist. Die offenen Punkte
stehen in [hardening-offen.md](hardening-offen.md).

## 1. Ghost nur auf Loopback

**Was:** Der Container veröffentlicht Port 2368 ausschließlich auf `127.0.0.1`.

**Warum:** Der einzige Weg zum Blog führt über den Proxy. Dort enden TLS und die
Weiterleitungsregeln. Eine Bindung an `0.0.0.0` würde Ghost zusätzlich direkt und ohne
TLS erreichbar machen.

**Wie:**

```yaml
ports:
  - "127.0.0.1:2368:2368"
```

**Risiko ohne:** Der Blog wäre unter `http://<SERVER_IP>:2368` erreichbar – ohne TLS,
ohne Proxy-Header, ohne die Möglichkeit, Zugriffe am Proxy zu filtern.

## 2. Kein veröffentlichter Datenbank-Port

**Was:** MySQL hat kein `ports:`-Mapping und ist nur im Netz `kisium-net` erreichbar.

**Warum:** Eine offene Datenbank ist ein direktes Angriffsziel. Automatisierte Scans
suchen permanent nach 3306. Ohne Port gibt es keinen Netzweg von außen.

**Wie:**

```yaml
# mysql: kein ports:-Block, nur networks: [kisium]
networks:
  kisium:
    name: kisium-net
```

**Risiko ohne:** Brute-Force auf die Datenbank, Datenabfluss oder Verschlüsselung per
Ransomware – ohne dass der Proxy etwas davon sieht.

## 3. Zugangsdaten nur in `.env`, Start bricht bei Lücke ab

**Was:** Alle Passwörter und Zugangsdaten kommen aus Umgebungsvariablen; die
Compose-Datei enthält keine Werte.

**Warum:** Kein Secret im Repository, keine versehentlich leeren Passwörter. Die
Schreibweise `${MYSQL_PASSWORD:?…}` erzwingt einen Wert – Compose bricht sonst ab.

**Wie:**

```yaml
database__connection__password: ${MYSQL_PASSWORD:?MYSQL_PASSWORD fehlt in .env}
```

**Risiko ohne:** Ein leeres oder Standard-Passwort läuft unbemerkt weiter; Secrets
landen im Git-Verlauf und sind auch nach dem Löschen dort noch auffindbar.

## 4. TLS am Proxy, HTTP wird umgeleitet

**Was:** Port 80 antwortet mit `301` auf HTTPS; das Zertifikat ist von Let's Encrypt
und am 03.11.2026 gültig bis 30.01.2027.

**Warum:** Ohne TLS gehen Session-Cookies und Login-Daten im Klartext über das Netz.
Der Redirect verhindert, dass jemand versehentlich die HTTP-Variante benutzt.

**Wie:** Die Konfiguration liegt im Proxy, nicht im Repo (`TODO`: Export nach
[nginx/](../nginx/)). Nachweis:

```bash
curl -sSI http://<DEINE_DOMAIN> | head -1     # HTTP/1.1 301 Moved Permanently
```

**Risiko ohne:** Mitlesen und Manipulieren der Verbindung; Browser warnen, Suchmaschinen
stufen die Seite ab.

## 5. Keine Daten an Dritte

**Was:** Gravatar, Update-Ping und RPC sind in Ghost abgeschaltet.

**Warum:** Diese Funktionen senden Anfragen an externe Server. Für einen Blog, der
nichts trackt, sind sie ein unnötiger Datenabfluss – Gravatar verrät etwa die
E-Mail-Hashes der Kommentierenden.

**Wie:**

```yaml
privacy__useGravatar: "false"
privacy__useRpcPing: "false"
privacy__useUpdateCheck: "false"
```

**Risiko ohne:** Besucherdaten gehen an Dritte, ohne dass es im Blog erwähnt wird.

## 6. Healthcheck und definierte Startreihenfolge

**Was:** MySQL hat einen Healthcheck, Ghost wartet auf `service_healthy`.

**Warum:** Ohne diese Bedingung startet Ghost, bevor die Datenbank antwortet, und läuft
in eine Neustart-Schleife. Das ist kein Sicherheits-, sondern ein Verfügbarkeitsproblem –
aber im Betrieb der Unterschied zwischen „läuft“ und „läuft nach jedem Reboot“.

**Wie:**

```yaml
depends_on:
  mysql:
    condition: service_healthy
```

**Risiko ohne:** Nach einem Neustart startet der Blog erst nach mehreren Fehlversuchen
oder gar nicht.

## Offene Punkte

| Punkt | Status | Details |
|---|---|---|
| HSTS | Header fehlt (03.11.2026) | [hardening-offen.md](hardening-offen.md#hsts-fehlt) |
| SSH-Härtung | nicht belegt | [hardening-offen.md](hardening-offen.md#ssh-härtung) |
| Firewall | nicht belegt | [hardening-offen.md](hardening-offen.md#firewall) |
| Automatische Updates | nicht belegt | [hardening-offen.md](hardening-offen.md#automatische-updates) |
| Container-Härtung | nicht geprüft | [hardening-offen.md](hardening-offen.md#container-härtung) |
| Tailscale / SearXNG | in keiner Quelle belegt | [hardening-offen.md](hardening-offen.md#tailscale-und-searxng) |

Grundsatz: Keine Maßnahme ist „empfohlen, weil Best Practice“. Jede Zeile hat entweder
einen Beleg aus der Konfiguration oder steht ausdrücklich unter „offen“.
