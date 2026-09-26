import Foundation

/// Ce qu'un membre a joué sur la saison, Grand Prix par Grand Prix — la réponse attendue
/// de `GET /membres/{profil_id}/historique`.
///
/// > **La route n'existe pas encore** (absente de `docs/architecture.md`) : l'écran tourne
/// > sur ``apercu`` jusqu'à la passe réseau. Chaque champ a une valeur par défaut, pour
/// > qu'un backend en retard d'un champ fasse perdre ce champ, pas toute la réponse.
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1).
struct HistoriqueSaison: Decodable, Equatable {
    let saison: Int
    /// `nil` tant qu'aucun pronostic n'est jugé — « pas encore jugé » n'est pas « zéro ».
    let totalPoints: Int?
    let pronosticsReussis: Int
    /// Rang au classement ; `nil` hors de tout championnat.
    let rang: Int?
    let grandsPrix: [GrandPrixJoue]

    enum CodingKeys: String, CodingKey {
        case saison, rang
        case totalPoints = "total_points"
        case pronosticsReussis = "pronostics_reussis"
        case grandsPrix = "grands_prix"
    }

    init(saison: Int, totalPoints: Int?, pronosticsReussis: Int, rang: Int?,
         grandsPrix: [GrandPrixJoue]) {
        self.saison = saison
        self.totalPoints = totalPoints
        self.pronosticsReussis = pronosticsReussis
        self.rang = rang
        self.grandsPrix = grandsPrix
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        saison = try c.decodeIfPresent(Int.self, forKey: .saison) ?? 2026
        totalPoints = try c.decodeIfPresent(Int.self, forKey: .totalPoints)
        pronosticsReussis = try c.decodeIfPresent(Int.self, forKey: .pronosticsReussis) ?? 0
        rang = try c.decodeIfPresent(Int.self, forKey: .rang)
        grandsPrix = try c.decodeIfPresent([GrandPrixJoue].self, forKey: .grandsPrix) ?? []
    }
}

/// Un Grand Prix joué : ses pronostics et le podium réel.
///
/// **Le nom et la date ne viennent pas de la réponse** : ils sont lus dans
/// ``GrandPrixSaison/saison2026`` par le `slug`, la même liste que le calendrier — un GP
/// doit s'écrire pareil sur les deux écrans.
struct GrandPrixJoue: Decodable, Equatable, Identifiable {
    let slug: String
    let pronostics: [PronosticMembre]
    /// Les trois premiers, dans l'ordre. Vide tant que les résultats ne sont pas lus.
    let podium: [PiloteClasse]

    var id: String { slug }

    /// `nil` tant qu'aucun pronostic n'est jugé.
    var pointsGagnes: Int? {
        let juges = pronostics.compactMap(\.pointsGagnes)
        return juges.isEmpty ? nil : juges.reduce(0, +)
    }

    var reussis: Int { pronostics.filter { ($0.pointsGagnes ?? 0) > 0 }.count }

    /// L'entrée du calendrier statique — nom, date, drapeau.
    var fiche: GrandPrixSaison? { GrandPrixSaison.saison2026.first { $0.slug == slug } }

    enum CodingKeys: String, CodingKey { case slug, pronostics, podium }

    init(slug: String, pronostics: [PronosticMembre], podium: [PiloteClasse]) {
        self.slug = slug
        self.pronostics = pronostics
        self.podium = podium
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        pronostics = try c.decodeIfPresent([PronosticMembre].self, forKey: .pronostics) ?? []
        podium = try c.decodeIfPresent([PiloteClasse].self, forKey: .podium) ?? []
    }
}

/// Un pilote du podium réel.
struct PiloteClasse: Decodable, Equatable {
    let prenom: String
    let nom: String
    let ecurie: String
}

// MARK: - Aperçu

extension HistoriqueSaison {

    /// **Données inventées**, cohérentes entre elles — le total est la somme des points
    /// gagnés, les réussis le compte des pronostics gagnants. Remplacées à la passe réseau.
    static let apercu: HistoriqueSaison = {
        func prono(_ type: String, _ libelle: String, pilote: String,
                   points: Int, gagnes: Int) -> PronosticMembre {
            PronosticMembre(id: UUID(), type: type, pilote: pilote, libelle: libelle,
                            points: points, pointsGagnes: gagnes, podium: nil)
        }
        // **Deux obligatoires et trois bonus par GP** (`docs/metier.md` §2) : le vainqueur,
        // le podium — deux paris jugés chacun pour son compte, donc deux rangées —, puis
        // les trois bonus. Six rangées en tout.
        //
        // **Les podiums sont les résultats réels** (`GET /grands-prix/{id}/resultats`), et
        // chaque verdict est jugé contre le classement réel : un bonus « Top 6 » ou
        // « Top 10 » se vérifie sur la course. Seuls les choix et les points sont inventés.
        let gps = [
            // Norris · Antonelli · Russell — puis Hamilton, Leclerc, Piastri ; Alonso 9e.
            GrandPrixJoue(slug: "pays-bas", pronostics: [
                prono("vainqueur", "Vainqueur", pilote: "O.Piastri", points: 31, gagnes: 0),
                prono("podium", "Podium", pilote: "L.Norris", points: 12, gagnes: 12),
                prono("podium", "Podium", pilote: "M.Verstappen", points: 10, gagnes: 0),
                prono("bonus", "Top 6", pilote: "C.Leclerc", points: 18, gagnes: 18),
                prono("bonus", "Top 10", pilote: "F.Alonso", points: 25, gagnes: 25),
                prono("bonus", "Top 6", pilote: "M.Verstappen", points: 14, gagnes: 0)
            ], podium: [
                PiloteClasse(prenom: "Lando", nom: "Norris", ecurie: "McLaren"),
                PiloteClasse(prenom: "Kimi", nom: "Antonelli", ecurie: "Mercedes"),
                PiloteClasse(prenom: "George", nom: "Russell", ecurie: "Mercedes")
            ]),
            // Antonelli · Russell · Verstappen — puis Norris, Piastri, Hamilton ; Gasly 7e.
            GrandPrixJoue(slug: "italie", pronostics: [
                prono("vainqueur", "Vainqueur", pilote: "C.Leclerc", points: 34, gagnes: 0),
                prono("podium", "Podium", pilote: "G.Russell", points: 20, gagnes: 20),
                prono("podium", "Podium", pilote: "L.Norris", points: 16, gagnes: 0),
                prono("bonus", "Top 6", pilote: "K.Antonelli", points: 12, gagnes: 12),
                prono("bonus", "Top 10", pilote: "P.Gasly", points: 28, gagnes: 28),
                prono("bonus", "Top 6", pilote: "C.Leclerc", points: 13, gagnes: 0)
            ], podium: [
                PiloteClasse(prenom: "Kimi", nom: "Antonelli", ecurie: "Mercedes"),
                PiloteClasse(prenom: "George", nom: "Russell", ecurie: "Mercedes"),
                PiloteClasse(prenom: "Max", nom: "Verstappen", ecurie: "Red Bull")
            ]),
            // Antonelli · Verstappen · Norris — puis Leclerc, Russell, Lawson ; Piastri 8e.
            GrandPrixJoue(slug: "espagne", pronostics: [
                prono("vainqueur", "Vainqueur", pilote: "M.Verstappen", points: 28, gagnes: 0),
                prono("podium", "Podium", pilote: "K.Antonelli", points: 19, gagnes: 19),
                prono("podium", "Podium", pilote: "L.Hamilton", points: 22, gagnes: 0),
                prono("bonus", "Top 6", pilote: "G.Russell", points: 13, gagnes: 13),
                prono("bonus", "Top 10", pilote: "F.Colapinto", points: 36, gagnes: 36),
                prono("bonus", "Top 6", pilote: "O.Piastri", points: 15, gagnes: 0)
            ], podium: [
                PiloteClasse(prenom: "Kimi", nom: "Antonelli", ecurie: "Mercedes"),
                PiloteClasse(prenom: "Max", nom: "Verstappen", ecurie: "Red Bull"),
                PiloteClasse(prenom: "Lando", nom: "Norris", ecurie: "McLaren")
            ]),
            // Russell · Verstappen · Hadjar — puis Leclerc, Antonelli, Hamilton ; Ocon 8e,
            // Norris hors du top 10.
            GrandPrixJoue(slug: "azerbaidjan", pronostics: [
                prono("vainqueur", "Vainqueur", pilote: "G.Russell", points: 42, gagnes: 42),
                prono("podium", "Podium", pilote: "M.Verstappen", points: 11, gagnes: 11),
                prono("podium", "Podium", pilote: "C.Leclerc", points: 15, gagnes: 0),
                prono("bonus", "Top 6", pilote: "L.Hamilton", points: 21, gagnes: 21),
                prono("bonus", "Top 10", pilote: "E.Ocon", points: 33, gagnes: 33),
                prono("bonus", "Top 6", pilote: "L.Norris", points: 14, gagnes: 0)
            ], podium: [
                PiloteClasse(prenom: "George", nom: "Russell", ecurie: "Mercedes"),
                PiloteClasse(prenom: "Max", nom: "Verstappen", ecurie: "Red Bull"),
                PiloteClasse(prenom: "Isack", nom: "Hadjar", ecurie: "Red Bull")
            ])
        ]
        return HistoriqueSaison(
            saison: 2026,
            totalPoints: gps.compactMap(\.pointsGagnes).reduce(0, +),
            pronosticsReussis: gps.map(\.reussis).reduce(0, +),
            rang: 2,
            grandsPrix: gps)
    }()
}
