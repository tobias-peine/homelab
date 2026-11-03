# Hardening

Stand 03.11.2026, geprüft auf dem laufenden Server. Jede Maßnahme mit Begründung,
Umsetzung und dem Risiko, wenn sie fehlt. Offene Punkte: [hardening-offen.md](hardening-offen.md).

## 1. SSH nur mit Schlüssel

**Was:** Passwort-Login ist aus, Root-Login nur per Key, maximal sechs Versuche.

**Warum:** Passwörter sind brute-forcebar; Bots scannen IPv4-Bereiche permanent. Ein
Key lässt sich nicht erraten.

**Wie:** `sshd -T` am 03.11.2026:

```
passwordauthentication no
kbdinteractiveauthentication no
pubkeyauthentication yes
permitrootlogin without-password
maxauthtries 6
```

**Risiko ohne:** Automatisierte Login-Versuche, Credential-Stuffing, im schlimmsten Fall
ein Shell-Zugang als root.

## 2. Firewall: eingehend nur 22, 80, 443

**Was:** UFW ist aktiv, Default eingehend `deny`, ausgehend `allow`.

**Warum:** Jeder offene Port ist eine Angriffsfläche. Der Proxy braucht 80/443, SSH
braucht 22 – alles andere hat keinen Grund, von außen erreichbar zu sein.

**Wie:**

```
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)
22/tcp      ALLOW IN    Anywhere
80,443/tcp  ALLOW IN    Anywhere
```

**Risiko ohne:** Dienste, die versehentlich auf `0.0.0.0` lauschen, sind sofort im
Internet sichtbar – auch wenn sie es nicht sollen.

## 3. Automatische Sicherheitsupdates

**Was:** `unattended-upgrades` ist aktiv und enabled; automatische Neustarts sind aus.

**Warum:** Ein öffentlich erreichbarer Proxy und ein Webserver sammeln bekannte Lücken.
Updates von Hand werden vergessen; automatische Neustarts würden den Blog ungeplant
unterbrechen.

**Wie:**

```
systemctl is-active unattended-upgrades   → active
systemctl is-enabled unattended-upgrades  → enabled
Unattended-Upgrade::Automatic-Reboot "false"
```

**Risiko ohne:** Eine bekannte Lücke bleibt offen, bis jemand von Hand updatet.

## 4. Proxy-Admin nur auf Loopback

**Was:** Die NPM-Oberfläche lauscht auf `127.0.0.1:81`, nicht auf `0.0.0.0`.

**Warum:** Das Admin-Interface ist der mächtigste Teil des Stacks – wer dort hineinkommt,
kann Routen und Zertifikate ändern. Es braucht keinen öffentlichen Port.

**Wie:** Im Compose: `"127.0.0.1:81:81"`.

**Risiko ohne:** Login-Oberfläche im Internet, erreichbar für jeden Scanner.

## 5. Datenbanken ohne öffentlichen Port

**Was:** MySQL und Postgres haben kein `ports:`-Mapping; sie sind nur in ihren
Docker-Netzen erreichbar.

**Warum:** Eine offene Datenbank ist ein direktes Ziel. Ohne Port gibt es keinen Netzweg
von außen.

**Wie:** `docker ps` zeigt für `kisium-mysql` nur `3306/tcp`, für `paperless-db` nur
`5432/tcp` – ohne Host-Bindung.

**Risiko ohne:** Brute-Force, Datenabfluss, Ransomware – am Proxy vorbei.

## 6. TLS am Proxy, HTTP wird umgeleitet

**Was:** Port 80 antwortet mit `301` auf HTTPS; das Let's-Encrypt-Zertifikat ist am
03.11.2026 gültig bis 30.01.2027.

**Warum:** Ohne TLS gehen Session-Cookies und Login-Daten im Klartext über das Netz.

**Wie:** NPM terminiert TLS; die Zertifikate werden automatisch erneuert. Nachweis:

```bash
curl -sSI http://<DEINE_DOMAIN> | head -1     # 301 Moved Permanently
```

**Risiko ohne:** Mitlesen und Manipulieren der Verbindung; Browser warnen.

## 7. Keine Daten an Dritte

**Was:** Gravatar, Update-Ping und RPC sind in Ghost abgeschaltet.

**Warum:** Diese Funktionen senden Anfragen an externe Server. Für einen Blog, der
nichts trackt, sind sie ein unnötiger Datenabfluss.

**Wie:**

```yaml
privacy__useGravatar: "false"
privacy__useRpcPing: "false"
privacy__useUpdateCheck: "false"
```

**Risiko ohne:** Besucherdaten gehen an Dritte, ohne dass es im Blog erwähnt wird.

## 8. Healthcheck ohne Zombie-Leck

**Was:** Der Ghost-Check prüft den Port mit `nc -z`; der Container läuft mit `init: true`.

**Warum:** `wget --spider` folgte dem `301` von `http://127.0.0.1:2368` auf
`https://127.0.0.1:2368` und sprach TLS mit einem HTTP-Port. Jeder Fehlversuch
hinterließ einen `ssl_client`-Zombie; nach elf Stunden waren es 1.354. `init: true`
sorgt dafür, dass der Container Kindprozesse einsammelt.

**Wie:**

```yaml
init: true
healthcheck:
  test: ["CMD", "nc", "-z", "127.0.0.1", "2368"]
```

**Risiko ohne:** Der Container gilt dauerhaft als `unhealthy`, die Prozessliste läuft
voll, und irgendwann fehlen PIDs oder Speicher.

## 9. HSTS auf allen Proxy-Hosts

**Was:** Alle fünf Hosts senden `Strict-Transport-Security: max-age=31536000; includeSubDomains`.

**Warum:** Ohne HSTS kann der erste Aufruf über HTTP abgefangen werden, bevor der `301`
greift. Der Browser merkt sich dann, dass die Seite nur über HTTPS zu laden ist.

**Wie:** In `/data/nginx/custom/server_proxy.conf` (wird in jeden Proxy-Host eingebunden):

```nginx
more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains";
```

`add_header` auf Server-Ebene funktionierte nicht: `location /` bindet
`conf.d/include/proxy.conf` ein, und dort steht `add_header X-Served-By $host;`. Ein
eigenes `add_header` in der Location bricht die Vererbung von der Server-Ebene. Das
headers-more-Modul (in NPM enthalten) setzt den Header unabhängig davon.

**Nachweis:**

```bash
curl -sSI https://<DEINE_DOMAIN> | grep -i strict-transport
```

**Risiko ohne:** SSL-Stripping beim ersten Request; der Browser kennt die HTTPS-Pflicht
nicht.

## 10. `no-new-privileges` für alle Container

**Was:** Alle zehn Container laufen mit `security_opt: ["no-new-privileges:true"]`.

**Warum:** Ein gesetztes Setuid-Binary oder ein privilegierter Helper kann innerhalb des
Containers keine zusätzlichen Rechte mehr gewinnen. Das ist besonders relevant, weil
fast alle Dienste als root laufen.

**Wie:** In den Compose-Dateien pro Service:

```yaml
security_opt:
  - no-new-privileges:true
```

**Nachweis:**

```bash
docker inspect <container> --format '{{.HostConfig.SecurityOpt}}'   # [no-new-privileges:true]
```

**Risiko ohne:** Ein Fehler in einem exponierten Dienst kann über Setuid-Binaries
Rechte eskalieren, statt auf den Container beschränkt zu bleiben.

## Offene Punkte

| Punkt | Status | Details |
|---|---|---|
| Container-Härtung | `no-new-privileges` aktiv; `cap_drop`/non-root offen | [hardening-offen.md](hardening-offen.md#container-härtung) |
| Fail2ban | nicht aktiv | [hardening-offen.md](hardening-offen.md#fail2ban) |
| Tailscale | nicht installiert | [hardening-offen.md](hardening-offen.md#tailscale) |
| Root-Login | per Key erlaubt | [hardening-offen.md](hardening-offen.md#root-login) |

Grundsatz: Keine Maßnahme ist „empfohlen, weil Best Practice“. Jede Zeile hat einen
Beleg vom Server oder steht ausdrücklich unter „offen“.
