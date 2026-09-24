import Foundation

/// Ce que la base sait des Grands Prix de la saison, servi par `GET /scraper/cotes`
/// (§3.4) — de quoi croiser la liste statique de ``CalendrierView``.
///
/// > **La liste ne dépend pas de cet appel.** Les douze cartes viennent de
/// > ``GrandPrixSaison/saison2026`` et s'affichent quoi qu'il arrive : l'échec fait perdre
/// > les états et les identifiants, jamais le calendrier (`docs/swift-app.md` §7.6).
///
/// Il n'y a **pas de route `GET /gp`** : `/scraper/cotes` est publique, rend tous les
/// Grands Prix en base avec `id`, `statut`, les deux heures et leurs marchés — c'est la
/// lecture que fait déjà le calendrier de la version web (`chargerCotesEnBase`).
///
/// **Pas de cache de session** : chaque apparition de l'onglet rappelle la route. Les états
/// déjà affichés restent en place pendant le rechargement — le spinner ne sert qu'au
/// premier chargement et après un échec.
@MainActor
final class CalendrierSaison: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret([GrandPrixEnBase])
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    private var enCours = false

    /// Ce que la base sait, `nil` tant que rien n'a été lu — **« inconnu » n'est pas
    /// « absent de la base »** : le second fait d'un Grand Prix un « À venir », le premier
    /// ne dit rien.
    var enBase: [GrandPrixEnBase]? {
        if case .pret(let liste) = etat { return liste }
        return nil
    }

    func charger() async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            let liste: [GrandPrixEnBase] = try await APIClient.partage.requete("scraper/cotes")
            etat = .pret(liste)
        } catch is CancellationError {
            // Onglet quitté pendant l'appel : la prochaine apparition le relance.
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }
}
