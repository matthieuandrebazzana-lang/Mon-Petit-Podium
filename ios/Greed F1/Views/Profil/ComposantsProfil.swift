import SwiftUI

// MARK: - La pastille d'identité

/// La photo du membre, ou son initiale sur un aplat.
///
/// **Un seul propriétaire pour les deux cas.** L'absence de photo n'est pas un état dégradé
/// mais l'état par défaut de tout compte : les deux branches vivent donc ensemble, et aucun
/// écran ne redécide ce qu'il montre quand `photo` est `nil`.
struct PastilleProfil: View {

    let pseudo: String

    var photo: URL?

    /// L'aplat de l'initiale. ``Color/primaireFonce`` sur son propre profil — l'aplat est
    /// déjà celui de la marque, et l'initiale s'y pose d'un ton plus sombre. Sur le profil
    /// d'un autre, **sa** teinte (``Color/teinteAvatar(pour:)``) : la même que son filet et
    /// son avatar au classement, et c'est elle qui le fait reconnaître d'un écran à l'autre.
    var fond: Color = .primaireFonce

    var taille: CGFloat = 64

    var body: some View {
        Group {
            if let photo {
                AsyncImage(url: photo) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initiale
                }
            } else {
                initiale
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(Circle())
    }

    /// Le blanc tient **≥ 10,35:1** sur les six teintes Pantone comme sur `#5A000C` : une
    /// initiale y est lisible sans exception.
    private var initiale: some View {
        fond.overlay {
            Text(pseudo.first.map { String($0).uppercased() } ?? "?")
                .font(.custom("HelveticaNeue-Medium", size: taille * 0.40625))
                .foregroundColor(.white)
        }
    }
}

// MARK: - L'en-tête d'un profil

/// L'aplat d'identité d'un pilote : sa pastille, son pseudo, la saison, sa voiture et son
/// numéro.
///
/// > **Une seule source pour les deux profils.** ``ProfilView`` et ``ProfilMembreView``
/// > montrent exactement la même chose ; deux en-têtes écrits séparément auraient divergé
/// > au premier ajustement de rembourrage, et le symptôme — un pseudo deux points plus bas
/// > d'un écran à l'autre — est de ceux qu'on ne voit jamais.
///
/// Seule la pastille change : elle est un **bouton** sur son propre profil, où elle porte
/// l'appareil photo, et un simple disque sur celui d'un autre. Elle arrive donc de
/// l'appelant.
struct EnteteProfil<Avatar: View>: View {

    let pseudo: String
    let livree: Livree
    let numero: String

    /// La photo découpée dans le cockpit de la voiture — celle de la pastille.
    var photo: URL?

    private let avatar: Avatar

    init(pseudo: String,
         livree: Livree,
         numero: String,
         photo: URL? = nil,
         @ViewBuilder avatar: () -> Avatar) {
        self.pseudo = pseudo
        self.livree = livree
        self.numero = numero
        self.photo = photo
        self.avatar = avatar()
    }

    var body: some View {
        HStack(spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(pseudo)
                    .font(.custom("HelveticaNeue-Medium", size: 22))
                    .tracking(-0.44)                      // -0,02 em, la règle des titres
                    .foregroundColor(.white)              // 10,88:1 sur #800111
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // **`encreSecondaire` (blanc 70 %), pas 60 %.** Mesuré : le blanc à 60 %
                // composité sur `primaire` donne #D9B3B8, soit 4,47:1 — sous le plancher
                // de 4,5:1 d'un texte ordinaire. À 70 % il y tient 5,75:1, pour un gris que
                // l'œil ne distingue pas du premier (`ios/CLAUDE.md` §3).
                Text("Saison 2026")
                    .font(.corpsSm)
                    .foregroundColor(.encreSecondaire)
            }

            Spacer(minLength: 8)

            VueVoiture(livree: livree,
                       numero: numero,
                       nom: pseudo,
                       photo: photo,
                       teintePilote: .primaire)
                .frame(height: 76)

            Text("#\(numero.isEmpty ? "—" : numero)")
                .font(.custom("HelveticaNeue-Medium", size: 26))
                .tracking(-0.65)
                .foregroundColor(.encreSecondaire)        // 5,75:1 sur #800111
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.primaire)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()
    }
}

// MARK: - Les quatre statistiques

/// Une tuile de statistique. `valeur` est **déjà mise en forme** — pourcentage, points,
/// tiret d'absence : la grille ne formate rien, sinon deux écrans l'arrondiraient chacun à
/// sa façon.
struct StatistiqueProfil: Identifiable, Equatable {
    let valeur: String
    let libelle: String
    var id: String { libelle }
}

/// Quatre tuiles, deux par rangée. **`LazyVGrid` à colonnes flexibles**, pas deux
/// `HStack` : les quatre gardent alors la même largeur quelle que soit la longueur du
/// libellé, et « Cote moy. tentée » ne fait pas grossir sa colonne.
struct GrilleStatistiques: View {

    let statistiques: [StatistiqueProfil]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(statistiques) { statistique in
                VStack(spacing: 4) {
                    Text(statistique.valeur)
                        .font(.score)
                        .tracking(Tracking.score)
                        .foregroundColor(.primaire)       // 12,60:1 sur le blanc
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    // **`grisSecondaire`, pas `texteDoux`** : sur le blanc, #999999 ne vaut
                    // que 2,85:1 — sous le plancher de 4,5:1. #6B6B6B y tient 5,33:1.
                    Text(statistique.libelle)
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.grisSecondaire)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
                .ombreCarte()
                .accessibilityElement(children: .combine)
            }
        }
    }
}
