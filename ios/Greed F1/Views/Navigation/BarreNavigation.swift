import SwiftUI
import UIKit

/// Barre de navigation principale : quatre onglets, montée dès que l'utilisateur est connecté.
///
/// La barre est un **matériau translucide** posé par-dessus le contenu plutôt qu'un bandeau
/// opaque, et le contenu défile dessous. ``appliquerApparence()`` est le seul endroit qui
/// l'habille.
///
/// > **Les quatre icônes sont les assets de la version web**, pas des SF Symbols : garage,
/// > coupe, calendrier et pilote casqué, découpés de la planche `logo-02.svg` par
/// > `ios/scripts/decouper-icones.sh`. Elles sont en rendu *template*, donc teintes par
/// > `.tint()` et par l'apparence ci-dessous comme le serait un symbole système.
struct BarreNavigation: View {

    /// Le view model d'authentification descend explicitement, comme sur `LandingView` :
    /// c'est lui qui porte le pseudo affiché par l'accueil.
    @ObservedObject var viewModel: AuthViewModel

    /// Les championnats du compte, **une instance pour deux onglets** : l'accueil et
    /// l'onglet Championnats lisent la même liste (``MesChampionnats``).
    @StateObject private var mesChampionnats = MesChampionnats()

    var body: some View {
        TabView {
            AccueilView(viewModel: viewModel, mesChampionnats: mesChampionnats)
                .tabItem { Label("Accueil", image: "icone-accueil") }

            ChampionnatsView(mesChampionnats: mesChampionnats)
                .tabItem { Label("Championnats", image: "icone-championnats") }

            CalendrierView()
                .tabItem { Label("Calendrier", image: "icone-calendrier") }

            // La pile porte « Mes Grands Prix » (``HistoriqueGPView``).
            NavigationStack { ProfilView(viewModel: viewModel) }
                .tabItem { Label("Profil", image: "icone-profil") }
        }
        .tint(.primaire)
        // La voiture du compte connecté, pour les écrans qui peignent le classement :
        // ``AuthViewModel`` en est la seule source (``Membre/avecVoiture(de:)``).
        .environment(\.monProfil, viewModel.profil)
        // La prévisualisation admin, pour les surfaces qui portent un bouton de pronostics.
        .environment(\.modePrevisualisation, viewModel.modePrevisualisation)
    }

    // MARK: - Apparence

    /// Habille la barre d'onglets. À appeler une fois, au démarrage de l'app.
    ///
    /// SwiftUI ne sait pas teindre un onglet **inactif** : il faut passer par
    /// `UITabBarAppearance`. Tant qu'on y est, on y fixe aussi le matériau et la typographie.
    ///
    /// > **Inerte sous iOS 26.** Le « Liquid Glass » y reprend la main sur toute la barre :
    /// > mesuré au simulateur iPhone 17 Pro / iOS 26.5, le fond reste `#FEFAF7` et l'encre
    /// > inactive `#1C1815` (17:1) quoi qu'on demande ici — `unselectedItemTintColor` est
    /// > ignoré de même. Seul `.tint(.primaire)` passe (actif mesuré à **11,33:1**).
    /// > Ce bloc ne sert donc qu'aux versions **iOS 17 et 18**, où le gris système par défaut
    /// > tombe à ~2,5:1 sur ce fond clair. Il n'y est pas vérifié : aucun runtime antérieur
    /// > n'est installé.
    static func appliquerApparence() {
        let apparence = UITabBarAppearance()

        // Matériau système (flou + filet supérieur), teinté beige. `configureWithDefaultBackground`
        // conserve l'effet de flou ; poser une couleur par-dessus ne fait que la teinter.
        // Sous « Réduire la transparence », iOS retombe seul sur un fond opaque.
        apparence.configureWithDefaultBackground()
        apparence.backgroundColor = UIColor(Color.fondPrincipal).withAlphaComponent(0.72)

        habiller(apparence.stackedLayoutAppearance)
        habiller(apparence.inlineLayoutAppearance)
        habiller(apparence.compactInlineLayoutAppearance)

        UITabBar.appearance().standardAppearance = apparence
        UITabBar.appearance().scrollEdgeAppearance = apparence
    }

    /// Teinte et typographie d'un agencement d'onglet.
    ///
    /// **L'inactif est `grisSecondaire` (#6B6B6B), pas le gris système.** Sur le beige
    /// `#F5F0EB` le gris d'iOS mesure **2,52:1** — sous le plancher de 4,5:1 du libellé
    /// comme sous celui de 3:1 de l'icône. `#6B6B6B` y tient **4,71:1**.
    /// L'actif `#800111` y tient **9,61:1**.
    private static func habiller(_ agencement: UITabBarItemAppearance) {
        let inactif = UIColor(Color.grisSecondaire)
        let actif = UIColor(Color.primaire)

        agencement.normal.iconColor = inactif
        agencement.normal.titleTextAttributes = [
            .foregroundColor: inactif,
            .font: UIFont(name: "HelveticaNeue", size: 10) ?? .systemFont(ofSize: 10),
            // Crénage positif sur un petit texte : le design system le prescrit sur les
            // labels, et un libellé de 10 pt en a besoin autant.
            .kern: 0.2
        ]

        agencement.selected.iconColor = actif
        agencement.selected.titleTextAttributes = [
            .foregroundColor: actif,
            .font: UIFont(name: "HelveticaNeue-Medium", size: 10) ?? .systemFont(ofSize: 10, weight: .medium),
            .kern: 0.2
        ]
    }
}

#Preview {
    BarreNavigation(viewModel: AuthViewModel())
}
