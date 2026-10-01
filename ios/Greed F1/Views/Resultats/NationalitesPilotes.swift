import SwiftUI

/// La nationalité d'un pilote de la grille 2026, en code ISO 3166-1 alpha-2.
///
/// **C'est la transcription de `frontend/src/lib/nationalites.js`**, pilote pour pilote,
/// exactement comme ``LivreeEcurie`` est celle de `lib/livrees.js`. Les deux tables
/// décrivent les mêmes vingt-trois pilotes et doivent dire la même chose : toute
/// correction ici se relit là-bas, et réciproquement.
///
/// **Pourquoi cette table existe.** Rien de ce que le serveur envoie ne dit de quel pays
/// est un pilote — le classement porte un numéro de voiture, un nom complet et une écurie.
/// `country_code` de `/drivers` d'OpenF1 est déprécié et disparaît fin 2026
/// (`docs/scraper.md` §9) : la nationalité ne peut venir que d'une table statique.
///
/// **Aucun dessin n'entre ici.** Les seize drapeaux sont des assets
/// (`drapeau-<code minuscule>`), écrits par `ios/scripts/extraire-drapeaux-pilotes.sh`
/// depuis la bibliothèque qu'importe déjà la version web — jamais redessinés, jamais
/// approximés.
///
/// **À mettre à jour à chaque saison**, comme la grille de ``LivreeEcurie``. Une table
/// périmée ne fait aucun dégât silencieux : le garde-fou de ``nationalite(numero:nom:)``
/// laisse la ligne sans drapeau, ce qui se voit, plutôt que de prêter la nationalité d'un
/// pilote à son successeur.
enum NationalitesPilotes {

    /// Saison décrite par la table — la même mention que la version web, et pour la même
    /// raison : lire « 2026 » en 2027 dit immédiatement ce qu'il y a à faire.
    static let saison = 2026

    /// La nationalité d'un pilote : le code ISO et le **libellé français affiché**.
    ///
    /// Le drapeau n'est qu'une texture ; c'est le mot qui porte le sens, et c'est lui que
    /// lit un lecteur d'écran.
    struct Nationalite: Equatable {
        let code: String
        let pays: String

        /// L'asset du drapeau — `drapeau-gb`, `drapeau-nl`… Le catalogue les porte tous
        /// les seize ; un code absent de la table n'arrive jamais jusqu'ici.
        var asset: String { "drapeau-\(code.lowercased())" }

        /// Le pays dans la langue de l'interface, tiré du code ISO — ``pays``, écrit en
        /// français, n'est que le repli.
        var paysAffiche: String {
            localeInterface.localizedString(forRegionCode: code.uppercased()) ?? pays
        }
    }

    /// Les vingt-trois pilotes que la saison 2026 a fait courir.
    ///
    /// `nom` est écrit **dans la forme d'OpenF1** (`full_name`, « Lando Norris ») : c'est
    /// elle que le classement sert, et c'est sur son dernier mot que porte le garde-fou.
    /// `unibet` reprend le libellé des cotes, pour que la même question posée depuis un
    /// widget de pari trouve la même réponse.
    private struct Pilote {
        let numero: Int
        let nom: String
        let unibet: String
        var alias: [String] = []
        let code: String
        let pays: String
    }

    private static let pilotes: [Pilote] = [
        Pilote(numero: 1,  nom: "Lando Norris",      unibet: "L.Norris",     code: "GB", pays: "Royaume-Uni"),
        Pilote(numero: 3,  nom: "Max Verstappen",    unibet: "M.Verstappen", code: "NL", pays: "Pays-Bas"),
        Pilote(numero: 5,  nom: "Gabriel Bortoleto", unibet: "G.Bortoleto",  code: "BR", pays: "Brésil"),
        Pilote(numero: 6,  nom: "Isack Hadjar",      unibet: "I.Hadjar",     code: "FR", pays: "France"),
        Pilote(numero: 10, nom: "Pierre Gasly",      unibet: "P.Gasly",      code: "FR", pays: "France"),
        Pilote(numero: 11, nom: "Sergio Perez",      unibet: "S.Perez",      code: "MX", pays: "Mexique"),
        // Les deux libellés d'Antonelli sont ceux que la version web liste en alias :
        // OpenF1 abrège « Andrea Kimi » en « Kimi », Unibet garde les deux initiales.
        Pilote(numero: 12, nom: "Kimi Antonelli",    unibet: "AK.Antonelli",
               alias: ["A.Antonelli", "Andrea Kimi Antonelli"],              code: "IT", pays: "Italie"),
        Pilote(numero: 14, nom: "Fernando Alonso",   unibet: "F.Alonso",     code: "ES", pays: "Espagne"),
        Pilote(numero: 16, nom: "Charles Leclerc",   unibet: "C.Leclerc",    code: "MC", pays: "Monaco"),
        Pilote(numero: 18, nom: "Lance Stroll",      unibet: "L.Stroll",     code: "CA", pays: "Canada"),
        Pilote(numero: 22, nom: "Yuki Tsunoda",      unibet: "Y.Tsunoda",    code: "JP", pays: "Japon"),
        Pilote(numero: 23, nom: "Alexander Albon",   unibet: "A.Albon",      code: "TH", pays: "Thaïlande"),
        Pilote(numero: 27, nom: "Nico Hulkenberg",   unibet: "N.Hulkenberg", code: "DE", pays: "Allemagne"),
        Pilote(numero: 30, nom: "Liam Lawson",       unibet: "L.Lawson",     code: "NZ", pays: "Nouvelle-Zélande"),
        Pilote(numero: 31, nom: "Esteban Ocon",      unibet: "E.Ocon",       code: "FR", pays: "France"),
        Pilote(numero: 41, nom: "Arvid Lindblad",    unibet: "A.Lindblad",   code: "GB", pays: "Royaume-Uni"),
        Pilote(numero: 43, nom: "Franco Colapinto",  unibet: "F.Colapinto",  code: "AR", pays: "Argentine"),
        Pilote(numero: 44, nom: "Lewis Hamilton",    unibet: "L.Hamilton",   code: "GB", pays: "Royaume-Uni"),
        // Unibet suffixe « Jr », OpenF1 non — le même écart que traite la version web.
        Pilote(numero: 55, nom: "Carlos Sainz",      unibet: "C.Sainz Jr",
               alias: ["Carlos Sainz Jr"],                                   code: "ES", pays: "Espagne"),
        Pilote(numero: 63, nom: "George Russell",    unibet: "G.Russell",    code: "GB", pays: "Royaume-Uni"),
        Pilote(numero: 77, nom: "Valtteri Bottas",   unibet: "V.Bottas",     code: "FI", pays: "Finlande"),
        Pilote(numero: 81, nom: "Oscar Piastri",     unibet: "O.Piastri",    code: "AU", pays: "Australie"),
        Pilote(numero: 87, nom: "Oliver Bearman",    unibet: "O.Bearman",    code: "GB", pays: "Royaume-Uni")
    ]

    // MARK: - Index

    private static let parNumero: [Int: Pilote] =
        Dictionary(uniqueKeysWithValues: pilotes.map { ($0.numero, $0) })

    /// Index { libellé normalisé → pilote }, pour les appelants qui n'ont qu'un nom.
    ///
    /// **Une clé revendiquée par deux pilotes est retirée plutôt qu'attribuée au premier
    /// venu.** Le cas n'existe pas dans la grille 2026 ; il existera le jour où deux frères
    /// courront ensemble, et mieux vaut alors ne poser aucun drapeau que le mauvais.
    private static let parLibelle: [String: Pilote] = {
        var vus: [String: Pilote] = [:]
        var ambigus: Set<String> = []

        for pilote in pilotes {
            let libelles = [pilote.nom, pilote.unibet] + pilote.alias + [nomDeFamille(pilote.nom)]
            for libelle in libelles {
                let k = cle(libelle)
                guard !k.isEmpty else { continue }
                if let vu = vus[k], vu.numero != pilote.numero { ambigus.insert(k) }
                else { vus[k] = pilote }
            }
        }

        for k in ambigus { vus.removeValue(forKey: k) }
        return vus
    }()

    // MARK: - Lecture

    /// La nationalité d'un pilote, ou `nil`.
    ///
    /// **Le numéro ET le nom de famille doivent concorder**, et c'est tout le garde-fou.
    /// Les numéros sont réattribués d'une saison à l'autre : si le 12 n'est plus Antonelli,
    /// une table périmée ne collera pas le drapeau italien sur son successeur, elle ne
    /// rendra rien. **Une ligne sans drapeau se voit ; une ligne sous le mauvais drapeau ne
    /// se voit pas.**
    ///
    /// Le nom seul reste accepté quand le numéro manque ou n'est pas dans la table — c'est
    /// le cas d'un pilote remplaçant, où le nom est la seule chose qu'on ait.
    static func nationalite(numero: Int?, nom: String) -> Nationalite? {
        if let numero, let parNumero = parNumero[numero] {
            let recu = nomDeFamille(nom)
            // Pas de nom fourni : le numéro suffit, l'appelant n'a rien à confronter.
            guard !recu.isEmpty else { return Nationalite(code: parNumero.code, pays: parNumero.pays) }
            // Un nom fourni qui ne concorde pas : la table est périmée, on se tait.
            guard recu == nomDeFamille(parNumero.nom) else { return nil }
            return Nationalite(code: parNumero.code, pays: parNumero.pays)
        }

        guard let parNom = parLibelle[cle(nom)] else { return nil }
        return Nationalite(code: parNom.code, pays: parNom.pays)
    }

    // MARK: - Normalisation

    /// Minuscules, accents ôtés, ponctuation fondue en espace.
    private static func cle(_ texte: String) -> String {
        let sansAccent = texte.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        let fondu = sansAccent
            .lowercased()
            .map { ".-".contains($0) ? " " : $0 }
        return String(fondu)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Le dernier mot d'un nom complet — « Lando Norris » → « norris ».
    private static func nomDeFamille(_ nom: String) -> String {
        cle(nom).split(separator: " ").last.map(String.init) ?? ""
    }
}
