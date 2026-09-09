import SwiftUI
import AurixCore

enum Theme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.075)
    static let card = Color(red: 0.07, green: 0.095, blue: 0.12)
    static let cyan = Color(red: 0.50, green: 0.87, blue: 0.90)
    static let ivory = Color(red: 0.96, green: 0.94, blue: 0.87)
    static let muted = Color(red: 0.59, green: 0.65, blue: 0.69)
    static let protein = Color(red: 0.76, green: 0.79, blue: 1.0)
    static let carbs = Color(red: 0.95, green: 0.76, blue: 0.48)
    static let fat = Color(red: 0.65, green: 0.84, blue: 0.66)
}

struct Brand: View {
    var large = false
    var body: some View {
        Group {
            if large {
                VStack(spacing: 3) {
                    Image("AppMark").resizable().scaledToFit().frame(width: 158, height: 148)
                    Text("AURIX").font(.system(size: 34, weight: .light)).tracking(11).padding(.leading, 11)
                    Text("FUEL A BETTER YOU").font(.system(size: 9, weight: .light)).tracking(3.8).padding(.leading, 3.8).padding(.top, 7)
                }.foregroundStyle(Theme.ivory)
            } else {
                HStack(spacing: 8) {
                    Image("AppMark").resizable().scaledToFit().frame(width: 40, height: 36)
                    Text("AURIX").font(.system(size: 17, weight: .light)).tracking(5).foregroundStyle(Theme.ivory)
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("AURIX")
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var disabled = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: symbol) }
                .font(.system(size: 17, weight: .semibold)).padding(.horizontal, 22).frame(minHeight: 58)
                .foregroundStyle(Theme.background).background(Theme.cyan, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(PressStyle()).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct Meter: View {
    let name: String
    let value: Double
    let goal: Double
    let unit: String
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 10) {
            HStack { Text(name).font(.system(size: 13, weight: .medium)); Spacer() }.foregroundStyle(Theme.muted)
            ZStack {
                Circle().stroke(color.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, value / max(1, goal)))))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.85), value: value)
                VStack(spacing: 2) {
                    Text(value, format: .number.precision(.fractionLength(0))).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                    Text("von \(Int(goal)) \(unit)").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }.padding(.horizontal, 8)
            }.frame(width: 112, height: 112).padding(.vertical, 2)
            Text(value <= goal ? "\(Int(max(0, goal - value))) \(unit) offen" : "+\(Int(value - goal)) \(unit)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(color)
        }.padding(16).frame(maxWidth: .infinity).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name): \(Int(value)) von \(Int(goal)) \(unit)")
    }
}

struct MacroSummary: View {
    let nutrition: Nutrition
    var body: some View {
        Text("\(Int(nutrition.calories)) kcal  ·  P \(Int(nutrition.protein))  K \(Int(nutrition.carbs))  F \(Int(nutrition.fat)) g")
            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit = "g"
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                .accessibilityLabel(title)
            Text(unit).foregroundStyle(Theme.muted).frame(minWidth: 28, alignment: .leading)
        }
    }
}

extension View {
    func keyboardDone() -> some View {
        toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Fertig") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        } }
    }
    func aurixScreen() -> some View { background(Theme.background.ignoresSafeArea()).foregroundStyle(Theme.ivory) }
}
