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
    /// La clé du titre court, en tête de la bulle.
    var cleTitre: String { "tutoriel.bulle.\(rawValue).titre" }
}

/// Ce qu'une bulle désigne : le cadre de la vue **en coordonnées de l'écran**, et où la
/// bulle préfère se poser.
struct CibleBulle: Equatable {
    var cadre: CGRect
    var position: PositionBulle
    var pointe: CGFloat
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
/// - **Une bulle bloque l'écran jusqu'à « Compris ».** Elle vit dans sa propre fenêtre
///   (``FenetreBulle``), au-dessus de l'app **et de ses feuilles** : un voile couvre tout,
///   sauf une découpe autour de ce qu'elle désigne, et rien dessous ne reçoit de toucher
///   ni de focus VoiceOver.
/// - **Marquée vue au tap sur « Compris » seulement** (``compris()``). Une bulle fermée
///   autrement — son écran est parti, l'app a été quittée — reviendra à la prochaine
///   visite. L'accueil, lui, est marqué dès qu'il s'affiche.
@MainActor @Observable
final class Tutoriel {

    static let partage = Tutoriel()

    /// L'accueil de première connexion est à l'écran.
    private(set) var accueilOuvert = false

    /// La bulle affichée, s'il y en a une — jusqu'à la fin de sa sortie.
    private(set) var bulleActive: BulleAide?

    /// Ce que désigne ``bulleActive``.
    private(set) var cible: CibleBulle?

    /// Le voile et la bulle sont à l'écran. Basculé **après** la pose de la fenêtre, pour
    /// que l'entrée s'anime, et **avant** son retrait, pour que la sortie s'anime aussi.
    private(set) var calqueVisible = false

    @ObservationIgnored private var fenetre: UIWindow?

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
    func demander(_ bulle: BulleAide, cible: CibleBulle) {
        guard !accueilOuvert, bulleActive == nil,
              let compte = SupabaseManager.partage.idCompte,
              !UserDefaults.standard.bool(forKey: Self.cleBulle(bulle, compte)),
              let scene = Self.sceneActive else { return }
        bulleActive = bulle
        self.cible = cible
        let nouvelle = FenetreBulle(scene: scene)
        fenetre = nouvelle
        // Le tour suivant : la vue est montée invisible, son entrée peut s'animer.
        Task { @MainActor in
            guard self.fenetre === nouvelle else { return }
            withAnimation(Mouvement.entree(Mouvement.passageEcran)) { self.calqueVisible = true }
            // Le focus VoiceOver passe à la fenêtre modale : son premier élément, le titre.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    /// La vue désignée a bougé sous la bulle — rotation de contenu, chargement tardif.
    func deplacer(_ bulle: BulleAide, cadre: CGRect) {
        guard bulleActive == bulle, cible?.cadre != cadre else { return }
        cible?.cadre = cadre
    }

    /// « Compris » : la seule façon de marquer une bulle vue.
    func compris() {
        guard let bulle = bulleActive else { return }
        if let compte = SupabaseManager.partage.idCompte {
            UserDefaults.standard.set(true, forKey: Self.cleBulle(bulle, compte))
        }
        fermerBulle()
    }

    /// Ferme `bulle` si c'est elle qui est affichée — son écran est parti. **Sans la
    /// marquer** : elle reviendra.
    func fermer(_ bulle: BulleAide) {
        guard bulleActive == bulle else { return }
        fermerBulle()
    }

    private func fermerBulle() {
        guard let partante = fenetre else { return }
        withAnimation(Mouvement.entree(Mouvement.passageEcran)) {
            calqueVisible = false
        } completion: { [weak self] in
            partante.isHidden = true
            guard let self, self.fenetre === partante else { return }
            self.fenetre = nil
            self.bulleActive = nil
            self.cible = nil
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private static var sceneActive: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
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

/// > **Non monté depuis 0.58.1** — la bulle ne se ferme plus qu'à « Compris ». Conservé : il a
/// > fait ses preuves pour voir un toucher sans le prendre.
///
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
