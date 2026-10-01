import SwiftUI

/// Sélecteur FR / EN — **un seul propriétaire**, monté sur `LandingView`, `ConnexionView`
/// et dans les paramètres de `ProfilView`.
///
/// Deux segments dans une capsule, la pastille glisse de l'un à l'autre. Elle est en
/// `primaire` avec l'encre blanche (**10,88:1**) ; le segment inactif est en `secondaire`,
/// qui tient sur le beige comme sur le blanc. Ce choix tient donc sur les deux fonds où le
/// sélecteur est posé, sans que l'écran ait à choisir son encre.
///
/// Le glissement suit la courbe de déplacement, sous les 300 ms, et s'interrompt : un
/// second appui en plein vol repart de la position affichée. Sous mouvement réduit, la
/// pastille change de place sans glisser.
struct SelecteurLangue: View {

    @EnvironmentObject private var langues: LanguageManager
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit
    @Namespace private var pastille

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Langue.allCases) { langue in
                segment(langue)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.secondaire.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("langue.titre"))
    }

    private func segment(_ langue: Langue) -> some View {
        let actif = langues.langue == langue
        return Button {
            withAnimation(mouvementReduit ? nil : Mouvement.deplacement(Mouvement.passageEcran)) {
                langues.choisir(langue)
            }
        } label: {
            Text(langue.code)
                .font(.label)
                .tracking(Tracking.label)
                .foregroundColor(actif ? .white : .secondaire)
                .frame(width: 40, height: 28)
                .background {
                    if actif {
                        Capsule()
                            .fill(Color.primaire)
                            .matchedGeometryEffect(id: "pastille", in: pastille)
                    }
                }
                // 44 × 44 pt de zone tactile autour d'un segment visuel de 40 × 28.
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
                .padding(.vertical, -8)
                .padding(.horizontal, -2)
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(langue == .fr ? "Français" : "English")
        .accessibilityAddTraits(actif ? .isSelected : [])
    }
}
