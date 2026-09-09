import Foundation

public enum GoalCalculator {
    /// Mifflin–St Jeor starting estimate, never a measured energy requirement.
    public static func suggested(for profile: UserProfile) -> Nutrition {
        let resting = 10 * profile.weight + 6.25 * profile.height - 5 * Double(profile.age) + (profile.maleFormula ? 5 : -161)
        let maintenance = resting * profile.activity
        let adjustment: Double = profile.direction == .gain ? 250 : profile.direction == .lose ? -300 : 0
        let calories = min(8000, max(1500, (maintenance + adjustment).rounded(.toNearestOrAwayFromZero)))
        let protein = (profile.weight * 1.8).rounded()
        let fat = (calories * 0.25 / 9).rounded()
        let carbs = max(0, ((calories - protein * 4 - fat * 9) / 4).rounded())
        return Nutrition(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    public static func trackingStreak(entries: [FoodEntry], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(entries.filter { $0.date <= now }.map { calendar.startOfDay(for: $0.date) })
        var date = calendar.startOfDay(for: now)
        if !days.contains(date) { date = calendar.date(byAdding: .day, value: -1, to: date)! }
        var count = 0
        while days.contains(date) {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }
}
