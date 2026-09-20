import SwiftUI

/// Écran de connexion : champs email et mot de passe, bouton principal, lien vers l'inscription.
struct ConnexionView: View {
    
    @StateObject private var viewModel = AuthViewModel()
    @State private var email = ""
    @State private var motDePasse = ""
    
    var body: some View {
        NavigationStack {
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
                    
                    Text("Connexion")
                        .font(.custom("Helvetica Neue", size: 24))
                        .foregroundColor(.primary)
                    
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
                        .textContentType(.password)
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
                    
                    // Bouton de connexion
                    Button {
                        Task {
                            await viewModel.connexion(email: email, motDePasse: motDePasse)
                        }
                    } label: {
                        if viewModel.estEnChargement {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text("Se connecter")
                                .font(.custom("Helvetica Neue", size: 18))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .background(Color.primaire)
                    .cornerRadius(24)
                    .disabled(viewModel.estEnChargement || email.isEmpty || motDePasse.isEmpty)
                    
                    // Lien vers l'inscription
                    NavigationLink {
                        InscriptionView()
                    } label: {
                        Text("Pas encore de compte ? **Créer un compte**")
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
}

#Preview {
    ConnexionView()
}
