import Foundation
import WidgetKit

/// Ce que l'app et le widget « Classement » se partagent dans l'App Group — la suite de
/// ``DonneesWidget``, **seul propriétaire** de l'App Group, compilée par les deux cibles.
///
/// - **L'app** écrit la liste des championnats du compte (id, nom), celui de la carte au
///   premier plan de la pile d'accueil, et l'identifiant du profil (``SynchroWidgetClassement``).
/// - **Le widget** y range le dernier classement reçu de chaque championnat et sa date :
///   hors ligne ou jeton expiré, il les affiche avec « Mis à jour à HH:mm ». Les avatars
///   réduits vivent à côté, en fichiers (``dossierAvatars``).
///
/// La déconnexion et la suppression du compte effacent **tout** (``effacerClassement()``),
/// avec le jeton du Keychain (``JetonWidget``).
extension DonneesWidget {

    /// Le `kind` du widget « Classement ».
    static let typeWidgetClassement = "GreedF1ClassementWidget"

    /// Un tap ouvre l'app **sur ce championnat** (`BarreNavigation`).
    static func urlChampionnat(_ id: UUID) -> URL {
        URL(string: "greedf1://championnat/\(id.uuidString.lowercased())")!
    }

    /// L'identifiant porté par une URL ``urlChampionnat(_:)``, sinon `nil`.
    static func championnat(de url: URL) -> UUID? {
        guard url.scheme == "greedf1", url.host == "championnat" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    struct ChampionnatWidget: Codable, Equatable, Hashable, Identifiable {
        let id: UUID
        let nom: String
    }

    /// Un classement tel que le widget l'a reçu, et quand.
    struct ReleveClassement: Codable, Equatable {
        let membres: [Membre]
        let date: Date
    }

    struct ContenuClassement: Codable, Equatable {
        var championnats: [ChampionnatWidget] = []
        /// La carte au premier plan de la pile d'accueil — le choix par défaut du widget.
        var premierPlan: UUID?
        /// Le compte connecté : sa ligne est celle qui s'ajoute sous le podium.
        var profilId: UUID?
        /// Par identifiant de championnat, en minuscules.
        var releves: [String: ReleveClassement] = [:]

        /// Le championnat à afficher : celui choisi s'il est encore dans la liste, sinon le
        /// premier plan, sinon le premier connu.
        func championnat(choisi: UUID?) -> ChampionnatWidget? {
            if let choisi, let trouve = championnats.first(where: { $0.id == choisi }) { return trouve }
            if let premierPlan, let trouve = championnats.first(where: { $0.id == premierPlan }) { return trouve }
            return championnats.first
        }

        func releve(_ id: UUID) -> ReleveClassement? { releves[id.uuidString.lowercased()] }
    }

    private static let cleClassement = "widget.classement"

    // MARK: - Lecture

    static func lireClassement() -> ContenuClassement {
        guard let donnees = stockageClassement?.data(forKey: cleClassement),
              let contenu = try? decodeurClassement.decode(ContenuClassement.self, from: donnees)
        else { return ContenuClassement() }
        return contenu
    }

    // MARK: - Écriture

    /// La liste du compte, le premier plan et le profil. Les relevés des championnats
    /// quittés partent avec eux. Rend `true` si quelque chose a changé.
    @discardableResult
    static func publier(championnats: [ChampionnatWidget], premierPlan: UUID?,
                        profilId: UUID?) -> Bool {
        modifierClassement { contenu in
            if contenu.profilId != profilId { contenu.releves = [:] }
            contenu.championnats = championnats
            contenu.premierPlan = premierPlan
            contenu.profilId = profilId
            let gardes = Set(championnats.map { $0.id.uuidString.lowercased() })
            contenu.releves = contenu.releves.filter { gardes.contains($0.key) }
        }
    }

    /// La carte du dessus de la pile vient de changer.
    @discardableResult
    static func enregistrer(premierPlan: UUID?) -> Bool {
        modifierClassement { $0.premierPlan = premierPlan }
    }

    /// Le widget range ce qu'il vient de recevoir.
    @discardableResult
    static func enregistrer(_ releve: ReleveClassement, pour id: UUID) -> Bool {
        modifierClassement { $0.releves[id.uuidString.lowercased()] = releve }
    }

    /// Déconnexion, suppression du compte : la liste, les relevés et les avatars.
    static func effacerClassement() {
        stockageClassement?.removeObject(forKey: cleClassement)
        if let dossier = dossierAvatars { try? FileManager.default.removeItem(at: dossier) }
    }

    /// Demande au widget « Classement » de se redessiner, **seulement si quelque chose a
    /// changé** — comme ``recharger(si:)``.
    static func rechargerClassement(si change: Bool = true) {
        guard change else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: typeWidgetClassement)
    }

    /// Les avatars réduits du widget, un fichier par URL.
    static var dossierAvatars: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupe)?
            .appendingPathComponent("Library/Caches/avatars-widget", isDirectory: true)
    }

    // MARK: - Interne

    private static var stockageClassement: UserDefaults? { UserDefaults(suiteName: groupe) }

    private static let decodeurClassement: JSONDecoder = {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .secondsSince1970
        return decodeur
    }()

    private static let encodeurClassement: JSONEncoder = {
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .secondsSince1970
        return encodeur
    }()

    private static func modifierClassement(_ changement: (inout ContenuClassement) -> Void) -> Bool {
        let avant = lireClassement()
        var apres = avant
        changement(&apres)
        guard apres != avant, let donnees = try? encodeurClassement.encode(apres) else { return false }
        stockageClassement?.set(donnees, forKey: cleClassement)
        return true
    }
}
