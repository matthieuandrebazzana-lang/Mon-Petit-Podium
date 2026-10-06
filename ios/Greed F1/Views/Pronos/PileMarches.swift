import SwiftUI

/// Les marchés de « Fais tes paris », **empilés comme un paquet de cartes** — le pendant de
/// ``PileChampionnats`` sur l'écran des cotes.
///
/// Chaque marché est une carte sur sa teinte — le rouge et le bleu des deux obligatoires,
/// puis une teinte bonus par marché dans l'ordre (``MarcheCote/aplatBonus(rang:)``), damier et lueur
/// compris. Fermée, elle ne montre que sa **bande** : le nom du marché et la pastille de ses
/// paris bonus. La suivante se pose sur elle en recouvrant le rayon de son bas, comme les
/// bandes de l'accueil. **À l'arrivée, toutes sont fermées** : la liste se lit d'abord
/// comme un sommaire.
///
/// **Un tap sur une bande déplie la carte à sa place**, et les cartes suivantes descendent
/// de la hauteur prise ; un tap sur l'en-tête d'une carte ouverte la replie et les fait
/// remonter. **Plusieurs cartes s'ouvrent ensemble** — contrairement à l'accueil, en ouvrir
/// une ne ferme pas les autres. Une étoile touchée dans une carte ouverte ne la referme pas.
///
/// **Aucun geste de glissement.** L'ordre est celui d'``OrdreMarches``, et rien ne le
/// change : tout glissement vertical, y compris parti d'une carte, fait défiler l'écran.
///
/// > **Ce qui est repris de l'accueil, et ce qui ne l'est pas.** La mécanique est la même —
/// > cartes superposées dans une `ZStack`, ordre d'empilement par rang, carte fermée rognée
/// > à sa bande plus le rayon qui se glisse sous la suivante, cartes suivantes décalées de
/// > la hauteur dépliée moins un chevauchement, ressort `Mouvement.pile`. Deux écarts :
/// >
/// > - **le décalage est un `padding`, pas un `offset`** : une carte ouverte porte une
/// >   `LazyVGrid`, et un conteneur paresseux ne sait quelles cellules construire que
/// >   d'après sa place *de mise en page* — un `offset`, effet de rendu, la lui cacherait ;
/// > - **la hauteur dépliée est calculée, pas mesurée** : les cartes de cote ont une
/// >   hauteur fixe (``CarteCote/hauteur``), donc celle de la grille est connue d'avance.
/// >   Mesurée, elle n'arriverait qu'après la première mise en page de la grille — une
/// >   image trop tard : les cartes suivantes partiraient d'une hauteur fausse, puis
/// >   sauteraient hors du ressort.
///
/// **Seules les cartes ouvertes construisent leur grille.** Fermées, elles ne portent que
/// leur en-tête : vingt marchés repliés ne coûtent que vingt bandes.
struct PileMarches: View {

    let marches: [MarcheCotes]
    let favoris: [Favori]
    let estEpingle: (Cote) -> Bool
    let basculer: (Cote, MarcheCotes) -> Void

    /// Les cartes dépliées. **Vide à l'arrivée**, et propre à cet écran : il n'est pas
    /// mémorisé d'une visite à l'autre.
    @State private var ouverts: Set<MarcheCotes.ID> = []

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    var body: some View {
        let positions = disposition
        let aplats = self.aplats

        ZStack(alignment: .top) {
            ForEach(Array(marches.enumerated()), id: \.element.id) { rang, marche in
                let ouvert = ouverts.contains(marche.id)

                CarteMarche(
                    marche: marche,
                    aplat: aplats[rang],
                    compte: favoris.filter { $0.marche == marche.marche }.count,
                    ouvert: ouvert,
                    hauteur: positions.hauteurs[rang],
                    margeBas: rang == marches.count - 1 ? 0 : GeometriePileMarches.chevauchement,
                    estEpingle: estEpingle,
                    basculer: { basculer($0, marche) },
                    toucher: { toucher(marche.id) }
                )
                // Le décalage de la carte : la somme des pas de celles qui la précèdent.
                .padding(.top, positions.hauts[rang])
                // Chaque carte passe sur la précédente — c'est elle qui couvre le rayon du
                // bas de sa voisine, comme une bande de l'accueil couvre celle de derrière.
                .zIndex(Double(rang))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Les teintes

    /// L'aplat de chaque carte : le sien pour un obligatoire, sinon la teinte bonus de son
    /// **rang parmi les marchés bonus** — le premier bonus prend toujours la première
    /// teinte, quel que soit le nombre d'obligatoires au-dessus.
    private var aplats: [Color] {
        var rangBonus = 0
        return marches.map { marche in
            if let obligatoire = MarcheCote(rawValue: marche.marche) { return obligatoire.aplat }
            defer { rangBonus += 1 }
            return MarcheCote.aplatBonus(rang: rangBonus)
        }
    }

    // MARK: - La disposition

    /// Le haut et la hauteur de chaque carte, calculés d'un seul passage.
    ///
    /// - fermée : sa bande, plus le rayon qui se glisse sous la suivante — sans lui, ses
    ///   coins carrés se verraient dans l'arrondi de l'autre. La dernière n'a personne sur
    ///   elle : sa bande seule ;
    /// - ouverte : sa hauteur pleine ; la suivante recouvre son bas du même rayon, posé
    ///   dans une marge vide de la carte, jamais sur une cote.
    private var disposition: (hauts: [CGFloat], hauteurs: [CGFloat]) {
        var hauts: [CGFloat] = []
        var hauteurs: [CGFloat] = []
        var haut: CGFloat = 0
        let bande = GeometriePileMarches.bande
        let chevauchement = GeometriePileMarches.chevauchement

        for (rang, marche) in marches.enumerated() {
            let derniere = rang == marches.count - 1
            let hauteur: CGFloat
            let pas: CGFloat
            if ouverts.contains(marche.id) {
                hauteur = GeometriePileMarches.hauteurOuverte(issues: marche.cotes.count,
                                                              derniere: derniere)
                pas = hauteur - chevauchement
            } else {
                hauteur = derniere ? bande : bande + chevauchement
                pas = bande
            }
            hauts.append(haut)
            hauteurs.append(hauteur)
            haut += pas
        }
        return (hauts, hauteurs)
    }

    // MARK: - Le tap

    /// Ouvre ou ferme une carte, **sans toucher aux autres**. Le ressort critique de la
    /// pile de l'accueil — un tap ne lance rien, rien ne doit rebondir (/apple-design §4) —,
    /// interruptible : un second tap en plein dépliage repart de la hauteur affichée. Sous
    /// mouvement réduit, la carte se pose sans trajet.
    private func toucher(_ id: MarcheCotes.ID) {
        withAnimation(mouvementReduit ? nil : Mouvement.pile) {
            if ouverts.contains(id) {
                ouverts.remove(id)
            } else {
                ouverts.insert(id)
            }
        }
    }
}

// MARK: - La géométrie

/// Les cotes de la pile, **écrites une fois** : la carte s'y dessine, la pile en calcule ses
/// décalages. Deux textes séparés divergeraient au premier ajustement, et le symptôme —
/// une carte suivante qui mord sur une rangée de cotes — serait de ceux qu'on ne voit pas.
private enum GeometriePileMarches {

    /// La bande d'une carte fermée, qui est aussi l'en-tête d'une carte ouverte : **52 pt**,
    /// la hauteur de l'en-tête de marché de toujours — un nom Unibet y tient sur deux
    /// lignes de 13 pt.
    static let bande: CGFloat = 52

    /// Ce que chaque carte glisse sous la suivante : son rayon, pas un point de plus.
    static let chevauchement: CGFloat = Rayon.carte

    /// Le rembourrage de la grille dans sa carte, et l'espace entre deux cotes.
    static let marge: CGFloat = 12
    static let espacement: CGFloat = 12

    /// La hauteur d'une carte ouverte : sa bande, puis la grille à deux colonnes, puis sa
    /// marge basse — **augmentée du chevauchement** quand une carte suivante vient s'y
    /// poser, pour qu'elle ne couvre que du vide.
    static func hauteurOuverte(issues: Int, derniere: Bool) -> CGFloat {
        let rangees = (issues + 1) / 2
        let grille = rangees == 0
            ? 0
            : CGFloat(rangees) * CarteCote.hauteur + CGFloat(rangees - 1) * espacement
        return bande + grille + marge + (derniere ? 0 : chevauchement)
    }
}

// MARK: - Une carte

/// Une carte de la pile : l'en-tête, qui se touche, et — ouverte seulement — la grille de
/// ses cotes. La carte est **rognée** à la hauteur que la pile lui donne : c'est ce cadre
/// qui s'anime, et la grille se découvre dessous au lieu d'être dessinée en cours de route.
private struct CarteMarche: View {

    let marche: MarcheCotes
    let aplat: Color
    let compte: Int
    let ouvert: Bool
    let hauteur: CGFloat
    /// La marge vide du bas, sur laquelle la carte suivante vient se poser.
    let margeBas: CGFloat
    let estEpingle: (Cote) -> Bool
    let basculer: (Cote) -> Void
    let toucher: () -> Void

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous)

        VStack(spacing: 0) {
            Button(action: toucher) {
                EnTeteMarche(libelle: MarcheCote.libelle(de: marche), aplat: aplat,
                             compte: compte, ouvert: ouvert)
            }
            .buttonStyle(StyleAppui(.grandeSurface))

            if ouvert {
                grille
                    // La grille se découvre sous le bord qui descend : l'opacité ne fait
                    // qu'adoucir son arrivée, le cadre rogné porte le mouvement.
                    .transition(.opacity)
            }
        }
        // Toujours à sa hauteur naturelle, rognée ensuite par le cadre — comme les cartes de
        // l'accueil : la grille ne se tasse jamais pendant que le cadre s'anime.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .frame(height: hauteur, alignment: .top)
        .background {
            ZStack(alignment: .top) {
                aplat
                damier
                LueurHaute()
            }
        }
        .clipShape(forme)
        .contentShape(forme)
        .ombreAplat()                             // aplat de couleur (§4.7)
    }

    /// Le damier, **cadré sur la bande et non sur la carte**. ``Damier`` remplit son cadre
    /// (`scaledToFill`) : posé sur une carte ouverte de 1 000 pt, le motif grossissait près
    /// de trois fois et se lisait comme un flou. Sur un cadre fixe, il garde à l'ouverture
    /// l'échelle exacte de la bande fermée, et s'efface sous l'en-tête — entre deux rangées
    /// de cotes, une coupure franche se verrait.
    private var damier: some View {
        let bande = GeometriePileMarches.bande
        let hauteur = bande + 2 * GeometriePileMarches.chevauchement + GeometriePileMarches.marge
        return Damier(opacite: Materiau.damier)
            .frame(height: hauteur)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: (bande + GeometriePileMarches.chevauchement) / hauteur),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
    }

    /// Les cotes du marché, sur deux colonnes. **Paresseuse** : un marché d'une soixantaine
    /// d'issues ne construit que ses rangées visibles.
    private var grille: some View {
        LazyVGrid(columns: [GridItem(spacing: GeometriePileMarches.espacement),
                            GridItem(spacing: GeometriePileMarches.espacement)],
                  spacing: GeometriePileMarches.espacement) {
            ForEach(marche.cotes) { cote in
                CarteCote(
                    nom: cote.pilote,
                    points: cote.points,
                    couleurEcurie: GrillePilotes.couleurEcurie(de: cote.pilote),
                    retenu: estEpingle(cote),
                    // Posée sur un aplat, la carte blanche s'en détache par son seul
                    // contraste — et une ombre par cote se recalculerait à chaque image
                    // du dépliage.
                    ombre: false,
                    onBasculer: { basculer(cote) }
                )
            }
        }
        .padding(.horizontal, GeometriePileMarches.marge)
        .padding(.bottom, GeometriePileMarches.marge + margeBas)
    }
}

// MARK: - L'en-tête

/// L'en-tête d'un marché — la bande d'une carte fermée, le haut d'une carte ouverte.
///
/// **La pastille est toujours rendue, y compris à zéro** : une pastille qui apparaîtrait au
/// premier favori ferait sauter l'en-tête sous le doigt. Elle dit, carte fermée, ce qui y
/// est déjà épinglé. Le chevron pivote de 90° à l'ouverture, dans le ressort de la pile.
///
/// VoiceOver lit l'action et le marché — « Ouvrir Vainqueur » —, puis le compte des favoris.
private struct EnTeteMarche: View {

    let libelle: String
    let aplat: Color
    let compte: Int
    let ouvert: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(libelle)
                .font(.custom("HelveticaNeue-Medium", size: 13))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(.encreSurAplat)          // 10,88:1 · 11,04:1 · bonus ≥ 4,86:1
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                // La coche, et non un `+` : la pastille compte ce qui est **déjà** épinglé.
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("\(compte)")
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .contentTransition(.numericText())
            }
            .foregroundColor(aplat)           // l'aplat sur du blanc, ≥ 4,86:1
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.surface)
            .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.encreSurAplat)          // ≥ 4,86:1 sur les huit aplats (sauge)
                .rotationEffect(.degrees(ouvert ? 90 : 0))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: GeometriePileMarches.bande)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ouvert ? t("cotes.a11y.fermer", libelle) : t("cotes.a11y.ouvrir", libelle))
        .accessibilityValue(tp("cotes.favoris", compte))
        .accessibilityAddTraits(.isButton)
    }
}
