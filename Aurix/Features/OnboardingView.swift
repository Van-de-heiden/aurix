import SwiftUI
import UIKit
import AurixCore

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var profile = UserProfile()
    @State private var step = 0
    @FocusState private var nameFocused: Bool
    private let lastStep = 9

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if step == 0 {
                WelcomeBackdrop()
                welcome
            } else {
                LinearGradient(colors: [Theme.cyan.opacity(0.055), .clear], startPoint: .topLeading, endPoint: .center)
                    .ignoresSafeArea().allowsHitTesting(false)
                questionnaire
            }
        }
        .aurixScreen()
    }
    private var welcome: some View {
        VStack(spacing: 0) {
            Brand(large: true).padding(.top, 30).frame(maxWidth: .infinity)
            Spacer()
            Text("Food fuels\nmore than just today.").font(.system(size: 21, weight: .regular)).multilineTextAlignment(.center).lineSpacing(4).padding(.bottom, 30)
            PrimaryButton(title: "Los geht’s") { advance() }.accessibilityIdentifier("onboarding.start")
            Text("Nur du. Dein Ziel. AURIX.").font(.system(size: 12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 16)
        }.padding(.horizontal, 28).padding(.bottom, 20)
    }
    private var questionnaire: some View {
        VStack(spacing: 20) {
            HStack {
                Button { nameFocused = false; withAnimation(stepAnimation) { step -= 1 } } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }.accessibilityLabel("Zurück")
                Spacer(); Text("\(step) / \(lastStep)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            ProgressView(value: Double(step), total: Double(lastStep)).tint(Theme.cyan)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(eyebrow).font(.system(size: 10, weight: .semibold)).tracking(2.5).foregroundStyle(Theme.cyan)
                    Text(title).font(.system(size: 34, weight: .medium, design: .rounded)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                    content
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14).padding(.bottom, 20)
                    .id(step).transition(.opacity)
            }.scrollDismissesKeyboard(.interactively)
            PrimaryButton(title: step == lastStep ? "Mein nächstes Kapitel" : "Weiter", disabled: !canAdvance) { advance() }
                .accessibilityIdentifier("onboarding.next")
        }.padding(.horizontal, 26).padding(.bottom, 18)
    }
    private var eyebrow: String { step == lastStep ? "DEIN AUSGANGSPUNKT" : "DEIN WEG BEGINNT HIER" }
    private var title: String {
        switch step {
        case 1: return "Wie heisst du?"
        case 2: return "Was ist dein Ziel?"
        case 3: return "Wie alt bist du?"
        case 4: return "Wie gross bist du?"
        case 5: return "Was wiegst du aktuell?"
        case 6: return "Welche Berechnung passt?"
        case 7: return "Wie aktiv ist dein Alltag?"
        case 8: return "Wo möchtest du hin?"
        default: return "Das ist dein Start."
        }
    }
    @ViewBuilder private var content: some View {
        switch step {
        case 1:
            TextField("Dein Vorname", text: $profile.name).font(.system(size: 28, weight: .medium)).textContentType(.givenName).focused($nameFocused)
                .submitLabel(.continue).onSubmit { if canAdvance { advance() } }.padding(22).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                .onChange(of: profile.name) { _, new in if new.count > 60 { profile.name = String(new.prefix(60)) } }
            Text("So persönlich wie dein Fortschritt.").foregroundStyle(Theme.muted)
        case 2:
            ForEach(GoalDirection.allCases, id: \.self) { goal in
                choice(goal.title, detail: goal.subtitle, icon: goal.symbol, selected: profile.direction == goal) { profile.direction = goal }
            }
        case 3:
            wheel(value: Binding(get: { Double(profile.age) }, set: { profile.age = Int($0) }), values: Array(18...90).map(Double.init), unit: "Jahre")
        case 4:
            wheel(value: $profile.height, values: Array(120...220).map(Double.init), unit: "cm")
        case 5:
            WeightSelection(value: $profile.weight).accessibilityIdentifier("onboarding.weight")
        case 6:
            choice("Männlich", detail: "Mifflin–St Jeor, männliche Formel", icon: "figure.stand", selected: profile.maleFormula) { profile.maleFormula = true }
            choice("Weiblich", detail: "Mifflin–St Jeor, weibliche Formel", icon: "figure.stand", selected: !profile.maleFormula) { profile.maleFormula = false }
            Text("Das beeinflusst nur die Bedarfsschätzung. Alle Tagesziele kannst du später selbst anpassen.").font(.footnote).foregroundStyle(Theme.muted)
        case 7:
            choice("Eher ruhig", detail: "Viel Sitzen, wenig Sport", icon: "chair", selected: profile.activity == 1.2) { profile.activity = 1.2 }
            choice("Etwas Bewegung", detail: "Spaziergänge, 1–2 Trainings pro Woche", icon: "figure.walk", selected: profile.activity == 1.375) { profile.activity = 1.375 }
            choice("Regelmässig aktiv", detail: "3–5 Trainings und Bewegung im Alltag", icon: "dumbbell", selected: profile.activity == 1.55) { profile.activity = 1.55 }
            choice("Sehr aktiv", detail: "Viel Bewegung und intensives Training", icon: "figure.run", selected: profile.activity == 1.725) { profile.activity = 1.725 }
        case 8:
            WeightSelection(value: $profile.targetWeight).accessibilityIdentifier("onboarding.targetWeight")
            Text(profile.direction == .maintain ? "Dein Wohlfühlgewicht als Orientierung." : "Ein Ziel ohne unnötigen Zeitdruck. Du bestimmst das Tempo.").font(.footnote).foregroundStyle(Theme.muted)
            if !canAdvance { Text(profile.direction == .gain ? "Wähle ein Ziel über deinem aktuellen Gewicht." : "Wähle ein Ziel unter deinem aktuellen Gewicht.").font(.footnote).foregroundStyle(Theme.carbs) }
        default:
            let goals = profile.goals
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                goalTile("Kalorien", Int(goals.calories), "kcal", Theme.cyan)
                goalTile("Protein", Int(goals.protein), "g", Theme.protein)
                goalTile("Carbs", Int(goals.carbs), "g", Theme.carbs)
                goalTile("Fette", Int(goals.fat), "g", Theme.fat)
            }
            Text("Ein berechneter Startwert – kein gemessener Bedarf. Passe deine Ziele in den Einstellungen jederzeit an.").font(.footnote).foregroundStyle(Theme.muted)
            Label("Foto, Barcode, Sprache oder von Hand.", systemImage: "bolt").font(.subheadline)
        }
    }
    private func choice(_ text: String, detail: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { action() }; UISelectionFeedbackGenerator().selectionChanged() } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 22)).frame(width: 30).foregroundStyle(selected ? Theme.cyan : Theme.muted)
                VStack(alignment: .leading, spacing: 5) { Text(text).font(.system(size: 17, weight: .semibold)); Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading) }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.cyan : Theme.muted.opacity(0.4))
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Theme.cyan.opacity(0.7) : .clear, lineWidth: 1))
        }.buttonStyle(PressStyle()).foregroundStyle(Theme.ivory).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func wheel(value: Binding<Double>, values: [Double], unit: String) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value.wrappedValue, format: .number.precision(.fractionLength(0))).font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                Text(unit).foregroundStyle(Theme.cyan).font(.title3)
            }.frame(maxWidth: .infinity)
            Picker(unit, selection: value) {
                ForEach(values, id: \.self) { number in Text(number.formatted(.number.precision(.fractionLength(0))) + " " + unit).tag(number) }
            }.pickerStyle(.wheel).frame(height: 190).clipped()
        }.padding(.vertical, 18).background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 26))
    }
    private func goalTile(_ label: String, _ value: Int, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.footnote).foregroundStyle(color)
            Text("\(value)").font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            Text(unit + " pro Tag").font(.caption).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private var canAdvance: Bool {
        if step == 1 { return !profile.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if step == 8 { return profile.direction == .maintain || (profile.direction == .gain ? profile.targetWeight > profile.weight : profile.targetWeight < profile.weight) }
        return true
    }
    private var stepAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }
    private func advance() {
        nameFocused = false
        if step == 7 { profile.targetWeight = min(200, max(40, profile.weight + (profile.direction == .gain ? 5 : profile.direction == .lose ? -5 : 0))) }
        if step == 8 { profile.goals = GoalCalculator.suggested(for: profile) }
        if step == lastStep { profile.name = profile.name.trimmingCharacters(in: .whitespaces); store.saveProfile(profile) }
        else { withAnimation(stepAnimation) { step += 1 } }
    }
}

private struct WelcomeBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        GeometryReader { geometry in
            Image("Summit").resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .scaleEffect(revealed && !reduceMotion ? 1.015 : 1)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.12), .clear, Theme.background.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        // A short, isolated entrance: no ongoing full-screen animation behind pickers.
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 1.2)) { revealed = true } }
    }
}

struct WeightSelection: View {
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("kg").foregroundStyle(Theme.cyan).font(.title3)
            }.frame(maxWidth: .infinity)
            KilogramWheel(value: $value).frame(height: 190)
        }.padding(.vertical, 18).background(Theme.card, in: RoundedRectangle(cornerRadius: 26))
    }
}

/// UIKit creates only the visible wheel rows, rather than 1,601 SwiftUI views.
private struct KilogramWheel: UIViewRepresentable {
    @Binding var value: Double

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.synchronize(picker, value: value)
        return picker
    }
    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.synchronize(picker, value: value)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var value: Binding<Double>
        private var whole = 80
        init(value: Binding<Double>) { self.value = value }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? 161 : (whole == 200 ? 1 : 2)
        }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            component == 0 ? String(row + 40) : (row == 0 ? ".0" : ".5")
        }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            pickerView.bounds.width * 0.42
        }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let half = max(0, pickerView.selectedRow(inComponent: 1))
            if component == 0 {
                whole = row + 40
                pickerView.reloadComponent(1)
                pickerView.selectRow(whole == 200 ? 0 : half, inComponent: 1, animated: false)
            }
            value.wrappedValue = Double(whole) + (whole == 200 ? 0 : Double(max(0, pickerView.selectedRow(inComponent: 1))) * 0.5)
        }
        func synchronize(_ picker: UIPickerView, value: Double) {
            let rounded = min(200, max(40, (value * 2).rounded() / 2))
            let newWhole = Int(rounded)
            if whole != newWhole {
                whole = newWhole
                picker.reloadComponent(1)
            }
            let selections = [whole - 40, Int((rounded - Double(whole)) * 2)]
            for component in 0...1 where picker.selectedRow(inComponent: component) != selections[component] {
                picker.selectRow(selections[component], inComponent: component, animated: false)
            }
        }
    }
}
