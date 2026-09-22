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
                        WidgetGrandPrixSuivant(nom: "GP Pays-Bas", echeance: "Fermeture dans 3 jours")

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
        .navigationTitle("")
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
                LigneClassement(membre: membre, total: membres.count)
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
    let echeance: String

    var body: some View {
        Button {
            // Destination à câbler : saisie des pronostics (`screen-25`).
        } label: {
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
private struct MembreMock: Identifiable {
    /// L'identifiant du compte. C'est de lui que se tire la teinte de l'avatar, jamais du
    /// rang : un membre qui perd une place ne change pas de couleur.
    let id: String
    let pseudo: String
    let points: Int
    let rang: Int
    /// Pronostics réussis sur la saison.
    let reussis: Int
    /// Le meilleur coup de la saison, en points. **Jamais une cote.**
    let meilleurCoup: Int

    /// Huit membres, repris de `screen-13` : de quoi remplir le plus grand des championnats
    /// mockés. Un championnat plus petit en prend le préfixe.
    static let exemples: [MembreMock] = [
        MembreMock(id: "nicolas", pseudo: "Nicolas", points: 168, rang: 1, reussis: 9, meilleurCoup: 42),
        MembreMock(id: "matthieu", pseudo: "Matthieu", points: 93, rang: 2, reussis: 5, meilleurCoup: 25),
        MembreMock(id: "7homas", pseudo: "7homas", points: 66, rang: 3, reussis: 4, meilleurCoup: 22),
        MembreMock(id: "clem1500", pseudo: "Clem1500", points: 50, rang: 4, reussis: 2, meilleurCoup: 25),
        MembreMock(id: "petiotte", pseudo: "Petiotte", points: 47, rang: 5, reussis: 2, meilleurCoup: 35),
        MembreMock(id: "camikaz", pseudo: "Camikaz", points: 26, rang: 6, reussis: 2, meilleurCoup: 14),
        MembreMock(id: "lucas", pseudo: "Lucas", points: 18, rang: 7, reussis: 1, meilleurCoup: 18),
        MembreMock(id: "julie", pseudo: "Julie", points: 12, rang: 8, reussis: 1, meilleurCoup: 12)
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
