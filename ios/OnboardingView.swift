import SwiftUI

/// Écran d'onboarding — un premier compte Google (ou Apple, une fois activé) n'a transmis
/// aucun pseudo ; `gerer_nouvel_utilisateur` en a fabriqué un provisoire
/// (`pilote-xxxxxxxxxx`, `docs/database.md`). Cet écran le remplace avant d'entrer dans le
/// reste de l'application — `GreedF1App` y bascule tant que
/// `AuthViewModel.pseudoAConfigurer` vaut vrai. Contrepartie exacte d'`Onboarding.jsx`.
///
/// **Pas de bouton retour** : il n'y a nulle part d'utile où revenir tant que le pseudo
/// n'est pas choisi, un retour ramènerait ici aussitôt. La seule sortie est la
/// déconnexion, offerte en pied d'écran.
struct OnboardingView: View {

    @ObservedObject var viewModel: AuthViewModel
    @State private var pseudo = ""

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 56)

                Text(t("onboarding.titre"))
                    .font(.custom("Helvetica Neue", size: 36))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)

                Text(t("onboarding.texte"))
                    .font(.custom("Helvetica Neue", size: 15))
                    .foregroundColor(.grisSecondaire)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                Spacer()
                    .frame(height: 32)

                // Card blanche avec le champ — même habillage que InscriptionView.
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("auth.pseudo"))
                        .font(.custom("Helvetica Neue", size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(.grisSecondaire)
                        .tracking(1)

                    TextField("MaxV33", text: $pseudo)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                        .font(.custom("Helvetica Neue", size: 16))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 0)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.3)),
                            alignment: .bottom
                        )
                }
                .padding(24)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
                .padding(.horizontal, 32)

                if let erreur = viewModel.messageErreur {
                    Text(erreur)
                        .font(.custom("Helvetica Neue", size: 14))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                }

                Spacer()
                    .frame(height: 32)

                Button {
                    Task {
                        await viewModel.definirPseudo(pseudo.trimmingCharacters(in: .whitespaces))
                    }
                } label: {
                    if viewModel.estEnChargement {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text(t("commun.continuer"))
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(Color.primaire)
                .cornerRadius(24)
                .disabled(viewModel.estEnChargement || pseudo.trimmingCharacters(in: .whitespaces).count < 2)
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    Task { await viewModel.deconnexion() }
                } label: {
                    Text(t("commun.seDeconnecter"))
                        .font(.custom("Helvetica Neue", size: 14))
                        .foregroundColor(.grisSecondaire)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    OnboardingView(viewModel: AuthViewModel())
}
