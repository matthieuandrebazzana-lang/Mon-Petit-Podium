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

    /// La voiture du membre, peinte dans le résumé de la saison. `nil` tant que son profil
    /// n'est pas lu : une silhouette neutre tient la place.
    var voiture: VoitureMembre?

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
    @Environment(\.championnatParDefaut) private var championnatParDefaut

    private let margeLaterale: CGFloat = 16

    /// - Parameters:
    ///   - profilId: le membre ; `nil` = le compte connecté.
    ///   - championnatId: un championnat partagé ; `nil` = le premier des miens
    ///     (``EnvironmentValues/championnatParDefaut``).
    init(titre: String? = nil, profilId: UUID? = nil,
         championnatId: UUID? = nil, rang: Int? = nil, voiture: VoitureMembre? = nil) {
        self.titreRecu = titre
        self.rang = rang
        self.voiture = voiture
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
        gpActif?.slugDrapeau
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
                    ZStack(alignment: .top) { contenu }
                        .fonduChargement(enChargement)
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
                            .foregroundStyle(Color.encreSurAplat)
                    }
                    .accessibilityLabel(t("commun.fermer"))
                }
            }
        }
        .toolbar(gpOuvert == nil ? .visible : .hidden, for: .tabBar)
        .task { await donnees.charger(championnatConnu: championnatParDefaut) }
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
            SqueletteHistorique(margeLaterale: margeLaterale)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t("parGP.a11y.chargementGP"))

        case .echec(let erreur):
            EchecChargement(erreur: erreur) {
                Task { await donnees.charger(championnatConnu: championnatParDefaut) }
            }
            .padding(.horizontal, margeLaterale)

        case .sansChampionnat:
            EtatVideGrandsPrix(texte: t("historique.videAucunChampionnat"))
                .padding(.horizontal, margeLaterale)

        case .pret(let liste) where liste.isEmpty:
            VStack(spacing: 0) {
                resumeSaison
                    .padding(.horizontal, margeLaterale)
                    .arriveeEnCascade(rang: 0)
                Spacer().frame(height: 24)
                EtatVideGrandsPrix(texte: t("historique.videAucunGP"))
                    .padding(.horizontal, margeLaterale)
                    .arriveeEnCascade(rang: 1)
            }
            .transition(.contenuArrive)

        case .pret:
            VStack(spacing: 0) {
                resumeSaison
                    .padding(.horizontal, margeLaterale)
                    .arriveeEnCascade(rang: 0)

                Spacer().frame(height: 8)
                CarrouselGrandsPrix(grandsPrix: grandsPrix, actif: $actif, surDrapeau: surDrapeau,
                                    ouvert: gpOuvert, espace: espaceHeros, numero: numero(de:),
                                    ouvrir: ouvrir)
                    .arriveeEnCascade(rang: 1)
            }
            .transition(.contenuArrive)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre)
                .font(.titre)
                .tracking(Tracking.titre)
                // Blanc sur le drapeau voilé (≥ 4,5:1 par construction) · 15,37:1 sur le beige.
                .foregroundColor(surDrapeau ? .encreSurAplat : .texte)
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

    private var enChargement: Bool {
        if case .chargement = donnees.etat { return true }
        return false
    }

    /// `nil` tant qu'aucun pronostic n'est jugé.
    private var totalPoints: Int? {
        let juges = grandsPrix.compactMap(\.totalPoints)
        return juges.isEmpty ? nil : juges.reduce(0, +)
    }

    // MARK: - Résumé de la saison

    /// **Deux moitiés** : le total à gauche, et la voiture du membre à droite, museau vers
    /// le texte. **Une seule marge, posée sur le conteneur** : le texte touche le bord
    /// gauche de la zone utile, la voiture son bord droit, et aucun des deux ne porte de
    /// marge propre — sans quoi les deux écarts divergent au premier ajustement. La voiture
    /// est un calque : la hauteur du bandeau est celle du texte, et la voiture s'y règle.
    /// Le rang, quand on vient d'un championnat, suit l'intitulé en pastille — le coin, où
    /// il se rangeait, est à la voiture.
    private var resumeSaison: some View {
        HStack(spacing: 0) {
            texteResume
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(maxWidth: .infinity)
                .overlay { voitureResume }
        }
        .padding(.horizontal, margeResume)
        // Damier blanc au niveau des cartes de pronostic : au pire pixel le bordeaux
        // remonte à peine — blanc 9,83:1, `encreSecondaire` 5,41:1.
        .background {
            ZStack {
                Color.primaire
                Damier(opacite: Materiau.damierPronostic, encre: .encreSurAplat)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleResume)
    }

    /// Les trois lignes sont **centrées sur la plus longue**, « réussis sur tentés », et
    /// c'est elle seule qui donne sa largeur au bloc : son bord gauche est alors celui du
    /// texte, à la même distance du bord que la voiture du sien. Un gabarit invisible porte
    /// la hauteur des trois lignes mais la largeur de la dernière — l'intitulé et le total
    /// y sont réduits à une largeur nulle — et le bloc visible s'y pose en calque : il
    /// reçoit exactement cette largeur, sans rien mesurer à la main.
    private var texteResume: some View {
        VStack(spacing: 0) {
            enteteResume.fixedSize().frame(width: 0)
            Spacer().frame(height: 6)
            totalResume.fixedSize().frame(width: 0)
            Spacer().frame(height: 4)
            ligneReussis
        }
        .hidden()
        .overlay {
            VStack(alignment: .center, spacing: 0) {
                enteteResume
                Spacer().frame(height: 6)
                totalResume
                Spacer().frame(height: 4)
                ligneReussis
            }
        }
        .padding(.vertical, 20)
    }

    private var enteteResume: some View {
        HStack(spacing: 8) {
            Text(t("historique.totalSaison"))
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encreSecondaire)    // blanc 70 % — 5,75:1
                .lineLimit(1)
            if let rang { pastilleRang(rang) }
        }
    }

    private var totalResume: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(totalPoints.map(\.enPoints) ?? "—")
                .font(.scoreLg)
                .tracking(Tracking.scoreLg)
                .foregroundColor(.encreSurAplat)              // 10,88:1 sur le bordeaux
            if totalPoints != nil {
                Text(t("points.unite"))
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.encreSurAplat)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Réussis sur tentés : « 10 réussis » ne dit rien sans le nombre joué.
    private var ligneReussis: some View {
        Text(tp("historique.reussisSur", tentes, reussis))
            .font(.custom("HelveticaNeue", size: 13))
            .foregroundColor(.encreSecondaire)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    /// Tournée d'un quart de tour : la planche dessine la voiture museau en haut. Sa
    /// largeur — la hauteur à l'écran — vaut 88 % du bandeau, sa longueur ne dépasse
    /// jamais la moitié qui la porte. Elle touche le bord droit de cette moitié : la marge
    /// est celle du conteneur, pas la sienne. Avant la lecture du profil, une silhouette
    /// neutre de même emprise : le texte ne bouge pas quand la voiture arrive.
    private var voitureResume: some View {
        GeometryReader { cadre in
            let largeur = min(cadre.size.height * 0.88, cadre.size.width * VueVoiture.rapport)
            let longueur = largeur / VueVoiture.rapport
            Group {
                if let voiture {
                    VueVoiture(livree: voiture.livree, numero: voiture.numero,
                               nom: voiture.nom, photo: voiture.photo,
                               teintePilote: .primaire)
                } else {
                    RoundedRectangle(cornerRadius: largeur / 2, style: .continuous)
                        .fill(Color.encreSurAplat.opacity(0.12))
                }
            }
            .frame(width: largeur, height: longueur)
            .rotationEffect(.degrees(-90))
            // L'emprise tournée : la rotation ne change pas le cadre de mise en page.
            .frame(width: longueur, height: largeur)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }

    /// L'écart au bord du bandeau, posé une fois sur le conteneur : le même pour le texte
    /// à gauche et la voiture à droite.
    private let margeResume: CGFloat = 20

    /// Le rang seul : « Classement » ne tient pas à côté de l'intitulé dans la moitié
    /// gauche, et le libellé d'accessibilité le dit en entier. Blanc sur blanc 15 % posé
    /// sur le bordeaux : 8,1:1, plus de 7:1 sous le damier.
    private func pastilleRang(_ rang: Int) -> some View {
        Text(ordinal(rang))
            .font(.custom("HelveticaNeue-Medium", size: 13))
            .foregroundColor(.encreSurAplat)
            .lineLimit(1)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(Color.encreSurAplat.opacity(0.15))
            .clipShape(Capsule())
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
///
/// **Une seule carte ne défile pas** : posée centrée hors de tout `ScrollView`, sans point de
/// pagination. Dans le défilement, `defaultScrollAnchor(.trailing)`, résolu au premier tour
/// de mise en page — `largeur` encore à 0 —, la poussait de 80 pt hors de l'écran, et
/// aucune voisine ne venait ensuite recaler la position.
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
            if let seul = grandsPrix.first, grandsPrix.count == 1 {
                // Une carte seule ne défile pas : rien à faire glisser, pas de voisine à
                // montrer, et l'ancre de fin du défilement la poussait hors de l'écran.
                carte(seul)
                    .padding(.vertical, respiration)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: espacement) {
                        ForEach(grandsPrix) { gp in
                            carte(gp)
                                .scrollTransition(.interactive, axis: .horizontal) { [reduit = mouvementReduit] carte, phase in
                                    let ecart = min(abs(phase.value), 1)
                                    return carte
                                        .scaleEffect(reduit ? 1 : 1 - 0.1 * ecart)
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
            }

            // Un indicateur ne dit quelque chose qu'à partir de deux pages.
            if grandsPrix.count > 1 {
                PointsPagination(nombre: grandsPrix.count, actif: indexActif, surDrapeau: surDrapeau)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
        .onAppear { if actif == nil { actif = grandsPrix.last?.id } }
    }

    private func carte(_ gp: GrandsPrixJoues.GrandPrixJoue) -> some View {
        Button { ouvrir(gp.id) } label: {
            CarteCarrousel(gp: gp, numero: numero(gp))
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .frame(width: largeurCarte, height: hauteurCarte)
        .matchedGeometryEffect(id: IdHeros.carte(gp.id), in: espace, isSource: true)
        .opacity(ouvert == gp.id ? 0 : 1)
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
    private var encreActive: Color { surDrapeau ? .encreSurAplat : .encrePrimaire }
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
                        .background(Color.voile.opacity(0.25))
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
        .foregroundColor(.encreSurAplat)
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
                        .foregroundColor(.encreSurAplat.opacity(0.30))
                        .padding(36)
                }
                .overlay {
                    if clair {
                        // Nu en haut, voilé sous le nom : le voile plein est atteint avant
                        // la première ligne de texte du bas (≈ 58 % de la hauteur).
                        LinearGradient(stops: [
                            .init(color: .voile.opacity(0), location: 0.30),
                            .init(color: .voile.opacity(voile), location: 0.56),
                            .init(color: .voile.opacity(voile), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    } else {
                        Color.voile.opacity(voile)
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
                .background(Color.voile.opacity(voile))
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
struct FondDrapeauFlou: View {

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
            .overlay { Color.voile.opacity(ApparenceDrapeau.voileEncreSecondaire(pour: slug) ?? 0.4) }
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

    private var slugFond: String? { gp.slugDrapeau }

    // MARK: Le contenu

    private var contenu: some View {
        ContenuDetailGrandPrix(gp: gp, deploye: deploye)
            .allowsHitTesting(deploye)
    }
}

// MARK: - Le contenu du détail

/// L'en-tête centré (nom, date, points, réussis sur tentés, « Provisoire »), puis **une
/// carte par pronostic**, puis le podium réel — sur le drapeau flouté que pose l'hôte.
///
/// **Deux hôtes, un seul contenu** : la carte déployée du carrousel
/// (``DetailGrandPrixJoue``) et l'écran « Mes résultats » du widget de l'accueil
/// (``MesResultatsGPView``). C'est le même Grand Prix : deux mises en page écrites
/// séparément divergeraient au premier ajustement.
///
/// `deploye` pilote l'entrée décalée des blocs (``EntreeDetail``) ; un hôte sans héros
/// passe `true`, et tout est là d'emblée.
struct ContenuDetailGrandPrix: View {

    let gp: GrandsPrixJoues.GrandPrixJoue
    var deploye = true

    var body: some View {
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
    }

    private var entete: some View {
        VStack(spacing: 0) {
            Text(gp.fiche?.nom ?? gp.nom)
                .font(.titreLg)
                .tracking(Tracking.titreLg)
                .foregroundColor(.encreSurAplat)
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
            .foregroundColor(.encreSurAplat)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tp("classement.a11y.points", gp.totalPoints ?? 0))

            Spacer().frame(height: 4)

            Text(tp("historique.reussisSur", gp.pronostics.count, gp.reussis))
                .font(.custom("HelveticaNeue", size: 14))
                .foregroundColor(.encreSurAplat)
                .accessibilityLabel(tp("historique.a11y.reussisSur", gp.pronostics.count, gp.reussis))

            if gp.provisoire {
                Spacer().frame(height: 10)
                MentionProvisoire(encre: .encreSurAplat)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.encreSurAplat.opacity(0.15))
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
                    CarteVerdict(pronostic: pronostic, provisoire: gp.provisoire)
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
struct EntreeDetail: ViewModifier {

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
/// en pastille, puis les points — **la carte entière dit le verdict**, teinte comprise.
///
/// | État | Fond de carte | Icône | Verdict | Points |
/// |---|---|---|---|---|
/// | gagné | `vertSauge` à 7 % | ✓ blanc sur vert plein (4,86:1) | « GAGNÉ » blanc sur vert (4,86:1) | vert, grand texte (≥ 4,12:1) |
/// | perdu | `primaire` à 4 % | ✗ blanc sur bordeaux plein (10,88:1) | « PERDU » blanc sur bordeaux (10,88:1) | `0` en `grisSecondaire` |
/// | en attente | blanc | horloge grise sur beige | « EN ATTENTE » gris sur beige (4,71:1) | en jeu, en gris |
///
/// > **Le verdict est une pastille pleine, pas un texte vert.** Mesuré : le vert sauge
/// > tombe à **4,12:1** sur la carte teintée et damée, sous le plancher d'un texte
/// > ordinaire. Blanc sur vert plein, il tient 4,86:1 — et se lit de plus loin.
/// >
/// > **L'unité « pts » reste grise** à côté d'un nombre vert : le nombre est un grand
/// > texte (3:1 suffit), l'unité, à 12 pt, n'en est pas un.
///
/// En attente, les points sont ceux **en jeu**, en gris — jamais en rouge, qui annoncerait
/// un échec qui n'a pas eu lieu. Non évaluable : un tiret, il n'y a rien à juger.
///
/// Le damier (``Materiau/damierPronostic``) se coupe d'un coup par
/// ``Materiau/damierSurPronostics``.
struct CarteVerdict: View {

    let pronostic: PronosticMembre
    /// Le Grand Prix est provisoire : un verdict déjà rendu peut encore bouger.
    let provisoire: Bool

    private enum Etat { case gagne, perdu, enAttente, nonEvaluable }

    private var etat: Etat {
        if let gagnes = pronostic.pointsGagnes { return gagnes > 0 ? .gagne : .perdu }
        return pronostic.nonEvaluable ? .nonEvaluable : .enAttente
    }

    private var forme: RoundedRectangle {
        RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 14) {
            icone

            VStack(alignment: .leading, spacing: 4) {
                Text(pronostic.marche)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)     // ≥ 4,51:1 sur les trois fonds
                    .lineLimit(2)
                Text(pronostic.choix)
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundColor(.texte)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 6) {
                    pastilleVerdict
                    if provisoire && pronostic.pointsGagnes != nil {
                        MentionProvisoire()
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(valeur)
                        .font(.custom("HelveticaNeue-Medium", size: 26))
                        .tracking(Tracking.score)
                        .monospacedDigit()
                        .foregroundColor(encrePoints)
                    if etat != .nonEvaluable {
                        Text(t("points.unite"))
                            .font(.custom("HelveticaNeue", size: 12))
                            .foregroundColor(.grisSecondaire)
                    }
                }
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
        .background { fond }
        .clipShape(forme)
        .overlay { forme.strokeBorder(bordure, lineWidth: 1) }
        .ombreCarte()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible)
    }

    // MARK: Le fond

    private var fond: some View {
        ZStack {
            Color.surface
            teinte
            if Materiau.damierSurPronostics {
                Damier(opacite: Materiau.damierPronostic)
            }
        }
    }

    private var teinte: Color {
        switch etat {
        case .gagne: return Color.vertSauge.opacity(Materiau.teinteGagne)
        case .perdu: return Color.primaire.opacity(Materiau.teintePerdu)
        case .enAttente, .nonEvaluable: return .clear
        }
    }

    /// Le liseré du verdict : il détache la carte teintée du drapeau voilé.
    private var bordure: Color {
        switch etat {
        case .gagne: return Color.vertSauge.opacity(0.25)
        case .perdu: return Color.primaire.opacity(0.18)
        case .enAttente, .nonEvaluable: return .clear
        }
    }

    // MARK: Le verdict

    private var icone: some View {
        ZStack {
            Circle().fill(aplat)
            Image(systemName: symbole)
                .font(.system(size: 16, weight: etat == .gagne || etat == .perdu ? .bold : .medium))
                .foregroundColor(encreIcone)
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    private var pastilleVerdict: some View {
        Text(libelleEtat)
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(encreIcone)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(aplat, in: Capsule())
    }

    private var symbole: String {
        switch etat {
        case .gagne: return "checkmark"
        case .perdu: return "xmark"
        case .enAttente: return "clock"
        case .nonEvaluable: return "minus"
        }
    }

    /// L'aplat de l'icône **et** de la pastille : plein pour un verdict rendu.
    private var aplat: Color {
        switch etat {
        case .gagne: return .vertSauge
        case .perdu: return .primaire
        case .enAttente, .nonEvaluable: return .fondPrincipal
        }
    }

    private var encreIcone: Color {
        switch etat {
        case .gagne, .perdu: return .encreSurAplat
        case .enAttente, .nonEvaluable: return .grisSecondaire
        }
    }

    private var encrePoints: Color {
        etat == .gagne ? .encreSucces : .grisSecondaire
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
                            .foregroundColor(.encreSurAplat)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .ombreTexteDrapeau()
                        Text(gp.fiche?.dateAffichee ?? "")
                            .font(.custom("HelveticaNeue", size: 13))
                            .foregroundColor(.encreSurAplat)
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
                        .foregroundColor(.encreSurAplat)
                        .lineLimit(1)
                        .ombreTexteDrapeau()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(gp.totalPoints.map(\.enPoints) ?? "—")
                            .font(.custom("HelveticaNeue-Medium", size: 34))
                            .tracking(-0.85)              // grand chiffre : −0,025em × 34
                            .foregroundColor(.encreSurAplat)
                        Text(t("points.unite"))
                            .font(.custom("HelveticaNeue", size: 14))
                            .foregroundColor(.encreSurAplat)
                    }
                    .fixedSize()
                    .ombreTexteDrapeau()
                }
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.encreSurAplat)
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
            .foregroundColor(.encreSurAplat)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.encreSurAplat.opacity(0.20))
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
                        .foregroundColor(.encreSurAplat.opacity(0.30))
                        .padding(.vertical, 20)
                }
                .overlay { Color.voile.opacity(0.25) }
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
/// (``CarteVerdict``).
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
        self.shadow(color: .voile.opacity(0.6), radius: 4, x: 0, y: 2)
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

struct TuilePodium: View {

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

// MARK: - La silhouette

/// « Mes / Ses Grands Prix » pendant le premier chargement : le bandeau du résumé, puis le
/// carrousel — **à sa géométrie** (``CarrouselGrandsPrix``) : carte centrale de la largeur
/// moins 2 × 40 pt, haute de 60 % de la largeur, ses deux voisines réduites à 0,9 qui
/// dépassent des bords, 20 pt de respiration au-dessus et au-dessous.
private struct SqueletteHistorique: View {

    let margeLaterale: CGFloat

    @State private var largeur: CGFloat = 0

    private var largeurCarte: CGFloat { max(largeur - 80, 0) }
    private var hauteurCarte: CGFloat { (largeur * 0.6).rounded() }

    var body: some View {
        VStack(spacing: 8) {
            SkeletonView(.blocRectangulaire, hauteur: 112, rayon: Rayon.bloc)
                .padding(.horizontal, margeLaterale)

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: largeur == 0 ? 0 : hauteurCarte + 40)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
                .overlay {
                    if largeur > 0 {
                        HStack(spacing: 12) {
                            carte.scaleEffect(0.9)
                            carte
                            carte.scaleEffect(0.9)
                        }
                        .fixedSize()
                    }
                }
        }
    }

    private var carte: some View {
        SkeletonView(.blocRectangulaire, largeur: largeurCarte, hauteur: hauteurCarte,
                     rayon: Rayon.carrousel)
    }
}
