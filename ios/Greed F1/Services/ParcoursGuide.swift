import SwiftUI
import UIKit

/// Les seize étapes du parcours guidé, dans l'ordre.
enum EtapeParcours: Int, CaseIterable {
    case bienvenue = 1
    case carteCreer
    case nomChampionnat
    case codeInvitation
    case carteRejoindre
    case codeExemple
    case classement
    case piste
    case inviter
    case voiture
    case marches
    case favoris
    case vainqueurPodium
    case bonus
    case valider
    case fin

    static let total = allCases.count

    /// Le nom de l'étape dans ses clés de traduction (`parcours.<nom>.titre` / `.texte`).
    var nom: String { String(describing: self) }

    /// L'étape attend un geste sur ce qu'elle désigne, pas « Compris ».
    var attendGeste: Bool {
        switch self {
        case .bienvenue, .codeInvitation, .classement, .voiture, .fin: return false
        default: return true
        }
    }

    /// La vue désignée reçoit ses touchers — les étapes « geste », et la voiture, qui se
    /// règle dans sa découpe.
    var cibleInteractive: Bool { attendGeste || self == .voiture }

    /// L'étape désigne une vue — sinon la bulle est centrée, sans découpe.
    var aUneCible: Bool { self != .bienvenue }

    /// L'onglet où l'étape se joue.
    var onglet: BarreNavigation.Onglet { self == .voiture ? .profil : .accueil }

    /// Les écrans de démo que l'onglet Accueil doit montrer à cette étape — **la pile se
    /// déduit de l'étape**, elle n'est jamais poussée ailleurs.
    var pileAccueil: [EtapePronos] {
        switch self {
        case .nomChampionnat, .codeInvitation: return [.demo(.creer)]
        case .codeExemple:                     return [.demo(.rejoindre)]
        case .classement, .piste, .inviter:    return [.demo(.championnat)]
        case .marches, .favoris:               return [.cotes(DonneesDemo.grandPrix)]
        case .vainqueurPodium, .bonus, .valider:
            return [.cotes(DonneesDemo.grandPrix), .pronos(DonneesDemo.grandPrix)]
        default:                               return []
        }
    }

    /// Où reprendre : le code inventé à l'étape 4 n'a pas survécu à la fermeture, on
    /// recrée donc le championnat.
    var reprise: EtapeParcours { self == .codeInvitation ? .nomChampionnat : self }
}

/// Les écrans de démo poussés par le parcours sur la pile de l'accueil.
enum EcranDemo: Hashable {
    case creer, rejoindre, championnat
}

/// **Le parcours guidé — seul propriétaire de l'étape en cours, de ce que le compte a déjà
/// fait, et de ce qui est à l'écran** : la bulle, son voile, sa découpe, et le filtre de
/// touchers (``FiltreParcours``).
///
/// - **Une clé par compte** dans `UserDefaults` : `parcours.etape.<id>` (la dernière étape
///   atteinte) et `parcours.termine.<id>`. `oublierCompte()` les efface.
/// - **Terminé au seul « Compris » de la dernière étape.** « Quitter » et « Plus tard »
///   ferment le parcours sans rien marquer : chaque lancement à froid propose alors de
///   reprendre (``propositionVisible``), tant qu'il n'est pas terminé.
/// - **Les écrans désignés se signalent eux-mêmes** (``View/etapeParcours(_:position:pointe:action:)``)
///   et annoncent leur geste par ``signaler(_:)`` — ignoré si ce n'est pas l'étape en cours.
@MainActor @Observable
final class ParcoursGuide {

    static let partage = ParcoursGuide()

    /// Le parcours est à l'écran.
    private(set) var actif = false

    /// La proposition de reprise est à l'écran.
    private(set) var propositionVisible = false

    private(set) var etape: EtapeParcours = .bienvenue

    /// Le geste de l'étape est fait, et elle attend maintenant « Compris » — la vue Piste
    /// après le tap sur « Piste », la voiture après un enregistrement ou dix secondes.
    private(set) var comprisDisponible = false

    /// Une feuille ou un menu de l'écran est ouvert par-dessus : la bulle et le voile
    /// s'effacent, et la feuille reçoit ses touchers.
    private(set) var suspendu = false

    /// Ce que l'étape désigne, en coordonnées de l'écran.
    private(set) var cible: CibleBulle?

    /// Le cadre de la bulle, en coordonnées de l'écran — la seule zone de sa fenêtre qui
    /// prenne les touchers.
    @ObservationIgnored var cadreBulle: CGRect = .zero

    /// Le voile et la bulle sont à l'écran. Basculé **après** la pose de la fenêtre, pour
    /// que l'entrée s'anime, et **avant** son retrait, pour que la sortie s'anime aussi.
    private(set) var calqueVisible = false

    /// Ce qui est à l'écran, pour la barre : parcours ou proposition. La permission des
    /// notifications attend que ce soit faux.
    var occupe: Bool { actif || propositionVisible }

    @ObservationIgnored private var fenetre: FenetreBulle?
    @ObservationIgnored private let filtre = FiltreParcours()
    @ObservationIgnored private var actionAccessible: (() -> Void)?
    @ObservationIgnored private var minuterie: Task<Void, Never>?
    /// Le lancement à froid a déjà été traité — la proposition ne revient qu'au suivant.
    @ObservationIgnored private var lancementTraite = false

    /// Le temps après lequel l'étape « voiture » accepte « Compris » sans changement.
    private static let delaiVoiture: Duration = .seconds(10)

    private init() {}

    // MARK: Lancement, reprise, sortie

    /// À l'arrivée dans l'app connectée, **une fois par lancement** : un compte qui n'a
    /// jamais commencé démarre ; un parcours interrompu propose de reprendre.
    func traiterLancement() {
        guard !lancementTraite, let compte = SupabaseManager.partage.idCompte else { return }
        lancementTraite = true
        let stockage = UserDefaults.standard
        guard !stockage.bool(forKey: Self.cleTermine(compte)) else { return }
        if stockage.object(forKey: Self.cleEtape(compte)) == nil {
            commencer(depuis: .bienvenue)
        } else {
            propositionVisible = true
            poserFenetre()
        }
    }

    /// « Reprendre » de la proposition.
    func reprendre() {
        propositionVisible = false
        commencer(depuis: etapeEnregistree.reprise)
    }

    /// « Plus tard » : la proposition reviendra au prochain lancement à froid.
    func plusTard() {
        propositionVisible = false
        retirerFenetre()
    }

    /// « Quitter » : le parcours se ferme, **sans être marqué terminé**. L'étape reste.
    func quitter() {
        actif = false
        comprisDisponible = false
        suspendu = false
        cible = nil
        minuterie?.cancel()
        DonneesDemo.oublier()
        retirerFenetre()
    }

    /// « Revoir le tutoriel » des réglages — depuis le début.
    func relancer() {
        guard let compte = SupabaseManager.partage.idCompte else { return }
        UserDefaults.standard.removeObject(forKey: Self.cleTermine(compte))
        propositionVisible = false
        commencer(depuis: .bienvenue)
    }

    private func commencer(depuis depart: EtapeParcours) {
        DonneesDemo.preparerReprise(depart)
        actif = true
        aller(a: depart)
        poserFenetre()
    }

    // MARK: Avancer

    /// « Compris » est proposé : étape sans geste, ou geste fait pour les deux étapes qui
    /// finissent sur « Compris » (la vue Piste, la voiture).
    var comprisPossible: Bool {
        switch etape {
        case .piste, .voiture: return comprisDisponible
        default:               return !etape.attendGeste
        }
    }

    /// « Compris ».
    func compris() {
        guard actif, comprisPossible else { return }
        avancer()
    }

    private func avancer() {
        guard let suivante = EtapeParcours(rawValue: etape.rawValue + 1) else {
            terminer()
            return
        }
        aller(a: suivante)
    }

    /// Un écran annonce que le geste de `etape` est fait. Ignoré hors de cette étape.
    func signaler(_ geste: EtapeParcours) {
        guard actif, geste == etape else { return }
        switch etape {
        case .piste, .voiture:
            withAnimation(Mouvement.entree(Mouvement.passageEcran)) { comprisDisponible = true }
            synchroniserFiltre()
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        default:
            if etape.attendGeste { avancer() }
        }
    }

    /// Le geste de l'étape, fait pour qui ne peut pas le faire — VoiceOver.
    func faireGeste() {
        actionAccessible?()
    }

    private func aller(a nouvelle: EtapeParcours) {
        minuterie?.cancel()
        withAnimation(Mouvement.entree(Mouvement.passageEcran)) {
            etape = nouvelle
            comprisDisponible = false
            cible = nil
        }
        actionAccessible = nil
        if let compte = SupabaseManager.partage.idCompte {
            UserDefaults.standard.set(nouvelle.rawValue, forKey: Self.cleEtape(compte))
        }
        if nouvelle == .voiture {
            minuterie = Task { [weak self] in
                try? await Task.sleep(for: Self.delaiVoiture)
                guard !Task.isCancelled else { return }
                self?.signaler(.voiture)
            }
        }
        synchroniserFiltre()
        // Le focus VoiceOver passe à la bulle de la nouvelle étape.
        Task { @MainActor in
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private func terminer() {
        if let compte = SupabaseManager.partage.idCompte {
            UserDefaults.standard.set(true, forKey: Self.cleTermine(compte))
        }
        quitter()
    }

    // MARK: Les vues désignées

    /// Une vue désignée par `etape` a mesuré son cadre — à chaque image d'un défilement.
    func cibler(_ etape: EtapeParcours, cible nouvelle: CibleBulle, action: (() -> Void)?) {
        guard actif, etape == self.etape else { return }
        actionAccessible = action
        if cible != nouvelle { cible = nouvelle }
        // La découpe du filtre est celle que l'on voit : le jour du voile compris.
        filtre.decoupe = nouvelle.cadre.insetBy(dx: -8, dy: -8)
    }

    /// La vue désignée a quitté l'écran.
    func perdre(_ etape: EtapeParcours) {
        guard etape == self.etape, cible != nil else { return }
        cible = nil
        filtre.decoupe = nil
    }

    /// Une feuille ou un menu s'ouvre par-dessus l'écran de l'étape, ou se ferme.
    func suspendre(_ oui: Bool) {
        guard actif, suspendu != oui else { return }
        withAnimation(Mouvement.entree(Mouvement.passageEcran)) { suspendu = oui }
        fenetre?.modale = !oui
        synchroniserFiltre()
    }

    private func synchroniserFiltre() {
        filtre.gesteAutorise = actif && etape.cibleInteractive
            && !(etape == .piste && comprisDisponible)
        if !actif { filtre.decoupe = nil }
        // Une feuille ou un menu ouvert reçoit ses touchers : ils ne mènent qu'à lui.
        filtre.actif = occupe && !suspendu
    }

    // MARK: La fenêtre

    private func poserFenetre() {
        synchroniserFiltre()
        guard fenetre == nil, let scene = Self.sceneActive else { return }
        let nouvelle = FenetreBulle(scene: scene)
        fenetre = nouvelle
        if let principale = nouvelle.principale, filtre.view !== principale {
            filtre.view?.removeGestureRecognizer(filtre)
            principale.addGestureRecognizer(filtre)
        }
        // Le tour suivant : la vue est montée invisible, son entrée peut s'animer.
        Task { @MainActor in
            guard self.fenetre === nouvelle else { return }
            withAnimation(Mouvement.entree(Mouvement.passageEcran)) { self.calqueVisible = true }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private func retirerFenetre() {
        synchroniserFiltre()
        guard let partante = fenetre else { return }
        // Oubliée tout de suite : une relance pendant la sortie pose une fenêtre neuve.
        fenetre = nil
        withAnimation(Mouvement.entree(Mouvement.passageEcran)) {
            calqueVisible = false
        } completion: {
            partante.isHidden = true
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private static var sceneActive: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    // MARK: Stockage

    /// La dernière étape atteinte par ce compte — la première s'il n'a jamais commencé.
    var etapeEnregistree: EtapeParcours {
        guard let compte = SupabaseManager.partage.idCompte else { return .bienvenue }
        return EtapeParcours(rawValue: UserDefaults.standard.integer(forKey: Self.cleEtape(compte)))
            ?? .bienvenue
    }

    private static let prefixe = "parcours."

    private static func cleEtape(_ compte: UUID) -> String {
        prefixe + "etape." + compte.uuidString
    }

    private static func cleTermine(_ compte: UUID) -> String {
        prefixe + "termine." + compte.uuidString
    }

    /// À la sortie du compte (`oublierCompte()`) : le parcours se ferme, et le prochain
    /// compte connecté sera traité à son arrivée.
    ///
    /// > **La progression, elle, reste** — elle est rangée par compte, et un compte qui se
    /// > reconnecte ne doit pas revoir un parcours qu'il a fini (« une fois par compte »).
    /// > Seules partent les clés `tutoriel.*` de l'ancien tutoriel, qui ne servent plus.
    nonisolated static func oublier() {
        let stockage = UserDefaults.standard
        for cle in stockage.dictionaryRepresentation().keys where cle.hasPrefix("tutoriel.") {
            stockage.removeObject(forKey: cle)
        }
        Task { @MainActor in
            partage.propositionVisible = false
            partage.quitter()
            partage.lancementTraite = false
        }
    }
}
