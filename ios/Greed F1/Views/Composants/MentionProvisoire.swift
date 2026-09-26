import SwiftUI

/// Le statut des résultats d'un Grand Prix, et celui d'un pronostic — **un seul
/// propriétaire** des deux questions que plusieurs écrans posent de la même façon.
/// Pendant de `frontend/src/lib/resultats.js`.
///
/// - `grands_prix.statut_resultats` (migration 25) : `provisoire` dès la publication du
///   classement, `definitif` après la relecture d'OpenF1, 24 h après la course. Les points
///   d'un GP provisoire comptent déjà partout ; ils peuvent encore bouger une fois.
/// - `pronostics.statut_evaluation` (migration 24) : `non_evaluable` quand aucun évaluateur
///   ne porte le marché. `points_gagnes` est nul dans les deux cas, il ne suffit donc pas
///   à distinguer « en attente » de « non évaluable ».
enum StatutResultats {
    static let provisoire = "provisoire"
    static let nonEvaluable = "non_evaluable"

    /// Le mot affiché, partout le même.
    static let mention = "Provisoire"
    /// Ce qu'il veut dire, pour VoiceOver.
    static let detail = "Résultats provisoires : ils deviennent définitifs 24 heures après la course."

    static func estProvisoire(_ statut: String?) -> Bool { statut == provisoire }
    static func estNonEvaluable(_ statut: String?) -> Bool { statut == nonEvaluable }
}

/// La mention « Provisoire » posée sur des résultats pas encore définitifs.
///
/// **Discrète par construction** : le corps et l'encre du label de la surface qui la porte
/// (`labelSm`, `grisSecondaire` par défaut — 4,71:1 sur le beige, davantage sur le blanc).
/// Elle ne choisit donc aucune encre nouvelle, et **ne s'anime pas** : c'est un statut, pas
/// un évènement (portier `/animate`, aucun jeton de mouvement ajouté).
struct MentionProvisoire: View {

    var encre: Color = .grisSecondaire

    var body: some View {
        Text(StatutResultats.mention)
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(encre)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(StatutResultats.detail)
    }
}
