import SwiftUI

/// **Mes résultats** d'un Grand Prix terminé — la destination de « Voir mes résultats → »
/// du widget de l'accueil.
///
/// **C'est le détail du carrousel du profil**, sans le héros : le drapeau flouté sur tout
/// l'écran (``FondDrapeauFlou``), puis ``ContenuDetailGrandPrix`` — l'en-tête (nom, date,
/// points, réussis sur tentés, « Provisoire ») et une carte par pronostic. Le même Grand
/// Prix ne se dessine pas de deux façons.
///
/// **Données** : ``GrandsPrixJoues`` restreint à ce seul GP, **résultats disponibles ou
/// non** — l'accueil dit la course terminée avant que le scraper n'ait jugé, et ses paris
/// s'affichent alors en attente.
///
/// **Rien joué, ou aucun championnat** (la route des paris en demande un) : le classement
/// officiel, comme avant (``ResultatsGPView``).
struct MesResultatsGPView: View {

    let grandPrix: GrandPrixPronos
    /// La date écrite du GP — celle du classement officiel, en repli.
    let date: String

    @StateObject private var donnees: GrandsPrixJoues

    init(grandPrix: GrandPrixPronos, date: String) {
        self.grandPrix = grandPrix
        self.date = date
        _donnees = StateObject(wrappedValue: GrandsPrixJoues(profilId: nil, championnatId: nil,
                                                             gpId: grandPrix.id))
    }

    var body: some View {
        // Un `ZStack` et non un `Group` : le `.task` ne doit partir qu'une fois.
        ZStack {
            switch donnees.etat {
            case .pret(let liste):
                if let gp = liste.first {
                    detail(gp)
                } else {
                    officiel
                }

            case .sansChampionnat:
                officiel

            case .chargement, .echec:
                attente
            }
        }
        .task { await donnees.charger() }
    }

    private func detail(_ gp: GrandsPrixJoues.GrandPrixJoue) -> some View {
        ZStack {
            FondDrapeauFlou(slug: gp.slugDrapeau)
            ContenuDetailGrandPrix(gp: gp)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(gp.slugDrapeau != nil ? .dark : nil, for: .navigationBar)
    }

    private var officiel: some View {
        ResultatsGPView(nom: grandPrix.nomAffiche, date: date, gpId: grandPrix.id)
    }

    /// Le premier chargement, ou son échec — les briques de ``EntreePronosView``.
    private var attente: some View {
        ZStack(alignment: .top) {
            Color.fondPrincipal
                .ignoresSafeArea()

            Group {
                if case .echec(let erreur) = donnees.etat {
                    EchecChargement(erreur: erreur) {
                        Task { await donnees.charger() }
                    }
                } else {
                    ChargementPronos()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
