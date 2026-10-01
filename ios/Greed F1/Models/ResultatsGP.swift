import Foundation

/// Les résultats d'un Grand Prix, tels que les sert `GET /grands-prix/{id}/resultats`
/// (`ResultatsServis`, `docs/swift-app.md` §3.6) — appelée **sans** `championnat_id`.
///
/// Seuls les champs que l'écran lit sont décodés : `grand_prix` redit ce que le calendrier
/// a déjà transmis, et `membres` vaut `nil` sans `championnat_id`.
///
/// > **Ni pole ni meilleur tour** : le backend ne les sert pas. Ils ne sont pas inventés.
struct ResultatsGP: Decodable, Equatable {
    /// **`false` tant que le job n'a pas récupéré la course** — l'écran dit alors
    /// « non disponibles », jamais un classement vide.
    let disponible: Bool
    let recupereLe: Date?
    let classement: [LigneResultat]
    /// `grand_prix.statut_resultats` vaut `provisoire` — ``StatutResultats``.
    let provisoire: Bool

    enum CodingKeys: String, CodingKey {
        case disponible, classement
        case recupereLe = "recupere_le"
        case grandPrix = "grand_prix"
    }

    private struct Resume: Decodable {
        let statutResultats: String?
        enum CodingKeys: String, CodingKey { case statutResultats = "statut_resultats" }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disponible = try c.decode(Bool.self, forKey: .disponible)
        recupereLe = try c.decodeIfPresent(Date.self, forKey: .recupereLe)
        classement = try c.decode([LigneResultat].self, forKey: .classement)
        let resume = try? c.decodeIfPresent(Resume.self, forKey: .grandPrix)
        provisoire = StatutResultats.estProvisoire(resume?.statutResultats)
    }
}

/// Une ligne du classement de la course (`LigneClassement` du backend).
struct LigneResultat: Decodable, Equatable, Identifiable {
    /// `nil` pour un pilote non classé — l'abandon précoce.
    let position: Int?
    let driverNumber: Int?
    /// Le `full_name` d'OpenF1 : « Max VERSTAPPEN ».
    let pilote: String
    /// Le libellé d'OpenF1 : « Red Bull Racing ».
    let equipe: String?
    /// Les points du **championnat du monde** (25, 18, 15…), jamais des points de pronostic.
    let pointsFia: Int
    /// Un pilote peut abandonner **et** rester classé : ces trois-là sont indépendants de
    /// `position`.
    let abandon: Bool
    let nonPartant: Bool
    let disqualifie: Bool

    var id: String { "\(driverNumber.map(String.init) ?? "–")-\(pilote)" }

    enum CodingKeys: String, CodingKey {
        case position, pilote, equipe, abandon, disqualifie
        case driverNumber = "driver_number"
        case pointsFia = "points_fia"
        case nonPartant = "non_partant"
    }

    init(from decoder: Decoder) throws {
        // Les défauts du modèle Pydantic : un backend plus ancien qui omettrait un champ
        // ne doit pas faire tomber tout le classement.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        driverNumber = try c.decodeIfPresent(Int.self, forKey: .driverNumber)
        pilote = try c.decode(String.self, forKey: .pilote)
        equipe = try c.decodeIfPresent(String.self, forKey: .equipe)
        pointsFia = try c.decodeIfPresent(Int.self, forKey: .pointsFia) ?? 0
        abandon = try c.decodeIfPresent(Bool.self, forKey: .abandon) ?? false
        nonPartant = try c.decodeIfPresent(Bool.self, forKey: .nonPartant) ?? false
        disqualifie = try c.decodeIfPresent(Bool.self, forKey: .disqualifie) ?? false
    }

    init(position: Int?, driverNumber: Int?, pilote: String, equipe: String?,
         pointsFia: Int, abandon: Bool = false, nonPartant: Bool = false,
         disqualifie: Bool = false) {
        self.position = position
        self.driverNumber = driverNumber
        self.pilote = pilote
        self.equipe = equipe
        self.pointsFia = pointsFia
        self.abandon = abandon
        self.nonPartant = nonPartant
        self.disqualifie = disqualifie
    }

    // MARK: - Lecture

    /// Le prénom — tout sauf le dernier mot.
    var prenom: String {
        mots.dropLast().joined(separator: " ")
    }

    /// Le nom de famille — le dernier mot, **ramené à l'initiale majuscule seulement s'il
    /// est entièrement en capitales** : « VERSTAPPEN » → « Verstappen », « Sainz Jr »
    /// intact. Transcription de `couperLeNom` (`ResultatsGp.jsx`).
    var nom: String {
        guard let brut = mots.last else { return "" }
        guard brut.rangeOfCharacter(from: .lowercaseLetters) == nil else { return brut }
        return brut.lowercased(with: Locale(identifier: "fr_FR"))
            .split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "-")
    }

    private var mots: [String] {
        pilote.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// « Disqualifié », « Non partant », « Abandon » — ou rien. **Un seul mot** : l'ordre
    /// est celui de la gravité, un disqualifié a d'abord été classé.
    var mention: String? {
        if disqualifie { return t("resultats.disqualifie") }
        if nonPartant { return t("resultats.nonPartant") }
        if abandon { return t("resultats.abandon") }
        return nil
    }

    /// Le slug de la livrée, `nil` pour une écurie inconnue.
    var ecurieSlug: String? { LivreeEcurie.duLibelle(equipe)?.slug }
}
