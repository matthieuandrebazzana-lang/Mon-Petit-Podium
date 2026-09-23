import SwiftUI

@main
struct GreedF1App: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        BarreNavigation.appliquerApparence()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.estConnecte {
                    BarreNavigation(viewModel: authViewModel)
                } else {
                    LandingView(viewModel: authViewModel)
                }
            }
            // Réveil de Railway dès le lancement, sans attendre la réponse : le temps
            // d'atteindre un écran qu'il sert, le service est levé (docs/swift-app.md §3.1).
            .onAppear { APIClient.partage.reveiller() }
        }
    }
}
