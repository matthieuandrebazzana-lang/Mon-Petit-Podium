import Foundation

/// Les deux lectures de ``ResultatsParGPView`` — et **le second dépend du premier**.
///
/// | Ce qui est lu | Par où |
/// |---|---|
/// | Les Grands Prix de la saison | `GET /championnats/{id}/calendrier` |
/// | Les paris d'**un** Grand Prix | `GET /grands-prix/{gp}/pronostics/championnat/{id}` |
///
/// **La route sert un Grand Prix à la fois**, et c'est ce qui dessine l'écran : le
/// sélecteur est la conséquence de la forme de la donnée (`docs/composants.md` §9).
///
/// Un Grand Prix déjà consulté est **gardé pour la vie de l'écran** : revenir sur une
/// pastille ressert sa liste sans spinner, comme la clé par Grand Prix du web.
@MainActor
final class ResultatsParGrandPrix: ObservableObject {

    enum Etat<Valeur: Equatable>: Equatable {
        case chargement
        case pret(Valeur)
        case echec(ErreurAPI)
    }

    @Published private(set) var saison: Etat<[GrandPrixDuChampionnat]> = .chargement
    @Published private(set) var paris: [UUID: Etat<[MembrePronostics]>] = [:]

    private let championnatId: UUID
    private var enCours: Set<UUID> = []
    private var saisonEnCours = false

    init(championnatId: UUID) {
        self.championnatId = championnatId
    }

    private var idChampionnat: String { championnatId.uuidString.lowercased() }

    /// Les Grands Prix **terminés**, dans l'ordre du calendrier (date croissante).
    var termines: [GrandPrixDuChampionnat] {
        guard case .pret(let liste) = saison else { return [] }
        return liste.filter(\.resultatsDisponibles)
    }

    func chargerSaison() async {
        guard !saisonEnCours else { return }
        saisonEnCours = true
        defer { saisonEnCours = false }

        if case .pret = saison {} else { saison = .chargement }
        do {
            let liste: [GrandPrixDuChampionnat] =
                try await APIClient.partage.requete("championnats/\(idChampionnat)/calendrier")
            saison = .pret(liste)
        } catch is CancellationError {
        } catch let erreur as ErreurAPI {
            saison = .echec(erreur)
        } catch {
            saison = .echec(.serveur(statut: nil, message: nil))
        }
    }

    /// Les paris d'un Grand Prix. Déjà lus : rien n'est rappelé, sauf après un échec.
    func chargerParis(_ gp: UUID) async {
        if case .pret = paris[gp] { return }
        guard !enCours.contains(gp) else { return }
        enCours.insert(gp)
        defer { enCours.remove(gp) }

        paris[gp] = .chargement
        do {
            let chemin = "grands-prix/\(gp.uuidString.lowercased())/pronostics/championnat/\(idChampionnat)"
            let membres: [MembrePronostics] = try await APIClient.partage.requete(chemin)
            paris[gp] = .pret(MembrePronostics.classer(membres))
        } catch is CancellationError {
            // Pastille quittée pendant l'appel : la prochaine sélection relance.
            paris[gp] = nil
        } catch let erreur as ErreurAPI {
            paris[gp] = .echec(erreur)
        } catch {
            paris[gp] = .echec(.serveur(statut: nil, message: nil))
        }
    }
}
