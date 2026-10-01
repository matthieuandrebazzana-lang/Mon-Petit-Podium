import Foundation

// MARK: - Un Grand Prix vu par un championnat — `GET /championnats/{id}/calendrier`

/// Ce que ``ResultatsParGPView`` lit de `GrandPrixCalendrier` : de quoi nommer une option
/// du sélecteur et savoir si la course est jugée. Le reste de la réponse (mini-classement,
/// mes points) n'est pas décodé — un champ lu mais jamais montré est un champ qui peut
/// casser le décodage pour rien.
struct GrandPrixDuChampionnat: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let nom: String
    let dateCourse: Date?
    /// Lu dans `resultats_gp`, **jamais déduit du statut** — qui peut mentir dans les deux
    /// sens (`GrandPrixCalendrier`, backend).
    let resultatsDisponibles: Bool
    /// `provisoire` jusqu'au calcul définitif de J+1 — ``StatutResultats``. Servi par la
    /// route depuis le backend `0.78.0`, `nil` avant.
    let statutResultats: String?

    enum CodingKeys: String, CodingKey {
        case nom
        case id = "gp_id"
        case dateCourse = "date_course"
        case resultatsDisponibles = "resultats_disponibles"
        case statutResultats = "statut_resultats"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        dateCourse = try? c.decodeIfPresent(Date.self, forKey: .dateCourse)
        resultatsDisponibles = try c.decodeIfPresent(Bool.self, forKey: .resultatsDisponibles) ?? false
        statutResultats = try? c.decodeIfPresent(String.self, forKey: .statutResultats)
    }

    var provisoire: Bool { StatutResultats.estProvisoire(statutResultats) }

    /// Le libellé d'une pastille du sélecteur — `libelleCourtGp` du web : **le préfixe
    /// « GP » saute, et lui seul**. Identique sur toutes les options, il ne distingue rien
    /// et vole sa largeur au seul mot qui distingue.
    var libelleCourt: String {
        let court = nom.replacingOccurrences(of: #"^GP\s+"#, with: "",
                                             options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return court.isEmpty ? t("commun.grandPrix") : court
    }
}

// MARK: - Les paris de chacun — `GET /grands-prix/{gp}/pronostics/championnat/{id}`

/// Un membre du championnat et ses pronostics sur **un** Grand Prix (`MembrePronostics`,
/// backend). Les membres sans pronostic sont servis avec une liste vide : l'écran doit
/// montrer qui manque à l'appel, pas seulement qui a joué.
struct MembrePronostics: Decodable, Identifiable, Equatable {
    let profilId: UUID
    let pseudo: String
    let couleur1: String
    let couleur2: String
    let couleurTexte: String?
    let numero: Int?
    let livreeMode: ModeLivree
    let livreeEcurie: String?
    let avatarUrl: URL?
    /// Ce qu'il a marqué sur ce Grand Prix. **`nil` tant que rien n'est jugé**, jamais `0`,
    /// qui dirait « tout raté » (`CLAUDE.md` §3.1).
    let totalPoints: Int?
    let pronostics: [PronosticMembre]

    var id: UUID { profilId }

    enum CodingKeys: String, CodingKey {
        case pseudo, couleur1, couleur2, numero, pronostics
        case profilId = "profil_id"
        case couleurTexte = "couleur_texte"
        case livreeMode = "livree_mode"
        case livreeEcurie = "livree_ecurie"
        case avatarUrl = "avatar_url"
        case totalPoints = "total_points"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profilId = try c.decode(UUID.self, forKey: .profilId)
        pseudo = try c.decode(String.self, forKey: .pseudo)
        // Valeurs par défaut du modèle Pydantic : un backend déployé avant sa migration
        // perd un champ, il ne fait pas tomber la liste (`CLAUDE.md` §3.3).
        couleur1 = try c.decodeIfPresent(String.self, forKey: .couleur1) ?? "#800111"
        couleur2 = try c.decodeIfPresent(String.self, forKey: .couleur2) ?? "#FFFFFF"
        couleurTexte = try c.decodeIfPresent(String.self, forKey: .couleurTexte)
        numero = try c.decodeIfPresent(Int.self, forKey: .numero)
        livreeMode = (try? c.decodeIfPresent(ModeLivree.self, forKey: .livreeMode)) ?? .perso
        livreeEcurie = try c.decodeIfPresent(String.self, forKey: .livreeEcurie)
        avatarUrl = URL.facultative(try c.decodeIfPresent(String.self, forKey: .avatarUrl))
        totalPoints = try c.decodeIfPresent(Int.self, forKey: .totalPoints)
        pronostics = try c.decodeIfPresent([PronosticMembre].self, forKey: .pronostics) ?? []
    }

    var aJoue: Bool { !pronostics.isEmpty }

    /// Les paris **tels qu'ils s'affichent** : le podium en deux lignes, une par pilote
    /// (``PronosticMembre/paris``). Un joueur qui a tout joué en compte six.
    var paris: [PronosticMembre] { pronostics.flatMap(\.paris) }

    /// Ce que la grille **peut** rapporter, tant que rien n'est jugé — les deux cotes du
    /// podium comprises (`metier.md` §2).
    var potentiel: Int { paris.reduce(0) { $0 + ($1.points ?? 0) } }

    /// La teinte de l'initiale : l'UUID en minuscules, la règle de ``Membre/cleTeinte``.
    var cleTeinte: String { profilId.uuidString.lowercased() }

    /// Ce que porte sa voiture — **celle du profil** quand c'est le compte connecté, pour la
    /// même raison que ``Membre/avecVoiture(de:)`` : la ligne servie peut précéder une
    /// modification faite dans l'onglet Profil.
    func livree(profil: Profil?) -> Livree {
        if let profil, profil.id == profilId {
            return Livree(mode: profil.livreeMode == .ecurie ? .ecurie : .perso,
                          ecurie: profil.livreeEcurie, coque: profil.couleur1,
                          ailerons: profil.couleur2, couleurTexte: profil.couleurTexte)
        }
        return Livree(mode: livreeMode == .ecurie ? .ecurie : .perso, ecurie: livreeEcurie,
                      coque: couleur1, ailerons: couleur2, couleurTexte: couleurTexte)
    }

    /// Les membres, du meilleur au moins bon **sur ce Grand Prix-là** —
    /// `classerParPointsDuGp` du web. **`nil` passe derrière zéro** : pas encore jugé
    /// n'est ni gagné ni raté. À égalité, l'ordre du serveur (d'inscription) est conservé.
    static func classer(_ lignes: [MembrePronostics]) -> [MembrePronostics] {
        lignes.enumerated()
            .sorted { a, b in
                let sa = a.element.totalPoints ?? -1
                let sb = b.element.totalPoints ?? -1
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)
    }
}

/// Un pronostic servi (`PronosticServi`, backend) — ou, pour un podium, l'une de ses deux
/// lignes (``paris``).
struct PronosticMembre: Decodable, Identifiable, Equatable {
    let pronosticId: UUID
    /// `0` pour un pronostic entier, `1` ou `2` pour le pilote d'un podium détaillé.
    private(set) var rang = 0
    let type: String
    private(set) var pilote: String?
    /// Le libellé du marché tel que le bookmaker l'écrit.
    let libelle: String?
    /// Ce que le pronostic **peut** rapporter — déjà un nombre de points, jamais une cote.
    private(set) var points: Int?
    /// Ce qu'il a rapporté. **`nil` = pas encore jugé, `0` = raté** — jamais confondus.
    private(set) var pointsGagnes: Int?
    /// `en_attente`, `non_evaluable`, `gagne` ou `perdu` (migration 24, servi par la 25).
    /// Seul moyen de distinguer, quand `pointsGagnes` est nul, l'attente du non évaluable.
    private(set) var statutEvaluation: String?
    private(set) var podium: Podium?

    struct Podium: Decodable, Equatable {
        let nom1: String?
        let nom2: String?
        /// La cote du second pilote ; celle du premier est ``PronosticMembre/points``.
        let points2: Int?
        /// Ce que chaque pilote a rapporté, **jugé par le backend** (migration 27) —
        /// jamais redéduit du total ici. `nil` tant que rien n'est jugé.
        let pointsGagnes1: Int?
        let pointsGagnes2: Int?

        enum CodingKeys: String, CodingKey {
            case nom1 = "nom_1"
            case nom2 = "nom_2"
            case points2 = "points_2"
            case pointsGagnes1 = "points_gagnes_1"
            case pointsGagnes2 = "points_gagnes_2"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, pilote, libelle, points, podium
        case pronosticId = "id"
        case pointsGagnes = "points_gagnes"
        case statutEvaluation = "statut_evaluation"
    }

    /// Unique **par ligne affichée** : les deux pilotes d'un podium partagent le même
    /// pronostic.
    var id: String { rang == 0 ? pronosticId.uuidString : "\(pronosticId.uuidString)-\(rang)" }

    /// Le pronostic en lignes d'affichage — **la seule découpe du podium de l'app**.
    ///
    /// Chaque pilote porte son nom, sa cote et **son** verdict, lu dans ce que le backend
    /// a écrit pour lui. Tant que le pronostic n'est pas jugé, les deux lignes reprennent
    /// son statut (attente ou non évaluable). Jugé mais sans détail — base non migrée, ou
    /// cotes égales non réparties —, le podium reste **une seule ligne** portant son total :
    /// le verdict affiché suit toujours les points écrits, jamais un `en_attente` qui les
    /// contredit, et un verdict par pilote ne se devine pas depuis le total.
    var paris: [PronosticMembre] {
        guard let podium, rang == 0 else { return [self] }
        if pointsGagnes != nil, podium.pointsGagnes1 == nil || podium.pointsGagnes2 == nil {
            return [self]
        }
        let jambes: [(nom: String?, points: Int?, gagnes: Int?)] = [
            (podium.nom1 ?? pilote, points, podium.pointsGagnes1),
            (podium.nom2, podium.points2, podium.pointsGagnes2),
        ]
        return jambes.enumerated().map { index, jambe in
            var ligne = self
            ligne.rang = index + 1
            ligne.pilote = jambe.nom
            ligne.points = jambe.points
            ligne.podium = nil
            if pointsGagnes != nil {
                ligne.pointsGagnes = jambe.gagnes
                ligne.statutEvaluation = jambe.gagnes.map { $0 > 0 ? "gagne" : "perdu" }
            }
            return ligne
        }
    }

    var nonEvaluable: Bool {
        pointsGagnes == nil && StatutResultats.estNonEvaluable(statutEvaluation)
    }

    var marche: String { libelle ?? type.capitalized }

    /// La sélection — `choixDuPronostic` du web : les deux noms du podium, sinon le pilote.
    var choix: String {
        if let podium {
            let deux = [podium.nom1, podium.nom2].compactMap { $0 }
            if !deux.isEmpty { return deux.joined(separator: " + ") }
        }
        return pilote ?? t("pronostic.coteRetiree")
    }
}
