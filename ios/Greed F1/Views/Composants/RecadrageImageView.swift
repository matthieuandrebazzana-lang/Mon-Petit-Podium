import SwiftUI
import UIKit

/// Recadrage d'une photo avant son envoi — modale plein écran, ouverte juste après le choix
/// dans le `PhotosPicker` de ``ProfilView``, ``CreerChampionnatView`` et
/// ``ChampionnatDetailView``. Masque **cercle** pour un profil, **carré** pour un
/// championnat.
///
/// **Zoomable au pince (1,0 à 4,0), déplaçable au drag, jamais au-delà des bords de
/// l'image** : la fenêtre de recadrage reste couverte en toute position, ce que la borne
/// basse de 1,0 garantit d'elle-même — l'image ne peut jamais devenir plus petite que la
/// fenêtre.
///
/// **Le recadrage se calcule, il ne se rend pas.** ``recadree(fenetre:)`` retrouve la
/// fenêtre en coordonnées de l'image d'origine à partir de l'échelle et du décalage
/// affichés, puis redessine — le même geste que ``DepotPhoto/reduire(_:)``, qui fait déjà ce
/// calcul pour le recadrage carré automatique que celui-ci remplace : l'image reçue par
/// ``DepotPhoto`` est désormais déjà carrée, son propre recadrage n'y est plus qu'un
/// redimensionnement.
struct RecadrageImageView: View {

    enum Forme {
        case cercle, carre
    }

    let image: UIImage
    let forme: Forme

    /// Le résultat, déjà carré et cadré selon le choix du membre.
    let onValider: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private static let echelleMin: CGFloat = 1
    private static let echelleMax: CGFloat = 4

    /// Réserve verticale pour la barre de boutons, hors zone sûre — ajoutée à part, elle
    /// varie d'un iPhone à l'autre.
    private static let hauteurBarreBoutons: CGFloat = 96
    private static let margeFenetre: CGFloat = 32

    /// Échelle et décalage **validés** : ce qu'a laissé le dernier geste, et d'où repart le
    /// suivant. Jamais composés avec le delta en cours avant `onEnded` — sans quoi chaque
    /// nouveau geste repartirait d'une valeur déjà cumulée deux fois.
    @State private var echelle: CGFloat = 1
    @State private var decalage: CGSize = .zero

    @GestureState private var pincementActif: CGFloat = 1
    @GestureState private var glissementActif: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let fenetre = fenetreRecadrage(dans: geo)

            ZStack {
                Color.voile.ignoresSafeArea()

                imageAffichee(fenetre: fenetre)

                MasqueRecadrage(fenetre: fenetre, cercle: forme == .cercle)
                    .fill(Color.voile.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    boutons(fenetre: fenetre)
                        .padding(.horizontal, 16)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                }
            }
            .contentShape(Rectangle())
            .gesture(gestePincement(fenetre: fenetre))
            .simultaneousGesture(gesteGlissement(fenetre: fenetre))
        }
        .background(Color.voile.ignoresSafeArea())
        .statusBarHidden()
    }

    // MARK: - Géométrie

    /// La fenêtre de recadrage, centrée dans l'espace laissé par la barre de boutons.
    private func fenetreRecadrage(dans geo: GeometryProxy) -> CGRect {
        let y0 = geo.safeAreaInsets.top + Self.margeFenetre
        let y1 = geo.size.height - geo.safeAreaInsets.bottom - Self.hauteurBarreBoutons
        let cote = min(geo.size.width - Self.margeFenetre * 2, max(y1 - y0, 100))
        let centre = CGPoint(x: geo.size.width / 2, y: (y0 + y1) / 2)
        return CGRect(x: centre.x - cote / 2, y: centre.y - cote / 2, width: cote, height: cote)
    }

    /// L'échelle affichée **tout de suite** : validée, composée du pincement en cours, et
    /// bornée en direct — un pinceur qui dépasse 4,0 doit le voir s'arrêter sous son doigt,
    /// pas seulement au relâchement.
    private var echelleEffective: CGFloat {
        borner(echelle * pincementActif, Self.echelleMin...Self.echelleMax)
    }

    /// Le décalage affiché **tout de suite**, borné aux limites que l'échelle courante
    /// autorise : la fenêtre reste couverte par l'image à chaque frame du geste, jamais
    /// seulement à son terme.
    private func decalageEffectif(fenetre: CGRect, largeur: CGFloat, hauteur: CGFloat) -> CGSize {
        let brut = CGSize(width: decalage.width + glissementActif.width,
                          height: decalage.height + glissementActif.height)
        let limiteX = max(0, (largeur - fenetre.width) / 2)
        let limiteY = max(0, (hauteur - fenetre.height) / 2)
        return CGSize(width: borner(brut.width, -limiteX...limiteX),
                      height: borner(brut.height, -limiteY...limiteY))
    }

    private func borner(_ valeur: CGFloat, _ bornes: ClosedRange<CGFloat>) -> CGFloat {
        min(max(valeur, bornes.lowerBound), bornes.upperBound)
    }

    // MARK: - Image et gestes

    /// L'image à l'échelle 1,0 **couvre exactement la fenêtre** (`scaledToFill`, calculé) :
    /// c'est ce qui garantit qu'aucune position ne montre du noir sous la fenêtre.
    private func imageAffichee(fenetre: CGRect) -> some View {
        let echelleBase = fenetre.width / min(image.size.width, image.size.height)
        let echelleTotale = echelleBase * echelleEffective
        let largeur = image.size.width * echelleTotale
        let hauteur = image.size.height * echelleTotale
        let decalageAffiche = decalageEffectif(fenetre: fenetre, largeur: largeur, hauteur: hauteur)

        return Image(uiImage: image)
            .resizable()
            .frame(width: largeur, height: hauteur)
            .position(x: fenetre.midX + decalageAffiche.width,
                     y: fenetre.midY + decalageAffiche.height)
            .allowsHitTesting(false)
    }

    private func gestePincement(fenetre: CGRect) -> some Gesture {
        MagnifyGesture()
            .updating($pincementActif) { valeur, etat, _ in
                etat = valeur.magnification
            }
            .onEnded { valeur in
                echelle = borner(echelle * valeur.magnification, Self.echelleMin...Self.echelleMax)
                recaler(fenetre: fenetre)
            }
    }

    private func gesteGlissement(fenetre: CGRect) -> some Gesture {
        DragGesture()
            .updating($glissementActif) { valeur, etat, _ in
                etat = valeur.translation
            }
            .onEnded { valeur in
                decalage.width += valeur.translation.width
                decalage.height += valeur.translation.height
                recaler(fenetre: fenetre)
            }
    }

    /// Reclampe le décalage validé une fois le geste fini. **Nécessaire après un
    /// pincement qui vient de réduire l'échelle** : la limite qu'un décalage validé
    /// respectait à l'ancienne échelle peut ne plus tenir à la nouvelle.
    private func recaler(fenetre: CGRect) {
        let echelleBase = fenetre.width / min(image.size.width, image.size.height)
        let echelleTotale = echelleBase * echelle
        let largeur = image.size.width * echelleTotale
        let hauteur = image.size.height * echelleTotale
        let limiteX = max(0, (largeur - fenetre.width) / 2)
        let limiteY = max(0, (hauteur - fenetre.height) / 2)
        withAnimation(mouvementReduit ? nil : Mouvement.deplacement(0.22)) {
            decalage.width = borner(decalage.width, -limiteX...limiteX)
            decalage.height = borner(decalage.height, -limiteY...limiteY)
        }
    }

    // MARK: - Recadrage

    /// Retrouve, en coordonnées de l'image d'origine, ce que la fenêtre montre à l'écran,
    /// et redessine dedans — même technique que ``DepotPhoto/reduire(_:)``, qui applique
    /// déjà l'orientation EXIF par le simple fait de passer par `draw(in:)`.
    private func recadree(fenetre: CGRect) -> UIImage {
        let echelleBase = fenetre.width / min(image.size.width, image.size.height)
        let echelleTotale = echelleBase * echelle
        let largeur = image.size.width * echelleTotale
        let hauteur = image.size.height * echelleTotale
        let decalageValide = decalageEffectif(fenetre: fenetre, largeur: largeur, hauteur: hauteur)

        let origineAffichee = CGPoint(x: fenetre.midX + decalageValide.width - largeur / 2,
                                      y: fenetre.midY + decalageValide.height - hauteur / 2)
        let origineDansImage = CGPoint(x: (fenetre.minX - origineAffichee.x) / echelleTotale,
                                       y: (fenetre.minY - origineAffichee.y) / echelleTotale)
        let tailleDansImage = CGSize(width: fenetre.width / echelleTotale,
                                     height: fenetre.height / echelleTotale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let rendu = UIGraphicsImageRenderer(size: tailleDansImage, format: format)
        return rendu.image { _ in
            image.draw(in: CGRect(x: -origineDansImage.x, y: -origineDansImage.y,
                                  width: image.size.width, height: image.size.height))
        }
    }

    // MARK: - Boutons

    /// **Annuler** en `encreSecondaire` (blanc à 70 %) — le jeton du projet pour un texte de
    /// second rang posé sur un aplat, ici le noir de la modale. **Utiliser cette photo** en
    /// `primaire`, comme tous les boutons pleins de l'app.
    private func boutons(fenetre: CGRect) -> some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text(t("commun.annuler"))
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundColor(.encreSecondaire)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }

            Button {
                let resultat = recadree(fenetre: fenetre)
                onValider(resultat)
                dismiss()
            } label: {
                Text(t("recadrage.utiliser"))
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .foregroundColor(.encreSurAplat)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.primaire)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
            }
        }
        .buttonStyle(StyleAppui(.bouton))
    }
}

/// La fenêtre de recadrage, découpée dans un voile plein écran par une règle **paire-impaire** :
/// un seul calque, jamais un cadre et un voile posés séparément qui pourraient se
/// désaligner l'un de l'autre.
private struct MasqueRecadrage: Shape {
    let fenetre: CGRect
    let cercle: Bool

    func path(in rect: CGRect) -> Path {
        var chemin = Path(rect)
        if cercle {
            chemin.addPath(Path(ellipseIn: fenetre))
        } else {
            chemin.addPath(Path(roundedRect: fenetre, cornerRadius: Rayon.carte, style: .continuous))
        }
        return chemin
    }
}

#Preview {
    RecadrageImageView(image: UIImage(systemName: "photo")!, forme: .cercle) { _ in }
}
