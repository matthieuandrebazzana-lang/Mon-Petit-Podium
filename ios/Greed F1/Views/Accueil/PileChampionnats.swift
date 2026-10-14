import SwiftUI

/// Les championnats de l'accueil, **empilés comme un paquet de cartes**.
///
/// La carte du dessus est la ``CarteChampionnat`` de toujours, entière ; un tap l'ouvre.
/// Toutes les autres dépassent au-dessus d'elle d'une bande — le nom et le classement,
/// sur leur teinte assombrie — et **toutes restent visibles** : vingt championnats, vingt
/// bandes. **Le paquet a de la profondeur** : chaque carte est un peu plus petite que
/// celle de devant, bande comprise (``Perspective``).
///
/// **Seule la carte du dessus se glisse.** Vers le haut elle part au fond et la suivante
/// se découvre ; vers le bas, la carte du fond redescend au premier plan. Une bande ne
/// capte aucun geste : un glissement parti d'elle fait défiler l'accueil. **Un aperçu
/// déplié ne bloque pas ce geste** : le swipe s'exécute et replie l'aperçu dans le même
/// ressort, sans animation à part.
///
/// **Un tap sur une bande l'affiche en aperçu** : elle se déplie en carte pleine **à sa
/// place dans le paquet**, sans changer l'ordre — ni celui des cartes, ni celui de leur
/// empilement. Les cartes de devant, carte du dessus comprise, **descendent** de la hauteur
/// dépliée et restent par-dessus l'aperçu : il ne couvre jamais rien. Un seul aperçu
/// à la fois — en ouvrir un autre replie le premier —, un tap ailleurs le referme
/// (``AccueilView`` porte ce tap-là), et un second tap sur l'aperçu ouvre le championnat.
///
/// **L'ordre est mémorisé**, par compte (``OrdrePile``) : par défaut du plus grand
/// effectif au plus petit, puis chaque swipe, et chaque championnat ouvert depuis un
/// aperçu — il revient au premier plan au retour. Un championnat nouveau entre au fond.
///
/// > **Une carte qui part au fond reste au premier plan pendant tout son trajet.** Elle
/// > glisse par-dessus le paquet et ne passe derrière ses voisines qu'une fois son ressort
/// > **entièrement** retombé — le changement d'ordre d'empilement se fait alors à
/// > l'arrêt, là où il ne se voit pas. L'ordre complet est dans ``plan(profondeur:id:)``.
///
/// > **Les cartes se chevauchent pendant tout le trajet.** Une carte en vol ne mesure que
/// > sa bande, et le ressort lancé dépasse : sans rien dessous, le fond de l'écran passait
/// > entre elle et sa voisine, en une barre claire. Chaque carte en vol pose donc sous
/// > tout le paquet une **jupe** de sa teinte (``JupePile``), qui suit son trajet.
///
/// > **Pendant le geste, seule la carte tirée se redessine.** Son déplacement est un
/// > `@GestureState` porté par ``CartePile`` elle-même : la pile n'en sait rien, et ses
/// > autres cartes ne sont pas invalidées à chaque image.
struct PileChampionnats: View {

    let championnats: [Championnat]
    @ObservedObject var mesChampionnats: MesChampionnats
    /// Le compte connecté : l'ordre mémorisé est le sien, jamais celui d'un autre compte
    /// ouvert sur le même iPhone.
    let idUtilisateur: UUID?
    /// La bande affichée en aperçu. Tenue par l'accueil, qui la referme sur un tap hors
    /// de la pile.
    @Binding var apercu: UUID?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// L'ordre mémorisé, de la carte du dessus à celle du fond — **par identifiant** : la
    /// liste est relue à chaque apparition de l'accueil, et le paquet ne doit pas se
    /// rebattre pour autant. Rapproché de la liste reçue par ``ordreEffectif``.
    @State private var ordre: [UUID]
    /// Les cartes parties de l'avant vers le fond, gardées au premier plan jusqu'à la fin
    /// de leur trajet.
    @State private var enVol: Set<UUID> = []
    /// Les trajets lancés dont le ressort n'est pas encore retombé. Un trajet relancé en
    /// plein vol reprend les cartes du précédent : elles ne redescendent dans l'ordre
    /// d'empilement qu'une fois **tous** terminés.
    @State private var trajetsEnCours = 0
    /// La hauteur pleine de chaque carte, mesurée par elle-même : elle varie d'un
    /// championnat à l'autre (photo ou pas), et c'est elle qui fixe la descente des cartes
    /// de devant quand la carte s'ouvre en aperçu.
    @State private var hauteursPleines: [UUID: CGFloat] = [:]
    /// Vrai tant qu'un doigt tire la carte du dessus à la verticale — un changement au
    /// début du geste, un à la fin, aucun entre les deux.
    @State private var glissementEnCours = false
    @State private var championnatOuvert: Championnat?
    /// L'ordre à afficher au retour d'un championnat ouvert depuis un aperçu. Déjà
    /// mémorisé ; appliqué au retour seulement, pour que le paquet ne bouge pas sous
    /// l'écran qui se pousse.
    @State private var ordreAuRetour: [UUID]?

    /// La bande de chaque carte du dessous, **avant réduction** — voir ``Perspective``.
    private let depassement = Perspective.bande

    init(championnats: [Championnat], mesChampionnats: MesChampionnats,
         idUtilisateur: UUID?, apercu: Binding<UUID?>) {
        self.championnats = championnats
        self.mesChampionnats = mesChampionnats
        self.idUtilisateur = idUtilisateur
        self._apercu = apercu
        self._ordre = State(initialValue: OrdrePile.lire(pour: idUtilisateur))
    }

    private var nombre: Int { championnats.count }

    /// L'ordre mémorisé, rapporté à la liste reçue — voir ``OrdrePile/rapprocher(_:de:)``.
    private var ordreEffectif: [UUID] { OrdrePile.rapprocher(ordre, de: championnats) }

    var body: some View {
        let ordre = ordreEffectif
        let rangs = Dictionary(uniqueKeysWithValues: ordre.enumerated().map { ($1, $0) })

        // Sous mouvement réduit, le paquet ne se déplace pas : il se remplace, en fondu.
        ZStack {
            paquet(rangs: rangs)
                .id(mouvementReduit ? ordre.first : nil)
                .transition(.opacity)
        }
        .sensoryFeedback(.selection, trigger: ordre.first)
        .navigationDestination(item: $championnatOuvert) { championnat in
            ChampionnatDetailView(championnat: championnat, mesChampionnats: mesChampionnats)
        }
        .onAppear(perform: rapprocherEtMemoriser)
        .onChange(of: championnats.map(\.id)) { rapprocherEtMemoriser() }
        .onChange(of: idUtilisateur) { _, id in
            self.ordre = OrdrePile.lire(pour: id)
            rapprocherEtMemoriser()
        }
        .onChange(of: championnatOuvert) { _, ouvert in
            guard ouvert == nil, let nouvel = ordreAuRetour else { return }
            ordreAuRetour = nil
            withAnimation(animationApercu) {
                self.ordre = nouvel
                apercu = nil
            }
        }
        .onDisappear {
            // Changement d'onglet : l'aperçu ne survit pas. Un écran poussé, si — il
            // se replie au retour, dans le même mouvement que le paquet.
            if championnatOuvert == nil { apercu = nil }
        }
    }

    private func paquet(rangs: [UUID: Int]) -> some View {
        let rangApercu = apercu.flatMap { rangs[$0] }
        let descente = rangApercu.map(descenteApercu) ?? 0
        return ZStack(alignment: .top) {
            ForEach(championnats) { championnat in
                JupePile(
                    championnat: championnat,
                    profondeur: rangs[championnat.id] ?? 0,
                    depassement: depassement,
                    enVol: enVol.contains(championnat.id)
                )
                .zIndex(0)
            }

            ForEach(championnats) { championnat in
                let profondeur = rangs[championnat.id] ?? 0
                let vol = enVol.contains(championnat.id)

                CartePile(
                    championnat: championnat,
                    profondeur: profondeur,
                    depassement: depassement,
                    enVol: vol,
                    apercu: apercu == championnat.id,
                    descente: (rangApercu.map { profondeur < $0 } ?? false) ? descente : 0,
                    ombreAllegee: glissementEnCours && profondeur > 0 && !vol,
                    glissable: profondeur == 0 && nombre > 1,
                    mouvementReduit: mouvementReduit,
                    toucher: { toucher(championnat, profondeur: profondeur) },
                    suivant: envoyerAuFond,
                    precedent: ramenerDuFond,
                    suivreGeste: { enCours in
                        if glissementEnCours != enCours { glissementEnCours = enCours }
                    },
                    mesurer: { hauteur in
                        if hauteursPleines[championnat.id] != hauteur {
                            hauteursPleines[championnat.id] = hauteur
                        }
                    }
                )
                .zIndex(plan(profondeur: profondeur, id: championnat.id))
            }
        }
        // Les bandes sont décalées vers le haut : la place qu'elles occupent est réservée ici.
        .padding(.top, Perspective.decalage(nombre - 1))
        // Et celle que prennent les cartes de devant en descendant sous un aperçu, en bas :
        // l'accueil s'écarte avec elles, dans le même ressort.
        .padding(.bottom, descente)
    }

    /// De combien descendent les cartes de devant l'aperçu : sa hauteur pleine, moins la
    /// bande qu'il occupait déjà — réduite à sa profondeur —, moins un chevauchement qui
    /// glisse la carte suivante sur son bas. **8 pt et non `Rayon.carte`** comme au repos :
    /// la jauge est posée à 16 pt du bas, et 20 pt de chevauchement en laissaient dépasser
    /// un trait.
    private func descenteApercu(rang: Int) -> CGFloat {
        guard let apercu, let hauteur = hauteursPleines[apercu] else { return 0 }
        return max(0, hauteur - Perspective.depassement(rang) - 8)
    }

    /// L'ordre d'empilement, du plus haut au plus bas :
    /// 1. la carte du dessus **tant que le doigt la tire** ;
    /// 2. les cartes en vol vers le fond, jusqu'à la fin de leur ressort — au-dessus de la
    ///    nouvelle carte du dessus, qu'elles découvrent en partant ;
    /// 3. la carte du dessus ;
    /// 4. les autres, de l'avant vers le fond.
    ///
    /// Aux rangs 2 et 4, entre elles, dans leur ordre d'origine. **L'aperçu n'a pas de rang
    /// à lui** : il garde celui de sa profondeur, sous les cartes de devant — qui
    /// descendent pour lui faire place, et ne se font donc jamais couvrir.
    private func plan(profondeur: Int, id: UUID) -> Double {
        let n = Double(nombre)
        let p = Double(profondeur)
        if profondeur == 0 && glissementEnCours { return 7 * n }
        if enVol.contains(id) { return 2 * n + 1 + (n - p) }
        if profondeur == 0 { return 2 * n }
        return n - p
    }

    // MARK: - Tap et aperçu

    /// Le ressort d'un aperçu : critique, sans dépassement — un tap ne lance rien
    /// (/apple-design §4). Sous mouvement réduit, l'aperçu se pose sans trajet.
    private var animationApercu: Animation? {
        mouvementReduit ? nil : Mouvement.pile
    }

    /// - l'aperçu : ouvre son championnat ;
    /// - la carte du dessus : l'ouvre — ou, un aperçu étant déplié, le replie seulement ;
    /// - une bande : la déplie en aperçu, en repliant celui d'avant.
    private func toucher(_ championnat: Championnat, profondeur: Int) {
        if apercu == championnat.id {
            ouvrirDepuisApercu(championnat)
        } else if profondeur == 0 {
            if apercu != nil {
                withAnimation(animationApercu) { apercu = nil }
            } else {
                championnatOuvert = championnat
            }
        } else {
            withAnimation(animationApercu) { apercu = championnat.id }
        }
    }

    /// Le championnat ouvert depuis son aperçu passera au premier plan : l'ordre est
    /// mémorisé **tout de suite** — l'app peut être tuée sur l'écran poussé —, mais
    /// appliqué au retour seulement.
    private func ouvrirDepuisApercu(_ championnat: Championnat) {
        var nouvel = ordreEffectif
        nouvel.removeAll { $0 == championnat.id }
        nouvel.insert(championnat.id, at: 0)
        OrdrePile.ecrire(nouvel, pour: idUtilisateur)
        ordreAuRetour = nouvel
        championnatOuvert = championnat
    }

    // MARK: - Réordonnancement

    /// Rapproche l'ordre mémorisé de la liste reçue, et le mémorise s'il a changé : c'est
    /// ce qui fixe la place d'un championnat nouveau — au fond — avant que l'ordre par
    /// défaut ne le range ailleurs à la prochaine lecture.
    private func rapprocherEtMemoriser() {
        let rapproche = ordreEffectif
        guard rapproche != ordre, !championnats.isEmpty else { return }
        ordre = rapproche
        OrdrePile.ecrire(rapproche, pour: idUtilisateur)
    }

    /// La carte du dessus part au fond, **par-dessus le paquet** : elle ne redescend dans
    /// l'ordre d'empilement qu'à l'arrêt complet.
    private func envoyerAuFond(lancee: Bool) {
        guard nombre > 1 else { return }
        var nouvel = ordreEffectif
        let partante = nouvel.removeFirst()
        nouvel.append(partante)
        OrdrePile.ecrire(nouvel, pour: idUtilisateur)
        glissementEnCours = false

        if mouvementReduit {
            withAnimation(Mouvement.entree(Mouvement.passageEcran)) {
                ordre = nouvel
                apercu = nil
            }
            return
        }

        trajetsEnCours += 1
        // `.removed` et non le défaut `.logicallyComplete` : un ressort est « logiquement »
        // fini avant d'être immobile, et la carte passerait derrière en bougeant encore.
        withAnimation(lancee ? Mouvement.pileLancee : Mouvement.pile, completionCriteria: .removed) {
            enVol.insert(partante)
            enVol.remove(nouvel[0])
            ordre = nouvel
            apercu = nil
        } completion: {
            trajetsEnCours -= 1
            guard trajetsEnCours == 0 else { return }
            withAnimation(Mouvement.entree(Mouvement.fonduPile)) {
                enVol.removeAll()
            }
        }
    }

    /// Ramène la carte du fond au premier plan. Personne ne passe au fond : toutes les
    /// autres reculent d'un cran, dans le même ordre, et rien ne se croise.
    private func ramenerDuFond() {
        guard nombre > 1 else { return }
        var nouvel = ordreEffectif
        nouvel.insert(nouvel.removeLast(), at: 0)
        OrdrePile.ecrire(nouvel, pour: idUtilisateur)
        glissementEnCours = false
        withAnimation(mouvementReduit ? Mouvement.entree(Mouvement.passageEcran) : Mouvement.pileLancee) {
            enVol.remove(nouvel[0])
            ordre = nouvel
            apercu = nil
        }
    }
}

// MARK: - La perspective

/// La profondeur du paquet : **chaque cran vers le fond retire 3 %** à la carte — largeur,
/// hauteur, bande visible, texte —, centrée. 1 pour la carte du dessus, 0,97, 0,94…
///
/// **Plafonnée à cinq crans** (0,85) : au-delà la vingtième bande deviendrait illisible,
/// et passerait sous le plancher tactile. La bande nue mesure donc 52 pt — 44 / 0,85
/// arrondi —, et **la plus petite garde ses 44 pt** : 50,4 · 48,9 · 47,3 · 45,8 · 44,2.
private enum Perspective {

    static let pas: CGFloat = 0.03
    static let crans = 5
    static let bande: CGFloat = 52

    static func echelle(_ profondeur: Int) -> CGFloat {
        1 - pas * CGFloat(min(max(profondeur, 0), crans))
    }

    /// La bande visible d'une carte, à sa profondeur.
    static func depassement(_ profondeur: Int) -> CGFloat {
        bande * echelle(profondeur)
    }

    /// De combien le haut d'une carte monte au-dessus de celui de la carte du dessus : la
    /// somme des bandes, chacune à sa taille.
    static func decalage(_ profondeur: Int) -> CGFloat {
        guard profondeur > 0 else { return 0 }
        return (1...profondeur).reduce(0) { $0 + depassement($1) }
    }
}

// MARK: - L'ordre mémorisé

/// L'ordre de la pile, **un par compte**, dans `UserDefaults` — le seul propriétaire de
/// sa clé, de sa lecture et de son ordre par défaut.
enum OrdrePile {

    private static func cle(_ utilisateur: UUID) -> String {
        "accueil.pile.ordre.\(utilisateur.uuidString)"
    }

    static func lire(pour utilisateur: UUID?) -> [UUID] {
        guard let utilisateur,
              let brut = UserDefaults.standard.stringArray(forKey: cle(utilisateur)) else { return [] }
        return brut.compactMap(UUID.init(uuidString:))
    }

    /// Sans compte connu, rien n'est écrit : l'ordre irait sous une clé que personne ne
    /// relirait.
    static func ecrire(_ ordre: [UUID], pour utilisateur: UUID?) {
        guard let utilisateur else { return }
        UserDefaults.standard.set(ordre.map(\.uuidString), forKey: cle(utilisateur))
        // La carte du dessus est le choix par défaut du widget « Classement ».
        SynchroWidgetClassement.premierPlan(ordre.first)
    }

    /// Du plus grand effectif au plus petit ; à égalité, par nom.
    static func parDefaut(_ championnats: [Championnat]) -> [UUID] {
        championnats.sorted {
            if $0.nombreMembres != $1.nombreMembres { return $0.nombreMembres > $1.nombreMembres }
            return $0.nom.localizedStandardCompare($1.nom) == .orderedAscending
        }.map(\.id)
    }

    /// L'ordre mémorisé, privé des championnats quittés ; les championnats qu'il ne
    /// connaît pas vont **au fond**, rangés entre eux par l'ordre par défaut. Rien de
    /// mémorisé : l'ordre par défaut.
    static func rapprocher(_ memorise: [UUID], de championnats: [Championnat]) -> [UUID] {
        let presents = Set(championnats.map(\.id))
        var vus = Set<UUID>()
        let gardes = memorise.filter { presents.contains($0) && vus.insert($0).inserted }
        let nouveaux = parDefaut(championnats.filter { !vus.contains($0.id) })
        return gardes + nouveaux
    }
}

// MARK: - Une carte

/// Une carte de la pile, à n'importe quelle profondeur. **Elle porte son propre geste** :
/// le déplacement sous le doigt est un `@GestureState` local, si bien qu'un glissement ne
/// redessine qu'elle — la pile et les autres cartes ne sont pas invalidées.
private struct CartePile: View {

    let championnat: Championnat
    let profondeur: Int
    let depassement: CGFloat
    /// En route vers le fond, au-dessus du paquet.
    let enVol: Bool
    /// Dépliée en carte pleine à sa place dans le paquet.
    let apercu: Bool
    /// Devant un aperçu : la carte descend de toute la hauteur qu'il a prise.
    let descente: CGFloat
    /// Vrai pendant qu'une autre carte est tirée : l'ombre perd sa couche ambiante, la
    /// seule coûteuse, et la retrouve au lâcher.
    let ombreAllegee: Bool
    /// Seule la carte du dessus d'une pile d'au moins deux cartes porte un geste — aperçu
    /// déplié ou non : le swipe le replie. Toutes les autres laissent le glissement au
    /// défilement de l'accueil.
    let glissable: Bool
    let mouvementReduit: Bool
    let toucher: () -> Void
    let suivant: (_ lancee: Bool) -> Void
    let precedent: () -> Void
    let suivreGeste: (_ enCours: Bool) -> Void
    let mesurer: (_ hauteurPleine: CGFloat) -> Void

    /// Le geste en cours. Retombe tout seul à la fin — et quand le système l'annule, cas
    /// où `onEnded` n'est jamais appelé —, sur le ressort du lancer.
    @GestureState(resetTransaction: Transaction(animation: Mouvement.pileLancee))
    private var geste = EtatGeste()
    /// L'axe du dernier geste, relu par `onEnded`. Une référence et non un état : l'écrire
    /// ne redessine rien.
    @State private var axeRetenu = AxeRetenu()

    private var dessus: Bool { profondeur == 0 }
    /// La face pleine se montre : carte du dessus ou aperçu.
    private var pleine: Bool { dessus || apercu }

    /// Pleine pour la carte du dessus et l'aperçu. Une carte du dessous mesure sa bande,
    /// plus le rayon qui se glisse sous la suivante — sans lui, ses coins carrés se
    /// verraient dans l'arrondi de l'autre. **En vol, elle s'arrête à sa bande** : posée
    /// par-dessus sa voisine, ce rayon en couvrirait le nom.
    private var hauteur: CGFloat? {
        if pleine { return nil }
        return enVol ? depassement : depassement + Rayon.carte
    }

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous)

        Button(action: toucher) {
            CarteChampionnat(championnat: championnat, ombre: false)
                // Toujours à sa hauteur pleine, rognée ensuite : la mesure qui fixe la
                // descente des cartes de devant ne dépend pas de la face montrée.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: \.size.height, action: mesurer)
                .accessibilityHidden(!pleine)
                .overlay {
                    FaceDessous(championnat: championnat, depassement: depassement)
                        .opacity(pleine ? 0 : 1)
                        // Les deux faces se relaient plus vite que la carte ne se déplace :
                        // au rythme du ressort, leurs deux textes se lisaient superposés.
                        .animation(Mouvement.entree(Mouvement.fonduPile), value: pleine)
                        .accessibilityHidden(pleine)
                }
                .frame(height: hauteur, alignment: .top)
                .clipShape(forme)
                // En sombre, la teinte Pantone tombe à 1,06:1 contre le fond : le filet
                // dessine le bord de chaque carte du paquet (invisible en clair).
                .overlay(forme.strokeBorder(Color.filetAplat, lineWidth: 1))
                .contentShape(forme)
                // En vol, l'ombre s'éteint au rythme du trajet : sur la bande voisine elle se
                // voit, et elle ne doit pas disparaître d'un coup quand la carte passe derrière.
                .ombreAplat(intensite: enVol ? 0 : 1, allegee: ombreAllegee)
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        // Le paquet rapetisse vers le fond, centré, depuis le haut de chaque carte : la
        // bande visible rétrécit avec elle. L'aperçu reprend sa taille pleine : il se
        // détache du paquet sans le quitter.
        .scaleEffect(apercu ? 1 : Perspective.echelle(profondeur), anchor: .top)
        .offset(y: -Perspective.decalage(profondeur) + descente + geste.dy)
        // En vol, elle passe au-dessus des bandes : elle ne doit pas leur voler le tap.
        .allowsHitTesting(!enVol)
        // Priorité haute : sans elle, le ScrollView de l'accueil captait le geste vertical
        // et l'écran défilait sous la carte. Partout ailleurs, le geste reste au défilement.
        .highPriorityGesture(glisser, including: glissable ? .all : .subviews)
        .onChange(of: geste.axe) { _, axe in
            if dessus { suivreGeste(axe == .vertical) }
        }
        .accessibilityActions {
            if glissable {
                Button(t("accueil.pile.suivant")) { suivant(false) }
                Button(t("accueil.pile.precedent")) { precedent() }
            }
        }
    }

    /// Le geste vertical de la carte du dessus. **Vers le haut elle suit le doigt 1:1** ;
    /// vers le bas elle résiste — la carte qui vient alors est celle du fond, et c'est
    /// elle qui fera le trajet. Un lancer suffit : la décision lit la position projetée,
    /// pas seulement la distance parcourue (/apple-design §6).
    ///
    /// L'axe se décide au premier déplacement : un geste majoritairement horizontal ne
    /// déplace rien. Les mesures se font dans l'espace **global** : la translation lue ne
    /// dépend jamais du décalage que le geste applique lui-même à la carte.
    private var glisser: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($geste) { valeur, etat, _ in
                if etat.axe == nil {
                    let t = valeur.translation
                    etat.axe = abs(t.height) >= abs(t.width) ? .vertical : .horizontal
                    axeRetenu.axe = etat.axe
                }
                guard etat.axe == .vertical, dessus, !mouvementReduit else { return }
                let dy = valeur.translation.height
                etat.dy = dy < 0 ? dy : elastique(dy)
            }
            .onEnded { valeur in
                guard axeRetenu.axe == .vertical, dessus else { return }
                let dy = valeur.translation.height
                let projete = valeur.predictedEndTranslation.height
                if dy < -48 || projete < -140 {
                    suivant(true)
                } else if dy > 48 || projete > 140 {
                    precedent()
                }
                // Sinon rien : le geste retombe et la carte revient en place sur son ressort.
            }
    }

    /// Résistance progressive : plus le doigt tire, moins la carte suit.
    private func elastique(_ ecart: CGFloat) -> CGFloat {
        let dimension: CGFloat = 120
        return (ecart * dimension * 0.55) / (dimension + 0.55 * abs(ecart))
    }
}

/// L'état d'un glissement : son axe, fixé au premier déplacement (`nil` hors geste), et le
/// déplacement vertical appliqué à la carte.
private struct EtatGeste {
    var axe: Axis?
    var dy: CGFloat = 0
}

private final class AxeRetenu {
    var axe: Axis?
}

// MARK: - La jupe d'une carte

/// Le dessous d'une carte de la pile, posé **sous tout le paquet** : sa teinte voilée,
/// de `Rayon.carte` sous le haut de sa bande jusqu'à `Rayon.carte` sous son bas.
///
/// Elle ne sert qu'en vol : la carte s'arrête alors à sa bande et passe **devant** sa
/// voisine, et c'est la jupe qui comble, derrière cette voisine, les coins arrondis et
/// le dépassement du ressort — ce que fait au repos le rayon que la carte glisse sous
/// elle. Son haut reste sous l'arrondi de sa carte, jamais au-dessus du paquet.
///
/// **Hors vol elle est éteinte.** Au repos elle serait couverte, mais une carte du
/// dessus tirée vers le haut découvre le bas de la bande suivante : ses coins carrés
/// s'y verraient. Elle s'allume avec le trajet, sur son ressort, et s'éteint avec le
/// fondu qui rend à la carte son rayon.
private struct JupePile: View {

    let championnat: Championnat
    let profondeur: Int
    let depassement: CGFloat
    let enVol: Bool

    var body: some View {
        let echelle = Perspective.echelle(profondeur)
        Color.teinteChampionnat(pour: championnat.cleTeinte)
            .overlay(Color.voile.opacity(Materiau.voilePile))
            .frame(height: depassement)
            .scaleEffect(echelle, anchor: .top)
            .offset(y: -Perspective.decalage(profondeur) + Rayon.carte * echelle)
            .opacity(enVol ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - La face d'une carte du dessous

/// Ce que montre une carte recouverte : la même surface que ``CarteChampionnat`` —
/// teinte, damier, lueur —, assombrie d'un cran, et sur sa bande visible le nom et le
/// classement « 1/3 ».
///
/// **Les encres sont celles de la grande carte** : le blanc pour le nom et la position,
/// ``Color/encreSecondaire`` pour l'effectif. Toutes deux sont mesurées sur la teinte nue
/// (≥ 4,97:1) ; le voile ne fait qu'y ajouter du contraste.
private struct FaceDessous: View {

    let championnat: Championnat
    let depassement: CGFloat

    private var membres: Int { championnat.nombreMembres }

    var body: some View {
        ZStack(alignment: .top) {
            Color.teinteChampionnat(pour: championnat.cleTeinte)
            Damier(opacite: Materiau.damier)
            LueurHaute()
            Color.voile.opacity(Materiau.voilePile)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(championnat.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .tracking(-0.15)                              // −0,01em × 15
                    .foregroundColor(.encreSurAplat)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(championnat.position.map { String($0.monRang) } ?? "–")
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                        .foregroundColor(.encreSurAplat)
                    Text("/\(membres)")
                        .font(.custom("HelveticaNeue-Medium", size: 13))
                        .foregroundColor(.encreSecondaire)
                }
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(height: depassement)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("accueil.pile.afficher", championnat.nom))
        .accessibilityValue(libelleRang)
    }

    private var libelleRang: String {
        guard let rang = championnat.position?.monRang else {
            return tp("championnat.classementIndisponible", membres)
        }
        return t("championnat.classementRang", ordinal(rang), membres)
    }
}
