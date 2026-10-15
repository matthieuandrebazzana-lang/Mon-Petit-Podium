import SwiftUI
import WidgetKit

/// Le widget « Classement » dans ses trois formats.
///
/// - **Petit** : les cinq premiers, et l'utilisateur en plus s'il n'y est pas — ou la piste.
/// - **Moyen** : les cinq premiers à gauche, et l'utilisateur en plus s'il n'y est pas, la
///   piste à droite — ou les dix premiers sur deux colonnes de cinq, l'utilisateur à la
///   place du dixième s'il n'y est pas — ou la piste seule.
/// - **Grand** : les dix premiers à gauche, et l'utilisateur en plus s'il n'y est pas, la
///   piste à droite — ou la piste seule, sur toute la largeur.
///
/// Les rangs affichés sont toujours les **rangs réels** du classement.
///
/// **La piste est celle de l'app, réduite** : les voitures à leur place par
/// ``DispositionPiste`` — le même calcul, sur la même piste —, les mêmes livrées
/// (``VueVoiture``, planches SVG), sans kerbs ni scores.
struct VueClassement: View {

    let entree: EntreeClassement

    @Environment(\.widgetFamily) private var format
    @Environment(\.widgetContentMargins) private var marges
    @Environment(\.showsWidgetContainerBackground) private var afficheFond

    init(entree: EntreeClassement) {
        self.entree = entree
        // La langue de l'app, pas celle du téléphone (``DonneesWidget``).
        if let langue = entree.langue { LanguageManager.shared.imposer(langue) }
    }

    var body: some View {
        Group {
            if let championnat = entree.championnat, let releve = entree.releve {
                switch (format, entree.affichage, entree.affichageGrand) {
                case (.systemLarge, _, .pisteSeule):
                    PisteTitree(entree: entree, championnat: championnat, membres: releve.membres,
                                tailleTitre: 16, miseAJourEnTete: false)
                case (.systemLarge, _, _):
                    GrandClassement(entree: entree, championnat: championnat, membres: releve.membres)
                case (.systemMedium, _, _):
                    switch entree.affichageMoyen {
                    case .piste:
                        PisteTitree(entree: entree, championnat: championnat, membres: releve.membres,
                                    tailleTitre: 14, miseAJourEnTete: true)
                    case .classement:
                        MoyenClassement(entree: entree, championnat: championnat, membres: releve.membres)
                    case .classementEtPiste:
                        MoyenClassementEtPiste(entree: entree, championnat: championnat,
                                               membres: releve.membres)
                    }
                case (_, .piste, _):
                    PisteTitree(entree: entree, championnat: championnat, membres: releve.membres,
                                tailleTitre: 13, miseAJourEnTete: false)
                default:
                    PetitClassement(entree: entree, championnat: championnat, membres: releve.membres)
                }
            } else {
                ClassementNeutre()
            }
        }
        // Les marges du système, posées ici (``ClassementWidget`` les désactive) : le
        // surcroît de damier de la piste, peint au fond de cette vue, couvre alors tout le
        // widget — le même cadre que le damier du `containerBackground`, donc le même motif,
        // chevron sur chevron.
        .padding(marges)
        .backgroundPreferenceValue(ZoneDamierPiste.self) { zone in
            if let zone, afficheFond {
                GeometryReader { widget in
                    DamierPiste(cadre: widget[zone.cadre], bords: zone.bords, widget: widget.size)
                }
            }
        }
        .environment(\.locale, localeInterface)
        .widgetURL(entree.championnat.map { DonneesWidget.urlChampionnat($0.id) } ?? DonneesWidget.urlAccueil)
    }

    /// Les lignes affichées : les `tete` premiers, et l'utilisateur à la place de la
    /// dernière s'il n'y est pas — ou **en plus**, quand `enPlus` (le petit format : le
    /// podium reste entier).
    static func lignes(_ membres: [Membre], tete: Int, moi: UUID?, enPlus: Bool) -> [Membre] {
        guard let moi, let index = membres.firstIndex(where: { $0.profilId == moi }),
              index >= tete else { return Array(membres.prefix(tete)) }
        return Array(membres.prefix(enPlus ? tete : tete - 1)) + [membres[index]]
    }

    /// Ce que dit le widget, en toutes lettres.
    static func resume(_ championnat: DonneesWidget.ChampionnatWidget, _ membres: [Membre]) -> String {
        guard !membres.isEmpty else { return t("piste.aucunMembre") }
        let lignes = membres.map {
            t("piste.a11y.ligne", $0.rang, $0.pseudo, tp("classement.a11y.points", $0.totalPoints))
        }
        return t("widgetClassement.a11y.titre", championnat.nom) + lignes.joined(separator: ". ") + "."
    }
}

// MARK: - Petit format

private struct PetitClassement: View {

    let entree: EntreeClassement
    let championnat: DonneesWidget.ChampionnatWidget
    let membres: [Membre]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NomChampionnat(nom: championnat.nom, taille: 13)
                .padding(.bottom, 4)

            if membres.isEmpty {
                AucunMembre()
            } else {
                ColonneLignes(membres: VueClassement.lignes(membres, tete: 5, moi: entree.profilId, enPlus: true),
                              entree: entree, gabarit: .petit)
            }
            Spacer(minLength: 0)
            MiseAJour(entree: entree)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VueClassement.resume(championnat, membres))
    }
}

/// La piste sous le nom du championnat — le petit format, le moyen, et le grand en « Piste
/// seule ». **Une seule vue** : seuls le corps du titre et la place de « Mis à jour à »
/// changent, la piste se dispose seule dans ce qu'on lui laisse.
private struct PisteTitree: View {

    let entree: EntreeClassement
    let championnat: DonneesWidget.ChampionnatWidget
    let membres: [Membre]
    let tailleTitre: CGFloat
    /// Au moyen format, la hauteur est ce qui manque le plus : « Mis à jour à » remonte à
    /// droite du titre, où la largeur ne sert à rien.
    let miseAJourEnTete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NomChampionnat(nom: championnat.nom, taille: tailleTitre)
                if miseAJourEnTete {
                    Spacer(minLength: 0)
                    MiseAJour(entree: entree)
                }
            }
            PisteSimplifiee(membres: membres, avatars: entree.avatars)
                // Le titre au-dessus ; « Mis à jour à » dessous, s'il y est.
                .zoneDamierPiste(bords: miseAJourEnTete || entree.aJour
                                 ? [.leading, .trailing, .bottom] : [.leading, .trailing])
            if !miseAJourEnTete { MiseAJour(entree: entree) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VueClassement.resume(championnat, membres))
    }
}

// MARK: - Moyen format

/// Les dix premiers **sur deux colonnes de cinq**, lues de haut en bas puis de gauche à
/// droite ; l'utilisateur prend la place du dixième s'il n'y est pas. Cinq lignes dans
/// 115 pt — elles se resserrent sur les plus petits iPhone plutôt que de déborder. Cinq
/// membres ou moins : une seule colonne, pleine largeur.
private struct MoyenClassement: View {

    let entree: EntreeClassement
    let championnat: DonneesWidget.ChampionnatWidget
    let membres: [Membre]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NomChampionnat(nom: championnat.nom, taille: 14)
                Spacer(minLength: 0)
                MiseAJour(entree: entree)
            }
            .padding(.bottom, 4)

            if membres.isEmpty {
                AucunMembre()
                Spacer(minLength: 0)
            } else {
                let lignes = VueClassement.lignes(membres, tete: 10, moi: entree.profilId, enPlus: false)
                HStack(alignment: .top, spacing: 12) {
                    ColonneLignes(membres: Array(lignes.prefix(5)), entree: entree, gabarit: .moyen)
                    if lignes.count > 5 {
                        ColonneLignes(membres: Array(lignes.dropFirst(5)), entree: entree, gabarit: .moyen)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VueClassement.resume(championnat, membres))
    }
}

/// Le classement à gauche, la piste à droite — le grand « Classement + piste » ramené au
/// moyen format. Une colonne : les cinq premiers, et l'utilisateur **en plus** s'il n'y est
/// pas, comme au petit format. « Mis à jour à » reste à droite du titre, comme au moyen
/// « Classement » : la hauteur manque, pas la largeur. La piste prend toute la hauteur, à
/// la largeur que lui donne le rapport de la piste de l'app — la hauteur la borne de toute
/// façon, une colonne plus large ne grandirait pas les voitures.
private struct MoyenClassementEtPiste: View {

    let entree: EntreeClassement
    let championnat: DonneesWidget.ChampionnatWidget
    let membres: [Membre]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    NomChampionnat(nom: championnat.nom, taille: 14)
                    Spacer(minLength: 0)
                    MiseAJour(entree: entree)
                }
                .padding(.bottom, 4)

                if membres.isEmpty {
                    AucunMembre()
                } else {
                    ColonneLignes(membres: VueClassement.lignes(membres, tete: 5, moi: entree.profilId, enPlus: true),
                                  entree: entree, gabarit: .moyen)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PisteSimplifiee(membres: membres, avatars: entree.avatars)
                .aspectRatio(DispositionPiste.pisteApp.width / DispositionPiste.pisteApp.height,
                             contentMode: .fit)
                .frame(maxHeight: .infinity)
                .zoneDamierPiste(bords: [.top, .bottom, .trailing])
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VueClassement.resume(championnat, membres))
    }
}

// MARK: - Grand format

private struct GrandClassement: View {

    let entree: EntreeClassement
    let championnat: DonneesWidget.ChampionnatWidget
    let membres: [Membre]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                NomChampionnat(nom: championnat.nom, taille: 16)
                    .padding(.bottom, 6)

                if membres.isEmpty {
                    AucunMembre()
                } else {
                    ColonneLignes(membres: VueClassement.lignes(membres, tete: 10, moi: entree.profilId, enPlus: true),
                                  entree: entree, gabarit: .grand)
                }
                Spacer(minLength: 0)
                MiseAJour(entree: entree)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PisteSimplifiee(membres: membres, avatars: entree.avatars)
                .frame(width: 112)
                .zoneDamierPiste(bords: [.top, .bottom, .trailing])
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VueClassement.resume(championnat, membres))
    }
}

// MARK: - Les pièces

private struct NomChampionnat: View {
    let nom: String
    let taille: CGFloat

    var body: some View {
        Text(nom)
            .font(.custom("HelveticaNeue-Medium", size: taille))
            .tracking(-0.02 * taille)                         // la règle des titres
            .foregroundColor(.texte)
            .lineLimit(1)
    }
}

/// Les mesures d'une ligne, **une par format**. Le corps ne descend jamais sous 12 pt ; la
/// ligne, elle, cède entre `hauteurMin` et `hauteurMax` selon ce que l'iPhone donne au
/// widget — celle de l'iPhone SE est la plus courte (`docs/contexte-chat.md`).
private struct GabaritLigne {
    let corps: CGFloat
    let avatar: CGFloat
    let rang: CGFloat
    let espace: CGFloat
    let hauteurMin: CGFloat
    let hauteurMax: CGFloat
    let interligne: CGFloat

    /// Six lignes dans 138 × 118 pt (iPhone 17 Pro), 116 × 96 (SE).
    static let petit = GabaritLigne(corps: 12, avatar: 14, rang: 15, espace: 4,
                                    hauteurMin: 14, hauteurMax: 20, interligne: 1)
    /// Cinq lignes par colonne, deux colonnes de 160 pt (17 Pro), 138 (SE).
    static let moyen = GabaritLigne(corps: 12, avatar: 16, rang: 15, espace: 5,
                                    hauteurMin: 17, hauteurMax: 22, interligne: 1)
    /// Onze lignes dans 208 × 317 pt (17 Pro), 165 × 259 (SE).
    static let grand = GabaritLigne(corps: 14, avatar: 22, rang: 18, espace: 7,
                                    hauteurMin: 21, hauteurMax: 28, interligne: 2)
}

/// Une colonne de lignes, la ligne de l'utilisateur reconnue à son profil.
private struct ColonneLignes: View {
    let membres: [Membre]
    let entree: EntreeClassement
    let gabarit: GabaritLigne

    var body: some View {
        VStack(spacing: gabarit.interligne) {
            ForEach(membres) { membre in
                LigneWidget(membre: membre, moi: membre.profilId == entree.profilId,
                            avatar: entree.avatars[membre.profilId], gabarit: gabarit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// Une ligne : rang, avatar, pseudo, points. **La ligne de l'utilisateur est posée sur la
/// surface** — c'est elle que l'œil cherche, et la distinguer par un mot de plus la ferait
/// déborder. Le rang reprend la règle du classement de l'app : rouge sur le podium, gris
/// au-delà.
private struct LigneWidget: View {

    let membre: Membre
    let moi: Bool
    let avatar: UIImage?
    let gabarit: GabaritLigne

    var body: some View {
        HStack(spacing: gabarit.espace) {
            Text(String(membre.rang))
                .font(.custom("HelveticaNeue-Medium", size: gabarit.corps))
                .foregroundColor(membre.rang <= 3 ? .encrePrimaire : .grisSecondaire)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(width: gabarit.rang, alignment: .leading)

            PastilleWidget(pseudo: membre.pseudo, image: avatar,
                           teinte: .teinteAvatar(pour: membre.cleTeinte),
                           taille: gabarit.avatar)

            Text(membre.pseudo)
                .font(.custom(moi ? "HelveticaNeue-Medium" : "HelveticaNeue", size: gabarit.corps))
                .foregroundColor(.texte)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(membre.totalPoints))
                .font(.custom("HelveticaNeue-Medium", size: gabarit.corps))
                .foregroundColor(.encrePrimaire)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 3)
        .frame(minHeight: gabarit.hauteurMin, maxHeight: gabarit.hauteurMax)
        .background {
            if moi {
                RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous)
                    .fill(Color.surface)
            }
        }
    }
}

/// La photo du membre, ou son initiale sur sa teinte — la règle de ``PastilleProfil``,
/// avec une image déjà chargée : le widget ne télécharge rien au rendu.
private struct PastilleWidget: View {
    let pseudo: String
    let image: UIImage?
    let teinte: Color
    let taille: CGFloat

    var body: some View {
        ZStack {
            teinte
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(pseudo.first.map { String($0).uppercased() } ?? "?")
                    .font(.custom("HelveticaNeue-Medium", size: taille * 0.44))
                    .foregroundColor(.encreSurAplat)
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(Circle())
    }
}

/// « Mis à jour à 14h05 » — **seulement quand les données ne sont pas fraîches** : hors
/// ligne ou jeton expiré. À jour, il n'y a rien à dire.
private struct MiseAJour: View {
    let entree: EntreeClassement

    var body: some View {
        if !entree.aJour, let date = entree.releve?.date {
            Text(t("widgetClassement.misAJour", heureInterface(date)))
                .font(.labelSm)
                .foregroundColor(.grisSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct AucunMembre: View {
    var body: some View {
        Text(t("piste.aucunMembre"))
            .font(.custom("HelveticaNeue", size: 12))
            .foregroundColor(.secondaire)
    }
}

/// Rien à montrer : ni compte connu, ni classement reçu.
struct ClassementNeutre: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("icone-championnats")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .foregroundStyle(Color.encrePrimaire)
                .accessibilityHidden(true)
            Text(t("widgetClassement.vide"))
                .font(.custom("HelveticaNeue-Medium", size: 13))
                .foregroundColor(.secondaire)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Le fond

/// Le fond du widget, **dans tous ses états** — à jour, périmé, hors ligne, neutre : le
/// beige et le damier en filigrane (``Color/damierWidget``), le composant ``Damier`` de
/// l'app. Le motif est vectoriel et rendu à la taille du widget (≈ 5 Mo au grand format,
/// 3×) : rien à précomposer sous la limite d'environ 30 Mo.
struct FondClassement: View {
    var body: some View {
        ZStack {
            Color.fondPrincipal
            Damier(opacite: 1, encre: .damierWidget)
        }
    }
}

/// Le cadre de la piste, remonté à la racine du widget, et les **bords sans texte** — ceux
/// où le surcroît de damier peut filer jusqu'au bord du widget.
struct ZoneDamierPiste: PreferenceKey {
    struct Zone {
        let cadre: Anchor<CGRect>
        let bords: Edge.Set
    }

    static let defaultValue: Zone? = nil

    static func reduce(value: inout Zone?, nextValue: () -> Zone?) {
        value = value ?? nextValue()
    }
}

private extension View {
    func zoneDamierPiste(bords: Edge.Set) -> some View {
        anchorPreference(key: ZoneDamierPiste.self, value: .bounds) {
            ZoneDamierPiste.Zone(cadre: $0, bords: bords)
        }
    }
}

/// Le surcroît de damier sous la piste (``Color/damierWidgetPiste``) : **le même motif**
/// que le fond, au même cadre — le widget entier —, découvert par un masque adouci. Pas de
/// couture : le motif ne fait que s'appuyer.
///
/// > **Côté texte, le fondu reste dans le cadre de la piste** (rentré de deux fois le
/// > flou) : les points de la colonne voisine, le titre, « Mis à jour à » restent sur le
/// > fond seul, où leur contraste est mesuré. Les autres bords filent au bord du widget.
private struct DamierPiste: View {
    let cadre: CGRect
    let bords: Edge.Set
    let widget: CGSize

    private static let flou: CGFloat = 4

    var body: some View {
        let rentre = Self.flou * 2
        let gauche = bords.contains(.leading) ? -rentre : cadre.minX + rentre
        let droite = bords.contains(.trailing) ? widget.width + rentre : cadre.maxX - rentre
        let haut = bords.contains(.top) ? -rentre : cadre.minY + rentre
        let bas = bords.contains(.bottom) ? widget.height + rentre : cadre.maxY - rentre

        Damier(opacite: 1, encre: .damierWidgetPiste)
            .mask {
                Rectangle()
                    .frame(width: max(0, droite - gauche), height: max(0, bas - haut))
                    .position(x: (gauche + droite) / 2, y: (haut + bas) / 2)
                    .blur(radius: Self.flou)
            }
    }
}

// MARK: - La piste simplifiée

/// Les voitures à leur place, **sans kerbs, scores, ligne médiane ni panneau** : posées
/// directement sur le fond du widget, le même beige que le classement.
///
/// **La disposition est celle de l'app, réduite d'un bloc.** ``DispositionPiste`` travaille
/// sur la piste de l'app elle-même (``DispositionPiste/pisteApp``), avec les mêmes
/// paramètres — même taille de voiture, mêmes voies, mêmes écarts verticaux —, puis le
/// résultat entier est réduit **uniformément** à la place du widget, centré, au rapport de
/// la piste. Rien n'est recalculé à la taille du widget : un écart entre deux voitures y
/// vaut la même fraction de piste que dans l'app.
///
/// > Jusqu'en `ios 0.55.1`, le calcul tournait sur une piste virtuelle de 360 pt de large
/// > (de haut au moyen format) : une autre piste que celle de l'app, donc d'autres voies et
/// > d'autres écarts pour le même classement.
struct PisteSimplifiee: View {

    let membres: [Membre]
    let avatars: [UUID: UIImage]

    var body: some View {
        let piste = DispositionPiste.pisteApp
        let disposition = DispositionPiste.disposition(membres, hauteur: piste.height,
                                                       largeur: piste.width)

        GeometryReader { bloc in
            let echelle = max(0.01, min(bloc.size.width / piste.width,
                                        bloc.size.height / piste.height))
            let largeurVoiture = disposition.gabarit.largeur * echelle
            let hauteurVoiture = disposition.gabarit.hauteur * echelle

            ZStack(alignment: .topLeading) {
                Color.clear

                ForEach(disposition.placements) { placement in
                    VueVoiture(livree: placement.membre.livree,
                               numero: placement.membre.numeroAffiche,
                               nom: placement.membre.pseudo,
                               imagePhoto: avatars[placement.membre.profilId],
                               teintePilote: .teinteAvatar(pour: placement.membre.cleTeinte))
                        .frame(width: largeurVoiture, height: hauteurVoiture)
                        .offset(x: (piste.width / 2 + placement.decalage) * echelle - largeurVoiture / 2,
                                y: placement.centre * echelle - hauteurVoiture / 2)
                }
            }
            // La piste réduite, au rapport de celle de l'app, centrée dans le bloc.
            .frame(width: piste.width * echelle, height: piste.height * echelle)
            .frame(width: bloc.size.width, height: bloc.size.height)
        }
        .accessibilityHidden(true)
    }
}
