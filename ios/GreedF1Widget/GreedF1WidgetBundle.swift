import WidgetKit
import SwiftUI

@main
struct GreedF1WidgetBundle: WidgetBundle {

    /// La langue de l'app avant toute lecture de ``t(_:)`` — le nom et la description de la
    /// galerie compris. Le téléphone n'a pas son mot à dire (``DonneesWidget``).
    init() {
        if let langue = DonneesWidget.langue { LanguageManager.shared.imposer(langue) }
    }

    var body: some Widget {
        GreedF1Widget()
        ClassementWidget()
        // « Mes pronos » est DÉSACTIVÉ (iOS 0.57.2, avant la soumission App Store) : posé sur
        // l'écran d'accueil, il s'affichait entièrement blanc, et la cause n'a pas été
        // trouvée. Son code reste en place (``PronosWidget``, ``FournisseurPronos``,
        // `VuesPronos.swift`, ``DonneesWidget/PronosWidget``) ; la route `/widget/pronos`
        // aussi. Pour le réactiver : décommenter la ligne ci-dessous ET repasser
        // ``DonneesWidget/widgetPronosActif`` à `true` (rechargements côté app).
        // PronosWidget()
    }
}
