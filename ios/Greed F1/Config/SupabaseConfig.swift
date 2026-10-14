import Foundation

/// Constantes de connexion, lues depuis `Info.plist` — qui les tient lui-même de
/// `Config.xcconfig`, **non versionné**. Rien n'est écrit en dur ici.
///
/// Les valeurs (URL Supabase, clé anonyme, URL Railway) sont publiques par conception :
/// c'est la RLS qui protège les données, pas l'obscurité de la clé. La clé
/// `service_role` ne quitte jamais Railway et n'a rien à faire dans ce bundle.
///
/// Source unique : `docs/swift-app.md` §1.
enum SupabaseConfig {

    /// Une valeur de configuration manquante est une erreur de *build*, pas d'exécution :
    /// l'app s'arrête tout de suite plutôt que d'échouer plus tard sur un appel réseau
    /// incompréhensible.
    enum Erreur: String {
        case cleAbsente = """
            Clé absente d'Info.plist. Copier Config.xcconfig.example en Config.xcconfig \
            et renseigner les valeurs (docs/swift-app.md §1).
            """
        case urlInvalide = "Valeur présente dans Info.plist mais inexploitable comme URL."
    }

    /// Projet Supabase : base PostgreSQL, authentification et Storage.
    static let supabaseURL: URL = url(pour: "SUPABASE_URL")

    /// Clé **anonyme** Supabase. Jamais la clé `service_role`.
    static let supabaseAnonKey: String = chaine(pour: "SUPABASE_ANON_KEY")

    /// Backend métier FastAPI, sur Railway.
    static let apiBaseURL: URL = url(pour: "API_BASE_URL")

    /// Le préfixe d'équipe des groupes Keychain (`AppIdentifierPrefix`, posé par le build,
    /// avec son point final). `nil` hors d'un build signé : on laisse alors iOS choisir.
    static let prefixeTrousseau: String? = {
        guard let valeur = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !valeur.isEmpty, !valeur.hasPrefix("$(") else { return nil }
        return valeur
    }()

    // MARK: - Lecture du bundle

    private static func chaine(pour cle: String) -> String {
        guard let valeur = Bundle.main.object(forInfoDictionaryKey: cle) as? String,
              !valeur.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            fatalError("\(cle) — \(Erreur.cleAbsente.rawValue)")
        }
        return valeur
    }

    private static func url(pour cle: String) -> URL {
        let valeur = chaine(pour: cle)
        guard let url = URL(string: valeur), url.scheme != nil, url.host != nil else {
            fatalError("\(cle) = « \(valeur) » — \(Erreur.urlInvalide.rawValue)")
        }
        return url
    }
}
