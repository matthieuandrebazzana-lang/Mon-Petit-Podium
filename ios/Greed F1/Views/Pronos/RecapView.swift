import SwiftUI

// MARK: - Une ligne du récapitulatif

/// Un pronostic tel que le récapitulatif l'écrit : **le marché, le pilote, les points**, et
/// s'il est bonus ou obligatoire.
///
/// **Une seule forme pour les deux sections**, et non deux structures jumelles : les deux
/// rangées se composent exactement pareil, seul l'aplat de l'étiquette change. Deux types
/// distincts auraient divergé au premier ajustement de rembourrage.
struct LigneRecap: Identifiable, Hashable {

    let marche: MarcheCote
    let pilote: String
    let points: Int
    let bonus: Bool

    var id: String { "\(bonus ? "bonus" : "obligatoire"):\(marche.rawValue):\(pilote)" }

    /// L'aplat de l'étiquette de points. L'ambre des paris bonus, sinon celui du marché —
    /// rouge pour le vainqueur, bleu ardoise pour le podium, comme à la saisie.
    var aplat: Color { bonus ? .accent : marche.aplat }

    /// L'encre de cette étiquette. **L'ambre n'accepte que ``Color/texte``** (7,86:1) ; le
    /// blanc y tomberait à 2,2:1. Sur les deux autres aplats, le blanc tient 10,88:1 et
    /// 11,04:1.
    var encre: Color { bonus ? .texte : .white }
}

// MARK: - L'écran

/// **Récapitulatif** — ce que la grille vaut une fois validée, et de quoi revenir la
/// corriger.
///
/// Références visuelles : `Ressources/Screenshots/screen-27-recap-haut.PNG` et
/// `screen-28-recap-bas.PNG`.
///
/// C'est le terminus des trois écrans de pronostics : ``CotesView`` met les paris bonus de
/// côté, ``PronosView`` remplit les trois emplacements obligatoires, et celui-ci ne saisit
/// plus rien — il montre. Tout ce qui s'y modifie repasse par l'écran précédent, et le
/// bouton « Modifier mes pronos » y ramène : **un seul endroit où l'on change d'avis**.
///
/// > **Les données sont mockées.** La grille vient de ``PronosView``, le compte à rebours
/// > d'``EcheanceMock``. Rien n'est envoyé : la route `POST /pronostics` sera branchée à la
/// > passe API (`docs/swift-app.md` §5) — d'où le bandeau « Pronos enregistrés ! », qui
/// > annonce pour l'instant un enregistrement qui n'a pas eu lieu.
struct RecapView: View {

    let nomGrandPrix: String
    let slugGrandPrix: String
    let sousTitre: String

    /// Les trois emplacements obligatoires, dans l'ordre où ``PronosView`` les a remplis.
    let obligatoires: [LigneRecap]

    /// Les paris bonus retenus au tableau des cotes.
    let parisBonus: [PariBonus]

    /// Ce que le bouton de retour **annonce** — « Accueil » depuis l'accueil, le nom du
    /// championnat depuis un championnat. Les deux entrées du parcours ne ramènent pas au
    /// même écran (``EtapePronos``).
    let libelleRetour: String

    /// Ce qu'il **fait** : vider le chemin du parcours. Le mot et l'action arrivent
    /// ensemble, d'un seul appelant, et ne peuvent donc pas se contredire.
    let retour: () -> Void

    /// Ce qui ferme **ce seul écran**, et ramène donc à la saisie.
    @Environment(\.dismiss) private var fermer

    private let margeLaterale: CGFloat = 16

    /// Rembourrage de la carte de résumé. Mesuré sur `screen-28` : 48 px à 3×.
    private let rembourrageCarte: CGFloat = 16

    private var lignesBonus: [LigneRecap] {
        parisBonus.map {
            LigneRecap(marche: $0.marche, pilote: $0.pilote, points: $0.points, bonus: true)
        }
    }

    /// Ce que la grille rapporterait si tout tombait. **La même addition qu'à la saisie** —
    /// les trois obligatoires plus les paris bonus — et elle porte ici le nom que lui donne
    /// la capture : « total de points disponibles ».
    private var total: Int {
        (obligatoires + lignesBonus).reduce(0) { $0 + $1.points }
    }

    var body: some View {
        // Le `GeometryReader` ne sert qu'à **une** mesure : la hauteur de la barre d'état.
        // Le drapeau est un fond perdu qui part du haut de l'écran, et le rembourrage haut
        // de son contenu est exactement cette valeur — la deviner aurait posé le bouton de
        // retour sur l'heure d'un appareil et trop bas sur un autre.
        GeometryReader { proxy in
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        EnteteDrapeau(
                            nom: nomGrandPrix,
                            sousTitre: sousTitre,
                            slug: slugGrandPrix,
                            retrait: proxy.safeAreaInsets.top,
                            libelleRetour: libelleRetour,
                            retour: retour
                        )

                        Spacer().frame(height: 16)
                        bandeauConfirmation

                        Spacer().frame(height: 12)   // espacement entre blocs (§4.6)
                        blocEcheance

                        Spacer().frame(height: 12)
                        carteResume
                    }
                    .padding(.bottom, 24)
                }
                // Le contenu part du **haut de l'écran**, pas du bas de la barre d'état :
                // c'est ce qui laisse le drapeau remonter jusque sous l'heure. Le bas garde
                // sa zone sûre — rien ne doit courir sous l'indicateur d'accueil.
                .ignoresSafeArea(edges: .top)
            }
        }
        // > *Écart signalé (`CLAUDE.md` §6).* **La barre de navigation native est retirée,
        // > et le retour vit dans l'en-tête.** Trois raisons, toutes mesurées au
        // > simulateur :
        // >
        // > 1. Le bouton natif prend son libellé du titre de l'écran précédent, qui est
        // >    vide : il afficherait « Retour », et il ne remonterait que d'un cran — la
        // >    saisie —, là où ce bouton-ci vide le parcours entier.
        // > 2. Sous iOS 26, un élément de barre reçoit d'office sa capsule de verre, qui
        // >    se pose en clair sur le drapeau et n'est ni dans la capture ni dans le
        // >    design system.
        // > 3. Barre visible, la zone sûre haute l'englobe : le drapeau commencerait 44 pt
        // >    plus bas, ou passerait dessous et laisserait l'heure du système en encre
        // >    sombre à **2,31:1** sur le bleu d'Azerbaïdjan. Barre masquée, la zone sûre
        // >    se réduit à la barre d'état, le drapeau commence pile dessous — c'est ce
        // >    que montre `screen-27` — et l'heure garde le beige de l'app.
        // >
        // > Masquer la barre, contrairement à `navigationBarBackButtonHidden`, **préserve
        // > le retour par glissement**. Le prix est que le bouton défile avec l'en-tête ;
        // > le geste reste, lui, disponible partout.
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Le bandeau de confirmation

    /// La confirmation, et **ce qu'elle autorise encore** : une grille validée n'est pas
    /// figée. La seconde ligne n'est pas une politesse, c'est la règle — les pronostics se
    /// modifient jusqu'au départ (`docs/metier.md`), et sans elle le bouton « Modifier mes
    /// pronos » juste en dessous aurait l'air d'une sortie de secours.
    ///
    /// > **Le sous-titre est en blanc plein, pas à 70 %.** Mesuré sur le vert sauge : le
    /// > blanc y tient **4,86:1** — et c'est déjà le maximum. À 70 % il tombe à **3,59:1**,
    /// > sous le plancher de 4,5:1 d'un texte de 13 pt. La hiérarchie passe donc par la
    /// > taille et la graisse (17/500 contre 13/400), jamais par l'opacité.
    private var bandeauConfirmation: some View {
        HStack(spacing: 14) {
            coche

            VStack(alignment: .leading, spacing: 2) {
                Text("Pronos enregistrés !")
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundColor(.white)          // 4,86:1 sur le vert sauge

                Text("Tu peux les modifier jusqu'au départ.")
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.vertSauge
                LueurHaute()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .ombreAplat()                                 // aplat de couleur (§4.7)
        .padding(.horizontal, margeLaterale)
        .accessibilityElement(children: .combine)
    }

    /// La coche, posée sur un disque de **blanc à 20 %**. C'est la surface claire du design
    /// system, et le blanc y tient **3,32:1** — au-dessus du plancher de 3:1 d'un élément
    /// graphique porteur de sens, qu'elle est : elle dit que c'est parti.
    private var coche: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 46, height: 46)
            .background(Color.white.opacity(0.20))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    // MARK: - Le compte à rebours

    /// Le **même** bloc qu'à la saisie, avec le bouton de correction glissé dessous. Deux
    /// blocs écrits séparément auraient fini par afficher deux échéances différentes à un
    /// écran d'intervalle.
    private var blocEcheance: some View {
        BlocEcheance(libelle: "Ouverture dans") {
            boutonModifier
        }
        .padding(.horizontal, margeLaterale)
    }

    /// **Il ferme cet écran, il n'en pousse pas un autre.** La saisie est juste dessous
    /// dans la pile : la rouvrir par-dessus aurait empilé deux copies du même écran, et le
    /// retour serait passé deux fois par le récapitulatif.
    private var boutonModifier: some View {
        Button {
            fermer()
        } label: {
            Text("Modifier mes pronos")
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .foregroundColor(.white)              // 10,88:1 sur #800111
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
        .padding(.top, 4)
    }

    // MARK: - La carte de résumé

    /// Ce qui a été pronostiqué, marché par marché, et ce que ça vaut en tout.
    ///
    /// > **Pas de séparateur entre deux rangées**, contrairement à ce que la consigne
    /// > demandait : `screen-28-recap-bas.PNG` n'en montre qu'aux **ruptures de section**
    /// > — avant « Bonus » et avant le total. Un filet toutes les trois lignes découpe ce
    /// > qui doit se lire comme une liste ; posé aux deux endroits où le sujet change, il
    /// > dit quelque chose.
    private var carteResume: some View {
        VStack(alignment: .leading, spacing: 0) {
            titreSection("Obligatoires")

            Spacer().frame(height: 14)
            rangees(obligatoires)

            if !lignesBonus.isEmpty {
                Spacer().frame(height: 20)
                separateur
                Spacer().frame(height: 16)
                titreSection("Bonus")

                Spacer().frame(height: 14)
                rangees(lignesBonus)
            }

            Spacer().frame(height: 20)
            separateur
            Spacer().frame(height: 16)
            rangeeTotal
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(rembourrageCarte)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()                                 // rayon `carte` → `ombreCarte` (§4.7)
        .padding(.horizontal, margeLaterale)
    }

    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)         // 5,33:1 sur le blanc
    }

    private func rangees(_ lignes: [LigneRecap]) -> some View {
        VStack(spacing: 18) {
            ForEach(lignes) { RangeeRecap(ligne: $0) }
        }
    }

    /// Le filet des ruptures de section. **Il n'a pas de propriétaire dans le design
    /// system** — c'est le premier écran qui en emploie un ; le jour où un second en a
    /// besoin, il montera dans `Config/Formes.swift` plutôt que d'être recopié ici.
    private var separateur: some View {
        Rectangle()
            .fill(Color.secondaire.opacity(0.12))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    /// Le total, en gros. **C'est le chiffre qu'on vient chercher**, et il est écrit dans
    /// l'encre de la marque plutôt qu'en noir : le reste de la carte est une liste, lui est
    /// une conclusion.
    ///
    /// « Disponibles » n'est pas décoratif : ces points ne sont **pas acquis**, ils sont ce
    /// que la grille rapporterait si tout tombait.
    private var rangeeTotal: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Total de points disponibles")
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 140, alignment: .leading)

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(total.enPoints)
                    .font(.custom("HelveticaNeue-Medium", size: 40))
                    .tracking(-1.00)                  // −0,025em × 40
                Text("pts")
                    .font(.custom("HelveticaNeue-Medium", size: 20))
            }
            .foregroundColor(.primaire)               // 10,88:1 sur le blanc
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total de points disponibles, \(total) points")
    }
}

// MARK: - Une rangée

/// Le marché au-dessus, le pilote en dessous, les points au bout.
///
/// **Le marché est écrit au-dessus de chaque nom et non une fois par groupe** : le podium
/// occupe deux rangées, et un titre unique aurait laissé croire que la seconde dépend de la
/// première. Chaque ligne se lit seule.
private struct RangeeRecap: View {

    let ligne: LigneRecap

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ligne.marche.libelleCourt)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire) // 5,33:1 sur le blanc
                    .lineLimit(1)

                Text(ligne.pilote)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.texte)          // 15,37:1 sur le blanc
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(ligne.points.enPoints) pts")
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .foregroundColor(ligne.encre)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ligne.aplat)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ligne.bonus ? "Pari bonus, " : "")\(ligne.marche.libelleCourt), "
            + "\(ligne.pilote), \(ligne.points) points"
        )
    }
}

// MARK: - L'en-tête

/// Le drapeau du pays hôte en fond perdu, le nom du Grand Prix et son horaire dessus.
///
/// **La pile de calques est celle de l'accueil et du calendrier, et elle ne se défait
/// pas** : le drapeau tout en bas · ``LueurHaute`` · le voile calculé par
/// ``ApparenceDrapeau`` · l'assombrissement uniforme de 15 % · le contenu seul. Tout ce qui
/// éclaircit passe SOUS le voile, sans quoi la garantie de 3:1 n'en est plus une.
///
/// > *Écart signalé (`CLAUDE.md` §6).* Sur `screen-27-recap-haut.PNG` le drapeau s'arrête
/// > sous l'heure, qui reste sur le beige de l'app. Ici il **monte jusqu'en haut de
/// > l'écran** : c'est la forme iOS d'un en-tête pleine largeur, et une bande beige de
/// > 60 pt au-dessus d'un fond perdu se lirait comme un calage raté. La barre de navigation
/// > passe en encre claire pour rester lisible dessus.
private struct EnteteDrapeau: View {

    let nom: String
    let sousTitre: String
    let slug: String

    /// La zone sûre haute. La barre de navigation étant masquée, c'est **la seule barre
    /// d'état** : le drapeau commence donc pile sous l'heure, comme sur `screen-27`.
    let retrait: CGFloat

    let libelleRetour: String
    let retour: () -> Void

    private var apparence: ApparenceDrapeau? { ApparenceDrapeau.pour(slug: slug) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                boutonAccueil
                Spacer(minLength: 0)
            }

            Spacer().frame(height: 28)

            // 28 pt, avec le crénage négatif qu'/apple-design §15 impose au-delà de 24 :
            // sans lui, les lettres d'un titre s'éloignent à mesure qu'il grandit.
            Text(nom)
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .ombrePortee(apparence?.ombreNom ?? false)

            Spacer().frame(height: 8)

            Text(sousTitre)
                .font(.custom(encreDouceGrasse ? "HelveticaNeue-Medium" : "HelveticaNeue",
                              size: 13))
                .foregroundColor(encreDouce)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .ombrePortee(apparence?.ombreNom ?? false)
                .accessibilityLabel(sousTitre)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, retrait + 4)
        .padding(.bottom, 36)
        .background { fond }
    }

    /// **44 × 44 pt malgré un chevron de 17** : la zone tactile est posée par le
    /// `contentShape`, sans quoi seuls les glyphes seraient touchables.
    ///
    /// L'ombre portée est **inconditionnelle**, comme celle des cartes du calendrier : le
    /// libellé est à 17 pt — un texte ordinaire, donc un plancher de 4,5:1 — quand le voile
    /// d'``ApparenceDrapeau`` n'en garantit que 3 sur la bande la plus claire. L'ombre lui
    /// rend son contour là où le blanc du drapeau le lui prend.
    private var boutonAccueil: some View {
        Button(action: retour) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                Text(libelleRetour)
                    .font(.custom("HelveticaNeue", size: 17))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(libelleRetour)
        .accessibilityHint("Quitter le récapitulatif")
    }

    @ViewBuilder private var fond: some View {
        if let apparence {
            ZStack {
                // **`scaledToFill` et non `scaledToFit`** : le drapeau couvre toute la
                // bande, rogné sur son plus grand côté, jamais déformé ni cerné de vide.
                Image("flag-\(slug)")
                    .resizable()
                    .scaledToFill()

                LueurHaute()
                Color.black.opacity(apparence.voile)
                Color.black.opacity(0.15)
            }
            // Le drapeau est plus grand que la bande : sans ce rognage, `scaledToFill` le
            // laisserait déborder par-dessus le bandeau de confirmation.
            .clipped()
        } else {
            // Pays hors table : l'aplat de la marque, et aucun assombrissement — il n'a ni
            // bande ni rupture à corriger, le voiler ne ferait que l'éteindre.
            ZStack {
                Color.primaire
                LueurHaute()
            }
        }
    }

    private var encreDouce: Color { apparence?.encreDouce ?? .encreSecondaire }
    private var encreDouceGrasse: Bool { apparence?.encreDouceGrasse ?? false }
}

/// L'ombre portée du texte posé sur un drapeau à plusieurs bandes — la même valeur qu'à
/// l'accueil et au calendrier, pour que les trois écrans ne divergent pas.
private extension View {
    @ViewBuilder func ombrePortee(_ active: Bool) -> some View {
        if active {
            self.shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
        } else {
            self
        }
    }
}

#Preview("Grille complète") {
    NavigationStack {
        RecapView(
            nomGrandPrix: "GP Azerbaïdjan",
            slugGrandPrix: "azerbaidjan",
            sousTitre: "Samedi 26 septembre · Départ 07h00",
            obligatoires: [
                LigneRecap(marche: .vainqueur, pilote: "M.Verstappen", points: 80, bonus: false),
                LigneRecap(marche: .podium, pilote: "AK.Antonelli", points: 12, bonus: false),
                LigneRecap(marche: .podium, pilote: "L.Hamilton", points: 21, bonus: false)
            ],
            parisBonus: [
                PariBonus(marche: .vainqueur, pilote: "A.Albon", points: 5000),
                PariBonus(marche: .vainqueur, pilote: "C.Sainz Jr", points: 5000)
            ],
            libelleRetour: "Accueil",
            retour: { }
        )
    }
}

#Preview("Sans pari bonus") {
    NavigationStack {
        RecapView(
            nomGrandPrix: "GP Pays-Bas",
            slugGrandPrix: "pays-bas",
            sousTitre: "Dimanche 30 août · Départ 15h00",
            obligatoires: [
                LigneRecap(marche: .vainqueur, pilote: "L.Norris", points: 32, bonus: false),
                LigneRecap(marche: .podium, pilote: "M.Verstappen", points: 8, bonus: false),
                LigneRecap(marche: .podium, pilote: "C.Leclerc", points: 15, bonus: false)
            ],
            parisBonus: [],
            libelleRetour: "Accueil",
            retour: { }
        )
    }
}
