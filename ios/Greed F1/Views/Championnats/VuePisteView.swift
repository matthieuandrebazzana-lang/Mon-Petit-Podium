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
