import SwiftUI

/// Onglet **Accueil** — salutation, Grand Prix suivant, championnats, deux actions.
///
/// Référence visuelle : `Ressources/Screenshots/screen-04-accueil_haut.PNG`.
///
/// > **Les données sont mockées.** Aucun appel réseau : ``GrandPrixMock`` et
/// > ``ChampionnatMock`` sont des valeurs en dur, remplacées plus tard par le backend.
/// > Elles reprennent le contenu de la capture pour que le rendu se compare à elle.
struct AccueilView: View {

    @ObservedObject var viewModel: AuthViewModel

    /// Marge latérale commune à tous les blocs — la même que `LandingView`, sans quoi les
    /// deux écrans ne s'aligneraient pas au passage de l'un à l'autre.
    private let margeLaterale: CGFloat = 16

    // MARK: - Données mockées

    private let grandPrix = GrandPrixMock(
        nom: "GP Azerbaïdjan",
        date: "26 septembre 2026",
        joursAvantFermeture: 4
    )

    /// Les identifiants sont **stables** : c'est d'eux que se tire la teinte de la carte
    /// (`Color.teinteChampionnat(pour:)`), et un `UUID()` neuf à chaque lancement aurait
    /// fait changer la couleur d'un championnat d'une ouverture de l'app à la suivante.
    ///
    /// Ces deux-là sont choisis pour **tomber sur deux teintes différentes** (azurite et
    /// aubergine) : avec six teintes pour une empreinte, deux identifiants se heurtent une
    /// fois sur six, et un mock à deux cartes de la même couleur aurait laissé croire à un
    /// défaut plutôt qu'à un tirage.
    private let championnats: [ChampionnatMock] = [
        ChampionnatMock(id: "team-f1", nom: "Team F1", membres: 3, saison: 2026, rang: 1),
        ChampionnatMock(id: "les-bolides", nom: "Les Bolides", membres: 6, saison: 2026, rang: 2)
    ]

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    entete
                    Spacer().frame(height: 24)

                    widgetGrandPrix
                    Spacer().frame(height: 24)   // changement de sujet : 24 pt (§4.6)

                    titreSection("Mes championnats")
                    Spacer().frame(height: 12)   // espacement entre blocs : 12 pt (§4.6)

                    listeChampionnats
                    Spacer().frame(height: 24)

                    actions
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - En-tête

    /// Salutation à gauche, avatar à droite. L'avatar est un **élément d'affichage**, pas
    /// une commande : il n'a pas d'action dans cet écran, donc pas de plancher de 44 pt.
    /// Le pseudo est déjà lu par la salutation — l'avatar est masqué à VoiceOver.
    private var entete: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Bonjour, \(pseudoAffiche)")
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)        // 15,37:1 sur le beige
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            avatar
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Color.primaire)
            .frame(width: 42, height: 42)
            .overlay {
                Text(initiale)
                    .font(.custom("HelveticaNeue-Medium", size: 18))
                    .foregroundColor(.white)     // 10,88:1 sur #800111
            }
            .accessibilityHidden(true)
    }

    /// Repli sur « pilote » : une session peut être ouverte sans métadonnée `pseudo`
    /// (comptes créés avant que l'inscription ne la pose). Un écran ne montre jamais un
    /// trou à la place d'un nom.
    private var pseudoAffiche: String {
        viewModel.pseudo.isEmpty ? "pilote" : viewModel.pseudo
    }

    private var initiale: String {
        pseudoAffiche.first.map { String($0).uppercased() } ?? "?"
    }

    // MARK: - Widget du Grand Prix suivant

    /// Aplat de couleur au rayon `bloc` → ``ombreAplat()``, pas ``ombreBloc()`` : les
    /// ombres blanches ne se voient plus sous un aplat rouge (§4.7).
    private var widgetGrandPrix: some View {
        Button {
            // Destination à câbler : saisie des pronostics (`screen-25`).
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    badgeProchainGP
                    Spacer(minLength: 8)
                    Text(grandPrix.date)
                        .font(.custom("HelveticaNeue", size: 11))
                        .foregroundColor(.encreSecondaire)       // 5,75:1 sur #800111
                }

                Spacer().frame(height: 14)

                Text(grandPrix.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 22))
                    .tracking(-0.44)                             // −0,02em × 22
                    .foregroundColor(.white)                     // 10,88:1
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 6)

                Text("Pronos ouverts · Fermeture dans \(grandPrix.joursAvantFermeture) jours")
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.encreSecondaire)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 20)

                boutonPronostiquer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)                                          // padding intérieur : 16–20 pt
            .background(Color.primaire)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
            .ombreAplat()
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .accessibilityLabel(
            "Prochain Grand Prix, \(grandPrix.nom), le \(grandPrix.date). "
            + "Pronostics ouverts, fermeture dans \(grandPrix.joursAvantFermeture) jours."
        )
    }

    /// Le badge est une **pastille de matériau clair sur le rouge** : blanc à 20 %.
    /// Mesuré au simulateur, le blanc y tient **7,19:1** — le libellé de 10 pt passe son
    /// plancher de 4,5:1.
    private var badgeProchainGP: some View {
        Text("Prochain GP")
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.20))
            .clipShape(Capsule())
    }

    /// Surface posée *à l'intérieur* du bloc : rayon `champ`, donc **aucune ombre** (§4.7).
    /// 44 pt de haut, le plancher tactile iOS.
    private var boutonPronostiquer: some View {
        HStack(spacing: 6) {
            Text("Pronostiquer")
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .medium))
        }
        .font(.corpsSm)
        .foregroundColor(.primaire)                               // 10,88:1 sur le blanc
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }

    // MARK: - Championnats

    /// Titre de section. **L'encre est `grisSecondaire` (#6B6B6B), pas `texteDoux`** : sur
    /// le beige `#F5F0EB` le premier mesure **4,71:1**, le second 2,52:1 — sous le plancher
    /// de 4,5:1 d'un texte de 11 pt.
    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listeChampionnats: some View {
        VStack(spacing: 12) {
            ForEach(championnats) { championnat in
                Button {
                    // Destination à câbler : classement du championnat (`screen-13`).
                } label: {
                    CarteChampionnat(championnat: championnat)
                }
                .buttonStyle(StyleAppui(.grandeSurface))
            }
        }
    }

    // MARK: - Actions

    /// Deux colonnes de largeur égale : deux éléments en `maxWidth: .infinity` dans un
    /// `HStack` partagent l'espace à parts égales, sans grille à déclarer.
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                // Destination à câbler : créer un championnat (`screen-11`).
            } label: {
                LibelleAction(texte: "Créer un championnat", encre: .white)
                    .background(Color.primaire)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
                    .ombreAplat()
            }
            .buttonStyle(StyleAppui(.bouton))

            Button {
                // Destination à câbler : rejoindre par code à 6 caractères (`screen-12`).
            } label: {
                LibelleAction(texte: "Rejoindre", encre: .primaire)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
                    .ombreCarte()
            }
            .buttonStyle(StyleAppui(.bouton))
        }
    }
}

// MARK: - Carte d'un championnat

/// Une rangée de la liste : pastille colorée, nom, métadonnées, rang.
///
/// Sortie de ``AccueilView`` parce que la liste en monte plusieurs : un seul propriétaire
/// pour la forme de la carte, qui ne peut donc pas diverger d'une rangée à l'autre.
private struct CarteChampionnat: View {

    let championnat: ChampionnatMock

    var body: some View {
        HStack(spacing: 14) {
            pastille

            VStack(alignment: .leading, spacing: 3) {
                Text(championnat.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .tracking(-0.34)                              // −0,02em × 17
                    .foregroundColor(.texte)                      // 17,4:1 sur le blanc
                    .lineLimit(1)

                Text("\(championnat.membres) membres · Saison \(String(championnat.saison))")
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.grisSecondaire)             // 5,33:1 sur le blanc
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            rang
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
    }

    /// Pastille carrée au rayon `champ` — posée *à l'intérieur* de la carte, donc **sans
    /// ombre**. Elle est remplie de la **teinte Pantone du championnat**, tirée de son
    /// identifiant. L'initiale y est blanche : les six teintes tiennent de 10,35:1 à
    /// 18,12:1.
    private var pastille: some View {
        RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous)
            .fill(Color.teinteChampionnat(pour: championnat.id))
            .frame(width: 46, height: 46)
            .overlay {
                Text(championnat.initiale)
                    .font(.custom("HelveticaNeue-Medium", size: 20))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
    }

    /// Le rang et son total, comme sur la capture : le chiffre porte l'information, le
    /// total la met à l'échelle. Le `firstTextBaseline` aligne les deux corps de texte sur
    /// leur ligne de pied — sans lui, le petit flotterait au milieu du grand.
    private var rang: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(String(championnat.rang))
                .font(.custom("HelveticaNeue-Medium", size: 24))
                .tracking(-0.60)                                  // −0,025em × 24 : un chiffre
                .foregroundColor(.primaire)                       // 10,88:1 sur le blanc
                                                                  // n'a ni jambage ni hampe
            Text("/\(championnat.membres)")
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Classement : \(championnat.rang)ᵉ sur \(championnat.membres)")
    }
}

// MARK: - Libellé d'un bouton d'action

/// Un seul propriétaire pour la forme des deux boutons du bas : ils ne divergent pas.
private struct LibelleAction: View {

    let texte: String
    let encre: Color

    var body: some View {
        Text(texte)
            .font(.corpsSm)
            .foregroundColor(encre)
            .lineLimit(1)
            .minimumScaleFactor(0.85)   // « Créer un championnat » sur une demi-largeur d'iPhone SE
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 52)          // > 44 pt, contrainte tactile iOS
    }
}

// MARK: - Données mockées

/// Le Grand Prix suivant. Remplacé par le modèle du backend quand l'écran sera câblé ; la
/// date et le compte à rebours sont ici des textes, pas des `Date` — rien ne les calcule.
private struct GrandPrixMock {
    let nom: String
    let date: String
    let joursAvantFermeture: Int
}

/// Un championnat de la liste. Sa couleur n'est **pas** une donnée : elle se tire de `id`
/// par `Color.teinteChampionnat(pour:)`, jamais du rang dans la liste.
private struct ChampionnatMock: Identifiable {
    let id: String
    let nom: String
    let membres: Int
    let saison: Int
    let rang: Int

    var initiale: String {
        nom.first.map { String($0).uppercased() } ?? "?"
    }
}

#Preview {
    AccueilView(viewModel: AuthViewModel())
}
