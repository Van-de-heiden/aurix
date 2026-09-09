import SwiftUI

@main
struct AurixApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if store.cannotLoad {
                    ContentUnavailableView("Tagebuch nicht verfügbar", systemImage: "externaldrive.badge.exclamationmark", description: Text("Bitte öffne AURIX erneut. Deine gespeicherten Dateien werden nicht überschrieben."))
                } else if store.profile == nil { OnboardingView() }
                else { HomeView() }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(Theme.cyan)
            .alert("AURIX", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Verstanden", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}
