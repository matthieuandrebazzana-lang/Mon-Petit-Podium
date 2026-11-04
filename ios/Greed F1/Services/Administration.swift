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

    // MARK: - Alertes

    /// `GET /admin/alertes` — ce que l'administrateur doit voir sans lire les logs Railway :
    /// libellé Unibet non reconnu, rattachement impossible, définitif en échec, pronostics
    /// en attente d'une donnée. Jusqu'à la `0.59.0`, l'app ne les montrait pas : seul le web
    /// les listait, et l'alerte du remplaçant du Mexique est passée inaperçue
    /// (`bugs-connus.md` §44).
    static func chargerAlertes() async throws -> ReponseAlertes {
        try await APIClient.partage.requete("admin/alertes")
    }

    /// `GET /admin/grands-prix/{id}/engages` — les engagés **du week-end**, parmi lesquels
    /// une alerte de libellé se résout. Jamais une grille statique.
    static func chargerEngages(gpId: String) async throws -> EngagesDuGP {
        try await APIClient.partage.requete("admin/grands-prix/\(gpId)/engages")
    }

    /// `POST /admin/alertes/resoudre` — rattache le libellé au pilote (ou à l'écurie)
    /// choisi, puis le backend **recalcule le GP** : toutes les cotes de ce libellé, tous
    /// marchés confondus.
    ///
    /// - Returns: le message à afficher sous la liste.
    static func resoudre(alerte: AlerteAdmin, numeroPilote: Int?, ecurieId: String?) async throws -> String {
        let reponse: ReponseResolution = try await APIClient.partage.requete(
            "admin/alertes/resoudre", methode: .post,
            corps: DemandeResolution(gpId: alerte.gpId ?? "", libelle: alerte.libelle ?? "",
                                     numeroPilote: numeroPilote, ecurieId: ecurieId))
        return reponse.statut == "recalcule" ? t("admin.alertes.recalcule") : t("admin.alertes.enregistre")
    }
}

/// Une alerte du profil admin. Chaque champ est facultatif : un backend plus ancien ou
/// plus récent n'en envoie pas toujours la même liste (règle 3.3 du `CLAUDE.md`).
struct AlerteAdmin: Decodable, Identifiable, Hashable {
    let type: String
    let gpId: String?
    let gp: String?
    let cle: String?
    let nature: String?
    let marche: String?
    let libelle: String?
    let tentatives: Int?
    let derniereErreur: String?

    var id: String { "\(type)-\(gpId ?? "")-\(cle ?? "")-\(libelle ?? "")" }

    /// Seule une alerte de libellé, rattachée à un GP, se résout depuis l'app.
    var resoluble: Bool {
        type == "libelle_non_reconnu" && gpId != nil && !(libelle ?? "").isEmpty
    }

    /// L'écurie se choisit pour une issue écurie ; le pilote pour toutes les autres.
    var choisitUneEcurie: Bool { nature == "ecurie" }

    var titre: String {
        switch type {
        case "libelle_non_reconnu":    return t("admin.alertes.libelle", libelle ?? "?")
        case "rattachement_impossible": return t("admin.alertes.rattachement")
        case "definitif_en_echec":     return t("admin.alertes.definitif", tentatives ?? 0)
        case "grand_prix_ambigu":      return t("admin.alertes.gpAmbigu")
        case "pronostics_en_attente":  return t("admin.alertes.enAttente", tentatives ?? 0)
        default:                       return type
        }
    }

    var detail: String {
        if type == "libelle_non_reconnu" {
            return [marche.map { t("admin.alertes.marche", $0) }, derniereErreur]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return derniereErreur ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case type, gp, cle, nature, marche, libelle, tentatives
        case gpId = "gp_id"
        case derniereErreur = "derniere_erreur"
    }
}

struct ReponseAlertes: Decodable {
    let disponible: Bool
    let alertes: [AlerteAdmin]
}

struct EngagesDuGP: Decodable {
    struct Pilote: Decodable, Identifiable, Hashable {
        let numero: Int
        let nom: String
        let equipe: String
        var id: Int { numero }
    }
    struct Ecurie: Decodable, Identifiable, Hashable {
        let ecurieId: String
        let nom: String
        var id: String { ecurieId }
        enum CodingKeys: String, CodingKey {
            case nom
            case ecurieId = "ecurie_id"
        }
    }
    let pilotes: [Pilote]
    let ecuries: [Ecurie]
}

private struct DemandeResolution: Encodable {
    let gpId: String
    let libelle: String
    let numeroPilote: Int?
    let ecurieId: String?

    enum CodingKeys: String, CodingKey {
        case libelle
        case gpId = "gp_id"
        case numeroPilote = "numero_pilote"
        case ecurieId = "ecurie_id"
    }
}

private struct ReponseResolution: Decodable {
    let statut: String
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
        case "lance":  return t("admin.lance")
        case "traite": return t("admin.traite")
        default:       return t("admin.acceptee")
        }
    }
}
