import SwiftUI

/// Formes — seul propriétaire des rayons de l'app (`docs/swift-app.md` §4.6).
///
/// > **Sur iOS, toujours `RoundedRectangle(cornerRadius:style: .continuous)`** — le
/// > squircle d'Apple, qui est exactement l'intention derrière ces rayons.
///
/// Espacement entre blocs : **12 pt**. Padding intérieur : **16 à 20 pt**. Changement de
/// sujet dans un écran : **24 pt** au-dessus du titre de section.
///
/// **Les bordures fines sont proscrites** — et jamais de règle horizontale.
enum Rayon {
    /// Blocs principaux.
    static let bloc: CGFloat = 24
    /// Cartes.
    static let carte: CGFloat = 20
    /// Petites cartes et boutons.
    static let carteSm: CGFloat = 18
    /// Widgets de cote.
    static let widget: CGFloat = 16
    /// Champs et petits éléments posés à l'intérieur d'un bloc.
    static let champ: CGFloat = 14
    /// Pastilles de points — le nombre de points d'un pronostic, posé au bout d'une ligne.
    /// C'est le `rounded-[10px]` de la version web, et il n'habille que cet objet-là.
    static let pastille: CGFloat = 10
}

// MARK: - Élévation

/// Élévation — seul propriétaire des ombres de l'app (`docs/swift-app.md` §4.7).
///
/// **Un seul principe : plus une surface est grande, plus elle est épaisse.** Les trois
/// premiers niveaux superposent **deux couches** — une ombre de contact serrée qui pose
/// l'objet, une ombre ambiante large qui l'éloigne du fond. Une seule couche donne l'un ou
/// l'autre, jamais les deux.
///
/// **La teinte est le marron `secondaire` en très faible opacité, jamais un noir** : une
/// ombre noire sur le beige tire vers le gris et salit la couleur.
///
/// Les valeurs sont transposées de `frontend/src/index.css`, où **le rayon SwiftUI vaut la
/// moitié du flou CSS** (`shadowRadius = blur / 2`).
///
/// **Règle d'attribution** : rayon `bloc` (24) → ``ombreBloc()`` · rayon `carte` (20) →
/// ``ombreCarte()`` · rayon `champ` (14) → **aucune ombre**, ce sont les surfaces posées
/// *à l'intérieur* d'un bloc, qui ne cassent jamais son plan · **aplat de couleur** →
/// ``ombreAplat()``, quel que soit son rayon.
extension View {

    /// `shadow-carte` — cartes blanches.
    func ombreCarte() -> some View {
        self.shadow(color: Color.secondaire.opacity(0.04), radius: 1, y: 1)
            .shadow(color: Color.secondaire.opacity(0.06), radius: 6, y: 4)
    }

    /// `shadow-bloc` — blocs principaux au rayon 24.
    func ombreBloc() -> some View {
        self.shadow(color: Color.secondaire.opacity(0.05), radius: 2, y: 2)
            .shadow(color: Color.secondaire.opacity(0.09), radius: 14, y: 10)
    }

    /// `shadow-flottant` — barres de navigation et d'action collées : l'ombre **remonte**,
    /// elle ne descend pas. Une seule couche.
    func ombreFlottant() -> some View {
        self.shadow(color: Color.secondaire.opacity(0.10), radius: 12, y: -1)
    }

    /// `shadow-aplat` — **pour les aplats de couleur seulement**.
    ///
    /// > Elle existe parce que les trois autres sont réglées pour du **blanc**. Sous un
    /// > bloc rouge, violet ou sombre, un marron clair ne se voit plus : celle-ci est plus
    /// > profonde et plus contrastée. Plus la surface est dense, plus elle doit peser sur
    /// > le fond.
    ///
    /// - `intensite` module l'opacité des deux couches sans toucher à leur géométrie : une
    ///   surface qui s'efface derrière une autre éteint son ombre au lieu de la couper net.
    /// - `allegee` retire la couche ambiante, la seule coûteuse (flou de 17). Réservé aux
    ///   surfaces **immobiles pendant qu'une voisine bouge** : chaque image recalcule toutes
    ///   les ombres de l'écran, y compris celles qui ne changent pas.
    func ombreAplat(intensite: Double = 1, allegee: Bool = false) -> some View {
        self.shadow(color: Color.secondaire.opacity(0.10 * intensite), radius: 3, y: 2)
            .shadow(color: Color.secondaire.opacity(allegee ? 0 : 0.16 * intensite),
                    radius: allegee ? 0 : 17, y: allegee ? 0 : 14)
    }
}
