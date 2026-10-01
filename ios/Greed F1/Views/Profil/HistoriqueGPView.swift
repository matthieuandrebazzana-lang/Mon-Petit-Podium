import SwiftUI

/// **Ses Grands Prix** — ce qu'un membre a joué sur la saison, Grand Prix par Grand Prix.
///
/// Ouvert depuis ``ProfilMembreView`` et depuis ``ProfilView``, par la même ligne
/// (``LigneGrandsPrix``). Pas de maquette : chaque carte reprend l'empilement du widget
/// GP de l'accueil (drapeau · tracé · voile · contenu), le détail reprend ``PastillePoints``
/// et ``Verdict``.
///
/// > *Écart signalé (`CLAUDE.md` §3.2).* Le type porte « historique », terme proscrit du
/// > vocabulaire. **Rien de ce qui s'affiche ne le dit** : l'écran s'intitule
/// > « Ses Grands Prix ».
///
/// **Données** : ``GrandsPrixJoues`` — les routes de ``ResultatsParGPView``, relues pour
/// chaque GP terminé et filtrées sur le membre. Spinner pendant l'appel.
///
/// **Une seule carte ouverte à la fois** : en ouvrir une referme la précédente.
struct HistoriqueGPView: View {

    /// « Ses Grands Prix », ou « Mes Grands Prix » depuis son propre profil. `nil` vaut
    /// « Ses Grands Prix », relu dans la langue de l'interface.
    var titreRecu: String?
    private var titre: String { titreRecu ?? t("profil.sesGrandsPrix") }

    /// Rang au classement du championnat d'où l'on vient ; `nil` depuis son propre profil.
    var rang: Int?

    @StateObject private var donnees: GrandsPrixJoues

    @State private var ouvert: UUID?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private let margeLaterale: CGFloat = 16

    /// - Parameters:
    ///   - profilId: le membre ; `nil` = le compte connecté.
    ///   - championnatId: un championnat partagé ; `nil` = le premier des miens.
    init(titre: String? = nil, profilId: UUID? = nil,
         championnatId: UUID? = nil, rang: Int? = nil) {
        self.titreRecu = titre
        self.rang = rang
        _donnees = StateObject(wrappedValue: GrandsPrixJoues(profilId: profilId,
                                                             championnatId: championnatId))
    }

    /// Du plus ancien au plus récent — l'ordre du calendrier servi.
    private var grandsPrix: [GrandsPrixJoues.GrandPrixJoue] {
        if case .pret(let liste) = donnees.etat { return liste }
        return []
    }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    entete

                    Spacer().frame(height: 20)
                    contenu
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await donnees.charger() }
    }

    @ViewBuilder private var contenu: some View {
        switch donnees.etat {
        case .chargement:
            ProgressView()
                .tint(.secondaire)
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityLabel(t("parGP.a11y.chargementGP"))

        case .echec(let erreur):
            EchecChargement(erreur: erreur) {
                Task { await donnees.charger() }
            }

        case .sansChampionnat:
            messageVide(t("historique.videAucunChampionnat"))

        case .pret(let liste) where liste.isEmpty:
            resumeSaison
            Spacer().frame(height: 24)
            messageVide(t("historique.videAucunGP"))

        case .pret:
            resumeSaison

            Spacer().frame(height: 24)
            VStack(spacing: 12) {
                ForEach(grandsPrix) { gp in
                    CarteGrandPrixJoue(gp: gp, ouvert: ouvert == gp.id) {
                        basculer(gp.id)
                    }
                }
            }
        }
    }

    private func messageVide(_ texte: String) -> some View {
        Text(texte)
            .font(.custom("HelveticaNeue", size: 15))
            .foregroundColor(.secondaire)                 // 9,32:1 sur le beige
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func basculer(_ id: UUID) {
        withAnimation(mouvementReduit ? nil : Mouvement.deplacement(0.22)) {
            ouvert = ouvert == id ? nil : id
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre)
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)                  // 15,37:1 sur le beige
                .accessibilityAddTraits(.isHeader)

            // `grisSecondaire` tient 4,71:1 sur le beige.
            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sousTitre: String {
        guard case .pret = donnees.etat else { return t("commun.saison2026") }
        return tp("historique.gpJoues", joues)
    }

    private var joues: Int { grandsPrix.count }

    /// `nil` tant qu'aucun pronostic n'est jugé.
    private var totalPoints: Int? {
        let juges = grandsPrix.compactMap(\.totalPoints)
        return juges.isEmpty ? nil : juges.reduce(0, +)
    }

    // MARK: - Résumé de la saison

    private var resumeSaison: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("historique.totalSaison"))
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.encreSecondaire)    // blanc 70 % — 5,75:1

                Spacer().frame(height: 6)

                Text(totalPoints.map(\.enPoints) ?? "—")
                    .font(.scoreLg)
                    .tracking(Tracking.scoreLg)
                    .foregroundColor(.white)              // 10,88:1 sur le bordeaux
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer().frame(height: 4)

                Text(tp("historique.pronosReussis", reussis))
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.encreSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let rang {
                VStack(spacing: 2) {
                    Text(ordinal(rang))
                        .font(.custom("HelveticaNeue-Medium", size: 26))
                        .foregroundColor(.white)
                    // **Blanc 70 % et non 50 %** : sur la pastille (blanc 15 % sur le
                    // bordeaux), 50 % ne tient que 3,15:1 — sous le plancher de 4,5:1 d'un
                    // texte de 10 pt. 70 % y tient 4,76:1.
                    Text(t("championnat.classement"))
                        .font(.labelSm)
                        .tracking(Tracking.label)
                        .textCase(.uppercase)
                        .foregroundColor(.encreSecondaire)
                }
                .frame(minWidth: 88)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
            }
        }
        .padding(20)
        .background(Color.primaire)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleResume)
    }

    private var reussis: Int { grandsPrix.map(\.reussis).reduce(0, +) }

    private var libelleResume: String {
        var libelle = t("historique.a11y.total", tp("classement.a11y.points", totalPoints ?? 0),
                        tp("classement.a11y.reussis", reussis))
        if let rang { libelle += t("historique.a11y.rang", ordinal(rang)) }
        return libelle
    }
}

// MARK: - Une carte de Grand Prix

/// Une carte par Grand Prix joué, **sur le modèle du widget de l'accueil** : le même
/// empilement de calques, dans le même ordre — drapeau · tracé · voile · contenu.
///
/// La partie haute a une hauteur fixe : les cartes s'alignent en colonne régulière, et
/// l'ouverture de l'une ne décale jamais le contenu des autres, seulement leur position.
/// La partie basse, blanche, se déplie dessous et partage le rayon de la carte.
private struct CarteGrandPrixJoue: View {

    let gp: GrandsPrixJoues.GrandPrixJoue
    let ouvert: Bool
    let basculer: () -> Void

    private let hauteur: CGFloat = 160
    private let rembourrage: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            Button(action: basculer) { haut }
                .buttonStyle(StyleAppui(.grandeSurface))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(libelleAccessible)
                .accessibilityValue(ouvert ? t("commun.deplie") : t("commun.replie"))
                .accessibilityAddTraits(.isButton)

            if ouvert {
                detail
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
    }

    // MARK: La partie haute

    private var haut: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(gp.fiche?.nom ?? gp.nom)
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .ombreTexteDrapeau()
                        Text(gp.fiche?.dateAffichee ?? "")
                            .font(.custom("HelveticaNeue", size: 13))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .ombreTexteDrapeau()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    badgeStatut
                }

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(tp("historique.reussisSur", gp.pronostics.count, gp.reussis))
                        .font(.custom("HelveticaNeue-Medium", size: 14))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .ombreTexteDrapeau()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(gp.totalPoints.map(\.enPoints) ?? "—")
                            .font(.custom("HelveticaNeue-Medium", size: 34))
                            .tracking(-0.85)              // grand chiffre : −0,025em × 34
                            .foregroundColor(.white)
                        Text(t("points.unite"))
                            .font(.custom("HelveticaNeue", size: 14))
                            .foregroundColor(.white)
                    }
                    .fixedSize()
                    .ombreTexteDrapeau()
                }
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(ouvert ? 180 : 0))
                .frame(width: 16)
                .accessibilityHidden(true)
        }
        .padding(rembourrage)
        .frame(maxWidth: .infinity)
        .frame(height: hauteur)
        .background { fond }
        .clipped()
        // Le drapeau en `scaledToFill` déborde : la cible est la surface visible, rien d'autre.
        .contentShape(Rectangle())
    }

    /// Tous les Grands Prix de l'écran sont terminés — il ne liste que ceux qui ont été
    /// joués et jugés. **« Provisoire » prend la place de « Terminé »** jusqu'au calcul
    /// définitif (24 h après la course) : même pastille, même encre sur le drapeau voilé,
    /// seul le mot change.
    private var badgeStatut: some View {
        Text(gp.provisoire ? StatutResultats.mention : EtatGp.termine.libelle)
            .font(.custom("HelveticaNeue", size: 11))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
            .fixedSize()
    }

    /// **L'ordre des calques est celui du widget de l'accueil, et il ne se défait pas.**
    ///
    /// 1. Le drapeau, en `scaledToFill` — il couvre toute la carte, rogné sur son plus
    ///    grand côté, jamais déformé (`object-fit: cover`).
    /// 2. Le tracé, centré, blanc à 30 % : un filigrane — le nom dit déjà de quel circuit
    ///    il s'agit.
    /// 3. Le voile noir à 25 %, sur toute la surface — jamais sur une bande seule, sinon
    ///    un drapeau à bandes se lirait coupé en deux.
    ///
    /// **Des `overlay` et non un `ZStack`** : un `ZStack` prend la taille de son plus grand
    /// enfant — le drapeau débordant — et le tracé s'ajustait alors à cette boîte trop
    /// grande. Chaque `overlay` reçoit, lui, la taille exacte de la carte.
    @ViewBuilder private var fond: some View {
        if gp.fiche != nil {
            Color.clear
                .overlay {
                    Image("flag-\(gp.slug)")
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    Image("trace-\(gp.slug)")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.30))
                        .padding(.vertical, 20)
                }
                .overlay { Color.black.opacity(0.25) }
                .clipped()
                .accessibilityHidden(true)
        } else {
            // GP hors calendrier statique : l'aplat de la marque, sans drapeau à voiler.
            Color.primaire
        }
    }

    private var libelleAccessible: String {
        t("historique.a11y.carte", gp.fiche?.nom ?? gp.nom, gp.fiche?.dateAffichee ?? "",
          tp("classement.a11y.points", gp.totalPoints ?? 0),
          tp("historique.a11y.reussisSur", gp.pronostics.count, gp.reussis))
    }

    // MARK: La partie basse

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **Toutes les entrées, sans plafond** : vainqueur, podium, puis les bonus.
            VStack(spacing: 12) {
                ForEach(obligatoires) { RangeeHistorique(pronostic: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if !bonus.isEmpty {
                titreSection(t("recap.bonus"))

                VStack(spacing: 12) {
                    ForEach(bonus) { RangeeHistorique(pronostic: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if gp.podium.count == 3 {
                titreSection(t("historique.resultatReel"))

                HStack(spacing: 8) {
                    ForEach(Array(gp.podium.enumerated()), id: \.offset) { index, pilote in
                        TuilePodium(position: index + 1, pilote: pilote)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var obligatoires: [PronosticMembre] { gp.pronostics.filter { $0.type != "bonus" } }
    private var bonus: [PronosticMembre] { gp.pronostics.filter { $0.type == "bonus" } }

    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)             // 5,33:1 sur le blanc
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .accessibilityAddTraits(.isHeader)
    }
}

/// L'ombre du texte posé sur le drapeau. **Le texte s'impose par sa propre force, pas
/// par un voile** — même principe que les noms de pays du calendrier, en plus appuyé :
/// le texte de la carte est plus grand, et le drapeau couvre toute la surface.
private extension View {
    func ombreTexteDrapeau() -> some View {
        self.shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Un pronostic

/// Le marché, la sélection, puis ce qu'il a rapporté — la structure de
/// ``SectionMesResultats``, avec ses deux composants.
private struct RangeeHistorique: View {

    let pronostic: PronosticMembre

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pronostic.marche)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)     // 5,33:1 sur le blanc
                    .lineLimit(1)
                Text(pronostic.choix)
                    .font(.custom("HelveticaNeue", size: 14))
                    .foregroundColor(.texte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PastillePoints(pointsGagnes: pronostic.pointsGagnes, points: pronostic.points ?? 0)
                .fixedSize()
            Verdict(pointsGagnes: pronostic.pointsGagnes, nonEvaluable: pronostic.nonEvaluable)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("resultats.a11y.pronostic", pronostic.marche, pronostic.choix, verdict))
    }

    private var verdict: String {
        if pronostic.nonEvaluable { return t("parGP.a11y.nonEvaluable") }
        guard let gagnes = pronostic.pointsGagnes else {
            return tp("parGP.a11y.enAttente", pronostic.points ?? 0)
        }
        return gagnes > 0 ? tp("parGP.a11y.gagne", gagnes) : t("parGP.a11y.rate")
    }
}

// MARK: - Une marche du podium

private struct TuilePodium: View {

    let position: Int
    let pilote: LigneResultat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ordinal(position))
                .font(.labelSm)
                .tracking(Tracking.label)
                .foregroundColor(.secondaire)
            Text(pilote.prenom)
                .font(.custom("HelveticaNeue", size: 12))
                .foregroundColor(.texte)
                .lineLimit(1)
            Text(pilote.nom)
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .foregroundColor(.texte)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(pilote.equipe ?? "")
                .font(.custom("HelveticaNeue", size: 11))
                .foregroundColor(.secondaire)             // 9,32:1 beige · 11,0:1 ambre
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(position == 1 ? Color.ambreClair : Color.fondPrincipal)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ordinal(position)), \(pilote.prenom) \(pilote.nom), \(pilote.equipe ?? "")")
    }
}

#Preview {
    NavigationStack {
        HistoriqueGPView()
    }
}
