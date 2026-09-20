import SwiftUI

/// Écran d'inscription : champs pseudo, email, mot de passe, bouton principal.
struct InscriptionView: View {
    
    @StateObject private var viewModel = AuthViewModel()
    @State private var pseudo = ""
    @State private var email = ""
    @State private var motDePasse = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Fond beige clair
            Color(red: 0xF5 / 255, green: 0xF0 / 255, blue: 0xEB / 255)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Logo ou titre
                Text("Greed F1")
                    .font(.custom("Helvetica Neue", size: 40))
                    .fontWeight(.bold)
                    .foregroundColor(.primaire)
                
                Text("Inscription")
                    .font(.custom("Helvetica Neue", size: 24))
                    .foregroundColor(.primary)
                
                // Champ pseudo
                TextField("Pseudo", text: $pseudo)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                // Champ email
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                // Champ mot de passe
                SecureField("Mot de passe", text: $motDePasse)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                // Message d'erreur
                if let erreur = viewModel.messageErreur {
                    Text(erreur)
                        .font(.custom("Helvetica Neue", size: 14))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Bouton d'inscription
                Button {
                    Task {
                        await viewModel.inscription(email: email, motDePasse: motDePasse, pseudo: pseudo)
                        // Si l'inscription réussit, revenir à l'écran de connexion
                        if viewModel.estConnecte {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.estEnChargement {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    } else {
                        Text("Créer mon compte")
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                }
                .background(Color.primaire)
                .cornerRadius(24)
                .disabled(viewModel.estEnChargement || pseudo.isEmpty || email.isEmpty || motDePasse.isEmpty)
                
                // Lien de retour
                Button {
                    dismiss()
                } label: {
                    Text("Déjà un compte ? **Se connecter**")
                        .font(.custom("Helvetica Neue", size: 16))
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    InscriptionView()
}
