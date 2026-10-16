import WidgetKit
import Foundation

/// Ce que dit le widget « Mes pronos » d'un Grand Prix à un instant donné.
enum PhasePronos: Equatable {
    /// Le relevé des cotes n'a pas eu lieu : « Ouverture dans ».
    case avantOuverture
    /// Cotes arrêtées, départ à venir : « Fermeture dans ».
    case ouverts
    /// Départ passé, résultats pas encore servis.
    case fermes
    /// Le GP est `termine` : « Résultats disponibles » et les points.
    case resultats
}

/// Un instant de la timeline. `grandPrix == nil` : l'état vide, « Ouvre l'app… ».
struct EntreePronos: TimelineEntry {
    let date: Date
    let grandPrix: DonneesWidget.GrandPrixPronosWidget?
    /// Le statut à `date` — celui de la base, ou celui que la timeline **prévoit** au
    /// relevé des cotes (comme ``TimelineProchainGP``).
    let statut: String
    let langue: Langue?

    /// L'échéance à cet instant — ``EcheancePronostics``, le seul calcul d'échéance.
    var echeance: EcheancePronostics? {
        grandPrix.map {
            EcheancePronostics.pour(statut: statut, dateCourse: $0.dateCourse,
                                    dateQualifications: $0.dateQualifications, le: date)
        }
    }

    var phase: PhasePronos? {
        guard let grandPrix, let echeance else { return nil }
        if grandPrix.statut == "termine" { return .resultats }
        if echeance.ferme { return .fermes }
        return echeance.phase == .ouverture ? .avantOuverture : .ouverts
    }

    /// Le tap : la saisie ou le récapitulatif tant qu'il y a quelque chose à voir, les
    /// résultats après la course, l'accueil sinon.
    var url: URL {
        guard let grandPrix, let phase else { return DonneesWidget.urlAccueil }
        switch phase {
        case .resultats: return DonneesWidget.urlResultats(grandPrix.id)
        case .ouverts: return DonneesWidget.urlPronos(grandPrix.id)
        case .fermes:
            return grandPrix.aDesPronostics ? DonneesWidget.urlPronos(grandPrix.id) : DonneesWidget.urlAccueil
        case .avantOuverture: return DonneesWidget.urlAccueil
        }
    }

    static func vide(_ date: Date = .now, langue: Langue? = DonneesWidget.langue) -> EntreePronos {
        EntreePronos(date: date, grandPrix: nil, statut: "", langue: langue)
    }
}

/// Lit `GET /widget/pronos` avec le **jeton widget** du Keychain partagé (``JetonWidget``)
/// — **jamais la session Supabase** (`docs/decisions.md` §28, §30). Hors ligne ou jeton
/// expiré, la dernière réponse rangée dans l'App Group répond, sans date affichée.
struct FournisseurPronos: TimelineProvider {

    func placeholder(in context: Context) -> EntreePronos { TimelinePronos.exemple() }

    func getSnapshot(in context: Context, completion: @escaping (EntreePronos) -> Void) {
        let premiere = TimelinePronos.entrees(DonneesWidget.lirePronos(), langue: DonneesWidget.langue,
                                              le: .now).entrees.first ?? .vide()
        // La galerie n'a pas de données à attendre : l'exemple, si l'App Group est vide.
        completion(premiere.grandPrix == nil && context.isPreview ? TimelinePronos.exemple() : premiere)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreePronos>) -> Void) {
        Task {
            await Self.lirePronos()
            let maintenant = Date.now
            let (entrees, relecture) = TimelinePronos.entrees(
                DonneesWidget.lirePronos(), langue: DonneesWidget.langue, le: maintenant)
            completion(Timeline(entries: entrees.isEmpty ? [.vide(maintenant)] : entrees,
                                policy: .after(relecture)))
        }
    }

    /// `GET /widget/pronos`. **15 s au plus**, comme les deux autres widgets : un Railway
    /// endormi ne vaut pas d'attendre, l'App Group répond. Rien n'est rangé sans jeton,
    /// sur un refus, ou sur une réponse illisible.
    static func lirePronos() async {
        guard let jeton = JetonWidget.lire(), jeton.expireLe > .now else { return }
        var requete = URLRequest(url: SupabaseConfig.apiBaseURL.appendingPathComponent("widget/pronos"))
        requete.timeoutInterval = 15
        requete.setValue("Bearer \(jeton.jeton)", forHTTPHeaderField: "Authorization")
        requete.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: requete),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder.api.decode(DonneesWidget.PronosWidget.self, from: donnees)) != nil
        else { return }
        DonneesWidget.enregistrerPronos(donnees)
    }
}

/// Le calcul de la timeline — pur, sans réseau ni horloge.
///
/// **Elle change d'état d'elle-même** :
///
/// | Instant | Ce que dit le widget |
/// |---|---|
/// | avant qualifications + 2 h | « À faire » · « Ouverture dans » |
/// | qualifications + 2 h → départ | « À faire » ou « Pronos faits » · « Fermeture dans » |
/// | départ → résultats | « Fermés » |
/// | GP `termine`, départ + 36 h au plus | « Résultats disponibles » et les points |
/// | ensuite | le Grand Prix suivant |
///
/// Les 36 h sont celles de ``CadenceClassement/apresDepart`` : la fenêtre des résultats
/// est aussi celle des relectures au quart d'heure. Le passage à « Fermeture dans » est
/// une **prévision**, relue cinq minutes après ; un instant passé n'est jamais prévu.
/// Les jours sont des entrées, le reste une minuterie (``DecompteProchainGP``).
enum TimelinePronos {

    /// Une semaine d'entrées au plus : la relecture la plus lointaine tombe à 2 h.
    static let horizon: TimeInterval = 7 * 86_400

    /// Le Grand Prix à afficher à `instant` : le dernier couru tant que ses résultats sont
    /// frais et que le suivant n'est pas parti, sinon le prochain — ou, faute de prochain,
    /// le dernier couru.
    static func actif(_ contenu: DonneesWidget.PronosWidget, le instant: Date)
        -> DonneesWidget.GrandPrixPronosWidget? {
        if let dernier = contenu.dernier, let depart = dernier.dateCourse,
           instant < depart.addingTimeInterval(CadenceClassement.apresDepart),
           contenu.prochain?.dateCourse.map({ $0 > instant }) ?? true {
            return dernier
        }
        return contenu.prochain ?? contenu.dernier
    }

    /// Le relevé des cotes du prochain GP, s'il est encore à venir — la seule prévision.
    static func ouverturePrevue(_ gp: DonneesWidget.GrandPrixPronosWidget, apres maintenant: Date) -> Date? {
        guard gp.statut == "a_venir",
              let ouverture = gp.dateQualifications?.addingTimeInterval(EcheancePronostics.delaiOuverture),
              ouverture > maintenant
        else { return nil }
        return ouverture
    }

    static func entrees(_ contenu: DonneesWidget.PronosWidget?, langue: Langue?,
                        le maintenant: Date) -> (entrees: [EntreePronos], relecture: Date) {
        let departs = [contenu?.prochain, contenu?.dernier].compactMap { $0?.dateCourse }
        var relecture = CadenceClassement.prochaine(apres: maintenant, departs: departs)
        guard let contenu, contenu.prochain != nil || contenu.dernier != nil else {
            return ([.vide(maintenant, langue: langue)], relecture)
        }

        // Les instants où le widget change : maintenant, la fin des résultats frais, le
        // relevé prévu, le départ, et chaque jour entier avant l'échéance en cours.
        var instants: Set<Date> = [maintenant]
        if let depart = contenu.dernier?.dateCourse {
            instants.insert(depart.addingTimeInterval(CadenceClassement.apresDepart))
        }
        let ouverture = contenu.prochain.flatMap { ouverturePrevue($0, apres: maintenant) }
        if let ouverture { relecture = min(relecture, ouverture.addingTimeInterval(5 * 60)) }
        if let prochain = contenu.prochain {
            let echeances = [ouverture, prochain.dateCourse].compactMap { $0 }
            for echeance in echeances {
                instants.insert(echeance)
                var jour = echeance.addingTimeInterval(-86_400)
                while jour > maintenant {
                    instants.insert(jour)
                    jour.addTimeInterval(-86_400)
                }
            }
        }

        let fin = maintenant.addingTimeInterval(horizon)
        let entrees = instants.filter { $0 >= maintenant && $0 < fin }.sorted().map { instant in
            let gp = actif(contenu, le: instant)
            var statut = gp?.statut ?? ""
            if let gp, gp.id == contenu.prochain?.id, let ouverture, instant >= ouverture {
                statut = "cotes_figees"
            }
            return EntreePronos(date: instant, grandPrix: gp, statut: statut, langue: langue)
        }
        return (entrees, relecture)
    }

    // MARK: - Exemples

    /// La galerie et le `placeholder` — une grille plausible, jamais affichée comme une
    /// donnée réelle.
    static func exemple(_ phase: PhasePronos = .ouverts, avecPronos: Bool = true,
                        le maintenant: Date = .now) -> EntreePronos {
        let lignes: [DonneesWidget.PronosticWidget] = [
            .init(categorie: "obligatoire", type: "vainqueur", libelle: "Vainqueur", choix: "Lando Norris",
                  points: 28, pointsGagnes: phase == .resultats ? 28 : nil,
                  statut: phase == .resultats ? "gagne" : "en_attente"),
            .init(categorie: "obligatoire", type: "podium", libelle: "Podium", choix: "Oscar Piastri",
                  points: 14, pointsGagnes: phase == .resultats ? 0 : nil,
                  statut: phase == .resultats ? "perdu" : "en_attente"),
            .init(categorie: "obligatoire", type: "podium", libelle: "Podium", choix: "George Russell",
                  points: 19, pointsGagnes: phase == .resultats ? 19 : nil,
                  statut: phase == .resultats ? "gagne" : "en_attente"),
            .init(categorie: "bonus", type: "bonus", libelle: "Top 6", choix: "Lewis Hamilton",
                  points: 17, pointsGagnes: nil, statut: phase == .resultats ? "non_evaluable" : "en_attente"),
            .init(categorie: "bonus", type: "bonus", libelle: "Top 10", choix: "Isack Hadjar",
                  points: 31, pointsGagnes: phase == .resultats ? 31 : nil,
                  statut: phase == .resultats ? "gagne" : "en_attente")
        ]
        let (depart, statut): (Date, String) = switch phase {
        case .avantOuverture: (maintenant.addingTimeInterval(2 * 86_400 + 5 * 3600), "a_venir")
        case .ouverts: (maintenant.addingTimeInterval(86_400 + 7 * 3600), "cotes_figees")
        case .fermes: (maintenant.addingTimeInterval(-3600), "cotes_figees")
        case .resultats: (maintenant.addingTimeInterval(-5 * 3600), "termine")
        }
        let gp = DonneesWidget.GrandPrixPronosWidget(
            nom: "GP Etats Unis", dateCourse: depart,
            dateQualifications: depart.addingTimeInterval(-22 * 3600), statut: statut,
            pronostics: avecPronos ? lignes : [],
            pointsGagnes: phase == .resultats && avecPronos ? 78 : nil)
        return EntreePronos(date: maintenant, grandPrix: gp, statut: statut, langue: DonneesWidget.langue)
    }
}
