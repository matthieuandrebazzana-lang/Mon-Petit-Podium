import Foundation

/// Le classement d'un championnat, servi par `GET /championnats/{id}/classement` (§3.3).
///
/// > **Un seul appel pour les deux segments.** ``ChampionnatDetailView`` possède cette
/// > instance ; le classement et la piste lisent le même tableau. Deux appels auraient pu
/// > se croiser avec un Grand Prix noté entre les deux — une voiture qui ne dit plus le
/// > score de sa ligne.
///
/// **Pas de cache de session** (`docs/swift-app.md` §7.6) : chaque apparition de l'écran
/// rappelle la route, et le classement déjà affiché reste en place pendant ce
/// rechargement. Le spinner ne sert qu'au premier chargement et après un échec.
@MainActor
final class ClassementChampionnat: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret([Membre])
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    private let championnatId: UUID

    /// Vrai pendant un appel : un retour rapide du profil d'un membre n'en lance pas un
    /// second par-dessus le premier.
    private var enCours = false

    init(championnatId: UUID) {
        self.championnatId = championnatId
    }

    func charger() async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            // L'UUID en minuscules : la forme que sert le backend, et celle de ses journaux.
            let chemin = "championnats/\(championnatId.uuidString.lowercased())/classement"
            let membres: [Membre] = try await APIClient.partage.requete(chemin)
            etat = .pret(membres)
        } catch is CancellationError {
            // Écran quitté pendant l'appel : rien à signaler.
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }
}
