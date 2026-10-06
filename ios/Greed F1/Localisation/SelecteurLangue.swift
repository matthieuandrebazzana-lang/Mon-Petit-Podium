import SwiftUI

/// Sélecteur FR / EN — **un seul propriétaire**, monté sur `LandingView`, `ConnexionView`
/// et dans les paramètres de `ProfilView`.
///
/// Deux segments dans une capsule, chacun un drapeau (emoji natif, ``Langue/drapeau``) et
/// un code. **Les deux options restent en couleur pleine, quelle que soit la langue
/// active** : drapeaux entiers, sans désaturation ni opacité réduite, libellés à pleine
/// encre. L'état se lit **uniquement à la pastille** :
///
/// - **actif** — pastille pleine `primaire` (`#800111`), encre blanche (**10,88:1**) ;
/// - **inactif** — le fond neutre de la capsule (``Color/fondSegmentInactif``), encre
///   ``Color/encreSegmentInactif`` (`secondaire` plein).
///
/// Taille : segments de 80 × 40, drapeau à 20 pt, code à ``Font/segment`` (14 pt, 500) —
/// assez pour être trouvé d'un coup d'œil sur l'accueil, sans dépasser le poids d'un
/// bouton secondaire. Ces choix tiennent sur les deux fonds où le sélecteur est posé — le
/// beige de l'accueil et de la connexion, le blanc du bloc Paramètres — sans que l'écran
/// choisisse son encre.
///
/// Au changement, la pastille glisse sur la courbe de déplacement (200 ms), et les encres
/// des libellés s'échangent dans la même transaction : un seul geste, une seule animation.
/// Elle s'interrompt — un second appui en plein vol repart de la position affichée.
/// **Sous mouvement réduit**, rien ne glisse : la pastille passe d'un segment à l'autre en
/// fondu.
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
        .padding(4)
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
            HStack(spacing: 7) {
                Text(langue.drapeau)
                    .font(.system(size: 20))
                Text(langue.code)
                    .font(.segment)
                    .tracking(Tracking.segment)
                    .foregroundColor(actif ? .encreSurAplat : .encreSegmentInactif)
            }
            .frame(width: 80, height: 40)
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
            // 48 pt de haut de zone tactile : le segment de 80 × 40 plus le liseré de la capsule.
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .padding(.vertical, -4)
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(langue == .fr ? "Français" : "English")
        .accessibilityAddTraits(actif ? .isSelected : [])
    }
}
