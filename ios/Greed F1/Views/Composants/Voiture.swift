import SwiftUI

// MARK: - Palette des voitures

/// Les vingt couleurs proposées par les sélecteurs du profil.
///
/// **Ce n'est pas la palette du design system, et elle n'a pas à l'être.** Ces teintes ne
/// peignent **que des voitures** — jamais un fond, un bouton ni un texte d'écran. C'est
/// l'écart que la version web assume déjà dans `frontend/src/lib/palette.js`, et cette
/// table en est la transcription exacte : une vingt-et-unième teinte inventée ici ferait
/// diverger les deux applications au premier enregistrement.
///
/// Quatre d'entre elles reprennent le design system plutôt que d'inventer un ton de plus :
/// bordeaux `#800111`, marron `#543925`, amber `#E8A020`, beige `#F5F0EB`.
enum PaletteVoiture {

    struct Teinte: Identifiable, Equatable {
        let nom: String
        let hex: String
        var id: String { hex }
        var couleur: Color { EncreSVG.couleur(hex) ?? .primaire }
    }

    static let teintes: [Teinte] = [
        Teinte(nom: "Rouge",      hex: "#CC0000"),
        Teinte(nom: "Blanc",      hex: "#FFFFFF"),
        Teinte(nom: "Noir",       hex: "#000000"),
        Teinte(nom: "Gris",       hex: "#8A8A8A"),
        Teinte(nom: "Argent",     hex: "#C0C0C0"),
        Teinte(nom: "Bleu foncé", hex: "#003087"),
        Teinte(nom: "Bleu clair", hex: "#0090D4"),
        Teinte(nom: "Turquoise",  hex: "#00A19C"),
        Teinte(nom: "Vert foncé", hex: "#005C43"),
        Teinte(nom: "Vert clair", hex: "#00D2BE"),
        Teinte(nom: "Orange",     hex: "#FF8000"),
        Teinte(nom: "Jaune",      hex: "#FFD700"),
        Teinte(nom: "Rose",       hex: "#E8027B"),
        Teinte(nom: "Violet",     hex: "#960064"),
        Teinte(nom: "Bordeaux",   hex: "#800111"),
        Teinte(nom: "Marron",     hex: "#543925"),
        Teinte(nom: "Amber",      hex: "#E8A020"),
        Teinte(nom: "Beige",      hex: "#F5F0EB"),
        Teinte(nom: "Or",         hex: "#B8860B"),
        Teinte(nom: "Anthracite", hex: "#2D2D2D")
    ]

    /// Les défauts de colonne, répétés ici pour que le rendu n'attende personne.
    static let coqueParDefaut = "#800111"
    static let aileronsParDefaut = "#FFFFFF"

    /// Nom lisible d'une teinte, pour l'étiquette du sélecteur.
    static func nom(de hex: String) -> String {
        let propre = EncreSVG.normaliser(hex)
        return teintes.first { EncreSVG.normaliser($0.hex) == propre }?.nom ?? "Personnalisée"
    }

    /// Luminance relative (WCAG). **Écrite une fois** : deux implémentations du même calcul
    /// finiraient par juger deux textes de la même app selon des règles différentes.
    static func luminance(_ hex: String) -> Double {
        let propre = EncreSVG.normaliser(hex).dropFirst()
        guard propre.count == 6, let valeur = UInt32(propre, radix: 16) else { return 0 }
        func canal(_ octet: UInt32) -> Double {
            let v = Double(octet) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * canal((valeur >> 16) & 0xFF)
             + 0.7152 * canal((valeur >> 8) & 0xFF)
             + 0.0722 * canal(valeur & 0xFF)
    }

    /// L'encre lisible sur un aplat : le texte du design system, ou le blanc.
    ///
    /// **Le numéro est la seule chose qui identifie une voiture** à la taille où on la
    /// regarde. La palette compte du blanc, de l'argent, du beige et du jaune : un numéro
    /// blanc dessus serait invisible, et le cas n'a rien de théorique.
    static func encreSur(_ aplat: String) -> Color {
        luminance(aplat) > 0.45 ? .texte : .white
    }
}

// MARK: - Livrées d'écurie

/// Les onze livrées, **découpées dans les planches, pas redessinées**.
///
/// **Chaque livrée porte sa propre fenêtre, mesurée.** Les planches empilent leurs
/// voitures en zigzag, ni jointives ni régulièrement espacées : des tranches arithmétiques
/// auraient coupé les unes et laissé du vide autour des autres. Les valeurs sont les boîtes
/// englobantes réelles, obtenues en échantillonnant les courbes de Bézier — les mêmes que
/// `frontend/src/composants/VoituresEcuries.jsx`, coordonnée pour coordonnée.
///
/// > **Alpine et Mercedes sortent d'une autre planche.** `VOITUREs_am.svg` les porte aux
/// > mêmes coordonnées que la table du web, là où `voitures_ecuries.svg` en garde une
/// > seconde copie ailleurs dans le fichier. Les deux rendent le même dessin ; c'est la
/// > première qui fait foi, comme côté web.
///
/// **L'ordre est celui de `frontend/src/lib/livrees.js`** — celui de la grille 2026, et
/// celui dans lequel la grille de choix les présente.
struct LivreeEcurie: Identifiable {

    let slug: String
    let nom: String

    /// La planche de la **voiture** et sa fenêtre.
    let planche: String
    let fenetre: CGRect

    /// La planche de la **vignette de casque** et sa fenêtre — la grille de choix.
    let planchebadge: String
    let fenetreBadge: CGRect

    /// Le disque noir du casque, où se découpe la photo du membre.
    let cockpit: (x: CGFloat, y: CGFloat, r: CGFloat)

    /// L'axe de la voiture, et les deux lignes de base des textes de la carrosserie.
    let cx: CGFloat
    let yNumero: CGFloat
    let yNom: CGFloat

    /// Les deux aplats sous les textes. **Ils diffèrent sur neuf livrées sur onze** : la
    /// planche écrit les deux en blanc, ce qui rend le pseudo illisible sur les ailerons
    /// clairs de Haas et de Cadillac. Calculer l'encre corrige un défaut du fichier source.
    let fondNumero: String
    let fondAile: String

    /// La teinte de l'écurie — celle de `frontend/src/lib/ecuries.js`, jamais la couleur
    /// dominante du dessin : trois livrées sont à dominante blanche et deux à dominante
    /// grise, soit cinq pastilles indistinguables sur onze.
    let teinte: String

    var id: String { slug }

    private static let voiture = CGSize(width: 141.12, height: 288.09)
    private static let badge = CGSize(width: 255.70, height: 255.70)

    private init(_ slug: String, _ nom: String,
                 planche: String, x: CGFloat, y: CGFloat,
                 badge: String, bx: CGFloat, by: CGFloat,
                 cockpit: (CGFloat, CGFloat, CGFloat),
                 cx: CGFloat, yNumero: CGFloat, yNom: CGFloat,
                 fondNumero: String, fondAile: String, teinte: String) {
        self.slug = slug
        self.nom = nom
        self.planche = planche
        self.fenetre = CGRect(origin: CGPoint(x: x, y: y), size: Self.voiture)
        self.planchebadge = badge
        self.fenetreBadge = CGRect(origin: CGPoint(x: bx, y: by), size: Self.badge)
        self.cockpit = (cockpit.0, cockpit.1, cockpit.2)
        self.cx = cx
        self.yNumero = yNumero
        self.yNom = yNom
        self.fondNumero = fondNumero
        self.fondAile = fondAile
        self.teinte = teinte
    }

    static let toutes: [LivreeEcurie] = [
        LivreeEcurie("red-bull", "Red Bull",
                     planche: "voitures_ecuries", x: 349.53, y: 168.95,
                     badge: "matt", bx: 82.37, by: 362.13,
                     cockpit: (420.22, 340.08, 20.41),
                     cx: 420.09, yNumero: 240.63, yNom: 444.66,
                     fondNumero: "#23366C", fondAile: "#3A3938", teinte: "#1E3A8A"),

        LivreeEcurie("ferrari", "Ferrari",
                     planche: "voitures_ecuries", x: 74.55, y: 459.29,
                     badge: "matti", bx: 51.48, by: 3857.05,
                     cockpit: (145.23, 630.42, 20.41),
                     cx: 145.10, yNumero: 530.96, yNom: 735.00,
                     fondNumero: "#BF181F", fondAile: "#3A3938", teinte: "#FF2800"),

        LivreeEcurie("mercedes", "Mercedes",
                     planche: "VOITUREs_am", x: 39.62, y: 459.01,
                     badge: "matti", bx: 51.48, by: 3481.59,
                     cockpit: (110.30, 630.14, 20.41),
                     cx: 110.17, yNumero: 530.69, yNom: 734.73,
                     fondNumero: "#3A3938", fondAile: "#3A3938", teinte: "#00D2BE"),

        LivreeEcurie("alpine", "Alpine",
                     planche: "VOITUREs_am", x: 39.62, y: 29.39,
                     badge: "matti", bx: 51.48, by: 3047.65,
                     cockpit: (110.30, 200.52, 20.41),
                     cx: 110.17, yNumero: 101.07, yNom: 305.11,
                     fondNumero: "#2F4E9D", fondAile: "#E194C0", teinte: "#0090FF"),

        LivreeEcurie("aston-martin", "Aston Martin",
                     planche: "voitures_ecuries", x: 342.85, y: 978.63,
                     badge: "matti", bx: 51.48, by: 2637.40,
                     cockpit: (413.53, 1149.76, 20.41),
                     cx: 413.40, yNumero: 1050.3075, yNom: 1254.3446,
                     fondNumero: "#044032", fondAile: "#3A3938", teinte: "#006F44"),

        LivreeEcurie("audi", "Audi",
                     planche: "voitures_ecuries", x: 74.79, y: 1261.85,
                     badge: "matti", bx: 51.48, by: 2301.97,
                     cockpit: (145.47, 1432.98, 20.42),
                     cx: 145.34, yNumero: 1333.5222, yNom: 1537.5593,
                     fondNumero: "#837E7A", fondAile: "#3A3938", teinte: "#FF4D4D"),

        LivreeEcurie("mclaren", "McLaren",
                     planche: "voitures_ecuries", x: 351.87, y: 1418.37,
                     badge: "matti", bx: 51.48, by: 1930.42,
                     cockpit: (422.56, 1589.50, 20.41),
                     cx: 422.43, yNumero: 1490.0491, yNom: 1694.0862,
                     fondNumero: "#EC6408", fondAile: "#EC6408", teinte: "#FF8000"),

        LivreeEcurie("racing-bulls", "Racing Bulls",
                     planche: "voitures_ecuries", x: 77.66, y: 1647.49,
                     badge: "matt", bx: 82.37, by: 6.04,
                     cockpit: (148.35, 1818.62, 20.41),
                     cx: 148.22, yNumero: 1719.1651, yNom: 1923.2022,
                     fondNumero: "#EDEDED", fondAile: "#3A3938", teinte: "#6CBBEE"),

        LivreeEcurie("williams", "Williams",
                     planche: "voitures_ecuries", x: 337.74, y: 1849.97,
                     badge: "matti", bx: 51.48, by: 814.22,
                     cockpit: (408.42, 2021.10, 20.41),
                     cx: 408.29, yNumero: 1921.6448, yNom: 2125.6822,
                     fondNumero: "#668BC7", fondAile: "#3A3938", teinte: "#37BEDD"),

        LivreeEcurie("haas", "Haas",
                     planche: "voitures_ecuries", x: 329.28, y: 2259.66,
                     badge: "matti", bx: 51.48, by: 112.31,
                     cockpit: (399.96, 2430.79, 20.41),
                     cx: 399.83, yNumero: 2331.3398, yNom: 2535.3775,
                     fondNumero: "#BFBABB", fondAile: "#EDEDED", teinte: "#212121"),

        LivreeEcurie("cadillac", "Cadillac",
                     planche: "voitures_ecuries", x: 72.21, y: 2050.49,
                     badge: "matti", bx: 51.48, by: 433.73,
                     cockpit: (142.89, 2221.62, 20.41),
                     cx: 142.76, yNumero: 2122.1698, yNom: 2326.2074,
                     fondNumero: "#1D1D1B", fondAile: "#EDEDED", teinte: "#9CA3AF")
    ]

    /// La livrée d'un slug. **`nil` pour un slug inconnu, jamais une livrée inventée** —
    /// la voiture retombe alors sur le mode personnalisé, ce que ``Livree`` garantit,
    /// plutôt que de laisser un trou.
    static func slug(_ slug: String?) -> LivreeEcurie? {
        guard let slug else { return nil }
        return toutes.first { $0.slug == slug }
    }

    /// La livrée d'une écurie désignée par **n'importe lequel de ses libellés** — « Red
    /// Bull », « Red Bull Racing », « Oracle Red Bull Racing ». C'est la forme d'OpenF1 que
    /// reçoit le classement d'une course, et il n'a que ça pour choisir la voiture.
    ///
    /// Transcription de `livreeDeLEcurie` + `ALIAS_ECURIES` (`frontend/src/lib/`) —
    /// **à mettre à jour avec eux, à chaque saison**. `nil` pour un libellé inconnu.
    static func duLibelle(_ libelle: String?) -> LivreeEcurie? {
        guard let libelle, !libelle.isEmpty else { return nil }
        let recu = cle(libelle)
        if let nom = alias.first(where: { cle($0.key) == recu })?.value {
            return toutes.first { $0.nom == nom }
        }
        return toutes.first { cle($0.nom) == recu }
    }

    private static let alias: [String: String] = [
        "Red Bull Racing": "Red Bull", "Oracle Red Bull Racing": "Red Bull",
        "Haas F1 Team": "Haas", "MoneyGram Haas": "Haas",
        "Audi F1 Team": "Audi", "Audi Sauber": "Audi", "Sauber": "Audi",
        "Alpine F1 Team": "Alpine", "BWT Alpine": "Alpine",
        "Aston Martin Aramco": "Aston Martin",
        "Visa Cash App RB": "Racing Bulls", "RB": "Racing Bulls",
        "Cadillac F1 Team": "Cadillac",
        "Scuderia Ferrari": "Ferrari",
        "Mercedes AMG": "Mercedes",
        "Williams Racing": "Williams"
    ]

    /// La `cle` du web : accents ôtés, minuscules, espaces, points et tirets fondus.
    private static func cle(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .map { ".-".contains($0) ? " " : $0 }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

// MARK: - Ce que porte une voiture

/// Ce que porte une voiture — **le seul endroit qui en décide**.
///
/// Sans lui, chaque écran relirait le mode à sa façon et un membre pourrait apparaître en
/// livrée Ferrari au classement et aux couleurs de son choix sur la piste.
struct Livree: Equatable {

    enum Mode: String { case perso, ecurie }

    var mode: Mode = .perso
    var ecurie: String?
    var coque: String = PaletteVoiture.coqueParDefaut
    var ailerons: String = PaletteVoiture.aileronsParDefaut

    /// **`nil` n'est pas « pas de couleur » mais « pas de choix »** : les deux textes
    /// reprennent alors l'encre calculée qui contraste avec l'aplat sous chacun d'eux.
    /// Aucun repli sur le blanc — il rendrait le numéro invisible sur les quatre teintes
    /// claires de la palette.
    var couleurTexte: String?

    /// La livrée d'écurie effectivement portée, ou `nil` si c'est la livrée personnelle.
    var ecurieChoisie: LivreeEcurie? {
        mode == .ecurie ? LivreeEcurie.slug(ecurie) : nil
    }

    /// L'aplat sous le numéro — l'aplat du **museau**, jamais celui de l'aileron. Le
    /// sélecteur « Couleur du texte » en a besoin pour afficher, dès le premier montage,
    /// ce qui est réellement à l'écran.
    var aplatDuNumero: String {
        ecurieChoisie?.fondNumero ?? coque
    }
}

// MARK: - La voiture

/// La voiture vue du dessus, dans ses deux modes.
///
/// - **Ma livrée** — la première voiture de `voitures_perso.svg`, repeinte par les deux
///   couleurs du membre : partout où la planche écrit `#be1622` (sa classe `cls-6`, la
///   carrosserie) on peint la coque, partout où elle écrit `#ededed` (`cls-14`) on peint
///   les ailerons.
/// - **Livrée écurie** — l'une des onze voitures des planches, dont les couleurs sont fixes.
///
/// **Les pièces mécaniques gardent leurs gris d'origine** — pneus `#1d1d1b`, suspensions
/// `#706f6f`, fond plat `#3c3c3b`, casque `#020102`. Les repeindre ferait perdre la lecture
/// de l'objet : une voiture entièrement monochrome n'a plus de roues.
///
/// **Le cockpit porte l'identité du membre** : la photo y est découpée en rond, et à
/// défaut son initiale sur la teinte de la marque. Posée exactement sur le cercle que la
/// planche peint — la géométrie vient du fichier, pas d'un réglage à l'œil.
struct VueVoiture: View {

    let livree: Livree

    /// Le numéro peint sur le museau. Trois chiffres au plus, comme côté web.
    var numero: String = ""

    /// Le pseudo peint sur l'aileron arrière.
    var nom: String = ""

    /// La photo du membre, découpée dans le cockpit. Absente, c'est l'initiale — qui n'est
    /// pas un cas dégradé mais l'état par défaut de tout compte.
    var photo: URL?

    /// Allume le cockpit. Sans lui ni photo, le casque reste le noir de la planche : c'est
    /// ce que veut un aperçu sans membre derrière.
    var teintePilote: Color?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// Le rapport de toutes les fenêtres de voiture — 141,12 × 288,09. Il est le même sur
    /// les douze : c'est le même dessin, douze fois repeint.
    static let rapport: CGFloat = 141.12 / 288.09

    // MARK: Valeurs de la planche

    /// Cadrage et ancrages de la voiture personnalisable (première de la planche).
    /// `cockpit` est le `<circle fill="#020102">` du casque, relevé dans le fichier — pas
    /// déduit de `cx`, dont il s'écarte de 0,13 unité.
    private static let perso = (
        fenetre: CGRect(x: 55.08, y: 57.74, width: 141.12, height: 288.09),
        cockpit: (x: CGFloat(125.77), y: CGFloat(228.87), r: CGFloat(20.41)),
        cx: CGFloat(125.64), yNumero: CGFloat(129.41), yNom: CGFloat(333.45)
    )

    /// Les deux classes colorisables de la planche personnalisable : la carrosserie et la
    /// surface secondaire de la **première** voiture. Les trois autres voitures de la
    /// planche ont leurs propres couples de classes et ne sont pas dans la fenêtre.
    private static let encreCoque = "#be1622"
    private static let encreAilerons = "#ededed"

    /// Corps du numéro peint sur le museau. Valeur de la planche, inchangée.
    private static let tailleNumero: CGFloat = 20.54

    /// Hauteur de capitale d'Helvetica, en fraction du corps — 717/1000 dans les métriques
    /// de la fonte. **Elle remet le numéro à l'endroit sans déplacer le dessin** : la
    /// planche l'écrivait sous `rotate(180)`, donc lisible depuis l'avant de la voiture et
    /// tête-bêche dans toutes les vues de l'app, qui sont toutes des vues de dessus.
    private static let hauteurCapitale: CGFloat = 0.717

    /// Le nom doit tenir dans les 98 unités de l'aileron arrière, quel que soit le pseudo :
    /// à taille fixe, « Alexandre » débordait.
    private static let nomMaximum = 10

    // MARK: Corps

    var body: some View {
        GeometryReader { geometrie in
            let cadre = CadrePlanche(fenetre: fenetre, taille: geometrie.size)

            ZStack {
                VuePlanche(planche: planche, fenetre: fenetre, substitutions: substitutions)

                cockpitDuMembre(cadre)
                textesDeCarrosserie(cadre)
            }
            // Un changement de couleur prend une courbe d'entrée, pas un saut : parcourir
            // la palette repeint la coque, les ailerons, le numéro et le pseudo d'un seul
            // mouvement. Sous mouvement réduit, la couleur change quand même — c'est une
            // information, pas un déplacement — mais sans transition.
            .animation(mouvementReduit ? nil : Mouvement.entree(0.2), value: livree)
        }
        .aspectRatio(Self.rapport, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(nom.isEmpty ? "Voiture" : "Voiture de \(nom)")
    }

    // MARK: Découpage

    /// Un slug inconnu retombe sur la voiture personnalisable plutôt que de ne rien rendre :
    /// une livrée retirée d'une saison à l'autre laisserait sinon un trou.
    private var ecurie: LivreeEcurie? { livree.ecurieChoisie }

    private var planche: String { ecurie?.planche ?? "voitures_perso" }
    private var fenetre: CGRect { ecurie?.fenetre ?? Self.perso.fenetre }
    private var cx: CGFloat { ecurie?.cx ?? Self.perso.cx }
    private var yNumero: CGFloat { ecurie?.yNumero ?? Self.perso.yNumero }
    private var yNom: CGFloat { ecurie?.yNom ?? Self.perso.yNom }
    private var cockpit: (x: CGFloat, y: CGFloat, r: CGFloat) {
        ecurie.map { ($0.cockpit.x, $0.cockpit.y, $0.cockpit.r) } ?? Self.perso.cockpit
    }

    /// Les couleurs d'écurie sont fixes : la table est vide, la planche garde ses encres.
    private var substitutions: [String: Color] {
        guard ecurie == nil else { return [:] }
        return [
            Self.encreCoque: EncreSVG.couleur(livree.coque) ?? .primaire,
            Self.encreAilerons: EncreSVG.couleur(livree.ailerons) ?? .white
        ]
    }

    /// La couleur choisie l'emporte sur l'encre calculée, et elle vaut pour les **deux**
    /// textes : c'est une seule décision du membre, « de quelle couleur est écrit mon nom
    /// sur ma voiture ».
    private var encreNumero: Color {
        livree.couleurTexte.flatMap(EncreSVG.couleur)
            ?? PaletteVoiture.encreSur(ecurie?.fondNumero ?? livree.coque)
    }

    private var encreNom: Color {
        livree.couleurTexte.flatMap(EncreSVG.couleur)
            ?? PaletteVoiture.encreSur(ecurie?.fondAile ?? livree.coque)
    }

    // MARK: Calques posés sur la planche

    /// Le cockpit, peint **par-dessus** le corps : dans un SVG l'ordre de document est le
    /// seul ordre de peinture, et ce `ZStack` le reproduit. Le disque teinté tient la place
    /// avec l'initiale dessus, exactement comme une pastille, jusqu'à ce que le pixel arrive.
    @ViewBuilder
    private func cockpitDuMembre(_ cadre: CadrePlanche) -> some View {
        if let teintePilote {
            let diametre = cockpit.r * 2 * cadre.echelle
            ZStack {
                teintePilote
                Text(nom.first.map { String($0).uppercased() } ?? "?")
                    // La taille de l'initiale, en fraction du DIAMÈTRE du cockpit : le
                    // rapport qu'`Avatar` applique déjà à son diamètre explicite. Une
                    // initiale dans un rond est la même question.
                    .font(.custom("HelveticaNeue-Medium", size: diametre * 0.44))
                    .foregroundColor(.white)
                if let photo {
                    AsyncImage(url: photo) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                }
            }
            .frame(width: diametre, height: diametre)
            .clipShape(Circle())
            .position(cadre.point(cockpit.x, cockpit.y))
        }
    }

    /// Les deux textes de la carrosserie. **Ils ne sont pas dans la planche** : celle-ci
    /// n'y porte que ses réserves (« ZoneName »), que ``PlancheSVG`` ignore.
    ///
    /// > **La graisse 700 est un écart assumé** à la règle « 400 et 500 uniquement »
    /// > (`ios/CLAUDE.md` §3). Elle n'est pas choisie ici : c'est celle que la planche
    /// > prescrit elle-même (`font-family: HelveticaNeue-Bold; font-weight: 700`), et c'est
    /// > du **dessin**, pas de la typographie d'interface. À 20,54 unités sur une
    /// > carrosserie de 141, une graisse 500 rendrait le numéro illisible sur la piste.
    private func textesDeCarrosserie(_ cadre: CadrePlanche) -> some View {
        let echelle = cadre.echelle
        let corpsNumero = Self.tailleNumero * echelle
        let corpsNom = Self.tailleDuNom(nomAffiche)

        return ZStack {
            if !numeroAffiche.isEmpty {
                Text(numeroAffiche)
                    .font(.custom("HelveticaNeue-Bold", size: corpsNumero))
                    .foregroundColor(encreNumero)
                    // La planche donne la ligne de base ; on vise le milieu de la hauteur
                    // de capitale, qui est ce que l'œil aligne sur le museau.
                    .position(cadre.point(cx, yNumero + Self.tailleNumero * Self.hauteurCapitale / 2))
            }
            if !nomAffiche.isEmpty {
                Text(nomAffiche)
                    .font(.custom("HelveticaNeue-Bold", size: corpsNom * echelle))
                    .foregroundColor(encreNom)
                    .position(cadre.point(cx, yNom - corpsNom * Self.hauteurCapitale / 2))
            }
        }
    }

    private var numeroAffiche: String {
        String(numero.trimmingCharacters(in: .whitespaces).prefix(3))
    }

    private var nomAffiche: String {
        String(nom.trimmingCharacters(in: .whitespaces).prefix(Self.nomMaximum))
    }

    /// La taille du nom suit la longueur du pseudo : Helvetica Neue Bold fait environ
    /// 0,58 em de large par caractère, donc 94 unités utiles divisées par cette largeur
    /// donnent la taille maximale tenable.
    private static func tailleDuNom(_ nom: String) -> CGFloat {
        min(17.5, (162 / CGFloat(max(nom.count, 1)) * 10).rounded() / 10)
    }
}

// MARK: - Vignette d'écurie

/// Le casque d'une écurie — la vignette de la grille de choix.
///
/// **C'est une fenêtre sur `matti.svg` ou `matt.svg`**, jamais un dessin recomposé. Les
/// onze casques y font exactement 255,70 × 255,70 : c'est le même dessin, onze fois repeint.
///
/// > **Deux planches, et ce n'est pas un doublon.** `matti.svg` porte les onze, mais ses
/// > casques Red Bull et Racing Bulls gardent une visière orange (`#ec6408`) que la livrée
/// > 2026 n'a plus. `matt.svg` porte les deux corrigés, et ce sont ceux-là que la table
/// > désigne.
struct VignetteEcurie: View {

    let livree: LivreeEcurie

    var body: some View {
        VuePlanche(planche: livree.planchebadge, fenetre: livree.fenetreBadge)
            .aspectRatio(1, contentMode: .fit)
    }
}
