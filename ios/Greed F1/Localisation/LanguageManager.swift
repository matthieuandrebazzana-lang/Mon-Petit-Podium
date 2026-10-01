import SwiftUI
import Observation

/// Les deux langues de l'interface. Les données de l'API (marchés Unibet, pilotes, GP,
/// écuries) ne se traduisent pas : seule l'interface passe par ``t(_:)``.
enum Langue: String, CaseIterable, Identifiable {
    case fr, en

    var id: String { rawValue }

    /// Libellé du sélecteur — « FR », « EN ».
    var code: String { rawValue.uppercased() }

    /// Drapeau du sélecteur, en **emoji natif** — aucun asset : le système le dessine.
    var drapeau: String {
        switch self {
        case .fr: return "🇫🇷"
        case .en: return "🇬🇧"
        }
    }

    /// Locale des dates, des jours et des mois : **celle de la langue choisie**, jamais celle
    /// du téléphone. Un iPhone réglé en anglais qui a choisi le français lit « 15 mars ».
    var locale: Locale {
        switch self {
        case .fr: return Locale(identifier: "fr_FR")
        case .en: return Locale(identifier: "en_GB")
        }
    }

    fileprivate var table: [String: String] {
        switch self {
        case .fr: return TraductionsFR.table
        case .en: return TraductionsEN.table
        }
    }
}

/// Langue active de l'interface — **seul propriétaire** de la question.
///
/// > **Pourquoi `@Observable` ET `ObservableObject`.** L'objet est injecté au niveau de
/// > l'app comme `environmentObject` (le sélecteur le lit ainsi), mais c'est l'Observation
/// > qui fait tout le travail : ``t(_:)`` lit ``langue`` pendant l'évaluation d'un `body`,
/// > et SwiftUI inscrit cette lecture comme une dépendance de la vue, **même à travers une
/// > fonction globale et un singleton**. Changer de langue réévalue donc exactement les
/// > vues qui affichent du texte, sans `.id()` qui reconstruirait l'arbre — l'onglet, la
/// > pile de navigation et les données chargées restent en place.
///
/// Premier lancement : français si la première langue du téléphone est le français,
/// anglais pour toute autre. **Cette détection n'est jamais enregistrée** — seul un choix
/// manuel l'est, et il l'emporte ensuite à chaque lancement.
@Observable
final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    private static let cleStockage = "langueInterface"

    private(set) var langue: Langue

    private init() {
        if let enregistree = UserDefaults.standard.string(forKey: Self.cleStockage),
           let langue = Langue(rawValue: enregistree) {
            self.langue = langue
        } else {
            self.langue = Self.langueDuTelephone
        }
    }

    /// Choix manuel : il écrase la détection et survit aux lancements.
    func choisir(_ nouvelle: Langue) {
        guard nouvelle != langue else { return }
        objectWillChange.send()
        langue = nouvelle
        UserDefaults.standard.set(nouvelle.rawValue, forKey: Self.cleStockage)
    }

    var locale: Locale { langue.locale }

    private static var langueDuTelephone: Langue {
        let premiere = Locale.preferredLanguages.first ?? ""
        return Locale(identifier: premiere).language.languageCode?.identifier == "fr" ? .fr : .en
    }

    /// Le texte d'une clé dans la langue active. Une clé absente d'une langue retombe sur
    /// l'autre, puis sur la clé elle-même — visible à l'écran, donc impossible à rater.
    fileprivate func texte(_ cle: String) -> String {
        if let valeur = langue.table[cle] { return valeur }
        #if DEBUG
        print("⚠️ Traduction manquante [\(langue.code)] : \(cle)")
        #endif
        let autre: Langue = langue == .fr ? .en : .fr
        return autre.table[cle] ?? cle
    }

    /// Règle de pluriel de la langue active. **Elles diffèrent sur zéro** : « 0 réussi »
    /// en français (0 et 1 sont au singulier), « 0 correct picks » en anglais.
    fileprivate func estSingulier(_ nombre: Int) -> Bool {
        switch langue {
        case .fr: return abs(nombre) < 2
        case .en: return abs(nombre) == 1
        }
    }
}

// MARK: - Accès

/// Le texte d'une clé dans la langue active.
///
/// Appelé dans un `body`, il y inscrit la langue comme dépendance : la vue se redessine
/// d'elle-même au changement de langue.
func t(_ cle: String) -> String {
    LanguageManager.shared.texte(cle)
}

/// Le texte d'une clé, avec ses valeurs (`%@`, `%d`, `%1$@`…), mises en forme dans la
/// locale de la langue active.
func t(_ cle: String, _ valeurs: CVarArg...) -> String {
    let gestionnaire = LanguageManager.shared
    return String(format: gestionnaire.texte(cle), locale: gestionnaire.locale, arguments: valeurs)
}

/// Pluriel — lit `cle.un` ou `cle.plusieurs` selon la règle de la langue active, et y
/// place le nombre (`%d`), puis les valeurs suivantes.
func tp(_ cle: String, _ nombre: Int, _ valeurs: CVarArg...) -> String {
    let gestionnaire = LanguageManager.shared
    let forme = gestionnaire.estSingulier(nombre) ? "\(cle).un" : "\(cle).plusieurs"
    return String(format: gestionnaire.texte(forme), locale: gestionnaire.locale,
                  arguments: [nombre as CVarArg] + valeurs)
}

/// Locale de la langue active — pour toute date, tout jour, tout mois, tout nombre affiché.
var localeInterface: Locale { LanguageManager.shared.locale }

/// Langue active, pour les rares écrans dont la **mise en forme** change d'une langue à
/// l'autre au-delà du texte (ordre jour/mois).
var langueInterface: Langue { LanguageManager.shared.langue }

/// Rang ordinal dans la langue active — « 1er », « 2e » ; « 1st », « 2nd », « 3rd », « 11th ».
func ordinal(_ rang: Int) -> String {
    switch LanguageManager.shared.langue {
    case .fr:
        return rang == 1 ? "1er" : "\(rang)e"
    case .en:
        let suffixe: String
        switch (rang % 10, rang % 100) {
        case (_, 11...13): suffixe = "th"
        case (1, _): suffixe = "st"
        case (2, _): suffixe = "nd"
        case (3, _): suffixe = "rd"
        default: suffixe = "th"
        }
        return "\(rang)\(suffixe)"
    }
}

/// Heure de départ dans l'écriture de la langue active — « 07h00 » en français, l'écriture
/// du projet ; « 07:00 » en anglais.
func heureInterface(_ date: Date) -> String {
    let formateur = DateFormatter()
    formateur.locale = localeInterface
    formateur.dateFormat = langueInterface == .fr ? "HH'h'mm" : "HH:mm"
    return formateur.string(from: date)
}
