import SwiftUI

/// Tout ce que le widget du prochain Grand Prix a besoin de savoir pour se peindre aux
/// couleurs du pays hôte — transposition de `frontend/src/composants/DrapeauxGP.jsx`.
///
/// **L'opacité du voile est CALCULÉE, jamais choisie.** Le texte du widget reste blanc sur
/// les douze drapeaux : c'est ce qui rend le bloc reconnaissable d'un week-end à l'autre.
/// Mais sept d'entre eux portent une bande blanche, où du texte blanc ne se voit pas du
/// tout. D'où un voile noir, dérivé de la bande la plus claire par pas de 0,05 — un
/// drapeau ajouté demain reçoit le bon voile sans que personne ne refasse le calcul.
///
/// > Un noir à 30 % sur une bande blanche la ramène à `#B2B2B2`, où le blanc plein ne vaut
/// > que **2,11:1** — sous le plancher de 3:1. Il en faut **0,45**, et davantage encore si
/// > l'on tient compte de la lumière spéculaire posée par-dessus. C'est pourquoi
/// > ``LueurHaute`` entre dans le calcul du substrat au lieu d'être découverte à l'écran.
///
/// **L'ordre des calques ne se défait pas** : le drapeau tout en bas · la lumière
/// spéculaire · le voile · l'assombrissement uniforme · puis le contenu seul. Tout ce qui
/// éclaircit passe SOUS le voile, sans quoi la garantie de 3:1 n'en est plus une.
///
/// Mesuré pour les douze drapeaux du calendrier : **aucun** ne laisse passer un blanc à
/// 70 % ni une surface blanche translucide. L'encre de second rang y est donc toujours du
/// blanc plein en graisse 500, et les surfaces intérieures toujours du noir translucide —
/// la hiérarchie passe par la taille et la graisse, jamais par l'opacité (/apple-design
/// §12). Les deux champs restent calculés plutôt que figés : c'est la mesure qui tranche,
/// et un treizième drapeau plus sombre changerait la réponse.
struct ApparenceDrapeau {

    /// Opacité du voile noir posé sur le drapeau.
    let voile: Double

    /// Encre de second rang — date, libellés des tuiles.
    let encreDouce: Color

    /// Graisse de cette encre : 500 dès que le blanc à 70 % ne tient plus le seuil.
    let encreDouceGrasse: Bool

    /// Matériau de la pastille « Prochain GP ».
    let pastille: Color

    /// Matériau des deux tuiles de statut.
    let surface: Color

    /// Ombre portée sous le nom du Grand Prix.
    ///
    /// **Seulement sur les drapeaux à plusieurs bandes.** Le nom occupe toute la largeur du
    /// widget : il traverse une frontière de bandes, et une lettre posée pile sur la couture
    /// perd son contour d'un côté ou de l'autre.
    let ombreNom: Bool

    /// L'apparence d'un Grand Prix, ou `nil` si son pays n'est pas dans la table — le
    /// widget garde alors l'aplat `primaire` de la marque.
    static func pour(slug: String) -> ApparenceDrapeau? {
        guard let couleurs = TeintesDrapeaux.table[slug] else { return nil }
        return ApparenceDrapeau(couleurs: couleurs)
    }

    private init(couleurs: [UInt32]) {
        let voile = Self.voileNecessaire(couleurs)
        let sol = Self.substrat(couleurs, voile: voile)

        // Deux questions, deux mesures sur ce même substrat.
        // 1. Un blanc à 70 % s'y détache-t-il encore ?
        let douxTient = Self.contraste(Self.composer(sol, vers: 0xFFFFFF, alpha: 0.7), sol)
            >= Self.contrasteCible
        // 2. Une surface blanche translucide y laisse-t-elle son texte blanc lisible ?
        //    On éprouve la plus claire des deux (20 %) : si elle passe, l'autre passe.
        let surfacesClaires = Self.contraste(0xFFFFFF, Self.composer(sol, vers: 0xFFFFFF, alpha: 0.2))
            >= Self.contrasteCible

        self.voile = voile
        self.encreDouce = douxTient ? .white.opacity(0.70) : .white
        self.encreDouceGrasse = !douxTient
        self.pastille = surfacesClaires ? .white.opacity(0.20) : .black.opacity(0.25)
        self.surface = surfacesClaires ? .white.opacity(0.12) : .black.opacity(0.20)
        self.ombreNom = couleurs.count > 1
    }

    // MARK: - Le calcul

    /// Plancher AA des grands textes. Le texte du widget est à 15 pt et au-delà.
    private static let contrasteCible: Double = 3

    /// Opacité maximale de ``LueurHaute``. Elle éclaircit le haut du widget, donc elle joue
    /// contre le contraste : le calcul l'inclut.
    private static let lueurMax: Double = 0.22

    /// Pas du voile. Assez fin pour ne jamais voiler un drapeau plus que nécessaire.
    private static let pasVoile: Double = 0.05

    /// Le voile qui tient `contraste` pour du blanc sur ce drapeau, ou `nil` hors table.
    ///
    /// Pour un texte **ordinaire** posé sur un drapeau (4,5:1), là où le widget n'en porte
    /// que de grands (3:1). Même mesure, même substrat : seule la cible change.
    static func voile(pour slug: String, contraste cible: Double) -> Double? {
        TeintesDrapeaux.table[slug].map { voileNecessaire($0, cible: cible) }
    }

    /// Le voile qui fait tenir **4,5:1** à l'encre de second rang (blanc à 70 %,
    /// ``Color/encreSecondaire``) sur ce drapeau, ou `nil` hors table.
    ///
    /// Pour le fond flouté de « Mes / Ses Grands Prix » : l'en-tête y pose un titre blanc
    /// et un sous-titre à 70 %. Mesuré sur la bande la plus claire — le flou mélange les
    /// bandes, il ne les éclaircit jamais au-delà de la plus claire.
    static func voileEncreSecondaire(pour slug: String) -> Double? {
        guard let couleurs = TeintesDrapeaux.table[slug] else { return nil }
        var voile: Double = 0
        while voile < 0.9 {
            let sol = substrat(couleurs, voile: voile)
            if contraste(composer(sol, vers: 0xFFFFFF, alpha: 0.7), sol) >= 4.5 { break }
            voile = ((voile + pasVoile) * 100).rounded() / 100
        }
        return voile
    }

    /// Un drapeau dont la bande la plus claire est blanche ou presque — Italie, Pays-Bas,
    /// Singapour, Qatar… `false` hors table.
    ///
    /// Un voile uniforme qui y fait tenir le texte change sa bande blanche en gris, et la
    /// carte entière se lit pâle et délavée. Ces drapeaux ne sont donc pas voilés partout :
    /// le voile se limite à la zone du texte, et le reste montre les vraies couleurs.
    static func estClair(_ slug: String) -> Bool {
        guard let couleurs = TeintesDrapeaux.table[slug] else { return false }
        return luminance(bandeLaPlusClaire(couleurs)) >= 0.7
    }

    private static func voileNecessaire(_ couleurs: [UInt32], cible: Double = contrasteCible) -> Double {
        var voile: Double = 0
        while voile < 0.9,
              contraste(0xFFFFFF, substrat(couleurs, voile: voile)) < cible {
            voile = ((voile + pasVoile) * 100).rounded() / 100
        }
        return voile
    }

    /// Ce que le blanc rencontre vraiment : la bande la plus claire, éclaircie par la
    /// lumière spéculaire, puis assombrie par le voile.
    private static func substrat(_ couleurs: [UInt32], voile: Double) -> UInt32 {
        let clair = composer(bandeLaPlusClaire(couleurs), vers: 0xFFFFFF, alpha: lueurMax)
        return voile > 0 ? composer(clair, vers: 0x000000, alpha: voile) : clair
    }

    /// La bande la plus claire d'un drapeau : c'est elle qui contraint, le texte pouvant
    /// tomber n'importe où sur le widget.
    private static func bandeLaPlusClaire(_ couleurs: [UInt32]) -> UInt32 {
        couleurs.reduce(couleurs[0]) { luminance($1) > luminance($0) ? $1 : $0 }
    }

    private static func composer(_ fond: UInt32, vers: UInt32, alpha: Double) -> UInt32 {
        var resultat: UInt32 = 0
        for decalage in stride(from: 16, through: 0, by: -8) {
            let bas = Double((fond >> UInt32(decalage)) & 0xFF)
            let haut = Double((vers >> UInt32(decalage)) & 0xFF)
            let canal = UInt32((bas * (1 - alpha) + haut * alpha).rounded())
            resultat |= canal << UInt32(decalage)
        }
        return resultat
    }

    private static func luminance(_ couleur: UInt32) -> Double {
        func canal(_ decalage: UInt32) -> Double {
            let valeur = Double((couleur >> decalage) & 0xFF) / 255
            return valeur <= 0.03928 ? valeur / 12.92 : pow((valeur + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * canal(16) + 0.7152 * canal(8) + 0.0722 * canal(0)
    }

    private static func contraste(_ a: UInt32, _ b: UInt32) -> Double {
        let clair = max(luminance(a), luminance(b))
        let sombre = min(luminance(a), luminance(b))
        return (clair + 0.05) / (sombre + 0.05)
    }
}
