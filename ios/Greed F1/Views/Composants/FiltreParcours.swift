import UIKit

/// **Le filtre de touchers du parcours guidé**, posé sur la fenêtre de l'app par
/// ``ParcoursGuide``.
///
/// Tant qu'il est actif, il laisse défiler l'écran et annule tout le reste :
///
/// - **un glissement passe** — le filtre échoue dès que le doigt a bougé de plus de
///   ``seuil``, et la vue défilante prend la main ;
/// - **un tap hors de la découpe est annulé** — le filtre se reconnaît au lever du doigt,
///   et `cancelsTouchesInView` retire le toucher aux vues dessous ;
/// - **un tap dans la découpe passe**, seulement si ``gesteAutorise`` : le filtre échoue
///   dès le premier contact.
///
/// > **Les gestes SwiftUI attendent son échec** (``gestureRecognizer(_:shouldBeRequiredToFailBy:)``) :
/// > sans cela, le tap d'un bouton se reconnaîtrait au même lever de doigt que le filtre,
/// > et l'ordre entre les deux ne serait pas garanti. Les glissements des vues défilantes
/// > n'attendent pas : ils le font échouer en démarrant. Vérifié au simulateur sous
/// > iOS 26.5 : bouton, `NavigationLink`, `onTapGesture`, `Toggle` et champ texte.
final class FiltreParcours: UIGestureRecognizer, UIGestureRecognizerDelegate {

    /// Le cadre de la découpe, en coordonnées de la fenêtre. `nil` : aucune découpe.
    var decoupe: CGRect?
    /// Un tap dans la découpe atteint la vue — étapes « geste ».
    var gesteAutorise = false
    /// Le filtre ne fait rien — aucune étape à l'écran.
    var actif = false {
        didSet { isEnabled = actif }
    }

    /// Le mouvement au-delà duquel un toucher devient un défilement.
    private static let seuil: CGFloat = 10

    private var depart: CGPoint?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
        isEnabled = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Un second doigt : ni pincement ni rotation ne déclenchent quoi que ce soit, et
        // le premier doigt reste suivi — son lever annule encore ce qu'il touchait.
        guard depart == nil else { return }
        guard let toucher = touches.first else { return }
        let point = toucher.location(in: view)
        if gesteAutorise, let decoupe, decoupe.contains(point) {
            state = .failed
            return
        }
        depart = point
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let depart, let toucher = touches.first else { return }
        let point = toucher.location(in: view)
        if hypot(point.x - depart.x, point.y - depart.y) > Self.seuil { state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible else { return }
        state = depart == nil ? .failed : .recognized
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        depart = nil
    }

    // MARK: Délégué

    /// Tout geste qui n'est pas un défilement attend que le filtre ait échoué — un appui
    /// long compris : il ne se déclenche donc jamais hors de la découpe.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        !Self.estDefilement(other)
    }

    /// Un défilement démarre en même temps : c'est lui qui fait échouer le filtre.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        Self.estDefilement(other)
    }

    private static func estDefilement(_ geste: UIGestureRecognizer) -> Bool {
        geste.view is UIScrollView && geste is UIPanGestureRecognizer
    }
}

// MARK: - Le toucher qui ferme une bulle

/// > **Non monté depuis 0.58.1** — la bulle ne se ferme plus qu'à « Compris ». Conservé : il a
/// > fait ses preuves pour voir un toucher sans le prendre, et ``FiltreParcours`` en est
/// > parti.
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
