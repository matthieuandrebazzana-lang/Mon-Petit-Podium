import SwiftUI

/// Les résultats d'un Grand Prix couru — **ce que j'ai marqué**, puis **qui a gagné**.
///
/// Références visuelles : `maquettes_V2/IMG_3247.PNG` et `IMG_3248.PNG`, la version web sur
/// iPhone. Le pendant web est `frontend/src/ecrans/ResultatsGp.jsx`, qui reste le
/// propriétaire des règles reprises ici.
///
/// ## Deux sections, dans l'ordre où l'on se pose les questions
///
/// **« Mes résultats »** ouvre l'écran — le total du joueur sur ce Grand Prix, puis un
/// widget par pronostic joué. **« Résultats du GP »** suit, avec le classement complet de
/// la course. Les deux portent le même en-tête, un filet bordeaux et un titre, pour se lire
/// comme deux pairs et non comme un bloc et son annexe.
///
/// > **La troisième section de la version web — le classement des membres du championnat —
/// > n'est pas ici**, et c'est délibéré : elle n'a de sens qu'ouverte depuis un
/// > championnat, et l'écran est atteint depuis le calendrier, où il n'y a aucun membre
/// > à classer. Elle viendra avec le câblage de `GET /grands-prix/{id}/resultats`.
///
/// > **Les données sont mockées.** ``ResultatGPMock`` porte les valeurs de la capture ;
/// > aucun appel réseau ne part de cet écran.
///
/// ## Les règles que l'écran ne décide pas
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1) : « 24 pts », et
/// nulle part un « ×2,40 ». **`NULL` et `0` ne se confondent jamais** — un pronostic pas
/// encore jugé porte une pastille beige et une horloge, un pronostic raté une pastille
/// bordeaux et une croix. Les deux états ne peuvent pas prendre la même couleur, c'est la
/// seule distinction qu'aucun écran n'a le droit de perdre.
///
/// **`pointsFia` est le seul nombre de l'app qui ne soit pas des points au sens de la règle
/// 3.1** : ce sont les points du championnat du monde (25, 18, 15…). Il s'écrit donc à la
/// main, **jamais par ``Swift/Int/enPoints``**, qui est l'habilleur des points de
/// pronostic : lui confier ce nombre-ci le ferait entrer dans le même vocabulaire, et un
/// ajustement futur de l'unité se propagerait ici sans que rien ne le dise.
///
/// ## Rien n'anime, et c'est une décision
///
/// Le portier du mouvement pose d'abord la question « cette chose doit-elle animer du tout
/// ? ». Ici, non : l'écran est une **lecture pure** — aucun geste, aucun état qui change,
/// vingt-sept cartes qui arrivent déjà remplies. Une entrée en cascade sur vingt-deux
/// lignes de classement ferait attendre le résultat qu'on vient lire, et un écran de
/// résultats se consulte plusieurs fois par week-end. Le seul mouvement est celui du
/// défilement, et le seul retour d'appui celui du chevron de retour natif. **Aucun jeton de
/// mouvement nouveau n'entre** (`CLAUDE.md` §4).
struct ResultatsGPView: View {

    /// Le Grand Prix couru, son classement et mes pronostics.
    let resultat: ResultatGPMock

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
                    TitreSectionResultats(titre: "Mes résultats",
                                          sousTitre: "Ce que tes pronostics ont rapporté")

                    Spacer().frame(height: 12)
                    blocTotal

                    Spacer().frame(height: 10)
                    mesPronostics

                    Spacer().frame(height: 24)
                    TitreSectionResultats(titre: "Résultats du GP",
                                          sousTitre: "Classement officiel de la course")

                    Spacer().frame(height: 12)
                    classement
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
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(resultat.nom)
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)            // 15,37:1 sur le beige
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            // `grisSecondaire` (4,71:1) et non le `#999999` de la version web (2,52:1) :
            // le contraste se mesure (`ios/CLAUDE.md` §3).
            Text("\(resultat.etat) · \(resultat.date)")
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Section 1 — Mes résultats

    /// Le bloc rouge : le total du joueur sur ce Grand Prix.
    ///
    /// **`total` nul ne vaut pas zéro** — c'est « rien n'est encore jugé », et l'écrire
    /// « 0 » annoncerait un échec qui n'a pas eu lieu (`CLAUDE.md` §3.1). Le tiret le dit,
    /// et la ligne du dessous compte alors des pronostics en attente plutôt que des
    /// réussites.
    private var blocTotal: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mes points ce GP")
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.encreSecondaire)  // blanc 70 % — 5,75:1 sur le bordeaux

            Spacer().frame(height: 6)

            Text(resultat.total.map(\.enPoints) ?? "—")
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

    /// « 1 prono réussi sur 5 », ou le décompte de ce qui attend encore d'être jugé.
    ///
    /// **Le pluriel est porté par la valeur**, jamais écrit en dur : « 1 pronos réussis »
    /// se serait lu sur tout Grand Prix à une seule réussite.
    private var recapitulatif: String {
        guard resultat.total != nil else {
            let n = resultat.pronostics.count
            return "\(n) pronostic\(n > 1 ? "s" : "") en attente de validation"
        }
        let reussis = resultat.reussis
        return "\(reussis) prono\(reussis > 1 ? "s" : "") réussi\(reussis > 1 ? "s" : "") "
             + "sur \(resultat.juges)"
    }

    private var mesPronostics: some View {
        VStack(spacing: 8) {
            ForEach(resultat.pronostics) { pronostic in
                CartePronostic(pronostic: pronostic)
            }
        }
    }

    // MARK: - Section 2 — Résultats du GP

    private var classement: some View {
        VStack(spacing: 8) {
            ForEach(resultat.classement) { ligne in
                LigneClassementGP(ligne: ligne)
            }
        }
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
private struct PastillePoints: View {

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
private struct Verdict: View {

    let pointsGagnes: Int?

    var body: some View {
        ZStack {
            Circle().fill(aplat)

            if let pointsGagnes {
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

    let ligne: LigneClassementMock

    /// Hauteur de la miniature. Les douze fenêtres de voiture font 141,12 × 288,09, soit un
    /// rapport de 0,49 : à 50 pt de haut la voiture fait 24,5 pt de large.
    private let hauteurVoiture: CGFloat = 50

    /// **Le nom complet, pas le seul nom de famille** : c'est sur son dernier mot que porte
    /// le garde-fou de la table, et lui passer « Sainz » quand elle attend « Carlos Sainz »
    /// reviendrait au même, mais lui passer un prénom seul ne dirait rien.
    private var nationalite: NationalitesPilotes.Nationalite? {
        NationalitesPilotes.nationalite(numero: ligne.numero,
                                        nom: "\(ligne.prenom) \(ligne.nom)")
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
                       numero: ligne.numero.map(String.init) ?? "")
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
        [ligne.ecurie, ligne.mention].compactMap { $0 }.joined(separator: " · ")
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

/// Une ligne du classement de la course.
///
/// **Le prénom et le nom sont deux champs**, pas un nom complet coupé à l'affichage :
/// OpenF1 écrit son `full_name` avec le nom de famille en capitales (« Max VERSTAPPEN »),
/// et le découpage est un travail de lecture de la donnée, pas de mise en page. Il vivra
/// dans le modèle du backend quand l'écran sera câblé.
struct LigneClassementMock: Identifiable {
    /// `nil` pour un pilote non classé — l'abandon précoce.
    let position: Int?
    /// Le numéro de voiture. Il sert deux fois : peint sur le museau, et **confronté au nom
    /// de famille** par ``NationalitesPilotes`` avant qu'un drapeau soit posé.
    let numero: Int?
    let prenom: String
    let nom: String
    let ecurie: String
    /// Le slug de la livrée — la clé de ``LivreeEcurie``, jamais le libellé affiché.
    let ecurieSlug: String
    /// Les points du **championnat du monde** (25, 18, 15…), pas des points de pronostic.
    let pointsFia: Int
    /// « Abandon », « Non partant », « Disqualifié » — ou rien.
    var mention: String?

    var id: String { "\(numero ?? 0)-\(nom)" }
}

/// Les résultats d'un Grand Prix. Remplacé par le modèle du backend quand l'écran sera
/// câblé sur `GET /grands-prix/{id}/resultats`.
struct ResultatGPMock {

    let slug: String
    let nom: String
    /// L'état du Grand Prix, tel que le calendrier l'écrit — « Terminé ».
    let etat: String
    /// La date **écrite**, jamais dérivée d'une `Date` : `2026-09-13` analysée comme une
    /// date nue vaut minuit UTC, et le quantième reculerait d'un jour à l'ouest de
    /// Greenwich. C'est la règle de `CalendrierView`, et elle vaut ici à l'identique.
    let date: String

    let pronostics: [PronosticJoueMock]
    let classement: [LigneClassementMock]

    /// Le total **se lit sur les pronostics**, il n'est pas écrit à côté : une constante
    /// aurait divergé de la liste au premier pronostic retouché. `nil` tant qu'aucun
    /// pronostic n'est jugé — « pas encore jugé » n'est pas « zéro » (`CLAUDE.md` §3.1).
    var total: Int? {
        let juges = pronostics.compactMap(\.pointsGagnes)
        return juges.isEmpty ? nil : juges.reduce(0, +)
    }

    /// Le nombre de pronostics jugés, et celui qui a rapporté quelque chose.
    var juges: Int { pronostics.filter { $0.pointsGagnes != nil }.count }
    var reussis: Int { pronostics.filter { ($0.pointsGagnes ?? 0) > 0 }.count }

    /// Les résultats d'un Grand Prix couru, **pour un mock**.
    ///
    /// Les trois Grands Prix derrière nous partagent le classement et les pronostics de la
    /// capture, et seuls leur nom et leur date changent. C'est assumé : la donnée viendra
    /// de `GET /grands-prix/{id}/resultats`, et écrire trois classements inventés à la main
    /// aurait donné trois tables à corriger le jour où une seule doit disparaître.
    static func pour(slug: String, nom: String, date: String) -> ResultatGPMock {
        ResultatGPMock(slug: slug, nom: nom, etat: "Terminé", date: date,
                       pronostics: gpEspagne.pronostics, classement: gpEspagne.classement)
    }

    /// Le GP Espagne de la capture — `maquettes_V2/IMG_3247.PNG` et `IMG_3248.PNG`.
    ///
    /// > **Lawson court pour Red Bull et Hadjar pour Racing Bulls**, ce qui inverse la
    /// > grille de `frontend/src/lib/ecuries.js`. C'est ce que montre la capture, et c'est
    /// > elle qui fait foi pour un mock : chaque écurie garde ainsi ses deux pilotes.
    /// > La table du web reste le propriétaire de la question le jour où l'écran sera
    /// > câblé — le classement viendra alors d'OpenF1, qui sait qui court pour qui.
    static let gpEspagne = ResultatGPMock(
        slug: "espagne",
        nom: "GP Espagne",
        etat: "Terminé",
        date: "13 septembre 2026",
        pronostics: [
            PronosticJoueMock(marche: "Vainqueur", choix: "L.Hamilton",
                              points: 95, pointsGagnes: 0),
            PronosticJoueMock(marche: "Podium", choix: "L.Norris + AK.Antonelli",
                              points: 24, pointsGagnes: 24),
            PronosticJoueMock(marche: "Ecart du gagnant", choix: "Entre 5 et 10 secondes",
                              points: 41, pointsGagnes: 0),
            PronosticJoueMock(marche: "Top 10", choix: "P.Gasly",
                              points: 18, pointsGagnes: 0),
            PronosticJoueMock(marche: "Nationalité du vainqueur", choix: "Royaume-Uni",
                              points: 21, pointsGagnes: 0)
        ],
        classement: [
            .init(position: 1,  numero: 12, prenom: "Kimi",     nom: "Antonelli",
                  ecurie: "Mercedes",     ecurieSlug: "mercedes",     pointsFia: 25),
            .init(position: 2,  numero: 3,  prenom: "Max",      nom: "Verstappen",
                  ecurie: "Red Bull Racing", ecurieSlug: "red-bull",  pointsFia: 18),
            .init(position: 3,  numero: 1,  prenom: "Lando",    nom: "Norris",
                  ecurie: "McLaren",      ecurieSlug: "mclaren",      pointsFia: 15),
            .init(position: 4,  numero: 16, prenom: "Charles",  nom: "Leclerc",
                  ecurie: "Ferrari",      ecurieSlug: "ferrari",      pointsFia: 12),
            .init(position: 5,  numero: 63, prenom: "George",   nom: "Russell",
                  ecurie: "Mercedes",     ecurieSlug: "mercedes",     pointsFia: 10),
            .init(position: 6,  numero: 30, prenom: "Liam",     nom: "Lawson",
                  ecurie: "Red Bull Racing", ecurieSlug: "red-bull",  pointsFia: 8),
            .init(position: 7,  numero: 43, prenom: "Franco",   nom: "Colapinto",
                  ecurie: "Alpine",       ecurieSlug: "alpine",       pointsFia: 6),
            .init(position: 8,  numero: 81, prenom: "Oscar",    nom: "Piastri",
                  ecurie: "McLaren",      ecurieSlug: "mclaren",      pointsFia: 4),
            .init(position: 9,  numero: 41, prenom: "Arvid",    nom: "Lindblad",
                  ecurie: "Racing Bulls", ecurieSlug: "racing-bulls", pointsFia: 2),
            .init(position: 10, numero: 6,  prenom: "Isack",    nom: "Hadjar",
                  ecurie: "Racing Bulls", ecurieSlug: "racing-bulls", pointsFia: 1),
            .init(position: 11, numero: 44, prenom: "Lewis",    nom: "Hamilton",
                  ecurie: "Ferrari",      ecurieSlug: "ferrari",      pointsFia: 0),
            .init(position: 12, numero: 10, prenom: "Pierre",   nom: "Gasly",
                  ecurie: "Alpine",       ecurieSlug: "alpine",       pointsFia: 0),
            .init(position: 13, numero: 14, prenom: "Fernando", nom: "Alonso",
                  ecurie: "Aston Martin", ecurieSlug: "aston-martin", pointsFia: 0),
            .init(position: 14, numero: 55, prenom: "Carlos",   nom: "Sainz",
                  ecurie: "Williams",     ecurieSlug: "williams",     pointsFia: 0),
            .init(position: 15, numero: 23, prenom: "Alexander", nom: "Albon",
                  ecurie: "Williams",     ecurieSlug: "williams",     pointsFia: 0),
            .init(position: 16, numero: 27, prenom: "Nico",     nom: "Hulkenberg",
                  ecurie: "Audi",         ecurieSlug: "audi",         pointsFia: 0),
            .init(position: 17, numero: 5,  prenom: "Gabriel",  nom: "Bortoleto",
                  ecurie: "Audi",         ecurieSlug: "audi",         pointsFia: 0),
            .init(position: 18, numero: 31, prenom: "Esteban",  nom: "Ocon",
                  ecurie: "Haas",         ecurieSlug: "haas",         pointsFia: 0),
            .init(position: 19, numero: 87, prenom: "Oliver",   nom: "Bearman",
                  ecurie: "Haas",         ecurieSlug: "haas",         pointsFia: 0),
            .init(position: 20, numero: 77, prenom: "Valtteri", nom: "Bottas",
                  ecurie: "Cadillac",     ecurieSlug: "cadillac",     pointsFia: 0),
            .init(position: 21, numero: 11, prenom: "Sergio",   nom: "Perez",
                  ecurie: "Cadillac",     ecurieSlug: "cadillac",     pointsFia: 0),
            .init(position: nil, numero: 18, prenom: "Lance",   nom: "Stroll",
                  ecurie: "Aston Martin", ecurieSlug: "aston-martin", pointsFia: 0,
                  mention: "Abandon")
        ]
    )
}

#Preview {
    NavigationStack {
        ResultatsGPView(resultat: .gpEspagne)
    }
}
