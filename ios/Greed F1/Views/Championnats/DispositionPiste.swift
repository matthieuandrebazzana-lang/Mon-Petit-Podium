import SwiftUI

/// **Où se pose chaque voiture** — la transposition de `frontend/src/ecrans/Piste.jsx`.
///
/// **Compilé aussi par le widget « Classement »** (exception d'appartenance) : sa piste
/// simplifiée pose les voitures avec ce calcul-ci, jamais un second. Sorti de
/// ``VuePisteView`` pour cela — rien ici ne doit appeler ce que le widget n'a pas.
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
