import Foundation

/// Cache *stale-while-revalidate* — le modèle de `lib/useDonnees.js` côté web
/// (`docs/decisions.md` §27 et §29, `docs/swift-app.md` §7.6).
///
/// **L'ancienne valeur s'affiche toujours**, aussitôt ; elle est relue en arrière-plan si
/// elle a plus de ``fraicheur`` (30 s), et la réponse la remplace. Un échec de relecture
/// ne la retire pas.
///
/// **Une relecture en cours n'est jamais relancée en double** : deux écrans qui demandent
/// la même clé ensemble attendent la même requête. Une demande arrivée **après** une
/// invalidation n'attend pas une réponse partie avant elle — elle la laisse finir, puis
/// relit.
///
/// **Deux étages.** La mémoire, pour tout ; le disque (``SnapshotsDisque``), pour les clés
/// lues avec `snapshot: true` — ce que l'app montre au lancement à froid : championnats,
/// prochain GP, classement du premier plan, profil et ses statistiques, calendrier. C'est
/// **la réponse brute du serveur** qui est écrite, et relue par le même décodeur que le
/// réseau : aucun modèle n'a à savoir s'encoder. Un instantané relu du disque est toujours
/// revalidé, quel que soit son âge.
///
/// **La clé porte l'identifiant du compte** (`docs/architecture.md` §9), en mémoire comme
/// sur le disque — deux personnes qui se relaient sur le même téléphone ne voient jamais
/// les données de l'autre. Une réponse arrivée après un changement de compte est jetée, ni
/// affichée ni écrite. ``vider()`` efface les deux étages à la déconnexion et à la
/// suppression du compte.
///
/// **Invalidation** : `charger(forcer: true)` d'un service — appelé après chaque écriture —
/// périme sa propre clé, et toute écriture réussie (``APIClient`` : `POST`, `PATCH`,
/// `DELETE` ; le pseudo, écrit en direct) périme **tout** : une voiture repeinte change le
/// classement, un championnat quitté la liste. Périmer n'est pas effacer : la valeur reste
/// affichable, elle sera simplement relue à la prochaine demande.
@MainActor
final class CacheService {

    static let partage = CacheService()

    /// Au-delà de cet âge, une valeur affichée est relue en arrière-plan.
    static let fraicheur: TimeInterval = 30

    private struct Entree {
        let valeur: Any
        var lueLe: Date
    }

    /// Une relecture en vol, et la génération de sa clé à son départ.
    private struct Lecture {
        let tache: Task<Data, Error>
        let generation: Int
    }

    private var entrees: [String: Entree] = [:]
    private var enVol: [String: Lecture] = [:]
    /// Incrémentée à chaque invalidation : une lecture partie sous une génération plus
    /// ancienne peut dater d'avant l'écriture.
    private var generations: [String: Int] = [:]

    private init() {}

    /// Lit `cle` en *stale-while-revalidate*.
    ///
    /// - Parameters:
    ///   - snapshot: la réponse est aussi écrite sur disque, et relue au lancement à froid.
    ///   - forcer: périme la clé avant de lire — la route est rappelée quoi qu'il arrive.
    ///   - decoder: décode la réponse brute — le même pour le réseau et pour le disque.
    ///   - afficher: reçoit la valeur connue (même périmée) **puis** la valeur relue.
    ///   - lire: l'appel réseau, qui rend le JSON brut. Son erreur remonte telle quelle ;
    ///     la valeur connue, déjà affichée, n'est pas retirée.
    func charger<Valeur: Decodable>(
        _ cle: String,
        snapshot: Bool = false,
        forcer: Bool = false,
        afficher: (Valeur) -> Void,
        lire: @escaping () async throws -> Data
    ) async throws {
        try await charger(cle, snapshot: snapshot, forcer: forcer, decoder: Self.decodeur,
                          afficher: afficher, lire: lire)
    }

    /// Variante au décodeur explicite — une réponse dont l'app ne garde qu'une partie.
    func charger<Valeur: Decodable>(
        _ cle: String,
        snapshot: Bool = false,
        forcer: Bool = false,
        decoder: @escaping (Data) throws -> Valeur,
        afficher: (Valeur) -> Void,
        lire: @escaping () async throws -> Data
    ) async throws {
        let compte = Self.compte()
        let cleCompte = "\(compte)|\(cle)"
        if forcer { perimer(cleCompte) }

        if let valeur = connue(cle, compte: compte, snapshot: snapshot, decoder: decoder) {
            afficher(valeur)
            if let entree = entrees[cleCompte],
               Date.now.timeIntervalSince(entree.lueLe) < Self.fraicheur { return }
        }

        let donnees = try await relire(cleCompte, lire: lire)
        // Le compte a changé pendant l'appel : la réponse est celle de l'autre.
        guard Self.compte() == compte else { throw CancellationError() }
        let valeur: Valeur
        do {
            valeur = try decoder(donnees)
        } catch {
            // Le serveur a dit « succès » dans une forme qu'on ne sait pas lire.
            throw ErreurAPI.serveur(statut: nil, message: nil)
        }
        entrees[cleCompte] = Entree(valeur: valeur, lueLe: .now)
        if snapshot, compte != Self.anonyme {
            SnapshotsDisque.ecrire(donnees, cle: cle, compte: compte)
        }
        afficher(valeur)
    }

    /// La valeur connue de `cle` — mémoire, sinon disque —, **sans réseau**. C'est ce qui
    /// permet à un service de naître déjà rempli, et à l'écran de ne jamais montrer de
    /// silhouette quand l'app sait quelque chose.
    func valeur<Valeur: Decodable>(_ cle: String, snapshot: Bool = false) -> Valeur? {
        valeur(cle, snapshot: snapshot, decoder: Self.decodeur)
    }

    func valeur<Valeur: Decodable>(
        _ cle: String,
        snapshot: Bool = false,
        decoder: @escaping (Data) throws -> Valeur
    ) -> Valeur? {
        connue(cle, compte: Self.compte(), snapshot: snapshot, decoder: decoder)
    }

    /// Périme toutes les entrées, en mémoire comme sur disque (un instantané relu est
    /// toujours revalidé) : relues à la prochaine demande, affichées d'ici là.
    func toutPerimer() {
        for cle in Set(entrees.keys).union(enVol.keys) { perimer(cle) }
    }

    /// Efface tout, mémoire et disque, et abandonne les relectures en vol — à la
    /// déconnexion et à la suppression du compte.
    func vider() {
        for lecture in enVol.values { lecture.tache.cancel() }
        enVol.removeAll()
        entrees.removeAll()
        generations.removeAll()
        SnapshotsDisque.toutEffacer()
    }

    // MARK: - Interne

    private func connue<Valeur: Decodable>(
        _ cle: String,
        compte: String,
        snapshot: Bool,
        decoder: (Data) throws -> Valeur
    ) -> Valeur? {
        let cleCompte = "\(compte)|\(cle)"
        if let entree = entrees[cleCompte] { return entree.valeur as? Valeur }
        guard snapshot, compte != Self.anonyme,
              let donnees = SnapshotsDisque.lire(cle: cle, compte: compte),
              let valeur = try? decoder(donnees) else { return nil }
        // Relu du disque : affiché tout de suite, mais **toujours** revalidé.
        entrees[cleCompte] = Entree(valeur: valeur, lueLe: .distantPast)
        return valeur
    }

    /// Une seule requête par clé à la fois.
    private func relire(_ cleCompte: String,
                        lire: @escaping () async throws -> Data) async throws -> Data {
        let generation = generations[cleCompte, default: 0]
        if let lecture = enVol[cleCompte] {
            if lecture.generation == generation { return try await lecture.tache.value }
            // Partie avant une invalidation : on la laisse finir, puis on relit.
            _ = try? await lecture.tache.value
            if enVol[cleCompte]?.tache == lecture.tache { enVol[cleCompte] = nil }
            return try await relire(cleCompte, lire: lire)
        }
        let tache = Task { try await lire() }
        enVol[cleCompte] = Lecture(tache: tache, generation: generation)
        defer { if enVol[cleCompte]?.tache == tache { enVol[cleCompte] = nil } }
        return try await tache.value
    }

    private func perimer(_ cleCompte: String) {
        entrees[cleCompte]?.lueLe = .distantPast
        generations[cleCompte, default: 0] += 1
    }

    private static let anonyme = "anonyme"

    /// Le décodeur unique de l'app (``JSONDecoder/api``), dates comprises.
    private static func decodeur<Valeur: Decodable>(_ donnees: Data) throws -> Valeur {
        try JSONDecoder.api.decode(Valeur.self, from: donnees)
    }

    /// L'identifiant du compte de la session **locale** — sans réseau. Le compte d'abord,
    /// sans quoi un changement de compte servirait les données du précédent.
    private static func compte() -> String {
        SupabaseManager.partage.idCompte?.uuidString.lowercased() ?? anonyme
    }
}

// MARK: - Le disque

/// Les instantanés sur disque : un fichier JSON par compte et par clé, dans le dossier
/// **Caches** de l'app (`Caches/Instantanes/<compte>/`) — iOS peut le purger, et rien n'y
/// est irremplaçable. **Seul propriétaire de ces fichiers.**
///
/// Ce qui y entre est une réponse du serveur à une lecture de **ce** compte : jamais un
/// jeton, jamais un secret (la session reste dans le Keychain), jamais la donnée d'un autre
/// compte — l'enveloppe porte le compte, et une enveloppe qui ne correspond pas est ignorée.
///
/// **Version de schéma** : une version inconnue ou un fichier illisible est ignoré sans
/// erreur, et l'écran retombe sur le réseau. Changer la forme d'une réponse que l'app ne
/// saurait plus décoder ? Incrémenter ``version``.
enum SnapshotsDisque {

    static let version = 1

    private struct Enveloppe: Codable {
        let version: Int
        let compte: String
        let cle: String
        let lueLe: Date
        /// La réponse brute du serveur.
        let donnees: Data
    }

    /// Les écritures partent dans l'ordre, hors du fil principal ; l'effacement passe par
    /// la même file, donc après toute écriture déjà demandée.
    private static let file = DispatchQueue(label: "com.bazzana.greedf1.instantanes", qos: .utility)

    private static var dossier: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Instantanes", isDirectory: true)
    }

    private static func fichier(_ cle: String, compte: String) -> URL? {
        let nom = String(cle.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        return dossier?
            .appendingPathComponent(compte, isDirectory: true)
            .appendingPathComponent(nom + ".json")
    }

    /// Lecture **synchrone** : quelques kilo-octets, lus une fois au lancement, et c'est ce
    /// qui permet le premier affichage sans attendre.
    static func lire(cle: String, compte: String) -> Data? {
        guard let url = fichier(cle, compte: compte),
              let brut = try? Data(contentsOf: url),
              let enveloppe = try? JSONDecoder().decode(Enveloppe.self, from: brut),
              enveloppe.version == version,
              enveloppe.compte == compte,
              enveloppe.cle == cle else { return nil }
        return enveloppe.donnees
    }

    static func ecrire(_ donnees: Data, cle: String, compte: String) {
        guard let url = fichier(cle, compte: compte) else { return }
        let enveloppe = Enveloppe(version: version, compte: compte, cle: cle, lueLe: .now, donnees: donnees)
        file.async {
            guard let brut = try? JSONEncoder().encode(enveloppe) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? brut.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Tous les comptes : à la déconnexion, rien ne doit rester.
    static func toutEffacer() {
        guard let dossier else { return }
        file.sync { try? FileManager.default.removeItem(at: dossier) }
    }
}
