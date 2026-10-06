import SwiftUI
import UIKit

/// **Réglages** — poussé depuis l'engrenage de ``ProfilView``. Tout ce qui règle l'app
/// plutôt que le profil : apparence, langue, notifications, compte, et la version en pied.
///
/// > **Poussé, pas en feuille.** C'est le geste des Réglages d'iOS, la pile de navigation
/// > du Profil existe déjà, et le chevron de retour natif dit où l'on revient (wayfinding,
/// > /apple-design §16).
///
/// Quatre blocs `surface` au rayon 24 (`ombreBloc`), comme ceux du profil — la palette et
/// les encres viennent toutes de `Couleurs.swift`, donc l'écran suit le mode sombre sans
/// rien lire lui-même.
struct ReglagesView: View {

    @ObservedObject var viewModel: AuthViewModel

    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.openURL) private var ouvrirURL
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    /// La même marge que ``ProfilView``, sans quoi le passage de l'un à l'autre décalerait.
    private let margeLaterale: CGFloat = 16

    /// Suppression de compte (App Store, règle 5.1.1(v)) : deux alertes système
    /// chaînées, **jamais** une feuille maison — c'est le seul geste de l'écran
    /// assez grave pour justifier l'interruption d'une alerte, et deux fois
    /// plutôt qu'une (`/apple-design` §16, agence : la confirmation se réserve
    /// aux actions vraiment destructrices et irréversibles). `DELETE
    /// /profils/moi` fait tout côté serveur ; l'échec se dit sous le bouton,
    /// comme le reste de cet écran, jamais dans une troisième alerte.
    @State private var confirmationSuppression = false
    @State private var confirmationSuppressionFinale = false
    @State private var envoiSuppression = false
    @State private var erreurSuppression: ErreurAPI?

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Text(t("reglages.titre"))
                        .font(.titre)
                        .tracking(Tracking.titre)
                        .foregroundColor(.texte)          // 15,37:1 · sombre 17,01:1
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(height: 20)
                    blocApparence

                    Spacer().frame(height: 12)
                    blocLangue

                    Spacer().frame(height: 12)
                    blocNotifications

                    Spacer().frame(height: 12)
                    blocCompte

                    Spacer().frame(height: 20)
                    versionAffichee
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        // Le titre est dans le contenu, à 28 pt : la barre ne garde que le chevron natif.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Apparence

    /// Automatique / Clair / Sombre — le ``SelecteurSegmente`` de la vue championnat, à
    /// trois segments. Le choix part à ``ThemeManager``, qui fond la fenêtre d'un mode à
    /// l'autre ; la pastille glisse dans la même transaction.
    private var blocApparence: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitreDeBloc(texte: t("reglages.apparence"))

            Spacer().frame(height: 12)

            SelecteurSegmente(
                titre: t("reglages.apparence"),
                options: Apparence.allCases.map { ($0, t($0.cleLibelle)) },
                selection: Binding(get: { theme.apparence }, set: { theme.choisir($0) })
            )

            Spacer().frame(height: 10)

            Text(t("reglages.apparence.explication"))
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(BlocReglages())
    }

    // MARK: - Langue

    /// Le même ``SelecteurLangue`` que l'accueil et la connexion, déplacé du profil.
    private var blocLangue: some View {
        HStack(spacing: 12) {
            Text(t("reglages.langue"))
                .font(.custom("HelveticaNeue-Medium", size: 17))
                .foregroundColor(.texte)
            Spacer(minLength: 0)
            SelecteurLangue()
        }
        .frame(minHeight: 44)
        .modifier(BlocReglages())
    }

    // MARK: - Notifications

    /// **Pas d'interrupteur dans l'app** (`ios/CLAUDE.md` §3, `decisions.md` §25) : le
    /// bouton ouvre directement la page des notifications de Greed F1 dans les Réglages
    /// d'iOS (`openNotificationSettingsURLString`, iOS 16+), qui en tiennent lieu.
    private var blocNotifications: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitreDeBloc(texte: t("reglages.notifications"))

            Spacer().frame(height: 6)

            Text(t("reglages.notificationsExplication"))
                .font(.corpsSm)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 6)

            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    ouvrirURL(url)
                }
            } label: {
                RangeeReglage(libelle: t("reglages.gererNotifications"),
                              encre: .texte,
                              icone: "arrow.up.forward")
            }
            .buttonStyle(StyleAppui(.bouton))
        }
        .modifier(BlocReglages())
    }

    // MARK: - Compte

    /// **« Supprimer » sous « Se déconnecter », jamais avant.** Wayfinding
    /// d'`/apple-design` §16 : la sortie ordinaire et réversible se rencontre d'abord, la
    /// sortie destructrice et irréversible en dernier — le pouce qui vise la première ne
    /// doit pas tomber sur la seconde par réflexe de position.
    private var blocCompte: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitreDeBloc(texte: t("reglages.compte"))

            Spacer().frame(height: 4)

            Button {
                Task { await viewModel.deconnexion() }
            } label: {
                RangeeReglage(libelle: t("commun.seDeconnecter"), encre: .texte)
            }
            .buttonStyle(StyleAppui(.bouton))

            Rectangle()
                .fill(Color.secondaire.opacity(0.15))
                .frame(height: 1)

            Button {
                confirmationSuppression = true
            } label: {
                // `encrePrimaire`, pas `primaire` : en sombre, l'aplat `#C0182A` ne tient
                // que 2,26:1 sur la surface ; `#FF6961` y tient 4,94:1.
                RangeeReglage(libelle: t("reglages.supprimerCompte"), encre: .encrePrimaire)
            }
            .buttonStyle(StyleAppui(.bouton))
            .disabled(envoiSuppression)

            if let erreurSuppression {
                ErreurEnLigne(erreur: erreurSuppression)
                    .transition(.opacity)
            }
        }
        .modifier(BlocReglages())
        .animation(mouvementReduit ? nil : Mouvement.entree(0.20), value: erreurSuppression)
        .sensoryFeedback(.error, trigger: erreurSuppression) { _, nouveau in nouveau != nil }
        .alert(t("reglages.supprimerCompteTitre"), isPresented: $confirmationSuppression) {
            Button(t("commun.annuler"), role: .cancel) {}
            Button(t("reglages.supprimer"), role: .destructive) {
                confirmationSuppressionFinale = true
            }
        } message: {
            Text(t("reglages.supprimerCompteMessage"))
        }
        .alert(t("reglages.esTuSur"), isPresented: $confirmationSuppressionFinale) {
            Button(t("commun.annuler"), role: .cancel) {}
            Button(t("reglages.supprimerDefinitivement"), role: .destructive,
                   action: supprimerCompte)
        } message: {
            Text(t("reglages.supprimerCompteMessageFinal"))
        }
    }

    /// Lancée depuis la seconde alerte. **Pas liée à l'écran** : quitter les réglages
    /// pendant l'appel ne l'annule pas — un compte à moitié supprimé serait pire qu'un
    /// écran quitté.
    private func supprimerCompte() {
        guard !envoiSuppression else { return }
        erreurSuppression = nil
        envoiSuppression = true

        Task {
            do {
                try await viewModel.supprimerCompte()
                // Rien à faire ici : `oublierCompte()` (dans le view model)
                // publie `estConnecte = false`, et c'est `GreedF1App` qui
                // bascule seul vers `LandingView` — le même chemin qu'une
                // déconnexion ordinaire.
            } catch let refus as ErreurAPI {
                envoiSuppression = false
                erreurSuppression = refus
            } catch {
                envoiSuppression = false
            }
        }
    }

    // MARK: - Pied

    /// Le numéro de version, en pied des réglages comme dans ceux d'iOS. Seule source :
    /// `MARKETING_VERSION` (`ios/CLAUDE.md` §4).
    private var versionAffichee: some View {
        Text(t("accueil.version", Bundle.main.versionAffichee))
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Composants

/// Un bloc des réglages : `surface` au rayon 24, donc `ombreBloc` (§4.7) — le même habit
/// que les blocs du profil.
private struct BlocReglages: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
            .ombreBloc()
    }
}

/// Une rangée d'action pleine largeur, 44 pt de haut au moins : libellé à gauche, icône
/// éventuelle à droite.
private struct RangeeReglage: View {
    let libelle: String
    let encre: Color
    var icone: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(libelle)
                .font(.custom("HelveticaNeue", size: 17))
                .foregroundColor(encre)
            Spacer(minLength: 0)
            if let icone {
                Image(systemName: icone)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.grisSecondaire)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { ReglagesView(viewModel: AuthViewModel()) }
        .environmentObject(ThemeManager.shared)
        .environmentObject(LanguageManager.shared)
}
