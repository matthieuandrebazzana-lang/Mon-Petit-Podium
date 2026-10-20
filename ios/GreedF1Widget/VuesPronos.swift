import SwiftUI
import WidgetKit

/// Le widget « Mes pronos » — petit et moyen formats.
///
/// - **Petit** : l'état (« À faire » rouge, « Pronos faits » vert), le nom du GP et le
///   décompte qui défile seul ; après la course, les points marqués.
/// - **Moyen** : le même en-tête, puis la grille — obligatoires à gauche, bonus à droite,
///   les points en jeu ou gagnés au bout de chaque ligne.
///
/// **Sur le drapeau, comme « Prochain GP »** : mêmes calques (``FondPronos``), mêmes encres
/// fixes et même ombre portée, calculées par ``ApparenceDrapeau``. Aucune date de relevé.
struct VuePronos: View {

    let entree: EntreePronos

    @Environment(\.widgetFamily) private var format

    init(entree: EntreePronos) {
        self.entree = entree
        // La langue de l'app, posée avant que le premier `t()` ne soit lu.
        if let langue = entree.langue { LanguageManager.shared.imposer(langue) }
    }

    var body: some View {
        Group {
            if let gp = entree.grandPrix, let phase = entree.phase, let echeance = entree.echeance {
                let apparence = ApparenceDrapeau.pour(slug: gp.slug)
                if format == .systemSmall {
                    PetitPronos(entree: entree, gp: gp, phase: phase, echeance: echeance, apparence: apparence)
                } else {
                    MoyenPronos(entree: entree, gp: gp, phase: phase, echeance: echeance, apparence: apparence)
                }
            } else {
                VidePronos(compact: format == .systemSmall, echec: entree.echec)
            }
        }
        .environment(\.locale, localeInterface)
        .widgetURL(entree.url)
    }
}

// MARK: - Le fond

/// Les calques de « Prochain GP », dans le même ordre : drapeau · ``LueurHaute`` · voile
/// calculé · assombrissement de 15 %. **Sans tracé en filigrane** : la grille occupe le
/// moyen format, un dessin derrière elle la brouillerait. Sans données, le fond de l'app.
struct FondPronos: View {

    let grandPrix: DonneesWidget.GrandPrixPronosWidget?

    var body: some View {
        if let grandPrix {
            ZStack {
                if let apparence = ApparenceDrapeau.pour(slug: grandPrix.slug) {
                    Image("flag-\(grandPrix.slug)")
                        .resizable()
                        .scaledToFill()
                    LueurHaute()
                    Color.voile.opacity(apparence.voile)
                    Color.voile.opacity(0.15)
                } else {
                    Color.primaire
                    LueurHaute()
                }
            }
        } else {
            Color.fondPrincipal
        }
    }
}

// MARK: - L'état

/// La pastille d'état — **sa couleur est son sens**, et elle est pleine : posée sur un
/// drapeau qui ne change pas, elle garde ses encres fixes.
///
/// | État | Aplat | Encre | Contraste |
/// |---|---|---|---|
/// | À faire | `primaireFixe` | `encreSurAplat` | 10,88:1 |
/// | Pronos faits | `vertSauge` | `encreSurAplat` | 4,86:1 |
/// | Résultats | `accent` | `encreSurClair` | 7,86:1 |
/// | Fermés | matériau du drapeau | `encreSurAplat` | celui de « Prochain GP » |
struct PastillePronos: View {

    let phase: PhasePronos
    let aDesPronostics: Bool
    let apparence: ApparenceDrapeau?
    var long = false

    private var texte: String {
        switch phase {
        case .resultats: return long ? t("widgetPronos.resultatsDisponibles") : t("widgetPronos.etat.resultats")
        case .fermes where !aDesPronostics: return t("widgetPronos.etat.fermes")
        default: return aDesPronostics ? t("widgetPronos.etat.faits") : t("widgetPronos.etat.aFaire")
        }
    }

    private var aplat: Color {
        switch phase {
        case .resultats: return .accent
        case .fermes where !aDesPronostics: return apparence?.pastille ?? Color.encreSurAplat.opacity(0.20)
        default: return aDesPronostics ? .vertSauge : .primaireFixe
        }
    }

    private var encre: Color { phase == .resultats ? .encreSurClair : .encreSurAplat }

    var body: some View {
        Text(texte)
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundStyle(encre)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(aplat)
            .clipShape(Capsule())
    }
}

// MARK: - Petit

struct PetitPronos: View {

    let entree: EntreePronos
    let gp: DonneesWidget.GrandPrixPronosWidget
    let phase: PhasePronos
    let echeance: EcheancePronostics
    let apparence: ApparenceDrapeau?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PastillePronos(phase: phase, aDesPronostics: gp.aDesPronostics, apparence: apparence)

            Spacer(minLength: 6)

            Text(gp.nomAffiche)
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .tracking(-0.40)
                .foregroundStyle(Color.encreSurAplat)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .ombrePortee(apparence?.ombreNom ?? false)

            Spacer(minLength: 6)

            Text(phase == .resultats ? t("widgetPronos.mesPoints") : echeance.label)
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(apparence?.encreDouce ?? .encreSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .ombrePortee(apparence?.ombreNom ?? false)

            Spacer().frame(height: 3)

            Group {
                if phase == .resultats {
                    Text(totalResultats(gp))
                } else {
                    DecompteProchainGP(echeance: echeance, depuis: entree.date)
                }
            }
            .font(.custom("HelveticaNeue-Medium", size: 17))
            .foregroundStyle(Color.encreSurAplat)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .ombrePortee(apparence?.ombreNom ?? false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible(gp, phase, echeance))
    }
}

// MARK: - Moyen

struct MoyenPronos: View {

    let entree: EntreePronos
    let gp: DonneesWidget.GrandPrixPronosWidget
    let phase: PhasePronos
    let echeance: EcheancePronostics
    let apparence: ApparenceDrapeau?

    private var obligatoires: [DonneesWidget.PronosticWidget] { gp.pronostics.filter { !$0.estBonus } }
    private var bonus: [DonneesWidget.PronosticWidget] { gp.pronostics.filter(\.estBonus) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Spacer(minLength: 8)
            if gp.pronostics.isEmpty {
                Text(messageSansPronos)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundStyle(Color.encreSurAplat)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .ombrePortee(apparence?.ombreNom ?? false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    colonne(t("pronos.obligatoires"), obligatoires)
                    colonne(t("recap.bonus"), bonus)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible(gp, phase, echeance))
    }

    private var messageSansPronos: String {
        switch phase {
        case .avantOuverture, .ouverts: return t("widgetPronos.aucunPronos")
        case .fermes, .resultats: return t("widgetPronos.aucunPronosFerme")
        }
    }

    /// L'état et l'échéance (ou les points) sur la première rangée, le nom dessous.
    private var entete: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                PastillePronos(phase: phase, aDesPronostics: gp.aDesPronostics,
                               apparence: apparence, long: true)
                Spacer(minLength: 4)
                Text(phase == .resultats ? t("widgetPronos.mesPoints") : echeance.label)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(apparence?.encreDouce ?? .encreSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .ombrePortee(apparence?.ombreNom ?? false)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(gp.nomAffiche)
                    .font(.custom("HelveticaNeue-Medium", size: 20))
                    .tracking(-0.40)
                    .foregroundStyle(Color.encreSurAplat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .ombrePortee(apparence?.ombreNom ?? false)
                Spacer(minLength: 4)
                Group {
                    if phase == .resultats {
                        Text(totalResultats(gp))
                    } else {
                        DecompteProchainGP(echeance: echeance, depuis: entree.date)
                    }
                }
                .font(.custom("HelveticaNeue-Medium", size: 17))
                .foregroundStyle(Color.encreSurAplat)
                .lineLimit(1)
                .fixedSize()
                .ombrePortee(apparence?.ombreNom ?? false)
            }
        }
    }

    private func colonne(_ titre: String, _ lignes: [DonneesWidget.PronosticWidget]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titre)
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(apparence?.encreDouce ?? .encreSecondaire)
                .lineLimit(1)
                .ombrePortee(apparence?.ombreNom ?? false)
            if lignes.isEmpty {
                Text("—")
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundStyle(apparence?.encreDouce ?? .encreSecondaire)
            }
            ForEach(Array(lignes.prefix(3).enumerated()), id: \.offset) { _, ligne in
                LignePronos(ligne: ligne, resultats: phase == .resultats, apparence: apparence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Une ligne de la grille : le choix, puis les points en jeu — ou, après la course, ce
/// qu'il a rapporté. **Un pronostic non jugé n'affiche jamais `0`** : « En attente ».
/// Le verdict passe par la graisse et l'encre douce, jamais par une couleur posée sur un
/// drapeau qu'on ne connaît pas.
struct LignePronos: View {

    let ligne: DonneesWidget.PronosticWidget
    let resultats: Bool
    let apparence: ApparenceDrapeau?

    private var perdu: Bool { resultats && ligne.statut == "perdu" }

    private var valeur: String {
        guard resultats else { return formaterPoints(ligne.points) }
        if let gagnes = ligne.pointsGagnes { return t("points.valeur", gagnes.enPoints) }
        return ligne.statut == "non_evaluable" ? t("parGP.nonEvaluable") : t("historique.statut.enAttente")
    }

    var body: some View {
        HStack(spacing: 6) {
            if resultats {
                Image(systemName: icone)
                    .font(.system(size: 10, weight: .medium))
                    // Une largeur commune : les noms s'alignent quel que soit le verdict.
                    .frame(width: 11)
                    .accessibilityHidden(true)
            }
            Text(nomCourt(ligne.choix ?? ligne.libelle ?? "—"))
                .font(.custom("HelveticaNeue-Medium", size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(valeur)
                .font(.custom(perdu ? "HelveticaNeue" : "HelveticaNeue-Medium", size: 12))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(perdu ? (apparence?.encreDouce ?? .encreSecondaire) : Color.encreSurAplat)
        .ombrePortee(apparence?.ombreNom ?? false)
    }

    private var icone: String {
        switch ligne.statut {
        case "gagne": return "checkmark"
        case "perdu": return "xmark"
        default: return "clock"
        }
    }

    /// « L. Norris » → « Norris » : le nom de famille suffit et tient dans la colonne. **Seule
    /// une initiale suivie d'un point est retirée** : une écurie (« Red Bull », « Aston
    /// Martin ») ou une issue (« Entre 5 et 10 secondes ») reste entière. Le format de la
    /// base, « L.Norris », n'a pas d'espace et passe tel quel.
    private func nomCourt(_ texte: String) -> String {
        let mots = texte.split(separator: " ")
        guard mots.count >= 2, let initiale = mots.first, initiale.count <= 2,
              initiale.hasSuffix("."), initiale.first?.isLetter ?? false
        else { return texte }
        return mots.dropFirst().joined(separator: " ")
    }
}

// MARK: - État vide

/// Aucune donnée : le logo et une invitation, sur le fond de l'app (clair et sombre par
/// jetons). Jamais une grille inventée. Après un échec de lecture sans rien de rangé :
/// « Impossible de charger tes pronos », en encre `texte` (≥ 14:1 sur `fondPrincipal`).
struct VidePronos: View {
    let compact: Bool
    var echec = false

    var body: some View {
        VStack(spacing: compact ? 10 : 12) {
            Image("logo-05")
                .resizable()
                .scaledToFit()
                .frame(height: compact ? 56 : 64)
                .accessibilityHidden(true)
            Text(t(echec ? "widgetPronos.erreur" : "widgetPronos.vide"))
                .font(.custom(echec ? "HelveticaNeue-Medium" : "HelveticaNeue", size: compact ? 12 : 13))
                .foregroundStyle(echec ? Color.texte : Color.grisSecondaire)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Partagé

/// « 78 pts », ou « En attente » tant qu'aucun pronostic n'est jugé — jamais un `0` inventé.
private func totalResultats(_ gp: DonneesWidget.GrandPrixPronosWidget) -> String {
    guard gp.aDesPronostics else { return "—" }
    return gp.pointsGagnes.map { t("points.valeur", $0.enPoints) } ?? t("historique.statut.enAttente")
}

/// Ce que VoiceOver lit : l'état, le GP, l'échéance (ou les points), puis la grille.
private func libelleAccessible(_ gp: DonneesWidget.GrandPrixPronosWidget, _ phase: PhasePronos,
                               _ echeance: EcheancePronostics) -> String {
    let etat: String = switch phase {
    case .resultats: t("widgetPronos.resultatsDisponibles")
    case .fermes where !gp.aDesPronostics: t("widgetPronos.etat.fermes")
    default: gp.aDesPronostics ? t("widgetPronos.etat.faits") : t("widgetPronos.etat.aFaire")
    }
    let suite = phase == .resultats ? "\(t("widgetPronos.mesPoints")) \(totalResultats(gp))" : echeance.phrase
    let grille = gp.pronostics.map { ligne in
        "\(ligne.choix ?? ligne.libelle ?? ""), \(phase == .resultats ? (ligne.pointsGagnes.map { t("points.valeur", $0.enPoints) } ?? t("historique.statut.enAttente")) : formaterPoints(ligne.points))"
    }.joined(separator: ". ")
    return t("widgetPronos.a11y", etat, gp.nomAffiche, suite) + (grille.isEmpty ? "" : " \(grille).")
}
