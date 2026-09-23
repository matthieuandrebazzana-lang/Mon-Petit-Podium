import SwiftUI

/// La fiche d'un Grand Prix pas encore couru — le programme du week-end, le circuit et son
/// palmarès.
///
/// Références visuelles : `Ressources/Screenshots/screen-18-detail-gp-haut.PNG` et
/// `screen-19-detail-gp-bas.PNG`. Le pendant web est `frontend/src/ecrans/DetailGp.jsx`,
/// qui reste le propriétaire des règles reprises ici.
///
/// **On y arrive en touchant une carte du calendrier.** Un Grand Prix couru n'ouvre pas cet
/// écran mais ses résultats : devant une course passée, la question est « qui a gagné »,
/// pas « à quelle heure sont les EL1 ». C'est ``CalendrierView`` qui fait ce départage.
///
/// ## Trois blocs, dans l'ordre où on les cherche
///
/// 1. **Le programme** — ce qu'on vient chercher la semaine qui précède, donc en haut.
/// 2. **Le circuit** — le tracé en grand, puis quatre chiffres.
/// 3. **Le palmarès** — les derniers vainqueurs, qu'on parcourt sans but précis.
///
/// > **Les données sont mockées.** ``FichesGrandPrix`` transcrit `GP_2026` et `CIRCUITS` ;
/// > aucun appel réseau ne part de cet écran. Le bouton « Voir les cotes » de la version
/// > web n'est pas là : il exige des cotes arrêtées, que seule la base connaît.
///
/// ## Rien n'anime, et c'est une décision
///
/// Le portier du mouvement répond non : aucun élément ne change d'état sous les yeux, et la
/// fiche s'ouvre plusieurs fois dans la semaine qui précède la course. Un tracé qui se
/// dessinerait serait joli la première fois et une attente les vingt suivantes. Le seul
/// mouvement est le glissement natif du `NavigationLink`. **Aucun jeton de mouvement
/// nouveau** (`CLAUDE.md` §4).
struct DetailGPView: View {

    let grandPrix: GrandPrixSaisonMock

    /// Marge latérale commune à tous les écrans — la même que ``CalendrierView``.
    private let margeLaterale: CGFloat = 16

    /// Hauteur **fixe** de la bande du tracé : les cadrages vont de 1,13 (Zandvoort) à 3,4
    /// (Bakou), et une hauteur qui les suivrait ferait sauter la grille de chiffres d'un
    /// Grand Prix à l'autre. `scaledToFit` centre chaque circuit dedans.
    private let hauteurTrace: CGFloat = 190

    private var seances: [FichesGrandPrix.Seance] { FichesGrandPrix.seances(slug: grandPrix.slug) }
    private var fiche: FichesGrandPrix.Fiche? { FichesGrandPrix.fiche(slug: grandPrix.slug) }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    entete

                    Spacer().frame(height: 20)
                    TitreBloc(titre: "Week-end")
                    Spacer().frame(height: 8)
                    ProgrammeWeekend(seances: seances)

                    if let fiche {
                        Spacer().frame(height: 24)
                        TitreBloc(titre: "Circuit")
                        Spacer().frame(height: 8)
                        blocTrace
                        Spacer().frame(height: 10)
                        grilleStats(fiche)

                        if !fiche.vainqueurs.isEmpty {
                            Spacer().frame(height: 24)
                            TitreBloc(titre: "Derniers vainqueurs")
                            Spacer().frame(height: 8)
                            grilleVainqueurs(fiche.vainqueurs)
                        }
                    }
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        // Le nom du Grand Prix est déjà dans le contenu, à 28 pt : la barre ne garde que le
        // chevron de retour natif, qui porte « Calendrier ». Même choix que les résultats.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(grandPrix.nom)
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)                // 15,37:1 sur le beige
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)

            // `grisSecondaire` (4,71:1) et non le `#999999` de la version web (2,52:1).
            Text("\(grandPrix.circuit) · \(grandPrix.pays)")
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)

            Spacer().frame(height: 6)

            // **Le mot et la couleur viennent d'``EtatGp``**, jamais d'ici : le calendrier
            // et la fiche doivent dire le même mot avec la même couleur.
            Text(grandPrix.etat.libelle)
                .font(.custom("HelveticaNeue-Medium", size: 11))
                .foregroundColor(grandPrix.etat.encrePastille)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(grandPrix.etat.fondPastille)
                .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Le circuit

    /// Le trait est en `secondaire` : un élément graphique porteur de sens demande 3:1, et
    /// le marron en vaut 9,4:1 sur blanc.
    private var blocTrace: some View {
        Image("trace-\(grandPrix.slug)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(.secondaire)
            .frame(maxWidth: .infinity)
            .frame(height: hauteurTrace)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
            .ombreBloc()
            .accessibilityLabel("Tracé du circuit de \(grandPrix.circuit)")
    }

    /// Quatre chiffres, quatre cases : un carré de deux sur deux, jamais une case inventée.
    /// **Un tiret, jamais un zéro**, là où la fiche n'a rien.
    private func grilleStats(_ fiche: FichesGrandPrix.Fiche) -> some View {
        let colonnes = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        let longueur = fiche.longueurKm.formatted(
            .number.precision(.fractionLength(3)).locale(Locale(identifier: "fr_FR")))

        return LazyVGrid(columns: colonnes, spacing: 10) {
            CaseStat(libelle: "Longueur", valeur: "\(longueur) km")
            CaseStat(libelle: "Tours", valeur: fiche.tours.map(String.init) ?? "—")
            CaseStat(libelle: "Premier GP", valeur: fiche.premierGp.map(String.init) ?? "—")
            CaseStat(libelle: "Record du tour",
                     valeur: fiche.record?.temps ?? "—",
                     detail: fiche.record.map { "\($0.pilote) · \(String($0.annee))" }
                        ?? "Circuit jamais couru")
        }
    }

    // MARK: - Le palmarès

    /// Deux colonnes : un palmarès se parcourt du regard, et « qui gagne ici ? » se répond
    /// en voyant les millésimes **ensemble**. Une dernière rangée incomplète reste
    /// incomplète.
    private func grilleVainqueurs(_ vainqueurs: [FichesGrandPrix.Vainqueur]) -> some View {
        let colonnes = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: colonnes, alignment: .leading, spacing: 10) {
            ForEach(vainqueurs) { CarteVainqueur(vainqueur: $0) }
        }
    }
}

// MARK: - Titre d'un bloc

private struct TitreBloc: View {

    let titre: String

    var body: some View {
        Text(titre)
            .font(.custom("HelveticaNeue-Medium", size: 13))
            .tracking(Tracking.label)
            .foregroundColor(.secondaire)               // 10,55:1 sur le beige
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Le programme du week-end

/// Cinq rangées dans **un** bloc, pas cinq cartes : ce sont cinq valeurs d'une même liste,
/// lues d'un coup. Les rangées se séparent par du blanc, jamais par un filet.
///
/// **Passée** — opacité 0,5, la valeur du web et son écart assumé (`SeancesWeekend.jsx`).
/// **Imminente** — la prochaine séance, à moins de vingt-quatre heures : aplat ambre pâle
/// et pastille « Bientôt », celle de « Pronos ouverts ». Une seule mise en avant.
private struct ProgrammeWeekend: View {

    let seances: [FichesGrandPrix.Seance]

    /// `SEUIL_IMMINENT_MS` côté web.
    private let seuilImminent: TimeInterval = 24 * 60 * 60

    var body: some View {
        // L'instant est lu une fois au rendu, et rien ne le réévalue : c'est un écran de
        // consultation, pas un compte à rebours.
        let maintenant = Date()
        let prochaine = seances.first { ($0.instant ?? .distantPast) > maintenant }
        let imminente = prochaine.flatMap { seance in
            seance.instant.map { $0.timeIntervalSince(maintenant) <= seuilImminent } == true
                ? seance.cle : nil
        }

        VStack(spacing: 2) {
            ForEach(seances) { seance in
                RangeeSeance(seance: seance,
                             passee: seance.instant.map { $0 <= maintenant } ?? false,
                             imminente: seance.cle == imminente)
            }
        }
        .padding(8)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }
}

private struct RangeeSeance: View {

    let seance: FichesGrandPrix.Seance
    let passee: Bool
    let imminente: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(seance.libelle)
                        .font(.custom("HelveticaNeue-Medium", size: 17))
                        .foregroundColor(.texte)        // 17,40:1 sur blanc
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if imminente {
                        Text("Bientôt")
                            .font(.custom("HelveticaNeue-Medium", size: 11))
                            .foregroundColor(.texte)    // 7,86:1 sur ambre
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Rayon.pastille,
                                                        style: .continuous))
                    }
                }

                Text(seance.instant.map(Self.jour) ?? "Horaire à confirmer")
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.secondaire)       // 10,55:1 sur blanc
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Chiffres tabulaires : les cinq heures s'alignent sur leur colonne.
            Text(seance.instant.map(Self.heure) ?? "—")
                .font(.custom("HelveticaNeue-Medium", size: 19).monospacedDigit())
                .tracking(-0.19)                        // −0,01 em
                .foregroundColor(.texte)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(imminente ? Color.accent.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
        .opacity(passee ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: Formats — heure locale du téléphone, écriture des maquettes

    private static let formatJour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH'h'mm"
        return f
    }()

    /// « jeu. 24 sept. » → « Jeu. 24 sept » : le point final du mois fait doublon avec
    /// celui du jour (`formaterSeance` côté web).
    static func jour(_ date: Date) -> String {
        var texte = formatJour.string(from: date)
        if texte.hasSuffix(".") { texte.removeLast() }
        return texte.prefix(1).uppercased() + texte.dropFirst()
    }

    static func heure(_ date: Date) -> String { formatHeure.string(from: date) }
}

// MARK: - Une case de statistique

/// Le libellé est en `secondaire` (10,55:1 sur blanc) et non en `texteDoux` (2,85:1).
/// Aligné à gauche : quatre longueurs différentes centrées ne laissent aucune colonne.
private struct CaseStat: View {

    let libelle: String
    let valeur: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(libelle)
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .tracking(Tracking.label)
                .foregroundColor(.secondaire)

            Text(valeur)
                .font(.custom("HelveticaNeue-Medium", size: 22).monospacedDigit())
                .tracking(-0.44)
                .foregroundColor(.primaire)             // 12,21:1 sur blanc
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let detail {
                Text(detail)
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.secondaire)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carteSm, style: .continuous))
        .ombreCarte()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Une carte de vainqueur

/// Le millésime, la **vraie livrée** de l'écurie avec le numéro et le nom peints dessus, le
/// prénom, le nom, puis le pays précédé de son drapeau emoji.
///
/// **Fond blanc sur les six** (web `0.76.0`) : un palmarès est une liste d'égaux, et un fond
/// par nationalité y lisait une hiérarchie que la donnée ne porte pas. Les cartes ne sont
/// pas tapables — il n'y a rien derrière un palmarès.
private struct CarteVainqueur: View {

    let vainqueur: FichesGrandPrix.Vainqueur

    /// La voiture fait 112 pt de haut, comme côté web.
    private let hauteurVoiture: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(vainqueur.annee))
                .font(.labelSm)
                .tracking(Tracking.label)
                .foregroundColor(.secondaire)

            VueVoiture(livree: Livree(mode: .ecurie, ecurie: vainqueur.ecurie),
                       numero: String(vainqueur.numero),
                       nom: vainqueur.nom.uppercased())
                .frame(width: hauteurVoiture * VueVoiture.rapport, height: hauteurVoiture)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityHidden(true)

            Spacer().frame(height: 10)

            if !vainqueur.prenom.isEmpty {
                Text(vainqueur.prenom)
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.secondaire)
                    .lineLimit(1)
            }

            // Le nom de famille porte la reconnaissance : plus gros et plus gras.
            Text(vainqueur.nom)
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .foregroundColor(.texte)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            // Le glyphe hors de portée de la troncature : c'est la moitié de l'information.
            HStack(spacing: 4) {
                Text(vainqueur.emoji)
                    .font(.system(size: 13))
                    .fixedSize()
                    .accessibilityHidden(true)
                Text(vainqueur.pays)
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.secondaire)
                    .lineLimit(1)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
        .ombreCarte()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        DetailGPView(grandPrix: .init(slug: "azerbaidjan", pays: "Azerbaïdjan",
                                      nom: "GP Azerbaïdjan", circuit: "Bakou", jour: "26",
                                      mois: "SEPT", etat: .ouvert, date: "26 septembre 2026"))
    }
}
