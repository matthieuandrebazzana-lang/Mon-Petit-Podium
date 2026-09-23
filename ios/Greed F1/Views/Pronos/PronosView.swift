import SwiftUI

/// **Mes pronos** — la saisie des deux pronostics obligatoires, et le rappel des paris
/// bonus retenus au tableau des cotes.
///
/// Références visuelles : `Ressources/Screenshots/screen-25-pronos-haut.PNG` (vide) et
/// `screen-26-pronos-remplis.PNG` (remplie).
///
/// C'est le second des deux écrans de saisie. ``CotesView`` lui confie les paris bonus ;
/// il n'en ajoute pas, il les montre — le geste d'ajout vit à l'écran précédent, et à un
/// seul endroit.
///
/// > **Les données sont mockées.** Le compte à rebours est figé à 4j 14h 34min — aucun
/// > `Timer` : l'écran ne calcule pas encore d'échéance, il en affiche une. La validation
/// > ouvre une alerte ; la route `POST /pronostics` et l'écran récapitulatif
/// > (`screen-27`) seront branchés à la passe API (`docs/swift-app.md` §5).
struct PronosView: View {

    let nomGrandPrix: String
    let slugGrandPrix: String
    let sousTitre: String
    let parisBonus: [PariBonus]

    private let margeLaterale: CGFloat = 16

    /// Ce qui est choisi, emplacement par emplacement. **Un dictionnaire et non trois
    /// `@State`** : les trois emplacements obéissent à la même règle d'exclusion, et trois
    /// variables séparées auraient fini par l'appliquer différemment.
    @State private var choix: [EmplacementProno: PiloteMock] = [:]

    /// L'emplacement dont la feuille de choix est ouverte. `nil` quand elle est fermée.
    @State private var feuille: EmplacementProno?

    private let modeAdmin = false

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    titre

                    Spacer().frame(height: 12)
                    BlocEcheance(libelle: "Ouverture dans")

                    Spacer().frame(height: 24)   // changement de sujet (§4.6)
                    titreSection("Obligatoires")

                    Spacer().frame(height: 10)
                    blocVainqueur

                    Spacer().frame(height: 12)   // espacement entre blocs (§4.6)
                    blocPodium

                    Spacer().frame(height: 24)
                    sectionParisBonus
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { barreAction }
        .overlay(alignment: .bottomLeading) {
            if modeAdmin { PastillePrevisualisation().padding(.leading, margeLaterale) }
        }
        .sheet(item: $feuille) { emplacement in
            FeuilleChoixPilote(
                emplacement: emplacement,
                choisi: choix[emplacement],
                indisponibles: indisponibles(pour: emplacement)
            ) { pilote in
                choix[emplacement] = pilote
                feuille = nil
            }
        }
    }

    // MARK: - Titre

    private var titre: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mes pronos")
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)            // 15,37:1 sur le beige

            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)   // 4,71:1 — `texteDoux` n'y tient que 2,52:1
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Titre de section. **L'encre est `grisSecondaire`, pas `texteDoux`** : sur le beige
    /// le premier mesure 4,71:1, le second 2,52:1 — sous le plancher d'un texte de 11 pt.
    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Les deux blocs obligatoires

    private var blocVainqueur: some View {
        BlocObligatoire(marche: .vainqueur) {
            emplacement(.vainqueur)
        }
    }

    private var blocPodium: some View {
        BlocObligatoire(marche: .podium) {
            VStack(spacing: 8) {
                emplacement(.podium1)
                emplacement(.podium2)
            }
        }
    }

    /// **Les deux emplacements du podium ne sont pas numérotés.** Une pastille « 1er » /
    /// « 2e » désignerait leur rang dans le bloc et non dans la course — alors qu'ils valent
    /// les 2e et 3e places. Les numéroter laisserait croire à un ordre à respecter, qu'il
    /// n'y a pas : la validation demande « ces deux pilotes sont-ils sur le podium ? »,
    /// jamais « lequel devant ».
    private func emplacement(_ slot: EmplacementProno) -> some View {
        EmplacementProno.Champ(
            marche: slot.marche,
            choisi: choix[slot],
            points: choix[slot].map { slot.marche.points(de: $0) }
        ) {
            feuille = slot
        }
    }

    // MARK: - Les paris bonus

    /// Les paris bonus **retenus au tableau des cotes**. Ils s'affichent ici, ils ne s'y
    /// ajoutent pas : le geste d'ajout vit à l'écran précédent, et à un seul endroit.
    private var sectionParisBonus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mes paris bonus")
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)

                Spacer(minLength: 12)

                HStack(spacing: 0) {
                    Text("\(parisBonus.count)")
                        .font(.custom("HelveticaNeue-Medium", size: 12))
                        .foregroundColor(.primaire)
                    Text(" sur \(CotesView.bonusMaximum) max")
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.grisSecondaire)
                }
            }
            .padding(.horizontal, 4)

            if parisBonus.isEmpty {
                zoneVide
            } else {
                VStack(spacing: 8) {
                    ForEach(parisBonus) { pari in
                        CarteParisBonus(pari: pari)
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

            Text("Aucun pari bonus pour l'instant")
                .font(.corps)
                .foregroundColor(.texte)

            Text("Ils se choisissent au tableau des cotes, avec l'étoile.")
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
    /// changer d'avis, il doit bouger sous les yeux au moment du choix et non attendre le
    /// récapitulatif.
    ///
    /// Il n'apparaît **qu'une fois quelque chose de choisi** — « 0 pts » avant le premier
    /// pilote se lirait comme un mauvais départ, et c'est ce que montre `screen-25`, où la
    /// ligne est absente.
    private var barreAction: some View {
        VStack(spacing: 10) {
            if total > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("Total si tout tombe")
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
                        Text("pts")
                            .font(.custom("HelveticaNeue-Medium", size: 14))
                    }
                    .foregroundColor(.primaire)       // 10,88:1 sur le beige
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)
            }

            NavigationLink(value: EtapePronos.recap(
                nom: nomGrandPrix, slug: slugGrandPrix, sousTitre: sousTitre,
                obligatoires: lignesObligatoires, bonus: parisBonus
            )) {
                Text("Valider mes pronos")
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
                    .opacity(complet ? 1 : 0.45)
            }
            .buttonStyle(StyleAppui(.bouton))
            .disabled(!complet)
            .accessibilityHint(complet ? "" : "Choisis le vainqueur et les deux pilotes du podium.")
        }
        .animation(Mouvement.entree(0.18), value: complet)
        .animation(Mouvement.entree(0.18), value: total)
        .padding(.horizontal, margeLaterale)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .ombreFlottant()
    }

    // MARK: - La règle

    /// La saisie est complète quand **les trois emplacements obligatoires** sont remplis.
    /// Les paris bonus n'y entrent pas : ils sont facultatifs par définition.
    private var complet: Bool {
        EmplacementProno.allCases.allSatisfy { choix[$0] != nil }
    }

    /// Ce que rapporterait la grille si tout tombait : les trois pronostics obligatoires,
    /// plus les paris bonus retenus.
    ///
    /// > Vérifié contre `screen-26-pronos-remplis.PNG` : Verstappen vainqueur (80) +
    /// > Antonelli podium (12) + Hamilton podium (21) + Albon bonus (5000) + Sainz bonus
    /// > (5000) = **10 113 pts**, exactement le total de la capture.
    private var total: Int {
        let obligatoires = EmplacementProno.allCases.reduce(0) { somme, slot in
            somme + (choix[slot].map { slot.marche.points(de: $0) } ?? 0)
        }
        return obligatoires + parisBonus.reduce(0) { $0 + $1.points }
    }

    /// Les trois emplacements obligatoires, dans l'ordre, tels que le récapitulatif les
    /// écrit. **Construits ici** : c'est cet écran qui tient la grille, et le
    /// récapitulatif qui la montre — lui laisser lire le dictionnaire des choix aurait
    /// donné deux endroits où l'ordre des lignes se décide.
    private var lignesObligatoires: [LigneRecap] {
        EmplacementProno.allCases.compactMap { slot in
            choix[slot].map {
                LigneRecap(marche: slot.marche, pilote: $0.nom,
                           points: slot.marche.points(de: $0), bonus: false)
            }
        }
    }

    /// Les pilotes qu'un emplacement ne peut plus proposer.
    ///
    /// **Un pilote ne peut pas occuper deux emplacements à la fois** : pronostiquer
    /// Verstappen vainqueur *et* Verstappen 2e du podium serait se contredire, et la
    /// validation du backend le refuserait. La feuille de choix le montre donc barré plutôt
    /// que de laisser composer une grille impossible puis de la rejeter.
    private func indisponibles(pour slot: EmplacementProno) -> Set<String> {
        Set(
            EmplacementProno.allCases
                .filter { $0 != slot }
                .compactMap { choix[$0]?.nom }
        )
    }
}

// MARK: - Les trois emplacements

/// Les trois emplacements obligatoires d'une grille.
///
/// **Ils portent leur marché**, plutôt que de laisser l'écran s'en souvenir : c'est lui qui
/// décide des points, de l'aplat et de l'encre douce, et un emplacement qui l'oublierait
/// irait chercher la mauvaise cote.
enum EmplacementProno: String, CaseIterable, Identifiable {

    case vainqueur
    case podium1
    case podium2

    var id: String { rawValue }

    var marche: MarcheCote {
        self == .vainqueur ? .vainqueur : .podium
    }

    /// Le champ d'un emplacement : la valeur à gauche, les points à droite, le chevron au
    /// bout. **Le choix, ou son absence, dit toujours la même chose au même endroit.**
    ///
    /// Contrastes mesurés, le champ vide étant la surface la plus sombre et donc celle qui
    /// contraint pour l'encre douce, le champ rempli la plus claire pour le blanc :
    ///
    /// | | vide (blanc 15 %) | rempli (blanc 22 %) |
    /// |---|---|---|
    /// | Vainqueur | `#932734` · encre douce **4,69:1** | `#9F404C` · blanc **6,34:1** |
    /// | Podium | `#4C6584` · encre douce **4,82:1** | `#607792` · blanc **4,61:1** |
    ///
    /// > **Les points d'un champ rempli sont en blanc plein, pas en encre douce.** Mesuré :
    /// > le blanc à 85 % sur `#607792` ne vaut que 3,84:1, sous le plancher de 4,5:1. Ce
    /// > sont la taille (13 contre 15) et la graisse qui distinguent alors les points du
    /// > nom, pas l'opacité. Le chevron, lui, est un **élément graphique** (plancher 3:1) et
    /// > garde l'encre douce, qui y tient 3,84:1.
    struct Champ: View {

        let marche: MarcheCote
        let choisi: PiloteMock?
        let points: Int?
        let onOuvrir: () -> Void

        var body: some View {
            Button(action: onOuvrir) {
                HStack(spacing: 12) {
                    Text(choisi?.nom ?? "Non sélectionné")
                        .font(.custom(choisi == nil ? "HelveticaNeue" : "HelveticaNeue-Medium",
                                      size: 15))
                        .foregroundColor(choisi == nil ? marche.encreDouce : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let points {
                        Text("\(points.enPoints) pts")
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
                // ombre** (§4.7). Elle ne casse jamais le plan de son bloc.
                .background(Color.white.opacity(choisi == nil ? 0.15 : 0.22))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
            }
            .buttonStyle(StyleAppui(.grandeSurface))
            .accessibilityLabel(marche.libelle)
            .accessibilityValue(choisi.map { "\($0.nom), \((points ?? 0).enPoints) points" } ?? "Non sélectionné")
            .accessibilityHint("Choisir un pilote")
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
                Text("Obligatoire")
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

// MARK: - Le compte à rebours

/// Les tuiles du compte à rebours, **mockées**. Un seul propriétaire : la saisie et le
/// récapitulatif affichent la même échéance, et deux tables tenues séparément auraient
/// fini par annoncer deux heures d'ouverture différentes à un écran d'intervalle.
///
/// Aucun `Timer` : l'écran ne calcule pas encore d'échéance, il en affiche une. Le calcul
/// viendra avec la date de la course (`docs/swift-app.md` §5).
enum EcheanceMock {

    static let tuiles: [(valeur: String, label: String)] = [
        ("04", "Jours"), ("14", "Heures"), ("34", "Minutes")
    ]

    /// Ce que l'assistance vocale lit à la place des trois tuiles.
    static let libelleAccessible =
        "4 jours, 14 heures et 34 minutes"
}

/// Le compte à rebours, et **ce qu'on pose éventuellement dessous** — le récapitulatif y
/// glisse son bouton « Modifier mes pronos », la saisie n'y met rien.
///
/// Trois tuiles plutôt qu'une ligne : « 4j 14h 34min » demande de lire une phrase pour en
/// extraire trois nombres, quand un chiffre posé sous son unité se lit d'un coup d'œil.
/// C'est déjà l'arbitrage des deux cases de l'accueil.
///
/// **La carte prend le beige du fond, pas le blanc des autres cartes** : sur une surface
/// blanche, trois aplats presque noirs se découperaient comme des trous. Sur le beige ils
/// se lisent comme des objets posés, et c'est ``ombreBloc()`` qui dit alors que la carte
/// est une carte.
///
/// > *Écart signalé.* La consigne du récapitulatif demandait un widget **blanc**. La
/// > capture `screen-28-recap-bas.PNG` montre le même beige qu'à la saisie, et c'est
/// > l'arbitrage ci-dessus : deux écrans qui montrent le même compte à rebours ne peuvent
/// > pas le poser sur deux surfaces différentes.
struct BlocEcheance<Pied: View>: View {

    private let libelle: String
    private let pied: Pied

    init(libelle: String, @ViewBuilder pied: () -> Pied) {
        self.libelle = libelle
        self.pied = pied()
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(libelle)
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)

            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(EcheanceMock.tuiles.enumerated()), id: \.offset) { rang, tuile in
                    if rang > 0 { deuxPoints }
                    TuileEcheance(valeur: tuile.valeur, label: tuile.label)
                }
            }

            pied
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.fondPrincipal)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()                                // rayon `bloc` → `ombreBloc` (§4.7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(libelle) \(EcheanceMock.libelleAccessible).")
    }

    /// Le deux-points entre deux tuiles. **Décoratif** : les unités sont écrites sous
    /// chaque tuile, il ne porte aucune information et reste hors de l'assistance vocale.
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
    init(libelle: String) {
        self.init(libelle: libelle) { EmptyView() }
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

// MARK: - Une carte de pari bonus

/// Un pari bonus retenu. **L'encre reste `#1A1A1A` sur l'ambre** : le blanc y tomberait à
/// 2,2:1, quand l'encre du design system y tient **7,86:1**.
private struct CarteParisBonus: View {

    let pari: PariBonus

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // `texte` à 75 % et non 70 % : mesuré, le 70 % de la version web compose
                // `#58421C` sur l'ambre, soit 4,28:1 — sous le plancher de 4,5:1. À 75 % il
                // donne `#4D3B1B` et 4,84:1.
                Text(pari.marche.libelle)
                    .font(.labelSm)
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundColor(.encreSecondaireAmbre)
                    .lineLimit(1)

                Text(pari.pilote)
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                    .foregroundColor(.texte)      // 7,86:1 sur l'ambre
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Noir à 15 % sur l'ambre — la surface forte du design system côté encre
            // foncée. L'encre `texte` y tient 6,4:1.
            Text("\(pari.points.enPoints) pts")
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .foregroundColor(.texte)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .lineLimit(1)

            // La rangée est **déjà ambre** : l'aplat ambre de la coche y disparaîtrait
            // dans le fond. `inverse` échange les deux encres, et tient le même 7,86:1.
            EtoileParisBonus(actif: true, inverse: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(Color.accent)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        .ombreCarte()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pari bonus, \(pari.marche.libelle), \(pari.pilote), \(pari.points) points")
    }
}

// MARK: - La feuille de choix

/// La liste des cotes d'un marché, en feuille modale.
///
/// **Une feuille et non un accordéon** : sur iOS, c'est la forme native d'un choix dans une
/// liste longue — vingt-deux pilotes tiennent mal sous un champ, et la feuille apporte
/// gratuitement le geste de fermeture par glissement et la poignée qui l'annonce.
///
/// Elle s'ouvre en hauteur moyenne : le bloc qu'on est en train de remplir reste visible
/// derrière, ce qui garde le lien entre le champ touché et la liste qui s'ouvre.
private struct FeuilleChoixPilote: View {

    let emplacement: EmplacementProno
    let choisi: PiloteMock?
    let indisponibles: Set<String>
    let onChoisir: (PiloteMock) -> Void

    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(GrilleMock.pilotes) { pilote in
                        ligne(pilote)
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
                    Button("Fermer") { fermer() }
                        .foregroundColor(.primaire)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func ligne(_ pilote: PiloteMock) -> some View {
        let indisponible = indisponibles.contains(pilote.nom)
        let actif = choisi?.nom == pilote.nom

        return Button {
            onChoisir(pilote)
        } label: {
            HStack(spacing: 12) {
                // Le liseré d'écurie, debout : c'est le même renfort que sur la carte de
                // cote, et il ne porte pas seul l'information — le nom est écrit à côté.
                if let teinte = pilote.couleurEcurie {
                    Capsule()
                        .fill(teinte.opacity(0.60))
                        .frame(width: 3, height: 22)
                        .accessibilityHidden(true)
                }

                Text(pilote.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.texte)      // 15,37:1 sur le blanc
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(emplacement.marche.points(de: pilote).enPoints) pts")
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
        .accessibilityValue(indisponible ? "Déjà choisi à un autre emplacement" : "")
    }
}

#Preview("Vide") {
    NavigationStack {
        PronosView(
            nomGrandPrix: "GP Azerbaïdjan",
            slugGrandPrix: "azerbaidjan",
            sousTitre: "Samedi 26 septembre · Départ 07h00",
            parisBonus: []
        )
        .etapesPronos(libelleRetour: "Accueil") { }
    }
}

#Preview("Deux paris bonus") {
    NavigationStack {
        PronosView(
            nomGrandPrix: "GP Azerbaïdjan",
            slugGrandPrix: "azerbaidjan",
            sousTitre: "Samedi 26 septembre · Départ 07h00",
            parisBonus: [
                PariBonus(marche: .vainqueur, pilote: "A.Albon", points: 5000),
                PariBonus(marche: .vainqueur, pilote: "C.Sainz Jr", points: 5000)
            ]
        )
        .etapesPronos(libelleRetour: "Accueil") { }
    }
}
