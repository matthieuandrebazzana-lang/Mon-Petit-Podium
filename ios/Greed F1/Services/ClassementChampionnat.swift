import Foundation

/// Le classement d'un championnat, servi par `GET /championnats/{id}/classement` (§3.3).
///
/// > **Un seul appel pour les deux segments.** ``ChampionnatDetailView`` possède cette
/// > instance ; le classement et la piste lisent le même tableau. Deux appels auraient pu
/// > se croiser avec un Grand Prix noté entre les deux — une voiture qui ne dit plus le
/// > score de sa ligne.
///
/// **Cache *stale-while-revalidate*** (``CacheService``, `docs/swift-app.md` §7.6) :
/// rouvrir le championnat affiche aussitôt le classement connu, relu en arrière-plan s'il
/// a plus de 30 s. **Celui du premier plan de la pile va sur disque** — préchargé par
/// ``BarreNavigation`` une fois l'accueil affiché (``precharger(_:)``) : c'est le
/// championnat qu'on ouvre le plus, il s'ouvre donc déjà rempli, même à froid. La
/// silhouette ne sert que sans aucune donnée.
@MainActor
final class ClassementChampionnat: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret([Membre])
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    private let championnatId: UUID
    private let snapshot: Bool

    /// Vrai pendant un appel : un retour rapide du profil d'un membre n'en lance pas un
    /// second par-dessus le premier.
    private var enCours = false

    /// - Parameter snapshot: `nil` — sur disque si c'est le premier plan de la pile.
    init(championnatId: UUID, snapshot: Bool? = nil) {
        self.championnatId = championnatId
        self.snapshot = snapshot
            ?? (OrdrePile.lire(pour: SupabaseManager.partage.idCompte).first == championnatId)
        if let membres: [Membre] = CacheService.partage.valeur(Self.chemin(championnatId),
                                                               snapshot: self.snapshot) {
            etat = .pret(membres)
        }
    }

    /// Remplit le cache — mémoire et disque — sans écran : l'ouverture du championnat
    /// trouvera le classement déjà là.
    static func precharger(_ championnatId: UUID) async {
        await ClassementChampionnat(championnatId: championnatId, snapshot: true).charger()
    }

    /// L'UUID en minuscules : la forme que sert le backend, et celle de ses journaux.
    private static func chemin(_ championnatId: UUID) -> String {
        "championnats/\(championnatId.uuidString.lowercased())/classement"
    }

    /// - Parameter forcer: rappelle la route même si le cache est frais.
    func charger(forcer: Bool = false) async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            let chemin = Self.chemin(championnatId)
            try await CacheService.partage.charger(
                chemin, snapshot: snapshot, forcer: forcer,
                afficher: { (membres: [Membre]) in
                    if etat != .pret(membres) { etat = .pret(membres) }
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
