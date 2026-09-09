import SwiftUI
import UniformTypeIdentifiers
import AurixCore

struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var ai = false
    @State private var goals = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document: ArchiveDocument?
    @State private var status: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("AppMark").resizable().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.profile?.name ?? "AURIX").font(.title3.bold())
                            Text(store.profile?.direction.title ?? "Dein Fortschritt").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Dein Setup") {
                    Button { goals = true } label: { Label("Profil & Tagesziele", systemImage: "target") }
                    Button { ai = true } label: { Label("KI verbinden", systemImage: "sparkles") }
                }
                Section("Deine Daten") {
                    LabeledContent("Tagebuch & Sicherung", value: store.storageDescription)
                    LabeledContent("Mahlzeiten", value: "\(store.entries.count)")
                    Button { do { document = ArchiveDocument(data: try store.encoded()); exporting = true } catch { status = error.localizedDescription } } label: { Label("Sicherung exportieren", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Sicherung importieren", systemImage: "square.and.arrow.down") }
                    Button {
                        Task { await BarcodeService.shared.clear(); status = "Produktcache geleert. Dein Tagebuch bleibt erhalten." }
                    } label: { Label("Produktcache leeren", systemImage: "arrow.clockwise") }
                    Text("Dein Tagebuch bleibt lokal und kann über die iPhone-Gerätesicherung gesichert werden. Eine lokale Rückfallkopie wird überschrieben. Produktcache: höchstens 200 Produkte, höchstens 30 Tage. Keine gespeicherten Meal-Fotos oder Audiodateien.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("AURIX") {
                    Text("Food fuels more than just today.").font(.system(size: 16, weight: .medium, design: .rounded))
                    Text("Version 1.0 · Für deinen nächsten Gipfel.").font(.caption).foregroundStyle(Theme.muted)
                    Link("Produktdaten: Open Food Facts · ODbL", destination: URL(string: "https://world.openfoodfacts.org/data")!)
                    Link("OpenAI: Umgang mit API-Daten", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                }
            }.scrollContentBackground(.hidden).aurixScreen().navigationTitle("Einstellungen")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
                .sheet(isPresented: $ai) { AISettingsView() }
                .sheet(isPresented: $goals) { GoalsEditor(profile: store.profile ?? UserProfile()) }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "AURIX-Sicherung") { result in
                    if case .failure(let error) = result { status = error.localizedDescription }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else { throw CoreError.invalidArchive }
                        try store.importArchive(Data(contentsOf: url))
                        status = "Sicherung importiert. Bestehende Einträge und Ziele bleiben erhalten; fehlende Einträge wurden ergänzt."
                    } catch { status = error.localizedDescription }
                }
                .alert("AURIX", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
                    Button("OK") { status = nil }
                } message: { Text(status ?? "") }
        }.task { await BarcodeService.shared.maintenance() }
    }
}

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var saved = Keychain.read() != nil
    @State private var error: String?
    @AppStorage("aiConsent") private var consent = false
    @AppStorage("aiDailyLimit") private var limit = 20
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(Theme.cyan)
                        Text("Einmal verbinden.\nEinfach erfassen.").font(.system(size: 26, weight: .medium, design: .rounded))
                        Text("Für Foto- und Spracherfassung nutzt AURIX deinen eigenen OpenAI-Zugang.").font(.subheadline).foregroundStyle(Theme.muted)
                    }.padding(.vertical, 12)
                }
                Section("Dein privater Schlüssel") {
                    if saved { Label("Schlüssel im iPhone-Schlüsselbund gespeichert", systemImage: "checkmark.shield").font(.subheadline).foregroundStyle(Theme.cyan) }
                    SecureField(saved ? "Neuen Schlüssel einsetzen" : "OpenAI-API-Schlüssel einsetzen", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().submitLabel(.done)
                    Text("Nur auf diesem iPhone. Der Schlüssel wird nicht mit deinem Tagebuch exportiert.").font(.caption).foregroundStyle(Theme.muted)
                }
                Section("KI-Erfassung erlauben") {
                    Text("Bei einem Foto wird das verkleinerte Bild an OpenAI gesendet. Bei Sprache oder Texteingabe nur die Mahlzeitenbeschreibung. Dein Profil und Tagebuch werden nicht mitgesendet. Die Werte sind Schätzungen und werden automatisch eingetragen.").font(.footnote)
                    Toggle("Diese Übertragung erlauben", isOn: $consent)
                    Link("Details zur API-Datenverarbeitung", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!).font(.footnote)
                }
                Section("Verbrauch im Griff") {
                    Stepper("Max. \(limit) KI-Anfragen pro Tag", value: $limit, in: 5...50, step: 5)
                    LabeledContent("Heute angefragt", value: "\(AIService.requestsToday)")
                    Text("Das Limit gilt für Anfragen aus dieser App, auch fehlgeschlagene. Es ist kein kontoweites Ausgabenlimit. Barcode und manuelle Einträge brauchen keine KI.").font(.caption).foregroundStyle(Theme.muted)
                }
                Section {
                    Button {
                        do {
                            if !key.isEmpty { try Keychain.save(key); key = ""; saved = true }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    } label: { Text("Verbindung speichern").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 6) }.disabled((key.isEmpty && !saved) || !consent)
                    if saved {
                        Button("Schlüssel entfernen", role: .destructive) {
                            do { try Keychain.delete(); saved = false; key = ""; consent = false } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).aurixScreen().keyboardDone()
                .navigationTitle("KI verbinden").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schliessen") { key = ""; dismiss() } } }
                .alert("Verbindung", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }.onDisappear { key = "" }
    }
}

struct GoalsEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var profile: UserProfile
    var body: some View {
        NavigationStack {
            Form {
                Section("Du") {
                    TextField("Vorname", text: $profile.name)
                    Stepper("Alter: \(profile.age)", value: $profile.age, in: 18...100)
                    NumberField(title: "Grösse", value: $profile.height, unit: "cm")
                    NumberField(title: "Gewicht", value: $profile.weight, unit: "kg")
                    NumberField(title: "Zielgewicht", value: $profile.targetWeight, unit: "kg")
                    Picker("Ziel", selection: $profile.direction) { ForEach(GoalDirection.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Bedarfsformel", selection: $profile.maleFormula) { Text("Männlich").tag(true); Text("Weiblich").tag(false) }
                    Picker("Aktivität", selection: $profile.activity) {
                        Text("Ruhig").tag(1.2); Text("Etwas Bewegung").tag(1.375); Text("Regelmässig aktiv").tag(1.55); Text("Sehr aktiv").tag(1.725)
                    }
                }
                Section("Deine Tagesziele") {
                    NumberField(title: "Kalorien", value: $profile.goals.calories, unit: "kcal")
                    NumberField(title: "Protein", value: $profile.goals.protein)
                    NumberField(title: "Carbs", value: $profile.goals.carbs)
                    NumberField(title: "Fette", value: $profile.goals.fat)
                    Button("Vorschlag aus Profil neu berechnen") { profile.goals = GoalCalculator.suggested(for: profile) }
                    Text("Die Berechnung ist ein Startwert. Geänderte Körperdaten passen deine Ziele erst an, wenn du neu berechnest. Makros und Kalorien bleiben einzeln einstellbar.").font(.caption).foregroundStyle(Theme.muted)
                }
            }.scrollContentBackground(.hidden).aurixScreen().scrollDismissesKeyboard(.interactively).keyboardDone()
                .navigationTitle("Profil & Ziele").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { store.saveProfile(profile); if store.profile == profile { dismiss() } }.disabled(!profile.isValid) }
                }
        }
    }
}
