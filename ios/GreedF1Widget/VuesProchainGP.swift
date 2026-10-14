import SwiftUI
import WidgetKit

/// Le widget « Prochain GP » dans ses trois formats — la transposition du widget de
/// l'accueil (`WidgetGrandPrix`, `AccueilView.swift`), **avec ses jetons, ses assets et son
/// calcul de voile**, jamais une copie de leurs valeurs.
///
/// - **Moyen** : le design complet — drapeau voilé, tracé en filigrane, pastille et date,
///   nom, cases « Départ » et échéance.
/// - **Petit** : drapeau, nom, échéance.
/// - **Écran verrouillé** : nom et échéance, monochromes — iOS teinte lui-même.
struct VueProchainGP: View {

    let entree: EntreeProchainGP

    @Environment(\.widgetFamily) private var format

    init(entree: EntreeProchainGP) {
        self.entree = entree
        // La langue de l'app, pas celle du téléphone (``DonneesWidget``) : posée avant que
        // le premier `t()` ne soit lu.
        if let langue = entree.langue { LanguageManager.shared.imposer(langue) }
    }

    var body: some View {
        Group {
            switch format {
            case .accessoryRectangular: VerrouProchainGP(entree: entree)
            case .systemSmall: PetitProchainGP(entree: entree)
            default: MoyenProchainGP(entree: entree)
            }
        }
        .environment(\.locale, localeInterface)
        .widgetURL(DonneesWidget.urlAccueil)
    }
}

// MARK: - Le fond

/// Les calques du widget de l'accueil, **dans le même ordre** : drapeau · ``LueurHaute`` ·
/// voile calculé (``ApparenceDrapeau``) · assombrissement uniforme de 15 %. Hors table :
/// l'aplat `primaire` et sa lueur. Le tracé en filigrane n'habille que le format moyen ;
/// l'écran verrouillé n'a pas de fond, iOS pose le sien.
struct FondProchainGP: View {

    let grandPrix: DonneesWidget.GrandPrix?

    @Environment(\.widgetFamily) private var format

    private var apparence: ApparenceDrapeau? { grandPrix.flatMap { ApparenceDrapeau.pour(slug: $0.slug) } }

    var body: some View {
        if format == .accessoryRectangular {
            Color.clear
        } else if let grandPrix {
            ZStack {
                if let apparence {
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

                if format == .systemMedium {
                    // Un filigrane, pas l'illustration de l'accueil : il passe derrière tout
                    // le contenu et ne porte aucun sens — le nom dit déjà le circuit.
                    Image("trace-\(grandPrix.slug)")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.encreSurAplat.opacity(0.22))
                        .padding(.vertical, 18)
                        .padding(.horizontal, 40)
                }
            }
        } else {
            // L'état neutre : le fond de l'app, qui suit clair et sombre.
            Color.fondPrincipal
        }
    }
}

// MARK: - Le décompte

/// L'échéance **qui défile seule** — `Text(timerInterval:)`, sans rechargement du widget.
/// Les jours restants sont écrits par l'entrée (« 2j »), la minuterie ne compte que ce qui
/// reste sous 24 h : voir ``TimelineProchainGP``. Sans échéance, le mot de l'app (« À
/// confirmer », « Fermés »).
struct DecompteProchainGP: View {

    let echeance: EcheancePronostics
    let depuis: Date

    var body: some View {
        if echeance.texte != nil, let restant = echeance.restant, restant > 0 {
            // `restant - 1` : une entrée posée pile sur un jour entier affiche « 1j 24:00:00 »
            // plutôt que « 2j 0:00:00 », qui resterait figé jusqu'à l'entrée suivante.
            let jours = max(0, Int(((restant - 1) / 86_400).rounded(.down)))
            let reste = restant - Double(jours) * 86_400
            HStack(spacing: 0) {
                if jours > 0 { Text(t("widget.jours", jours) + " ") }
                Text(timerInterval: depuis...depuis.addingTimeInterval(reste), countsDown: true)
            }
            .monospacedDigit()
        } else {
            Text(echeance.texte ?? echeance.substitut)
        }
    }
}

// MARK: - Moyen

struct MoyenProchainGP: View {

    let entree: EntreeProchainGP

    var body: some View {
        if let gp = entree.grandPrix, let echeance = entree.echeance {
            let apparence = ApparenceDrapeau.pour(slug: gp.slug)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    PastilleProchainGP(apparence: apparence)
                    Spacer(minLength: 8)
                    Text(dateCourse(gp))
                        .font(.custom(apparence?.encreDouceGrasse ?? false ? "HelveticaNeue-Medium" : "HelveticaNeue",
                                      size: 11))
                        .foregroundStyle(apparence?.encreDouce ?? .encreSecondaire)
                        .ombrePortee(apparence?.ombreNom ?? false)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 6)

                // 24 pt : le 26 de l'accueil ne tient pas dans 170 pt de haut avec les
                // cases ; même crénage négatif (−0,02em), même ombre.
                Text(gp.nomAffiche)
                    .font(.custom("HelveticaNeue-Medium", size: 24))
                    .tracking(-0.48)
                    .foregroundStyle(Color.encreSurAplat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .ombrePortee(apparence?.ombreNom ?? false)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 6)

                HStack(spacing: 8) {
                    CaseProchainGP(label: t("echeance.depart"), apparence: apparence) {
                        Text(gp.dateCourse.map(heureInterface) ?? t("echeance.aConfirmer"))
                    }
                    CaseProchainGP(label: echeance.label, apparence: apparence) {
                        DecompteProchainGP(echeance: echeance, depuis: entree.date)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(libelleAccessible(gp, echeance))
        } else {
            NeutreProchainGP(compact: false)
        }
    }
}

/// « Prochain GP », dans la pastille de l'accueil — même matériau calculé.
struct PastilleProchainGP: View {
    let apparence: ApparenceDrapeau?

    var body: some View {
        Text(t("accueil.prochainGP"))
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundStyle(Color.encreSurAplat)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(apparence?.pastille ?? Color.encreSurAplat.opacity(0.20))
            .clipShape(Capsule())
    }
}

/// Une case de statut de l'accueil (`caseStatut`) : label au-dessus, valeur dessous, rayon
/// `champ` et aucune ombre (§4.7).
struct CaseProchainGP<Valeur: View>: View {
    let label: String
    let apparence: ApparenceDrapeau?
    @ViewBuilder let valeur: Valeur

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(apparence?.encreDouce ?? .encreSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            valeur
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundStyle(Color.encreSurAplat)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(apparence?.surface ?? Color.encreSurAplat.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }
}

// MARK: - Petit

struct PetitProchainGP: View {

    let entree: EntreeProchainGP

    var body: some View {
        if let gp = entree.grandPrix, let echeance = entree.echeance {
            let apparence = ApparenceDrapeau.pour(slug: gp.slug)
            VStack(alignment: .leading, spacing: 0) {
                Text(gp.nomAffiche)
                    .font(.custom("HelveticaNeue-Medium", size: 20))
                    .tracking(-0.40)
                    .foregroundStyle(Color.encreSurAplat)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .ombrePortee(apparence?.ombreNom ?? false)

                Spacer(minLength: 8)

                Text(echeance.label)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(apparence?.encreDouce ?? .encreSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .ombrePortee(apparence?.ombreNom ?? false)

                Spacer().frame(height: 4)

                DecompteProchainGP(echeance: echeance, depuis: entree.date)
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundStyle(Color.encreSurAplat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .ombrePortee(apparence?.ombreNom ?? false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(libelleAccessible(gp, echeance))
        } else {
            NeutreProchainGP(compact: true)
        }
    }
}

// MARK: - Écran verrouillé

/// Monochrome : aucune couleur ni aucun drapeau, iOS teinte le texte lui-même. La
/// hiérarchie passe par la graisse, jamais par une encre.
struct VerrouProchainGP: View {

    let entree: EntreeProchainGP

    var body: some View {
        if let gp = entree.grandPrix, let echeance = entree.echeance {
            VStack(alignment: .leading, spacing: 1) {
                Text(gp.nomAffiche)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .widgetAccentable()
                    .lineLimit(1)
                Text(echeance.label)
                    .font(.custom("HelveticaNeue", size: 13))
                    .lineLimit(1)
                DecompteProchainGP(echeance: echeance, depuis: entree.date)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(libelleAccessible(gp, echeance))
        } else {
            Text(t("widget.vide"))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - État neutre

/// Aucune donnée : le logo et une invitation, sur le fond de l'app (clair et sombre par
/// jetons). Jamais un Grand Prix inventé.
struct NeutreProchainGP: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 10 : 12) {
            Image("logo-05")
                .resizable()
                .scaledToFit()
                .frame(height: compact ? 56 : 64)
                .accessibilityHidden(true)
            Text(t("widget.vide"))
                .font(.custom("HelveticaNeue", size: compact ? 12 : 13))
                .foregroundStyle(Color.grisSecondaire)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Partagé

/// « 25 oct. 2026 » — la date abrégée de l'en-tête de l'accueil, dans la langue de l'app.
private func dateCourse(_ gp: DonneesWidget.GrandPrix) -> String {
    gp.dateCourse?.formatted(.dateTime.day().month(.abbreviated).year().locale(localeInterface))
        ?? t("echeance.aConfirmer")
}

/// Ce que VoiceOver lit : le nom et la phrase d'échéance de l'app, qui ne défile pas.
private func libelleAccessible(_ gp: DonneesWidget.GrandPrix, _ echeance: EcheancePronostics) -> String {
    t("widget.a11y", gp.nomAffiche, dateCourse(gp), echeance.phrase)
}
