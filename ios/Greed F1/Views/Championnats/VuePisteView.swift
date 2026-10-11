import SwiftUI

/// **La vue piste** — l'écran signature, et depuis la version `0.17.0` un **écran plein**,
/// poussé par ``ChampionnatDetailView`` au lieu d'être l'onglet d'une bascule segmentée.
///
/// Référence visuelle : `maquettes_V2/screen-14-vue-piste.PNG`, la version web sur iPhone.
/// L'algorithme est la transposition de `frontend/src/ecrans/Piste.jsx`, **passe pour
/// passe** : c'est lui la source unique de la question « où se pose une voiture », et deux
/// placements écrits séparément divergeraient au premier ajustement (`CLAUDE.md` §6).
///
/// Trois calques, dans cet ordre de peinture :
///
/// 1. **Le sol**, la planche `vue_piste.svg` lue au runtime, **étirée** aux deux axes et
///    poussée sous les deux zones sûres : une piste qui s'arrêterait à la Dynamic Island
///    se lirait comme un bandeau posé de travers.
/// 2. **Le bandeau**, à la couleur Pantone du championnat — celle de sa carte d'accueil et
///    de l'en-tête de son écran, jamais une couleur choisie ici. Il porte le **retour**,
///    seul chemin hors de l'écran, et le nom du championnat.
/// 3. **Les voitures**, en coordonnées absolues dans la zone bornée aux deux kerbs.
///
/// > ### Ce que « plein écran » retire, et ce qu'il garde
/// >
/// > La barre de navigation et la barre d'onglets sont **masquées** : la piste est un
/// > dessin, et tout chrome posé dessus en rogne la hauteur, donc l'échelle des scores.
/// > Le bandeau, lui, **n'est pas du chrome** — il porte la teinte du championnat, son nom
/// > et le retour. C'est le même arbitrage que la version web, où l'écran de piste est en
/// > `fixed inset-0` mais garde son `<header>`.
/// >
/// > **Seul le sol franchit les zones sûres.** Le contenu les respecte : la couleur passe
/// > sous la barre d'état, le texte jamais — la règle de `coiffe-ecran`. En bas, la même
/// > règle sort le score de la dernière voiture de sous l'indicateur d'accueil, et c'est
/// > mesuré ainsi sur la maquette : la piste y occupe 667 pt de haut sur un iPhone 15 Pro,
/// > pas 701.
///
/// > **La piste n'appelle rien** : elle reçoit de ``ChampionnatDetailView`` le tableau que
/// > `GET /championnats/{id}/classement` a servi au segment « Classement ». Un second appel
/// > aurait pu poser une voiture à un autre score que sa ligne.
/// **Le sol de la piste, et rien d'autre** — la planche `vue_piste.svg`, étirée aux deux
/// axes, poussée jusqu'au bord de l'écran, zones sûres comprises.
///
/// Extrait de ``VuePisteView`` pour servir à **deux endroits** : le sol de l'écran plein,
/// et celui de ``ChampionnatDetailView``, qui le pousse **derrière son en-tête et son
/// sélecteur** pour que les kerbs montent jusqu'en haut de l'écran au lieu de s'arrêter
/// sous eux. Un second calcul de débord écrit séparément aurait divergé au premier
/// ajustement (`CLAUDE.md` §6).
struct SolPiste: View {

    /// La `viewBox` de la planche, telle quelle.
    private static let planche = CGRect(x: 0, y: 0, width: 589.5, height: 1280.4)

    /// **Le rayon des coins de la planche** — le `rx` de son aplat, 62,7 unités. Les kerbs
    /// s'y arrondissent et leurs bandes s'arrêtent avant : posé tel quel, le bas de l'écran
    /// montrait un kerb rouge uni, sans damier, sur une vingtaine de points.
    private static let rayonPlanche: CGFloat = 62.7

    /// Les quatre segments de la ligne médiane. **La planche les peint à 11 %**, et
    /// ``PlancheSVG`` ne lit que `fill` : l'opacité passe donc par la substitution d'encre,
    /// qui est le mécanisme prévu pour ça. Sans elle, la ligne médiane sortirait en
    /// `#1d1d1b` plein et se lirait comme un rail.
    ///
    /// **Le sol suit l'apparence** : son `#f4efea` est le beige de l'app, et il passe derrière
    /// l'en-tête de ``ChampionnatDetailView`` — il devient donc ``Color/fondPrincipal``, et
    /// les scores posés dessus en `texte` restent lisibles dans les deux modes. Les kerbs
    /// rouges ne bougent pas.
    private static let substitutions: [String: Color] = [
        "#1d1d1b": .ligneMedianePiste,
        "#f4efea": .fondPrincipal
    ]

    var body: some View {
        GeometryReader { bloc in
            // **Étirée aux deux axes, sur tout le bloc proposé**, zones sûres comprises.
            // `etiree` — l'équivalent de `preserveAspectRatio="none"` : la piste couvre
            // l'écran quel que soit son rapport de forme, et ses kerbs gardent une largeur
            // proportionnelle à celle de la piste.
            //
            // **Le bas de la planche passe sous l'écran**, de la hauteur de son arrondi :
            // les kerbs gardent leur damier jusqu'au bord, et l'arrondi du dessin laisse
            // la place à celui de l'écran. Le haut n'en a pas besoin.
            VuePlanche(planche: "vue_piste", fenetre: Self.planche,
                       substitutions: Self.substitutions, etiree: true)
                .ignoresSafeArea()
                .padding(.bottom, -debordBas(ecran: bloc.size.height
                                             + bloc.safeAreaInsets.top
                                             + bloc.safeAreaInsets.bottom))
        }
        .allowsHitTesting(false)
    }

    /// Ce que la planche doit dépasser sous l'écran pour que son arrondi en sorte. Étirée,
    /// elle fait `ecran + d` de haut, et son arrondi `rayon × (ecran + d) / hauteur` :
    /// égaler `d` à ce dernier donne `d = rayon × ecran / (hauteur − rayon)`.
    private func debordBas(ecran: CGFloat) -> CGFloat {
        Self.rayonPlanche * ecran / (Self.planche.height - Self.rayonPlanche)
    }
}

struct VuePisteView: View {

    let championnat: Championnat

    /// Le classement, **déjà trié par points décroissants** — c'est ce que rend le serveur,
    /// et les deux passes en dépendent : elles balaient les hauteurs dans l'ordre croissant
    /// une seule fois.
    let membres: [Membre]

    /// Vrai quand la piste est montée **dans** ``ChampionnatDetailView``, sous son
    /// sélecteur segmenté. L'en-tête de cet écran porte déjà le nom du championnat et la
    /// navigation reste la sienne : ni bandeau, ni chrome masqué. Faux, c'est l'écran plein.
    var integree: Bool = false

    /// Vrai quand l'entrée des voitures peut partir. ``ChampionnatDetailView`` ne construit
    /// plus la piste intégrée qu'au premier tap sur « Piste » : elle y arrive donc à `true`
    /// et l'entrée part au montage. Le drapeau reste pour qui monterait la piste invisible.
    var lancerEntree: Bool = true

    /// Vrai une fois la piste montée. C'est lui qui lance l'entrée des voitures.
    @State private var enPiste = false

    /// La disposition, recalculée au seul changement du classement ou de la piste.
    @State private var memo = DispositionPiste.Memo()

    @Environment(\.dismiss) private var fermer
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// **Les deux kerbs, mesurés sur les tracés de la planche** — 24,88 et 561,17 sur
    /// 589,5 — et non une tranche arithmétique. La zone de jeu s'arrête à eux : les
    /// voitures disposent de toute la largeur de la piste, et d'elle seule.
    private static let margeGauche: CGFloat = 24.88 / 589.5
    private static let margeDroite: CGFloat = (589.5 - 561.17) / 589.5

    /// La rangée du retour, puis celle du nom. **Deux rangées, et c'est mesuré côté web**
    /// (`--piste-retour-h`, `--piste-bandeau-h`) : partagées en une seule, il faudrait
    /// réserver la largeur du bouton **des deux côtés** pour que le nom reste centré sur la
    /// piste, et il ne resterait plus de quoi écrire un nom de championnat.
    ///
    /// La rangée du nom porte aussi l'effectif et la saison : **80 pt**, pour que le bandeau
    /// pèse comme l'en-tête d'un écran et non comme une simple barre.
    private static let hauteurRetour: CGFloat = 38
    private static let hauteurNom: CGFloat = 80

    var body: some View {
        // **Le bloc est mesuré une fois, ici.** Les deux marges de kerb sont des fractions
        // de SA largeur : mesurées après les avoir retirées, elles se réduiraient à chaque
        // passe de mise en page.
        GeometryReader { bloc in
            ZStack(alignment: .top) {
                // Le sol, sous tout le reste et **sur l'écran entier**, zones sûres
                // comprises. **Intégrée, ce n'est plus elle qui le peint** :
                // ``ChampionnatDetailView`` le pousse derrière son propre en-tête, pour que
                // les kerbs montent jusqu'au bord supérieur de l'écran au lieu de s'arrêter
                // sous le sélecteur « Classement / Piste ». Un second sol peint ici par-dessus
                // masquerait celui-là sans rien ajouter.
                if !integree {
                    SolPiste()
                }

                VStack(spacing: 0) {
                    if !integree { bandeau }
                    zoneDeJeu
                        .padding(.leading, Self.margeGauche * bloc.size.width)
                        .padding(.trailing, Self.margeDroite * bloc.size.width)
                }
            }
            .frame(width: bloc.size.width, height: bloc.size.height)
        }
        // Sous les coins arrondis que la planche dessine. Le beige de l'app est à un
        // point de celui du sol (`#F5F0EB` contre `#F4EFEA`) : c'est lui qu'on pose, plutôt
        // qu'une septième teinte déclarée par un écran, ce que le design system proscrit.
        //
        // **Intégrée, pas de fond ici** : un aplat opaque plein écran couvrirait le sol que
        // ``ChampionnatDetailView`` peint derrière son en-tête.
        .background {
            if !integree { Color.fondPrincipal.ignoresSafeArea() }
        }
        // **Le chrome disparaît, les deux barres avec.** Le retour du bandeau est le seul
        // chemin sortant, et le geste de bord continue de fonctionner.
        // Intégrée, la piste laisse les barres à l'écran qui l'accueille.
        .toolbar(integree ? .automatic : .hidden, for: .navigationBar, .tabBar)
        // L'entrée part au montage de la piste, pas à celui d'une voiture : les huit
        // partagent une seule bascule, et c'est le retard de chacune qui les échelonne.
        .onAppear { if lancerEntree { entrer() } }
        .onChange(of: lancerEntree) { _, lancer in
            if lancer && !enPiste { entrer() }
        }
    }

    private func entrer() {
        if mouvementReduit {
            enPiste = true
        } else {
            withAnimation { enPiste = true }
        }
    }

    // MARK: - Le bandeau

    /// L'aplat de la teinte du championnat, son damier, le retour, le nom.
    ///
    /// Ordre de peinture : l'aplat, le damier, puis le texte — le même que les cartes de
    /// championnat, et pour la même raison : un SVG comme un empilement de calques n'a pas
    /// d'autre `z-index` que celui-là.
    ///
    /// **Le rayon ne porte que sur le bas.** Le haut du bandeau passe sous la barre d'état
    /// — `ignoresSafeArea(edges: .top)` est posé **après** la découpe, donc la forme est
    /// dessinée dans le cadre déjà étendu : les deux coins hauts sortent de l'écran au lieu
    /// de laisser voir le sol beige de part et d'autre de l'heure.
    private var bandeau: some View {
        VStack(spacing: 0) {
            retour
                .frame(height: Self.hauteurRetour, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Text(championnat.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 22))
                    .tracking(-0.44)                          // `-0,02 × 22`, la règle des titres
                    .foregroundColor(.encreSurAplat)                  // ≥ 10,35:1 sur les six teintes
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)

                Text(tp("championnat.membresSaison", effectif))
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.encreSecondaire)        // blanc à 70 %, réglé pour un aplat
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: Self.hauteurNom)
        }
        .background {
            // **L'aplat porte les deux calques en `overlay`, jamais en `ZStack`.** Le
            // damier est un `scaledToFill` : dans une pile il impose sa *taille de
            // remplissage* — 402 de large proposés à un dessin de 542 × 420 en réclament
            // 311 de haut — et le fond débordait de 104 pt sous le bandeau, par-dessus le
            // haut de la piste. Mesuré au simulateur, invisible à la lecture du code.
            // Une couleur, elle, prend exactement la place qu'on lui propose ; un
            // `overlay` ne change pas la taille de son hôte.
            Color.teinteChampionnat(pour: championnat.cleTeinte)
                .overlay { Damier(opacite: Materiau.damier) }
                .overlay { LueurHaute() }
                .clipShape(
                    UnevenRoundedRectangle(bottomLeadingRadius: Rayon.bloc,
                                           bottomTrailingRadius: Rayon.bloc,
                                           style: .continuous)
                )
                .ignoresSafeArea(edges: .top)
        }
    }

    /// L'effectif du sous-titre. **Celui du classement reçu** dès qu'il a des lignes — la
    /// même règle que l'en-tête de ``ChampionnatDetailView`` : annoncer huit membres
    /// au-dessus de sept voitures serait le défaut discret par excellence.
    private var effectif: Int {
        membres.isEmpty ? championnat.nombreMembres : membres.count
    }

    /// Le retour, et rien d'autre. **Un chevron et le nom de sa destination** — « d'où je
    /// viens », pas « reculer » : c'est ce que fait le bouton natif d'iOS, et l'écran qui
    /// le remplace lui doit la même promesse.
    ///
    /// La rangée fait 38 pt, la cible tactile 44 : le dépassement est repris par un
    /// `padding` négatif pour ne pas pousser le nom du championnat de six points.
    private var retour: some View {
        Button {
            fermer()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                Text(t("championnat.classement"))
                    .font(.custom("HelveticaNeue-Medium", size: 13))
            }
            .foregroundColor(.encreSurAplat)                      // ≥ 10,35:1 sur les six teintes
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .padding(.vertical, -3)
        .accessibilityLabel(t("piste.retourClassement"))
    }

    // MARK: - La zone de jeu

    /// Tout ce qui est sous le bandeau, bornes comprises. La piste est **mesurée**, jamais
    /// devinée : les deux passes reçoivent la taille réelle, et rien ici ne recopie une
    /// fraction de la planche.
    private var zoneDeJeu: some View {
        GeometryReader { geometrie in
            let taille = geometrie.size
            let disposition = memo.disposition(membres, taille: taille)

            ZStack(alignment: .topLeading) {
                // Sans lui, un `ZStack` d'enfants décalés se réduirait à leur boîte
                // englobante et la mesure ne vaudrait plus rien.
                Color.clear

                ForEach(Array(disposition.placements.enumerated()), id: \.element.id) { rang, placement in
                    voiture(placement, gabarit: disposition.gabarit, rang: rang,
                            hauteur: taille.height, largeur: taille.width)
                }

                if membres.isEmpty { etatVide }
            }
            // La liste ordonnée que la piste dessine. Les voitures sont un **dessin** : le
            // score peint sous chacune ne dit rien seul, et il est masqué aux technologies
            // d'assistance au profit de cette liste-ci.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(resume)
        }
    }

    /// Une voiture, son score sous elle, et son entrée.
    ///
    /// **Deux décalages distincts, et il faut les deux.** Le premier est la place de la
    /// voiture sur la piste, calculée par ``DispositionPiste`` et immuable. Le second est
    /// l'entrée, qui la fait monter du bas de la piste jusqu'à cette place. Les confondre
    /// ferait converger toutes les voitures vers zéro avant de sauter à leur position.
    private func voiture(_ placement: DispositionPiste.Placement,
                         gabarit: DispositionPiste.Gabarit,
                         rang: Int, hauteur: CGFloat, largeur: CGFloat) -> some View {
        let largeurVoiture = gabarit.largeur
        let hauteurVoiture = gabarit.hauteur

        // Chaque voiture part du bas de la piste : la distance dépend de son point
        // d'arrivée, une valeur commune ferait démarrer le leader du milieu de l'écran.
        let depart = hauteur - placement.centre + hauteurVoiture

        return VStack(spacing: 3) {
            VueVoiture(livree: placement.membre.livree,
                       numero: placement.membre.numeroAffiche,
                       nom: placement.membre.pseudo,
                       photo: placement.membre.avatarUrl,
                       teintePilote: .teinteAvatar(pour: placement.membre.cleTeinte))
                .frame(width: largeurVoiture, height: hauteurVoiture)

            Text(String(placement.membre.totalPoints))
                .font(.custom("HelveticaNeue", size: DispositionPiste.tailleScore))
                .foregroundColor(.texte)                  // 15,23:1 sur le beige de la piste
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: largeurVoiture)
        .accessibilityHidden(true)
        .offset(x: largeur / 2 + placement.decalage - largeurVoiture / 2,
                y: placement.centre - hauteurVoiture / 2)
        // L'entrée, et elle seule : `offset` s'ajoute au précédent, il ne le remplace pas.
        .offset(y: enPiste ? 0 : depart)
        .opacity(enPiste ? 1 : 0)
        .animation(mouvementReduit
                   ? nil
                   : Mouvement.entree(0.28).delay(Double(rang) * Mouvement.decalage),
                   value: enPiste)
    }

    /// Le championnat n'a personne à montrer. **Dire ce qui manque** plutôt que laisser un
    /// blanc, qui se lirait comme un chargement en panne.
    private var etatVide: some View {
        Text(t("piste.aucunMembre"))
            .font(.corpsSm)
            .foregroundColor(.secondaire)                 // 9,32:1 sur le beige
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
    }

    /// Ce que la piste dit, en toutes lettres — le classement dans l'ordre.
    private var resume: String {
        guard !membres.isEmpty else { return t("piste.aucunMembre") }
        let lignes = membres.map { t("piste.a11y.ligne", $0.rang, $0.pseudo, tp("classement.a11y.points", $0.totalPoints)) }
        return t("piste.a11y.titre", championnat.nom) + lignes.joined(separator: ". ") + "."
    }
}

// MARK: - Le placement des voitures

/// **Où se pose chaque voiture** — la transposition de `frontend/src/ecrans/Piste.jsx`.
///
/// Deux passes, et l'ordre compte :
///
/// - **Passe 1**, ``hauteurs(pour:dans:gabarit:)`` : le score donne la hauteur.
/// - **Passe 2**, ``ranger(_:points:seuil:plafond:)`` : deux voitures qui se rencontrent
///   sont d'abord **décalées en vertical** de quelques points, puis, si ça ne suffit pas,
///   **écartées latéralement** sur une voie de plus.
///
/// > ### La plus grande taille qui tient (`ios 0.53.5`)
/// >
/// > Toutes les voitures partagent **une seule taille**, cherchée par **dichotomie** entre
/// > ``largeurMinimale`` et ``largeurMaximale`` : à chaque taille essayée, la disposition
/// > est refaite en entier — hauteurs, décalages, nombre de voies — et contrôlée sur les
/// > boîtes réelles. On garde la plus grande sans chevauchement ni contact avec un kerb.
/// > Jusqu'en `0.53.4`, la taille partait de 52 pt et baissait de 5 % par palier, et les
/// > voies se serraient autour de l'axe : Team Bazzana finissait à ~44 pt, la moitié de
/// > la largeur de la piste vide.
/// >
/// > **Les voies d'un groupe sont côte à côte, centrées sur l'axe** (`ios 0.53.6`) : un pas
/// > constant, largeur de voiture + ``ecartMinimal``. La largeur entre les kerbs n'est
/// > qu'une limite — la taille retenue est la plus grande où le groupe le plus large tient
/// > à ``bordMinimal`` de chaque kerb. De `0.53.5` jusque-là, les voies s'étalaient d'un
/// > kerb à l'autre : le duo de tête de Team Bazzana finissait chacun contre son kerb.
/// > Une voiture seule à sa hauteur reste sur l'axe.
/// >
/// > La taille reste **uniforme** : deux voitures voisines à deux tailles différentes
/// > laisseraient croire que la taille veut dire quelque chose.
enum DispositionPiste {

    /// Les bornes de la recherche. En deçà du plancher la voiture cesse de se lire — le
    /// numéro et le pseudo peints sur le dessin deviennent illisibles.
    static let largeurMaximale: CGFloat = 64
    static let largeurMinimale: CGFloat = 40

    /// Ce qu'une voiture peut descendre sous la hauteur que lui donnent ses points pour
    /// éviter d'ouvrir une voie. **Quelques points, pas plus** : au-delà, la hauteur ne dit
    /// plus le score. L'ordre du classement, lui, ne s'inverse jamais.
    static let decalageVerticalMax: CGFloat = 12

    /// Ce qui doit rester entre une voiture et le kerb, de chaque côté.
    static let bordMinimal: CGFloat = 8

    /// L'écart en deçà duquel deux voitures voisines **comptent comme chevauchées**. Mesuré
    /// au simulateur : deux boîtes jointives, roue contre roue, se lisent déjà comme une
    /// superposition — le contrôle exige donc ces quelques points de piste entre elles.
    static let ecartMinimal: CGFloat = 4

    /// Le corps du score posé sous une voiture. Fixe, lui : c'est un chiffre à lire, pas un
    /// dessin, et 14 pt reste la valeur que la version web donne à une voiture pleine.
    static let tailleScore: CGFloat = 14

    /// Marges au-dessus de la première voiture et au-dessous de la dernière. La zone de jeu
    /// s'étend de l'une à l'autre : l'échelle occupe donc toujours la piste entière.
    static let margeHaute: CGFloat = 20
    static let margeBasse: CGFloat = 16

    /// La place que prend le score sous une voiture. Elle entre dans l'empreinte verticale
    /// de celle-ci — voir ``Gabarit/seuil``.
    static let hauteurLegende: CGFloat = 16

    /// La taille d'une voiture, **la même pour toutes** sur un écran donné. La hauteur
    /// **se déduit** du rapport du dessin (141,12 × 288,09), partagé par les douze livrées.
    struct Gabarit: Equatable {
        let largeur: CGFloat

        var hauteur: CGFloat { (largeur * 288.09 / 141.12).rounded() }

        /// Deux voitures se rencontrent en deçà de cet écart de hauteurs. **La voiture ET
        /// sa légende** : au seuil du seul dessin, la légende du groupe du dessus se
        /// poserait sur le museau de la voiture du dessous.
        var seuil: CGFloat { hauteur + hauteurLegende }

        static let defaut = Gabarit(largeur: largeurMaximale)
    }

    /// Où se pose une voiture. **Rien sur sa taille** : elle est dans ``Disposition``,
    /// commune à toutes, et un champ par placement inviterait à en faire varier une.
    struct Placement: Identifiable {
        let membre: Membre
        /// Le centre vertical du **dessin**, en points depuis le haut de la piste.
        let centre: CGFloat
        /// L'écart à l'axe de la piste, en points. Négatif à gauche.
        let decalage: CGFloat

        var id: UUID { membre.id }
    }

    /// Le résultat complet : la taille retenue, et la place de chacune.
    struct Disposition {
        let gabarit: Gabarit
        let placements: [Placement]

        static let vide = Disposition(gabarit: .defaut, placements: [])
    }

    // MARK: Passe 1 — l'échelle verticale

    /// **L'échelle est tendue sur les scores réels** — la passe 1 de `Piste.jsx`.
    ///
    /// ```
    /// y = bas − (points − minimum) / (maximum − minimum) × (bas − haut)
    /// ```
    ///
    /// Le meilleur score se pose **toujours** tout en haut de la zone de jeu, le moins bon
    /// **toujours** tout en bas, et chaque score intermédiaire proportionnellement entre
    /// les deux. Un score élevé donne un `y` petit : le haut de l'écran.
    ///
    /// Les bornes `haut` et `bas` sont **calculées**, pas choisies en pourcentage : c'est la
    /// place qu'il faut à une voiture et à son score pour ne sortir ni en haut ni en bas.
    ///
    /// > ### Pourquoi plus « le bas de la piste vaut zéro »
    /// >
    /// > Jusqu'à la version `0.39.3`, l'échelle allait de zéro au meilleur score : un
    /// > championnat dont le dernier avait 24 points sur 168 posait sa voiture aux sept
    /// > huitièmes de la piste, et le bas restait vide. Le web, lui, tendait déjà sur le
    /// > minimum — deux placements écrits séparément avaient divergé.
    ///
    /// Deux cas sans échelle à tendre :
    ///
    /// - **Un seul membre** : il mène, il se pose en haut.
    /// - **Tout le monde à égalité** — le cas d'avant le premier Grand Prix : la grille se
    ///   pose à mi-hauteur, et la passe 2 en fait une grille de départ sur plusieurs voies.
    ///
    /// Les hauteurs sortent d'ici **exactes** : deux scores identiques rendent exactement la
    /// même valeur, et c'est ce qui garantit que deux ex æquo restent à la même hauteur.
    static func hauteurs(pour points: [Int], dans hauteur: CGFloat,
                         gabarit: Gabarit) -> [CGFloat] {
        let (haut, bas) = bornes(dans: hauteur, gabarit: gabarit)

        guard let maximum = points.max(), let minimum = points.min() else { return [] }
        if points.count == 1 { return [haut] }
        guard maximum > minimum else { return points.map { _ in (haut + bas) / 2 } }

        let etendue = CGFloat(maximum - minimum)
        return points.map { valeur in
            bas - CGFloat(valeur - minimum) / etendue * (bas - haut)
        }
    }

    /// Les centres extrêmes d'une voiture : sous la marge haute, au-dessus du score du bas.
    static func bornes(dans hauteur: CGFloat, gabarit: Gabarit) -> (haut: CGFloat, bas: CGFloat) {
        let haut = margeHaute + gabarit.hauteur / 2
        return (haut, max(haut, hauteur - margeBasse - hauteurLegende - gabarit.hauteur / 2))
    }

    // MARK: Passe 2 — décalage vertical, puis voies

    /// Ce que rend la passe 2 : la hauteur retenue de chaque voiture, sa voie dans son
    /// groupe, et les groupes — des indices consécutifs qui se résolvent ensemble.
    struct Rangement {
        var centres: [CGFloat]
        var voies: [Int]
        var groupes: [[Int]]
    }

    /// **Le décalage vertical passe avant la voie.** Les voitures sont balayées de haut en
    /// bas ; chacune cherche, parmi les voies déjà ouvertes de son groupe, celle qui lui
    /// demande **le plus petit** décalage vers le bas, sans dépasser
    /// ``decalageVerticalMax``. Aucune ne convient : elle ouvre une voie, à sa hauteur.
    ///
    /// Trois garde-fous tiennent la lecture du classement :
    ///
    /// - une voiture ne remonte jamais au-dessus de la précédente — l'ordre ne s'inverse pas ;
    /// - deux **ex æquo** restent à la même hauteur, au point près ;
    /// - personne ne descend sous `plafond`, le centre le plus bas de la piste.
    ///
    /// Un groupe se ferme dès qu'une voiture trouve **toutes** les voies libres : c'est le
    /// placement au premier libre, qui ouvre exactement autant de voies que de voitures qui
    /// se chevauchent à un même endroit (`docs/bugs-connus.md` §33).
    static func ranger(_ centres: [CGFloat], points: [Int], seuil: CGFloat,
                       plafond: CGFloat) -> Rangement {
        var rangement = Rangement(centres: centres, voies: [], groupes: [])
        // Le centre de la dernière voiture de chaque voie du groupe en cours.
        var dernieres: [CGFloat] = []

        for index in centres.indices {
            let voulu = centres[index]
            let precedent = index > 0 ? rangement.centres[index - 1] : -.infinity
            let exAequo = index > 0 && points[index] == points[index - 1]
            let plancher = max(voulu, precedent)

            if dernieres.allSatisfy({ plancher - $0 >= seuil }) {
                rangement.centres[index] = plancher
                rangement.voies.append(0)
                rangement.groupes.append([index])
                dernieres = [plancher]
                continue
            }

            var choix: (voie: Int, centre: CGFloat)?
            for (voie, derniere) in dernieres.enumerated() {
                let centre = max(plancher, derniere + seuil)
                guard centre - voulu <= decalageVerticalMax + 0.01,
                      centre <= plafond + 0.01,
                      !exAequo || centre == precedent else { continue }
                if centre < choix?.centre ?? .infinity { choix = (voie, centre) }
            }

            if let choix {
                rangement.centres[index] = choix.centre
                rangement.voies.append(choix.voie)
                dernieres[choix.voie] = choix.centre
            } else {
                rangement.centres[index] = plancher
                rangement.voies.append(dernieres.count)
                dernieres.append(plancher)
            }
            rangement.groupes[rangement.groupes.count - 1].append(index)
        }
        return rangement
    }

    // MARK: Passe 2c — la répartition latérale

    /// Le rang signé d'une voie dans l'éventail : `0` est la meilleure voiture du groupe,
    /// les impaires partent à gauche, les paires à droite.
    ///
    /// ```
    ///   voie      3       1      0      2       4
    ///   rang     −2      −1      0     +1      +2
    /// ```
    ///
    /// Deux voitures consécutives ne partent jamais du même côté (`docs/bugs-connus.md` §33).
    static func rangEventail(_ voie: Int) -> CGFloat {
        let sens: CGFloat = voie % 2 == 0 ? 1 : -1
        return sens * (CGFloat(voie) / 2).rounded(.up)
    }

    /// L'abscisse d'une voie, depuis le milieu de la piste. **Les voies sont côte à côte**,
    /// à un pas constant — largeur de voiture + ``ecartMinimal`` —, dans l'ordre de
    /// l'éventail, et le bloc est **centré sur l'axe**. Une seule voie tient l'axe.
    ///
    /// La largeur ne fixe pas le pas : elle ne fait que le borner quand `serre` est vrai —
    /// le repli du plancher, où même 40 pt ne tiennent pas entre les kerbs.
    static func abscisse(voies nombre: Int, largeur: CGFloat, gabarit: Gabarit,
                         serre: Bool = false) -> (Int) -> CGFloat {
        guard nombre > 1 else { return { _ in 0 } }

        var pas = gabarit.largeur + ecartMinimal
        if serre {
            let utile = max(0, largeur - 2 * bordMinimal - gabarit.largeur)
            pas = min(pas, utile / CGFloat(nombre - 1))
        }
        let etendue = pas * CGFloat(nombre - 1)
        // Les rangs vont de `−⌊n/2⌋` à `⌈n/2⌉ − 1` : décalés de `⌊n/2⌋`, ils comptent les
        // voies de gauche à droite.
        return { voie in -etendue / 2 + (rangEventail(voie) + CGFloat(nombre / 2)) * pas }
    }

    // MARK: Le contrôle — les chevauchements réels

    /// La boîte qu'occupe une voiture à l'écran : le dessin **et** le score posé dessous.
    /// L'origine des abscisses est l'axe de la piste.
    static func boite(_ placement: Placement, gabarit: Gabarit) -> CGRect {
        CGRect(x: placement.decalage - gabarit.largeur / 2,
               y: placement.centre - gabarit.hauteur / 2,
               width: gabarit.largeur,
               height: gabarit.hauteur + hauteurLegende)
    }

    /// Les indices des voitures dont la boîte en croise une autre. Chaque boîte est élargie
    /// d'un demi ``ecartMinimal`` de chaque côté : deux voitures jointives se croisent.
    static func enChevauchement(_ placements: [Placement], gabarit: Gabarit) -> Set<Int> {
        let boites = placements.map { boite($0, gabarit: gabarit).insetBy(dx: -ecartMinimal / 2, dy: 0) }
        var touchees: Set<Int> = []
        for i in boites.indices {
            for j in boites.indices where j > i {
                let commun = boites[i].intersection(boites[j])
                if !commun.isNull, commun.width > 0.5, commun.height > 0.5 {
                    touchees.insert(i)
                    touchees.insert(j)
                }
            }
        }
        return touchees
    }

    /// Vrai quand une voiture passe à moins de ``bordMinimal`` d'un kerb.
    static func deborde(_ placements: [Placement], largeur: CGFloat, gabarit: Gabarit) -> Bool {
        let limite = largeur / 2 - bordMinimal + 0.5
        return placements.contains { abs($0.decalage) + gabarit.largeur / 2 > limite }
    }

    // MARK: L'enchaînement

    /// Les deux passes à un gabarit donné : la hauteur de la passe 1, décalée de quelques
    /// points au plus par la passe 2, et la voie côte à côte autour de l'axe.
    static func placements(_ membres: [Membre], hauteur: CGFloat, largeur: CGFloat,
                           gabarit: Gabarit, serre: Bool = false) -> [Placement] {
        guard !membres.isEmpty, hauteur > 0, largeur > 0 else { return [] }

        let points = membres.map(\.totalPoints)
        let rangement = ranger(hauteurs(pour: points, dans: hauteur, gabarit: gabarit),
                               points: points, seuil: gabarit.seuil,
                               plafond: bornes(dans: hauteur, gabarit: gabarit).bas)
        var resultat: [Placement] = []

        for groupe in rangement.groupes {
            // **Le groupe compte ses voies, jamais ses membres.**
            let nombre = (groupe.map { rangement.voies[$0] }.max() ?? 0) + 1
            let abscisseDeVoie = abscisse(voies: nombre, largeur: largeur, gabarit: gabarit,
                                          serre: serre)

            for index in groupe {
                resultat.append(Placement(membre: membres[index],
                                          centre: rangement.centres[index],
                                          decalage: abscisseDeVoie(rangement.voies[index])))
            }
        }
        return resultat
    }

    /// Vrai quand aucune boîte n'en croise une autre et qu'aucune voiture ne mord sur la
    /// marge des kerbs.
    static func propre(_ placements: [Placement], largeur: CGFloat, gabarit: Gabarit) -> Bool {
        enChevauchement(placements, gabarit: gabarit).isEmpty
            && !deborde(placements, largeur: largeur, gabarit: gabarit)
    }

    /// **La disposition retenue** : la plus grande largeur entière entre ``largeurMinimale``
    /// et ``largeurMaximale`` qui donne une disposition ``propre(_:largeur:gabarit:)``,
    /// trouvée par dichotomie — cinq essais au plus, chacun une disposition complète.
    ///
    /// Aucune ne l'est — neuf ex æquo, par exemple, ouvrent neuf voies qui ne tiennent pas
    /// côte à côte : le plancher, pas resserré pour rester entre les kerbs. Au-delà, il ne
    /// reste plus de largeur à donner.
    static func disposition(_ membres: [Membre],
                            hauteur: CGFloat, largeur: CGFloat) -> Disposition {
        guard !membres.isEmpty, hauteur > 0, largeur > 0 else { return .vide }

        func essai(_ taille: Int, serre: Bool = false) -> Disposition {
            let gabarit = Gabarit(largeur: CGFloat(taille))
            return Disposition(gabarit: gabarit,
                               placements: placements(membres, hauteur: hauteur,
                                                      largeur: largeur, gabarit: gabarit,
                                                      serre: serre))
        }

        var bas = Int(largeurMinimale), haut = Int(largeurMaximale)
        var retenue: Disposition?
        while bas <= haut {
            let milieu = (bas + haut) / 2
            let candidate = essai(milieu)
            if propre(candidate.placements, largeur: largeur, gabarit: candidate.gabarit) {
                retenue = candidate
                bas = milieu + 1
            } else {
                haut = milieu - 1
            }
        }
        return retenue ?? essai(Int(largeurMinimale), serre: true)
    }

    /// **Le mémo de la disposition** : elle ne se recalcule que si le classement ou la taille
    /// de la piste change, jamais à un simple rendu — une bascule de segment, une entrée de
    /// voitures ou un changement d'apparence réévaluent la vue sans rien changer à ça.
    ///
    /// Une classe et non un `@State` de valeur : la lecture se fait **pendant** le `body`,
    /// où écrire un état observé relancerait un rendu.
    final class Memo {
        private struct Cle: Equatable {
            let ordre: [UUID]
            let points: [Int]
            let taille: CGSize
        }

        private var cle: Cle?
        private var resultat: Disposition = .vide

        func disposition(_ membres: [Membre], taille: CGSize) -> Disposition {
            let nouvelle = Cle(ordre: membres.map(\.id), points: membres.map(\.totalPoints),
                               taille: taille)
            if nouvelle != cle {
                cle = nouvelle
                resultat = DispositionPiste.disposition(membres, hauteur: taille.height,
                                                        largeur: taille.width)
            }
            return resultat
        }
    }
}

#Preview("Huit membres") {
    NavigationStack {
        VuePisteView(championnat: .apercu, membres: MembreMock.exemples.map(\.enMembre))
    }
}

#Preview("Trois ex æquo") {
    // Le cas que la passe 2 doit résoudre : trois scores identiques, donc trois hauteurs
    // identiques, donc trois voies — centre, gauche, droite.
    NavigationStack {
        VuePisteView(championnat: .apercu,
                     membres: MembreMock.exemples.prefix(5).enumerated().map { rang, membre in
                         MembreMock(id: membre.id, pseudo: membre.pseudo,
                                    points: rang < 3 ? 80 : membre.points, rang: membre.rang,
                                    reussis: membre.reussis, tentes: membre.tentes,
                                    meilleurCoup: membre.meilleurCoup,
                                    grandsPrixJoues: membre.grandsPrixJoues,
                                    moyenneTentee: membre.moyenneTentee,
                                    livree: membre.livree, numero: membre.numero).enMembre
                     })
    }
}
