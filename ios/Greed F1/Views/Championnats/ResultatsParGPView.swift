import SwiftUI

/// Résultats par Grand Prix — **ce que les autres ont joué**, course par course.
///
/// Référence : `maquettes_V2/screen-15-resultats-par-gp.PNG`, et l'écran web
/// `ResultatsChampionnat.jsx` dont il reprend les règles (`docs/composants.md` §9).
///
/// - Le sélecteur ne propose que les Grands Prix **terminés** : ce sont les seuls dont les
///   paris sont jugés.
/// - Les membres sont triés **par points gagnés sur ce Grand Prix**, jamais par le
///   classement général — un dernier de la saison peut signer le meilleur dimanche.
/// - **Un membre sans pronostic n'est pas dépliable** : un chevron qui ouvrirait sur rien
///   serait une promesse fausse. « Rien joué » se dit sur la ligne.
///
/// > **Le changement de Grand Prix ne fait aucun fondu.** La liste est remplacée par une
/// > donnée qui arrive du réseau : il n'y a pas d'« avant » à faire tenir. Seule la
/// > pastille glisse — elle, c'est le doigt qui l'a déplacée.
struct ResultatsParGPView: View {

    let championnat: Championnat

    @StateObject private var donnees: ResultatsParGrandPrix

    @Environment(\.dismiss) private var fermer
    @Environment(\.monProfil) private var monProfil
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// Le Grand Prix regardé. **Il se pose une fois et ne bouge plus** : un rechargement
    /// de la saison ne ramène pas le sélecteur sur le défaut pendant qu'on en lit un autre.
    @State private var gpChoisi: UUID?
    /// Un seul membre déplié à la fois.
    @State private var membreOuvert: UUID?

    @Namespace private var pastille

    private let margeLaterale: CGFloat = 16

    init(championnat: Championnat) {
        self.championnat = championnat
        _donnees = StateObject(wrappedValue: ResultatsParGrandPrix(championnatId: championnat.id))
    }

    private var gpRegarde: GrandPrixDuChampionnat? {
        donnees.termines.first { $0.id == gpChoisi }
    }

    /// Ceux qui ont joué — « 7 joueurs » sur `screen-15`, sur huit lignes.
    private var joueurs: Int? {
        guard let gp = gpChoisi, case .pret(let membres) = donnees.paris[gp] else { return nil }
        return membres.filter(\.aJoue).count
    }

    private var sousTitre: String {
        guard let gp = gpRegarde else { return "Saison 2026" }
        guard let joueurs else { return gp.nom }
        return "\(gp.nom) · \(joueurs) joueur\(joueurs > 1 ? "s" : "")"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        entete(retrait: proxy.safeAreaInsets.top)
                        contenu
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        // Barre masquée plutôt que `navigationBarBackButtonHidden` : le retour par
        // glissement reste disponible (même arbitrage que ``RecapView``).
        .toolbar(.hidden, for: .navigationBar)
        .task { await donnees.chargerSaison() }
        .onChange(of: donnees.termines) { _, termines in
            // Le dernier couru : celui dont on vient de découvrir les points.
            if gpChoisi == nil { gpChoisi = termines.last?.id }
        }
        .task(id: gpChoisi) {
            guard let gpChoisi else { return }
            await donnees.chargerParis(gpChoisi)
        }
    }

    // MARK: - En-tête

    private func entete(retrait: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            boutonRetour

            Spacer().frame(height: 20)

            Text("Résultats par Grand Prix")
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.white)                  // 10,88:1 sur `primaire`
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 6)

            // `encreSecondaire` (5,75:1) — le blanc à 60 % de la maquette tombe à 4,47:1.
            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 15))
                .foregroundColor(.encreSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, margeLaterale)
        .padding(.top, retrait + 4)
        .padding(.bottom, 28)
        .background {
            ZStack {
                Color.primaire
                Damier(opacite: Materiau.damier)
                LueurHaute()
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Rayon.bloc,
                                          bottomTrailingRadius: Rayon.bloc,
                                          style: .continuous))
        .ombreAplat()
        .accessibilityElement(children: .contain)
    }

    /// **44 × 44 pt au moins**, posés par le `contentShape` : sans lui, seuls les glyphes
    /// seraient touchables.
    private var boutonRetour: some View {
        Button { fermer() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                Text(championnat.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel("Retour à \(championnat.nom)")
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch donnees.saison {
        case .chargement:
            ProgressView()
                .tint(.secondaire)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel("Chargement des Grands Prix")

        case .echec(let erreur):
            EchecChargement(erreur: erreur) {
                Task { await donnees.chargerSaison() }
            }

        case .pret:
            if donnees.termines.isEmpty {
                etatVide
            } else {
                VStack(spacing: 16) {
                    selecteur
                    blocParis
                }
            }
        }
    }

    /// Données manquantes, pas une erreur : aucune course n'est encore jugée.
    private var etatVide: some View {
        VStack(spacing: 6) {
            Text("Aucun Grand Prix terminé")
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundColor(.texte)
            Text("Les paris de chacun apparaîtront ici dès les premiers résultats.")
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)             // 5,33:1 sur le blanc
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
        .padding(.horizontal, margeLaterale)
    }

    // MARK: - Le sélecteur

    /// Une piste blanche, une pastille bordeaux **qui glisse** vers le Grand Prix choisi —
    /// la pastille est la seule chose qui bouge, parce que c'est le doigt qui l'a déplacée.
    /// Le sélecteur ramène sous les yeux l'option choisie quand il déborde l'écran.
    private var selecteur: some View {
        ScrollViewReader { defilement in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(donnees.termines) { gp in
                        optionGP(gp)
                            .id(gp.id)
                    }
                }
                .padding(4)
                .background(Color.surface)
                .clipShape(Capsule())
                .padding(.horizontal, margeLaterale)
            }
            .onAppear {
                if let gpChoisi { defilement.scrollTo(gpChoisi, anchor: .center) }
            }
            .onChange(of: gpChoisi) { _, cible in
                guard let cible else { return }
                withAnimation(mouvementReduit ? nil : Mouvement.deplacement(Mouvement.passageEcran)) {
                    defilement.scrollTo(cible, anchor: .center)
                }
            }
        }
    }

    private func optionGP(_ gp: GrandPrixDuChampionnat) -> some View {
        let actif = gp.id == gpChoisi
        return Button {
            guard !actif else { return }
            membreOuvert = nil
            withAnimation(mouvementReduit ? nil : Mouvement.deplacement(Mouvement.passageEcran)) {
                gpChoisi = gp.id
            }
        } label: {
            Text(gp.libelleCourt)
                .font(.custom(actif ? "HelveticaNeue-Medium" : "HelveticaNeue", size: 16))
                // Actif : blanc sur `primaire`, 10,88:1. Inactif : 5,33:1 sur le blanc.
                .foregroundColor(actif ? .white : .grisSecondaire)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background {
                    if actif {
                        Capsule()
                            .fill(Color.primaire)
                            .matchedGeometryEffect(id: "pastille", in: pastille)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(gp.nom)
        .accessibilityAddTraits(actif ? .isSelected : [])
    }

    // MARK: - Les paris de chacun

    @ViewBuilder private var blocParis: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Les paris de chacun")
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)             // 5,33:1 sur le blanc
                .padding(.bottom, 4)

            switch gpChoisi.flatMap({ donnees.paris[$0] }) ?? .chargement {
            case .chargement:
                ProgressView()
                    .tint(.secondaire)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel("Chargement des paris")

            case .echec(let erreur):
                EchecChargement(erreur: erreur) {
                    guard let gpChoisi else { return }
                    Task { await donnees.chargerParis(gpChoisi) }
                }

            case .pret(let membres):
                if membres.isEmpty {
                    Text("Ce championnat n'a aucun membre.")
                        .font(.corpsSm)
                        .foregroundColor(.grisSecondaire)
                } else {
                    VStack(spacing: 2) {
                        ForEach(membres) { membre in
                            LigneParisMembre(
                                membre: membre,
                                livree: membre.livree(profil: monProfil),
                                photo: monProfil?.id == membre.profilId
                                    ? monProfil?.avatarUrl : membre.avatarUrl,
                                estMoi: monProfil?.id == membre.profilId,
                                ouvert: membreOuvert == membre.id,
                                basculer: { basculer(membre.id) }
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
        .padding(.horizontal, margeLaterale)
    }

    /// Ouvre un membre et ferme le précédent dans la même transaction — l'ouverture plus
    /// lente que la fermeture (240 / 170 ms), le même accordéon que ``CotesView``.
    private func basculer(_ id: UUID) {
        let cible: UUID? = membreOuvert == id ? nil : id
        let duree = cible == nil ? Mouvement.accordeonFermeture : Mouvement.accordeonOuverture
        withAnimation(mouvementReduit ? nil : Mouvement.entree(duree)) {
            membreOuvert = cible
        }
    }
}

// MARK: - Une ligne de membre

private struct LigneParisMembre: View {

    let membre: MembrePronostics
    let livree: Livree
    let photo: URL?
    let estMoi: Bool
    let ouvert: Bool
    let basculer: () -> Void

    /// Juste après la course, la grille peut ne pas être notée : on montre alors ce
    /// qu'elle **peut** rapporter, avec le mot qui le dit.
    private var juge: Bool { membre.totalPoints != nil }

    var body: some View {
        if membre.aJoue {
            VStack(spacing: 0) {
                Button(action: basculer) {
                    HStack(spacing: 12) {
                        identite
                        score
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.grisSecondaire)  // élément graphique, 5,33:1
                            .rotationEffect(.degrees(ouvert ? 180 : 0))
                            .frame(width: 16)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
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
            .clipped()
        } else {
            HStack(spacing: 12) {
                identite
                // La colonne de droite dit quelque chose sur toutes les lignes : sinon
                // l'œil lit un score manquant plutôt qu'un joueur absent.
                Text("Rien joué")
                    .font(.custom("HelveticaNeue", size: 15))
                    .foregroundColor(.grisSecondaire)
                    .fixedSize()
                // La place du chevron est tenue : la colonne des pseudos reste une colonne.
                Color.clear.frame(width: 16, height: 1)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(membre.pseudo)\(estMoi ? ", toi" : ""). Aucun prono sur ce Grand Prix.")
        }
    }

    private var identite: some View {
        HStack(spacing: 12) {
            VueVoiture(livree: livree,
                       numero: membre.numero.map(String.init) ?? "",
                       photo: photo,
                       teintePilote: .teinteAvatar(pour: membre.cleTeinte))
                .frame(width: 20, height: 20 / VueVoiture.rapport)

            PastilleProfil(pseudo: membre.pseudo, photo: photo,
                           fond: .teinteAvatar(pour: membre.cleTeinte), taille: 40)

            VStack(alignment: .leading, spacing: 2) {
                (Text(membre.pseudo).foregroundColor(.texte)          // 15,37:1
                 + Text(estMoi ? " · Toi" : "").foregroundColor(.primaire))
                    .font(.custom("HelveticaNeue-Medium", size: 16))
                    .lineLimit(1)

                Text(sousTitre)
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.grisSecondaire)                 // 5,33:1 sur le blanc
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sousTitre: String {
        let n = membre.pronostics.count
        guard n > 0 else { return "Aucun prono sur ce Grand Prix" }
        return "\(n) prono\(n > 1 ? "s" : "") validé\(n > 1 ? "s" : "")"
    }

    /// Le nombre habillé par ``formaterPoints(_:)``, seul propriétaire du « N pts » ; seul
    /// le qualificatif est écrit ici.
    private var score: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formaterPoints(juge ? membre.totalPoints : membre.potentiel))
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .foregroundColor(.primaire)                           // 10,88:1 sur le blanc
                .lineLimit(1)
            Text(juge ? "Gagnés" : "En jeu")
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)
        }
        .fixedSize()
    }

    private var libelleAccessible: String {
        let points = juge ? membre.totalPoints ?? 0 : membre.potentiel
        return "\(membre.pseudo)\(estMoi ? ", toi" : ""). \(sousTitre). "
            + "\(points) points \(juge ? "gagnés" : "en jeu")."
    }

    /// Le détail, **aligné sur le pseudo** et non sur la voiture : les pronostics
    /// appartiennent à la personne nommée.
    private var detail: some View {
        VStack(spacing: 10) {
            ForEach(membre.pronostics) { RangeePronostic(pronostic: $0) }
        }
        .padding(.leading, 84)
        .padding(.trailing, 4)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

// MARK: - Un pronostic déplié

/// Le marché, la sélection, puis ce que le pari a rapporté — ou peut rapporter tant que
/// la course n'est pas jugée. **Vert sauge si gagné, bordeaux si raté, neutre sinon** :
/// `0` et `nil` ne se confondent jamais (`CLAUDE.md` §3.1).
private struct RangeePronostic: View {

    let pronostic: PronosticMembre

    private var juge: Bool { pronostic.pointsGagnes != nil }
    private var reussi: Bool { (pronostic.pointsGagnes ?? 0) > 0 }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pronostic.marche)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)
                    .lineLimit(1)
                Text(pronostic.choix)
                    .font(.custom("HelveticaNeue", size: 14))
                    .foregroundColor(.texte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Vert sauge + blanc 4,86:1 · `primaire` + blanc 10,88:1 ·
            // `fondPrincipal` + `secondaire` 9,32:1.
            Text(formaterPoints(juge ? pronostic.pointsGagnes : pronostic.points))
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .foregroundColor(juge ? .white : .secondaire)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(juge ? (reussi ? Color.vertSauge : Color.primaire) : Color.fondPrincipal)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(pronostic.marche), \(pronostic.choix), "
            + (juge ? (reussi ? "gagné, \(pronostic.pointsGagnes ?? 0) points" : "raté")
                    : "en attente, \(pronostic.points ?? 0) points en jeu")
        )
    }
}

#Preview {
    NavigationStack {
        ResultatsParGPView(championnat: .apercu)
    }
}
