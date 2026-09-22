import SwiftUI

/// Palette du design system (`docs/design-system.md` §1).
/// Un seul propriétaire pour chaque couleur : les écrans ne choisissent jamais leur encre.
extension Color {

    /// Principal — rouge profond `#800111`. Blanc dessus : **10,88:1**.
    static let primaire = Color(hexadecimal: 0x800111)

    /// Principal foncé — `#5A000C`.
    static let primaireFonce = Color(hexadecimal: 0x5A000C)

    /// Fond de l'app — beige clair `#F5F0EB`.
    static let fondPrincipal = Color(hexadecimal: 0xF5F0EB)

    /// Surfaces et cartes — `#FFFFFF`.
    static let surface = Color.white

    /// Texte — `#1A1A1A`. Sur le fond de l'app : **15,37:1**.
    static let texte = Color(hexadecimal: 0x1A1A1A)

    /// Secondaire (marron) — `#543925`. Sur le fond de l'app : **9,32:1**.
    /// C'est l'encre des textes de second rang posés sur le beige : `texteDoux`
    /// n'y tient que 2,52:1 et ne passe pas le plancher de 4,5:1.
    static let secondaire = Color(hexadecimal: 0x543925)

    /// Texte secondaire — `#999999`. **Réservé aux fonds sombres** : sur le beige comme
    /// sur le blanc il reste sous 3:1.
    static let texteDoux = Color(hexadecimal: 0x999999)

    /// Gris des labels de formulaire (connexion, inscription).
    static let grisSecondaire = Color(hexadecimal: 0x6B6B6B)
}

// MARK: - Teintes de championnat

/// Les six teintes de championnat — palette Pantone sombre (`docs/swift-app.md` §4.4).
///
/// **Elles ne peignent QU'une carte de championnat et l'en-tête de son écran.** Le texte
/// reste blanc sur les six, et c'est mesuré : de **10,35:1** (tomate séchée) à **18,12:1**
/// (minuit). L'encre secondaire à 70 % n'y descend jamais sous **4,97:1**.
extension Color {

    static let azurite      = Color(hexadecimal: 0x1D2941)   // Azurite
    static let mure         = Color(hexadecimal: 0x2A1F21)   // Blackberry Syrup
    static let aubergine    = Color(hexadecimal: 0x301729)   // Aubergine Gleam
    static let terreau      = Color(hexadecimal: 0x54392D)   // Potting Soil
    static let tomateSechee = Color(hexadecimal: 0x752329)   // Sun-Dried Tomato
    static let minuit       = Color(hexadecimal: 0x16151D)   // Midnight Sky

    /// Les six, dans l'ordre du cycle. Six teintes couvrent six championnats distincts ;
    /// au-delà, le cycle recommence.
    static let teintesChampionnat: [Color] = [
        azurite, mure, aubergine, terreau, tomateSechee, minuit
    ]

    /// Teinte d'un championnat. **Tirée d'une empreinte de son identifiant, jamais de son
    /// rang dans une liste** — sinon la couleur d'un championnat changerait dès qu'un
    /// autre est rejoint ou quitté.
    ///
    /// L'empreinte est un FNV-1a écrit ici plutôt que le `hashValue` de Swift : celui-ci
    /// est salé à chaque lancement, et la teinte d'un championnat changerait d'une
    /// ouverture de l'app à la suivante.
    static func teinteChampionnat(pour identifiant: String) -> Color {
        var empreinte: UInt64 = 0xcbf2_9ce4_8422_2325
        for octet in identifiant.utf8 {
            empreinte = (empreinte ^ UInt64(octet)) &* 0x100_0000_01b3
        }
        return teintesChampionnat[Int(empreinte % UInt64(teintesChampionnat.count))]
    }

    /// Encre de second rang posée **sur un aplat de couleur** : blanc à **70 %**
    /// (`docs/swift-app.md` §4.4).
    ///
    /// > Pas à 60 % : mesuré au simulateur, le blanc à 60 % composité sur `primaire`
    /// > donne `#D9B3B8`, soit **4,47:1** — sous le plancher de 4,5:1 d'un texte
    /// > ordinaire. À 70 % il y tient **5,75:1**.
    static let encreSecondaire = Color.white.opacity(0.70)
}

extension Color {
    /// `Color(hexadecimal: 0x800111)` — une seule façon d'écrire un code hexadécimal.
    init(hexadecimal valeur: UInt32) {
        self.init(
            red: Double((valeur >> 16) & 0xFF) / 255,
            green: Double((valeur >> 8) & 0xFF) / 255,
            blue: Double(valeur & 0xFF) / 255
        )
    }
}

// MARK: - Typographie

/// Typographie du design system (`docs/swift-app.md` §4.5).
///
/// **Helvetica Neue partout. Graisses 400 et 500 uniquement** (`ios/CLAUDE.md` §3).
extension Font {
    static let titre   = Font.custom("HelveticaNeue-Medium", size: 28)
    static let titreLg = Font.custom("HelveticaNeue-Medium", size: 30)
    static let score   = Font.custom("HelveticaNeue-Medium", size: 32)
    static let scoreLg = Font.custom("HelveticaNeue-Medium", size: 44)
    static let corps   = Font.custom("HelveticaNeue",        size: 15)
    static let corpsSm = Font.custom("HelveticaNeue",        size: 14)
    static let label   = Font.custom("HelveticaNeue-Medium", size: 11)
    static let labelSm = Font.custom("HelveticaNeue-Medium", size: 10)
}

/// Crénage — **spécifique à la taille**, et **positif** sur les petits labels.
///
/// > **Les grands chiffres ont plus besoin du crénage négatif que les titres** : un chiffre
/// > n'a ni jambage ni hampe, donc rien qui vienne remplir l'espace.
///
/// Un style non listé ici se calcule de la même façon : `-0,02em` sur un titre,
/// `-0,025em` sur un grand chiffre, `0` sur le corps de texte.
enum Tracking {
    /// `titre` — `-0,02 × 28`.
    static let titre: CGFloat = -0.56
    /// `titreLg` — `-0,02 × 30`.
    static let titreLg: CGFloat = -0.60
    /// `score` — `-0,025 × 32`.
    static let score: CGFloat = -0.80
    /// `scoreLg` — `-0,03 × 44`.
    static let scoreLg: CGFloat = -1.32
    /// `corps` et `corpsSm`.
    static let corps: CGFloat = 0
    /// `label` et `labelSm`, tous deux en `.textCase(.uppercase)`.
    static let label: CGFloat = 0.7
}
