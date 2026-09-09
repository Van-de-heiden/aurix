import SwiftUI
import AurixCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var archive = Archive()
    @Published var error: String?
    @Published var toast: String?
    @Published private(set) var undoEntry: FoodEntry?
    @Published private(set) var cannotLoad = false
    private let file: URL
    private let backup: URL
    private var toastTask: Task<Void, Never>?

    var profile: UserProfile? { archive.profile }
    var entries: [FoodEntry] { archive.entries }
    var meals: [SavedMeal] { archive.meals }

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aurix", isDirectory: true)
        file = root.appendingPathComponent("diary.json")
        backup = root.appendingPathComponent("diary.backup.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                do { archive = try Self.decode(Data(contentsOf: file)) }
                catch {
                    archive = try Self.decode(Data(contentsOf: backup))
                    self.error = "Dein letzter Speicherstand wurde aus der lokalen Sicherung wiederhergestellt."
                    try encoded().write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
            }
        } catch { cannotLoad = true; self.error = "Das Tagebuch konnte nicht geöffnet werden. Deine Dateien bleiben erhalten. Schliesse die App und versuche es erneut." }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-screenshots-welcome") { archive = Archive() }
        if ProcessInfo.processInfo.arguments.contains("-screenshots-dashboard") {
            var profile = UserProfile(); profile.name = "Maurus"; profile.goals = Nutrition(calories: 2900, protein: 160, carbs: 350, fat: 90)
            archive = Archive(profile: profile, entries: [
                FoodEntry(name: "Skyr, Haferflocken & Beeren", nutrition: Nutrition(calories: 480, protein: 38, carbs: 62, fat: 9), slot: .breakfast),
                FoodEntry(name: "Poulet mit Reis", nutrition: Nutrition(calories: 720, protein: 52, carbs: 85, fat: 18), slot: .lunch, source: .photo, estimated: true),
                FoodEntry(name: "Protein-Drink", nutrition: Nutrition(calories: 230, protein: 30, carbs: 18, fat: 4), slot: .snack, source: .barcode)
            ])
        }
        #endif
    }

    func entries(on date: Date) -> [FoodEntry] {
        archive.entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }
    func totals(on date: Date) -> Nutrition { entries(on: date).reduce(.zero) { $0 + $1.nutrition } }
    func saveProfile(_ profile: UserProfile) {
        guard profile.isValid else { error = "Bitte prüfe deine Angaben und Ziele."; return }
        var next = archive; next.profile = profile; _ = commit(next)
    }
    @discardableResult func add(_ entry: FoodEntry) -> Bool {
        guard entry.isValid else { error = "Bitte prüfe Name und Nährwerte."; return false }
        guard !archive.entries.contains(where: { $0.id == entry.id }) else { return false }
        var next = archive; next.entries.append(entry)
        guard commit(next) else { return false }
        undoEntry = entry; notify("\(entry.name) erfasst", allowUndo: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
    }
    @discardableResult func update(_ entry: FoodEntry) -> Bool {
        guard entry.isValid, let index = archive.entries.firstIndex(where: { $0.id == entry.id }) else { return false }
        var next = archive; next.entries[index] = entry
        return commit(next)
    }
    func delete(_ entry: FoodEntry) {
        var next = archive; next.entries.removeAll { $0.id == entry.id }
        if commit(next) { notify("Eintrag gelöscht") }
    }
    func undoLastAdd() {
        guard let entry = undoEntry else { return }
        var next = archive; next.entries.removeAll { $0.id == entry.id }
        if commit(next) { undoEntry = nil; toast = nil; toastTask?.cancel() }
    }
    func saveMeal(_ meal: SavedMeal) {
        var next = archive
        if let index = next.meals.firstIndex(where: { $0.id == meal.id || (meal.barcode != nil && $0.barcode == meal.barcode) }) {
            next.meals[index] = meal
        } else { next.meals.append(meal) }
        if commit(next) { notify("In deinen Meals gespeichert") }
    }
    func deleteMeal(_ meal: SavedMeal) {
        var next = archive; next.meals.removeAll { $0.id == meal.id }; _ = commit(next)
    }
    func notify(_ message: String, allowUndo: Bool = false) {
        if !allowUndo { undoEntry = nil }
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.toast = nil; self?.undoEntry = nil
        }
    }
    func encoded() throws -> Data { try Self.encoder.encode(archive) }
    func importArchive(_ data: Data) throws {
        guard data.count <= 20_000_000 else { throw CoreError.invalidArchive }
        let incoming = try Self.decode(data)
        var next = archive
        let knownEntries = Set(next.entries.map(\.id)), knownMeals = Set(next.meals.map(\.id))
        next.entries += incoming.entries.filter { !knownEntries.contains($0.id) }
        next.meals += incoming.meals.filter { !knownMeals.contains($0.id) }
        if next.profile == nil { next.profile = incoming.profile }
        _ = try next.validated()
        if commit(next) { notify("Sicherung importiert · Duplikate übersprungen") }
    }
    var storageDescription: String {
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0) +
                   ((try? FileManager.default.attributesOfItem(atPath: backup.path)[.size] as? NSNumber)?.int64Value ?? 0)
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static func decode(_ data: Data) throws -> Archive {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(Archive.self, from: data).validated()
    }
    private func commit(_ next: Archive) -> Bool {
        guard !cannotLoad else { return false }
        do {
            _ = try next.validated()
            let data = try Self.encoder.encode(next)
            // One rolling backup only; photo/audio originals never enter the archive.
            if FileManager.default.fileExists(atPath: file.path) {
                try Data(contentsOf: file).write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            archive = next
            return true
        } catch { self.error = "Speichern fehlgeschlagen. Dein bisheriges Tagebuch ist unverändert. \(error.localizedDescription)"; return false }
    }
}
