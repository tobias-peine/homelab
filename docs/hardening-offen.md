# Hardening – offene Punkte

Diese Maßnahmen stehen im Auftrag oder sind aus dem Betrieb bekannt, aber durch keine
Konfiguration belegt. Sie sind `TODO`, bis der Nachweis vorliegt. Was hier steht, ist
der Prüfweg und ein Soll-Zustand – nicht der behauptete Ist-Zustand.

## HSTS fehlt

**Status:** Der Header `Strict-Transport-Security` fehlt in der HTTPS-Antwort vom
03.11.2026.

**Warum es zählt:** Ohne HSTS kann ein Angreifer den ersten Aufruf über HTTP abfangen,
bevor der `301`-Redirect greift (SSL-Stripping). Der Browser merkt sich dann, dass die
Seite nur über HTTPS zu laden ist.

**Prüfen:**

```bash
curl -sSI https://<DEINE_DOMAIN> | grep -i strict-transport
```

**Vorschlag (nicht produktiv):** Im NPM unter „Advanced“ ergänzen:

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

## SSH-Härtung

**Status:** Nicht belegt. Der Server wird als `root` administriert (Prompt `root@…`);
ob Root-Login per SSH erlaubt ist, ist offen. Eine `sshd_config` liegt nicht im Repo.

**Warum es zählt:** Passwort-Login als root ist das häufigste Einfallstor für
automatisierte Angriffe. Bots scannen IPv4-Bereiche permanent.

**Prüfen:**

```bash
sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication'
```

**Soll-Zustand (zu bestätigen):** `PermitRootLogin prohibit-password`,
`PasswordAuthentication no`, Login nur per Key. Ohne diese Werte bleibt der Punkt offen.

## Firewall

**Status:** Nicht belegt. Es gibt keine Dokumentation zu `ufw` oder `nftables`.

**Warum es zählt:** Auch ein Dienst, der nur auf Loopback lauscht, ist über andere
offene Ports erreichbar, wenn die Firewall fehlt.

**Prüfen:**

```bash
ufw status verbose 2>/dev/null || nft list ruleset
```

**Soll-Zustand (zu bestätigen):** eingehend nur 22 (oder ein anderer SSH-Port), 80 und
443; alles andere verwerfen.

## Automatische Updates

**Status:** Nicht belegt. `unattended-upgrades` ist nicht dokumentiert.

**Warum es zählt:** Ein Server ohne automatische Sicherheitsupdates sammelt bekannte
Lücken an – besonders bei einem öffentlich erreichbaren Proxy.

**Prüfen:**

```bash
systemctl status unattended-upgrades --no-pager
apt-config dump | grep -i unattended
```

**Soll-Zustand (zu bestätigen):** Sicherheitsupdates automatisch, Neustart nicht
automatisch, Benachrichtigung bei Fehlern.

## Container-Härtung

**Status:** Die Compose-Datei setzt weder `user:` noch `cap_drop` noch
`security_opt: no-new-privileges`. Ob die Images selbst als non-root laufen, ist nicht
geprüft.

**Warum es zählt:** Ein Container-Prozess als root ist innerhalb des Containers root –
und ein Ausbruch trifft dann einen root-Prozess.

**Prüfen:**

```bash
docker inspect kisium-ghost --format '{{.Config.User}}'
docker inspect kisium-ghost --format '{{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}}'
```

**Soll-Zustand (zu bestätigen):** `node` (oder ein anderer non-root-User),
`cap_drop: [ALL]`, `no-new-privileges: true`, read-only wo möglich.

## Tailscale und SearXNG

**Status:** In keiner Quelle belegt – weder im Blogartikel noch in der Compose-Datei
noch in der Server-Ausgabe. Wenn sie laufen, fehlen Ports, Netze und Konfiguration.

**TODO:** Beide mit Zweck, Port und Zugriffsweg ergänzen oder aus dem Auftrag streichen.

## Vorgehen

1. Wert auf dem Server auslesen (Befehl oben).
2. Ergebnis hier als „Ist“ eintragen, mit Datum.
3. Abweichung zum Soll entscheiden: ändern oder bewusst akzeptieren – beides mit Grund.
4. Erst dann wandert der Punkt nach [hardening.md](hardening.md).
