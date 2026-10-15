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

    /// **Les lectures du lancement vivent ici, pas dans leurs onglets** : un onglet n'est
    /// construit qu'à sa première visite, et ses données n'attendent pas ce tap. Chacune
    /// naît avec son instantané disque (``CacheService``) et part en parallèle des autres
    /// (``chargerAuLancement()``).
    @StateObject private var prochainGP = ProchainGrandPrix()
    @StateObject private var calendrier = CalendrierSaison()
    @StateObject private var statistiques = StatistiquesProfil(
        profilId: SupabaseManager.partage.idCompte, snapshot: true)

    /// Les lectures du lancement sont revenues ; le préchargement peut partir, une fois.
    @State private var lancementTermine = false
    @State private var classementPrecharge = false

    /// L'onglet affiché. **Explicite** pour que l'avatar de l'accueil puisse mener au profil.
    @State private var ongletActif: Onglet = .accueil

    /// Le championnat qu'un tap sur le widget « Classement » demande d'ouvrir.
    @State private var championnatDemande: UUID?

    @Environment(\.scenePhase) private var phase

    /// Les quatre onglets, dans l'ordre de la barre.
    enum Onglet: Hashable {
        case accueil, championnats, calendrier, profil
    }

    var body: some View {
        TabView(selection: $ongletActif) {
            AccueilView(viewModel: viewModel, mesChampionnats: mesChampionnats,
                        prochainGP: prochainGP, ongletActif: $ongletActif)
                .tabItem { Label(t("onglet.accueil"), image: "icone-accueil") }
                .tag(Onglet.accueil)

            ChampionnatsView(mesChampionnats: mesChampionnats,
                             championnatDemande: $championnatDemande)
                .tabItem { Label(t("onglet.championnats"), image: "icone-championnats") }
                .tag(Onglet.championnats)

            CalendrierView(calendrier: calendrier)
                .tabItem { Label(t("onglet.calendrier"), image: "icone-calendrier") }
                .tag(Onglet.calendrier)

            // La pile porte « Mes Grands Prix » (``HistoriqueGPView``).
            NavigationStack { ProfilView(viewModel: viewModel, statistiques: statistiques) }
                .tabItem { Label(t("onglet.profil"), image: "icone-profil") }
                .tag(Onglet.profil)
        }
        .tint(.encrePrimaire)
        // La voiture du compte connecté, pour les écrans qui peignent le classement :
        // ``AuthViewModel`` en est la seule source (``Membre/avecVoiture(de:)``).
        .environment(\.monProfil, viewModel.profil)
        // La prévisualisation admin, pour les surfaces qui portent un bouton de pronostics.
        .environment(\.modePrevisualisation, viewModel.modePrevisualisation)
        // Le championnat connu, pour « Mes Grands Prix » et « Mes résultats » (``GrandsPrixJoues``).
        .environment(\.championnatParDefaut, mesChampionnats.premierId)
        // Un tap sur le widget « Prochain GP » (``DonneesWidget/urlAccueil``) ramène à
        // l'accueil, quel que soit l'onglet où l'app avait été laissée.
        .onOpenURL { url in
            if url == DonneesWidget.urlAccueil { ongletActif = .accueil }
            // Un tap sur le widget « Classement » ouvre son championnat.
            if let id = DonneesWidget.championnat(de: url) {
                ongletActif = .championnats
                championnatDemande = id
            }
        }
        // Widget « Classement » (`docs/decisions.md` §28) : un jeton neuf par lancement
        // (`renouvelerJeton` ignore le passage en actif qui suit, et ne redemande qu'après
        // 24 h), la liste et la carte du dessus de la pile à chaque lecture.
        .task { await SynchroWidgetClassement.renouvelerJeton() }
        .onChange(of: phase) { _, nouvelle in
            if nouvelle == .active { Task { await SynchroWidgetClassement.renouvelerJeton() } }
        }
        .task { await chargerAuLancement() }
        .onChange(of: mesChampionnats.etat) { _, etat in
            if case .pret(let liste) = etat {
                SynchroWidgetClassement.publier(liste, profilId: viewModel.profil?.id)
            }
            prechargerClassement()
        }
        .onChange(of: viewModel.profil?.id) { _, id in
            if case .pret(let liste) = mesChampionnats.etat {
                SynchroWidgetClassement.publier(liste, profilId: id)
            }
        }
    }

    // MARK: - Lancement

    /// Les quatre lectures indépendantes partent **ensemble** — aucune n'attend l'autre,
    /// ni le profil (l'identifiant du compte est celui de la session locale). Puis, l'accueil
    /// rempli, le classement du championnat au premier plan de la pile est préchargé, sans
    /// rien afficher : l'ouvrir ne montre plus de silhouette.
    private func chargerAuLancement() async {
        async let championnats: Void = mesChampionnats.charger()
        async let gp: Void = prochainGP.charger()
        async let stats: Void = statistiques.charger(profilId: SupabaseManager.partage.idCompte)
        async let saison: Void = calendrier.charger()
        _ = await (championnats, gp, stats, saison)
        lancementTermine = true
        prechargerClassement()
    }

    /// Une fois les lectures du lancement revenues **et** la liste connue — l'accueil peut
    /// avoir lancé la sienne le premier, auquel cas elle arrive après.
    private func prechargerClassement() {
        guard lancementTermine, !classementPrecharge,
              case .pret(let liste) = mesChampionnats.etat,
              let premier = OrdrePile.rapprocher(
                OrdrePile.lire(pour: SupabaseManager.partage.idCompte), de: liste).first
        else { return }
        classementPrecharge = true
        Task(priority: .utility) { await ClassementChampionnat.precharger(premier) }
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
    /// > ignoré de même. Seul `.tint(.encrePrimaire)` passe (actif mesuré à **11,33:1**).
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
    /// L'actif `#800111` y tient **9,61:1**. Les deux sont des jetons dynamiques : en
    /// sombre, `#AEAEB2` et `#FF6961` (``Color/encrePrimaire``), le fond suivant
    /// ``Color/fondPrincipal``.
    private static func habiller(_ agencement: UITabBarItemAppearance) {
        let inactif = UIColor(Color.grisSecondaire)
        let actif = UIColor(Color.encrePrimaire)

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
