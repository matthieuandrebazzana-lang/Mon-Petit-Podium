import Foundation

/// Le décompte des Grands Prix restants de la saison — **un seul propriétaire** pour
/// l'accueil, la liste des championnats et le calendrier.
///
/// **Il se lit sur ``GrandPrixSaison/saison2026``**, jamais sur `grands_prix` seule : la
/// base ne connaît que ce que le scraper a rencontré, et la compter annoncerait « 1 Grand
/// Prix restant » au milieu d'une saison qui en compte douze.
///
/// Restant = **à venir ou pronos ouverts**. Un Grand Prix terminé ne l'est plus, un Grand
/// Prix fermé non plus : sa course est partie.
enum GPRestants {

    /// Le décompte sur la liste statique seule : tout Grand Prix absent de la base est « à
    /// venir » (``EtatGp/pour(_:le:)``). Il devient réel dès que les écrans qui le lisent
    /// passeront par ``compte(dans:)`` avec les états de ``CalendrierSaison``.
    static var compte: Int { compte(enBase: nil) }

    /// Le décompte sur la liste croisée avec la base.
    static func compte(enBase: [GrandPrixEnBase]?) -> Int {
        compte(dans: GrandPrixSaison.saison2026(croiseeAvec: enBase))
    }

    /// Le décompte sur des cartes déjà croisées. L'état est recalculé depuis `enBase`, et
    /// non lu sur ``GrandPrixSaison/etat`` : ce dernier vaut `nil` tant que la base n'a pas
    /// répondu, alors qu'une carte inconnue d'elle est bien « à venir ».
    static func compte(dans grandsPrix: [GrandPrixSaison]) -> Int {
        grandsPrix.filter { estRestant(EtatGp.pour($0.enBase)) }.count
    }

    static func estRestant(_ etat: EtatGp) -> Bool {
        etat == .aVenir || etat == .ouvert
    }

    /// « Saison 2026 · 12 Grands Prix restants » — l'accord suit le nombre.
    static func libelle(_ compte: Int) -> String {
        let pluriel = compte > 1 ? "s" : ""
        return "Saison 2026 · \(compte) Grand\(pluriel) Prix restant\(pluriel)"
    }
}
