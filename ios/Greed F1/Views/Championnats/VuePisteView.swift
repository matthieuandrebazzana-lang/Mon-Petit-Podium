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
    private static let substitutions: [String: Color] = [
        "#1d1d1b": Color(hexadecimal: 0x1D1D1B).opacity(0.11)
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

    /// Vrai une fois la piste montée. C'est lui qui lance l'entrée des voitures.
    @State private var enPiste = false

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
        .onAppear {
            if mouvementReduit {
                enPiste = true
            } else {
                withAnimation { enPiste = true }
            }
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
                    .foregroundColor(.white)                  // ≥ 10,35:1 sur les six teintes
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)

                Text("\(effectif) \(effectif > 1 ? "membres" : "membre") · Saison 2026")
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
                Text("Classement")
                    .font(.custom("HelveticaNeue-Medium", size: 13))
            }
            .foregroundColor(.white)                      // ≥ 10,35:1 sur les six teintes
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .padding(.vertical, -3)
        .accessibilityLabel("Retour au classement")
    }

    // MARK: - La zone de jeu

    /// Tout ce qui est sous le bandeau, bornes comprises. La piste est **mesurée**, jamais
    /// devinée : les deux passes reçoivent la taille réelle, et rien ici ne recopie une
    /// fraction de la planche.
    private var zoneDeJeu: some View {
        GeometryReader { geometrie in
            let taille = geometrie.size
            let placements = DispositionPiste.placements(membres,
                                                         hauteur: taille.height,
                                                         largeur: taille.width)

            ZStack(alignment: .topLeading) {
                // Sans lui, un `ZStack` d'enfants décalés se réduirait à leur boîte
                // englobante et la mesure ne vaudrait plus rien.
                Color.clear

                ForEach(Array(placements.enumerated()), id: \.element.id) { rang, placement in
                    voiture(placement, rang: rang, hauteur: taille.height, largeur: taille.width)
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
                         rang: Int, hauteur: CGFloat, largeur: CGFloat) -> some View {
        let largeurVoiture = DispositionPiste.largeurVoiture
        let hauteurVoiture = DispositionPiste.hauteurVoiture

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
        Text("Aucun membre à afficher sur la piste.")
            .font(.corpsSm)
            .foregroundColor(.secondaire)                 // 9,32:1 sur le beige
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
    }

    /// Ce que la piste dit, en toutes lettres — le classement dans l'ordre.
    private var resume: String {
        guard !membres.isEmpty else { return "Aucun membre à afficher sur la piste." }
        let lignes = membres.map { "\($0.rang). \($0.pseudo), \($0.totalPoints) points" }
        return "Piste du championnat \(championnat.nom). " + lignes.joined(separator: ". ") + "."
    }
}

// MARK: - Le placement des voitures

/// **Où se pose chaque voiture** — la transposition de `frontend/src/ecrans/Piste.jsx`.
///
/// Deux passes, et l'ordre compte :
///
/// - **Passe 1**, ``hauteurs(pour:dans:)`` : le score donne la hauteur, et elle seule.
/// - **Passe 2**, le reste : deux voitures qui se rencontrent sont écartées
///   **latéralement**. **Aucune hauteur ne bouge en passe 2** — l'écarter de l'axe ne la
///   déplace pas verticalement. Sa hauteur dit ses points, et elle seule.
///
/// > ### Toutes les voitures ont la même taille
/// >
/// > **52 × 106, sans exception** — ni le score, ni le rang, ni l'encombrement de son
/// > groupe ne change la taille d'une voiture. Jusqu'à la version `0.16.0` un groupe large
/// > rétrécissait les siennes pour tenir entre les kerbs : deux voitures voisines
/// > sortaient alors à deux tailles différentes, et l'écran laissait croire que la taille
/// > voulait dire quelque chose. C'est le **pas** de l'éventail qui se resserre désormais,
/// > jamais le dessin.
enum DispositionPiste {

    /// La voiture, à la seule taille qu'elle ait. La hauteur **se déduit** du rapport du
    /// dessin (141,12 × 288,09), partagé par les douze livrées.
    static let largeurVoiture: CGFloat = 52
    static let hauteurVoiture: CGFloat = (largeurVoiture * 288.09 / 141.12).rounded()

    /// Le corps du score posé sous une voiture. Fixe lui aussi — c'est `52 × 0,26` arrondi,
    /// la valeur que la version web donne à une voiture pleine.
    static let tailleScore: CGFloat = 14

    /// Gouttière entre deux voitures voisines d'un même groupe. Elle **s'ajoute** à la
    /// boîte du dessin et ne l'entame jamais : c'est elle qui fixe le pas des voies.
    static let gouttiere: CGFloat = 12

    /// Marges au-dessus de la première voiture et au-dessous de la dernière. La zone de jeu
    /// s'étend de l'une à l'autre : l'échelle occupe donc toujours la piste entière.
    static let margeHaute: CGFloat = 20
    static let margeBasse: CGFloat = 16

    /// La place que prend le score sous une voiture. Elle entre dans l'empreinte verticale
    /// de celle-ci — voir le seuil de ``groupes(de:)``.
    static let hauteurLegende: CGFloat = 16

    /// Deux voitures se rencontrent en deçà de cet écart de hauteurs. **La voiture ET sa
    /// légende** : chacune porte son score sous elle, donc son empreinte à l'écran est
    /// celle du dessin **plus** celle du chiffre. Au seuil du seul dessin, la légende du
    /// groupe du dessus se poserait sur le museau de la voiture du dessous.
    static let seuil: CGFloat = hauteurVoiture + hauteurLegende

    /// Où se pose une voiture. **Rien sur sa taille** : elles l'ont toutes la même, et un
    /// champ par placement inviterait à en faire varier une.
    struct Placement: Identifiable {
        let membre: Membre
        /// Le centre vertical du **dessin**, en points depuis le haut de la piste.
        let centre: CGFloat
        /// L'écart à l'axe de la piste, en points. Négatif à gauche.
        let decalage: CGFloat

        var id: UUID { membre.id }
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
    /// Les bornes `haut` et `bas` tombent autour de 10 % et 90 % de la piste, mais elles
    /// sont **calculées**, pas choisies en pourcentage : c'est la place qu'il faut à une
    /// voiture et à son score pour ne sortir ni en haut ni en bas.
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
    ///   pose à mi-hauteur. La coller en haut ou en bas dirait quelque chose de faux, et la
    ///   passe 2 en fait une grille de départ sur plusieurs voies.
    ///
    /// Les hauteurs sortent d'ici **exactes**, sans correction d'écart : deux scores
    /// identiques rendent exactement la même valeur, et c'est ce qui garantit que deux
    /// ex æquo forment toujours un groupe à la passe 2.
    ///
    /// La légende compte dans la borne basse, sinon le score du dernier sortirait sous la
    /// piste.
    static func hauteurs(pour points: [Int], dans hauteur: CGFloat) -> [CGFloat] {
        let haut = margeHaute + hauteurVoiture / 2
        let bas = max(haut, hauteur - margeBasse - hauteurLegende - hauteurVoiture / 2)

        guard let maximum = points.max(), let minimum = points.min() else { return [] }
        if points.count == 1 { return [haut] }
        guard maximum > minimum else { return points.map { _ in (haut + bas) / 2 } }

        let etendue = CGFloat(maximum - minimum)
        return points.map { valeur in
            bas - CGFloat(valeur - minimum) / etendue * (bas - haut)
        }
    }

    // MARK: Passe 2a — le regroupement

    /// Deux voitures se chevauchent quand l'écart de leurs hauteurs est plus petit que
    /// l'empreinte d'une voiture. **Le regroupement se propage en cascade** : si A chevauche
    /// B et B chevauche C, les trois n'en font qu'un, *même si A et C ne se touchent pas*.
    /// C'est pour cela que la comparaison porte sur la voiture précédente, jamais sur la
    /// première du groupe.
    ///
    /// **Rien ici ne regarde les scores.** Deux scores voisins mais distincts sont regroupés
    /// si et seulement si leurs voitures se rencontrent à l'écran.
    ///
    /// Un groupe dit **qui se résout ensemble, jamais combien de voies** : c'est
    /// ``voies(de:)`` qui compte les abscisses.
    static func groupes(de hauteurs: [CGFloat]) -> [[Int]] {
        var groupes: [[Int]] = []

        for (index, centre) in hauteurs.enumerated() {
            if let precedent = groupes.last?.last, centre - hauteurs[precedent] < seuil {
                groupes[groupes.count - 1].append(index)
            } else {
                groupes.append([index])
            }
        }
        return groupes
    }

    // MARK: Passe 2b — les voies d'un groupe

    /// Reçoit les hauteurs d'un groupe, dans l'ordre du classement, et rend pour chacune
    /// l'indice de la voie où sa voiture se pose. Deux voitures d'une même voie sont
    /// écartées d'au moins une empreinte : elles peuvent partager une abscisse sans se
    /// toucher.
    ///
    /// **C'est ici que l'escalier diagonal se défait.** Un groupe de huit voitures que la
    /// cascade a réunies n'a pas besoin de huit abscisses : si chacune ne chevauche que sa
    /// voisine immédiate, **deux voies suffisent**.
    ///
    /// Le placement au premier libre est **optimal** ici : les hauteurs arrivant triées, le
    /// nombre de voies ouvertes à un instant donné est exactement le nombre de voitures qui
    /// se chevauchent à cet endroit.
    static func voies(de hauteurs: [CGFloat]) -> [Int] {
        // La hauteur de la dernière voiture posée sur chaque voie. Les hauteurs étant
        // croissantes, c'est la seule dont l'écart puisse manquer.
        var dernieres: [CGFloat] = []

        return hauteurs.map { centre in
            if let voie = dernieres.firstIndex(where: { centre - $0 >= seuil }) {
                dernieres[voie] = centre
                return voie
            }
            dernieres.append(centre)
            return dernieres.count - 1
        }
    }

    // MARK: Passe 2c — la répartition latérale

    /// L'abscisse d'une **voie**, comptée depuis le milieu de la piste. **Aucune hauteur
    /// n'entre ici et aucune n'en sort, et aucune taille non plus.**
    ///
    /// ### L'éventail : la voie `0` est l'axe, les suivantes s'écartent par paires
    ///
    /// ```
    ///   voie      3       1      0      2       4
    ///   x      −2 · pas  −pas    0    +pas   +2 · pas
    /// ```
    ///
    /// ``voies(de:)`` ouvre les voies dans l'ordre d'arrivée et les membres arrivent triés
    /// par points décroissants : **la meilleure voiture du groupe ouvre donc toujours la
    /// voie `0`** et tient l'axe. L'écran dit alors quelque chose de vrai — qui mène le
    /// groupe tient le milieu de la piste, ses poursuivants s'écartent autour de lui.
    ///
    /// Une numérotation d'un kerb à l'autre ferait descendre le cycle trois fois de suite
    /// dans le même sens, soit un petit escalier redessiné à chaque tour. L'éventail le
    /// fait tourner **milieu, gauche, droite, milieu…** : deux voitures consécutives ne
    /// partent jamais du même côté de l'axe.
    ///
    /// ### Le pas
    ///
    /// Il vaut une voiture pleine plus une gouttière **tant que la piste le permet** : un
    /// petit groupe se serre autour de l'axe plutôt que de s'étaler, la proximité étant ce
    /// qui dit que ces voitures-là sont au coude à coude.
    ///
    /// Au-delà il se resserre jusqu'à ce que l'éventail tienne entre les kerbs. Celui-ci
    /// occupe `rangMaximal` voies **de chaque côté** de l'axe, plus l'axe : toujours un
    /// nombre **impair** de cellules. Le resserrement ne commence donc qu'à **six voies**
    /// sur une piste de 354 pt (cinq voies : 5 × 64 = 320 ≤ 354) — six voitures qui se
    /// chevauchent toutes, ce qu'un championnat de huit ne produit pas.
    ///
    /// > **Et la voiture, elle, ne rétrécit pas.** Passé six voies les dessins commencent à
    /// > se recouvrir par les bords ; c'est assumé, parce que l'alternative — une taille
    /// > qui dépend de l'encombrement — faisait cohabiter deux échelles sur le même écran.
    static func abscisse(voies nombre: Int, largeur: CGFloat) -> (Int) -> CGFloat {
        // Les voies impaires partent à gauche, les paires à droite : la gauche est servie
        // la première, et c'est elle qui fixe l'encombrement de l'éventail.
        let rangMaximal = nombre / 2
        let pas = min(largeurVoiture + gouttiere, largeur / CGFloat(2 * rangMaximal + 1))

        return { voie in
            let sens: CGFloat = voie % 2 == 0 ? 1 : -1
            return sens * (CGFloat(voie) / 2).rounded(.up) * pas
        }
    }

    // MARK: L'enchaînement

    /// Elle enchaîne les trois étapes et **ne décide rien elle-même**. La hauteur qu'elle
    /// recopie est celle de la passe 1, inchangée.
    static func placements(_ membres: [Membre],
                           hauteur: CGFloat, largeur: CGFloat) -> [Placement] {
        guard !membres.isEmpty, hauteur > 0, largeur > 0 else { return [] }

        let centres = hauteurs(pour: membres.map(\.totalPoints), dans: hauteur)
        var resultat: [Placement] = []

        for groupe in groupes(de: centres) {
            // **Le groupe compte ses voies, jamais ses membres.** La cascade réunit des
            // voitures qui ne se touchent pas deux à deux ; leur donner une abscisse
            // chacune est ce qui dessinait l'escalier.
            let voiesDuGroupe = voies(de: groupe.map { centres[$0] })
            let abscisseDeVoie = abscisse(voies: (voiesDuGroupe.max() ?? 0) + 1,
                                          largeur: largeur)

            for (place, index) in groupe.enumerated() {
                resultat.append(Placement(membre: membres[index],
                                          centre: centres[index],
                                          decalage: abscisseDeVoie(voiesDuGroupe[place])))
            }
        }
        return resultat
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
