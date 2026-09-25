import SwiftUI

// MARK: - Ce qu'un profil montre d'un membre

/// Le profil d'un autre membre, tel que le classement le passe à l'écran.
///
/// **Ce que le classement sait s'affiche tout de suite** : pseudo, voiture, numéro, et les
/// statistiques qu'il sert déjà (le meilleur coup). Les quatre tuiles définitives viennent
/// ensuite de `GET /profils/{id}/stats`, mises en forme par ``StatsProfil/tuiles`` — jamais
/// par l'écran.
struct MembreProfil {

    /// L'identifiant du compte. C'est de lui que se tire la teinte de la pastille, jamais
    /// du rang : un membre qui perd une place ne change pas de couleur.
    let identifiant: String

    /// Le compte à interroger pour les statistiques. **`nil` pour un membre d'aperçu** :
    /// aucun appel ne part, les tuiles provisoires restent.
    var profilId: UUID?

    let pseudo: String

    var photo: URL?

    /// Ce que porte sa voiture — sa livrée et son numéro, exactement ce que ``ProfilView``
    /// laisse régler à son propriétaire.
    let livree: Livree
    let numero: String

    /// Grands Prix joués cette saison, pour la ligne « Ses Grands Prix ». **`nil` tant que
    /// les statistiques ne sont pas lues** : la ligne dit alors la saison, pas un « 0 GP
    /// joué » qui serait faux.
    let grandsPrixJoues: Int?

    /// Les quatre tuiles **provisoires**, dans l'ordre de ``ProfilView`` — ce que le
    /// classement sait déjà, affiché sous le spinner le temps que les vraies arrivent.
    let statistiques: [StatistiqueProfil]
}

// MARK: - L'écran

/// **Le profil d'un autre membre** — en lecture seule.
///
/// Référence visuelle : `Ressources/Screenshots/screen-22-profil-membre.PNG`.
///
/// C'est ``ProfilView`` moins tout ce qui s'y règle : ni appareil photo sur la pastille, ni
/// « Supprimer la photo », ni bloc de livrée, ni déconnexion. **Rien de ce qui est ici ne se
/// modifie**, et c'est ce qui autorise l'écran à ne porter aucun état.
///
/// > **Deux sources, une seule attente.** L'identité vient de la ligne du classement,
/// > affichée sans délai ; seules les statistiques font un appel
/// > (``StatistiquesProfil``, `GET /profils/{id}/stats`), avec spinner, message
/// > d'``ErreurAPI`` et « Réessayer ».
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1) : « 22 », et nulle
/// part un « ×2,20 ».
struct ProfilMembreView: View {

    let membre: MembreProfil

    @StateObject private var statistiques = StatistiquesProfil()

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Text(membre.pseudo)
                        .font(.titre)
                        .tracking(Tracking.titre)
                        .foregroundColor(.texte)          // 15,37:1 sur le beige
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(height: 12)
                    entete

                    Spacer().frame(height: 20)
                    grilleStatistiques

                    Spacer().frame(height: 12)
                    sesGrandsPrix
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        // Le pseudo est déjà dans le contenu, à 28 pt : le répéter dans la barre ferait
        // doublon. Elle ne garde que le chevron de retour natif, qui porte le titre de
        // l'écran précédent — « Classement ».
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await chargerStatistiques() }
    }

    // MARK: - Statistiques

    @ViewBuilder
    private var grilleStatistiques: some View {
        if membre.profilId == nil {
            // Membre d'aperçu : rien à demander au serveur.
            GrilleStatistiques(statistiques: membre.statistiques)
        } else {
            BlocStatistiques(etat: statistiques.etat,
                             provisoires: membre.statistiques) {
                Task { await chargerStatistiques() }
            }
        }
    }

    private func chargerStatistiques() async {
        guard let id = membre.profilId else { return }
        await statistiques.charger(profilId: id)
    }

    // MARK: - En-tête

    /// **Le même aplat que sur son propre profil**, à la pastille près : ici elle ne porte
    /// pas l'appareil photo, et l'initiale s'y pose sur *sa* teinte — celle de son avatar au
    /// classement, celle de son filet. C'est ce qui fait reconnaître le membre avant même
    /// d'avoir lu le pseudo.
    private var entete: some View {
        EnteteProfil(pseudo: membre.pseudo,
                     livree: membre.livree,
                     numero: membre.numero,
                     photo: membre.photo) {
            PastilleProfil(pseudo: membre.pseudo,
                           photo: membre.photo,
                           fond: .teinteAvatar(pour: membre.identifiant))
        }
    }

    // MARK: - Ses Grands Prix

    private var sesGrandsPrix: some View {
        LigneGrandsPrix(titre: "Ses Grands Prix", sousTitre: sousTitreGrandsPrix) {
            HistoriqueGPView(titre: "Ses Grands Prix")
        }
    }

    private var sousTitreGrandsPrix: String {
        StatsProfil.sousTitreGrandsPrix(joues: statistiques.stats?.gpJoues ?? membre.grandsPrixJoues)
    }
}

#Preview {
    NavigationStack {
        ProfilMembreView(membre: MembreProfil(
            identifiant: "7homas",
            pseudo: "7homas",
            livree: Livree(mode: .perso,
                           coque: "#2D2D2D",
                           ailerons: "#00A19C",
                           couleurTexte: "#00D2BE"),
            numero: "44",
            grandsPrixJoues: 2,
            statistiques: [
                StatistiqueProfil(valeur: "40%", libelle: "Paris gagnés"),
                StatistiqueProfil(valeur: "33", libelle: "Pts moy. / GP"),
                StatistiqueProfil(valeur: "22", libelle: "Meilleur coup"),
                StatistiqueProfil(valeur: "41", libelle: "Cote moy. tentée")
            ]
        ))
    }
}
