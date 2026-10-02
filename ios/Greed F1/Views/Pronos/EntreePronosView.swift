import SwiftUI

/// **La porte d'entrée du parcours de pronostics** — elle ne dessine rien d'elle-même, elle
/// choisit le premier écran.
///
/// - Une grille est **déjà enregistrée** (vainqueur et podium en base, relus en direct
///   sous RLS) : le récapitulatif, dont « Modifier mes pronos » empile le parcours —
///   cotes, puis saisie.
/// - **Rien encore** : le tableau des cotes, comme avant.
///
/// **Après la course** (``dateResultats`` renseignée) : sa grille s'il en a une, sinon le
/// classement officiel (``ResultatsGPView``) — il n'y a plus de cotes à parcourir.
///
/// Le chargeur est **celui du tableau des cotes**, qu'elle lui passe : les cotes déjà lues
/// s'affichent sans second spinner.
struct EntreePronosView: View {

    let grandPrix: GrandPrixPronos
    let libelleRetour: String
    let avancer: (EtapePronos) -> Void
    let retour: () -> Void
    /// La date écrite du GP, **seulement après la course** — `nil` avant.
    let dateResultats: String?

    @StateObject private var donnees: DonneesPronostics

    /// Le premier écran, **décidé une fois**, au premier chargement réussi. Revenir de la
    /// saisie après un premier envoi ne doit pas escamoter sous le doigt le tableau des
    /// cotes d'où l'on était parti ; le récapitulatif, lui, se relit à chaque retour.
    @State private var recapDabord: Bool?

    init(grandPrix: GrandPrixPronos, libelleRetour: String,
         avancer: @escaping (EtapePronos) -> Void, retour: @escaping () -> Void,
         dateResultats: String? = nil) {
        self.grandPrix = grandPrix
        self.dateResultats = dateResultats
        self.libelleRetour = libelleRetour
        self.avancer = avancer
        self.retour = retour
        _donnees = StateObject(wrappedValue: DonneesPronostics(gpId: grandPrix.id,
                                                              avecMesPronostics: true))
    }

    var body: some View {
        // Un `ZStack` et non un `Group` : un `Group` distribuerait le `.task` à chacun de
        // ses enfants, et le relancerait à chaque changement d'écran.
        ZStack {
            switch recapDabord {
            case true?:
                if let lu = donnees.donnees, let grille = GrilleEnregistree(relue: lu) {
                    RecapView(grandPrix: grandPrix, grille: grille,
                              libelleRetour: libelleRetour, retour: retour,
                              modifier: { avancer(.cotes(grandPrix)) })
                } else {
                    attente
                }

            case false?:
                if let dateResultats {
                    ResultatsGPView(nom: grandPrix.nomAffiche, date: dateResultats, gpId: grandPrix.id)
                } else {
                    CotesView(grandPrix: grandPrix, donnees: donnees)
                }

            case nil:
                attente
            }
        }
        // Rechargé à chaque apparition — au retour de « Modifier mes pronos », le
        // récapitulatif montre la grille telle que la base la tient.
        .task { await charger() }
    }

    private func charger() async {
        await donnees.charger()
        if recapDabord == nil, let lu = donnees.donnees {
            recapDabord = GrilleEnregistree(relue: lu) != nil
        }
    }

    /// Le premier chargement, ou son échec — les mêmes briques que les trois écrans.
    private var attente: some View {
        ZStack(alignment: .top) {
            Color.fondPrincipal
                .ignoresSafeArea()

            Group {
                if case .echec(let erreur) = donnees.etat {
                    EchecChargement(erreur: erreur) {
                        Task { await charger() }
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
