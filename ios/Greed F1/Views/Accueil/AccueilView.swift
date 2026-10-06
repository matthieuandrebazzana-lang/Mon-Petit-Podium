import SwiftUI

/// Onglet **Accueil** — salutation, Grand Prix suivant, championnats, deux actions.
///
/// Référence visuelle : `Ressources/Screenshots/screen-04-accueil_haut.PNG` et
/// `screen-05-accueil-bas.PNG`, écran par écran.
///
/// > **Tout est réel.** Les championnats viennent de ``MesChampionnats``
/// > (`GET /championnats/moi`), le Grand Prix suivant de ``ProchainGrandPrix`` — une
/// > lecture **directe** de Supabase, qui n'attend pas le réveil de Railway. Son décompte
/// > est celui d'``EcheancePronostics``, le seul calcul d'échéance de l'app.
///
/// **Rien n'est dessiné en SwiftUI de ce qui existe en SVG** (`ios/CLAUDE.md` §3) : le
/// drapeau, le tracé du circuit, le damier et les deux logos d'action sont des assets,
/// extraits des planches par `ios/scripts/extraire-gp.mjs` et `decouper-icones.sh`.
struct AccueilView: View {

    @ObservedObject var viewModel: AuthViewModel
    @ObservedObject var mesChampionnats: MesChampionnats
    /// L'onglet de ``BarreNavigation`` : l'avatar de l'en-tête y bascule sur le profil.
    @Binding var ongletActif: BarreNavigation.Onglet

    /// Marge latérale commune à tous les blocs — la même que `LandingView`, sans quoi les
    /// deux écrans ne s'aligneraient pas au passage de l'un à l'autre.
    private let margeLaterale: CGFloat = 16

    /// Possédé par l'écran, relu à chaque apparition — pas de cache de session (§7.6).
    @StateObject private var prochainGP = ProchainGrandPrix()

    /// Grands Prix restants — lus sur la liste de la saison, voir ``GPRestants``.
    private var grandsPrixRestants: Int { GPRestants.compte }

    /// Le chemin du parcours de pronostics — voir ``EtapePronos``.
    @State private var cheminPronos: [EtapePronos] = []

    /// La bande de la pile dépliée en aperçu — voir ``PileChampionnats``. Tenue ici parce
    /// qu'un tap **n'importe où** hors de la pile la referme.
    @State private var apercuPile: UUID?

    var body: some View {
        // L'accueil est la **racine de sa propre pile** : c'est de ses deux cartes
        // d'action que part la création d'un championnat. Une pile par onglet, et non
        // une pile autour de la barre — sinon le retour ramènerait sur un autre onglet
        // que celui d'où l'on est parti.
        // Le chemin est **explicite** parce que le récapitulatif doit pouvoir revenir ici
        // d'un coup, trois écrans plus haut (``EtapePronos``). Les deux cartes d'action
        // gardent leurs `NavigationLink` classiques : elles n'ont rien à remonter.
        NavigationStack(path: $cheminPronos) {
            ZStack {
                Color.fondPrincipal
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        entete

                        Spacer().frame(height: 12)
                        blocGrandPrix

                        titreSection(t("accueil.mesChampionnats"))

                        Spacer().frame(height: 10)
                        listeChampionnats

                        Spacer().frame(height: 10)
                        actions

                        Spacer().frame(height: 20)
                        blocSaison

                        Spacer().frame(height: 28)
                        versionAffichee
                    }
                    .padding(.horizontal, margeLaterale)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    // Un tap hors de la pile referme l'aperçu. Les boutons de l'écran
                    // passent avant ce geste, et il n'existe que pendant un aperçu.
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture().onEnded {
                            withAnimation(Mouvement.pile) { apercuPile = nil }
                        },
                        including: apercuPile == nil ? .subviews : .all
                    )
                }
            }
            // Pas de titre : le bouton de retour des écrans poussés d'ici affiche alors le
            // « Retour » générique du système, comme la capture de référence.
            .toolbar(.hidden, for: .navigationBar)
            .etapesPronos(libelleRetour: t("onglet.accueil"),
                          avancer: { cheminPronos.append($0) }) { cheminPronos.removeAll() }
            // Rechargée à chaque apparition, pas de cache de session (§7.6).
            .task { await mesChampionnats.charger() }
            .task { await prochainGP.charger() }
            // Retour du parcours de pronostics : une grille vient peut-être d'être envoyée.
            .onChange(of: cheminPronos.isEmpty) { _, vide in
                if vide { Task { await prochainGP.relirePronostics() } }
            }
        }
    }

    // MARK: - En-tête

    /// Avatar seul sur la première rangée, salutation dessous : c'est la composition de la
    /// barre collante de la version web, dont le titre compact reste effacé tant que
    /// l'écran n'a pas défilé.
    private var entete: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                // Un bouton qui **change d'onglet**, pas un lien qui pousse : le profil a
                // sa place dans la barre, et un second exemplaire empilé ici ferait deux
                // chemins de retour vers le même écran.
                Button {
                    ongletActif = .profil
                } label: {
                    Avatar(pseudo: pseudoAffiche, photo: viewModel.photoProfil)
                }
                .buttonStyle(StyleAppui(.bouton))
            }
            .frame(height: 44)   // plancher tactile iOS

            Spacer().frame(height: 12)

            Text(t("accueil.salut", pseudoAffiche))
                .font(.titreLg)
                .tracking(Tracking.titreLg)
                .foregroundColor(.texte)        // 15,37:1 sur le beige
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 4)

            // **`grisSecondaire` et non `texteDoux`.** La version web pose ici son
            // `#999999`, qui ne vaut que 2,52:1 sur le beige — sous le plancher de 4,5:1
            // d'un texte ordinaire. `#6B6B6B` y tient 4,71:1 pour un gris que l'œil ne
            // distingue pas du premier. Le contraste se mesure (`ios/CLAUDE.md` §3).
            Text(t("accueil.saisonF1"))
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundColor(.grisSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Repli sur « pilote » : une session peut être ouverte sans métadonnée `pseudo`
    /// (comptes créés avant que l'inscription ne la pose). Un écran ne montre jamais un
    /// trou à la place d'un nom.
    private var pseudoAffiche: String {
        viewModel.pseudo.isEmpty ? t("accueil.pilote") : viewModel.pseudo
    }

    // MARK: - Le Grand Prix suivant

    /// Le widget, sa silhouette pendant le premier chargement, ou l'échec rejouable. **Aucun
    /// Grand Prix à venir ⇒ rien du tout**, espacement compris : un bloc vide promettrait
    /// une course que la base ne connaît pas.
    @ViewBuilder private var blocGrandPrix: some View {
        switch prochainGP.etat {
        case .chargement:
            SilhouetteWidget()
            Spacer().frame(height: 24)

        case .echec(let erreur):
            EchecChargement(erreur: erreur) {
                Task { await prochainGP.charger() }
            }
            Spacer().frame(height: 24)

        case .pret(let gp?):
            WidgetGrandPrix(grandPrix: gp, aDesPronostics: prochainGP.aDesPronostics)
            Spacer().frame(height: 24)   // changement de sujet : 24 pt (§4.6)

        case .pret(nil):
            Spacer().frame(height: 12)
        }
    }

    // MARK: - Sections

    /// Titre de section. **L'encre est `grisSecondaire` (#6B6B6B), pas `texteDoux`** : sur
    /// le beige `#F5F0EB` le premier mesure **4,71:1**, le second 2,52:1 — sous le plancher
    /// de 4,5:1 d'un texte de 11 pt.
    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.label)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Les championnats en paquet de cartes — voir ``PileChampionnats``. **Aucun
    /// championnat ⇒ rien**, comme la liste qu'il remplace : les deux cartes d'action,
    /// juste en dessous, sont l'état vide.
    private var listeChampionnats: some View {
        EtatMesChampionnats(mesChampionnats: mesChampionnats) { championnats in
            if !championnats.isEmpty {
                PileChampionnats(
                    championnats: championnats,
                    mesChampionnats: mesChampionnats,
                    idUtilisateur: viewModel.profil?.id,
                    apercu: $apercuPile
                )
            }
        }
    }

    /// Les deux cartes d'action, dont la composition vit dans ``ActionsChampionnat``
    /// — la liste des championnats pose exactement le même bloc.
    private var actions: some View { ActionsChampionnat(mesChampionnats: mesChampionnats) }

    /// La ligne qui ferme l'écran. Elle répond à un vrai défaut de composition — sous une
    /// liste d'un ou deux championnats, le bas de l'écran restait vide sur toute sa moitié.
    private var blocSaison: some View {
        Text(GPRestants.libelle(grandsPrixRestants))
            .font(.custom("HelveticaNeue-Medium", size: 13))
            .foregroundColor(.secondaire)       // 9,32:1 sur le beige
            .frame(maxWidth: .infinity)
    }

    private var versionAffichee: some View {
        Text(t("accueil.version", Bundle.main.versionAffichee))
            .font(.labelSm)
            .tracking(Tracking.label)
            .textCase(.uppercase)
            .foregroundColor(.grisSecondaire)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Avatar

/// La pastille du compte : sa photo de profil, ou son initiale sur la teinte de la marque.
///
/// **Même diamètre dans les deux cas** — seul le contenu change, jamais la composition de
/// la barre. La photo est chargée par `AsyncImage` : tant qu'elle n'est pas là, c'est
/// l'initiale qui tient la place, et non un disque vide.
private struct Avatar: View {

    let pseudo: String
    let photo: URL?

    private let diametre: CGFloat = 44

    var body: some View {
        Group {
            if let photo {
                AsyncImage(url: photo) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initiale
                }
            } else {
                initiale
            }
        }
        .frame(width: diametre, height: diametre)
        .clipShape(Circle())
        // Une photo en `scaledToFill` déborde du disque : la cible reste le disque.
        .contentShape(Circle())
        .accessibilityLabel(t("accueil.monProfil"))
    }

    private var initiale: some View {
        Color.primaire
            .overlay {
                Text(pseudo.first.map { String($0).uppercased() } ?? "?")
                    .font(.custom("HelveticaNeue-Medium", size: 18))
                    .foregroundColor(.white)      // 10,88:1 sur #800111
            }
    }
}

// MARK: - Widget du prochain Grand Prix

/// La pièce maîtresse de l'écran d'entrée : le drapeau du pays hôte, le tracé de son
/// circuit, et deux cases de statut.
///
/// **L'ordre des calques est celui de la version web, et il ne se défait pas** : le
/// drapeau tout en bas · ``LueurHaute`` · le voile calculé · l'assombrissement uniforme ·
/// le contenu seul. Tout ce qui éclaircit passe SOUS le voile, sinon la garantie de 3:1
/// de ``ApparenceDrapeau`` n'en est plus une.
///
/// **L'assombrissement de 15 % porte sur tout le widget, jamais sur la seule bande du
/// tracé.** Sur un drapeau à bande répétée — les Pays-Bas, rouge / blanc / bleu — une
/// bande assombrie au milieu coupait la surface en deux : la bande du haut paraissait plus
/// vive que celle du bas, et l'œil lisait un défaut de calage plutôt qu'une intention.
private struct WidgetGrandPrix: View {

    let grandPrix: GrandPrixEnBase
    /// Au moins un pronostic du joueur est en base pour ce Grand Prix — `nil` tant qu'on ne
    /// sait pas. Ne décide que du bouton : la destination, ``EntreePronosView``, choisit
    /// seule entre cotes et récap.
    let aDesPronostics: Bool?

    @Environment(\.modePrevisualisation) private var previsualisation

    /// Hauteur de la bande du tracé. C'est la moitié du widget : la réduire ferait sauter
    /// l'accueil au moment précis où le joueur le regarde.
    private let hauteurTrace: CGFloat = 160

    /// Rembourrage intérieur. La bande du tracé l'annule pour toucher les deux bords.
    private let rembourrage: CGFloat = 20

    private var apparence: ApparenceDrapeau? { ApparenceDrapeau.pour(slug: grandPrix.slug) }

    /// Le même Grand Prix, dans le vocabulaire statique de ``CalendrierView`` — c'est ce que
    /// demande ``DetailGPView``, qui ne connaît que ``GrandPrixSaison``. `nil` si le slug est
    /// hors de la liste statique, ce qui ne devrait pas arriver : la base ne connaît que les
    /// Grands Prix de la saison.
    private var grandPrixSaison: GrandPrixSaison? {
        guard var saison = GrandPrixSaison.saison2026.first(where: { $0.slug == grandPrix.slug })
        else { return nil }
        saison.enBase = grandPrix
        saison.etatConnu = true
        return saison
    }

    /// « 26 septembre 2026 », **en heure locale du téléphone** (§7.4) — c'est un instant
    /// servi par la base, pas une date nue : le formater est juste.
    private var date: String {
        grandPrix.dateCourse?.formatted(.dateTime.day().month(.wide).year()
            .locale(localeInterface)) ?? t("commun.dateAConfirmer")
    }

    /// « 26 sept. 2026 » — l'en-tête quand la pastille « Pronos ouverts » y est posée.
    private var dateAbregee: String {
        grandPrix.dateCourse?.formatted(.dateTime.day().month(.abbreviated).year()
            .locale(localeInterface)) ?? t("echeance.aConfirmer")
    }

    /// « 07h00 » — l'écriture du projet, avec le « h » ; « 07:00 » en anglais.
    private var heureDepart: String {
        grandPrix.dateCourse.map(heureInterface) ?? t("echeance.aConfirmer")
    }

    private func echeance(le maintenant: Date = .now) -> EcheancePronostics {
        EcheancePronostics.pour(statut: grandPrix.statut, dateCourse: grandPrix.dateCourse,
                                dateQualifications: grandPrix.dateQualifications, le: maintenant)
    }

    /// **Les pronostics sont ouverts** — la même condition que le décompte « Fermeture
    /// dans », et celle de la pastille « Pronos ouverts ».
    ///
    /// La prévisualisation admin lève cette seule condition, comme `cotesArretees(gp) ||
    /// previsualisation` côté web — rien d'autre (`decisions.md` §15 bis).
    private var ouvert: Bool {
        EcheancePronostics.cotesArretees(statut: grandPrix.statut, dateCourse: grandPrix.dateCourse)
            || previsualisation
    }

    /// L'état du widget, dans le vocabulaire du calendrier — ``EtatGp``. Pas
    /// ``EtatGp/pour(_:le:)`` : la lecture directe ne ramène pas les marchés, et c'est
    /// ``ouvert`` qui fait foi ici, comme pour le décompte.
    private var etat: EtatGp {
        if grandPrix.statut == "termine" { return .termine }
        if ouvert { return .ouvert }
        if let depart = grandPrix.dateCourse, depart <= .now { return .ferme }
        return .aVenir
    }

    /// Le libellé du bouton du bas, `nil` quand il n'y a rien à faire.
    ///
    /// - **Ouvert** : « Voir mes pronos » s'il en a en base, sinon « Faire mes pronos ».
    /// - **Fermé** : « Voir mes pronos » s'il en a, sinon rien — plus rien à saisir.
    /// - **À venir** : rien, avant le relevé des cotes il n'y a rien à saisir.
    /// - **Existence inconnue** (lecture en cours ou échouée) : rien plutôt qu'un bouton
    ///   faux — le widget reste tappable, ``EntreePronosView`` tranche.
    private var libelleBouton: String? {
        switch etat {
        case .ouvert:
            guard let aDesPronostics else { return nil }
            return aDesPronostics ? t("accueil.voirPronos") : t("accueil.faireMesPronos")
        case .ferme:
            return aDesPronostics == true ? t("accueil.voirPronos") : nil
        case .aVenir: return nil
        case .termine: return t("accueil.voirResultats")
        }
    }

    @ViewBuilder var body: some View {
        if let libelleBouton {
            lien(libelleBouton)
        } else if let grandPrixSaison {
            // **À venir ou fermé** : rien à saisir, mais le widget reste tappable — c'est la
            // fiche du week-end qui répond, le même `NavigationLink` que ``CalendrierView``
            // pose sur ses cartes dans les mêmes états.
            NavigationLink {
                DetailGPView(grandPrix: grandPrixSaison)
            } label: {
                surface
            }
            .buttonStyle(StyleAppui(.grandeSurface))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                t("accueil.a11y.prochainGP", grandPrix.nomAffiche, date, heureDepart, echeance().phrase)
            )
            .accessibilityHint(t("accueil.a11y.voirFiche"))
            .accessibilityAddTraits(.isButton)
        } else {
            surface
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    t("accueil.a11y.prochainGP", grandPrix.nomAffiche, date, heureDepart, echeance().phrase)
                )
        }
    }

    private var surface: some View {
        contenu
            .padding(rembourrage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { fond }
            .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
            // Le drapeau en `scaledToFill` déborde du widget : `clipShape` le rogne à
            // l'œil, pas au doigt. La cible est la forme visible, et rien d'autre.
            .contentShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
            .ombreAplat()
    }

    @ViewBuilder private func lien(_ libelle: String) -> some View {
        if etat == .termine {
            // **Ses propres pronos d'abord** : le récapitulatif de sa grille, ou le
            // classement officiel s'il n'a rien joué (``EntreePronosView``).
            NavigationLink(value: EtapePronos.resultats(GrandPrixPronos(
                id: grandPrix.id,
                nom: grandPrix.nom,
                slug: grandPrix.slug,
                sousTitre: date
            ), date: date)) {
                surface
            }
            .buttonStyle(StyleAppui(.grandeSurface))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                t("accueil.a11y.dernierGP", grandPrix.nomAffiche, date)
                + (StatutResultats.estProvisoire(grandPrix.statutResultats)
                   ? " \(StatutResultats.detail)" : "")
            )
            .accessibilityHint(libelle)
            .accessibilityAddTraits(.isButton)
        } else {
            lienPronos(libelle)
        }
    }

    private func lienPronos(_ libelle: String) -> some View {
        // **Le widget EST le bouton « Pronostiquer » de l'accueil.** La version web pose un
        // bouton nommé à l'intérieur du bloc ; ici c'est le bloc entier qui mène au tableau
        // des cotes, et le libellé accessible ci-dessous le nomme. Un bouton dans un bouton
        // n'existe pas, et deux cibles empilées se disputeraient le doigt.
        //
        // La destination est celle de la version web : `/cotes`, jamais la saisie — on
        // ajoute ses paris bonus avant de pronostiquer, et un bouton qui sauterait cette
        // étape mentirait sur son libellé. Une grille déjà enregistrée ouvre, elle, son
        // récapitulatif (``EntreePronosView``).
        NavigationLink(value: EtapePronos.entree(GrandPrixPronos(
            id: grandPrix.id,
            nom: grandPrix.nom,
            slug: grandPrix.slug,
            sousTitre: t("accueil.sousTitreGP", date, heureDepart)
        ))) {
            surface
        }
        .buttonStyle(StyleAppui(.grandeSurface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            t("accueil.a11y.prochainGP", grandPrix.nomAffiche, date, heureDepart, echeance().phrase)
        )
        .accessibilityHint(libelle)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Les calques du fond

    @ViewBuilder private var fond: some View {
        if let apparence {
            ZStack {
                // **`scaledToFill` et non `scaledToFit`** : le drapeau couvre toute la
                // surface, rogné sur son plus grand côté, jamais déformé ni cerné de vide.
                // C'est le pendant exact d'`object-fit: cover`.
                Image("flag-\(grandPrix.slug)")
                    .resizable()
                    .scaledToFill()

                LueurHaute()
                Color.black.opacity(apparence.voile)
                Color.black.opacity(0.15)
            }
        } else {
            // Pays hors table : l'aplat de la marque, et aucun assombrissement — il n'a ni
            // bande ni rupture à corriger, le voiler ne ferait que l'éteindre.
            ZStack {
                Color.primaire
                LueurHaute()
            }
        }
    }

    // MARK: Le contenu

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            enTete

            Spacer().frame(height: 12)
            nomDuGrandPrix

            Spacer().frame(height: 16)
            bandeTrace

            Spacer().frame(height: 16)
            cases

            if let libelleBouton {
                Spacer().frame(height: 12)
                bouton(libelleBouton)
            }
        }
    }

    /// Le bouton du bas. **Un habillage, pas un `Button`** : le widget entier est déjà la
    /// cible (voir ``lienPronos(_:)``), et un bouton dans un bouton se disputerait le doigt.
    /// Blanc sur le drapeau, encre de la marque : 10,88:1.
    private func bouton(_ libelle: String) -> some View {
        Text("\(libelle) →")
            .font(.custom("HelveticaNeue-Medium", size: 15))
            .foregroundColor(.primaire)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }

    private var enTete: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(t("accueil.prochainGP"))
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(apparence?.pastille ?? Color.white.opacity(0.20))
                .clipShape(Capsule())

            if etat == .termine && StatutResultats.estProvisoire(grandPrix.statutResultats) {
                // Résultats pas encore définitifs (24 h après la course) : la pastille
                // voisine, même matériau et même encre blanche — seul le mot change.
                Text(StatutResultats.mention)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(apparence?.pastille ?? Color.white.opacity(0.20))
                    .clipShape(Capsule())
            }

            if etat == .ouvert {
                // La pastille du calendrier — ``EtatGp/fondPastille`` et
                // ``EtatGp/encrePastille`` : noir sur ambre, 7,86:1.
                Text(EtatGp.ouvert.libelle)
                    .font(.labelSm)
                    .tracking(Tracking.label)
                    .textCase(.uppercase)
                    .foregroundColor(EtatGp.ouvert.encrePastille)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(EtatGp.ouvert.fondPastille)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 8)

            // Les deux pastilles côte à côte ne laissent pas la place au mois écrit en
            // entier : « 26 sept. 2026 » plutôt qu'une date tronquée.
            Text(etat == .ouvert ? dateAbregee : date)
                .font(.custom(encreDouceGrasse ? "HelveticaNeue-Medium" : "HelveticaNeue", size: 11))
                .foregroundColor(encreDouce)
                .ombrePortee(apparence?.ombreNom ?? false)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// Le nom du Grand Prix, **centré au-dessus de son circuit** : les deux se lisent alors
    /// comme un seul objet, titre et illustration. Un nom aligné à gauche au-dessus d'un
    /// dessin centré ne donnerait pas cela.
    ///
    /// 26 pt, avec le crénage négatif qu'/apple-design §15 impose au-delà de 24 : sans lui,
    /// les lettres d'un titre s'éloignent à mesure qu'il grandit.
    private var nomDuGrandPrix: some View {
        Text(grandPrix.nomAffiche)
            .font(.custom("HelveticaNeue-Medium", size: 26))
            .tracking(-0.52)                              // −0,02em × 26
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .ombrePortee(apparence?.ombreNom ?? false)
            .frame(maxWidth: .infinity)
    }

    /// La bande du tracé — le **vrai** circuit du pays hôte, extrait d'`assets/traces.svg`.
    ///
    /// Le rembourrage du widget est annulé : la bande touche les deux bords, ce qui en fait
    /// un registre horizontal de la composition plutôt qu'une image posée dans une marge.
    /// `scaledToFit` met chaque circuit à l'échelle dans cette boîte et le centre — Bakou,
    /// 3,4 fois plus large que haut, remplit la largeur ; Zandvoort, presque carré, remplit
    /// la hauteur. Chacun garde sa vraie forme au lieu d'être étiré.
    ///
    /// Le trait est à 60 % de blanc : sur les drapeaux clairs, une fois le voile et
    /// l'assombrissement posés dessous, il y tient **2,70:1** — c'est un élément décoratif,
    /// pas un porteur de sens, et le nom du Grand Prix dit déjà de quel circuit il s'agit.
    @ViewBuilder private var bandeTrace: some View {
        Image("trace-\(grandPrix.slug)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(.white.opacity(0.60))
            .frame(maxWidth: .infinity)
            .frame(height: hauteurTrace)
            .padding(.horizontal, -rembourrage)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Deux cases plutôt qu'une phrase : un chiffre posé sous son label se lit d'un coup
    /// d'œil, là où « Pronos ouverts · Fermeture dans 2j 14h 32min » demande de lire une
    /// ligne entière pour en extraire la même information.
    ///
    /// **Le décompte bat la seconde**, parce qu'il en affiche dans la dernière heure. Seul
    /// le texte change : aucune animation — un chiffre qui bouge toutes les secondes n'a
    /// pas à attirer l'œil davantage (portier `/animate`, aucun jeton nouveau).
    private var cases: some View {
        TimelineView(.periodic(from: .now, by: 1)) { contexte in
            let echeance = echeance(le: contexte.date)
            HStack(spacing: 8) {
                caseStatut(label: t("echeance.depart"), valeur: heureDepart)
                caseStatut(label: echeance.label, valeur: echeance.texte ?? echeance.substitut)
            }
        }
    }

    /// Surface posée *à l'intérieur* du widget : rayon `champ`, donc **aucune ombre** (§4.7).
    private func caseStatut(label: String, valeur: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.labelSm)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundColor(encreDouce)
                .lineLimit(1)

            Text(valeur)
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(apparence?.surface ?? Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Rayon.champ, style: .continuous))
    }

    private var encreDouce: Color { apparence?.encreDouce ?? .encreSecondaire }
    private var encreDouceGrasse: Bool { apparence?.encreDouceGrasse ?? false }
}

/// L'ombre portée du texte posé sur un drapeau à plusieurs bandes. Un seul propriétaire :
/// le nom du Grand Prix et sa date la reçoivent, et elles ne peuvent pas diverger.
private extension View {
    @ViewBuilder func ombrePortee(_ active: Bool) -> some View {
        if active {
            self.shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
        } else {
            self
        }
    }
}

// MARK: - Silhouette

/// Le widget pendant son premier chargement. **Il garde l'aplat rouge et la hauteur du
/// vrai** : c'est le seul aplat de couleur de l'accueil, et le voir passer au gris puis
/// revenir au rouge ferait clignoter l'écran d'entrée — la hauteur tenue évite que la
/// liste des championnats ne saute de 360 pt à l'arrivée des données.
private struct SilhouetteWidget: View {
    var body: some View {
        ZStack {
            Color.primaire
            LueurHaute()
            ProgressView()
                .tint(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: Rayon.bloc, style: .continuous))
        .ombreAplat()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("accueil.a11y.chargementGP"))
    }
}

#Preview {
    AccueilView(viewModel: AuthViewModel(), mesChampionnats: MesChampionnats(),
                ongletActif: .constant(.accueil))
}
