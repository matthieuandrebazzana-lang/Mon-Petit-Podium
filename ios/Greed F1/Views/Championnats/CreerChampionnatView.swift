import SwiftUI
import PhotosUI

/// Création d'un championnat : son nom, sa photo, et le rappel que le code d'invitation
/// sera engendré par le serveur.
///
/// Référence visuelle : `Ressources/Screenshots/screen-11-creer-championnat.PNG`.
///
/// **`POST /championnats`** (`docs/swift-app.md` §3.3). Le succès ne quitte pas l'écran :
/// il **remplit** l'aplat rouge du code reçu — c'est ce que l'utilisateur vient chercher,
/// et il doit pouvoir le partager avant d'aller plus loin —, puis le bouton devient
/// « Voir le championnat ». Un refus s'écrit sous le bouton (``ErreurEnLigne``), jamais
/// dans une alerte. La liste de ``MesChampionnats`` est rechargée dès le succès.
///
/// > **La photo n'est pas encore envoyée** : elle est choisie et vérifiée ici, le dépôt
/// > Storage suivi du `PATCH` vient à la fin de l'étape 2 (§7.6).
///
/// **Le code d'invitation n'est pas engendré ici, et c'est délibéré.** Six caractères tirés
/// par l'app pourraient entrer en collision avec un code déjà attribué ; c'est le serveur
/// qui les tire, sous la contrainte d'unicité de la base. L'écran n'en montre donc que la
/// silhouette — six tirets — et le dit.
struct CreerChampionnatView: View {

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @ObservedObject var mesChampionnats: MesChampionnats

    @State private var nom = ""
    @FocusState private var nomActif: Bool

    /// La photo choisie dans la photothèque, puis son recadrage (``RecadrageImageView``,
    /// masque carré), puis sa vignette une fois recadrée. **Trois états et non un** :
    /// `PhotosPickerItem` est une référence, l'image n'arrive qu'après un chargement
    /// asynchrone, et la vignette ne doit apparaître qu'une fois le recadrage validé.
    @State private var choixPhoto: PhotosPickerItem?
    @State private var imageACadrer: UIImage?
    @State private var vignette: Image?

    /// Le refus opposé à une photo trop lourde. `nil` tant qu'il n'y a rien à dire.
    @State private var refusPhoto: String?

    /// Vrai pendant l'appel : le bouton porte un spinner et ne se rappuie pas.
    @State private var envoi = false
    /// Le refus du serveur, affiché sous le bouton jusqu'à la prochaine frappe.
    @State private var erreur: ErreurAPI?
    /// Le championnat que le serveur a créé. **Non nul, l'écran a fini son travail** : le
    /// nom se fige, le code s'affiche, le bouton mène au championnat.
    @State private var cree: Championnat?

    /// Bornes du serveur, **après `strip()`** — `422` au-delà (§3.3).
    private static let longueurNom = 2...40

    /// Le plafond annoncé sous la ligne « Ajouter une photo ». **Annoncé et appliqué au
    /// même endroit** : une limite écrite dans le sous-titre et vérifiée ailleurs finit par
    /// diverger, et le symptôme est un fichier accepté que le serveur rejettera.
    private static let poidsMaximal = 2 * 1024 * 1024

    private var nomNettoye: String {
        nom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Les bornes du serveur, vérifiées avant l'envoi : un nom d'une lettre allumerait
    /// sinon un bouton que le serveur refuserait.
    private var nomValide: Bool {
        Self.longueurNom.contains(nomNettoye.count)
    }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    titre

                    Spacer().frame(height: 12)
                    blocIdentite

                    Spacer().frame(height: 12)   // espacement entre blocs (§4.6)
                    blocCode

                    Spacer().frame(height: 12)
                    boutonCreer

                    if let erreur {
                        Spacer().frame(height: 12)
                        ErreurEnLigne(erreur: erreur)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Le titre de l'écran est dans le contenu, à 28 pt : la barre système ne porte que
        // le chevron de retour, qui reste **le bouton natif** — c'est lui qui donne le
        // geste de retour par le bord, qu'un bouton dessiné à la main ne donne pas.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Mouvement.entree(0.20), value: erreur)
        // Retour haptique **au même instant** que ce qu'il confirme : le code qui apparaît,
        // ou le refus qui s'écrit.
        .sensoryFeedback(.success, trigger: cree) { _, nouveau in nouveau != nil }
        .sensoryFeedback(.error, trigger: erreur) { _, nouveau in nouveau != nil }
        .fullScreenCover(isPresented: Binding(
            get: { imageACadrer != nil },
            set: { affiche in if !affiche { imageACadrer = nil } }
        )) {
            if let imageACadrer {
                RecadrageImageView(image: imageACadrer, forme: .carre) { recadree in
                    refusPhoto = nil
                    withAnimation(Mouvement.entree(0.20)) {
                        vignette = Image(uiImage: recadree)
                    }
                }
            }
        }
    }

    // MARK: - Envoi

    private struct CorpsCreation: Encodable {
        let nom: String
    }

    /// `POST /championnats`. La tâche n'est **pas** liée à l'écran : quitter pendant
    /// l'appel ne l'annule pas, et la liste se recharge quand même — le championnat existe
    /// côté serveur, il doit apparaître côté app.
    private func creer() {
        guard nomValide, !envoi, cree == nil else { return }
        nomActif = false
        erreur = nil
        envoi = true
        let corps = CorpsCreation(nom: nomNettoye)

        Task {
            do {
                let championnat: Championnat = try await APIClient.partage.requete(
                    "championnats", methode: .post, corps: corps)
                envoi = false
                cree = championnat
                await mesChampionnats.charger(forcer: true)
            } catch let refus as ErreurAPI {
                envoi = false
                erreur = refus
            } catch {
                envoi = false
            }
        }
    }

    // MARK: - Titre

    private var titre: some View {
        Text(t("championnat.creer"))
            .font(.titre)
            .tracking(Tracking.titre)
            .foregroundColor(.texte)            // 15,37:1 sur le beige
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Nom et photo

    /// Le bloc blanc : ce que l'utilisateur renseigne. **Un seul bloc pour les deux**, parce
    /// que le nom et la photo décrivent la même chose — l'identité du championnat — et que
    /// la proximité est ce qui le dit sans avoir à l'écrire.
    private var blocIdentite: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                label(t("creer.nom"))
                champNom
            }

            lignephoto
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

    /// Le champ. **Le beige de l'app posé dans le blanc**, et non un gris neutre : c'est
    /// exactement ce que fait la version web, et c'est ce qui rattache le creux du champ au
    /// fond de l'écran plutôt que d'y introduire une couleur de plus.
    ///
    /// Le rayon est `champ` (14) : une surface posée **à l'intérieur** d'un bloc, donc
    /// **sans ombre** — elle ne casse jamais le plan de son bloc (`Formes.swift`).
    private var champNom: some View {
        TextField("", text: lienNom, prompt: placeholder)
            .font(.custom("HelveticaNeue", size: 17))
            .foregroundColor(.texte)
            .tint(.encrePrimaire)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nomActif)
            .onSubmit { nomActif = false }
            // Créé, le nom ne se modifie plus : le serveur ne sait pas le renommer (§3.3).
            .disabled(cree != nil)
            .padding(.horizontal, 16)
            .frame(height: 52)                  // > 44 pt, contrainte tactile iOS
            .background(Color.fondPrincipal)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
            .accessibilityLabel(t("creer.nom"))
    }

    /// Le lien du champ : plafonné à la borne du serveur **en écrivant**, pour la même
    /// raison que le code de ``RejoindreChampionnatView`` — une correction après coup perd
    /// des frappes. Toute frappe efface aussi le refus précédent : il parlait d'un autre nom.
    private var lienNom: Binding<String> {
        Binding(
            get: { nom },
            set: { saisie in
                nom = String(saisie.prefix(Self.longueurNom.upperBound))
                erreur = nil
            }
        )
    }

    /// **`grisSecondaire` et non le `#999999` de la version web.** Sur le beige du champ,
    /// `#999999` ne vaut que 2,52:1 ; `#6B6B6B` y tient **4,70:1** pour un gris que l'œil ne
    /// distingue pas du premier. Le contraste se mesure (`ios/CLAUDE.md` §3).
    private var placeholder: Text {
        Text(t("creer.placeholder"))
            .font(.custom("HelveticaNeue", size: 17))
            .foregroundColor(.grisSecondaire)
    }

    /// La ligne « Ajouter une photo » : la vignette, le libellé, et le rappel du format.
    ///
    /// **Toute la rangée est la cible**, pas seulement le carré : 72 pt de haut sur la
    /// largeur du bloc, très au-delà du plancher tactile de 44 pt, et le libellé est
    /// exactement ce qu'on cherche à toucher.
    private var lignephoto: some View {
        PhotosPicker(selection: $choixPhoto, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 14) {
                vignettePhoto

                VStack(alignment: .leading, spacing: 3) {
                    Text(vignette == nil ? t("creer.ajouterPhoto") : t("creer.changerPhoto"))
                        .font(.corps)
                        .foregroundColor(.texte)        // 15,37:1 sur le blanc
                        .lineLimit(1)

                    Text(refusPhoto ?? t("creer.photoAide"))
                        .font(.custom("HelveticaNeue", size: 12))
                        // Le refus prend l'encre primaire : c'est la seule chose de l'écran
                        // qui demande à être relue avant de continuer.
                        .foregroundColor(refusPhoto == nil ? .grisSecondaire : .encrePrimaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .accessibilityLabel(vignette == nil ? t("creer.ajouterPhoto") : t("creer.changerPhoto"))
        .accessibilityHint(t("creer.a11y.photoAide"))
        .onChange(of: choixPhoto) { _ in chargerPhoto() }
    }

    /// Le carré : l'icône d'appareil photo, remplacée par l'image dès qu'elle est décodée.
    private var vignettePhoto: some View {
        ZStack {
            Color.fondPrincipal

            if let vignette {
                vignette
                    .resizable()
                    .scaledToFill()
                    .transition(transitionVignette)
            } else {
                Image(systemName: "camera")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(.secondaire)       // 9,52:1 sur le beige
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
        .accessibilityHidden(true)
    }

    /// **La vignette est le seul élément de l'écran qui apparaît sans prévenir** : le
    /// sélecteur se referme et l'image est déjà là. Sans transition, l'icône d'appareil
    /// photo se téléporte en photo — c'est le « changement brutal » que le mouvement existe
    /// pour éviter. Elle naît donc à `0,94` et jamais à `0` : rien, dans le monde réel,
    /// n'apparaît à partir de rien.
    ///
    /// Sous `accessibilityReduceMotion`, l'échelle tombe — c'est un déplacement — et
    /// l'opacité reste : l'arrivée de l'image doit rester lisible.
    private var transitionVignette: AnyTransition {
        let fondu = AnyTransition.opacity
        guard !mouvementReduit else { return fondu }
        return fondu.combined(with: .scale(scale: 0.94))
    }

    /// Charge la photo choisie, sous le plafond annoncé.
    ///
    /// `Data` plutôt que `Image` : c'est le seul moyen d'en connaître le poids avant de
    /// l'accepter, et c'est aussi ce que la passe API enverra au bucket Supabase Storage.
    private func chargerPhoto() {
        guard let choixPhoto else { return }

        Task {
            guard
                let donnees = try? await choixPhoto.loadTransferable(type: Data.self),
                let image = UIImage(data: donnees)
            else {
                await MainActor.run { refusPhoto = t("photo.illisible") }
                return
            }

            guard donnees.count <= Self.poidsMaximal else {
                await MainActor.run {
                    let mega = Double(donnees.count) / 1_048_576
                    refusPhoto = t("creer.photoTropLourde", mega)
                    self.choixPhoto = nil
                }
                return
            }

            await MainActor.run {
                refusPhoto = nil
                imageACadrer = image
            }
        }
    }

    // MARK: - Code d'invitation

    /// L'aplat rouge : six tirets et une phrase. Il **n'attend rien de l'utilisateur** — il
    /// répond d'avance à la question que pose l'écran suivant, « comment mes amis me
    /// rejoignent-ils ? », et la réponse est : tu n'as rien à faire.
    private var blocCode: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("championnat.codeInvitation"))
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encreSecondaire)      // 5,75:1 sur primaire

            HStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { index in
                    caseCode(index)
                }
            }
            .frame(height: 30)

            Text(cree == nil ? t("creer.codeAuto")
                             : t("creer.codePartage"))
                .font(.custom("HelveticaNeue", size: 12))
                .foregroundColor(.encreSecondaire)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            if let cree {
                partage(cree)
                    .transition(.opacity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primaire)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()                                   // aplat de couleur (§4.7)
        .accessibilityElement(children: .contain)
    }

    /// Un caractère du code, ou son tiret tant que le serveur ne l'a pas tiré.
    ///
    /// **Les six caractères entrent l'un après l'autre**, décalés de ``Mouvement/decalage`` :
    /// c'est le décalage qui fait lire un code, et non un bloc qui s'allume. Ils naissent à
    /// `0,94`, jamais à `0` ; sous `accessibilityReduceMotion` il ne reste que le fondu.
    @ViewBuilder
    private func caseCode(_ index: Int) -> some View {
        ZStack {
            if let caractere = caractereCode(index) {
                Text(String(caractere))
                    .font(.custom("HelveticaNeue-Medium", size: 26))
                    .foregroundColor(.encreSurAplat)            // 9,61:1 sur primaire
                    .transition(transitionCaractere)
            } else {
                Capsule()
                    .fill(Color.encreGraphique)         // 3,46:1 sur primaire
                    .frame(width: 26, height: 3)
                    .transition(.opacity)
            }
        }
        .frame(width: 26)
        .animation(Mouvement.entree(0.20).delay(Double(index) * Mouvement.decalage),
                   value: cree)
        .accessibilityHidden(true)
    }

    private func caractereCode(_ index: Int) -> Character? {
        guard let code = cree?.codeInvitation, index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }

    private var transitionCaractere: AnyTransition {
        let fondu = AnyTransition.opacity
        guard !mouvementReduit else { return fondu }
        return fondu.combined(with: .scale(scale: 0.94))
    }

    /// Le code n'a de valeur que transmis : la feuille de partage système le porte, avec
    /// une phrase qui dit à l'ami quoi en faire.
    private func partage(_ championnat: Championnat) -> some View {
        ShareLink(item: t("championnat.messagePartage", championnat.nom, championnat.codeInvitation)) {
            Label(t("creer.partagerCode"), systemImage: "square.and.arrow.up")
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundColor(.encreSurAplat)
                .frame(minHeight: 44)                   // contrainte tactile iOS
                .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel(t("creer.a11y.partagerCode", championnat.codeInvitation.map(String.init).joined(separator: " ")))
    }

    // MARK: - Le bouton

    /// **L'écran n'a qu'une action**, et le bouton ne s'allume que lorsqu'elle est possible.
    ///
    /// Désactivé, il garde sa forme et sa place : c'est la même silhouette, sur un aplat
    /// inerte. Le marron `secondaire` à 22 % sur le beige donne `#D2C8BF`, où la même encre
    /// pleine tient **6,42:1** — un bouton éteint reste lisible, sans quoi on ne sait pas
    /// ce qu'on attend de nous.
    ///
    /// **Créé, il devient le chemin vers le championnat** — même place, même forme : l'écran
    /// garde une seule action, c'est seulement l'action suivante.
    @ViewBuilder
    private var boutonCreer: some View {
        if let cree {
            NavigationLink {
                ChampionnatDetailView(championnat: cree, mesChampionnats: mesChampionnats)
            } label: {
                Text(t("championnat.voir"))
                    .habillageBoutonPrincipal(actif: true)
            }
            .boutonPressable()
            .shadow(color: Color.secondaire.opacity(0.16), radius: 17, y: 14)
        } else {
            boutonEnvoi
        }
    }

    private var boutonEnvoi: some View {
        Button(action: creer) {
            ZStack {
                // Le libellé reste en place, invisible, sous le spinner : le bouton ne
                // change pas de taille, et le texte revient à l'identique en cas d'échec.
                Text(t("creer.bouton")).opacity(envoi ? 0 : 1)
                if envoi { ProgressView().tint(.encreSurAplat) }
            }
            .habillageBoutonPrincipal(actif: nomValide)
        }
        .boutonPressable()
        .disabled(!nomValide || envoi)
        .accessibilityLabel(envoi ? t("creer.a11y.enCours") : t("creer.bouton"))
        // **Le seul changement d'état que l'écran produit de lui-même.** Il s'anime parce
        // qu'il arrive une fois par visite, à la première lettre tapée, et qu'un bouton qui
        // change d'encre d'une image à l'autre se lit comme un défaut d'affichage. Couleur
        // et opacité seulement, jamais une géométrie : rien ne bouge sous le doigt, et le
        // repli `accessibilityReduceMotion` est donc inutile ici.
        .animation(Mouvement.entree(0.18), value: nomValide)
        .shadow(color: Color.secondaire.opacity(nomValide ? 0.16 : 0), radius: 17, y: 14)
    }

    // MARK: - Pièces communes

    private func label(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)   // 5,33:1 sur le blanc
    }
}

#Preview {
    NavigationStack {
        CreerChampionnatView(mesChampionnats: MesChampionnats())
    }
}
