import SwiftUI
import AurixCore

struct EntryEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: FoodEntry
    var isNew = false
    @State private var saveAsMeal = false
    @State private var confirmDelete = false
    @State private var multiplier = 1.0
    @State private var originalNutrition: Nutrition?
    @State private var originalPortion: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Meal") {
                    TextField("Name der Mahlzeit", text: $entry.name).submitLabel(.done)
                    TextField("Portion, z. B. 1 Sandwich", text: $entry.portion).submitLabel(.done)
                    Picker("Mahlzeit", selection: $entry.slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                    DatePicker("Datum", selection: $entry.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                if !isNew {
                    Section("Menge schnell anpassen") {
                        HStack {
                            ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { factor in
                                Button { scale(factor) } label: {
                                    Text(factor.formatted(.number.precision(.fractionLength(0...1))) + "×").frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(multiplier == factor ? Theme.cyan.opacity(0.18) : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section("Nährwerte für diesen Eintrag") {
                    NumberField(title: "Kalorien", value: $entry.nutrition.calories, unit: "kcal")
                    NumberField(title: "Protein", value: $entry.nutrition.protein)
                    NumberField(title: "Carbs", value: $entry.nutrition.carbs)
                    NumberField(title: "Fette", value: $entry.nutrition.fat)
                }
                if !entry.note.isEmpty || entry.estimated {
                    Section(entry.source.label) {
                        if entry.estimated { Text("Dieser Eintrag enthält geschätzte Werte.").font(.footnote).foregroundStyle(Theme.muted) }
                        if !entry.note.isEmpty { Text(entry.note).font(.footnote) }
                    }
                }
                Section { Toggle("Als eigenes Meal speichern", isOn: $saveAsMeal) }
                if !isNew {
                    Section {
                        Button("Eintrag löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }.scrollContentBackground(.hidden).aurixScreen().scrollDismissesKeyboard(.interactively).keyboardDone()
                .navigationTitle(isNew ? "Von Hand erfassen" : "Meal bearbeiten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { save() }.fontWeight(.semibold).disabled(!entry.isValid) }
                }
                .confirmationDialog("Diesen Eintrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Eintrag löschen", role: .destructive) { store.delete(entry); dismiss() }
                }
        }.onAppear { originalNutrition = entry.nutrition; originalPortion = entry.portion }
    }
    private func scale(_ factor: Double) {
        multiplier = factor
        entry.nutrition = (originalNutrition ?? entry.nutrition).scaled(by: factor)
        entry.portion = factor == 1 ? (originalPortion ?? "1 Portion") : "\(factor.formatted())× (\(originalPortion ?? "1 Portion"))"
    }
    private func save() {
        entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNew ? store.add(entry) : store.update(entry) else { return }
        if saveAsMeal { store.saveMeal(SavedMeal(name: entry.name, nutrition: entry.nutrition, portion: entry.portion, barcode: entry.barcode, estimated: entry.estimated)) }
        dismiss()
    }
}
