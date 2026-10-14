import SwiftUI

@main
struct GreedF1App: App {
    /// Seul moyen de recevoir le jeton APNs (`NotificationsPush`).
    @UIApplicationDelegateAdaptor(DelegueApplication.self) private var delegue
    @StateObject private var authViewModel = AuthViewModel()
    /// Langue de l'interface — injectée ici, lue par ``t(_:)`` partout (`LanguageManager`).
    @StateObject private var langues = LanguageManager.shared
    /// Apparence forcée ou automatique — posée sur les fenêtres (`ThemeManager`).
    @StateObject private var theme = ThemeManager.shared

    init() {
        BarreNavigation.appliquerApparence()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.estConnecte {
                    // Premier compte Google (ou Apple) sans pseudo choisi : l'onboarding
                    // passe avant le reste de l'app, contrepartie exacte du garde posé
                    // dans `RouteProtegee` côté web.
                    if authViewModel.pseudoAConfigurer {
                        OnboardingView(viewModel: authViewModel)
                    } else {
                        BarreNavigation(viewModel: authViewModel)
                            // Permission demandée une fois connecté et le pseudo choisi ;
                            // iOS ne montre la feuille qu'une fois, la suite est silencieuse.
                            .task { await NotificationsPush.partage.activer() }
                    }
                } else {
                    LandingView(viewModel: authViewModel)
                }
            }
            // Réveil de Railway dès le lancement, sans attendre la réponse : le temps
            // d'atteindre un écran qu'il sert, le service est levé (docs/swift-app.md §3.1).
            .onAppear {
                APIClient.partage.reveiller()
                // La fenêtre existe maintenant : le choix enregistré peut s'y poser.
                theme.appliquer()
                // La langue active — choisie ou détectée — est celle du widget.
                DonneesWidget.recharger(si: DonneesWidget.enregistrer(langue: langues.langue))
            }
            // Les notifications partent dans la langue enregistrée avec le jeton.
            .onChange(of: langues.langue) {
                NotificationsPush.partage.langueChangee()
                DonneesWidget.recharger(si: DonneesWidget.enregistrer(langue: langues.langue))
            }
            .environmentObject(langues)
            .environmentObject(theme)
            // Les formats système (dates, nombres) suivent la langue choisie, pas le téléphone.
            .environment(\.locale, langues.locale)
        }
    }
}
