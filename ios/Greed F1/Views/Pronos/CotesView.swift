import SwiftUI

// MARK: - La grille 2026 : pilote → écurie

/// L'écurie de chaque pilote de la grille 2026, **dans les libellés du bookmaker** — la seule
/// chose que l'API ne sert pas (`docs/swift-app.md` §7.6 : « l'écurie d'un pilote n'est pas
/// servie »). Statique, et **à tenir avec `frontend/src/lib/ecuries.js`**.
///
/// `ecurie` est le **slug de ``LivreeEcurie``**, jamais une couleur écrite ici : la teinte
/// des onze écuries a déjà un propriétaire (`Views/Composants/Voiture.swift`).
///
/// Les points, eux, ne vivent plus ici : ce sont ceux de `GET /grands-prix/{id}/cotes`.
enum GrillePilotes {

    private static let ecuries: [String: String] = Dictionary(uniqueKeysWithValues: [
        ("AK.Antonelli", "mercedes"),     ("G.Russell", "mercedes"),
        ("L.Norris", "mclaren"),          ("O.Piastri", "mclaren"),
        ("M.Verstappen", "red-bull"),     ("I.Hadjar", "red-bull"),
        ("L.Hamilton", "ferrari"),        ("C.Leclerc", "ferrari"),
        ("L.Lawson", "racing-bulls"),     ("A.Lindblad", "racing-bulls"),
        ("F.Alonso", "aston-martin"),     ("L.Stroll", "aston-martin"),
        ("P.Gasly", "alpine"),            ("F.Colapinto", "alpine"),
        ("N.Hulkenberg", "audi"),         ("G.Bortoleto", "audi"),
        ("E.Ocon", "haas"),               ("O.Bearman", "haas"),
        ("A.Albon", "williams"),          ("C.Sainz Jr", "williams"),
        ("S.Perez", "cadillac"),          ("V.Bottas", "cadillac")
    ].map { (ClePilote.de($0.0), $0.1) })

    /// La teinte d'écurie d'une issue. `nil` pour tout ce qui n'est pas un pilote connu —
    /// une écart, une nationalité, un duel : la carte garde alors son blanc, comme au web,
    /// qui n'invente jamais une couleur de repli.
    static func couleurEcurie(de issue: String?) -> Color? {
        ecuries[ClePilote.de(issue)]
            .flatMap { LivreeEcurie.slug($0) }
            .flatMap { EncreSVG.couleur($0.teinte) }
    }
}

/// Le nombre de points, **habillé à un seul endroit** — le pendant iOS de
/// `frontend/src/lib/format.js`, dont le CLAUDE.md dit qu'il est « le seul endroit qui
/// habille un nombre de points ».
///
/// > **Pas de séparateur de milliers, et ce n'est pas un oubli.** Interpolé tel quel dans
/// > un `Text("\(points)")`, SwiftUI passe par `LocalizedStringKey` et applique la locale :
/// > « 5 000 » là où la version web écrit « 5000 ». Deux applications qui montrent la même
/// > cote ne peuvent pas l'écrire de deux façons.
extension Int {
    var enPoints: String { String(self) }
}

/// Trois états, jamais deux (§6.1) : une valeur, **ou** « Cote retirée » quand l'issue a
/// disparu du Grand Prix depuis l'épinglage. **Jamais un zéro inventé.**
func formaterPoints(_ points: Int?) -> String {
    guard let points else { return t("points.coteRetiree") }
    return t("points.valeur", points.enPoints)
}

// MARK: - Les deux marchés obligatoires

/// Un marché du noyau — son libellé, son aplat, et **l'encre de second rang qui va avec**.
///
/// > **Les trois voyagent ensemble, et c'est le point.** Un écran qui choisirait son encre
/// > à côté de son aplat finirait par poser le blanc à 70 % de ``Color/encreSecondaire``
/// > sur le bleu ardoise, où il ne vaut que **3,86:1** — sous le plancher de 4,5:1. Une
/// > question, un propriétaire (`CLAUDE.md` §6).
///
/// Les autres marchés — ceux que le scraper découvre — gardent le libellé du bookmaker et
/// prennent l'aplat ``aplat(slug:)`` : ils n'ont pas d'encre douce, rien n'y est posé.
enum MarcheCote: String, CaseIterable, Identifiable {

    case vainqueur
    case podium

    var id: String { rawValue }

    /// Le slug du marché côté serveur — le contrôle des obligatoires est **strict** (§6.3).
    var slug: String { rawValue }

    /// Le libellé affiché. « 2e et 3e du podium » est le **seul** libellé que l'app
    /// réécrit : le vainqueur est déjà sur le podium (§6.3). Les marchés découverts par le
    /// scraper gardent le nom du bookmaker, seule source légitime.
    var libelle: String {
        switch self {
        case .vainqueur: return t("marche.vainqueur")
        case .podium:    return t("marche.podiumLong")
        }
    }

    /// Le libellé **court** — celui qui tient dans une étiquette de 10 pt au récapitulatif.
    var libelleCourt: String {
        switch self {
        case .vainqueur: return t("marche.vainqueur")
        case .podium:    return t("marche.podium")
        }
    }

    /// Le rouge de la marque pour le vainqueur, le bleu ardoise pour le podium.
    var aplat: Color {
        switch self {
        case .vainqueur: return .primaire
        case .podium:    return .bleuArdoise
        }
    }

    /// L'encre de second rang sur cet aplat — **mesurée sur le champ de 15 % de blanc** :
    /// `#932734` → 4,69:1 · `#4C6584` → 4,82:1.
    var encreDouce: Color {
        switch self {
        case .vainqueur: return .encreSecondaire         // blanc à 70 %
        case .podium:    return .encreSecondaireClaire   // blanc à 85 %
        }
    }

    /// L'aplat d'en-tête d'un marché quelconque. **Le brun `secondaire` pour les marchés
    /// bonus** : le blanc y tient 11,6:1, et il ne se confond ni avec le rouge du vainqueur
    /// ni avec le bleu du podium.
    static func aplat(slug: String) -> Color {
        MarcheCote(rawValue: slug)?.aplat ?? .secondaire
    }

    /// L'aplat du `rang`-ième marché bonus de la pile — ``Color/teintesMarcheBonus``, dans
    /// l'ordre de la liste. Les deux obligatoires gardent le leur (``aplat(slug:)``).
    static func aplatBonus(rang: Int) -> Color {
        Color.teintesMarcheBonus[rang % Color.teintesMarcheBonus.count]
    }

    /// Le vainqueur et le podium **ne se jouent pas en pari bonus** : ils sont déjà les
    /// deux pronostics obligatoires. **Seule la liste des paris bonus de ``PronosView`` les
    /// écarte** : dans « Fais tes paris » ils s'épinglent comme les autres. Le slug réel est `vainqueur` / `podium` ; le préfixe
    /// `vainqueur_course` couvre une variante de nommage du scraper.
    static func exclueDesBonus(slug: String?) -> Bool {
        guard let slug else { return false }
        return slug == MarcheCotes.vainqueur
            || slug.hasPrefix("vainqueur_course")
            || slug.hasPrefix(MarcheCotes.podium)
    }

    /// Le libellé d'en-tête d'un marché quelconque.
    static func libelle(de marche: MarcheCotes) -> String {
        MarcheCote(rawValue: marche.marche)?.libelle ?? marche.libelle
    }
}

// MARK: - Le parcours de pronostics

/// Les trois écrans du parcours, **et l'ordre dans lequel on les traverse** : le tableau
/// des cotes, la saisie, le récapitulatif. Le parcours s'ouvre par ``entree`` : le
/// récapitulatif si une grille est déjà enregistrée, le tableau des cotes sinon
/// (``EntreePronosView``).
///
/// > **Pourquoi un chemin de navigation plutôt que trois `NavigationLink` posés chacun sur
/// > sa destination.** Le récapitulatif doit pouvoir revenir d'un coup à l'écran d'où le
/// > parcours est parti, trois crans plus bas. Mesuré au simulateur : une `dismiss` prise
/// > au milieu d'une pile **ne fait rien** — elle ne ferme que l'écran du dessus. Seul un
/// > `NavigationStack(path:)` se vide, et il faut pour cela que les trois écrans soient
/// > des **valeurs** dans ce chemin.
///
/// **Le récapitulatif n'est atteint qu'après un `200`** : ``PronosView`` l'empile elle-même
/// (`avancer`) une fois l'écriture acceptée, jamais par un lien — le bandeau « Pronos
/// enregistrés ! » ne peut donc plus annoncer un enregistrement qui n'a pas eu lieu.
enum EtapePronos: Hashable {

    /// La porte d'entrée des widgets — c'est elle qui choisit le premier écran.
    case entree(GrandPrixPronos)
    /// La porte d'entrée **après la course** : ses résultats (``MesResultatsGPView``) s'il
    /// a joué, sinon le classement officiel. `date` est la date écrite, celle de
    /// ``ResultatsGPView``.
    case resultats(GrandPrixPronos, date: String)
    case cotes(GrandPrixPronos)
    case pronos(GrandPrixPronos)
    case recap(GrandPrixPronos, GrilleEnregistree)
}

extension View {

    /// Les trois destinations du parcours, **déclarées une fois pour toutes**, à poser sur
    /// la racine de chaque pile qui y mène — l'accueil et l'onglet Championnats.
    ///
    /// `avancer` empile une étape (la saisie s'en sert après le `200`), `retour` vide le
    /// chemin, et `libelleRetour` nomme ce que le récapitulatif annonce. **Le mot et l'action
    /// arrivent ensemble** : un bouton qui nommerait une destination qu'il n'atteint pas
    /// mentirait.
    func etapesPronos(libelleRetour: String,
                      avancer: @escaping (EtapePronos) -> Void,
                      retour: @escaping () -> Void) -> some View {
        navigationDestination(for: EtapePronos.self) { etape in
            switch etape {
            case let .entree(gp):
                EntreePronosView(grandPrix: gp, libelleRetour: libelleRetour,
                                 avancer: avancer, retour: retour)

            case let .resultats(gp, date):
                // Le détail du carrousel du profil — le même GP, la même vue. La branche
                // `dateResultats` d'``EntreePronosView`` reste en place, non montée.
                MesResultatsGPView(grandPrix: gp, date: date)

            case let .cotes(gp):
                CotesView(grandPrix: gp)

            case let .pronos(gp):
                PronosView(grandPrix: gp, avancer: avancer)

            case let .recap(gp, grille):
                RecapView(grandPrix: gp, grille: grille,
                          libelleRetour: libelleRetour, retour: retour)
            }
        }
    }
}

// MARK: - L'écran

/// **Fais tes paris** — le tableau des cotes, et l'épinglage des favoris. Les marchés sont
/// une pile de cartes repliables (``PileMarches``), toutes fermées à l'arrivée.
///
/// Référence visuelle : `Ressources/Screenshots/screen-24-cotes-haut.PNG`.
///
/// Les cotes sont celles de `GET /grands-prix/{id}/cotes`, **tous les marchés** que le
/// scraper a relevés, dans l'ordre d'``OrdreMarches``. L'étoile épingle une cote **en
/// favori côté serveur** (`POST …/favoris`) : c'est parmi eux que ``PronosView`` fait
/// choisir les trois paris bonus, et le serveur refuse un bonus qui n'en est pas un.
///
/// **Aucun plafond sur les favoris** : le maximum de trois porte sur les paris bonus
/// retenus à la saisie, pas sur ce qu'on met de côté.
struct CotesView: View {

    let grandPrix: GrandPrixPronos

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    /// Le plafond de la règle métier. **Écrit une fois** : le compteur « X sur 3 max » de
    /// ``PronosView`` le relit ici plutôt que d'en garder une seconde copie.
    static let bonusMaximum = 3

    @StateObject private var donnees: DonneesPronostics

    /// Le refus d'un épinglage, posé sous la rangée des favoris — jamais une alerte.
    @State private var erreurFavori: ErreurAPI?

    /// Le marché déplié de l'ancien accordéon — **non monté** depuis la pile de marchés
    /// (``PileMarches``), qui tient elle-même ses cartes ouvertes, plusieurs à la fois.
    @State private var marcheOuvert: MarcheCotes.ID?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// Prévisualisation admin — la pastille rappelle que ce qu'on voit n'est pas ce que
    /// voient les autres (``AuthViewModel/modePrevisualisation``).
    @Environment(\.modePrevisualisation) private var modeAdmin

    /// `donnees` est le chargeur d'``EntreePronosView`` quand c'est elle qui l'ouvre : les
    /// cotes déjà lues s'affichent sans second spinner.
    init(grandPrix: GrandPrixPronos, donnees: DonneesPronostics? = nil) {
        self.grandPrix = grandPrix
        _donnees = StateObject(wrappedValue: donnees
            ?? DonneesPronostics(gpId: grandPrix.id, avecMesPronostics: false))
    }

    /// Tous les favoris, vainqueur et podium compris : l'exclusion des paris bonus ne vaut
    /// que pour la liste de ``PronosView`` (``MarcheCote/exclueDesBonus(slug:)``).
    private var favoris: [Favori] { donnees.donnees?.favoris ?? [] }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    titre

                    switch donnees.etat {
                    case .chargement:
                        Spacer().frame(height: 20)
                        ChargementPronos()

                    case .echec(let erreur):
                        Spacer().frame(height: 20)
                        EchecChargement(erreur: erreur) {
                            Task { await donnees.charger() }
                        }

                    case .pret(let lu):
                        Spacer().frame(height: 20)
                        sectionParisBonus

                        Spacer().frame(height: 20)
                        ModeEmploi()

                        if lu.gp.marches.isEmpty {
                            Spacer().frame(height: 24)
                            Text(t("cotes.aucune"))
                                .font(.corps)
                                .foregroundColor(.secondaire)       // 9,32:1 sur le beige
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }

                        if !lu.gp.marches.isEmpty {
                            Spacer().frame(height: 24)   // changement de sujet (§4.6)
                            PileMarches(marches: lu.gp.marches, favoris: favoris,
                                        estEpingle: estEpingle) { cote, marche in
                                basculer(cote, dans: marche)
                            }
                        }
                    }
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        // Le titre de l'écran est dans le contenu, à 28 pt : la barre système ne porte que
        // le chevron de retour, qui reste le bouton natif — c'est lui qui donne le geste
        // de retour par le bord, qu'un bouton dessiné à la main ne donne pas.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { barreAction }
        .overlay(alignment: .bottomLeading) {
            if modeAdmin { PastillePrevisualisation().padding(.leading, margeLaterale) }
        }
        // Rechargé à chaque apparition — y compris au retour de la saisie (§7.6).
        .task { await donnees.charger() }
    }

    // MARK: - Titre

    private var titre: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("cotes.titre"))
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)            // 15,37:1 sur le beige

            // **`grisSecondaire` et non `texteDoux`** : sur le beige `#F5F0EB`, `#999999`
            // ne vaut que 2,52:1, sous le plancher de 4,5:1 d'un texte ordinaire.
            Text(grandPrix.sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mes favoris

    /// Le panier du joueur : ce qu'il a épinglé, et ce dans quoi ``PronosView`` puisera.
    /// La rangée défile à l'horizontale, calée sur les pastilles.
    private var sectionParisBonus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                // **L'encre est `secondaire` (9,32:1), pas `texteDoux`** : `#999999` ne
                // tient pas sur le beige.
                Text(t("pronos.mesBonus"))
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.secondaire)

                Spacer(minLength: 12)

                if !favoris.isEmpty {
                    Text(tp("cotes.favoris", favoris.count))
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.grisSecondaire)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)

            if favoris.isEmpty {
                zoneVideParisBonus
            } else {
                rangeeParisBonus
            }

            if let erreurFavori {
                ErreurEnLigne(erreur: erreurFavori)
            }
        }
    }

    private var rangeeParisBonus: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(favoris) { favori in
                    ChipPariBonus(favori: favori) { retirer(favori) }
                }
            }
            .padding(.horizontal, margeLaterale)
            .padding(.vertical, 2)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        // La rangée annule la marge de l'écran pour que les pastilles glissent d'un bord à
        // l'autre, et la remet en rembourrage : c'est ce qui fait qu'aucune n'est déjà
        // coupée à l'arrivée.
        .padding(.horizontal, -margeLaterale)
    }

    /// La zone vide. **L'ambre y est décoratif** — l'étoile est masquée à l'assistance
    /// vocale et c'est la phrase qui porte seule le sens.
    private var zoneVideParisBonus: some View {
        VStack(spacing: 10) {
            Image("icone-etoile")
                .renderingMode(.template)
                .foregroundColor(.accent)
                .accessibilityHidden(true)

            Text(t("cotes.aucunFavori"))
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
    }

    // MARK: - Un marché

    /// Un marché **en accordéon** : l'en-tête se touche, la grille de ses cotes se déplie
    /// dessous. Les marchés Unibet sont trop nombreux pour être tous dépliés d'un coup.
    ///
    /// **Non monté** : remplacé par ``PileMarches``, gardé en place (`CLAUDE.md` §6).
    private func sectionMarche(_ marche: MarcheCotes) -> some View {
        let ouvert = marcheOuvert == marche.id

        return VStack(spacing: 12) {
            Button { deplier(marche.id) } label: { enTeteMarche(marche, ouvert: ouvert) }
                .buttonStyle(StyleAppui(.grandeSurface))

            if ouvert {
                LazyVGrid(columns: [GridItem(spacing: 12), GridItem(spacing: 12)], spacing: 12) {
                    ForEach(marche.cotes) { cote in
                        CarteCote(
                            nom: cote.pilote,
                            points: cote.points,
                            couleurEcurie: GrillePilotes.couleurEcurie(de: cote.pilote),
                            retenu: estEpingle(cote)
                        ) {
                            basculer(cote, dans: marche)
                        }
                    }
                }
                // La grille descend de son en-tête : quelques points de glissement disent
                // d'où elle vient, l'opacité fait le reste.
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
    }

    /// Ouvre un marché et ferme le précédent **dans la même transaction** : les deux
    /// mouvements partent ensemble. Courbe d'entrée, à la durée de l'ouverture quand quelque
    /// chose s'ouvre, de la fermeture sinon. Mouvement réduit : l'état change sans déplacement.
    private func deplier(_ id: MarcheCotes.ID) {
        let cible: MarcheCotes.ID? = marcheOuvert == id ? nil : id
        let duree = cible == nil ? Mouvement.accordeonFermeture : Mouvement.accordeonOuverture
        withAnimation(mouvementReduit ? nil : Mouvement.entree(duree)) {
            marcheOuvert = cible
        }
    }

    /// L'en-tête du marché. **La pastille est toujours rendue, y compris à zéro** : une
    /// pastille qui apparaîtrait au premier favori ferait sauter l'en-tête sous le doigt.
    /// Elle dit, marché replié, ce qui y est déjà épinglé.
    ///
    /// Le chevron pivote de 90° à l'ouverture ; **52 pt minimum** de haut, toute la largeur
    /// se touche.
    private func enTeteMarche(_ marche: MarcheCotes, ouvert: Bool) -> some View {
        let compte = favoris.filter { $0.marche == marche.marche }.count
        let libelle = MarcheCote.libelle(de: marche)
        let aplat = MarcheCote.aplat(slug: marche.marche)

        return HStack(spacing: 12) {
            Text(libelle)
                .font(.custom("HelveticaNeue-Medium", size: 13))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(.encreSurAplat)          // 10,88:1 · 11,04:1 · 11,6:1
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                // La coche, et non un `+` : la pastille compte ce qui est **déjà** épinglé.
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("\(compte)")
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .contentTransition(.numericText())
            }
            .foregroundColor(aplat)               // l'aplat sur du blanc
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.surface)
            .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.encreSurAplat)          // ≥ 10,88:1 sur les trois aplats
                .rotationEffect(.degrees(ouvert ? 90 : 0))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            ZStack {
                aplat
                LueurHaute()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreAplat()                             // aplat de couleur (§4.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("cotes.a11y.marche", libelle, tp("cotes.favoris", compte)))
        .accessibilityValue(ouvert ? t("commun.deplie") : t("commun.replie"))
        .accessibilityHint(ouvert ? t("cotes.a11y.masquer") : t("cotes.a11y.afficher"))
    }

    // MARK: - Barre d'action

    /// La saisie est **collée en bas**. Le bouton **nomme sa destination** et reste actif
    /// sans favori : les paris bonus sont facultatifs, trois est un maximum, pas un quota.
    private var barreAction: some View {
        NavigationLink(value: EtapePronos.pronos(grandPrix)) {
            Text(t("cotes.saisir"))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .foregroundColor(.encreSurAplat)          // 10,88:1 sur #800111
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
        .padding(.horizontal, margeLaterale)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .ombreFlottant()
    }

    // MARK: - L'épinglage

    private func estEpingle(_ cote: Cote) -> Bool {
        favoris.contains { $0.idOutcomeUnibet == cote.id }
    }

    /// L'ajout et le retrait passent par **le même geste sur la même étoile**, et par la
    /// même écriture serveur que la croix d'une pastille.
    private func basculer(_ cote: Cote, dans marche: MarcheCotes) {
        erreurFavori = nil
        Task {
            let erreur = await donnees.basculerFavori(cote, dans: marche)
            withAnimation(mouvementReduit ? .none : Mouvement.entree(0.22)) {
                erreurFavori = erreur
            }
        }
    }

    /// La croix d'une pastille : la même bascule, vue de l'autre bout. Une cote retirée
    /// par le bookmaker se dépunaise quand même — son marché est reconstitué du favori.
    private func retirer(_ favori: Favori) {
        let cote = Cote(pilote: favori.pilote ?? favori.idOutcomeUnibet,
                        points: favori.points ?? 0, id: favori.idOutcomeUnibet)
        let marche = MarcheCotes(marche: favori.marche ?? "", libelle: favori.libelle ?? "",
                                 cotes: [])
        basculer(cote, dans: marche)
    }
}

// MARK: - L'attente

/// Le spinner des écrans de pronostics : premier chargement seulement — les données déjà
/// affichées restent en place pendant un rechargement (§7.6).
struct ChargementPronos: View {
    var body: some View {
        ProgressView()
            .tint(.encrePrimaire)
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityLabel(t("cotes.a11y.chargement"))
    }
}

// MARK: - Une carte de cote

/// La brique de la grille à deux colonnes : un pilote, ce qu'il rapporte, et l'étoile qui
/// le met de côté.
///
/// **Compacte** : le nom sur une ligne, les points dessous, l'étoile à droite, centrée sur
/// les deux — rien d'autre, aucun vide. Toute la carte est le bouton : sa zone tactile
/// (``hauteur`` × une demi-largeur d'écran) dépasse largement les 44 × 44 pt.
///
/// **Hauteur fixe, et c'est ce qui fait la grille.** Deux cartes d'une même rangée doivent
/// finir à la même ligne quel que soit le nom qu'elles portent : le nom est donc sur **une
/// seule ligne**, réduit puis tronqué au-delà.
///
/// **Sans `onBasculer`, pas d'étoile ni de bouton** — `favori` pose alors la petite étoile
/// pleine d'``EtoileFavori`` à côté du nom. La pile de marchés passe toujours `onBasculer`.
///
/// **La teinte d'écurie se pose PAR-DESSUS le blanc, elle ne le remplace pas.** Un aplat
/// semi-transparent posé seul laisserait passer le beige de la page : la carte cesserait
/// d'être une carte blanche et tous les contrastes mesurés ci-dessous changeraient.
///
/// Contrastes mesurés sur les onze teintes, fond compris : le nom tient au pire **14,5:1**,
/// les points **9,0:1**, et l'étoile au repos **3,16:1** — au-dessus du plancher de 3:1
/// exigé d'un élément graphique porteur de sens, qu'elle est ici.
struct CarteCote: View {

    let nom: String
    let points: Int
    /// La teinte d'écurie, `nil` hors pilote connu (``GrillePilotes``).
    let couleurEcurie: Color?
    let retenu: Bool
    /// `false` dans une carte de ``PileMarches`` : posée sur un aplat, la carte s'en
    /// détache sans ombre.
    var ombre = true
    /// Le pilote est un favori ailleurs — l'étoile pleine, purement indicative.
    var favori = false
    /// `nil` : marché exclu des bonus, la carte ne s'épingle pas.
    let onBasculer: (() -> Void)?

    /// La hauteur des cartes, écrite une fois : liseré 3, rembourrage 8 + 8, nom 17,
    /// interligne 1, points 19. **``PileMarches`` en calcule la hauteur de ses grilles.**
    static let hauteur: CGFloat = 56

    /// Le liseré reste discret sur les livrées claires (1,5:1 sur le turquoise Mercedes) et
    /// aucune opacité n'y change rien — à 100 % il ne monterait qu'à 1,8:1, la couleur étant
    /// intrinsèquement pâle, pendant que les livrées sombres se mettraient à crier. 60 % est
    /// le compromis juste : c'est un **renfort**, jamais le seul porteur de l'information,
    /// le nom du pilote étant écrit juste dessous.
    private let opaciteLisere: Double = 0.60

    /// La teinte de fond, à 9,4 % — la même valeur que le `18` hexadécimal de la version web.
    private let opaciteFond: Double = 0.094

    var body: some View {
        if let onBasculer {
            Button(action: onBasculer) { carte }
                .buttonStyle(StyleAppui(.grandeSurface))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(libelleAccessible)
                .accessibilityValue(retenu ? t("cotes.a11y.enFavori") : t("cotes.a11y.pasEnFavori"))
                .accessibilityHint(retenu ? t("cotes.a11y.retirerFavori") : t("cotes.a11y.ajouterFavori"))
                .accessibilityAddTraits(.isButton)
        } else {
            carte
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(libelleAccessible)
                .accessibilityValue(favori ? t("cotes.a11y.enFavori") : "")
        }
    }

    private var libelleAccessible: String {
        "\(nom), " + tp("classement.a11y.points", points)
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let teinte = couleurEcurie {
                teinte.opacity(opaciteLisere)
                    .frame(height: 3)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if favori { EtoileFavori() }
                        Text(nom)
                            .font(.custom("HelveticaNeue-Medium", size: 14))
                            .foregroundColor(.texte)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    // Le rouge de la marque sur le blanc de la carte : 10,9:1, et 9,0:1 au
                    // pire des onze fonds teintés. **Graisse 500** — Helvetica Neue n'a ici
                    // que le 400 et le 500 (`ios/CLAUDE.md` §3).
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(points.enPoints)
                            .font(.custom("HelveticaNeue-Medium", size: 16))
                            .tracking(-0.40)      // −0,025em × 16
                        Text(t("points.unite"))
                            .font(.custom("HelveticaNeue-Medium", size: 11))
                    }
                    .foregroundColor(.encrePrimaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if onBasculer != nil {
                    EtoileParisBonus(actif: retenu)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.hauteur, alignment: .top)
        .background {
            ZStack {
                Color.surface
                if let teinte = couleurEcurie { teinte.opacity(opaciteFond) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .modifier(OmbreFacultative(active: ombre))
    }
}

/// La petite étoile **pleine** d'un favori — purement indicative, jamais un contrôle.
/// ``EtoileJaune`` à 12 pt. Masquée à VoiceOver : la valeur de la ligne le dit.
struct EtoileFavori: View {
    var body: some View {
        EtoileJaune(cote: 12)
            .accessibilityHidden(true)
    }
}

/// `icone-etoile` en ``Color/jauneEtoile``, **cernée d'un trait `texte`**. Le jaune seul ne
/// tient que 1,40:1 sur le blanc : c'est le contour qui porte le contraste — **17,4:1** sur
/// le blanc, **14,5:1** au pire des onze teintes d'écurie (l'encre du nom des cartes), et
/// le jaune s'en détache à 12,4:1 : l'étoile se lit sur n'importe quel fond de carte. Le contour n'est pas un second tracé : c'est le même asset, en encre foncée,
/// décalé d'un demi-point dans huit directions sous l'étoile jaune.
struct EtoileJaune: View {
    let cote: CGFloat
    var epaisseur: CGFloat = 0.75

    private static let directions: [CGSize] = [
        CGSize(width: 1, height: 0), CGSize(width: -1, height: 0),
        CGSize(width: 0, height: 1), CGSize(width: 0, height: -1),
        CGSize(width: 0.7, height: 0.7), CGSize(width: -0.7, height: 0.7),
        CGSize(width: 0.7, height: -0.7), CGSize(width: -0.7, height: -0.7)
    ]

    var body: some View {
        ZStack {
            ForEach(0..<Self.directions.count, id: \.self) { i in
                etoile(.encreSurClair)
                    .offset(x: Self.directions[i].width * epaisseur,
                            y: Self.directions[i].height * epaisseur)
            }
            etoile(.jauneEtoile)
        }
        .frame(width: cote, height: cote)
        .drawingGroup()                           // neuf calques, une seule texture
    }

    private func etoile(_ encre: Color) -> some View {
        Image("icone-etoile")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(encre)
    }
}

/// L'ombre de carte, ou rien — `ombreCarte()` ne se retire pas d'un booléen.
private struct OmbreFacultative: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.ombreCarte() } else { content }
    }
}

// MARK: - L'étoile des paris bonus

/// Le signe du pari bonus — **l'étoile de la marque**, puis la coche une fois retenu.
///
/// > **L'étoile n'est pas redessinée en SwiftUI** (`ios/CLAUDE.md` §3) : c'est
/// > `icone-etoile`, découpée de `logoV2.svg` par `scripts/decouper-icones.sh` sur la même
/// > fenêtre que `IconeEtoileLogo.jsx` côté web. Les deux applications cadrent donc le même
/// > dessin, au centième d'unité.
///
/// **Le gris de l'étoile est mesuré, pas choisi.** Le `texteDoux` `#999999` du design
/// system ne vaut que **2,85:1** sur du blanc, sous le plancher de 3:1 exigé d'un élément
/// graphique porteur de sens — et le signe est ici le seul indicateur de l'état « pas
/// encore ajouté ». Le marron `secondaire` à 60 % le porte à **3,40:1** sans introduire de
/// couleur nouvelle, **3,16:1** au pire des onze teintes d'écurie. Ce gris est celui du
/// tableau des cotes ; `jaune` passe à ``EtoileJaune`` pour ``PronosView``, comme dans sa
/// feuille de choix — le contour `texte` y porte le contraste (17,4:1 sur le blanc).
///
/// **La coche est une encre foncée sur un aplat ambre, jamais une coche ambre.** `#E8A020`
/// tracé sur le blanc ne vaut que 2,2:1 ; le même ambre **en aplat** avec l'encre `#1A1A1A`
/// monte à **7,86:1**. C'est l'arbitrage de `Color.accent` : « en aplat, elle n'accepte
/// qu'une encre ».
///
/// > *Écart signalé.* La demande décrivait « étoile grise → étoile ambre ». Une étoile
/// > ambre sur blanc tomberait à 2,2:1 sur le seul signe qui dit l'état de la carte. Le
/// > couple étoile → coche sur pastille tient le même repère ambre à 7,86:1, et c'est déjà
/// > ce que fait la version web depuis la `0.67.0`.
///
/// `inverse` échange les deux encres — aplat `texte`, coche `accent` — pour la rangée de
/// ``PronosView``, **déjà ambre** : l'aplat ambre y disparaîtrait dans le fond. Le rapport
/// mesuré est le même, l'ambre et l'encre foncée n'ayant pas d'ordre.
struct EtoileParisBonus: View {

    let actif: Bool
    var inverse = false
    /// L'étoile jaune d'``EtoileJaune`` au lieu du gris — ``PronosView`` seulement.
    var jaune = false

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private let cote: CGFloat = 22

    var body: some View {
        ZStack {
            etoile
                .opacity(actif ? 0 : 1)
                .scaleEffect(echelle(visible: !actif))

            Circle()
                .fill(inverse ? Color.encreSurClair : Color.accent)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(inverse ? .accent : .encreSurClair)
                }
                .opacity(actif ? 1 : 0)
                .scaleEffect(echelle(visible: actif))
        }
        .frame(width: cote, height: cote)
        // **Échange d'icône, pas d'apparition.** Les deux signes vivent dans la même
        // cellule et se croisent en opacité : le couple est ainsi interruptible — un
        // double appui rapide repart de la valeur à l'écran au lieu de redémarrer à zéro.
        // Le jeton est celui du projet (`Mouvement.echangeIcone`), aucun n'est ajouté.
        .animation(mouvementReduit ? .easeOut(duration: Mouvement.echangeIcone)
                                   : Mouvement.entree(Mouvement.echangeIcone),
                   value: actif)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var etoile: some View {
        if jaune {
            EtoileJaune(cote: cote)
        } else {
            Image("icone-etoile")
                .renderingMode(.template)
                .foregroundColor(.secondaire.opacity(0.60))
        }
    }

    /// **Jamais `scale(0)`** : une chose doit avoir une silhouette avant d'être remplie.
    /// Sous mouvement réduit l'échelle disparaît — c'est un déplacement — et l'opacité
    /// porte seule l'échange.
    private func echelle(visible: Bool) -> CGFloat {
        if mouvementReduit { return 1 }
        return visible ? 1 : 0.9
    }
}

// MARK: - Une pastille de pari bonus

/// Une pastille de la rangée « Mes paris bonus ».
///
/// **Les points sont un aplat ambre à encre foncée, jamais du texte ambre** — 7,86:1 au
/// lieu de 2,2:1.
///
/// Le bouton de retrait fait ses **44 pt** alors que la croix n'en occupe que 14 : dans une
/// rangée qui défile sous le pouce, une cible étroite se rate.
private struct ChipPariBonus: View {

    let favori: Favori
    let onRetirer: () -> Void

    /// Le libellé de l'issue — l'identifiant brut quand la cote a disparu du Grand Prix.
    private var nom: String { favori.pilote ?? favori.idOutcomeUnibet }

    var body: some View {
        HStack(spacing: 8) {
            Text(nom)
                .font(.custom("HelveticaNeue-Medium", size: 13))
                .foregroundColor(.texte)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formaterPoints(favori.points))
                    .font(.custom("HelveticaNeue-Medium", size: 12))
            }
            .foregroundColor(.encreSurClair)      // 7,86:1 sur l'ambre
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accent)
            .clipShape(Capsule())

            Button(action: onRetirer) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondaire.opacity(0.70))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(StyleAppui(.bouton))
            .accessibilityLabel(t("cotes.a11y.retirerNom", nom))
        }
        .padding(.leading, 14)
        .frame(height: 44)
        .background(Color.surface)
        .clipShape(Capsule())
        .ombreCarte()
        // **Entrée et sortie par le même chemin** : la pastille grandit et s'efface là où
        // elle est née. Une entrée par le haut et une sortie par le bas se liraient comme
        // deux objets différents.
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}

// MARK: - Le mode d'emploi

/// Trois gestes, dans l'ordre où on les fait, à l'endroit exact où l'on passe de « ce que
/// j'ai retenu » à « ce que le bookmaker propose ». Sans lui, rien à l'écran ne dit
/// qu'ajouter une cote sert à quelque chose plus tard.
///
/// > **Deux écarts au design system, tous deux explicitement demandés.** Les bordures fines
/// > sont proscrites (`Formes.swift`) : celle-ci fait un vrai travail — sur un ambre très
/// > pâle posé sur du beige, c'est le trait qui dit où commence l'encadré. Et `#FFF3DC` est
/// > une teinte nouvelle, qui ne peint que cet encadré : ``Color/fondModeEmploi``, déclarée
/// > dans `Couleurs.swift` depuis qu'elle a une variante sombre.
///
/// Contraste mesuré : `#543925` sur `#FFF3DC` vaut **9,60:1**.
private struct ModeEmploi: View {

    private let fond = Color.fondModeEmploi

    private var etapes: [String] {
        [t("cotes.etape1"), t("cotes.etape2"), t("cotes.etape3")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(etapes.enumerated()), id: \.offset) { rang, etape in
                HStack(alignment: .top, spacing: 10) {
                    // Encre foncée sur l'ambre : 7,86:1. Le blanc y tomberait à 2,2:1.
                    Text("\(rang + 1)")
                        .font(.custom("HelveticaNeue-Medium", size: 11))
                        .foregroundColor(.encreSurClair)
                        .frame(width: 20, height: 20)
                        .background(Color.accent)
                        .clipShape(Circle())
                        .accessibilityHidden(true)

                    Text(etape)
                        .font(.custom("HelveticaNeue", size: 13))
                        .foregroundColor(.secondaire)       // 9,60:1
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fond)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous)
                .strokeBorder(Color.accent, lineWidth: 1)
        }
    }
}

// MARK: - La pastille de prévisualisation

/// Le rappel permanent que ce qu'on voit **n'est pas ce que voient les autres**.
///
/// Le mode prévisualisation montre volontairement quelque chose de faux : des Grands Prix
/// ouverts aux pronostics alors que leurs cotes ne sont pas figées. Sans marque à l'écran,
/// rien ne distingue cette vue de la vraie — et l'administrateur qui a allumé
/// l'interrupteur trois écrans plus tôt conclurait de bonne foi que le job du samedi a
/// tourné.
///
/// **Ce n'est pas un contrôle** : `allowsHitTesting(false)`, elle ne doit jamais intercepter
/// un appui destiné à ce qu'elle recouvre. L'exigence des 44 × 44 pt ne la concerne donc
/// pas, faute de cible.
///
/// > *Écart signalé.* La version web la pose sur un matériau translucide. Ici elle est
/// > **opaque** : la barre d'action est déjà un matériau, et /apple-design §12 proscrit
/// > d'empiler une surface translucide claire sur une autre — la lisibilité s'effondre.
/// > Sur le blanc, `primaire` tient 10,88:1.
struct PastillePrevisualisation: View {

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.primaire)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(t("cotes.previsualisation"))
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encrePrimaire)       // 10,88:1 sur le blanc
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Color.surface)
        .clipShape(Capsule())
        .ombreCarte()
        .allowsHitTesting(false)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    NavigationStack {
        CotesView(grandPrix: GrandPrixPronos(
            id: UUID(), nom: "GP Azerbaïdjan", slug: "azerbaidjan",
            sousTitre: "Samedi 26 septembre · Départ 07h00"))
        .etapesPronos(libelleRetour: "Accueil", avancer: { _ in }) { }
    }
}
