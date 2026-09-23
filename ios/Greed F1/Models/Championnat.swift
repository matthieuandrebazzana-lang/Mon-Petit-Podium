import Foundation

/// Un championnat tel que le servent `GET /championnats/moi`, `POST /championnats`,
/// `POST /championnats/rejoindre` et `PATCH /championnats/{id}` (§3.3).
///
/// **L'échec d'une lecture secondaire n'emporte jamais la liste** : `prochainGp` et
/// `position` sont facultatifs en toute circonstance, et absents des réponses de
/// création et d'adhésion.
struct Championnat: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let nom: String
    /// 6 caractères alphanumériques majuscules, sans séparateur (`F1X7K2`).
    let codeInvitation: String
    /// **Nullable** : le championnat survit à la suppression du compte de son créateur.
    let creePar: UUID?
    let creeLe: Date
    let nombreMembres: Int
    /// Calculé par le serveur depuis le jeton.
    let estCreateur: Bool
    /// `nil` ⇒ aucune photo, et **rien** ne s'affiche à sa place.
    let photoUrl: URL?
    /// Le même pour tous les championnats. `nil` si plus aucun GP à venir, ou si sa
    /// lecture a échoué côté serveur.
    let prochainGp: ProchainGP?
    /// `nil` si le classement n'a pas pu être lu, ou au-delà du 12ᵉ championnat.
    let position: PositionMembre?

    enum CodingKeys: String, CodingKey {
        case id, nom, position
        case codeInvitation = "code_invitation"
        case creePar = "cree_par"
        case creeLe = "cree_le"
        case nombreMembres = "nombre_membres"
        case estCreateur = "est_createur"
        case photoUrl = "photo_url"
        case prochainGp = "prochain_gp"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        codeInvitation = try c.decode(String.self, forKey: .codeInvitation)
        creePar = try c.decodeIfPresent(UUID.self, forKey: .creePar)
        creeLe = try c.decode(Date.self, forKey: .creeLe)
        nombreMembres = try c.decode(Int.self, forKey: .nombreMembres)
        estCreateur = try c.decode(Bool.self, forKey: .estCreateur)
        photoUrl = URL.facultative(try c.decodeIfPresent(String.self, forKey: .photoUrl))
        // `try?` et non `try` : un sous-objet mal formé fait perdre son GP ou son rang à
        // une carte, jamais la liste entière.
        prochainGp = (try? c.decodeIfPresent(ProchainGP.self, forKey: .prochainGp)) ?? nil
        position = (try? c.decodeIfPresent(PositionMembre.self, forKey: .position)) ?? nil
    }
}

/// Le Grand Prix à venir annoncé sur une carte de championnat.
struct ProchainGP: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let nom: String
    /// **`nil` n'est PAS une date passée** : l'horaire n'est pas encore annoncé, le GP
    /// reste ouvert et se trie en fin de liste (§7.4).
    let dateCourse: Date?
    /// `a_venir`, `cotes_figees`… — gardé brut tant qu'aucun écran ne l'interprète.
    let statut: String

    enum CodingKeys: String, CodingKey {
        case id, nom, statut
        case dateCourse = "date_course"
    }
}

/// Où en est l'appelant dans un championnat — de quoi remplir la jauge de sa carte.
struct PositionMembre: Codable, Equatable, Hashable {
    let monRang: Int
    let mesPoints: Int
    /// Le **plus haut total** du championnat, pas celui du premier de la liste.
    let pointsLeader: Int

    enum CodingKeys: String, CodingKey {
        case monRang = "mon_rang"
        case mesPoints = "mes_points"
        case pointsLeader = "points_leader"
    }
}
