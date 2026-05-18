# Automatischer APK-Release mit GitHub Actions

## Was wurde eingerichtet?
- Im Ordner `.github/workflows` liegt jetzt die Datei `release-apk.yml`.
- Diese Datei definiert einen Workflow, der automatisch ausgeführt wird, wenn du ein neues Tag wie `v1.2.3` ins GitHub-Repo pusht.
- Der Workflow baut das APK, erzeugt das `update.json` und veröffentlicht beides als Release auf GitHub.

## Wie nutzt du das?

### 1. Tag erstellen und pushen

1. Stelle sicher, dass alle Änderungen im Repo sind und gepusht wurden.
2. Erstelle ein neues Tag (z.B. für Version 1.2.3):
   ```sh
   git tag v1.2.3 -m "Kurze Release-Beschreibung"
   git push origin v1.2.3
   ```
3. Nach dem Push startet GitHub Actions automatisch den Workflow.

### 2. Was passiert automatisch?
- Das APK wird gebaut (`flutter build apk --release`).
- Die Datei `update.json` wird mit der neuen Version, Download-Link und Release-Notes erzeugt.
- APK und `update.json` werden als Assets im neuen Release auf GitHub veröffentlicht.

### 3. Wo findest du die Dateien?
- Im Bereich "Releases" deines GitHub-Repos findest du das neue Release mit APK und update.json.
- Deine App kann das update.json wie bisher auslesen.

## Vorteile
- Kein manuelles Hochladen mehr nötig.
- Immer konsistente Releases und Update-Infos.
- Weniger Fehlerquellen.

## Voraussetzungen
- Dein Projekt muss auf GitHub liegen.
- Du brauchst keine weiteren Einstellungen – der Workflow funktioniert mit dem Standard-GitHub-Token.

## Anpassungen
- Für signierte APKs oder andere Plattformen kann der Workflow erweitert werden.
- Die Release-Notes werden aus dem Tag-Text übernommen.

---
Fragen? Einfach im Code nachschauen oder hier nachfragen!