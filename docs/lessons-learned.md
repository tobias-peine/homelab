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
docker exec <container> id
```

**Mitgenommen:** Ein leeres `Config.User` ist keine Aussage darüber, dass sich niemand
Gedanken gemacht hat – es ist die Aussage, dass der Default greift. Defaults muss man
nachsehen, nicht annehmen.

## 2. Der Dienst war erreichbar – nur nicht von außen

**Fehler:** Der Container lief, `curl` im Container funktionierte, über die Domain kam
eine abgelehnte Verbindung. Das hat einen Abend gekostet.

**Ursache:** Die Anwendung lauschte nur auf der Loopback-Adresse im Container. Dockers
Port-Proxy kommt aber aus dem Bridge-Netz und erreicht genau diese Adresse nicht.

**Lösung:** Ein eigenes Netz mit fester IP, die Anwendung auf dieser Adresse starten –
oder die Anwendung so konfigurieren, dass sie auf `0.0.0.0` lauscht, während der Port
nach außen weiterhin nur lokal veröffentlicht wird.

**Mitgenommen:** Von außen nach innen prüfen, nicht raten:

1. Löst der DNS-Eintrag auf den Server auf?
2. Nimmt der Proxy die Anfrage an?
3. Kommt sie im richtigen Netz an?
4. Lauscht die Anwendung auf der erwarteten Adresse?

Wer bei Schritt 4 anfängt, sucht lange.

## 3. Das Backup war nie getestet

**Fehler:** Ein Skript schrieb jede Nacht Daten weg, lief ohne Fehlermeldung – und wurde
deshalb für ein Backup gehalten. Zurückgespielt wurde nie etwas.

**Ursache:** „Das Skript läuft“ wurde mit „die Daten sind sicher“ gleichgesetzt. Ein
erfolgreicher `cp`/`mysqldump` beweist nur, dass der Befehl beendet wurde, nicht dass
die Sicherung vollständig oder wiederherstellbar ist.

**Lösung:** Ein Restore-Test auf einem separaten Ziel, mit Erwartungswerten: Startseite
`200`, gleiche Beitragsanzahl, Bild lädt, Login möglich. Der Ablauf steht in
[backup-restore.md](backup-restore.md).

**Mitgenommen:** Ein Backup ist erst ein Backup, wenn der Restore einmal funktioniert
hat. Alles davor ist eine Annahme.

## 4. Über tausend Zombie-Prozesse

**Fehler:** Auf dem Server standen am 02.11.2026 laut Login-Banner:

```
There are 1057 zombie processes.
Memory usage: 63%
Swap usage:   48%
Processes:    1262
```

**Ursache:** Nicht gefunden. Ein Zombie ist ein beendeter Kindprozess, dessen Parent
den Exit-Status nicht abholt (`wait()`). Das kann ein Container mit falschem
PID-Handling sein, ein Dienst in einer Schleife oder ein Prozess, der Kinder startet
und nicht einsammelt. Eine Vermutung ist keine Diagnose.

**Lösung:** Offen. Nächster Schritt: Parent-Prozesse der Zombies bestimmen und
eingrenzen, ob sie aus einem Container kommen.

```bash
ps -eo stat,ppid,pid,comm | awk '$1 ~ /^Z/ {print}'
docker stats --no-stream
```

**Mitgenommen:** Die Prozessliste ist ein Symptom, keine Randnotiz. Wer nur CPU und
RAM ansieht, übersieht, dass 1.057 Prozesse auf das Einsammeln warten – und dass der
Swap zu 48 % voll ist, während der Arbeitsspeicher zu 63 % belegt ist.

## 5. Die Dokumentation lag nur im Kopf

**Fehler:** Nach einigen Wochen konnte ich nicht mehr sagen, warum ein Port genau so
gebunden war und welcher Container welche Daten hält. Jede Änderung begann mit Suchen.

**Ursache:** Die Konfiguration war da, aber die Begründung nicht. Ohne sie sieht man
beim nächsten Mal nur eine Zeile YAML und weiß nicht, ob man sie ändern darf.

**Lösung:** Diese Dateien. Jede Maßnahme mit Begründung, jede Lücke als `TODO`. Der
Test: Kann jemand anderes den Stack aus dem Repo nachbauen, ohne mich zu fragen?

**Mitgenommen:** Dokumentation ist kein Papierkram, sondern Teil des Betriebs. Sie ist
dann gut, wenn sie auch die offenen Stellen nennt – nicht nur das, was funktioniert.

---

**Was hier bewusst fehlt:** erfundene Zahlen. Wo ich keine Messung habe, steht `TODO`.
Das ist unbequemer als eine glatte Erfolgsgeschichte, aber im Gespräch haltbar.
