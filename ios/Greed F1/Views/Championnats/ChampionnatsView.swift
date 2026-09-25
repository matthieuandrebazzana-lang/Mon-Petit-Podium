import SwiftUI

/// Onglet **Championnats** — la liste de tous les championnats du joueur, et les deux
/// façons d'en avoir un de plus.
///
/// Référence visuelle : `Ressources/Screenshots/screen-06-championnats-haut.PNG` et
/// `screen-07-championnats-bas.PNG`.
///
/// > **Les données sont réelles** : ``MesChampionnats`` (`GET /championnats/moi`), la
/// > même instance que l'accueil.
///
/// **La carte est celle de l'accueil, pas une copie** : ``CarteChampionnat`` et
/// ``ActionsChampionnat`` vivent dans `Views/Composants/`, et les deux écrans montent la
/// même. C'est la règle « une source unique par question » du `CLAUDE.md` de la racine.
struct ChampionnatsView: View {

    /// Marge latérale commune à tous les écrans — la même que `AccueilView`, sans quoi les
    /// deux onglets ne s'aligneraient pas au passage de l'un à l'autre.
    private let margeLaterale: CGFloat = 16

    @ObservedObject var mesChampionnats: MesChampionnats

    /// Grands Prix restants — lus sur la liste de la saison, voir ``GPRestants``.
    private var grandsPrixRestants: Int { GPRestants.compte }

    /// **Le tri est l'effectif décroissant, jamais le rang du joueur.** Un championnat de
    /// huit membres est l'affaire principale même quand on y est huitième ; trier par rang
    /// remonterait en tête le championnat d'essai à un seul membre, où l'on est toujours
    /// premier.
    ///
    /// À effectif égal, le nom départage — sans quoi deux championnats de même taille
    /// échangeraient leur place au gré de l'ordre d'arrivée des données.
    private func tries(_ championnats: [Championnat]) -> [Championnat] {
        championnats.sorted {
            $0.nombreMembres == $1.nombreMembres
                ? $0.nom < $1.nom
                : $0.nombreMembres > $1.nombreMembres
        }
    }

    /// Le chemin du parcours de pronostics — voir ``EtapePronos``. **Le vider ramène au
    /// championnat**, pas à l'accueil : le détail d'un championnat est poussé hors de ce
    /// chemin, et reste donc en place. C'est pourquoi le libellé du retour diffère de
    /// celui de l'accueil.
    @State private var cheminPronos: [EtapePronos] = []

    var body: some View {
        NavigationStack(path: $cheminPronos) {
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        entete

                        Spacer().frame(height: 16)
                        liste

                        Spacer().frame(height: 10)
                        ActionsChampionnat(mesChampionnats: mesChampionnats)

                        Spacer().frame(height: 20)
                        blocSaison
                    }
                    .padding(.horizontal, margeLaterale)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            // Le titre de l'écran est dans le contenu, à 28 pt : la barre système ferait
            // doublon. Elle reste néanmoins **titrée**, parce que c'est ce titre que le
            // détail affiche à côté de son chevron de retour.
            .navigationTitle("Championnats")
            .toolbar(.hidden, for: .navigationBar)
            .etapesPronos(libelleRetour: "Championnat",
                          avancer: { cheminPronos.append($0) }) { cheminPronos.removeAll() }
            // Rechargée à chaque apparition, pas de cache de session (§7.6).
            .task { await mesChampionnats.charger() }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Championnats")
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)        // 15,37:1 sur le beige
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            // **`grisSecondaire` et non `texteDoux`.** La version web pose ici son
            // `#999999`, qui ne vaut que 2,52:1 sur le beige — sous le plancher de 4,5:1
            // d'un texte ordinaire. `#6B6B6B` y tient 4,71:1 pour un gris que l'œil ne
            // distingue pas du premier. Le contraste se mesure (`ios/CLAUDE.md` §3).
            Text(sousTitre)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Le décompte n'est dit qu'une fois la liste connue : « 0 championnat » pendant le
    /// chargement serait faux.
    private var sousTitre: String {
        guard case .pret(let liste) = mesChampionnats.etat else { return "Saison 2026" }
        return "\(liste.count) \(liste.count > 1 ? "championnats" : "championnat") · Saison 2026"
    }

    // MARK: - La liste

    /// `NavigationLink` et non `Button` : c'est lui qui porte le glissement d'écran natif
    /// et le geste de retour par le bord, qu'un `Button` poussant un état ne donne pas.
    private var liste: some View {
        EtatMesChampionnats(mesChampionnats: mesChampionnats) { championnats in
            VStack(spacing: 10) {
                ForEach(tries(championnats)) { championnat in
                    NavigationLink {
                        ChampionnatDetailView(championnat: championnat, mesChampionnats: mesChampionnats)
                    } label: {
                        CarteChampionnat(championnat: championnat)
                    }
                    .buttonStyle(StyleAppui(.grandeSurface))
                }
            }
        }
    }

    /// La ligne qui ferme l'écran, identique à celle de l'accueil.
    private var blocSaison: some View {
        Text(GPRestants.libelle(grandsPrixRestants))
            .font(.custom("HelveticaNeue-Medium", size: 13))
            .foregroundColor(.secondaire)       // 9,32:1 sur le beige
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    ChampionnatsView(mesChampionnats: MesChampionnats())
}
