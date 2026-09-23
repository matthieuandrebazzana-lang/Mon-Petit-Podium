import SwiftUI

extension View {

    /// L'habillage du bouton qui clôt « Créer » et « Rejoindre » — **le même bouton à deux
    /// endroits**, donc un seul propriétaire.
    ///
    /// Éteint, il garde sa forme et sa place : le marron `secondaire` à 22 % sur le beige
    /// donne `#D2C8BF`, où la même encre pleine tient **6,42:1** — un bouton éteint reste
    /// lisible, sans quoi on ne sait pas ce qu'on attend de nous.
    func habillageBoutonPrincipal(actif: Bool) -> some View {
        self
            .font(.custom("HelveticaNeue-Medium", size: 18))
            .foregroundColor(actif ? .white : .secondaire)
            .frame(maxWidth: .infinity)
            .frame(height: 56)              // > 44 pt, contrainte tactile iOS
            .background(actif ? Color.primaire : Color.secondaire.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
    }
}
