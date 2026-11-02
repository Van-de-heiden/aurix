import SwiftUI
import AurixCore

enum Theme {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.060)
    static let card = Color(red: 0.100, green: 0.115, blue: 0.105)
    static let elevated = Color(red: 0.145, green: 0.160, blue: 0.145)
    static let lime = Color(red: 0.82, green: 0.98, blue: 0.39)
    static let ivory = Color(red: 0.96, green: 0.97, blue: 0.93)
    static let muted = Color(red: 0.61, green: 0.65, blue: 0.61)
    static let protein = Color(red: 0.73, green: 0.72, blue: 0.98)
    static let carbs = Color(red: 1.0, green: 0.73, blue: 0.49)
    static let fat = Color(red: 0.46, green: 0.82, blue: 0.71)
}

/// The same three forward-cut shapes are used in the app icon and wordmark.
struct FuelMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (x, width, top, bottom) in [(0.06, 0.24, 0.26, 0.74), (0.36, 0.24, 0.10, 0.90), (0.66, 0.24, 0.26, 0.74)] {
            path.move(to: CGPoint(x: rect.minX + rect.width * (x + 0.12), y: rect.minY + rect.height * top))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * (x + width), y: rect.minY + rect.height * top))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * (x + width - 0.12), y: rect.minY + rect.height * bottom))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * bottom))
            path.closeSubpath()
        }
        return path
    }
}

struct Brand: View {
    var large = false
    var body: some View {
        Group {
            if large {
                VStack(spacing: 20) {
                    FuelMark().fill(Theme.lime).frame(width: 94, height: 94)
                    Text("DAYFUEL").font(.system(size: 42, weight: .black, design: .rounded)).italic().tracking(-2)
                    Text("FUEL YOUR EVERYDAY").font(.system(size: 10, weight: .bold)).tracking(3)
                        .foregroundStyle(Theme.muted)
                }.foregroundStyle(Theme.ivory)
            } else {
                HStack(spacing: 7) {
                    FuelMark().fill(Theme.lime).frame(width: 27, height: 30)
                    Text("DAYFUEL").font(.system(size: 21, weight: .black, design: .rounded)).italic().tracking(-0.8).foregroundStyle(Theme.ivory)
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("DAYFUEL")
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
                .foregroundStyle(Theme.background).background(Theme.lime, in: RoundedRectangle(cornerRadius: 18))
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
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(name.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1)
                Spacer(minLength: 0)
            }.foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-1).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text(unit).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            GeometryReader { geometry in
                Capsule().fill(color.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, value / max(1, goal))))
                    }
            }.frame(height: 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: value)
            Text("Ziel \(Int(goal)) · \(Int(abs(goal - value))) \(value <= goal ? "offen" : "darüber")")
                .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name): \(Int(value)) von \(Int(goal)) \(unit)")
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .bold, design: .rounded)).tracking(-0.5)
            Spacer()
            if let detail { Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted) }
        }
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
