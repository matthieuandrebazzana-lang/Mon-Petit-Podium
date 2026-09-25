import SwiftUI

/// **Ses Grands Prix** — ce qu'un membre a joué sur la saison, Grand Prix par Grand Prix.
///
/// Ouvert depuis ``ProfilMembreView`` et depuis ``ProfilView``, par la même ligne
/// (``LigneGrandsPrix``). Pas de maquette : chaque carte reprend l'empilement du widget
/// GP de l'accueil (drapeau · tracé · voile · contenu), le détail reprend ``PastillePoints``
/// et ``Verdict``.
///
/// > *Écart signalé (`CLAUDE.md` §3.2).* Le type et la route portent « historique », terme
/// > proscrit du vocabulaire. **Rien de ce qui s'affiche ne le dit** : l'écran s'intitule
/// > « Ses Grands Prix ».
///
/// **Données** : ``HistoriqueSaison/apercu`` tant que `GET /membres/{id}/historique`
/// n'existe pas.
///
/// **Une seule carte ouverte à la fois** : en ouvrir une referme la précédente.
struct HistoriqueGPView: View {

    /// « Ses Grands Prix », ou « Mes Grands Prix » depuis son propre profil.
    var titre = "Ses Grands Prix"

    var historique: HistoriqueSaison = .apercu

    @State private var ouvert: String?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private let margeLaterale: CGFloat = 16

    /// Du plus ancien au plus récent — l'ordre du calendrier. **Le tri se fait ici**, quel
    /// que soit l'ordre dans lequel l'API renverra la liste ; un GP hors calendrier
    /// statique ferme la marche.
    private var grandsPrix: [GrandPrixJoue] {
        let ordre = GrandPrixSaison.saison2026.map(\.slug)
        return historique.grandsPrix.sorted {
            (ordre.firstIndex(of: $0.slug) ?? .max) < (ordre.firstIndex(of: $1.slug) ?? .max)
        }
    }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    entete

                    Spacer().frame(height: 20)
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
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func basculer(_ id: String) {
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
            Text("Saison \(String(historique.saison)) · \(joues) \(joues > 1 ? "GP joués" : "GP joué")")
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var joues: Int { historique.grandsPrix.count }

    // MARK: - Résumé de la saison

    private var resumeSaison: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Total saison")
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.encreSecondaire)    // blanc 70 % — 5,75:1

                Spacer().frame(height: 6)

                Text(historique.totalPoints.map(\.enPoints) ?? "—")
                    .font(.scoreLg)
                    .tracking(Tracking.scoreLg)
                    .foregroundColor(.white)              // 10,88:1 sur le bordeaux
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer().frame(height: 4)

                Text("\(reussis) prono\(reussis > 1 ? "s" : "") réussi\(reussis > 1 ? "s" : "")")
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.encreSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let rang = historique.rang {
                VStack(spacing: 2) {
                    Text(rang == 1 ? "1er" : "\(rang)e")
                        .font(.custom("HelveticaNeue-Medium", size: 26))
                        .foregroundColor(.white)
                    // **Blanc 70 % et non 50 %** : sur la pastille (blanc 15 % sur le
                    // bordeaux), 50 % ne tient que 3,15:1 — sous le plancher de 4,5:1 d'un
                    // texte de 10 pt. 70 % y tient 4,76:1.
                    Text("Classement")
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

    private var reussis: Int { historique.pronosticsReussis }

    private var libelleResume: String {
        var libelle = "Total saison, \(historique.totalPoints ?? 0) points, "
            + "\(reussis) pronostic\(reussis > 1 ? "s" : "") réussi\(reussis > 1 ? "s" : "")."
        if let rang = historique.rang { libelle += " \(rang == 1 ? "1er" : "\(rang)e") au classement." }
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

    let gp: GrandPrixJoue
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
                .accessibilityValue(ouvert ? "Déplié" : "Replié")
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
                        Text(gp.fiche?.nom ?? gp.slug)
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .ombreTexteDrapeau()
                        Text(gp.fiche?.date ?? "")
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
                    Text("\(gp.reussis)/\(gp.pronostics.count) pronos réussis")
                        .font(.custom("HelveticaNeue-Medium", size: 14))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .ombreTexteDrapeau()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(gp.pointsGagnes.map(\.enPoints) ?? "—")
                            .font(.custom("HelveticaNeue-Medium", size: 34))
                            .tracking(-0.85)              // grand chiffre : −0,025em × 34
                            .foregroundColor(.white)
                        Text("pts")
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
    /// joués et jugés.
    private var badgeStatut: some View {
        Text("Terminé")
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
        "\(gp.fiche?.nom ?? gp.slug), \(gp.fiche?.date ?? ""), terminé. "
            + "\(gp.pointsGagnes ?? 0) points, \(gp.reussis) sur \(gp.pronostics.count) pronostics réussis."
    }

    // MARK: La partie basse

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 12) {
                ForEach(gp.pronostics) { RangeeHistorique(pronostic: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if gp.podium.count == 3 {
                Text("Résultat réel")
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)     // 5,33:1 sur le blanc
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)

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
            Verdict(pointsGagnes: pronostic.pointsGagnes)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pronostic.marche), \(pronostic.choix), \(verdict)")
    }

    private var verdict: String {
        guard let gagnes = pronostic.pointsGagnes else {
            return "en attente, \(pronostic.points ?? 0) points en jeu"
        }
        return gagnes > 0 ? "gagné, \(gagnes) points" : "raté"
    }
}

// MARK: - Une marche du podium

private struct TuilePodium: View {

    let position: Int
    let pilote: PiloteClasse

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(position == 1 ? "1er" : "\(position)e")
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
            Text(pilote.ecurie)
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
        .accessibilityLabel("\(position == 1 ? "1er" : "\(position)e"), \(pilote.prenom) \(pilote.nom), \(pilote.ecurie)")
    }
}

#Preview {
    NavigationStack {
        HistoriqueGPView()
    }
}
