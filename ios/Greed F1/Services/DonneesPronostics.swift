import Foundation
import Supabase

/// Ce qu'il faut aux écrans de pronostics : les cotes (`GET /grands-prix/{id}/cotes`), les
/// favoris (`GET …/favoris`) et, pour la saisie seulement, **mes pronostics déjà
/// enregistrés**, lus en direct sous RLS (§3.9) — pendant de `chargerTableauCotes` et
/// `chargerSaisie` (`frontend/src/lib/pronostics.js`).
///
/// Possédé par l'écran (`@StateObject`), rappelé à chaque apparition — **pas de cache de
/// session** (§7.6). Les données déjà affichées restent en place pendant le rechargement ;
/// le spinner ne sert qu'au premier chargement et après un échec. **Le premier échec
/// l'emporte** : un demi-écran à côté d'une erreur demanderait de deviner ce qui manque.
@MainActor
final class DonneesPronostics: ObservableObject {

    struct Donnees: Equatable {
        var gp: CotesGrandPrix
        /// Dans l'ordre d'épinglage, tel que le serveur les sert.
        var favoris: [Favori]
        /// `nil` quand l'écran ne les demande pas (tableau des cotes).
        var miens: [PronosticEnBase]?
    }

    enum Etat: Equatable {
        case chargement
        case pret(Donnees)
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    let gpId: UUID
    private let avecMesPronostics: Bool
    private var enCours = false

    init(gpId: UUID, avecMesPronostics: Bool) {
        self.gpId = gpId
        self.avecMesPronostics = avecMesPronostics
    }

    var donnees: Donnees? {
        if case .pret(let donnees) = etat { return donnees }
        return nil
    }

    private var racine: String { "grands-prix/\(gpId.uuidString.lowercased())" }

    // MARK: - Lecture

    func charger() async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if donnees == nil { etat = .chargement }
        do {
            async let gp: CotesGrandPrix = APIClient.partage.requete("\(racine)/cotes")
            async let favoris: [Favori] = APIClient.partage.requete("\(racine)/favoris")
            async let miens = avecMesPronostics ? lireMesPronostics() : nil
            etat = .pret(Donnees(gp: try await gp, favoris: try await favoris,
                                 miens: try await miens))
        } catch is CancellationError {
            // Écran quitté pendant l'appel : la prochaine apparition le relance.
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }

    /// Mes pronostics de ce Grand Prix, **en direct** — la politique RLS autorise un joueur
    /// à relire les siens, passer par Railway n'ajouterait qu'un réveil.
    private func lireMesPronostics() async throws -> [PronosticEnBase] {
        let client = SupabaseManager.partage.client
        do {
            let moi = try await client.auth.session.user.id
            let reponse = try await client
                .from("pronostics")
                .select("id, type, id_outcome_unibet, points_gagnes, pronostic_podium(pilote_1, pilote_2)")
                .eq("gp_id", value: gpId.uuidString.lowercased())
                .eq("profil_id", value: moi.uuidString.lowercased())
                .execute()
            return try JSONDecoder.api.decode([PronosticEnBase].self, from: reponse.data)
        } catch is CancellationError {
            throw CancellationError()
        } catch is URLError {
            throw ErreurAPI.reseau
        } catch {
            throw ErreurAPI.serveur(statut: nil, message: nil)
        }
    }

    // MARK: - Écritures

    /// Épingle ou retire une cote — **mise à jour optimiste** : l'étoile bascule à l'appui,
    /// pas au retour d'un Railway peut-être endormi. En cas de refus, retour à l'état
    /// d'avant : une coche qui mente est pire qu'une étoile qui n'a pas bougé.
    ///
    /// - Returns: l'erreur à afficher, `nil` si l'écriture a abouti.
    func basculerFavori(_ cote: Cote, dans marche: MarcheCotes) async -> ErreurAPI? {
        guard var donnees else { return nil }
        let avant = donnees.favoris
        if avant.contains(where: { $0.idOutcomeUnibet == cote.id }) {
            donnees.favoris.removeAll { $0.idOutcomeUnibet == cote.id }
        } else {
            donnees.favoris.append(Favori(idOutcomeUnibet: cote.id, marche: marche.marche,
                                          libelle: marche.libelle, pilote: cote.pilote,
                                          points: cote.points))
        }
        etat = .pret(donnees)

        do {
            try await APIClient.partage.envoyer("\(racine)/favoris", methode: .post,
                                                corps: CorpsFavori(id_outcome_unibet: cote.id))
            return nil
        } catch {
            if var actuel = self.donnees {
                actuel.favoris = avant
                etat = .pret(actuel)
            }
            return (error as? ErreurAPI) ?? .serveur(statut: nil, message: nil)
        }
    }

    /// `POST …/pronostics` — remplace le jeu complet. **Jamais rejoué d'office** (écriture).
    /// Un `423` arrive en ``ErreurAPI/serveur(statut:message:)`` avec le message du serveur
    /// (« Les pronostics de ce Grand Prix sont fermés… ») : c'est la base qui fait foi.
    func enregistrer(_ corps: CorpsPronostics) async throws {
        try await APIClient.partage.envoyer("\(racine)/pronostics", methode: .post, corps: corps)
        // Le widget « Mes pronos » relit la grille qui vient d'être enregistrée.
        DonneesWidget.rechargerPronos()
    }
}
