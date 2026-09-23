import SwiftUI

/// Le refus d'une écriture, dit **sous le bloc qui l'a provoqué** — jamais dans une alerte
/// système.
///
/// Une alerte interrompt pour dire ce que l'écran peut dire en place : l'utilisateur la
/// ferme, puis doit se souvenir de ce qu'elle disait pour corriger son code ou son nom.
/// Ici le message reste visible pendant la correction, et s'efface à la première frappe.
///
/// **Le même bloc pour « Créer » et « Rejoindre »** : deux refus écrits séparément
/// n'auraient pas fini par dire la même chose de la même façon.
struct ErreurEnLigne: View {

    let erreur: ErreurAPI

    var body: some View {
        Text(erreur.message)
            .font(.corps)
            // L'encre primaire : c'est la seule chose de l'écran qui demande à être relue
            // avant de continuer. 9,61:1 sur le beige.
            .foregroundColor(.primaire)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityLabel("Erreur : \(erreur.message)")
    }
}
