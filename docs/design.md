# AURIX — Designentscheidungen

Die App wird nur für ihren Besitzer gebaut. Vier gleichwertige Meter, schnelle Erfassung, wenige Oberflächenelemente. Keine Maskottchen. Bergwelt, Weite und warmes Horizontlicht bilden den Markenraum. Morgenessen / Mittagessen / Abendessen / Snacks sind sichtbar, die Zuordnung ist per Uhrzeit vorausgewählt und manuell änderbar.

Das Bergmotiv wurde mit dem eingebauten Imagegen erstellt. Das finale Logo wurde auf ausdrücklichen Nutzerwunsch aus seiner hochgeladenen AURIX-Referenz mit Imagegen freigestellt und originalgetreu nachgebildet: cyanblaues A mit gerundetem Gipfel und geschwungenem Einschnitt. Die App verwendet diese verbindliche Referenzform. Für den Asset-Katalog wurden Format, Abmessungen und beim App-Icon der notwendige deckende Hintergrund angepasst:

- `Aurix/Resources/Assets.xcassets/Summit.imageset/summit.jpg`
- `Aurix/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- `Aurix/Resources/Assets.xcassets/AppMark.imageset/mark.png` (kleine Variante desselben Icons)

## Bergmotiv-Briefing

Photorealistic cinematic portrait 1024×1536; vast dark alpine mountain summit at dawn, very small solitary human on a rocky peak, multiple ridges receding into valley mist, narrow warm golden horizon. Charcoal/midnight slate, muted cyan shadows, warm ivory sunlight. Top clean dark sky for app typography, near-black foreground for controls. No text, logo, UI, monk, mascot, neon beams or exaggerated effects.

## Icon-Briefing

Exact source: the top-left A emblem in the user's AURIX brand board, repeated on the first phone. Preserve rounded summit, continuous sloping right leg, detached curved lower-left segment, and smooth swooping negative-space incision. Pale ice-cyan top to vivid sky-blue bottom gradient. Extract symbol only onto transparent background. No added ivory trail, conventional crossbar, words, landscape, frame, or shadow. SwiftUI renders the spaced light AURIX wordmark separately. The iOS icon composites the same mark on midnight; iOS supplies rounding.

## Verhalten

Onboarding: ein Thema pro Schritt; Zahlenräder für Körperdaten, grosse Karten für Ziel/Aktivität, keine animierten Wartezeiten. Dashboard: 2×2 Meter gleicher Grösse mit klarer Ist/Ziel-Beschriftung; Füllstände animieren nur bei Wertänderung. Einträge werden unmittelbar gespeichert; Rückgängig bleibt kurz erreichbar. Streak misst aufeinanderfolgende Tage mit erfassten Mahlzeiten, nicht „gutes“ oder „schlechtes“ Essen.

Nach dem ersten Gerätetest: Das Bergmotiv bewegt sich nur kurz beim Einstieg. Die Fragen haben einen ruhigen Verlaufshintergrund und kurze Überblendungen (0.18 Sekunden, bei „Bewegung reduzieren“ ohne Animation). Gewicht und Zielgewicht verwenden einen nativen `UIPickerView` mit zwei Komponenten: ganze Kilogramm und `.0` / `.5`. UIKit erzeugt die sichtbaren Zeilen bei Bedarf. Der Bereich bleibt 40–200 kg; bei 200 kg entfällt `.5`.

Die Hauptnavigation ist ein systemeigener `TabView` mit Heute, Erfassen und Meine Meals. iOS bestimmt Gestaltung, Abstände und die Position über dem Home-Indikator. Es gibt keine selbst gezeichnete Ersatzleiste. Eine Erfassung über den Tab führt nach dem Speichern zu Heute; die Plusknöpfe bei Mahlzeiten öffnen weiterhin eine schliessbare Erfassung. Beim Verlassen des Erfassen-Tabs werden Kamera, Mikrofon und laufende Analyse beendet und temporäre Daten freigegeben.
