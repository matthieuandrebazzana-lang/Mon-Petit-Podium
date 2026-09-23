import SwiftUI

/// Onglet **Accueil** — salutation, Grand Prix suivant, championnats, deux actions.
///
/// Référence visuelle : `Ressources/Screenshots/screen-04-accueil_haut.PNG` et
/// `screen-05-accueil-bas.PNG`, écran par écran.
///
/// > **Les données sont mockées.** Aucun appel réseau : ``GrandPrixMock`` et
/// > ``ChampionnatMock`` sont des valeurs en dur, reprises des captures pour que le rendu
/// > se compare à elles.
///
/// **Rien n'est dessiné en SwiftUI de ce qui existe en SVG** (`ios/CLAUDE.md` §3) : le
/// drapeau, le tracé du circuit, le damier et les deux logos d'action sont des assets,
/// extraits des planches par `ios/scripts/extraire-gp.mjs` et `decouper-icones.sh`.
struct AccueilView: View {

    @ObservedObject var viewModel: AuthViewModel

    /// Marge latérale commune à tous les blocs — la même que `LandingView`, sans quoi les
    /// deux écrans ne s'aligneraient pas au passage de l'un à l'autre.
    private let margeLaterale: CGFloat = 16

    // MARK: - Données mockées

    private let grandPrix = GrandPrixMock(
        slug: "azerbaidjan",
        nom: "GP Azerbaïdjan",
        date: "26 septembre 2026",
        heureDepart: "07h00",
        libelleEcheance: "Ouverture dans",
        echeance: "4j 14h 48min"
    )

    /// Les identifiants sont **stables** : c'est d'eux que se tire la teinte de la carte
    /// (`Color.teinteChampionnat(pour:)`), et un `UUID()` neuf à chaque lancement aurait
    /// fait changer la couleur d'un championnat d'une ouverture de l'app à la suivante.
    ///
    /// **La fraction de la jauge n'est pas le rang.** Elle dit où en est le membre par
    /// rapport au leader — c'est ce que la version web calcule à partir des points, et
    /// c'est pour cela qu'un premier sur trois remplit la barre entière.
    private let championnats: [ChampionnatMock] = [
        ChampionnatMock(id: "team-f1", nom: "Team F1", membres: 3, rang: 1, fraction: 1),
        ChampionnatMock(id: "team-bazzana", nom: "Team Bazzana", membres: 8, rang: 2, fraction: 0.55)
    ]

    /// Grands Prix restants — une **constante**, comme sur la version web : la base ne
    /// contient que les Grands Prix déjà relevés par le scraper, et les compter annoncerait
    /// « 1 Grand Prix restant » au milieu d'une saison qui en compte douze.
    private let grandsPrixRestants = 12

    /// Le chemin du parcours de pronostics — voir ``EtapePronos``.
    @State private var cheminPronos: [EtapePronos] = []

    var body: some View {
        // L'accueil est la **racine de sa propre pile** : c'est de ses deux cartes
        // d'action que part la création d'un championnat. Une pile par onglet, et non
        // une pile autour de la barre — sinon le retour ramènerait sur un autre onglet
        // que celui d'où l'on est parti.
        // Le chemin est **explicite** parce que le récapitulatif doit pouvoir revenir ici
        // d'un coup, trois écrans plus haut (``EtapePronos``). Les deux cartes d'action
        // gardent leurs `NavigationLink` classiques : elles n'ont rien à remonter.
        NavigationStack(path: $cheminPronos) {
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        entete

                        Spacer().frame(height: 12)
                        WidgetGrandPrix(grandPrix: grandPrix)

                        Spacer().frame(height: 24)   // changement de sujet : 24 pt (§4.6)
                        titreSection("Mes championnats")

                        Spacer().frame(height: 10)
                        listeChampionnats

                        Spacer().frame(height: 10)
                        actions

                        Spacer().frame(height: 20)
                        blocSaison

                        Spacer().frame(height: 28)
                        versionAffichee
                    }
                    .padding(.horizontal, margeLaterale)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            // Pas de titre : le bouton de retour des écrans poussés d'ici affiche alors le
            // « Retour » générique du système, comme la capture de référence.
            .toolbar(.hidden, for: .navigationBar)
            .etapesPronos(libelleRetour: "Accueil") { cheminPronos.removeAll() }
        }
    }

    // MARK: - En-tête

    /// Avatar seul sur la première rangée, salutation dessous : c'est la composition de la
    /// barre collante de la version web, dont le titre compact reste effacé tant que
    /// l'écran n'a pas défilé.
    private var entete: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Avatar(pseudo: pseudoAffiche, photo: viewModel.photoProfil)
            }
            .frame(height: 44)   // plancher tactile iOS : l'avatar mènera au profil

            Spacer().frame(height: 12)

            Text("Salut \(pseudoAffiche)")
                .font(.titreLg)
                .tracking(Tracking.titreLg)
                .foregroundColor(.texte)        // 15,37:1 sur le beige
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 4)

            // **`grisSecondaire` et non `texteDoux`.** La version web pose ici son
            // `#999999`, qui ne vaut que 2,52:1 sur le beige — sous le plancher de 4,5:1
            // d'un texte ordinaire. `#6B6B6B` y tient 4,71:1 pour un gris que l'œil ne
            // distingue pas du premier. Le contraste se mesure (`ios/CLAUDE.md` §3).
            Text("Saison 2026 · Formule 1")
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Repli sur « pilote » : une session peut être ouverte sans métadonnée `pseudo`
    /// (comptes créés avant que l'inscription ne la pose). Un écran ne montre jamais un
    /// trou à la place d'un nom.
    private var pseudoAffiche: String {
        viewModel.pseudo.isEmpty ? "pilote" : viewModel.pseudo
    }

    // MARK: - Sections

    /// Titre de section. **L'encre est `grisSecondaire` (#6B6B6B), pas `texteDoux`** : sur
    /// le beige `#F5F0EB` le premier mesure **4,71:1**, le second 2,52:1 — sous le plancher
    /// de 4,5:1 d'un texte de 11 pt.
    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listeChampionnats: some View {
        VStack(spacing: 10) {
            ForEach(championnats) { championnat in
                Button {
                    // Destination à câbler : classement du championnat (`screen-13`).
                } label: {
                    CarteChampionnat(championnat: championnat)
                }
                .buttonStyle(StyleAppui(.grandeSurface))
            }
        }
    }

    /// Les deux cartes d'action, dont la composition vit dans ``ActionsChampionnat``
    /// — la liste des championnats pose exactement le même bloc.
    private var actions: some View { ActionsChampionnat() }

    /// La ligne qui ferme l'écran. Elle répond à un vrai défaut de composition — sous une
    /// liste d'un ou deux championnats, le bas de l'écran restait vide sur toute sa moitié.
    private var blocSaison: some View {
        Text("Saison 2026 · \(grandsPrixRestants) Grands Prix restants")
            .font(.custom("HelveticaNeue-Medium", size: 13))
            .foregroundColor(.secondaire)       // 9,32:1 sur le beige
            .frame(maxWidth: .infinity)
    }

    private var versionAffichee: some View {
        Text("Version \(Bundle.main.versionAffichee)")
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Avatar

/// La pastille du compte : sa photo de profil, ou son initiale sur la teinte de la marque.
///
/// **Même diamètre dans les deux cas** — seul le contenu change, jamais la composition de
/// la barre. La photo est chargée par `AsyncImage` : tant qu'elle n'est pas là, c'est
/// l'initiale qui tient la place, et non un disque vide.
private struct Avatar: View {

    let pseudo: String
    let photo: URL?

    private let diametre: CGFloat = 44

    var body: some View {
        Group {
            if let photo {
                AsyncImage(url: photo) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initiale
                }
            } else {
                initiale
            }
        }
        .frame(width: diametre, height: diametre)
        .clipShape(Circle())
        .accessibilityLabel("Mon profil")
    }

    private var initiale: some View {
        Color.primaire
            .overlay {
                Text(pseudo.first.map { String($0).uppercased() } ?? "?")
                    .font(.custom("HelveticaNeue-Medium", size: 18))
                    .foregroundColor(.white)      // 10,88:1 sur #800111
            }
    }
}

// MARK: - Widget du prochain Grand Prix

/// La pièce maîtresse de l'écran d'entrée : le drapeau du pays hôte, le tracé de son
/// circuit, et deux cases de statut.
///
/// **L'ordre des calques est celui de la version web, et il ne se défait pas** : le
/// drapeau tout en bas · ``LueurHaute`` · le voile calculé · l'assombrissement uniforme ·
/// le contenu seul. Tout ce qui éclaircit passe SOUS le voile, sinon la garantie de 3:1
/// de ``ApparenceDrapeau`` n'en est plus une.
///
/// **L'assombrissement de 15 % porte sur tout le widget, jamais sur la seule bande du
/// tracé.** Sur un drapeau à bande répétée — les Pays-Bas, rouge / blanc / bleu — une
/// bande assombrie au milieu coupait la surface en deux : la bande du haut paraissait plus
/// vive que celle du bas, et l'œil lisait un défaut de calage plutôt qu'une intention.
private struct WidgetGrandPrix: View {

    let grandPrix: GrandPrixMock

    /// Hauteur de la bande du tracé. C'est la moitié du widget : la réduire ferait sauter
    /// l'accueil au moment précis où le joueur le regarde.
    private let hauteurTrace: CGFloat = 160

    /// Rembourrage intérieur. La bande du tracé l'annule pour toucher les deux bords.
    private let rembourrage: CGFloat = 20

    private var apparence: ApparenceDrapeau? { ApparenceDrapeau.pour(slug: grandPrix.slug) }

    var body: some View {
        // **Le widget EST le bouton « Pronostiquer » de l'accueil.** La version web pose un
        // bouton nommé à l'intérieur du bloc ; ici c'est le bloc entier qui mène au tableau
        // des cotes, et le libellé accessible ci-dessous le nomme. Un bouton dans un bouton
        // n'existe pas, et deux cibles empilées se disputeraient le doigt.
        //
        // La destination est celle de la version web : `/cotes`, jamais la saisie — on
        // ajoute ses paris bonus avant de pronostiquer, et un bouton qui sauterait cette
        // étape mentirait sur son libellé.
        NavigationLink(value: EtapePronos.cotes(
            nom: grandPrix.nom,
            slug: grandPrix.slug,
            sousTitre: "\(grandPrix.date) · Départ \(grandPrix.heureDepart)"
        )) {
            contenu
                .padding(rembourrage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { fond }
                .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
                .ombreAplat()
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Prochain Grand Prix, \(grandPrix.nom), le \(grandPrix.date). "
            + "Départ à \(grandPrix.heureDepart). "
            + "\(grandPrix.libelleEcheance) \(grandPrix.echeance)."
        )
        .accessibilityHint("Pronostiquer")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Les calques du fond

    @ViewBuilder private var fond: some View {
        if let apparence {
            ZStack {
                // **`scaledToFill` et non `scaledToFit`** : le drapeau couvre toute la
                // surface, rogné sur son plus grand côté, jamais déformé ni cerné de vide.
                // C'est le pendant exact d'`object-fit: cover`.
                Image("flag-\(grandPrix.slug)")
                    .resizable()
                    .scaledToFill()

                LueurHaute()
                Color.black.opacity(apparence.voile)
                Color.black.opacity(0.15)
            }
        } else {
            // Pays hors table : l'aplat de la marque, et aucun assombrissement — il n'a ni
            // bande ni rupture à corriger, le voiler ne ferait que l'éteindre.
            ZStack {
                Color.primaire
                LueurHaute()
            }
        }
    }

    // MARK: Le contenu

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            enTete

            Spacer().frame(height: 12)
            nomDuGrandPrix

            Spacer().frame(height: 16)
            bandeTrace

            Spacer().frame(height: 16)
            cases
        }
    }

    private var enTete: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Prochain GP")
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(apparence?.pastille ?? Color.white.opacity(0.20))
                .clipShape(Capsule())

            Spacer(minLength: 8)

            Text(grandPrix.date)
                .font(.custom(encreDouceGrasse ? "HelveticaNeue-Medium" : "HelveticaNeue", size: 11))
                .foregroundColor(encreDouce)
                .ombrePortee(apparence?.ombreNom ?? false)
                .lineLimit(1)
        }
    }

    /// Le nom du Grand Prix, **centré au-dessus de son circuit** : les deux se lisent alors
    /// comme un seul objet, titre et illustration. Un nom aligné à gauche au-dessus d'un
    /// dessin centré ne donnerait pas cela.
    ///
    /// 26 pt, avec le crénage négatif qu'/apple-design §15 impose au-delà de 24 : sans lui,
    /// les lettres d'un titre s'éloignent à mesure qu'il grandit.
    private var nomDuGrandPrix: some View {
        Text(grandPrix.nom)
            .font(.custom("HelveticaNeue-Medium", size: 26))
            .tracking(-0.52)                              // −0,02em × 26
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .ombrePortee(apparence?.ombreNom ?? false)
            .frame(maxWidth: .infinity)
    }

    /// La bande du tracé — le **vrai** circuit du pays hôte, extrait d'`assets/traces.svg`.
    ///
    /// Le rembourrage du widget est annulé : la bande touche les deux bords, ce qui en fait
    /// un registre horizontal de la composition plutôt qu'une image posée dans une marge.
    /// `scaledToFit` met chaque circuit à l'échelle dans cette boîte et le centre — Bakou,
    /// 3,4 fois plus large que haut, remplit la largeur ; Zandvoort, presque carré, remplit
    /// la hauteur. Chacun garde sa vraie forme au lieu d'être étiré.
    ///
    /// Le trait est à 60 % de blanc : sur les drapeaux clairs, une fois le voile et
    /// l'assombrissement posés dessous, il y tient **2,70:1** — c'est un élément décoratif,
    /// pas un porteur de sens, et le nom du Grand Prix dit déjà de quel circuit il s'agit.
    @ViewBuilder private var bandeTrace: some View {
        Image("trace-\(grandPrix.slug)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(.white.opacity(0.60))
            .frame(maxWidth: .infinity)
            .frame(height: hauteurTrace)
            .padding(.horizontal, -rembourrage)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Deux cases plutôt qu'une phrase : un chiffre posé sous son label se lit d'un coup
    /// d'œil, là où « Pronos ouverts · Fermeture dans 2j 14h 32min » demande de lire une
    /// ligne entière pour en extraire la même information.
    private var cases: some View {
        HStack(spacing: 8) {
            caseStatut(label: "Départ", valeur: grandPrix.heureDepart)
            caseStatut(label: grandPrix.libelleEcheance, valeur: grandPrix.echeance)
        }
    }

    /// Surface posée *à l'intérieur* du widget : rayon `champ`, donc **aucune ombre** (§4.7).
    private func caseStatut(label: String, valeur: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(encreDouce)
                .lineLimit(1)

            Text(valeur)
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(apparence?.surface ?? Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }

    private var encreDouce: Color { apparence?.encreDouce ?? .encreSecondaire }
    private var encreDouceGrasse: Bool { apparence?.encreDouceGrasse ?? false }
}

/// L'ombre portée du texte posé sur un drapeau à plusieurs bandes. Un seul propriétaire :
/// le nom du Grand Prix et sa date la reçoivent, et elles ne peuvent pas diverger.
private extension View {
    @ViewBuilder func ombrePortee(_ active: Bool) -> some View {
        if active {
            self.shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
        } else {
            self
        }
    }
}

// MARK: - Données mockées

/// Le Grand Prix suivant. Remplacé par le modèle du backend quand l'écran sera câblé ; la
/// date et le compte à rebours sont ici des textes, pas des `Date` — rien ne les calcule.
///
/// `slug` est la clé des deux assets — `flag-<slug>` et `trace-<slug>` — et celle de la
/// table des teintes. **Une seule normalisation pour les trois** : la faire deux fois
/// laisserait les tables se désynchroniser sur un libellé qu'Unibet aurait renommé.
private struct GrandPrixMock {
    let slug: String
    let nom: String
    let date: String
    let heureDepart: String
    /// « Ouverture dans » avant les qualifications, « Fermeture dans » après : la case ne
    /// choisit pas son échéance, elle la reçoit.
    let libelleEcheance: String
    let echeance: String
}

#Preview {
    AccueilView(viewModel: AuthViewModel())
}
