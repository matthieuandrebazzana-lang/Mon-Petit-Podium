import SwiftUI
import UIKit

/// Palette du design system (`docs/design-system.md` §1, `docs/swift-app.md` §4).
/// Un seul propriétaire pour chaque couleur : les écrans ne choisissent jamais leur encre.
///
/// > **Clair et sombre.** Les couleurs qui changent avec l'apparence sont déclarées par
/// > ``Color/init(clair:sombre:)`` — un `UIColor(dynamicProvider:)` que le système résout
/// > à chaque rendu. Une vue n'a donc **jamais** à lire `colorScheme` pour choisir son
/// > encre : elle nomme un jeton, et le jeton suit ``ThemeManager``. Les contrastes de la
/// > colonne sombre sont mesurés sur `#1C1C1E` (fond) et `#2C2C2E` (surfaces).
extension Color {

    /// Principal — **l'aplat** de la marque. Clair `#800111`, blanc dessus **10,88:1**.
    /// Sombre `#C0182A`, blanc dessus **6,17:1**.
    ///
    /// > **Un aplat, pas une encre.** En sombre, `#C0182A` ne tient que **2,76:1** sur le
    /// > fond et **2,26:1** sur une surface — sous le plancher de 3:1 d'un élément
    /// > graphique. Tout rouge posé **en texte ou en trait** passe par ``encrePrimaire``.
    static let primaire = Color(clair: 0x800111, sombre: 0xC0182A)

    /// Principal **en encre** — texte, trait, contour de sélection, onglet actif. Clair
    /// `#800111` (identique à ``primaire``) ; sombre `#FF6961`, **6,03:1** sur le fond et
    /// **4,94:1** sur une surface.
    static let encrePrimaire = Color(clair: 0x800111, sombre: 0xFF6961)

    /// Principal foncé — l'aplat de l'avatar. Clair `#5A000C` ; sombre `#A3142A`, blanc
    /// dessus **7,80:1** — `#5A000C` y disparaîtrait sur la surface (1,2:1).
    static let primaireFonce = Color(clair: 0x5A000C, sombre: 0xA3142A)

    /// Fond de l'app — beige clair `#F5F0EB`, sombre `#1C1C1E`.
    static let fondPrincipal = Color(clair: 0xF5F0EB, sombre: 0x1C1C1E)

    /// Surfaces et cartes — `#FFFFFF`, sombre `#2C2C2E`.
    static let surface = Color(clair: 0xFFFFFF, sombre: 0x2C2C2E)

    /// Texte — `#1A1A1A`, **15,37:1** sur le beige. Sombre `#FFFFFF` : **17,01:1** sur le
    /// fond, **13,94:1** sur une surface.
    static let texte = Color(clair: 0x1A1A1A, sombre: 0xFFFFFF)

    /// Secondaire (marron) — `#543925`, **9,32:1** sur le beige. Sombre `#EBEBF0` :
    /// **14,32:1** sur le fond, **11,73:1** sur une surface — le brun y tomberait à 1,61:1.
    /// C'est l'encre des textes de second rang posés sur le beige : `texteDoux`
    /// n'y tient que 2,52:1 et ne passe pas le plancher de 4,5:1.
    static let secondaire = Color(clair: 0x543925, sombre: 0xEBEBF0)

    /// Texte secondaire — `#999999`. **Réservé aux fonds sombres** : sur le beige comme
    /// sur le blanc il reste sous 3:1. Fixe : il n'est posé que sur des aplats foncés.
    static let texteDoux = Color(hexadecimal: 0x999999)

    /// Gris des labels — `#6B6B6B`. Sombre `#AEAEB2`, le gris secondaire d'iOS : **7,69:1**
    /// sur le fond, **6,30:1** sur une surface. Pas `#EBEBF0` : il se confondrait avec le
    /// texte blanc et la hiérarchie disparaîtrait.
    static let grisSecondaire = Color(clair: 0x6B6B6B, sombre: 0xAEAEB2)

    /// Accent ambre — `#E8A020`, le `--color-accent` de la version web et la teinte du
    /// dessin de `assets/logo.svg`.
    ///
    /// **Elle ne devient JAMAIS une encre.** Sur le blanc elle ne vaut que **2,2:1**,
    /// sous le plancher de 3:1 d'un élément graphique porteur de sens : elle n'est
    /// tenable en dessin que parce que le logo « Rejoindre un championnat » y est
    /// décoratif et que c'est le titre de la carte qui porte le sens.
    ///
    /// **En aplat, elle n'accepte qu'une encre : `texte`**, où elle tient **7,86:1**.
    /// C'est ce qui fait de la pastille « Pronos ouverts » la seule des quatre à garder
    /// sa couleur de fond sur un drapeau — les trois autres passent par du blanc, parce
    /// que leur mot ne tient pas en ambre.
    static let accent = Color(hexadecimal: 0xE8A020)

    /// Jaune vif — `#FFD700`, **l'étoile des favoris** (``EtoileJaune``), et rien d'autre.
    ///
    /// **Ne s'emploie jamais seul** : sur le blanc il ne vaut que **1,40:1**. Il est toujours
    /// cerné d'un trait `texte`, qui porte le contraste de l'élément graphique.
    static let jauneEtoile = Color(hexadecimal: 0xFFD700)

    /// Bleu ardoise — `#2C4A6E`, le `bleu-ardoise` de `frontend/src/lib/couleurs.js`.
    ///
    /// **C'est l'aplat du marché « 2e et 3e du podium »**, et il n'en peint aucun autre :
    /// les deux pronostics obligatoires se distinguent ainsi l'un de l'autre au premier
    /// coup d'œil, le vainqueur gardant le rouge de la marque.
    ///
    /// Le blanc y tient **11,04:1**. C'est en revanche un aplat **plus clair que
    /// `primaire`**, et c'est ce qui oblige ``encreSecondaireClaire`` à exister.
    static let bleuArdoise = Color(hexadecimal: 0x2C4A6E)

    /// Vert sauge — `#4A7C59`. L'encre de ce qui est **consultable et derrière nous** :
    /// la pastille « Terminé » et la bande « Voir les résultats ».
    ///
    /// **Sur du blanc seulement**, où elle tient **4,86:1** — le plus serré des quatre
    /// états, et c'est lui qui a fixé l'opacité de la bande. Sur le beige de l'app elle
    /// tombe à 4,34:1 et ne passe plus le plancher d'un texte ordinaire.
    static let vertSauge = Color(hexadecimal: 0x4A7C59)

    /// Vert sauge **en encre** sur un fond neutre. Clair `#4A7C59` (4,86:1 sur le blanc) ;
    /// sombre `#7BC793`, **8,45:1** sur le fond et **6,92:1** sur une surface — le sauge
    /// y tomberait à 2,87:1.
    static let encreSucces = Color(clair: 0x4A7C59, sombre: 0x7BC793)

    /// Ambre clair — `#FFF8E1`. **Le fond de la tuile du vainqueur**, et d'elle seule : le
    /// 1er se distingue des deux marches du podium, posées sur ``fondPrincipal``.
    ///
    /// Un fond, jamais une encre. `texte` y tient **16,5:1**, `secondaire` **11,0:1**.
    ///
    /// Sombre `#3A3222`, un ambre éteint : le blanc de ``texte`` y tient **12,66:1**.
    static let ambreClair = Color(clair: 0xFFF8E1, sombre: 0x3A3222)

    /// Ambre très pâle — `#FFF3DC`, **le fond du mode d'emploi** de « Fais tes paris », et
    /// de lui seul. `secondaire` y tient **9,60:1**. Sombre : l'ambre éteint `#3A3222` de
    /// ``ambreClair``, où `secondaire` (`#EBEBF0`) tient **10,65:1**.
    static let fondModeEmploi = Color(clair: 0xFFF3DC, sombre: 0x3A3222)
}

// MARK: - Teintes de championnat

/// Les six teintes de championnat — palette Pantone sombre (`docs/swift-app.md` §4.4).
///
/// **Elles ne peignent QU'une carte de championnat et l'en-tête de son écran.** Le texte
/// reste blanc sur les six, et c'est mesuré : de **10,35:1** (tomate séchée) à **18,12:1**
/// (minuit). L'encre secondaire à 70 % n'y descend jamais sous **4,97:1**.
extension Color {

    static let azurite      = Color(hexadecimal: 0x1D2941)   // Azurite
    static let mure         = Color(hexadecimal: 0x2A1F21)   // Blackberry Syrup
    static let aubergine    = Color(hexadecimal: 0x301729)   // Aubergine Gleam
    static let terreau      = Color(hexadecimal: 0x54392D)   // Potting Soil
    static let tomateSechee = Color(hexadecimal: 0x752329)   // Sun-Dried Tomato
    static let minuit       = Color(hexadecimal: 0x16151D)   // Midnight Sky

    /// Les six, dans l'ordre du cycle. Six teintes couvrent six championnats distincts ;
    /// au-delà, le cycle recommence.
    static let teintesChampionnat: [Color] = [
        azurite, mure, aubergine, terreau, tomateSechee, minuit
    ]

    /// Teinte d'un championnat. **Tirée d'une empreinte de son identifiant, jamais de son
    /// rang dans une liste** — sinon la couleur d'un championnat changerait dès qu'un
    /// autre est rejoint ou quitté.
    static func teinteChampionnat(pour identifiant: String) -> Color {
        teintesChampionnat[Int(empreinte(identifiant) % UInt64(teintesChampionnat.count))]
    }

    /// Teinte de l'avatar d'un membre, tirée de **son identifiant** par la même empreinte.
    ///
    /// Elle est donc **stable d'un écran à l'autre et d'un lancement au suivant** : un
    /// membre garde sa couleur dans le classement d'un championnat comme dans celui du
    /// voisin, ce qui est exactement ce qui permet de le repérer d'un coup d'œil.
    ///
    /// **Le décalage de l'empreinte n'est pas cosmétique** : sans lui, un championnat et
    /// son créateur — qui partagent souvent un identifiant proche — tomberaient sur la même
    /// teinte, et l'avatar disparaîtrait dans l'en-tête de sa propre carte.
    ///
    /// Le blanc tient de **10,35:1** à **18,12:1** sur les six teintes : une initiale y est
    /// lisible sans exception.
    static func teinteAvatar(pour identifiant: String) -> Color {
        let decale = empreinte(identifiant) &* 0x27d4_eb2f_1651_8000
        return teintesChampionnat[Int(decale % UInt64(teintesChampionnat.count))]
    }

    /// L'empreinte FNV-1a des deux fonctions ci-dessus, **écrite ici plutôt que reprise du
    /// `hashValue` de Swift** : celui-ci est salé à chaque lancement, et la teinte d'un
    /// championnat comme celle d'un avatar changeraient d'une ouverture de l'app à la
    /// suivante.
    private static func empreinte(_ identifiant: String) -> UInt64 {
        var valeur: UInt64 = 0xcbf2_9ce4_8422_2325
        for octet in identifiant.utf8 {
            valeur = (valeur ^ UInt64(octet)) &* 0x100_0000_01b3
        }
        return valeur
    }

    /// Encre de second rang posée **sur un aplat de couleur** : blanc à **70 %**
    /// (`docs/swift-app.md` §4.4).
    ///
    /// > Pas à 60 % : mesuré au simulateur, le blanc à 60 % composité sur `primaire`
    /// > donne `#D9B3B8`, soit **4,47:1** — sous le plancher de 4,5:1 d'un texte
    /// > ordinaire. À 70 % il y tient **5,75:1**.
    static let encreSecondaire = Color.encreSurAplat.opacity(0.70)
}

// MARK: - Teintes des marchés bonus

/// Les six teintes des marchés bonus de « Fais tes paris » — **une par marché, dans l'ordre
/// de la liste**, le cycle recommençant au septième. Douces, et distinctes du rouge du
/// vainqueur comme du bleu ardoise du podium, qui restent les deux seuls aplats obligatoires.
///
/// **Mesurées, pas choisies** : le blanc tient sur chacune, et chacune tient sur le blanc
/// (la pastille de l'en-tête l'écrit en encre) — terracotta **6,01:1**, sauge **4,86:1**,
/// ocre **5,31:1**, mauve **6,26:1**, orange doux **4,96:1**, menthe **5,11:1**.
extension Color {

    static let terracotta = Color(hexadecimal: 0x9E4A3A)
    static let ocre       = Color(hexadecimal: 0x8A6516)
    static let mauve      = Color(hexadecimal: 0x7D5279)
    static let orangeDoux = Color(hexadecimal: 0xA65E14)
    static let menthe     = Color(hexadecimal: 0x2D7A6B)

    /// Ordonnées pour que deux voisines ne soient jamais deux chaudes ou deux vertes.
    static let teintesMarcheBonus: [Color] = [
        terracotta, vertSauge, ocre, mauve, orangeDoux, menthe
    ]
}

// MARK: - Teintes des cartes du récapitulatif

/// Le fond d'une carte du récapitulatif : **la couleur de sa catégorie**, posée à
/// ``opaciteTeinteCarte`` sur ``surface``. Trois teintes seulement — tous les bonus
/// partagent l'ocre.
///
/// > **En sombre, la teinte s'éclaircit.** Les aplats foncés à 18 % sur `#2C2C2E` ne se
/// > distinguaient plus de la surface (bleu ardoise : 1,07:1). Les variantes claires
/// > tiennent **1,30 à 1,41:1** face à la surface — visibles, jamais saturées.
///
/// Mesuré damier compris (6 %) : ``texte`` ≥ **11,23:1** en clair, ≥ **9,60:1** en sombre ;
/// ``encreSurTeinte`` ≥ **5,46:1** et ≥ **5,70:1**. Le ``grisSecondaire`` n'y tenait que
/// 3,44:1 en clair — c'est ce qui oblige ``encreSurTeinte`` à exister.
extension Color {

    static let opaciteTeinteCarte: Double = 0.18

    /// Clair `#800111` (``primaire``), sombre `#FF6961` (``encrePrimaire``).
    static let teinteVainqueur = Color.encrePrimaire
    /// Clair `#2C4A6E` (``bleuArdoise``), sombre `#7A9CC6`.
    static let teintePodium = Color(clair: 0x2C4A6E, sombre: 0x7A9CC6)
    /// Clair `#8A6516` (``ocre``), sombre `#D4A84B`.
    static let teinteBonus = Color(clair: 0x8A6516, sombre: 0xD4A84B)

    /// Encre de second rang sur une carte teintée — clair `#4D4D4D`, sombre `#C7C7CC`.
    static let encreSurTeinte = Color(clair: 0x4D4D4D, sombre: 0xC7C7CC)
}

extension Color {
    /// `Color(hexadecimal: 0x800111)` — une seule façon d'écrire un code hexadécimal.
    init(hexadecimal valeur: UInt32) {
        self.init(
            red: Double((valeur >> 16) & 0xFF) / 255,
            green: Double((valeur >> 8) & 0xFF) / 255,
            blue: Double(valeur & 0xFF) / 255
        )
    }

    /// Une couleur **qui suit l'apparence** — `clair` en mode clair, `sombre` en mode
    /// sombre. Résolue par le système à chaque rendu (`UIColor(dynamicProvider:)`), donc
    /// aussi par UIKit : barre d'onglets, alertes, feuilles.
    init(clair: UInt32, sombre: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hexadecimal: traits.userInterfaceStyle == .dark ? sombre : clair))
        })
    }

    /// Variante qui prend deux couleurs déjà déclarées — une opacité, un jeton fixe.
    init(clair: Color, sombre: Color) {
        self.init(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? sombre : clair)
        })
    }
}

// MARK: - Encres fixes

/// Les encres qui **ne suivent pas** l'apparence. Elles sont posées sur un aplat qui, lui,
/// ne change pas de luminosité d'un mode à l'autre — rouge, teinte de championnat, marché,
/// drapeau voilé, ambre — et leur contraste se mesure contre cet aplat, pas contre le fond.
///
/// > **Pourquoi des jetons et pas `.white`.** Un `.white` écrit dans une vue ne dit pas
/// > s'il est l'encre d'un aplat (à garder) ou le fond d'une carte (à inverser en sombre).
/// > Le jeton le dit, et un `grep` de `.white` hors de ce fichier ne doit rien trouver.
extension Color {

    /// Encre **sur un aplat de couleur** — blanc, dans les deux modes.
    static let encreSurAplat = Color.white

    /// Encre **sur un aplat clair** — ``accent``, ``jauneEtoile``, une livrée claire : le
    /// `#1A1A1A` du mode clair, **dans les deux modes**. Sur l'ambre, **7,86:1** ; le blanc
    /// de ``texte`` sombre n'y vaudrait que 2,2:1.
    static let encreSurClair = Color(hexadecimal: 0x1A1A1A)

    /// Voile **noir** — sur un drapeau, une photo, le recadrage. Toujours noir : il
    /// assombrit une image, il ne suit pas l'interface.
    static let voile = Color.black

    /// Encre des quatre ombres (``View/ombreCarte()``…). Clair : le brun ``secondaire`` du
    /// design system. Sombre : noir — le `#EBEBF0` de ``secondaire`` y ferait un halo clair.
    static let encreOmbre = Color(clair: Color(hexadecimal: 0x543925), sombre: .black)

    /// Filet d'un aplat **sombre** posé sur le fond sombre — teintes de championnat, aplats
    /// de marché. Invisible en clair ; blanc à **10 %** en sombre, où Minuit `#16151D` ne
    /// tient que **1,06:1** contre `#1C1C1E` et disparaîtrait sans lui.
    static let filetAplat = Color(clair: .clear, sombre: Color.white.opacity(0.10))

    /// **Les valeurs du mode clair, figées** — pour ce qui est posé **sur une image** qui ne
    /// change pas d'apparence : la pastille d'état d'une carte de Grand Prix, sur son
    /// drapeau. Elle reste une pastille blanche aux encres mesurées sur le blanc (rouge
    /// **10,88:1**, marron **10,55:1**) ; en jetons dynamiques elle deviendrait une pastille
    /// `#2C2C2E` où le vert sauge ne tiendrait plus que 2,87:1.
    static let surfaceFixe    = Color(hexadecimal: 0xFFFFFF)
    static let primaireFixe   = Color(hexadecimal: 0x800111)
    static let secondaireFixe = Color(hexadecimal: 0x543925)

    /// Le blanc **d'une livrée** — l'aileron par défaut d'une voiture, quand sa couleur est
    /// illisible. Une peinture, pas une encre d'interface : elle ne suit pas l'apparence.
    static let blancLivree = Color(hexadecimal: 0xFFFFFF)

    /// La ligne médiane de la piste (``SolPiste``) : le `#1d1d1b` de la planche à **11 %**
    /// en clair, le blanc à 11 % en sombre — le noir disparaîtrait sur le sol sombre.
    static let ligneMedianePiste = Color(clair: Color(hexadecimal: 0x1D1D1B).opacity(0.11),
                                         sombre: Color.white.opacity(0.11))

    /// Le damier **du fond du widget « Classement »** dès qu'il porte du texte de
    /// classement (« Classement », « Classement + piste », état neutre) — le bordeaux en
    /// clair, le blanc en sombre, **opacité comprise** : une texture uniforme, sans fondu.
    ///
    /// > **2 % en clair et non les 5 % demandés** : ``grisSecondaire`` (rangs au-delà du
    /// > podium) ne tient que **4,71:1** sur le beige nu et tombe à **4,28:1** au pire pixel
    /// > d'un damier à 5 % ; il faut ≤ 2,2 %. À 2 % : **4,53:1**. En sombre, 5 % :
    /// > ``encrePrimaire`` **5,26:1**, ``grisSecondaire`` 6,71:1, ``texte`` 14,84:1.
    static let damierWidget = Color(clair: Color(hexadecimal: 0x800111).opacity(0.02),
                                    sombre: Color.white.opacity(0.05))

    /// Le damier du widget quand **la piste est seule** — 8 % dans les deux modes, seul
    /// calque sur le fond. Seul texte posé dessus : le nom du championnat en ``texte``,
    /// **13,17:1** en clair, **13,52:1** en sombre au pire pixel.
    static let damierWidgetPiste = Color(clair: Color(hexadecimal: 0x800111).opacity(0.08),
                                         sombre: Color.white.opacity(0.08))
}

// MARK: - Typographie

/// Typographie du design system (`docs/swift-app.md` §4.5).
///
/// **Helvetica Neue partout. Graisses 400 et 500 uniquement** (`ios/CLAUDE.md` §3).
extension Font {
    static let titre   = Font.custom("HelveticaNeue-Medium", size: 28)
    static let titreLg = Font.custom("HelveticaNeue-Medium", size: 30)
    static let score   = Font.custom("HelveticaNeue-Medium", size: 32)
    static let scoreLg = Font.custom("HelveticaNeue-Medium", size: 44)
    static let corps   = Font.custom("HelveticaNeue",        size: 15)
    static let corpsSm = Font.custom("HelveticaNeue",        size: 14)
    static let label   = Font.custom("HelveticaNeue-Medium", size: 11)
    static let labelSm = Font.custom("HelveticaNeue-Medium", size: 10)
    /// Code d'un sélecteur segmenté (« FR », « EN ») — un label agrandi pour se voir.
    static let segment = Font.custom("HelveticaNeue-Medium", size: 14)
}

/// Crénage — **spécifique à la taille**, et **positif** sur les petits labels.
///
/// > **Les grands chiffres ont plus besoin du crénage négatif que les titres** : un chiffre
/// > n'a ni jambage ni hampe, donc rien qui vienne remplir l'espace.
///
/// Un style non listé ici se calcule de la même façon : `-0,02em` sur un titre,
/// `-0,025em` sur un grand chiffre, `0` sur le corps de texte.
enum Tracking {
    /// `titre` — `-0,02 × 28`.
    static let titre: CGFloat = -0.56
    /// `titreLg` — `-0,02 × 30`.
    static let titreLg: CGFloat = -0.60
    /// `score` — `-0,025 × 32`.
    static let score: CGFloat = -0.80
    /// `scoreLg` — `-0,03 × 44`.
    static let scoreLg: CGFloat = -1.32
    /// `corps` et `corpsSm`.
    static let corps: CGFloat = 0
    /// `label` et `labelSm`, tous deux en `.textCase(.uppercase)`.
    static let label: CGFloat = 0.7
    /// `segment` — même `+0,05em` que `label`, à 14 pt.
    static let segment: CGFloat = 0.7
}

// MARK: - Encre graphique sur aplat

extension Color {

    /// Encre de second rang sur les aplats **clairs** — ``bleuArdoise`` : blanc à **85 %**.
    ///
    /// > Elle existe parce que ``encreSecondaire`` (70 %) est réglée sur `primaire`, le
    /// > plus sombre des aplats de l'app. Mesuré : le blanc à 70 % composité sur le champ
    /// > du bloc bleu (`#4C6584`) ne vaut que **3,86:1**, et **4,47:1** à 80 % — sous le
    /// > plancher de 4,5:1 d'un texte ordinaire dans les deux cas. À 85 % il y tient
    /// > **4,82:1**, et **7,11:1** sur l'aplat lui-même.
    ///
    /// **Le choix ne revient pas à l'écran** : c'est le marché qui porte son aplat ET son
    /// encre douce, sinon les deux blocs de la saisie en choisiraient chacun une.
    static let encreSecondaireClaire = Color.encreSurAplat.opacity(0.85)

    /// Encre de second rang sur l'aplat **ambre** — ``accent`` : l'encre ``texte`` à
    /// **75 %**.
    ///
    /// > Le blanc est exclu d'office (2,2:1 sur l'ambre). Le `texte/70` de la version web
    /// > compose `#58421C`, soit **4,28:1** — sous le plancher. À 75 % il donne `#4D3B1B`
    /// > et **4,84:1**.
    static let encreSecondaireAmbre = Color.encreSurClair.opacity(0.75)

    /// Encre d'un **élément graphique** posé sur un aplat de couleur — les six tirets du
    /// code d'invitation, et ce qui viendra du même genre : blanc à **50 %**.
    ///
    /// > Elle existe parce que ``encreSecondaire`` (70 %) est réglée pour du **texte** et
    /// > pèse trop lourd sur un simple tiret, quand le blanc à 40 % de la version web ne
    /// > tient que **2,64:1** sur `primaire` — sous le plancher de 3:1 d'un élément
    /// > graphique porteur de sens, et ces tirets en portent un : ils disent que le code
    /// > fait six caractères. Mesuré : 45 % tombe pile à 3,01:1, 50 % donne **3,46:1**.
    static let encreGraphique = Color.encreSurAplat.opacity(0.50)

    /// Encre d'un **segment inactif** d'un sélecteur posé sur ``fondSegmentInactif`` —
    /// ``secondaire`` **plein**.
    ///
    /// > Les deux options d'un sélecteur restent en couleur pleine : l'état se lit à la
    /// > pastille, pas à une encre atténuée. Mesuré sur le fond du sélecteur : **8,18:1**
    /// > sur le beige, **9,22:1** sur le blanc.
    static let encreSegmentInactif = Color.secondaire

    /// Fond neutre d'un sélecteur segmenté — ``secondaire`` à **8 %**, qui se lit sur le
    /// beige comme sur le blanc d'un bloc.
    static let fondSegmentInactif = Color.secondaire.opacity(0.08)
}
