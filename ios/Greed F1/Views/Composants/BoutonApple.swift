import AuthenticationServices
import SwiftUI

/// « Continuer avec Apple » — le bouton **natif** (`SignInWithAppleButton`, la forme
/// SwiftUI d'`ASAuthorizationAppleIDButton`), jamais redessiné : sa forme, son logo et
/// son libellé appartiennent à Apple (Human Interface Guidelines), et la revue App Store
/// les vérifie.
///
/// **Noir sur fond clair, blanc sur fond sombre** — ce qu'Apple prescrit pour chacun
/// (`fondPrincipal` beige, ou `#1C1C1E` en mode sombre, où un bouton noir disparaîtrait).
/// Le bouton natif ne relit pas son style quand l'apparence change : l'`id` le reconstruit. Même hauteur (56 pt) et même rayon
/// que le bouton Google voisin, passé par l'écran — les deux ne divergent pas.
///
/// Son libellé suit la langue du **système**, pas celle du ``SelecteurLangue`` : le
/// bouton natif ne se traduit pas de l'extérieur.
struct BoutonApple: View {

    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.colorScheme) private var schema
    /// Le rayon du bouton Google posé à côté.
    let rayon: CGFloat

    var body: some View {
        SignInWithAppleButton(.continue) { requete in
            viewModel.preparerRequeteApple(requete)
        } onCompletion: { resultat in
            Task { await viewModel.connexionApple(resultat) }
        }
        .signInWithAppleButtonStyle(schema == .dark ? .white : .black)
        .id(schema)
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
        .disabled(viewModel.estEnChargement)
    }
}
