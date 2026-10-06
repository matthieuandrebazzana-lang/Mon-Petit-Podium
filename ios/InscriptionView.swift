import SwiftUI

/// Écran d'inscription — reproduit exactement screen-02-inscription.png.
///
/// Bouton retour, titre "Créer un compte", card blanche avec labels et champs
/// (pseudo, email, mot de passe), bouton principal, lien connexion.
struct InscriptionView: View {
    
    @ObservedObject var viewModel: AuthViewModel
    @State private var pseudo = ""
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
                    .foregroundColor(.encrePrimaire)
                }
                .padding(.leading, 32)
                .padding(.top, 16)
                
                Spacer()
                    .frame(height: 40)
                
                // Titre "Créer un compte"
                Text(t("inscription.titre"))
                    .font(.custom("Helvetica Neue", size: 36))
                    .fontWeight(.bold)
                    .foregroundColor(.texte)
                    .padding(.horizontal, 32)
                
                Spacer()
                    .frame(height: 32)
                
                // Card blanche avec les champs
                VStack(alignment: .leading, spacing: 20) {
                    // Champ PSEUDO
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("auth.pseudo"))
                            .font(.custom("Helvetica Neue", size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(.grisSecondaire)
                            .tracking(1)
                        
                        TextField("", text: $pseudo)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                            .font(.custom("Helvetica Neue", size: 16))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 0)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.grisSecondaire),
                                alignment: .bottom
                            )
                    }
                    
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
                                    .foregroundColor(.grisSecondaire),
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
                        
                        SecureField(t("inscription.motDePasseMin"), text: $motDePasse)
                            .textContentType(.newPassword)
                            .font(.custom("Helvetica Neue", size: 16))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 0)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.grisSecondaire),
                                alignment: .bottom
                            )
                    }
                }
                .padding(24)
                .background(Color.surface)
                .cornerRadius(16)
                .shadow(color: Color.encreOmbre.opacity(0.05), radius: 10, x: 0, y: 2)
                .padding(.horizontal, 32)
                
                // Message d'erreur
                if let erreur = viewModel.messageErreur {
                    Text(erreur)
                        .font(.custom("Helvetica Neue", size: 14))
                        .foregroundColor(.encrePrimaire)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                }
                
                Spacer()
                    .frame(height: 32)
                
                // Bouton "Créer mon compte"
                Button {
                    Task {
                        await viewModel.inscription(email: email, motDePasse: motDePasse, pseudo: pseudo)
                        // Si l'inscription réussit, revenir à l'écran précédent
                        if viewModel.estConnecte {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.estEnChargement {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .encreSurAplat))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text(t("inscription.creer"))
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(.encreSurAplat)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(Color.primaire)
                .cornerRadius(24)
                .disabled(viewModel.estEnChargement || pseudo.isEmpty || email.isEmpty || motDePasse.isEmpty)
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Lien "Déjà un compte ? Se connecter"
                NavigationLink {
                    ConnexionView(viewModel: viewModel)
                } label: {
                    Text(.init(t("inscription.dejaCompte")))
                        .font(.custom("Helvetica Neue", size: 16))
                        .foregroundColor(.texte)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    InscriptionView(viewModel: AuthViewModel())
}
