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
            estConnecte = true
        } catch {
            // Pas de session valide — l'utilisateur verra l'écran de connexion.
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
            let _ = try await supabase.auth.signIn(
                email: email,
                password: motDePasse
            )
            estConnecte = true
        } catch {
            messageErreur = "Erreur de connexion : \(error.localizedDescription)"
        }
        
        estEnChargement = false
    }
    
    /// Déconnecte l'utilisateur actuel.
    func deconnexion() async {
        estEnChargement = true
        messageErreur = nil
        
        do {
            try await supabase.auth.signOut()
            estConnecte = false
        } catch {
            messageErreur = "Erreur lors de la déconnexion : \(error.localizedDescription)"
        }
        
        estEnChargement = false
    }
}
