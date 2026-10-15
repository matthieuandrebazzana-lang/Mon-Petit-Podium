import WidgetKit
import SwiftUI

/// Le widget « Classement » — petit, moyen et grand formats de l'écran d'accueil.
/// Configurable (``IntentionClassement``) : le championnat, la liste ou la piste au petit
/// format, les deux, la liste ou la piste au moyen, les deux ou la piste seule au grand.
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    ClassementWidget()
} timeline: {
    FournisseurClassement.exemple(.classement)
    FournisseurClassement.exemple(.classement, moyen: .classement)
    FournisseurClassement.exemple(.classement, moyen: .piste)
}

#Preview(as: .systemLarge) {
    ClassementWidget()
} timeline: {
    FournisseurClassement.exemple(.classement)
    FournisseurClassement.exemple(.classement, grand: .pisteSeule)
    EntreeClassement.neutre()
}
