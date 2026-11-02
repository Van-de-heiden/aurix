# DAYFUEL — Design 2.0

## Marke

DAYFUEL verbindet tägliches Essen mit Energie und persönlichem Fortschritt. „Fuel your everyday“ ist die englische Markenlinie; die Bedienung bleibt auf Schweizer Hochdeutsch. Der vom Nutzer gewählte Stil ist klar und sportlich.

Das Zeichen besteht aus drei nach vorne geschnittenen Balken. Der mittlere ist höher: Bewegung und kontinuierlicher Fortschritt. `FuelMark` zeichnet die Geometrie direkt in SwiftUI. `scripts/generate_brand.swift` reproduziert daraus App-Icon (1024 px, deckend) und kleines Markenasset (256 px, transparent). Keine Schrift oder Landschaft im Icon; iOS rundet es selbst.

## Gestaltung

- Hintergrund: Graphit (sRGB 0.055 / 0.065 / 0.060).
- Karten: dunkles Grün-Grau (0.100 / 0.115 / 0.105).
- Primärer Akzent: Lime (0.82 / 0.98 / 0.39), dunkle Schrift auf Primärbuttons.
- Text: gebrochenes Weiss; Sekundärtext mit klarer Abstufung.
- Protein: Lavendel; Carbs: Apricot; Fette: Mint. Zahlen und Beschriftungen tragen Information auch ohne Farbe.
- Wortmarke: fett, kursiv, eng. Überschriften: gerundete Systemschrift mit deutlicher Hierarchie. Zahlen: tabellarische Ziffern.
- Kartenradien 17–26 pt, klare Abstände, kurze Übergänge. Keine dauerhafte Animation oder Warteinszenierung.

## Screens

Onboarding: typografischer Einstieg mit grosser Aussage, danach ein Thema je Schritt. Native Gewichtsrollen und Zielberechnung bleiben erhalten.

Heute: kompakter Markenheader, Datum, vier gleichwertige Nährwertkarten mit Fortschrittsbalken, direkter Foto- und Barcode-Einstieg, Körpermessungen und Mahlzeiten. Tages- und Kalendernavigation bleiben bedienbar. Ist und Ziel stehen immer sichtbar dabei; ein überschrittenes Ziel wird als Differenz angezeigt.

Erfassen: vier Modi bleiben sichtbar. Der Scanner hat ruhige Zielmarkierung, Taschenlampe und immer erreichbare Barcode-Eingabe. Fehler unterscheiden ungültige Nummer, unbekanntes Produkt, unvollständige Daten und Nichterreichbarkeit. Bekannte eigene Produkte funktionieren offline. Unbekannte Barcodes lassen sich einmal manuell hinterlegen. Ein Moduswechsel verwirft die alte Barcode-Zuordnung.

Meine Meals: eigene Suchzeile, klarer Hinzufügen-Button, gespeicherte Meals und letzte Mahlzeiten als Karten. Leere Bereiche und erfolglose Suchen erhalten verständliche Zustände. Bearbeiten und Löschen bleiben im Kontextmenü erreichbar.

Verlauf: native Segmente für Messart und Zeitraum, grosse letzte Messung, Veränderung, echte Tageswerte und 7-Tage-Mittel. Die Legende benennt Serien mit Text und Form. Kein Auffüllen fehlender Messungen.

Einstellungen: neues Zeichen und DAYFUEL-Texte einschliesslich Sicherungsexport, Berechtigungsbeschreibungen und Version. Das bestehende Speicherformat, Bundle-ID und Schlüsselbund bleiben kompatibel.

## Technische Identität

`Aurix.xcodeproj`, Scheme `Aurix`, Modul `AurixCore`, `ch.mauruspichler.aurix`, der Application-Support-Ordner und der Schlüsselbunddienst behalten ihre technischen Namen. Ein Update ersetzt so die bisherige App und kann deren Daten weiter lesen. Die sichtbare App heisst DAYFUEL.
