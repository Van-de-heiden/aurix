import Foundation

public enum BodyMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case weight, waist
    public var id: String { rawValue }
    public var title: String { self == .weight ? "Gewicht" : "Bauchumfang" }
    public var unit: String { self == .weight ? "kg" : "cm" }
    public var symbol: String { self == .weight ? "scalemass" : "ruler" }
    public var range: ClosedRange<Double> { self == .weight ? 35...300 : 30...250 }
    public var cadenceDays: Int { self == .weight ? 1 : 7 }
}

public struct BodyMeasurement: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var metric: BodyMetric
    public var value: Double
    public var date: Date
    public init(id: UUID = UUID(), metric: BodyMetric, value: Double, date: Date = Date()) {
        self.id = id; self.metric = metric; self.value = value; self.date = date
    }
    public var isValid: Bool {
        value.isFinite && metric.range.contains(value) && date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= 0
    }
}

public struct MeasurementPoint: Identifiable, Sendable {
    public var date: Date
    public var value: Double
    public var count: Int
    public var id: Date { date }
}

public enum BodyProgress {
    /// One value per metric and local calendar day. Editing an existing day replaces it.
    public static func upserting(_ measurement: BodyMeasurement, into existing: [BodyMeasurement], calendar: Calendar = .current) -> [BodyMeasurement] {
        var result = existing.filter { $0.id != measurement.id }
        let sameDay = result.first { $0.metric == measurement.metric && calendar.isDate($0.date, inSameDayAs: measurement.date) }
        result.removeAll { $0.metric == measurement.metric && calendar.isDate($0.date, inSameDayAs: measurement.date) }
        var next = measurement
        if let sameDay { next.id = sameDay.id }
        result.append(next)
        return result.sorted { $0.date < $1.date }
    }
    /// Existing local measurements win when importing an older backup for the same day.
    public static func merging(_ incoming: [BodyMeasurement], into existing: [BodyMeasurement], calendar: Calendar = .current) -> [BodyMeasurement] {
        var result = existing
        var ids = Set(existing.map(\.id))
        var days = Dictionary(grouping: existing, by: \.metric).mapValues { Set($0.map { calendar.startOfDay(for: $0.date) }) }
        for item in incoming.sorted(by: { $0.date > $1.date }) {
            let day = calendar.startOfDay(for: item.date)
            guard !ids.contains(item.id), days[item.metric]?.contains(day) != true else { continue }
            result.append(item); ids.insert(item.id); days[item.metric, default: []].insert(day)
        }
        return result.sorted { $0.date < $1.date }
    }
    public static func series(_ measurements: [BodyMeasurement], metric: BodyMetric, through now: Date = Date(), calendar: Calendar = .current) -> [MeasurementPoint] {
        let grouped = Dictionary(grouping: measurements.filter { $0.metric == metric && $0.date <= now }, by: { calendar.startOfDay(for: $0.date) })
        return grouped.compactMap { day, items in
            items.max(by: { $0.date < $1.date }).map { MeasurementPoint(date: day, value: $0.value, count: 1) }
        }.sorted { $0.date < $1.date }
    }
    /// Calendar days, not seven entries: gaps are never filled with zero or fabricated values.
    public static func rollingWeek(_ points: [MeasurementPoint], calendar: Calendar = .current) -> [MeasurementPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        var first = 0, sum = 0.0
        var result: [MeasurementPoint] = []
        for (index, point) in sorted.enumerated() {
            guard let start = calendar.date(byAdding: .day, value: -6, to: point.date) else { continue }
            sum += point.value
            while first < index, sorted[first].date < start { sum -= sorted[first].value; first += 1 }
            let count = index - first + 1
            if count >= 2 { result.append(MeasurementPoint(date: point.date, value: sum / Double(count), count: count)) }
        }
        return result
    }
    public static func isDue(_ metric: BodyMetric, measurements: [BodyMeasurement], now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let latest = measurements.filter({ $0.metric == metric && $0.date <= now }).max(by: { $0.date < $1.date }) else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest.date), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= metric.cadenceDays
    }
}
