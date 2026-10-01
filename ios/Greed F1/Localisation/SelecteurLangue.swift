import SwiftUI

/// Sélecteur FR / EN — **un seul propriétaire**, monté sur `LandingView`, `ConnexionView`
/// et dans les paramètres de `ProfilView`.
///
/// Deux segments dans une capsule, chacun un drapeau (emoji natif, ``Langue/drapeau``) et
/// un code. Les deux états doivent se distinguer d'un coup d'œil :
///
/// - **actif** — pastille pleine `primaire`, encre blanche (**10,88:1**), drapeau entier ;
/// - **inactif** — le fond neutre de la capsule (``Color/fondSegmentInactif``), encre
///   ``Color/encreSegmentInactif`` (**4,94:1** au pire, sur le beige), drapeau à 40 %,
///   désaturé et légèrement réduit.
///
/// > **Le texte inactif n'est atténué qu'à 80 %.** Plus bas il passe sous 4,5:1 (2,47:1 à
/// > 50 %). L'écart entre les états est porté par la pastille et par le drapeau, qui est
/// > graphique et redondant avec le code : lui peut s'effacer franchement.
///
/// Ces choix tiennent sur les deux fonds où le sélecteur est posé — le beige de l'accueil
/// et de la connexion, le blanc du bloc Paramètres — sans que l'écran choisisse son encre.
///
/// Au changement, la pastille glisse sur la courbe de déplacement (200 ms), pendant que
/// drapeaux et encres échangent leur poids dans la même transaction : un seul geste, une
/// seule animation. Elle s'interrompt — un second appui en plein vol repart de la position
/// affichée. **Sous mouvement réduit**, rien ne glisse ni ne change d'échelle : la pastille
/// passe d'un segment à l'autre en fondu, et les opacités suivent.
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
        .background(Capsule().fill(Color.fondSegmentInactif))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("langue.titre"))
    }

    private var animation: Animation {
        mouvementReduit
            ? Mouvement.entree(Mouvement.echangeIcone)
            : Mouvement.deplacement(Mouvement.passageEcran)
    }

    private func segment(_ langue: Langue) -> some View {
        let actif = langues.langue == langue
        return Button {
            guard !actif else { return }
            withAnimation(animation) {
                langues.choisir(langue)
            }
        } label: {
            HStack(spacing: 5) {
                Text(langue.drapeau)
                    .font(.system(size: 15))
                    .saturation(actif ? 1 : 0)
                    .opacity(actif ? 1 : 0.4)
                    .scaleEffect(actif || mouvementReduit ? 1 : 0.88)
                Text(langue.code)
                    .font(.label)
                    .tracking(Tracking.label)
                    .foregroundColor(actif ? .white : .encreSegmentInactif)
            }
            .frame(width: 62, height: 32)
            .background {
                if actif {
                    if mouvementReduit {
                        Capsule()
                            .fill(Color.primaire)
                            .transition(.opacity)
                    } else {
                        Capsule()
                            .fill(Color.primaire)
                            .matchedGeometryEffect(id: "pastille", in: pastille)
                    }
                }
            }
            // 44 pt de haut de zone tactile autour d'un segment visuel de 62 × 32.
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .padding(.vertical, -6)
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(langue == .fr ? "Français" : "English")
        .accessibilityAddTraits(actif ? .isSelected : [])
    }
}
