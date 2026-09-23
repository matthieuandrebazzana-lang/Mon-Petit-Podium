import Foundation

/// Les championnats du compte connecté, servis par `GET /championnats/moi` (§3.3).
///
/// > **Un seul propriétaire.** L'accueil et l'onglet **Championnats** affichent la même
/// > liste : une instance, créée par ``BarreNavigation``, descend dans les deux. Deux
/// > appels écrits séparément auraient fini par ne plus dire la même chose — un
/// > championnat rejoint visible ici et pas là.
///
/// **Pas de cache de session** (`docs/swift-app.md` §7.6) : chaque apparition d'un des
/// deux écrans rappelle la route. La liste déjà affichée reste en place pendant ce
/// rechargement — le spinner ne sert qu'au premier chargement et après un échec, sans
/// quoi chaque changement d'onglet ferait clignoter l'écran.
@MainActor
final class MesChampionnats: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret([Championnat])
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    /// Vrai pendant un appel : deux écrans qui apparaissent ensemble n'en lancent qu'un.
    private var enCours = false

    /// Une demande forcée arrivée pendant un appel : la liste en vol peut dater d'avant
    /// l'écriture, elle est donc redemandée une fois l'appel fini.
    private var aRelancer = false

    /// - Parameter forcer: `true` après une écriture (création, adhésion). Sans lui, un
    ///   chargement déjà en vol — lancé **avant** l'écriture — absorberait la demande, et
    ///   le championnat obtenu manquerait à la liste jusqu'au prochain changement d'onglet.
    func charger(forcer: Bool = false) async {
        guard !enCours else {
            if forcer { aRelancer = true }
            return
        }
        enCours = true
        defer { enCours = false }

        repeat {
            aRelancer = false
            await lire()
        } while aRelancer
    }

    private func lire() async {
        if case .pret = etat {} else { etat = .chargement }
        do {
            let liste: [Championnat] = try await APIClient.partage.requete("championnats/moi")
            etat = .pret(liste)
        } catch is CancellationError {
            // Écran quitté pendant l'appel : rien à signaler. Un premier chargement
            // interrompu garde son spinner, et la prochaine apparition le relance.
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }
}
