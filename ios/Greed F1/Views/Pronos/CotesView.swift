import SwiftUI

// MARK: - La grille 2026 et ses points

/// Un pilote de la grille 2026 et ce qu'il rapporte sur les deux marchés du noyau.
///
/// > **`vainqueur` et `podium` sont des POINTS, jamais des cotes** (`CLAUDE.md` §3.1) :
/// > une cote de 2,20 vaut 22 points, et rien — ni en base, ni ici — ne stocke la cote.
/// > Aucun écran n'écrit « ×2,20 ».
///
/// **Une seule table pour les deux marchés.** Deux listes tenues séparément auraient fini
/// par ne plus nommer les mêmes pilotes, et le symptôme aurait été un pilote proposé au
/// vainqueur et introuvable au podium.
///
/// L'ordre est celui des **points croissants** du marché « Vainqueur » — les favoris en
/// tête, comme sur la version web. Le marché « Podium » suit le même ordre : ses points
/// dérivent des mêmes probabilités, ils ne les réordonnent pas.
///
/// `ecurie` est le **slug de ``LivreeEcurie``**, jamais une couleur écrite ici : la teinte
/// des onze écuries a déjà un propriétaire (`Views/Composants/Voiture.swift`), lui-même
/// aligné sur `frontend/src/lib/ecuries.js`. Une douzième copie de `#FF2800` aurait
/// divergé au premier ajustement de livrée.
struct PiloteMock: Identifiable {

    let nom: String
    let ecurie: String
    let vainqueur: Int
    let podium: Int

    var id: String { nom }

    /// La teinte de l'écurie, **lue dans la table des livrées**. `nil` pour un slug
    /// inconnu — la carte garde alors son blanc, exactement comme la version web, qui
    /// n'invente jamais une couleur de repli pour un pilote qu'elle ne connaît pas.
    var couleurEcurie: Color? {
        LivreeEcurie.slug(ecurie).flatMap { EncreSVG.couleur($0.teinte) }
    }
}

/// Les vingt-deux pilotes de la grille 2026, dans les libellés qu'emploie le bookmaker.
///
/// **Vingt-deux et non vingt** : onze écuries × deux baquets. C'est la grille de
/// `frontend/src/lib/ecuries.js`, elle-même alignée sur `backend/app/calcul/pilotes.py`.
///
/// > **Les valeurs sont mockées**, mais pas arbitraires : celles que montrent
/// > `screen-24-cotes-haut.PNG` et `screen-26-pronos-remplis.PNG` sont reprises telles
/// > quelles, et le total de la capture — 10 113 pts — retombe exactement sur la somme
/// > calculée par ``PronosView``. Le reste de la table les prolonge.
enum GrilleMock {

    static let pilotes: [PiloteMock] = [
        PiloteMock(nom: "AK.Antonelli",  ecurie: "mercedes",      vainqueur: 22,    podium: 12),
        PiloteMock(nom: "L.Norris",      ecurie: "mclaren",       vainqueur: 48,    podium: 14),
        PiloteMock(nom: "G.Russell",     ecurie: "mercedes",      vainqueur: 70,    podium: 16),
        PiloteMock(nom: "M.Verstappen",  ecurie: "red-bull",      vainqueur: 80,    podium: 18),
        PiloteMock(nom: "L.Hamilton",    ecurie: "ferrari",       vainqueur: 130,   podium: 21),
        PiloteMock(nom: "C.Leclerc",     ecurie: "ferrari",       vainqueur: 150,   podium: 23),
        PiloteMock(nom: "O.Piastri",     ecurie: "mclaren",       vainqueur: 170,   podium: 25),
        PiloteMock(nom: "L.Lawson",      ecurie: "racing-bulls",  vainqueur: 900,   podium: 90),
        PiloteMock(nom: "I.Hadjar",      ecurie: "red-bull",      vainqueur: 1100,  podium: 110),
        PiloteMock(nom: "F.Alonso",      ecurie: "aston-martin",  vainqueur: 1500,  podium: 150),
        PiloteMock(nom: "P.Gasly",       ecurie: "alpine",        vainqueur: 2000,  podium: 200),
        PiloteMock(nom: "A.Lindblad",    ecurie: "racing-bulls",  vainqueur: 2500,  podium: 250),
        PiloteMock(nom: "N.Hulkenberg",  ecurie: "audi",          vainqueur: 3300,  podium: 330),
        PiloteMock(nom: "E.Ocon",        ecurie: "haas",          vainqueur: 4000,  podium: 400),
        PiloteMock(nom: "O.Bearman",     ecurie: "haas",          vainqueur: 4000,  podium: 400),
        PiloteMock(nom: "A.Albon",       ecurie: "williams",      vainqueur: 5000,  podium: 500),
        PiloteMock(nom: "C.Sainz Jr",    ecurie: "williams",      vainqueur: 5000,  podium: 500),
        PiloteMock(nom: "G.Bortoleto",   ecurie: "audi",          vainqueur: 6600,  podium: 660),
        PiloteMock(nom: "F.Colapinto",   ecurie: "alpine",        vainqueur: 8000,  podium: 800),
        PiloteMock(nom: "L.Stroll",      ecurie: "aston-martin",  vainqueur: 10000, podium: 1000),
        PiloteMock(nom: "S.Perez",       ecurie: "cadillac",      vainqueur: 15000, podium: 1500),
        PiloteMock(nom: "V.Bottas",      ecurie: "cadillac",      vainqueur: 15000, podium: 1500)
    ]
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

// MARK: - Les deux marchés

/// Un marché du noyau — son libellé, son aplat, et **l'encre de second rang qui va avec**.
///
/// > **Les trois voyagent ensemble, et c'est le point.** Un écran qui choisirait son encre
/// > à côté de son aplat finirait par poser le blanc à 70 % de ``Color/encreSecondaire``
/// > sur le bleu ardoise, où il ne vaut que **3,86:1** — sous le plancher de 4,5:1. Une
/// > question, un propriétaire (`CLAUDE.md` §6).
enum MarcheCote: String, CaseIterable, Identifiable {

    case vainqueur
    case podium

    var id: String { rawValue }

    /// Le libellé affiché. « 2e et 3e du podium » est le **seul** libellé que l'app
    /// réécrit : c'est une constante partagée avec le backend, donc ce marché-là ne peut
    /// désigner que celui-là. Les marchés découverts par le scraper garderont le nom du
    /// bookmaker, seule source légitime.
    var libelle: String {
        switch self {
        case .vainqueur: return "Vainqueur"
        case .podium:    return "2e et 3e du podium"
        }
    }

    /// L'aplat du marché. Le rouge de la marque pour le vainqueur, le bleu ardoise pour le
    /// podium : les deux pronostics obligatoires se distinguent alors au premier coup
    /// d'œil, avant même d'être lus.
    var aplat: Color {
        switch self {
        case .vainqueur: return .primaire
        case .podium:    return .bleuArdoise
        }
    }

    /// L'encre de second rang sur cet aplat — **mesurée sur le champ de 15 % de blanc**,
    /// qui est la surface la plus claire du bloc et donc celle qui contraint :
    /// `#932734` → 4,69:1 · `#4C6584` → 4,82:1.
    var encreDouce: Color {
        switch self {
        case .vainqueur: return .encreSecondaire         // blanc à 70 %
        case .podium:    return .encreSecondaireClaire   // blanc à 85 %
        }
    }

    /// Les points de ce marché, pilote par pilote, dans l'ordre de la grille.
    var cotes: [(pilote: PiloteMock, points: Int)] {
        GrilleMock.pilotes.map { ($0, points(de: $0)) }
    }

    func points(de pilote: PiloteMock) -> Int {
        switch self {
        case .vainqueur: return pilote.vainqueur
        case .podium:    return pilote.podium
        }
    }
}

/// Un pari bonus retenu : **le marché ET le pilote**, jamais le pilote seul.
///
/// « A.Albon vainqueur » et « A.Albon sur le podium » sont deux paris distincts, qui ne
/// rapportent pas le même nombre de points. Ne garder que le nom du pilote aurait fondu
/// les deux en un.
struct PariBonus: Identifiable, Equatable {

    let marche: MarcheCote
    let pilote: String
    let points: Int

    var id: String { "\(marche.rawValue):\(pilote)" }
}

// MARK: - L'écran

/// **Fais tes paris** — le tableau des cotes, et l'ajout des paris bonus.
///
/// Référence visuelle : `Ressources/Screenshots/screen-24-cotes-haut.PNG`.
///
/// C'est le premier des deux écrans de saisie : on y met de côté jusqu'à **trois** paris
/// bonus, puis on passe à ``PronosView`` pour les deux pronostics obligatoires. Le panier
/// est donc **en haut**, avant le catalogue, et non relégué sous quarante-quatre cartes.
///
/// > **Les données sont mockées** (``GrilleMock``). Aucun appel réseau : la route
/// > `GET /grands-prix/{id}/cotes` et l'écriture des favoris seront branchées à la passe
/// > API (`docs/swift-app.md` §5).
struct CotesView: View {

    let nomGrandPrix: String
    let sousTitre: String

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    /// Le plafond de la règle métier. **Écrit une fois** : le compteur « X sur 3 max » de
    /// ``PronosView`` le relit ici plutôt que d'en garder une seconde copie.
    static let bonusMaximum = 3

    @State private var parisBonus: [PariBonus] = []

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// Mode administrateur — **mocké à `false`**. La pastille « Prévisualisation » n'existe
    /// que pour lui : elle dit que ce qu'on voit n'est pas ce que voient les autres.
    private let modeAdmin = false

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    titre

                    Spacer().frame(height: 20)
                    sectionParisBonus

                    Spacer().frame(height: 20)
                    ModeEmploi()

                    ForEach(MarcheCote.allCases) { marche in
                        Spacer().frame(height: 24)   // changement de sujet (§4.6)
                        sectionMarche(marche)
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
    }

    // MARK: - Titre

    private var titre: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fais tes paris")
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)            // 15,37:1 sur le beige

            // **`grisSecondaire` et non `texteDoux`** : sur le beige `#F5F0EB`, `#999999`
            // ne vaut que 2,52:1, sous le plancher de 4,5:1 d'un texte ordinaire.
            // `#6B6B6B` y tient 4,71:1 pour un gris que l'œil ne distingue pas du premier.
            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mes paris bonus

    /// Le panier du joueur : ce qu'il a mis de côté, et ce dans quoi ``PronosView``
    /// puisera. La rangée défile à l'horizontale, calée sur les pastilles — un doigt qui la
    /// pousse la laisse sur une pastille entière, jamais coupée en deux.
    private var sectionParisBonus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                // **L'encre est `secondaire` (9,32:1), pas `texteDoux`** : c'est le titre
                // que la composition veut bien visible, et `#999999` ne tient pas sur le
                // beige. Même correction qu'au bandeau de saison.
                Text("Mes paris bonus")
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.secondaire)

                Spacer(minLength: 12)

                if !parisBonus.isEmpty {
                    Text("\(parisBonus.count) \(parisBonus.count > 1 ? "paris" : "pari")")
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.grisSecondaire)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)

            if parisBonus.isEmpty {
                zoneVideParisBonus
            } else {
                rangeeParisBonus
            }
        }
    }

    private var rangeeParisBonus: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(parisBonus) { pari in
                    ChipPariBonus(pari: pari) { retirer(pari) }
                }
            }
            .padding(.horizontal, margeLaterale)
            .padding(.vertical, 2)
        }
        // La rangée annule la marge de l'écran pour que les pastilles glissent d'un bord à
        // l'autre, et la remet en rembourrage : c'est ce qui fait qu'aucune n'est déjà
        // coupée à l'arrivée.
        .padding(.horizontal, -margeLaterale)
    }

    /// La zone vide. **L'ambre y est décoratif** — l'étoile est masquée à l'assistance
    /// vocale et c'est la phrase qui porte seule le sens : `#E8A020` sur le blanc du bloc
    /// ne vaut que 2,2:1, sous le plancher de 3:1 d'un élément graphique porteur de sens.
    /// L'étoile qu'on touche vraiment, elle, est mesurée à 3,4:1 dans sa carte.
    private var zoneVideParisBonus: some View {
        VStack(spacing: 10) {
            Image("icone-etoile")
                .renderingMode(.template)
                .foregroundColor(.accent)
                .accessibilityHidden(true)

            Text("Ajoute des paris bonus ci-dessous avec l'étoile, puis retrouve-les à l'écran suivant.")
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

    private func sectionMarche(_ marche: MarcheCote) -> some View {
        VStack(spacing: 12) {
            enTeteMarche(marche)

            LazyVGrid(columns: [GridItem(spacing: 12), GridItem(spacing: 12)], spacing: 12) {
                ForEach(marche.cotes, id: \.pilote.id) { cote in
                    CarteCote(
                        pilote: cote.pilote,
                        points: cote.points,
                        retenu: estRetenu(marche, cote.pilote),
                        sature: sature && !estRetenu(marche, cote.pilote)
                    ) {
                        basculer(marche, cote.pilote, points: cote.points)
                    }
                }
            }
        }
    }

    /// L'en-tête du marché. **La pastille est toujours rendue, y compris à zéro** : une
    /// pastille qui apparaîtrait au premier pari bonus ferait sauter l'en-tête sous le
    /// doigt qui vient de l'ajouter.
    private func enTeteMarche(_ marche: MarcheCote) -> some View {
        let compte = parisBonus.filter { $0.marche == marche }.count

        return HStack(spacing: 12) {
            Text(marche.libelle)
                .font(.custom("HelveticaNeue-Medium", size: 13))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(.white)          // 10,88:1 · 11,04:1
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                // La coche, et non un `+` : la pastille compte ce qui est **déjà** ajouté,
                // elle ne propose rien. Un `+` inviterait à appuyer sur un en-tête qui ne
                // bascule rien.
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("\(compte)")
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .contentTransition(.numericText())
            }
            .foregroundColor(marche.aplat)        // l'aplat sur du blanc : 10,88:1 · 9,40:1
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.surface)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                marche.aplat
                LueurHaute()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreAplat()                             // aplat de couleur (§4.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Marché \(marche.libelle). \(compte) pari bonus ajouté\(compte > 1 ? "s" : "").")
    }

    // MARK: - Barre d'action

    /// La validation est **collée en bas** : sur un écran qui déroule quarante-quatre
    /// cartes, un bouton en fin de page obligerait à redescendre à chaque changement d'avis.
    private var barreAction: some View {
        let libelle = parisBonus.count > 1 ? "paris" : "pari"

        return NavigationLink {
            PronosView(sousTitre: sousTitre, parisBonus: parisBonus)
        } label: {
            Text("Continuer · \(parisBonus.count) \(libelle)")
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .foregroundColor(.white)          // 10,88:1 sur #800111
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    ZStack {
                        Color.primaire
                        LueurHaute()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
                .opacity(parisBonus.isEmpty ? 0.45 : 1)
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(parisBonus.isEmpty)
        .animation(Mouvement.entree(0.18), value: parisBonus.isEmpty)
        .padding(.horizontal, margeLaterale)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .ombreFlottant()
    }

    // MARK: - La règle des trois paris

    private var sature: Bool { parisBonus.count >= Self.bonusMaximum }

    private func estRetenu(_ marche: MarcheCote, _ pilote: PiloteMock) -> Bool {
        parisBonus.contains { $0.marche == marche && $0.pilote == pilote.nom }
    }

    /// L'ajout et le retrait passent par **le même geste sur la même étoile** : rien ne
    /// s'ajoute ici qui ne se retire au même endroit.
    private func basculer(_ marche: MarcheCote, _ pilote: PiloteMock, points: Int) {
        let pari = PariBonus(marche: marche, pilote: pilote.nom, points: points)

        withAnimation(mouvementReduit ? .none : Mouvement.entree(0.22)) {
            if let rang = parisBonus.firstIndex(of: pari) {
                parisBonus.remove(at: rang)
            } else if !sature {
                parisBonus.append(pari)
            }
        }
    }

    private func retirer(_ pari: PariBonus) {
        withAnimation(mouvementReduit ? .none : Mouvement.entree(0.22)) {
            parisBonus.removeAll { $0 == pari }
        }
    }
}

// MARK: - Une carte de cote

/// La brique de la grille à deux colonnes : un pilote, ce qu'il rapporte, et l'étoile qui
/// le met de côté.
///
/// **Hauteur fixe, et c'est ce qui fait la grille.** Deux cartes d'une même rangée doivent
/// finir à la même ligne quel que soit le nom qu'elles portent : une hauteur libre donnerait
/// des rangées en dents de scie dès qu'un pilote a un nom plus long que son voisin. Le nom
/// est donc sur **une seule ligne**, tronqué au-delà.
///
/// **La teinte d'écurie se pose PAR-DESSUS le blanc, elle ne le remplace pas.** Un aplat
/// semi-transparent posé seul laisserait passer le beige de la page : la carte cesserait
/// d'être une carte blanche et tous les contrastes mesurés ci-dessous changeraient.
///
/// Contrastes mesurés sur les onze teintes, fond compris : le nom tient au pire **14,5:1**,
/// les points **9,0:1**, et l'étoile au repos **3,16:1** — au-dessus du plancher de 3:1
/// exigé d'un élément graphique porteur de sens, qu'elle est ici.
private struct CarteCote: View {

    let pilote: PiloteMock
    let points: Int
    let retenu: Bool
    let sature: Bool
    let onBasculer: () -> Void

    /// La hauteur des cartes, écrite une fois. C'est celle de la version web (90 px),
    /// élargie de deux points pour que l'étoile y tienne sa zone tactile sans mordre sur
    /// la ligne des points.
    private let hauteur: CGFloat = 92

    /// Le liseré reste discret sur les livrées claires (1,5:1 sur le turquoise Mercedes) et
    /// aucune opacité n'y change rien — à 100 % il ne monterait qu'à 1,8:1, la couleur étant
    /// intrinsèquement pâle, pendant que les livrées sombres se mettraient à crier. 60 % est
    /// le compromis juste : c'est un **renfort**, jamais le seul porteur de l'information,
    /// le nom du pilote étant écrit juste dessous.
    private let opaciteLisere: Double = 0.60

    /// La teinte de fond, à 9,4 % — la même valeur que le `18` hexadécimal de la version web.
    private let opaciteFond: Double = 0.094

    var body: some View {
        Button(action: onBasculer) {
            VStack(alignment: .leading, spacing: 0) {
                if let teinte = pilote.couleurEcurie {
                    teinte.opacity(opaciteLisere)
                        .frame(height: 3)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(pilote.nom)
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                        .foregroundColor(.texte)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 6)

                    // Le rouge de la marque sur le blanc de la carte : 10,9:1, et 9,0:1 au
                    // pire des onze fonds teintés. **Graisse 500** — les 700 de la version
                    // web sont un écart que `ios/CLAUDE.md` §3 ne reprend pas : Helvetica
                    // Neue n'a ici que le 400 et le 500.
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(points.enPoints)
                            .font(.custom("HelveticaNeue-Medium", size: 20))
                            .tracking(-0.50)      // −0,025em × 20
                        Text("pts")
                            .font(.custom("HelveticaNeue-Medium", size: 12))
                    }
                    .foregroundColor(.primaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // L'étoile chevauche le rembourrage, jamais le texte : les points lui
                    // laissent la place à droite.
                    .padding(.trailing, 34)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: hauteur, alignment: .top)
            .background {
                ZStack {
                    Color.surface
                    if let teinte = pilote.couleurEcurie { teinte.opacity(opaciteFond) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
            .ombreCarte()
            .overlay(alignment: .bottomTrailing) {
                EtoileParisBonus(actif: retenu)
                    .frame(width: 44, height: 44)   // plancher tactile iOS
            }
            .opacity(sature ? 0.5 : 1)
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .disabled(sature)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pilote.nom), \(points) points")
        .accessibilityValue(retenu ? "Pari bonus ajouté" : "Pas encore ajouté")
        .accessibilityHint(retenu ? "Retirer de mes paris bonus" : "Ajouter à mes paris bonus")
        .accessibilityAddTraits(.isButton)
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
/// couleur nouvelle, **3,16:1** au pire des onze teintes d'écurie.
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

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private let cote: CGFloat = 22

    var body: some View {
        ZStack {
            Image("icone-etoile")
                .renderingMode(.template)
                .foregroundColor(.secondaire.opacity(0.60))
                .opacity(actif ? 0 : 1)
                .scaleEffect(echelle(visible: !actif))

            Circle()
                .fill(inverse ? Color.texte : Color.accent)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(inverse ? .accent : .texte)
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

    let pari: PariBonus
    let onRetirer: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(pari.pilote)
                .font(.custom("HelveticaNeue-Medium", size: 13))
                .foregroundColor(.texte)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(pari.points.enPoints)
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                Text("pts")
                    .font(.custom("HelveticaNeue", size: 10))
            }
            .foregroundColor(.texte)              // 7,86:1 sur l'ambre
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
            .accessibilityLabel("Retirer \(pari.pilote) de mes paris bonus")
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
/// > une teinte nouvelle : elle est écrite en valeur littérale **ici** plutôt qu'ajoutée à
/// > la palette, parce qu'elle ne peint que cet encadré et rien d'autre — un jeton
/// > inviterait à la réutiliser ailleurs.
///
/// Contraste mesuré : `#543925` sur `#FFF3DC` vaut **9,60:1**.
private struct ModeEmploi: View {

    private let fond = Color(hexadecimal: 0xFFF3DC)

    private let etapes = [
        "Ajoute tes paris bonus avec l'étoile",
        "Choisis tes 2 pronostics obligatoires (Vainqueur + Podium) depuis l'écran suivant",
        "Sélectionne jusqu'à 3 paris bonus parmi eux"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(etapes.enumerated()), id: \.offset) { rang, etape in
                HStack(alignment: .top, spacing: 10) {
                    // Encre foncée sur l'ambre : 7,86:1. Le blanc y tomberait à 2,2:1.
                    Text("\(rang + 1)")
                        .font(.custom("HelveticaNeue-Medium", size: 11))
                        .foregroundColor(.texte)
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

            Text("Prévisualisation")
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.primaire)       // 10,88:1 sur le blanc
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
        CotesView(
            nomGrandPrix: "GP Azerbaïdjan",
            sousTitre: "Samedi 26 septembre · Départ 07h00"
        )
    }
}
