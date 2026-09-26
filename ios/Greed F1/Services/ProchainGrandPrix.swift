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
@MainActor
final class ProchainGrandPrix: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret(GrandPrixEnBase?)
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    private var enCours = false

    func charger() async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            let reponse = try await SupabaseManager.partage.client
                .from("grands_prix")
                .select("id,nom,date_course,date_qualifications,statut")
                .or("statut.in.(a_venir,cotes_figees),date_course.gte.\(Self.debutDuJour())")
                .order("date_course", ascending: true, nullsFirst: false)
                .limit(1)
                .execute()
            let lus = try JSONDecoder.api.decode([GrandPrixEnBase].self, from: reponse.data)
            etat = .pret(lus.first)
        } catch is CancellationError {
            // Écran quitté pendant l'appel : la prochaine apparition le relance.
        } catch is URLError {
            etat = .echec(.reseau)
        } catch {
            etat = .echec(.serveur(statut: nil, message: nil))
        }
    }

    /// Minuit ce matin, heure locale, en ISO 8601 UTC — la borne du « GP du jour ». Un
    /// départ postérieur appartient à aujourd'hui ou plus tard.
    static func debutDuJour(le maintenant: Date = .now) -> String {
        let debut = Calendar.current.startOfDay(for: maintenant)
        return ISO8601DateFormatter().string(from: debut)
    }
}
