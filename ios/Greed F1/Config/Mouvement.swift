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

    /// **Bascule clair ↔ sombre de toute l'app** (``ThemeManager``) — un fondu croisé de la
    /// fenêtre, courbe de sortie.
    ///
    /// > Un geste rare, donc animé ; un fondu, jamais un déplacement — il n'empêche qu'un
    /// > saut brutal de luminosité sur tout l'écran (/apple-design §14). C'est un fondu,
    /// > donc il reste **sous mouvement réduit** : il ne déplace rien.
    static let basculeApparence: TimeInterval = 0.25

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

    /// **Le vrai contenu qui remplace une silhouette de chargement**
    /// (``View/fonduChargement(_:)``, ``View/arriveeEnCascade(rang:)``) : la silhouette sort
    /// en fondu, le contenu entre en fondu et remonte de ``glissementArrivee``.
    ///
    /// > Plus long que ``passageEcran`` : ce n'est pas la réponse à un geste, c'est le
    /// > contenu qu'on attendait — il s'installe, au plafond des 300 ms.
    static let arriveeContenu: TimeInterval = 0.30

    /// Le glissement de cette entrée, de bas en haut.
    static let glissementArrivee: CGFloat = 12

    /// **Décalage entre deux éléments du contenu arrivé** — plus serré que ``decalage`` :
    /// une liste entière attend derrière, il faut qu'elle soit lue vite.
    static let decalageArrivee: TimeInterval = 0.05

    /// Nombre d'éléments qui se décalent ; au-delà, tous partent avec le dernier.
    static let cascadeArrivee = 5

    /// **Période du balayage d'une silhouette de chargement** (``SkeletonView``) — une
    /// bande lumineuse qui traverse l'écran, linéairement, en boucle.
    ///
    /// > La seule valeur du vocabulaire au-delà de 300 ms, et ce n'est pas une
    /// > contradiction : le plafond vaut pour une réponse à un geste, ceci est un mouvement
    /// > **continu** qui dit « ça charge ». Assez vif pour ne pas traîner (un balayage
    /// > lent fait paraître l'attente plus longue), loin de l'oscillation à 0,2 Hz que
    /// > /apple-design §14 déconseille. Absent sous mouvement réduit.
    static let balayageSquelette: TimeInterval = 1.4

    /// Accordéon — **l'ouverture est plus lente que la fermeture** (240 / 170 ms) : on
    /// regarde ce qui arrive, on ne regarde pas ce qui s'en va.
    static let accordeonOuverture: TimeInterval = 0.24
    static let accordeonFermeture: TimeInterval = 0.17

    // MARK: Micro-animations (0.53.0)

    /// **Décalage entre deux lignes du classement d'un championnat** — 40 ms, plus serré
    /// que ``decalageArrivee`` : un classement compte jusqu'à vingt lignes, et la dernière
    /// doit être partie avant que l'œil ait fini de lire la première. Sur
    /// ``cascadeClassement`` lignes au plus, comme ``cascadeArrivee``.
    static let decalageClassement: TimeInterval = 0.04
    static let cascadeClassement = 10

    /// **Apparition du widget du Grand Prix de l'accueil** — `scale(0.95)` + fondu vers 1,
    /// sur un ressort légèrement sous-amorti.
    ///
    /// > **Écart assumé à la règle de ``relachement``** (pas de ressort sans geste) : la
    /// > demande l'impose, et l'amplitude le rend inoffensif — 0,8 d'amortissement sur 5 %
    /// > d'échelle dépasse de moins d'un point sur une carte de 343 pt. Sous mouvement
    /// > réduit : le fondu seul.
    static let apparitionWidget = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let echelleApparition: CGFloat = 0.95

    /// **Durée de `movingParts.pop`** — fixée par Pow (1,2 s, linéaire), recopiée ici
    /// pour que l'animation qui l'insère dure autant que lui.
    ///
    /// > Au-delà du plafond de 300 ms, et ce n'est pas une contradiction : l'éclat est un
    /// > décor posé **par-dessus** une interface qui a déjà répondu, il ne retarde rien.
    static let dureeEclat: TimeInterval = 1.2

    /// **Le temps laissé à l'éclat de la validation avant le récapitulatif** — 450 ms :
    /// l'anneau et la gerbe sont lancés et lisibles, le passage d'écran part pendant la
    /// retombée. Le bouton reste éteint pendant ce temps (les pronostics sont déjà écrits),
    /// le retour arrière reste libre. **Zéro sous mouvement réduit** : rien ne joue, rien
    /// n'attend.
    static let pauseCelebration: TimeInterval = 0.45

    /// **Rebond de l'étoile de favori** — 1 → 1,3 → 1 : 120 ms de montée sur la courbe de
    /// sortie, puis le ressort de ``relachement`` qui la ramène. Le geste a précédé :
    /// le ressort est à sa place.
    static let echelleRebondEtoile: CGFloat = 1.3
    static let monteeRebondEtoile: TimeInterval = 0.12
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
        /// Les trois boutons principaux du parcours — « Valider mes pronos », « Créer »,
        /// « Rejoindre » — `0.96` : la compression la plus franche, réservée à l'action qui
        /// conclut un écran. Posée par ``View/boutonPressable()``.
        case principal
        /// Cartes et blocs pleine largeur — `0.985`.
        case grandeSurface

        var echelle: CGFloat {
            switch self {
            case .bouton: return 0.97
            case .principal: return 0.96
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

// MARK: - Bouton pressable

/// **Le retour d'appui des boutons principaux** — « Valider mes pronos », « Créer un
/// championnat », « Rejoindre ».
///
/// Un `ViewModifier` ne voit pas l'état d'appui d'un `Button` : seul un `ButtonStyle` le
/// reçoit. `BoutonPressable` pose donc ``StyleAppui`` à l'amplitude ``StyleAppui/Amplitude/principal``
/// — `scale(0.96)`, enfoncement en ``Mouvement/enfoncement``, relâchement sur
/// ``Mouvement/relachement`` (`spring(response: 0.3, dampingFraction: 0.6)`) — et reste ainsi
/// le **seul propriétaire** du mouvement d'un appui. Mouvement réduit : l'opacité seule,
/// comme tout ``StyleAppui``.
struct BoutonPressable: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(StyleAppui(.principal))
    }
}

extension View {
    /// Voir ``BoutonPressable``. Se pose sur le `Button`, à la place de `.buttonStyle(_:)`.
    func boutonPressable() -> some View {
        modifier(BoutonPressable())
    }
}
