import Foundation
import Supabase
import UIKit

/// Dépôt des photos dans Supabase Storage — le pendant de `lib/stockage.js` et
/// `lib/image.js`. Source : `docs/swift-app.md` §3.8.
///
/// **Le fichier va DIRECTEMENT à Supabase, jamais à Railway** : la RLS de `storage.objects`
/// compare le premier segment du chemin à `auth.uid()`, elle porte déjà l'autorisation.
/// **L'URL obtenue, elle, s'enregistre par l'API** — c'est là que `url_de_photo_valide`
/// vérifie qu'elle est bien la nôtre. Ce service s'arrête donc à l'URL.
enum DepotPhoto {

    /// Les deux compartiments de la migration `20260821180000`.
    enum Compartiment: String {
        case avatars
        case championnats

        /// Le nom de base de l'objet sous le dossier du propriétaire (§3.8, tableau).
        var nomDeBase: String {
            switch self {
            case .avatars:      return "avatar"
            case .championnats: return "photo"
            }
        }
    }

    /// Côté du carré déposé, et qualité JPEG — les valeurs de `lib/image.js`. Une photo
    /// d'iPhone de 4 Mo pèse alors moins de 200 Ko, très loin des 2 Mo du compartiment.
    private static let cote: CGFloat = 800
    private static let qualite: CGFloat = 0.85

    /// Extension déposée, et celles qu'une photo antérieure a pu porter — à effacer
    /// **après** un dépôt réussi, jamais avant.
    private static let extensionDeposee = "jpg"
    private static let extensionsAnciennes = ["jpeg", "png", "webp"]

    /// Réduit, dépose, et rend l'URL publique **avec son péremptoire de cache** : le chemin
    /// étant stable, sans `?v=` le CDN servirait l'ancienne image et la colonne ne
    /// changerait pas.
    ///
    /// - Parameter proprietaire: l'identifiant du profil (avatar) ou du championnat. Il
    ///   doit être celui du jeton pour un avatar : la RLS refuse tout autre dossier.
    /// - Throws: une ``ErreurAPI`` au message affichable.
    static func deposer(_ donnees: Data,
                        dans compartiment: Compartiment,
                        proprietaire: String) async throws -> String {
        guard let image = UIImage(data: donnees), let jpeg = reduire(image) else {
            throw ErreurAPI.serveur(statut: nil, message: "Photo illisible. Essaie une autre image.")
        }

        // Minuscules : c'est la forme de `auth.uid()`, et celle qu'écrit la version web.
        let dossier = proprietaire.lowercased()
        let chemin = "\(dossier)/\(compartiment.nomDeBase).\(extensionDeposee)"
        let stockage = SupabaseManager.partage.client.storage.from(compartiment.rawValue)

        do {
            _ = try await stockage.upload(
                chemin,
                data: jpeg,
                options: FileOptions(cacheControl: "31536000",
                                     contentType: "image/jpeg",
                                     upsert: true)
            )
        } catch is URLError {
            throw ErreurAPI.reseau
        } catch {
            throw ErreurAPI.serveur(
                statut: nil,
                message: "Impossible d'envoyer cette photo. Réessaie dans quelques instants."
            )
        }

        // Ménage : une photo antérieure rangée sous une autre extension. Son échec
        // s'ignore — il ne coûte qu'un objet orphelin.
        let anciens = extensionsAnciennes.map { "\(dossier)/\(compartiment.nomDeBase).\($0)" }
        _ = try? await stockage.remove(paths: anciens)

        let publique = try stockage.getPublicURL(path: chemin)
        let version = Int(Date().timeIntervalSince1970 * 1000)
        return "\(publique.absoluteString)?v=\(version)"
    }

    /// Recadrage carré au centre, 800 px de côté au plus, JPEG 0,85 — orientation EXIF
    /// appliquée par le redessin, comme le canvas de la version web.
    private static func reduire(_ image: UIImage) -> Data? {
        let largeur = image.size.width, hauteur = image.size.height
        guard largeur > 0, hauteur > 0 else { return nil }

        let carre = min(largeur, hauteur)
        let sortie = min(cote, carre * image.scale)
        let echelle = sortie / carre

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendu = UIGraphicsImageRenderer(size: CGSize(width: sortie, height: sortie),
                                            format: format)
        let reduite = rendu.image { _ in
            image.draw(in: CGRect(x: -(largeur - carre) / 2 * echelle,
                                  y: -(hauteur - carre) / 2 * echelle,
                                  width: largeur * echelle,
                                  height: hauteur * echelle))
        }
        return reduite.jpegData(compressionQuality: qualite)
    }
}
