import SwiftUI
import UIKit

/// Où la bulle se pose par rapport à ce qu'elle désigne.
enum PositionBulle {
    /// Au-dessus, la pointe vers le bas.
    case dessus
    /// En dessous, la pointe vers le haut.
    case dessous
}

extension View {

    /// Pose une bulle d'aide sur cette vue — **une seule fois par compte** (``Tutoriel``).
    ///
    /// La bulle est demandée quand `quand` est vrai **et** que le bord de la vue où elle
    /// s'accroche est à l'écran, avec sa place, après une courte pause : l'écran s'installe
    /// avant qu'on lui parle. Une vue montée hors de l'écran — plus bas dans une liste —
    /// attend donc d'être vue.
    ///
    /// - `pointe` : où la pointe touche la vue, en fraction de sa largeur (0,5 = centre).
    func bulleAide(_ bulle: BulleAide, quand condition: Bool = true,
                   position: PositionBulle = .dessus, pointe: CGFloat = 0.5) -> some View {
        modifier(BulleAideModificateur(bulle: bulle, condition: condition,
                                       position: position, pointe: pointe))
    }
}

/// Voir ``View/bulleAide(_:quand:position:pointe:)``.
///
/// > **Un calque, jamais un cadre.** La bulle déborde de la vue sans rien pousser, et ne
/// > capte aucun toucher : ce qu'elle recouvre reste utilisable. Elle passe au-dessus de
/// > ses voisines par un `zIndex`, seulement tant qu'elle est là.
struct BulleAideModificateur: ViewModifier {

    let bulle: BulleAide
    let condition: Bool
    let position: PositionBulle
    let pointe: CGFloat

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @State private var visible = false
    @State private var demande: Task<Void, Never>?

    /// Le temps que l'écran s'installe — et que le passage d'écran soit fini.
    private static let pause: Duration = .milliseconds(600)

    /// La distance entre la pointe et la vue.
    private static let ecart: CGFloat = 6

    private var affichee: Bool { Tutoriel.partage.bulleActive == bulle }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: position == .dessus ? .top : .bottom) {
                if affichee {
                    // **Un cadre de hauteur nulle posé sur le bord**, que la bulle déborde
                    // vers l'extérieur : un `alignmentGuide` sur le contenu d'un `overlay`
                    // conditionnel était ignoré (mesuré au simulateur, la bulle recouvrait
                    // la vue au lieu de se poser à côté).
                    VueBulleAide(texte: t(bulle.cleTexte), position: position, pointe: pointe)
                        .frame(height: 0, alignment: position == .dessus ? .bottom : .top)
                        .offset(y: position == .dessus ? -Self.ecart : Self.ecart)
                        .transition(mouvementReduit
                                    ? AnyTransition.opacity
                                    : AnyTransition.bulleAide(pointe: UnitPoint(x: pointe,
                                                                   y: position == .dessus ? 1 : 0)))
                }
            }
            .zIndex(affichee ? 1 : 0)
            .background {
                GeometryReader { geometrie in
                    Color.clear
                        .onChange(of: bienPlacee(geometrie.frame(in: .global)),
                                  initial: true) { _, nouveau in visible = nouveau }
                }
            }
            // **L'accueil du tutoriel compte dans la condition** : une demande faite sous
            // lui est ignorée (``Tutoriel/demander(_:)``), et sa fermeture doit la relancer.
            .onChange(of: visible && condition && !Tutoriel.partage.accueilOuvert,
                      initial: true) { _, pret in
                demande?.cancel()
                guard pret else { return }
                demande = Task {
                    try? await Task.sleep(for: Self.pause)
                    guard !Task.isCancelled else { return }
                    Tutoriel.partage.demander(bulle)
                }
            }
            .onDisappear {
                demande?.cancel()
                Tutoriel.partage.fermer(bulle)
            }
    }

    /// **Le bord où la bulle s'accroche est à l'écran, avec la place de la bulle** — pas la
    /// vue entière : une pile de marchés ou un bloc de livrée dépasse souvent l'écran. Il
    /// faut ``place`` points libres du côté de la bulle (barre d'état, barre d'onglets
    /// exclues), et ``prise`` points de la vue visibles sous sa pointe.
    private func bienPlacee(_ cadre: CGRect) -> Bool {
        let ecran = UIScreen.main.bounds
        guard cadre.width > 0, cadre.height > 0,
              cadre.minX >= -1, cadre.maxX <= ecran.width + 1 else { return false }
        let bas = ecran.height - Self.barreOnglets
        let prise = min(cadre.height, Self.prise)
        switch position {
        case .dessus:  return cadre.minY >= Self.place && cadre.minY + prise <= bas
        case .dessous: return cadre.maxY + Self.place <= bas && cadre.maxY - prise >= Self.barreEtat
        }
    }

    /// La hauteur à laisser libre pour la bulle elle-même — trois lignes de texte et la pointe.
    private static let place: CGFloat = 120
    /// La part de la vue qui doit se voir sous la pointe.
    private static let prise: CGFloat = 60
    /// La barre d'onglets et la zone sûre du bas.
    private static let barreOnglets: CGFloat = 90
    /// La barre d'état et l'îlot.
    private static let barreEtat: CGFloat = 60
}

// MARK: - La bulle

/// **L'aplat `primaire`, l'encre `encreSurAplat`** — le blanc y tient 10,9:1 en clair
/// (`#800111`) et 6,17:1 en sombre (`#C0182A`) : la bulle se lit d'abord comme un message
/// de l'app, pas comme une carte de contenu. Ombre d'aplat (`Formes.swift`).
private struct VueBulleAide: View {

    let texte: String
    let position: PositionBulle
    let pointe: CGFloat

    private static let largeurPointe: CGFloat = 16
    private static let hauteurPointe: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            if position == .dessous { triangle(versLeHaut: true) }

            Text(texte)
                .font(.corps)
                .foregroundColor(.encreSurAplat)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.primaire,
                            in: RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))

            if position == .dessus { triangle(versLeHaut: false) }
        }
        .compositingGroup()
        .ombreAplat()
        .allowsHitTesting(false)
        // Annoncée une fois par ``Tutoriel`` ; la lire en plus dans le parcours
        // VoiceOver la ferait relire à chaque passage.
        .accessibilityHidden(true)
    }

    /// La pointe, alignée sur `pointe` et retenue dans les coins arrondis.
    private func triangle(versLeHaut: Bool) -> some View {
        GeometryReader { geometrie in
            let marge = Rayon.champ + Self.largeurPointe / 2
            let x = min(max(geometrie.size.width * pointe, marge), geometrie.size.width - marge)
            Pointe(versLeHaut: versLeHaut)
                .fill(Color.primaire)
                .frame(width: Self.largeurPointe, height: Self.hauteurPointe)
                .position(x: x, y: Self.hauteurPointe / 2)
        }
        .frame(height: Self.hauteurPointe)
    }
}

private struct Pointe: Shape {
    let versLeHaut: Bool

    func path(in rect: CGRect) -> Path {
        var chemin = Path()
        if versLeHaut {
            chemin.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            chemin.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            chemin.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            chemin.move(to: CGPoint(x: rect.minX, y: rect.minY))
            chemin.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            chemin.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        chemin.closeSubpath()
        return chemin
    }
}
