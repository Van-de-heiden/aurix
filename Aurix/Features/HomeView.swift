import SwiftUI
import AurixCore

private enum HomeSheet: Identifiable {
    case capture(MealSlot, Date), edit(FoodEntry), settings, calendar, measurement(BodyMetric, Date)
    var id: String {
        switch self { case .capture: return "capture"; case .edit(let entry): return entry.id.uuidString
        case .settings: return "settings"; case .calendar: return "calendar"; case .measurement(let metric, _): return "measurement-\(metric.rawValue)" }
    }
}

struct HomeView: View {
    private enum Tab: Hashable { case today, capture, meals, progress }
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var date = Date()
    @State private var sheet: HomeSheet?
    @State private var selectedTab = Tab.today
    @State private var lastToday = Calendar.current.startOfDay(for: Date())
    private var profile: UserProfile { store.profile ?? UserProfile() }
    private var currentEntries: [FoodEntry] { store.entries(on: date) }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboard
                .tabItem { Label("Heute", systemImage: "square.grid.2x2") }
                .tag(Tab.today)
            Group {
                // A capture session only exists while this tab is visible. Leaving it
                // stops camera/audio and releases drafts and temporary image data.
                if selectedTab == .capture {
                    CaptureView(date: entryDate, slot: .suggested(), onClose: { selectedTab = .today })
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Erfassen", systemImage: "plus.circle") }
            .tag(Tab.capture)
            MealsView(date: entryDate, slot: .suggested(), onEntryAdded: { selectedTab = .today })
                .tabItem { Label("Meine Meals", systemImage: "square.stack") }
                .tag(Tab.meals)
            ProgressScreen()
                .tabItem { Label("Verlauf", systemImage: "chart.xyaxis.line") }
                .tag(Tab.progress)
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .capture(let slot, let day): CaptureView(date: day, slot: slot)
            case .edit(let entry): EntryEditor(entry: entry)
            case .settings: SettingsView()
            case .measurement(let metric, let day):
                let existing = store.measurements.first { $0.metric == metric && Calendar.current.isDate($0.date, inSameDayAs: day) }
                MeasurementEditor(metric: metric, day: day, existing: existing,
                    initialValue: store.latestMeasurement(metric)?.value ?? (metric == .weight ? profile.weight : nil))
            case .calendar:
                NavigationStack {
                    DatePicker("Tag wählen", selection: $date, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical).padding()
                        .navigationTitle("Dein Tagebuch").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { sheet = nil } } }
                }.presentationDetents([.medium])
            }
        }
        .onChange(of: phase) { _, new in
            guard new == .active else { return }
            let today = Calendar.current.startOfDay(for: Date())
            if Calendar.current.isDate(date, inSameDayAs: lastToday) { date = Date() }
            lastToday = today
        }
    }
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Brand()
                    Spacer()
                    Button { sheet = .settings } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 18)).frame(width: 44, height: 44).background(Theme.card, in: Circle())
                    }.accessibilityLabel("Einstellungen")
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isToday ? "Dein Tag, \(profile.name)." : date.formatted(.dateTime.day().month(.wide)))
                            .font(.system(size: 28, weight: .medium, design: .rounded)).tracking(-0.7).minimumScaleFactor(0.75).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    let streak = store.trackingStreak
                    if streak > 0 {
                        Label("\(streak)", systemImage: "flame.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.carbs)
                            .padding(.horizontal, 10).padding(.vertical, 8).background(Theme.carbs.opacity(0.09), in: Capsule())
                            .accessibilityLabel("\(streak) Tage in Folge erfasst")
                    }
                }
                dayPicker
                let total = store.totals(on: date)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    Meter(name: "Kalorien", value: total.calories, goal: profile.goals.calories, unit: "kcal", color: Theme.cyan)
                    Meter(name: "Protein", value: total.protein, goal: profile.goals.protein, unit: "g", color: Theme.protein)
                    Meter(name: "Carbs", value: total.carbs, goal: profile.goals.carbs, unit: "g", color: Theme.carbs)
                    Meter(name: "Fette", value: total.fat, goal: profile.goals.fat, unit: "g", color: Theme.fat)
                }.accessibilityIdentifier("dashboard.meters")
                measurementShortcuts
                HStack {
                    Text("Deine Mahlzeiten").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Spacer(); Text("\(currentEntries.count) Einträge").font(.caption).foregroundStyle(Theme.muted)
                }.padding(.top, 2)
                VStack(spacing: 12) { ForEach(MealSlot.allCases) { slot in mealSection(slot) } }
                Text("Food fuels more than just today.").font(.system(size: 10)).foregroundStyle(Theme.muted.opacity(0.7)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 12)
        }
        .aurixScreen().scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if let toast = store.toast {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.cyan)
                        Text(toast).font(.caption).lineLimit(2)
                        Spacer()
                        if store.undoEntry != nil { Button("Rückgängig") { store.undoLastAdd() }.font(.caption.bold()) }
                    }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 22).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }.animation(reduceMotion ? nil : .snappy, value: store.toast)
        }
    }
    private var measurementShortcuts: some View {
        HStack(spacing: 0) {
            ForEach(BodyMetric.allCases) { metric in
                let measurement = store.measurements.first { $0.metric == metric && Calendar.current.isDate($0.date, inSameDayAs: date) }
                let due = isToday && BodyProgress.isDue(metric, measurements: store.measurements)
                Button { sheet = .measurement(metric, min(entryDate, Date())) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: metric.symbol).font(.system(size: 18)).foregroundStyle(Theme.cyan)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ivory)
                            Text(measurement.map { $0.value.formatted(.number.precision(.fractionLength(1))) + " " + metric.unit } ?? (due ? "Jetzt erfassen" : metric == .waist && isToday ? "Diese Woche erfasst" : "Erfassen"))
                                .font(.system(size: 11)).foregroundStyle(due ? Theme.cyan : Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("measurement.quick.\(metric.rawValue)")
                if metric == .weight { Divider().frame(height: 30) }
            }
        }.background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
    }
    private var entryDate: Date {
        let calendar = Calendar.current, now = Date()
        return calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: calendar.component(.minute, from: now), second: 0, of: date) ?? date
    }
    private var dayPicker: some View {
        HStack {
            Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38) }.accessibilityLabel("Vorheriger Tag")
            Spacer()
            Button { sheet = .calendar } label: {
                HStack(spacing: 7) { Text(isToday ? "Heute" : date.formatted(.dateTime.weekday(.abbreviated))); Text(date.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(Theme.muted); Image(systemName: "chevron.down").font(.system(size: 9)) }.font(.system(size: 13, weight: .medium))
            }.accessibilityLabel("Datum auswählen")
            Spacer()
            Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 38, height: 38) }.disabled(isToday).opacity(isToday ? 0.25 : 1).accessibilityLabel("Nächster Tag")
        }.background(Theme.card.opacity(0.6), in: Capsule())
    }
    private func mealSection(_ slot: MealSlot) -> some View {
        let entries = currentEntries.filter { $0.slot == slot }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: slot.symbol == "apple.logo" ? "leaf" : slot.symbol).foregroundStyle(Theme.muted).frame(width: 22)
                Text(slot.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if !entries.isEmpty { Text("\(Int(entries.reduce(0) { $0 + $1.nutrition.calories })) kcal").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Button { sheet = .capture(slot, entryDate) } label: { Image(systemName: "plus").frame(width: 36, height: 36).background(Theme.cyan.opacity(0.08), in: Circle()) }.accessibilityLabel("Zum \(slot.title) hinzufügen")
            }
            if entries.isEmpty {
                Button { sheet = .capture(slot, entryDate) } label: { Text("Noch nichts erfasst").font(.system(size: 12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6) }
            }
            ForEach(entries) { entry in
                Button { sheet = .edit(entry) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entry.source.symbol).font(.system(size: 16)).foregroundStyle(Theme.cyan).frame(width: 36, height: 42).background(Theme.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                            MacroSummary(nutrition: entry.nutrition)
                            Text(entry.portion + (entry.estimated ? " · Schätzung" : "")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }.padding(.vertical, 4)
                }.buttonStyle(PressStyle())
            }
        }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private func moveDay(_ direction: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: direction, to: date) { date = min(next, Date()) }
    }
}
