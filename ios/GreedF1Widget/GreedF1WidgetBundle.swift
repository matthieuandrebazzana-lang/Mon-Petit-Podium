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
    }
}
