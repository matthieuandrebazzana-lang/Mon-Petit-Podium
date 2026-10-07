import SwiftUI
import Pow

/// Effets Pow — **le seul fichier qui importe Pow**.
///
/// Pow ne lit pas `accessibilityReduceMotion` : chaque effet est donc enveloppé ici, avec
/// son repli, et les écrans n'appellent que ces trois modificateurs. Sous mouvement réduit,
/// **aucun ne joue** — le changement d'état qu'ils soulignent (étoile pleine, carte ambre,
/// bouton qui passe au récapitulatif) se voit déjà sans eux.
///
/// > **Un effet Pow ne part que d'un geste.** Les trois sont des effets de changement : ils
/// > ne jouent pas à l'apparition, seulement quand leur déclencheur change. Le déclencheur
/// > est un compteur ou un état incrémenté **dans l'action du bouton**, jamais dans un
/// > `.task` ni un `onAppear`.
extension View {

    /// **Éclat** — l'anneau et la gerbe de particules de `movingParts.pop`, autour de la vue.
    ///
    /// La transition de Pow fait entrer son contenu **depuis `scale(0)`**, ce que
    /// ``Mouvement`` interdit : elle est donc posée sur un calque vide de `diametre` pt
    /// centré sur la vue, inséré à chaque incrément de `declencheur`. La vue elle-même ne
    /// disparaît jamais ; si elle doit rebondir, elle le fait elle-même
    /// (``EtoileParisBonus``, `keyframeAnimator`).
    func eclatPop(_ declencheur: Int, couleur: Color, diametre: CGFloat) -> some View {
        overlay {
            EclatPop(declencheur: declencheur, couleur: couleur, diametre: diametre)
        }
    }

    /// **Confettis discrets** — la gerbe de `spray`, qui monte au-dessus de la vue, en
    /// `primaire` et `encrePrimaire`. Pow y joint son propre motif haptique : il ne part
    /// que sur un geste, comme l'effet.
    func confettiDiscret(_ declencheur: Int) -> some View {
        modifier(ConfettiDiscret(declencheur: declencheur))
    }

    /// **Pulsation** — une forme `primaire` qui s'élargit derrière la vue et s'efface : la
    /// carte qui vient d'être choisie le dit une fois.
    func pulseSelection<Forme: InsettableShape>(_ declencheur: Int, forme: Forme) -> some View {
        modifier(PulseSelection(declencheur: declencheur, forme: forme))
    }
}

private struct EclatPop: View {

    let declencheur: Int
    let couleur: Color
    let diametre: CGFloat

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    var body: some View {
        ZStack {
            // Rien au repos : le calque n'existe qu'après le premier geste, et un nouvel
            // identifiant le réinsère — donc rejoue la transition — à chaque incrément.
            if declencheur > 0 && !mouvementReduit {
                Color.clear
                    .frame(width: diametre, height: diametre)
                    .id(declencheur)
                    .transition(.movingParts.pop(couleur))
            }
        }
        .animation(.linear(duration: Mouvement.dureeEclat), value: declencheur)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ConfettiDiscret: ViewModifier {

    let declencheur: Int

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    func body(content: Content) -> some View {
        content.changeEffect(
            .spray(origin: .center) {
                // Pow tire au hasard parmi ces symboles : deux encres, deux tailles.
                Circle().fill(Color.primaire).frame(width: 7, height: 7)
                Circle().fill(Color.encrePrimaire).frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1).fill(Color.primaire).frame(width: 4, height: 8)
                RoundedRectangle(cornerRadius: 1).fill(Color.encrePrimaire).frame(width: 6, height: 3)
            },
            value: declencheur,
            isEnabled: !mouvementReduit)
    }
}

private struct PulseSelection<Forme: InsettableShape>: ViewModifier {

    let declencheur: Int
    let forme: Forme

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    func body(content: Content) -> some View {
        content.changeEffect(
            .pulse(shape: forme, style: Color.primaire, drawingMode: .stroke, count: 1),
            value: declencheur,
            isEnabled: !mouvementReduit)
    }
}
