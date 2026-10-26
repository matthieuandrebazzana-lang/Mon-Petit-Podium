import Foundation

/// « Le profil a déjà été ouvert », **un par compte**, dans `UserDefaults` — le seul
/// propriétaire de sa clé. Tant que ce n'est pas le cas, l'avatar de l'accueil pulse
/// (``AccueilView``) ; ``BarreNavigation`` le marque à la première arrivée sur l'onglet
/// Profil, qu'on y vienne par l'avatar ou par la barre.
///
/// > Un compte créé avant ce drapeau voit l'invitation une fois, jusqu'à sa prochaine
/// > ouverture du profil. C'est voulu.
enum DecouverteProfil {

    private static let prefixe = "accueil.profilDecouvert."

    private static func cle(_ utilisateur: UUID) -> String {
        prefixe + utilisateur.uuidString
    }

    /// Sans compte connu, rien à inviter : l'invitation ne pourrait pas s'éteindre.
    static func faite(pour utilisateur: UUID?) -> Bool {
        guard let utilisateur else { return true }
        return UserDefaults.standard.bool(forKey: cle(utilisateur))
    }

    static func marquer(pour utilisateur: UUID?) {
        guard let utilisateur else { return }
        UserDefaults.standard.set(true, forKey: cle(utilisateur))
    }

    /// Efface le drapeau de **tous** les comptes : appelé par `oublierCompte()`, où la
    /// session — donc l'identifiant — peut déjà avoir disparu.
    static func oublier() {
        let stockage = UserDefaults.standard
        for cle in stockage.dictionaryRepresentation().keys where cle.hasPrefix(prefixe) {
            stockage.removeObject(forKey: cle)
        }
    }
}
