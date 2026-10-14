import WidgetKit
import SwiftUI

/// Le widget « Classement » — petit et grand formats de l'écran d'accueil. Configurable
/// (``IntentionClassement``) : le championnat, et la liste ou la piste au petit format.
/// Ses données viennent de l'App Group et de `GET /widget/championnats/{id}/classement`,
/// avec le jeton widget — jamais la session (``FournisseurClassement``).
struct ClassementWidget: Widget {

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: DonneesWidget.typeWidgetClassement,
                               intent: IntentionClassement.self,
                               provider: FournisseurClassement()) { entree in
            VueClassement(entree: entree)
                .containerBackground(Color.fondPrincipal, for: .widget)
        }
        // Lus à l'installation, dans la langue de l'app connue à cet instant.
        .configurationDisplayName(t("widgetClassement.nom"))
        .description(t("widgetClassement.description"))
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

#Preview(as: .systemLarge) {
    ClassementWidget()
} timeline: {
    FournisseurClassement.exemple(.classement)
    EntreeClassement.neutre()
}
