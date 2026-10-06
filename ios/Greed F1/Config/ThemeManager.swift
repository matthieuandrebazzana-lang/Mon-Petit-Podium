import SwiftUI
import UIKit
import Observation

/// Les trois choix d'apparence de ``ReglagesView``.
enum Apparence: String, CaseIterable, Identifiable {
    case automatique, clair, sombre

    var id: String { rawValue }

    /// Clé de traduction du libellé — traduit à l'affichage, jamais stocké traduit.
    var cleLibelle: String { "reglages.apparence.\(rawValue)" }

    /// Ce que reçoivent les fenêtres. `.unspecified` rend la main au réglage du téléphone.
    fileprivate var style: UIUserInterfaceStyle {
        switch self {
        case .automatique: return .unspecified
        case .clair:       return .light
        case .sombre:      return .dark
        }
    }
}

/// Apparence de l'interface — **seul propriétaire** de la question, sur le modèle de
/// ``LanguageManager`` (`@Observable` et `ObservableObject`, injecté au niveau de l'app).
///
/// Par défaut l'app suit le téléphone. Un choix manuel est enregistré et l'emporte ensuite
/// à chaque lancement ; revenir à « Automatique » efface l'enregistrement.
///
/// > **Pourquoi `overrideUserInterfaceStyle` et pas `.preferredColorScheme`.** Une fois un
/// > mode forcé, `.preferredColorScheme(nil)` ne rend pas toujours la main au système :
/// > « Automatique » resterait bloqué sur le dernier mode forcé. L'override de fenêtre, lui,
/// > revient proprement par `.unspecified`, et il couvre aussi UIKit — alertes de
/// > suppression, barre d'onglets, feuilles, et la résolution des couleurs dynamiques de
/// > `Couleurs.swift`. `@Environment(\.colorScheme)` reste juste dans toutes les vues.
@Observable
final class ThemeManager: ObservableObject {

    static let shared = ThemeManager()

    private static let cleStockage = "apparenceInterface"

    private(set) var apparence: Apparence

    private init() {
        apparence = UserDefaults.standard.string(forKey: Self.cleStockage)
            .flatMap(Apparence.init(rawValue:)) ?? .automatique
    }

    /// Choix manuel — appliqué tout de suite, sans redémarrage.
    func choisir(_ nouvelle: Apparence) {
        guard nouvelle != apparence else { return }
        objectWillChange.send()
        apparence = nouvelle
        if nouvelle == .automatique {
            UserDefaults.standard.removeObject(forKey: Self.cleStockage)
        } else {
            UserDefaults.standard.set(nouvelle.rawValue, forKey: Self.cleStockage)
        }
        appliquer(anime: true)
    }

    /// Pose le style sur **toutes** les fenêtres de l'app. À rappeler au lancement : une
    /// fenêtre créée avant ne connaît pas le choix enregistré.
    ///
    /// Au lancement, sans animation. Sur un choix, en fondu croisé
    /// (``Mouvement/basculeApparence``) : sans lui, tout l'écran saute d'un coup du beige
    /// au presque noir.
    func appliquer(anime: Bool = false) {
        let style = apparence.style
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for fenetre in scene.windows where fenetre.overrideUserInterfaceStyle != style {
                guard anime else {
                    fenetre.overrideUserInterfaceStyle = style
                    continue
                }
                UIView.transition(with: fenetre,
                                  duration: Mouvement.basculeApparence,
                                  options: [.transitionCrossDissolve, .curveEaseOut,
                                            .allowUserInteraction]) {
                    fenetre.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}
