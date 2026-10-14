import WidgetKit
import SwiftUI

/// Le widget « Prochain GP » — écran d'accueil (petit, moyen) et écran verrouillé
/// (rectangulaire). Statique : aucune configuration, aucune session ; ses données viennent
/// de l'App Group (``DonneesWidget``) et de `GET /calendrier` (``FournisseurProchainGP``).
struct GreedF1Widget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DonneesWidget.typeWidget, provider: FournisseurProchainGP()) { entree in
            VueProchainGP(entree: entree)
                .containerBackground(for: .widget) {
                    FondProchainGP(grandPrix: entree.grandPrix)
                }
        }
        // Lus à l'installation, dans la langue de l'app connue à cet instant.
        .configurationDisplayName(t("widget.nom"))
        .description(t("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemMedium) {
    GreedF1Widget()
} timeline: {
    TimelineProchainGP.exemple
    EntreeProchainGP.neutre()
}
