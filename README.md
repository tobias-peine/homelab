# Homelab

Ein VPS (8 GB RAM, 4 vCores, Debian/Ubuntu), Docker, ein Reverse Proxy auf dem Host –
und die Dienste, die ich täglich benutze. Hier steht, was läuft, **warum** es so aufgebaut
ist und was dabei schiefging.

Der ausführliche Erfahrungsbericht: **[Mein Homelab – drei teure Fehler](https://kisium.de/mein-homelab/)**

## Aufbau

```
Internet
   │  443 / 80
   ▼
Reverse Proxy auf dem Host (openresty) ──► TLS, Weiterleitungen, Rate-Limits
   │  127.0.0.1:2368
   ▼
┌──────────────────────────── Docker: kisium-net ────────────────────────────┐
│                                                                            │
│   ghost:6-alpine  ──────────►  mysql:8.4                                   │
│   (Blog, Port nur lokal)       (utf8mb4, Healthcheck)                      │
│                                                                            │
│   Volumes: ghost_content, mysql_data                                       │
└────────────────────────────────────────────────────────────────────────────┘
```

## Warum es so aussieht

**Der Port ist an `127.0.0.1` gebunden, nicht an `0.0.0.0`.**
`"127.0.0.1:2368:2368"` heißt: Von außen kommt niemand an Ghost vorbei. Der einzige
Weg hinein führt über den Reverse Proxy, der TLS terminiert und die Header setzt.
Hätte ich `"2368:2368"` geschrieben, wäre Ghost direkt im Internet erreichbar – ohne
TLS davor.

**MySQL hat einen Healthcheck, Ghost wartet darauf.**
`depends_on: condition: service_healthy` verhindert den klassischen Fehler, dass Ghost
startet, bevor die Datenbank antwortet – und dann in einer Neustart-Schleife hängt.

**Alle Geheimnisse kommen aus `.env`.**
Kein Passwort steht in dieser Datei. `${MYSQL_PASSWORD:?...}` bricht den Start ab, wenn die
Variable fehlt, statt mit einem leeren Passwort weiterzulaufen. Das ist der Unterschied
zwischen „funktioniert zufällig" und „funktioniert auch morgen noch".

**Keine Daten an Dritte.**
Gravatar, Update-Ping und RPC sind ausgeschaltet. Ein Blog über den eigenen Weg muss nicht
nebenbei verraten, wer ihn liest.

## Was ich dabei gelernt habe

**1. Ein Container ist keine Sicherheitsgrenze per Default.**
Mein erster Container lief zwei Monate als `root`. Seitdem: eigener Benutzer,
`no-new-privileges`, read-only-Mounts wo möglich.

**2. Ein Backup ohne Restore-Test ist kein Backup.**
Ich habe den Dienst gelöscht, zurückgespielt und die Zeit gestoppt. Erst danach wusste ich,
dass es funktioniert.

**3. Debuggen von außen nach innen.**
DNS → Port → Proxy → Container → Anwendung. Zwei Stunden habe ich einmal in der Anwendung
gesucht, dabei war der DNS-Eintrag falsch.

**4. Zombie-Prozesse sind ein Symptom, keine Randnotiz.**
Auf dem Server standen zeitweise über tausend Zombies und der Swap lief voll. Ursache war
ein Dienst, der Kindprozesse startete und nicht einsammelte. Wer nur auf die CPU schaut,
findet das nie.

## Loslegen

```bash
cp .env.example .env
# Werte eintragen
docker compose up -d
docker compose ps        # Healthchecks beobachten
```

## Offene Punkte

- [ ] Backup-Skript mit automatischem Restore-Test veröffentlichen
- [ ] Monitoring-Alarme dokumentieren
- [ ] Reverse-Proxy-Konfiguration (bereinigt) ergänzen

---

Geschrieben von [Tobias Peine](https://kisium.de) – Quereinstieg in die IT.
