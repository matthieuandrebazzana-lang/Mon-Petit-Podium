import Foundation

extension JSONDecoder {

    /// Le décodeur **unique** des réponses de Railway et des lectures directes Supabase.
    ///
    /// Les dates arrivent en ISO 8601 UTC, `+00:00` ou `Z`, **avec ou sans fraction de
    /// seconde** selon la source — Pydantic ou PostgREST (`docs/swift-app.md` §7.4).
    /// Les clés, elles, ne sont pas converties : chaque modèle déclare ses `CodingKeys`
    /// en `snake_case`, ce qui le rend lisible par n'importe quel décodeur.
    static let api: JSONDecoder = {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .custom { decoder in
            let conteneur = try decoder.singleValueContainer()
            let texte = try conteneur.decode(String.self)
            guard let date = DateISO.lire(texte) else {
                throw DecodingError.dataCorruptedError(
                    in: conteneur, debugDescription: "Date illisible : \(texte)")
            }
            return date
        }
        return decodeur
    }()
}

/// Lecture d'une date ISO 8601, sous ses deux formes. `ISO8601DateFormatter` est sûr
/// entre fils d'exécution : les deux lecteurs sont construits une fois pour toutes.
private enum DateISO {
    private static let avecFraction: ISO8601DateFormatter = {
        let lecteur = ISO8601DateFormatter()
        lecteur.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return lecteur
    }()

    private static let sansFraction: ISO8601DateFormatter = {
        let lecteur = ISO8601DateFormatter()
        lecteur.formatOptions = [.withInternetDateTime]
        return lecteur
    }()

    static func lire(_ texte: String) -> Date? {
        avecFraction.date(from: texte) ?? sansFraction.date(from: texte)
    }
}
