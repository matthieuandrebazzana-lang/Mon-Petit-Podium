import SwiftUI

/// Mouvement — seul propriétaire des courbes et des durées (`docs/swift-app.md` §4.10).
///
/// La règle du projet est d'**étendre** ce vocabulaire, jamais de le forker : un écran ne
/// déclare pas sa propre courbe.
///
/// Les valeurs imposées, qui valent aussi en natif : jamais `scale(0)` — une chose doit
/// avoir une silhouette avant d'être remplie ; jamais d'`easeIn` sur une interface ;
/// **sous les 300 ms** ; et le repli `accessibilityReduceMotion` livré **avec**
/// l'animation, jamais après.
enum Mouvement {

    /// Entrées et sorties — `cubic-bezier(0.22, 1, 0.36, 1)`.
    static func entree(_ duree: TimeInterval) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duree)
    }

    /// Déplacements — `cubic-bezier(0.77, 0, 0.175, 1)`.
    static func deplacement(_ duree: TimeInterval) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duree)
    }

    /// Enfoncement d'un appui : immédiat, 100 ms — c'est la réponse au doigt.
    static let enfoncement = Animation.easeOut(duration: 0.1)

    /// Relâchement d'un appui : le ressort de `--ease-ressort`, qui dépasse légèrement.
    ///
    /// > **Le ressort ne s'emploie QUE là où un geste a précédé le mouvement**, jamais sur
    /// > une apparition automatique, où le dépassement se lirait comme une erreur.
    static let relachement = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// Déploiement d'une carte en plein écran — la carte du carrousel qui devient le détail
    /// de son Grand Prix (`matchedGeometryEffect`).
    ///
    /// > **Un ressort critique, pas une courbe.** La fermeture peut arriver en plein
    /// > déploiement : un ressort repart de la position et de la vitesse affichées, là où
    /// > une courbe à durée fixe repartirait de zéro. **Aucun dépassement** (amortissement
    /// > 1) : ``relachement`` rebondit, et un écran entier qui rebondit se lit comme une
    /// > erreur. Le repli est plus vif que le déploiement : on regarde ce qui arrive, pas
    /// > ce qui s'en va.
    static let deploiement = Animation.spring(response: 0.34, dampingFraction: 1)
    static let repli = Animation.spring(response: 0.28, dampingFraction: 1)

    /// **La pastille d'un sélecteur segmenté qui glisse d'un segment à l'autre**
    /// (``SelecteurSegmente``, `matchedGeometryEffect`).
    ///
    /// > **Un ressort critique, pas une courbe** : un second appui en plein vol repart de la
    /// > position *et de la vitesse* affichées — une courbe à durée fixe repartirait de zéro
    /// > et marquerait un à-coup. **Aucun dépassement** : un appui n'a pas d'élan à
    /// > restituer (/apple-design §4), et un segment se bascule trop souvent pour rebondir.
    static let glissement = Animation.spring(response: 0.3, dampingFraction: 1)

    /// Échange d'icône — étoile de favori, icônes de nav, interrupteur.
    static let echangeIcone: TimeInterval = 0.18

    /// **Décalage entre deux entrées voisines** — le « stagger » d'une série qui apparaît
    /// d'un coup.
    ///
    /// > Il existe parce que le vocabulaire n'avait pas de valeur pour ça, et que faire
    /// > entrer huit voitures **exactement ensemble** ne dit rien : c'est le décalage qui
    /// > les fait lire une par une. Il reste sous le seuil où l'œil compte les éléments —
    /// > à 60 ms, huit voitures sont toutes lancées en moins d'une demi-seconde.
    ///
    /// La version web dit la même chose avec `--voiture-stagger`.
    static let decalage: TimeInterval = 0.06

    /// **Réordonnancement de la pile des championnats après un tap** — un ressort
    /// critique, sans dépassement : rien n'a été lancé, rien ne doit rebondir.
    static let pile = Animation.spring(response: 0.38, dampingFraction: 1)

    /// **Le même réordonnancement après un swipe** : le doigt a lancé la carte, le ressort
    /// garde un léger dépassement (/apple-design §4, amortissement 0,8 sur un geste
    /// porteur d'élan). Il repart de la position où le doigt a lâché la carte, et sa
    /// réponse courte (0,35 s) aimante la carte en place sans traîner derrière le geste.
    static let pileLancee = Animation.spring(response: 0.35, dampingFraction: 0.8)

    /// Les relais rapides de la pile des championnats : la face pleine d'une carte qui
    /// cède la place à sa bande, et l'ombre d'une carte arrivée au fond qui revient une
    /// fois celle-ci passée derrière ses voisines.
    static let fonduPile: TimeInterval = 0.14

    /// Passage d'écran.
    static let passageEcran: TimeInterval = 0.20

    /// Accordéon — **l'ouverture est plus lente que la fermeture** (240 / 170 ms) : on
    /// regarde ce qui arrive, on ne regarde pas ce qui s'en va.
    static let accordeonOuverture: TimeInterval = 0.24
    static let accordeonFermeture: TimeInterval = 0.17
}

// MARK: - Retour d'appui

/// Retour d'appui — **seul propriétaire du mouvement d'un élément pressable**.
///
/// > **Le retour d'appui a DEUX courbes.** L'enfoncement est immédiat (100 ms, `easeOut`).
/// > Le **relâchement** remonte sur le ressort et dépasse légèrement. Une courbe unique
/// > donne l'un ou l'autre, jamais les deux.
///
/// > **Deux amplitudes** : `0.97` pour les boutons, `0.985` pour les grandes surfaces —
/// > 3 % sur une carte pleine largeur déplacent une dizaine de points, et l'appui devient
/// > une secousse.
///
/// **Mouvement réduit ≠ pas de retour.** Sous `accessibilityReduceMotion`, l'échelle
/// disparaît — c'est un déplacement — mais l'opacité reste : l'appui doit se voir.
struct StyleAppui: ButtonStyle {

    enum Amplitude {
        /// Boutons — `0.97`.
        case bouton
        /// Cartes et blocs pleine largeur — `0.985`.
        case grandeSurface

        var echelle: CGFloat {
            switch self {
            case .bouton: return 0.97
            case .grandeSurface: return 0.985
            }
        }
    }

    private let amplitude: Amplitude

    init(_ amplitude: Amplitude) {
        self.amplitude = amplitude
    }

    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration, echelle: amplitude.echelle)
    }

    /// `ButtonStyle` n'est pas une `View` : un `@Environment` déclaré directement dessus
    /// ne se rafraîchit pas. Le corps réel est donc une vue à part, qui le lit, elle.
    private struct Corps: View {

        let configuration: ButtonStyleConfiguration
        let echelle: CGFloat

        @Environment(\.accessibilityReduceMotion) private var mouvementReduit

        var body: some View {
            configuration.label
                .scaleEffect(mouvementReduit ? 1 : (configuration.isPressed ? echelle : 1))
                .opacity(configuration.isPressed && mouvementReduit ? 0.82 : 1)
                .animation(animation, value: configuration.isPressed)
        }

        /// L'animation est relue à chaque changement de `isPressed` : la courbe
        /// d'enfoncement et celle de relâchement sortent donc de la même expression.
        private var animation: Animation {
            if mouvementReduit {
                return Mouvement.enfoncement
            }
            return configuration.isPressed ? Mouvement.enfoncement : Mouvement.relachement
        }
    }
}
