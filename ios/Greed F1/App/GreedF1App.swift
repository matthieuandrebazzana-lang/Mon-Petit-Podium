import SwiftUI

@main
struct GreedF1App: App {
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            if authViewModel.estConnecte {
                Text("Accueil — à venir")
                    .font(.custom("Helvetica Neue", size: 24))
                    .foregroundColor(.primaire)
            } else {
                LandingView(viewModel: authViewModel)
            }
        }
    }
}
