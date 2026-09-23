import Foundation

/// Un échec d'appel à Railway, rangé par **genre** — le pendant de `lib/erreurs.js`.
///
/// Le genre voyage avec l'erreur plutôt que d'être deviné d'après le texte : un écran
/// décide du geste à proposer (réessayer, se reconnecter, sortir) sur le genre, jamais
/// sur une chaîne déjà traduite. Source : `docs/swift-app.md` §3.0 et §7.2.
enum ErreurAPI: Error, Equatable {

    /// `502`, `503`, `504`, délai dépassé, pas de connexion. **Ce n'est pas une panne** :
    /// c'est Railway qui se réveille, et réessayer marche.
    case reseau

    /// `401` — la session est réellement perdue (`supabase-swift` rafraîchit le jeton
    /// tout seul). ``APIClient`` a déjà purgé la session locale.
    case session

    /// `404` — ce qui est demandé n'existe pas. Réessayer rejouerait le même refus.
    case donnees(message: String?)

    /// Tout le reste. `message` est le `detail` français du backend quand il est
    /// affichable, `nil` sinon (liste Pydantic, message technique, corps illisible).
    case serveur(statut: Int?, message: String?)

    /// Le message à afficher, toujours non vide, toujours en français.
    ///
    /// Le genre l'emporte sur le texte reçu pour le réseau et la session : le serveur
    /// n'y dit rien d'utile. Pour le reste, son `detail` est plus précis que le générique
    /// (« Tu ne fais pas partie de ce championnat. ») et il est conservé.
    var message: String {
        switch self {
        case .reseau:
            return "Connexion au serveur en cours… Réessaie dans quelques secondes."
        case .session:
            return "Session expirée. Reconnecte-toi."
        case .donnees(let message):
            return message ?? "Ce contenu n'existe pas ou n'est plus accessible."
        case .serveur(_, let message):
            return message ?? "Une erreur est survenue. Réessaie."
        }
    }

    /// Faux quand réessayer ne réparera rien : une session morte rejouerait le même
    /// jeton en boucle, une donnée absente ne réapparaîtra pas parce qu'on redemande.
    var estRejouable: Bool {
        switch self {
        case .session, .donnees: return false
        case .reseau, .serveur:  return true
        }
    }

    /// Classe une réponse HTTP qui n'est pas un succès.
    static func depuis(statut: Int, corps: Data) -> ErreurAPI {
        switch statut {
        case 401:           return .session
        case 502, 503, 504: return .reseau
        case 404:           return .donnees(message: detailAffichable(corps))
        default:            return .serveur(statut: statut, message: detailAffichable(corps))
        }
    }

    // MARK: - Le corps d'erreur

    /// Les deux formes de `detail` que rend FastAPI (§3.0).
    private enum DetailErreur: Decodable {
        /// Nos propres refus : une chaîne française, affichable telle quelle.
        case message(String)
        /// Validation Pydantic : une liste d'objets en anglais, **jamais affichée**.
        case validation

        init(from decoder: Decoder) throws {
            let conteneur = try decoder.singleValueContainer()
            if let texte = try? conteneur.decode(String.self) {
                self = .message(texte)
            } else {
                self = .validation
            }
        }
    }

    private struct CorpsErreur: Decodable {
        let detail: DetailErreur
    }

    /// Signatures franches d'un message qui ne vient PAS de nos routes : page d'erreur
    /// Railway, proxy, ancienne version encore déployée. On ne tente pas de répondre à
    /// « est-ce du français ? », question qu'aucune heuristique ne sait trancher.
    ///
    /// Transcription de `SIGNATURE_TECHNIQUE` (`frontend/src/lib/api.js`), à un écart
    /// près : `Error:` et `relation "` sont sortis du `\b…\b`, où une ponctuation finale
    /// les empêchait de jamais correspondre.
    private static let signatureTechnique = #"\b(?:code\s+[0-9A-Z]{5}|statut\s+\d{3}|Traceback|Exception|does not exist|permission denied|null value|Internal Server Error|Bad Gateway|Application failed)\b|Error:|relation ""#

    private static func detailAffichable(_ corps: Data) -> String? {
        guard let lu = try? JSONDecoder().decode(CorpsErreur.self, from: corps),
              case .message(let texte) = lu.detail
        else { return nil }

        let nettoye = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nettoye.isEmpty,
              nettoye.range(of: signatureTechnique,
                            options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        return nettoye
    }
}
