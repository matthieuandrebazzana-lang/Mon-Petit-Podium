import SwiftUI

/// Gabarit d'un onglet pas encore construit : le fond de l'app, son titre, rien d'autre.
///
/// Un seul propriétaire pour les quatre écrans en attente — quatre copies de la même
/// pile de police auraient divergé au premier ajustement. Chaque onglet remplace son
/// appel par son vrai contenu au fur et à mesure.
struct EcranProvisoire: View {

    let titre: String

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            Text(titre)
                // `text-titre` : 28 px, graisse 500, crénage −0,02em → −0,56 pt.
                .font(.custom("HelveticaNeue-Medium", size: 28))
                .kerning(-0.56)
                .foregroundStyle(Color.texte)
        }
    }
}

#Preview {
    EcranProvisoire(titre: t("onglet.accueil"))
}
