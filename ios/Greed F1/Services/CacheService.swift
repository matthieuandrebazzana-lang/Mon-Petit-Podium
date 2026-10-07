import Foundation

/// Cache mémoire *stale-while-revalidate* — le modèle de `lib/useDonnees.js` côté web
/// (`docs/decisions.md` §27, `docs/swift-app.md` §7.6).
///
/// Un écran qui réapparaît affiche **aussitôt** ce que l'app savait déjà, puis :
///
/// - la valeur a moins que sa durée de validité → rien n'est rappelé ;
/// - elle est plus vieille → elle reste affichée pendant que la route est rappelée, et la
///   réponse la remplace.
///
/// **Mémoire seulement** : rien n'est écrit sur disque, tout disparaît à la fermeture de
/// l'app. **La clé porte l'identifiant du compte** (`docs/architecture.md` §9) — deux
/// personnes qui se relaient sur le même téléphone ne voient jamais les données de l'autre,
/// et ``vider()`` part en plus à la déconnexion.
///
/// **Invalidation** : `charger(forcer: true)` d'un service — appelé après chaque écriture —
/// périme sa propre clé, et toute écriture réussie de ``APIClient`` (`POST`, `PATCH`,
/// `DELETE`) périme **tout** : une voiture repeinte change le classement, un championnat
/// quitté la liste. Périmer n'est pas effacer : la valeur reste affichable, elle sera
/// simplement relue à la prochaine apparition.
@MainActor
final class CacheService {

    static let partage = CacheService()

    /// Les durées de validité — une par famille de route.
    enum Duree {
        /// Championnats, classement, statistiques : ce qui bouge dès qu'un GP est noté.
        static let court: TimeInterval = 60
        /// Le calendrier et le prochain Grand Prix : quelques changements par semaine.
        static let calendrier: TimeInterval = 5 * 60
    }

    private struct Entree {
        let valeur: Any
        var lueLe: Date
    }

    private var entrees: [String: Entree] = [:]

    private init() {}

    /// Lit `cle` en *stale-while-revalidate*.
    ///
    /// - Parameters:
    ///   - forcer: périme la clé avant de lire — la route est rappelée quoi qu'il arrive.
    ///   - afficher: reçoit la valeur en cache (même périmée) **puis** la valeur relue.
    ///   - lire: l'appel réseau. Son erreur remonte telle quelle ; la valeur en cache, déjà
    ///     affichée, n'est pas retirée.
    func charger<Valeur>(
        _ cle: String,
        duree: TimeInterval,
        forcer: Bool = false,
        afficher: (Valeur) -> Void,
        lire: () async throws -> Valeur
    ) async throws {
        let cleCompte = Self.cleCompte(cle)
        if forcer { perimer(cleCompte) }

        if let entree = entrees[cleCompte], let valeur = entree.valeur as? Valeur {
            afficher(valeur)
            if Date.now.timeIntervalSince(entree.lueLe) < duree { return }
        }

        let valeur = try await lire()
        entrees[cleCompte] = Entree(valeur: valeur, lueLe: .now)
        afficher(valeur)
    }

    /// Périme toutes les entrées : relues à la prochaine apparition, affichées d'ici là.
    func toutPerimer() {
        for cle in entrees.keys { perimer(cle) }
    }

    /// Efface tout — à la déconnexion et à la suppression du compte.
    func vider() {
        entrees.removeAll()
    }

    private func perimer(_ cleCompte: String) {
        entrees[cleCompte]?.lueLe = .distantPast
    }

    /// `<compte>|<route>` — le compte d'abord, sans quoi un changement de compte servirait
    /// les données du précédent.
    private static func cleCompte(_ cle: String) -> String {
        let compte = SupabaseManager.partage.client.auth.currentUser?.id.uuidString ?? "anonyme"
        return "\(compte)|\(cle)"
    }
}
