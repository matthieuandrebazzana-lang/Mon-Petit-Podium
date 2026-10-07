import SwiftUI

/// Une silhouette de chargement — **le seul composant** qui dessine un état de premier
/// chargement (`ios/CLAUDE.md` §3).
///
/// Elle ne sert **que quand aucune donnée n'est disponible** : les services passent par
/// ``CacheService``, qui affiche aussitôt ce qu'il connaît, et ne restent en `.chargement`
/// qu'au tout premier appel (ou après une déconnexion). Un rechargement garde donc le vrai
/// contenu à l'écran, jamais une silhouette. Les actions ponctuelles (envoi des pronostics,
/// sauvegarde de la livrée) gardent leur spinner : ce n'est pas le même état.
///
/// ## Le balayage
///
/// Un aplat `secondaire` à **15 %**, sur lequel une bande à **30 %** glisse de gauche à
/// droite (``Mouvement/balayageSquelette``, linéaire : c'est un mouvement continu, pas une
/// entrée). **La bande est calée sur l'écran, pas sur la forme** : toutes les silhouettes
/// d'un écran lisent la même horloge et la même position, la lumière passe donc sur elles
/// d'un seul geste au lieu de repartir de zéro dans chaque rectangle.
///
/// **Mouvement réduit** : aucun balayage — c'est un déplacement. L'aplat seul reste, il dit
/// déjà « ici viendra quelque chose » (/apple-design §14).
///
/// **Clair et sombre** : l'encre est un jeton (`secondaire` par défaut, `#543925` /
/// `#EBEBF0`), rien à câbler. Posée sur un drapeau, une silhouette prend `encreSurAplat`.
struct SkeletonView: View {

    /// Les quatre formes. Chacune a une taille par défaut, que l'appelant peut remplacer.
    enum Variante {
        /// 96 × 12, en gélule — un libellé, un score.
        case ligneCourte
        /// Pleine largeur × 12, en gélule — un nom, un sous-titre.
        case ligneLongue
        /// 56 × 56, rayon `champ` — une photo, un avatar.
        case blocCarre
        /// Pleine largeur × 120, rayon `carte` — une carte, un widget.
        case blocRectangulaire
    }

    let variante: Variante
    var largeur: CGFloat? = nil
    var hauteur: CGFloat? = nil
    var rayon: CGFloat? = nil
    var encre: Color = .secondaire

    init(_ variante: Variante,
         largeur: CGFloat? = nil,
         hauteur: CGFloat? = nil,
         rayon: CGFloat? = nil,
         encre: Color = .secondaire) {
        self.variante = variante
        self.largeur = largeur
        self.hauteur = hauteur
        self.rayon = rayon
        self.encre = encre
    }

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: rayonEffectif, style: .continuous)
        TimelineView(.animation(minimumInterval: nil, paused: mouvementReduit)) { contexte in
            GeometryReader { geometrie in
                forme.fill(remplissage(cadre: geometrie.frame(in: .global),
                                       instant: contexte.date))
            }
        }
        .frame(width: largeurFixe, height: hauteurEffective)
        .frame(maxWidth: largeurFixe == nil ? .infinity : nil, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: Géométrie

    private var largeurFixe: CGFloat? {
        if let largeur { return largeur }
        switch variante {
        case .ligneCourte: return 96
        case .blocCarre: return hauteur ?? 56
        case .ligneLongue, .blocRectangulaire: return nil
        }
    }

    private var hauteurEffective: CGFloat {
        if let hauteur { return hauteur }
        switch variante {
        case .ligneCourte, .ligneLongue: return 12
        case .blocCarre: return largeur ?? 56
        case .blocRectangulaire: return 120
        }
    }

    private var rayonEffectif: CGFloat {
        if let rayon { return rayon }
        switch variante {
        case .ligneCourte, .ligneLongue: return hauteurEffective / 2
        case .blocCarre: return Rayon.champ
        case .blocRectangulaire: return Rayon.carte
        }
    }

    // MARK: Le balayage

    /// Largeur parcourue par la bande — un peu plus que l'iPhone le plus large en portrait
    /// (440 pt), pour qu'elle entre et sorte entièrement hors champ.
    private static let course: CGFloat = 480
    /// Demi-largeur de la bande lumineuse.
    private static let demiBande: CGFloat = 90

    private static let opaciteFond = 0.15
    private static let opaciteLueur = 0.30

    /// Le dégradé de la forme : fond à 15 %, crête à 30 % au centre de la bande. Hors de la
    /// bande, `LinearGradient` prolonge ses couleurs d'extrémité — le fond, donc.
    private func remplissage(cadre: CGRect, instant: Date) -> LinearGradient {
        let fond = encre.opacity(Self.opaciteFond)
        guard !mouvementReduit, cadre.width > 0 else {
            return LinearGradient(colors: [fond], startPoint: .leading, endPoint: .trailing)
        }
        let periode = Mouvement.balayageSquelette
        let phase = instant.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: periode) / periode
        // Le centre de la bande, en coordonnées d'écran : de hors champ à gauche à hors
        // champ à droite.
        let centre = -Self.demiBande + CGFloat(phase) * (Self.course + 2 * Self.demiBande)
        let local = centre - cadre.minX
        return LinearGradient(
            stops: [.init(color: fond, location: 0),
                    .init(color: encre.opacity(Self.opaciteLueur), location: 0.5),
                    .init(color: fond, location: 1)],
            startPoint: UnitPoint(x: (local - Self.demiBande) / cadre.width, y: 0.5),
            endPoint: UnitPoint(x: (local + Self.demiBande) / cadre.width, y: 0.5))
    }
}

// MARK: - Le passage au vrai contenu

extension View {
    /// Le passage d'une silhouette au contenu arrivé — **posé sur le conteneur du
    /// `switch`**, jamais sur l'une de ses branches : c'est l'insertion et le retrait qui
    /// s'animent. La silhouette sort en fondu (``Mouvement/arriveeContenu``, 300 ms, courbe
    /// d'entrée) ; le vrai contenu, lui, entre par ``arriveeEnCascade(rang:)``.
    ///
    /// **Le conteneur le pose dans l'environnement** : une fois qu'il a montré une
    /// silhouette, les éléments qui apparaissent en lui glissent et se décalent. Un écran
    /// servi par le cache n'en montre jamais — son contenu est là d'emblée, sans entrée.
    ///
    /// > **Un `ZStack`, pas un `VStack`.** Pendant son fondu de sortie, la silhouette garde
    /// > sa place dans la mise en page : empilée, elle repousserait le contenu sous elle
    /// > puis le laisserait sauter vers le haut. Superposés, les deux se croisent.
    func fonduChargement(_ enChargement: Bool) -> some View {
        modifier(FonduChargement(enChargement: enChargement))
    }

    /// L'entrée d'un élément du vrai contenu à la place de sa silhouette : un fondu, et un
    /// glissement de ``Mouvement/glissementArrivee`` (12 pt) vers le haut, en
    /// ``Mouvement/arriveeContenu`` (300 ms, courbe d'entrée).
    ///
    /// `rang` est la place de l'élément dans sa série : chacun part
    /// ``Mouvement/decalageArrivee`` (50 ms) après le précédent, **sur cinq éléments au
    /// plus** (``Mouvement/cascadeArrivee``) — au-delà, tous partent avec le cinquième, pour
    /// ne pas faire attendre le bas d'une longue liste.
    ///
    /// **Mouvement réduit** : le fondu seul, tous ensemble — ni glissement ni cascade.
    ///
    /// Sans silhouette montrée avant lui (``View/fonduChargement(_:)``), l'élément est là
    /// d'emblée.
    ///
    /// `decalage` et `plafond` remplacent l'écart et le nombre d'éléments décalés pour une
    /// série plus longue — le classement d'un championnat (``Mouvement/decalageClassement``,
    /// ``Mouvement/cascadeClassement``).
    func arriveeEnCascade(rang: Int = 0,
                          decalage: TimeInterval = Mouvement.decalageArrivee,
                          plafond: Int = Mouvement.cascadeArrivee) -> some View {
        modifier(ArriveeEnCascade(rang: rang, decalage: decalage, plafond: plafond))
    }
}

extension View {
    /// **L'entrée du widget du Grand Prix de l'accueil** à la place de sa silhouette :
    /// `scale(0.95)` + fondu vers 1, sur ``Mouvement/apparitionWidget``. Même règle que
    /// ``View/arriveeEnCascade(rang:decalage:plafond:)`` : seulement après une silhouette,
    /// une seule fois. **Mouvement réduit** : le fondu seul, sur la courbe d'entrée.
    func apparitionWidget() -> some View {
        modifier(ApparitionWidget())
    }
}

extension AnyTransition {
    /// La branche du `switch` qui porte le vrai contenu : **elle n'ajoute pas son propre
    /// fondu** à l'entrée — ses éléments entrent eux-mêmes (``View/arriveeEnCascade(rang:)``),
    /// et deux fondus superposés retarderaient l'apparition. Sa sortie reste un fondu.
    static let contenuArrive = AnyTransition.asymmetric(insertion: .identity, removal: .opacity)
}

private struct ArriveeApresSquelette: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Vrai dans un conteneur qui a montré une silhouette (``FonduChargement``). Lu par les
    /// entrées d'ici, et par celles qu'un composant orchestre lui-même — la pile des
    /// championnats (``PileChampionnats``), qui échelonne ses cartes par profondeur.
    var arriveeApresSquelette: Bool {
        get { self[ArriveeApresSquelette.self] }
        set { self[ArriveeApresSquelette.self] = newValue }
    }
}

private struct FonduChargement: ViewModifier {

    let enChargement: Bool

    /// Posé **dès que la silhouette est montrée**, et non à l'arrivée du contenu : les
    /// éléments qui apparaissent alors lisent déjà la bonne valeur à leur `onAppear`.
    @State private var squeletteVu = false

    func body(content: Content) -> some View {
        content
            .environment(\.arriveeApresSquelette, squeletteVu)
            .animation(Mouvement.entree(Mouvement.arriveeContenu), value: enChargement)
            .onAppear { if enChargement { squeletteVu = true } }
            .onChange(of: enChargement) { _, charge in
                if charge { squeletteVu = true }
            }
    }
}

private struct ArriveeEnCascade: ViewModifier {

    let rang: Int
    let decalage: TimeInterval
    let plafond: Int

    @Environment(\.arriveeApresSquelette) private var apresSquelette
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @State private var arrive = false

    /// Masqué seulement en attendant sa propre entrée : un élément déjà là ne disparaît
    /// pas si le conteneur montre plus tard une silhouette.
    private var masque: Bool { apresSquelette && !arrive }

    func body(content: Content) -> some View {
        content
            .opacity(masque ? 0 : 1)
            .offset(y: masque && !mouvementReduit ? Mouvement.glissementArrivee : 0)
            .transition(.contenuArrive)
            .onAppear {
                guard apresSquelette, !arrive else {
                    arrive = true
                    return
                }
                let retard = mouvementReduit
                    ? 0
                    : Double(min(rang, plafond - 1)) * decalage
                withAnimation(Mouvement.entree(Mouvement.arriveeContenu).delay(retard)) {
                    arrive = true
                }
            }
    }
}

private struct ApparitionWidget: ViewModifier {

    @Environment(\.arriveeApresSquelette) private var apresSquelette
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @State private var arrive = false

    private var masque: Bool { apresSquelette && !arrive }

    func body(content: Content) -> some View {
        content
            .opacity(masque ? 0 : 1)
            .scaleEffect(masque && !mouvementReduit ? Mouvement.echelleApparition : 1)
            .transition(.contenuArrive)
            .onAppear {
                guard apresSquelette, !arrive else {
                    arrive = true
                    return
                }
                withAnimation(mouvementReduit
                              ? Mouvement.entree(Mouvement.arriveeContenu)
                              : Mouvement.apparitionWidget) {
                    arrive = true
                }
            }
    }
}
