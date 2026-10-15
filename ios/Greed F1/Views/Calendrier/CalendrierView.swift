import SwiftUI

/// Onglet **Calendrier** — les Grands Prix de la saison 2026, des Pays-Bas à Abu Dhabi.
/// Les onze du début de saison sont temporairement masqués
/// (``GrandPrixSaison/masquesDuCalendrier``).
///
/// Références visuelles : `Ressources/Screenshots/screen-08-calendrier-haut.PNG`,
/// `screen-09-calendrier-milieu.PNG` et `screen-10-calendrier-bas.PNG`.
///
/// > **La liste est statique, les états sont réels.** ``GrandPrixSaison/saison2026`` porte
/// > les vingt-trois cartes ; ``CalendrierSaison`` (`GET /calendrier`) leur ajoute ce que
/// > seule la base sait — **l'identifiant, le statut et l'existence de cotes**. Le
/// > rapprochement se fait par ``SlugCircuit``, jamais par le nom brut. L'échec de
/// > l'appel fait perdre les états, jamais la liste (`docs/swift-app.md` §7.6).
///
/// ## La liste est statique, et c'est un choix
///
/// `public.grands_prix` ne contient que ce que le scraper a rencontré, et Unibet n'expose
/// jamais que le Grand Prix suivant : un calendrier lu en base afficherait **une** course
/// au milieu d'une saison qui en compte vingt-trois. Le calendrier de la Formule 1 est une
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

    /// Possédé par ``BarreNavigation``, chargé dès le lancement (``CacheService``, §7.6).
    @ObservedObject var calendrier: CalendrierSaison

    /// Les cartes de la saison, croisées avec ce que la base sait — ou avec rien, tant qu'elle n'a
    /// pas répondu : leurs états sont alors **inconnus**, pas « à venir ».
    ///
    /// **Les onze Grands Prix du début de saison sont masqués** — voir
    /// ``GrandPrixSaison/masquesDuCalendrier``. Le filtre est posé ici, à l'affichage, et
    /// nulle part ailleurs : le prochain Grand Prix et le défilement se lisent sur cette liste.
    private var grandsPrix: [GrandPrixSaison] {
        GrandPrixSaison.saison2026(croiseeAvec: calendrier.enBase)
            .filter { !GrandPrixSaison.masquesDuCalendrier.contains($0.slug) }
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

    /// Premier chargement : la liste est esquissée (``SqueletteCalendrier``).
    private var enChargement: Bool {
        if case .chargement = calendrier.etat { return true }
        return false
    }

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
                            contenu
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

    /// **Au premier chargement, la liste entière est esquissée**, comme sur les autres
    /// écrans : six cartes grises (``SqueletteCalendrier``), puis le vrai calendrier, ses
    /// cartes en cascade — `fonduChargement(_:)` posé ici, sur le conteneur du `switch`. Le cache
    /// (5 min) sert la liste aussitôt aux visites suivantes, et un rechargement garde les
    /// états déjà affichés : la silhouette ne se voit qu'une fois.
    ///
    /// **Après un échec, la liste revient sans ses états**, l'erreur posée au-dessus : les
    /// cartes sont statiques, l'échec fait perdre les états, jamais la liste
    /// (`docs/swift-app.md` §7.6).
    private var contenu: some View {
        ZStack(alignment: .top) {
            switch calendrier.etat {
            case .chargement:
                SqueletteCalendrier(espacement: espacement)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(t("calendrier.a11y.chargement"))

            case .echec(let erreur):
                VStack(spacing: 0) {
                    EchecChargement(erreur: erreur) {
                        Task { await calendrier.charger() }
                    }
                    .padding(.bottom, espacement)
                    liste
                }
                .transition(.contenuArrive)

            case .pret:
                liste
                    .transition(.contenuArrive)
            }
        }
        .fonduChargement(enChargement)
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
                // couru avant l'ouverture de l'app peut ne pas l'avoir : ses résultats
                // s'affichent alors « non disponibles », jamais ceux d'un autre.
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
                .arriveeEnCascade(rang: max(0, rang - rangProchain))
            }
        }
    }

    /// **La cascade part du prochain Grand Prix**, pas du haut de la saison : l'écran
    /// s'ouvre sur lui (``ouvrirSurLeProchainGp(_:)``), et compter depuis la première carte
    /// ferait partir d'un bloc, avec la cinquième, toutes celles qu'on voit. Les cartes
    /// au-dessus, hors champ, entrent avec lui.
    private var rangProchain: Int {
        guard let prochain else { return 0 }
        return grandsPrix.firstIndex { $0.slug == prochain.slug } ?? 0
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
    /// dessous : les cartes gardent la même hauteur qu'elles portent un bouton ou
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
    ///
    /// Un circuit sans asset — les onze du début de saison — n'en pose aucun, plutôt qu'une
    /// image vide qui avertirait la console à chaque affichage.
    @ViewBuilder private var trace: some View {
        if UIImage(named: "trace-\(grandPrix.slug)") != nil {
            traceDessine
        }
    }

    private var traceDessine: some View {
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

// MARK: - La silhouette du calendrier

/// Le calendrier pendant son premier chargement : six cartes de la hauteur des vraies
/// (200 pt, `Rayon.bloc`), sur la surface neutre — **ni drapeau, ni texte** : un bloc pour
/// le drapeau et son tracé, puis la rangée basse d'une carte, le quantième à gauche, le
/// nom du Grand Prix et son circuit à droite. Six suffisent à remplir l'écran le plus haut.
private struct SqueletteCalendrier: View {

    let espacement: CGFloat

    var body: some View {
        VStack(spacing: espacement) {
            ForEach(0..<6, id: \.self) { _ in carte }
        }
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonView(.blocRectangulaire, hauteur: 88, rayon: Rayon.champ)

            Spacer(minLength: 16)

            HStack(alignment: .bottom, spacing: 12) {
                SkeletonView(.ligneCourte, largeur: 56, hauteur: 44, rayon: Rayon.champ)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    SkeletonView(.ligneLongue, largeur: 150, hauteur: 14)
                    SkeletonView(.ligneCourte, largeur: 90, hauteur: 10)
                }
            }
        }
        .padding(20)
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()
    }
}

#Preview {
    CalendrierView(calendrier: CalendrierSaison())
}
