import SwiftUI

/// Matériaux — seul propriétaire des deux calques décoratifs du design system
/// (`docs/design-system.md`, « matériaux »).
///
/// Ils ne portent aucun sens et ne reçoivent jamais de doigt : les deux sont posés en
/// `allowsHitTesting(false)` et masqués à VoiceOver, exactement comme les
/// `aria-hidden` / `pointer-events-none` de la version web.
///
/// **Un écran ne redessine jamais l'un des deux.** C'est la règle d'`ios/CLAUDE.md` §3 :
/// deux textures écrites séparément divergent au premier ajustement, et le symptôme —
/// une carte au motif un peu plus dense que sa voisine — est de ceux qu'on ne voit pas.
enum Materiau {

    /// Opacité du damier sur un **aplat de couleur**. Mesurée côté web : à 0,15 le motif
    /// ne coûte jamais plus d'un cran de contraste au texte posé dessus.
    static let damier: Double = 0.15

    /// Opacité du damier sur une **carte blanche**, et c'est la moitié.
    ///
    /// > À 0,15 le blanc tombe à `#E7E7E7` : le motif ne se lit plus comme une texture
    /// > mais comme un gris sale, et il dispute le regard au logo et au titre. À 0,075
    /// > (`#F3F3F3`) il est encore là sans dominer.
    static let damierDoux: Double = 0.075
}

// MARK: - Le damier

/// Le damier de `Ressources/texture-hexa.svg` (`assets/06.svg`), en filigrane.
///
/// **`scaledToFill` et non `resizable()` seul** : le motif est dessiné dans un cadrage de
/// 542 × 420, et l'étirer aux proportions d'une carte déformerait chaque chevron. La
/// version web dit la même chose avec `background-size: cover`.
///
/// L'hôte doit porter son propre `clipShape` : sans lui le motif déborde des coins
/// arrondis de la carte.
struct Damier: View {

    /// `Materiau.damier` sur un aplat de couleur, `Materiau.damierDoux` sur du blanc.
    let opacite: Double

    var body: some View {
        Image("texture-hexa")
            .resizable()
            .scaledToFill()
            .opacity(opacite)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - La lumière spéculaire

/// Le galbe de lumière du haut d'un aplat (`lueur-haute`, /apple-design §12).
///
/// > Un aplat plein est une surface morte. Ce galbe très doux lui donne une source
/// > lumineuse, sans jamais se lire comme un dégradé.
///
/// Transposition du `radial-gradient(120% 90% at 50% -25%, …)` de la version web : le
/// centre est au-dessus du bloc, et la lumière s'éteint avant d'en atteindre le bas.
///
/// **Elle passe TOUJOURS sous le voile d'un drapeau**, jamais au-dessus : elle éclaircit
/// la surface, donc elle joue contre le contraste du texte. Posée par-dessus, elle
/// remonterait la luminance là même où le texte la croise — voir ``ApparenceDrapeau``,
/// dont le calcul l'inclut au lieu de la découvrir à l'écran.
struct LueurHaute: View {

    var body: some View {
        EllipticalGradient(
            stops: [
                .init(color: .white.opacity(0.22), location: 0),
                .init(color: .white.opacity(0.06), location: 0.45),
                .init(color: .white.opacity(0), location: 0.70)
            ],
            center: UnitPoint(x: 0.5, y: -0.25),
            startRadiusFraction: 0,
            endRadiusFraction: 0.6
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
