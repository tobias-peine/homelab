# Homelab

Ein VPS (8 GB, 4 vCores, Debian), Docker, ein Reverse Proxy davor – und die Dienste, die
ich täglich benutze. Hier steht, was läuft, warum es so aufgebaut ist und was schiefging.

> **Hinweis:** Diese README ist das Gerüst. Die echten Compose-Dateien und Konfigurationen
> folgen – ohne Passwörter, ohne interne IPs, ohne Schlüssel.

## Aufbau

```
Internet
   │
   ▼
Nginx Proxy Manager  ──►  TLS (Let's Encrypt), Weiterleitungen
   │
   ├── paperless      Dokumentenarchiv
   ├── n8n            Automatisierungen
   ├── ollama         lokale Modelle
   ├── ghost          dieser Blog
   └── monitoring     Uptime und Benachrichtigungen
```

## Was ich dabei gelernt habe

**1. Ein Container ist keine Sicherheitsgrenze per Default.**
Mein erster lief als `root`, zwei Monate lang. Seitdem: eigener Benutzer, `no-new-privileges`,
read-only Mounts wo möglich.

**2. Ein Backup ohne Restore-Test ist kein Backup.**
Ich habe den Dienst gelöscht, zurückgespielt und die Zeit gestoppt. Erst danach wusste ich,
dass es funktioniert.

**3. Debuggen von außen nach innen.**
DNS → Port → Proxy → Container → Anwendung. Zwei Stunden habe ich einmal in der Anwendung
gesucht, dabei war der DNS-Eintrag falsch.

## Struktur

```
docker-compose.yml     Dienste und Netzwerke
nginx/                 Proxy-Konfiguration
scripts/               Backup, Update, Prüfungen
docs/                  Notizen zu Entscheidungen
```

## Offene Punkte

- [ ] Compose-Dateien (bereinigt) veröffentlichen
- [ ] Backup-Skript mit Restore-Test
- [ ] Monitoring-Alarme dokumentieren

---

Geschrieben von [Tobias Peine](https://kisium.de) – Quereinstieg in die IT.
Der ausführliche Erfahrungsbericht: [Mein Homelab](https://kisium.de/mein-homelab/)
