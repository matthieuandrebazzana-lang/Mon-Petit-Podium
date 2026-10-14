import CryptoKit
import SwiftUI
import UIKit
import WidgetKit

/// Un instant du widget « Classement ».
struct EntreeClassement: TimelineEntry {
    let date: Date
    let championnat: DonneesWidget.ChampionnatWidget?
    /// Le dernier classement reçu — de l'API à l'instant, ou de l'App Group.
    let releve: DonneesWidget.ReleveClassement?
    /// Faux quand l'API n'a pas répondu (hors ligne, jeton expiré) : le widget dit alors
    /// de quand datent ses données.
    let aJour: Bool
    let profilId: UUID?
    let affichage: AffichagePetit
    /// Les avatars réduits, par profil — lus dans l'App Group, jamais téléchargés au rendu.
    let avatars: [UUID: UIImage]
    let langue: Langue?

    static func neutre(_ date: Date = .now, affichage: AffichagePetit = .classement) -> EntreeClassement {
        EntreeClassement(date: date, championnat: nil, releve: nil, aJour: false, profilId: nil,
                         affichage: affichage, avatars: [:], langue: DonneesWidget.langue)
    }
}

/// Lit l'App Group et `GET /widget/championnats/{id}/classement` avec le **jeton widget**
/// du Keychain partagé (``JetonWidget``) — **jamais la session Supabase**, qu'il ne voit
/// pas et ne rafraîchit jamais (`docs/decisions.md` §28).
struct FournisseurClassement: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> EntreeClassement { Self.exemple(.classement) }

    func snapshot(for configuration: IntentionClassement, in context: Context) async -> EntreeClassement {
        let entree = Self.depuisAppGroup(configuration, aJour: true)
        // La galerie n'a pas de données à attendre : l'exemple, si l'App Group est vide.
        return entree.releve == nil && context.isPreview ? Self.exemple(configuration.affichage) : entree
    }

    func timeline(for configuration: IntentionClassement, in context: Context) async -> Timeline<EntreeClassement> {
        let contenu = DonneesWidget.lireClassement()
        var aJour = false
        if let championnat = contenu.championnat(choisi: configuration.championnat?.id),
           let membres = await Self.lireClassement(championnat.id) {
            DonneesWidget.enregistrer(.init(membres: membres, date: .now), pour: championnat.id)
            aJour = true
        }
        // Le relevé reçu à l'instant, sinon le dernier connu : ses avatars avant le rendu.
        let relu = DonneesWidget.lireClassement()
        if let releve = relu.championnat(choisi: configuration.championnat?.id).flatMap({ relu.releve($0.id) }) {
            await AvatarsWidget.preparer(releve.membres)
        }
        return Timeline(entries: [Self.depuisAppGroup(configuration, aJour: aJour)],
                        policy: .after(CadenceClassement.prochaine(apres: .now,
                                                                   grandsPrix: DonneesWidget.lire().grandsPrix)))
    }

    /// Ce que l'App Group sait, avatars compris.
    static func depuisAppGroup(_ configuration: IntentionClassement, aJour: Bool) -> EntreeClassement {
        let contenu = DonneesWidget.lireClassement()
        let championnat = contenu.championnat(choisi: configuration.championnat?.id)
        let releve = championnat.flatMap { contenu.releve($0.id) }
        return EntreeClassement(
            date: .now, championnat: championnat, releve: releve, aJour: aJour,
            profilId: contenu.profilId, affichage: configuration.affichage,
            avatars: AvatarsWidget.lire(releve?.membres ?? []), langue: DonneesWidget.langue)
    }

    /// `GET /widget/championnats/{id}/classement`. **15 s au plus**, comme le widget
    /// « Prochain GP » : un Railway endormi ne vaut pas d'attendre, l'App Group répond.
    /// `nil` sans jeton, jeton expiré, refus ou réseau absent.
    static func lireClassement(_ id: UUID) async -> [Membre]? {
        guard let jeton = JetonWidget.lire(), jeton.expireLe > .now else { return nil }
        let url = SupabaseConfig.apiBaseURL
            .appendingPathComponent("widget/championnats/\(id.uuidString.lowercased())/classement")
        var requete = URLRequest(url: url)
        requete.timeoutInterval = 15
        requete.setValue("Bearer \(jeton.jeton)", forHTTPHeaderField: "Authorization")
        requete.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: requete),
              (reponse as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder.api.decode([Membre].self, from: donnees)
    }

    /// La galerie et le `placeholder` — un classement plausible, jamais affiché comme une
    /// donnée réelle.
    static func exemple(_ affichage: AffichagePetit) -> EntreeClassement {
        let pseudos = ["Matt", "Léa", "Hugo", "Inès", "Tom", "Zoé", "Noah", "Jade"]
        let points = [168, 151, 151, 122, 97, 80, 64, 41]
        let couleurs = [("#CC0000", "#FFFFFF"), ("#003087", "#FFD700"), ("#00A19C", "#FFFFFF"),
                        ("#FF8000", "#000000"), ("#960064", "#FFFFFF"), ("#005C43", "#E8A020"),
                        ("#2D2D2D", "#CC0000"), ("#0090D4", "#FFFFFF")]
        let membres = pseudos.indices.map { i in
            Membre(profilId: UUID(), pseudo: pseudos[i], totalPoints: points[i],
                   pronosticsReussis: 0, meilleureCote: nil, rang: i + 1, ordreInscription: i + 1,
                   couleur1: couleurs[i].0, couleur2: couleurs[i].1, numero: nil, livreeMode: .perso)
        }
        return EntreeClassement(
            date: .now, championnat: .init(id: UUID(), nom: "Team Bazzana"),
            releve: .init(membres: membres, date: .now), aJour: true,
            profilId: membres[4].profilId, affichage: affichage, avatars: [:],
            langue: DonneesWidget.langue)
    }
}

// MARK: - La cadence

/// **Toutes les 2 h, toutes les 15 min dans les 36 h qui suivent un départ** — le temps
/// que les résultats tombent (provisoires, puis définitifs) et que le classement bouge.
/// Un départ qui tombe avant la prochaine relecture la ramène à lui.
enum CadenceClassement {

    static let normale: TimeInterval = 2 * 60 * 60
    static let course: TimeInterval = 15 * 60
    static let apresDepart: TimeInterval = 36 * 60 * 60

    static func prochaine(apres maintenant: Date, grandsPrix: [DonneesWidget.GrandPrix]) -> Date {
        let departs = grandsPrix.compactMap(\.dateCourse)
        if departs.contains(where: { maintenant >= $0 && maintenant < $0.addingTimeInterval(apresDepart) }) {
            return maintenant.addingTimeInterval(course)
        }
        let normale = maintenant.addingTimeInterval(normale)
        let depart = departs.filter { $0 > maintenant }.min()
        return min(normale, depart ?? normale)
    }
}

// MARK: - Les avatars

/// Les photos des membres, **réduites et rangées dans l'App Group** : un widget ne peut pas
/// télécharger pendant son rendu (`AsyncImage` y reste vide). Le fournisseur les prépare,
/// la vue ne fait que les lire. Une photo changée change d'URL (`?v=`) : une URL
/// téléchargée une fois ne l'est plus jamais.
enum AvatarsWidget {

    /// 96 px : l'avatar le plus grand du widget fait 26 pt, le cockpit d'une voiture moins.
    static let cote: CGFloat = 96

    static func preparer(_ membres: [Membre]) async {
        guard let dossier = DonneesWidget.dossierAvatars else { return }
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        await withTaskGroup(of: Void.self) { groupe in
            for url in Set(membres.compactMap(\.avatarUrl)) {
                let fichier = dossier.appendingPathComponent(nom(url))
                guard !FileManager.default.fileExists(atPath: fichier.path) else { continue }
                groupe.addTask {
                    var requete = URLRequest(url: url)
                    requete.timeoutInterval = 10
                    guard let (donnees, _) = try? await URLSession.shared.data(for: requete),
                          let reduite = reduire(donnees),
                          let jpeg = reduite.jpegData(compressionQuality: 0.85)
                    else { return }
                    try? jpeg.write(to: fichier, options: .atomic)
                }
            }
        }
    }

    static func lire(_ membres: [Membre]) -> [UUID: UIImage] {
        guard let dossier = DonneesWidget.dossierAvatars else { return [:] }
        var avatars: [UUID: UIImage] = [:]
        for membre in membres {
            guard let url = membre.avatarUrl,
                  let image = UIImage(contentsOfFile: dossier.appendingPathComponent(nom(url)).path)
            else { continue }
            avatars[membre.profilId] = image
        }
        return avatars
    }

    /// Réduite **sans décoder l'image entière** : une photo de 800 px décodée pèse 2,5 Mo,
    /// sa vignette 37 ko — la limite mémoire d'un widget est d'environ 30 Mo.
    private static func reduire(_ donnees: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(donnees as CFData, options) else { return nil }
        let vignette = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cote
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, vignette).map(UIImage.init(cgImage:))
    }

    private static func nom(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
}
