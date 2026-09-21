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
