import Foundation
import Security

/// Le **jeton widget** dans le Keychain partagé `com.bazzana.greedf1.widget` — seul
/// propriétaire de l'élément, compilé par l'app et par le widget (`docs/decisions.md` §28).
///
/// L'app l'écrit (``SynchroWidgetClassement``) ; le widget « Classement » ne fait que le
/// lire. **Ce n'est jamais la session Supabase** : un jeton HS256 de 30 jours, en lecture
/// seule, que le backend n'accepte que sur `GET /widget/championnats/{id}/classement`.
/// Le widget ne touche donc jamais au jeton de rafraîchissement Supabase, à usage unique,
/// qu'un double rafraîchissement app / widget aurait consommé.
enum JetonWidget {

    struct Contenu: Codable, Equatable {
        let jeton: String
        let profilId: UUID
        let expireLe: Date

        enum CodingKeys: String, CodingKey {
            case jeton
            case profilId = "profil_id"
            case expireLe = "expire_le"
        }
    }

    /// Le suffixe du groupe déclaré dans les deux `.entitlements`. Le préfixe d'équipe est
    /// lu dans `Info.plist` (``SupabaseConfig/prefixeTrousseau``) : écrit en dur, il
    /// divergerait au premier changement d'équipe de signature.
    private static let suffixeGroupe = "com.bazzana.greedf1.widget"
    private static let service = "com.bazzana.greedf1.widget"
    private static let compte = "jeton"

    private static var groupe: String? {
        SupabaseConfig.prefixeTrousseau.map { $0 + suffixeGroupe }
    }

    private static var requeteDeBase: [String: Any] {
        var requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte
        ]
        if let groupe { requete[kSecAttrAccessGroup as String] = groupe }
        return requete
    }

    static func lire() -> Contenu? {
        var requete = requeteDeBase
        requete[kSecReturnData as String] = true
        requete[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultat: CFTypeRef?
        guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data
        else { return nil }
        return try? JSONDecoder.api.decode(Contenu.self, from: donnees)
    }

    /// Remplace le jeton. **Lisible après le premier déverrouillage** : le widget se
    /// rafraîchit écran verrouillé, la nuit d'un Grand Prix comprise.
    @discardableResult
    static func enregistrer(_ contenu: Contenu) -> Bool {
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        guard let donnees = try? encodeur.encode(contenu) else { return false }
        effacer()
        var requete = requeteDeBase
        requete[kSecValueData as String] = donnees
        requete[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(requete as CFDictionary, nil) == errSecSuccess
    }

    static func effacer() {
        SecItemDelete(requeteDeBase as CFDictionary)
    }
}
