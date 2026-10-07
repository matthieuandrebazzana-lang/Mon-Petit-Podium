import Foundation

/// Point d'entrée **unique** vers le backend FastAPI (Railway).
///
/// Il porte trois choses qu'aucun écran ne doit refaire : le jeton en `Bearer`, relu à
/// chaque appel (§2.4) ; le décodage JSON, dates comprises (``JSONDecoder/api``) ; et le
/// classement des échecs en ``ErreurAPI``. Un écran reçoit donc soit un modèle décodé,
/// soit une erreur dont le ``ErreurAPI/message`` est déjà affichable.
///
/// Les lectures que la RLS décrit ne passent **pas** par ici mais par ``SupabaseManager``
/// en direct (`docs/swift-app.md` §3.9) : elles marchent pendant que Railway dort.
final class APIClient {

    /// L'instance partagée.
    static let partage = APIClient()

    enum Methode: String {
        case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE"
    }

    private let base = SupabaseConfig.apiBaseURL
    private let session: URLSession
    private let encodeur = JSONEncoder()

    /// Attentes avant chacun des nouveaux essais d'une lecture tombée sur Railway endormi.
    /// Un réveil prend quelques secondes : trois tentatives en ~5 s couvrent le cas
    /// courant sans faire patienter indéfiniment un écran vraiment hors ligne.
    private let attentesReveil: [Duration] = [.milliseconds(1500), .seconds(3)]

    private init() {
        let configuration = URLSessionConfiguration.default
        // Assez pour un réveil de Railway, pas de quoi figer un écran une minute entière
        // (le défaut) quand le réseau est vraiment coupé.
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: - Réveil

    /// Ping de réveil `GET /health`, **sans attendre la réponse** (§3.1). Appelé au
    /// lancement : le temps que l'utilisateur atteigne un écran servi par Railway, le
    /// service est levé. Son échec n'a aucune conséquence et ne se signale pas.
    func reveiller() {
        let requete = URLRequest(url: base.appendingPathComponent("health"),
                                 timeoutInterval: 60)
        Task.detached(priority: .utility) { [session] in
            _ = try? await session.data(for: requete)
        }
    }

    // MARK: - Requêtes

    /// Appelle une route et décode sa réponse.
    ///
    /// - Parameter corps: encodé tel quel — les modèles de corps portent leurs propres
    ///   `CodingKeys` en `snake_case`, comme les modèles de réponse.
    /// - Throws: une ``ErreurAPI`` — ou `CancellationError` quand la tâche appelante est
    ///   annulée (écran quitté) : ce n'est pas un échec, et rien ne doit s'afficher.
    func requete<Reponse: Decodable>(
        _ chemin: String,
        methode: Methode = .get,
        corps: (any Encodable)? = nil,
        parametres: [URLQueryItem] = []
    ) async throws -> Reponse {
        let donnees = try await executer(chemin, methode: methode, corps: corps,
                                         parametres: parametres)
        do {
            return try JSONDecoder.api.decode(Reponse.self, from: donnees)
        } catch {
            // Le serveur a dit « succès » dans une forme qu'on ne sait pas lire : ancienne
            // version déployée, ou modèle Swift en retard sur le backend.
            throw ErreurAPI.serveur(statut: nil, message: nil)
        }
    }

    /// Appelle une route dont la réponse ne sert à rien (`DELETE …/quitter`).
    func envoyer(
        _ chemin: String,
        methode: Methode,
        corps: (any Encodable)? = nil
    ) async throws {
        _ = try await executer(chemin, methode: methode, corps: corps, parametres: [])
    }

    // MARK: - Transport

    private func executer(
        _ chemin: String,
        methode: Methode,
        corps: (any Encodable)?,
        parametres: [URLQueryItem]
    ) async throws -> Data {
        // Seules les lectures sont rejouées d'office : rejouer une écriture dont on
        // ignore si la première a abouti n'est pas une décision de la couche réseau.
        let attentes = methode == .get ? attentesReveil : []
        var tentative = 0
        while true {
            do {
                let donnees = try await une(chemin, methode: methode, corps: corps,
                                            parametres: parametres)
                // Une écriture réussie périme tout le cache : ce qu'elle change ne se
                // limite pas à sa route (``CacheService``).
                if methode != .get { await CacheService.partage.toutPerimer() }
                return donnees
            } catch ErreurAPI.reseau where tentative < attentes.count {
                try? await Task.sleep(for: attentes[tentative])
                tentative += 1
            }
        }
    }

    private func une(
        _ chemin: String,
        methode: Methode,
        corps: (any Encodable)?,
        parametres: [URLQueryItem]
    ) async throws -> Data {
        var url = base.appendingPathComponent(chemin)
        if !parametres.isEmpty { url.append(queryItems: parametres) }

        var requete = URLRequest(url: url)
        requete.httpMethod = methode.rawValue
        requete.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jeton = await SupabaseManager.partage.jetonAcces() {
            requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        }
        if let corps {
            requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requete.httpBody = try? encodeur.encode(corps)
        }

        let donnees: Data
        let reponse: URLResponse
        do {
            (donnees, reponse) = try await session.data(for: requete)
        } catch let erreur as URLError where erreur.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ErreurAPI.reseau
        }

        guard let http = reponse as? HTTPURLResponse else {
            throw ErreurAPI.serveur(statut: nil, message: nil)
        }
        guard !(200..<300).contains(http.statusCode) else { return donnees }

        let erreur = ErreurAPI.depuis(statut: http.statusCode, corps: donnees)
        if erreur == .session {
            // `supabase-swift` rafraîchit le jeton tout seul : un `401` malgré cela veut
            // dire que la session est réellement perdue (§7.3). La purger publie
            // `signedOut`, sur lequel ``AuthViewModel`` ramène à la connexion.
            // **Un `503` ne passe jamais par ici** : une panne ne déconnecte personne.
            try? await SupabaseManager.partage.client.auth.signOut()
        }
        throw erreur
    }
}
