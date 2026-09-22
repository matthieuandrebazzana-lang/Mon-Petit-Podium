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

    /// Accent ambre — `#E8A020`, le `--color-accent` de la version web et la teinte du
    /// dessin de `assets/logo.svg`.
    ///
    /// **Elle ne devient JAMAIS une encre.** Sur le blanc elle ne vaut que **2,2:1**,
    /// sous le plancher de 3:1 d'un élément graphique porteur de sens : elle n'est
    /// tenable en dessin que parce que le logo « Rejoindre un championnat » y est
    /// décoratif et que c'est le titre de la carte qui porte le sens.
    ///
    /// **En aplat, elle n'accepte qu'une encre : `texte`**, où elle tient **7,86:1**.
    /// C'est ce qui fait de la pastille « Pronos ouverts » la seule des quatre à garder
    /// sa couleur de fond sur un drapeau — les trois autres passent par du blanc, parce
    /// que leur mot ne tient pas en ambre.
    static let accent = Color(hexadecimal: 0xE8A020)

    /// Vert sauge — `#4A7C59`. L'encre de ce qui est **consultable et derrière nous** :
    /// la pastille « Terminé » et la bande « Voir les résultats ».
    ///
    /// **Sur du blanc seulement**, où elle tient **4,86:1** — le plus serré des quatre
    /// états, et c'est lui qui a fixé l'opacité de la bande. Sur le beige de l'app elle
    /// tombe à 4,34:1 et ne passe plus le plancher d'un texte ordinaire.
    static let vertSauge = Color(hexadecimal: 0x4A7C59)
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
    static func teinteChampionnat(pour identifiant: String) -> Color {
        teintesChampionnat[Int(empreinte(identifiant) % UInt64(teintesChampionnat.count))]
    }

    /// Teinte de l'avatar d'un membre, tirée de **son identifiant** par la même empreinte.
    ///
    /// Elle est donc **stable d'un écran à l'autre et d'un lancement au suivant** : un
    /// membre garde sa couleur dans le classement d'un championnat comme dans celui du
    /// voisin, ce qui est exactement ce qui permet de le repérer d'un coup d'œil.
    ///
    /// **Le décalage de l'empreinte n'est pas cosmétique** : sans lui, un championnat et
    /// son créateur — qui partagent souvent un identifiant proche — tomberaient sur la même
    /// teinte, et l'avatar disparaîtrait dans l'en-tête de sa propre carte.
    ///
    /// Le blanc tient de **10,35:1** à **18,12:1** sur les six teintes : une initiale y est
    /// lisible sans exception.
    static func teinteAvatar(pour identifiant: String) -> Color {
        let decale = empreinte(identifiant) &* 0x27d4_eb2f_1651_8000
        return teintesChampionnat[Int(decale % UInt64(teintesChampionnat.count))]
    }

    /// L'empreinte FNV-1a des deux fonctions ci-dessus, **écrite ici plutôt que reprise du
    /// `hashValue` de Swift** : celui-ci est salé à chaque lancement, et la teinte d'un
    /// championnat comme celle d'un avatar changeraient d'une ouverture de l'app à la
    /// suivante.
    private static func empreinte(_ identifiant: String) -> UInt64 {
        var valeur: UInt64 = 0xcbf2_9ce4_8422_2325
        for octet in identifiant.utf8 {
            valeur = (valeur ^ UInt64(octet)) &* 0x100_0000_01b3
        }
        return valeur
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
