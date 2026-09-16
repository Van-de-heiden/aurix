import SwiftUI
import Charts
import AurixCore

private enum ProgressRange: String, CaseIterable {
    case month = "4 Wochen", quarter = "3 Monate", all = "Alle"
    func start(now: Date, first: Date?) -> Date {
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        switch self {
        case .month: return calendar.date(byAdding: .day, value: -27, to: today)!
        case .quarter: return calendar.date(byAdding: .month, value: -3, to: today)!
        case .all: return min(first ?? today, calendar.date(byAdding: .day, value: -1, to: today)!)
        }
    }
}

struct ProgressScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var metric = BodyMetric.weight
    @State private var range = ProgressRange.month
    @State private var selectedDate: Date?
    @State private var editing: BodyMeasurement?
    @State private var adding = false
    @State private var historyLimit = 30

    @State private var allPoints: [MeasurementPoint] = []
    @State private var averages: [MeasurementPoint] = []
    @State private var records: [BodyMeasurement] = []
    @Environment(\.scenePhase) private var scenePhase
    private var start: Date { range.start(now: Date(), first: allPoints.first?.date) }
    private var points: [MeasurementPoint] { allPoints.filter { $0.date >= start } }
    private var history: [BodyMeasurement] {
        records.filter { $0.date >= start }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker("Messwert", selection: $metric) {
                    ForEach(BodyMetric.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 20).accessibilityIdentifier("progress.metric")
                Picker("Zeitraum", selection: $range) {
                    ForEach(ProgressRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 20).accessibilityIdentifier("progress.range")
                List {
                    if let latest = allPoints.last {
                        Section {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Zuletzt · \(latest.date.formatted(.dateTime.day().month(.abbreviated)))").font(.caption).foregroundStyle(Theme.muted)
                                    Text("\(latest.value.formatted(.number.precision(.fractionLength(1)))) \(metric.unit)")
                                        .font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                                }
                                Spacer()
                                if let first = points.first, let last = points.last, points.count > 1 {
                                    VStack(alignment: .trailing, spacing: 5) {
                                        Text("Im Zeitraum").font(.caption).foregroundStyle(Theme.muted)
                                        Text((last.value - first.value).formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))) + " " + metric.unit)
                                            .font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(Theme.cyan)
                                    }
                                }
                            }.padding(.vertical, 5)
                            if metric == .weight { weeklyAverage }
                        }.listRowBackground(Theme.card)
                    }
                    Section {
                        if points.isEmpty {
                            ContentUnavailableView(metric == .weight ? "Dein Verlauf beginnt hier" : "Eine Messung pro Woche",
                                systemImage: "chart.xyaxis.line", description: Text(allPoints.isEmpty ? "Trage deinen ersten Messwert ein. Jeder weitere macht deinen Verlauf sichtbar." : "In diesem Zeitraum gibt es noch keine Messwerte. Wähle einen längeren Zeitraum."))
                            Button("\(metric.title) erfassen") { adding = true }.accessibilityIdentifier("progress.firstMeasurement")
                        } else {
                            MeasurementChart(points: points,
                                average: metric == .weight ? averages.filter { $0.date >= start } : [],
                                metric: metric, start: start, selectedDate: $selectedDate)
                                .frame(height: 230).padding(.vertical, 8).accessibilityIdentifier("progress.chart")
                            if let selected = selectedMeasurement {
                                Button { editing = selected } label: {
                                    HStack {
                                        Text(selected.date.formatted(.dateTime.day().month(.abbreviated)))
                                        Spacer()
                                        Text(selected.value, format: .number.precision(.fractionLength(1)))
                                        Text(metric.unit)
                                        Image(systemName: "pencil")
                                    }.font(.subheadline)
                                }.accessibilityIdentifier("progress.selectedMeasurement")
                            }
                            Text(metric == .weight ? "Punkte: Tageswerte · helle Linie: Mittel der vorhandenen Messungen in 7 Tagen. Tippe auf den Verlauf für einen Wert." : "Deine Messungen über die Wochen. Tippe auf den Verlauf für einen Wert.")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }.listRowBackground(Theme.card)
                    if !history.isEmpty {
                        Section("Messwerte · \(history.count)") {
                            ForEach(history.prefix(historyLimit)) { measurement in
                                Button { editing = measurement } label: {
                                    HStack {
                                        Text(measurement.date, format: .dateTime.day().month(.abbreviated).year())
                                            .foregroundStyle(Theme.ivory)
                                        Spacer()
                                        Text(measurement.value, format: .number.precision(.fractionLength(1))).monospacedDigit()
                                        Text(metric.unit).foregroundStyle(Theme.muted)
                                    }
                                }.accessibilityIdentifier("measurement.row.\(measurement.id.uuidString)")
                            }
                            if history.count > historyLimit { Button("Weitere Messwerte") { historyLimit += 30 } }
                        }.listRowBackground(Theme.card)
                    }
                }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
            }.aurixScreen().navigationTitle("Dein Verlauf")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { adding = true } label: { Label("Messwert erfassen", systemImage: "plus") }
                            .accessibilityIdentifier("measurement.add")
                    }
                }
                .sheet(isPresented: $adding) {
                    MeasurementEditor(metric: metric, initialValue: store.latestMeasurement(metric)?.value ?? (metric == .weight ? store.profile?.weight : nil))
                }
                .sheet(item: $editing) { MeasurementEditor(metric: $0.metric, existing: $0) }
                .onAppear { refresh() }
                .onChange(of: store.measurements) { _, _ in refresh() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
                .onChange(of: metric) { _, _ in selectedDate = nil; historyLimit = 30; refresh() }
                .onChange(of: range) { _, _ in selectedDate = nil; historyLimit = 30 }
        }
    }
    private func refresh() {
        allPoints = BodyProgress.series(store.measurements, metric: metric)
        averages = metric == .weight ? BodyProgress.rollingWeek(allPoints) : []
        records = store.measurements.filter { $0.metric == metric && $0.date <= Date() }.sorted { $0.date > $1.date }
    }
    private var selectedMeasurement: BodyMeasurement? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        return history.min { abs(calendar.startOfDay(for: $0.date).timeIntervalSince(selectedDate)) < abs(calendar.startOfDay(for: $1.date).timeIntervalSince(selectedDate)) }
    }
    @ViewBuilder private var weeklyAverage: some View {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        let week = allPoints.filter { $0.date >= start }
        if !week.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7-Tage-Mittel").font(.subheadline)
                    Text("\(week.count) von 7 Tagen erfasst").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text((week.reduce(0) { $0 + $1.value } / Double(week.count)).formatted(.number.precision(.fractionLength(1))) + " kg")
                    .font(.title3.weight(.medium)).monospacedDigit()
            }
        }
    }
}

private struct MeasurementChart: View {
    let points: [MeasurementPoint]
    let average: [MeasurementPoint]
    let metric: BodyMetric
    let start: Date
    @Binding var selectedDate: Date?
    private var yDomain: ClosedRange<Double> {
        let values = (points + average).map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max(metric == .weight ? 1 : 2, (high - low) * 0.2)
        return max(0, low - padding)...(high + padding)
    }
    // Bound rendering cost for many years of daily data; history retains every value.
    private func displayed(_ values: [MeasurementPoint]) -> [MeasurementPoint] {
        guard values.count > 400 else { return values }
        let stride = Double(values.count - 1) / 399
        return (0..<400).map { values[Int((Double($0) * stride).rounded())] }
    }
    var body: some View {
        Chart {
            ForEach(displayed(points)) { point in
                LineMark(x: .value("Tag", point.date), y: .value(metric.unit, point.value), series: .value("Serie", "Messwert"))
                    .foregroundStyle(Theme.cyan.opacity(metric == .weight ? 0.4 : 0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("Tag", point.date), y: .value(metric.unit, point.value))
                    .foregroundStyle(Theme.cyan).symbolSize(22)
                    .accessibilityLabel(point.date.formatted(.dateTime.day().month()))
                    .accessibilityValue("\(point.value.formatted()) \(metric.unit)")
            }
            ForEach(displayed(average)) { point in
                LineMark(x: .value("Tag", point.date), y: .value(metric.unit, point.value), series: .value("Serie", "7-Tage-Mittel"))
                    .foregroundStyle(Theme.ivory).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let selectedDate, let point = points.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }) {
                RuleMark(x: .value("Ausgewählter Tag", point.date)).foregroundStyle(Theme.muted.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: start...Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!)
        .chartXSelection(value: $selectedDate)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)); AxisGridLine() } }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartLegend(.hidden)
        .accessibilityLabel("\(metric.title) in \(metric.unit). \(points.count) Messungen. Bei langen Zeiträumen ist die Darstellung verdichtet.")
    }
}

struct MeasurementEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let metric: BodyMetric
    let existing: BodyMeasurement?
    @State private var date: Date
    @State private var weight: Double
    @State private var waistText: String
    @State private var deleting = false

    init(metric: BodyMetric, day: Date = Date(), existing: BodyMeasurement? = nil, initialValue: Double? = nil) {
        self.metric = metric; self.existing = existing
        _date = State(initialValue: existing?.date ?? day)
        let value = existing?.value ?? initialValue
        _weight = State(initialValue: min(300, max(35, ((value ?? 75) * 2).rounded() / 2)))
        _waistText = State(initialValue: value.map { String($0) } ?? "")
    }
    private var value: Double? { metric == .weight ? weight : Double(waistText.replacingOccurrences(of: ",", with: ".")) }
    private var valid: Bool { value.map { $0.isFinite && metric.range.contains($0) } == true && date <= Date() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Tag", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: { Text("Ein Wert pro Tag. Erneutes Speichern aktualisiert diesen Tag.") }
                Section {
                    if metric == .weight {
                        WeightSelection(value: $weight, range: 35...300).listRowInsets(EdgeInsets())
                    } else {
                        HStack {
                            TextField("Gemessener Bauchumfang", text: $waistText).keyboardType(.decimalPad)
                                .accessibilityIdentifier("measurement.waistValue")
                            Text("cm").foregroundStyle(Theme.muted)
                        }
                    }
                } header: { Text(metric.title) } footer: {
                    Text(metric == .weight ? "Für vergleichbare Werte möglichst immer unter ähnlichen Bedingungen messen." : "Einmal pro Woche genügt. Miss jedes Mal an derselben Stelle und unter ähnlichen Bedingungen.")
                }
                if existing != nil {
                    Section { Button("Messwert löschen", role: .destructive) { deleting = true }.accessibilityIdentifier("measurement.delete") }
                }
            }.scrollContentBackground(.hidden).aurixScreen().keyboardDone()
                .navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            guard let value else { return }
                            let measurement = BodyMeasurement(id: existing?.id ?? UUID(), metric: metric, value: value, date: date)
                            if store.saveMeasurement(measurement) { dismiss() }
                        }.disabled(!valid).accessibilityIdentifier("measurement.save")
                    }
                }
                .confirmationDialog("Diesen Messwert löschen?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Messwert löschen", role: .destructive) {
                        if let existing, store.deleteMeasurement(existing) { dismiss() }
                    }
                }
        }
    }
}
