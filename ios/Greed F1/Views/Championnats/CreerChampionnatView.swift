import SwiftUI
import PhotosUI

/// Création d'un championnat : son nom, sa photo, et le rappel que le code d'invitation
/// sera engendré par le serveur.
///
/// Référence visuelle : `Ressources/Screenshots/screen-11-creer-championnat.PNG`.
///
/// > **Rien ne part encore sur le réseau.** L'appui sur « Créer le championnat » ouvre une
/// > alerte ; la route `POST /championnats` et la navigation vers le championnat créé
/// > seront branchées à la passe API (`docs/swift-app.md` §5).
///
/// **Le code d'invitation n'est pas engendré ici, et c'est délibéré.** Six caractères tirés
/// par l'app pourraient entrer en collision avec un code déjà attribué ; c'est le serveur
/// qui les tire, sous la contrainte d'unicité de la base. L'écran n'en montre donc que la
/// silhouette — six tirets — et le dit.
struct CreerChampionnatView: View {

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @State private var nom = ""
    @FocusState private var nomActif: Bool

    /// La photo choisie dans la photothèque, et sa vignette une fois décodée. **Deux états
    /// et non un** : `PhotosPickerItem` est une référence, l'image n'arrive qu'après un
    /// chargement asynchrone, et la vignette ne doit apparaître qu'une fois l'image prête.
    @State private var choixPhoto: PhotosPickerItem?
    @State private var vignette: Image?

    /// Le refus opposé à une photo trop lourde. `nil` tant qu'il n'y a rien à dire.
    @State private var refusPhoto: String?

    @State private var alerteCreation = false

    /// Le plafond annoncé sous la ligne « Ajouter une photo ». **Annoncé et appliqué au
    /// même endroit** : une limite écrite dans le sous-titre et vérifiée ailleurs finit par
    /// diverger, et le symptôme est un fichier accepté que le serveur rejettera.
    private static let poidsMaximal = 2 * 1024 * 1024

    /// Un nom fait de seuls espaces n'est pas un nom.
    private var nomValide: Bool {
        !nom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        .alert("Championnat créé !", isPresented: $alerteCreation) {
            Button("Parfait", role: .cancel) { }
        } message: {
            Text("Son code d'invitation sera affiché ici dès que le serveur l'aura engendré.")
        }
    }

    // MARK: - Titre

    private var titre: some View {
        Text("Créer un championnat")
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
                label("Nom du championnat")
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
        TextField("", text: $nom, prompt: placeholder)
            .font(.custom("HelveticaNeue", size: 17))
            .foregroundColor(.texte)
            .tint(.primaire)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nomActif)
            .onSubmit { nomActif = false }
            .padding(.horizontal, 16)
            .frame(height: 52)                  // > 44 pt, contrainte tactile iOS
            .background(Color.fondPrincipal)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
            .accessibilityLabel("Nom du championnat")
    }

    /// **`grisSecondaire` et non le `#999999` de la version web.** Sur le beige du champ,
    /// `#999999` ne vaut que 2,52:1 ; `#6B6B6B` y tient **4,70:1** pour un gris que l'œil ne
    /// distingue pas du premier. Le contraste se mesure (`ios/CLAUDE.md` §3).
    private var placeholder: Text {
        Text("Les Potes F1")
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
                    Text(vignette == nil ? "Ajouter une photo" : "Changer la photo")
                        .font(.corps)
                        .foregroundColor(.texte)        // 15,37:1 sur le blanc
                        .lineLimit(1)

                    Text(refusPhoto ?? "Optionnel · JPG, PNG ou WEBP, 2 Mo maximum")
                        .font(.custom("HelveticaNeue", size: 12))
                        // Le refus prend l'encre primaire : c'est la seule chose de l'écran
                        // qui demande à être relue avant de continuer.
                        .foregroundColor(refusPhoto == nil ? .grisSecondaire : .primaire)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .accessibilityLabel(vignette == nil ? "Ajouter une photo" : "Changer la photo")
        .accessibilityHint("Optionnel. Deux mégaoctets maximum.")
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
                await MainActor.run { refusPhoto = "Photo illisible. Essaie une autre image." }
                return
            }

            guard donnees.count <= Self.poidsMaximal else {
                await MainActor.run {
                    let mega = Double(donnees.count) / 1_048_576
                    refusPhoto = String(format: "Photo trop lourde (%.1f Mo). 2 Mo maximum.", mega)
                    self.choixPhoto = nil
                }
                return
            }

            await MainActor.run {
                refusPhoto = nil
                withAnimation(Mouvement.entree(0.20)) {
                    vignette = Image(uiImage: image)
                }
            }
        }
    }

    // MARK: - Code d'invitation

    /// L'aplat rouge : six tirets et une phrase. Il **n'attend rien de l'utilisateur** — il
    /// répond d'avance à la question que pose l'écran suivant, « comment mes amis me
    /// rejoignent-ils ? », et la réponse est : tu n'as rien à faire.
    private var blocCode: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Code d'invitation")
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encreSecondaire)      // 5,75:1 sur primaire

            HStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    Capsule()
                        .fill(Color.encreGraphique)     // 3,46:1 sur primaire
                        .frame(width: 26, height: 3)
                }
            }

            Text("Généré automatiquement à la création.")
                .font(.custom("HelveticaNeue", size: 12))
                .foregroundColor(.encreSecondaire)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primaire)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()                                   // aplat de couleur (§4.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code d'invitation de six caractères, généré automatiquement à la création.")
    }

    // MARK: - Le bouton

    /// **L'écran n'a qu'une action**, et le bouton ne s'allume que lorsqu'elle est possible.
    ///
    /// Désactivé, il garde sa forme et sa place : c'est la même silhouette, sur un aplat
    /// inerte. Le marron `secondaire` à 22 % sur le beige donne `#D2C8BF`, où la même encre
    /// pleine tient **6,42:1** — un bouton éteint reste lisible, sans quoi on ne sait pas
    /// ce qu'on attend de nous.
    private var boutonCreer: some View {
        Button {
            nomActif = false
            alerteCreation = true
        } label: {
            Text("Créer le championnat")
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .foregroundColor(nomValide ? .white : .secondaire)
                .frame(maxWidth: .infinity)
                .frame(height: 56)              // > 44 pt, contrainte tactile iOS
                .background(nomValide ? Color.primaire : Color.secondaire.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(!nomValide)
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
        CreerChampionnatView()
    }
}
