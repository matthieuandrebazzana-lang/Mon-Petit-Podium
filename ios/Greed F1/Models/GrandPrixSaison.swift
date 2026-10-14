import SwiftUI

// Sortis de `CalendrierView.swift` : la cible du widget (`GreedF1Widget/`) les compile
// aussi, et elle ne peut pas emporter l'écran du calendrier avec eux.

/// Les quatre états d'un Grand Prix, et ce que chacun dit.
///
/// **Le mot, la couleur et l'action ne se décident pas dans la vue** : ils vivent ici, un
/// seul propriétaire, comme `ETATS_GP` côté web. Deux écrans devront dire le même mot avec
/// la même couleur — le calendrier de la saison et celui d'un championnat — et il n'y a
/// qu'un endroit à corriger.
///
/// `ferme` n'apparaît sur aucune des trois captures, mais il existe dès que l'heure de
/// départ est passée sans que les résultats soient tombés : l'omettre laisserait un trou
/// d'une heure et demie par week-end.
enum EtatGp {
    case termine
    case ferme
    case ouvert
    case aVenir

    var libelle: String {
        switch self {
        case .termine: return t("etat.termine")
        case .ferme: return t("etat.ferme")
        case .ouvert: return t("etat.ouvert")
        case .aVenir: return t("etat.aVenir")
        }
    }

    /// Fond de la pastille. Blanc partout sauf sur « Pronos ouverts » — voir
    /// ``CarteGrandPrixSaison/pastilleEtat``. **Les mêmes dans les deux modes** : la
    /// pastille est posée sur le drapeau, qui ne change pas d'apparence (jetons `…Fixe`).
    var fondPastille: Color {
        self == .ouvert ? .accent : .surfaceFixe
    }

    /// Encre de la pastille, mesurée sur son fond : vert sauge **4,86:1**, rouge de la
    /// marque **10,88:1**, texte sur ambre **7,86:1**, marron **10,55:1**.
    var encrePastille: Color {
        switch self {
        case .termine: return .vertSauge
        case .ferme: return .primaireFixe
        case .ouvert: return .encreSurClair
        case .aVenir: return .secondaireFixe
        }
    }

    /// Le libellé de la bande, ou `nil` s'il n'y a rien à faire.
    ///
    /// **Seul « Terminé » en porte une tant que le parcours de pronostics est mocké.** La
    /// bande « Pronostiquer » de la version web mène au tableau des cotes réel, qui n'est
    /// branché qu'à l'étape 7 ; la poser ici promettrait un tableau que rien ne remplit.
    var action: String? {
        self == .termine ? t("etat.voirResultats") : nil
    }
}

extension EtatGp {

    /// L'état d'un Grand Prix de la saison — `etatDuGpSaison` du web.
    ///
    /// **Absent de la base ⇒ « À venir », toujours** : on ne sait ni si ses cotes existent,
    /// ni à quelle heure il part. L'ordre des tests compte — une course courue est terminée
    /// quoi qu'il arrive, et une fermeture passée l'emporte sur des cotes encore affichées.
    /// La fermeture est `date_course`, sans marge ; un départ inconnu n'est jamais passé.
    ///
    /// **« Pronos ouverts » = ``EcheancePronostics/cotesArretees(statut:dateCourse:le:)``**,
    /// la condition du widget et du décompte — pas la seule présence de cotes. Des cotes
    /// relevées en cours de semaine sur un GP encore `a_venir` ne l'ouvrent pas : c'est
    /// l'écart assumé avec `etatDuGpSaison` du web, qui les comptait.
    static func pour(_ enBase: GrandPrixEnBase?, le maintenant: Date = .now) -> EtatGp {
        guard let enBase else { return .aVenir }
        if enBase.statut == "termine" { return .termine }
        if let depart = enBase.dateCourse, depart <= maintenant { return .ferme }
        if EcheancePronostics.cotesArretees(statut: enBase.statut, dateCourse: enBase.dateCourse,
                                            le: maintenant) { return .ouvert }
        return .aVenir
    }
}

/// Un Grand Prix de la saison : la part **statique** — pays, circuit, date écrite — et ce
/// que la base en sait, quand elle a répondu.
///
/// Le jour et le mois sont des **chaînes**, pas une `Date` : voir l'en-tête de
/// ``CalendrierView``.
struct GrandPrixSaison {
    let slug: String
    let jour: String
    let mois: String
    /// La date complète, **écrite** — l'en-tête de ``ResultatsGPView`` la porte telle
    /// quelle. Elle n'est pas recomposée depuis ``jour`` et ``mois`` : la même règle que
    /// ces deux-là, et pour la même raison. Voir l'en-tête de ``CalendrierView``.
    let date: String
    /// La ligne de `grands_prix` qui lui répond, `nil` si la base ne la connaît pas.
    var enBase: GrandPrixEnBase? = nil
    /// Faux tant que la base n'a pas répondu : l'état est alors **inconnu**.
    var etatConnu = false

    /// **L'identifiant réel** — `nil` pour tout Grand Prix que le scraper n'a pas encore
    /// rencontré. C'est lui que demanderont les résultats et les pronostics.
    var gpId: UUID? { enBase?.id }

    /// L'état de la carte, `nil` s'il est inconnu.
    ///
    /// **Absent de la base et jour de course passé ⇒ « Terminé »**, d'après la date écrite
    /// (``GPRestants/estTermine(_:le:)``, la même règle que le décompte). Sans ce repli, les
    /// Grands Prix courus avant l'ouverture de l'app — que le scraper n'a jamais rencontrés —
    /// seraient « À venir », et le premier d'entre eux, l'Australie, passerait pour le prochain.
    var etat: EtatGp? {
        guard etatConnu else { return nil }
        if enBase == nil, GPRestants.estTermine(self) { return .termine }
        return EtatGp.pour(enBase)
    }

    /// Pays, nom et circuit **dans la langue de l'interface**, relus à chaque affichage —
    /// clés `gp.<slug>.*` de `Localisation/`. Rien n'est stocké : un texte stocké ne suivrait
    /// pas un changement de langue.
    ///
    /// **`pays` n'est pas `nom` moins « GP ».** Las Vegas se court aux États-Unis, et le
    /// drapeau de sa carte est celui des États-Unis : les deux clés répondent à deux
    /// questions différentes.
    var pays: String { t("gp.\(slug).pays") }
    /// « GP Malaisie » / « Malaysian GP ».
    var nom: String { t("gp.\(slug).nom") }
    /// Le nom sans « GP » — « Malaisie » / « Malaysia » : la pastille d'un sélecteur.
    var nomCourt: String { t("gp.\(slug).court") }
    var circuit: String { t("gp.\(slug).circuit") }

    /// L'entrée de la liste statique qui porte ce slug, `nil` hors saison.
    static func entree(slug: String) -> GrandPrixSaison? {
        saison2026.first { $0.slug == slug }
    }

    /// **Le nom affiché d'un Grand Prix de la base** — le seul propriétaire. Celui de la liste
    /// statique, traduit, dès que le slug y répond ; le nom d'Unibet n'est qu'un repli hors
    /// saison. Le nom de la base sert au rattachement (``SlugCircuit``), jamais à
    /// l'affichage : le 1er octobre 2026 Unibet a publié « GP Bahrein » à la place de Sepang,
    /// et l'accueil disait Bahreïn quand le calendrier disait Malaisie.
    static func nomAffiche(slug: String, repli: String) -> String {
        entree(slug: slug)?.nom ?? repli
    }

    /// Même règle pour le libellé court ; le repli retire le préfixe « GP » du nom en base.
    static func nomCourtAffiche(slug: String, repli: String) -> String {
        if let entree = entree(slug: slug) { return entree.nomCourt }
        return repli.replacingOccurrences(of: #"^GP\s+"#, with: "",
                                          options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Le mois de la carte dans la langue de l'interface — « AOÛT » ou « AUG », « DÉC » ou
    /// « DEC ». ``mois`` reste la clé écrite, en français, que ``GPRestants`` lit.
    var moisAffiche: String {
        guard let jour = GPRestants.jourDeCourse(self) else { return mois }
        return jour.formatted(.dateTime.month(.abbreviated).locale(localeInterface))
            .replacingOccurrences(of: ".", with: "")
            .uppercased(with: localeInterface)
    }

    /// « 23 août » / « 23 August » — le libellé accessible de la carte.
    var jourMoisAffiche: String {
        guard let jour = GPRestants.jourDeCourse(self) else { return "\(self.jour) \(mois.lowercased())" }
        return jour.formatted(.dateTime.day().month(.wide).locale(localeInterface))
    }

    /// La date complète dans la langue de l'interface — « 1er novembre 2026 »,
    /// « 1 November 2026 ». Repli sur ``date``, écrite, si le mois n'est pas reconnu.
    var dateAffichee: String {
        guard let jour = GPRestants.jourDeCourse(self) else { return date }
        let texte = jour.formatted(.dateTime.day().month(.wide).year().locale(localeInterface))
        // Le premier du mois s'écrit « 1er » en français.
        if langueInterface == .fr, self.jour == "1" { return "1er" + texte.dropFirst() }
        return texte
    }

    /// La liste statique croisée avec la base — `enrichir` du web.
    ///
    /// **Le nom affiché reste celui de la liste**, pas celui d'Unibet : le calendrier doit
    /// se lire pareil d'une semaine à l'autre, y compris quand le bookmaker change
    /// l'orthographe d'un pays.
    static func saison2026(croiseeAvec enBase: [GrandPrixEnBase]?) -> [GrandPrixSaison] {
        guard let enBase else { return saison2026 }
        // Deux lignes pour un même week-end — une manuelle pas encore adoptée et celle du
        // scraper : celle qui porte des cotes l'emporte, c'est la seule pronosticable.
        let parSlug = Dictionary(enBase.map { ($0.slug, $0) }, uniquingKeysWith: { premier, second in
            !premier.cotesDisponibles && second.cotesDisponibles ? second : premier
        })
        return saison2026.map { gp in
            var croise = gp
            croise.enBase = parSlug[gp.slug]
            croise.etatConnu = true
            return croise
        }
    }

    /// **TEMPORAIRE — les onze Grands Prix du début de saison, masqués du calendrier** tant
    /// que leurs drapeaux et leurs tracés SVG manquent : sans eux, leurs cartes ne montraient
    /// qu'un aplat rouge. Le calendrier repart donc des Pays-Bas, comme avant leur ajout.
    ///
    /// **Leurs données restent dans ``saison2026``** : le rattachement par ``SlugCircuit``,
    /// les noms traduits, le calendrier du profil et l'accueil continuent de les connaître.
    /// Seul l'onglet Calendrier les filtre. **Pour les réactiver** : ajouter leurs assets
    /// `flag-<slug>` / `trace-<slug>` et leurs teintes, puis vider cet ensemble.
    static let masquesDuCalendrier: Set<String> = [
        "australie", "chine", "japon", "miami", "canada", "monaco",
        "barcelone", "autriche", "grande-bretagne", "belgique", "hongrie"
    ]

    /// Les Grands Prix de la saison, dans l'ordre — les douze de la fin de saison sont la
    /// transcription de `GP_2026` (`frontend/src/lib/calendrier2026.js`) ; les onze qui
    /// précèdent viennent d'OpenF1 (`/sessions?year=2026&session_name=Race`).
    ///
    /// **Vingt-trois, pas vingt-quatre** : Bahreïn (12 avril) et l'Arabie saoudite (19 avril)
    /// ont été annulés — OpenF1 n'en publie aucun résultat. Le « GP Bahreïn » du 4 octobre,
    /// couru à Sepang, est la carte `malaisie`.
    ///
    /// Les onze premiers n'ont **ni drapeau, ni tracé, ni teintes** : aucune source n'existe
    /// dans `assets/`, et rien ne se redessine à la main (`ios/CLAUDE.md` §3). La carte se
    /// rabat sur l'aplat de la marque, sans tracé — voir ``CarteGrandPrixSaison``.
    ///
    /// `slug` est la clé de **trois** tables à la fois — l'asset `flag-<slug>`, l'asset
    /// `trace-<slug>` et la table des teintes de ``TeintesDrapeaux`` — et celle du
    /// croisement avec la base, par ``SlugCircuit``.
    ///
    /// Pays, nom et circuit ne sont pas écrits ici : ce sont les clés `gp.<slug>.*` des
    /// deux dictionnaires de `Localisation/`.
    static let saison2026: [GrandPrixSaison] = [
        .init(slug: "australie", jour: "8", mois: "MARS", date: "8 mars 2026"),
        .init(slug: "chine", jour: "15", mois: "MARS", date: "15 mars 2026"),
        .init(slug: "japon", jour: "29", mois: "MARS", date: "29 mars 2026"),
        .init(slug: "miami", jour: "3", mois: "MAI", date: "3 mai 2026"),
        .init(slug: "canada", jour: "24", mois: "MAI", date: "24 mai 2026"),
        .init(slug: "monaco", jour: "7", mois: "JUIN", date: "7 juin 2026"),
        .init(slug: "barcelone", jour: "14", mois: "JUIN", date: "14 juin 2026"),
        .init(slug: "autriche", jour: "28", mois: "JUIN", date: "28 juin 2026"),
        .init(slug: "grande-bretagne", jour: "5", mois: "JUIL", date: "5 juillet 2026"),
        .init(slug: "belgique", jour: "19", mois: "JUIL", date: "19 juillet 2026"),
        .init(slug: "hongrie", jour: "26", mois: "JUIL", date: "26 juillet 2026"),
        .init(slug: "pays-bas", jour: "23", mois: "AOÛT", date: "23 août 2026"),
        .init(slug: "italie", jour: "6", mois: "SEPT", date: "6 septembre 2026"),
        .init(slug: "espagne", jour: "13", mois: "SEPT", date: "13 septembre 2026"),
        .init(slug: "azerbaidjan", jour: "26", mois: "SEPT", date: "26 septembre 2026"),
        .init(slug: "malaisie", jour: "4", mois: "OCT", date: "4 octobre 2026"),
        .init(slug: "singapour", jour: "11", mois: "OCT", date: "11 octobre 2026"),
        .init(slug: "etats-unis", jour: "25", mois: "OCT", date: "25 octobre 2026"),
        .init(slug: "mexique", jour: "1", mois: "NOV", date: "1er novembre 2026"),
        .init(slug: "bresil", jour: "15", mois: "NOV", date: "15 novembre 2026"),
        .init(slug: "las-vegas", jour: "21", mois: "NOV", date: "21 novembre 2026"),
        .init(slug: "qatar", jour: "29", mois: "NOV", date: "29 novembre 2026"),
        .init(slug: "abu-dhabi", jour: "6", mois: "DÉC", date: "6 décembre 2026")
    ]
}
