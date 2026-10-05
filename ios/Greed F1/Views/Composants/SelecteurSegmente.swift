import SwiftUI

/// Sélecteur segmenté pleine largeur — « deux vues du même objet » (Classement / Piste).
///
/// **Le même vocabulaire que ``SelecteurLangue``**, sans en être une copie : les encres et
/// le fond viennent des jetons qu'il partage avec lui (``Color/fondSegmentInactif``,
/// ``Color/encreSegmentInactif``), l'état se lit **à la pastille** seule :
///
/// - **actif** — pastille pleine `primaire` (`#800111`), encre blanche (**10,88:1**) ;
/// - **inactif** — fond neutre, encre `secondaire` pleine (**7,56:1** au pire pixel du
///   damier, mesuré).
///
/// > Il remplace le `Picker(.segmented)` natif : sous iOS 26 celui-ci peignait un texte
/// > blanc sur un gris clair, presque illisible sur le beige, et ne se laisse pas teinter.
///
/// Le fond porte un damier ``Materiau/damierFiligrane`` en `secondaire` — sous la pastille
/// rien ne transparaît, elle est opaque.
///
/// Au changement, la pastille glisse sur la courbe de déplacement (200 ms) — le glissement
/// du contrôle natif qu'il remplace —, et s'interrompt : un second appui en plein vol
/// repart de la position affichée. **Sous mouvement réduit**, fondu.
struct SelecteurSegmente<Valeur: Hashable>: View {

    let titre: String
    let options: [(valeur: Valeur, libelle: String)]
    @Binding var selection: Valeur

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit
    @Namespace private var pastille

    /// Hauteur d'un segment ; la capsule ajoute 3 pt de liseré de chaque côté (42 pt), et
    /// la zone tactile est portée à 48 pt.
    private let hauteur: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.valeur) { option in
                segment(option.valeur, libelle: option.libelle)
            }
        }
        .padding(3)
        .background {
            ZStack {
                Color.fondSegmentInactif
                Damier(opacite: Materiau.damierFiligrane, encre: .secondaire)
            }
            .clipShape(Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(titre)
    }

    private var animation: Animation {
        mouvementReduit
            ? Mouvement.entree(Mouvement.echangeIcone)
            : Mouvement.deplacement(Mouvement.passageEcran)
    }

    private func segment(_ valeur: Valeur, libelle: String) -> some View {
        let actif = selection == valeur
        return Button {
            guard !actif else { return }
            withAnimation(animation) { selection = valeur }
        } label: {
            Text(libelle)
                .font(.segment)
                .tracking(Tracking.segment)
                .foregroundColor(actif ? .white : .encreSegmentInactif)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: hauteur)
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
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .padding(.vertical, -6)
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityAddTraits(actif ? .isSelected : [])
    }
}
