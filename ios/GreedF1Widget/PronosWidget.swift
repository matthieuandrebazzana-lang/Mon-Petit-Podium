import WidgetKit
import SwiftUI

/// Le widget « Mes pronos » — petit et moyen formats de l'écran d'accueil. Statique : aucun
/// réglage. Ses données viennent de `GET /widget/pronos`, avec le jeton widget — jamais la
/// session (``FournisseurPronos``, `docs/decisions.md` §30).
struct PronosWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DonneesWidget.typeWidgetPronos, provider: FournisseurPronos()) { entree in
            VuePronos(entree: entree)
                .containerBackground(for: .widget) { FondPronos(grandPrix: entree.grandPrix) }
        }
        // Lus à l'installation, dans la langue de l'app connue à cet instant.
        .configurationDisplayName(t("widgetPronos.nom"))
        .description(t("widgetPronos.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    PronosWidget()
} timeline: {
    TimelinePronos.exemple(.ouverts)
    TimelinePronos.exemple(.ouverts, avecPronos: false)
    TimelinePronos.exemple(.resultats)
    EntreePronos.vide()
}

#Preview(as: .systemSmall) {
    PronosWidget()
} timeline: {
    TimelinePronos.exemple(.ouverts)
    TimelinePronos.exemple(.ouverts, avecPronos: false)
    TimelinePronos.exemple(.resultats)
    EntreePronos.vide()
}
