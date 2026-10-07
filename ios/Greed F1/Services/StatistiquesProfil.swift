import Foundation

/// Les statistiques d'un profil, servies par `GET /profils/{id}/stats` (§3.2) — le sien
/// comme celui d'un autre membre : **la même route pour les deux**, et c'est ce qui permet
/// de comparer les deux grilles.
///
/// Possédée par l'écran (`@StateObject`). **Cache *stale-while-revalidate*, 60 s**
/// (``CacheService``, `docs/swift-app.md` §7.6) : la grille connue s'affiche aussitôt, et
/// n'est relue que si elle a plus d'une minute. Le spinner ne sert qu'au premier
/// chargement et après un échec.
@MainActor
final class StatistiquesProfil: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret(StatsProfil)
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    /// Vrai pendant un appel : un retour rapide sur l'écran n'en lance pas un second.
    private var enCours = false

    /// Les statistiques lues, `nil` tant qu'aucune ne l'a été.
    var stats: StatsProfil? {
        if case .pret(let stats) = etat { return stats }
        return nil
    }

    /// `profilId` nul : le compte n'a pas pu être lu, il n'y a personne à interroger.
    /// C'est un échec rejouable, pas un chargement sans fin.
    func charger(profilId: UUID?, forcer: Bool = false) async {
        guard let profilId else {
            if stats == nil { etat = .echec(.reseau) }
            return
        }
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            // L'UUID en minuscules : la forme que sert le backend, et celle de ses journaux.
            let chemin = "profils/\(profilId.uuidString.lowercased())/stats"
            try await CacheService.partage.charger(
                chemin, duree: CacheService.Duree.court, forcer: forcer,
                afficher: { (lues: StatsProfil) in
                    if etat != .pret(lues) { etat = .pret(lues) }
                },
                lire: { try await APIClient.partage.requete(chemin) })
        } catch is CancellationError {
            // Écran quitté pendant l'appel : rien à signaler.
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }
}
