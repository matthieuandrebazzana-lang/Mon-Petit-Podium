import SwiftUI

/// Les deux cartes que l'accueil et l'onglet **Championnats** affichent à l'identique :
/// la carte d'un championnat et la carte d'action (« Créer », « Rejoindre »).
///
/// > **Un seul propriétaire.** Les deux écrans posent la même carte ; recopiée dans
/// > chacun, elle aurait divergé au premier ajustement — un rembourrage ici, une opacité
/// > là — et le symptôme (deux cartes qui ne sont plus tout à fait les mêmes d'un onglet
/// > à l'autre) est de ceux qu'on ne voit pas. C'est la règle « une source unique par
/// > question » du `CLAUDE.md` de la racine.

// MARK: - Données mockées

/// Un championnat de la liste. Sa couleur n'est **pas** une donnée : elle se tire de `id`
/// par `Color.teinteChampionnat(pour:)`, jamais du rang dans la liste.
struct ChampionnatMock: Identifiable {
    let id: String
    let nom: String
    let membres: Int
    let rang: Int
    /// Les points du membre rapportés à ceux du leader, entre 0 et 1.
    let fraction: CGFloat
    /// Photo du championnat, dans le bucket Supabase Storage. `nil` tant que les écrans
    /// sont mockés : aucun appel réseau n'en part.
    var photo: URL? = nil
}

// MARK: - Carte d'un championnat

/// Un aplat de la teinte Pantone du championnat, son damier en filigrane, son rang en très
/// grand, et la jauge qui dit où en est le membre par rapport au leader.
///
/// La couleur vient de l'identifiant et **jamais du rang** : elle doit rester la même quand
/// le championnat change de place dans la liste, sans quoi deux voisins échangeraient leurs
/// couleurs à la première adhésion.
struct CarteChampionnat: View {

    let championnat: ChampionnatMock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(championnat.nom)
                        .font(.custom("HelveticaNeue-Medium", size: 20))
                        .tracking(-0.40)                          // −0,02em × 20
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("\(championnat.membres) \(championnat.membres > 1 ? "membres" : "membre") · Saison 2026")
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.encreSecondaire)        // ≥ 4,97:1 sur les six teintes
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // La photo du championnat, entre le nom et le rang. **Centrée sur la
                // rangée** alors que le nom et le rang s'alignent par le haut : un carré de
                // 56 pt calé sur la ligne de base d'un nom de 20 paraîtrait tomber. Absente,
                // elle ne réserve pas sa place — aucune gouttière ne subsiste.
                if let photo = championnat.photo {
                    AsyncImage(url: photo) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.15)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
                    .accessibilityHidden(true)
                }

                rang
            }

            jauge
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background {
            // Le damier d'abord, la lueur par-dessus : la lueur est un galbe de lumière qui
            // doit porter sur la surface FINIE, texture comprise.
            ZStack {
                Color.teinteChampionnat(pour: championnat.id)
                Damier(opacite: Materiau.damier)
                LueurHaute()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreAplat()
    }

    /// Le rang, en très grand et en retrait, suivi du total.
    ///
    /// **Format position/total** — « 1/3 » et non « 1 ». Un rang seul ne dit pas s'il est
    /// bon : premier sur trois et premier sur douze ne valent pas la même chose, et c'est
    /// l'effectif qui fait la différence.
    ///
    /// **Les deux nombres ne sont pas de la même taille, et c'est la hiérarchie qui le
    /// décide** : 48 pt pour la position, qui est la réponse, 24 pt pour le total, qui est
    /// le contexte. Deux chiffres de même corps se liraient comme une date.
    ///
    /// Le chiffre est à 80 % de blanc, et **c'est un plancher mesuré** : sur la plus claire
    /// des six teintes il y tient 3,2:1, juste au-dessus du plancher des grands textes. À
    /// 75 % il tombe à 2,99:1.
    private var rang: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(String(championnat.rang))
                    .font(.custom("HelveticaNeue-Medium", size: 48))
                    .tracking(-1.44)                              // −0,03em × 48
                    .foregroundColor(.white.opacity(0.80))
                Text("/\(championnat.membres)")
                    .font(.custom("HelveticaNeue-Medium", size: 24))
                    .tracking(-0.60)                              // −0,025em × 24
                    .foregroundColor(.encreSecondaire)
            }

            Text("Classement")
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encreSecondaire)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Classement : \(championnat.rang)\(championnat.rang == 1 ? "er" : "e") sur \(championnat.membres)"
        )
    }

    /// La jauge. Elle est **vide avant le premier Grand Prix**, quand tout le monde est
    /// encore à zéro — ce qui est exact, et bien plus honnête qu'une barre à moitié pleine
    /// posée là pour faire joli.
    private var jauge: some View {
        GeometryReader { geometrie in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.30))
                Capsule()
                    .fill(Color.white)
                    .frame(width: geometrie.size.width * championnat.fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Carte d'action

/// « Créer » et « Rejoindre » — la forme et la hauteur des cartes de championnat, sur une
/// surface blanche.
///
/// **Le logo vient de la planche `logo.svg`, jamais d'un symbole système** : les deux
/// dessins sont ceux de la marque, découpés par `scripts/decouper-icones.sh`, et c'est ce
/// qui fait qu'une carte d'action se reconnaît d'un écran à l'autre.
///
/// *Conséquence à connaître.* L'ambre `#E8A020` sur le blanc ne vaut que **2,2:1**, sous le
/// plancher de 3:1 d'un élément graphique porteur de sens. Ce n'est pas rédhibitoire ici :
/// le logo est **décoratif**, et c'est le titre, à 17 pt et 12,6:1, qui porte le sens. Si le
/// logo doit redevenir lisible à distance, c'est la teinte qu'il faut reprendre, pas la
/// composition.
struct CarteAction: View {

    let logo: String
    let encreLogo: Color
    let titre: String
    let sousTitre: String

    var body: some View {
        HStack(spacing: 14) {
            Image(logo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(encreLogo)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(titre)
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .tracking(-0.34)                              // −0,02em × 17
                    .foregroundColor(.texte)                      // 12,6:1 sous le damier
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // **Le marron `secondaire`, pas le gris `texteDoux`.** Sur le blanc ramené
                // à #F3F3F3 par le damier, `#999999` tombe sous le seuil AA quand le marron
                // y tient 9,52:1.
                Text(sousTitre)
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.secondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondaire)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background {
            ZStack {
                Color.surface
                Damier(opacite: Materiau.damierDoux)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Les deux actions, réunies

/// Les deux cartes d'action, dans l'ordre. Elles ferment aussi bien l'accueil que la liste
/// des championnats, et **c'est le même bloc** : deux listes écrites séparément auraient
/// fini par ne plus proposer les mêmes libellés.
///
/// **Deux rangées pleine largeur, jamais une grille à deux colonnes.** Elles adoptent la
/// hauteur et la forme des cartes de championnat : la liste se lit alors d'un seul
/// mouvement du pouce, du dernier championnat aux deux façons d'en avoir un de plus.
struct ActionsChampionnat: View {

    var body: some View {
        VStack(spacing: 10) {
            Button {
                // Destination à câbler : créer un championnat (`screen-11`).
            } label: {
                CarteAction(
                    logo: "icone-creer",
                    encreLogo: .primaire,
                    titre: "Créer un championnat",
                    sousTitre: "Lance ton championnat 2026"
                )
            }
            .buttonStyle(StyleAppui(.grandeSurface))

            Button {
                // Destination à câbler : rejoindre par code à 6 caractères (`screen-12`).
            } label: {
                CarteAction(
                    logo: "icone-rejoindre",
                    encreLogo: .ambreLogo,
                    titre: "Rejoindre un championnat",
                    sousTitre: "Entre un code à 6 caractères"
                )
            }
            .buttonStyle(StyleAppui(.grandeSurface))
        }
    }
}
