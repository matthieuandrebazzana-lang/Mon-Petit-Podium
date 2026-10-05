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

    /// Assombrissement des cartes **du dessous** de la pile des championnats — un noir à
    /// 18 %, posé sur toute la carte.
    ///
    /// > Il dit la profondeur : la carte du dessus garde sa teinte pleine, celles qu'elle
    /// > recouvre reculent d'un cran. Il ne coûte rien au contraste, il en ajoute — le
    /// > blanc et ``Color/encreSecondaire`` sont mesurés sur la teinte nue.
    static let voilePile: Double = 0.18

    /// Le damier des cartes de pronostic — un filigrane, plus bas encore que
    /// ``damierDoux`` : la carte porte déjà une teinte de verdict.
    static let damierPronostic: Double = 0.06

    /// **Le repli sans damier** des cartes de pronostic : `false` le retire partout d'un
    /// coup, si le rendu se révèle trop chargé sur iPhone réel.
    static let damierSurPronostics = true

    /// Le damier **en filigrane d'un écran clair** — 5 %, au milieu de la fourchette de
    /// 4 à 6 % : il se devine sans se lire. Posé sur le détail d'un championnat, et nulle
    /// part ailleurs pour l'instant : le fond du sélecteur Classement / Piste, les trois
    /// lignes du podium, la carte « Résultats par Grand Prix ».
    ///
    /// > Mesuré au pire pixel : `grisSecondaire` tient **4,83:1** sur le podium (damier
    /// > `primaire`), **4,98:1** sur la carte (damier gris) ; `secondaire` **7,56:1** dans
    /// > le sélecteur.
    static let damierFiligrane: Double = 0.05

    /// Teinte d'une carte de pronostic **gagné** — `vertSauge` à 7 % sur le blanc.
    ///
    /// > Mesuré, damier compris : le marché en `grisSecondaire` y tient **4,51:1** au pire
    /// > pixel. Le vert sauge, lui, n'y tient plus que **4,12:1** — d'où le verdict en
    /// > pastille pleine (blanc sur vert, 4,86:1) et non en texte vert.
    static let teinteGagne: Double = 0.07

    /// Teinte d'une carte de pronostic **perdu** — `primaire` à 4 %. Le bordeaux est plus
    /// sombre que le vert : à 5 % le gris du marché tombait à 4,47:1 sur le damier.
    static let teintePerdu: Double = 0.04
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
///
/// > **Le motif est posé en `overlay` sur un `Color.clear`, jamais nu.** Nu, un
/// > `scaledToFill` impose sa *taille de remplissage* à la `ZStack` qui l'accueille :
/// > une carte de 361 × 120 réclamait 280 pt de haut, et le fond débordait de 80 pt
/// > au-dessus et en dessous. Le `clipShape` de la carte le cachait à l'œil, **pas au
/// > doigt** : la carte suivante, peinte par-dessus, captait le tap du bas de la
/// > précédente — « Créer un championnat » ouvrait « Rejoindre ». Un `Color.clear` prend
/// > exactement la place qu'on lui propose, et le `clipped()` rogne le motif à ce cadre.
struct Damier: View {

    /// `Materiau.damier` sur un aplat de couleur, `Materiau.damierDoux` sur du blanc.
    let opacite: Double

    /// L'encre du motif. `nil` garde le gris de la texture source (`#616160`) ; une
    /// couleur passe l'image en `template` et la peint entièrement de cette encre.
    var encre: Color? = nil

    var body: some View {
        Color.clear
            .overlay {
                if let encre {
                    Image("texture-hexa")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFill()
                        .foregroundStyle(encre)
                } else {
                    Image("texture-hexa")
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
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
