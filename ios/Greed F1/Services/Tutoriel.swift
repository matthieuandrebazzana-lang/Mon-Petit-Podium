import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Les bulles d'aide contextuelles — une par écran, chacune **une seule fois par compte**.
enum BulleAide: String, CaseIterable {
    /// « Fais tes paris » : l'étoile des favoris.
    case cotesEtoile
    /// Saisie des pronostics : obligatoires contre bonus.
    case pronosObligatoires
    /// Première arrivée dans un championnat : la vue Piste.
    case championnatPiste
    /// Profil : changer la livrée.
    case profilLivree
    /// Accueil sans championnat : créer ou rejoindre.
    case accueilSansChampionnat

    /// La clé du texte, traduite à l'affichage — jamais stockée traduite.
    var cleTexte: String { "tutoriel.bulle.\(rawValue)" }
}

/// Ce que l'accueil du tutoriel demande à l'onglet Accueil en se fermant.
enum ActionTutoriel: Hashable {
    case creer, rejoindre
}

/// **Le tutoriel — seul propriétaire de ce que l'utilisateur a déjà vu**, et de ce qui
/// est affiché maintenant : l'accueil de première connexion, ou une bulle d'aide.
///
/// - **« Déjà vu » vit dans `UserDefaults`, une clé par compte** (`tutoriel.accueil.<id>`,
///   `tutoriel.bulle.<bulle>.<id>`), comme ``DecouverteProfil``. `oublierCompte()` les
///   efface toutes : un compte qui se reconnecte revoit l'accueil et les bulles — voulu.
/// - **Jamais deux bulles à la fois, jamais une bulle pendant l'accueil.** Une demande qui
///   arrive alors est simplement ignorée : la bulle n'est pas marquée vue, elle reviendra
///   à la prochaine visite de son écran.
/// - **Une bulle ne bloque rien.** Elle ne capte aucun toucher ; le premier toucher de
///   l'écran, n'importe où — défilement compris —, la ferme et passe à ce qu'il visait
///   (``DetecteurToucher``).
/// - **Marquée vue dès qu'elle s'affiche**, de même que l'accueil : rien ne peut s'afficher
///   deux fois, et une app quittée au milieu ne rouvre pas sur le tutoriel.
@MainActor @Observable
final class Tutoriel {

    static let partage = Tutoriel()

    /// L'accueil de première connexion est à l'écran.
    private(set) var accueilOuvert = false

    /// La bulle affichée, s'il y en a une.
    private(set) var bulleActive: BulleAide?

    @ObservationIgnored private var detecteur: DetecteurToucher?

    private init() {}

    // MARK: Accueil

    /// À l'arrivée dans l'app connectée : l'accueil s'ouvre si ce compte ne l'a jamais vu.
    func ouvrirAccueilSiNeuf() {
        guard let compte = SupabaseManager.partage.idCompte,
              !UserDefaults.standard.bool(forKey: Self.cleAccueil(compte)) else { return }
        ouvrirAccueil()
    }

    /// « Revoir le tutoriel » des réglages — l'accueil seul, les bulles vues le restent.
    func ouvrirAccueil() {
        fermerBulle()
        if let compte = SupabaseManager.partage.idCompte {
            UserDefaults.standard.set(true, forKey: Self.cleAccueil(compte))
        }
        accueilOuvert = true
    }

    func fermerAccueil() {
        accueilOuvert = false
    }

    // MARK: Bulles

    /// Affiche `bulle` si elle n'a jamais été vue et que rien d'autre n'est à l'écran.
    func demander(_ bulle: BulleAide) {
        guard !accueilOuvert, bulleActive == nil,
              let compte = SupabaseManager.partage.idCompte else { return }
        let cle = Self.cleBulle(bulle, compte)
        guard !UserDefaults.standard.bool(forKey: cle) else { return }
        UserDefaults.standard.set(true, forKey: cle)
        withAnimation(Mouvement.entree(Mouvement.passageEcran)) { bulleActive = bulle }
        installerDetecteur()
        UIAccessibility.post(notification: .announcement, argument: t(bulle.cleTexte))
    }

    /// Ferme `bulle` si c'est elle qui est affichée — son écran est parti.
    func fermer(_ bulle: BulleAide) {
        guard bulleActive == bulle else { return }
        fermerBulle()
    }

    private func fermerBulle() {
        retirerDetecteur()
        guard bulleActive != nil else { return }
        withAnimation(Mouvement.entree(Mouvement.passageEcran)) { bulleActive = nil }
    }

    /// Le détecteur se pose sur la fenêtre le temps d'une bulle, et sur elle seule.
    private func installerDetecteur() {
        guard detecteur == nil,
              let fenetre = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) else { return }
        let nouveau = DetecteurToucher { [weak self] in
            Task { @MainActor in self?.fermerBulle() }
        }
        fenetre.addGestureRecognizer(nouveau)
        detecteur = nouveau
    }

    private func retirerDetecteur() {
        guard let detecteur else { return }
        detecteur.view?.removeGestureRecognizer(detecteur)
        self.detecteur = nil
    }

    // MARK: Stockage

    private static let prefixe = "tutoriel."

    private static func cleAccueil(_ compte: UUID) -> String {
        prefixe + "accueil." + compte.uuidString
    }

    private static func cleBulle(_ bulle: BulleAide, _ compte: UUID) -> String {
        prefixe + "bulle." + bulle.rawValue + "." + compte.uuidString
    }

    /// Efface l'état de **tous** les comptes : appelé par `oublierCompte()`, où la session
    /// — donc l'identifiant — peut déjà avoir disparu. Même règle que ``DecouverteProfil``.
    nonisolated static func oublier() {
        let stockage = UserDefaults.standard
        for cle in stockage.dictionaryRepresentation().keys where cle.hasPrefix(prefixe) {
            stockage.removeObject(forKey: cle)
        }
    }
}

// MARK: - Le toucher qui ferme une bulle

/// **Voit chaque toucher de la fenêtre sans jamais le prendre.** Il échoue dès le premier
/// contact — après avoir prévenu —, n'annule ni ne retarde rien, et cohabite avec tous les
/// autres gestes : le bouton touché se déclenche, le défilement défile.
final class DetecteurToucher: UIGestureRecognizer, UIGestureRecognizerDelegate {

    private let auToucher: () -> Void

    init(auToucher: @escaping () -> Void) {
        self.auToucher = auToucher
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        auToucher()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
