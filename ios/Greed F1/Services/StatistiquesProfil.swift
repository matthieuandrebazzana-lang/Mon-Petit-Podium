import Foundation

/// Les statistiques d'un profil, servies par `GET /profils/{id}/stats` (§3.2) — le sien
/// comme celui d'un autre membre : **la même route pour les deux**, et c'est ce qui permet
/// de comparer les deux grilles.
///
/// **Cache *stale-while-revalidate*** (``CacheService``, `docs/swift-app.md` §7.6) : la
/// grille connue s'affiche aussitôt, relue si elle a plus de 30 s. **Les siennes seules
/// vont sur disque** (`snapshot`) : l'instance du compte connecté, possédée par
/// ``BarreNavigation`` et chargée dès le lancement, naît avec le dernier relevé ; celle
/// d'un autre membre (``ProfilMembreView``) reste en mémoire. La silhouette ne sert que
/// sans aucune donnée.
@MainActor
final class StatistiquesProfil: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret(StatsProfil)
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    /// Les statistiques du compte connecté : écrites sur disque.
    private let snapshot: Bool

    /// - Parameter profilId: connu d'avance (le compte connecté), l'instance naît remplie.
    init(profilId: UUID? = nil, snapshot: Bool = false) {
        self.snapshot = snapshot
        if let profilId, let lues: StatsProfil = CacheService.partage.valeur(
            Self.chemin(profilId), snapshot: snapshot) {
            etat = .pret(lues)
        }
    }

    /// L'UUID en minuscules : la forme que sert le backend, et celle de ses journaux.
    private static func chemin(_ profilId: UUID) -> String {
        "profils/\(profilId.uuidString.lowercased())/stats"
    }

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
            let chemin = Self.chemin(profilId)
            try await CacheService.partage.charger(
                chemin, snapshot: snapshot, forcer: forcer,
                afficher: { (lues: StatsProfil) in
                    if etat != .pret(lues) { etat = .pret(lues) }
                },
                lire: { try await APIClient.partage.lireJSON(chemin) })
        } catch is CancellationError {
            // Écran quitté pendant l'appel : rien à signaler.
        } catch {
            if case .pret = etat { return }
            etat = .echec(error as? ErreurAPI ?? .serveur(statut: nil, message: nil))
        }
    }
}
