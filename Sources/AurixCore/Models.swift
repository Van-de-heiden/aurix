import Foundation

public struct Nutrition: Codable, Equatable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
    }
    public static let zero = Nutrition()
    public var isValid: Bool {
        [calories, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 } &&
        calories <= 30_000 && protein <= 3_000 && carbs <= 5_000 && fat <= 3_000
    }
    public func scaled(by factor: Double) -> Nutrition {
        Nutrition(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }
    public static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                  carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }
}

public enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var title: String {
        switch self { case .breakfast: return "Morgenessen"; case .lunch: return "Mittagessen"
        case .dinner: return "Abendessen"; case .snack: return "Snacks" }
    }
    public var symbol: String {
        switch self { case .breakfast: return "sunrise"; case .lunch: return "sun.max"
        case .dinner: return "moon"; case .snack: return "apple.logo" }
    }
    public static func suggested(at date: Date = Date(), calendar: Calendar = .current) -> MealSlot {
        switch calendar.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 18..<22: return .dinner
        default: return .snack
        }
    }
}

public enum EntrySource: String, Codable, Sendable {
    case manual, barcode, photo, voice, saved
    public var label: String {
        switch self { case .manual: return "Manuell"; case .barcode: return "Barcode"
        case .photo, .voice: return "KI-Schätzung"; case .saved: return "Eigenes Meal" }
    }
    public var symbol: String {
        switch self { case .manual: return "fork.knife"; case .barcode: return "barcode"
        case .photo: return "camera"; case .voice: return "waveform"; case .saved: return "star" }
    }
}

public struct FoodEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var nutrition: Nutrition
    public var date: Date
    public var slot: MealSlot
    public var source: EntrySource
    public var portion: String
    public var note: String
    public var barcode: String?
    public var estimated: Bool
    public init(id: UUID = UUID(), name: String, nutrition: Nutrition, date: Date = Date(),
                slot: MealSlot = .suggested(), source: EntrySource = .manual, portion: String = "1 Portion",
                note: String = "", barcode: String? = nil, estimated: Bool = false) {
        self.id = id; self.name = name; self.nutrition = nutrition; self.date = date; self.slot = slot
        self.source = source; self.portion = portion; self.note = note; self.barcode = barcode; self.estimated = estimated
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200 &&
        portion.count <= 200 && note.count <= 2_000 && nutrition.isValid
    }
}

public struct SavedMeal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var nutrition: Nutrition
    public var portion: String
    public var barcode: String?
    public var estimated: Bool
    public init(id: UUID = UUID(), name: String, nutrition: Nutrition, portion: String = "1 Portion", barcode: String? = nil, estimated: Bool = false) {
        self.id = id; self.name = name; self.nutrition = nutrition; self.portion = portion
        self.barcode = barcode; self.estimated = estimated
    }
    public func entry(date: Date, slot: MealSlot) -> FoodEntry {
        FoodEntry(name: name, nutrition: nutrition, date: date, slot: slot, source: .saved,
                  portion: portion, barcode: barcode, estimated: estimated)
    }
}

public enum GoalDirection: String, Codable, CaseIterable, Sendable {
    case gain, maintain, lose
    public var title: String { switch self { case .gain: return "Aufbauen"; case .maintain: return "Halten"; case .lose: return "Abnehmen" } }
    public var subtitle: String {
        switch self { case .gain: return "Mehr Kraft. Mehr Substanz."; case .maintain: return "Deine Form. Dein Gleichgewicht."
        case .lose: return "Schritt für Schritt leichter." }
    }
    public var symbol: String { switch self { case .gain: return "arrow.up.right"; case .maintain: return "equal"; case .lose: return "arrow.down.right" } }
}

public struct UserProfile: Codable, Equatable, Sendable {
    public var name: String = ""
    public var age: Int = 25
    public var height: Double = 175
    public var weight: Double = 75
    public var targetWeight: Double = 75
    public var maleFormula: Bool = true
    public var activity: Double = 1.55
    public var direction: GoalDirection = .maintain
    public var goals: Nutrition = Nutrition(calories: 2400, protein: 150, carbs: 285, fat: 73)
    public init() {}
    public var isValid: Bool {
        (18...100).contains(age) && (100...230).contains(height) && (35...300).contains(weight) &&
        (35...300).contains(targetWeight) && (1.2...1.9).contains(activity) && name.count <= 60 &&
        goals.isValid && (1200...8000).contains(goals.calories) && goals.protein > 0 && goals.carbs > 0 && goals.fat > 0
    }
}

public struct Archive: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var profile: UserProfile?
    public var entries: [FoodEntry] = []
    public var meals: [SavedMeal] = []
    public init(profile: UserProfile? = nil, entries: [FoodEntry] = [], meals: [SavedMeal] = []) {
        self.profile = profile; self.entries = entries; self.meals = meals
    }
    public func validated() throws -> Archive {
        guard schemaVersion == 1, entries.count <= 100_000, meals.count <= 10_000,
              profile?.isValid != false, entries.allSatisfy(\.isValid),
              meals.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 200 && $0.nutrition.isValid && $0.portion.count <= 200 }),
              Set(entries.map(\.id)).count == entries.count, Set(meals.map(\.id)).count == meals.count
        else { throw CoreError.invalidArchive }
        return self
    }
}

public enum CoreError: LocalizedError {
    case invalidArchive, invalidNutrition, noFood, incompleteProduct
    public var errorDescription: String? {
        switch self { case .invalidArchive: return "Diese Sicherung ist unvollständig oder hat ein unbekanntes Format."
        case .invalidNutrition: return "Die Nährwerte sind unvollständig oder unplausibel. Bitte versuche es erneut oder erfasse sie manuell."
        case .noFood: return "Keine Mahlzeit erkannt. Versuche ein klareres Foto oder beschreibe dein Essen."
        case .incompleteProduct: return "Zu diesem Produkt fehlen verlässliche Nährwerte. Du kannst es einmal manuell speichern." }
    }
}
