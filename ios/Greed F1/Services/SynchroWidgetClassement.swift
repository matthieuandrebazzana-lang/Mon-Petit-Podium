import Foundation

/// Ce que l'app fait pour le widget « Classement » — **l'app seule**, jamais le widget
/// (`docs/decisions.md` §28).
///
/// - **Une fois par lancement**, puis à un retour au premier plan après plus de 24 h, un
///   jeton widget neuf (`POST /widget/token`, authentifié par la session Supabase) rangé
///   dans le Keychain partagé (``JetonWidget``). Le widget, lui, ne voit jamais la session
///   et ne la rafraîchit jamais.
/// - **À chaque liste lue ou pile réordonnée**, les championnats du compte (id, nom) et
///   celui du premier plan dans l'App Group (``DonneesWidget``), puis un rechargement.
/// - **À la déconnexion et à la suppression du compte**, tout est effacé : jeton, liste,
///   relevés, avatars.
enum SynchroWidgetClassement {

    /// Un seul appel à la fois : l'ouverture et le retour au premier plan arrivent ensemble.
    @MainActor private static var enCours = false

    /// Dernier jeton obtenu par ce lancement — en mémoire seulement : un lancement à froid
    /// en redemande toujours un.
    @MainActor private static var obtenuLe: Date?

    /// Délai au-delà duquel un retour au premier plan redemande un jeton.
    private static let validiteLancement: TimeInterval = 24 * 3600

    /// Demande un jeton neuf et le range, sauf si ce lancement en a obtenu un il y a moins
    /// de 24 h. Un échec garde l'ancien — il vaut 30 jours, et le widget affiche ses
    /// dernières données s'il expire — et laisse le prochain passage en actif réessayer.
    @MainActor
    static func renouvelerJeton() async {
        guard !enCours else { return }
        if let obtenuLe, Date.now.timeIntervalSince(obtenuLe) < validiteLancement { return }
        enCours = true
        defer { enCours = false }
        do {
            let contenu: JetonWidget.Contenu = try await APIClient.partage.requete(
                "widget/token", methode: .post, perime: false)
            let avant = JetonWidget.lire()
            JetonWidget.enregistrer(contenu)
            obtenuLe = .now
            // Un widget resté sans jeton (première ouverture, retour après expiration)
            // n'attend pas sa prochaine échéance pour se remplir.
            if avant == nil || avant?.profilId != contenu.profilId
                || (avant?.expireLe ?? .distantPast) < .now {
                DonneesWidget.rechargerClassement()
                DonneesWidget.rechargerPronos()
            }
        } catch {
            // `503` sans `WIDGET_TOKEN_SECRET` sur Railway, réseau absent : rien à dire à
            // l'écran, le widget garde ce qu'il a.
        }
    }

    /// La liste du compte et la carte du dessus de la pile d'accueil.
    static func publier(_ championnats: [Championnat], profilId: UUID?) {
        let ordre = OrdrePile.rapprocher(OrdrePile.lire(pour: profilId), de: championnats)
        let change = DonneesWidget.publier(
            championnats: championnats.map { .init(id: $0.id, nom: $0.nom) },
            premierPlan: ordre.first, profilId: profilId)
        DonneesWidget.rechargerClassement(si: change)
    }

    /// La pile vient d'être réordonnée.
    static func premierPlan(_ id: UUID?) {
        DonneesWidget.rechargerClassement(si: DonneesWidget.enregistrer(premierPlan: id))
    }

    /// Déconnexion, suppression du compte, session perdue. Le compte suivant redemande
    /// son jeton dès sa connexion.
    @MainActor
    static func effacer() {
        obtenuLe = nil
        JetonWidget.effacer()
        DonneesWidget.effacerClassement()
        DonneesWidget.rechargerClassement()
        // Le widget « Mes pronos » partage le jeton : ses données partent avec lui.
        DonneesWidget.effacerPronos()
        DonneesWidget.rechargerPronos()
    }
}
