import AppIntents
import WidgetKit

/// La configuration du widget « Classement » : le championnat, et pour le petit format, la
/// liste ou la piste.
///
/// > **Les libellés de cette configuration sont la seule exception à `t()`.** App Intents
/// > extrait titres et libellés **à la compilation** (constantes obligatoires) et c'est iOS
/// > qui les affiche, dans la langue du téléphone : ils vivent donc dans
/// > `Intentions.xcstrings`, propre au widget. Le widget lui-même suit `t()` et la langue
/// > de l'app.
struct IntentionClassement: WidgetConfigurationIntent {

    static var title: LocalizedStringResource = LocalizedStringResource(
        "intention.titre", defaultValue: "Classement", table: "Intentions")
    static var description = IntentDescription(LocalizedStringResource(
        "intention.description", defaultValue: "Choisis le championnat à afficher.",
        table: "Intentions"))

    /// `nil` : **la carte au premier plan de la pile d'accueil**, relue à chaque
    /// rafraîchissement — le widget suit la pile tant qu'on ne lui impose rien.
    @Parameter(title: LocalizedStringResource("intention.championnat", defaultValue: "Championnat",
                                              table: "Intentions"))
    var championnat: ChampionnatEntite?

    @Parameter(title: LocalizedStringResource("intention.affichage", defaultValue: "Petit format",
                                              table: "Intentions"),
               default: .classement)
    var affichage: AffichagePetit
}

/// Ce que montre le petit format. Le grand montre les deux.
enum AffichagePetit: String, AppEnum {
    case classement, piste

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "intention.typeAffichage", defaultValue: "Affichage", table: "Intentions"))

    static var caseDisplayRepresentations: [AffichagePetit: DisplayRepresentation] = [
        .classement: DisplayRepresentation(title: LocalizedStringResource(
            "intention.affichage.classement", defaultValue: "Classement", table: "Intentions")),
        .piste: DisplayRepresentation(title: LocalizedStringResource(
            "intention.affichage.piste", defaultValue: "Piste", table: "Intentions"))
    ]
}

/// Un championnat du compte, tel que l'app l'a écrit dans l'App Group
/// (``DonneesWidget/ContenuClassement``). Son nom est une donnée : il ne se traduit pas.
struct ChampionnatEntite: AppEntity {

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "intention.championnat", defaultValue: "Championnat", table: "Intentions"))
    static var defaultQuery = RequeteChampionnats()

    let id: UUID
    let nom: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(nom)") }
}

/// La liste vient de l'App Group, **jamais du réseau** : elle est là dès que l'app a été
/// ouverte une fois connectée.
struct RequeteChampionnats: EntityQuery {

    private var tous: [ChampionnatEntite] {
        DonneesWidget.lireClassement().championnats.map { ChampionnatEntite(id: $0.id, nom: $0.nom) }
    }

    func entities(for identifiers: [UUID]) async throws -> [ChampionnatEntite] {
        tous.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ChampionnatEntite] { tous }
}
