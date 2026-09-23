import Foundation

/// Mode de la voiture d'un membre.
///
/// Une valeur inconnue **retombe sur `perso`**, ce n'est pas une panne
/// (`docs/swift-app.md` §3.2) — même repli que le backend et la version web.
enum ModeLivree: String, Codable {
    case perso, ecurie

    init(from decoder: Decoder) throws {
        let valeur = try? decoder.singleValueContainer().decode(String.self)
        self = valeur.flatMap(ModeLivree.init(rawValue:)) ?? .perso
    }
}

/// Un profil tel que le sert `GET /profils/{id}` (`ProfilServi`, §3.2) — et tel que le
/// lit ``AuthViewModel`` en direct dans `public.profils` pour le compte connecté.
///
/// Les champs qui ont une **valeur par défaut côté backend** en ont une ici : un
/// backend déployé avant sa migration, ou une colonne absente de la sélection, fait
/// perdre un champ au lieu de faire échouer tout le décodage.
struct Profil: Codable, Identifiable, Equatable {
    let id: UUID
    let pseudo: String
    /// Coque de la voiture, `#RRGGBB`.
    let couleur1: String
    /// Ailerons, `#RRGGBB`.
    let couleur2: String
    /// 1 à 99. **`nil` = pas de numéro choisi**, jamais `0` : c'est alors le rang au
    /// classement qui s'affiche sur la voiture.
    let numero: Int?
    let livreeMode: ModeLivree
    /// Slug de livrée d'écurie. Un slug inconnu retombe sur `perso` à l'affichage.
    let livreeEcurie: String?
    /// Décide d'un **affichage**, jamais d'un droit — et ne se lit jamais depuis un
    /// cache ni depuis le jeton (§3.9).
    let isAdmin: Bool
    /// URL publique Storage. `nil` ⇒ les initiales du pseudo.
    let avatarUrl: URL?
    /// **`nil` veut dire « pas de choix », jamais « pas de couleur »** : l'encre se
    /// calcule alors contre l'aplat (§6.6).
    let couleurTexte: String?
    let creeLe: Date

    enum CodingKeys: String, CodingKey {
        case id, pseudo, couleur1, couleur2, numero
        case livreeMode = "livree_mode"
        case livreeEcurie = "livree_ecurie"
        case isAdmin = "is_admin"
        case avatarUrl = "avatar_url"
        case couleurTexte = "couleur_texte"
        case creeLe = "cree_le"
    }

    /// Les colonnes de `public.profils` que ce modèle lit — pour un `select` PostgREST.
    /// Nommées plutôt que `*` : une colonne ajoutée en base n'entre pas sans qu'on l'ait
    /// décidé.
    static let colonnes = CodingKeys.allCases.map(\.stringValue).joined(separator: ", ")

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        pseudo = try c.decode(String.self, forKey: .pseudo)
        couleur1 = try c.decodeIfPresent(String.self, forKey: .couleur1) ?? "#800111"
        couleur2 = try c.decodeIfPresent(String.self, forKey: .couleur2) ?? "#FFFFFF"
        numero = try c.decodeIfPresent(Int.self, forKey: .numero)
        livreeMode = try c.decodeIfPresent(ModeLivree.self, forKey: .livreeMode) ?? .perso
        livreeEcurie = try c.decodeIfPresent(String.self, forKey: .livreeEcurie)
        // Le défaut est le moins privilégié des deux : une réponse tronquée referme la
        // section d'administration, jamais l'inverse.
        isAdmin = try c.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        avatarUrl = URL.facultative(try c.decodeIfPresent(String.self, forKey: .avatarUrl))
        couleurTexte = try c.decodeIfPresent(String.self, forKey: .couleurTexte)
        creeLe = try c.decode(Date.self, forKey: .creeLe)
    }
}

extension Profil.CodingKeys: CaseIterable {}

extension URL {
    /// Une URL servie par l'API, où une chaîne vide ou mal formée vaut « pas d'image »
    /// plutôt qu'un échec de décodage de toute la réponse.
    static func facultative(_ texte: String?) -> URL? {
        guard let texte, !texte.isEmpty else { return nil }
        return URL(string: texte)
    }
}
