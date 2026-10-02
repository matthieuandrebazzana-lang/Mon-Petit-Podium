import Foundation

// MARK: - Le Grand Prix que traverse le parcours

/// Ce que les trois écrans du parcours savent d'un Grand Prix **avant** d'avoir rien
/// chargé : de quoi titrer l'écran et demander ses cotes.
///
/// **L'identifiant voyage désormais avec le reste** (`docs/swift-app.md` §7.6, étape 7) :
/// sans lui, aucun écran de saisie ne savait quel Grand Prix demander.
struct GrandPrixPronos: Hashable {
    let id: UUID
    let nom: String
    /// La clé des assets `flag-<slug>` — l'en-tête du récapitulatif porte le drapeau.
    let slug: String
    let sousTitre: String

    /// Le nom à afficher — ``GrandPrixSaison/nomAffiche(slug:repli:)``, jamais ``nom``.
    var nomAffiche: String { GrandPrixSaison.nomAffiche(slug: slug, repli: nom) }
}

/// Les trois champs dont ``EcheancePronostics`` a besoin — **jamais un calcul local** : le
/// compte à rebours de la saisie et du récapitulatif les passe tels quels à la seule source.
struct HorairesGP: Hashable {
    let statut: String?
    let dateCourse: Date?
    let dateQualifications: Date?

    func echeance(le maintenant: Date = .now) -> EcheancePronostics {
        EcheancePronostics.pour(statut: statut, dateCourse: dateCourse,
                                dateQualifications: dateQualifications, le: maintenant)
    }
}

// MARK: - Les cotes — `GET /grands-prix/{id}/cotes`

/// Un Grand Prix et ses marchés, tels que `GET /grands-prix/{id}/cotes` les sert (§3.4).
struct CotesGrandPrix: Decodable, Equatable {
    let id: UUID
    let nom: String
    let horaires: HorairesGP
    /// **Déjà triés** par ``OrdreMarches`` : les deux écrans du parcours les montrent dans
    /// le même ordre, quelle que soit la porte d'entrée.
    let marches: [MarcheCotes]

    enum CodingKeys: String, CodingKey {
        case id, nom, statut, marches
        case dateCourse = "date_course"
        case dateQualifications = "date_qualifications"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        horaires = HorairesGP(
            statut: try c.decodeIfPresent(String.self, forKey: .statut),
            dateCourse: try c.decodeIfPresent(Date.self, forKey: .dateCourse),
            dateQualifications: try c.decodeIfPresent(Date.self, forKey: .dateQualifications))
        let lus = try c.decodeIfPresent([MarcheCotes].self, forKey: .marches) ?? []
        marches = OrdreMarches.trier(lus, slug: \.marche)
    }

    /// Le marché d'un slug — `marcheDe` du web.
    func marche(_ slug: String) -> MarcheCotes? {
        marches.first { $0.marche == slug }
    }

    /// Une issue retrouvée par son identifiant, **avec son marché** — `indexerCotes`.
    func cote(_ id: String?) -> (cote: Cote, marche: MarcheCotes)? {
        guard let id else { return nil }
        for marche in marches {
            if let cote = marche.cotes.first(where: { $0.id == id }) { return (cote, marche) }
        }
        return nil
    }
}

/// Un marché du bookmaker : son slug, son libellé tel qu'Unibet l'écrit, ses issues.
struct MarcheCotes: Decodable, Hashable, Identifiable {
    /// **Slug** fabriqué par le scraper — la clé technique, jamais affichée.
    let marche: String
    /// Le nom du marché **tel que le bookmaker l'écrit** — ce qui s'affiche.
    let libelle: String
    let cotes: [Cote]

    var id: String { marche }

    static let vainqueur = "vainqueur"
    static let podium = "podium"
}

/// Une issue. **`points` est déjà un nombre de points entier** (cote × 10, arrondie) : on
/// ne le multiplie ni ne le divise jamais (§6.1).
struct Cote: Decodable, Hashable, Identifiable {
    /// Le libellé de l'issue — un pilote pour les marchés de pilotes, une écurie, un écart…
    let pilote: String
    let points: Int
    /// `id_outcome_unibet` — **la clé de toute la saisie**. Le même pilote n'a pas le même
    /// identifiant d'un marché à l'autre : toute exclusion croisée passe par ``ClePilote``.
    let id: String
}

// MARK: - Les favoris — `GET /grands-prix/{id}/favoris`

/// Une cote épinglée à l'étoile. **Les paris bonus ne se choisissent que parmi eux** : le
/// serveur refuse un bonus qui n'est pas un favori (§3.5).
///
/// Les quatre champs descriptifs sont `nil` quand la cote a disparu du Grand Prix depuis
/// l'épinglage : le favori reste servi, et s'affiche « Cote retirée ».
struct Favori: Decodable, Hashable, Identifiable {
    let idOutcomeUnibet: String
    let marche: String?
    let libelle: String?
    let pilote: String?
    let points: Int?

    var id: String { idOutcomeUnibet }

    enum CodingKeys: String, CodingKey {
        case marche, libelle, pilote, points
        case idOutcomeUnibet = "id_outcome_unibet"
    }

    init(idOutcomeUnibet: String, marche: String?, libelle: String?, pilote: String?, points: Int?) {
        self.idOutcomeUnibet = idOutcomeUnibet
        self.marche = marche
        self.libelle = libelle
        self.pilote = pilote
        self.points = points
    }
}

// MARK: - Mes pronostics — lecture directe sous RLS

/// Une ligne de `pronostics` lue **directement** dans Supabase (§3.9, « Mes pronostics d'un
/// GP ») : un joueur relit toujours les siens, la RLS le décrit exactement.
///
/// Elle ne sert qu'à **préremplir** la saisie : les pilotes et les points viennent des
/// cotes déjà chargées, rapprochées par `id_outcome_unibet`.
struct PronosticEnBase: Decodable, Equatable {
    let type: String
    let idOutcomeUnibet: String
    /// Les deux issues du podium, `nil` hors podium ou quand la ligne de détail manque.
    let podium: (String, String)?

    enum CodingKeys: String, CodingKey {
        case type
        case idOutcomeUnibet = "id_outcome_unibet"
        case pronosticPodium = "pronostic_podium"
    }

    private struct Detail: Decodable {
        let pilote_1: String
        let pilote_2: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        idOutcomeUnibet = try c.decode(String.self, forKey: .idOutcomeUnibet)
        // PostgREST rend une jointure « un vers un » tantôt en objet, tantôt en tableau
        // d'un élément selon la version : les deux formes sont acceptées, comme au web.
        let detail = (try? c.decodeIfPresent(Detail.self, forKey: .pronosticPodium))
            ?? (try? c.decodeIfPresent([Detail].self, forKey: .pronosticPodium))?.first
        podium = detail.map { ($0.pilote_1, $0.pilote_2) }
    }

    static func == (a: Self, b: Self) -> Bool {
        a.type == b.type && a.idOutcomeUnibet == b.idOutcomeUnibet
            && a.podium?.0 == b.podium?.0 && a.podium?.1 == b.podium?.1
    }
}

// MARK: - L'écriture — `POST /grands-prix/{id}/pronostics`

/// Le corps de `POST …/pronostics` : **uniquement des `id_outcome_unibet`**. Il remplace le
/// jeu complet de l'appelant, dans une seule transaction.
struct CorpsPronostics: Encodable {
    struct Podium: Encodable {
        let pilote_1: String
        let pilote_2: String
    }
    let vainqueur: String
    let podium: Podium
    let bonus: [String]
}

struct CorpsFavori: Encodable {
    let id_outcome_unibet: String
}

// MARK: - La clé d'un pilote

/// La clé de comparaison d'un pilote — `clePilote` du web : accents retirés, minuscules,
/// espaces resserrés.
///
/// **L'exclusion croisée se compare sur elle, jamais sur `id_outcome_unibet`** (§6.3) :
/// Antonelli n'a pas le même identifiant au marché « Vainqueur » et au marché « Podium ».
/// Un filtre par identifiant n'exclurait jamais le vainqueur du podium.
enum ClePilote {
    static func de(_ nom: String?) -> String {
        guard let nom else { return "" }
        return nom
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

// MARK: - L'ordre des marchés

/// L'ordre d'affichage des marchés — **par catégorie, jamais dans l'ordre d'Unibet**.
/// Transcription d'`ORDRE_MARCHES` (`frontend/src/lib/pronostics.js`) : à tenir avec le web.
///
/// Les tests sont **mutuellement exclusifs** (égalité stricte sur les deux obligatoires,
/// `qualif` exclu du tour le plus rapide) : l'ordre de la liste est l'ordre d'affichage,
/// pas un ordre de priorité. Un marché non reconnu part à la fin, dans l'ordre d'Unibet —
/// le taire serait pire que le mal placer.
enum OrdreMarches {

    private static func rangTop(_ slug: String) -> Int? {
        guard let trouve = slug.firstMatch(of: /^(?:dans-le-)?top-?(\d+)$/) else { return nil }
        return Int(trouve.1)
    }

    private static func estTourRapide(_ s: String) -> Bool {
        s.contains("tour") && (s.contains("rapide") || s.contains("meilleur")) && !s.contains("qualif")
    }

    private static let categories: [(reconnait: (String) -> Bool, ordonne: ((String) -> Int)?)] = [
        ({ $0 == MarcheCotes.vainqueur }, nil),
        ({ $0 == MarcheCotes.podium }, nil),
        ({ rangTop($0) != nil }, { rangTop($0) ?? 0 }),
        ({ $0.contains("ecart") || ($0.contains("marge") && $0.contains("victoire")) }, nil),
        ({ estTourRapide($0) && !$0.contains("voiture") }, nil),
        ({ estTourRapide($0) && $0.contains("voiture") }, nil),
        ({ $0.hasPrefix("ecurie") || $0.hasPrefix("equipe") || $0.hasPrefix("constructeur") }, nil),
        ({ $0.contains("nationalite")
            || ($0.contains("pays") && ($0.contains("vainqueur") || $0.contains("gagnant"))) }, nil),
        ({ $0.contains("qualif") }, nil),
        ({ $0.contains("duel") || $0.contains("coequipier") }, nil)
    ]

    /// `[catégorie, rang dans la catégorie]` — `rangMarche`.
    static func rang(_ marche: String?) -> (Int, Int) {
        let slug = (marche ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !slug.isEmpty,
              let i = categories.firstIndex(where: { $0.reconnait(slug) })
        else { return (categories.count, 0) }
        return (i, categories[i].ordonne?(slug) ?? 0)
    }

    /// Tri **stable** : à catégorie égale, l'ordre d'Unibet tranche — `trierParMarche`.
    static func trier<T>(_ liste: [T], slug: (T) -> String?) -> [T] {
        liste.enumerated()
            .map { (element: $0.element, rang: $0.offset, cle: rang(slug($0.element))) }
            .sorted { a, b in
                if a.cle.0 != b.cle.0 { return a.cle.0 < b.cle.0 }
                if a.cle.1 != b.cle.1 { return a.cle.1 < b.cle.1 }
                return a.rang < b.rang
            }
            .map(\.element)
    }
}
