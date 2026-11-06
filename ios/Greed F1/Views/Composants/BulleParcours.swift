import SwiftUI
import UIKit

/// Où la bulle se pose par rapport à ce qu'elle désigne.
enum PositionBulle {
    /// Au-dessus, la pointe vers le bas.
    case dessus
    /// En dessous, la pointe vers le haut.
    case dessous
}

/// Ce qu'une bulle désigne : le cadre de la vue **en coordonnées de l'écran**, et où la
/// bulle préfère se poser.
struct CibleBulle: Equatable {
    var cadre: CGRect
    var position: PositionBulle
    var pointe: CGFloat
}

extension View {

    /// Désigne cette vue à l'étape `etape` du parcours guidé (``ParcoursGuide``).
    ///
    /// La vue mesure son cadre **à chaque image** — un défilement compris — et le confie au
    /// parcours : le voile, sa découpe et la bulle la suivent, et le filtre de touchers
    /// laisse passer ce qui tombe dans la découpe.
    ///
    /// - `pointe` : où la pointe touche la vue, en fraction de sa largeur (0,5 = centre).
    /// - `action` : le geste de l'étape, fait pour VoiceOver depuis la bulle — la vue
    ///   désignée, elle, est sous le voile modal.
    /// - `actif` : faux, la vue ne se désigne pas — un composant monté à deux endroits.
    @ViewBuilder
    func etapeParcours(_ etape: EtapeParcours, position: PositionBulle = .dessus,
                       pointe: CGFloat = 0.5, actif: Bool = true,
                       action: (() -> Void)? = nil) -> some View {
        if actif {
            modifier(CibleParcours(etape: etape, position: position, pointe: pointe, action: action))
        } else {
            self
        }
    }
}

/// Voir ``View/etapeParcours(_:position:pointe:action:)``.
///
/// > **La vue ne dessine rien elle-même.** Voile, découpe et bulle vivent dans
/// > ``FenetreBulle``, au-dessus de tout — une feuille ou un plein écran compris, qu'un
/// > `overlay` n'aurait pas couverts.
struct CibleParcours: ViewModifier {

    let etape: EtapeParcours
    let position: PositionBulle
    let pointe: CGFloat
    let action: (() -> Void)?

    /// Le dernier cadre mesuré — **hors de l'état observé** : il change à chaque image d'un
    /// défilement, et l'écran ne doit pas se redessiner pour autant.
    @State private var mesure = Mesure()

    private final class Mesure { var cadre: CGRect = .zero }

    private var designee: Bool {
        let guide = ParcoursGuide.partage
        return guide.actif && guide.etape == etape
    }

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometrie in
                    Color.clear
                        .onChange(of: geometrie.frame(in: .global), initial: true) { _, cadre in
                            mesure.cadre = cadre
                            signaler()
                        }
                }
            }
            // L'étape arrive sur une vue déjà montée, qui ne bouge plus.
            .onChange(of: designee, initial: true) { _, oui in
                if oui { signaler() }
            }
            .onDisappear { ParcoursGuide.partage.perdre(etape) }
    }

    private func signaler() {
        guard designee, mesure.cadre.width > 0, mesure.cadre.height > 0 else { return }
        ParcoursGuide.partage.cibler(etape, cible: CibleBulle(cadre: mesure.cadre, position: position,
                                                              pointe: pointe),
                                     action: action)
    }
}

// MARK: - La fenêtre

/// **Une fenêtre à part, au-dessus de l'app**, le temps du parcours — posée et retirée par
/// ``ParcoursGuide``. Niveau `normal + 1` : au-dessus des feuilles, sous les alertes.
///
/// **Elle ne prend que les touchers de la bulle.** Tout le reste passe à la fenêtre de
/// l'app, où ``FiltreParcours`` laisse défiler et n'accepte de tap que dans la découpe. Le
/// voile n'est qu'une peinture. Modale pour VoiceOver : seule la bulle existe pour lui —
/// sauf quand une feuille ou un menu est ouvert par-dessus l'écran (``modale``).
final class FenetreBulle: UIWindow {

    /// La fenêtre de l'app, celle où le filtre se pose.
    private(set) weak var principale: UIWindow?
    private let hote: UIHostingController<CalqueParcours>

    init(scene: UIWindowScene) {
        principale = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        let marges = principale?.safeAreaInsets ?? .zero
        hote = UIHostingController(rootView: CalqueParcours(
            marges: EdgeInsets(top: marges.top, leading: marges.left,
                               bottom: marges.bottom, trailing: marges.right)))
        super.init(windowScene: scene)
        // L'apparence choisie dans l'app (``ThemeManager``) vaut pour cette fenêtre aussi.
        overrideUserInterfaceStyle = principale?.overrideUserInterfaceStyle ?? .unspecified
        hote.view.backgroundColor = .clear
        hote.view.accessibilityViewIsModal = true
        rootViewController = hote
        backgroundColor = .clear
        windowLevel = .normal + 1
        // Visible sans devenir la fenêtre clé : le clavier de l'app reste à l'app.
        isHidden = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non pris en charge") }

    /// VoiceOver ne voit que la bulle — faux quand une feuille de l'écran doit être lue.
    var modale: Bool {
        get { hote.view.accessibilityViewIsModal }
        set { hote.view.accessibilityViewIsModal = newValue }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let guide = ParcoursGuide.partage
        guard guide.calqueVisible, !guide.suspendu, guide.cadreBulle.contains(point) else {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Le calque

/// **Le voile, sa découpe et la bulle**, en coordonnées de l'écran.
///
/// La bulle se pose du côté demandé par l'écran ; si elle n'y tient pas, de l'autre ; si
/// elle ne tient d'aucun côté (une vue plus haute que l'écran), elle se retient dans
/// l'écran, par-dessus, sans pointe. Sans cible — bienvenue, proposition de reprise —, elle
/// est centrée et le voile couvre tout.
struct CalqueParcours: View {

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
        let guide = ParcoursGuide.partage
        GeometryReader { geometrie in
            let ecran = CGRect(origin: .zero, size: geometrie.size)
            ZStack(alignment: .topLeading) {
                if guide.calqueVisible, !guide.suspendu, let contenu = contenu(guide) {
                    let decoupe = contenu.cible.map {
                        $0.cadre.insetBy(dx: -Self.jour, dy: -Self.jour).intersection(ecran)
                    }
                    let place = placement(cible: contenu.cible, decoupe: decoupe, ecran: ecran)

                    VoileDecoupe(decoupe: decoupe, rayon: Rayon.carte)
                        .fill(Color.voileBulle, style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    Group {
                        if contenu.proposition {
                            VueProposition()
                        } else {
                            VueBulleParcours(pointe: place.pointe,
                                             abscissePointe: place.abscissePointe)
                        }
                    }
                    .frame(width: place.cadre.width)
                    // **La hauteur se lit dans la taille propre, arrondie** — jamais dans le
                    // cadre global : l'échelle de l'entrée et le décalage le font varier d'un
                    // arrondi à chaque passe, et le placement se relançait sans fin.
                    .onGeometryChange(for: CGFloat.self) { ($0.size.height * 2).rounded() / 2 } action: {
                        hauteurBulle = $0
                    }
                    // Le cadre global ne sert qu'aux touchers : hors de l'état observé.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        guide.cadreBulle = $0
                    }
                    .opacity(hauteurBulle > 0 ? 1 : 0)
                    .offset(x: place.cadre.minX, y: place.cadre.minY)
                    .animation(mouvementReduit ? nil : Mouvement.entree(Mouvement.passageEcran),
                               value: place.cadre.minY)
                    .id(contenu.cle)
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
        .accessibilityAction(.escape) {
            if guide.propositionVisible { guide.plusTard() } else { guide.quitter() }
        }
    }

    private struct Contenu {
        var cible: CibleBulle?
        var proposition: Bool
        /// Change à chaque étape : la bulle sort et rentre, elle ne glisse pas d'une
        /// étape à l'autre.
        var cle: String
    }

    /// Ce que le calque montre — `nil` tant que la vue de l'étape ne s'est pas signalée.
    private func contenu(_ guide: ParcoursGuide) -> Contenu? {
        if guide.propositionVisible { return Contenu(cible: nil, proposition: true, cle: "reprise") }
        guard guide.actif else { return nil }
        if guide.etape.aUneCible && guide.cible == nil { return nil }
        let cle = "\(guide.etape.rawValue)-\(guide.comprisDisponible && guide.etape == .piste)"
        return Contenu(cible: guide.etape.aUneCible ? guide.cible : nil, proposition: false, cle: cle)
    }

    private struct Placement {
        var cadre: CGRect
        /// Où la pointe se trouve sur la bulle — `nil` si la bulle recouvre la vue.
        var pointe: PositionBulle?
        var abscissePointe: CGFloat
    }

    private func placement(cible: CibleBulle?, decoupe: CGRect?, ecran: CGRect) -> Placement {
        let largeur = min(ecran.width - 2 * Self.marge, Self.largeurMax)
        let x = (ecran.width - largeur) / 2
        let h = hauteurBulle
        let haut = marges.top + Self.marge / 2
        let bas = ecran.height - marges.bottom - Self.marge / 2

        guard let cible, let decoupe, !decoupe.isNull else {
            return Placement(cadre: CGRect(x: x, y: (ecran.height - h) / 2, width: largeur, height: h),
                             pointe: nil, abscissePointe: largeur / 2)
        }

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

        let cibleX = cible.cadre.minX + cible.cadre.width * cible.pointe - x
        let retrait = Rayon.carte + VueBulleParcours.largeurPointe / 2
        let abscisse = min(max(cibleX, retrait), largeur - retrait)
        return Placement(cadre: CGRect(x: x, y: y, width: largeur, height: h),
                         pointe: cote, abscissePointe: abscisse)
    }
}

/// L'écran entier moins la découpe — à remplir en `eoFill`.
private struct VoileDecoupe: Shape {
    let decoupe: CGRect?
    let rayon: CGFloat

    func path(in rect: CGRect) -> Path {
        var chemin = Path(rect)
        guard let decoupe, !decoupe.isNull, !decoupe.isEmpty else { return chemin }
        chemin.addRoundedRect(in: decoupe, cornerSize: CGSize(width: rayon, height: rayon),
                              style: .continuous)
        return chemin
    }
}

// MARK: - La bulle d'une étape

/// **Fond `surface`, ombre de bloc** — sur le voile, la bulle se lit comme une carte posée
/// au premier plan. Titre en ``Color/texte`` (17:1 en clair, 13,94:1 en sombre), texte en
/// ``Color/secondaire`` (≥ 11:1 dans les deux modes), « Compris » en ``Color/encreSurAplat``
/// sur l'aplat ``Color/primaire`` (10,9:1 en clair, 6,17:1 en sombre).
///
/// En tête, la progression (une jauge `encrePrimaire` sur un rail `fondSegmentInactif`) et
/// « Quitter », toujours là : on ne reste jamais enfermé (App Store, accessibilité).
private struct VueBulleParcours: View {

    /// Le côté de la bulle qui porte la pointe — `nil` : pas de pointe.
    let pointe: PositionBulle?
    let abscissePointe: CGFloat

    static let largeurPointe: CGFloat = 22
    static let hauteurPointe: CGFloat = 10

    var body: some View {
        let guide = ParcoursGuide.partage
        let etape = guide.etape
        // La vue Piste change de texte une fois « Piste » touché.
        let cle = etape == .piste && guide.comprisDisponible ? "pisteApres" : etape.nom

        VStack(spacing: 0) {
            // La place de la pointe est toujours réservée, des deux côtés : la hauteur de la
            // bulle ne dépend pas de son côté, et le placement ne boucle pas.
            triangle(versLeHaut: true, visible: pointe == .dessous)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    ProgressionParcours(etape: etape.rawValue)
                    Button { guide.quitter() } label: {
                        Text(t("parcours.quitter"))
                            .font(.segment)
                            .foregroundColor(.secondaire)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(StyleAppui(.bouton))
                    .accessibilityHint(t("parcours.a11y.quitter"))
                }
                .padding(.top, -10)

                Text(t("parcours.\(cle).titre"))
                    .font(.titreBulle)
                    .foregroundColor(.texte)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(2)
                Spacer().frame(height: 6)
                Text(texte(cle))
                    .font(.corps)
                    .foregroundColor(.secondaire)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilitySortPriority(1)

                if guide.comprisPossible {
                    Spacer().frame(height: 18)
                    BoutonBulle(titre: t(etape == .fin ? "parcours.fin.action" : "parcours.compris")) {
                        guide.compris()
                    }
                    .transition(.opacity)
                }
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
        .modifier(GesteAccessible(etape: etape, actif: etape.attendGeste && !guide.comprisDisponible))
    }

    /// Le texte de l'étape — avec le code d'exemple à l'étape où on le saisit.
    private func texte(_ cle: String) -> String {
        ParcoursGuide.partage.etape == .codeExemple
            ? t("parcours.\(cle).texte", DonneesDemo.codeExemple)
            : t("parcours.\(cle).texte")
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

/// **Le geste de l'étape, comme action VoiceOver de la bulle** : la vue désignée est sous
/// le voile modal, l'utilisateur de VoiceOver fait donc le geste d'ici (« Actions »).
private struct GesteAccessible: ViewModifier {
    let etape: EtapeParcours
    let actif: Bool

    func body(content: Content) -> some View {
        if actif {
            content.accessibilityAction(named: Text(t("parcours.\(etape.nom).action"))) {
                ParcoursGuide.partage.faireGeste()
            }
        } else {
            content
        }
    }
}

/// La jauge de progression : discrète, sans chiffre affiché — VoiceOver la lit
/// « Étape n sur 16 ».
private struct ProgressionParcours: View {
    let etape: Int

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    var body: some View {
        GeometryReader { geometrie in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.fondSegmentInactif)
                Capsule()
                    .fill(Color.encrePrimaire)
                    .frame(width: geometrie.size.width * CGFloat(etape) / CGFloat(EtapeParcours.total))
            }
        }
        .frame(height: 4)
        .animation(mouvementReduit ? nil : Mouvement.entree(Mouvement.passageEcran), value: etape)
        .accessibilityElement()
        .accessibilityLabel(t("parcours.a11y.etape", etape, EtapeParcours.total))
    }
}

/// « Compris », « Reprendre » : l'aplat ``Color/primaire`` pleine largeur de la bulle.
private struct BoutonBulle: View {
    let titre: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titre)
                .font(.actionBulle)
                .foregroundColor(.encreSurAplat)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.primaire,
                            in: RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
    }
}

// MARK: - La proposition de reprise

/// **« Reprendre le tutoriel ? »** — au lancement à froid, tant que le parcours n'est pas
/// terminé. « Plus tard » ne marque rien : la question reviendra au prochain lancement.
private struct VueProposition: View {

    var body: some View {
        let guide = ParcoursGuide.partage
        VStack(alignment: .leading, spacing: 0) {
            Text(t("parcours.reprise.titre"))
                .font(.titreBulle)
                .foregroundColor(.texte)
                .accessibilityAddTraits(.isHeader)
            Spacer().frame(height: 6)
            Text(t("parcours.reprise.texte", guide.etapeEnregistree.reprise.rawValue,
                   EtapeParcours.total))
                .font(.corps)
                .foregroundColor(.secondaire)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 18)
            BoutonBulle(titre: t("parcours.reprise.reprendre")) { guide.reprendre() }
            Spacer().frame(height: 4)
            Button { guide.plusTard() } label: {
                Text(t("parcours.reprise.plusTard"))
                    .font(.actionBulle)
                    .foregroundColor(.encrePrimaire)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(StyleAppui(.bouton))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface,
                    in: RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .padding(.vertical, VueBulleParcours.hauteurPointe)
        .compositingGroup()
        .ombreBloc()
        .accessibilityElement(children: .contain)
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

// MARK: - La pastille « Exemple »

/// **« Exemple »** — sur chaque écran de démo du parcours : ce qu'on y voit est fictif.
/// L'ambre ``Color/accent`` porte ``Color/encreSurClair``, fixe, comme la pastille
/// « Résultats » du widget.
struct PastilleExemple: View {
    var body: some View {
        Text(t("parcours.exemple"))
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.encreSurClair)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color.accent, in: Capsule())
            .accessibilityLabel(t("parcours.a11y.exemple"))
    }
}
