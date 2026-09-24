import Foundation

/// Les résultats d'un Grand Prix, servis par `GET /grands-prix/{id}/resultats` (§3.6).
///
/// Possédé par ``ResultatsGPView`` (`@StateObject`), rappelé à chaque apparition — **pas de
/// cache de session** (`docs/swift-app.md` §7.6). Le classement déjà affiché reste en
/// place pendant le rechargement ; le spinner ne sert qu'au premier chargement et après un
/// échec.
@MainActor
final class ResultatsGrandPrix: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret([LigneResultat])
        /// `disponible: false`, classement vide, `404`, ou GP inconnu de la base : la
        /// course n'a pas (encore) de résultats. **Ce n'est pas un échec** — rien à
        /// réessayer.
        case indisponible
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat

    private let gpId: UUID?
    private var enCours = false

    init(gpId: UUID?, etat: Etat = .chargement) {
        self.gpId = gpId
        self.etat = gpId == nil ? .indisponible : etat
    }

    func charger() async {
        guard let gpId, !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            let chemin = "grands-prix/\(gpId.uuidString.lowercased())/resultats"
            let reponse: ResultatsGP = try await APIClient.partage.requete(chemin)
            etat = reponse.disponible && !reponse.classement.isEmpty
                ? .pret(reponse.classement)
                : .indisponible
        } catch is CancellationError {
            // Écran quitté pendant l'appel : rien à signaler.
        } catch ErreurAPI.donnees {
            etat = .indisponible
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }
}
