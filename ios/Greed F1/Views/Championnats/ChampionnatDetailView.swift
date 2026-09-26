import PhotosUI
import SwiftUI

/// Le détail d'un championnat : son classement, et la porte de la vue piste.
///
/// Références visuelles : `maquettes/maquette-07-championnat.html` pour la composition,
/// `Ressources/Screenshots/screen-13-classement-championnat.PNG` pour ce que la version web
/// en a finalement fait.
///
/// > **Un seul appel pour les deux segments.** ``ClassementChampionnat`` lit
/// > `GET /championnats/{id}/classement` à chaque apparition ; le classement et la piste
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
    /// calculé par le serveur ; le `PATCH` le revérifie de toute façon). Puis le dépôt en
    /// vol et son refus, en alerte pour la même raison que le départ : il part d'un menu.
    @State private var selecteurPhoto = false
    @State private var choixPhoto: PhotosPickerItem?
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

    /// Les deux segments de l'écran.
    private enum Vue: Hashable {
        case classement, piste
    }

    @State private var vue: Vue = .classement

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            // **L'en-tête et le sélecteur ne défilent pas**, le contenu dessous oui. La
            // piste redevient un segment de cet écran : elle s'affiche **en place**, sous
            // l'en-tête, au lieu d'être poussée comme un écran plein.
            VStack(spacing: 0) {
                entete
                    .padding(.horizontal, margeLaterale)
                    .padding(.top, 8)

                selecteur
                    .padding(.horizontal, margeLaterale)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // Un fondu court entre les deux contenus, et rien d'autre : un segment
                // se bascule souvent, un glissement latéral finirait par se faire attendre.
                // L'opacité reste permise en mouvement réduit.
                ZStack {
                    switch classement.etat {
                    case .chargement:
                        ProgressView()
                            .tint(.secondaire)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Chargement du classement")

                    case .echec(let erreur):
                        EchecChargement(erreur: erreur) {
                            Task { await classement.charger() }
                        }
                        .frame(maxHeight: .infinity)

                    case .pret(let servis):
                        let membres = servis.map { $0.avecVoiture(de: monProfil) }
                        switch vue {
                        case .classement:
                            contenuClassement(membres)
                                .transition(.opacity)
                        case .piste:
                            VuePisteView(championnat: championnat, membres: membres,
                                         integree: true)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(Mouvement.entree(Mouvement.passageEcran), value: vue)
            }
        }
        // À chaque apparition, retour du profil d'un membre compris : pas de cache de
        // session (`docs/swift-app.md` §7.6). Le classement affiché reste en place.
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
        .navigationTitle("Classement")
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
        .alert("Quitter « \(championnat.nom) » ?", isPresented: $confirmationDepart) {
            Button("Quitter", role: .destructive) { quitter() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tu disparais du classement. Pour revenir, il te faudra de nouveau le code d'invitation.")
        }
        .alert("Impossible de quitter le championnat",
               isPresented: Binding(get: { erreurDepart != nil },
                                    set: { if !$0 { erreurDepart = nil } }),
               presenting: erreurDepart) { _ in
            Button("OK", role: .cancel) {}
        } message: { erreur in
            Text(erreur.message)
        }
        .photosPicker(isPresented: $selecteurPhoto, selection: $choixPhoto,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: choixPhoto) { _, choix in
            guard let choix else { return }
            envoyerPhoto(choix)
        }
        .alert("Impossible de changer la photo",
               isPresented: Binding(get: { erreurPhoto != nil },
                                    set: { if !$0 { erreurPhoto = nil } }),
               presenting: erreurPhoto) { _ in
            Button("OK", role: .cancel) {}
        } message: { erreur in
            Text(erreur.message)
        }
    }

    /// Charge la photo choisie, la dépose sous le dossier du championnat
    /// (``DepotPhoto``, comme l'avatar), enregistre son URL par `PATCH /championnats/{id}`,
    /// puis recharge la liste — c'est elle qui peint la photo sur les cartes.
    ///
    /// **Tâche non liée à l'écran**, comme ``quitter()`` : l'envoi va au bout même si l'on
    /// revient en arrière entre-temps. La sélection est remise à `nil` à la fin : choisir
    /// deux fois la même photo doit relancer l'envoi.
    private func envoyerPhoto(_ choix: PhotosPickerItem) {
        guard !envoiPhoto else { return }
        envoiPhoto = true
        erreurPhoto = nil
        Task {
            defer {
                envoiPhoto = false
                choixPhoto = nil
            }
            do {
                guard let donnees = try await choix.loadTransferable(type: Data.self) else {
                    throw ErreurAPI.serveur(statut: nil, message: "Photo illisible. Essaie une autre image.")
                }
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
                erreurPhoto = .serveur(statut: nil, message: "Photo illisible. Essaie une autre image.")
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

    private var entete: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(championnat.nom)
                    .font(.titre)
                    .tracking(Tracking.titre)
                    .foregroundColor(.texte)        // 15,37:1 sur le beige
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // `grisSecondaire` (4,71:1) et non le `#999999` de la maquette (2,52:1).
                Text("\(effectif) \(effectif > 1 ? "membres" : "membre") · Saison 2026")
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.grisSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            menuChampionnat
        }
    }

    /// Les trois points. **Un `Menu` natif** : il s'ouvre depuis son déclencheur et se
    /// referme vers lui, porte seul l'accessibilité, et range l'action destructive en
    /// rouge, en dernier — ce que l'utilisateur d'iOS attend sans lire.
    ///
    /// Renommer viendra avec `PATCH /championnats/{id}` ; la zone tactile fait déjà ses
    /// 44 × 44 pt, le plancher iOS.
    private var menuChampionnat: some View {
        Menu {
            Button {
                codeAffiche = true
            } label: {
                Label("Code d'invitation", systemImage: "person.badge.plus")
            }

            if championnat.estCreateur {
                Button {
                    selecteurPhoto = true
                } label: {
                    Label("Modifier la photo", systemImage: "photo")
                }
            }

            Button(role: .destructive) {
                confirmationDepart = true
            } label: {
                Label("Quitter le championnat", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Group {
                if occupe {
                    ProgressView()
                        .tint(.grisSecondaire)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.grisSecondaire)   // 4,71:1 sur le beige
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(occupe)
        .accessibilityLabel(envoiPhoto ? "Envoi de la photo" : "Options du championnat")
        // L'icône est centrée sur 44 pt : sans ce décalage, le bouton dépasserait la marge
        // latérale à droite et le sommet du titre à gauche.
        .padding(.trailing, -10)
        .padding(.top, -6)
    }

    // MARK: - Le sélecteur

    /// **Un `Picker` segmenté natif** : c'est le contrôle qu'iOS donne à « deux vues du
    /// même objet », et il porte seul l'accessibilité, le retour d'appui et le glissement
    /// de la pastille. Rien ici ne le redessine.
    private var selecteur: some View {
        Picker("Affichage", selection: $vue) {
            Text("Classement").tag(Vue.classement)
            Text("Piste").tag(Vue.piste)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Le contenu « Classement »

    private func contenuClassement(_ membres: [Membre]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                listeClassement(membres)
                lienResultats
            }
            .padding(.horizontal, margeLaterale)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Le lien vers les résultats par Grand Prix

    /// La carte d'entrée de ``ResultatsParGPView`` — celle de la version web, au même
    /// endroit. **Le libellé nomme sa destination** ; l'icône est le pilote casqué, car
    /// l'écran montre des personnes, pas des dates.
    private var lienResultats: some View {
        NavigationLink {
            ResultatsParGPView(championnat: championnat)
        } label: {
            HStack(spacing: 12) {
                Image("icone-profil")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 20)
                    .foregroundColor(.primaire)
                    .frame(width: 40, height: 40)
                    .background(Color.fondPrincipal)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Résultats par Grand Prix")
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                        .foregroundColor(.texte)                 // 15,37:1 sur le blanc
                    Text("Les paris de chaque membre, course par course")
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
            .background(Color.surface)
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
            Text("Vue piste")
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .foregroundColor(.white)
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
            ForEach(membres) { membre in
                // `NavigationLink` et non `Button` : c'est lui qui porte le glissement
                // d'écran natif et le geste de retour par le bord, qu'un `Button` poussant
                // un état ne donne pas.
                NavigationLink {
                    ProfilMembreView(membre: membre.profil(dans: championnat.id))
                } label: {
                    LigneClassement(membre: membre, total: membres.count)
                }
                .buttonStyle(StyleAppui(.grandeSurface))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

}

// MARK: - Une ligne du classement

/// Rang, avatar, nom, détail, score.
///
/// **Le sous-titre ne répète pas le score.** La maquette pose « 3 420 pts » sous le nom et
/// « 3420 » à droite : le même nombre deux fois, et la ligne n'apprend rien de plus. La
/// version web l'a tranché à l'usage (`screen-13`) en mettant là ce que le score ne dit
/// pas — les pronostics réussis et le meilleur coup. C'est cette version-là qui est reprise.
private struct LigneClassement: View {

    let membre: Membre
    let total: Int

    /// Le sous-titre. **Pas de meilleur coup tant que rien n'est réussi** : `nil` veut dire
    /// « aucun », et « meilleur coup 0 pts » le confondrait avec un coup raté
    /// (`CLAUDE.md` §3.1).
    private var detail: String {
        let reussis = "\(membre.pronosticsReussis) \(membre.pronosticsReussis > 1 ? "réussis" : "réussi")"
        guard let meilleur = membre.meilleureCote else { return reussis }
        return "\(reussis) · meilleur coup \(meilleur) pts"
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
            "\(membre.rang)\(membre.rang == 1 ? "er" : "e") sur \(total), \(membre.pseudo), "
            + "\(membre.totalPoints) points, \(membre.pronosticsReussis) pronostics réussis"
            + (membre.meilleureCote.map { ", meilleur coup \($0) points." } ?? ".")
        )
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
            .foregroundColor(membre.rang <= 3 ? .primaire : .grisSecondaire)
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
                .foregroundColor(.primaire)                   // 10,88:1 sur le blanc
                .lineLimit(1)

            Text("pts")
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

    private var nom: String { grandPrix.nom }

    /// Ce que dit la seconde ligne — ``EcheancePronostics/phrase``, **le seul calcul
    /// d'échéance de l'app**. Lu à l'affichage : l'écran se recharge à chaque apparition,
    /// une précision à la minute n'a pas à battre en direct ici.
    private var echeance: String { grandPrix.echeance().phrase }

    var body: some View {
        aplat
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Prochain Grand Prix : \(nom). \(echeance).")
    }

    private var aplat: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nom)
                    .font(.custom("HelveticaNeue-Medium", size: 16))
                    .foregroundColor(.white)              // 10,88:1 sur #800111
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
                Text("Code d'invitation")
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

                Text("Partage-le pour qu'on rejoigne « \(championnat.nom) ».")
                    .font(.corpsSm)
                    .foregroundColor(.grisSecondaire)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // La même phrase que l'écran « Créer » : l'ami la reçoit à l'identique, d'où
            // qu'on la lui envoie.
            ShareLink(item: "Rejoins mon championnat « \(championnat.nom) » sur Greed F1 avec le code \(championnat.codeInvitation).") {
                Label("Partager", systemImage: "square.and.arrow.up")
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
                StatistiqueProfil(valeur: StatistiqueProfil.absente, libelle: "Paris gagnés"),
                StatistiqueProfil(valeur: StatistiqueProfil.absente, libelle: "Pts moy. / GP"),
                StatistiqueProfil(valeur: meilleureCote.map(String.init) ?? StatistiqueProfil.absente,
                                  libelle: "Meilleur coup"),
                StatistiqueProfil(valeur: StatistiqueProfil.absente, libelle: "Cote moy. tentée")
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
                StatistiqueProfil(valeur: "\(pourcentageReussite)%", libelle: "Paris gagnés"),
                StatistiqueProfil(valeur: String(pointsMoyensParGrandPrix), libelle: "Pts moy. / GP"),
                StatistiqueProfil(valeur: String(meilleurCoup), libelle: "Meilleur coup"),
                StatistiqueProfil(valeur: String(moyenneTentee), libelle: "Cote moy. tentée")
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
