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

extension ProchainGP {

    /// La clé des assets `flag-<slug>` / `trace-<slug>` et de ``TeintesDrapeaux``, tirée
    /// du nom tel qu'il est en base. **Transcription de `slugCircuit`**
    /// (`frontend/src/composants/TracesCircuits.jsx`) : minuscules, accents retirés,
    /// préfixe « GP » ôté en tête, le reste en tirets — puis les alias, parce qu'Unibet
    /// écrit « GP Pays Bas » une semaine et « GP Pays-Bas » la suivante. Un slug inconnu
    /// est rendu tel quel : c'est à l'écran de constater qu'aucun asset ne lui répond.
    var slug: String {
        var texte = nom.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        texte = texte.replacingOccurrences(of: #"^\s*(grand\s+prix|gp)\b"#, with: "",
                                           options: .regularExpression)
        texte = texte.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        texte = texte.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if TeintesDrapeaux.table[texte] != nil { return texte }
        for (motif, cle) in Self.alias
        where texte.range(of: motif, options: .regularExpression) != nil {
            return cle
        }
        return texte
    }

    /// Les alias de `ALIAS`, dans le même ordre — le premier qui répond l'emporte.
    private static let alias: [(String, String)] = [
        ("zandvoort|hollande|neerland", "pays-bas"),
        ("monza", "italie"),
        ("madrid|madring", "espagne"),
        ("bakou|baku", "azerbaidjan"),
        ("sepang|malaisi|malaysi|kuala.?lumpur", "malaisie"),
        ("singapore|marina.?bay", "singapour"),
        (#"austin|texas|amerique|\busa\b|cota"#, "etats-unis"),
        ("mexico", "mexique"),
        ("sao.?paulo|interlagos|bresi", "bresil"),
        ("vegas", "las-vegas"),
        ("lusail|losail|doha", "qatar"),
        ("abou.?dab|abu.?dhab|yas.?marina|emirats", "abu-dhabi")
    ]

    /// **Les cotes sont arrêtées et les pronostics ouverts** — `cotesArretees` de
    /// `lib/calendrier.js` (`docs/metier.md`) : statut `cotes_figees` **et** départ pas
    /// encore passé. **Un départ inconnu laisse ouvert** : aucune fermeture à opposer.
    func pronosticsOuverts(le maintenant: Date = .now) -> Bool {
        guard statut == "cotes_figees" else { return false }
        guard let dateCourse else { return true }
        return dateCourse > maintenant
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
