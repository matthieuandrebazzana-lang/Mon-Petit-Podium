import SwiftUI

// MARK: - Une ligne du récapitulatif

/// Un pronostic tel que le récapitulatif l'écrit : **l'étiquette, le pilote, les points**, et
/// son genre — vainqueur, podium ou bonus.
///
/// **Une seule forme pour les deux sections**, et non deux structures jumelles : seul
/// l'aplat de l'étiquette change.
struct LigneRecap: Identifiable, Hashable {

    enum Genre: String, Hashable { case vainqueur, podium, bonus }

    let genre: Genre
    /// Le libellé reçu à la fabrication. Seul celui d'un bonus est affiché tel quel — c'est
    /// celui du bookmaker ; les deux obligatoires sont relus dans la langue de l'interface.
    private let libelleRecu: String
    let pilote: String
    /// `nil` quand la cote a disparu depuis l'épinglage — « Cote retirée », jamais `0`.
    let points: Int?

    init(genre: Genre, libelle: String, pilote: String, points: Int?) {
        self.genre = genre
        self.libelleRecu = libelle
        self.pilote = pilote
        self.points = points
    }

    /// « Vainqueur », « Podium », ou le libellé du marché bonus tel que le bookmaker l'écrit.
    var libelle: String {
        switch genre {
        case .vainqueur: return MarcheCote.vainqueur.libelleCourt
        case .podium:    return MarcheCote.podium.libelleCourt
        case .bonus:     return libelleRecu
        }
    }

    var bonus: Bool { genre == .bonus }

    var id: String { "\(genre.rawValue):\(libelleRecu):\(pilote)" }

    /// L'aplat de l'étiquette de points. L'ambre des paris bonus, sinon celui du marché —
    /// rouge pour le vainqueur, bleu ardoise pour le podium, comme à la saisie.
    var aplat: Color {
        switch genre {
        case .vainqueur: return MarcheCote.vainqueur.aplat
        case .podium:    return MarcheCote.podium.aplat
        case .bonus:     return .accent
        }
    }

    /// L'encre de cette étiquette. **L'ambre n'accepte que ``Color/texte``** (7,86:1) ; le
    /// blanc y tomberait à 2,2:1. Sur les deux autres aplats, le blanc tient 10,88:1 et
    /// 11,04:1.
    var encre: Color { bonus ? .texte : .white }

    /// Une ligne obligatoire — vainqueur ou podium. **La seule fabrique** des deux chemins
    /// qui mènent au récapitulatif : après le `200`, et à la relecture d'une grille déjà
    /// enregistrée.
    static func obligatoire(_ marche: MarcheCote, pilote: String, points: Int?) -> LigneRecap {
        LigneRecap(genre: marche == .vainqueur ? .vainqueur : .podium,
                   libelle: marche.libelleCourt, pilote: pilote, points: points)
    }

    static func bonus(_ favori: Favori) -> LigneRecap {
        LigneRecap(genre: .bonus, libelle: favori.libelle ?? t("recap.bonus"),
                   pilote: favori.pilote ?? favori.idOutcomeUnibet, points: favori.points)
    }
}

/// La grille **acceptée par le serveur** (`200` de `POST …/pronostics`), et de quoi
/// décompter la fermeture. Elle voyage dans le chemin de navigation, d'où `Hashable`.
struct GrilleEnregistree: Hashable {
    let horaires: HorairesGP
    let obligatoires: [LigneRecap]
    let bonus: [LigneRecap]
}

extension GrilleEnregistree {

    /// La grille **déjà en base**, relue sous RLS — `nil` tant qu'il n'y a pas de vainqueur
    /// et de podium enregistrés : ``EntreePronosView`` ouvre alors le tableau des cotes.
    ///
    /// Pilotes et points viennent des cotes chargées, rapprochées par `id_outcome_unibet`,
    /// comme au préremplissage de la saisie. Une cote retirée depuis garde sa ligne, avec
    /// `points` à `nil` (« Cote retirée ») — jamais `0`, qui voudrait dire « raté ».
    init?(relue lu: DonneesPronostics.Donnees) {
        let miens = lu.miens ?? []
        guard let vainqueur = miens.first(where: { $0.type == MarcheCotes.vainqueur }),
              let podium = miens.first(where: { $0.type == MarcheCotes.podium })?.podium
        else { return nil }

        func ligne(_ marche: MarcheCote, _ id: String) -> LigneRecap {
            let cote = lu.gp.cote(id)?.cote
            return .obligatoire(marche, pilote: cote?.pilote ?? "—", points: cote?.points)
        }

        // Un bonus dépunaisé depuis reste en base jusqu'au prochain envoi : il s'affiche,
        // reconstitué de sa cote, plutôt que de disparaître en silence.
        let favoris = miens.filter { $0.type == "bonus" }.map { prono -> Favori in
            if let favori = lu.favoris.first(where: { $0.idOutcomeUnibet == prono.idOutcomeUnibet }) {
                return favori
            }
            let trouve = lu.gp.cote(prono.idOutcomeUnibet)
            return Favori(idOutcomeUnibet: prono.idOutcomeUnibet, marche: trouve?.marche.marche,
                          libelle: trouve?.marche.libelle, pilote: trouve?.cote.pilote,
                          points: trouve?.cote.points)
        }

        self.init(horaires: lu.gp.horaires,
                  obligatoires: [ligne(.vainqueur, vainqueur.idOutcomeUnibet),
                                 ligne(.podium, podium.0),
                                 ligne(.podium, podium.1)],
                  bonus: OrdreMarches.trier(favoris, slug: \.marche).map(LigneRecap.bonus))
    }
}

// MARK: - L'écran

/// **Récapitulatif** — ce que la grille vaut une fois validée, et de quoi revenir la
/// corriger.
///
/// Références visuelles : `Ressources/Screenshots/screen-27-recap-haut.PNG` et
/// `screen-28-recap-bas.PNG`.
///
/// C'est le terminus des trois écrans de pronostics : ``CotesView`` met les paris bonus de
/// côté, ``PronosView`` remplit les trois emplacements obligatoires, et celui-ci ne saisit
/// plus rien — il montre. Tout ce qui s'y modifie repasse par l'écran précédent, et le
/// bouton « Modifier mes pronos » y ramène : **un seul endroit où l'on change d'avis**.
///
/// > **Il n'est empilé qu'après le `200`** de `POST …/pronostics` (``PronosView``) : le
/// > bandeau « Pronos enregistrés ! » dit donc un enregistrement qui a eu lieu, et la grille
/// > est exactement celle que le serveur a acceptée. **Ou d'entrée**, par
/// > ``EntreePronosView``, quand une grille est déjà en base : elle est alors relue, pas
/// > supposée (``GrilleEnregistree/init(relue:)``).
struct RecapView: View {

    let grandPrix: GrandPrixPronos

    /// Ce qui vient d'être enregistré, ou ce qui l'était déjà.
    let grille: GrilleEnregistree

    /// Ce que le bouton de retour **annonce** — « Accueil » depuis l'accueil, le nom du
    /// championnat depuis un championnat. Les deux entrées du parcours ne ramènent pas au
    /// même écran (``EtapePronos``).
    let libelleRetour: String

    /// Ce qu'il **fait** : vider le chemin du parcours. Le mot et l'action arrivent
    /// ensemble, d'un seul appelant, et ne peuvent donc pas se contredire.
    let retour: () -> Void

    /// Ce que fait « Modifier mes pronos » quand **aucune saisie n'est dessous** — le
    /// récapitulatif ouvert d'entrée par ``EntreePronosView`` empile alors le parcours
    /// (cotes, puis saisie). `nil` après un enregistrement : la saisie est juste en dessous.
    var modifier: (() -> Void)? = nil

    /// Ce qui ferme **ce seul écran**, et ramène donc à la saisie.
    @Environment(\.dismiss) private var fermer

    private let margeLaterale: CGFloat = 16

    /// Rembourrage de la carte de résumé. Mesuré sur `screen-28` : 48 px à 3×.
    private let rembourrageCarte: CGFloat = 16

    /// **La course est terminée** : la grille ne se modifie plus. Le bandeau cesse de le
    /// promettre et le bouton « Modifier mes pronos » disparaît.
    private var termine: Bool { grille.horaires.statut == "termine" }

    private var obligatoires: [LigneRecap] { grille.obligatoires }
    private var lignesBonus: [LigneRecap] { grille.bonus }

    /// Ce que la grille rapporterait si tout tombait. **La même addition qu'à la saisie** —
    /// les trois obligatoires plus les paris bonus — et elle porte ici le nom que lui donne
    /// la capture : « total de points disponibles ».
    private var total: Int {
        (obligatoires + lignesBonus).reduce(0) { $0 + ($1.points ?? 0) }
    }

    var body: some View {
        // Le `GeometryReader` ne sert qu'à **une** mesure : la hauteur de la barre d'état.
        // Le drapeau est un fond perdu qui part du haut de l'écran, et le rembourrage haut
        // de son contenu est exactement cette valeur — la deviner aurait posé le bouton de
        // retour sur l'heure d'un appareil et trop bas sur un autre.
        GeometryReader { proxy in
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        EnteteDrapeau(
                            nom: grandPrix.nom,
                            sousTitre: grandPrix.sousTitre,
                            slug: grandPrix.slug,
                            retrait: proxy.safeAreaInsets.top,
                            libelleRetour: libelleRetour,
                            retour: retour
                        )

                        Spacer().frame(height: 16)
                        bandeauConfirmation

                        Spacer().frame(height: 12)   // espacement entre blocs (§4.6)
                        blocEcheance

                        Spacer().frame(height: 12)
                        carteResume
                    }
                    .padding(.bottom, 24)
                }
                // Le contenu part du **haut de l'écran**, pas du bas de la barre d'état :
                // c'est ce qui laisse le drapeau remonter jusque sous l'heure. Le bas garde
                // sa zone sûre — rien ne doit courir sous l'indicateur d'accueil.
                .ignoresSafeArea(edges: .top)
            }
        }
        // > *Écart signalé (`CLAUDE.md` §6).* **La barre de navigation native est retirée,
        // > et le retour vit dans l'en-tête.** Trois raisons, toutes mesurées au
        // > simulateur :
        // >
        // > 1. Le bouton natif prend son libellé du titre de l'écran précédent, qui est
        // >    vide : il afficherait « Retour », et il ne remonterait que d'un cran — la
        // >    saisie —, là où ce bouton-ci vide le parcours entier.
        // > 2. Sous iOS 26, un élément de barre reçoit d'office sa capsule de verre, qui
        // >    se pose en clair sur le drapeau et n'est ni dans la capture ni dans le
        // >    design system.
        // > 3. Barre visible, la zone sûre haute l'englobe : le drapeau commencerait 44 pt
        // >    plus bas, ou passerait dessous et laisserait l'heure du système en encre
        // >    sombre à **2,31:1** sur le bleu d'Azerbaïdjan. Barre masquée, la zone sûre
        // >    se réduit à la barre d'état, le drapeau commence pile dessous — c'est ce
        // >    que montre `screen-27` — et l'heure garde le beige de l'app.
        // >
        // > Masquer la barre, contrairement à `navigationBarBackButtonHidden`, **préserve
        // > le retour par glissement**. Le prix est que le bouton défile avec l'en-tête ;
        // > le geste reste, lui, disponible partout.
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Le bandeau de confirmation

    /// La confirmation, et **ce qu'elle autorise encore** : une grille validée n'est pas
    /// figée. La seconde ligne n'est pas une politesse, c'est la règle — les pronostics se
    /// modifient jusqu'au départ (`docs/metier.md`), et sans elle le bouton « Modifier mes
    /// pronos » juste en dessous aurait l'air d'une sortie de secours.
    ///
    /// > **Le sous-titre est en blanc plein, pas à 70 %.** Mesuré sur le vert sauge : le
    /// > blanc y tient **4,86:1** — et c'est déjà le maximum. À 70 % il tombe à **3,59:1**,
    /// > sous le plancher de 4,5:1 d'un texte de 13 pt. La hiérarchie passe donc par la
    /// > taille et la graisse (17/500 contre 13/400), jamais par l'opacité.
    private var bandeauConfirmation: some View {
        HStack(spacing: 14) {
            coche

            VStack(alignment: .leading, spacing: 2) {
                Text(t("recap.enregistres"))
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundColor(.white)          // 4,86:1 sur le vert sauge

                Text(termine ? t("recap.courseTerminee") : t("recap.modifiableJusquauDepart"))
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.vertSauge
                LueurHaute()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .ombreAplat()                                 // aplat de couleur (§4.7)
        .padding(.horizontal, margeLaterale)
        .accessibilityElement(children: .combine)
    }

    /// La coche, posée sur un disque de **blanc à 20 %**. C'est la surface claire du design
    /// system, et le blanc y tient **3,32:1** — au-dessus du plancher de 3:1 d'un élément
    /// graphique porteur de sens, qu'elle est : elle dit que c'est parti.
    private var coche: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 46, height: 46)
            .background(Color.white.opacity(0.20))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    // MARK: - Le compte à rebours

    /// Le **même** bloc qu'à la saisie, avec le bouton de correction glissé dessous. Deux
    /// blocs écrits séparément auraient fini par afficher deux échéances différentes à un
    /// écran d'intervalle.
    private var blocEcheance: some View {
        BlocEcheance(horaires: grille.horaires) {
            if !termine { boutonModifier }
        }
        .padding(.horizontal, margeLaterale)
    }

    /// **Après un enregistrement, il ferme cet écran, il n'en pousse pas un autre.** La
    /// saisie est juste dessous dans la pile : la rouvrir par-dessus aurait empilé deux
    /// copies du même écran, et le retour serait passé deux fois par le récapitulatif.
    /// Ouvert d'entrée, rien n'est dessous : il empile alors le parcours (``modifier``).
    private var boutonModifier: some View {
        Button {
            if let modifier { modifier() } else { fermer() }
        } label: {
            Text(t("recap.modifier"))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .foregroundColor(.white)              // 10,88:1 sur #800111
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    ZStack {
                        Color.primaire
                        LueurHaute()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
        .padding(.top, 4)
    }

    // MARK: - La carte de résumé

    /// Ce qui a été pronostiqué, marché par marché, et ce que ça vaut en tout.
    ///
    /// > **Pas de séparateur entre deux rangées**, contrairement à ce que la consigne
    /// > demandait : `screen-28-recap-bas.PNG` n'en montre qu'aux **ruptures de section**
    /// > — avant « Bonus » et avant le total. Un filet toutes les trois lignes découpe ce
    /// > qui doit se lire comme une liste ; posé aux deux endroits où le sujet change, il
    /// > dit quelque chose.
    private var carteResume: some View {
        VStack(alignment: .leading, spacing: 0) {
            titreSection(t("pronos.obligatoires"))

            Spacer().frame(height: 14)
            rangees(obligatoires)

            if !lignesBonus.isEmpty {
                Spacer().frame(height: 20)
                separateur
                Spacer().frame(height: 16)
                titreSection(t("recap.bonus"))

                Spacer().frame(height: 14)
                rangees(lignesBonus)
            }

            Spacer().frame(height: 20)
            separateur
            Spacer().frame(height: 16)
            rangeeTotal
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(rembourrageCarte)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()                                 // rayon `carte` → `ombreCarte` (§4.7)
        .padding(.horizontal, margeLaterale)
    }

    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)         // 5,33:1 sur le blanc
    }

    private func rangees(_ lignes: [LigneRecap]) -> some View {
        VStack(spacing: 18) {
            ForEach(lignes) { RangeeRecap(ligne: $0) }
        }
    }

    /// Le filet des ruptures de section. **Il n'a pas de propriétaire dans le design
    /// system** — c'est le premier écran qui en emploie un ; le jour où un second en a
    /// besoin, il montera dans `Config/Formes.swift` plutôt que d'être recopié ici.
    private var separateur: some View {
        Rectangle()
            .fill(Color.secondaire.opacity(0.12))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    /// Le total, en gros. **C'est le chiffre qu'on vient chercher**, et il est écrit dans
    /// l'encre de la marque plutôt qu'en noir : le reste de la carte est une liste, lui est
    /// une conclusion.
    ///
    /// « Disponibles » n'est pas décoratif : ces points ne sont **pas acquis**, ils sont ce
    /// que la grille rapporterait si tout tombait.
    private var rangeeTotal: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(t("recap.totalDisponible"))
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 140, alignment: .leading)

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(total.enPoints)
                    .font(.custom("HelveticaNeue-Medium", size: 40))
                    .tracking(-1.00)                  // −0,025em × 40
                Text(t("points.unite"))
                    .font(.custom("HelveticaNeue-Medium", size: 20))
            }
            .foregroundColor(.primaire)               // 10,88:1 sur le blanc
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("recap.a11y.total", tp("classement.a11y.points", total)))
    }
}

// MARK: - Une rangée

/// Le marché au-dessus, le pilote en dessous, les points au bout.
///
/// **Le marché est écrit au-dessus de chaque nom et non une fois par groupe** : le podium
/// occupe deux rangées, et un titre unique aurait laissé croire que la seconde dépend de la
/// première. Chaque ligne se lit seule.
private struct RangeeRecap: View {

    let ligne: LigneRecap

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ligne.libelle)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire) // 5,33:1 sur le blanc
                    .lineLimit(1)

                Text(ligne.pilote)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.texte)          // 15,37:1 sur le blanc
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formaterPoints(ligne.points))
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .foregroundColor(ligne.encre)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ligne.aplat)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            (ligne.bonus ? t("recap.a11y.pariBonus") : "") + "\(ligne.libelle), "
            + "\(ligne.pilote), \(formaterPoints(ligne.points))"
        )
    }
}

// MARK: - L'en-tête

/// Le drapeau du pays hôte en fond perdu, le nom du Grand Prix et son horaire dessus.
///
/// **La pile de calques est celle de l'accueil et du calendrier, et elle ne se défait
/// pas** : le drapeau tout en bas · ``LueurHaute`` · le voile calculé par
/// ``ApparenceDrapeau`` · l'assombrissement uniforme de 15 % · le contenu seul. Tout ce qui
/// éclaircit passe SOUS le voile, sans quoi la garantie de 3:1 n'en est plus une.
///
/// > *Écart signalé (`CLAUDE.md` §6).* Sur `screen-27-recap-haut.PNG` le drapeau s'arrête
/// > sous l'heure, qui reste sur le beige de l'app. Ici il **monte jusqu'en haut de
/// > l'écran** : c'est la forme iOS d'un en-tête pleine largeur, et une bande beige de
/// > 60 pt au-dessus d'un fond perdu se lirait comme un calage raté. La barre de navigation
/// > passe en encre claire pour rester lisible dessus.
private struct EnteteDrapeau: View {

    let nom: String
    let sousTitre: String
    let slug: String

    /// La zone sûre haute. La barre de navigation étant masquée, c'est **la seule barre
    /// d'état** : le drapeau commence donc pile sous l'heure, comme sur `screen-27`.
    let retrait: CGFloat

    let libelleRetour: String
    let retour: () -> Void

    private var apparence: ApparenceDrapeau? { ApparenceDrapeau.pour(slug: slug) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                boutonAccueil
                Spacer(minLength: 0)
            }

            Spacer().frame(height: 28)

            // 28 pt, avec le crénage négatif qu'/apple-design §15 impose au-delà de 24 :
            // sans lui, les lettres d'un titre s'éloignent à mesure qu'il grandit.
            Text(nom)
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .ombrePortee(apparence?.ombreNom ?? false)

            Spacer().frame(height: 8)

            Text(sousTitre)
                .font(.custom(encreDouceGrasse ? "HelveticaNeue-Medium" : "HelveticaNeue",
                              size: 13))
                .foregroundColor(encreDouce)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .ombrePortee(apparence?.ombreNom ?? false)
                .accessibilityLabel(sousTitre)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, retrait + 4)
        .padding(.bottom, 36)
        .background { fond }
    }

    /// **44 × 44 pt malgré un chevron de 17** : la zone tactile est posée par le
    /// `contentShape`, sans quoi seuls les glyphes seraient touchables.
    ///
    /// L'ombre portée est **inconditionnelle**, comme celle des cartes du calendrier : le
    /// libellé est à 17 pt — un texte ordinaire, donc un plancher de 4,5:1 — quand le voile
    /// d'``ApparenceDrapeau`` n'en garantit que 3 sur la bande la plus claire. L'ombre lui
    /// rend son contour là où le blanc du drapeau le lui prend.
    private var boutonAccueil: some View {
        Button(action: retour) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                Text(libelleRetour)
                    .font(.custom("HelveticaNeue", size: 17))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(libelleRetour)
        .accessibilityHint(t("recap.a11y.quitter"))
    }

    @ViewBuilder private var fond: some View {
        if let apparence {
            ZStack {
                // **`scaledToFill` et non `scaledToFit`** : le drapeau couvre toute la
                // bande, rogné sur son plus grand côté, jamais déformé ni cerné de vide.
                Image("flag-\(slug)")
                    .resizable()
                    .scaledToFill()

                LueurHaute()
                Color.black.opacity(apparence.voile)
                Color.black.opacity(0.15)
            }
            // Le drapeau est plus grand que la bande : sans ce rognage, `scaledToFill` le
            // laisserait déborder par-dessus le bandeau de confirmation.
            .clipped()
        } else {
            // Pays hors table : l'aplat de la marque, et aucun assombrissement — il n'a ni
            // bande ni rupture à corriger, le voiler ne ferait que l'éteindre.
            ZStack {
                Color.primaire
                LueurHaute()
            }
        }
    }

    private var encreDouce: Color { apparence?.encreDouce ?? .encreSecondaire }
    private var encreDouceGrasse: Bool { apparence?.encreDouceGrasse ?? false }
}

/// L'ombre portée du texte posé sur un drapeau à plusieurs bandes — la même valeur qu'à
/// l'accueil et au calendrier, pour que les trois écrans ne divergent pas.
private extension View {
    @ViewBuilder func ombrePortee(_ active: Bool) -> some View {
        if active {
            self.shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
        } else {
            self
        }
    }
}

#Preview("Grille complète") {
    NavigationStack {
        RecapView(
            grandPrix: GrandPrixPronos(id: UUID(), nom: "GP Azerbaïdjan", slug: "azerbaidjan",
                                       sousTitre: "Samedi 26 septembre · Départ 07h00"),
            grille: GrilleEnregistree(
                horaires: HorairesGP(statut: "cotes_figees",
                                     dateCourse: .now.addingTimeInterval(200_000),
                                     dateQualifications: nil),
                obligatoires: [
                    LigneRecap(genre: .vainqueur, libelle: "Vainqueur", pilote: "M.Verstappen", points: 80),
                    LigneRecap(genre: .podium, libelle: "Podium", pilote: "AK.Antonelli", points: 12),
                    LigneRecap(genre: .podium, libelle: "Podium", pilote: "L.Hamilton", points: 21)
                ],
                bonus: [
                    LigneRecap(genre: .bonus, libelle: "Top 6", pilote: "A.Albon", points: 50)
                ]),
            libelleRetour: t("onglet.accueil"),
            retour: { }
        )
    }
}
