import SwiftUI

@main
struct GreedF1App: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        BarreNavigation.appliquerApparence()
    }

    var body: some Scene {
        WindowGroup {
            if authViewModel.estConnecte {
                BarreNavigation()
            } else {
                LandingView(viewModel: authViewModel)
            }
        }
    }
}
