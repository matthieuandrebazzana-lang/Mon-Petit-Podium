import SwiftUI

/// **L'accueil de première connexion** — cinq pages à faire défiler, posées en calque sur
/// ``BarreNavigation`` (``Tutoriel``).
///
/// - **« Passer » est sur toutes les pages**, en haut à droite, à la place où iOS met la
///   sortie d'un écran présenté : on ne reste jamais enfermé (wayfinding, /apple-design §16).
/// - **La dernière page finit sur les deux façons d'avoir un championnat** ; l'une ou
///   l'autre ferme le calque et pousse l'écran correspondant sur l'onglet Accueil.
/// - **Les visuels sont les composants de l'app**, jamais une image ajoutée : cartes
///   d'action, étoile des favoris, voitures, sol de la piste, damier.
/// - **Aucun nombre n'est une cote** : les exemples sont en points (`formaterPoints`).
///
/// Mouvement : le défilement est celui du système, au doigt. « Suivant » glisse sur
/// ``Mouvement/glissement`` — instantané sous mouvement réduit ; le calque sort en fondu
/// (``BarreNavigation``), rien ne se déplace.
struct AccueilTutorielView: View {

    /// La voiture du compte, pour les pages Voiture et Piste. `nil` tant que le profil
    /// n'est pas lu : la livrée par défaut tient alors la place.
    let profil: Profil?

    /// Ferme le calque — avec, ou non, une action à lancer.
    let terminer: (ActionTutoriel?) -> Void

    @State private var page = 0

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private let margeLaterale: CGFloat = 16

    private var derniere: Bool { page == PageTutoriel.allCases.count - 1 }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(t("tutoriel.passer")) { terminer(nil) }
                        .font(.segment)
                        .foregroundColor(.encrePrimaire)       // 9,61:1 · sombre 6,03:1
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .buttonStyle(StyleAppui(.bouton))
                }
                .padding(.horizontal, 8)

                TabView(selection: $page) {
                    ForEach(PageTutoriel.allCases) { contenu in
                        PageTutorielView(page: contenu, profil: profil)
                            .tag(contenu.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pagination

                Spacer().frame(height: 20)

                actions
                    .padding(.horizontal, margeLaterale)
            }
            .padding(.bottom, 8)
        }
        // VoiceOver reste dans le calque : la barre d'onglets dessous n'existe pas pour lui.
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Pagination

    private var pagination: some View {
        HStack(spacing: 8) {
            ForEach(PageTutoriel.allCases) { contenu in
                Capsule()
                    .fill(contenu.rawValue == page ? Color.encrePrimaire
                                                   : Color.secondaire.opacity(0.25))
                    .frame(width: contenu.rawValue == page ? 20 : 8, height: 8)
            }
        }
        .animation(mouvementReduit ? nil : Mouvement.glissement, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("tutoriel.a11y.etape", page + 1, PageTutoriel.allCases.count))
    }

    // MARK: - Actions

    /// **Une hauteur fixe pour les deux états** : passer de « Suivant » aux deux actions
    /// ne fait pas sauter la page au-dessus.
    private var actions: some View {
        VStack(spacing: 10) {
            if derniere {
                Button { terminer(.creer) } label: {
                    Text(t("championnat.creer"))
                        .habillageBoutonPrincipal(actif: true)
                }
                .buttonStyle(StyleAppui(.bouton))

                Button { terminer(.rejoindre) } label: {
                    Text(t("championnat.rejoindre"))
                        .font(.custom("HelveticaNeue-Medium", size: 18))
                        .foregroundColor(.encrePrimaire)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.surface,
                                    in: RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
                        .ombreCarte()
                }
                .buttonStyle(StyleAppui(.bouton))
            } else {
                Spacer(minLength: 0)
                Button {
                    withAnimation(mouvementReduit ? nil : Mouvement.glissement) { page += 1 }
                } label: {
                    Text(t("tutoriel.suivant"))
                        .habillageBoutonPrincipal(actif: true)
                }
                .buttonStyle(StyleAppui(.bouton))
            }
        }
        .frame(height: 122, alignment: .bottom)
    }
}

// MARK: - Les cinq pages

enum PageTutoriel: Int, CaseIterable, Identifiable {
    case championnats, pronos, favoris, voiture, piste

    var id: Int { rawValue }

    var cleTitre: String { "tutoriel.\(cle).titre" }
    var cleCorps: String { "tutoriel.\(cle).corps" }

    /// Une seconde phrase, plus discrète — les pronos seulement.
    var cleNote: String? { self == .pronos ? "tutoriel.pronos.note" : nil }

    private var cle: String {
        switch self {
        case .championnats: return "championnats"
        case .pronos:       return "pronos"
        case .favoris:      return "favoris"
        case .voiture:      return "voiture"
        case .piste:        return "piste"
        }
    }
}

private struct PageTutorielView: View {

    let page: PageTutoriel
    let profil: Profil?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                visuel
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .background {
                        ZStack {
                            Color.surface
                            Damier(opacite: Materiau.damierDoux)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
                    .ombreBloc()
                    .accessibilityHidden(true)

                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 10) {
                    Text(t(page.cleTitre))
                        .font(.titre)
                        .tracking(Tracking.titre)
                        .foregroundColor(.texte)               // 15,37:1 · sombre 17,01:1
                        .accessibilityAddTraits(.isHeader)

                    Text(corps)
                        .font(.corps)
                        .foregroundColor(.secondaire)          // 9,32:1 · sombre 14,3:1

                    if let note = page.cleNote {
                        Text(t(note))
                            .font(.corpsSm)
                            .foregroundColor(.grisSecondaire)  // 4,71:1 · sombre 7,2:1
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    /// Le corps des favoris nomme l'écran des cotes par son titre, lu à sa source.
    private var corps: String {
        page == .favoris ? t(page.cleCorps, t("cotes.titre")) : t(page.cleCorps)
    }

    @ViewBuilder private var visuel: some View {
        switch page {
        case .championnats: VisuelChampionnats()
        case .pronos:       VisuelPronos()
        case .favoris:      VisuelFavoris()
        case .voiture:      VisuelVoiture(profil: profil)
        case .piste:        VisuelPiste(profil: profil)
        }
    }
}

// MARK: - Visuels

/// Les deux logos d'action, et un code d'invitation dans ses six cases.
private struct VisuelChampionnats: View {

    /// Un exemple de code — six caractères, sans séparateur (`metier.md` §5).
    private let code = Array("F1X7K2")

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 40) {
                logo("icone-creer", encre: .encrePrimaire)
                logo("icone-rejoindre", encre: .accent)
            }
            HStack(spacing: 8) {
                ForEach(code.indices, id: \.self) { rang in
                    Text(String(code[rang]))
                        .font(.custom("HelveticaNeue-Medium", size: 24))
                        .foregroundColor(.texte)
                        .frame(width: 40, height: 52)
                        .background(Color.fondPrincipal,
                                    in: RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
                }
            }
        }
    }

    private func logo(_ nom: String, encre: Color) -> some View {
        Image(nom)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 64)
            .foregroundColor(encre)
    }
}

/// Trois pronostics aux teintes du récapitulatif — vainqueur, podium, bonus —, en points.
private struct VisuelPronos: View {
    var body: some View {
        VStack(spacing: 10) {
            LigneExemple(libelle: t("marche.vainqueur"), teinte: .teinteVainqueur, points: 28)
            LigneExemple(libelle: t("marche.podium"), teinte: .teintePodium, points: 15)
            LigneExemple(libelle: t("recap.bonus"), teinte: .teinteBonus, points: 95)
        }
        .padding(.horizontal, 24)
    }
}

/// Une cote épinglée, une autre pas : l'étoile grise et la pastille de favori.
private struct VisuelFavoris: View {
    var body: some View {
        VStack(spacing: 10) {
            ligne(points: 95, actif: false)
            ligne(points: 42, actif: true)
            ligne(points: 61, actif: false)
        }
        .padding(.horizontal, 24)
    }

    private func ligne(points: Int, actif: Bool) -> some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(Color.secondaire.opacity(0.15))
                .frame(width: 110, height: 10)
            Spacer(minLength: 0)
            Text(formaterPoints(points))
                .font(.segment)
                .foregroundColor(.texte)
            EtoileParisBonus(actif: actif)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.fondPrincipal,
                    in: RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }
}

/// La voiture du compte, entre deux livrées d'écurie.
private struct VisuelVoiture: View {
    let profil: Profil?

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            voiture(Livree(mode: .ecurie, ecurie: "ferrari"), hauteur: 150)
            voiture(profil?.livree ?? Livree(), numero: numero, nom: profil?.pseudo ?? "",
                    hauteur: 200)
            voiture(Livree(mode: .ecurie, ecurie: "mclaren"), hauteur: 150)
        }
    }

    private var numero: String { profil?.numero.map(String.init) ?? "" }

    private func voiture(_ livree: Livree, numero: String = "", nom: String = "",
                         hauteur: CGFloat) -> some View {
        VueVoiture(livree: livree, numero: numero, nom: nom)
            .frame(width: hauteur * VueVoiture.rapport, height: hauteur)
    }
}

/// Le sol de la piste, et trois voitures échelonnées — la tienne en tête.
private struct VisuelPiste: View {
    let profil: Profil?

    var body: some View {
        ZStack {
            // Le sol de ``SolPiste``, sa planche et ses encres lues à leur source.
            VuePlanche(planche: "vue_piste", fenetre: SolPiste.planche,
                       substitutions: SolPiste.substitutions, etiree: true)

            GeometryReader { geometrie in
                let l = geometrie.size.width
                let h = geometrie.size.height
                voiture(profil?.livree ?? Livree(), nom: profil?.pseudo ?? "")
                    .position(x: l * 0.5, y: h * 0.28)
                voiture(Livree(mode: .ecurie, ecurie: "williams"))
                    .position(x: l * 0.36, y: h * 0.62)
                voiture(Livree(mode: .ecurie, ecurie: "aston-martin"))
                    .position(x: l * 0.64, y: h * 0.74)
            }
        }
    }

    private func voiture(_ livree: Livree, nom: String = "") -> some View {
        VueVoiture(livree: livree, nom: nom)
            .frame(width: 84 * VueVoiture.rapport, height: 84)
    }
}

/// Une ligne de pronostic : l'étiquette à la teinte de sa catégorie, un nom esquissé, les
/// points — la forme des cartes du récapitulatif (``Color/opaciteTeinteCarte``, seconde
/// encre ``Color/encreSurTeinte``).
private struct LigneExemple: View {
    let libelle: String
    let teinte: Color
    let points: Int

    var body: some View {
        HStack(spacing: 12) {
            // **La catégorie se lit au filet, le texte reste à l'encre de la carte** : à
            // 11 pt, les teintes ne tiennent pas 4,5:1 sur leur propre fond teinté (bonus
            // clair 4,16:1, vainqueur sombre 3,80:1). Le filet, élément graphique, en
            // demande 3:1 — 3,68:1 au plus bas.
            Capsule()
                .fill(teinte)
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(libelle)
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.encreSurTeinte)
                Capsule()
                    .fill(Color.secondaire.opacity(0.15))
                    .frame(width: 120, height: 10)
            }
            Spacer(minLength: 0)
            Text(formaterPoints(points))
                .font(.segment)
                .foregroundColor(.texte)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background {
            ZStack {
                Color.surface
                teinte.opacity(Color.opaciteTeinteCarte)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }
}
