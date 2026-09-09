import SwiftUI
import PhotosUI
import AurixCore

private enum CaptureMode: String, CaseIterable, Identifiable {
    case photo = "Foto", barcode = "Barcode", voice = "Sprache", manual = "Manuell"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .photo: return "camera"; case .barcode: return "barcode.viewfinder"
        case .voice: return "waveform"; case .manual: return "square.and.pencil" }
    }
}

struct CaptureView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let date: Date
    @State var slot: MealSlot
    @State private var mode = CaptureMode.photo
    @StateObject private var camera = CameraController()
    @StateObject private var speech = SpeechRecorder()
    @State private var busy = false
    @State private var busyLabel = "Dein Meal wird erkannt …"
    @State private var error: String?
    @State private var keySheet = false
    @State private var mealsSheet = false
    @State private var photo: PhotosPickerItem?
    @State private var typed = ""
    @State private var unknownBarcode: String?
    @State private var task: Task<Void, Never>?
    @State private var operation = UUID()
    @State private var finishingVoice = false
    @AppStorage("aiConsent") private var consent = false
    @State private var hasKey = Keychain.read() != nil
    private var aiReady: Bool { consent && hasKey }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Menu { ForEach(MealSlot.allCases) { value in Button(value.title) { slot = value } } } label: {
                        HStack(spacing: 8) { Image(systemName: "fork.knife"); Text(slot.title); Image(systemName: "chevron.down").font(.caption2) }.font(.system(size: 13, weight: .medium))
                    }.disabled(busy)
                    Spacer()
                    if !Calendar.current.isDateInToday(date) { Text(date.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(Theme.muted) }
                    Button { mealsSheet = true } label: { Image(systemName: "star").frame(width: 40, height: 36) }.accessibilityLabel("Meine Meals öffnen").disabled(busy)
                }.padding(.horizontal, 22)
                HStack(spacing: 6) {
                    ForEach(CaptureMode.allCases) { item in
                        Button { mode = item } label: {
                            VStack(spacing: 7) { Image(systemName: item.symbol).font(.system(size: 19)); Text(item.rawValue).font(.system(size: 11, weight: .medium)) }
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .foregroundStyle(mode == item ? Theme.background : Theme.muted)
                                .background(mode == item ? Theme.cyan : Theme.card, in: RoundedRectangle(cornerRadius: 17))
                        }.buttonStyle(PressStyle()).disabled(busy).accessibilityIdentifier("capture.\(item.id)")
                    }
                }.padding(.horizontal, 22)
                Group {
                    switch mode {
                    case .photo, .barcode: cameraContent
                    case .voice: voiceContent
                    case .manual: ManualCaptureForm(date: date, slot: slot, barcode: unknownBarcode) { dismiss() }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.padding(.top, 8).aurixScreen()
                .navigationTitle("Essen erfassen").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }.accessibilityLabel("Schliessen") } }
                .overlay {
                    if busy {
                        ZStack {
                            Theme.background.opacity(0.88).ignoresSafeArea()
                            VStack(spacing: 18) {
                                ProgressView().tint(Theme.cyan).scaleEffect(1.3)
                                Text(busyLabel).font(.system(size: 19, weight: .medium, design: .rounded))
                                Text("Wird direkt in \(slot.title) erfasst.").font(.footnote).foregroundStyle(Theme.muted)
                                Button("Abbrechen") { operation = UUID(); task?.cancel(); busy = false; camera.retryBarcode() }.font(.footnote).padding(.top, 10)
                            }.padding(26)
                        }
                    }
                }
                .alert("Noch nicht erfasst", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    if unknownBarcode != nil { Button("Produkt von Hand speichern") { mode = .manual; error = nil } }
                    Button("Nochmals versuchen", role: .cancel) { error = nil; camera.retryBarcode() }
                } message: { Text(error ?? "") }
                .sheet(isPresented: $keySheet, onDismiss: { hasKey = Keychain.read() != nil }) { AISettingsView() }
                .sheet(isPresented: $mealsSheet) { MealsView(date: date, slot: slot) }
        }
        .onAppear {
            camera.onPhoto = { data in analysePhoto(data) }
            camera.onBarcode = { code in scan(code) }
            speech.onTimedFinish = { finishVoice() }
            startMode()
        }
        .onChange(of: mode) { _, _ in operation = UUID(); task?.cancel(); finishingVoice = false; speech.cancel(); camera.stop(); startMode() }
        .onChange(of: phase) { _, value in
            if value != .active { speech.cancel(); camera.stop() }
            else if !busy { startMode() }
        }
        .onDisappear {
            operation = UUID(); task?.cancel(); speech.cancel(); camera.stop(); camera.onPhoto = nil; camera.onBarcode = nil; speech.onTimedFinish = nil
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            task?.cancel()
            task = Task {
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self), data.count <= 30_000_000,
                          let image = UIImage(data: data), let compressed = CameraController.compressed(image) else { throw AIService.ServiceError.imageTooLarge }
                    try Task.checkCancellation()
                    photo = nil; analysePhoto(compressed)
                } catch { if !Task.isCancelled { self.error = error.localizedDescription }; photo = nil }
            }
        }
    }
    private var cameraContent: some View {
        VStack(spacing: 18) {
            ZStack {
                CameraPreview(session: camera.session)
                if !camera.ready {
                    Theme.card
                    VStack(spacing: 14) {
                        Image(systemName: "camera").font(.system(size: 32)).foregroundStyle(Theme.cyan)
                        Text(camera.error ?? "Kamera wird gestartet …").font(.system(size: 14)).multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                        if camera.error != nil {
                            Button("iPhone-Einstellungen öffnen") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.caption)
                        }
                    }.padding(28)
                }
                if camera.ready {
                    RoundedRectangle(cornerRadius: 22).stroke(Theme.ivory.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [25, 170]))
                        .frame(width: 245, height: mode == .barcode ? 150 : 235)
                    VStack {
                        Spacer()
                        Text(mode == .barcode ? "Barcode ruhig ins Bild halten" : "Deine ganze Mahlzeit ins Bild")
                            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9).background(.black.opacity(0.5), in: Capsule()).padding(.bottom, 18)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 28)).frame(minHeight: 230, maxHeight: .infinity)
            if mode == .photo {
                if !aiReady { connectButton }
                HStack {
                    PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) { Image(systemName: "photo.on.rectangle").font(.system(size: 23)).frame(width: 56, height: 56) }.disabled(!aiReady).accessibilityLabel("Foto auswählen")
                    Spacer()
                    Button {
                        guard aiReady else { keySheet = true; return }
                        camera.capture()
                    } label: { Circle().fill(Theme.ivory).frame(width: 66, height: 66).padding(5).overlay(Circle().stroke(Theme.ivory.opacity(0.5), lineWidth: 2)) }
                        .buttonStyle(PressStyle()).disabled(!camera.ready).accessibilityLabel("Foto aufnehmen und erfassen")
                    Spacer(); Color.clear.frame(width: 56, height: 56)
                }
                Text("Foto → KI-Schätzung → eingetragen.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                Label("Erkannte Produkte werden sofort erfasst.", systemImage: "bolt.fill").font(.system(size: 13)).foregroundStyle(Theme.cyan).padding(.vertical, 10)
                Text("Open Food Facts · Menge danach jederzeit anpassbar.").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }.padding(.horizontal, 22).padding(.bottom, 20)
    }
    private var voiceContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Sag einfach,\nwas du gegessen hast.").font(.system(size: 29, weight: .medium, design: .rounded)).multilineTextAlignment(.center).padding(.top, 20)
                ZStack {
                    Circle().fill(Theme.cyan.opacity(0.07)).frame(width: 144, height: 144)
                    Image(systemName: speech.recording ? "waveform" : "mic").font(.system(size: 43, weight: .light)).foregroundStyle(Theme.cyan)
                        .symbolEffect(.pulse, options: .repeating, isActive: speech.recording && !reduceMotion)
                }
                if !aiReady { connectButton }
                else {
                    PrimaryButton(title: finishingVoice ? "Text abschliessen …" : speech.recording ? "Fertig & erfassen" : "Aufnahme starten", symbol: speech.recording ? "stop.fill" : "mic.fill", disabled: speech.preparing || finishingVoice) {
                        if speech.recording { finishVoice() }
                        else { task = Task { await speech.start() } }
                    }
                }
                if speech.recording || !speech.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if speech.recording { Label("AUFNAHME · MAX. 45 SEK.", systemImage: "record.circle").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.carbs) }
                        Text(speech.transcript.isEmpty ? "Ich höre zu …" : speech.transcript).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                        if !speech.recording && !busy {
                            Button("Diesen Text erfassen") { analyseText(speech.transcript) }.font(.subheadline)
                        }
                    }.padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                }
                if let error = speech.error { Text(error).font(.footnote).foregroundStyle(Theme.carbs) }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Oder kurz tippen").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    TextField("Zwei Eier, drei Toast und ein Proteindrink", text: $typed, axis: .vertical).lineLimit(3...5).padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    Button { analyseText(typed) } label: { Label("Mit KI erfassen", systemImage: "sparkles").frame(maxWidth: .infinity).padding(14) }
                        .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.recording)
                }
                Text("Spracherkennung über Apple, wenn verfügbar auf dem Gerät. Nur der Text geht zur KI. Es bleibt keine Audiodatei zurück.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 22).padding(.bottom, 25)
        }.scrollDismissesKeyboard(.interactively).keyboardDone()
    }
    private var connectButton: some View {
        Button { keySheet = true } label: {
            HStack { Image(systemName: "sparkles"); Text("KI einmal verbinden"); Spacer(); Image(systemName: "arrow.right") }.font(.system(size: 14, weight: .medium)).padding(16).background(Theme.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func startMode() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-screenshots-dashboard") { return }
        #endif
        guard phase == .active else { return }
        if mode == .photo { camera.start(.photo) }
        if mode == .barcode { camera.start(.barcode) }
    }
    private func analysePhoto(_ data: Data) {
        guard !busy, mode == .photo, phase == .active else { return }
        guard aiReady else { keySheet = true; return }
        runAI(text: "Erfasse die ganze sichtbare Mahlzeit als einen Eintrag.", image: data, source: .photo)
    }
    private func analyseText(_ text: String) {
        guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard aiReady else { keySheet = true; return }
        runAI(text: text, source: .voice)
    }
    private func finishVoice() {
        guard !busy, !finishingVoice else { return }
        finishingVoice = true
        task = Task {
            let text = await speech.finish()
            finishingVoice = false
            guard !Task.isCancelled else { return }
            if text.isEmpty { error = "Ich habe kein Essen verstanden. Versuche es nochmals oder tippe eine kurze Beschreibung." }
            else { analyseText(text) }
        }
    }
    private func runAI(text: String, image: Data? = nil, source: EntrySource) {
        busy = true; busyLabel = "Dein Meal wird erkannt …"; unknownBarcode = nil
        let run = UUID(); operation = run
        let targetSlot = slot
        task = Task {
            defer { if operation == run { busy = false } }
            do {
                let estimate = try await AIService.estimate(text: text, image: image)
                try Task.checkCancellation()
                guard operation == run else { return }
                let entry = try estimate.entry(date: date, slot: targetSlot, source: source)
                if store.add(entry) { dismiss() }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func scan(_ code: String) {
        guard !busy, mode == .barcode, phase == .active else { return }
        busy = true; busyLabel = "Produkt wird erkannt …"; unknownBarcode = code
        let run = UUID(); operation = run
        let targetSlot = slot
        task = Task {
            defer { if operation == run { busy = false } }
            do {
                if let saved = store.meals.first(where: { $0.barcode == code }) {
                    if store.add(saved.entry(date: date, slot: targetSlot)) { dismiss() }
                    return
                }
                let product = try await BarcodeService.shared.product(for: code)
                try Task.checkCancellation()
                guard operation == run else { return }
                let portion = try ProductResolver.resolve(product)
                let entry = FoodEntry(name: product.name, nutrition: portion.nutrition, date: date, slot: targetSlot,
                    source: .barcode, portion: portion.label,
                    note: portion.assumed ? "Keine Portionsgrösse hinterlegt. Automatisch mit 100 \(portion.unit) erfasst; Menge bei Bedarf ändern." : "Nährwerte: Open Food Facts.",
                    barcode: code, estimated: portion.assumed)
                if store.add(entry) { dismiss() }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct ManualCaptureForm: View {
    @EnvironmentObject private var store: AppStore
    var date: Date
    var slot: MealSlot
    var barcode: String?
    var completion: () -> Void
    @State private var name = ""
    @State private var portion = "1 Portion"
    @State private var nutrition = Nutrition.zero
    @State private var saveMeal = false
    var body: some View {
        Form {
            Section {
                TextField("Was hast du gegessen?", text: $name).submitLabel(.done)
                TextField("Menge / Portion", text: $portion).submitLabel(.done)
            }
            Section("Nährwerte für deine Portion") {
                NumberField(title: "Kalorien", value: $nutrition.calories, unit: "kcal")
                NumberField(title: "Protein", value: $nutrition.protein)
                NumberField(title: "Carbs", value: $nutrition.carbs)
                NumberField(title: "Fette", value: $nutrition.fat)
            }
            Section {
                Toggle("Als eigenes Meal speichern", isOn: $saveMeal)
                if barcode != nil { Text("Wird unter diesem Barcode gespeichert und beim nächsten Scan wiedererkannt.").font(.footnote).foregroundStyle(Theme.muted) }
            }
            Section {
                Button {
                    let entry = FoodEntry(name: name.trimmingCharacters(in: .whitespacesAndNewlines), nutrition: nutrition, date: date, slot: slot, portion: portion, barcode: barcode)
                    guard store.add(entry) else { return }
                    if saveMeal || barcode != nil { store.saveMeal(SavedMeal(name: entry.name, nutrition: nutrition, portion: portion, barcode: barcode)) }
                    completion()
                } label: { Label("Jetzt erfassen", systemImage: "plus.circle.fill").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !nutrition.isValid)
            }
        }.scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively).keyboardDone()
    }
}
