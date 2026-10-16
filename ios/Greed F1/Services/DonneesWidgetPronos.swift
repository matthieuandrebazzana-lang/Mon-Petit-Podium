import Foundation
import WidgetKit

/// Ce que l'app et le widget « Mes pronos » se partagent dans l'App Group — la suite de
/// ``DonneesWidget``, **seul propriétaire** de l'App Group, compilée par les deux cibles
/// (`docs/decisions.md` §30).
///
/// - **Le widget** lit `GET /widget/pronos` avec le jeton widget (``JetonWidget``) et range
///   ici **la réponse brute** : hors ligne ou jeton expiré, il redessine la dernière reçue,
///   sans en dire la date. Une seule forme, décodée par ``JSONDecoder/api`` dans les deux
///   sens — aucun modèle n'a à savoir s'encoder.
/// - **L'app** ne l'écrit jamais : elle demande un rechargement (ouverture, envoi de
///   pronostics) et l'efface à la déconnexion (``effacerPronos()``). Elle y relit seulement
///   le Grand Prix qu'un tap sur le widget demande d'ouvrir.
extension DonneesWidget {

    /// Le `kind` du widget « Mes pronos ».
    static let typeWidgetPronos = "GreedF1PronosWidget"

    // MARK: - Les données

    /// La réponse de `GET /widget/pronos`.
    struct PronosWidget: Decodable, Equatable {
        /// Le premier GP non terminé — son départ peut être passé, résultats en attente.
        let prochain: GrandPrixPronosWidget?
        /// Le dernier GP terminé.
        let dernier: GrandPrixPronosWidget?

        func grandPrix(_ id: UUID) -> GrandPrixPronosWidget? {
            [prochain, dernier].compactMap { $0 }.first { $0.id == id }
        }
    }

    struct GrandPrixPronosWidget: Decodable, Equatable, Identifiable {
        let id: UUID
        let nom: String
        let dateCourse: Date?
        let dateQualifications: Date?
        let statut: String
        let statutResultats: String?
        /// Au moins un pronostic en base — `etat_pronos == "enregistres"`.
        let aDesPronostics: Bool
        let pronostics: [PronosticWidget]
        /// Le total marqué, **seulement une fois `termine`** et un pronostic jugé. `nil`
        /// sinon — jamais `0` avant la course.
        let pointsGagnes: Int?

        enum CodingKeys: String, CodingKey {
            case id, nom, statut, pronostics
            case dateCourse = "date_course"
            case dateQualifications = "date_qualifications"
            case statutResultats = "statut_resultats"
            case etatPronos = "etat_pronos"
            case pointsGagnes = "points_gagnes"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            nom = try c.decode(String.self, forKey: .nom)
            dateCourse = try c.decodeIfPresent(Date.self, forKey: .dateCourse)
            dateQualifications = try c.decodeIfPresent(Date.self, forKey: .dateQualifications)
            statut = try c.decode(String.self, forKey: .statut)
            statutResultats = try? c.decodeIfPresent(String.self, forKey: .statutResultats)
            pronostics = (try? c.decodeIfPresent([PronosticWidget].self, forKey: .pronostics)) ?? []
            let etat = try? c.decodeIfPresent(String.self, forKey: .etatPronos)
            aDesPronostics = etat == "enregistres" || !pronostics.isEmpty
            pointsGagnes = try? c.decodeIfPresent(Int.self, forKey: .pointsGagnes)
        }

        /// Pour les exemples de la galerie seulement.
        init(id: UUID = UUID(), nom: String, dateCourse: Date?, dateQualifications: Date?,
             statut: String, statutResultats: String? = nil, pronostics: [PronosticWidget],
             pointsGagnes: Int? = nil) {
            self.id = id
            self.nom = nom
            self.dateCourse = dateCourse
            self.dateQualifications = dateQualifications
            self.statut = statut
            self.statutResultats = statutResultats
            self.aDesPronostics = !pronostics.isEmpty
            self.pronostics = pronostics
            self.pointsGagnes = pointsGagnes
        }

        /// Le seul propriétaire du slug, comme pour toute ligne de la base.
        var slug: String { SlugCircuit.de(nom, dateCourse: dateCourse) }
        var nomAffiche: String { GrandPrixSaison.nomAffiche(slug: slug, repli: nom) }
    }

    /// Une ligne — **le podium en arrive deux**, une par pilote.
    struct PronosticWidget: Decodable, Equatable, Hashable {
        /// `obligatoire` ou `bonus`.
        let categorie: String
        /// `vainqueur`, `podium` ou `bonus`.
        let type: String
        let libelle: String?
        let choix: String?
        /// Les points en jeu — jamais une cote.
        let points: Int?
        /// `nil` tant que le pronostic n'est pas jugé ; `0` = raté.
        let pointsGagnes: Int?
        /// `en_attente`, `non_evaluable`, `gagne` ou `perdu`.
        let statut: String?

        enum CodingKeys: String, CodingKey {
            case categorie, type, libelle, choix, points, statut
            case pointsGagnes = "points_gagnes"
        }

        var estBonus: Bool { categorie == "bonus" }
    }

    // MARK: - Les liens

    /// Un tap ouvre la saisie ou le récapitulatif de ce GP (``EntreePronosView`` tranche).
    static func urlPronos(_ id: UUID) -> URL {
        URL(string: "greedf1://pronos/\(id.uuidString.lowercased())")!
    }

    /// Un tap après la course ouvre ses résultats.
    static func urlResultats(_ id: UUID) -> URL {
        URL(string: "greedf1://resultats/\(id.uuidString.lowercased())")!
    }

    enum DemandePronos: Equatable {
        case pronos(UUID)
        case resultats(UUID)
    }

    /// La demande portée par une URL ``urlPronos(_:)`` ou ``urlResultats(_:)``, sinon `nil`.
    static func demandePronos(de url: URL) -> DemandePronos? {
        guard url.scheme == "greedf1", let id = UUID(uuidString: url.lastPathComponent)
        else { return nil }
        switch url.host {
        case "pronos": return .pronos(id)
        case "resultats": return .resultats(id)
        default: return nil
        }
    }

    // MARK: - Lecture et écriture

    private static let clePronos = "widget.pronos"

    static func lirePronos() -> PronosWidget? {
        guard let brut = UserDefaults(suiteName: groupe)?.data(forKey: clePronos) else { return nil }
        return try? JSONDecoder.api.decode(PronosWidget.self, from: brut)
    }

    /// Le widget range la réponse **brute** qu'il vient de décoder. Rend `true` si elle a
    /// changé.
    @discardableResult
    static func enregistrerPronos(_ brut: Data) -> Bool {
        let stockage = UserDefaults(suiteName: groupe)
        guard stockage?.data(forKey: clePronos) != brut else { return false }
        stockage?.set(brut, forKey: clePronos)
        return true
    }

    /// Déconnexion, suppression du compte : le widget retombe sur son état vide.
    static func effacerPronos() {
        UserDefaults(suiteName: groupe)?.removeObject(forKey: clePronos)
    }

    /// Demande au widget « Mes pronos » de relire `GET /widget/pronos`.
    static func rechargerPronos() {
        WidgetCenter.shared.reloadTimelines(ofKind: typeWidgetPronos)
    }
}
