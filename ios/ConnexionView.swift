import SwiftUI

/// Écran de connexion — reproduit exactement screen-03-connexion.png.
///
/// Bouton retour, titre "Bon retour !", card blanche avec labels et champs,
/// lien "Mot de passe oublié ?", bouton principal, lien inscription.
struct ConnexionView: View {
    
    @ObservedObject var viewModel: AuthViewModel
    @State private var email = ""
    @State private var motDePasse = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Fond beige clair
            Color.fondPrincipal
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Bouton retour en haut à gauche
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(t("commun.retour"))
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.primaire)
                }
                .padding(.leading, 32)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    SelecteurLangue()
                        .padding(.trailing, 32)
                        .padding(.top, 16)
                }
                
                Spacer()
                    .frame(height: 40)
                
                // Titre "Bon retour !"
                Text(t("connexion.titre"))
                    .font(.custom("Helvetica Neue", size: 36))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                
                Spacer()
                    .frame(height: 32)
                
                // Card blanche avec les champs
                VStack(alignment: .leading, spacing: 20) {
                    // Champ EMAIL
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("auth.email"))
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(.grisSecondaire)
                            .tracking(1)
                        
                        TextField("", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
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
                    
                    // Champ MOT DE PASSE
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("auth.motDePasse"))
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(.grisSecondaire)
                            .tracking(1)
                        
                        SecureField("", text: $motDePasse)
                            .textContentType(.password)
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
                    
                    // Lien "Mot de passe oublié ?"
                    HStack {
                        Spacer()
                        Button {
                            // TODO: Navigation vers reset password
                        } label: {
                            Text(t("connexion.oublie"))
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.primaire)
                        }
                    }
                }
                .padding(24)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
                .padding(.horizontal, 32)
                
                // Message d'erreur
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
                
                // Bouton "Se connecter"
                Button {
                    Task {
                        await viewModel.connexion(email: email, motDePasse: motDePasse)
                    }
                } label: {
                    if viewModel.estEnChargement {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text(t("connexion.seConnecter"))
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(Color.primaire)
                .cornerRadius(24)
                .disabled(viewModel.estEnChargement || email.isEmpty || motDePasse.isEmpty)
                .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 24)

                // Séparateur puis Apple et Google — même ordre que Connexion.jsx (`BoutonsOAuth`,
                // ordre par défaut) : le séparateur annonce ce bouton-ci, posé après le
                // formulaire email/mot de passe.
                HStack(spacing: 10) {
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
                    Text(t("connexion.ouContinuer"))
                        .font(.custom("Helvetica Neue", size: 13))
                        .foregroundColor(.grisSecondaire)
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
                }
                .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 16)

                BoutonApple(viewModel: viewModel, rayon: 24)
                    .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 12)

                Button {
                    Task { await viewModel.connexionOAuth(fournisseur: .google) }
                } label: {
                    HStack(spacing: 10) {
                        Image("icone-google")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text(t("auth.google"))
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .background(Color.white)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
                .disabled(viewModel.estEnChargement)
                .padding(.horizontal, 32)

                Spacer()

                // Lien "Pas encore de compte ? S'inscrire"
                NavigationLink {
                    InscriptionView(viewModel: viewModel)
                } label: {
                    Text(.init(t("connexion.pasDeCompte")))
                        .font(.custom("Helvetica Neue", size: 16))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    ConnexionView(viewModel: AuthViewModel())
}
