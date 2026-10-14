import Foundation
import WidgetKit

/// Ce que l'app confie au widget « Prochain GP » (`GreedF1Widget/`) — **seul propriétaire**
/// de l'App Group `group.com.bazzana.greedf1`.
///
/// Compilé par **les deux cibles** : l'app y écrit, le widget y lit — et y réécrit ce que
/// `GET /calendrier` lui a appris, pour qu'un widget sans réseau ne retombe pas sur des
/// données plus vieilles que celles qu'il a déjà vues.
///
/// **Rien n'y dépend d'une session.** Le widget ne connaît ni le compte, ni ses pronostics :
/// le Grand Prix suivant, ses deux heures, son statut, et la langue de l'app — tout ce qui
/// est public.
///
/// **La langue est celle de l'app, pas celle du téléphone** : l'app écrit sa langue active
/// (choisie ou détectée) au lancement et à chaque changement, et le widget l'impose à
/// ``LanguageManager`` avant de dessiner.
enum DonneesWidget {

    static let groupe = "group.com.bazzana.greedf1"

    /// Le `kind` du widget — ce que ``recharger()`` demande à WidgetKit de relire.
    static let typeWidget = "GreedF1Widget"

    /// Un tap sur le widget ouvre l'app **sur l'accueil** (`BarreNavigation`).
    static let urlAccueil = URL(string: "greedf1://accueil")!

    /// Un Grand Prix tel que le widget en a besoin. Le **slug** est déjà résolu
    /// (``SlugCircuit/de(_:dateCourse:)``, le seul propriétaire) ; ``nom`` n'est que le
    /// repli d'affichage hors saison, comme partout (``GrandPrixSaison/nomAffiche(slug:repli:)``).
    struct GrandPrix: Codable, Equatable {
        let id: UUID
        let nom: String
        let slug: String
        let dateCourse: Date?
        let dateQualifications: Date?
        let statut: String

        init(_ gp: GrandPrixEnBase) {
            id = gp.id
            nom = gp.nom
            slug = gp.slug
            dateCourse = gp.dateCourse
            dateQualifications = gp.dateQualifications
            statut = gp.statut
        }

        var nomAffiche: String { GrandPrixSaison.nomAffiche(slug: slug, repli: nom) }
    }

    struct Contenu: Codable, Equatable {
        var grandsPrix: [GrandPrix] = []
        /// `fr` ou `en` — ``Langue/rawValue``. `nil` tant que l'app n'a pas été lancée.
        var langue: String?
    }

    private static let cle = "widget.prochainGP"

    private static var stockage: UserDefaults? { UserDefaults(suiteName: groupe) }

    // MARK: - Lecture

    static func lire() -> Contenu {
        guard let donnees = stockage?.data(forKey: cle),
              let contenu = try? JSONDecoder().decode(Contenu.self, from: donnees)
        else { return Contenu() }
        return contenu
    }

    static var langue: Langue? { lire().langue.flatMap(Langue.init(rawValue:)) }

    // MARK: - Écriture

    /// Fusionne des Grands Prix par identifiant — un relevé plus récent remplace l'ancien,
    /// les autres restent. Rend `true` si quelque chose a changé.
    @discardableResult
    static func fusionner(_ lus: [GrandPrixEnBase]) -> Bool {
        modifier { contenu in
            var parId = Dictionary(contenu.grandsPrix.map { ($0.id, $0) },
                                   uniquingKeysWith: { _, dernier in dernier })
            for gp in lus { parId[gp.id] = GrandPrix(gp) }
            contenu.grandsPrix = parId.values.sorted(by: Self.ordre)
        }
    }

    /// La langue active de l'app. Rend `true` si elle a changé.
    @discardableResult
    static func enregistrer(langue: Langue) -> Bool {
        modifier { $0.langue = langue.rawValue }
    }

    /// Demande au widget de se redessiner. **Seulement si quelque chose a changé** : un
    /// rechargement demandé pour rien coûte une relecture du réseau au widget.
    static func recharger(si change: Bool = true) {
        guard change else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: typeWidget)
    }

    private static func modifier(_ changement: (inout Contenu) -> Void) -> Bool {
        let avant = lire()
        var apres = avant
        changement(&apres)
        guard apres != avant, let donnees = try? JSONEncoder().encode(apres) else { return false }
        stockage?.set(donnees, forKey: cle)
        return true
    }

    /// Par départ croissant, **un départ inconnu en fin de liste** (§7.4).
    static func ordre(_ a: GrandPrix, _ b: GrandPrix) -> Bool {
        switch (a.dateCourse, b.dateCourse) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        default: return false
        }
    }
}
