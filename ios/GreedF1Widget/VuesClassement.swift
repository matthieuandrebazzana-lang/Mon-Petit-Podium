import SwiftUI
import WidgetKit

/// Le widget « Classement » dans ses trois formats.
///
/// - **Petit** et **moyen** : le classement (les trois premiers, et l'utilisateur s'il n'y
///   est pas) **ou** la piste, selon la configuration (``IntentionClassement``).
/// - **Grand** : le classement à gauche, jusqu'à huit lignes, et la piste à droite — ou la
///   piste seule, sur toute la largeur.
///
/// **La piste est celle de l'app, simplifiée** : les voitures à leur place par
/// ``DispositionPiste`` — le même calcul, jamais un second —, les mêmes livrées
/// (``VueVoiture``, planches SVG), sans kerbs ni scores.
struct VueClassement: View {

    let entree: EntreeClassement

    @Environment(\.widgetFamily) private var format

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
                case (.systemMedium, .piste, _):
                    PisteTitree(entree: entree, championnat: championnat, membres: releve.membres,
                                tailleTitre: 14, miseAJourEnTete: true,
                                hauteurVirtuelle: PisteSimplifiee.hauteurVirtuelleMoyen)
                case (.systemMedium, _, _):
                    MoyenClassement(entree: entree, championnat: championnat, membres: releve.membres)
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
                .padding(.bottom, 6)

            if membres.isEmpty {
                AucunMembre()
            } else {
                VStack(spacing: 2) {
                    ForEach(VueClassement.lignes(membres, tete: 3, moi: entree.profilId, enPlus: true)) { membre in
                        LigneWidget(membre: membre, moi: membre.profilId == entree.profilId,
                                    avatar: entree.avatars[membre.profilId], compacte: true)
                    }
                }
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
    var hauteurVirtuelle: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NomChampionnat(nom: championnat.nom, taille: tailleTitre)
                if miseAJourEnTete {
                    Spacer(minLength: 0)
                    MiseAJour(entree: entree)
                }
            }
            PisteSimplifiee(membres: membres, avatars: entree.avatars, hauteurVirtuelle: hauteurVirtuelle)
            if !miseAJourEnTete { MiseAJour(entree: entree) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VueClassement.resume(championnat, membres))
    }
}

// MARK: - Moyen format

/// Le petit classement, en ligne pleine largeur : les trois premiers, et l'utilisateur en
/// plus s'il n'y est pas. Quatre lignes dans 120 pt — elles se resserrent un peu sur les
/// plus petits iPhone plutôt que de déborder.
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
            .padding(.bottom, 6)

            if membres.isEmpty {
                AucunMembre()
            } else {
                VStack(spacing: 2) {
                    ForEach(VueClassement.lignes(membres, tete: 3, moi: entree.profilId, enPlus: true)) { membre in
                        LigneWidget(membre: membre, moi: membre.profilId == entree.profilId,
                                    avatar: entree.avatars[membre.profilId], compacte: true,
                                    souple: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .padding(.bottom, 8)

                if membres.isEmpty {
                    AucunMembre()
                } else {
                    VStack(spacing: 4) {
                        ForEach(VueClassement.lignes(membres, tete: 8, moi: entree.profilId, enPlus: false)) { membre in
                            LigneWidget(membre: membre, moi: membre.profilId == entree.profilId,
                                        avatar: entree.avatars[membre.profilId], compacte: false)
                        }
                    }
                }
                Spacer(minLength: 0)
                MiseAJour(entree: entree)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PisteSimplifiee(membres: membres, avatars: entree.avatars)
                .frame(width: 112)
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

/// Une ligne : rang, avatar, pseudo, points. **La ligne de l'utilisateur est posée sur la
/// surface** — c'est elle que l'œil cherche, et la distinguer par un mot de plus la ferait
/// déborder. Le rang reprend la règle du classement de l'app : rouge sur le podium, gris
/// au-delà.
private struct LigneWidget: View {

    let membre: Membre
    let moi: Bool
    let avatar: UIImage?
    let compacte: Bool
    /// Vrai : la ligne cède jusqu'à 20 pt quand la hauteur manque (le moyen format).
    var souple = false

    private var corps: CGFloat { compacte ? 12 : 14 }

    var body: some View {
        HStack(spacing: compacte ? 6 : 8) {
            Text(String(membre.rang))
                .font(.custom("HelveticaNeue-Medium", size: corps))
                .foregroundColor(membre.rang <= 3 ? .encrePrimaire : .grisSecondaire)
                .monospacedDigit()
                .frame(width: compacte ? 14 : 18, alignment: .leading)

            PastilleWidget(pseudo: membre.pseudo, image: avatar,
                           teinte: .teinteAvatar(pour: membre.cleTeinte),
                           taille: compacte ? 20 : 26)

            Text(membre.pseudo)
                .font(.custom(moi ? "HelveticaNeue-Medium" : "HelveticaNeue", size: corps))
                .foregroundColor(.texte)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(membre.totalPoints))
                .font(.custom("HelveticaNeue-Medium", size: corps))
                .foregroundColor(.encrePrimaire)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 4)
        .frame(minHeight: souple ? 20 : nil, maxHeight: souple ? 24 : nil)
        .frame(height: souple ? nil : (compacte ? 24 : 30))
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

// MARK: - La piste simplifiée

/// Les voitures à leur place, **sans kerbs, scores, ligne médiane ni panneau** : posées
/// directement sur le fond du widget, le même beige que le classement.
///
/// **Le placement est celui de l'app, à l'échelle près.** ``DispositionPiste`` cherche une
/// voiture de 40 à 64 pt sur une piste de la taille d'un écran : il travaille donc ici sur
/// une piste **virtuelle** aux proportions du bloc, et le résultat est réduit d'autant.
/// Mêmes voies, mêmes ex æquo, même ordre — seule l'échelle change.
///
/// La piste virtuelle fait 360 pt de large — la zone de jeu de l'app sur un iPhone —, **sauf
/// au moyen format**, où elle ferait 125 pt de haut : moins qu'une voiture et sa marge,
/// toutes se poseraient au même niveau. Là, c'est la **hauteur** qui est fixée
/// (``hauteurVirtuelleMoyen``) et la largeur qui suit.
struct PisteSimplifiee: View {

    let membres: [Membre]
    let avatars: [UUID: UIImage]

    /// La largeur de la piste virtuelle — celle de la zone de jeu de l'app sur un iPhone.
    static let largeurVirtuelle: CGFloat = 360

    /// `nil` : la piste virtuelle fait ``largeurVirtuelle`` de large. Sinon, elle fait
    /// cette hauteur-là.
    var hauteurVirtuelle: CGFloat? = nil

    /// **Mesuré au harnais**, sur 9 membres de 168 à 12 points dans 332 × 116 pt : à 240 pt
    /// de piste virtuelle, des voitures de 31 pt mais 27 pt d'écart vertical du premier au
    /// dernier pour 63 pt de voiture — un seul éventail, la hauteur ne dit plus rien. À
    /// 360 pt, des voitures de 21 pt (le grand format en a 20, le petit 18) et 57 pt
    /// d'écart : deux niveaux lisibles. Au-delà, les voitures passent sous celles du petit.
    static let hauteurVirtuelleMoyen: CGFloat = 360

    var body: some View {
        GeometryReader { bloc in
            let zone = CGSize(width: max(1, bloc.size.width), height: max(1, bloc.size.height))
            let echelle = hauteurVirtuelle.map { zone.height / $0 }
                ?? zone.width / Self.largeurVirtuelle
            let disposition = DispositionPiste.disposition(
                membres, hauteur: zone.height / echelle, largeur: zone.width / echelle)
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
                        .offset(x: zone.width / 2 + placement.decalage * echelle - largeurVoiture / 2,
                                y: placement.centre * echelle - hauteurVoiture / 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
