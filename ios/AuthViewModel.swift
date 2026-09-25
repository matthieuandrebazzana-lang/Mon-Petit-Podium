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
    
    /// Le profil du compte connecté, lu **dans `public.profils`** — jamais dans les
    /// métadonnées du jeton, figées à l'inscription (`docs/swift-app.md` §3.9).
    /// `nil` tant qu'il n'a pas été lu, ou quand personne n'est connecté.
    @Published private(set) var profil: Profil?

    /// Pseudo du compte connecté. Vide tant que le profil n'a pas été lu.
    var pseudo: String { profil?.pseudo ?? "" }

    /// Photo de profil du compte connecté. `nil` quand le compte n'en a pas : l'écran
    /// retombe alors sur l'initiale, jamais sur un disque vide.
    var photoProfil: URL? { profil?.avatarUrl }

    /// Faut-il afficher la section d'administration ? **Relu à chaque chargement du
    /// profil, `false` à tout échec** : une section affichée à tort ne vaut rien, et ce
    /// drapeau décide d'un affichage, jamais d'un droit (`POST /admin/action` autorise).
    @Published private(set) var estAdmin = false

    /// L'interrupteur « Mode admin actif » du profil, **brut**. État de session : jamais
    /// persisté, il repart éteint à chaque lancement (`decisions.md` §15).
    @Published var modeAdminActif = false

    /// La prévisualisation des pronostics : `estAdmin && modeAdminActif`, **nommée une
    /// fois plutôt que recopiée** — une conjonction recopiée finit écrite à moitié. C'est
    /// elle, et jamais l'interrupteur brut, que lisent les écrans (``EnvironmentValues/modePrevisualisation``).
    /// Elle ne ment qu'à l'écran : aucune écriture, et le serveur refuse toujours un
    /// pronostic hors fenêtre (`423`).
    var modePrevisualisation: Bool { estAdmin && modeAdminActif }

    /// Message d'erreur à afficher sous le formulaire, ou `nil` si aucune erreur.
    @Published var messageErreur: String?
    
    private let supabase = SupabaseManager.partage.client
    
    init() {
        Task {
            await verifierSession()
        }
        Task { [weak self] in
            await self?.suivreDeconnexions()
        }
    }

    /// Une session peut se perdre ailleurs que par le bouton de déconnexion : un `401`
    /// de Railway la purge (``APIClient``), un rafraîchissement de jeton peut échouer.
    /// Supabase publie alors `signedOut`, et c'est ici — un seul propriétaire — que
    /// l'app revient à l'écran d'accueil non connecté.
    private func suivreDeconnexions() async {
        for await (evenement, _) in supabase.auth.authStateChanges
        where evenement == .signedOut {
            oublierCompte()
        }
    }
    
    /// Vérifie si une session existe déjà au lancement de l'app.
    func verifierSession() async {
        do {
            let session = try await supabase.auth.session
            estConnecte = true
            await chargerProfil(id: session.user.id)
        } catch {
            // Pas de session valide — l'utilisateur verra l'écran de connexion.
            oublierCompte()
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
            estConnecte = true
            await chargerProfil(id: session.user.id)
        } catch {
            messageErreur = "Erreur de connexion : \(error.localizedDescription)"
        }
        
        estEnChargement = false
    }
    
    /// (Re)lit le profil du compte connecté, en direct sous RLS — lecture que la
    /// politique « soi-même » décrit exactement, donc sans passer par Railway ni
    /// attendre son réveil. **Seul endroit qui le lit** : connexion, inscription et
    /// session au lancement passent toutes par ici.
    ///
    /// Deux sens du doute (§3.9) : un pseudo ou une photo **périmés** valent mieux que
    /// rien, donc un échec garde le profil déjà connu ; `is_admin`, lui, retombe
    /// **toujours** à `false`.
    func chargerProfil(id: UUID) async {
        do {
            let reponse = try await supabase
                .from("profils")
                .select(Profil.colonnes)
                .eq("id", value: id)
                .single()
                .execute()
            let lu = try JSONDecoder.api.decode(Profil.self, from: reponse.data)
            profil = lu
            estAdmin = lu.isAdmin
        } catch {
            estAdmin = false
        }
    }

    /// Relit le profil du compte connecté, s'il y en a un — après un changement de
    /// pseudo, de photo ou de voiture.
    func rechargerProfil() async {
        guard let id = try? await supabase.auth.session.user.id else { return }
        await chargerProfil(id: id)
    }

    /// Enregistre la voiture (`PATCH /profils/moi`), puis relit le profil. **C'est ce
    /// profil-ci que la piste et le classement peignent pour le compte connecté** — pas la
    /// ligne du classement, servie avant la modification : une seule source pour sa
    /// propre voiture, et elle se met à jour ici.
    ///
    /// La relecture passe par ``chargerProfil(id:)``, le seul lecteur du profil, plutôt
    /// que par la réponse du `PATCH` : `estAdmin` ne se décide qu'à un seul endroit.
    ///
    /// - Throws: une ``ErreurAPI`` dont le message est affichable (`422` : deux couleurs
    ///   identiques, numéro hors bornes…).
    func enregistrerVoiture(_ modification: ModificationVoiture) async throws {
        try await APIClient.partage.envoyer("profils/moi", methode: .patch, corps: modification)
        await rechargerProfil()
    }

    /// Change la photo de profil : dépôt direct dans Storage (``DepotPhoto``), puis l'URL
    /// par `PATCH /profils/moi`, puis relecture — même chemin que la voiture.
    ///
    /// **Le dossier est l'identifiant de la session**, jamais celui d'un profil en cache :
    /// la RLS du compartiment et le backend le comparent tous deux au jeton.
    ///
    /// - Throws: une ``ErreurAPI`` dont le message est affichable.
    func enregistrerPhoto(_ donnees: Data) async throws {
        guard let id = try? await supabase.auth.session.user.id else { throw ErreurAPI.session }
        let url = try await DepotPhoto.deposer(donnees, dans: .avatars, proprietaire: id.uuidString)
        try await APIClient.partage.envoyer("profils/moi", methode: .patch,
                                            corps: ModificationPhoto(avatarUrl: url))
        await rechargerProfil()
    }

    /// Efface tout ce qui appartient au compte (§2.6) : deux personnes qui se relaient
    /// sur le même téléphone ne voient jamais les données de l'autre.
    private func oublierCompte() {
        profil = nil
        estAdmin = false
        modeAdminActif = false
        estConnecte = false
    }
    
    /// Déconnecte l'utilisateur actuel.
    func deconnexion() async {
        estEnChargement = true
        messageErreur = nil
        
        do {
            try await supabase.auth.signOut()
            oublierCompte()
        } catch {
            messageErreur = "Erreur lors de la déconnexion : \(error.localizedDescription)"
        }
        
        estEnChargement = false
    }
}

// MARK: - Le profil connecté, vu par les écrans

/// Le profil du compte connecté, descendu par l'environnement depuis ``BarreNavigation``.
///
/// **Une clé, pas un `EnvironmentObject`** : `nil` par défaut, un écran monté hors de la
/// barre — un aperçu, une feuille — retombe sur ce que le serveur a servi au lieu de
/// s'arrêter net sur un objet absent.
private struct CleMonProfil: EnvironmentKey {
    static let defaultValue: Profil? = nil
}

/// La prévisualisation admin (``AuthViewModel/modePrevisualisation``), descendue de la
/// même façon : `false` hors de la barre, donc jamais allumée par accident dans un aperçu.
private struct CleModePrevisualisation: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var monProfil: Profil? {
        get { self[CleMonProfil.self] }
        set { self[CleMonProfil.self] = newValue }
    }

    var modePrevisualisation: Bool {
        get { self[CleModePrevisualisation.self] }
        set { self[CleModePrevisualisation.self] = newValue }
    }
}
