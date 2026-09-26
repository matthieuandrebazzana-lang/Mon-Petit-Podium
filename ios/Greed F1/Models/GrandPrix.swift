import Foundation

/// Un Grand Prix tel que la base le connaît — servi par `GET /scraper/cotes` (§3.4) ou lu
/// directement dans `public.grands_prix` sous RLS.
///
/// **La base ne sait que ce que le scraper a rencontré** : l'identifiant, le statut, les
/// deux heures et l'existence de cotes. Le reste d'un Grand Prix — pays, circuit, séances,
/// palmarès — est statique côté app (`docs/swift-app.md` §7.6).
struct GrandPrixEnBase: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let nom: String
    /// **`nil` n'est PAS une date passée** : l'horaire n'est pas encore annoncé, le GP
    /// reste ouvert et se trie en fin de liste (§7.4).
    let dateCourse: Date?
    /// Nulle tant qu'Unibet n'a pas annoncé le programme. Ne sert **qu'au** décompte
    /// d'ouverture, jamais à décider du bouton de pronostics (§6.4).
    let dateQualifications: Date?
    /// `a_venir`, `cotes_figees` ou `termine` — la contrainte `check` de la table.
    let statut: String
    /// Au moins un marché servi. Toujours faux sur une lecture directe, qui ne les demande pas.
    let cotesDisponibles: Bool
    /// `provisoire`, `definitif` ou `nil` (pas de résultats) — ``StatutResultats``. Nul sur
    /// une lecture qui ne le demande pas.
    let statutResultats: String?

    enum CodingKeys: String, CodingKey {
        case id, nom, statut, marches
        case dateCourse = "date_course"
        case statutResultats = "statut_resultats"
        case dateQualifications = "date_qualifications"
    }

    /// Un marché n'est compté, jamais lu : le calendrier ne veut savoir que s'il en existe.
    private struct Marche: Decodable {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        dateCourse = try c.decodeIfPresent(Date.self, forKey: .dateCourse)
        dateQualifications = try c.decodeIfPresent(Date.self, forKey: .dateQualifications)
        statut = try c.decode(String.self, forKey: .statut)
        statutResultats = try? c.decodeIfPresent(String.self, forKey: .statutResultats)
        // `try?` : un marché mal formé fait perdre l'information « cotes présentes », jamais
        // le Grand Prix, et encore moins la liste.
        let marches = (try? c.decodeIfPresent([Marche].self, forKey: .marches)) ?? nil
        cotesDisponibles = !(marches ?? []).isEmpty
    }

    var slug: String { SlugCircuit.de(nom) }
}

// MARK: - Le slug

/// La clé des assets `flag-<slug>` / `trace-<slug>`, de ``TeintesDrapeaux`` et de la liste
/// statique du calendrier, tirée du nom tel qu'il est en base.
///
/// **Transcription de `slugCircuit`** (`frontend/src/composants/TracesCircuits.jsx`) :
/// minuscules, accents retirés, préfixe « GP » ôté en tête, le reste en tirets — puis les
/// alias, parce qu'Unibet écrit « GP Pays Bas » une semaine et « GP Pays-Bas » la suivante.
/// Un slug inconnu est rendu tel quel : c'est à l'écran de constater qu'aucun asset ne lui
/// répond.
///
/// **Un seul propriétaire** : le widget d'un championnat, celui de l'accueil et le
/// croisement du calendrier rapprochent tous par cette clé. Deux normalisations auraient
/// fini par ne plus retrouver le même Grand Prix.
enum SlugCircuit {

    static func de(_ nom: String) -> String {
        var texte = nom.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        texte = texte.replacingOccurrences(of: #"^\s*(grand\s+prix|gp)\b"#, with: "",
                                           options: .regularExpression)
        texte = texte.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        texte = texte.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if TeintesDrapeaux.table[texte] != nil { return texte }
        for (motif, cle) in alias
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
}

// MARK: - L'échéance des pronostics

/// Ce que le compte à rebours doit dire d'un Grand Prix — **la seule source** de l'app
/// (`docs/swift-app.md` §6.4), pendant exact de `etatPronostics` et `cotesArretees`
/// (`frontend/src/lib/calendrier.js`).
///
/// Elle sert toutes les surfaces qui portent un décompte ou un bouton de pronostics : le
/// widget de l'accueil, celui d'un championnat, puis l'écran de saisie et le récapitulatif.
/// **L'horloge ne décide jamais de ce qu'elle annonce** : elle reçoit `label` et `texte`.
///
/// ## Deux échéances, pas une
///
/// | Phase | Échéance | Label |
/// |---|---|---|
/// | Avant le relevé des cotes | qualifications + 2 h | « Ouverture dans » |
/// | Pronostics ouverts | départ | « Fermeture dans » |
/// | Après la fermeture | — | « Pronostics » · « Fermés » |
///
/// C'est ``cotesArretees(statut:dateCourse:le:)`` qui départage les deux premières, jamais
/// le statut brut : le bouton de pronostics s'affiche sur exactement la même condition.
struct EcheancePronostics: Equatable {

    enum Phase: Equatable { case ouverture, fermeture }

    let phase: Phase
    /// Les pronostics sont fermés. **Faux pendant toute la phase d'ouverture** : rien n'est
    /// fermé avant d'avoir été ouvert.
    let ferme: Bool
    /// Les secondes jusqu'à l'échéance, `nil` quand il n'y a rien à décompter.
    let restant: TimeInterval?
    /// « 2j 14h 32min ». **`texte` non nul est le seul test à faire** pour savoir s'il y a
    /// quelque chose à décompter.
    let texte: String?
    /// Le titre au-dessus du décompte — « Fermeture dans », « Ouverture », « Pronostics »…
    let label: String
    /// Le mot qui prend la place du décompte quand il n'y en a pas.
    let substitut: String

    /// Le relevé des cotes est prévu **deux heures** après les qualifications — le délai du
    /// job du samedi. Une prévision, pas une garantie.
    static let delaiOuverture: TimeInterval = 2 * 60 * 60

    /// La ligne unique d'une surface qui n'a pas la place de deux cases : « Fermeture dans
    /// 2j 14h 32min », « Ouverture à confirmer », « Pronostics fermés ».
    var phrase: String {
        if let texte { return "\(label) \(texte)" }
        return "\(label) \(substitut.lowercased())"
    }

    /// Les cotes sont arrêtées et les pronostics ouverts — `cotesArretees` du web.
    ///
    /// **Deux conditions, et rien d'autre** : statut `cotes_figees` ET départ pas encore
    /// passé. **Surtout pas `date_qualifications`**, nulle sur toute ligne qu'Unibet n'a pas
    /// programmée. **Un départ inconnu laisse ouvert**, et **aucune marge** : la fermeture
    /// est `date_course` elle-même, comme en base et au backend.
    static func cotesArretees(statut: String?, dateCourse: Date?, le maintenant: Date = .now) -> Bool {
        guard statut == "cotes_figees" else { return false }
        guard let dateCourse else { return true }
        return dateCourse > maintenant
    }

    static func pour(statut: String?, dateCourse: Date?, dateQualifications: Date?,
                     le maintenant: Date = .now) -> EcheancePronostics {
        let fermePasse = dateCourse.map { $0 <= maintenant } ?? false
        let ouverts = cotesArretees(statut: statut, dateCourse: dateCourse, le: maintenant)

        // **« Pas encore ouverts » exige les trois à la fois** : cotes non arrêtées,
        // fermeture pas encore passée, et GP non couru. Le premier test suffit un samedi
        // matin ; il ne suffit pas le dimanche soir, où un GP `termine` le passe aussi.
        if !ouverts && !fermePasse && statut != "termine" {
            // Le décompte se tait dès que l'heure prévue est passée sans que le statut ait
            // bougé : mieux vaut ne plus rien promettre qu'une ouverture déjà en retard.
            let restant = dateQualifications
                .map { $0.addingTimeInterval(delaiOuverture).timeIntervalSince(maintenant) }
                .flatMap { $0 > 0 ? $0 : nil }
            return EcheancePronostics(
                phase: .ouverture, ferme: false, restant: restant,
                texte: restant.map(formaterRestant),
                label: restant == nil ? "Ouverture" : "Ouverture dans",
                substitut: "À confirmer")
        }

        if fermePasse || statut == "termine" {
            return EcheancePronostics(
                phase: .fermeture, ferme: true, restant: 0, texte: nil,
                label: "Pronostics", substitut: "Fermés")
        }

        // Ouverts. Un départ inconnu n'a aucune fermeture à décompter : le titre annonce
        // alors le départ, et le mot dit qu'on l'attend.
        let restant = dateCourse.map { $0.timeIntervalSince(maintenant) }
        return EcheancePronostics(
            phase: .fermeture, ferme: false, restant: restant,
            texte: restant.map(formaterRestant),
            label: restant == nil ? "Départ" : "Fermeture dans",
            substitut: "À confirmer")
    }

    /// « 2j 14h 32min », puis « 32min 10s » dans la dernière heure — `formaterRestant`.
    static func formaterRestant(_ secondes: TimeInterval) -> String {
        let total = max(0, Int(secondes))
        let (j, h, m, s) = (total / 86_400, total % 86_400 / 3600, total % 3600 / 60, total % 60)
        if j > 0 { return "\(j)j \(h)h \(m)min" }
        if h > 0 { return "\(h)h \(m)min" }
        // Sous l'heure, les minutes seules ne suffisent plus à dire l'urgence.
        if m > 0 { return "\(m)min \(s)s" }
        return "\(s)s"
    }
}
