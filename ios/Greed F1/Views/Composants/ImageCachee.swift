import SwiftUI
import UIKit

/// Les photos déjà téléchargées — avatars et photos de championnat —, **une table pour toute
/// l'app**, indexée par URL.
///
/// `AsyncImage` ne garde rien : chaque vue qui réapparaît retéléchargeait sa photo et
/// montrait l'initiale le temps de l'aller-retour — le clignotement à chaque navigation.
///
/// L'URL suffit comme clé : un dépôt de photo produit une **nouvelle** URL (`?v=`,
/// ``DepotPhoto``), une photo remplacée ne peut donc pas être servie périmée. `NSCache`
/// rend la mémoire de lui-même quand le système la réclame.
final class CacheImages: @unchecked Sendable {

    static let partage = CacheImages()

    private let table: NSCache<NSURL, UIImage> = {
        let table = NSCache<NSURL, UIImage>()
        table.countLimit = 200
        table.totalCostLimit = 50 * 1024 * 1024
        return table
    }()

    /// Les téléchargements en vol : vingt pastilles de la même photo n'en lancent qu'un.
    @MainActor private var enVol: [URL: Task<UIImage?, Never>] = [:]

    private init() {}

    func image(pour url: URL) -> UIImage? {
        table.object(forKey: url as NSURL)
    }

    /// Télécharge, décode **hors du fil principal**, et range. `nil` en cas d'échec : la
    /// vue garde alors son remplaçant, et retentera à sa prochaine apparition.
    @MainActor
    func charger(_ url: URL) async -> UIImage? {
        if let image = image(pour: url) { return image }
        if let tache = enVol[url] { return await tache.value }

        let tache = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            guard let (donnees, _) = try? await URLSession.shared.data(from: url),
                  let brute = UIImage(data: donnees) else { return nil }
            return await brute.byPreparingForDisplay() ?? brute
        }
        enVol[url] = tache
        let image = await tache.value
        enVol[url] = nil
        if let image {
            let cout = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            table.setObject(image, forKey: url as NSURL, cost: cout)
        }
        return image
    }
}

/// `AsyncImage`, avec la mémoire de ``CacheImages`` : une photo déjà vue s'affiche **dès la
/// première image**, sans repasser par son remplaçant.
///
/// Même forme d'appel qu'`AsyncImage(url:content:placeholder:)`.
struct ImageCachee<Contenu: View, Remplacant: View>: View {

    let url: URL?
    @ViewBuilder let contenu: (Image) -> Contenu
    @ViewBuilder let placeholder: () -> Remplacant

    /// Ne sert qu'à redessiner la vue quand le téléchargement aboutit : l'image elle-même
    /// est relue dans le cache, qui reste la seule source.
    @State private var chargee: URL?

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Contenu,
         @ViewBuilder placeholder: @escaping () -> Remplacant) {
        self.url = url
        self.contenu = content
        self.placeholder = placeholder
    }

    var body: some View {
        // Lu pour que l'arrivée du téléchargement redessine la vue.
        let _ = chargee
        if let url, let image = CacheImages.partage.image(pour: url) {
            contenu(Image(uiImage: image))
        } else {
            placeholder()
                .task(id: url) {
                    guard let url, await CacheImages.partage.charger(url) != nil else { return }
                    chargee = url
                }
        }
    }
}
