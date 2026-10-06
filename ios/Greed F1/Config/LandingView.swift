import SwiftUI

/// Écran d'accueil (landing) — premier écran vu par un utilisateur non connecté.
///
/// Référence visuelle : `Ressources/Screenshots/screen-01-landing.PNG`.
/// Le bloc bandeau + titre + sous-titre + boutons est centré verticalement d'un seul
/// tenant ; seul le numéro de version est ancré en bas.
struct LandingView: View {

    @ObservedObject var viewModel: AuthViewModel

    /// Marge latérale commune au bandeau et aux boutons — ils s'alignent sur la capture.
    private let margeLaterale: CGFloat = 16

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Le sélecteur de langue, discret, au-dessus de tout : il doit être
                    // trouvable avant de lire le premier mot.
                    HStack {
                        Spacer()
                        SelecteurLangue()
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 24)

                    bandeau
                    Spacer().frame(height: 20)

                    titre
                    Spacer().frame(height: 12)

                    sousTitre
                    Spacer().frame(height: 32)

                    boutons

                    Spacer(minLength: 24)

                    version
                }
                .padding(.horizontal, margeLaterale)
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Bandeau

    /// `logo-bandeau` est `logo-05.svg` à viewBox rognée (`0 215 894.21 243`) : le
    /// rectangle rouge seul, sans l'icône carrée qui le surmonte dans le logo complet.
    /// Le SVG porte déjà ses coins arrondis — aucun `cornerRadius` ici.
    private var bandeau: some View {
        Image("logo-bandeau")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Greed F1")
    }

    // MARK: - Textes

    private var titre: some View {
        Text(t("landing.titre"))
            .font(.custom("HelveticaNeue-Medium", size: 32))
            .tracking(-0.8)          // −0,025em, cf. docs/design-system.md §2
            .foregroundColor(.texte)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sousTitre: some View {
        Text(t("landing.sousTitre"))
            .font(.custom("HelveticaNeue", size: 17))
            .foregroundColor(.secondaire)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
    }

    private var version: some View {
        Text("Greed F1 · v\(Bundle.main.versionAffichee)")
            .font(.custom("HelveticaNeue", size: 12))
            .foregroundColor(.secondaire.opacity(0.75))   // 4,72:1 mesuré sur le fond
            .padding(.bottom, 8)
    }

    // MARK: - Boutons

    /// Apple puis Google, séparateur « ou », puis les deux boutons habituels : les
    /// raccourcis les plus rapides passent en tête. Contrepartie de `Landing.jsx`
    /// (`BoutonsOAuth separateurApres`). Apple, au moins aussi visible que Google
    /// (App Store, règle 4.8), en premier.
    private var boutons: some View {
        VStack(spacing: 12) {
            BoutonApple(viewModel: viewModel, rayon: 28)   // capsule : 56 / 2

            Button {
                Task { await viewModel.connexionOAuth(fournisseur: .google) }
            } label: {
                HStack(spacing: 10) {
                    Image("icone-google")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text(t("auth.google"))
                        .font(.custom("HelveticaNeue-Medium", size: 17))
                        .foregroundColor(.texte)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .background(Color.surface)
            .clipShape(Capsule())

            separateurOu

            NavigationLink {
                InscriptionView(viewModel: viewModel)
            } label: {
                LibelleBouton(texte: t("landing.creerCompte"), encre: .encreSurAplat)
                    .background(Color.primaire)
                    .clipShape(Capsule())
            }

            NavigationLink {
                ConnexionView(viewModel: viewModel)
            } label: {
                LibelleBouton(texte: t("landing.dejaCompte"), encre: .encrePrimaire)
                    .background(Color.surface)
                    .clipShape(Capsule())
            }

            if let erreur = viewModel.messageErreur {
                Text(erreur)
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundColor(.encrePrimaire)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var separateurOu: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.texte.opacity(0.1)).frame(height: 1)
            Text(t("landing.ou"))
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.secondaire)
            Rectangle().fill(Color.texte.opacity(0.1)).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    /// Un seul propriétaire pour la forme des deux boutons : ils ne divergent pas.
    private struct LibelleBouton: View {
        let texte: String
        let encre: Color

        var body: some View {
            Text(texte)
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .foregroundColor(encre)
                .frame(maxWidth: .infinity)
                .frame(height: 56)      // > 44 pt, contrainte tactile iOS
        }
    }
}

// MARK: - Version

extension Bundle {
    /// `CFBundleShortVersionString`, c'est-à-dire `MARKETING_VERSION` du projet Xcode :
    /// **la seule source** du numéro de version de l'app iOS.
    var versionAffichee: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

#Preview {
    LandingView(viewModel: AuthViewModel())
}
