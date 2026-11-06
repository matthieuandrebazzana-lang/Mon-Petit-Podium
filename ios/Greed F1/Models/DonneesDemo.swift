import Foundation

/// **Les données fictives du parcours guidé** (``ParcoursGuide``) : un championnat, ses
/// membres, un Grand Prix d'exemple et ses cotes — locales, jamais envoyées.
///
/// - **Un espace d'identifiants réservé** (`00000000-DE30-…`) : un service qui reçoit l'un
///   d'eux lit les fixtures au lieu du réseau (``ClassementChampionnat``,
///   ``DonneesPronostics``), et ``APIClient`` refuse toute route qui en contient un —
///   dernier filet, si un écran oubliait la règle.
/// - **Jamais dans un cache** : ni ``CacheService``, ni ``MesChampionnats``, ni l'App Group
///   des widgets. Rien de ce qui est ici ne survit au processus, sauf l'étape du parcours.
/// - **Des points, jamais une cote** : chaque issue porte directement son nombre de points,
///   comme `cotes.valeur` en base (`CLAUDE.md` §3.1).
enum DonneesDemo {

    // MARK: Identifiants

    private static let prefixe = "00000000-DE30-4000-8000-"

    private static func uuid(_ suffixe: Int) -> UUID {
        UUID(uuidString: prefixe + String(format: "%012d", suffixe))!
    }

    /// Le championnat d'un ami, rejoint avec ``codeExemple``.
    static let championnatId = uuid(1)
    /// Le championnat « créé » à l'étape 3 — il n'existe nulle part.
    static let championnatCreeId = uuid(2)
    /// Le Grand Prix d'exemple.
    static let grandPrixId = uuid(3)

    /// Le code à saisir pour rejoindre le championnat d'exemple.
    static let codeExemple = "DEMO26"

    /// Le Grand Prix d'exemple : Abu Dhabi, qui a son drapeau et son tracé.
    static let slug = "abu-dhabi"

    static func estDemo(_ id: UUID?) -> Bool {
        id?.uuidString.hasPrefix(prefixe) ?? false
    }

    /// Une route qui désigne un identifiant de démo — refusée par ``APIClient``.
    static func cheminDeDemo(_ chemin: String) -> Bool {
        chemin.uppercased().contains(prefixe)
    }

    // MARK: La mémoire du parcours

    /// Ce que le parcours a saisi : **en mémoire seulement**, perdu à la fermeture de l'app.
    /// La reprise reconstruit ce que son étape demande (``preparerReprise(_:)``).
    @MainActor static var favoris: [Favori] = []
    @MainActor static var miens: [PronosticEnBase] = []

    @MainActor static func oublier() {
        favoris = []
        miens = []
    }

    /// La reprise à une étape avancée retrouve ce que les étapes d'avant auraient posé :
    /// deux favoris pour la saisie, le vainqueur et le podium pour les bonus.
    @MainActor static func preparerReprise(_ etape: EtapeParcours) {
        oublier()
        if etape.rawValue > EtapeParcours.favoris.rawValue {
            let gp = cotes()
            favoris = [("top-6", 1), ("meilleur-tour", 0)].compactMap { slug, rang in
                guard let marche = gp.marche(slug), rang < marche.cotes.count else { return nil }
                let cote = marche.cotes[rang]
                return Favori(idOutcomeUnibet: cote.id, marche: marche.marche,
                              libelle: marche.libelle, pilote: cote.pilote, points: cote.points)
            }
        }
        if etape.rawValue > EtapeParcours.vainqueurPodium.rawValue {
            miens = [PronosticEnBase(type: "vainqueur", idOutcomeUnibet: "demo-v-2", podium: nil),
                     PronosticEnBase(type: "podium", idOutcomeUnibet: "demo-p-1",
                                     podium: ("demo-p-1", "demo-p-3"))]
        }
    }

    // MARK: Le Grand Prix

    /// Le Grand Prix tel que le parcours le traverse. Sous-titre : « Exemple ».
    static var grandPrix: GrandPrixPronos {
        GrandPrixPronos(id: grandPrixId, nom: "GP Abu Dhabi", slug: slug,
                        sousTitre: t("parcours.demo.sousTitreGP"))
    }

    /// **Toujours ouvert** : qualifications passées d'un jour, départ dans deux — recalculés
    /// à chaque lecture, pour que la saisie de démo marche même quand les vrais pronos sont
    /// fermés.
    static func cotes(le maintenant: Date = .now) -> CotesGrandPrix {
        let jour: TimeInterval = 86_400
        let horaires = HorairesGP(statut: "cotes_figees",
                                  dateCourse: maintenant.addingTimeInterval(2 * jour),
                                  dateQualifications: maintenant.addingTimeInterval(-jour))
        let marches = [
            MarcheCotes(marche: MarcheCotes.vainqueur, libelle: "Vainqueur", cotes: [
                Cote(pilote: "L.Norris", points: 28, id: "demo-v-1"),
                Cote(pilote: "M.Verstappen", points: 35, id: "demo-v-2"),
                Cote(pilote: "O.Piastri", points: 42, id: "demo-v-3"),
                Cote(pilote: "G.Russell", points: 60, id: "demo-v-4"),
                Cote(pilote: "C.Leclerc", points: 85, id: "demo-v-5"),
                Cote(pilote: "L.Hamilton", points: 120, id: "demo-v-6")
            ]),
            MarcheCotes(marche: MarcheCotes.podium, libelle: "Podium", cotes: [
                Cote(pilote: "L.Norris", points: 13, id: "demo-p-1"),
                Cote(pilote: "M.Verstappen", points: 14, id: "demo-p-2"),
                Cote(pilote: "O.Piastri", points: 16, id: "demo-p-3"),
                Cote(pilote: "G.Russell", points: 21, id: "demo-p-4"),
                Cote(pilote: "C.Leclerc", points: 26, id: "demo-p-5"),
                Cote(pilote: "L.Hamilton", points: 34, id: "demo-p-6")
            ]),
            MarcheCotes(marche: "top-6", libelle: "Top 6", cotes: [
                Cote(pilote: "AK.Antonelli", points: 15, id: "demo-t-1"),
                Cote(pilote: "F.Alonso", points: 38, id: "demo-t-2"),
                Cote(pilote: "C.Sainz Jr", points: 45, id: "demo-t-3"),
                Cote(pilote: "P.Gasly", points: 70, id: "demo-t-4")
            ]),
            MarcheCotes(marche: "meilleur-tour", libelle: "Tour le plus rapide", cotes: [
                Cote(pilote: "M.Verstappen", points: 30, id: "demo-m-1"),
                Cote(pilote: "L.Norris", points: 32, id: "demo-m-2"),
                Cote(pilote: "C.Leclerc", points: 55, id: "demo-m-3"),
                Cote(pilote: "G.Russell", points: 65, id: "demo-m-4")
            ]),
            MarcheCotes(marche: "face-a-face-hamilton-leclerc", libelle: "Face-à-face Hamilton / Leclerc",
                        cotes: [
                Cote(pilote: "L.Hamilton", points: 19, id: "demo-f-1"),
                Cote(pilote: "C.Leclerc", points: 18, id: "demo-f-2")
            ]),
            MarcheCotes(marche: "safety-car", libelle: "Safety car", cotes: [
                Cote(pilote: "Oui", points: 22, id: "demo-s-1"),
                Cote(pilote: "Non", points: 16, id: "demo-s-2")
            ])
        ]
        return CotesGrandPrix(id: grandPrixId, nom: "GP Abu Dhabi", horaires: horaires,
                              marches: OrdreMarches.trier(marches, slug: \.marche))
    }

    // MARK: Les championnats

    /// Le championnat d'un ami, rejoint à l'étape 6.
    static var championnat: Championnat {
        Championnat(id: championnatId, nom: t("parcours.demo.championnat"),
                    codeInvitation: codeExemple, nombreMembres: membresFictifs.count + 1,
                    estCreateur: false)
    }

    /// Le championnat « créé » à l'étape 3 — son code est tiré comme le serveur le tire.
    static func championnatCree(nom: String) -> Championnat {
        Championnat(id: championnatCreeId, nom: nom, codeInvitation: codeFictif(),
                    nombreMembres: 1, estCreateur: true)
    }

    /// Six caractères alphanumériques majuscules — la forme du générateur de la base
    /// (`docs/metier.md` §5), mais tirés ici : aucun n'est réservé, aucun n'est envoyé.
    static func codeFictif() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    // MARK: Le classement

    private struct MembreFictif {
        let pseudo: String
        let points: Int
        let reussis: Int
        let meilleur: Int?
        let couleur1: String
        let couleur2: String
        let numero: Int?
        let ecurie: String?
    }

    private static let membresFictifs: [MembreFictif] = [
        MembreFictif(pseudo: "Léa", points: 412, reussis: 19, meilleur: 95,
                     couleur1: "#FF8000", couleur2: "#1B1B1B", numero: 4, ecurie: "mclaren"),
        MembreFictif(pseudo: "Hugo", points: 356, reussis: 17, meilleur: 120,
                     couleur1: "#1E3A8A", couleur2: "#FFD700", numero: 33, ecurie: nil),
        MembreFictif(pseudo: "Sam", points: 298, reussis: 15, meilleur: 60,
                     couleur1: "#FF2800", couleur2: "#FFFFFF", numero: 16, ecurie: "ferrari"),
        MembreFictif(pseudo: "Inès", points: 187, reussis: 11, meilleur: 42,
                     couleur1: "#00D2BE", couleur2: "#1B1B1B", numero: 12, ecurie: nil),
        MembreFictif(pseudo: "Noah", points: 121, reussis: 8, meilleur: 35,
                     couleur1: "#2D826D", couleur2: "#CEDC00", numero: nil, ecurie: nil)
    ]

    /// Le classement d'exemple, **toi compris** — au troisième rang, avec ta vraie voiture
    /// (posée par ``Membre/avecVoiture(de:)``, comme pour un vrai classement).
    @MainActor static func classement() -> [Membre] {
        let moi = SupabaseManager.partage.idCompte ?? uuid(99)
        var lignes: [(UUID, String, Int, Int, Int?, String, String, Int?, String?)] =
            membresFictifs.enumerated().map { index, m in
                (uuid(10 + index), m.pseudo, m.points, m.reussis, m.meilleur,
                 m.couleur1, m.couleur2, m.numero, m.ecurie)
            }
        lignes.insert((moi, t("parcours.demo.toi"), 240, 13, 85, "#800111", "#FFFFFF", nil, nil), at: 3)
        lignes.sort { $0.2 > $1.2 }
        return lignes.enumerated().map { rang, l in
            Membre(profilId: l.0, pseudo: l.1, totalPoints: l.2, pronosticsReussis: l.3,
                   meilleureCote: l.4, rang: rang + 1, ordreInscription: rang + 1,
                   couleur1: l.5, couleur2: l.6, numero: l.7,
                   livreeMode: l.8 == nil ? .perso : .ecurie, livreeEcurie: l.8)
        }
    }
}

// MARK: - Constructions directes

extension CotesGrandPrix {
    /// La construction directe, pour la démo : le décodeur reste le seul chemin des
    /// données servies.
    init(id: UUID, nom: String, horaires: HorairesGP, marches: [MarcheCotes]) {
        self.id = id
        self.nom = nom
        self.horaires = horaires
        self.marches = marches
    }
}

extension Championnat {
    /// La construction directe, pour la démo.
    init(id: UUID, nom: String, codeInvitation: String, nombreMembres: Int, estCreateur: Bool) {
        self.id = id
        self.nom = nom
        self.codeInvitation = codeInvitation
        self.creePar = nil
        self.creeLe = .now
        self.nombreMembres = nombreMembres
        self.estCreateur = estCreateur
        self.photoUrl = nil
        self.prochainGp = nil
        self.position = nil
    }
}

extension PronosticEnBase {
    /// La construction directe, pour la démo.
    init(type: String, idOutcomeUnibet: String, podium: (String, String)?) {
        self.type = type
        self.idOutcomeUnibet = idOutcomeUnibet
        self.podium = podium
    }
}
