# AURIX

**Food fuels more than just today.**

A personal, native iPhone nutrition tracker. SwiftUI, iOS 17+, no paid dependencies or required backend.

## In Xcode starten

1. Dieses Repository klonen und **`Aurix.xcodeproj`** öffnen (nicht nur `Package.swift`).
2. Scheme **Aurix**, dein iPhone als Run-Ziel auswählen.
3. Unter **Aurix → Signing & Capabilities → Team** dein Apple-Developer-Team auswählen. Automatisches Signing ist vorbereitet. Falls die Bundle-ID bereits vergeben ist, `ch.mauruspichler.aurix` auf deine eigene ID ändern.
4. Auf dem iPhone den Entwicklermodus aktivieren, falls Xcode ihn verlangt. **⌘R**.
5. Onboarding abschliessen. Für Foto/Sprache einmal unter **Einstellungen → KI verbinden** deinen OpenAI-API-Schlüssel einsetzen und die Übertragung aktivieren.

Der Schlüssel ist absichtlich nicht in Repository, Build-Konfiguration oder App-Binary enthalten. Die private Einzelgeräte-App speichert ihn ausschliesslich im iPhone-Schlüsselbund (`WhenUnlockedThisDeviceOnly`). Es gibt keinen erforderlichen Server. Für eine Weitergabe der App an andere Nutzer wäre eine Server-Authentifizierung eine eigene nächste Aufgabe.

Kamera, Barcode und Mikrofon auf dem echten iPhone testen. Der Simulator unterstützt die manuelle Erfassung sowie die Fotomediathek mit importierten Bildern; er ersetzt keinen Kamera-/Mikrofontest.

## Funktionen

- Atmosphärischer Berg-Start, eigens erstelltes AURIX-Icon.
- Onboarding mit einer Frage pro Bildschirm, Auswahlkarten, Zahlenrädern, sanften Übergängen und Rücknavigation.
- Vier gleich grosse Anzeigen für Kalorien, Protein, Carbs und Fette.
- Tagebuch mit Morgenessen, Mittagessen, Abendessen und Snacks. Rückwirkende Einträge und Kalenderauswahl.
- **Foto:** verkleinern, Metadaten entfernen, OpenAI-Schätzung direkt speichern.
- **Barcode:** Open Food Facts abfragen, automatisch eine ganze Einzelpackung bzw. deklarierte Portion erfassen. Mehrfachpackungen werden separat berücksichtigt. Fehlt eine Portionsgrösse, explizit gekennzeichnete 100-g/ml-Standardmenge.
- **Sprache:** Apple-Spracherkennung (`de-CH`, auf dem Gerät wenn unterstützt), daraus KI-Meal; alternativ Beschreibung tippen.
- **Manuell:** Name, Portion und vier Nährwerte. Eigene Meals, Wiederholen, Bearbeiten, Löschen und schnelle Mengenfaktoren.
- Unbekanntes Barcode-Produkt einmal manuell hinterlegen und künftig wiedererkennen.
- Sofortiges Speichern mit optionalem Rückgängig, kein verpflichtender KI-Prüfschritt.
- Sportliche Tracking-Streaks und kleine Meilensteine, ohne zusätzliche Benachrichtigungen.
- Bearbeitbare Tagesziele, lokaler Export/Import mit ID-basierter Deduplizierung.

## Speicherung und Kosten

Das Tagebuch ist eine kompakte, versionierte JSON-Datei im privaten Application-Support-Verzeichnis. Änderungen werden atomar gespeichert; eine einzige rollierende Sicherung dient als Rückfall. Bei beschädigten Dateien wird nicht stillschweigend ein leeres Tagebuch angelegt.

Keine Meal-Fotos und keine Audioaufnahmen werden dauerhaft gespeichert. Bilder existieren nur für den aktuellen Analysevorgang, max. 1280 px Kantenlänge. Der Produktcache ist auf **200 Produkte / 30 Tage** begrenzt, überschreibt dieselbe Datei und liegt im vom System löschbaren Cache-Verzeichnis. Netzwerk-Sessions verwenden keinen dauerhaften HTTP-Cache. Das Tagebuch selbst bleibt erhalten; es wächst ungefähr linear mit den Einträgen. Gerätebackups können es sichern, eine iCloud-Synchronisierung ist nicht implementiert.

OpenAI wird nur für Foto bzw. die Interpretation einer gesprochenen/getippten Mahlzeit aufgerufen. Standard: **GPT-4.1 mini**, Responses API, striktes JSON-Schema, `store: false`, max. 600 Ausgabetokens, kein Gesprächsverlauf. Das gewählte Modell ist zentral in `Sources/AurixCore/AIContract.swift` konfiguriert. Modellverfügbarkeit und Guthaben hängen vom API-Projekt ab.

Das lokale Tageslimit zählt **Anfragen, auch fehlgeschlagene**, standardmässig 20, einstellbar 5–50. Es ist kein Preisversprechen und kein kontoweites Ausgabenlimit. Es gibt keine automatischen Wiederholungsversuche.

## Datenqualität

Foto-/Sprachnährwerte bleiben Schätzungen. Sie sind sichtbar gekennzeichnet und korrigierbar. Ein Bild liefert keine verlässliche Messung der Portion oder versteckter Zutaten. Fehlende Barcode-Makros werden als Fehler behandelt, nicht als null eingesetzt. Open Food Facts kann unvollständig sein. Eigene Meals und manuelle Werte funktionieren offline; neue Produkte und KI benötigen Internet.

Die Bedarfsschätzung verwendet Mifflin–St Jeor mit auswählbarer Aktivität, moderatem Zielaufschlag/-abschlag und manuell überschreibbaren Makrozielen. Sie ist ein Ausgangswert, keine Messung oder medizinische Beratung. Ein Zielgewicht verändert das Tagebuch nicht automatisch. Wasser, HealthKit, Gewichtsdiagramme, Cloud-Sync und Erinnerungen sind bewusst noch nicht eingebaut.

## Entwicklung und Prüfung

Keine externen Swift-Pakete. `AurixCore` ist das lokale Swift-Package mit Datenmodell, Portionslogik, Zielberechnung und API-Vertrag. App-spezifische Kamera-, Speicher- und UI-Komponenten liegen unter `Aurix/`.

```sh
swift test
xcodebuild -project Aurix.xcodeproj -scheme Aurix \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions prüft die Kernlogik, baut die iOS-App und führt einen UI-Smoke-Test mit Screenshot-Anhängen aus. Den Lauf und das temporäre Screenshot-Artefakt findest du unter **Actions → iOS build and verification**. Es wird kein API-Schlüssel im CI benötigt oder übertragen. Echte OpenAI-Aufrufe und physische Kamera-/Mikrofonerfassung sind von diesen Tests nicht abgedeckt.

Das fertige Xcode-Projekt ist eingecheckt. Nach Änderungen an der Dateistruktur lässt es sich mit `python3 scripts/generate_project.py` ohne Zusatzpaket neu erzeugen.

## Quellen

- [OpenAI: Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) und [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini).
- [OpenAI: API-Datenverarbeitung](https://developers.openai.com/api/docs/guides/your-data). `store: false` bedeutet nicht pauschal keine serverseitige Aufbewahrung.
- [Open Food Facts: API](https://openfoodfacts.github.io/openfoodfacts-server/api/) und [Daten / ODbL](https://world.openfoodfacts.org/data). Der Cache ist von den persönlichen Daten getrennt; Produktdaten werden nicht als mitgelieferte proprietäre Datenbank veröffentlicht.
- [Apple: Spracherkennung](https://developer.apple.com/tutorials/app-dev-training/transcribing-speech-to-text).
- [Apple: Schlüsselbundzugriff auf diesem Gerät](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly).
- [Mifflin et al., 1990](https://pubmed.ncbi.nlm.nih.gov/2305711/).

## Design

Midnight, warme Elfenbeintöne und dezentes Cyan. Die Landschaft prägt den Start; die Einführung nutzt danach einen ruhigen Verlauf, kurze Übergänge und native Gewichtsrollen für ganze Kilos plus `.0` / `.5`. Im Alltag bestimmen Ziele und Mahlzeiten die Oberfläche. Die drei Hauptbereiche sind über Apples native Tableiste erreichbar. Bewegung respektiert „Bewegung reduzieren“. Eigene generierte Markenassets sind direkt in den Asset-Katalog eingebunden. Die Herkunft und Gestaltungsbriefings stehen in `docs/design.md`.
