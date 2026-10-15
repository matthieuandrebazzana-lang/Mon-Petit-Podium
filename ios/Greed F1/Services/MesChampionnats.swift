import SwiftUI

/// Les championnats du compte connecté, servis par `GET /championnats/moi` (§3.3).
///
/// > **Un seul propriétaire.** L'accueil et l'onglet **Championnats** affichent la même
/// > liste : une instance, créée par ``BarreNavigation``, descend dans les deux. Deux
/// > appels écrits séparément auraient fini par ne plus dire la même chose — un
/// > championnat rejoint visible ici et pas là.
///
/// **Cache *stale-while-revalidate*, instantané sur disque** (``CacheService``,
/// `docs/swift-app.md` §7.6) : l'instance naît avec la liste connue — au lancement à froid,
/// celle du dernier passage —, relue en arrière-plan si elle a plus de 30 s. La silhouette
/// ne sert que sans aucune donnée, et l'échec ne remplace jamais une liste affichée.
@MainActor
final class MesChampionnats: ObservableObject {

    enum Etat: Equatable {
        case chargement
        case pret([Championnat])
        case echec(ErreurAPI)
    }

    @Published private(set) var etat: Etat = .chargement

    private static let cle = "championnats/moi"

    init() {
        if let liste: [Championnat] = CacheService.partage.valeur(Self.cle, snapshot: true) {
            etat = .pret(liste)
        }
    }

    /// Vrai pendant un appel : deux écrans qui apparaissent ensemble n'en lancent qu'un.
    private var enCours = false

    /// Une demande forcée arrivée pendant un appel : la liste en vol peut dater d'avant
    /// l'écriture, elle est donc redemandée une fois l'appel fini.
    private var aRelancer = false

    /// Le premier championnat de la liste, `nil` tant qu'elle n'est pas lue — celui dont
    /// « Mes Grands Prix » lit les paris (``GrandsPrixJoues``), sans rappeler la route.
    var premierId: UUID? {
        if case .pret(let liste) = etat { return liste.first?.id }
        return nil
    }

    /// - Parameter forcer: `true` après une écriture (création, adhésion) — périme le cache.
    ///   Sans lui, un
    ///   chargement déjà en vol — lancé **avant** l'écriture — absorberait la demande, et
    ///   le championnat obtenu manquerait à la liste jusqu'au prochain changement d'onglet.
    func charger(forcer: Bool = false) async {
        guard !enCours else {
            if forcer { aRelancer = true }
            return
        }
        enCours = true
        defer { enCours = false }

        var forcerLecture = forcer
        repeat {
            aRelancer = false
            await lire(forcer: forcerLecture)
            forcerLecture = true
        } while aRelancer
    }

    private func lire(forcer: Bool) async {
        if case .pret = etat {} else { etat = .chargement }
        do {
            try await CacheService.partage.charger(
                Self.cle, snapshot: true, forcer: forcer,
                afficher: { (liste: [Championnat]) in
                    if etat != .pret(liste) { etat = .pret(liste) }
                },
                lire: { try await APIClient.partage.lireJSON(Self.cle) })
        } catch is CancellationError {
            // Écran quitté pendant l'appel : rien à signaler. Un premier chargement
            // interrompu garde son spinner, et la prochaine apparition le relance.
        } catch {
            // Une liste affichée le reste : l'échec ne se dit que s'il n'y a rien.
            if case .pret = etat { return }
            etat = .echec(error as? ErreurAPI ?? .serveur(statut: nil, message: nil))
        }
    }
}

private struct CleChampionnatParDefaut: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// ``MesChampionnats/premierId``, posé par ``BarreNavigation`` : le championnat dont
    /// « Mes Grands Prix » et « Mes résultats » lisent les paris, sans rappeler
    /// `GET /championnats/moi`.
    var championnatParDefaut: UUID? {
        get { self[CleChampionnatParDefaut.self] }
        set { self[CleChampionnatParDefaut.self] = newValue }
    }
}
