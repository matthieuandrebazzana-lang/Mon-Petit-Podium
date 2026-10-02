import Foundation

/// Ce qu'un membre a joué sur la saison, Grand Prix par Grand Prix — pour
/// ``HistoriqueGPView``.
///
/// **Aucune route dédiée** : l'écran relit ce que sert déjà ``ResultatsParGPView``.
///
/// | Ce qui est lu | Par où |
/// |---|---|
/// | Les Grands Prix de la saison | `GET /championnats/{id}/calendrier` |
/// | Ses paris sur **un** GP terminé | `GET /grands-prix/{gp}/pronostics/championnat/{id}`, filtré sur son `profil_id` |
/// | Le podium réel | `GET /grands-prix/{gp}/resultats` |
///
/// **Un pronostic n'appartient pas à un championnat** (`pronostics_du_championnat` lit
/// `pronostics` par `profil_id` et `gp_id` seuls) : n'importe quel championnat partagé
/// avec le membre donne donc les mêmes paris. Depuis son propre profil, c'est le premier
/// de `GET /championnats/moi`.
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1).
@MainActor
final class GrandsPrixJoues: ObservableObject {

    /// Un Grand Prix terminé sur lequel le membre a joué.
    struct GrandPrixJoue: Identifiable, Equatable {
        let gpId: UUID
        let nom: String
        let dateCourse: Date?
        /// `nil` tant que rien n'est jugé — « pas encore jugé » n'est pas « zéro ».
        let totalPoints: Int?
        /// Les paris en lignes d'affichage — le podium en deux, une par pilote
        /// (``MembrePronostics/paris``) : les compteurs de la carte comptent ces lignes.
        let pronostics: [PronosticMembre]
        /// Les trois premiers, dans l'ordre. Vide tant que les résultats ne sont pas lus.
        let podium: [LigneResultat]
        /// Résultats encore provisoires : calcul définitif 24 h après la course.
        var provisoire = false

        var id: UUID { gpId }

        /// La clé du drapeau et du tracé — la même normalisation que le calendrier.
        var slug: String { SlugCircuit.de(nom, dateCourse: dateCourse) }

        /// L'entrée du calendrier statique : nom et date écrits comme sur le calendrier.
        var fiche: GrandPrixSaison? { GrandPrixSaison.saison2026.first { $0.slug == slug } }

        var reussis: Int { pronostics.filter { ($0.pointsGagnes ?? 0) > 0 }.count }
    }

    enum Etat: Equatable {
        case chargement
        case pret([GrandPrixJoue])
        /// Aucun championnat : la route des paris n'a rien à interroger.
        case sansChampionnat
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    private let profilId: UUID?
    private let championnatId: UUID?
    private var enCours = false

    /// - Parameters:
    ///   - profilId: le membre à lire ; `nil` = le compte connecté.
    ///   - championnatId: un championnat partagé avec lui ; `nil` = le premier des miens.
    init(profilId: UUID?, championnatId: UUID?) {
        self.profilId = profilId
        self.championnatId = championnatId
    }

    func charger() async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            let membre: UUID
            if let profilId {
                membre = profilId
            } else {
                membre = try await SupabaseManager.partage.client.auth.session.user.id
            }
            guard let championnat = try await championnatALire() else {
                etat = .sansChampionnat
                return
            }
            etat = .pret(try await lire(membre: membre, championnat: championnat))
        } catch is CancellationError {
            // Écran quitté pendant l'appel : la prochaine apparition relance.
        } catch let erreur as ErreurAPI {
            etat = .echec(erreur)
        } catch is URLError {
            etat = .echec(.reseau)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }

    private func championnatALire() async throws -> UUID? {
        if let championnatId { return championnatId }
        let miens: [Championnat] = try await APIClient.partage.requete("championnats/moi")
        return miens.first?.id
    }

    private func lire(membre: UUID, championnat: UUID) async throws -> [GrandPrixJoue] {
        let idChampionnat = championnat.uuidString.lowercased()
        let saison: [GrandPrixDuChampionnat] =
            try await APIClient.partage.requete("championnats/\(idChampionnat)/calendrier")
        let termines = saison.filter(\.resultatsDisponibles)

        let joues = try await withThrowingTaskGroup(of: (Int, GrandPrixJoue?).self) { groupe in
            for (rang, gp) in termines.enumerated() {
                groupe.addTask {
                    (rang, try await Self.lireGrandPrix(gp, membre: membre, championnat: idChampionnat))
                }
            }
            var lus: [(Int, GrandPrixJoue)] = []
            for try await (rang, gp) in groupe {
                if let gp { lus.append((rang, gp)) }
            }
            return lus
        }
        // L'ordre du calendrier servi (date croissante), quel que soit l'ordre d'arrivée.
        return joues.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Un GP : ses paris et, **en parallèle**, le podium. `nil` s'il n'a pas joué.
    private nonisolated static func lireGrandPrix(_ gp: GrandPrixDuChampionnat, membre: UUID,
                                                  championnat: String) async throws -> GrandPrixJoue? {
        let idGp = gp.id.uuidString.lowercased()
        async let membres: [MembrePronostics] =
            APIClient.partage.requete("grands-prix/\(idGp)/pronostics/championnat/\(championnat)")
        // Un podium illisible ne masque pas les paris : la section « Résultat réel » saute.
        async let resultats: ResultatsGP? = try? APIClient.partage.requete("grands-prix/\(idGp)/resultats")

        guard let ligne = try await membres.first(where: { $0.profilId == membre }),
              ligne.aJoue else { return nil }

        let classement = await resultats?.classement ?? []
        let podium = (1...3).compactMap { place in classement.first { $0.position == place } }
        return GrandPrixJoue(gpId: gp.id, nom: gp.nom, dateCourse: gp.dateCourse,
                             totalPoints: ligne.totalPoints, pronostics: ligne.paris,
                             podium: podium, provisoire: gp.provisoire)
    }
}
