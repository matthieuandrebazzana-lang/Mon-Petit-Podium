import SwiftUI

/// **La vue piste** — l'écran signature, ici en onglet de ``ChampionnatDetailView``.
///
/// Référence visuelle : `Ressources/Screenshots/screen-14-vue-piste.PNG`. L'algorithme est
/// la transposition de `frontend/src/ecrans/Piste.jsx`, **passe pour passe** : c'est lui la
/// source unique de la question « où se pose une voiture », et deux placements écrits
/// séparément divergeraient au premier ajustement (`CLAUDE.md` §6).
///
/// Trois calques, dans cet ordre de peinture :
///
/// 1. **Le sol**, la planche `vue_piste.svg` lue au runtime et **étirée** aux deux axes.
/// 2. **Le bandeau**, à la couleur Pantone du championnat — celle de sa carte d'accueil et
///    de l'en-tête de son écran, jamais une couleur choisie ici.
/// 3. **Les voitures**, en coordonnées absolues dans la zone bornée aux deux kerbs.
///
/// > **Les données sont mockées** : elles arrivent de ``ChampionnatDetailView``. L'appel à
/// > `classement_du_championnat` viendra à la passe réseau.
struct VuePisteView: View {

    let championnat: ChampionnatMock

    /// Le classement, **déjà trié par points décroissants** — c'est ce que rend le serveur,
    /// et les deux passes en dépendent : elles balaient les hauteurs dans l'ordre croissant
    /// une seule fois.
    let membres: [MembreMock]

    /// Vrai une fois la piste montée. C'est lui qui lance l'entrée des voitures.
    @State private var enPiste = false

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// La `viewBox` de la planche, telle quelle.
    private static let planche = CGRect(x: 0, y: 0, width: 589.5, height: 1280.4)

    /// **Les deux kerbs, mesurés sur les tracés de la planche** — 24,88 et 561,17 sur
    /// 589,5 — et non une tranche arithmétique. La zone de jeu s'arrête à eux : les
    /// voitures disposent de toute la largeur de la piste, et d'elle seule.
    private static let margeGauche: CGFloat = 24.88 / 589.5
    private static let margeDroite: CGFloat = (589.5 - 561.17) / 589.5

    /// Le bandeau vaut **10,94 % de la planche** (140,13 sur 1 280,4). Il est posé en points
    /// plutôt qu'en fraction parce qu'il porte du texte : à 10,94 % d'un onglet court, un
    /// nom de championnat de 20 pt n'aurait plus de quoi respirer.
    private static let hauteurBandeau: CGFloat = 64

    /// Les quatre segments de la ligne médiane. **La planche les peint à 11 %**, et
    /// ``PlancheSVG`` ne lit que `fill` : l'opacité passe donc par la substitution d'encre,
    /// qui est le mécanisme prévu pour ça. Sans elle, la ligne médiane sortirait en
    /// `#1d1d1b` plein et se lirait comme un rail.
    private static let substitutions: [String: Color] = [
        "#1d1d1b": Color(hexadecimal: 0x1D1D1B).opacity(0.11)
    ]

    var body: some View {
        // **Le bloc est mesuré une fois, ici.** Les deux marges de kerb sont des fractions
        // de SA largeur : mesurées après les avoir retirées, elles se réduiraient à chaque
        // passe de mise en page.
        GeometryReader { bloc in
            ZStack(alignment: .top) {
                // Le sol, sous tout le reste. `etiree` — l'équivalent de
                // `preserveAspectRatio="none"` : la piste couvre l'onglet entier quel que
                // soit son rapport de forme, et ses kerbs gardent une largeur
                // proportionnelle à celle de la piste.
                VuePlanche(planche: "vue_piste", fenetre: Self.planche,
                           substitutions: Self.substitutions, etiree: true)

                VStack(spacing: 0) {
                    bandeau
                    zoneDeJeu
                        .padding(.leading, Self.margeGauche * bloc.size.width)
                        .padding(.trailing, Self.margeDroite * bloc.size.width)
                }
            }
            .frame(width: bloc.size.width, height: bloc.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
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

    /// L'aplat de la teinte du championnat, son damier, son nom.
    ///
    /// Ordre de peinture : l'aplat, le damier, puis le texte — le même que les cartes de
    /// championnat, et pour la même raison : un SVG comme un empilement de calques n'a pas
    /// d'autre `z-index` que celui-là.
    ///
    /// **Le rayon ne porte que sur le bas** (`Rayon.bloc`) : le haut du bandeau suit déjà
    /// la découpe du bloc entier, et l'arrondir deux fois laisserait voir le sol dans les
    /// deux coins hauts.
    private var bandeau: some View {
        Text(championnat.nom)
            .font(.custom("HelveticaNeue-Medium", size: 20))
            .tracking(-0.40)                                  // −0,02em × 20
            .foregroundColor(.white)                          // ≥ 10,35:1 sur les six teintes
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: Self.hauteurBandeau)
            .background {
                ZStack {
                    Color.teinteChampionnat(pour: championnat.id)
                    Damier(opacite: Materiau.damier)
                    LueurHaute()
                }
            }
            .clipShape(
                UnevenRoundedRectangle(bottomLeadingRadius: Rayon.bloc,
                                       bottomTrailingRadius: Rayon.bloc,
                                       style: .continuous)
            )
            .accessibilityAddTraits(.isHeader)
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
        // Chaque voiture part du bas de la piste : la distance dépend de son point
        // d'arrivée, une valeur commune ferait démarrer le leader du milieu de l'écran.
        let depart = hauteur - placement.centre + placement.hauteurVoiture

        return VStack(spacing: 3) {
            VueVoiture(livree: placement.membre.livree,
                       numero: placement.membre.numero,
                       nom: placement.membre.pseudo,
                       teintePilote: .teinteAvatar(pour: placement.membre.id))
                .frame(width: placement.largeurVoiture, height: placement.hauteurVoiture)

            if placement.tailleScore > 0 {
                Text(String(placement.membre.points))
                    .font(.custom("HelveticaNeue", size: placement.tailleScore))
                    .foregroundColor(.texte)              // 15,23:1 sur le beige de la piste
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(width: placement.largeurVoiture)
        .accessibilityHidden(true)
        .offset(x: largeur / 2 + placement.decalage - placement.largeurVoiture / 2,
                y: placement.centre - placement.hauteurVoiture / 2)
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
        let lignes = membres.map { "\($0.rang). \($0.pseudo), \($0.points) points" }
        return "Piste du championnat \(championnat.nom). " + lignes.joined(separator: ". ") + "."
    }
}

// MARK: - Le placement des voitures

/// **Où se pose chaque voiture** — la transposition de `frontend/src/ecrans/Piste.jsx`.
///
/// Deux passes, et l'ordre compte :
///
/// - **Passe 1**, ``hauteurs(pour:dans:)`` : le score donne la hauteur, et elle seule. Le
///   meilleur en haut, le moins bon en bas, tout le monde à égalité au milieu.
/// - **Passe 2**, le reste : deux voitures qui se rencontrent sont écartées
///   **latéralement**. **Aucune hauteur ne bouge en passe 2** — la réduire ou l'écarter de
///   l'axe ne la déplace pas verticalement. Sa hauteur dit ses points, et elle seule.
///
/// > ### Écart assumé par rapport à la demande
/// >
/// > La demande donne des ordres de grandeur — « hauteur voiture ≈ 70 pt », « marge ≈ 8 pt ».
/// > Ce sont les **valeurs de la version web qui font foi** : la voiture fait 52 × 106 (son
/// > `viewBox` de 141,12 × 288,09 impose la hauteur, elle ne se choisit pas), et la
/// > gouttière vaut **12** depuis la version `0.71.0` — à 8, la voiture extérieure d'un
/// > groupe large passait à quatre pixels du kerb et paraissait le mordre. Une seconde
/// > table de valeurs ferait diverger les deux applications au premier ajustement.
enum DispositionPiste {

    /// La voiture à sa taille pleine, celle d'un groupe d'une seule. La hauteur **se
    /// déduit** du rapport du dessin (141,12 × 288,09), partagé par les douze livrées.
    static let largeurVoiture: CGFloat = 52
    static let hauteurVoiture: CGFloat = (largeurVoiture * 288.09 / 141.12).rounded()

    /// Le plancher de réduction. En deçà, la voiture cesse de se lire comme une voiture.
    /// Il est **bas exprès** : à 18 pt de large, seize voitures tiennent côte à côte sur
    /// une piste de 354 pt avant qu'il ne morde.
    static let largeurMinimale: CGFloat = 18

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

    /// Où se pose une voiture, et à quelle taille.
    struct Placement: Identifiable {
        let membre: MembreMock
        /// Le centre vertical du **dessin**, en points depuis le haut de la piste.
        let centre: CGFloat
        /// L'écart à l'axe de la piste, en points. Négatif à gauche.
        let decalage: CGFloat
        let largeurVoiture: CGFloat
        let hauteurVoiture: CGFloat
        /// Corps du score, ou `0` quand il cesse d'être lisible.
        let tailleScore: CGFloat

        var id: String { membre.id }
    }

    // MARK: Passe 1 — l'échelle verticale

    /// Le meilleur score en haut de la zone de jeu, le moins bon en bas, chaque score
    /// intermédiaire proportionnellement entre les deux. L'échelle est **tendue sur les
    /// scores réels** : la piste est intégralement utilisée, qu'elle sépare 0 et 28 points
    /// ou 1 240 et 1 260.
    ///
    /// **Tout le monde à égalité se pose à mi-hauteur** — c'est le cas d'avant le premier
    /// Grand Prix. Il n'y a pas d'échelle à tendre, et coller la grille en haut ou en bas
    /// dirait quelque chose de faux.
    ///
    /// Les hauteurs sortent d'ici **exactes**, sans correction d'écart : deux scores
    /// identiques rendent exactement la même valeur, et c'est ce qui garantit que deux
    /// ex æquo forment toujours un groupe à la passe 2.
    ///
    /// Les bornes se calculent à la taille **pleine**, la seule connue à ce stade — la
    /// taille se déduit des groupes, qui se déduisent des hauteurs. La légende compte dans
    /// la borne basse, sinon le score du dernier sortirait sous la piste.
    static func hauteurs(pour points: [Int], dans hauteur: CGFloat) -> [CGFloat] {
        let haut = margeHaute + hauteurVoiture / 2
        let bas = max(haut, hauteur - margeBasse - hauteurLegende - hauteurVoiture / 2)

        guard let maximum = points.max(), let minimum = points.min() else { return [] }
        guard maximum != minimum else { return points.map { _ in (haut + bas) / 2 } }

        return points.map { valeur in
            haut + CGFloat(maximum - valeur) / CGFloat(maximum - minimum) * (bas - haut)
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
    /// > ### Le seuil vaut la voiture **et sa légende**
    /// >
    /// > La demande écrit « hauteur voiture + hauteur score », et c'est bien ce seuil :
    /// > chaque voiture porte son score sous elle, donc son empreinte à l'écran est celle
    /// > du dessin **plus** celle du chiffre. Au seuil du seul dessin, la légende du groupe
    /// > du dessus se poserait sur le museau de la voiture du dessous.
    ///
    /// Un groupe dit **qui se résout ensemble, jamais combien de voies** : c'est
    /// ``voies(de:)`` qui compte les abscisses.
    static func groupes(de hauteurs: [CGFloat]) -> [[Int]] {
        let seuil = hauteurVoiture + hauteurLegende
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
    /// voisine immédiate, **deux voies suffisent**, et les voitures gardent leur taille
    /// pleine au lieu d'être réduites au huitième de la piste.
    ///
    /// Le placement au premier libre est **optimal** ici : les hauteurs arrivant triées, le
    /// nombre de voies ouvertes à un instant donné est exactement le nombre de voitures qui
    /// se chevauchent à cet endroit.
    static func voies(de hauteurs: [CGFloat]) -> [Int] {
        let seuil = hauteurVoiture + hauteurLegende
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

    /// La taille commune aux voitures d'un groupe, et l'abscisse d'une **voie**, comptée
    /// depuis le milieu de la piste. **Aucune hauteur n'entre ici et aucune n'en sort.**
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
    /// ### Le pas, et la taille qui s'en déduit
    ///
    /// Le pas vaut une voiture pleine plus une gouttière **tant que la piste le permet** :
    /// un petit groupe se serre autour de l'axe plutôt que de s'étaler, la proximité étant
    /// ce qui dit que ces voitures-là sont au coude à coude.
    ///
    /// Au-delà il se réduit jusqu'à ce que le groupe tienne entre les kerbs. L'éventail
    /// occupe `rangMaximal` voies **de chaque côté** de l'axe, plus l'axe : toujours un
    /// nombre **impair** de cellules. La réduction ne commence donc qu'à **six voies** sur
    /// une piste de 354 pt (cinq voies : 5 × 64 = 320 ≤ 354), et elle porte sur **les deux
    /// dimensions du même facteur** — une voiture étirée cesserait d'être une voiture.
    static func repartition(voies nombre: Int, largeur: CGFloat)
        -> (largeurVoiture: CGFloat, abscisse: (Int) -> CGFloat) {

        // Les voies impaires partent à gauche, les paires à droite : la gauche est servie
        // la première, et c'est elle qui fixe l'encombrement de l'éventail.
        let rangMaximal = nombre / 2
        let pas = min(largeurVoiture + gouttiere, largeur / CGFloat(2 * rangMaximal + 1))

        let taille = max(largeurMinimale, min(largeurVoiture, pas - gouttiere))

        return (taille, { voie in
            let sens: CGFloat = voie % 2 == 0 ? 1 : -1
            return sens * (CGFloat(voie) / 2).rounded(.up) * pas
        })
    }

    // MARK: L'enchaînement

    /// Elle enchaîne les trois étapes et **ne décide rien elle-même**. La hauteur qu'elle
    /// recopie est celle de la passe 1, inchangée.
    static func placements(_ membres: [MembreMock],
                           hauteur: CGFloat, largeur: CGFloat) -> [Placement] {
        guard !membres.isEmpty, hauteur > 0, largeur > 0 else { return [] }

        let centres = hauteurs(pour: membres.map(\.points), dans: hauteur)
        var resultat: [Placement] = []

        for groupe in groupes(de: centres) {
            // **Le groupe compte ses voies, jamais ses membres.** La cascade réunit des
            // voitures qui ne se touchent pas deux à deux ; leur donner une abscisse
            // chacune est ce qui dessinait l'escalier.
            let voiesDuGroupe = voies(de: groupe.map { centres[$0] })
            let (taille, abscisse) = repartition(voies: (voiesDuGroupe.max() ?? 0) + 1,
                                                 largeur: largeur)
            let echelle = taille / largeurVoiture

            // **Le score s'efface quand la voiture a touché son plancher**, et seulement
            // là : les cellules sont alors plus étroites que la voiture, donc plus étroites
            // qu'un nombre à trois chiffres. Vingt scores écrits côte à côte dans dix-sept
            // points chacun ne font pas vingt nombres, ils font une bavure — et le
            // classement les donne déjà.
            let scoreLisible = taille > largeurMinimale

            for (place, index) in groupe.enumerated() {
                resultat.append(Placement(
                    membre: membres[index],
                    centre: centres[index],
                    decalage: abscisse(voiesDuGroupe[place]),
                    largeurVoiture: taille,
                    hauteurVoiture: hauteurVoiture * echelle,
                    // Le score ne rétrécit pas au même rythme que la voiture : sous 11 pt
                    // il cesse d'être lisible, et un chiffre illisible ne vaut pas mieux
                    // qu'un chiffre absent.
                    tailleScore: scoreLisible ? max(11, (taille * 0.26).rounded()) : 0
                ))
            }
        }
        return resultat
    }
}

#Preview("Huit membres") {
    VuePisteView(championnat: ChampionnatMock(id: "team-bazzana", nom: "Team Bazzana",
                                              membres: 8, rang: 2, fraction: 0.55),
                 membres: MembreMock.exemples)
        .padding(16)
        .background(Color.fondPrincipal)
}

#Preview("Trois ex æquo") {
    // Le cas que la passe 2 doit résoudre : trois scores identiques, donc trois hauteurs
    // identiques, donc trois voies — centre, gauche, droite.
    VuePisteView(championnat: ChampionnatMock(id: "serres-chevalier", nom: "Les Bleus",
                                              membres: 5, rang: 1, fraction: 1),
                 membres: MembreMock.exemples.prefix(5).enumerated().map { rang, membre in
                     MembreMock(id: membre.id, pseudo: membre.pseudo,
                                points: rang < 3 ? 80 : membre.points, rang: membre.rang,
                                reussis: membre.reussis, tentes: membre.tentes,
                                meilleurCoup: membre.meilleurCoup,
                                grandsPrixJoues: membre.grandsPrixJoues,
                                moyenneTentee: membre.moyenneTentee,
                                livree: membre.livree, numero: membre.numero)
                 })
        .padding(16)
        .background(Color.fondPrincipal)
}
