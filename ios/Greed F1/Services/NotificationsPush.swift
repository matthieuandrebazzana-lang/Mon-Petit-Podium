import SwiftUI
import UserNotifications

/// Notifications push — **seul propriétaire** du jeton APNs côté app (`docs/decisions.md` §25).
///
/// L'app ne programme **aucune** notification locale : le backend envoie tout par APNs
/// (ouverture des pronos, dernière chance, résultats). Elle ne fait que trois choses :
///
/// 1. **demander la permission** une fois connectée — iOS n'affiche la feuille qu'une
///    seule fois ; les appels suivants rendent la réponse déjà donnée, sans rien montrer ;
/// 2. **enregistrer le jeton** (`POST /push/token`) avec la langue de l'interface — c'est
///    elle qui choisit le texte des notifications. Changer de langue le réenregistre ;
/// 3. **le retirer** (`DELETE /push/token`) à la déconnexion et avant la suppression du
///    compte — tant que la session vit encore : la route exige un jeton valide.
///
/// Pas d'interrupteur dans l'app : on coupe les notifications depuis les Réglages d'iOS.
@MainActor
final class NotificationsPush: NSObject {

    static let partage = NotificationsPush()

    /// Dernier jeton reçu d'APNs. Gardé d'un lancement à l'autre pour pouvoir le retirer
    /// à la déconnexion même si iOS ne l'a pas encore redonné à ce lancement-ci.
    private static let cleJeton = "jetonAPNs"

    private var jeton: String? {
        get { UserDefaults.standard.string(forKey: Self.cleJeton) }
        set { UserDefaults.standard.set(newValue, forKey: Self.cleJeton) }
    }

    /// Faut-il envoyer le jeton au serveur ? Faux une fois déconnecté : un jeton qu'iOS
    /// redonnerait après la déconnexion ne doit pas se rattacher au compte quitté.
    private var actif = false

    /// Une fois connecté : permission, puis enregistrement auprès d'APNs. La réponse
    /// arrive dans ``recevoir(jeton:)`` via ``DelegueApplication``.
    func activer() async {
        actif = true
        let centre = UNUserNotificationCenter.current()
        centre.delegate = self
        let accordee = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard accordee else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Jeton reçu d'APNs — à chaque lancement : il peut changer (restauration, réinstallation).
    func recevoir(jeton donnees: Data) {
        jeton = donnees.map { String(format: "%02x", $0) }.joined()
        Task { await enregistrer() }
    }

    /// La langue a changé : le serveur doit écrire les prochaines notifications dans celle-ci.
    func langueChangee() {
        Task { await enregistrer() }
    }

    private func enregistrer() async {
        guard actif, let jeton else { return }
        // Sans conséquence visible s'il échoue : il sera renvoyé au prochain lancement.
        try? await APIClient.partage.envoyer(
            "push/token", methode: .post,
            corps: EnregistrementJeton(token: jeton, langue: langueInterface.rawValue))
    }

    /// À appeler **avant** `signOut()` : la route a besoin de la session. Ne lève pas — une
    /// déconnexion ne doit jamais échouer à cause des notifications. Un jeton resté en base
    /// change de propriétaire au prochain compte connecté sur cet iPhone.
    func retirer() async {
        actif = false
        guard let jeton else { return }
        try? await APIClient.partage.envoyer("push/token", methode: .delete,
                                             corps: RetraitJeton(token: jeton))
    }
}

// MARK: - Notification reçue app ouverte

extension NotificationsPush: UNUserNotificationCenterDelegate {
    /// Sans ce délégué, iOS tait une notification qui arrive pendant que l'app est au
    /// premier plan — la notification de test, typiquement.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

// MARK: - Délégué d'application

/// Le jeton APNs n'arrive que par `UIApplicationDelegate` — SwiftUI n'a pas d'équivalent.
/// Branché par `@UIApplicationDelegateAdaptor` dans ``GreedF1App``.
final class DelegueApplication: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in NotificationsPush.partage.recevoir(jeton: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulateur sans compte, entitlement absent : rien à montrer à l'utilisateur.
        print("⚠️ APNs : enregistrement impossible — \(error.localizedDescription)")
    }
}

// MARK: - Corps

/// Corps de `POST /push/token`.
private struct EnregistrementJeton: Encodable {
    let token: String
    let langue: String
}

/// Corps de `DELETE /push/token`.
private struct RetraitJeton: Encodable {
    let token: String
}
