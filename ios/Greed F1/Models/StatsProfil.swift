import Foundation

/// Les statistiques d'un membre sur la saison, servies par `GET /profils/{id}/stats`
/// (`StatsProfil`, `docs/swift-app.md` §3.2).
///
/// **Tous des entiers, jamais une cote** (`CLAUDE.md` §3.1) : `coteMoyTentee` s'affiche
/// « 31 », nulle part « ×3,1 ».
///
/// Chaque champ a une valeur par défaut : un backend en retard d'un champ fait perdre ce
/// champ, pas toute la grille.
struct StatsProfil: Decodable, Equatable {
    let parisGagnesPct: Int
    let ptsMoyenGp: Int
    let meilleurCoup: Int
    let coteMoyTentee: Int
    /// Les trois compteurs suivants ne s'affichent pas tels quels : ils disent **si la
    /// saison a commencé** pour ce membre.
    let pronosticsNotes: Int
    let gpJoues: Int
    let totalPoints: Int
    let saison: Int

    enum CodingKeys: String, CodingKey {
        case saison
        case parisGagnesPct = "paris_gagnes_pct"
        case ptsMoyenGp = "pts_moyen_gp"
        case meilleurCoup = "meilleur_coup"
        case coteMoyTentee = "cote_moy_tentee"
        case pronosticsNotes = "pronostics_notes"
        case gpJoues = "gp_joues"
        case totalPoints = "total_points"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parisGagnesPct = try c.decodeIfPresent(Int.self, forKey: .parisGagnesPct) ?? 0
        ptsMoyenGp = try c.decodeIfPresent(Int.self, forKey: .ptsMoyenGp) ?? 0
        meilleurCoup = try c.decodeIfPresent(Int.self, forKey: .meilleurCoup) ?? 0
        coteMoyTentee = try c.decodeIfPresent(Int.self, forKey: .coteMoyTentee) ?? 0
        pronosticsNotes = try c.decodeIfPresent(Int.self, forKey: .pronosticsNotes) ?? 0
        gpJoues = try c.decodeIfPresent(Int.self, forKey: .gpJoues) ?? 0
        totalPoints = try c.decodeIfPresent(Int.self, forKey: .totalPoints) ?? 0
        saison = try c.decodeIfPresent(Int.self, forKey: .saison) ?? 2026
    }
}

extension StatsProfil {
    /// Les quatre tuiles, dans l'ordre des deux profils — **seul endroit qui les met en
    /// forme**, pendant de `GrilleStats.jsx`.
    ///
    /// Avant le premier pronostic jugé, trois tuiles sur quatre disent « – » et non « 0 » :
    /// « 0 % de paris gagnés » se lirait comme un mauvais bilan alors qu'il n'y a pas encore
    /// de bilan. La quatrième existe dès le premier pronostic saisi, course courue ou non.
    var tuiles: [StatistiqueProfil] {
        let juge = pronosticsNotes > 0
        return [
            StatistiqueProfil(valeur: juge ? "\(parisGagnesPct)%" : StatistiqueProfil.absente,
                              libelle: "Paris gagnés"),
            StatistiqueProfil(valeur: juge ? String(ptsMoyenGp) : StatistiqueProfil.absente,
                              libelle: "Pts moy. / GP"),
            StatistiqueProfil(valeur: juge ? String(meilleurCoup) : StatistiqueProfil.absente,
                              libelle: "Meilleur coup"),
            StatistiqueProfil(valeur: coteMoyTentee > 0 ? String(coteMoyTentee) : StatistiqueProfil.absente,
                              libelle: "Cote moy. tentée")
        ]
    }
}
