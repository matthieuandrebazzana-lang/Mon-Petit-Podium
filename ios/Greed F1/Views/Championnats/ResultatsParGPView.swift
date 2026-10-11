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
/// **Fond** : le drapeau du Grand Prix regardé, flouté et voilé (``FondDrapeauFlou``) — le
/// fond de ``RecapView`` et du détail du carrousel du profil. L'en-tête s'y écrit en blanc ;
/// tant qu'aucun drapeau n'est posé (chargement, GP hors table), le beige reprend et
/// l'encre avec lui.
///
/// > **La liste ne fait aucun fondu au changement de Grand Prix.** Elle est remplacée par
/// > une donnée qui arrive du réseau : il n'y a pas d'« avant » à faire tenir. Le drapeau,
/// > lui, passe en fondu — c'est une couleur qui change, pas un objet qui bouge. La
/// > pastille glisse : c'est le doigt qui l'a déplacée.
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

    /// Le drapeau du fond — `nil` hors table des teintes : ``FondDrapeauFlou`` pose alors le
    /// beige seul. Même règle que ``RecapView``.
    private var slugFond: String? {
        guard let slug = gpRegarde?.slug, TeintesDrapeaux.table[slug] != nil else { return nil }
        return slug
    }

    /// Un drapeau derrière l'en-tête : son encre passe au blanc.
    private var surDrapeau: Bool { slugFond != nil }

    private var sousTitre: String {
        guard let gp = gpRegarde else { return t("commun.saison2026") }
        guard let joueurs else { return gp.nomAffiche }
        return tp("parGP.joueurs", joueurs, gp.nomAffiche)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FondDrapeauFlou(slug: slugFond)

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

            Text(t("championnat.resultatsParGP"))
                .font(.titre)
                .tracking(Tracking.titre)
                // Blanc sur le drapeau voilé, `texte` sur le beige (15,37:1).
                .foregroundColor(surDrapeau ? .encreSurAplat : .texte)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 6)

            // Blanc 70 % : le voile du fond est calculé pour qu'il tienne 4,5:1
            // (``ApparenceDrapeau/voileEncreSecondaire(pour:)``). Sur le beige, 4,71:1.
            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 15))
                .foregroundColor(surDrapeau ? .encreSecondaire : .grisSecondaire)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, margeLaterale)
        .padding(.top, retrait + 4)
        .padding(.bottom, 12)
        // L'encre suit le fond au même rythme que son fondu : jamais de blanc sur le beige
        // le temps que le drapeau arrive.
        .animation(Mouvement.deplacement(0.28), value: surDrapeau)
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
            .foregroundColor(surDrapeau ? .encreSurAplat : .encrePrimaire)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(t("commun.retourA", championnat.nom))
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch donnees.saison {
        case .chargement:
            ProgressView()
                .tint(.secondaire)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(t("parGP.a11y.chargementGP"))

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
            Text(t("parGP.aucunTermine"))
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundColor(.texte)
            Text(t("parGP.aucunTermineDetail"))
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

    /// Une piste, une pastille bordeaux **qui glisse** vers le Grand Prix choisi — la
    /// pastille est la seule chose qui bouge, parce que c'est le doigt qui l'a déplacée.
    /// Le sélecteur ramène sous les yeux l'option choisie quand il déborde l'écran.
    ///
    /// **Sur le drapeau, la piste est un voile, pas une surface blanche** : une bande
    /// blanche couperait l'écran en deux. Le voile ne fait qu'assombrir un fond déjà calculé
    /// pour que le blanc à 70 % y tienne 4,5:1 — il ajoute du contraste, il n'en retire
    /// jamais. Sur le beige, la piste blanche d'origine.
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
                .background(surDrapeau ? Color.voile.opacity(Materiau.voilePile) : Color.surface)
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
                // Actif : blanc sur `primaire`, 10,88:1. Inactif : blanc 70 % sur le drapeau
                // voilé (≥ 4,5:1), `grisSecondaire` sur la piste blanche (5,33:1).
                .foregroundColor(actif ? .encreSurAplat
                                 : surDrapeau ? .encreSecondaire : .grisSecondaire)
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
        .accessibilityLabel(gp.nomAffiche)
        .accessibilityAddTraits(actif ? .isSelected : [])
    }

    // MARK: - Les paris de chacun

    @ViewBuilder private var blocParis: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(t("parGP.parisDeChacun"))
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)         // 5,33:1 sur le blanc
                Spacer(minLength: 0)
                if gpRegarde?.provisoire == true {
                    MentionProvisoire()
                }
            }
            .padding(.bottom, 4)

            switch gpChoisi.flatMap({ donnees.paris[$0] }) ?? .chargement {
            case .chargement:
                ProgressView()
                    .tint(.secondaire)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel(t("parGP.a11y.chargementParis"))

            case .echec(let erreur):
                EchecChargement(erreur: erreur) {
                    guard let gpChoisi else { return }
                    Task { await donnees.chargerParis(gpChoisi) }
                }

            case .pret(let membres):
                if membres.isEmpty {
                    Text(t("parGP.aucunMembre"))
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
                .accessibilityValue(ouvert ? t("commun.deplie") : t("commun.replie"))
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
                Text(t("parGP.rienJoue"))
                    .font(.custom("HelveticaNeue", size: 15))
                    .foregroundColor(.grisSecondaire)
                    .fixedSize()
                // La place du chevron est tenue : la colonne des pseudos reste une colonne.
                Color.clear.frame(width: 16, height: 1)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t("parGP.a11y.rienJoue", membre.pseudo + (estMoi ? t("parGP.a11y.toi") : "")))
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
                 + Text(estMoi ? t("parGP.toi") : "").foregroundColor(.encrePrimaire))
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

    /// Chaque pilote du podium compte pour un : le nombre dit les lignes du dépli.
    private var sousTitre: String {
        let n = membre.paris.count
        guard n > 0 else { return t("parGP.aucunProno") }
        return tp("parGP.pronosValides", n)
    }

    /// Le nombre habillé par ``formaterPoints(_:)``, seul propriétaire du « N pts » ; seul
    /// le qualificatif est écrit ici.
    private var score: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formaterPoints(juge ? membre.totalPoints : membre.potentiel))
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .foregroundColor(.encrePrimaire)                           // 10,88:1 sur le blanc
                .lineLimit(1)
            Text(juge ? t("parGP.gagnes") : t("parGP.enJeu"))
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)
        }
        .fixedSize()
    }

    private var libelleAccessible: String {
        let points = juge ? membre.totalPoints ?? 0 : membre.potentiel
        return membre.pseudo + (estMoi ? t("parGP.a11y.toi") : "") + ". \(sousTitre). "
            + (juge ? tp("resultats.a11y.gagnes", points) : tp("parGP.a11y.pointsEnJeu", points)) + "."
    }

    /// Le détail, **aligné sur le pseudo** et non sur la voiture : les pronostics
    /// appartiennent à la personne nommée.
    private var detail: some View {
        VStack(spacing: 10) {
            ForEach(membre.paris) { RangeePronostic(pronostic: $0) }
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
            // Un pari non évaluable ne dit ni « en jeu » ni un score : le mot, sur l'aplat
            // neutre de l'attente (`fondPrincipal` + `secondaire` 9,32:1).
            Text(pronostic.nonEvaluable
                 ? t("parGP.nonEvaluable")
                 : formaterPoints(juge ? pronostic.pointsGagnes : pronostic.points))
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .foregroundColor(juge ? .encreSurAplat : .secondaire)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(juge ? (reussi ? Color.vertSauge : Color.primaire) : Color.fondPrincipal)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
                .fixedSize()

            // La pastille et le pictogramme disent la même chose de deux façons : la
            // couleur seule ne porte jamais une information (WCAG 1.4.1). Même
            // ``Verdict`` que les résultats d'un Grand Prix et « Mes Grands Prix ».
            Verdict(pointsGagnes: pronostic.pointsGagnes, nonEvaluable: pronostic.nonEvaluable)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(pronostic.marche), \(pronostic.choix), "
            + (juge ? (reussi ? tp("parGP.a11y.gagne", pronostic.pointsGagnes ?? 0) : t("parGP.a11y.rate"))
                    : pronostic.nonEvaluable ? t("parGP.a11y.nonEvaluable")
                    : tp("parGP.a11y.enAttente", pronostic.points ?? 0))
        )
    }
}

#Preview {
    NavigationStack {
        ResultatsParGPView(championnat: .apercu)
    }
}
