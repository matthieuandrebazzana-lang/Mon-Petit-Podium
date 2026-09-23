import Foundation

/// Un membre au classement d'un championnat, tel que le sert
/// `GET /championnats/{id}/classement` (`LigneClassement`, §3.3) — liste **déjà triée
/// et rangée** par le serveur. La vue piste reçoit le même tableau.
struct Membre: Codable, Identifiable, Equatable, Hashable {
    let profilId: UUID
    let pseudo: String
    /// **`0`, jamais `nil`**, quand rien n'est encore noté : « tout le monde à zéro ».
    let totalPoints: Int
    let pronosticsReussis: Int
    /// Le plus gros coup, en points. **`nil` tant qu'il n'a rien réussi** — `0` dirait
    /// que son meilleur coup vaut zéro.
    let meilleureCote: Int?
    /// 1 à N, **sans ex æquo**.
    let rang: Int
    /// Rang d'adhésion. C'est lui — jamais l'index dans le tableau — qui attribue une
    /// couleur ou un repère stable à un membre.
    let ordreInscription: Int
    let couleur1: String
    let couleur2: String
    /// `nil` = « pas de choix », l'encre se calcule contre l'aplat.
    let couleurTexte: String?
    /// `nil` = pas de numéro : la voiture affiche le rang.
    let numero: Int?
    let livreeMode: ModeLivree
    let livreeEcurie: String?
    let avatarUrl: URL?

    var id: UUID { profilId }

    enum CodingKeys: String, CodingKey {
        case pseudo, rang, couleur1, couleur2, numero
        case profilId = "profil_id"
        case totalPoints = "total_points"
        case pronosticsReussis = "pronostics_reussis"
        case meilleureCote = "meilleure_cote"
        case ordreInscription = "ordre_inscription"
        case couleurTexte = "couleur_texte"
        case livreeMode = "livree_mode"
        case livreeEcurie = "livree_ecurie"
        case avatarUrl = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profilId = try c.decode(UUID.self, forKey: .profilId)
        pseudo = try c.decode(String.self, forKey: .pseudo)
        totalPoints = try c.decode(Int.self, forKey: .totalPoints)
        pronosticsReussis = try c.decode(Int.self, forKey: .pronosticsReussis)
        meilleureCote = try c.decodeIfPresent(Int.self, forKey: .meilleureCote)
        rang = try c.decode(Int.self, forKey: .rang)
        ordreInscription = try c.decode(Int.self, forKey: .ordreInscription)
        couleur1 = try c.decodeIfPresent(String.self, forKey: .couleur1) ?? "#800111"
        couleur2 = try c.decodeIfPresent(String.self, forKey: .couleur2) ?? "#FFFFFF"
        couleurTexte = try c.decodeIfPresent(String.self, forKey: .couleurTexte)
        numero = try c.decodeIfPresent(Int.self, forKey: .numero)
        livreeMode = try c.decodeIfPresent(ModeLivree.self, forKey: .livreeMode) ?? .perso
        livreeEcurie = try c.decodeIfPresent(String.self, forKey: .livreeEcurie)
        avatarUrl = URL.facultative(try c.decodeIfPresent(String.self, forKey: .avatarUrl))
    }
}

extension Membre {
    /// La construction directe, pour les aperçus : le décodeur reste le seul chemin des
    /// données servies.
    init(profilId: UUID, pseudo: String, totalPoints: Int, pronosticsReussis: Int,
         meilleureCote: Int?, rang: Int, ordreInscription: Int,
         couleur1: String, couleur2: String, couleurTexte: String? = nil,
         numero: Int?, livreeMode: ModeLivree, livreeEcurie: String? = nil,
         avatarUrl: URL? = nil) {
        self.profilId = profilId
        self.pseudo = pseudo
        self.totalPoints = totalPoints
        self.pronosticsReussis = pronosticsReussis
        self.meilleureCote = meilleureCote
        self.rang = rang
        self.ordreInscription = ordreInscription
        self.couleur1 = couleur1
        self.couleur2 = couleur2
        self.couleurTexte = couleurTexte
        self.numero = numero
        self.livreeMode = livreeMode
        self.livreeEcurie = livreeEcurie
        self.avatarUrl = avatarUrl
    }

    /// La chaîne d'où se tire la teinte de l'avatar : l'UUID **en minuscules**, la forme
    /// que sert le backend — la même règle que ``Championnat/cleTeinte``.
    var cleTeinte: String { profilId.uuidString.lowercased() }
}
