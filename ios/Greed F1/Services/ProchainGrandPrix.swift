import Foundation
import Supabase

/// Le Grand Prix suivant du widget de l'accueil, **lu directement dans Supabase** sous RLS
/// (`grands_prix` est en lecture publique) — pendant de `chargerProchainGp`
/// (`frontend/src/lib/pronostics.js`).
///
/// **Pourquoi pas Railway** : l'accueil est le premier écran de l'app, et lui faire attendre
/// le réveil du plan gratuit pour afficher son bloc principal serait le pire endroit où
/// payer ce délai (`docs/swift-app.md` §7.6, étape 5).
///
/// Le prochain = le premier `a_venir` ou `cotes_figees` par `date_course` croissante, **un
/// départ inconnu en fin de liste** (§7.4). Aucun Grand Prix à venir est un état normal :
/// `pret(nil)`, et le widget ne s'affiche pas.
///
/// **Le GP du jour reste affiché jusqu'à minuit**, heure locale du téléphone, même une fois
/// `termine` : un GP dont le départ tombe aujourd'hui ou plus tard est candidat quel que
/// soit son statut. Sans cela, le widget passait au GP suivant dès que les résultats
/// tombaient, le dimanche après-midi — le lundi seulement, il cède la place.
///
/// **Il dit aussi si le joueur a déjà pronostiqué ce GP** (``aDesPronostics``) : c'est ce
/// qui choisit le bouton du widget — « Faire mes pronos » ou « Voir mes pronos ».
@MainActor
final class ProchainGrandPrix: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret(GrandPrixEnBase?)
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    /// Au moins un pronostic du joueur existe en base pour ce GP. **`nil` tant qu'on ne
    /// sait pas** — chargement, échec, pas de GP : le widget n'affiche alors aucun bouton
    /// plutôt qu'un bouton qui mentirait.
    @Published private(set) var aDesPronostics: Bool?

    private var enCours = false

    /// Le GP passe par le cache *stale-while-revalidate* (``CacheService``, 5 min, comme le
    /// calendrier) ; l'existence d'un pronostic, non — elle change au retour du parcours de
    /// pronostics, et sa lecture est une requête d'une ligne.
    func charger(forcer: Bool = false) async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            try await CacheService.partage.charger(
                "prochain-gp", duree: CacheService.Duree.calendrier, forcer: forcer,
                afficher: { (gp: GrandPrixEnBase?) in
                    if etat != .pret(gp) { etat = .pret(gp) }
                },
                lire: {
                    let reponse = try await SupabaseManager.partage.client
                        .from("grands_prix")
                        .select("id,nom,date_course,date_qualifications,statut,statut_resultats")
                        .or("statut.in.(a_venir,cotes_figees),date_course.gte.\(Self.debutDuJour())")
                        .order("date_course", ascending: true, nullsFirst: false)
                        .limit(1)
                        .execute()
                    return try JSONDecoder.api.decode([GrandPrixEnBase].self, from: reponse.data).first
                })
            await relirePronostics()
        } catch is CancellationError {
            // Écran quitté pendant l'appel : la prochaine apparition le relance.
        } catch is URLError {
            etat = .echec(.reseau)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }

    /// Relit la seule existence d'un pronostic du joueur pour le GP affiché, **en direct**
    /// sous RLS (un joueur relit les siens) — rappelé au retour du parcours de pronostics,
    /// sans recharger le GP.
    func relirePronostics() async {
        guard case .pret(let gp?) = etat else { aDesPronostics = nil; return }
        let client = SupabaseManager.partage.client
        do {
            let moi = try await client.auth.session.user.id
            let reponse = try await client
                .from("pronostics")
                .select("id")
                .eq("gp_id", value: gp.id.uuidString.lowercased())
                .eq("profil_id", value: moi.uuidString.lowercased())
                .limit(1)
                .execute()
            struct Ligne: Decodable { let id: UUID }
            let lus = try JSONDecoder.api.decode([Ligne].self, from: reponse.data)
            aDesPronostics = !lus.isEmpty
        } catch is CancellationError {
            // Écran quitté : la valeur connue reste.
        } catch {
            aDesPronostics = nil
        }
    }

    /// Minuit ce matin, heure locale, en ISO 8601 UTC — la borne du « GP du jour ». Un
    /// départ postérieur appartient à aujourd'hui ou plus tard.
    static func debutDuJour(le maintenant: Date = .now) -> String {
        let debut = Calendar.current.startOfDay(for: maintenant)
        return ISO8601DateFormatter().string(from: debut)
    }
}
