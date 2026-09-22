import SwiftUI

/// Onglet **Profil** — identité, statistiques, livrée, déconnexion.
///
/// Références visuelles : `Ressources/Screenshots/screen-20-mon-profil-haut.PNG` et
/// `screen-21-mon-profil-bas.PNG`, écran par écran.
///
/// > **Les données sont mockées.** Aucun appel réseau : les quatre statistiques et la
/// > livrée sont des valeurs en dur, reprises des captures pour que le rendu se compare à
/// > elles. Seuls le pseudo, la photo et la déconnexion passent par ``AuthViewModel``.
///
/// **La voiture et les onze casques sont découpés des planches** (`ios/CLAUDE.md` §3) :
/// rien n'est redessiné en SwiftUI. ``VueVoiture`` lit `voitures_perso.svg` et y substitue
/// les deux couleurs du membre, exactement comme la version web substitue `cls-6` et
/// `cls-14`.
struct ProfilView: View {

    @ObservedObject var viewModel: AuthViewModel

    /// Marge latérale commune à tous les écrans — la même que `AccueilView`, sans quoi les
    /// deux ne s'aligneraient pas au passage de l'un à l'autre.
    private let margeLaterale: CGFloat = 16

    // MARK: - État

    /// La livrée telle qu'elle est en base. C'est **elle** qui dit si quelque chose a
    /// changé : comparer deux états vaut mieux qu'un drapeau « modifié » qu'un chemin
    /// oublierait de lever.
    @State private var livreeEnregistree = Livree(
        mode: .perso,
        coque: "#CC0000",
        ailerons: "#003087",
        couleurTexte: "#00D2BE"
    )

    @State private var livree = Livree(
        mode: .perso,
        coque: "#CC0000",
        ailerons: "#003087",
        couleurTexte: "#00D2BE"
    )

    @State private var numeroEnregistre = "33"
    @State private var numero = "33"

    /// **Un seul réglage déplié à la fois.** Quatre grilles ouvertes ensemble feraient du
    /// bloc un mur qu'on ne parcourt plus ; et refermer le précédent dit, sans un mot, que
    /// ces quatre rangées sont un même choix décliné.
    @State private var replieDeplie: Reglage?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private enum Reglage: Hashable { case skin, coque, ailerons, texte }

    // MARK: - Données mockées

    /// **La section Administration ne se monte que pour un administrateur.** Tant que la
    /// colonne `is_admin` n'est pas lue, elle reste éteinte : une section d'outils affichée
    /// à tout le monde serait pire qu'absente.
    private let estAdmin = false

    private let statistiques: [Statistique] = [
        Statistique(valeur: "33%", libelle: "Paris gagnés"),
        Statistique(valeur: "31", libelle: "Pts moy. / GP"),
        Statistique(valeur: "25", libelle: "Meilleur coup"),
        Statistique(valeur: "46", libelle: "Cote moy. tentée")
    ]

    // MARK: - Corps

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Text("Mon profil")
                        .font(.titre)
                        .tracking(Tracking.titre)
                        .foregroundColor(.texte)          // 15,37:1 sur le beige
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(height: 12)
                    entete

                    if viewModel.photoProfil != nil {
                        Spacer().frame(height: 10)
                        supprimerLaPhoto
                    }

                    Spacer().frame(height: 20)
                    grilleStatistiques

                    Spacer().frame(height: 12)
                    blocLivree

                    if estAdmin {
                        Spacer().frame(height: 12)
                        blocAdministration
                    }

                    Spacer().frame(height: 28)
                    deconnexion

                    Spacer().frame(height: 16)
                    versionAffichee
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - En-tête

    /// L'aplat d'identité : photo, pseudo, saison, et la voiture du membre à droite.
    ///
    /// **La voiture est ici en petit et là-dessous en grand, et c'est voulu** : la même
    /// chose, vue à la taille où les autres la verront au classement, puis à la taille où
    /// on la règle. C'est ce qui rend lisible ce que le bloc du dessous fabrique.
    private var entete: some View {
        HStack(spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(pseudoAffiche)
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
                       nom: pseudoAffiche,
                       photo: viewModel.photoProfil,
                       teintePilote: .primaire)
                .frame(height: 76)

            Text("#\(numeroAffiche)")
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

    /// La pastille du compte, et le bouton qui change la photo. **L'appareil photo est posé
    /// sur le bord du disque, pas à côté** : le contrôle touche ce qu'il modifie, ce qui
    /// dispense de l'expliquer.
    private var avatar: some View {
        Button {
            // Le choix d'une photo arrivera avec la couche réseau ; la cible tactile,
            // elle, est déjà à sa place et à sa taille.
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let photo = viewModel.photoProfil {
                        AsyncImage(url: photo) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            initialeDuPseudo
                        }
                    } else {
                        initialeDuPseudo
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primaire)           // 10,88:1 sur le blanc
                    .frame(width: 24, height: 24)
                    .background(Color.white, in: Circle())
            }
            // Le disque fait 64 pt, le bouton 66 : le plancher tactile de 44 pt est tenu
            // par le disque lui-même, l'icône n'est qu'une indication.
            .frame(width: 66, height: 66, alignment: .topLeading)
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel("Changer ma photo de profil")
    }

    private var initialeDuPseudo: some View {
        Color.primaireFonce
            .overlay {
                Text(pseudoAffiche.first.map { String($0).uppercased() } ?? "?")
                    .font(.custom("HelveticaNeue-Medium", size: 26))
                    .foregroundColor(.white)
            }
    }

    private var supprimerLaPhoto: some View {
        Button("Supprimer la photo") {
            // Idem : la suppression passera par le backend.
        }
        .font(.corps)
        .foregroundColor(.grisSecondaire)                  // 4,71:1 sur le beige
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .buttonStyle(StyleAppui(.bouton))
    }

    /// Repli sur « pilote » : une session peut être ouverte sans métadonnée `pseudo`.
    /// Un écran ne montre jamais un trou à la place d'un nom.
    private var pseudoAffiche: String {
        viewModel.pseudo.isEmpty ? "pilote" : viewModel.pseudo
    }

    private var numeroAffiche: String {
        numero.isEmpty ? "—" : numero
    }

    // MARK: - Statistiques

    private struct Statistique: Identifiable {
        let valeur: String
        let libelle: String
        var id: String { libelle }
    }

    /// Quatre tuiles, deux par rangée. **`LazyVGrid` à colonnes flexibles**, pas deux
    /// `HStack` : les quatre gardent alors la même largeur quelle que soit la longueur du
    /// libellé, et « Cote moy. tentée » ne fait pas grossir sa colonne.
    private var grilleStatistiques: some View {
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
            }
        }
    }

    // MARK: - Ma livrée

    private var blocLivree: some View {
        VStack(alignment: .leading, spacing: 0) {
            titreDeBloc("Ma livrée")

            Spacer().frame(height: 8)

            VueVoiture(livree: livree,
                       numero: numero,
                       nom: pseudoAffiche,
                       photo: viewModel.photoProfil,
                       teintePilote: .primaire)
                .frame(height: 150)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 12)

            rangeeNumero

            rangee(.skin, libelle: "Skin", valeur: nomDuSkin) {
                pastilleDuSkin
            } contenu: {
                grilleSkins
            }

            // **Les trois couleurs ne concernent que la livrée personnelle.** Sur une
            // livrée d'écurie elles ne peindraient rien : les onze voitures ont leurs
            // couleurs, et les rangées disparaissent plutôt que de rester sans effet.
            if livree.mode == .perso {
                rangee(.coque, libelle: "Coque", valeur: PaletteVoiture.nom(de: livree.coque)) {
                    pastille(livree.coque)
                } contenu: {
                    grilleCouleurs(choisie: livree.coque) { livree.coque = $0 }
                }

                rangee(.ailerons, libelle: "Ailerons", valeur: PaletteVoiture.nom(de: livree.ailerons)) {
                    pastille(livree.ailerons)
                } contenu: {
                    grilleCouleurs(choisie: livree.ailerons) { livree.ailerons = $0 }
                }

                rangee(.texte, libelle: "Couleur du texte", valeur: PaletteVoiture.nom(de: couleurTexteAffichee)) {
                    pastille(couleurTexteAffichee)
                } contenu: {
                    grilleCouleurs(choisie: couleurTexteAffichee) { livree.couleurTexte = $0 }
                }
            }

            Spacer().frame(height: 16)
            boutonEnregistrer
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

    /// `null` n'est pas « pas de couleur » mais « pas de choix » : le sélecteur montre
    /// alors **ce qui est réellement à l'écran**, c'est-à-dire l'encre calculée sur l'aplat
    /// du museau. Afficher du blanc par défaut ferait mentir la rangée.
    private var couleurTexteAffichee: String {
        livree.couleurTexte ?? (PaletteVoiture.luminance(livree.aplatDuNumero) > 0.45
                                ? "#1A1A1A" : "#FFFFFF")
    }

    private var nomDuSkin: String {
        livree.ecurieChoisie?.nom ?? "Ma livrée"
    }

    // MARK: Rangées

    /// Le champ du numéro. **Pas de sélecteur déroulant** : deux chiffres se tapent plus
    /// vite qu'ils ne se cherchent dans une liste de quatre-vingt-dix-neuf.
    private var rangeeNumero: some View {
        HStack {
            Text("Numéro")
                .font(.custom("HelveticaNeue", size: 17))
                .foregroundColor(.grisSecondaire)

            Spacer()

            HStack(spacing: 2) {
                Text("#")
                    .font(.custom("HelveticaNeue", size: 17))
                    .foregroundColor(.grisSecondaire)

                TextField("", text: $numero)
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundColor(.texte)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.leading)
                    .frame(width: 34)
                    .onChange(of: numero) { _, nouvelle in
                        // Le clavier numérique n'empêche pas un collage : le filtre est
                        // ici, pas dans le type du clavier.
                        let propre = String(nouvelle.filter(\.isNumber).prefix(2))
                        if propre != nouvelle { numero = propre }
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.fondPrincipal)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
        }
        .frame(minHeight: 56)
    }

    /// Une rangée de réglage : libellé, valeur, pastille, chevron — et le sélecteur qu'elle
    /// déplie sous elle.
    ///
    /// > **Le sélecteur s'ouvre là où on a appuyé, pas ailleurs.** Une feuille modale aurait
    /// > coupé la voiture de l'écran au moment précis où l'on change sa couleur ; dépliée
    /// > sur place, elle reste visible et se repeint sous le doigt.
    private func rangee<Pastille: View, Contenu: View>(
        _ reglage: Reglage,
        libelle: String,
        valeur: String,
        @ViewBuilder pastille: () -> Pastille,
        @ViewBuilder contenu: () -> Contenu
    ) -> some View {
        let ouvert = replieDeplie == reglage

        return VStack(spacing: 0) {
            Button {
                withAnimation(mouvementReduit ? nil : Mouvement.deplacement(0.22)) {
                    replieDeplie = ouvert ? nil : reglage
                }
            } label: {
                HStack(spacing: 10) {
                    Text(libelle)
                        .font(.custom("HelveticaNeue", size: 17))
                        .foregroundColor(.grisSecondaire)

                    Spacer(minLength: 8)

                    Text(valeur)
                        .font(.custom("HelveticaNeue-Medium", size: 17))
                        .foregroundColor(.texte)
                        .lineLimit(1)

                    pastille()
                        .frame(width: 30, height: 30)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.grisSecondaire)  // 5,33:1 sur le blanc
                        .rotationEffect(.degrees(ouvert ? 180 : 0))
                        .frame(width: 20)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(StyleAppui(.grandeSurface))

            if ouvert {
                contenu()
                    .padding(.bottom, 12)
                    // Le sélecteur **paraît** pendant que le bloc s'ouvre : l'opacité seule,
                    // la hauteur étant déjà animée par la disposition. Deux mouvements
                    // superposés sur la même chose se liraient comme un défaut de calage.
                    .transition(.opacity)
            }
        }
    }

    private func pastille(_ hex: String) -> some View {
        Circle()
            .fill(EncreSVG.couleur(hex) ?? .primaire)
            // Le blanc et le beige de la palette disparaîtraient sur une carte blanche :
            // le filet n'est pas décoratif, c'est ce qui rend la pastille lisible.
            .overlay(Circle().strokeBorder(Color.secondaire.opacity(0.18), lineWidth: 1))
    }

    /// La pastille du skin : les **deux** couleurs, coupées en deux — c'est ce que le
    /// réglage fabrique, et une seule des deux n'en dirait que la moitié. Sur une livrée
    /// d'écurie, c'est sa teinte, pleine.
    @ViewBuilder
    private var pastilleDuSkin: some View {
        if let ecurie = livree.ecurieChoisie {
            pastille(ecurie.teinte)
        } else {
            ZStack {
                Circle().fill(EncreSVG.couleur(livree.coque) ?? .primaire)
                Circle()
                    .fill(EncreSVG.couleur(livree.ailerons) ?? .white)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: 15)
                    }
                    .rotationEffect(.degrees(-30))
            }
            .overlay(Circle().strokeBorder(Color.secondaire.opacity(0.18), lineWidth: 1))
        }
    }

    // MARK: Sélecteurs

    /// Les douze skins : la livrée personnelle d'abord, puis les onze écuries dans l'ordre
    /// de la grille 2026. Trois colonnes, quatre rangées.
    private var grilleSkins: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                  spacing: 12) {
            caseSkin(nom: "Ma livrée", choisi: livree.mode == .perso) {
                livree.mode = .perso
                livree.ecurie = nil
            } vignette: {
                ZStack {
                    Color.primaire
                    VueVoiture(livree: Livree(mode: .perso,
                                              coque: livree.coque,
                                              ailerons: livree.ailerons))
                        .padding(6)
                }
            }

            ForEach(LivreeEcurie.toutes) { ecurie in
                caseSkin(nom: ecurie.nom, choisi: livree.ecurie == ecurie.slug && livree.mode == .ecurie) {
                    livree.mode = .ecurie
                    livree.ecurie = ecurie.slug
                } vignette: {
                    ZStack {
                        Color.fondPrincipal
                        VignetteEcurie(livree: ecurie).padding(9)
                    }
                }
            }
        }
    }

    private func caseSkin<Vignette: View>(
        nom: String,
        choisi: Bool,
        action: @escaping () -> Void,
        @ViewBuilder vignette: () -> Vignette
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                vignette()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if choisi {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.primaire, in: Circle())
                                .padding(5)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous)
                            .strokeBorder(choisi ? Color.primaire : .clear, lineWidth: 2)
                    }

                Text(nom)
                    .font(.custom("HelveticaNeue", size: 11))
                    .foregroundColor(choisi ? .primaire : .grisSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(nom)
        .accessibilityAddTraits(choisi ? [.isSelected] : [])
    }

    /// Les vingt couleurs. **Quatre colonnes** : à deux, la liste faisait dix rangées et le
    /// bloc devenait plus haut que l'écran ; à cinq, « Anthracite » ne tenait plus sous sa
    /// pastille.
    private func grilleCouleurs(choisie: String,
                                action: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                  spacing: 12) {
            ForEach(PaletteVoiture.teintes) { teinte in
                let estChoisie = EncreSVG.normaliser(teinte.hex) == EncreSVG.normaliser(choisie)

                Button {
                    action(teinte.hex)
                } label: {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(teinte.couleur)
                            .frame(width: 38, height: 38)
                            .overlay(Circle().strokeBorder(Color.secondaire.opacity(0.18), lineWidth: 1))
                            .overlay {
                                if estChoisie {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        // L'encre de la coche est **mesurée sur la teinte
                                        // qu'elle couvre** : blanc sur les foncées, texte
                                        // sur les claires. Une coche blanche sur le beige
                                        // de la palette ne se verrait pas.
                                        .foregroundColor(PaletteVoiture.encreSur(teinte.hex))
                                }
                            }
                            .overlay {
                                if estChoisie {
                                    Circle()
                                        .strokeBorder(Color.primaire, lineWidth: 2)
                                        .padding(-3)
                                }
                            }

                        Text(teinte.nom)
                            .font(.custom("HelveticaNeue", size: 10))
                            .foregroundColor(estChoisie ? .primaire : .grisSecondaire)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StyleAppui(.bouton))
                .accessibilityLabel(teinte.nom)
                .accessibilityAddTraits(estChoisie ? [.isSelected] : [])
            }
        }
    }

    // MARK: Enregistrement

    /// Rien n'a changé → rien à enregistrer. Le bouton reste **présent mais éteint** : le
    /// faire disparaître déplacerait tout ce qui est en dessous à chaque touche tapée dans
    /// le champ du numéro.
    private var aChange: Bool {
        livree != livreeEnregistree || numero != numeroEnregistre
    }

    private var boutonEnregistrer: some View {
        Button {
            livreeEnregistree = livree
            numeroEnregistre = numero
            withAnimation(mouvementReduit ? nil : Mouvement.deplacement(0.22)) {
                replieDeplie = nil
            }
        } label: {
            Text("Enregistrer ma voiture")
                .font(.custom("HelveticaNeue-Medium", size: 17))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.primaire.opacity(aChange ? 1 : 0.45))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(!aChange)
        .animation(mouvementReduit ? nil : Mouvement.entree(0.18), value: aChange)
    }

    // MARK: - Administration

    private var blocAdministration: some View {
        VStack(alignment: .leading, spacing: 0) {
            titreDeBloc("Administration")

            Spacer().frame(height: 10)

            Toggle(isOn: .constant(false)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode admin actif")
                        .font(.custom("HelveticaNeue-Medium", size: 17))
                        .foregroundColor(.texte)
                    Text("Tu vois l'app comme un membre ordinaire.")
                        .font(.corpsSm)
                        .foregroundColor(.grisSecondaire)
                }
            }
            .tint(.primaire)

            Spacer().frame(height: 12)

            Text("Rallume le mode pour retrouver les outils. Il repart éteint à chaque lancement.")
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

    // MARK: - Pied

    private var deconnexion: some View {
        Button {
            Task { await viewModel.deconnexion() }
        } label: {
            Text("Se déconnecter")
                .font(.custom("HelveticaNeue", size: 17))
                .foregroundColor(.grisSecondaire)          // 4,71:1 sur le beige
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(StyleAppui(.bouton))
    }

    private var versionAffichee: some View {
        Text("Version \(Bundle.main.versionAffichee)")
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .frame(maxWidth: .infinity)
    }

    /// Titre de section. L'encre est `grisSecondaire`, jamais `texteDoux` : sur le blanc,
    /// #999999 ne vaut que 2,85:1 — sous le plancher de 4,5:1 d'un texte de 11 pt.
    private func titreDeBloc(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ProfilView(viewModel: AuthViewModel())
}
