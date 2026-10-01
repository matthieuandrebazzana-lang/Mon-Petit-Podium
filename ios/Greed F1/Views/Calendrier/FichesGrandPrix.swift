import Foundation

/// Ce que la fiche d'un Grand Prix sait sans la base : le programme du week-end, la fiche
/// du circuit et son palmarès.
///
/// **Transcription de deux tables web**, qui restent propriétaires de ces valeurs :
/// `seances` de `frontend/src/lib/calendrier2026.js` (`GP_2026`) et `CIRCUITS` de
/// `frontend/src/lib/circuits.js`. Corriger une valeur ici sans la corriger là-bas ferait
/// dire deux choses aux deux apps — on corrige d'abord le web, puis on reporte.
///
/// > **Les données sont mockées** au même titre que ``CalendrierView`` : aucun appel réseau.
/// > Les heures des qualifications et de la course seront remplacées par celles de la base
/// > au câblage — c'est la règle de `seancesDuGp` côté web.
enum FichesGrandPrix {

    // MARK: - Les séances

    /// Une séance du week-end. `cle` suit `SEANCES` côté web, qui en fixe aussi l'ordre.
    struct Seance: Identifiable {
        let cle: String
        let instant: Date?
        var id: String { cle }
        /// Le nom de la séance dans la langue de l'interface — relu à chaque affichage.
        var libelle: String { t("seance.\(cle)") }
    }

    /// L'ordre des sept séances possibles — `SEANCES` côté web. **Le format du week-end
    /// vient des clés présentes, jamais d'un réglage** : Singapour, seul week-end sprint,
    /// n'a simplement pas d'`el2` ni d'`el3`.
    private static let ordre: [String] = [
        "el1", "el2", "qualifications_sprint", "el3", "sprint", "qualifications", "course"
    ]

    /// Instants UTC, recopiés de `GP_2026`.
    private static let horaires: [String: [String: String]] = [
        "pays-bas": ["el1": "2026-08-21T11:30:00Z", "el2": "2026-08-21T15:00:00Z",
                     "el3": "2026-08-22T10:30:00Z", "qualifications": "2026-08-22T14:00:00Z",
                     "course": "2026-08-23T13:00:00Z"],
        "italie": ["el1": "2026-09-04T10:30:00Z", "el2": "2026-09-04T14:00:00Z",
                   "el3": "2026-09-05T10:30:00Z", "qualifications": "2026-09-05T14:00:00Z",
                   "course": "2026-09-06T13:00:00Z"],
        "espagne": ["el1": "2026-09-11T11:30:00Z", "el2": "2026-09-11T15:00:00Z",
                    "el3": "2026-09-12T10:30:00Z", "qualifications": "2026-09-12T14:00:00Z",
                    "course": "2026-09-13T13:00:00Z"],
        "azerbaidjan": ["el1": "2026-09-24T08:30:00Z", "el2": "2026-09-24T12:00:00Z",
                        "el3": "2026-09-25T08:30:00Z", "qualifications": "2026-09-25T12:00:00Z",
                        "course": "2026-09-26T11:00:00Z"],
        "malaisie": ["el1": "2026-10-02T04:30:00Z", "el2": "2026-10-02T08:30:00Z",
                     "el3": "2026-10-03T04:30:00Z", "qualifications": "2026-10-03T08:00:00Z",
                     "course": "2026-10-04T07:00:00Z"],
        "singapour": ["el1": "2026-10-09T08:30:00Z", "qualifications_sprint": "2026-10-09T12:30:00Z",
                      "sprint": "2026-10-10T09:00:00Z", "qualifications": "2026-10-10T13:00:00Z",
                      "course": "2026-10-11T12:00:00Z"],
        "etats-unis": ["el1": "2026-10-23T17:30:00Z", "el2": "2026-10-23T21:00:00Z",
                       "el3": "2026-10-24T17:30:00Z", "qualifications": "2026-10-24T22:00:00Z",
                       "course": "2026-10-25T19:00:00Z"],
        "mexique": ["el1": "2026-10-30T18:30:00Z", "el2": "2026-10-30T22:00:00Z",
                    "el3": "2026-10-31T17:30:00Z", "qualifications": "2026-10-31T23:00:00Z",
                    "course": "2026-11-01T21:00:00Z"],
        "bresil": ["el1": "2026-11-13T14:30:00Z", "el2": "2026-11-13T19:00:00Z",
                   "el3": "2026-11-14T14:30:00Z", "qualifications": "2026-11-14T18:00:00Z",
                   "course": "2026-11-15T17:00:00Z"],
        "las-vegas": ["el1": "2026-11-20T00:30:00Z", "el2": "2026-11-20T04:00:00Z",
                      "el3": "2026-11-21T00:30:00Z", "qualifications": "2026-11-21T04:00:00Z",
                      "course": "2026-11-22T04:00:00Z"],
        "qatar": ["el1": "2026-11-27T13:30:00Z", "el2": "2026-11-27T17:00:00Z",
                  "el3": "2026-11-28T14:30:00Z", "qualifications": "2026-11-28T18:00:00Z",
                  "course": "2026-11-29T16:00:00Z"],
        "abu-dhabi": ["el1": "2026-12-04T09:30:00Z", "el2": "2026-12-04T13:00:00Z",
                      "el3": "2026-12-05T10:30:00Z", "qualifications": "2026-12-05T14:00:00Z",
                      "course": "2026-12-06T13:00:00Z"]
    ]

    /// Les séances d'un Grand Prix, dans l'ordre du week-end.
    ///
    /// Sans entrée, les cinq séances du **format ordinaire, sans heure** — cinq noms valent
    /// mieux qu'un bloc vide, et le format sprint ne se devine pas (`SEANCES_ORDINAIRE`).
    static func seances(slug: String) -> [Seance] {
        let iso = ISO8601DateFormatter()
        guard let table = horaires[slug] else {
            let ordinaire: Set = ["el1", "el2", "el3", "qualifications", "course"]
            return ordre.filter { ordinaire.contains($0) }
                .map { Seance(cle: $0, instant: nil) }
        }
        return ordre.filter { table[$0] != nil }.map {
            Seance(cle: $0, instant: table[$0].flatMap(iso.date(from:)))
        }
    }

    // MARK: - Le circuit

    struct RecordTour {
        let temps: String
        let pilote: String
        let annee: Int
    }

    /// Un vainqueur. `ecurie` nomme l'écurie **d'aujourd'hui** (AlphaTauri → Racing Bulls),
    /// comme côté web : c'est la livrée qu'on sait peindre.
    struct Vainqueur: Identifiable {
        let annee: Int
        let pilote: String
        let numero: Int
        let ecurie: String
        let pays: String
        /// Code ISO 3166-1 alpha-2, en minuscules — il nomme l'asset `drapeau-<code>`.
        let code: String
        var id: Int { annee }

        /// La nationalité dans la langue de l'interface, tirée du code ISO — ``pays``, écrit
        /// en français, n'est que le repli.
        var paysAffiche: String {
            localeInterface.localizedString(forRegionCode: code.uppercased()) ?? pays
        }

        /// Le drapeau de nationalité, le même catalogue que le classement des résultats.
        var drapeau: String { "drapeau-\(code)" }

        /// Le premier mot est le prénom, le reste le nom — la dérivation du web.
        var prenom: String { pilote.split(separator: " ").dropLast().joined(separator: " ") }
        var nom: String { pilote.split(separator: " ").last.map(String.init) ?? pilote }
    }

    struct Fiche {
        let longueurKm: Double
        let tours: Int?
        let premierGp: Int?
        let record: RecordTour?
        let vainqueurs: [Vainqueur]
    }

    /// Les nationalités de `NATIONALITES` (`DrapeauxGP.jsx`) — libellé et code ISO. Chaque
    /// code a son asset `drapeau-<code>`, écrit par `extraire-drapeaux-pilotes.sh`.
    private static let nl = ("Pays-Bas", "nl"), au = ("Australie", "au"),
                        gb = ("Royaume-Uni", "gb"), at = ("Autriche", "at"),
                        mc = ("Monaco", "mc"), fr = ("France", "fr"),
                        mx = ("Mexique", "mx"), fi = ("Finlande", "fi"),
                        de = ("Allemagne", "de"), es = ("Espagne", "es")

    private static func v(_ annee: Int, _ pilote: String, _ numero: Int, _ ecurie: String,
                          _ nat: (String, String)) -> Vainqueur {
        Vainqueur(annee: annee, pilote: pilote, numero: numero, ecurie: ecurie,
                  pays: nat.0, code: nat.1)
    }

    /// `CIRCUITS`, transcrit. **Les palmarès incomplets le restent** : Las Vegas n'a couru
    /// que trois fois, le Qatar quatre — une case de remplissage serait une donnée fausse.
    private static let circuits: [String: Fiche] = [
        "pays-bas": Fiche(longueurKm: 4.259, tours: 72, premierGp: 1952,
                          record: RecordTour(temps: "1:11.097", pilote: "Lewis Hamilton", annee: 2021),
                          vainqueurs: [
                            v(2025, "Oscar Piastri", 81, "mclaren", au),
                            v(2024, "Lando Norris", 4, "mclaren", gb),
                            v(2023, "Max Verstappen", 1, "red-bull", nl),
                            v(2022, "Max Verstappen", 1, "red-bull", nl),
                            v(2021, "Max Verstappen", 33, "red-bull", nl),
                            v(1985, "Niki Lauda", 1, "mclaren", at)]),
        "italie": Fiche(longueurKm: 5.793, tours: 53, premierGp: 1950,
                        record: RecordTour(temps: "1:21.046", pilote: "Rubens Barrichello", annee: 2004),
                        vainqueurs: [
                            v(2025, "Max Verstappen", 1, "red-bull", nl),
                            v(2024, "Charles Leclerc", 16, "ferrari", mc),
                            v(2023, "Max Verstappen", 1, "red-bull", nl),
                            v(2022, "Max Verstappen", 1, "red-bull", nl),
                            v(2021, "Daniel Ricciardo", 3, "mclaren", au),
                            v(2020, "Pierre Gasly", 10, "racing-bulls", fr)]),
        "espagne": Fiche(longueurKm: 5.474, tours: 56, premierGp: 2026, record: nil,
                         vainqueurs: [
                            v(2025, "Oscar Piastri", 81, "mclaren", au),
                            v(2024, "Max Verstappen", 1, "red-bull", nl),
                            v(2023, "Max Verstappen", 1, "red-bull", nl),
                            v(2022, "Max Verstappen", 1, "red-bull", nl),
                            v(2021, "Lewis Hamilton", 44, "mercedes", gb),
                            v(2020, "Lewis Hamilton", 44, "mercedes", gb)]),
        "azerbaidjan": Fiche(longueurKm: 6.003, tours: 51, premierGp: 2016,
                             record: RecordTour(temps: "1:43.009", pilote: "Charles Leclerc", annee: 2019),
                             vainqueurs: [
                                v(2025, "Max Verstappen", 1, "red-bull", nl),
                                v(2024, "Oscar Piastri", 81, "mclaren", au),
                                v(2023, "Sergio Pérez", 11, "red-bull", mx),
                                v(2022, "Max Verstappen", 1, "red-bull", nl),
                                v(2021, "Sergio Pérez", 11, "red-bull", mx),
                                v(2019, "Valtteri Bottas", 77, "mercedes", fi)]),
        "malaisie": Fiche(longueurKm: 5.543, tours: 56, premierGp: 1999,
                          record: RecordTour(temps: "1:34.080", pilote: "Sebastian Vettel", annee: 2017),
                          vainqueurs: [
                            v(2017, "Max Verstappen", 33, "red-bull", nl),
                            v(2016, "Daniel Ricciardo", 3, "red-bull", au),
                            v(2015, "Sebastian Vettel", 5, "ferrari", de),
                            v(2014, "Lewis Hamilton", 44, "mercedes", gb),
                            v(2013, "Sebastian Vettel", 1, "red-bull", de),
                            v(2012, "Fernando Alonso", 5, "ferrari", es)]),
        "singapour": Fiche(longueurKm: 4.94, tours: 62, premierGp: 2008,
                           record: RecordTour(temps: "1:34.486", pilote: "Daniel Ricciardo", annee: 2024),
                           vainqueurs: [
                            v(2025, "George Russell", 63, "mercedes", gb),
                            v(2024, "Lando Norris", 4, "mclaren", gb),
                            v(2023, "Carlos Sainz", 55, "ferrari", es),
                            v(2022, "Sergio Pérez", 11, "red-bull", mx),
                            v(2019, "Sebastian Vettel", 5, "ferrari", de),
                            v(2018, "Lewis Hamilton", 44, "mercedes", gb)]),
        "etats-unis": Fiche(longueurKm: 5.513, tours: 56, premierGp: 2012,
                            record: RecordTour(temps: "1:36.169", pilote: "Charles Leclerc", annee: 2019),
                            vainqueurs: [
                                v(2025, "Max Verstappen", 1, "red-bull", nl),
                                v(2024, "Charles Leclerc", 16, "ferrari", mc),
                                v(2023, "Max Verstappen", 1, "red-bull", nl),
                                v(2022, "Max Verstappen", 1, "red-bull", nl),
                                v(2021, "Max Verstappen", 33, "red-bull", nl),
                                v(2019, "Valtteri Bottas", 77, "mercedes", fi)]),
        "mexique": Fiche(longueurKm: 4.304, tours: 71, premierGp: 1963,
                         record: RecordTour(temps: "1:17.774", pilote: "Valtteri Bottas", annee: 2021),
                         vainqueurs: [
                            v(2025, "Lando Norris", 4, "mclaren", gb),
                            v(2024, "Carlos Sainz", 55, "ferrari", es),
                            v(2023, "Max Verstappen", 1, "red-bull", nl),
                            v(2022, "Max Verstappen", 1, "red-bull", nl),
                            v(2021, "Max Verstappen", 33, "red-bull", nl),
                            v(2019, "Lewis Hamilton", 44, "mercedes", gb)]),
        "bresil": Fiche(longueurKm: 4.309, tours: 71, premierGp: 1973,
                        record: RecordTour(temps: "1:10.540", pilote: "Valtteri Bottas", annee: 2018),
                        vainqueurs: [
                            v(2025, "Lando Norris", 4, "mclaren", gb),
                            v(2024, "Max Verstappen", 1, "red-bull", nl),
                            v(2023, "Max Verstappen", 1, "red-bull", nl),
                            v(2022, "George Russell", 63, "mercedes", gb),
                            v(2021, "Lewis Hamilton", 44, "mercedes", gb),
                            v(2019, "Max Verstappen", 33, "red-bull", nl)]),
        "las-vegas": Fiche(longueurKm: 6.201, tours: 50, premierGp: 2023,
                           record: RecordTour(temps: "1:34.876", pilote: "Lando Norris", annee: 2024),
                           vainqueurs: [
                            v(2025, "Max Verstappen", 1, "red-bull", nl),
                            v(2024, "George Russell", 63, "mercedes", gb),
                            v(2023, "Max Verstappen", 1, "red-bull", nl)]),
        "qatar": Fiche(longueurKm: 5.419, tours: 57, premierGp: 2021,
                       record: RecordTour(temps: "1:23.196", pilote: "Max Verstappen", annee: 2021),
                       vainqueurs: [
                        v(2025, "Max Verstappen", 1, "red-bull", nl),
                        v(2024, "Max Verstappen", 1, "red-bull", nl),
                        v(2023, "Max Verstappen", 1, "red-bull", nl),
                        v(2021, "Lewis Hamilton", 44, "mercedes", gb)]),
        "abu-dhabi": Fiche(longueurKm: 5.281, tours: 58, premierGp: 2009,
                           record: RecordTour(temps: "1:26.103", pilote: "Max Verstappen", annee: 2021),
                           vainqueurs: [
                            v(2025, "Lando Norris", 4, "mclaren", gb),
                            v(2024, "Lando Norris", 4, "mclaren", gb),
                            v(2023, "Max Verstappen", 1, "red-bull", nl),
                            v(2022, "Max Verstappen", 1, "red-bull", nl),
                            v(2021, "Max Verstappen", 33, "red-bull", nl),
                            v(2020, "Max Verstappen", 33, "red-bull", nl)])
    ]

    /// La fiche d'un circuit, `nil` hors table — l'écran retire alors le bloc plutôt que
    /// d'afficher quatre tirets.
    static func fiche(slug: String) -> Fiche? { circuits[slug] }
}
