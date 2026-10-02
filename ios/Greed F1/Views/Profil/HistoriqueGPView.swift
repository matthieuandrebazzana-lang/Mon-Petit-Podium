import SwiftUI

/// **Ses Grands Prix** — ce qu'un membre a joué sur la saison, Grand Prix par Grand Prix.
///
/// Ouvert depuis ``ProfilMembreView`` et depuis ``ProfilView``, par la même ligne
/// (``LigneGrandsPrix``). Le résumé de la saison, puis **un carrousel** : une carte par
/// Grand Prix joué, la carte active centrée, ses voisines visibles de part et d'autre.
/// Taper une carte la **déploie en plein écran** : elle devient le détail de ses
/// pronostics (``DetailGrandPrixJoue``), par un `matchedGeometryEffect`.
///
/// > *Écart signalé (`CLAUDE.md` §3.2).* Le type porte « historique », terme proscrit du
/// > vocabulaire. **Rien de ce qui s'affiche ne le dit** : l'écran s'intitule
/// > « Ses Grands Prix ».
///
/// **Données** : ``GrandsPrixJoues`` — les routes de ``ResultatsParGPView``, relues pour
/// chaque GP terminé et filtrées sur le membre. Spinner pendant l'appel.
///
/// **Fond** : le drapeau de la carte active, **fortement flouté** et voilé jusqu'à la
/// mesure (``FondDrapeauFlou``), en fondu d'une carte à l'autre. La carte porte le même
/// drapeau, **net** : elle se lit comme la version au point du fond. Le beige tant qu'il
/// n'y a pas de carte.
struct HistoriqueGPView: View {

    /// « Ses Grands Prix », ou « Mes Grands Prix » depuis son propre profil. `nil` vaut
    /// « Ses Grands Prix », relu dans la langue de l'interface.
    var titreRecu: String?
    private var titre: String { titreRecu ?? t("profil.sesGrandsPrix") }

    /// Rang au classement du championnat d'où l'on vient ; `nil` depuis son propre profil.
    var rang: Int?

    @StateObject private var donnees: GrandsPrixJoues

    /// La carte centrée du carrousel.
    @State private var actif: UUID?
    /// Le Grand Prix dont le détail est monté — encore monté pendant le repli.
    @State private var gpOuvert: UUID?
    /// Le détail couvre l'écran (`true`) ou se tient sur sa carte (`false`). C'est cette
    /// valeur qui s'anime ; ``gpOuvert`` ne fait que monter et démonter le détail.
    @State private var deploye = false

    @Namespace private var espaceHeros

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private let margeLaterale: CGFloat = 16

    /// - Parameters:
    ///   - profilId: le membre ; `nil` = le compte connecté.
    ///   - championnatId: un championnat partagé ; `nil` = le premier des miens.
    init(titre: String? = nil, profilId: UUID? = nil,
         championnatId: UUID? = nil, rang: Int? = nil) {
        self.titreRecu = titre
        self.rang = rang
        _donnees = StateObject(wrappedValue: GrandsPrixJoues(profilId: profilId,
                                                             championnatId: championnatId))
    }

    /// Du plus ancien au plus récent — l'ordre du calendrier servi.
    private var grandsPrix: [GrandsPrixJoues.GrandPrixJoue] {
        if case .pret(let liste) = donnees.etat { return liste }
        return []
    }

    private var gpActif: GrandsPrixJoues.GrandPrixJoue? {
        grandsPrix.first { $0.id == actif } ?? grandsPrix.last
    }

    /// Le slug du drapeau actif ; `nil` = le beige du design system.
    private var slugFond: String? {
        gpActif.flatMap { $0.fiche != nil && TeintesDrapeaux.table[$0.slug] != nil ? $0.slug : nil }
    }

    /// Un drapeau derrière l'en-tête : son encre passe au blanc.
    private var surDrapeau: Bool { slugFond != nil }

    var body: some View {
        ZStack {
            FondDrapeauFlou(slug: slugFond)

            // L'ancre plein écran du héros : le détail déployé en prend le cadre.
            Color.clear
                .ignoresSafeArea()
                .matchedGeometryEffect(id: IdHeros.pleinEcran, in: espaceHeros, isSource: true)
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    entete
                        .padding(.horizontal, margeLaterale)

                    Spacer().frame(height: 20)
                    contenu
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDisabled(gpOuvert != nil)
            .accessibilityHidden(gpOuvert != nil)

            if let gp = grandsPrix.first(where: { $0.id == gpOuvert }) {
                DetailGrandPrixJoue(gp: gp, numero: numero(de: gp), espace: espaceHeros,
                                    deploye: deploye, fermer: fermer)
                    .zIndex(1)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(surDrapeau || gpOuvert != nil ? .dark : nil, for: .navigationBar)
        // Le retour ramènerait au profil, détail ouvert : il cède la place à la croix.
        .navigationBarBackButtonHidden(gpOuvert != nil)
        .toolbar {
            if gpOuvert != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: fermer) {
                        // Blanc : la teinte `primaire` de l'app disparaît sur le drapeau voilé.
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(t("commun.fermer"))
                }
            }
        }
        .toolbar(gpOuvert == nil ? .visible : .hidden, for: .tabBar)
        .task { await donnees.charger() }
    }

    // MARK: - Le héros

    /// Le détail est d'abord posé **exactement sur la carte**, puis se déploie au tour
    /// suivant : sans ce tour, il naîtrait déjà plein écran et rien ne bougerait.
    ///
    /// Taper la carte qui se replie la redéploie depuis où elle est — le ressort repart de
    /// la position affichée. Une autre carte attend la fin du repli.
    private func ouvrir(_ id: UUID) {
        if let gpOuvert, gpOuvert != id { return }
        let dejaMonte = gpOuvert == id
        gpOuvert = id
        let deployer = { withAnimation(mouvementReduit ? Mouvement.entree(0.2) : Mouvement.deploiement) { deploye = true } }
        if dejaMonte { deployer() } else { DispatchQueue.main.async(execute: deployer) }
    }

    private func fermer() {
        withAnimation(mouvementReduit ? Mouvement.entree(0.16) : Mouvement.repli) {
            deploye = false
        } completion: {
            // Redéployé pendant le repli : le détail reste.
            if !deploye { gpOuvert = nil }
        }
    }

    /// Le rang du Grand Prix dans la saison — celui du calendrier statique, « 01 » pour
    /// Zandvoort ; son rang dans la liste à défaut.
    private func numero(de gp: GrandsPrixJoues.GrandPrixJoue) -> String {
        let rang = GrandPrixSaison.saison2026.firstIndex { $0.slug == gp.slug }
            ?? grandsPrix.firstIndex { $0.id == gp.id } ?? 0
        return String(format: "%02d", rang + 1)
    }

    @ViewBuilder private var contenu: some View {
        switch donnees.etat {
        case .chargement:
            ProgressView()
                .tint(.secondaire)
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityLabel(t("parGP.a11y.chargementGP"))

        case .echec(let erreur):
            EchecChargement(erreur: erreur) {
                Task { await donnees.charger() }
            }
            .padding(.horizontal, margeLaterale)

        case .sansChampionnat:
            EtatVideGrandsPrix(texte: t("historique.videAucunChampionnat"))
                .padding(.horizontal, margeLaterale)

        case .pret(let liste) where liste.isEmpty:
            resumeSaison
                .padding(.horizontal, margeLaterale)
            Spacer().frame(height: 24)
            EtatVideGrandsPrix(texte: t("historique.videAucunGP"))
                .padding(.horizontal, margeLaterale)

        case .pret:
            resumeSaison
                .padding(.horizontal, margeLaterale)

            Spacer().frame(height: 8)
            CarrouselGrandsPrix(grandsPrix: grandsPrix, actif: $actif, surDrapeau: surDrapeau,
                                ouvert: gpOuvert, espace: espaceHeros, numero: numero(de:),
                                ouvrir: ouvrir)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre)
                .font(.titre)
                .tracking(Tracking.titre)
                // Blanc sur le drapeau voilé (≥ 4,5:1 par construction) · 15,37:1 sur le beige.
                .foregroundColor(surDrapeau ? .white : .texte)
                .accessibilityAddTraits(.isHeader)

            // `grisSecondaire` tient 4,71:1 sur le beige ; le blanc à 70 % tient 4,5:1 sur
            // le drapeau, voilé pour ça.
            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(surDrapeau ? .encreSecondaire : .grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Mouvement.deplacement(0.28), value: surDrapeau)
    }

    private var sousTitre: String {
        guard case .pret = donnees.etat else { return t("commun.saison2026") }
        return tp("historique.gpJoues", joues)
    }

    private var joues: Int { grandsPrix.count }

    /// `nil` tant qu'aucun pronostic n'est jugé.
    private var totalPoints: Int? {
        let juges = grandsPrix.compactMap(\.totalPoints)
        return juges.isEmpty ? nil : juges.reduce(0, +)
    }

    // MARK: - Résumé de la saison

    /// **Centré** : le total est la seule chose que ce bandeau dit, il se lit au milieu.
    /// Le rang, quand on vient d'un championnat, se range en pastille dans le coin — à
    /// l'écart du chiffre, qu'il ne décentre pas.
    private var resumeSaison: some View {
        VStack(spacing: 0) {
            Text(t("historique.totalSaison"))
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encreSecondaire)        // blanc 70 % — 5,75:1

            Spacer().frame(height: 6)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(totalPoints.map(\.enPoints) ?? "—")
                    .font(.scoreLg)
                    .tracking(Tracking.scoreLg)
                    .foregroundColor(.white)              // 10,88:1 sur le bordeaux
                if totalPoints != nil {
                    Text(t("points.unite"))
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                        .foregroundColor(.white)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Spacer().frame(height: 4)

            // Réussis sur tentés : « 10 réussis » ne dit rien sans le nombre joué.
            Text(tp("historique.reussisSur", tentes, reussis))
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.encreSecondaire)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .overlay(alignment: .topTrailing) {
            if let rang {
                VStack(spacing: 0) {
                    Text(ordinal(rang))
                        .font(.custom("HelveticaNeue-Medium", size: 18))
                        .foregroundColor(.white)
                    // **Blanc 70 % et non 50 %** : sur la pastille (blanc 15 % sur le
                    // bordeaux), 50 % ne tient que 3,15:1 — sous le plancher de 4,5:1 d'un
                    // texte de 10 pt. 70 % y tient 4,76:1.
                    Text(t("championnat.classement"))
                        .font(.labelSm)
                        .tracking(Tracking.label)
                        .textCase(.uppercase)
                        .foregroundColor(.encreSecondaire)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
                .padding(12)
            }
        }
        .background(Color.primaire)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleResume)
    }

    private var tentes: Int { grandsPrix.map(\.pronostics.count).reduce(0, +) }

    private var reussis: Int { grandsPrix.map(\.reussis).reduce(0, +) }

    private var libelleResume: String {
        var libelle = t("historique.a11y.total", tp("classement.a11y.points", totalPoints ?? 0),
                        tp("historique.a11y.reussisSur", tentes, reussis))
        if let rang { libelle += t("historique.a11y.rang", ordinal(rang)) }
        return libelle
    }
}

// MARK: - Le carrousel

/// Les Grands Prix joués, **un par page** — natif de bout en bout (`ScrollView` +
/// `scrollTargetBehavior(.viewAligned)`) : l'élan d'un balayage, l'aimantation sur une
/// carte et l'interruption au doigt sont ceux du système, rien n'est réimplémenté.
///
/// **Les voisines suivent le doigt** : échelle 0,9 et opacité 0,9 interpolées par
/// `scrollTransition(.interactive)` sur la position réelle, jamais une animation déclenchée
/// à l'arrivée. Sous « Réduire les animations », l'échelle tombe — c'est un mouvement —,
/// l'opacité reste.
///
/// **Il s'ouvre sur le plus récent** : c'est celui qu'on vient voir après une course.
private struct CarrouselGrandsPrix: View {

    let grandsPrix: [GrandsPrixJoues.GrandPrixJoue]
    @Binding var actif: UUID?
    /// Drapeau derrière le carrousel : les points de pagination passent au blanc.
    let surDrapeau: Bool
    /// La carte déployée en détail : masquée ici, c'est le détail qui la montre.
    let ouvert: UUID?
    /// Chaque carte y est la source du héros (``IdHeros/carte(_:)``).
    let espace: Namespace.ID
    let numero: (GrandsPrixJoues.GrandPrixJoue) -> String
    let ouvrir: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @State private var largeur: CGFloat = 0

    /// Ce qui dépasse des voisines, de chaque côté, avant leur réduction à 0,9.
    private let marge: CGFloat = 40
    private let espacement: CGFloat = 12
    /// Place laissée à l'ombre de la carte, que le défilement rognerait sinon.
    private let respiration: CGFloat = 20

    private var largeurCarte: CGFloat { max(largeur - 2 * marge, 0) }
    /// Environ 60 % de la largeur de l'écran.
    private var hauteurCarte: CGFloat { (largeur * 0.6).rounded() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: espacement) {
                    ForEach(grandsPrix) { gp in
                        Button { ouvrir(gp.id) } label: {
                            CarteCarrousel(gp: gp, numero: numero(gp))
                        }
                        .buttonStyle(StyleAppui(.grandeSurface))
                        .frame(width: largeurCarte, height: hauteurCarte)
                        .matchedGeometryEffect(id: IdHeros.carte(gp.id), in: espace, isSource: true)
                        .opacity(ouvert == gp.id ? 0 : 1)
                        .scrollTransition(.interactive, axis: .horizontal) { carte, phase in
                            let ecart = min(abs(phase.value), 1)
                            return carte
                                .scaleEffect(mouvementReduit ? 1 : 1 - 0.1 * ecart)
                                .opacity(1 - 0.1 * ecart)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, respiration)
            }
            .contentMargins(.horizontal, marge, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $actif)
            .defaultScrollAnchor(.trailing)
            .frame(height: hauteurCarte + 2 * respiration)

            PointsPagination(nombre: grandsPrix.count, actif: indexActif, surDrapeau: surDrapeau)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
        .onAppear { if actif == nil { actif = grandsPrix.last?.id } }
    }

    private var indexActif: Int {
        grandsPrix.firstIndex { $0.id == actif } ?? grandsPrix.count - 1
    }

}

// MARK: - Les points de pagination

/// Un point par carte ; l'actif s'allonge en capsule. **Un indicateur, pas une commande** :
/// le balayage suffit, et des points de 6 pt ne feraient jamais une cible de 44.
private struct PointsPagination: View {

    let nombre: Int
    let actif: Int
    let surDrapeau: Bool

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<nombre, id: \.self) { index in
                Capsule()
                    .fill(index == actif ? encreActive : encreInactive)
                    .frame(width: index == actif ? 18 : 6, height: 6)
            }
        }
        .animation(mouvementReduit ? nil : Mouvement.deplacement(0.22), value: actif)
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("historique.a11y.position", actif + 1, nombre))
    }

    // Le point actif porte le sens : blanc plein sur le drapeau, `primaire` sur le beige
    // (8,6:1). Les autres ne font que compter.
    private var encreActive: Color { surDrapeau ? .white : .primaire }
    private var encreInactive: Color { surDrapeau ? .encreGraphique : .secondaire.opacity(0.25) }
}

// MARK: - Une carte du carrousel

/// Numéro et date en haut, le tracé en filigrane au centre, le nom en grand, puis les
/// pronostics réussis et les points — ceux-ci en bas à droite, au plus gros corps.
///
/// **Fond** : le drapeau du pays hôte, **net** — le fond de l'écran en est la version
/// floutée —, puis le tracé, puis un voile noir **léger** : calculé pour 3:1 sur la bande
/// la plus claire (``ApparenceDrapeau/voile(pour:contraste:)``), là où l'ancien voile de
/// 4,5:1 éteignait le drapeau. Le texte ordinaire (13 et 14 pt) tient le reste par son
/// ombre portée (``View/ombreTexteDrapeau()``), comme le nom des cartes de pays.
///
/// **Drapeau clair** (bande blanche — ``ApparenceDrapeau/estClair(_:)``) : un voile
/// uniforme y changeait le blanc en gris, et la carte se lisait délavée. Le drapeau y
/// reste donc **nu** sur sa partie haute — les bandes gardent leurs vraies couleurs — et
/// le voile ne couvre que le bas, où sont le nom et les points. Le numéro et la date du
/// haut passent en pastilles sombres, chacune mesurée pour 4,5:1 sur la bande blanche.
private struct CarteCarrousel: View {

    let gp: GrandsPrixJoues.GrandPrixJoue
    let numero: String

    private var clair: Bool { gp.fiche != nil && ApparenceDrapeau.estClair(gp.slug) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(numero)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .monospacedDigit()
                    .modifier(PastilleCarte(voile: voilePastille))
                if gp.provisoire {
                    Text(StatutResultats.mention)
                        .font(.custom("HelveticaNeue", size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
                }
                Spacer(minLength: 8)
                Text(date)
                    .font(.custom("HelveticaNeue", size: 13))
                    .lineLimit(1)
                    .modifier(PastilleCarte(voile: voilePastille))
            }

            Spacer(minLength: 8)

            Text(nom)
                .font(.titreLg)
                .tracking(Tracking.titreLg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .ombreTexteDrapeau()

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(tp("historique.reussisSur", gp.pronostics.count, gp.reussis))
                    .font(.custom("HelveticaNeue", size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .ombreTexteDrapeau()
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(gp.totalPoints.map(\.enPoints) ?? "—")
                        .font(.scoreLg)
                        .tracking(Tracking.scoreLg)
                    Text(t("points.unite"))
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                }
                .fixedSize()
                .ombreTexteDrapeau()
            }
        }
        .foregroundColor(.white)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { fond }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carrousel, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Rayon.carrousel, style: .continuous))
        .ombreAplat()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible)
        .accessibilityHint(t("historique.a11y.ouvrir"))
        .accessibilityAddTraits(.isButton)
    }

    private var nom: String { gp.fiche?.nom ?? gp.nom }

    private var date: String {
        if let fiche = gp.fiche { return fiche.jourMoisAffiche }
        return gp.dateCourse?.formatted(.dateTime.day().month(.wide).locale(localeInterface)) ?? ""
    }

    /// **Des `overlay` et non un `ZStack`** — même raison que ``CarteGrandPrixJoue`` : le
    /// drapeau en `scaledToFill` déborde, et chaque `overlay` reçoit la taille exacte.
    @ViewBuilder private var fond: some View {
        if gp.fiche != nil {
            Color.clear
                .overlay {
                    Image("flag-\(gp.slug)")
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    Image("trace-\(gp.slug)")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.30))
                        .padding(36)
                }
                .overlay {
                    if clair {
                        // Nu en haut, voilé sous le nom : le voile plein est atteint avant
                        // la première ligne de texte du bas (≈ 58 % de la hauteur).
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0), location: 0.30),
                            .init(color: .black.opacity(voile), location: 0.56),
                            .init(color: .black.opacity(voile), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    } else {
                        Color.black.opacity(voile)
                    }
                }
                .clipped()
                .accessibilityHidden(true)
        } else {
            Color.primaire
        }
    }

    private var voile: Double {
        ApparenceDrapeau.voile(pour: gp.slug, contraste: 3) ?? 0.15
    }

    /// `nil` hors drapeau clair : le numéro et la date restent alors du texte nu, tenu par
    /// le voile uniforme et son ombre.
    private var voilePastille: Double? {
        clair ? ApparenceDrapeau.voile(pour: gp.slug, contraste: 4.5) : nil
    }

    private var libelleAccessible: String {
        "\(numero). " + t("historique.a11y.carte", nom, gp.fiche?.dateAffichee ?? date,
                          tp("classement.a11y.points", gp.totalPoints ?? 0),
                          tp("historique.a11y.reussisSur", gp.pronostics.count, gp.reussis))
    }
}

/// Le numéro ou la date en haut d'une carte : texte nu sur un drapeau sombre, pastille
/// noire translucide sur un drapeau clair, où le haut n'est pas voilé.
private struct PastilleCarte: ViewModifier {

    /// L'opacité de la pastille, mesurée pour 4,5:1 sur la bande la plus claire ; `nil` =
    /// pas de pastille.
    let voile: Double?

    func body(content: Content) -> some View {
        if let voile {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(voile))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
        } else {
            content.ombreTexteDrapeau()
        }
    }
}

/// Les identifiants du héros carte → détail, dans l'espace de ``HistoriqueGPView``.
private enum IdHeros: Hashable {
    /// Le cadre d'une carte du carrousel — la source tant que le détail est replié.
    case carte(UUID)
    /// Tout l'écran, zones sûres comprises — la source une fois le détail déployé.
    case pleinEcran
}

// MARK: - Le fond flouté

/// Le drapeau de la carte active, **flouté**, sur tout l'écran — la carte en est la
/// version nette.
///
/// > **Étiré, jamais recadré.** L'écran est en portrait, un drapeau en paysage : en
/// > `scaledToFill`, l'Italie ne montrait que sa bande centrale — le blanc —, et tout le
/// > fond virait au gris pâle. Étiré, il garde ses trois bandes ; le flou efface la
/// > déformation. Même règle que les drapeaux de nationalité. Le voile noir est **calculé** pour que l'en-tête tienne : titre blanc,
/// sous-titre à 70 % à 4,5:1 (``ApparenceDrapeau/voileEncreSecondaire(pour:)``).
///
/// **Un fondu d'un drapeau à l'autre**, jamais un glissement : c'est une couleur qui
/// change, pas un objet qui bouge — il reste donc sous « Réduire les animations ».
///
/// **Le nouveau drapeau se pose SUR l'ancien**, qui reste opaque dessous jusqu'à la fin du
/// fondu. Deux drapeaux qui se croisent en opacité laissent voir le beige à mi-course —
/// un éclair clair à chaque balayage. Deux calques montés au plus : le flou ne se calcule
/// pas pour les cartes qu'on ne voit pas.
private struct FondDrapeauFlou: View {

    let slug: String?

    /// Le drapeau précédent, posé sous le fondu.
    @State private var dessous: String?

    /// Assez pour que les emblèmes ne se lisent plus derrière l'en-tête, pas au point de
    /// fondre les bandes en une seule teinte.
    private let rayonFlou: CGFloat = 40

    var body: some View {
        ZStack {
            Color.fondPrincipal

            if let dessous { drapeau(dessous) }

            if let slug {
                drapeau(slug)
                    .id(slug)
                    .transition(.opacity)
            }
        }
        .animation(Mouvement.deplacement(0.28), value: slug)
        .onChange(of: slug) { ancien, _ in dessous = ancien }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drapeau(_ slug: String) -> some View {
        Color.clear
            .overlay {
                Image("flag-\(slug)")
                    .resizable()
                    // `opaque` : sans lui le flou ronge les bords en transparence.
                    .blur(radius: rayonFlou, opaque: true)
            }
            .overlay { Color.black.opacity(ApparenceDrapeau.voileEncreSecondaire(pour: slug) ?? 0.4) }
            .clipped()
    }
}

// MARK: - État vide

/// Sobre : le drapeau à damier de la ligne du profil, une phrase, rien d'autre.
private struct EtatVideGrandsPrix: View {

    let texte: String

    var body: some View {
        VStack(spacing: 12) {
            Image("icone-drapeau-damier")
                .renderingMode(.template)
                .foregroundColor(.secondaire)
                .accessibilityHidden(true)
            Text(texte)
                .font(.corps)
                .foregroundColor(.secondaire)             // 9,32:1 sur le beige
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(.horizontal, 24)
    }
}

// MARK: - Le détail d'un Grand Prix

/// La carte déployée : le drapeau flouté et voilé sur tout l'écran, l'en-tête centré
/// (nom, date, points, réussis sur tentés), puis **une carte par pronostic**.
///
/// ## Le héros
///
/// Deux calques. **Le fond** suit le `matchedGeometryEffect` : posé sur la carte du
/// carrousel (``IdHeros/carte(_:)``), il prend le cadre de l'écran (``IdHeros/pleinEcran``)
/// quand ``deploye`` passe à `true`, ses coins passant de ``Rayon/carrousel`` à 0. Il porte
/// la face de la carte, qui s'efface pendant qu'il grandit : la carte se déplie en fond.
/// **Le contenu**, lui, est toujours à pleine taille — il ne se déforme jamais — et entre
/// en fondu, une fois le fond assez grand pour le porter ; les cartes de pronostics en
/// décalé (``Mouvement/decalage``). Au repli, il sort d'un coup, sans décalage.
///
/// Sous « Réduire les animations », aucun cadre ne bouge : le détail apparaît en fondu,
/// déjà plein écran.
private struct DetailGrandPrixJoue: View {

    let gp: GrandsPrixJoues.GrandPrixJoue
    let numero: String
    let espace: Namespace.ID
    let deploye: Bool
    let fermer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    var body: some View {
        ZStack {
            fond
            contenu
        }
        .accessibilityAction(.escape, fermer)
    }

    // MARK: Le fond

    private var fond: some View {
        ZStack {
            FondDrapeauFlou(slug: slugFond)
            CarteCarrousel(gp: gp, numero: numero)
                .opacity(deploye ? 0 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: deploye ? 0 : Rayon.carrousel,
                                    style: .continuous))
        .matchedGeometryEffect(id: deploye || mouvementReduit ? IdHeros.pleinEcran : IdHeros.carte(gp.id),
                               in: espace, properties: .frame, isSource: false)
        .opacity(mouvementReduit && !deploye ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var slugFond: String? {
        gp.fiche != nil && TeintesDrapeaux.table[gp.slug] != nil ? gp.slug : nil
    }

    // MARK: Le contenu

    private var contenu: some View {
        ScrollView {
            VStack(spacing: 0) {
                entete
                    .modifier(EntreeDetail(deploye: deploye, rang: 0))

                section(t("historique.sectionPronos"), pronostics: obligatoires, depuis: 1)

                if !bonus.isEmpty {
                    section(t("recap.bonus"), pronostics: bonus, depuis: 1 + obligatoires.count)
                }

                if gp.podium.count == 3 {
                    titreSection(t("historique.resultatReel"))
                        .modifier(EntreeDetail(deploye: deploye, rang: 1 + gp.pronostics.count))
                    HStack(spacing: 8) {
                        ForEach(Array(gp.podium.enumerated()), id: \.offset) { index, pilote in
                            TuilePodium(position: index + 1, pilote: pilote)
                        }
                    }
                    .padding(10)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
                    .ombreCarte()
                    .modifier(EntreeDetail(deploye: deploye, rang: 1 + gp.pronostics.count))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .contentShape(Rectangle())
        .allowsHitTesting(deploye)
    }

    private var entete: some View {
        VStack(spacing: 0) {
            Text(gp.fiche?.nom ?? gp.nom)
                .font(.titreLg)
                .tracking(Tracking.titreLg)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            if let date = gp.fiche?.dateAffichee {
                Spacer().frame(height: 4)
                // Blanc 70 % : le voile du fond est calculé pour qu'il tienne 4,5:1.
                Text(date)
                    .font(.custom("HelveticaNeue", size: 14))
                    .foregroundColor(.encreSecondaire)
            }

            Spacer().frame(height: 20)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(gp.totalPoints.map(\.enPoints) ?? "—")
                    .font(.scoreLg)
                    .tracking(Tracking.scoreLg)
                if gp.totalPoints != nil {
                    Text(t("points.unite"))
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                }
            }
            .foregroundColor(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tp("classement.a11y.points", gp.totalPoints ?? 0))

            Spacer().frame(height: 4)

            Text(tp("historique.reussisSur", gp.pronostics.count, gp.reussis))
                .font(.custom("HelveticaNeue", size: 14))
                .foregroundColor(.white)
                .accessibilityLabel(tp("historique.a11y.reussisSur", gp.pronostics.count, gp.reussis))

            if gp.provisoire {
                Spacer().frame(height: 10)
                MentionProvisoire(encre: .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func section(_ titre: String, pronostics: [PronosticMembre], depuis rang: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titreSection(titre)
                .modifier(EntreeDetail(deploye: deploye, rang: rang))
            VStack(spacing: 10) {
                ForEach(Array(pronostics.enumerated()), id: \.element.id) { index, pronostic in
                    CartePronostic(pronostic: pronostic, provisoire: gp.provisoire)
                        .modifier(EntreeDetail(deploye: deploye, rang: rang + index))
                }
            }
        }
    }

    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.encreSecondaire)            // 4,5:1 sur le fond, par le voile
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 24)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }

    private var obligatoires: [PronosticMembre] { gp.pronostics.filter { $0.type != "bonus" } }
    private var bonus: [PronosticMembre] { gp.pronostics.filter { $0.type == "bonus" } }
}

/// L'entrée d'un bloc du détail : fondu et 12 pt de montée, une fois le fond assez grand
/// pour le porter, puis chaque bloc ``Mouvement/decalage`` après le précédent. La sortie
/// est immédiate et commune — on ne regarde pas partir ce qu'on vient de fermer.
private struct EntreeDetail: ViewModifier {

    let deploye: Bool
    let rang: Int

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    func body(content: Content) -> some View {
        content
            .opacity(deploye ? 1 : 0)
            .offset(y: deploye || mouvementReduit ? 0 : 12)
            .animation(animation, value: deploye)
    }

    private var animation: Animation {
        guard deploye else { return Mouvement.entree(0.12) }
        if mouvementReduit { return Mouvement.entree(0.2) }
        // Les huit premiers seulement : au-delà, les blocs sont sous le pli.
        // 160 ms : le ressort a alors couvert les trois quarts du chemin, le fond porte
        // l'en-tête — plus tôt, il se posait encore sur le titre de la page.
        let retard = 0.16 + Double(min(rang, 8)) * Mouvement.decalage
        return Mouvement.entree(0.28).delay(retard)
    }
}

// MARK: - Une carte de pronostic

/// Un pronostic du détail : l'icône du verdict, le marché, ce qui a été joué, le verdict
/// en toutes lettres, puis les points.
///
/// **Sur le blanc**, où les encres de ``Verdict`` et ``PastillePoints`` sont mesurées —
/// les mêmes couples, à plus grande taille :
///
/// | État | Encre | Icône sur son aplat |
/// |---|---|---|
/// | gagné | vert sauge, **4,86:1** | 4,01:1 sur le vert à 15 % |
/// | perdu | bordeaux `primaire`, **8,6:1** | 8,94:1 sur le bordeaux à 10 % |
/// | en attente, non évaluable | `grisSecondaire`, **5,33:1** | 4,71:1 sur le beige |
///
/// En attente, les points sont ceux **en jeu**, en gris — jamais en rouge, qui annoncerait
/// un échec qui n'a pas eu lieu. Non évaluable : un tiret, il n'y a rien à juger.
private struct CartePronostic: View {

    let pronostic: PronosticMembre
    /// Le Grand Prix est provisoire : un verdict déjà rendu peut encore bouger.
    let provisoire: Bool

    private enum Etat { case gagne, perdu, enAttente, nonEvaluable }

    private var etat: Etat {
        if let gagnes = pronostic.pointsGagnes { return gagnes > 0 ? .gagne : .perdu }
        return pronostic.nonEvaluable ? .nonEvaluable : .enAttente
    }

    var body: some View {
        HStack(spacing: 14) {
            icone

            VStack(alignment: .leading, spacing: 3) {
                Text(pronostic.marche)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)     // 5,33:1 sur le blanc
                    .lineLimit(2)
                Text(pronostic.choix)
                    .font(.custom("HelveticaNeue-Medium", size: 16))
                    .foregroundColor(.texte)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 8) {
                    Text(libelleEtat)
                        .font(.custom("HelveticaNeue-Medium", size: 13))
                        .foregroundColor(encre)
                    if provisoire && pronostic.pointsGagnes != nil {
                        MentionProvisoire()
                    }
                }
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(valeur)
                        .font(.custom("HelveticaNeue-Medium", size: 22))
                        .monospacedDigit()
                    if etat != .nonEvaluable {
                        Text(t("points.unite"))
                            .font(.custom("HelveticaNeue", size: 12))
                    }
                }
                .foregroundColor(encre)
                if etat == .enAttente {
                    Text(t("parGP.enJeu"))
                        .font(.custom("HelveticaNeue", size: 11))
                        .foregroundColor(.grisSecondaire)
                }
            }
            .fixedSize()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        .ombreCarte()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible)
    }

    private var icone: some View {
        ZStack {
            Circle().fill(aplat)
            Image(systemName: symbole)
                .font(.system(size: 15, weight: etat == .enAttente ? .medium : .bold))
                .foregroundColor(encre)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private var symbole: String {
        switch etat {
        case .gagne: return "checkmark"
        case .perdu: return "xmark"
        case .enAttente: return "clock"
        case .nonEvaluable: return "minus"
        }
    }

    private var aplat: Color {
        switch etat {
        case .gagne: return Color.vertSauge.opacity(0.15)
        case .perdu: return Color.primaire.opacity(0.10)
        case .enAttente, .nonEvaluable: return .fondPrincipal
        }
    }

    private var encre: Color {
        switch etat {
        case .gagne: return .vertSauge
        case .perdu: return .primaire
        case .enAttente, .nonEvaluable: return .grisSecondaire
        }
    }

    private var libelleEtat: String {
        switch etat {
        case .gagne: return t("historique.statut.gagne")
        case .perdu: return t("historique.statut.perdu")
        case .enAttente: return t("historique.statut.enAttente")
        case .nonEvaluable: return t("parGP.nonEvaluable")
        }
    }

    /// Ce qu'il a rapporté, `0` s'il est raté — ce qu'il peut rapporter tant qu'il attend.
    private var valeur: String {
        switch etat {
        case .gagne, .perdu: return (pronostic.pointsGagnes ?? 0).enPoints
        case .enAttente: return (pronostic.points ?? 0).enPoints
        case .nonEvaluable: return "–"
        }
    }

    private var libelleAccessible: String {
        let verdict: String
        switch etat {
        case .nonEvaluable: verdict = t("parGP.a11y.nonEvaluable")
        case .enAttente: verdict = tp("parGP.a11y.enAttente", pronostic.points ?? 0)
        case .gagne: verdict = tp("parGP.a11y.gagne", pronostic.pointsGagnes ?? 0)
        case .perdu: verdict = t("parGP.a11y.rate")
        }
        var libelle = t("resultats.a11y.pronostic", pronostic.marche, pronostic.choix, verdict)
        if provisoire && pronostic.pointsGagnes != nil { libelle += ", " + StatutResultats.detail }
        return libelle
    }
}

// MARK: - Une carte de Grand Prix

/// **Non montée depuis le carrousel** (`CLAUDE.md` §6 : le code éprouvé reste en place).
///
/// Une carte par Grand Prix joué, **sur le modèle du widget de l'accueil** : le même
/// empilement de calques, dans le même ordre — drapeau · tracé · voile · contenu.
///
/// La partie haute a une hauteur fixe : les cartes s'alignent en colonne régulière, et
/// l'ouverture de l'une ne décale jamais le contenu des autres, seulement leur position.
/// La partie basse, blanche, se déplie dessous et partage le rayon de la carte.
private struct CarteGrandPrixJoue: View {

    let gp: GrandsPrixJoues.GrandPrixJoue
    let ouvert: Bool
    let basculer: () -> Void

    private let hauteur: CGFloat = 160
    private let rembourrage: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            Button(action: basculer) { haut }
                .buttonStyle(StyleAppui(.grandeSurface))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(libelleAccessible)
                .accessibilityValue(ouvert ? t("commun.deplie") : t("commun.replie"))
                .accessibilityAddTraits(.isButton)

            if ouvert {
                DetailPronosGP(gp: gp)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
    }

    // MARK: La partie haute

    private var haut: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(gp.fiche?.nom ?? gp.nom)
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .ombreTexteDrapeau()
                        Text(gp.fiche?.dateAffichee ?? "")
                            .font(.custom("HelveticaNeue", size: 13))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .ombreTexteDrapeau()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    badgeStatut
                }

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(tp("historique.reussisSur", gp.pronostics.count, gp.reussis))
                        .font(.custom("HelveticaNeue-Medium", size: 14))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .ombreTexteDrapeau()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(gp.totalPoints.map(\.enPoints) ?? "—")
                            .font(.custom("HelveticaNeue-Medium", size: 34))
                            .tracking(-0.85)              // grand chiffre : −0,025em × 34
                            .foregroundColor(.white)
                        Text(t("points.unite"))
                            .font(.custom("HelveticaNeue", size: 14))
                            .foregroundColor(.white)
                    }
                    .fixedSize()
                    .ombreTexteDrapeau()
                }
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(ouvert ? 180 : 0))
                .frame(width: 16)
                .accessibilityHidden(true)
        }
        .padding(rembourrage)
        .frame(maxWidth: .infinity)
        .frame(height: hauteur)
        .background { fond }
        .clipped()
        // Le drapeau en `scaledToFill` déborde : la cible est la surface visible, rien d'autre.
        .contentShape(Rectangle())
    }

    /// Tous les Grands Prix de l'écran sont terminés — il ne liste que ceux qui ont été
    /// joués et jugés. **« Provisoire » prend la place de « Terminé »** jusqu'au calcul
    /// définitif (24 h après la course) : même pastille, même encre sur le drapeau voilé,
    /// seul le mot change.
    private var badgeStatut: some View {
        Text(gp.provisoire ? StatutResultats.mention : EtatGp.termine.libelle)
            .font(.custom("HelveticaNeue", size: 11))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
            .fixedSize()
    }

    /// **L'ordre des calques est celui du widget de l'accueil, et il ne se défait pas.**
    ///
    /// 1. Le drapeau, en `scaledToFill` — il couvre toute la carte, rogné sur son plus
    ///    grand côté, jamais déformé (`object-fit: cover`).
    /// 2. Le tracé, centré, blanc à 30 % : un filigrane — le nom dit déjà de quel circuit
    ///    il s'agit.
    /// 3. Le voile noir à 25 %, sur toute la surface — jamais sur une bande seule, sinon
    ///    un drapeau à bandes se lirait coupé en deux.
    ///
    /// **Des `overlay` et non un `ZStack`** : un `ZStack` prend la taille de son plus grand
    /// enfant — le drapeau débordant — et le tracé s'ajustait alors à cette boîte trop
    /// grande. Chaque `overlay` reçoit, lui, la taille exacte de la carte.
    @ViewBuilder private var fond: some View {
        if gp.fiche != nil {
            Color.clear
                .overlay {
                    Image("flag-\(gp.slug)")
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    Image("trace-\(gp.slug)")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.30))
                        .padding(.vertical, 20)
                }
                .overlay { Color.black.opacity(0.25) }
                .clipped()
                .accessibilityHidden(true)
        } else {
            // GP hors calendrier statique : l'aplat de la marque, sans drapeau à voiler.
            Color.primaire
        }
    }

    private var libelleAccessible: String {
        t("historique.a11y.carte", gp.fiche?.nom ?? gp.nom, gp.fiche?.dateAffichee ?? "",
          tp("classement.a11y.points", gp.totalPoints ?? 0),
          tp("historique.a11y.reussisSur", gp.pronostics.count, gp.reussis))
    }
}

// MARK: - Le détail des pronostics

/// Les pronostics d'un Grand Prix joué — obligatoires, bonus, puis le podium réel. **Le
/// seul propriétaire de ce contenu** pour la partie basse de ``CarteGrandPrixJoue``, non
/// montée. Le détail déployé (``DetailGrandPrixJoue``) a ses propres cartes
/// (``CartePronostic``).
private struct DetailPronosGP: View {

    let gp: GrandsPrixJoues.GrandPrixJoue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **Toutes les entrées, sans plafond** : vainqueur, podium, puis les bonus.
            VStack(spacing: 12) {
                ForEach(obligatoires) { RangeeHistorique(pronostic: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if !bonus.isEmpty {
                titreSection(t("recap.bonus"))

                VStack(spacing: 12) {
                    ForEach(bonus) { RangeeHistorique(pronostic: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if gp.podium.count == 3 {
                titreSection(t("historique.resultatReel"))

                HStack(spacing: 8) {
                    ForEach(Array(gp.podium.enumerated()), id: \.offset) { index, pilote in
                        TuilePodium(position: index + 1, pilote: pilote)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var obligatoires: [PronosticMembre] { gp.pronostics.filter { $0.type != "bonus" } }
    private var bonus: [PronosticMembre] { gp.pronostics.filter { $0.type == "bonus" } }

    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)             // 5,33:1 sur le blanc
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .accessibilityAddTraits(.isHeader)
    }
}

/// L'ombre du texte posé sur le drapeau. **Le texte s'impose par sa propre force, pas
/// par un voile** — même principe que les noms de pays du calendrier, en plus appuyé :
/// le texte de la carte est plus grand, et le drapeau couvre toute la surface.
private extension View {
    func ombreTexteDrapeau() -> some View {
        self.shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Un pronostic

/// Le marché, la sélection, puis ce qu'il a rapporté — la structure de
/// ``SectionMesResultats``, avec ses deux composants.
private struct RangeeHistorique: View {

    let pronostic: PronosticMembre

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pronostic.marche)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)     // 5,33:1 sur le blanc
                    .lineLimit(1)
                Text(pronostic.choix)
                    .font(.custom("HelveticaNeue", size: 14))
                    .foregroundColor(.texte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PastillePoints(pointsGagnes: pronostic.pointsGagnes, points: pronostic.points ?? 0)
                .fixedSize()
            Verdict(pointsGagnes: pronostic.pointsGagnes, nonEvaluable: pronostic.nonEvaluable)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("resultats.a11y.pronostic", pronostic.marche, pronostic.choix, verdict))
    }

    private var verdict: String {
        if pronostic.nonEvaluable { return t("parGP.a11y.nonEvaluable") }
        guard let gagnes = pronostic.pointsGagnes else {
            return tp("parGP.a11y.enAttente", pronostic.points ?? 0)
        }
        return gagnes > 0 ? tp("parGP.a11y.gagne", gagnes) : t("parGP.a11y.rate")
    }
}

// MARK: - Une marche du podium

private struct TuilePodium: View {

    let position: Int
    let pilote: LigneResultat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ordinal(position))
                .font(.labelSm)
                .tracking(Tracking.label)
                .foregroundColor(.secondaire)
            Text(pilote.prenom)
                .font(.custom("HelveticaNeue", size: 12))
                .foregroundColor(.texte)
                .lineLimit(1)
            Text(pilote.nom)
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .foregroundColor(.texte)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(pilote.equipe ?? "")
                .font(.custom("HelveticaNeue", size: 11))
                .foregroundColor(.secondaire)             // 9,32:1 beige · 11,0:1 ambre
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(position == 1 ? Color.ambreClair : Color.fondPrincipal)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ordinal(position)), \(pilote.prenom) \(pilote.nom), \(pilote.equipe ?? "")")
    }
}

#Preview {
    NavigationStack {
        HistoriqueGPView()
    }
}
