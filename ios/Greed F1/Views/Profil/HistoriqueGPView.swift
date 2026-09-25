import SwiftUI

/// **Ses Grands Prix** — ce qu'un membre a joué sur la saison, Grand Prix par Grand Prix.
///
/// Ouvert depuis ``ProfilMembreView`` et depuis ``ProfilView``, par la même ligne
/// (``LigneGrandsPrix``). Pas de maquette : l'écran assemble le vocabulaire existant — le
/// bloc bordeaux de ``SectionMesResultats``, le drapeau à 15 % des lignes de résultats,
/// ``PastillePoints`` et ``Verdict``.
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

    /// Du plus récent au plus ancien — l'ordre du calendrier, retourné.
    private var grandsPrix: [GrandPrixJoue] {
        let ordre = GrandPrixSaison.saison2026.map(\.slug)
        return historique.grandsPrix.sorted {
            (ordre.firstIndex(of: $0.slug) ?? -1) > (ordre.firstIndex(of: $1.slug) ?? -1)
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

private struct CarteGrandPrixJoue: View {

    let gp: GrandPrixJoue
    let ouvert: Bool
    let basculer: () -> Void

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

    /// **Sur le drapeau à 15 %, aucun gris ne tient** — `grisSecondaire` y tombe à
    /// 3,76:1 sur le pire substrat (le noir). La date et le compte des réussis passent donc
    /// au marron `secondaire` (7,46:1), comme les lignes de résultats.
    private var haut: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gp.fiche?.nom ?? gp.slug)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.texte)
                    .lineLimit(1)
                Text(gp.fiche?.date ?? "")
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.secondaire)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(gp.pointsGagnes.map(\.enPoints) ?? "—")
                        .font(.custom("HelveticaNeue-Medium", size: 22))
                        .foregroundColor(.primaire)       // 7,68:1 sur le pire substrat
                    Text("pts")
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.primaire)
                }
                Text("\(gp.reussis)/\(gp.pronostics.count) réussis")
                    .font(.custom("HelveticaNeue", size: 11))
                    .foregroundColor(.secondaire)
            }
            .fixedSize()

            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondaire)
                .rotationEffect(.degrees(ouvert ? 180 : 0))
                .frame(width: 16)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .background { drapeau }
        .contentShape(Rectangle())
    }

    /// Le drapeau du pays hôte, étiré comme les lignes de résultats : un recadrage
    /// garderait la bande centrale et perdrait le pays.
    @ViewBuilder private var drapeau: some View {
        if gp.fiche != nil {
            Image("flag-\(gp.slug)")
                .resizable()
                .opacity(0.15)
                .accessibilityHidden(true)
        }
    }

    private var libelleAccessible: String {
        "\(gp.fiche?.nom ?? gp.slug), \(gp.fiche?.date ?? ""). "
            + "\(gp.pointsGagnes ?? 0) points, \(gp.reussis) sur \(gp.pronostics.count) réussis."
    }

    // MARK: La partie basse

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Le séparateur est un aplat beige de 1 pt, pas un trait gris : il sépare le
            // drapeau du blanc, rien de plus.
            Color.fondPrincipal.frame(height: 1)

            VStack(spacing: 12) {
                ForEach(gp.pronostics) { RangeeHistorique(pronostic: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if gp.podium.count == 3 {
                Text("Résultat réel")
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)     // 5,33:1 sur le blanc
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
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
