# Lessons Learned

Fünf Fehler, die mich Zeit gekostet haben – mit Ursache, Lösung und dem, was ich
seitdem anders mache. Wo eine Ursache nicht belegt ist, steht das dabei.

## 1. Der Container lief als root

**Fehler:** Der Dienst lief, alles funktionierte – aber der Prozess hatte uid 0.

**Ursache:** Im Dockerfile fehlte `USER`. Ohne diese Direktive startet Docker als root,
auch wenn die Dateien im Image einem anderen Benutzer gehören. Ein `chown` ändert den
Besitzer der Dateien, nicht den Benutzer des laufenden Prozesses.

**Lösung:** `USER node` vor dem `ENTRYPOINT`, die benötigten Verzeichnisse vorher
übergeben. Geprüft mit:

```bash
docker inspect <container> --format '{{.Config.User}}'   # leer = root
```

**Mitgenommen:** Ein leeres `Config.User` ist keine Aussage darüber, dass sich niemand
Gedanken gemacht hat – es ist die Aussage, dass der Default greift. Defaults muss man
nachsehen, nicht annehmen. Auf dem aktuellen Server sind fast alle Container noch root;
das steht als offener Punkt in [hardening-offen.md](hardening-offen.md).

## 2. Der Dienst war erreichbar – nur nicht von außen

**Fehler:** Der Container lief, `curl` im Container funktionierte, über die Domain kam
eine abgelehnte Verbindung. Das hat einen Abend gekostet.

**Ursache:** Die Anwendung lauschte nur auf der Loopback-Adresse im Container. Dockers
Port-Proxy kommt aber aus dem Bridge-Netz und erreicht genau diese Adresse nicht.

**Lösung:** Ein eigenes Netz mit fester IP, die Anwendung auf dieser Adresse starten –
oder die Anwendung so konfigurieren, dass sie auf `0.0.0.0` lauscht, während der Port
nach außen nur lokal veröffentlicht wird.

**Mitgenommen:** Von außen nach innen prüfen, nicht raten:

1. Löst der DNS-Eintrag auf den Server auf?
2. Nimmt der Proxy die Anfrage an?
3. Kommt sie im richtigen Netz an?
4. Lauscht die Anwendung auf der erwarteten Adresse?

Wer bei Schritt 4 anfängt, sucht lange.

## 3. Das Backup war nie getestet – und der Test lief auf ein gelöschtes Backup

**Fehler:** Ein Skript schrieb jede Nacht Daten weg, lief ohne Fehlermeldung – und wurde
deshalb für ein Backup gehalten. Zurückgespielt wurde nie etwas. Später gab es einen
täglichen Restore-Test, der aber zwei Tage lang auf ein am 25.10. gelöschtes Backup
zeigte: Der Wrapper ermittelte das neueste Backup, übergab den Pfad aber nicht an das
Skript. Im Log stand „Backup nicht gefunden“.

**Ursache:** „Das Skript läuft“ wurde mit „die Daten sind sicher“ gleichgesetzt. Beim
Wrapper fehlte die Übergabe von `"$LATEST"`; der Test fiel auf seinen hart codierten
Default zurück. Der Monitoring-Ping wurde nur bei Erfolg gesendet – deshalb blieb der
Fehler zwei Tage unbemerkt, bis jemand ins Log sah.

**Lösung:** Ein Restore-Test auf einem separaten Ziel, mit Erwartungswerten: Startseite
`200`, gleiche Beitragszahl, Bild lädt, Login möglich. Der Wrapper übergibt jetzt den
Backup-Pfad; der Test läuft täglich und meldet Erfolg an Healthchecks.io.

**Mitgenommen:** Ein Backup ist erst ein Backup, wenn der Restore einmal funktioniert
hat. Und ein Test, der immer wieder am selben Punkt scheitert, ist ein Monitoring-Problem,
kein Backup-Problem. Das Log ist die Quelle der Wahrheit, nicht der grüne Haken im
Dashboard.

## 4. Über tausend Zombie-Prozesse

**Fehler:** Auf dem Server standen am 03.11.2026 1.354 Zombie-Prozesse, alle mit dem
Elternprozess `node` (PID 1 des Ghost-Containers).

**Ursache:** Der Healthcheck war `wget -q --spider http://127.0.0.1:2368/`. Ghost leitet
wegen `url=https://…` mit `301` auf `https://127.0.0.1:2368/` um. `wget` folgte dem
Redirect und sprach TLS mit einem HTTP-Port – „wrong version number“. Jeder Fehlversuch
startete einen `ssl_client`, der als Zombie hängen blieb. Ghost als PID 1 sammelt keine
Kindprozesse ein. Bei einem Check alle 30 Sekunden waren es nach elf Stunden 1.354.

**Lösung:** Healthcheck auf `nc -z 127.0.0.1 2368` umgestellt, `init: true` für den
Container, neu gestartet. Danach: `healthy`, 0 Zombies, Startseite HTTP 200.

```yaml
init: true
healthcheck:
  test: ["CMD", "nc", "-z", "127.0.0.1", "2368"]
```

**Mitgenommen:** Die Prozessliste ist ein Symptom, keine Randnotiz. Ein Healthcheck, der
den Dienst nicht erreicht, ist kein Healthcheck – er ist ein Zombie-Generator. Und
`init: true` gehört in jeden Container, dessen PID 1 keine Kinder erntet.

## 5. Die Dokumentation lag nur im Kopf

**Fehler:** Nach einigen Wochen konnte ich nicht mehr sagen, warum ein Port genau so
gebunden war und welcher Container welche Daten hält. Jede Änderung begann mit Suchen.

**Ursache:** Die Konfiguration war da, aber die Begründung nicht. Ohne sie sieht man
beim nächsten Mal nur eine Zeile YAML und weiß nicht, ob man sie ändern darf.

**Lösung:** Diese Dateien. Jede Maßnahme mit Begründung, jede Lücke als `TODO`. Der
Test: Kann jemand anderes den Stack aus dem Repo nachbauen, ohne mich zu fragen?

Ein zweites Beispiel: NPM war manuell mit `docker network connect kisium-net npm`
verbunden. Beim Recreate über Compose war die Verbindung weg – der Blog antwortete mit
`502`, die anderen vier Hosts liefen weiter. Manuell gesetzter Zustand ist kein Zustand;
er muss in die Compose-Datei.

**Mitgenommen:** Dokumentation ist kein Papierkram, sondern Teil des Betriebs. Sie ist
dann gut, wenn sie auch die offenen Stellen nennt – nicht nur das, was funktioniert.

---

**Was hier bewusst fehlt:** erfundene Zahlen. Wo ich keine Messung habe, steht `TODO`.
Das ist unbequemer als eine glatte Erfolgsgeschichte, aber im Gespräch haltbar.
