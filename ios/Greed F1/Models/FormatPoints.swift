import Foundation

/// Le nombre de points, **habillé à un seul endroit** — le pendant iOS de
/// `frontend/src/lib/format.js`, dont le CLAUDE.md dit qu'il est « le seul endroit qui
/// habille un nombre de points ».
///
/// > **Pas de séparateur de milliers, et ce n'est pas un oubli.** Interpolé tel quel dans
/// > un `Text("\(points)")`, SwiftUI passe par `LocalizedStringKey` et applique la locale :
/// > « 5 000 » là où la version web écrit « 5000 ». Deux applications qui montrent la même
/// > cote ne peuvent pas l'écrire de deux façons.
extension Int {
    var enPoints: String { String(self) }
}

/// Trois états, jamais deux (§6.1) : une valeur, **ou** « Cote retirée » quand l'issue a
/// disparu du Grand Prix depuis l'épinglage. **Jamais un zéro inventé.**
func formaterPoints(_ points: Int?) -> String {
    guard let points else { return t("points.coteRetiree") }
    return t("points.valeur", points.enPoints)
}
