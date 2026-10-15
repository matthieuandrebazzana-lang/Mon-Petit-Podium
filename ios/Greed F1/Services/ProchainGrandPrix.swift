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
/// qui choisit le bouton du widget — « Faire mes pronos » ou « Voir mes pronos ». **Une
/// seule requête** : les pronostics du joueur viennent en jointure PostgREST
/// (`pronostics(id)`, filtrés sur son identifiant, une ligne au plus), sous la même RLS
/// qu'avant — un joueur ne lit que les siens.
///
/// **Instantané sur disque** (``CacheService``) : possédé par ``BarreNavigation`` et chargé
/// dès le lancement, il naît avec le GP et le bouton du dernier passage, relus en
/// arrière-plan.
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

    private static let cle = "prochain-gp"

    /// Une ligne de la réponse : le GP, et ses pronostics **du joueur** (zéro ou un).
    private struct Ligne: Decodable {
        let gp: GrandPrixEnBase
        let aDesPronostics: Bool

        private struct Pronostic: Decodable { let id: UUID }
        private enum CodingKeys: String, CodingKey { case pronostics }

        init(from decoder: Decoder) throws {
            gp = try GrandPrixEnBase(from: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            aDesPronostics = !(try c.decode([Pronostic].self, forKey: .pronostics)).isEmpty
        }
    }

    private static func decoder(_ donnees: Data) throws -> Ligne? {
        try JSONDecoder.api.decode([Ligne].self, from: donnees).first
    }

    init() {
        if let ligne: Ligne? = CacheService.partage.valeur(Self.cle, snapshot: true,
                                                            decoder: Self.decoder) {
            montrer(ligne)
        }
    }

    func charger(forcer: Bool = false) async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }

        if case .pret = etat {} else { etat = .chargement }
        do {
            try await CacheService.partage.charger(
                Self.cle, snapshot: true, forcer: forcer, decoder: Self.decoder,
                afficher: { (ligne: Ligne?) in montrer(ligne) },
                lire: {
                    guard let moi = SupabaseManager.partage.idCompte else { throw ErreurAPI.session }
                    let reponse = try await SupabaseManager.partage.client
                        .from("grands_prix")
                        .select("id,nom,date_course,date_qualifications,statut,statut_resultats,pronostics(id)")
                        .or("statut.in.(a_venir,cotes_figees),date_course.gte.\(Self.debutDuJour())")
                        .eq("pronostics.profil_id", value: moi.uuidString.lowercased())
                        .order("date_course", ascending: true, nullsFirst: false)
                        .limit(1)
                        .limit(1, referencedTable: "pronostics")
                        .execute()
                    return reponse.data
                })
        } catch is CancellationError {
            // Écran quitté pendant l'appel : la prochaine apparition le relance.
        } catch {
            // Un GP affiché le reste : l'échec ne se dit que s'il n'y a rien.
            if case .pret = etat { return }
            etat = .echec(error is URLError ? .reseau : (error as? ErreurAPI ?? .serveur(statut: nil, message: nil)))
            aDesPronostics = nil
        }
    }

    /// Rappelé au retour du parcours de pronostics : une grille vient peut-être d'être
    /// envoyée. La même requête relit le GP et le bouton.
    func relirePronostics() async {
        await charger(forcer: true)
    }

    private func montrer(_ ligne: Ligne?) {
        if etat != .pret(ligne?.gp) { etat = .pret(ligne?.gp) }
        if aDesPronostics != ligne?.aDesPronostics { aDesPronostics = ligne?.aDesPronostics }
        // Le widget « Prochain GP » lit ce que l'accueil vient de lire
        // (``DonneesWidget``) — et ne se redessine que si cela a changé.
        if let gp = ligne?.gp { DonneesWidget.recharger(si: DonneesWidget.fusionner([gp])) }
    }

    /// Minuit ce matin, heure locale, en ISO 8601 UTC — la borne du « GP du jour ». Un
    /// départ postérieur appartient à aujourd'hui ou plus tard.
    static func debutDuJour(le maintenant: Date = .now) -> String {
        let debut = Calendar.current.startOfDay(for: maintenant)
        return ISO8601DateFormatter().string(from: debut)
    }
}
