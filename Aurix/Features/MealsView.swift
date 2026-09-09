import SwiftUI
import AurixCore

struct MealsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var date: Date
    var slot: MealSlot
    @State private var query = ""
    @State private var editing: FoodEntry?
    @State private var selectedMeal: SavedMeal?
    private var recent: [FoodEntry] {
        var seen = Set<String>()
        return store.entries.sorted { $0.date > $1.date }.filter { seen.insert($0.name.lowercased()).inserted && matches($0.name) }.prefix(20).map { $0 }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { editing = FoodEntry(name: "", nutrition: .zero, date: date, slot: slot) } label: { Label("Eigenes Meal erfassen", systemImage: "plus.circle") }
                }
                Section("Meine Meals") {
                    if store.meals.isEmpty { Text("Speichere deine häufigsten Mahlzeiten. Danach reicht ein Tippen.").font(.subheadline).foregroundStyle(Theme.muted) }
                    ForEach(store.meals.filter { matches($0.name) }) { meal in
                        Button { if store.add(meal.entry(date: date, slot: slot)) { dismiss() } } label: { row(meal.name, meal.nutrition, meal.portion) }
                            .contextMenu {
                                Button("Meal bearbeiten", systemImage: "pencil") { selectedMeal = meal }
                                Button("Meal löschen", systemImage: "trash", role: .destructive) { store.deleteMeal(meal) }
                            }
                            .swipeActions {
                                Button(role: .destructive) { store.deleteMeal(meal) } label: { Label("Löschen", systemImage: "trash") }
                                Button { selectedMeal = meal } label: { Label("Bearbeiten", systemImage: "pencil") }.tint(Theme.cyan)
                            }
                    }
                }
                Section("Noch einmal essen") {
                    ForEach(recent) { old in
                        Button {
                            var entry = old; entry.id = UUID(); entry.date = date; entry.slot = slot
                            if store.add(entry) { dismiss() }
                        } label: { row(old.name, old.nutrition, old.portion) }
                    }
                    if recent.isEmpty { Text("Hier erscheinen deine letzten Mahlzeiten.").font(.subheadline).foregroundStyle(Theme.muted) }
                }
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden).aurixScreen()
                .searchable(text: $query, prompt: "Deine Meals durchsuchen")
                .navigationTitle("Meine Meals").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
                .sheet(item: $editing) { EntryEditor(entry: $0, isNew: true) }
                .sheet(item: $selectedMeal) { SavedMealEditor(meal: $0) }
        }
    }
    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedStandardContains(query) }
    private func row(_ name: String, _ nutrition: Nutrition, _ portion: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(name).foregroundStyle(Theme.ivory).font(.system(size: 15, weight: .medium))
                MacroSummary(nutrition: nutrition)
                Text(portion).font(.caption2).foregroundStyle(Theme.muted)
            }
            Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(Theme.cyan)
        }.padding(.vertical, 4)
    }
}

struct SavedMealEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var meal: SavedMeal
    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") { TextField("Name", text: $meal.name); TextField("Portion", text: $meal.portion) }
                Section("Pro Portion") {
                    NumberField(title: "Kalorien", value: $meal.nutrition.calories, unit: "kcal")
                    NumberField(title: "Protein", value: $meal.nutrition.protein)
                    NumberField(title: "Carbs", value: $meal.nutrition.carbs)
                    NumberField(title: "Fette", value: $meal.nutrition.fat)
                }
            }.scrollDismissesKeyboard(.interactively).keyboardDone().scrollContentBackground(.hidden).aurixScreen()
                .navigationTitle("Eigenes Meal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { store.saveMeal(meal); dismiss() }.disabled(meal.name.trimmingCharacters(in: .whitespaces).isEmpty || !meal.nutrition.isValid) }
                }
        }
    }
}
