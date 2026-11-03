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
/// > **La vue ne dessine rien elle-même.** Elle mesure son cadre et le confie à
/// > ``Tutoriel`` ; voile, découpe et bulle vivent dans ``FenetreBulle``, au-dessus de
/// > tout — une feuille ou un plein écran compris, qu'un `overlay` n'aurait pas couverts.
struct BulleAideModificateur: ViewModifier {

    let bulle: BulleAide
    let condition: Bool
    let position: PositionBulle
    let pointe: CGFloat

    @State private var visible = false
    /// Le dernier cadre mesuré — **hors de l'état observé** : il change à chaque image d'un
    /// défilement, et l'écran ne doit pas se redessiner pour autant.
    @State private var mesure = Mesure()
    @State private var demande: Task<Void, Never>?

    private final class Mesure { var cadre: CGRect = .zero }

    /// Le temps que l'écran s'installe — et que le passage d'écran soit fini.
    private static let pause: Duration = .milliseconds(600)

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometrie in
                    Color.clear
                        .onChange(of: geometrie.frame(in: .global), initial: true) { _, nouveau in
                            mesure.cadre = nouveau
                            if visible != bienPlacee(nouveau) { visible.toggle() }
                            Tutoriel.partage.deplacer(bulle, cadre: nouveau)
                        }
                }
            }
            // **L'accueil du tutoriel compte dans la condition** : une demande faite sous
            // lui est ignorée (``Tutoriel/demander(_:cible:)``), et sa fermeture doit la relancer.
            .onChange(of: visible && condition && !Tutoriel.partage.accueilOuvert,
                      initial: true) { _, pret in
                demande?.cancel()
                guard pret else { return }
                demande = Task {
                    try? await Task.sleep(for: Self.pause)
                    guard !Task.isCancelled, bienPlacee(mesure.cadre) else { return }
                    Tutoriel.partage.demander(bulle, cible: CibleBulle(cadre: mesure.cadre,
                                                                       position: position,
                                                                       pointe: pointe))
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

    /// La hauteur à laisser libre du côté préféré. La bulle se retourne si elle n'y tient
    /// pas (``CalqueBulleAide``) : ce seuil dit seulement que le bord est bien à l'écran.
    private static let place: CGFloat = 120
    /// La part de la vue qui doit se voir sous la pointe.
    private static let prise: CGFloat = 60
    /// La barre d'onglets et la zone sûre du bas.
    private static let barreOnglets: CGFloat = 90
    /// La barre d'état et l'îlot.
    private static let barreEtat: CGFloat = 60
}

// MARK: - La fenêtre

/// **Une fenêtre à part, au-dessus de l'app**, le temps d'une bulle — posée et retirée par
/// ``Tutoriel``. Elle prend tous les touchers (rien dessous ne réagit) et, modale, tout le
/// parcours VoiceOver. Niveau `normal + 1` : au-dessus des feuilles, sous les alertes.
final class FenetreBulle: UIWindow {

    private weak var principale: UIWindow?

    init(scene: UIWindowScene) {
        principale = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        super.init(windowScene: scene)
        // L'apparence choisie dans l'app (``ThemeManager``) vaut pour cette fenêtre aussi.
        overrideUserInterfaceStyle = principale?.overrideUserInterfaceStyle ?? .unspecified
        let marges = principale?.safeAreaInsets ?? .zero
        let hote = UIHostingController(rootView: CalqueBulleAide(
            marges: EdgeInsets(top: marges.top, leading: marges.left,
                               bottom: marges.bottom, trailing: marges.right)))
        hote.view.backgroundColor = .clear
        hote.view.accessibilityViewIsModal = true
        rootViewController = hote
        backgroundColor = .clear
        windowLevel = .normal + 1
        makeKeyAndVisible()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non pris en charge") }

    override var isHidden: Bool {
        didSet { if isHidden { principale?.makeKey() } }
    }
}

// MARK: - Le calque

/// **Le voile, sa découpe et la bulle**, en coordonnées de l'écran.
///
/// La bulle se pose du côté demandé par l'écran ; si elle n'y tient pas, de l'autre ; si
/// elle ne tient d'aucun côté (une vue plus haute que l'écran), elle se retient dans
/// l'écran, par-dessus, sans pointe.
struct CalqueBulleAide: View {

    let marges: EdgeInsets

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit
    @State private var hauteurBulle: CGFloat = 0

    /// Le jour laissé autour de la vue désignée.
    private static let jour: CGFloat = 8
    /// Entre la découpe et la pointe.
    private static let ecart: CGFloat = 6
    /// Marge latérale de la bulle, et distance minimale aux zones sûres.
    private static let marge: CGFloat = 16
    private static let largeurMax: CGFloat = 400

    var body: some View {
        let tutoriel = Tutoriel.partage
        GeometryReader { geometrie in
            let ecran = CGRect(origin: .zero, size: geometrie.size)
            ZStack(alignment: .topLeading) {
                // Prend chaque toucher, découpe comprise : rien dessous ne réagit.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)

                if tutoriel.calqueVisible, let bulle = tutoriel.bulleActive,
                   let cible = tutoriel.cible {
                    let decoupe = cible.cadre.insetBy(dx: -Self.jour, dy: -Self.jour)
                        .intersection(ecran)
                    let place = placement(cible: cible, decoupe: decoupe, ecran: ecran)

                    VoileDecoupe(decoupe: decoupe, rayon: Rayon.carte)
                        .fill(Color.voileBulle, style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    VueBulleAide(bulle: bulle, pointe: place.pointe, abscissePointe: place.abscissePointe)
                        .frame(width: place.cadre.width)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            hauteurBulle = $0
                        }
                        .opacity(hauteurBulle > 0 ? 1 : 0)
                        .offset(x: place.cadre.minX, y: place.cadre.minY)
                        .transition(mouvementReduit
                                    ? AnyTransition.opacity
                                    : AnyTransition.bulleAide(pointe: UnitPoint(
                                        x: place.abscissePointe / max(place.cadre.width, 1),
                                        y: place.pointe == .dessous ? 0 : 1)))
                }
            }
            .frame(width: ecran.width, height: ecran.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .accessibilityAction(.escape) { tutoriel.compris() }
    }

    private struct Placement {
        var cadre: CGRect
        /// Où la pointe se trouve sur la bulle — `nil` si la bulle recouvre la vue.
        var pointe: PositionBulle?
        var abscissePointe: CGFloat
    }

    private func placement(cible: CibleBulle, decoupe: CGRect, ecran: CGRect) -> Placement {
        let largeur = min(ecran.width - 2 * Self.marge, Self.largeurMax)
        let x = (ecran.width - largeur) / 2
        let h = hauteurBulle
        let haut = marges.top + Self.marge / 2
        let bas = ecran.height - marges.bottom - Self.marge / 2

        let yDessus = decoupe.minY - Self.ecart - h
        let yDessous = decoupe.maxY + Self.ecart
        let tientDessus = yDessus >= haut
        let tientDessous = yDessous + h <= bas

        // `.dessus` : la bulle est au-dessus de la vue, sa pointe en bas.
        let cote: PositionBulle?
        switch cible.position {
        case .dessus:  cote = tientDessus ? .dessus : (tientDessous ? .dessous : nil)
        case .dessous: cote = tientDessous ? .dessous : (tientDessus ? .dessus : nil)
        }
        let y: CGFloat
        switch cote {
        case .dessus:  y = yDessus
        case .dessous: y = yDessous
        case nil:
            let voulu = cible.position == .dessus ? yDessus : yDessous
            y = min(max(voulu, haut), max(bas - h, haut))
        }

        let cible_x = cible.cadre.minX + cible.cadre.width * cible.pointe - x
        let retrait = Rayon.carte + VueBulleAide.largeurPointe / 2
        let abscisse = min(max(cible_x, retrait), largeur - retrait)
        return Placement(cadre: CGRect(x: x, y: y, width: largeur, height: h),
                         pointe: cote, abscissePointe: abscisse)
    }
}

/// L'écran entier moins la découpe — à remplir en `eoFill`.
private struct VoileDecoupe: Shape {
    let decoupe: CGRect
    let rayon: CGFloat

    func path(in rect: CGRect) -> Path {
        var chemin = Path(rect)
        guard !decoupe.isNull, !decoupe.isEmpty else { return chemin }
        chemin.addRoundedRect(in: decoupe, cornerSize: CGSize(width: rayon, height: rayon),
                              style: .continuous)
        return chemin
    }
}

// MARK: - La bulle

/// **Fond `surface`, ombre de bloc** — sur le voile, la bulle se lit comme une carte posée
/// au premier plan. Titre en ``Color/texte`` (17:1 en clair, 13,94:1 en sombre), texte en
/// ``Color/secondaire`` (≥ 11:1 dans les deux modes), « Compris » en ``Color/encreSurAplat``
/// sur l'aplat ``Color/primaire`` (10,9:1 en clair, 6,17:1 en sombre).
private struct VueBulleAide: View {

    let bulle: BulleAide
    /// Le côté de la bulle qui porte la pointe — `nil` : pas de pointe.
    let pointe: PositionBulle?
    let abscissePointe: CGFloat

    static let largeurPointe: CGFloat = 22
    static let hauteurPointe: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            // La place de la pointe est toujours réservée, des deux côtés : la hauteur de la
            // bulle ne dépend pas de son côté, et le placement ne boucle pas.
            triangle(versLeHaut: true, visible: pointe == .dessous)

            VStack(alignment: .leading, spacing: 0) {
                Text(t(bulle.cleTitre))
                    .font(.titreBulle)
                    .foregroundColor(.texte)
                    .accessibilityAddTraits(.isHeader)
                Spacer().frame(height: 6)
                Text(t(bulle.cleTexte))
                    .font(.corps)
                    .foregroundColor(.secondaire)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 18)
                Button { Tutoriel.partage.compris() } label: {
                    Text(t("tutoriel.bulle.compris"))
                        .font(.actionBulle)
                        .foregroundColor(.encreSurAplat)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.primaire,
                                    in: RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
                }
                .buttonStyle(StyleAppui(.bouton))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.surface,
                        in: RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))

            triangle(versLeHaut: false, visible: pointe == .dessus)
        }
        .compositingGroup()
        .ombreBloc()
        .accessibilityElement(children: .contain)
    }

    private func triangle(versLeHaut: Bool, visible: Bool) -> some View {
        Pointe(versLeHaut: versLeHaut)
            .fill(Color.surface)
            .frame(width: Self.largeurPointe, height: Self.hauteurPointe)
            .position(x: abscissePointe, y: Self.hauteurPointe / 2)
            .frame(height: Self.hauteurPointe)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(true)
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
