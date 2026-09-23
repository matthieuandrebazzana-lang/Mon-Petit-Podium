import SwiftUI

/// Le détail d'un championnat : son classement, et la vue piste.
///
/// Références visuelles : `maquettes/maquette-07-championnat.html` pour la composition,
/// `Ressources/Screenshots/screen-13-classement-championnat.PNG` pour ce que la version web
/// en a finalement fait.
///
/// > **Les données sont mockées.** ``MembreMock`` porte des valeurs en dur ; aucun appel
/// > réseau ne part de cet écran.
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1) : « 168 pts », et
/// nulle part un « ×2,80 ».
struct ChampionnatDetailView: View {

    let championnat: ChampionnatMock

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    @State private var onglet: Onglet = .classement

    /// Les deux onglets. **Un `enum`, pas un `Int`** : l'index d'un segment ne dit pas ce
    /// qu'il montre, et l'écran finirait par comparer `== 1` quelque part.
    private enum Onglet: String, CaseIterable, Identifiable {
        case classement = "Classement"
        case piste = "Piste"

        var id: Self { self }
    }

    // MARK: - Données mockées

    /// Le classement, **déjà trié et rangé** — c'est ce que fait le serveur
    /// (`docs/swift-app.md` §5) et l'écran ne le retrie jamais.
    ///
    /// La liste est tronquée à l'effectif du championnat : un en-tête qui annonce huit
    /// membres au-dessus de six lignes est exactement le genre de défaut discret que le
    /// `CLAUDE.md` de la racine décrit.
    private var membres: [MembreMock] {
        Array(MembreMock.exemples.prefix(championnat.membres))
    }

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    entete

                    Spacer().frame(height: 16)
                    selecteur

                    Spacer().frame(height: 12)

                    switch onglet {
                    case .classement:
                        classement

                        Spacer().frame(height: 12)
                        WidgetGrandPrixSuivant(nom: "GP Pays-Bas", slug: "pays-bas",
                                               echeance: "Fermeture dans 3 jours")

                    case .piste:
                        piste
                    }
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        // Le nom du championnat est déjà dans le contenu, à 28 pt : le répéter dans la
        // barre ferait doublon. Elle ne garde donc que le chevron de retour natif, qui
        // porte le titre de l'écran précédent — « Championnats ».
        //
        // **Le titre est néanmoins posé, et masqué.** Un bouton de retour natif prend son
        // libellé du titre de l'écran d'où il vient : sans lui, le profil d'un membre
        // n'afficherait qu'un chevron nu. L'élément principal vide retire le texte de la
        // barre sans retirer le titre, là où `navigationTitle("")` aurait retiré les deux.
        //
        // > *Écart mesuré au simulateur (`CLAUDE.md` §6).* **Sous iOS 26, le libellé ne
        // > s'affiche de toute façon pas** : le Liquid Glass rend le bouton de retour en
        // > pastille de verre, chevron seul, quel que soit le titre — comme il reprend la
        // > main sur la barre d'onglets (`ios/CLAUDE.md` §3). Le titre reste posé pour
        // > **iOS 17 et 18**, la cible de déploiement, où le bouton l'affiche ; sans
        // > l'élément principal vide, ces deux versions gagneraient le libellé mais iOS 26
        // > hériterait d'un « Classement » centré en doublon du sélecteur juste dessous.
        .navigationTitle("Classement")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(championnat.nom)
                    .font(.titre)
                    .tracking(Tracking.titre)
                    .foregroundColor(.texte)        // 15,37:1 sur le beige
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // `grisSecondaire` (4,71:1) et non le `#999999` de la maquette (2,52:1).
                Text("\(championnat.membres) \(championnat.membres > 1 ? "membres" : "membre") · Saison 2026")
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.grisSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            menuChampionnat
        }
    }

    /// Les trois points. **Le menu est vide pour l'instant** — partager le code
    /// d'invitation, renommer et quitter viendront quand les routes seront câblées — mais
    /// la zone tactile fait déjà ses 44 × 44 pt : c'est le plancher iOS, et le rajouter
    /// après coup décalerait tout l'en-tête.
    private var menuChampionnat: some View {
        Button {
            // Destination à câbler : partager le code, renommer, quitter le championnat.
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.grisSecondaire)   // 4,71:1 sur le beige
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(StyleAppui(.bouton))
        .accessibilityLabel("Options du championnat")
        // L'icône est centrée sur 44 pt : sans ce décalage, le bouton dépasserait la marge
        // latérale à droite et le sommet du titre à gauche.
        .padding(.trailing, -10)
        .padding(.top, -6)
    }

    // MARK: - Le sélecteur

    /// Toggle segmenté. La pastille active **glisse** d'un segment à l'autre plutôt que
    /// d'apparaître à sa nouvelle place : c'est le seul indice qui dit *où* l'état est
    /// parti, et sans lui les deux onglets clignotent l'un dans l'autre.
    ///
    /// `Mouvement.deplacement` — la courbe des déplacements du design system, 0,22 s, sous
    /// le plafond de 300 ms. **Aucun ressort** : rien ici n'a été lancé au doigt, et un
    /// dépassement se lirait comme une erreur de calage.
    ///
    /// Sous `accessibilityReduceMotion`, la pastille change de place sans transition — le
    /// glissement est un déplacement, et c'est exactement ce que le réglage retire.
    private var selecteur: some View {
        HStack(spacing: 4) {
            ForEach(Onglet.allCases) { valeur in
                Button {
                    if mouvementReduit {
                        onglet = valeur
                    } else {
                        withAnimation(Mouvement.deplacement(0.22)) { onglet = valeur }
                    }
                } label: {
                    Text(valeur.rawValue)
                        .font(.custom("HelveticaNeue-Medium", size: 13))
                        .foregroundColor(onglet == valeur ? .white : .grisSecondaire)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if onglet == valeur {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primaire)
                                    .matchedGeometryEffect(id: "pastille", in: pastille)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(onglet == valeur ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.widget, style: .continuous))
        .ombreCarte()
    }

    @Namespace private var pastille
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    // MARK: - Onglet Classement

    /// Un seul bloc blanc, une ligne par membre.
    ///
    /// **Aucune règle horizontale entre les lignes** : le design system les proscrit
    /// (`docs/swift-app.md` §4.6, « jamais une règle horizontale »). Ce sont le filet de
    /// 4 pt posé *à l'intérieur* de chaque ligne — l'exception explicite de cette même
    /// section — et l'espace qui les séparent.
    private var classement: some View {
        VStack(spacing: 4) {
            ForEach(membres) { membre in
                // `NavigationLink` et non `Button` : c'est lui qui porte le glissement
                // d'écran natif et le geste de retour par le bord, qu'un `Button` poussant
                // un état ne donne pas.
                NavigationLink {
                    ProfilMembreView(membre: membre.profil)
                } label: {
                    LigneClassement(membre: membre, total: membres.count)
                }
                .buttonStyle(StyleAppui(.grandeSurface))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

    // MARK: - Onglet Piste

    /// L'écran d'attente de la vue piste (`screen-14`). Il **dit ce qui manque**, plutôt
    /// que de laisser un blanc qui se lirait comme un chargement en panne.
    private var piste: some View {
        VStack(spacing: 8) {
            Text("Vue piste")
                .font(.custom("HelveticaNeue-Medium", size: 17))
                .tracking(-0.34)
                .foregroundColor(.texte)

            Text("À venir")
                .font(.corpsSm)
                .foregroundColor(.secondaire)       // 9,32:1 sur le beige
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Une ligne du classement

/// Rang, avatar, nom, détail, score.
///
/// **Le sous-titre ne répète pas le score.** La maquette pose « 3 420 pts » sous le nom et
/// « 3420 » à droite : le même nombre deux fois, et la ligne n'apprend rien de plus. La
/// version web l'a tranché à l'usage (`screen-13`) en mettant là ce que le score ne dit
/// pas — les pronostics réussis et le meilleur coup. C'est cette version-là qui est reprise.
private struct LigneClassement: View {

    let membre: MembreMock
    let total: Int

    var body: some View {
        HStack(spacing: 12) {
            filet
            rang
            avatar

            VStack(alignment: .leading, spacing: 1) {
                Text(membre.pseudo)
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                    .foregroundColor(.texte)                 // 15,37:1 sur le blanc
                    .lineLimit(1)

                // `grisSecondaire` (5,33:1 sur le blanc) et non le `#999999` de la
                // maquette, qui n'y vaut que 2,85:1.
                Text("\(membre.reussis) réussis · meilleur coup \(membre.meilleurCoup) pts")
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundColor(.grisSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            score
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(minHeight: 44)                                // plancher tactile iOS
        // **La ligne entière est la cible**, pas ses seuls textes. Sans cela, le lien vers
        // le profil ne répondrait qu'au pseudo et au score, et l'intervalle entre les deux
        // lignes de texte — au milieu de la ligne, là où le doigt tombe — resterait mort.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(membre.rang)\(membre.rang == 1 ? "er" : "e") sur \(total), \(membre.pseudo), "
            + "\(membre.points) points, \(membre.reussis) pronostics réussis, "
            + "meilleur coup \(membre.meilleurCoup) points."
        )
    }

    /// Le filet de 4 pt — **l'exception explicite à l'interdiction des bordures fines**
    /// (`docs/swift-app.md` §4.6) : c'est un aplat posé à l'intérieur de la ligne, pas un
    /// trait qui la cerne. Il prend la teinte du membre, la même que son avatar, et c'est
    /// lui qui sépare deux lignes sans qu'aucune règle horizontale ne traverse le bloc.
    private var filet: some View {
        Capsule()
            .fill(Color.teinteAvatar(pour: membre.id))
            .frame(width: 4, height: 36)
            .accessibilityHidden(true)
    }

    /// **Le rouge de la marque pour les trois premiers, le gris pour les autres.** Le
    /// podium est la seule distinction que le classement général fait, et la couleur la
    /// dit sans ajouter un mot.
    ///
    /// `grisSecondaire` (5,33:1) et non le `#bbb` de la maquette, qui ne vaut que 2,0:1 sur
    /// le blanc — un chiffre n'est pas décoratif, il doit se lire.
    private var rang: some View {
        Text(String(membre.rang))
            .font(.custom("HelveticaNeue-Medium", size: 16))
            .foregroundColor(membre.rang <= 3 ? .primaire : .grisSecondaire)
            .frame(width: 20, alignment: .leading)
    }

    /// L'initiale sur la teinte du membre. La teinte se tire de son identifiant par
    /// ``Color/teinteAvatar(pour:)`` : elle est donc **stable d'un lancement à l'autre** et
    /// la même dans tous les championnats où il figure.
    private var avatar: some View {
        Circle()
            .fill(Color.teinteAvatar(pour: membre.id))
            .frame(width: 36, height: 36)
            .overlay {
                Text(membre.pseudo.first.map { String($0).uppercased() } ?? "?")
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                    .foregroundColor(.white)          // ≥ 10,35:1 sur les six teintes
            }
            .accessibilityHidden(true)
    }

    /// Le total, en rouge. **`PTS` sous le nombre, pas accolé à lui** : c'est l'unité, pas
    /// une partie du score, et la mettre sur la même ligne la ferait lire comme un chiffre
    /// de plus.
    private var score: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(String(membre.points))
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .tracking(-0.50)                              // −0,025em × 20
                .foregroundColor(.primaire)                   // 10,88:1 sur le blanc
                .lineLimit(1)

            Text("pts")
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)
        }
        .fixedSize()
    }
}

// MARK: - Le widget du Grand Prix suivant

/// L'aplat rouge qui ferme le classement : quel Grand Prix vient, quand il ferme, et le
/// bouton qui y mène.
///
/// **Le bouton NOMME sa destination** (`docs/swift-app.md` §7) — « Pronostiquer », jamais
/// « Continuer ».
private struct WidgetGrandPrixSuivant: View {

    let nom: String

    /// La clé des assets du pays hôte. Elle ne peint rien ici, elle **traverse** : c'est
    /// l'en-tête du récapitulatif, au bout du parcours, qui porte le drapeau.
    let slug: String

    let echeance: String

    var body: some View {
        // **La destination est le tableau des cotes, pas la saisie.** Le parcours passe par
        // les paris bonus avant les pronostics obligatoires : c'est ce que fait la version
        // web, et c'est ce que le mode d'emploi de `CotesView` annonce.
        NavigationLink(value: EtapePronos.cotes(nom: nom, slug: slug, sousTitre: echeance)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nom)
                        .font(.custom("HelveticaNeue-Medium", size: 16))
                        .foregroundColor(.white)              // 10,88:1 sur #800111
                        .lineLimit(1)

                    // **`encreSecondaire` (blanc à 70 %, 5,75:1) et non le blanc à 60 % de
                    // la maquette**, qui compose `#D9B3B8` sur le rouge — 4,47:1, sous le
                    // plancher de 4,5:1 d'un texte ordinaire.
                    Text(echeance)
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundColor(.encreSecondaire)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text("Pronostiquer")
                        .font(.custom("HelveticaNeue-Medium", size: 13))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.20))
                .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                // Aplat de la marque, galbé par la lumière spéculaire comme tous les
                // aplats de l'app. Pas de damier : le widget est une bande basse, et le
                // motif y passerait pour du bruit plutôt que pour une texture.
                ZStack {
                    Color.primaire
                    LueurHaute()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
            .ombreAplat()                                     // aplat de couleur (§4.7)
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pronostiquer pour le \(nom). \(echeance).")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Données mockées

/// Un membre du classement. `points` est un **entier**, et c'est déjà le nombre de points :
/// `CLAUDE.md` §3.1 — une cote de 2,80 vaut 28 points, et rien en base ne stocke une cote.
///
/// **Le type n'est pas `private`** : c'est lui qui alimente ``ProfilMembreView``, et un
/// second jeu de valeurs mockées pour le profil aurait fait dire deux choses différentes du
/// même membre — un meilleur coup au classement, un autre sur sa fiche.
struct MembreMock: Identifiable {
    /// L'identifiant du compte. C'est de lui que se tire la teinte de l'avatar, jamais du
    /// rang : un membre qui perd une place ne change pas de couleur.
    let id: String
    let pseudo: String
    let points: Int
    let rang: Int
    /// Pronostics réussis sur la saison.
    let reussis: Int
    /// Pronostics **tentés** sur la saison — obligatoires et bonus confondus. C'est le
    /// dénominateur de « Paris gagnés », et il est mocké plutôt que calculé : le nombre de
    /// paris par Grand Prix dépend des bonus retenus, que rien ici ne connaît.
    let tentes: Int
    /// Le meilleur coup de la saison, en points. **Jamais une cote.**
    let meilleurCoup: Int
    /// Grands Prix joués cette saison. C'est le diviseur de « Pts moy. / GP ».
    let grandsPrixJoues: Int
    /// La moyenne des paris tentés, **en points** — c'est ce que la tuile « Cote moy.
    /// tentée » affiche, et le mot « cote » n'y est qu'un libellé hérité de la version web :
    /// la valeur est un entier de points (`CLAUDE.md` §3.1).
    let moyenneTentee: Int
    /// Ce que porte sa voiture, et le numéro peint sur son museau.
    let livree: Livree
    let numero: String

    /// Le profil tel que ``ProfilMembreView`` l'attend. **Les quatre statistiques sont
    /// mises en forme ici**, à côté des chiffres bruts dont elles sortent : l'écran qui les
    /// affiche n'est alors jamais celui qui décide de leur arrondi.
    var profil: MembreProfil {
        MembreProfil(
            identifiant: id,
            pseudo: pseudo,
            livree: livree,
            numero: numero,
            grandsPrixJoues: grandsPrixJoues,
            statistiques: [
                StatistiqueProfil(valeur: "\(pourcentageReussite)%", libelle: "Paris gagnés"),
                StatistiqueProfil(valeur: String(pointsMoyensParGrandPrix), libelle: "Pts moy. / GP"),
                StatistiqueProfil(valeur: String(meilleurCoup), libelle: "Meilleur coup"),
                StatistiqueProfil(valeur: String(moyenneTentee), libelle: "Cote moy. tentée")
            ]
        )
    }

    /// Zéro pari tenté ne fait pas 0 % mais **rien à dire** : `NULL` et `0` ne se confondent
    /// jamais (`CLAUDE.md` §3.1), et une saison pas encore commencée n'est pas une saison
    /// ratée.
    private var pourcentageReussite: Int {
        tentes > 0 ? Int((Double(reussis) / Double(tentes) * 100).rounded()) : 0
    }

    private var pointsMoyensParGrandPrix: Int {
        grandsPrixJoues > 0 ? Int((Double(points) / Double(grandsPrixJoues)).rounded()) : 0
    }

    /// Huit membres, repris de `screen-13` : de quoi remplir le plus grand des championnats
    /// mockés. Un championnat plus petit en prend le préfixe.
    ///
    /// **Les valeurs de Matthieu et de 7homas sont celles des captures** — `screen-20`
    /// pour le premier (33 %, 31, 25, 46), `screen-22` pour le second (40 %, 33, 22, 41) —
    /// et elles tombent juste parce que les chiffres bruts les redonnent : 66 points en
    /// 2 Grands Prix font bien 33, et 4 réussis sur 10 tentés font bien 40 %.
    static let exemples: [MembreMock] = [
        MembreMock(id: "nicolas", pseudo: "Nicolas", points: 168, rang: 1,
                   reussis: 9, tentes: 25, meilleurCoup: 42,
                   grandsPrixJoues: 5, moyenneTentee: 38,
                   livree: Livree(mode: .perso, coque: "#CC0000", ailerons: "#FFFFFF"),
                   numero: "1"),
        MembreMock(id: "matthieu", pseudo: "Matthieu", points: 93, rang: 2,
                   reussis: 5, tentes: 15, meilleurCoup: 25,
                   grandsPrixJoues: 3, moyenneTentee: 46,
                   livree: Livree(mode: .perso, coque: "#CC0000", ailerons: "#003087",
                                  couleurTexte: "#00D2BE"),
                   numero: "33"),
        MembreMock(id: "7homas", pseudo: "7homas", points: 66, rang: 3,
                   reussis: 4, tentes: 10, meilleurCoup: 22,
                   grandsPrixJoues: 2, moyenneTentee: 41,
                   livree: Livree(mode: .perso, coque: "#2D2D2D", ailerons: "#00A19C",
                                  couleurTexte: "#00D2BE"),
                   numero: "44"),
        MembreMock(id: "clem1500", pseudo: "Clem1500", points: 50, rang: 4,
                   reussis: 2, tentes: 10, meilleurCoup: 25,
                   grandsPrixJoues: 2, moyenneTentee: 33,
                   livree: Livree(mode: .perso, coque: "#E8027B", ailerons: "#FFFFFF"),
                   numero: "27"),
        MembreMock(id: "petiotte", pseudo: "Petiotte", points: 47, rang: 5,
                   reussis: 2, tentes: 10, meilleurCoup: 35,
                   grandsPrixJoues: 2, moyenneTentee: 39,
                   livree: Livree(mode: .perso, coque: "#003087", ailerons: "#FFD700"),
                   numero: "10"),
        MembreMock(id: "camikaz", pseudo: "Camikaz", points: 26, rang: 6,
                   reussis: 2, tentes: 10, meilleurCoup: 14,
                   grandsPrixJoues: 2, moyenneTentee: 22,
                   livree: Livree(mode: .ecurie, ecurie: "mclaren"),
                   numero: "7"),
        MembreMock(id: "lucas", pseudo: "Lucas", points: 18, rang: 7,
                   reussis: 1, tentes: 5, meilleurCoup: 18,
                   grandsPrixJoues: 1, moyenneTentee: 26,
                   livree: Livree(mode: .perso, coque: "#FF8000", ailerons: "#000000"),
                   numero: "81"),
        MembreMock(id: "julie", pseudo: "Julie", points: 12, rang: 8,
                   reussis: 1, tentes: 5, meilleurCoup: 12,
                   grandsPrixJoues: 1, moyenneTentee: 19,
                   livree: Livree(mode: .perso, coque: "#960064", ailerons: "#C0C0C0"),
                   numero: "22")
    ]
}

#Preview {
    NavigationStack {
        ChampionnatDetailView(
            championnat: ChampionnatMock(
                id: "team-bazzana", nom: "Team Bazzana", membres: 8, rang: 2, fraction: 0.55
            )
        )
    }
}
