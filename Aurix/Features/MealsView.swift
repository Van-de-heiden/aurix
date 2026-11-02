import SwiftUI
import AurixCore

struct MealsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var date: Date
    var slot: MealSlot
    var onEntryAdded: (() -> Void)? = nil
    @State private var query = ""
    @State private var editing: FoodEntry?
    @State private var selectedMeal: SavedMeal?
    private var recent: [FoodEntry] {
        var seen = Set<String>()
        return store.entries.sorted { $0.date > $1.date }.filter { seen.insert($0.name.lowercased()).inserted && matches($0.name) }.prefix(20).map { $0 }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("DEINE FAVORITEN. EIN TIPP ENTFERNT.")
                        .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Theme.lime)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("Deine Meals durchsuchen", text: $query).font(.system(size: 15))
                            .submitLabel(.search)
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Suche leeren") }
                    }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 17))
                    PrimaryButton(title: "Eigenes Meal erfassen", symbol: "plus") {
                        editing = FoodEntry(name: "", nutrition: .zero, date: date, slot: slot)
                    }
                    SectionHeading(title: "Gespeichert", detail: "\(store.meals.filter { matches($0.name) }.count) Meals")
                    if store.meals.isEmpty {
                        emptyState("Deine Basics, immer bereit.", detail: "Speichere, was du oft isst. Beim nächsten Mal reicht ein Tippen.", symbol: "square.stack.3d.up")
                    } else if store.meals.filter({ matches($0.name) }).isEmpty {
                        emptyState("Kein Treffer", detail: "Versuche einen anderen Namen.", symbol: "magnifyingglass")
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(store.meals.filter { matches($0.name) }) { meal in
                            Button { if store.add(meal.entry(date: date, slot: slot)) { finishAdding() } } label: { row(meal.name, meal.nutrition, meal.portion) }
                                .buttonStyle(PressStyle())
                                .contextMenu {
                                    Button("Meal bearbeiten", systemImage: "pencil") { selectedMeal = meal }
                                    Button("Meal löschen", systemImage: "trash", role: .destructive) { store.deleteMeal(meal) }
                                }
                                .accessibilityCustomContent("Aktionen", "Zum Bearbeiten oder Löschen gedrückt halten")
                        }
                    }
                    SectionHeading(title: "Noch einmal essen", detail: "Zuletzt erfasst")
                    LazyVStack(spacing: 10) {
                        ForEach(recent) { old in
                            Button {
                                var entry = old; entry.id = UUID(); entry.date = date; entry.slot = slot
                                if store.add(entry) { finishAdding() }
                            } label: { row(old.name, old.nutrition, old.portion) }.buttonStyle(PressStyle())
                        }
                    }
                    if recent.isEmpty {
                        emptyState(query.isEmpty ? "Hier wird’s persönlich." : "Kein Treffer", detail: query.isEmpty ? "Deine letzten Mahlzeiten kannst du hier direkt wiederholen." : "Für diese Suche gibt es keine Mahlzeiten.", symbol: "clock.arrow.circlepath")
                    }
                }.padding(22)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).aurixScreen()
                .navigationTitle("Meine Meals")
                .toolbar {
                    if onEntryAdded == nil {
                        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                    }
                }
                .sheet(item: $editing) { EntryEditor(entry: $0, isNew: true) }
                .sheet(item: $selectedMeal) { SavedMealEditor(meal: $0) }
        }
    }
    private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private func finishAdding() {
        if let onEntryAdded { onEntryAdded() } else { dismiss() }
    }
    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedStandardContains(query) }
    private func row(_ name: String, _ nutrition: Nutrition, _ portion: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(name).foregroundStyle(Theme.ivory).font(.system(size: 15, weight: .medium))
                MacroSummary(nutrition: nutrition)
                Text(portion).font(.caption2).foregroundStyle(Theme.muted)
            }
            Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(Theme.lime)
        }.padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
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
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { if store.saveMeal(meal) { dismiss() } }.disabled(meal.name.trimmingCharacters(in: .whitespaces).isEmpty || !meal.nutrition.isValid) }
                }
        }
    }
}
