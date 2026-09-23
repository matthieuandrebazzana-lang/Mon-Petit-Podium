import SwiftUI

// MARK: - Ce qu'un profil montre d'un membre

/// Le profil d'un autre membre, tel que le classement le passe à l'écran.
///
/// **Les statistiques arrivent déjà mises en forme.** Elles sont calculées là où vivent les
/// chiffres bruts — le classement — et pas ici : l'écran qui affiche un pourcentage ne doit
/// pas être aussi celui qui décide comment on l'arrondit, sinon le profil et le classement
/// finiraient par ne plus dire la même chose du même membre.
struct MembreProfil {

    /// L'identifiant du compte. C'est de lui que se tire la teinte de la pastille, jamais
    /// du rang : un membre qui perd une place ne change pas de couleur.
    let identifiant: String

    let pseudo: String

    var photo: URL?

    /// Ce que porte sa voiture — sa livrée et son numéro, exactement ce que ``ProfilView``
    /// laisse régler à son propriétaire.
    let livree: Livree
    let numero: String

    /// Grands Prix joués cette saison, pour la ligne « Ses Grands Prix ». **`nil` tant que
    /// `GET /profils/{id}/stats` n'est pas branché** : la ligne dit alors la saison, pas
    /// un « 0 GP joué » qui serait faux.
    let grandsPrixJoues: Int?

    /// Les quatre tuiles, dans l'ordre de ``ProfilView`` — **les mêmes quatre**, sans quoi
    /// comparer son profil à celui d'un autre demanderait de relire les libellés.
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
/// > **Les données sont mockées.** ``MembreProfil`` est construit par le classement à
/// > partir de ses propres valeurs en dur ; aucun appel réseau ne part de cet écran.
///
/// **Les points sont des entiers, jamais une cote** (`CLAUDE.md` §3.1) : « 22 », et nulle
/// part un « ×2,20 ».
struct ProfilMembreView: View {

    let membre: MembreProfil

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
                    GrilleStatistiques(statistiques: membre.statistiques)

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

    /// La seule sortie de l'écran : ce que ce membre a joué, Grand Prix par Grand Prix.
    ///
    /// `NavigationLink` et non `Button` : c'est lui qui porte le glissement d'écran natif et
    /// le geste de retour par le bord, qu'un `Button` poussant un état ne donne pas.
    private var sesGrandsPrix: some View {
        NavigationLink {
            SesGrandsPrixView(pseudo: membre.pseudo)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(.white)              // 10,88:1 sur #800111
                    .frame(width: 44, height: 44)
                    .background(Color.primaire)
                    .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ses Grands Prix")
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                        .tracking(-0.30)                  // −0,02 em × 15
                        .foregroundColor(.texte)          // 15,37:1 sur le blanc
                        .lineLimit(1)

                    // `grisSecondaire` (5,33:1 sur le blanc) et non le `#999999` de la
                    // capture, qui n'y vaut que 2,85:1.
                    Text(sousTitreGrandsPrix)
                        .font(.custom("HelveticaNeue", size: 13))
                        .foregroundColor(.grisSecondaire)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.grisSecondaire)     // 5,33:1 sur le blanc
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.carte, style: .continuous))
            .ombreCarte()
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ses Grands Prix. \(sousTitreGrandsPrix).")
        .accessibilityAddTraits(.isButton)
    }

    private var sousTitreGrandsPrix: String {
        guard let joues = membre.grandsPrixJoues else { return "Saison 2026" }
        return "\(joues) \(joues > 1 ? "GP joués" : "GP joué") cette saison"
    }
}

// MARK: - L'écran d'attente

/// Ce que ce membre a joué, Grand Prix par Grand Prix. **Il dit ce qui manque**, plutôt que
/// de laisser un blanc qui se lirait comme un chargement en panne — le même parti que la
/// vue piste d'un championnat.
///
/// > *Écart signalé (`CLAUDE.md` §6).* La demande écrivait « Historique GP — à venir ».
/// > **« historique » est un terme proscrit** (`CLAUDE.md` §3.2, tableau du vocabulaire
/// > imposé) : l'écran garde donc le nom de la ligne qui y mène, « Ses Grands Prix ».
private struct SesGrandsPrixView: View {

    let pseudo: String

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("Ses Grands Prix")
                    .font(.custom("HelveticaNeue-Medium", size: 17))
                    .tracking(-0.34)
                    .foregroundColor(.texte)              // 15,37:1 sur le beige

                Text("À venir")
                    .font(.corpsSm)
                    .foregroundColor(.secondaire)         // 9,32:1 sur le beige
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
