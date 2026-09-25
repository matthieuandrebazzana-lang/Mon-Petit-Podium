import SwiftUI

/// Onglet **Profil** — identité, statistiques, livrée, déconnexion.
///
/// Références visuelles : `Ressources/Screenshots/screen-20-mon-profil-haut.PNG` et
/// `screen-21-mon-profil-bas.PNG`, écran par écran.
///
/// > **Deux sources.** L'identité et la voiture sont le profil que ``AuthViewModel`` lit en
/// > direct sous RLS — le seul propriétaire du compte connecté. Les quatre statistiques
/// > viennent de `GET /profils/{mon id}/stats` (``StatistiquesProfil``), la même route que
/// > le profil d'un autre membre. La voiture s'enregistre par `PATCH /profils/moi`, via
/// > ``AuthViewModel/enregistrerVoiture(_:)`` : c'est son profil relu que la piste et le
/// > classement peignent ensuite pour le compte connecté.
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
    ///
    /// Recopiée du profil lu (``synchroniserVoiture(_:)``) tant que rien n'a été touché.
    @State private var livreeEnregistree = Livree()
    @State private var livree = Livree()

    @State private var numeroEnregistre = ""
    @State private var numero = ""

    /// Le `PATCH /profils/moi` en vol, et son refus — dit sous le bouton (``ErreurEnLigne``).
    @State private var envoiVoiture = false
    @State private var erreurVoiture: ErreurAPI?

    @StateObject private var statistiques = StatistiquesProfil()

    /// **Un seul réglage déplié à la fois.** Quatre grilles ouvertes ensemble feraient du
    /// bloc un mur qu'on ne parcourt plus ; et refermer le précédent dit, sans un mot, que
    /// ces quatre rangées sont un même choix décliné.
    @State private var replieDeplie: Reglage?

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private enum Reglage: Hashable { case skin, coque, ailerons, texte }

    /// `POST /admin/action` en vol, et son issue — dite sous le bouton, jamais en alerte.
    @State private var envoiScraper = false
    @State private var retourScraper: String?
    @State private var erreurScraper: ErreurAPI?

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
                    LigneGrandsPrix(titre: "Mes Grands Prix",
                                    sousTitre: StatsProfil.sousTitreGrandsPrix(joues: statistiques.stats?.gpJoues)) {
                        HistoriqueGPView(titre: "Mes Grands Prix")
                    }

                    Spacer().frame(height: 12)
                    blocLivree

                    // **`estAdmin`, et non `modePrevisualisation`, et ce n'est pas un
                    // oubli** : la section porte l'interrupteur qui rallume le mode, elle
                    // doit donc rester visible mode éteint (`decisions.md` §15).
                    if viewModel.estAdmin {
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
        .onAppear { synchroniserVoiture(viewModel.profil) }
        .onChange(of: viewModel.profil) { _, profil in synchroniserVoiture(profil) }
        // Relancé quand le compte arrive : un profil lu après l'ouverture de l'onglet
        // n'attend pas le prochain passage pour ses statistiques.
        .task(id: viewModel.profil?.id) { await chargerStatistiques() }
    }

    // MARK: - Chargement

    /// Le profil n'a pas pu être lu au lancement : on le redemande avant de conclure
    /// qu'il n'y a personne à interroger.
    private func chargerStatistiques() async {
        if viewModel.profil == nil { await viewModel.rechargerProfil() }
        await statistiques.charger(profilId: viewModel.profil?.id)
    }

    /// Recopie la voiture du profil lu. **Jamais par-dessus un réglage en cours** : un
    /// rechargement du profil ne doit pas effacer une couleur que le membre vient de choisir.
    private func synchroniserVoiture(_ profil: Profil?) {
        guard let profil, !aChange else { return }
        let lue = Livree(mode: profil.livreeMode == .ecurie ? .ecurie : .perso,
                         ecurie: profil.livreeEcurie,
                         coque: profil.couleur1,
                         ailerons: profil.couleur2,
                         couleurTexte: profil.couleurTexte)
        // `nil` = pas de numéro choisi : le champ reste vide, jamais « 0 ».
        let numeroLu = profil.numero.map(String.init) ?? ""
        livreeEnregistree = lue
        livree = lue
        numeroEnregistre = numeroLu
        numero = numeroLu
    }

    // MARK: - En-tête

    /// L'aplat d'identité : photo, pseudo, saison, et la voiture du membre à droite.
    ///
    /// **C'est le même en-tête que sur le profil d'un autre membre** (``EnteteProfil``) :
    /// seule la pastille diffère, parce qu'ici elle se change. Deux aplats écrits
    /// séparément auraient divergé au premier ajustement de rembourrage.
    ///
    /// **La voiture est ici en petit et là-dessous en grand, et c'est voulu** : la même
    /// chose, vue à la taille où les autres la verront au classement, puis à la taille où
    /// on la règle. C'est ce qui rend lisible ce que le bloc du dessous fabrique.
    private var entete: some View {
        EnteteProfil(pseudo: pseudoAffiche,
                     livree: livree,
                     numero: numero,
                     photo: viewModel.photoProfil) {
            avatar
        }
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
                PastilleProfil(pseudo: pseudoAffiche, photo: viewModel.photoProfil)

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

    // MARK: - Statistiques

    /// Quatre tuiles, deux par rangée — **les mêmes que sur le profil d'un autre membre**
    /// (``GrilleStatistiques``), et c'est ce qui permet de comparer les deux d'un coup
    /// d'œil sans relire les libellés.
    private var grilleStatistiques: some View {
        BlocStatistiques(etat: statistiques.etat) {
            Task { await chargerStatistiques() }
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

            if let erreurVoiture {
                Spacer().frame(height: 10)
                ErreurEnLigne(erreur: erreurVoiture)
                    .transition(.opacity)
            }
        }
        .animation(mouvementReduit ? nil : Mouvement.entree(0.20), value: erreurVoiture)
        .sensoryFeedback(.error, trigger: erreurVoiture) { _, nouveau in nouveau != nil }
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
        Button(action: enregistrerVoiture) {
            ZStack {
                Text("Enregistrer ma voiture").opacity(envoiVoiture ? 0 : 1)
                if envoiVoiture { ProgressView().tint(.white) }
            }
            .font(.custom("HelveticaNeue-Medium", size: 17))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primaire.opacity(aChange ? 1 : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(!aChange || envoiVoiture)
        .animation(mouvementReduit ? nil : Mouvement.entree(0.18), value: aChange)
        .accessibilityLabel(envoiVoiture ? "Enregistrement en cours" : "Enregistrer ma voiture")
    }

    /// Ce que le `PATCH` transmet. **La couleur du texte ne part que si elle a été
    /// choisie** (§3.2, règle 4), et un champ de numéro vidé part en `retirer_numero` :
    /// `numero: null` serait lu « non transmis ».
    private var modificationVoiture: ModificationVoiture {
        var corps = ModificationVoiture(livreeMode: livree.mode == .ecurie ? .ecurie : .perso,
                                        livreeEcurie: livree.ecurie)
        if livree.mode == .perso {
            corps.couleur1 = livree.coque
            corps.couleur2 = livree.ailerons
            corps.couleurTexte = livree.couleurTexte
        }
        if let valeur = Int(numero) {
            corps.numero = valeur
        } else {
            corps.retirerNumero = true
        }
        return corps
    }

    /// La tâche n'est **pas** liée à l'écran : changer d'onglet pendant l'appel ne
    /// l'annule pas, et la voiture s'enregistre quand même.
    private func enregistrerVoiture() {
        guard aChange, !envoiVoiture else { return }
        erreurVoiture = nil
        envoiVoiture = true
        let corps = modificationVoiture
        let livreeEnvoyee = livree
        let numeroEnvoye = numero

        Task {
            do {
                try await viewModel.enregistrerVoiture(corps)
                envoiVoiture = false
                // Ce qui est parti, pas ce qui est à l'écran : un réglage touché pendant
                // l'appel reste « à enregistrer ». Puis le profil relu fait foi — couleurs
                // normalisées par le serveur —, sauf par-dessus ce réglage-là.
                livreeEnregistree = livreeEnvoyee
                numeroEnregistre = numeroEnvoye
                synchroniserVoiture(viewModel.profil)
                withAnimation(mouvementReduit ? nil : Mouvement.deplacement(0.22)) {
                    replieDeplie = nil
                }
            } catch let refus as ErreurAPI {
                envoiVoiture = false
                erreurVoiture = refus
            } catch {
                envoiVoiture = false
            }
        }
    }

    // MARK: - Administration

    private var blocAdministration: some View {
        VStack(alignment: .leading, spacing: 0) {
            titreDeBloc("Administration")

            Spacer().frame(height: 10)

            // L'état est **dit**, pas seulement peint : la description change avec lui.
            Toggle(isOn: $viewModel.modeAdminActif) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode admin actif")
                        .font(.custom("HelveticaNeue-Medium", size: 17))
                        .foregroundColor(.texte)
                    Text(viewModel.modeAdminActif
                         ? "Tu vois les Grands Prix comme s'ils étaient ouverts. Rien n'est modifié en base."
                         : "Tu vois l'app comme un membre ordinaire.")
                        .font(.corpsSm)
                        .foregroundColor(.grisSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(.primaire)
            .frame(minHeight: 44)

            Spacer().frame(height: 12)

            Text("Il repart éteint à chaque lancement.")
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            // Le filet sépare ce qui change l'affichage de ce qui écrit pour de bon.
            Rectangle()
                .fill(Color.secondaire.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 16)
                .accessibilityHidden(true)

            Text("Le scraping tourne déjà tout seul après les qualifications. Ce bouton le force entre-temps, sans figer les cotes.")
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 12)
            boutonScraper

            if let retourScraper {
                Spacer().frame(height: 10)
                Text(retourScraper)
                    .font(.corpsSm)
                    .foregroundColor(.texte)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }

            if let erreurScraper {
                Spacer().frame(height: 10)
                ErreurEnLigne(erreur: erreurScraper)
                    .transition(.opacity)
            }
        }
        .animation(mouvementReduit ? nil : Mouvement.entree(0.20), value: retourScraper)
        .animation(mouvementReduit ? nil : Mouvement.entree(0.20), value: erreurScraper)
        .sensoryFeedback(.success, trigger: retourScraper) { _, nouveau in nouveau != nil }
        .sensoryFeedback(.error, trigger: erreurScraper) { _, nouveau in nouveau != nil }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

    /// Même habillage que « Enregistrer ma voiture » : deux boutons pleins du même écran
    /// qui ne se ressembleraient pas cesseraient de se lire comme des boutons.
    private var boutonScraper: some View {
        Button(action: lancerScraper) {
            ZStack {
                Text("Scraper les cotes").opacity(envoiScraper ? 0 : 1)
                if envoiScraper { ProgressView().tint(.white) }
            }
            .font(.custom("HelveticaNeue-Medium", size: 17))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primaire)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(envoiScraper)
        .accessibilityLabel(envoiScraper ? "Scraping en cours" : "Scraper les cotes")
    }

    private func lancerScraper() {
        guard !envoiScraper else { return }
        envoiScraper = true
        retourScraper = nil
        erreurScraper = nil
        Task {
            do {
                retourScraper = try await Administration.lancerScraper()
            } catch let refus as ErreurAPI {
                erreurScraper = refus
            } catch {
                // Tâche annulée : rien à dire.
            }
            envoiScraper = false
        }
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
