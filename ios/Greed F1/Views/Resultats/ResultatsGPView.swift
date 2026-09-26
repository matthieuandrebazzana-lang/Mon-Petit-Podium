import SwiftUI

/// Les résultats d'un Grand Prix couru — le classement officiel de la course.
///
/// Références visuelles : `maquettes_V2/IMG_3247.PNG` et `IMG_3248.PNG`, la version web sur
/// iPhone. Le pendant web est `frontend/src/ecrans/ResultatsGp.jsx`, qui reste le
/// propriétaire des règles reprises ici.
///
/// ## Ce qui est branché
///
/// **« Résultats du GP »** lit `GET /grands-prix/{id}/resultats` (``ResultatsGrandPrix``),
/// appelée **sans** `championnat_id` : le classement de la course seul. Positions,
/// abandons, non-partants et disqualifiés viennent de la réponse ; **ni pole ni meilleur
/// tour** — le backend ne les sert pas, l'écran ne les invente pas.
///
/// `disponible: false`, classement vide, `404` ou Grand Prix inconnu de la base ⇒
/// « Résultats non disponibles », **jamais un classement vide**, qui se lirait comme une
/// course où personne n'aurait fini. Un vrai échec passe par ``EchecChargement``.
///
/// > **« Mes résultats » n'est pas monté** : ses données (mes pronostics en direct) sont
/// > le reste de l'étape 6. ``SectionMesResultats`` attend, non montée, plutôt que
/// > d'afficher des pronostics inventés.
///
/// ## Les règles que l'écran ne décide pas
///
/// **`pointsFia` est le seul nombre de l'app qui ne soit pas des points au sens de la règle
/// 3.1** : ce sont les points du championnat du monde (25, 18, 15…). Il s'écrit donc à la
/// main, **jamais par ``Swift/Int/enPoints``**, qui est l'habilleur des points de
/// pronostic.
///
/// ## Rien n'anime, et c'est une décision
///
/// L'écran est une **lecture pure** — aucun geste, aucun état qui change une fois chargé.
/// Une entrée en cascade sur vingt-deux lignes ferait attendre le résultat qu'on vient
/// lire. Le classement remplace le spinner sans transition. **Aucun jeton de mouvement
/// nouveau n'entre** (`CLAUDE.md` §4).
struct ResultatsGPView: View {

    let nom: String
    /// La date **écrite** du calendrier, jamais dérivée d'une `Date` (voir ``CalendrierView``).
    let date: String

    @StateObject private var resultats: ResultatsGrandPrix

    init(nom: String, date: String, gpId: UUID?) {
        self.nom = nom
        self.date = date
        _resultats = StateObject(wrappedValue: ResultatsGrandPrix(gpId: gpId))
    }

    /// Pour les aperçus : un état posé d'avance, aucun appel.
    init(nom: String, date: String, apercu: ResultatsGrandPrix.Etat) {
        self.nom = nom
        self.date = date
        _resultats = StateObject(wrappedValue: ResultatsGrandPrix(gpId: nil, etat: apercu))
    }

    /// Marge latérale commune à tous les écrans — la même que `CalendrierView`, sans quoi
    /// la carte du calendrier et l'écran qu'elle ouvre ne s'aligneraient pas.
    private let margeLaterale: CGFloat = 16

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    entete

                    Spacer().frame(height: 24)      // changement de sujet : 24 pt (§4.6)
                    TitreSectionResultats(
                        titre: "Résultats du GP",
                        sousTitre: resultats.provisoire
                            ? "Classement provisoire · définitif 24 h après la course"
                            : "Classement officiel de la course"
                    )

                    Spacer().frame(height: 12)
                    contenu
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        // Le nom du Grand Prix est déjà dans le contenu, à 28 pt : le répéter dans la barre
        // ferait doublon. Elle ne garde que le chevron de retour natif, qui porte le titre
        // de l'écran précédent — « Calendrier ».
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await resultats.charger() }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nom)
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)            // 15,37:1 sur le beige
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            // `grisSecondaire` (4,71:1) et non le `#999999` de la version web (2,52:1) :
            // le contraste se mesure (`ios/CLAUDE.md` §3). Seul un GP « Terminé » ouvre
            // cet écran (``CalendrierView``).
            // « Provisoire » s'y glisse tant que le calcul définitif n'est pas passé : même
            // ligne, même encre, rien de plus à lire.
            Text(resultats.provisoire
                 ? "Terminé · \(StatutResultats.mention) · \(date)"
                 : "Terminé · \(date)")
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
                .accessibilityHint(resultats.provisoire ? StatutResultats.detail : "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Résultats du GP

    @ViewBuilder private var contenu: some View {
        switch resultats.etat {
        case .chargement:
            ProgressView()
                .tint(.secondaire)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel("Chargement des résultats")

        case .echec(let erreur):
            EchecChargement(erreur: erreur) {
                Task { await resultats.charger() }
            }

        case .indisponible:
            VStack(spacing: 4) {
                Text("Résultats non disponibles")
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.texte)        // 15,37:1 sur le beige
                Text("Ils apparaîtront ici une fois la course récupérée.")
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.grisSecondaire)   // 4,71:1 sur le beige
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)

        case .pret(let classement):
            VStack(spacing: 8) {
                ForEach(classement) { ligne in
                    LigneClassementGP(ligne: ligne)
                }
            }
        }
    }
}

// MARK: - Section « Mes résultats » — non montée

/// Le total du joueur sur ce Grand Prix, puis un widget par pronostic joué.
///
/// **Non montée** tant que mes pronostics ne sont pas lus en direct (reste de l'étape 6) :
/// l'afficher sur des valeurs inventées mentirait. Le code est éprouvé contre la capture,
/// il reste en place (`CLAUDE.md` §6).
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1). **`NULL` et `0` ne
/// se confondent jamais** — un pronostic pas encore jugé porte une pastille beige et une
/// horloge, un pronostic raté une pastille bordeaux et une croix.
struct SectionMesResultats: View {

    let pronostics: [PronosticJoueMock]

    /// Le total **se lit sur les pronostics**. `nil` tant qu'aucun n'est jugé — « pas
    /// encore jugé » n'est pas « zéro ».
    private var total: Int? {
        let juges = pronostics.compactMap(\.pointsGagnes)
        return juges.isEmpty ? nil : juges.reduce(0, +)
    }

    private var juges: Int { pronostics.filter { $0.pointsGagnes != nil }.count }
    private var reussis: Int { pronostics.filter { ($0.pointsGagnes ?? 0) > 0 }.count }

    var body: some View {
        VStack(spacing: 0) {
            TitreSectionResultats(titre: "Mes résultats",
                                  sousTitre: "Ce que tes pronostics ont rapporté")
            Spacer().frame(height: 12)
            blocTotal
            Spacer().frame(height: 10)
            VStack(spacing: 8) {
                ForEach(pronostics) { pronostic in
                    CartePronostic(pronostic: pronostic)
                }
            }
        }
    }

    /// Le bloc rouge : le total du joueur. **`total` nul ne vaut pas zéro** — le tiret le
    /// dit, et la ligne du dessous compte alors des pronostics en attente.
    private var blocTotal: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mes points ce GP")
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encreSecondaire)  // blanc 70 % — 5,75:1 sur le bordeaux

            Spacer().frame(height: 6)

            Text(total.map(\.enPoints) ?? "—")
                .font(.scoreLg)
                .tracking(Tracking.scoreLg)
                .foregroundColor(.white)            // 10,88:1 sur le bordeaux

            Spacer().frame(height: 4)

            Text(recapitulatif)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.encreSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.primaire)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()                               // aplat de couleur → `shadow-aplat`
        .accessibilityElement(children: .combine)
    }

    /// **Le pluriel est porté par la valeur**, jamais écrit en dur.
    private var recapitulatif: String {
        guard total != nil else {
            let n = pronostics.count
            return "\(n) pronostic\(n > 1 ? "s" : "") en attente de validation"
        }
        return "\(reussis) prono\(reussis > 1 ? "s" : "") réussi\(reussis > 1 ? "s" : "") "
             + "sur \(juges)"
    }
}

// MARK: - L'en-tête d'une section

/// Le titre d'une section, et le filet qui la détache de la précédente.
///
/// **Le filet n'est pas un trait.** Le design system proscrit les bordures fines et n'en
/// excepte que l'aplat vertical posé à côté d'un titre — celui du classement d'un
/// championnat. C'est lui qui est repris ici, en bordeaux : la hiérarchie passe par **la
/// taille, la graisse et l'espace**, et le filet ne fait que donner à l'œil un point
/// d'accroche à gauche.
private struct TitreSectionResultats: View {

    let titre: String
    let sousTitre: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(Color.primaire)               // 9,61:1 sur le beige
                .frame(width: 3, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.custom("HelveticaNeue-Medium", size: 20))
                    .tracking(-0.40)                // -0,02 em sur un titre (§4.5)
                    .foregroundColor(.texte)        // 15,37:1 sur le beige

                Text(sousTitre)
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.grisSecondaire)   // 4,71:1 sur le beige
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Un pronostic joué

/// Trois choses, dans l'ordre où on les lit : **le marché**, **la sélection**, **le
/// verdict**. Le marché est en label parce qu'il classe ; la sélection est ce qu'on vient
/// lire, elle est donc la plus grosse et la seule en encre pleine.
///
/// La pastille et le pictogramme disent la même chose de deux façons — un nombre coloré et
/// une forme — et c'est délibéré : **la couleur seule ne porte jamais une information**
/// (WCAG 1.4.1), et ``Verdict`` porte le libellé accessible qui la nomme.
private struct CartePronostic: View {

    let pronostic: PronosticJoueMock

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pronostic.marche)
                    .font(.label)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    // **`secondaire` et non un gris.** Le marron tient 12,58:1 sur le
                    // blanc ; `texteDoux` n'y vaut que 2,85:1, sous le plancher de 4,5:1
                    // d'un texte ordinaire — et un libellé de marché se lit.
                    .foregroundColor(.secondaire)
                    .lineLimit(1)

                Text(pronostic.choix)
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundColor(.texte)        // 15,37:1 sur le blanc
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PastillePoints(pointsGagnes: pronostic.pointsGagnes, points: pronostic.points)
            Verdict(pointsGagnes: pronostic.pointsGagnes)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .ombreCarte()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pronostic.marche), \(pronostic.choix), \(libelleVerdict)")
    }

    private var libelleVerdict: String {
        guard let gagnes = pronostic.pointsGagnes else {
            return "\(pronostic.points) points en jeu, en attente de validation"
        }
        return gagnes > 0 ? "\(gagnes) points gagnés" : "raté, aucun point"
    }
}

/// Ce qu'un pronostic rapporte, et la couleur qui dit s'il l'a rapporté.
///
/// **Trois états, jamais deux.** Le beige de l'attente n'est pas un troisième verdict :
/// c'est l'**absence** de verdict. Il porte les points *potentiels*, et le peindre en rouge
/// annoncerait un échec qui n'a pas eu lieu.
///
/// | État | Aplat | Encre | Contraste |
/// |---|---|---|---|
/// | réussi (`> 0`) | vert sauge | blanc | **4,86:1** |
/// | raté (`0`) | bordeaux | blanc | **10,88:1** |
/// | en attente (`nil`) | beige | marron | **9,32:1** |
struct PastillePoints: View {

    let pointsGagnes: Int?
    let points: Int

    var body: some View {
        Text("\((pointsGagnes ?? points).enPoints) pts")
            .font(.custom("HelveticaNeue-Medium", size: 13))
            .foregroundColor(encre)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(aplat)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
    }

    private var aplat: Color {
        guard let pointsGagnes else { return .fondPrincipal }
        return pointsGagnes > 0 ? .vertSauge : .primaire
    }

    private var encre: Color {
        pointsGagnes == nil ? .secondaire : .white
    }
}

/// Le verdict d'un pronostic — une pastille de 22 pt, trois états.
///
/// > **L'horloge de l'attente prend `grisSecondaire`, pas `texteDoux`.** Sur le beige, le
/// > `#999999` de la version web ne vaut que **2,52:1**, sous le plancher de 3:1 d'un
/// > élément graphique porteur de sens — et celui-ci en porte un, il dit « pas encore
/// > jugé ». `#6B6B6B` y tient **4,71:1** pour un gris que l'œil ne distingue pas du
/// > premier.
struct Verdict: View {

    let pointsGagnes: Int?
    /// Quatrième état depuis la `0.78.0` : aucun évaluateur ne porte le marché. Ni
    /// l'horloge (« bientôt ») ni la croix (« raté ») ne disent vrai ; le tiret dit « rien
    /// à juger ». Même aplat et même encre que l'attente : ce n'est pas un verdict.
    var nonEvaluable = false

    var body: some View {
        ZStack {
            Circle().fill(aplat)

            if nonEvaluable && pointsGagnes == nil {
                Text("–")
                    .font(.custom("HelveticaNeue-Medium", size: 13))
                    .foregroundColor(.grisSecondaire)   // 4,71:1 sur le beige, comme l'horloge
            } else if let pointsGagnes {
                if pointsGagnes > 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.vertSauge)    // 4,01:1 sur le vert à 15 %
                } else {
                    Text("×")
                        .font(.custom("HelveticaNeue-Medium", size: 13))
                        .foregroundColor(.primaire)     // 8,94:1 sur le bordeaux à 10 %
                }
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.grisSecondaire)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)                      // dit par le libellé de la carte
    }

    private var aplat: Color {
        guard let pointsGagnes else { return .fondPrincipal }
        return pointsGagnes > 0 ? Color.vertSauge.opacity(0.15) : Color.primaire.opacity(0.10)
    }
}

// MARK: - Une ligne du classement

/// De gauche à droite : la position, la voiture de l'écurie, le pilote, les points du
/// championnat du monde. **Le drapeau de nationalité du pilote est en fond**, à 15 %.
///
/// ## Le lavis, et les encres qu'il autorise
///
/// **Mesuré sur le pire substrat des seize drapeaux** — le noir (bande allemande, champ de
/// l'Union Jack), qui compose `#D9D9D9` sur blanc à 15 % : l'encre `texte` y vaut
/// **12,30:1**, le marron `secondaire` **7,46:1**, le bordeaux `primaire` **7,68:1**.
///
/// > **Aucun gris ne tient ici.** `grisSecondaire` tombe à **3,76:1** sur ce même substrat
/// > — sous le plancher de 4,5:1 d'un texte ordinaire. Le prénom et l'écurie passent donc
/// > au marron `secondaire`, et le rang à l'encre `texte`, comme la version web.
///
/// **Le drapeau est étiré, pas recadré.** Une rangée fait 361 × 62 pt, soit un rapport de
/// 5,8:1 là où un drapeau en fait 1,5:1 : `scaledToFill` recadrerait sur la bande centrale
/// et l'Allemagne ressortirait entièrement rouge, indistinguable d'un pays à drapeau rouge.
/// `.resizable()` seul rend les deux échelles indépendantes — **toutes** les bandes
/// survivent, seule leur proportion s'étire, et la signature de couleur reste juste. C'est
/// le `preserveAspectRatio="none"` de la version web, et le même arbitrage que `FondPiste`.
///
/// **Un pays sans dessin n'est pas une panne** : la carte garde son blanc, jamais une
/// couleur de repli. Le cas n'arrive pas sur la grille 2026 — les seize codes ont leur
/// asset — mais il arrivera sur un pilote remplaçant qu'aucune table ne connaît encore.
private struct LigneClassementGP: View {

    let ligne: LigneResultat

    /// Hauteur de la miniature. Les douze fenêtres de voiture font 141,12 × 288,09, soit un
    /// rapport de 0,49 : à 50 pt de haut la voiture fait 24,5 pt de large.
    private let hauteurVoiture: CGFloat = 50

    /// **Le nom complet d'OpenF1** : c'est sur son dernier mot que porte le garde-fou de
    /// la table, confronté au numéro.
    private var nationalite: NationalitesPilotes.Nationalite? {
        NationalitesPilotes.nationalite(numero: ligne.driverNumber, nom: ligne.pilote)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(ligne.position.map(String.init) ?? "—")
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .tracking(-0.40)
                // Les trois premières places en bordeaux : il n'en faut pas plus pour
                // trouver le podium d'un coup d'œil dans une colonne de vingt-deux lignes.
                .foregroundColor(estSurLePodium ? .primaire : .texte)
                .frame(width: 24)
                .lineLimit(1)

            // La vraie livrée de l'écurie, jamais un rond de couleur. Un slug inconnu
            // retombe sur la voiture personnalisable plutôt que de laisser un trou.
            VueVoiture(livree: Livree(mode: .ecurie, ecurie: ligne.ecurieSlug),
                       numero: ligne.driverNumber.map(String.init) ?? "")
                .frame(height: hauteurVoiture)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                if !ligne.prenom.isEmpty {
                    Text(ligne.prenom)
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.secondaire)
                        .lineLimit(1)
                }

                // Le nom de famille porte la reconnaissance : plus gros et plus gras que le
                // prénom, la hiérarchie par la taille et la graisse plutôt que par une
                // couleur de plus.
                Text(ligne.nom)
                    .font(.custom("HelveticaNeue-Medium", size: 18))
                    .tracking(-0.36)
                    .foregroundColor(.texte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(sousLigne)
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.secondaire)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            pointsFia
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(fond)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .ombreCarte()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible)
    }

    private var estSurLePodium: Bool {
        (ligne.position ?? .max) <= 3
    }

    /// L'écurie, et la mention qui explique une ligne sans position. **Trois mentions, un
    /// seul mot** : elles ne peuvent pas se cumuler à l'écran, et l'ordre est celui de la
    /// gravité — un disqualifié a d'abord été classé.
    private var sousLigne: String {
        [ligne.equipe, ligne.mention].compactMap { $0 }.joined(separator: " · ")
    }

    private var fond: some View {
        ZStack {
            Color.surface
            if let nationalite {
                Image(nationalite.asset)
                    .resizable()                    // étiré, jamais recadré — voir l'en-tête
                    .opacity(0.15)
            }
        }
        .accessibilityHidden(true)
    }

    /// **Un zéro et une absence de classement ne s'écrivent pas pareil.** Un pilote classé
    /// qui ne marque pas porte « 0 pt » sans aplat : c'est un fait, et il vaut la peine
    /// d'être lu. Un pilote non classé n'a pas de résultat du tout, et porte un tiret.
    @ViewBuilder private var pointsFia: some View {
        if ligne.pointsFia > 0 {
            Text("\(ligne.pointsFia) pt\(ligne.pointsFia > 1 ? "s" : "")")
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundColor(.secondaire)       // 9,32:1 sur le beige
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.fondPrincipal)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
        } else {
            Text(ligne.position == nil ? "—" : "0 pt")
                .font(.custom("HelveticaNeue", size: 15))
                .foregroundColor(.secondaire)
                .lineLimit(1)
                .padding(.horizontal, 10)
        }
    }

    private var libelleAccessible: String {
        let rang = ligne.position.map { "\($0)\($0 == 1 ? "er" : "e")" } ?? "non classé"
        let pays = nationalite.map { ", \($0.pays)" } ?? ""
        let points = ligne.pointsFia > 0
            ? "\(ligne.pointsFia) point\(ligne.pointsFia > 1 ? "s" : "") au championnat"
            : (ligne.position == nil ? "aucun résultat" : "aucun point")
        return "\(rang), \(ligne.prenom) \(ligne.nom)\(pays), \(sousLigne). \(points)."
    }
}

// MARK: - Données mockées

/// Un pronostic joué sur ce Grand Prix.
///
/// **`pointsGagnes` est optionnel, et c'est tout le sujet** : `nil` veut dire « pas encore
/// jugé, ou marché non reconnu » et se rattrape ; `0` veut dire « raté ». `points` reste ce
/// que le pari rapportait *s'il passait*, et c'est lui qu'affiche la pastille tant que rien
/// n'est jugé.
struct PronosticJoueMock: Identifiable {
    let id = UUID()
    let marche: String
    let choix: String
    /// Les points en jeu — la valeur en base **EST** un nombre de points (`CLAUDE.md` §3.1).
    let points: Int
    let pointsGagnes: Int?
}

#if DEBUG
extension LigneResultat {

    /// Le GP Espagne de la capture — `maquettes_V2/IMG_3247.PNG` et `IMG_3248.PNG`, dans
    /// la forme d'OpenF1 (nom de famille en capitales, libellé d'écurie long).
    static let apercu: [LigneResultat] = [
        .init(position: 1,  driverNumber: 12, pilote: "Kimi ANTONELLI",   equipe: "Mercedes",        pointsFia: 25),
        .init(position: 2,  driverNumber: 3,  pilote: "Max VERSTAPPEN",   equipe: "Red Bull Racing", pointsFia: 18),
        .init(position: 3,  driverNumber: 1,  pilote: "Lando NORRIS",     equipe: "McLaren",         pointsFia: 15),
        .init(position: 4,  driverNumber: 16, pilote: "Charles LECLERC",  equipe: "Ferrari",         pointsFia: 12),
        .init(position: 5,  driverNumber: 63, pilote: "George RUSSELL",   equipe: "Mercedes",        pointsFia: 10),
        .init(position: 6,  driverNumber: 30, pilote: "Liam LAWSON",      equipe: "Racing Bulls",    pointsFia: 8),
        .init(position: 7,  driverNumber: 43, pilote: "Franco COLAPINTO", equipe: "Alpine",          pointsFia: 6),
        .init(position: 8,  driverNumber: 81, pilote: "Oscar PIASTRI",    equipe: "McLaren",         pointsFia: 4),
        .init(position: 9,  driverNumber: 55, pilote: "Carlos SAINZ",     equipe: "Williams",        pointsFia: 2),
        .init(position: 10, driverNumber: 27, pilote: "Nico HULKENBERG",  equipe: "Audi",            pointsFia: 1),
        .init(position: 11, driverNumber: 44, pilote: "Lewis HAMILTON",   equipe: "Ferrari",         pointsFia: 0, abandon: true),
        .init(position: nil, driverNumber: 18, pilote: "Lance STROLL",    equipe: "Aston Martin",    pointsFia: 0, abandon: true),
        .init(position: nil, driverNumber: 87, pilote: "Oliver BEARMAN",  equipe: "Haas F1 Team",    pointsFia: 0, nonPartant: true)
    ]
}

extension PronosticJoueMock {

    /// Les pronostics de la capture, pour l'aperçu de ``SectionMesResultats``.
    static let apercu: [PronosticJoueMock] = [
        PronosticJoueMock(marche: "Vainqueur", choix: "L.Hamilton", points: 95, pointsGagnes: 0),
        PronosticJoueMock(marche: "Podium", choix: "L.Norris + AK.Antonelli", points: 24, pointsGagnes: 24),
        PronosticJoueMock(marche: "Top 10", choix: "P.Gasly", points: 18, pointsGagnes: nil)
    ]
}
#endif

#Preview("Classement") {
    NavigationStack {
        ResultatsGPView(nom: "GP Espagne", date: "13 septembre 2026",
                        apercu: .pret(LigneResultat.apercu))
    }
}

#Preview("Non disponibles") {
    NavigationStack {
        ResultatsGPView(nom: "GP Azerbaïdjan", date: "26 septembre 2026", apercu: .indisponible)
    }
}

#Preview("Mes résultats") {
    ScrollView { SectionMesResultats(pronostics: PronosticJoueMock.apercu).padding(16) }
        .background(Color.fondPrincipal)
}
