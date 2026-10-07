import SwiftUI

/// Onglet **Calendrier** — les douze Grands Prix de la fin de saison 2026, du GP des
/// Pays-Bas à Abu Dhabi.
///
/// Références visuelles : `Ressources/Screenshots/screen-08-calendrier-haut.PNG`,
/// `screen-09-calendrier-milieu.PNG` et `screen-10-calendrier-bas.PNG`.
///
/// > **La liste est statique, les états sont réels.** ``GrandPrixSaison/saison2026`` porte
/// > les douze cartes ; ``CalendrierSaison`` (`GET /calendrier`) leur ajoute ce que
/// > seule la base sait — **l'identifiant, le statut et l'existence de cotes**. Le
/// > rapprochement se fait par ``SlugCircuit``, jamais par le nom brut. L'échec de
/// > l'appel fait perdre les états, jamais la liste (`docs/swift-app.md` §7.6).
///
/// ## La liste est statique, et c'est un choix
///
/// `public.grands_prix` ne contient que ce que le scraper a rencontré, et Unibet n'expose
/// jamais que le Grand Prix suivant : un calendrier lu en base afficherait **une** course
/// au milieu d'une saison qui en compte douze. Le calendrier de la Formule 1 est une
/// donnée publique et stable — elle n'a pas à être découverte chez un bookmaker. C'est le
/// raisonnement de la version web, et il vaut ici à l'identique.
///
/// **Le quantième et le mois sont écrits, jamais dérivés d'une `Date`.** `2026-08-23`
/// analysée comme une date nue vaut minuit UTC : en tirer le jour rendrait « 22 » pour
/// tout téléphone à l'ouest de Greenwich, et le calendrier annoncerait la veille de chaque
/// course sur la moitié de la planète.
struct CalendrierView: View {

    /// Marge latérale commune à tous les écrans — la même que `AccueilView` et
    /// `ChampionnatsView`, sans quoi les onglets ne s'aligneraient pas au passage de l'un
    /// à l'autre.
    private let margeLaterale: CGFloat = 16

    /// Espacement entre deux cartes. C'est aussi la **marge de défilement** : voir
    /// ``ancreDefilement``.
    private let espacement: CGFloat = 12

    // MARK: - Données

    /// Possédé par l'écran, servi par le cache *stale-while-revalidate* (``CacheService``, 5 min, §7.6).
    @StateObject private var calendrier = CalendrierSaison()

    /// Les douze cartes, croisées avec ce que la base sait — ou avec rien, tant qu'elle n'a
    /// pas répondu : leurs états sont alors **inconnus**, pas « à venir ».
    private var grandsPrix: [GrandPrixSaison] {
        GrandPrixSaison.saison2026(croiseeAvec: calendrier.enBase)
    }

    /// **Le décompte se lit sur les cartes**, il ne vient pas d'ailleurs. `nil` tant que les
    /// états sont inconnus : « 12 Grands Prix restants » serait une affirmation non vérifiée.
    private var restants: Int? {
        guard calendrier.enBase != nil else { return nil }
        return GPRestants.compte(dans: grandsPrix)
    }

    /// Le premier Grand Prix qui n'est pas derrière nous, `nil` si la saison est finie ou
    /// si les états sont inconnus. La liste est dans l'ordre de la saison : « le premier non
    /// terminé » est bien le prochain à courir — `indexProchainGpSaison` du web.
    private var prochain: GrandPrixSaison? {
        guard calendrier.enBase != nil else { return nil }
        return grandsPrix.first { $0.etat != .termine }
    }

    /// Le défilement ne s'est produit qu'une fois. Sans ce garde-fou, revenir sur l'onglet
    /// arracherait l'écran des mains de quelqu'un en train de lire une carte plus bas.
    @State private var defilementFait = false

    var body: some View {
        // **Une pile par onglet, et non une pile autour de la barre** — c'est le choix déjà
        // fait par l'accueil et par la liste des championnats : sans elle, le retour depuis
        // les résultats d'un Grand Prix ramènerait sur un autre onglet que celui d'où l'on
        // est parti.
        NavigationStack {
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                ScrollViewReader { lecteur in
                    ScrollView {
                        VStack(spacing: 0) {
                            entete

                            Spacer().frame(height: 16)
                            etatChargement
                            liste
                        }
                        .padding(.horizontal, margeLaterale)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    // Le prochain Grand Prix n'est connu qu'après l'appel : le défilement
                    // attend donc les états, et part dès qu'ils arrivent.
                    .onAppear { ouvrirSurLeProchainGp(lecteur) }
                    .onChange(of: prochain?.slug) { ouvrirSurLeProchainGp(lecteur) }
                }
            }
            // Le titre de l'écran est dans le contenu, à 28 pt : la barre système ferait
            // doublon et se contente de nommer le retour des écrans poussés d'ici.
            .navigationTitle(t("onglet.calendrier"))
            .toolbar(.hidden, for: .navigationBar)
            .task { await calendrier.charger() }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("onglet.calendrier"))
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)        // 15,37:1 sur le beige
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            // **`grisSecondaire` et non `texteDoux`.** La version web pose ici son
            // `#999999`, qui ne vaut que 2,52:1 sur le beige — sous le plancher de 4,5:1
            // d'un texte ordinaire. `#6B6B6B` y tient 4,71:1 pour un gris que l'œil ne
            // distingue pas du premier. Le contraste se mesure (`ios/CLAUDE.md` §3).
            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var sousTitre: String {
        guard let restants else { return t("commun.saison2026") }
        return GPRestants.libelle(restants)
    }

    // MARK: - Chargement et échec

    /// **Au-dessus de la liste, jamais à sa place** : les douze cartes sont statiques et
    /// restent lisibles pendant l'attente comme après un échec — seuls leurs états
    /// manquent. Le spinner ne vient qu'au premier chargement ; un rechargement garde les
    /// états déjà affichés, sans quoi chaque retour sur l'onglet ferait sauter la liste.
    @ViewBuilder private var etatChargement: some View {
        switch calendrier.etat {
        case .chargement:
            ProgressView()
                .tint(.secondaire)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, espacement)
                .accessibilityLabel(t("calendrier.a11y.chargement"))

        case .echec(let erreur):
            EchecChargement(erreur: erreur) {
                Task { await calendrier.charger() }
            }
            .padding(.bottom, espacement)

        case .pret:
            EmptyView()
        }
    }

    // MARK: - La liste

    /// L'espacement est posé par des cales explicites plutôt que par le `spacing` du
    /// `VStack`, et ce n'est pas cosmétique : **la cale est l'ancre de défilement**.
    /// Voir ``ancreDefilement``.
    private var liste: some View {
        VStack(spacing: 0) {
            ForEach(Array(grandsPrix.enumerated()), id: \.element.slug) { rang, gp in
                Color.clear
                    .frame(height: rang == 0 ? 0 : espacement)
                    .id(ancreDefilement(gp))

                // **Deux destinations, un seul départage** : un Grand Prix couru ouvre ses
                // résultats, les trois autres états ouvrent la fiche du week-end. Ces
                // trois-là tombaient auparavant sur un `Button` à l'action vide — la carte
                // s'enfonçait sous le doigt et rien ne s'ouvrait.
                //
                // **L'identifiant réel du Grand Prix voyage avec la carte** — c'est lui que
                // les résultats et les pronostics demanderont (étapes 6 et 7). Un « Terminé »
                // vient forcément de la base : il a donc toujours le sien.
                NavigationLink {
                    if gp.etat == .termine {
                        ResultatsGPView(nom: gp.nom, date: gp.dateAffichee, gpId: gp.gpId)
                    } else {
                        DetailGPView(grandPrix: gp)
                    }
                } label: {
                    CarteGrandPrixSaison(grandPrix: gp)
                }
                .buttonStyle(StyleAppui(.grandeSurface))
            }
        }
    }

    /// L'identifiant de la **cale** qui précède une carte, et non celui de la carte.
    ///
    /// `scrollTo(_:anchor: .top)` colle la vue visée au bord haut de la zone défilante :
    /// visant la carte, elle arriverait à ras, et **rien ne dirait qu'il y a quelque chose
    /// au-dessus**. Visant la cale, c'est l'espacement de 12 pt qui se retrouve en haut —
    /// la couture entre deux cartes est visible, et le défilement vers le haut retrouve son
    /// affordance. C'est la `MARGE_DEFILEMENT` de la version web, obtenue ici sans poser
    /// de marge qui n'existe pas dans la mise en page.
    private func ancreDefilement(_ gp: GrandPrixSaison) -> String { "ancre-\(gp.slug)" }

    /// L'écran s'ouvre sur le prochain Grand Prix.
    ///
    /// > **Ce n'est pas une animation, c'est une position de départ**, et le portier
    /// > `/animate` la classe au palier « plusieurs fois par jour » : l'onglet Calendrier
    /// > est en bas de l'écran de tout le monde, et faire défiler la saison sous les yeux
    /// > à chaque ouverture coûterait le temps du geste sans rien apprendre. Le défilement
    /// > est donc **instantané** — aucun `withAnimation`, et aucun jeton de mouvement
    /// > nouveau (`CLAUDE.md` §4).
    ///
    /// Le prochain Grand Prix est déjà la première carte ? Le haut de la liste est sa
    /// place, et il n'y a rien à faire — l'en-tête resterait sinon hors de l'écran.
    ///
    /// **Rien ne part tant que les états sont inconnus** : défiler sur une supposition,
    /// puis corriger à l'arrivée des données, ferait bouger la liste deux fois.
    private func ouvrirSurLeProchainGp(_ lecteur: ScrollViewProxy) {
        guard !defilementFait, calendrier.enBase != nil else { return }
        guard let prochain, prochain.slug != grandsPrix.first?.slug else {
            defilementFait = true
            return
        }
        defilementFait = true
        DispatchQueue.main.async {
            lecteur.scrollTo(ancreDefilement(prochain), anchor: .top)
        }
    }
}

// MARK: - La carte d'un Grand Prix

/// Un Grand Prix de la saison — l'unité de l'écran.
///
/// **Le drapeau n'est pas une vignette : il EST la carte.** Le pays en haut à gauche, son
/// état en haut à droite, le quantième en très grand en bas à gauche, le Grand Prix et son
/// circuit en bas à droite, et le tracé du circuit posé à travers toute la surface.
///
/// ## La pile de calques est celle du widget de l'accueil, et elle ne se défait pas
///
/// Drapeau · ``LueurHaute`` · voile calculé · assombrissement uniforme de 15 % · tracé ·
/// contenu. Tout ce qui éclaircit passe **sous** le voile, sans quoi la garantie de 3:1 de
/// ``ApparenceDrapeau`` n'en est plus une. Un Grand Prix se reconnaît ainsi à ses couleurs
/// d'un écran à l'autre, ce qui n'arriverait pas si le calendrier se peignait tout seul.
///
/// L'assombrissement porte sur **toute la carte**, jamais sur une bande : sur un drapeau à
/// bande répétée, une zone assombrie au milieu coupait la surface en deux et l'œil y lisait
/// un défaut de calage plutôt qu'une intention.
private struct CarteGrandPrixSaison: View {

    let grandPrix: GrandPrixSaison

    /// Hauteur de la carte. **Mesurée sur les captures** (595 px à 3×, soit 198 pt) et
    /// écrite une seule fois : la zone d'informations et la bande la partagent.
    private let hauteurCarte: CGFloat = 200

    /// Hauteur de la bande d'action. Elle est **retranchée** de la carte plutôt qu'ajoutée
    /// dessous : les douze cartes gardent la même hauteur qu'elles portent un bouton ou
    /// non, ce que les trois captures montrent au pixel près.
    ///
    /// 46 pt : au-dessus du plancher tactile de 44 pt, et il ne bouge pas quand la carte
    /// pâlit — une zone tactile ne se réduit jamais (`CLAUDE.md` §3.5).
    private let hauteurBande: CGFloat = 46

    /// Rembourrage du contenu.
    private let rembourrage: CGFloat = 20

    /// Opacité d'une carte **déjà courue**.
    ///
    /// Elle recule l'archive derrière ce qui reste à jouer : douze drapeaux pleins de la
    /// même intensité ne laissent aucun repère à l'œil, et le calendrier ne sert
    /// principalement qu'à trouver le prochain.
    ///
    /// > ### Écart mesuré, et assumé (`CLAUDE.md` §6)
    /// >
    /// > L'opacité porte sur **toute la carte, texte compris** : elle compose donc l'encre
    /// > *et* son fond sur le beige de l'app, et rapproche les deux. La pastille
    /// > « Terminé », la plus serrée des quatre, passe de **4,86:1** à **1,74:1** — sous le
    /// > plancher de 3:1. C'est la valeur de la version web et celle des captures, et
    /// > l'arbitrage se défend : ces cartes sont une archive, la seule information qu'on y
    /// > cherche est « c'est passé », et elle se lit à la pâleur avant de se lire au mot.
    /// > `0,75` est le point où la pastille repasse le plancher, si la lisibilité doit
    /// > primer un jour.
    private let opacitePasse: Double = 0.4

    private var apparence: ApparenceDrapeau? { ApparenceDrapeau.pour(slug: grandPrix.slug) }

    /// La bande ne s'affiche que sur un état connu.
    private var action: String? { grandPrix.etat?.action }

    /// Hauteur de la zone d'informations — la carte moins sa bande, quand elle en a une.
    private var hauteurInfos: CGFloat {
        hauteurCarte - (action == nil ? 0 : hauteurBande)
    }

    var body: some View {
        VStack(spacing: 0) {
            zoneInfos
            bandeAction
        }
        .frame(height: hauteurCarte)
        .background { fond }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        // **La cible est la forme visible.** Le drapeau en `scaledToFill` réclame ~241 pt
        // de haut dans une carte de 200 : `clipShape` le rogne à l'œil, pas au doigt, et
        // chaque carte volait ~20 pt à ses deux voisines — le tap ouvrait le GP d'à côté.
        .contentShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()
        // **`compositingGroup()` n'est pas décoratif, il est la condition de la ligne
        // suivante.** Sans lui, SwiftUI applique l'opacité **primitive par primitive** et
        // non à la carte composée : la bande blanche « Voir les résultats » passait alors
        // à 40 % par-dessus un drapeau lui-même à 40 %, et le drapeau se lisait au travers
        // — mesuré au simulateur sur les Pays-Bas, dont la bande bleue traversait
        // entièrement le bouton. C'est le pendant exact de l'avertissement de la version
        // web : appliquée couche par couche, chacune se compose sur celle du dessous au
        // lieu du fond de l'app, et le voile — qui est justement ce qui tient le contraste
        // du texte — perd plus que le drapeau qu'il couvre.
        //
        // Il est posé **après** `ombreAplat()` : l'ombre pâlit avec la carte, comme le
        // `box-shadow` de l'`<article>` web, qu'une opacité posée sur l'élément emporte.
        .compositingGroup()
        .opacity(grandPrix.etat == .termine ? opacitePasse : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible)
    }

    // MARK: Les calques du fond

    @ViewBuilder private var fond: some View {
        if let apparence {
            ZStack {
                // **`scaledToFill` et non `scaledToFit`** : le drapeau couvre toute la
                // surface, rogné sur son plus grand côté, jamais déformé ni cerné de vide.
                // C'est le pendant exact d'`object-fit: cover`.
                Image("flag-\(grandPrix.slug)")
                    .resizable()
                    .scaledToFill()

                LueurHaute()
                Color.voile.opacity(apparence.voile)
                Color.voile.opacity(0.15)
            }
        } else {
            // Pays hors table : l'aplat de la marque, et aucun assombrissement — il n'a ni
            // bande ni rupture à corriger, le voiler ne ferait que l'éteindre.
            ZStack {
                Color.primaire
                LueurHaute()
            }
        }
    }

    // MARK: La zone d'informations

    private var zoneInfos: some View {
        ZStack {
            trace
            contenu
        }
        .frame(maxWidth: .infinity)
        .frame(height: hauteurInfos)
    }

    /// Le **vrai** tracé du circuit, extrait de la version web par `extraire-gp.mjs`.
    ///
    /// Il est borné à la zone d'informations et ne court pas sous la bande d'action :
    /// celle-ci est opaque, et un circuit qui passerait dessous se lirait comme un trait
    /// coupé net.
    ///
    /// `scaledToFit` met chaque circuit à l'échelle dans cette boîte et le centre — Bakou,
    /// 3,4 fois plus large que haut, remplit la largeur ; Zandvoort, presque carré, remplit
    /// la hauteur. Chacun garde sa vraie forme au lieu d'être étiré.
    ///
    /// Le trait est à 60 % de blanc : une fois le voile et l'assombrissement posés dessous,
    /// il y tient **2,70:1** sur les drapeaux clairs — c'est un élément décoratif, pas un
    /// porteur de sens, et le nom du Grand Prix dit déjà de quel circuit il s'agit.
    private var trace: some View {
        Image("trace-\(grandPrix.slug)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(.encreSurAplat.opacity(0.60))
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            rangeeHaute
            Spacer(minLength: 8)
            rangeeBasse
        }
        .padding(rembourrage)
    }

    private var rangeeHaute: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(grandPrix.pays)
                .font(.custom(encreDouceGrasse ? "HelveticaNeue-Medium" : "HelveticaNeue", size: 12))
                .foregroundColor(encreDouce)
                .ombreTexte()
                .lineLimit(1)

            Spacer(minLength: 0)

            if let etat = grandPrix.etat {
                pastilleEtat(etat)
            }
        }
    }

    /// La pastille d'état. **Blanche sur trois états, ambre sur le quatrième**, et ce n'est
    /// pas une hésitation : posée sur douze drapeaux différents, un aplat coloré se
    /// disputerait la surface avec celui de la carte, et c'est l'encre qui doit distinguer
    /// l'archive de l'urgence. « Pronos ouverts » est la seule exception parce que l'ambre
    /// ne tient pas en encre sur du blanc (2,2:1), là où le noir sur ambre tient 7,86:1.
    ///
    /// **Absente tant que l'état est inconnu** — pendant le premier chargement ou après un
    /// échec. Un « À venir » par défaut dirait d'un Grand Prix ouvert qu'il ne l'est pas.
    private func pastilleEtat(_ etat: EtatGp) -> some View {
        Text(etat.libelle)
            .font(.custom("HelveticaNeue-Medium", size: 11))
            .foregroundColor(etat.encrePastille)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(etat.fondPastille)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rangeeBasse: some View {
        HStack(alignment: .bottom, spacing: 12) {
            quantieme

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(grandPrix.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 16))
                    .foregroundColor(.encreSurAplat)
                    .ombreTexte()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(grandPrix.circuit)
                    .font(.custom(encreDouceGrasse ? "HelveticaNeue-Medium" : "HelveticaNeue", size: 12))
                    .foregroundColor(encreDouce)
                    .ombreTexte()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// Le quantième — le repère de la carte : c'est par lui qu'on cherche « le prochain »,
    /// et les captures le dessinent en très grand.
    ///
    /// **64 pt en graisse 500, et non 700.** La version web pose ici un `font-bold` qu'elle
    /// documente comme un écart assumé ; `ios/CLAUDE.md` §3 n'admet que les graisses 400 et
    /// 500, et la règle vaut. Le crénage suit /apple-design §15, à `-0,03em` : un chiffre
    /// n'a ni jambage ni hampe, donc rien qui vienne remplir l'espace entre deux
    /// caractères — les grands chiffres en ont plus besoin que les titres.
    private var quantieme: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(grandPrix.jour)
                .font(.custom("HelveticaNeue-Medium", size: 64))
                .tracking(-1.92)                              // −0,03em × 64
                .foregroundColor(.encreSurAplat)
                .ombreTexte()
                .lineLimit(1)
                .fixedSize()

            Text(grandPrix.moisAffiche)
                .font(.labelSm)
                .tracking(Tracking.label)
                .foregroundColor(encreDouce)
                .ombreTexte()
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: La bande d'action

    /// Elle n'existe **que là où il y a quelque chose à faire**. Un Grand Prix à venir n'a
    /// pas encore de cotes, un Grand Prix ouvert n'a pas encore de résultats : dans les
    /// deux cas, une bande mènerait à un écran vide.
    ///
    /// Elle est blanche et **opaque**, la couleur étant portée par l'encre. Posée sur le
    /// drapeau du pays hôte, qui change à chaque carte, un aplat coloré se disputerait la
    /// surface avec celui de la carte ; et translucide, elle laisserait le vert sauge à
    /// 3,45:1 sur le noir d'Abu Dhabi.
    @ViewBuilder private var bandeAction: some View {
        if let action {
            Text(action)
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundColor(.encreSucces)       // 4,86:1 sur blanc · sombre 6,92:1
                .frame(maxWidth: .infinity)
                .frame(height: hauteurBande)
                .background(Color.surface)
        }
    }

    // MARK: Les encres

    private var encreDouce: Color { apparence?.encreDouce ?? .encreSecondaire }
    private var encreDouceGrasse: Bool { apparence?.encreDouceGrasse ?? false }

    /// La carte ne montre ni verbe ni destination — un drapeau, une date et un circuit. Le
    /// libellé accessible dit donc ce que l'appui va faire, ce qu'aucun élément visible ne
    /// fait ici.
    private var libelleAccessible: String {
        t("calendrier.a11y.carte", grandPrix.nom, grandPrix.circuit, grandPrix.jourMoisAffiche)
        + (grandPrix.etat.map { "\($0.libelle). " } ?? "")
        + (grandPrix.etat == .termine ? t("calendrier.a11y.voirResultats") : t("calendrier.a11y.voirWeekend"))
    }
}

/// L'ombre portée du texte d'une carte.
///
/// **Inconditionnelle, contrairement à celle du widget de l'accueil.** Là-bas le nom du
/// Grand Prix ne pouvait croiser qu'une couture entre deux bandes, d'où une ombre réservée
/// aux drapeaux qui en ont. Ici le tracé du circuit traverse toute la carte et existe sur
/// les douze : une lettre blanche posée pile sur un trait blanc à 60 % perd son contour,
/// quel que soit le drapeau. Même valeur que l'accueil, pour que les deux écrans ne
/// divergent pas.
private extension View {
    func ombreTexte() -> some View {
        self.shadow(color: .voile.opacity(0.45), radius: 1.5, y: 1)
    }
}

// MARK: - Les états

/// Les quatre états d'un Grand Prix, et ce que chacun dit.
///
/// **Le mot, la couleur et l'action ne se décident pas dans la vue** : ils vivent ici, un
/// seul propriétaire, comme `ETATS_GP` côté web. Deux écrans devront dire le même mot avec
/// la même couleur — le calendrier de la saison et celui d'un championnat — et il n'y a
/// qu'un endroit à corriger.
///
/// `ferme` n'apparaît sur aucune des trois captures, mais il existe dès que l'heure de
/// départ est passée sans que les résultats soient tombés : l'omettre laisserait un trou
/// d'une heure et demie par week-end.
enum EtatGp {
    case termine
    case ferme
    case ouvert
    case aVenir

    var libelle: String {
        switch self {
        case .termine: return t("etat.termine")
        case .ferme: return t("etat.ferme")
        case .ouvert: return t("etat.ouvert")
        case .aVenir: return t("etat.aVenir")
        }
    }

    /// Fond de la pastille. Blanc partout sauf sur « Pronos ouverts » — voir
    /// ``CarteGrandPrixSaison/pastilleEtat``. **Les mêmes dans les deux modes** : la
    /// pastille est posée sur le drapeau, qui ne change pas d'apparence (jetons `…Fixe`).
    var fondPastille: Color {
        self == .ouvert ? .accent : .surfaceFixe
    }

    /// Encre de la pastille, mesurée sur son fond : vert sauge **4,86:1**, rouge de la
    /// marque **10,88:1**, texte sur ambre **7,86:1**, marron **10,55:1**.
    var encrePastille: Color {
        switch self {
        case .termine: return .vertSauge
        case .ferme: return .primaireFixe
        case .ouvert: return .encreSurClair
        case .aVenir: return .secondaireFixe
        }
    }

    /// Le libellé de la bande, ou `nil` s'il n'y a rien à faire.
    ///
    /// **Seul « Terminé » en porte une tant que le parcours de pronostics est mocké.** La
    /// bande « Pronostiquer » de la version web mène au tableau des cotes réel, qui n'est
    /// branché qu'à l'étape 7 ; la poser ici promettrait un tableau que rien ne remplit.
    var action: String? {
        self == .termine ? t("etat.voirResultats") : nil
    }
}

extension EtatGp {

    /// L'état d'un Grand Prix de la saison — `etatDuGpSaison` du web.
    ///
    /// **Absent de la base ⇒ « À venir », toujours** : on ne sait ni si ses cotes existent,
    /// ni à quelle heure il part. L'ordre des tests compte — une course courue est terminée
    /// quoi qu'il arrive, et une fermeture passée l'emporte sur des cotes encore affichées.
    /// La fermeture est `date_course`, sans marge ; un départ inconnu n'est jamais passé.
    ///
    /// **« Pronos ouverts » = ``EcheancePronostics/cotesArretees(statut:dateCourse:le:)``**,
    /// la condition du widget et du décompte — pas la seule présence de cotes. Des cotes
    /// relevées en cours de semaine sur un GP encore `a_venir` ne l'ouvrent pas : c'est
    /// l'écart assumé avec `etatDuGpSaison` du web, qui les comptait.
    static func pour(_ enBase: GrandPrixEnBase?, le maintenant: Date = .now) -> EtatGp {
        guard let enBase else { return .aVenir }
        if enBase.statut == "termine" { return .termine }
        if let depart = enBase.dateCourse, depart <= maintenant { return .ferme }
        if EcheancePronostics.cotesArretees(statut: enBase.statut, dateCourse: enBase.dateCourse,
                                            le: maintenant) { return .ouvert }
        return .aVenir
    }
}

/// Un Grand Prix de la saison : la part **statique** — pays, circuit, date écrite — et ce
/// que la base en sait, quand elle a répondu.
///
/// Le jour et le mois sont des **chaînes**, pas une `Date` : voir l'en-tête de
/// ``CalendrierView``.
struct GrandPrixSaison {
    let slug: String
    let jour: String
    let mois: String
    /// La date complète, **écrite** — l'en-tête de ``ResultatsGPView`` la porte telle
    /// quelle. Elle n'est pas recomposée depuis ``jour`` et ``mois`` : la même règle que
    /// ces deux-là, et pour la même raison. Voir l'en-tête de ``CalendrierView``.
    let date: String
    /// La ligne de `grands_prix` qui lui répond, `nil` si la base ne la connaît pas.
    var enBase: GrandPrixEnBase? = nil
    /// Faux tant que la base n'a pas répondu : l'état est alors **inconnu**.
    var etatConnu = false

    /// **L'identifiant réel** — `nil` pour tout Grand Prix que le scraper n'a pas encore
    /// rencontré. C'est lui que demanderont les résultats et les pronostics.
    var gpId: UUID? { enBase?.id }

    /// L'état de la carte, `nil` s'il est inconnu.
    var etat: EtatGp? { etatConnu ? EtatGp.pour(enBase) : nil }

    /// Pays, nom et circuit **dans la langue de l'interface**, relus à chaque affichage —
    /// clés `gp.<slug>.*` de `Localisation/`. Rien n'est stocké : un texte stocké ne suivrait
    /// pas un changement de langue.
    ///
    /// **`pays` n'est pas `nom` moins « GP ».** Las Vegas se court aux États-Unis, et le
    /// drapeau de sa carte est celui des États-Unis : les deux clés répondent à deux
    /// questions différentes.
    var pays: String { t("gp.\(slug).pays") }
    /// « GP Malaisie » / « Malaysian GP ».
    var nom: String { t("gp.\(slug).nom") }
    /// Le nom sans « GP » — « Malaisie » / « Malaysia » : la pastille d'un sélecteur.
    var nomCourt: String { t("gp.\(slug).court") }
    var circuit: String { t("gp.\(slug).circuit") }

    /// L'entrée de la liste statique qui porte ce slug, `nil` hors saison.
    static func entree(slug: String) -> GrandPrixSaison? {
        saison2026.first { $0.slug == slug }
    }

    /// **Le nom affiché d'un Grand Prix de la base** — le seul propriétaire. Celui de la liste
    /// statique, traduit, dès que le slug y répond ; le nom d'Unibet n'est qu'un repli hors
    /// saison. Le nom de la base sert au rattachement (``SlugCircuit``), jamais à
    /// l'affichage : le 1er octobre 2026 Unibet a publié « GP Bahrein » à la place de Sepang,
    /// et l'accueil disait Bahreïn quand le calendrier disait Malaisie.
    static func nomAffiche(slug: String, repli: String) -> String {
        entree(slug: slug)?.nom ?? repli
    }

    /// Même règle pour le libellé court ; le repli retire le préfixe « GP » du nom en base.
    static func nomCourtAffiche(slug: String, repli: String) -> String {
        if let entree = entree(slug: slug) { return entree.nomCourt }
        return repli.replacingOccurrences(of: #"^GP\s+"#, with: "",
                                          options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Le mois de la carte dans la langue de l'interface — « AOÛT » ou « AUG », « DÉC » ou
    /// « DEC ». ``mois`` reste la clé écrite, en français, que ``GPRestants`` lit.
    var moisAffiche: String {
        guard let jour = GPRestants.jourDeCourse(self) else { return mois }
        return jour.formatted(.dateTime.month(.abbreviated).locale(localeInterface))
            .replacingOccurrences(of: ".", with: "")
            .uppercased(with: localeInterface)
    }

    /// « 23 août » / « 23 August » — le libellé accessible de la carte.
    var jourMoisAffiche: String {
        guard let jour = GPRestants.jourDeCourse(self) else { return "\(self.jour) \(mois.lowercased())" }
        return jour.formatted(.dateTime.day().month(.wide).locale(localeInterface))
    }

    /// La date complète dans la langue de l'interface — « 1er novembre 2026 »,
    /// « 1 November 2026 ». Repli sur ``date``, écrite, si le mois n'est pas reconnu.
    var dateAffichee: String {
        guard let jour = GPRestants.jourDeCourse(self) else { return date }
        let texte = jour.formatted(.dateTime.day().month(.wide).year().locale(localeInterface))
        // Le premier du mois s'écrit « 1er » en français.
        if langueInterface == .fr, self.jour == "1" { return "1er" + texte.dropFirst() }
        return texte
    }

    /// La liste statique croisée avec la base — `enrichir` du web.
    ///
    /// **Le nom affiché reste celui de la liste**, pas celui d'Unibet : le calendrier doit
    /// se lire pareil d'une semaine à l'autre, y compris quand le bookmaker change
    /// l'orthographe d'un pays.
    static func saison2026(croiseeAvec enBase: [GrandPrixEnBase]?) -> [GrandPrixSaison] {
        guard let enBase else { return saison2026 }
        // Deux lignes pour un même week-end — une manuelle pas encore adoptée et celle du
        // scraper : celle qui porte des cotes l'emporte, c'est la seule pronosticable.
        let parSlug = Dictionary(enBase.map { ($0.slug, $0) }, uniquingKeysWith: { premier, second in
            !premier.cotesDisponibles && second.cotesDisponibles ? second : premier
        })
        return saison2026.map { gp in
            var croise = gp
            croise.enBase = parSlug[gp.slug]
            croise.etatConnu = true
            return croise
        }
    }

    /// Les douze Grands Prix, dans l'ordre de la saison — transcription de `GP_2026`
    /// (`frontend/src/lib/calendrier2026.js`).
    ///
    /// `slug` est la clé de **trois** tables à la fois — l'asset `flag-<slug>`, l'asset
    /// `trace-<slug>` et la table des teintes de ``TeintesDrapeaux`` — et celle du
    /// croisement avec la base, par ``SlugCircuit``.
    ///
    /// Pays, nom et circuit ne sont pas écrits ici : ce sont les clés `gp.<slug>.*` des
    /// deux dictionnaires de `Localisation/`.
    static let saison2026: [GrandPrixSaison] = [
        .init(slug: "pays-bas", jour: "23", mois: "AOÛT", date: "23 août 2026"),
        .init(slug: "italie", jour: "6", mois: "SEPT", date: "6 septembre 2026"),
        .init(slug: "espagne", jour: "13", mois: "SEPT", date: "13 septembre 2026"),
        .init(slug: "azerbaidjan", jour: "26", mois: "SEPT", date: "26 septembre 2026"),
        .init(slug: "malaisie", jour: "4", mois: "OCT", date: "4 octobre 2026"),
        .init(slug: "singapour", jour: "11", mois: "OCT", date: "11 octobre 2026"),
        .init(slug: "etats-unis", jour: "25", mois: "OCT", date: "25 octobre 2026"),
        .init(slug: "mexique", jour: "1", mois: "NOV", date: "1er novembre 2026"),
        .init(slug: "bresil", jour: "15", mois: "NOV", date: "15 novembre 2026"),
        .init(slug: "las-vegas", jour: "21", mois: "NOV", date: "21 novembre 2026"),
        .init(slug: "qatar", jour: "29", mois: "NOV", date: "29 novembre 2026"),
        .init(slug: "abu-dhabi", jour: "6", mois: "DÉC", date: "6 décembre 2026")
    ]
}

#Preview {
    CalendrierView()
}
