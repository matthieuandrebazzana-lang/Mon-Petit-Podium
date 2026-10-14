import AuthenticationServices
import CryptoKit
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

    /// Faut-il envoyer ce compte choisir un pseudo avant d'entrer dans l'app ?
    ///
    /// Vrai quand le pseudo lu en base est celui que `gerer_nouvel_utilisateur` fabrique
    /// faute d'un pseudo transmis (`pilote-xxxxxxxxxx`, Google et Apple n'en envoient
    /// jamais) — contrepartie exacte de `pseudoAConfigurer` côté web
    /// (`lib/profils.js pseudoGenere`, `docs/database.md`). Calculé sur `profil`, jamais
    /// sur le jeton, qui ne porte aucune copie de cette valeur.
    var pseudoAConfigurer: Bool {
        profil?.pseudo.hasPrefix("pilote-") ?? false
    }
    
    private let supabase = SupabaseManager.partage.client

    /// Le nonce **en clair** de la demande Apple en cours. Apple reçoit son empreinte
    /// SHA-256 et la recopie dans le jeton d'identité ; Supabase reçoit le clair et
    /// vérifie qu'ils correspondent — un jeton intercepté ne se rejoue pas.
    private var nonceApple: String?
    
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
            messageErreur = t("auth.erreur.inscription", error.localizedDescription)
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
            messageErreur = t("auth.erreur.connexion", error.localizedDescription)
        }
        
        estEnChargement = false
    }

    /// Connecte via un fournisseur tiers **web** — Google. Apple passe par la feuille
    /// native, voir ``connexionApple(_:)``.
    ///
    /// Ouvre le navigateur système via `ASWebAuthenticationSession`, le chemin recommandé
    /// sur iOS (`docs/swift-app.md` §2.7) : `supabase-swift` la pilote lui-même derrière
    /// cette surcharge de `signInWithOAuth`, jusqu'à consommer le jeton PKCE au retour.
    /// Le schéma `greedf1://auth-callback` doit être déclaré dans `Info.plist`
    /// (`CFBundleURLTypes`) et dans les *Redirect URLs* du tableau de bord Supabase.
    func connexionOAuth(fournisseur: Provider) async {
        estEnChargement = true
        messageErreur = nil

        do {
            let session = try await supabase.auth.signInWithOAuth(
                provider: fournisseur,
                redirectTo: URL(string: "greedf1://auth-callback")
            )
            estConnecte = true
            await chargerProfil(id: session.user.id)
        } catch let erreur as NSError
            where erreur.domain == ASWebAuthenticationSessionErrorDomain
                && erreur.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            // L'utilisateur a fermé la fenêtre de connexion : ni erreur, ni action.
        } catch {
            messageErreur = t("auth.erreur.oauth")
        }

        estEnChargement = false
    }

    // MARK: - Sign in with Apple

    /// Remplit la demande que le bouton natif s'apprête à présenter : nom et email
    /// demandés, nonce haché. Appelée par ``BoutonApple`` juste avant la feuille.
    func preparerRequeteApple(_ requete: ASAuthorizationAppleIDRequest) {
        let nonce = Self.nonceAleatoire()
        nonceApple = nonce
        requete.requestedScopes = [.fullName, .email]
        requete.nonce = Self.sha256(nonce)
    }

    /// Connecte avec Sign in with Apple : **la feuille native, puis Supabase directement**
    /// (`signInWithIdToken`, fournisseur `.apple`) — aucune route Railway, Supabase valide
    /// lui-même le jeton d'identité contre les clés publiques d'Apple. Le bundle identifier
    /// doit figurer dans les *Client IDs* du fournisseur Apple du tableau de bord Supabase.
    ///
    /// Un premier compte reçoit un pseudo `pilote-…` du trigger, comme Google :
    /// ``pseudoAConfigurer`` l'envoie alors à l'onboarding, rien à câbler de plus.
    ///
    /// **Apple ne donne le nom qu'à la toute première autorisation**, jamais ensuite :
    /// il est donc écrit aussitôt dans les métadonnées du compte, sous les clés que Google
    /// y pose déjà (`full_name`, `name`). L'email, lui, est dans le jeton à chaque fois, et
    /// Supabase le range seul.
    func connexionApple(_ resultat: Result<ASAuthorization, Error>) async {
        messageErreur = nil

        let autorisation: ASAuthorization
        switch resultat {
        case .success(let reussite):
            autorisation = reussite
        case .failure(let erreur as ASAuthorizationError) where erreur.code == .canceled:
            // Feuille fermée par l'utilisateur : ni erreur, ni action.
            return
        case .failure:
            messageErreur = t("auth.erreur.oauth")
            return
        }

        guard let identifiant = autorisation.credential as? ASAuthorizationAppleIDCredential,
              let donneesJeton = identifiant.identityToken,
              let jeton = String(data: donneesJeton, encoding: .utf8),
              let nonce = nonceApple
        else {
            messageErreur = t("auth.erreur.oauth")
            return
        }

        estEnChargement = true
        defer { estEnChargement = false }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: jeton, nonce: nonce)
            )
            nonceApple = nil
            estConnecte = true

            if let nom = identifiant.fullName,
               case let complet = PersonNameComponentsFormatter().string(from: nom),
               !complet.isEmpty {
                var donnees: [String: AnyJSON] = ["full_name": .string(complet), "name": .string(complet)]
                if let prenom = nom.givenName { donnees["given_name"] = .string(prenom) }
                if let famille = nom.familyName { donnees["family_name"] = .string(famille) }
                // Un échec ici ne doit pas défaire la connexion : le nom n'est qu'un
                // complément, le compte existe.
                _ = try? await supabase.auth.update(user: UserAttributes(data: donnees))
            }

            await chargerProfil(id: session.user.id)
        } catch {
            messageErreur = t("auth.erreur.oauth")
        }
    }

    /// Le compte connecté s'est-il créé ou lié par Apple ?
    private func compteApple() async -> Bool {
        guard let identites = try? await supabase.auth.session.user.identities else { return false }
        return identites.contains { $0.provider == "apple" }
    }

    private static func nonceAleatoire(longueur: Int = 32) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generateur = SystemRandomNumberGenerator()
        return String((0..<longueur).map { _ in alphabet.randomElement(using: &generateur)! })
    }

    private static func sha256(_ texte: String) -> String {
        SHA256.hash(data: Data(texte.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Enregistre le pseudo choisi à l'onboarding — écriture **directe** dans
    /// `public.profils`, jamais par Railway : la colonne `pseudo` fait partie des huit
    /// ouvertes à `authenticated` par la migration 21 (`docs/database.md`), sous la
    /// politique « Chacun modifie son profil ». Contrepartie exacte de
    /// `AuthContexte.definirPseudo` côté web, jusqu'au code d'erreur `23505` traduit en
    /// « pseudo déjà pris ».
    ///
    /// - Returns: `true` si l'enregistrement a réussi.
    @discardableResult
    func definirPseudo(_ pseudo: String) async -> Bool {
        estEnChargement = true
        messageErreur = nil

        guard let id = try? await supabase.auth.session.user.id else {
            messageErreur = t("auth.erreur.session")
            estEnChargement = false
            return false
        }

        do {
            try await supabase
                .from("profils")
                .update(["pseudo": pseudo])
                .eq("id", value: id)
                .execute()
            await chargerProfil(id: id)
            estEnChargement = false
            return true
        } catch let erreur as PostgrestError where erreur.code == "23505" {
            messageErreur = t("auth.erreur.pseudoPris")
        } catch {
            messageErreur = t("commun.erreurGenerique")
        }

        estEnChargement = false
        return false
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
        CacheService.partage.vider()
        // Le widget « Classement » perd son jeton et ses données avec le compte.
        SynchroWidgetClassement.effacer()
        profil = nil
        estAdmin = false
        modeAdminActif = false
        estConnecte = false
    }
    
    /// Supprime le compte de l'appelant — App Store, règle 5.1.1(v).
    ///
    /// **Le serveur fait tout** (`DELETE /profils/moi`) : championnats créés
    /// transférés au membre le mieux classé ou éteints s'il était seul (règle
    /// 4.6), pronostics et photo de profil effacés, puis le compte Supabase
    /// Auth lui-même. Cette fonction n'a donc plus qu'à vider la session
    /// locale — `signOut()` ignore déjà un `401`/`403`/`404` sur son propre
    /// appel (le compte n'existe plus), exactement comme après une
    /// déconnexion ordinaire.
    ///
    /// **Un compte Apple redemande d'abord une autorisation** (feuille Face ID) : son code
    /// frais part avec la requête, et Railway s'en sert pour révoquer le jeton Apple
    /// (règle 5.1.1(v), `backend/app/apple.py`) — l'appareil ne peut pas révoquer seul,
    /// Apple exige un secret signé par la clé du compte développeur. Fermer la feuille
    /// annule la suppression : rien n'est touché.
    ///
    /// - Throws: une ``ErreurAPI`` dont le message est affichable. Si elle est
    ///   levée, rien n'a été touché **sauf** ce que `DELETE /profils/moi` a pu
    ///   accomplir avant l'échec — la route est conçue pour tolérer un second
    ///   appel (`app/api/routes/profils.py`). Une `ASAuthorizationError` si la
    ///   réautorisation Apple a été annulée ou a échoué.
    func supprimerCompte() async throws {
        var corps: SuppressionCompte?
        if await compteApple() {
            corps = SuppressionCompte(appleAuthorizationCode: try await ReautorisationApple().codeAutorisation())
        }
        // Tant que la session vit : la route le demande. La cascade de `auth.users`
        // l'effacerait de toute façon, mais pas si la suppression échoue à mi-chemin.
        await NotificationsPush.partage.retirer()
        try await APIClient.partage.envoyer("profils/moi", methode: .delete, corps: corps)
        try? await supabase.auth.signOut()
        oublierCompte()
    }

    /// Déconnecte l'utilisateur actuel.
    func deconnexion() async {
        estEnChargement = true
        messageErreur = nil
        
        // Avant `signOut()` : la route a besoin de la session encore valide.
        await NotificationsPush.partage.retirer()
        do {
            try await supabase.auth.signOut()
            oublierCompte()
        } catch {
            messageErreur = t("auth.erreur.deconnexion", error.localizedDescription)
        }
        
        estEnChargement = false
    }
}

// MARK: - Révocation Apple

/// Corps de `DELETE /profils/moi` — absent pour un compte email ou Google.
private struct SuppressionCompte: Encodable {
    let appleAuthorizationCode: String

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

/// Redemande une autorisation Apple hors du bouton — `ASAuthorizationController` nu,
/// enveloppé dans une continuation — pour obtenir un **code d'autorisation frais**, que
/// seul le serveur sait échanger puis révoquer.
@MainActor
private final class ReautorisationApple: NSObject, ASAuthorizationControllerDelegate,
                                          ASAuthorizationControllerPresentationContextProviding {

    private var suite: CheckedContinuation<String, Error>?
    /// Retenu le temps de la feuille : rien d'autre ne le garde en vie.
    private var controleur: ASAuthorizationController?

    func codeAutorisation() async throws -> String {
        let requete = ASAuthorizationAppleIDProvider().createRequest()
        let controleur = ASAuthorizationController(authorizationRequests: [requete])
        controleur.delegate = self
        controleur.presentationContextProvider = self
        self.controleur = controleur
        return try await withCheckedThrowingContinuation { suite in
            self.suite = suite
            controleur.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            if let code {
                suite?.resume(returning: code)
            } else {
                suite?.resume(throwing: ASAuthorizationError(.invalidResponse))
            }
            suite = nil
            self.controleur = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            suite?.resume(throwing: error)
            suite = nil
            self.controleur = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
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
