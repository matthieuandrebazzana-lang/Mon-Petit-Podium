import PhotosUI
import SwiftUI

/// Le détail d'un championnat : son classement, et la porte de la vue piste.
///
/// Références visuelles : `maquettes/maquette-07-championnat.html` pour la composition,
/// `Ressources/Screenshots/screen-13-classement-championnat.PNG` pour ce que la version web
/// en a finalement fait.
///
/// > **Un seul appel pour les deux segments.** ``ClassementChampionnat`` lit
/// > `GET /championnats/{id}/classement` (cache de 60 s, ``CacheService``) ; le classement et la piste
/// > reçoivent **le même tableau**, et basculer de l'un à l'autre ne rappelle rien.
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1) : « 168 pts », et
/// nulle part un « ×2,80 ».
struct ChampionnatDetailView: View {

    let championnat: Championnat

    /// La liste de l'accueil et de l'onglet, rechargée après un départ : sans elle, le
    /// championnat quitté resterait affiché jusqu'au prochain changement d'onglet.
    @ObservedObject var mesChampionnats: MesChampionnats

    @StateObject private var classement: ClassementChampionnat

    @Environment(\.dismiss) private var dismiss

    /// Le profil du compte connecté. **C'est lui qui peint sa propre voiture**, pas sa
    /// ligne du classement : celle-ci a été servie avant une éventuelle modification dans
    /// l'onglet Profil, et ne se relit qu'à la prochaine apparition.
    @Environment(\.monProfil) private var monProfil

    /// La feuille du code d'invitation.
    @State private var codeAffiche = false
    /// L'alerte qui précède le départ — **la seule confirmation de l'écran** : c'est la
    /// seule action destructive, et le départ ne se défait pas sans le code.
    @State private var confirmationDepart = false
    @State private var departEnCours = false
    /// Le refus du serveur. Une alerte, par exception à ``ErreurEnLigne`` : le départ part
    /// d'un menu, et il n'y a pas de bouton sous lequel écrire.
    @State private var erreurDepart: ErreurAPI?

    /// La photothèque, ouverte depuis le menu — **créateur seulement** (`est_createur`,
    /// calculé par le serveur ; le `PATCH` le revérifie de toute façon). Puis son recadrage
    /// (``RecadrageImageView``, masque carré), puis le dépôt en vol et son refus, en alerte
    /// pour la même raison que le départ : il part d'un menu.
    @State private var selecteurPhoto = false
    @State private var choixPhoto: PhotosPickerItem?
    @State private var imageACadrer: UIImage?
    @State private var envoiPhoto = false
    @State private var erreurPhoto: ErreurAPI?

    /// Une écriture en vol : le menu se ferme et son déclencheur devient un indicateur.
    private var occupe: Bool { departEnCours || envoiPhoto }

    init(championnat: Championnat, mesChampionnats: MesChampionnats) {
        self.championnat = championnat
        self.mesChampionnats = mesChampionnats
        _classement = StateObject(wrappedValue: ClassementChampionnat(championnatId: championnat.id))
    }

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    /// L'effectif affiché sous le nom. **Celui du classement dès qu'il est lu** : un
    /// en-tête qui annonce huit membres au-dessus de sept lignes est exactement le genre de
    /// défaut discret que le `CLAUDE.md` de la racine décrit. Avant, celui de la liste.
    private var effectif: Int {
        if case .pret(let membres) = classement.etat { return membres.count }
        return championnat.nombreMembres
    }

    private var classementEnChargement: Bool {
        if case .chargement = classement.etat { return true }
        return false
    }

    /// Les deux segments de l'écran.
    private enum Vue: Hashable {
        case classement, piste
    }

    @State private var vue: Vue = .classement

    /// Vrai dès le premier passage sur « Piste », et pour toujours. **La piste n'est
    /// construite qu'à ce moment-là** — sol, `Canvas`, photos des cockpits : qui ne regarde
    /// que le classement ne la paie pas. Une fois construite, elle reste montée, et les
    /// bascules suivantes ne font que changer son opacité (`visible(_:)`).
    @State private var pisteVue = false

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            // **Le sol de la piste, derrière l'en-tête.** Posé ici et non par
            // ``VuePisteView`` — intégrée, elle ne le peint plus — pour que ses kerbs
            // montent jusqu'au bord supérieur de l'écran, zones sûres comprises, au lieu de
            // s'arrêter sous le sélecteur « Classement / Piste ». C'est l'opacité du bloc
            // ci-dessous qui les cache là où il se pose, exactement comme l'aplat du
            // bandeau les cache sur l'écran plein.
            //
            // **Monté au premier tap sur « Piste », puis toujours** (``pisteVue``), en fondu
            // comme le contenu : le recréer à chaque bascule
            // redessinait la planche plein écran dans la transaction de la pastille. Masqué
            // à 0,001 et non à 0, pour la même raison que les contenus (`visible(_:)`).
            if pisteVue {
                SolPiste()
                    .ignoresSafeArea()
                    .opacity(vue == .piste ? 1 : 0.001)
                    .animation(Mouvement.entree(Mouvement.passageEcran), value: vue)
                    .transition(.opacity)
            }

            // **L'en-tête et le sélecteur ne défilent pas**, le contenu dessous oui. La
            // piste redevient un segment de cet écran : elle s'affiche **en place**, sous
            // l'en-tête, au lieu d'être poussée comme un écran plein.
            VStack(spacing: 0) {
                // **Fond opaque** — sans lui le sol de la piste, posé juste derrière,
                // remonterait sous le titre et le sélecteur au lieu de rester derrière eux.
                VStack(spacing: 0) {
                    entete
                        .padding(.horizontal, margeLaterale)
                        .padding(.top, 8)

                    selecteur
                        .padding(.horizontal, margeLaterale)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
                .background(Color.fondPrincipal)

                // Un fondu court entre les deux contenus, et rien d'autre : un segment
                // se bascule souvent, un glissement latéral finirait par se faire attendre.
                // L'opacité reste permise en mouvement réduit.
                //
                // > **Les deux contenus restent construits**, l'un sur l'autre ; seule leur
                // > opacité bascule. Un `switch` démontait l'un et construisait l'autre à
                // > chaque appui — la piste refaisait ses `Canvas`, rechargeait les photos de
                // > ses cockpits et rejouait l'entrée des voitures dans la même image que le
                // > départ de la pastille, qui saccadait. Le classement garde en prime sa
                // > position de défilement.
                //
                // > **La piste n'est construite qu'au premier tap** (``pisteVue``), puis
                // > reste montée : l'écran s'ouvre sans payer une vue qu'on ne regarde
                // > peut-être pas. Le premier passage coûte sa construction, les suivants
                // > ne basculent que l'opacité.
                ZStack {
                    switch classement.etat {
                    case .chargement:
                        SqueletteClassement()
                            .padding(.horizontal, margeLaterale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(t("championnat.a11y.chargementClassement"))

                    case .echec(let erreur):
                        EchecChargement(erreur: erreur) {
                            Task { await classement.charger() }
                        }
                        .frame(maxHeight: .infinity)

                    case .pret(let servis):
                        let membres = servis.map { $0.avecVoiture(de: monProfil) }
                        contenuClassement(membres)
                            .visible(vue == .classement)
                            .transition(.contenuArrive)
                        // Construite au premier tap sur « Piste », gardée ensuite.
                        if pisteVue {
                            PisteIntegree(championnat: championnat, membres: membres)
                                .equatable()
                                .visible(vue == .piste)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(Mouvement.entree(Mouvement.passageEcran), value: vue)
                .fonduChargement(classementEnChargement)
            }
        }
        .onChange(of: vue) { _, nouvelle in
            if nouvelle == .piste && !pisteVue {
                withAnimation(Mouvement.entree(Mouvement.passageEcran)) { pisteVue = true }
            }
        }
        // À chaque apparition, retour du profil d'un membre compris — servi par le cache
        // *stale-while-revalidate* (``CacheService``, 60 s, `docs/swift-app.md` §7.6).
        .task { await classement.charger() }
        // Le nom du championnat est déjà dans le contenu, à 28 pt : le répéter dans la
        // barre ferait doublon. Elle ne garde donc que le chevron de retour natif, qui
        // porte le titre de l'écran précédent — « Championnats ».
        //
        // **Le titre est néanmoins posé, et masqué.** Un bouton de retour natif prend son
        // libellé du titre de l'écran d'où il vient : sans lui, le profil d'un membre
        // n'afficherait qu'un chevron nu. L'élément principal vide retire le texte de la
        // barre sans retirer le titre, là où `navigationTitle("")` aurait retiré les deux.
        //
        // > *Écart mesuré au simulateur (`CLAUDE.md` §6).* **Sous iOS 26, le libellé ne
        // > s'affiche de toute façon pas** : le Liquid Glass rend le bouton de retour en
        // > pastille de verre, chevron seul, quel que soit le titre — comme il reprend la
        // > main sur la barre d'onglets (`ios/CLAUDE.md` §3). Le titre reste posé pour
        // > **iOS 17 et 18**, la cible de déploiement, où le bouton l'affiche ; sans
        // > l'élément principal vide, ces deux versions gagneraient le libellé mais iOS 26
        // > hériterait d'un « Classement » centré en doublon du nom juste dessous.
        .navigationTitle(t("championnat.classement"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $codeAffiche) {
            FeuilleCodeInvitation(championnat: championnat)
        }
        .alert(t("championnat.quitterTitre", championnat.nom), isPresented: $confirmationDepart) {
            Button(t("championnat.quitter"), role: .destructive) { quitter() }
            Button(t("commun.annuler"), role: .cancel) {}
        } message: {
            Text(t("championnat.quitterMessage"))
        }
        .alert(t("championnat.quitterImpossible"),
               isPresented: Binding(get: { erreurDepart != nil },
                                    set: { if !$0 { erreurDepart = nil } }),
               presenting: erreurDepart) { _ in
            Button(t("commun.ok"), role: .cancel) {}
        } message: { erreur in
            Text(erreur.message)
        }
        .photosPicker(isPresented: $selecteurPhoto, selection: $choixPhoto,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: choixPhoto) { _, choix in
            guard let choix else { return }
            chargerPourRecadrage(choix)
        }
        .fullScreenCover(isPresented: Binding(
            get: { imageACadrer != nil },
            set: { affiche in if !affiche { imageACadrer = nil } }
        )) {
            if let imageACadrer {
                RecadrageImageView(image: imageACadrer, forme: .carre) { recadree in
                    envoyerPhoto(recadree)
                }
            }
        }
        .alert(t("championnat.photoImpossible"),
               isPresented: Binding(get: { erreurPhoto != nil },
                                    set: { if !$0 { erreurPhoto = nil } }),
               presenting: erreurPhoto) { _ in
            Button(t("commun.ok"), role: .cancel) {}
        } message: { erreur in
            Text(erreur.message)
        }
    }

    /// Charge la photo choisie et ouvre son recadrage. La sélection est remise à `nil` à la
    /// fin : choisir deux fois la même photo doit rouvrir le recadrage.
    private func chargerPourRecadrage(_ choix: PhotosPickerItem) {
        erreurPhoto = nil
        Task {
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
    }

    /// Dépose la photo recadrée sous le dossier du championnat (``DepotPhoto``, comme
    /// l'avatar), enregistre son URL par `PATCH /championnats/{id}`, puis recharge la
    /// liste — c'est elle qui peint la photo sur les cartes.
    ///
    /// **Tâche non liée à l'écran**, comme ``quitter()`` : l'envoi va au bout même si l'on
    /// revient en arrière entre-temps.
    private func envoyerPhoto(_ image: UIImage) {
        guard !envoiPhoto else { return }
        envoiPhoto = true
        erreurPhoto = nil
        Task {
            defer { envoiPhoto = false }
            guard let donnees = image.jpegData(compressionQuality: 0.9) else {
                erreurPhoto = .serveur(statut: nil, message: t("photo.illisible"))
                return
            }
            do {
                let url = try await DepotPhoto.deposer(donnees, dans: .championnats,
                                                       proprietaire: championnat.id.uuidString)
                try await APIClient.partage.envoyer("championnats/\(championnat.id.uuidString.lowercased())",
                                                    methode: .patch,
                                                    corps: ModificationChampionnat(photoUrl: url))
            } catch is CancellationError {
                return
            } catch let erreur as ErreurAPI {
                erreurPhoto = erreur
                return
            } catch {
                erreurPhoto = .serveur(statut: nil, message: t("photo.illisible"))
                return
            }
            await mesChampionnats.charger(forcer: true)
        }
    }

    /// `DELETE /championnats/{id}/quitter`, puis la liste rechargée, puis le retour.
    ///
    /// **La tâche n'est pas liée à l'écran** — comme pour « Créer » et « Rejoindre » : le
    /// départ et le rechargement vont au bout même si l'écran disparaît entre-temps.
    /// `charger(forcer: true)` parce qu'un chargement en vol, lancé avant l'écriture,
    /// ramènerait encore le championnat quitté.
    private func quitter() {
        guard !departEnCours else { return }
        departEnCours = true
        Task {
            defer { departEnCours = false }
            do {
                try await APIClient.partage.envoyer("championnats/\(championnat.id.uuidString.lowercased())/quitter",
                                                    methode: .delete)
            } catch is CancellationError {
                return
            } catch let erreur as ErreurAPI {
                erreurDepart = erreur
                return
            } catch {
                erreurDepart = .serveur(statut: nil, message: nil)
                return
            }
            await mesChampionnats.charger(forcer: true)
            dismiss()
        }
    }

    // MARK: - En-tête

    /// Le retrait de l'icône ⋯ dans son cadre de 44 pt (glyphe ≈ 20 pt de large). Retiré
    /// des deux côtés du bouton pour que les écarts se mesurent **au glyphe**, ce que l'œil
    /// voit, et non au cadre tactile invisible.
    private let retraitGlyphe: CGFloat = 12

    /// **Trois colonnes** : le titre à gauche, la photo, les trois points à droite — tous
    /// trois centrés sur l'axe vertical, la photo à équidistance du texte et du ⋯, chacun
    /// mesuré sur sa partie visible. ``DispositionEntete`` choisit le côté de la photo :
    /// 100 pt, réduite jusqu'à 72 pt si le titre en a besoin. **L'en-tête grandit avec
    /// elle** : la photo ne se règle plus sur la hauteur du bloc texte.
    ///
    /// **Sans photo, rien** : ni initiale ni aplat. L'en-tête redevient le bloc texte à
    /// gauche et le ⋯ à droite, à sa hauteur naturelle — aucune place réservée.
    @ViewBuilder private var entete: some View {
        if let photo {
            DispositionEntete(titre: championnat.nom) {
                titreEtSousTitre
                PhotoChampionnat(nom: championnat.nom, photo: photo)
                iconeMenu
                    .padding(.horizontal, -retraitGlyphe)
            }
        } else {
            HStack(alignment: .center, spacing: 16) {
                titreEtSousTitre
                    .frame(maxWidth: .infinity, alignment: .leading)
                iconeMenu
                    .padding(.horizontal, -retraitGlyphe)
            }
        }
    }

    private var titreEtSousTitre: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(championnat.nom)
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)        // 15,37:1 sur le beige
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // `secondaire` (9,32:1) : `grisSecondaire` n'y tenait que 4,71:1, trop juste
            // à 13 pt sur le beige.
            Text(tp("championnat.membresSaison", effectif))
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.secondaire)
        }
        .accessibilityElement(children: .combine)
    }

    /// La photo **de la liste rechargée** dès qu'elle y figure : ``championnat`` est celui
    /// reçu à l'ouverture, et une photo envoyée depuis le menu n'y entrerait jamais.
    private var photo: URL? {
        if case .pret(let liste) = mesChampionnats.etat,
           let courant = liste.first(where: { $0.id == championnat.id }) {
            return courant.photoUrl
        }
        return championnat.photoUrl
    }

    /// Les trois options du menu — **un seul propriétaire** pour ``menuChampionnat`` et
    /// ``menuSurPhoto``, qui n'en diffèrent que par leur déclencheur. Range l'action
    /// destructive en rouge, en dernier — ce que l'utilisateur d'iOS attend sans lire.
    ///
    /// Renommer viendra avec `PATCH /championnats/{id}`.
    @ViewBuilder private var optionsChampionnat: some View {
        Button {
            codeAffiche = true
        } label: {
            Label(t("championnat.codeInvitation"), systemImage: "person.badge.plus")
        }

        if championnat.estCreateur {
            Button {
                selecteurPhoto = true
            } label: {
                Label(t("championnat.modifierPhoto"), systemImage: "photo")
            }
        }

        Button(role: .destructive) {
            confirmationDepart = true
        } label: {
            Label(t("championnat.quitterLeChampionnat"), systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    /// Les trois points : icône nue, zone tactile 44 × 44 pt (le plancher iOS). Un `Menu`
    /// natif — il s'ouvre depuis son déclencheur et se referme vers lui, porte seul
    /// l'accessibilité. Monté par ``entete``, à droite de la photo.
    private var iconeMenu: some View {
        Menu {
            optionsChampionnat
        } label: {
            Group {
                if occupe {
                    ProgressView()
                        .tint(.secondaire)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondaire)       // 9,32:1 sur le beige
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(occupe)
        .accessibilityLabel(envoiPhoto ? t("championnat.a11y.envoiPhoto") : t("championnat.a11y.options"))
    }

    /// > **Non monté.** L'en-tête a désormais une seule mise en page, photo ou initiale
    /// > comprise (``entete``) ; le décalage du ⋯ y est porté par `retraitGlyphe`.
    ///
    /// Les trois points, **sans photo** : décalé pour que son cadre de 44 pt ne dépasse pas
    /// la marge latérale à droite ni le sommet du titre à gauche.
    private var menuChampionnat: some View {
        iconeMenu
            .padding(.trailing, -10)
            .padding(.top, -6)
    }

    /// > **Non monté.** Le bouton ⋯ est redescendu à côté de la photo au lieu d'être posé
    /// > dessus (§En-tête, ``entete``) : plus de superposition, donc plus besoin
    /// > d'un déclencheur pensé pour rester lisible sur une image quelconque. Le composant
    /// > reste en place (`CLAUDE.md` §6).
    ///
    /// Les trois points, **posés sur la photo** : une capsule noire à 40 % d'opacité plutôt
    /// qu'une icône nue, dont le contraste dépendrait des couleurs de la photo — le même
    /// principe que le bouton appareil photo de ``ProfilView`` (« un matériau plutôt qu'un
    /// voile coloré »). 32 pt, dans le coin supérieur droit de la photo. L'icône passe au
    /// blanc : `grisSecondaire` était réglé pour un fond clair, il s'effacerait sur un fond
    /// sombre.
    private var menuSurPhoto: some View {
        Menu {
            optionsChampionnat
        } label: {
            Group {
                if occupe {
                    ProgressView()
                        .tint(.encreSurAplat)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.encreSurAplat)
                }
            }
            .frame(width: 32, height: 32)
            .background(Color.voile.opacity(0.4), in: Capsule())
            .contentShape(Capsule())
        }
        .disabled(occupe)
        .accessibilityLabel(envoiPhoto ? t("championnat.a11y.envoiPhoto") : t("championnat.a11y.options"))
    }

    // MARK: - Le sélecteur

    /// ``SelecteurSegmente`` et non plus le `Picker` segmenté natif : sous iOS 26 celui-ci
    /// écrivait en blanc sur un gris clair, presque illisible, sans se laisser teinter.
    /// Actif en pastille `primaire` pleine, inactif en `secondaire` sur fond neutre ; la
    /// pastille glisse comme celle du contrôle natif.
    private var selecteur: some View {
        SelecteurSegmente(titre: t("championnat.affichage"),
                          options: [(Vue.classement, t("championnat.classement")),
                                    (Vue.piste, t("championnat.piste"))],
                          selection: $vue)
    }

    // MARK: - Le contenu « Classement »

    private func contenuClassement(_ membres: [Membre]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                // Tant que le dernier Grand Prix couru est provisoire, le classement peut
                // encore bouger au calcul définitif (24 h après la course). La mention se
                // pose au-dessus du bloc, alignée sur sa marge droite, sans rien décaler
                // quand elle disparaît le lendemain.
                if membres.first?.resultatsProvisoires == true {
                    HStack {
                        Spacer(minLength: 0)
                        MentionProvisoire(encre: .secondaire)   // 9,32:1 sur le beige
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, -4)
                    .arriveeEnCascade(rang: 0)
                }
                listeClassement(membres)
                // Après la dernière ligne — au cinquième rang au plus.
                lienResultats
                    .arriveeEnCascade(rang: membres.count)
            }
            .padding(.horizontal, margeLaterale)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Le lien vers les résultats par Grand Prix

    /// La carte d'entrée de ``ResultatsParGPView`` — celle de la version web, au même
    /// endroit. **Le libellé nomme sa destination** ; l'icône est le drapeau à damier de
    /// « Mes Grands Prix », avec le même habillage (``TuileDrapeauDamier``) : les deux
    /// cellules ouvrent des Grands Prix.
    private var lienResultats: some View {
        NavigationLink {
            ResultatsParGPView(championnat: championnat)
        } label: {
            HStack(spacing: 12) {
                TuileDrapeauDamier()

                VStack(alignment: .leading, spacing: 2) {
                    Text(t("championnat.resultatsParGP"))
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                        .foregroundColor(.texte)                 // 15,37:1 sur le blanc
                    Text(t("championnat.resultatsParGPSousTitre"))
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.grisSecondaire)        // 5,33:1 sur le blanc
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.grisSecondaire)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 44)
            // Damier en filigrane, gris d'origine : la carte ouvre des Grands Prix, le
            // motif du drapeau à damier s'y devine. Sous-titre à 4,98:1 au pire pixel.
            .background {
                ZStack {
                    Color.surface
                    Damier(opacite: Materiau.damierFiligrane)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
            .ombreCarte()
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.grandeSurface))
    }

    // MARK: - Le lien vers la piste

    /// > **Non monté depuis le sélecteur segmenté.** La piste s'affiche de nouveau en place,
    /// > sous l'en-tête ; ce bouton et l'écran plein qu'il poussait restent disponibles.
    ///

    /// **Un bouton pleine largeur, et non plus un segment de bascule.** La piste est
    /// devenue un écran plein (``VuePisteView``) : un segment l'aurait ouverte en
    /// remplaçant le contenu *sous* un en-tête resté là, ce que « plein écran » exclut.
    ///
    /// C'est l'arbitrage de la version web, au même endroit et pour la même raison — les
    /// deux ensemble auraient offert **deux chemins vers le même écran**, à trois
    /// centimètres l'un de l'autre. L'aller-retour reste symétrique : l'écran de piste
    /// ramène ici par son propre bouton de retour.
    ///
    /// **Aucune icône.** Le libellé nomme sa destination, ce que le wayfinding demande.
    /// Le damier reste, à ses 15 % habituels : sur le bordeaux `primaire` il ramène le fond
    /// à `#7B0F1D`, où le blanc tient encore **10,89:1**.
    ///
    /// `NavigationLink` et non `Button` : c'est lui qui porte le glissement d'écran natif
    /// et le geste de retour par le bord, qu'un `Button` poussant un état ne donne pas.
    private func lienPiste(_ membres: [Membre]) -> some View {
        NavigationLink {
            VuePisteView(championnat: championnat, membres: membres)
        } label: {
            Text(t("championnat.vuePiste"))
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .foregroundColor(.encreSurAplat)
                .frame(maxWidth: .infinity)
                .frame(height: 56)              // > 44 pt, contrainte tactile iOS
                .background {
                    ZStack {
                        Color.primaire
                        Damier(opacite: Materiau.damier)
                        LueurHaute()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
                .ombreAplat()
        }
        .buttonStyle(StyleAppui(.bouton))
    }

    // MARK: - Le classement

    /// Un seul bloc blanc, une ligne par membre.
    ///
    /// **Aucune règle horizontale entre les lignes** : le design system les proscrit
    /// (`docs/swift-app.md` §4.6, « jamais une règle horizontale »). Ce sont le filet de
    /// 4 pt posé *à l'intérieur* de chaque ligne — l'exception explicite de cette même
    /// section — et l'espace qui les séparent.
    private func listeClassement(_ membres: [Membre]) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(membres.enumerated()), id: \.element.id) { rang, membre in
                // `NavigationLink` et non `Button` : c'est lui qui porte le glissement
                // d'écran natif et le geste de retour par le bord, qu'un `Button` poussant
                // un état ne donne pas.
                NavigationLink {
                    ProfilMembreView(membre: membre.profil(dans: championnat.id))
                } label: {
                    LigneClassement(membre: membre, total: membres.count)
                }
                .buttonStyle(StyleAppui(.grandeSurface))
                .arriveeEnCascade(rang: rang)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

}

// MARK: - La silhouette du classement

/// Le classement pendant son premier chargement : le bloc blanc de ``listeClassement``
/// (rembourrage 12, `Rayon.bloc`), cinq lignes esquissées — rang, avatar, nom et détail,
/// score — puis la carte « Résultats par Grand Prix ».
private struct SqueletteClassement: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in ligne }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
            .ombreBloc()

            SkeletonView(.blocRectangulaire, hauteur: 72)
        }
    }

    private var ligne: some View {
        HStack(spacing: 12) {
            SkeletonView(.blocCarre, largeur: 18, hauteur: 18, rayon: 9)
            SkeletonView(.blocCarre, largeur: 36, hauteur: 36, rayon: 18)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView(.ligneLongue, hauteur: 12)
                    .padding(.trailing, 40)
                SkeletonView(.ligneCourte, largeur: 80, hauteur: 10)
            }
            SkeletonView(.ligneCourte, largeur: 40, hauteur: 16)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(minHeight: 50)
    }
}

// MARK: - Une ligne du classement

/// Rang, avatar, nom, détail, score.
///
/// **Le sous-titre ne répète pas le score.** La maquette pose « 3 420 pts » sous le nom et
/// « 3420 » à droite : le même nombre deux fois, et la ligne n'apprend rien de plus. La
/// version web l'a tranché à l'usage (`screen-13`) en mettant là ce que le score ne dit
/// pas — les pronostics réussis et le meilleur coup. C'est cette version-là qui est reprise.
// MARK: - La photo du championnat

/// La photo du championnat, ou son initiale sur l'aplat ``Color/primaire`` (`#800111`).
///
/// **Montée seulement quand le championnat a une photo** (``ChampionnatDetailView``) : sans
/// photo, l'en-tête n'en réserve plus la place. L'initiale ne sert donc plus que pendant le
/// chargement, pour qu'une photo lente n'ouvre pas un trou blanc dans l'en-tête.
/// Carrée, rayon `widget` : à 72–100 pt, le rayon `champ` d'une vignette de 56 pt se
/// lisait comme un coin presque vif. **Son côté est celui que lui propose** ``DispositionEntete`` :
/// photo et initiale suivent les mêmes dimensions, sans qu'aucune ne les fixe.
private struct PhotoChampionnat: View {

    let nom: String
    let photo: URL?

    var body: some View {
        GeometryReader { cadre in
            Group {
                if let photo {
                    ImageCachee(url: photo) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        initiale(cote: cadre.size.width)
                    }
                } else {
                    initiale(cote: cadre.size.width)
                }
            }
            .frame(width: cadre.size.width, height: cadre.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Blanc sur `#800111` : **10,88:1**.
    private func initiale(cote: CGFloat) -> some View {
        Color.primaire.overlay {
            Text(nom.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                .font(.custom("HelveticaNeue-Medium", size: cote * 0.40625))
                .foregroundColor(.encreSurAplat)
        }
    }
}

// MARK: - Les deux contenus

private extension View {
    /// Un des deux contenus superposés : visible et actif, ou transparent, inerte et tu
    /// aux technologies d'assistance — jamais démonté.
    ///
    /// > **Masqué à 0,001, pas à 0.** SwiftUI ne dessine pas une vue d'opacité nulle : la
    /// > piste ne rastérisait alors ses `Canvas` qu'à la première bascule, et la pastille
    /// > perdait une à trois images au départ — mesuré à l'enregistrement du simulateur,
    /// > trois lancements sur trois. À 0,001 la vue est dessinée d'avance, et reste
    /// > invisible : 0,001 × 255 s'arrondit à zéro.
    func visible(_ affiche: Bool) -> some View {
        opacity(affiche ? 1 : 0.001)
            .allowsHitTesting(affiche)
            .accessibilityHidden(!affiche)
    }
}

/// La piste intégrée, **comparée avant d'être réévaluée** (`.equatable()`). Chaque bascule
/// réévalue l'écran, qui reconstruit le tableau des membres ; à valeurs égales, la piste ne
/// recalcule ni ses placements ni ses `Canvas`.
private struct PisteIntegree: View, Equatable {

    let championnat: Championnat
    let membres: [Membre]

    var body: some View {
        VuePisteView(championnat: championnat, membres: membres, integree: true)
    }
}

// MARK: - La disposition de l'en-tête

/// Titre, photo, ⋯ — **centrés sur l'axe vertical**, la photo **à équidistance** du texte
/// et du ⋯, mesurés sur leurs parties visibles (le texte à sa largeur réelle, le ⋯ à son
/// glyphe : l'appelant retire le cadre tactile par une marge négative).
///
/// **Le côté de la photo se choisit, il ne se subit pas** : 100 pt tant que le titre tient
/// en deux lignes dans ce qu'il reste ; sinon réduit par pas de 2 pt, jamais sous 72 pt.
/// Le titre est mesuré par TextKit dans sa police exacte — la question « combien de
/// lignes ? » n'a pas de réponse côté `Layout`, où un texte limité à deux lignes rend la
/// même hauteur qu'il soit coupé ou non. Le texte ne reçoit jamais plus que la largeur
/// laissée par la photo et les deux écarts minimaux : **il ne la chevauche pas.**
private struct DispositionEntete: Layout {

    let titre: String

    private let coteMax: CGFloat = 100
    private let coteMin: CGFloat = 72
    private let ecartMin: CGFloat = 16

    private struct Mesure {
        let cote: CGFloat
        let texte: CGSize
        let menu: CGSize
        let hauteur: CGFloat
    }

    private func mesurer(largeur: CGFloat, _ vues: Subviews) -> Mesure {
        let menu = vues[2].sizeThatFits(.unspecified)
        let libre = largeur - menu.width - 2 * ecartMin
        var cote = coteMax
        while cote > coteMin, lignes(dans: libre - cote) > 2 { cote -= 2 }
        let texte = vues[0].sizeThatFits(ProposedViewSize(width: max(0, libre - cote), height: nil))
        return Mesure(cote: cote, texte: texte, menu: menu,
                      hauteur: max(texte.height, cote, menu.height))
    }

    /// Le nombre de lignes du titre à cette largeur, dans la police de ``Font/titre``.
    private func lignes(dans largeur: CGFloat) -> Int {
        guard largeur > 0, let police = UIFont(name: "HelveticaNeue-Medium", size: 28) else { return .max }
        let texte = NSAttributedString(string: titre,
                                       attributes: [.font: police, .kern: Tracking.titre])
        let boite = texte.boundingRect(with: CGSize(width: largeur, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading],
                                       context: nil)
        return Int((boite.height / police.lineHeight).rounded())
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? 361
        return CGSize(width: largeur, height: mesurer(largeur: largeur, subviews).hauteur)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = mesurer(largeur: bounds.width, subviews)
        let ecart = (bounds.width - m.texte.width - m.cote - m.menu.width) / 2
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(m.texte))
        subviews[1].place(at: CGPoint(x: bounds.minX + m.texte.width + ecart, y: bounds.midY),
                          anchor: .leading, proposal: ProposedViewSize(width: m.cote, height: m.cote))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                          proposal: ProposedViewSize(m.menu))
    }
}

private struct LigneClassement: View {

    let membre: Membre
    let total: Int

    /// Le sous-titre. **Pas de meilleur coup tant que rien n'est réussi** : `nil` veut dire
    /// « aucun », et « meilleur coup 0 pts » le confondrait avec un coup raté
    /// (`CLAUDE.md` §3.1).
    private var detail: String {
        let reussis = tp("classement.reussis", membre.pronosticsReussis)
        guard let meilleur = membre.meilleureCote else { return reussis }
        return t("classement.reussisMeilleurCoup", reussis, meilleur)
    }

    var body: some View {
        HStack(spacing: 12) {
            filet
            rang
            avatar

            VStack(alignment: .leading, spacing: 1) {
                Text(membre.pseudo)
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                    .foregroundColor(.texte)                 // 15,37:1 sur le blanc
                    .lineLimit(1)

                // `grisSecondaire` (5,33:1 sur le blanc) et non le `#999999` de la
                // maquette, qui n'y vaut que 2,85:1.
                Text(detail)
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.grisSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            score
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(minHeight: 44)                                // plancher tactile iOS
        // **La ligne entière est la cible**, pas ses seuls textes. Sans cela, le lien vers
        // le profil ne répondrait qu'au pseudo et au score, et l'intervalle entre les deux
        // lignes de texte — au milieu de la ligne, là où le doigt tombe — resterait mort.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            t("classement.a11y.ligne", ordinal(membre.rang), total, membre.pseudo,
              tp("classement.a11y.points", membre.totalPoints),
              tp("classement.a11y.reussis", membre.pronosticsReussis))
            + (membre.meilleureCote.map { t("classement.a11y.meilleurCoup", $0) } ?? ".")
        )
    }

    /// > **Non monté.** Le damier est retiré des lignes du classement ; il reste sur le
    /// > sélecteur et la carte « Résultats par Grand Prix ».
    ///
    /// **Le podium porte un damier `primaire` en filigrane** (``Materiau/damierFiligrane``),
    /// les autres lignes rien. Au pire pixel : `grisSecondaire` 4,83:1, le score 9,87:1,
    /// le pseudo 15,79:1 — le motif ne coûte rien à la lecture. Il déborde de 4 pt à
    /// gauche, sous le filet, pour que celui-ci reste posé *dans* la ligne.
    @ViewBuilder private var fondPodium: some View {
        if membre.rang <= 3 {
            Damier(opacite: Materiau.damierFiligrane, encre: .primaire)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
                .padding(.horizontal, -4)
        }
    }

    /// Le filet de 4 pt — **l'exception explicite à l'interdiction des bordures fines**
    /// (`docs/swift-app.md` §4.6) : c'est un aplat posé à l'intérieur de la ligne, pas un
    /// trait qui la cerne. Il prend la teinte du membre, la même que son avatar, et c'est
    /// lui qui sépare deux lignes sans qu'aucune règle horizontale ne traverse le bloc.
    private var filet: some View {
        Capsule()
            .fill(Color.teinteAvatar(pour: membre.cleTeinte))
            .frame(width: 4, height: 36)
            .accessibilityHidden(true)
    }

    /// **Le rouge de la marque pour les trois premiers, le gris pour les autres.** Le
    /// podium est la seule distinction que le classement général fait, et la couleur la
    /// dit sans ajouter un mot.
    ///
    /// `grisSecondaire` (5,33:1) et non le `#bbb` de la maquette, qui ne vaut que 2,0:1 sur
    /// le blanc — un chiffre n'est pas décoratif, il doit se lire.
    private var rang: some View {
        Text(String(membre.rang))
            .font(.custom("HelveticaNeue-Medium", size: 16))
            .foregroundColor(membre.rang <= 3 ? .encrePrimaire : .grisSecondaire)
            .frame(width: 20, alignment: .leading)
    }

    /// La photo du membre, ou son initiale sur sa teinte — ``PastilleProfil``, comme dans
    /// ``ResultatsParGPView``. La teinte se tire de son identifiant par
    /// ``Color/teinteAvatar(pour:)`` : elle est donc **stable d'un lancement à l'autre** et
    /// la même dans tous les championnats où il figure.
    private var avatar: some View {
        PastilleProfil(pseudo: membre.pseudo, photo: membre.avatarUrl,
                       fond: .teinteAvatar(pour: membre.cleTeinte), taille: 36)
            .accessibilityHidden(true)
    }

    /// Le total, en rouge. **`PTS` sous le nombre, pas accolé à lui** : c'est l'unité, pas
    /// une partie du score, et la mettre sur la même ligne la ferait lire comme un chiffre
    /// de plus.
    private var score: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(String(membre.totalPoints))
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .tracking(-0.50)                              // −0,025em × 20
                .foregroundColor(.encrePrimaire)                   // 10,88:1 sur le blanc
                .lineLimit(1)

            Text(t("points.unite"))
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)
        }
        .fixedSize()
    }
}

// MARK: - Le widget du Grand Prix suivant

/// L'aplat rouge qui fermait le classement : quel Grand Prix vient, et quand il ferme.
///
/// > **Non monté.** Retiré de l'onglet Classement, sans remplacement : l'accueil annonce
/// > déjà le Grand Prix suivant. Le composant reste en place (`CLAUDE.md` §6).
///
/// **Une carte informative, pas un lien.** Pas de bouton ni de chevron : le chemin vers
/// les pronostics passe par l'accueil, et une seconde porte ici ferait doublon.
private struct WidgetGrandPrixSuivant: View {

    let grandPrix: ProchainGP

    private var nom: String { grandPrix.nomAffiche }

    /// Ce que dit la seconde ligne — ``EcheancePronostics/phrase``, **le seul calcul
    /// d'échéance de l'app**. Lu à l'affichage : l'écran se recharge à chaque apparition,
    /// une précision à la minute n'a pas à battre en direct ici.
    private var echeance: String { grandPrix.echeance().phrase }

    var body: some View {
        aplat
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t("championnat.a11y.prochainGP", nom, echeance))
    }

    private var aplat: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nom)
                    .font(.custom("HelveticaNeue-Medium", size: 16))
                    .foregroundColor(.encreSurAplat)              // 10,88:1 sur #800111
                    .lineLimit(1)

                // **`encreSecondaire` (blanc à 70 %, 5,75:1) et non le blanc à 60 % de
                // la maquette**, qui compose `#D9B3B8` sur le rouge — 4,47:1, sous le
                // plancher de 4,5:1 d'un texte ordinaire.
                Text(echeance)
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.encreSecondaire)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            // Aplat de la marque, galbé par la lumière spéculaire comme tous les
            // aplats de l'app. Pas de damier : le widget est une bande basse, et le
            // motif y passerait pour du bruit plutôt que pour une texture.
            ZStack {
                Color.primaire
                LueurHaute()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreAplat()                                     // aplat de couleur (§4.7)
    }
}

// MARK: - Le code d'invitation

/// Le code, en grand, et le partage système. **Une feuille compacte, pas un écran** : on
/// vient chercher six caractères, on repart — un glissement vers le bas suffit à la fermer.
///
/// Le code se lit aussi à voix haute caractère par caractère : `F1X7K2` prononcé d'un bloc
/// ne se recopie pas.
private struct FeuilleCodeInvitation: View {

    let championnat: Championnat

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(t("championnat.codeInvitation"))
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.grisSecondaire)       // 4,71:1 sur le beige

                Text(championnat.codeInvitation)
                    .font(.scoreLg)
                    .tracking(6)
                    .foregroundColor(.texte)                // 15,37:1 sur le beige
                    .textSelection(.enabled)
                    .accessibilityLabel(championnat.codeInvitation.map(String.init).joined(separator: " "))

                Text(t("championnat.partageIndication", championnat.nom))
                    .font(.corpsSm)
                    .foregroundColor(.grisSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // La même phrase que l'écran « Créer » : l'ami la reçoit à l'identique, d'où
            // qu'on la lui envoie.
            ShareLink(item: t("championnat.messagePartage", championnat.nom, championnat.codeInvitation)) {
                Label(t("commun.partager"), systemImage: "square.and.arrow.up")
                    .habillageBoutonPrincipal(actif: true)
            }
            .buttonStyle(StyleAppui(.bouton))
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.fondPrincipal)
    }
}

// MARK: - Un membre, vu par les écrans

extension Membre {
    /// La ligne, avec **la voiture du profil** quand c'est celle du compte connecté —
    /// livrée, couleurs, numéro et photo du cockpit. Le reste (points, rang) reste celui
    /// du serveur.
    /// Sans profil, ou pour un autre membre, la ligne est rendue telle quelle.
    func avecVoiture(de profil: Profil?) -> Membre {
        guard let profil, profil.id == profilId else { return self }
        return Membre(profilId: profilId, pseudo: pseudo, totalPoints: totalPoints,
                      pronosticsReussis: pronosticsReussis, meilleureCote: meilleureCote,
                      rang: rang, ordreInscription: ordreInscription,
                      couleur1: profil.couleur1, couleur2: profil.couleur2,
                      couleurTexte: profil.couleurTexte, numero: profil.numero,
                      livreeMode: profil.livreeMode, livreeEcurie: profil.livreeEcurie,
                      avatarUrl: profil.avatarUrl)
    }

    /// Ce que porte sa voiture. Un slug d'écurie inconnu retombe sur la livrée perso à
    /// l'affichage (``Livree/ecurieChoisie``), ce n'est pas une panne.
    var livree: Livree {
        Livree(mode: livreeMode == .ecurie ? .ecurie : .perso,
               ecurie: livreeEcurie,
               coque: couleur1,
               ailerons: couleur2,
               couleurTexte: couleurTexte)
    }

    /// Le numéro peint sur le museau. **Pas de numéro choisi ⇒ le rang**, jamais `0`
    /// (`docs/swift-app.md` §3.2).
    var numeroAffiche: String { String(numero ?? rang) }

    /// Le profil tel que ``ProfilMembreView`` l'attend, **de ce que le classement sait
    /// seul** — affiché sans attendre. Les statistiques qu'il ne sert pas s'affichent « – »
    /// sous le spinner : les calculer ici serait les inventer. `GET /profils/{id}/stats`
    /// les remplace dès qu'il répond.
    func profil(dans championnat: UUID) -> MembreProfil {
        MembreProfil(
            identifiant: cleTeinte,
            profilId: profilId,
            championnatId: championnat,
            rang: rang,
            pseudo: pseudo,
            photo: avatarUrl,
            livree: livree,
            numero: numeroAffiche,
            grandsPrixJoues: nil,
            statistiques: [
                StatistiqueProfil(valeur: StatistiqueProfil.absente, libelle: t("stats.parisGagnes")),
                StatistiqueProfil(valeur: StatistiqueProfil.absente, libelle: t("stats.ptsMoyens")),
                StatistiqueProfil(valeur: meilleureCote.map(String.init) ?? StatistiqueProfil.absente,
                                  libelle: t("stats.meilleurCoup")),
                StatistiqueProfil(valeur: StatistiqueProfil.absente, libelle: t("stats.coteMoyenne"))
            ]
        )
    }
}

// MARK: - Données mockées

/// Un membre du classement. `points` est un **entier**, et c'est déjà le nombre de points :
/// `CLAUDE.md` §3.1 — une cote de 2,80 vaut 28 points, et rien en base ne stocke une cote.
///
/// **Le type n'est pas `private`** : c'est lui qui alimente ``ProfilMembreView``, et un
/// second jeu de valeurs mockées pour le profil aurait fait dire deux choses différentes du
/// même membre — un meilleur coup au classement, un autre sur sa fiche.
struct MembreMock: Identifiable {
    /// L'identifiant du compte. C'est de lui que se tire la teinte de l'avatar, jamais du
    /// rang : un membre qui perd une place ne change pas de couleur.
    let id: String
    let pseudo: String
    let points: Int
    let rang: Int
    /// Pronostics réussis sur la saison.
    let reussis: Int
    /// Pronostics **tentés** sur la saison — obligatoires et bonus confondus. C'est le
    /// dénominateur de « Paris gagnés », et il est mocké plutôt que calculé : le nombre de
    /// paris par Grand Prix dépend des bonus retenus, que rien ici ne connaît.
    let tentes: Int
    /// Le meilleur coup de la saison, en points. **Jamais une cote.**
    let meilleurCoup: Int
    /// Grands Prix joués cette saison. C'est le diviseur de « Pts moy. / GP ».
    let grandsPrixJoues: Int
    /// La moyenne des paris tentés, **en points** — c'est ce que la tuile « Cote moy.
    /// tentée » affiche, et le mot « cote » n'y est qu'un libellé hérité de la version web :
    /// la valeur est un entier de points (`CLAUDE.md` §3.1).
    let moyenneTentee: Int
    /// Ce que porte sa voiture, et le numéro peint sur son museau.
    let livree: Livree
    let numero: String

    /// Le profil tel que ``ProfilMembreView`` l'attend. **Les quatre statistiques sont
    /// mises en forme ici**, à côté des chiffres bruts dont elles sortent : l'écran qui les
    /// affiche n'est alors jamais celui qui décide de leur arrondi.
    var profil: MembreProfil {
        MembreProfil(
            identifiant: id,
            pseudo: pseudo,
            livree: livree,
            numero: numero,
            grandsPrixJoues: grandsPrixJoues,
            statistiques: [
                StatistiqueProfil(valeur: "\(pourcentageReussite)%", libelle: t("stats.parisGagnes")),
                StatistiqueProfil(valeur: String(pointsMoyensParGrandPrix), libelle: t("stats.ptsMoyens")),
                StatistiqueProfil(valeur: String(meilleurCoup), libelle: t("stats.meilleurCoup")),
                StatistiqueProfil(valeur: String(moyenneTentee), libelle: t("stats.coteMoyenne"))
            ]
        )
    }

    /// Zéro pari tenté ne fait pas 0 % mais **rien à dire** : `NULL` et `0` ne se confondent
    /// jamais (`CLAUDE.md` §3.1), et une saison pas encore commencée n'est pas une saison
    /// ratée.
    private var pourcentageReussite: Int {
        tentes > 0 ? Int((Double(reussis) / Double(tentes) * 100).rounded()) : 0
    }

    private var pointsMoyensParGrandPrix: Int {
        grandsPrixJoues > 0 ? Int((Double(points) / Double(grandsPrixJoues)).rounded()) : 0
    }

    /// Huit membres, repris de `screen-13` : de quoi remplir le plus grand des championnats
    /// mockés. Un championnat plus petit en prend le préfixe.
    ///
    /// **Les valeurs de Matthieu et de 7homas sont celles des captures** — `screen-20`
    /// pour le premier (33 %, 31, 25, 46), `screen-22` pour le second (40 %, 33, 22, 41) —
    /// et elles tombent juste parce que les chiffres bruts les redonnent : 66 points en
    /// 2 Grands Prix font bien 33, et 4 réussis sur 10 tentés font bien 40 %.
    ///
    /// > ### Les huit scores sont le jeu d'essai de la vue piste
    /// >
    /// > **168, 93, 66, 50, 47, 26, 24, 0** — ceux de `maquettes_V2/screen-14-vue-piste.PNG`,
    /// > posés ici pour que le simulateur montre exactement ce que la maquette montre. Les
    /// > deux derniers ont changé en même temps que l'échelle de la piste : il fallait un
    /// > membre à **zéro** pour voir la ligne du bas, et deux scores **voisins** (26 et 24)
    /// > pour voir l'éventail les écarter.
    /// >
    /// > Les statistiques suivent le score, elles ne le contredisent jamais : Julie n'a
    /// > **aucun** pronostic réussi, donc aucun meilleur coup — `0` veut dire « raté », et
    /// > `CLAUDE.md` §3.1 interdit de le confondre avec « pas encore jugé ».
    static let exemples: [MembreMock] = [
        MembreMock(id: "nicolas", pseudo: "Nicolas", points: 168, rang: 1,
                   reussis: 9, tentes: 25, meilleurCoup: 42,
                   grandsPrixJoues: 5, moyenneTentee: 38,
                   livree: Livree(mode: .perso, coque: "#CC0000", ailerons: "#FFFFFF"),
                   numero: "1"),
        MembreMock(id: "matthieu", pseudo: "Matthieu", points: 93, rang: 2,
                   reussis: 5, tentes: 15, meilleurCoup: 25,
                   grandsPrixJoues: 3, moyenneTentee: 46,
                   livree: Livree(mode: .perso, coque: "#CC0000", ailerons: "#003087",
                                  couleurTexte: "#00D2BE"),
                   numero: "33"),
        MembreMock(id: "7homas", pseudo: "7homas", points: 66, rang: 3,
                   reussis: 4, tentes: 10, meilleurCoup: 22,
                   grandsPrixJoues: 2, moyenneTentee: 41,
                   livree: Livree(mode: .perso, coque: "#2D2D2D", ailerons: "#00A19C",
                                  couleurTexte: "#00D2BE"),
                   numero: "44"),
        MembreMock(id: "clem1500", pseudo: "Clem1500", points: 50, rang: 4,
                   reussis: 2, tentes: 10, meilleurCoup: 25,
                   grandsPrixJoues: 2, moyenneTentee: 33,
                   livree: Livree(mode: .perso, coque: "#E8027B", ailerons: "#FFFFFF"),
                   numero: "27"),
        MembreMock(id: "petiotte", pseudo: "Petiotte", points: 47, rang: 5,
                   reussis: 2, tentes: 10, meilleurCoup: 35,
                   grandsPrixJoues: 2, moyenneTentee: 39,
                   livree: Livree(mode: .perso, coque: "#003087", ailerons: "#FFD700"),
                   numero: "10"),
        MembreMock(id: "camikaz", pseudo: "Camikaz", points: 26, rang: 6,
                   reussis: 2, tentes: 10, meilleurCoup: 14,
                   grandsPrixJoues: 2, moyenneTentee: 22,
                   livree: Livree(mode: .ecurie, ecurie: "mclaren"),
                   numero: "7"),
        MembreMock(id: "lucas", pseudo: "Lucas", points: 24, rang: 7,
                   reussis: 1, tentes: 5, meilleurCoup: 24,
                   grandsPrixJoues: 1, moyenneTentee: 26,
                   livree: Livree(mode: .perso, coque: "#FF8000", ailerons: "#000000"),
                   numero: "81"),
        MembreMock(id: "julie", pseudo: "Julie", points: 0, rang: 8,
                   reussis: 0, tentes: 5, meilleurCoup: 0,
                   grandsPrixJoues: 1, moyenneTentee: 19,
                   livree: Livree(mode: .perso, coque: "#960064", ailerons: "#C0C0C0"),
                   numero: "22")
    ]
}

// MARK: - Aperçus

extension MembreMock {
    /// Le membre mocké sous la forme que sert le serveur — **pour les aperçus seulement**,
    /// qui gardent ainsi le jeu d'essai de la piste (`docs/swift-app.md` §5.6).
    var enMembre: Membre {
        Membre(profilId: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rang))!,
               pseudo: pseudo, totalPoints: points, pronosticsReussis: reussis,
               meilleureCote: reussis > 0 ? meilleurCoup : nil,
               rang: rang, ordreInscription: rang,
               couleur1: livree.coque, couleur2: livree.ailerons,
               couleurTexte: livree.couleurTexte, numero: Int(numero),
               livreeMode: livree.mode == .ecurie ? .ecurie : .perso,
               livreeEcurie: livree.ecurie)
    }
}

extension Championnat {
    /// Un championnat d'aperçu, décodé comme le serait une réponse du serveur.
    static let apercu: Championnat = try! JSONDecoder.api.decode(Championnat.self, from: Data("""
        {"id": "5f0c6a1e-2b7d-4c1a-9e3f-8a2b1c0d9e7f", "nom": "Team Bazzana",
         "code_invitation": "F1X7K2", "cree_par": null,
         "cree_le": "2026-08-13T18:23:31+00:00", "nombre_membres": 8,
         "est_createur": true, "photo_url": null,
         "prochain_gp": {"id": "9a1f0c2e-3b4d-4e5f-8a6b-7c8d9e0f1a2b", "nom": "GP Azerbaïdjan",
                         "date_course": "2026-12-27T11:00:00+00:00", "statut": "cotes_figees"}}
        """.utf8))
}

#Preview {
    NavigationStack {
        ChampionnatDetailView(championnat: .apercu, mesChampionnats: MesChampionnats())
    }
}
