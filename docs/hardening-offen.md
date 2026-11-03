# Hardening – offene Punkte

Stand 03.11.2026. Diese Punkte sind geprüft, aber nicht abgeschlossen. Sie sind `TODO`,
bis der Nachweis vorliegt.

## NPM als root

**Status:** `npm` läuft als root, weil es 80/443 bindet. Die Caps sind auf
`NET_BIND_SERVICE`, `CHOWN`, `DAC_OVERRIDE`, `SETGID`, `SETUID` reduziert;
`no-new-privileges` ist gesetzt. Open WebUI und Ollama laufen inzwischen als uid 1000.

**Warum es zählt:** NPM ist der einzige verbleibende root-Dienst im Stack. Ein Fehler im
Proxy trifft einen root-Prozess – allerdings mit stark reduzierten Capabilities.

**Prüfen:**

```bash
docker inspect npm --format \
  'user={{.Config.User}} capdrop={{.HostConfig.CapDrop}} capadd={{.HostConfig.CapAdd}} secopt={{.HostConfig.SecurityOpt}}'
```

**Soll-Zustand – zwei Optionen:**

1. **So lassen.** Root für 80/443 ist bei einem Reverse Proxy üblich; die Caps sind
   minimal. Das ist die pragmatische Variante.
2. **Rootless NPM.** NPM auf 8080/8443 betreiben und davor einen Redirect von 80/443
   legen (iptables/nftables oder ein zweiter kleiner Proxy). Mehr Teile, mehr
   Fehlerquellen, kein direkter Sicherheitsgewinn für die Anwendung dahinter.

**Risiko ohne:** Ein Ausbruch aus NPM landet bei uid 0 – mit den fünf genannten
Capabilities, nicht mit den Docker-Defaults.

## Vorgehen

1. Ist-Wert mit dem Befehl oben auslesen.
2. Ergebnis mit Datum hier eintragen.
3. Abweichung entscheiden: ändern oder bewusst akzeptieren – beides mit Grund.
4. Erst dann wandert der Punkt nach [hardening.md](hardening.md).
