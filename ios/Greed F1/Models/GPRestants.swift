import Foundation

/// Le décompte des Grands Prix restants de la saison — **un seul propriétaire** pour
/// l'accueil, la liste des championnats et le calendrier.
///
/// **Il se lit sur ``GrandPrixSaison/saison2026``**, jamais sur `grands_prix` seule : la
/// base ne connaît que ce que le scraper a rencontré, et la compter annoncerait « 1 Grand
/// Prix restant » au milieu d'une saison qui en compte douze.
///
/// Restant = **pas terminé**. Un Grand Prix que la base connaît l'est d'après son statut ;
/// un Grand Prix qu'elle ne connaît pas — ou quand elle n'a pas répondu — l'est d'après sa
/// **date écrite** : son jour de course est passé. Sans ce repli, l'accueil, qui ne lit pas
/// la base, comptait les douze Grands Prix comme « à venir » toute la saison.
enum GPRestants {

    /// Le décompte sur la liste statique seule : chaque Grand Prix est jugé sur sa date.
    static var compte: Int { compte(enBase: nil) }

    /// Le décompte sur la liste croisée avec la base.
    static func compte(enBase: [GrandPrixEnBase]?, le maintenant: Date = .now) -> Int {
        compte(dans: GrandPrixSaison.saison2026(croiseeAvec: enBase), le: maintenant)
    }

    /// Le décompte sur des cartes déjà croisées.
    static func compte(dans grandsPrix: [GrandPrixSaison], le maintenant: Date = .now) -> Int {
        grandsPrix.filter { !estTermine($0, le: maintenant) }.count
    }

    /// **Le statut de la base l'emporte** quand elle connaît le Grand Prix : une course
    /// courue dont les résultats ne sont pas encore tombés reste à compter. Sinon, la date.
    static func estTermine(_ gp: GrandPrixSaison, le maintenant: Date = .now) -> Bool {
        if let enBase = gp.enBase { return enBase.statut == "termine" }
        guard let fin = finDuJourDeCourse(gp) else { return false }
        return fin <= maintenant
    }

    /// Minuit à la fin du jour de course, en heure locale. `nil` si le mois écrit n'est pas
    /// reconnu — le Grand Prix reste alors compté, jamais effacé en silence.
    static func finDuJourDeCourse(_ gp: GrandPrixSaison) -> Date? {
        guard let mois = mois[gp.mois], let jour = Int(gp.jour) else { return nil }
        let calendrier = Calendar.current
        guard let debut = calendrier.date(from: DateComponents(year: 2026, month: mois, day: jour))
        else { return nil }
        return calendrier.date(byAdding: .day, value: 1, to: debut)
    }

    /// Les mois tels que ``GrandPrixSaison/mois`` les écrit.
    private static let mois: [String: Int] = [
        "JANV": 1, "FÉVR": 2, "MARS": 3, "AVR": 4, "MAI": 5, "JUIN": 6,
        "JUIL": 7, "AOÛT": 8, "SEPT": 9, "OCT": 10, "NOV": 11, "DÉC": 12
    ]

    /// « Saison 2026 · 9 Grands Prix restants » — l'accord suit le nombre.
    static func libelle(_ compte: Int) -> String {
        let pluriel = compte > 1 ? "s" : ""
        return "Saison 2026 · \(compte) Grand\(pluriel) Prix restant\(pluriel)"
    }
}
