import Foundation

/// Ce que la base sait des Grands Prix de la saison, servi par `GET /calendrier` (§3.4) —
/// de quoi croiser la liste statique de ``CalendrierView``.
///
/// > **La liste ne dépend pas de cet appel.** Les douze cartes viennent de
/// > ``GrandPrixSaison/saison2026`` et s'affichent quoi qu'il arrive : l'échec fait perdre
/// > les états et les identifiants, jamais le calendrier (`docs/swift-app.md` §7.6).
///
/// **`/calendrier` et non plus `/scraper/cotes`** (backend `0.85.0`) : le calendrier ne lit
/// que `id`, le statut, les deux heures et l'**existence** de cotes (`a_des_cotes`) — une
/// requête, là où `/scraper/cotes` relisait toutes les cotes de chaque GP. Les cotes
/// détaillées ne se chargent qu'à l'ouverture d'un GP (``DonneesPronostics``).
///
/// **Cache *stale-while-revalidate*, instantané sur disque** (``CacheService``) : l'instance
/// naît avec les états connus, relus en arrière-plan s'ils ont plus de 30 s. Possédée par
/// ``BarreNavigation``, chargée dès le lancement avec le reste. La silhouette ne sert que
/// sans aucune donnée.
@MainActor
final class CalendrierSaison: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret([GrandPrixEnBase])
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    private static let cle = "calendrier"

    init() {
        if let liste: [GrandPrixEnBase] = CacheService.partage.valeur(Self.cle, snapshot: true) {
            etat = .pret(liste)
        }
    }

    private var enCours = false

    /// Ce que la base sait, `nil` tant que rien n'a été lu — **« inconnu » n'est pas
    /// « absent de la base »** : le second fait d'un Grand Prix un « À venir », le premier
    /// ne dit rien.
    var enBase: [GrandPrixEnBase]? {
        if case .pret(let liste) = etat { return liste }
        return nil
    }

    func charger(forcer: Bool = false) async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            try await CacheService.partage.charger(
                Self.cle, snapshot: true, forcer: forcer,
                afficher: { (liste: [GrandPrixEnBase]) in
                    if etat != .pret(liste) { etat = .pret(liste) }
                },
                lire: { try await APIClient.partage.lireJSON(Self.cle) })
        } catch is CancellationError {
            // Onglet quitté pendant l'appel : la prochaine apparition le relance.
        } catch {
            if case .pret = etat { return }
            etat = .echec(error as? ErreurAPI ?? .serveur(statut: nil, message: nil))
        }
    }
}
