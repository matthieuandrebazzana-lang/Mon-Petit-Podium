import Foundation
import SwiftUI
import Supabase

/// Gère l'état d'authentification de l'application.
///
/// Vérifie la session au lancement, expose les actions de connexion/inscription/déconnexion,
/// et publie l'état utilisateur pour que la navigation racine bascule automatiquement.
@MainActor
final class AuthViewModel: ObservableObject {
    
    /// `true` si un utilisateur est connecté.
    @Published var estConnecte = false
    
    /// `true` pendant une opération réseau (connexion, inscription, déconnexion).
    @Published var estEnChargement = false
    
    /// Pseudo de l'utilisateur connecté — celui posé dans les métadonnées Supabase à
    /// l'inscription. Vide tant qu'aucune session n'est ouverte.
    @Published var pseudo = ""
    
    /// Photo de profil du compte connecté — l'URL publique de son objet dans Supabase
    /// Storage, telle que la métadonnée `avatar_url` la porte. `nil` quand le compte n'en a
    /// pas : l'écran retombe alors sur l'initiale, jamais sur un disque vide.
    @Published var photoProfil: URL?

    /// Message d'erreur à afficher sous le formulaire, ou `nil` si aucune erreur.
    @Published var messageErreur: String?
    
    private let supabase = SupabaseManager.partage.client
    
    init() {
        Task {
            await verifierSession()
        }
    }
    
    /// Vérifie si une session existe déjà au lancement de l'app.
    func verifierSession() async {
        do {
            let session = try await supabase.auth.session
            retenir(session.user)
            estConnecte = true
        } catch {
            // Pas de session valide — l'utilisateur verra l'écran de connexion.
            pseudo = ""
            photoProfil = nil
            estConnecte = false
        }
    }
    
    /// Inscrit un nouvel utilisateur avec email, mot de passe et pseudo.
    /// Le pseudo est stocké dans les métadonnées Supabase.
    func inscription(email: String, motDePasse: String, pseudo: String) async {
        estEnChargement = true
        messageErreur = nil
        
        do {
            let _ = try await supabase.auth.signUp(
                email: email,
                password: motDePasse,
                data: ["pseudo": .string(pseudo)]
            )
            // Inscription réussie — vérifier la session.
            await verifierSession()
        } catch {
            messageErreur = "Erreur lors de l'inscription : \(error.localizedDescription)"
        }
        
        estEnChargement = false
    }
    
    /// Connecte un utilisateur existant avec email et mot de passe.
    func connexion(email: String, motDePasse: String) async {
        estEnChargement = true
        messageErreur = nil
        
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: motDePasse
            )
            retenir(session.user)
            estConnecte = true
        } catch {
            messageErreur = "Erreur de connexion : \(error.localizedDescription)"
        }
        
        estEnChargement = false
    }
    
    /// Lit le pseudo d'un utilisateur Supabase. **Seul endroit qui le compose** : la
    /// connexion et la vérification de session en avaient besoin toutes les deux, et
    /// deux lectures écrites séparément auraient divergé au premier ajustement.
    ///
    /// Le repli sur la partie locale de l'adresse couvre les comptes créés avant que
    /// l'inscription ne pose la métadonnée `pseudo`.
    private func retenir(_ utilisateur: User) {
        pseudo = utilisateur.userMetadata["pseudo"]?.stringValue
            ?? utilisateur.email?.split(separator: "@").first.map(String.init)
            ?? ""
        photoProfil = utilisateur.userMetadata["avatar_url"]?.stringValue.flatMap(URL.init(string:))
    }
    
    /// Déconnecte l'utilisateur actuel.
    func deconnexion() async {
        estEnChargement = true
        messageErreur = nil
        
        do {
            try await supabase.auth.signOut()
            pseudo = ""
            photoProfil = nil
            estConnecte = false
        } catch {
            messageErreur = "Erreur lors de la déconnexion : \(error.localizedDescription)"
        }
        
        estEnChargement = false
    }
}
