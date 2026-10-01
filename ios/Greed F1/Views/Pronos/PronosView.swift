import SwiftUI

/// **Mes pronos** — la saisie des deux pronostics obligatoires, et le choix des paris bonus
/// parmi les favoris.
///
/// Références visuelles : `Ressources/Screenshots/screen-25-pronos-haut.PNG` (vide) et
/// `screen-26-pronos-remplis.PNG` (remplie).
///
/// Tout vient du serveur (`docs/swift-app.md` §7.6, étape 7) : les cotes et les favoris par
/// Railway, **mes pronostics déjà enregistrés en direct** sous RLS, qui préremplissent
/// l'écran **une seule fois** — un rechargement au retour du récapitulatif n'écrase jamais
/// une saisie en cours. La validation envoie `POST …/pronostics` ; le récapitulatif n'est
/// empilé **qu'après le `200`**.
struct PronosView: View {

    let grandPrix: GrandPrixPronos

    /// Empile une étape du parcours — le récapitulatif, une fois l'écriture acceptée.
    let avancer: (EtapePronos) -> Void

    private let margeLaterale: CGFloat = 16

    @StateObject private var donnees: DonneesPronostics

    /// Ce qui est choisi, emplacement par emplacement. **Un dictionnaire et non trois
    /// `@State`** : les trois emplacements obéissent à la même règle d'exclusion.
    @State private var choix: [EmplacementProno: Cote] = [:]

    /// Les paris bonus retenus, **par `id_outcome_unibet`**, dans l'ordre d'ajout.
    @State private var bonus: [String] = []

    /// La saisie a été préremplie depuis mes pronostics enregistrés — une seule fois.
    @State private var prerempli = false

    /// L'emplacement dont la feuille de choix est ouverte. `nil` quand elle est fermée.
    @State private var feuille: EmplacementProno?

    @State private var envoi = false

    /// Ce qui manque, ou le refus du serveur — **au-dessus du bouton**, jamais une alerte.
    @State private var erreurEnvoi: ErreurAPI?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// Prévisualisation admin — la pastille rappelle que ce qu'on voit n'est pas ce que
    /// voient les autres (``AuthViewModel/modePrevisualisation``).
    @Environment(\.modePrevisualisation) private var modeAdmin

    init(grandPrix: GrandPrixPronos, avancer: @escaping (EtapePronos) -> Void) {
        self.grandPrix = grandPrix
        self.avancer = avancer
        _donnees = StateObject(wrappedValue: DonneesPronostics(gpId: grandPrix.id,
                                                              avecMesPronostics: true))
    }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    titre

                    switch donnees.etat {
                    case .chargement:
                        Spacer().frame(height: 20)
                        ChargementPronos()

                    case .echec(let erreur):
                        Spacer().frame(height: 20)
                        EchecChargement(erreur: erreur) {
                            Task { await charger() }
                        }

                    case .pret(let lu):
                        contenu(lu)
                    }
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let lu = donnees.donnees { barreAction(lu) }
        }
        .overlay(alignment: .bottomLeading) {
            if modeAdmin { PastillePrevisualisation().padding(.leading, margeLaterale) }
        }
        .sheet(item: $feuille) { emplacement in
            FeuilleChoixPilote(
                emplacement: emplacement,
                cotes: donnees.donnees?.gp.marche(emplacement.marche.slug)?.cotes ?? [],
                choisi: choix[emplacement],
                indisponibles: indisponibles(pour: emplacement)
            ) { cote in
                choix[emplacement] = cote
                erreurEnvoi = nil
                feuille = nil
            }
        }
        // Rechargé à chaque apparition, y compris au retour du récapitulatif (§7.6).
        .task { await charger() }
    }

    private func charger() async {
        await donnees.charger()
        preremplir()
    }

    // MARK: - Titre

    private var titre: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("pronos.titre"))
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)            // 15,37:1 sur le beige

            Text(grandPrix.sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)   // 4,71:1 — `texteDoux` n'y tient que 2,52:1
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func contenu(_ lu: DonneesPronostics.Donnees) -> some View {
        Spacer().frame(height: 12)
        BlocEcheance(horaires: lu.gp.horaires)

        Spacer().frame(height: 24)   // changement de sujet (§4.6)
        titreSection(t("pronos.obligatoires"))

        if lu.gp.marche(MarcheCote.vainqueur.slug) == nil || lu.gp.marche(MarcheCote.podium.slug) == nil {
            // Le serveur refuserait tout pronostic : le dire avant qu'on remplisse.
            Spacer().frame(height: 10)
            Text(t("pronos.obligatoiresAbsents"))
                .font(.corps)
                .foregroundColor(.secondaire)           // 9,32:1 sur le beige
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }

        Spacer().frame(height: 10)
        BlocObligatoire(marche: .vainqueur) {
            emplacement(.vainqueur)
        }

        Spacer().frame(height: 12)   // espacement entre blocs (§4.6)
        BlocObligatoire(marche: .podium) {
            VStack(spacing: 8) {
                emplacement(.podium1)
                emplacement(.podium2)
            }
        }

        Spacer().frame(height: 24)
        sectionParisBonus(favoris: favorisTries(lu))
    }

    /// Titre de section. **L'encre est `grisSecondaire`, pas `texteDoux`** : sur le beige
    /// le premier mesure 4,71:1, le second 2,52:1.
    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// **Les deux emplacements du podium ne sont pas numérotés** : ils valent les 2e et 3e
    /// places sans ordre entre eux (§6.3).
    private func emplacement(_ slot: EmplacementProno) -> some View {
        EmplacementProno.Champ(marche: slot.marche, choisi: choix[slot]) {
            feuille = slot
        }
    }

    // MARK: - Les paris bonus

    /// Les favoris épinglés au tableau des cotes, **dans l'ordre de leurs marchés** — le même
    /// qu'au tableau (``OrdreMarches``). On en retient jusqu'à trois ; l'épinglage, lui,
    /// vit à l'écran précédent et à un seul endroit.
    private func sectionParisBonus(favoris: [Favori]) -> some View {
        let retenus = bonusRetenus(favoris)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("pronos.mesBonus"))
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)

                Spacer(minLength: 12)

                HStack(spacing: 0) {
                    Text("\(retenus.count)")
                        .font(.custom("HelveticaNeue-Medium", size: 12))
                        .foregroundColor(.primaire)
                        .contentTransition(.numericText())
                    Text(t("pronos.surMax", CotesView.bonusMaximum))
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.grisSecondaire)
                }
            }
            .padding(.horizontal, 4)

            if favoris.isEmpty {
                zoneVide
            } else {
                VStack(spacing: 8) {
                    ForEach(favoris) { favori in
                        let actif = retenus.contains(favori.idOutcomeUnibet)
                        CarteParisBonus(
                            favori: favori,
                            actif: actif,
                            sature: !actif && retenus.count >= CotesView.bonusMaximum
                        ) {
                            basculerBonus(favori.idOutcomeUnibet, favoris: favoris)
                        }
                    }
                }
            }
        }
    }

    private var zoneVide: some View {
        VStack(spacing: 8) {
            Image("icone-etoile")
                .renderingMode(.template)
                .foregroundColor(.secondaire.opacity(0.60))   // 3,40:1 sur le blanc
                .accessibilityHidden(true)

            Text(t("pronos.aucunBonus"))
                .font(.corps)
                .foregroundColor(.texte)

            Text(t("pronos.aucunBonusDetail"))
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
    }

    // MARK: - Barre d'action

    /// Le total vit **dans la barre, au-dessus du bouton** : c'est le chiffre qui fait
    /// changer d'avis. Il n'apparaît qu'une fois quelque chose de choisi.
    ///
    /// **Le bouton reste actif même quand la saisie est incomplète** (§7.1) : l'appui pose
    /// le message juste au-dessus, à l'endroit où il se lit.
    private func barreAction(_ lu: DonneesPronostics.Donnees) -> some View {
        let total = total(lu)

        return VStack(spacing: 10) {
            if let erreurEnvoi {
                ErreurEnLigne(erreur: erreurEnvoi)
                    .transition(.opacity)
            }

            if total > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text(t("pronos.totalSiToutTombe"))
                        .font(.label)
                        .tracking(Tracking.label)
                        .textCase(.uppercase)
                        .foregroundColor(.grisSecondaire)

                    Spacer(minLength: 12)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(total.enPoints)
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .tracking(-0.60)          // −0,025em × 24
                            .contentTransition(.numericText())
                        Text(t("points.unite"))
                            .font(.custom("HelveticaNeue-Medium", size: 14))
                    }
                    .foregroundColor(.primaire)       // 10,88:1 sur le beige
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)
            }

            Button {
                Task { await valider(lu) }
            } label: {
                ZStack {
                    Text(t("accueil.validerPronos"))
                        .opacity(envoi ? 0 : 1)
                    if envoi {
                        ProgressView().tint(.white)
                    }
                }
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .foregroundColor(.white)          // 10,88:1 sur #800111
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    ZStack {
                        Color.primaire
                        LueurHaute()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
            }
            .buttonStyle(StyleAppui(.bouton))
            .disabled(envoi)
            .accessibilityLabel(envoi ? t("pronos.a11y.enregistrement") : t("accueil.validerPronos"))
        }
        .animation(mouvementReduit ? .none : Mouvement.entree(0.18), value: total)
        .animation(mouvementReduit ? .none : Mouvement.entree(0.18), value: erreurEnvoi)
        .padding(.horizontal, margeLaterale)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .ombreFlottant()
    }

    // MARK: - La règle

    private func favorisTries(_ lu: DonneesPronostics.Donnees) -> [Favori] {
        OrdreMarches.trier(lu.favoris, slug: \.marche)
    }

    /// Les bonus **encore épinglés** — `bonusEpingles` du web. Un bonus enregistré dont la
    /// cote a été dépunaisée depuis n'occupe aucune des trois places : sans ce filtre,
    /// l'écran affichait « 3 sur 3 max » avec deux cases cochées.
    private func bonusRetenus(_ favoris: [Favori]) -> [String] {
        let epingles = Set(favoris.map(\.idOutcomeUnibet))
        return bonus.filter { epingles.contains($0) }
    }

    /// Le maximum est une limite, pas un quota : au-delà, l'appui ne fait rien plutôt que
    /// de remplacer en douce un bonus déjà choisi.
    private func basculerBonus(_ id: String, favoris: [Favori]) {
        erreurEnvoi = nil
        withAnimation(mouvementReduit ? .none : Mouvement.entree(0.22)) {
            if let rang = bonus.firstIndex(of: id) {
                bonus.remove(at: rang)
            } else if bonusRetenus(favoris).count < CotesView.bonusMaximum {
                bonus.append(id)
            }
        }
    }

    /// Ce que rapporterait la grille si tout tombait : chaque pronostic pour sa cote, le
    /// podium pour **la somme de ses deux pilotes** (§6.3), plus les bonus retenus.
    private func total(_ lu: DonneesPronostics.Donnees) -> Int {
        let obligatoires = choix.values.reduce(0) { $0 + $1.points }
        let retenus = Set(bonusRetenus(lu.favoris))
        return obligatoires + lu.favoris
            .filter { retenus.contains($0.idOutcomeUnibet) }
            .reduce(0) { $0 + ($1.points ?? 0) }
    }

    /// Les pilotes qu'un emplacement ne peut plus proposer, **par ``ClePilote``** : un même
    /// pilote n'a pas le même identifiant au vainqueur et au podium.
    ///
    /// L'exclusion est **réactive et non destructive** : changer de vainqueur rend aussitôt
    /// l'ancien aux listes, sans vider les sélections déjà faites — la validation nomme
    /// celle qui est devenue conflictuelle.
    private func indisponibles(pour slot: EmplacementProno) -> Set<String> {
        Set(EmplacementProno.allCases
            .filter { $0 != slot }
            .compactMap { choix[$0].map { ClePilote.de($0.pilote) } })
    }

    /// Un même pilote occupe deux emplacements — vainqueur changé après le podium.
    private var conflit: Bool {
        let cles = EmplacementProno.allCases.compactMap { choix[$0].map { ClePilote.de($0.pilote) } }
        return Set(cles).count < cles.count
    }

    /// Préremplissage depuis mes pronostics enregistrés, **une seule fois**.
    private func preremplir() {
        guard !prerempli, let lu = donnees.donnees else { return }
        prerempli = true
        let miens = lu.miens ?? []

        if let vainqueur = miens.first(where: { $0.type == "vainqueur" }),
           let cote = lu.gp.cote(vainqueur.idOutcomeUnibet)?.cote {
            choix[.vainqueur] = cote
        }
        if let podium = miens.first(where: { $0.type == "podium" })?.podium {
            if let cote = lu.gp.cote(podium.0)?.cote { choix[.podium1] = cote }
            if let cote = lu.gp.cote(podium.1)?.cote { choix[.podium2] = cote }
        }
        bonus = miens.filter { $0.type == "bonus" }.map(\.idOutcomeUnibet)
    }

    // MARK: - La validation

    private func refuser(_ message: String) {
        erreurEnvoi = .serveur(statut: nil, message: message)
    }

    private func valider(_ lu: DonneesPronostics.Donnees) async {
        erreurEnvoi = nil

        // **La fermeture est vérifiée ici ET en base** : c'est la base qui fait foi, et un
        // `423` peut encore arriver alors que l'horloge du téléphone disait ouvert.
        if lu.gp.horaires.echeance().ferme {
            refuser(t("pronos.refus.fermes"))
            return
        }
        guard let vainqueur = choix[.vainqueur] else {
            refuser(t("pronos.refus.vainqueur"))
            return
        }
        guard let podium1 = choix[.podium1], let podium2 = choix[.podium2] else {
            refuser(t("pronos.refus.podium"))
            return
        }
        guard !conflit else {
            refuser(t("pronos.refus.doublon"))
            return
        }

        let retenus = bonusRetenus(lu.favoris)
        envoi = true
        defer { envoi = false }
        do {
            try await donnees.enregistrer(CorpsPronostics(
                vainqueur: vainqueur.id,
                podium: .init(pilote_1: podium1.id, pilote_2: podium2.id),
                bonus: retenus))
        } catch is CancellationError {
            return
        } catch {
            erreurEnvoi = (error as? ErreurAPI) ?? .serveur(statut: nil, message: nil)
            return
        }

        // Le récapitulatif montre **exactement ce qui vient d'être accepté** : le serveur a
        // écrit ces identifiants-là, dans une seule transaction.
        let lignesBonus = favorisTries(lu)
            .filter { retenus.contains($0.idOutcomeUnibet) }
            .map(LigneRecap.bonus)
        let grille = GrilleEnregistree(
            horaires: lu.gp.horaires,
            obligatoires: [
                .obligatoire(.vainqueur, pilote: vainqueur.pilote, points: vainqueur.points),
                .obligatoire(.podium, pilote: podium1.pilote, points: podium1.points),
                .obligatoire(.podium, pilote: podium2.pilote, points: podium2.points)
            ],
            bonus: lignesBonus)
        avancer(.recap(grandPrix, grille))
    }
}

// MARK: - Les trois emplacements

/// Les trois emplacements obligatoires d'une grille. **Ils portent leur marché** : c'est
/// lui qui décide de la liste de cotes, de l'aplat et de l'encre douce.
enum EmplacementProno: String, CaseIterable, Identifiable {

    case vainqueur
    case podium1
    case podium2

    var id: String { rawValue }

    var marche: MarcheCote {
        self == .vainqueur ? .vainqueur : .podium
    }

    /// Le champ d'un emplacement : la valeur à gauche, les points à droite, le chevron au
    /// bout.
    ///
    /// | | vide (blanc 15 %) | rempli (blanc 22 %) |
    /// |---|---|---|
    /// | Vainqueur | `#932734` · encre douce **4,69:1** | `#9F404C` · blanc **6,34:1** |
    /// | Podium | `#4C6584` · encre douce **4,82:1** | `#607792` · blanc **4,61:1** |
    ///
    /// > **Les points d'un champ rempli sont en blanc plein, pas en encre douce** : le blanc
    /// > à 85 % sur `#607792` ne vaut que 3,84:1. Le chevron, élément graphique (3:1), garde
    /// > l'encre douce.
    struct Champ: View {

        let marche: MarcheCote
        let choisi: Cote?
        let onOuvrir: () -> Void

        var body: some View {
            Button(action: onOuvrir) {
                HStack(spacing: 12) {
                    Text(choisi?.pilote ?? t("pronos.nonSelectionne"))
                        .font(.custom(choisi == nil ? "HelveticaNeue" : "HelveticaNeue-Medium",
                                      size: 15))
                        .foregroundColor(choisi == nil ? marche.encreDouce : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let choisi {
                        Text(formaterPoints(choisi.points))
                            .font(.custom("HelveticaNeue", size: 13))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(marche.encreDouce)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 44)               // plancher tactile iOS
                // Surface posée *à l'intérieur* d'un bloc : rayon `champ`, donc **aucune
                // ombre** (§4.7).
                .background(Color.white.opacity(choisi == nil ? 0.15 : 0.22))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
            }
            .buttonStyle(StyleAppui(.grandeSurface))
            .accessibilityLabel(marche.libelle)
            .accessibilityValue(choisi.map { "\($0.pilote), " + tp("classement.a11y.points", $0.points) } ?? t("pronos.nonSelectionne"))
            .accessibilityHint(t("pronos.a11y.choisirPilote"))
        }
    }
}

// MARK: - Un bloc obligatoire

/// Un marché obligatoire, en **aplat de couleur** : le rouge de la marque pour le
/// vainqueur, le bleu ardoise pour le podium. Les deux pronostics que la règle impose se
/// distinguent ainsi au premier coup d'œil des paris bonus, qui sont ambre et plus petits.
private struct BlocObligatoire<Contenu: View>: View {

    let marche: MarcheCote
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(marche.libelle)
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(.white)      // 10,88:1 · 11,04:1
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                // Blanc à 18 % et non 20 % : c'est la valeur qui tient le blanc au-dessus
                // de 4,5:1 sur **les deux** aplats — 7,57:1 sur le rouge, 5,44:1 sur le
                // bleu, qui est le plus clair des deux et donc celui qui contraint.
                Text(t("pronos.obligatoire"))
                    .font(.labelSm)
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            contenu
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                marche.aplat
                LueurHaute()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreAplat()                             // aplat de couleur (§4.7)
    }
}

// MARK: - Une tuile du compte à rebours

/// Un nombre posé sous son unité. **Graisse 500** — `ios/CLAUDE.md` §3 n'en connaît que
/// deux, et les 700 de la version web n'ont pas d'équivalent ici.
private struct TuileEcheance: View {

    let valeur: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Text(valeur)
                .font(.custom("HelveticaNeue-Medium", size: 40))
                .tracking(-1.00)                  // −0,025em × 40
                .foregroundColor(.white)          // 17,4:1 sur #1A1A1A
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // **`texteDoux` est ici à sa place** : le design system le réserve aux fonds
            // sombres, et sur `#1A1A1A` il tient 6,12:1.
            Text(label)
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.texteDoux)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.texte)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }
}


// MARK: - Le compte à rebours

/// Le compte à rebours, et **ce qu'on pose éventuellement dessous** — le récapitulatif y
/// glisse son bouton « Modifier mes pronos », la saisie n'y met rien.
///
/// **Il ne décide jamais de ce qu'il annonce** : label, décompte et substitut viennent
/// d'``EcheancePronostics``, la seule source (§6.4) — « Fermeture dans » pendant la saisie,
/// « Pronostics · Fermés » après le départ. Une `TimelineView` à la seconde, **aucune
/// animation** : un chiffre qui glisse chaque seconde attirerait l'œil pour rien.
///
/// Trois tuiles : jours · heures · minutes, puis heures · minutes · secondes dans le
/// dernier jour — sous l'heure, les minutes seules ne suffisent plus à dire l'urgence.
///
/// **La carte prend le beige du fond, pas le blanc des autres cartes** : sur une surface
/// blanche, trois aplats presque noirs se découperaient comme des trous.
struct BlocEcheance<Pied: View>: View {

    private let horaires: HorairesGP
    private let pied: Pied

    init(horaires: HorairesGP, @ViewBuilder pied: () -> Pied) {
        self.horaires = horaires
        self.pied = pied()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { contexte in
            let echeance = horaires.echeance(le: contexte.date)

            VStack(spacing: 12) {
                Text(echeance.label)
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)

                if let restant = echeance.restant, echeance.texte != nil {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(Self.tuiles(restant).enumerated()), id: \.offset) { rang, tuile in
                            if rang > 0 { deuxPoints }
                            TuileEcheance(valeur: tuile.valeur, label: tuile.label)
                        }
                    }
                } else {
                    Text(echeance.substitut)
                        .font(.custom("HelveticaNeue-Medium", size: 28))
                        .tracking(Tracking.titre)
                        .foregroundColor(.texte)        // 15,37:1 sur le beige
                }

                pied
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color.fondPrincipal)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
            .ombreBloc()                                // rayon `bloc` → `ombreBloc` (§4.7)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(echeance.phrase + ".")
        }
    }

    /// Les trois tuiles d'un décompte en secondes.
    static func tuiles(_ secondes: TimeInterval) -> [(valeur: String, label: String)] {
        let total = max(0, Int(secondes))
        let (j, h, m, s) = (total / 86_400, total % 86_400 / 3600, total % 3600 / 60, total % 60)
        let deux = { (n: Int) in String(format: "%02d", n) }
        if j > 0 {
            return [(deux(j), t("compteur.jours")), (deux(h), t("compteur.heures")),
                    (deux(m), t("compteur.minutes"))]
        }
        return [(deux(h), t("compteur.heures")), (deux(m), t("compteur.minutes")),
                (deux(s), t("compteur.secondes"))]
    }

    /// Le deux-points entre deux tuiles. **Décoratif** : les unités sont écrites sous
    /// chaque tuile.
    private var deuxPoints: some View {
        VStack(spacing: 6) {
            Circle().frame(width: 5, height: 5)
            Circle().frame(width: 5, height: 5)
        }
        .foregroundColor(.secondaire.opacity(0.40))
        .padding(.top, 34)
        .accessibilityHidden(true)
    }
}

extension BlocEcheance where Pied == EmptyView {
    /// Le compte à rebours seul, sans rien dessous.
    init(horaires: HorairesGP) {
        self.init(horaires: horaires) { EmptyView() }
    }
}

// MARK: - Une carte de pari bonus

/// Un favori, **ambre une fois retenu en pari bonus**, blanc sinon. Chaque bonus est son
/// propre bloc : un mur ambre de vingt favoris ne dirait plus lesquels comptent.
///
/// **L'encre reste `#1A1A1A` sur l'ambre** : le blanc y tomberait à 2,2:1, l'encre du design
/// system y tient **7,86:1**. Sur le blanc, l'étiquette de marché passe en `grisSecondaire`
/// (5,33:1).
private struct CarteParisBonus: View {

    let favori: Favori
    let actif: Bool
    /// Trois bonus déjà retenus : celui-ci ne peut plus entrer.
    let sature: Bool
    let onBasculer: () -> Void

    private var nom: String { favori.pilote ?? favori.idOutcomeUnibet }
    private var marche: String { favori.libelle ?? t("points.coteRetiree") }

    var body: some View {
        Button(action: onBasculer) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    // `texte` à 75 % sur l'ambre : 4,84:1 (le 70 % du web n'y tient que 4,28:1).
                    Text(marche)
                        .font(.labelSm)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundColor(actif ? .encreSecondaireAmbre : .grisSecondaire)
                        .lineLimit(1)

                    Text(nom)
                        .font(.custom("HelveticaNeue-Medium", size: 14))
                        .foregroundColor(.texte)      // 7,86:1 sur l'ambre, 15,37:1 sur le blanc
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Noir à 15 % sur l'ambre (6,4:1), beige sur le blanc.
                Text(formaterPoints(favori.points))
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .foregroundColor(.texte)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(actif ? Color.black.opacity(0.15) : Color.fondPrincipal)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .lineLimit(1)

                // La rangée retenue est **déjà ambre** : `inverse` échange les deux encres.
                EtoileParisBonus(actif: actif, inverse: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(actif ? Color.accent : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
            .ombreCarte()
            .opacity(sature ? 0.5 : 1)
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .disabled(sature)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(marche), \(nom), \(formaterPoints(favori.points))")
        .accessibilityValue(actif ? t("pronos.a11y.retenu") : t("pronos.a11y.nonRetenu"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - La feuille de choix

/// Les cotes d'un marché obligatoire, en feuille modale — la forme native d'un choix dans
/// une liste longue, avec le geste de fermeture par glissement.
///
/// Un pilote déjà pris à un autre emplacement est **barré, pas retiré** : la liste ne
/// saute pas sous le doigt, et le lien entre les deux emplacements reste visible.
private struct FeuilleChoixPilote: View {

    let emplacement: EmplacementProno
    let cotes: [Cote]
    let choisi: Cote?
    /// Les ``ClePilote`` des pilotes pris ailleurs.
    let indisponibles: Set<String>
    let onChoisir: (Cote) -> Void

    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cotes) { cote in
                        ligne(cote)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.fondPrincipal.ignoresSafeArea())
            .navigationTitle(emplacement.marche.libelle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("commun.fermer")) { fermer() }
                        .foregroundColor(.primaire)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func ligne(_ cote: Cote) -> some View {
        let actif = choisi?.id == cote.id
        let indisponible = !actif && indisponibles.contains(ClePilote.de(cote.pilote))

        return Button {
            onChoisir(cote)
        } label: {
            HStack(spacing: 12) {
                // Le liseré d'écurie, debout : un renfort, jamais le seul porteur du sens.
                if let teinte = GrillePilotes.couleurEcurie(de: cote.pilote) {
                    Capsule()
                        .fill(teinte.opacity(0.60))
                        .frame(width: 3, height: 22)
                        .accessibilityHidden(true)
                }

                Text(cote.pilote)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.texte)      // 15,37:1 sur le blanc
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(formaterPoints(cote.points))
                    .font(.custom("HelveticaNeue-Medium", size: 13))
                    .foregroundColor(.primaire)   // 10,88:1 sur le blanc
                    .lineLimit(1)

                Image(systemName: actif ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(actif ? .primaire : .secondaire.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
            .ombreCarte()
            .opacity(indisponible ? 0.4 : 1)
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .disabled(indisponible)
        .accessibilityValue(indisponible ? t("pronos.a11y.dejaChoisi") : "")
    }
}

#Preview {
    NavigationStack {
        PronosView(
            grandPrix: GrandPrixPronos(id: UUID(), nom: "GP Azerbaïdjan", slug: "azerbaidjan",
                                       sousTitre: "Samedi 26 septembre · Départ 07h00"),
            avancer: { _ in }
        )
    }
}
