import SwiftUI

/// Rejoindre un championnat : la saisie du code à six caractères reçu d'un ami.
///
/// Référence visuelle : `Ressources/Screenshots/screen-12-rejoindre-championnat.PNG`.
///
/// **`POST /championnats/rejoindre`** (`docs/swift-app.md` §3.3). Le succès fige la
/// saisie, écrit le nom du championnat rejoint sous le bouton, et le bouton devient
/// « Voir le championnat ». Un refus — code inconnu (`404`) — s'écrit au même endroit
/// (``ErreurEnLigne``), jamais dans une alerte, et s'efface à la frappe suivante. La liste
/// de ``MesChampionnats`` est rechargée dès le succès.
///
/// **Avec ``ouvrir``, le succès ne s'attarde pas** : l'écran se ferme et l'appelant pousse
/// le détail du championnat rejoint à sa place — le retour ramène donc à l'écran d'où l'on
/// est parti, jamais à la saisie. **Déjà membre (`409`), même chose** : le championnat est
/// retrouvé par son code dans la liste rechargée, et s'ouvre sans erreur.
///
/// **Six cases, mais un seul champ de texte.** Les cases sont un dessin ; ce qui reçoit la
/// frappe est un `TextField` unique, invisible, posé par-dessus toute la rangée. C'est ce
/// qui donne gratuitement ce que six champs séparés demandent d'écrire à la main et
/// finissent toujours par rater : l'avance d'une case à l'autre, le retour arrière qui
/// recule, le collage d'un code entier, la dictée, et le clavier système avec sa barre de
/// suggestions. Le curseur se pose d'office après le dernier caractère saisi — **la
/// première case vide**, exactement ce que la maquette demande.
struct RejoindreChampionnatView: View {

    /// Marge latérale commune à tous les écrans.
    private let margeLaterale: CGFloat = 16

    /// Espacement entre deux cases. Leur côté, lui, se **mesure** : voir ``coteCase``.
    private let espacementCases: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @ObservedObject var mesChampionnats: MesChampionnats

    /// Pousse le détail du championnat rejoint, **une fois cet écran fermé** — voir
    /// ``ActionsChampionnat``. `nil` (aperçu) : l'ancien parcours, « Voir le championnat ».
    var ouvrir: ((Championnat) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @FocusState private var saisieActive: Bool

    /// Le côté d'une case, **déduit de la largeur réellement disponible** et non posé en
    /// dur : six cases carrées et cinq intervalles doivent tomber juste aussi bien sur un
    /// iPhone SE que sur un Pro Max. La valeur initiale n'est qu'une amorce, remplacée à la
    /// première mesure.
    @State private var coteCase: CGFloat = 46

    /// Vrai pendant l'appel : le bouton porte un spinner et ne se rappuie pas.
    @State private var envoi = false
    /// Le refus du serveur, affiché sous le bouton jusqu'à la prochaine frappe.
    @State private var erreur: ErreurAPI?
    /// Le championnat rejoint. **Non nul, l'écran a fini son travail.**
    @State private var rejoint: Championnat?
    /// Le championnat à pousser **une fois cet écran disparu** — voir ``aboutir(_:)``.
    @State private var aOuvrir: Championnat?

    /// La longueur du code, écrite **une fois** : la rangée, la validité du bouton et le
    /// texte d'accessibilité s'y réfèrent tous les trois.
    private static let longueurCode = 6

    /// La case où atterrira le prochain caractère. Une fois le code complet elle reste la
    /// dernière : l'anneau ne sort jamais de la rangée.
    private var indexActif: Int {
        min(code.count, Self.longueurCode - 1)
    }

    private var codeComplet: Bool {
        code.count == Self.longueurCode
    }

    /// Le code tel qu'il sera envoyé au serveur : **en majuscules**.
    ///
    /// > **La casse se corrige à l'affichage, pas à la frappe**, et ce n'est pas un détail
    /// > de style. Mesuré au simulateur : remonter la majuscule dans le texte du champ le
    /// > réécrit à chaque touche, et une frappe rapide y perd des caractères — « 7k2p4m »
    /// > arrivait « 7KP4M ». Le champ garde donc ce qui a été tapé ; les cases, elles,
    /// > n'affichent que des capitales, et le clavier logiciel en propose d'office
    /// > (`textInputAutocapitalization(.characters)`).
    private var codeNormalise: String {
        code.uppercased()
    }

    /// L'anneau de focus glisse d'une case à l'autre — il ne se téléporte pas.
    @Namespace private var espaceAnneau

    var body: some View {
        ZStack {
            Color.fondPrincipal
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    titre

                    Spacer().frame(height: 12)
                    blocCode

                    Spacer().frame(height: 12)   // espacement entre blocs (§4.6)
                    boutonRejoindre

                    if let erreur {
                        Spacer().frame(height: 12)
                        ErreurEnLigne(erreur: erreur)
                            .transition(.opacity)
                    } else if let rejoint {
                        Spacer().frame(height: 12)
                        bienvenue(rejoint)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, margeLaterale)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Le titre de l'écran est dans le contenu, à 28 pt : la barre système ne porte que
        // le chevron de retour, qui reste **le bouton natif** — c'est lui qui donne le
        // geste de retour par le bord, qu'un bouton dessiné à la main ne donne pas.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Mouvement.entree(0.20), value: erreur)
        .animation(Mouvement.entree(0.20), value: rejoint)
        // Retour haptique **au même instant** que ce qu'il confirme.
        .sensoryFeedback(.success, trigger: rejoint) { _, nouveau in nouveau != nil }
        .sensoryFeedback(.error, trigger: erreur) { _, nouveau in nouveau != nil }
        .onDisappear {
            guard let aOuvrir else { return }
            self.aOuvrir = nil
            ouvrir?(aOuvrir)
        }
    }

    // MARK: - Envoi

    private struct CorpsAdhesion: Encodable {
        let code: String
    }

    /// `POST /championnats/rejoindre`. Le serveur normalise lui-même le code (majuscules,
    /// espaces et tirets retirés) : ``codeNormalise`` n'est envoyé que par cohérence avec
    /// ce que les cases affichent.
    ///
    /// La tâche n'est **pas** liée à l'écran : quitter pendant l'appel ne l'annule pas, et
    /// la liste se recharge quand même.
    private func rejoindre() {
        guard codeComplet, !envoi, rejoint == nil else { return }
        saisieActive = false
        erreur = nil
        envoi = true
        let corps = CorpsAdhesion(code: codeNormalise)

        Task {
            do {
                let championnat: Championnat = try await APIClient.partage.requete(
                    "championnats/rejoindre", methode: .post, corps: corps)
                envoi = false
                aboutir(championnat)
                await mesChampionnats.charger(forcer: true)
            } catch ErreurAPI.serveur(statut: 409, let message) {
                // Déjà membre : ce n'est pas un échec, c'est le championnat qu'on cherchait.
                await mesChampionnats.charger(forcer: true)
                envoi = false
                if let connu = connuParCode() {
                    aboutir(connu)
                } else {
                    erreur = .serveur(statut: 409, message: message)
                }
            } catch let refus as ErreurAPI {
                envoi = false
                erreur = refus
            } catch {
                envoi = false
            }
        }
    }

    /// Le championnat de la liste qui porte le code saisi — l'adhésion en double ne rend
    /// rien d'autre qu'un `409`.
    private func connuParCode() -> Championnat? {
        guard case .pret(let liste) = mesChampionnats.etat else { return nil }
        return liste.first { $0.codeInvitation.uppercased() == codeNormalise }
    }

    /// Le championnat est obtenu. ``rejoint`` porte l'haptique de succès ; avec ``ouvrir``,
    /// l'écran se ferme et cède la place au détail.
    ///
    /// > **Le détail n'est poussé qu'à `onDisappear`**, jamais dans la même transaction
    /// > que la fermeture : mesuré au simulateur, retirer un écran et en pousser un autre
    /// > d'un même geste laisse la pile incohérente — la saisie réapparaissait sous le
    /// > détail. Une fermeture « sans animation » (`disablesAnimations`) n'y change rien :
    /// > la pile native l'anime quand même.
    private func aboutir(_ championnat: Championnat) {
        rejoint = championnat
        guard ouvrir != nil else { return }
        aOuvrir = championnat
        dismiss()
    }

    /// La confirmation, à la place exacte où un refus se serait écrit.
    private func bienvenue(_ championnat: Championnat) -> some View {
        Text(t("rejoindre.bienvenue", championnat.nom))
            .font(.corps)
            .foregroundColor(.texte)                // 15,37:1 sur le beige
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - Titre

    private var titre: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("championnat.rejoindre"))
                .font(.titre)
                .tracking(Tracking.titre)
                .foregroundColor(.texte)            // 15,37:1 sur le beige
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // **`grisSecondaire` et non le `#999999` de la version web** : sur le beige,
            // `#999999` ne vaut que 2,52:1 quand `#6B6B6B` y tient **4,71:1**, le plancher
            // d'un texte ordinaire. Le contraste se mesure (`ios/CLAUDE.md` §3).
            Text(t("rejoindre.indication", Self.longueurCode))
                .font(.corps)
                .foregroundColor(.grisSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Le bloc de saisie

    private var blocCode: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("championnat.codeInvitation"))
                .font(.label)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.grisSecondaire)   // 5,33:1 sur le blanc

            rangeeCases
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreBloc()
    }

    /// La rangée : les six cases, l'anneau qui glisse, et le champ invisible qui reçoit
    /// tout.
    ///
    /// **Le champ couvre la rangée entière.** Un appui n'importe où, y compris entre deux
    /// cases, ouvre donc le clavier — et la cible utile n'est pas la case (≈ 45 pt de
    /// côté, et moins sur un SE) mais la bande complète, bien au-delà des 44 × 44 pt
    /// exigés.
    private var rangeeCases: some View {
        HStack(spacing: espacementCases) {
            ForEach(0..<Self.longueurCode, id: \.self) { index in
                caseCode(index)
            }
        }
        .frame(maxWidth: .infinity)
        .background(mesureLargeur)
        .overlay(alignment: .leading) { anneauFocus }
        .overlay { champInvisible }
        .animation(animationAnneau, value: indexActif)
        .accessibilityElement(children: .contain)
    }

    /// Une case. Vide, elle porte un tiret ; remplie, le caractère.
    ///
    /// **Le beige de l'app posé dans le blanc**, comme le champ de `CreerChampionnatView` :
    /// c'est ce qui rattache le creux au fond de l'écran plutôt que d'introduire un gris de
    /// plus. Rayon `champ` (14) et **aucune ombre** — une surface posée *à l'intérieur*
    /// d'un bloc ne casse jamais son plan (`Formes.swift`).
    private func caseCode(_ index: Int) -> some View {
        ZStack {
            Color.fondPrincipal

            if let caractere = caractere(index) {
                Text(String(caractere))
                    .font(.custom("HelveticaNeue-Medium", size: 22))
                    .foregroundColor(.texte)        // 15,37:1 sur le beige
            } else {
                // Le tiret dit que la case attend un caractère : il **porte un sens**, donc
                // le plancher de 3:1. `grisSecondaire` y tient 4,71:1 sur le beige, quand
                // le gris clair de la version web tombe sous le seuil.
                Capsule()
                    .fill(Color.grisSecondaire)
                    .frame(width: 16, height: 3)
            }
        }
        .frame(width: coteCase, height: coteCase)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
        .matchedGeometryEffect(id: index, in: espaceAnneau, isSource: true)
        .accessibilityHidden(true)
    }

    /// Le caractère d'une case, ou `nil` si elle attend encore. **Déjà en majuscule** :
    /// c'est ``codeNormalise`` qui est lu, jamais la frappe brute.
    private func caractere(_ index: Int) -> Character? {
        let normalise = codeNormalise
        guard index < normalise.count else { return nil }
        return normalise[normalise.index(normalise.startIndex, offsetBy: index)]
    }

    /// L'anneau de la case active.
    ///
    /// > **Un seul anneau, qui se déplace** — et non six contours qui s'allument tour à
    /// > tour. C'est la même chose à l'arrêt, et tout autre chose en mouvement : le
    /// > déplacement dit d'où l'on vient et où l'on va, là où un fondu laisse deviner.
    ///
    /// **La seule bordure de l'app, et c'est un écart assumé** : `Formes.swift` proscrit
    /// les traits fins, parce qu'ils servent en général à séparer ce que l'espace sépare
    /// déjà. Celui-ci ne sépare rien — il désigne la case qui recevra la frappe, et rien
    /// d'autre sur cet écran ne peut le dire.
    private var anneauFocus: some View {
        RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous)
            .strokeBorder(Color.encrePrimaire, lineWidth: 2)
            .matchedGeometryEffect(id: indexActif, in: espaceAnneau, isSource: false)
            .accessibilityHidden(true)
    }

    /// **Le déplacement de l'anneau est la seule animation de l'écran.** Il arrive cinq
    /// fois par code et répond à un geste, donc il s'anime — sur la courbe des
    /// déplacements, 180 ms, sous le plafond des 300 ms.
    ///
    /// **Le caractère saisi, lui, ne s'anime pas** : c'est une frappe au clavier, et le
    /// retour d'une frappe est immédiat ou il est en retard.
    ///
    /// Sous `accessibilityReduceMotion`, l'anneau saute au lieu de glisser — c'est un
    /// déplacement, et il n'y a rien à comprendre dans le trajet lui-même.
    private var animationAnneau: Animation? {
        mouvementReduit ? nil : Mouvement.deplacement(0.18)
    }

    /// Le champ réel : invisible, étalé sur toute la rangée, et seul dépositaire du code.
    ///
    /// **Encre transparente plutôt qu'une opacité proche de zéro.** Mesuré au simulateur,
    /// un champ à `opacity(0.01)` laisse une trace grise lisible par-dessus les deux
    /// premières cases : l'opacité d'un champ de saisie ne se composite pas comme celle
    /// d'un dessin. `foregroundColor(.clear)` efface le texte, `tint(.clear)` efface le
    /// curseur et la surbrillance de sélection, et la vue reste **pleinement** touchable et
    /// visible des outils d'accessibilité — ce qu'`opacity(0)` aurait coûté.
    private var champInvisible: some View {
        TextField("", text: lienCode)
            .font(.custom("HelveticaNeue-Medium", size: 22))
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($saisieActive)
            .foregroundColor(.clear)
            .tint(.clear)
            .contentShape(Rectangle())
            .onChange(of: codeComplet) { _, complet in
                // Le code est complet : le clavier n'a plus rien à recevoir. Un appui sur
                // une case le rappelle.
                if complet { saisieActive = false }
            }
            .onSubmit { saisieActive = false }
            // Rejoint, le code ne se modifie plus : il a servi.
            .disabled(rejoint != nil)
            .accessibilityLabel(t("championnat.codeInvitation"))
            .accessibilityValue(valeurAccessible)
            .accessibilityHint(t("rejoindre.a11y.aide"))
    }

    /// Le lien du champ, qui **filtre en écrivant**.
    ///
    /// > **Mesuré au simulateur, et c'est le piège de cet écran.** Filtrer après coup —
    /// > laisser le champ écrire, puis corriger dans un `onChange` — perd des caractères
    /// > dès que la frappe est rapide : la correction réécrit le texte du champ pendant
    /// > qu'il traite les touches suivantes, et elles tombent. Un code tapé au clavier
    /// > matériel ou collé arrivait amputé de moitié. Le filtre appartient donc au
    /// > **setter** du lien : une seule écriture par touche, et rien à rattraper.
    private var lienCode: Binding<String> {
        Binding(
            get: { code },
            set: { saisie in
                code = Self.nettoyer(saisie)
                // Le refus parlait d'un autre code.
                erreur = nil
            }
        )
    }

    /// Le code épelé, caractère par caractère : lu d'une traite, « 7K2P4M » devient un mot
    /// que personne ne peut recopier.
    private var valeurAccessible: String {
        code.isEmpty ? t("rejoindre.a11y.vide") : codeNormalise.map(String.init).joined(separator: " ")
    }

    /// Lettres et chiffres latins, six au plus. **La casse n'y touche pas** : voir
    /// ``codeNormalise``.
    ///
    /// **Écrit ici et nulle part ailleurs** : la frappe, le collage d'un code reçu par
    /// message et la dictée passent tous les trois par cette fonction.
    private static func nettoyer(_ saisie: String) -> String {
        let retenus = saisie.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return String(retenus.prefix(longueurCode))
    }

    /// La mesure de la rangée. `GeometryReader` en arrière-plan d'une vue dont la largeur
    /// est déjà fixée (`maxWidth: .infinity`) : il lit, il ne contraint pas, et il n'y a
    /// donc pas de boucle de mise en page.
    private var mesureLargeur: some View {
        GeometryReader { geometrie in
            Color.clear.preference(
                key: LargeurRangee.self,
                value: geometrie.size.width
            )
        }
        .onPreferenceChange(LargeurRangee.self) { largeur in
            guard largeur > 0 else { return }
            let nombre = CGFloat(Self.longueurCode)
            coteCase = (largeur - espacementCases * (nombre - 1)) / nombre
        }
    }

    // MARK: - Le bouton

    /// **L'écran n'a qu'une action**, et le bouton ne s'allume que lorsqu'elle est possible
    /// — mêmes encres et même bascule que « Créer le championnat », parce que c'est le même
    /// bouton à deux endroits.
    ///
    /// **Rejoint, il devient le chemin vers le championnat** — même place, même forme.
    @ViewBuilder
    private var boutonRejoindre: some View {
        if let rejoint {
            NavigationLink {
                ChampionnatDetailView(championnat: rejoint, mesChampionnats: mesChampionnats)
            } label: {
                Text(t("championnat.voir"))
                    .habillageBoutonPrincipal(actif: true)
            }
            .buttonStyle(StyleAppui(.bouton))
            .shadow(color: Color.secondaire.opacity(0.16), radius: 17, y: 14)
        } else {
            boutonEnvoi
        }
    }

    private var boutonEnvoi: some View {
        Button(action: rejoindre) {
            ZStack {
                // Le libellé reste en place, invisible, sous le spinner : le bouton ne
                // change pas de taille, et le texte revient à l'identique en cas d'échec.
                Text(t("rejoindre.bouton")).opacity(envoi ? 0 : 1)
                if envoi { ProgressView().tint(.encreSurAplat) }
            }
            .habillageBoutonPrincipal(actif: codeComplet)
        }
        .buttonStyle(StyleAppui(.bouton))
        .disabled(!codeComplet || envoi)
        .accessibilityLabel(envoi ? t("rejoindre.a11y.enCours") : t("rejoindre.bouton"))
        // Couleur et opacité seulement, jamais une géométrie : rien ne bouge sous le doigt,
        // et le repli `accessibilityReduceMotion` est donc inutile ici.
        .animation(Mouvement.entree(0.18), value: codeComplet)
        .shadow(color: Color.secondaire.opacity(codeComplet ? 0.16 : 0), radius: 17, y: 14)
    }
}

// MARK: - Mesure

/// La largeur de la rangée de cases, remontée de la mise en page vers la vue.
private struct LargeurRangee: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    NavigationStack {
        RejoindreChampionnatView(mesChampionnats: MesChampionnats())
    }
}
