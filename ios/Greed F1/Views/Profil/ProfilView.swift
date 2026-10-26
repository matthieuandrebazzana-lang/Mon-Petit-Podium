import PhotosUI
import SwiftUI

/// Onglet **Profil** — identité, statistiques, livrée ; l'engrenage mène aux réglages
/// (``ReglagesView`` : apparence, langue, notifications, compte).
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

    /// Le pavé numérique n'a pas de touche de fermeture : la barre « OK » au-dessus du
    /// clavier, un toucher hors du champ et le défilement le referment.
    @FocusState private var numeroActif: Bool
    /// Le cadre du champ, dans l'espace de l'écran : un toucher **dedans** (pour placer le
    /// curseur) ne doit pas refermer le clavier.
    @State private var cadreNumero: CGRect = .zero
    private static let espaceEcran = "profil"
    private static let idNumero = "numero"

    /// Le `PATCH /profils/moi` en vol, et son refus — dit sous le bouton (``ErreurEnLigne``).
    @State private var envoiVoiture = false
    @State private var erreurVoiture: ErreurAPI?

    /// La photo choisie dans la photothèque, puis son recadrage (``RecadrageImageView``,
    /// masque cercle) et son dépôt en vol — le refus dit sous l'en-tête (``ErreurEnLigne``),
    /// jamais en alerte.
    @State private var choixPhoto: PhotosPickerItem?
    @State private var imageACadrer: UIImage?
    @State private var envoiPhoto = false
    @State private var erreurPhoto: ErreurAPI?

    /// Possédées par ``BarreNavigation``, chargées dès le lancement, sur disque (§7.6).
    @ObservedObject var statistiques: StatistiquesProfil

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

            ScrollViewReader { defilement in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(t("accueil.monProfil"))
                            .font(.titre)
                            .tracking(Tracking.titre)
                            .foregroundColor(.texte)      // 15,37:1 sur le beige
                            .frame(maxWidth: .infinity, alignment: .leading)

                        boutonReglages
                    }

                    Spacer().frame(height: 12)
                    entete

                    if let erreurPhoto {
                        Spacer().frame(height: 10)
                        ErreurEnLigne(erreur: erreurPhoto)
                    }

                    if viewModel.photoProfil != nil {
                        Spacer().frame(height: 10)
                        supprimerLaPhoto
                    }

                    Spacer().frame(height: 20)
                    grilleStatistiques

                    Spacer().frame(height: 12)
                    LigneGrandsPrix(titre: t("profil.mesGrandsPrix"),
                                    sousTitre: StatsProfil.sousTitreGrandsPrix(joues: statistiques.stats?.gpJoues)) {
                        HistoriqueGPView(titre: t("profil.mesGrandsPrix"), profilId: viewModel.profil?.id,
                                         voiture: voitureEnregistree)
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

                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            // Simultané : les boutons de l'écran reçoivent leur tap comme avant.
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named(Self.espaceEcran)).onEnded { toucher in
                    if numeroActif && !cadreNumero.contains(toucher.location) { numeroActif = false }
                }
            )
            // Le clavier monte par-dessus le bas de l'écran : le champ remonte au centre.
            .onChange(of: numeroActif) { _, actif in
                guard actif else { return }
                withAnimation(mouvementReduit ? nil : Mouvement.deplacement(0.22)) {
                    defilement.scrollTo(Self.idNumero, anchor: .center)
                }
            }
            }
        }
        .coordinateSpace(.named(Self.espaceEcran))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(t("clavier.ok")) { numeroActif = false }
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundColor(.encrePrimaire)
            }
        }
        .onAppear { synchroniserVoiture(viewModel.profil) }
        .onChange(of: viewModel.profil) { _, profil in synchroniserVoiture(profil) }
        // Relancé quand le compte arrive : un profil lu après l'ouverture de l'onglet
        // n'attend pas le prochain passage pour ses statistiques.
        .task(id: viewModel.profil?.id) { await chargerStatistiques() }
        .onChange(of: choixPhoto) { _, choix in
            guard let choix else { return }
            Task { await chargerPourRecadrage(choix) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { imageACadrer != nil },
            set: { affiche in if !affiche { imageACadrer = nil } }
        )) {
            if let imageACadrer {
                RecadrageImageView(image: imageACadrer, forme: .cercle) { recadree in
                    Task { await envoyerPhoto(recadree) }
                }
            }
        }
    }

    // MARK: - Chargement

    /// Les statistiques n'attendent pas le profil : leur identifiant est celui de la session
    /// locale. Un profil qui n'a pas pu être lu au lancement est redemandé à côté.
    private func chargerStatistiques() async {
        if viewModel.profil == nil { Task { await viewModel.rechargerProfil() } }
        await statistiques.charger(profilId: viewModel.profil?.id ?? SupabaseManager.partage.idCompte)
    }

    /// Recopie la voiture du profil lu. **Jamais par-dessus un réglage en cours** : un
    /// rechargement du profil ne doit pas effacer une couleur que le membre vient de choisir.
    private func synchroniserVoiture(_ profil: Profil?) {
        guard let profil, !aChange else { return }
        let lue = profil.livree
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
    ///
    /// **Le sélecteur enveloppe le disque ET l'appareil photo** : les deux ouvrent la
    /// photothèque, l'icône n'étant que l'indication de ce que fait le disque.
    private var avatar: some View {
        // Lue ici, sur l'acteur principal : l'étiquette du sélecteur ne l'est pas.
        let photo = viewModel.photoProfil
        return PhotosPicker(selection: $choixPhoto, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                PastilleProfil(pseudo: pseudoAffiche, photo: photo)
                    .overlay {
                        if envoiPhoto {
                            // Un matériau plutôt qu'un voile coloré : l'écran ne déclare
                            // pas sa propre couleur.
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay { ProgressView().tint(.encrePrimaire) }
                        }
                    }

                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.encrePrimaire)           // 10,88:1 sur le blanc · sombre 4,94:1
                    .frame(width: 24, height: 24)
                    .background(Color.surface, in: Circle())
            }
            // Le disque fait 64 pt, le bouton 66 : le plancher tactile de 44 pt est tenu
            // par le disque lui-même, l'icône n'est qu'une indication.
            .frame(width: 66, height: 66, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(envoiPhoto)
        .accessibilityLabel(t("profil.a11y.changerPhoto"))
    }

    /// Charge la photo choisie et ouvre son recadrage. La sélection est remise à `nil` à la
    /// fin : choisir deux fois la même photo doit rouvrir le recadrage, ce qu'un `onChange`
    /// sur une valeur inchangée ne ferait pas.
    private func chargerPourRecadrage(_ choix: PhotosPickerItem) async {
        erreurPhoto = nil
        defer { choixPhoto = nil }
        guard
            let donnees = try? await choix.loadTransferable(type: Data.self),
            let image = UIImage(data: donnees)
        else {
            erreurPhoto = .serveur(statut: nil, message: t("photo.illisible"))
            return
        }
        imageACadrer = image
    }

    /// Dépose la photo recadrée et enregistre son URL (``AuthViewModel/enregistrerPhoto(_:)``).
    private func envoyerPhoto(_ image: UIImage) async {
        envoiPhoto = true
        erreurPhoto = nil
        defer { envoiPhoto = false }
        guard let donnees = image.jpegData(compressionQuality: 0.9) else {
            erreurPhoto = .serveur(statut: nil, message: t("photo.illisible"))
            return
        }
        do {
            try await viewModel.enregistrerPhoto(donnees)
        } catch let erreur as ErreurAPI {
            erreurPhoto = erreur
        } catch {
            erreurPhoto = .serveur(statut: nil, message: t("photo.illisible"))
        }
    }

    private var supprimerLaPhoto: some View {
        Button(t("profil.supprimerPhoto")) {
            // Idem : la suppression passera par le backend.
        }
        .font(.corps)
        .foregroundColor(.grisSecondaire)                  // 4,71:1 sur le beige
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .buttonStyle(StyleAppui(.bouton))
    }

    /// La voiture **enregistrée**, jamais celle qu'on règle : « Mes Grands Prix » montre ce
    /// que les autres voient. `nil` tant que le profil n'est pas lu.
    private var voitureEnregistree: VoitureMembre? {
        viewModel.profil.map {
            VoitureMembre(livree: $0.livree, numero: $0.numero.map(String.init) ?? "",
                          nom: pseudoAffiche, photo: viewModel.photoProfil)
        }
    }

    /// Repli sur « pilote » : une session peut être ouverte sans métadonnée `pseudo`.
    /// Un écran ne montre jamais un trou à la place d'un nom.
    private var pseudoAffiche: String {
        viewModel.pseudo.isEmpty ? t("accueil.pilote") : viewModel.pseudo
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
            titreDeBloc(t("profil.maLivree"))

            Spacer().frame(height: 8)

            // **Esquissée tant que le profil n'est pas lu** : la livrée par défaut, peinte
            // en attendant, se lirait comme celle du membre puis changerait sous ses yeux.
            ZStack {
                if viewModel.profil == nil {
                    SkeletonView(.blocRectangulaire, largeur: 150, hauteur: 150)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(t("profil.a11y.chargementLivree"))
                } else {
                    VueVoiture(livree: livree,
                               numero: numero,
                               nom: pseudoAffiche,
                               photo: viewModel.photoProfil,
                               teintePilote: .primaire)
                    .arriveeEnCascade()
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .fonduChargement(viewModel.profil == nil)

            Spacer().frame(height: 12)

            rangeeNumero

            rangee(.skin, libelle: t("profil.skin"), valeur: nomDuSkin) {
                pastilleDuSkin
            } contenu: {
                grilleSkins
            }

            // **La coque et les ailerons ne concernent que « Ma livrée ».** Sur une livrée
            // d'écurie ils ne peindraient rien ; ils restent en base et reviennent dès que le
            // membre rebascule. La couleur du texte, elle, peint aussi une écurie : toujours là.
            if livree.mode == .perso {
                rangee(.coque, libelle: t("profil.coque"), valeur: PaletteVoiture.nom(de: livree.coque)) {
                    pastille(livree.coque)
                } contenu: {
                    grilleCouleurs(choisie: livree.coque) { livree.coque = $0 }
                }

                rangee(.ailerons, libelle: t("profil.ailerons"), valeur: PaletteVoiture.nom(de: livree.ailerons)) {
                    pastille(livree.ailerons)
                } contenu: {
                    grilleCouleurs(choisie: livree.ailerons) { livree.ailerons = $0 }
                }
            }

            rangee(.texte, libelle: t("profil.couleurTexte"), valeur: PaletteVoiture.nom(de: couleurTexteAffichee)) {
                pastille(couleurTexteAffichee)
            } contenu: {
                grilleCouleurs(choisie: couleurTexteAffichee) { livree.couleurTexte = $0 }
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
        livree.ecurieChoisie?.nom ?? t("profil.maLivreeNom")
    }

    // MARK: Rangées

    /// Le champ du numéro. **Pas de sélecteur déroulant** : deux chiffres se tapent plus
    /// vite qu'ils ne se cherchent dans une liste de quatre-vingt-dix-neuf.
    private var rangeeNumero: some View {
        HStack {
            Text(t("profil.numero"))
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
                    .focused($numeroActif)
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.espaceEcran)) } action: {
                cadreNumero = $0
            }
        }
        .frame(minHeight: 56)
        .id(Self.idNumero)
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
    /// d'écurie, c'est **sa vignette de casque**, découpée de la planche comme dans la
    /// grille — une teinte seule ne distinguait pas les écuries à dominante claire.
    @ViewBuilder
    private var pastilleDuSkin: some View {
        if let ecurie = livree.ecurieChoisie {
            VignetteEcurie(livree: ecurie)
        } else {
            ZStack {
                Circle().fill(EncreSVG.couleur(livree.coque) ?? .primaire)
                Circle()
                    .fill(EncreSVG.couleur(livree.ailerons) ?? .blancLivree)
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
            caseSkin(nom: t("profil.maLivreeNom"), choisi: livree.mode == .perso) {
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
                                .foregroundColor(.encreSurAplat)
                                .frame(width: 22, height: 22)
                                .background(Color.primaire, in: Circle())
                                .padding(5)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous)
                            .strokeBorder(choisi ? Color.encrePrimaire : .clear, lineWidth: 2)
                    }

                Text(nom)
                    .font(.custom("HelveticaNeue", size: 11))
                    .foregroundColor(choisi ? .encrePrimaire : .grisSecondaire)
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
                                        .strokeBorder(Color.encrePrimaire, lineWidth: 2)
                                        .padding(-3)
                                }
                            }

                        Text(teinte.nom)
                            .font(.custom("HelveticaNeue", size: 10))
                            .foregroundColor(estChoisie ? .encrePrimaire : .grisSecondaire)
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
                Text(t("profil.enregistrerVoiture")).opacity(envoiVoiture ? 0 : 1)
                if envoiVoiture { ProgressView().tint(.encreSurAplat) }
            }
            .font(.custom("HelveticaNeue-Medium", size: 17))
            .foregroundColor(.encreSurAplat)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primaire.opacity(aChange ? 1 : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(!aChange || envoiVoiture)
        .animation(mouvementReduit ? nil : Mouvement.entree(0.18), value: aChange)
        .accessibilityLabel(envoiVoiture ? t("pronos.a11y.enregistrement") : t("profil.enregistrerVoiture"))
    }

    /// Ce que le `PATCH` transmet. **La couleur du texte ne part que si elle a été
    /// choisie** (§3.2, règle 4), et un champ de numéro vidé part en `retirer_numero` :
    /// `numero: null` serait lu « non transmis ».
    private var modificationVoiture: ModificationVoiture {
        var corps = ModificationVoiture(livreeMode: livree.mode == .ecurie ? .ecurie : .perso,
                                        livreeEcurie: livree.ecurie)
        // Les couleurs partent aussi en mode écurie : leurs rangées y sont réglables, et le
        // backend les conserve pour le retour à « Ma livrée ».
        corps.couleur1 = livree.coque
        corps.couleur2 = livree.ailerons
        corps.couleurTexte = livree.couleurTexte
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
            titreDeBloc(t("admin.titre"))

            Spacer().frame(height: 10)

            // L'état est **dit**, pas seulement peint : la description change avec lui.
            Toggle(isOn: $viewModel.modeAdminActif) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("admin.modeActif"))
                        .font(.custom("HelveticaNeue-Medium", size: 17))
                        .foregroundColor(.texte)
                    Text(viewModel.modeAdminActif
                         ? t("admin.modeActifOui")
                         : t("admin.modeActifNon"))
                        .font(.corpsSm)
                        .foregroundColor(.grisSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(.primaire)
            .frame(minHeight: 44)

            Spacer().frame(height: 12)

            Text(t("admin.repartEteint"))
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            // Le filet sépare ce qui change l'affichage de ce qui écrit pour de bon.
            Rectangle()
                .fill(Color.secondaire.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 16)
                .accessibilityHidden(true)

            Text(t("admin.scrapingExplication"))
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
                Text(t("admin.scraper")).opacity(envoiScraper ? 0 : 1)
                if envoiScraper { ProgressView().tint(.encreSurAplat) }
            }
            .font(.custom("HelveticaNeue-Medium", size: 17))
            .foregroundColor(.encreSurAplat)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primaire)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(envoiScraper)
        .accessibilityLabel(envoiScraper ? t("admin.a11y.scrapingEnCours") : t("admin.scraper"))
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

    // MARK: - Réglages

    /// L'engrenage qui pousse ``ReglagesView`` — en haut à droite, à hauteur du titre.
    /// Zone tactile de 44 × 44 pt ; le symbole est ramené au bord de la marge par un
    /// retrait négatif, pour s'aligner sur le bord droit des blocs.
    ///
    /// L'asset `icon-reglages` (24 × 24, *template*) et non le `gearshape` du système : son
    /// trait de 1,5 suit celui des icônes du projet. L'encre est ``Color/encrePrimaire`` —
    /// un trait rouge, donc jamais l'aplat `primaire`, qui tombe à 2,26:1 en sombre.
    private var boutonReglages: some View {
        NavigationLink {
            ReglagesView(viewModel: viewModel)
        } label: {
            Image("icon-reglages")
                .resizable()
                .frame(width: 26, height: 26)
                .foregroundColor(.encrePrimaire)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .padding(.trailing, -11)
        .accessibilityLabel(t("reglages.a11y.ouvrir"))
    }

    private func titreDeBloc(_ texte: String) -> some View {
        TitreDeBloc(texte: texte)
    }
}

#Preview {
    ProfilView(viewModel: AuthViewModel(), statistiques: StatistiquesProfil())
}
