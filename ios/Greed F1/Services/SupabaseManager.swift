import Foundation
import Supabase

/// Point d'entrée **unique** de l'app vers Supabase. Railway, lui, passe par ``APIClient``,
/// qui vient chercher le jeton ici.
///
/// Le client est construit une seule fois : `supabase-swift` persiste la session dans le
/// Keychain et rafraîchit le jeton tout seul, mais seulement tant qu'un même client vit.
/// En instancier un second ferait travailler deux rafraîchisseurs sur le même Keychain.
///
/// Le jeton JWT se relit à **chaque** appel via ``jetonAcces()`` — jamais mémorisé :
/// un jeton capturé une fois pour toutes serait périmé au réveil de l'app
/// (`docs/swift-app.md` §2.4).
final class SupabaseManager {

    /// L'instance partagée. Toute requête Supabase part d'ici.
    static let partage = SupabaseManager()

    /// Le client Supabase : base, authentification, Storage.
    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.supabaseURL,
            supabaseKey: SupabaseConfig.supabaseAnonKey
        )
    }

    /// Jeton d'accès de la session courante, relu à chaque appel.
    /// `nil` quand personne n'est connecté — ce n'est pas une erreur.
    func jetonAcces() async -> String? {
        try? await client.auth.session.accessToken
    }
}
