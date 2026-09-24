import Foundation

/// `POST /admin/action` — **la seule route d'administration appelable depuis l'app**
/// (`docs/swift-app.md` §3.7). Le garde est le jeton du membre, doublé d'une relecture de
/// `profils.is_admin` en base : `estAdmin` côté client décide d'un affichage, jamais d'un
/// droit, et un `403` au premier appui est la réponse normale d'un drapeau périmé.
///
/// > **Jamais `POST /scraper/declencher`** : elle est fermée par `X-Admin-Secret`, et ce
/// > secret n'entre sous aucun prétexte dans un binaire iOS.
enum Administration {

    /// Lance le scraping des cotes **sans les figer**.
    ///
    /// Le figeage est l'action qu'aucune interface ne sait défaire (un `update` à la main,
    /// l'accident du GP des Pays-Bas — `bugs-connus.md` §4). Un bouton unique, sans
    /// confirmation, ne doit donc écrire que ce qui se rattrape : des cotes, sur des Grands
    /// Prix pas encore arrêtés. Le job du samedi fige toujours à son heure.
    ///
    /// - Returns: le message à afficher sous le bouton.
    /// - Throws: une ``ErreurAPI`` dont le message est affichable.
    static func lancerScraper() async throws -> String {
        let reponse: ReponseAction = try await APIClient.partage.requete(
            "admin/action", methode: .post, corps: DemandeAction(action: "scraper", figer: false))
        return reponse.message
    }
}

private struct DemandeAction: Encodable {
    let action: String
    let figer: Bool
}

/// La réponse `200`. **`statut` est le seul champ qui compte à l'écran** : `lance` veut
/// dire *accepté*, le travail part en arrière-plan et son compte rendu va dans les logs
/// Railway. Annoncer « cotes mises à jour » serait une promesse que la réponse ne porte pas.
private struct ReponseAction: Decodable {
    let statut: String

    var message: String {
        switch statut {
        case "lance":  return "Scraping lancé, sans figeage. Le compte rendu est dans les logs Railway."
        case "traite": return "Scraping terminé."
        default:       return "Demande acceptée par le serveur."
        }
    }
}
