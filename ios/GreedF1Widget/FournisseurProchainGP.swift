import WidgetKit
import Foundation

/// Un instant de la timeline du widget : le Grand Prix affiché, le statut qu'il a **à cet
/// instant**, et la langue de l'app. `grandPrix == nil` : l'état neutre, rien à montrer.
struct EntreeProchainGP: TimelineEntry {
    let date: Date
    let grandPrix: DonneesWidget.GrandPrix?
    /// Le statut à `date` — celui de la base, ou celui que la timeline **prévoit** au
    /// relevé des cotes (voir ``TimelineProchainGP``).
    let statut: String
    let langue: Langue?

    /// L'échéance à cet instant — ``EcheancePronostics``, le seul calcul d'échéance de
    /// l'app. Le widget ne décide jamais lui-même de ce qu'il annonce.
    var echeance: EcheancePronostics? {
        grandPrix.map {
            EcheancePronostics.pour(statut: statut, dateCourse: $0.dateCourse,
                                    dateQualifications: $0.dateQualifications, le: date)
        }
    }

    static func neutre(_ date: Date = .now, langue: Langue? = nil) -> EntreeProchainGP {
        EntreeProchainGP(date: date, grandPrix: nil, statut: "", langue: langue)
    }
}

/// Lit l'App Group (``DonneesWidget``), puis `GET /calendrier` — **la route publique** :
/// le widget n'a jamais de session. Le réseau rafraîchit l'App Group ; s'il échoue, ce que
/// l'app ou le dernier relevé y ont laissé suffit.
struct FournisseurProchainGP: TimelineProvider {

    func placeholder(in context: Context) -> EntreeProchainGP {
        TimelineProchainGP.exemple
    }

    func getSnapshot(in context: Context, completion: @escaping (EntreeProchainGP) -> Void) {
        // La galerie n'a pas de données à attendre : l'exemple, si l'App Group est vide.
        let contenu = DonneesWidget.lire()
        let entrees = TimelineProchainGP.entrees(contenu.grandsPrix, langue: contenu.langue
            .flatMap(Langue.init(rawValue:)), le: .now).entrees
        let premiere = entrees.first ?? .neutre()
        completion(premiere.grandPrix == nil && context.isPreview ? TimelineProchainGP.exemple : premiere)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeProchainGP>) -> Void) {
        Task {
            if let lus = await Self.lireCalendrier() { DonneesWidget.fusionner(lus) }
            let contenu = DonneesWidget.lire()
            let maintenant = Date.now
            let (entrees, relecture) = TimelineProchainGP.entrees(
                contenu.grandsPrix, langue: contenu.langue.flatMap(Langue.init(rawValue:)),
                le: maintenant)
            completion(Timeline(entries: entrees.isEmpty ? [.neutre(maintenant)] : entrees,
                                policy: .after(relecture)))
        }
    }

    /// `GET /calendrier`, sans jeton. **15 s au plus** : le plan gratuit de Railway peut
    /// dormir, et un widget n'a pas le temps d'attendre son réveil — l'App Group répond.
    static func lireCalendrier() async -> [GrandPrixEnBase]? {
        var requete = URLRequest(url: SupabaseConfig.apiBaseURL.appendingPathComponent("calendrier"))
        requete.timeoutInterval = 15
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: requete),
              (reponse as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder.api.decode([GrandPrixEnBase].self, from: donnees)
    }
}

/// Le calcul de la timeline — pur, sans réseau ni horloge.
///
/// **Elle change d'état d'elle-même**, sans attendre un rechargement :
///
/// | Instant | Ce que dit le widget |
/// |---|---|
/// | avant qualifications + 2 h | « Ouverture dans » |
/// | qualifications + 2 h → départ | « Fermeture dans » |
/// | départ → départ + 2 h | « Pronostics · Fermés » |
/// | départ + 2 h | le Grand Prix suivant |
///
/// **Le passage à « Fermeture dans » est une prévision** : le relevé des cotes tombe
/// deux heures après les qualifications (``EcheancePronostics/delaiOuverture``), mais seule
/// la base le confirme. La timeline le prévoit pour l'avenir, et redemande `/calendrier`
/// cinq minutes après ; un relevé en retard redevient alors « Ouverture · À confirmer »,
/// la phrase de l'app. Un instant déjà passé n'est jamais prévu : il est lu.
///
/// **Les jours sont des entrées, le reste une minuterie.** `Text(timerInterval:)` défile
/// seul mais ne sait écrire que des heures : 62:14:32 pour deux jours et demi. Une entrée
/// par jour restant affiche « 2j » devant une minuterie de moins de 24 h, qui tombe à zéro
/// pile quand l'entrée suivante prend le relais.
enum TimelineProchainGP {

    /// Une course est passée deux heures après son départ — la durée maximale d'un Grand
    /// Prix au règlement. Le widget passe alors au suivant.
    static let dureeCourse: TimeInterval = 2 * 60 * 60

    /// Relecture de `/calendrier` au plus tard toutes les heures.
    static let relectureMax: TimeInterval = 60 * 60

    /// Le Grand Prix affiché et celui d'après : au-delà, la prochaine relecture aura lieu.
    static let grandsPrixMax = 2

    static func entrees(_ grandsPrix: [DonneesWidget.GrandPrix], langue: Langue?,
                        le maintenant: Date) -> (entrees: [EntreeProchainGP], relecture: Date) {
        let aVenir = grandsPrix
            .filter { gp in
                guard let depart = gp.dateCourse else { return gp.statut != "termine" }
                return depart.addingTimeInterval(dureeCourse) > maintenant
            }
            .sorted(by: DonneesWidget.ordre)
        let candidats = aVenir.prefix(grandsPrixMax)

        var entrees: [EntreeProchainGP] = []
        var relecture = maintenant.addingTimeInterval(relectureMax)
        var debut = maintenant

        for gp in candidats {
            let fin = gp.dateCourse?.addingTimeInterval(dureeCourse)

            // Le relevé des cotes, s'il est encore à venir — la seule prévision.
            let ouverturePrevue = gp.dateQualifications
                .map { $0.addingTimeInterval(EcheancePronostics.delaiOuverture) }
                .flatMap { gp.statut == "a_venir" && $0 > maintenant ? $0 : nil }
            if let ouverturePrevue {
                relecture = min(relecture, ouverturePrevue.addingTimeInterval(5 * 60))
            }
            func statut(le instant: Date) -> String {
                if let ouverturePrevue, instant >= ouverturePrevue { return "cotes_figees" }
                return gp.statut
            }

            // Les instants où le widget change : le début, l'ouverture, le départ, et
            // chaque jour entier avant l'échéance **de la phase en cours** — l'ouverture
            // jusqu'à elle, le départ ensuite.
            var instants: Set<Date> = [debut]
            if let ouverturePrevue { instants.insert(ouverturePrevue) }
            if let depart = gp.dateCourse { instants.insert(depart) }
            let ouverture = ouverturePrevue ?? gp.dateQualifications
                .map { $0.addingTimeInterval(EcheancePronostics.delaiOuverture) }
            let phases: [(echeance: Date?, depuis: Date)] = [
                (gp.statut == "a_venir" ? ouverture : nil, debut),
                (gp.dateCourse, gp.statut == "a_venir" ? max(debut, ouverture ?? debut) : debut)
            ]
            for phase in phases {
                guard let echeance = phase.echeance else { continue }
                var jour = echeance.addingTimeInterval(-86_400)
                while jour > phase.depuis {
                    instants.insert(jour)
                    jour.addTimeInterval(-86_400)
                }
            }

            for instant in instants.sorted() where instant >= debut && (fin.map { instant < $0 } ?? true) {
                entrees.append(EntreeProchainGP(date: instant, grandPrix: gp,
                                                statut: statut(le: instant), langue: langue))
            }

            guard let fin else { break }   // départ inconnu : rien ne vient après lui
            debut = fin
        }

        // Plus aucun Grand Prix connu après le dernier : l'état neutre, pas un GP couru.
        // S'il en reste au-delà des deux calculés, la relecture horaire les aura repris.
        if aVenir.count <= grandsPrixMax, let derniere = candidats.last, let depart = derniere.dateCourse {
            entrees.append(.neutre(depart.addingTimeInterval(dureeCourse), langue: langue))
        }
        return (entrees, relecture)
    }

    /// La galerie des widgets et le `placeholder` — un Grand Prix plausible, jamais affiché
    /// comme une donnée réelle.
    static var exemple: EntreeProchainGP {
        let maintenant = Date.now
        let gp = DonneesWidget.GrandPrix(
            id: UUID(), nom: "GP Etats Unis", slug: "etats-unis",
            dateCourse: maintenant.addingTimeInterval(2 * 86_400 + 5 * 3600),
            dateQualifications: maintenant.addingTimeInterval(86_400 + 3600),
            statut: "a_venir")
        return EntreeProchainGP(date: maintenant, grandPrix: gp, statut: gp.statut,
                                langue: DonneesWidget.langue)
    }
}

extension DonneesWidget.GrandPrix {
    /// Pour l'exemple de la galerie seulement — les vraies valeurs viennent de la base.
    init(id: UUID, nom: String, slug: String, dateCourse: Date?, dateQualifications: Date?,
         statut: String) {
        self.id = id
        self.nom = nom
        self.slug = slug
        self.dateCourse = dateCourse
        self.dateQualifications = dateQualifications
        self.statut = statut
    }
}
