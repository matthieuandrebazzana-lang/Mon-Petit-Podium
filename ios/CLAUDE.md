# CLAUDE.md — Greed F1 iOS

> Contexte permanent de l'app native. À lire **en premier** à chaque session iOS,
> **après** le `CLAUDE.md` de la racine, qui reste la référence métier.
> La spec complète vit dans [`docs/swift-app.md`](../docs/swift-app.md).

---

## 1. Stack

| Élément | Valeur |
|---|---|
| Langage | Swift, mode de langage **5** (`SWIFT_VERSION = 5.0`), chaîne Xcode 26.6 |
| Interface | SwiftUI |
| Cible de déploiement | **iOS 17.0** (`IPHONEOS_DEPLOYMENT_TARGET`) |
| SDK | [`supabase-swift`](https://github.com/supabase/supabase-swift) **2.55.2**, épinglé — produits `Supabase` et `Auth` |
| Xcode | **26.6** (`objectVersion = 77`) |
| Bundle identifier | **`com.bazzana.greedf1`** |
| Familles d'appareils | iPhone seulement · portrait seulement |
| Simulateur cible | **iPhone 17 Pro, iOS 26.5** |

## 2. Adresses

**Le même backend que la version web** — l'app native ne parle à rien d'autre.

| Service | Adresse |
|---|---|
| Backend métier (FastAPI, Railway) | `https://mon-petit-podium-production.up.railway.app` |
| Base + Auth + Storage (Supabase) | `https://ycsxcythvtcruiomrgvv.supabase.co` |

Ces deux valeurs et la **clé anonyme** sont publiques par conception : c'est la **RLS** qui
protège les données. La clé **`service_role` ne doit sous aucun prétexte entrer dans ce
bundle** — elle ne quitte jamais Railway.

**Rien n'est écrit en dur.** Le chemin est
`Config.xcconfig → réglages de build → Info.plist → SupabaseConfig → SupabaseManager`.
`Config.xcconfig` n'est pas versionné : au premier clone, copier `Config.xcconfig.example`.

> **Cold start Railway.** Le plan gratuit met le service en veille. `502`/`503`/`504` sont
> des **erreurs réseau**, pas des pannes : message « Connexion au serveur en cours… », et
> réessayer marche. Voir `docs/swift-app.md` §7.

## 3. Règles de développement

**Les assets SVG viennent de `Greed F1/Ressources/`** — jamais redessinés en SwiftUI. Un
tracé recomposé à la main diverge du logo au premier ajustement. `ios/scripts/ajouter-assets.sh`
les installe dans `Assets.xcassets` avec « Preserve Vector Data », puis on écrit `Image("nom")`.

**Avant de créer une icône ou un élément graphique en SwiftUI, vérifier si un asset existe
déjà dans `Assets.xcassets`.** Si oui, l'utiliser via `Image("nom-asset")`. Ne jamais
recréer en SwiftUI ce qui existe déjà en SVG. La liste complète est en §6.

**Une planche ne s'utilise pas telle quelle.** `logo-02.svg`, `logo.svg` et `logoV2.svg`
portent plusieurs icônes côte à côte dans un seul tracé. `ios/scripts/decouper-icones.sh`
en découpe une par une, d'après `ios/scripts/icones.txt` : chaque icône est la planche
entière derrière une fenêtre `viewBox`, jamais un tracé recopié. Le script pose aussi la
taille naturelle en points — sans elle la barre d'onglets afficherait l'icône à la hauteur
du `viewBox` — et le rendu `template`, sans lequel l'icône reste noire, active comme
inactive. Ajouter une icône = ajouter **une ligne au manifeste**, puis rejouer le script.

**Les captures de `Greed F1/Ressources/Screenshots/` sont la référence visuelle exacte.**
Ouvrir la capture de l'écran **avant** de le coder, et vérifier le rendu contre elle après.
Elles portent l'extension **`.PNG` en majuscules**.

**Aucun fichier markdown de documentation intermédiaire.** Pas de `RECAP-*.md`, de
`TODO-*.md`, de `SOLUTION-FINALE.md`. Ce qui doit survivre va dans `docs/` ou dans ce
fichier ; le reste se dit dans la réponse. Un `.md` posé dans le dossier de la cible part
d'ailleurs dans le bundle de l'app.

**Compiler après chaque modification** :

```bash
xcodebuild -project "ios/Greed F1.xcodeproj" -scheme "Greed F1" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

Et pour voir le rendu, plutôt qu'en déduire la mise en page :

```bash
xcrun simctl install "iPhone 17 Pro" "<chemin>/Greed F1.app"
xcrun simctl launch  "iPhone 17 Pro" com.bazzana.greedf1
xcrun simctl io      "iPhone 17 Pro" screenshot /tmp/rendu.png
```

**Xcode réécrit `project.pbxproj` quand il est ouvert**, et perd les entrées qu'il ne
reconnaît pas — dont `membershipExceptions`. Toute exclusion passe donc par un **réglage de
build** (`EXCLUDED_SOURCE_FILE_NAMES`), qu'il conserve. Son glob **ne franchit pas un `/`** :
un motif par niveau de profondeur.

**Sous iOS 26, la barre d'onglets n'obéit plus.** Le « Liquid Glass » reprend la main sur
tout `UITabBarAppearance` — fond, encre inactive, police, et `unselectedItemTintColor` avec.
Mesuré au simulateur : fond `#FEFAF7`, inactif `#1C1815` (17:1). Seul `.tint()` passe. Le
bloc d'apparence de `BarreNavigation` ne sert donc **qu'à iOS 17 et 18**, où le gris système
par défaut tombe à 2,5:1 sur ce fond clair. Ne pas s'acharner à le forcer sur 26.

**Le design system a trois propriétaires, un par sujet** — `Config/Couleurs.swift`
(palette et typographie : `Font.titre`, `Tracking.label`…), `Config/Formes.swift`
(`Rayon`, les quatre `ombre*()`), `Config/Mouvement.swift` (courbes, durées, `StyleAppui`).
Un écran ne déclare **jamais** sa propre couleur, son rayon, sa courbe ni son ombre : il
étend le vocabulaire (`docs/swift-app.md` §4). Helvetica Neue, **graisses 400 et 500
uniquement**.
Le contraste se mesure : texte ordinaire **4,5:1**, grand texte **3:1**. Zones tactiles
**44 × 44 pt** minimum.

## 4. Règles de commit

- **Incrémenter `MARKETING_VERSION`** dans `ios/Greed F1.xcodeproj/project.pbxproj` (deux
  occurrences, Debug et Release). C'est `CFBundleShortVersionString`, et **la seule source**
  du numéro affiché : `LandingView` le lit via `Bundle.main.versionAffichee`, il ne se
  recopie nulle part.
- **La version web (`frontend/package.json`, `CLAUDE.md` §8) ne bouge pas** sur un commit
  iOS — la faire bouger laisserait croire à un déploiement Vercel qui n'a pas eu lieu.
  Même logique que la version backend.
- Message de commit **concis, en français**.
- **Pousser immédiatement** : `git push origin main`. Ne pas attendre de feu vert.
- **Jamais de ligne `Co-Authored-By`** — Vercel bloque les déploiements automatiques du plan
  Hobby dès qu'un collaborateur externe est détecté.

## 5. Structure des fichiers

Le dossier `Greed F1/` est un **groupe synchronisé** (`PBXFileSystemSynchronizedRootGroup`) :
un fichier posé sur le disque entre dans la cible **sans toucher au `.pbxproj`**. Le revers
est qu'il entre aussi dans le **bundle** — d'où les exclusions ci-dessous.

```
ios/
├── CLAUDE.md                    ce fichier
├── Greed F1.xcodeproj/
├── scripts/
│   ├── ajouter-assets.sh        SVG de Ressources/ → Assets.xcassets, récursif, hors planches
│   ├── decouper-icones.sh       planches → icônes individuelles, d'après le manifeste
│   ├── icones.txt               manifeste des découpes : planche, nom, fenêtre, hauteur
│   ├── extraire-gp.mjs          drapeaux + tracés + table des teintes, DEPUIS LA VERSION WEB
│   ├── extraire-fond-piste.sh   assets/vue_piste.svg → la planche du sol de la piste
│   └── extraire-drapeaux-pilotes.sh  les 16 drapeaux de NATIONALITÉ, DEPUIS LA VERSION WEB
├── AuthViewModel.swift          ┐
├── ConnexionView.swift          ├ hors du groupe synchronisé, référencés un à un
├── InscriptionView.swift        ┘
└── Greed F1/
    ├── App/
    │   └── GreedF1App.swift     point d'entrée
    ├── Config/
    │   ├── Config.xcconfig          valeurs de connexion — NON VERSIONNÉ, hors bundle
    │   ├── Config.xcconfig.example  gabarit à copier — hors bundle
    │   ├── SupabaseConfig.swift     lecture d'Info.plist, rien en dur
    │   ├── Couleurs.swift           palette + typographie du design system
    │   ├── Formes.swift             rayons + les quatre ombres
    │   ├── Materiaux.swift          damier et lumière spéculaire (les deux calques décoratifs)
    │   ├── Mouvement.swift          courbes, durées, StyleAppui (retour d'appui)
    │   └── LandingView.swift        écran d'accueil (non connecté)
    ├── Models/                  (vide)
    ├── Services/
    │   └── SupabaseManager.swift
    ├── Views/
    │   ├── ContentView.swift
    │   ├── Navigation/
    │   │   ├── BarreNavigation.swift  TabView à 4 onglets + apparence de la barre
    │   │   └── EcranProvisoire.swift  gabarit d'un onglet pas encore construit
    │   ├── Accueil/
    │   │   ├── AccueilView.swift       construit — données mockées
    │   │   ├── ApparenceDrapeau.swift  voile et encres d'un drapeau, CALCULÉS
    │   │   └── DrapeauxGP.swift        table des teintes — GÉNÉRÉE, ne pas éditer
    │   ├── Composants/
    │   │   ├── CartesChampionnat.swift  carte de championnat + cartes d'action, PARTAGÉES
    │   │   ├── PlancheSVG.swift         lecture d'une planche SVG au runtime + rendu Canvas
    │   │   └── Voiture.swift            palette, les 11 livrées, la voiture, les vignettes
    │   ├── Championnats/
    │   │   ├── ChampionnatsView.swift       liste — données mockées
    │   │   ├── ChampionnatDetailView.swift  classement + porte de la piste — données mockées
    │   │   ├── VuePisteView.swift           la piste en ÉCRAN PLEIN, placement des voitures — MOCKÉ
    │   │   ├── CreerChampionnatView.swift   nom, photo, code à venir — alerte mockée
    │   │   └── RejoindreChampionnatView.swift  code à 6 cases — alerte mockée
    │   ├── Calendrier/
    │   │   ├── CalendrierView.swift   liste de la saison — terminé → résultats, sinon → fiche
    │   │   ├── DetailGPView.swift     fiche d'un GP à venir : séances, circuit, vainqueurs — MOCKÉE
    │   │   └── FichesGrandPrix.swift  séances + fiches circuit, transcrites de `GP_2026` et `CIRCUITS`
    │   ├── Resultats/
    │   │   ├── ResultatsGPView.swift       mes résultats + classement officiel — MOCKÉS
    │   │   └── NationalitesPilotes.swift   pilote → pays, contrepartie de `lib/nationalites.js`
    │   ├── Pronos/
    │   │   ├── CotesView.swift      tableau des cotes + paris bonus, et `EtapePronos` — MOCKÉS
    │   │   ├── PronosView.swift     saisie des deux pronostics obligatoires — MOCKÉE
    │   │   └── RecapView.swift      récapitulatif après validation — MOCKÉ
    │   └── Profil/
    │       ├── ProfilView.swift         mon profil — données mockées
    │       ├── ProfilMembreView.swift   profil d'un autre membre, lecture seule — MOCKÉ
    │       └── ComposantsProfil.swift   pastille, en-tête et grille de stats, PARTAGÉS
    ├── Resources/               ← EMBARQUÉ dans l'app
    │   ├── Info.plist               hors bundle (exception d'appartenance)
    │   ├── Assets.xcassets/      les assets de §6
    │   └── Vecteurs/             les 5 planches LUES AU RUNTIME — voir §6
    └── Ressources/              ← RÉFÉRENCE, exclue du bundle
        ├── logo-05.svg              source, viewBox « 0 0 894.21 520.39 »
        ├── logo-bandeau.svg         idem à viewBox rognée « 0 215 894.21 243 »
        ├── logo.svg                 ┐
        ├── logo-02.svg              ├ planches d'icônes, à découper par script
        ├── logoV2.svg               ┘
        ├── texture-hexa.svg         damier des cartes (assets/06.svg)
        ├── flags/                   flag-<slug>.svg — un drapeau par Grand Prix HÔTE
        ├── flags-pilotes/           drapeau-<code>.svg — un drapeau par NATIONALITÉ
        ├── traces/                  trace-<slug>.svg — un circuit par Grand Prix
        └── Screenshots/             28 captures de la version web
```

> **`Resources/` et `Ressources/` ne se confondent pas.** `Resources/` (un s) est ce que
> l'app embarque. `Ressources/` (deux s) est de la matière de travail : elle est retirée du
> bundle par `EXCLUDED_SOURCE_FILE_NAMES` — sans quoi les 28 captures y ajoutaient **17 Mo**.

## 6. Assets disponibles

**Vérifier ici avant de dessiner quoi que ce soit en SwiftUI.**

### Embarqués — `Greed F1/Resources/Assets.xcassets/`

Tous en « Preserve Vector Data », appelés par `Image("nom")`.

| Asset | Usage |
|---|---|
| `AccentColor` | Couleur d'accent du système |
| `AppIcon` | Icône de l'app |
| `logo-05` | Logo complet — icône carrée + bandeau, viewBox « 0 0 894.21 520.39 » |
| `logo-bandeau` | Bandeau seul, en-tête de `LandingView` |
| `icone-accueil` | Garage — onglet **Accueil**, 25,67 × 28 pt, *template* |
| `icone-championnats` | Coupe — onglet **Championnats**, 17,86 × 28 pt, *template* |
| `icone-calendrier` | Calendrier — onglet **Calendrier**, 22,20 × 28 pt, *template* |
| `icone-profil` | Pilote casqué — onglet **Profil**, 22,42 × 28 pt, *template* |
| `icone-creer` | Croix + coupe — carte « Créer un championnat », 40 × 40 pt, *template* |
| `icone-rejoindre` | Deux casques — carte « Rejoindre un championnat », 40 × 40 pt, *template* |
| `icone-etoile` | Étoile — bouton « pari bonus » de `CotesView`, 22 × 22 pt, *template* |
| `texture-hexa` | Damier en filigrane des cartes — monté par ``Damier``, jamais en direct |
| `flag-<slug>` | Les 12 drapeaux des pays hôtes. **Pas de rendu *template*** : ils gardent leurs couleurs |
| `drapeau-<code>` | Les 16 drapeaux de **nationalité** des pilotes, en ISO alpha-2 — `drapeau-gb`, `drapeau-nl`… Pas *template* non plus |
| `trace-<slug>` | Les 12 tracés de circuits, *template* — ils prennent l'encre de l'écran |

> **Les drapeaux et les tracés viennent de la version web, pas d'une recopie.**
> `scripts/extraire-gp.mjs` lit les trois tables de `frontend/src/composants/`
> (`DRAPEAUX`, `DRAPEAUX_SVG`, `TRACES`) et en écrit les fichiers de `Ressources/flags/`
> et `Ressources/traces/`, plus la table des teintes de `DrapeauxGP.swift`. Un cadrage ou
> un chemin recopié à la main divergerait de la source au premier ajustement. **Cinq
> drapeaux sont des bandes** (Pays-Bas, Italie, Espagne, Azerbaïdjan, Singapour) : c'est
> ce que la planche `assets/flags.svg` ne dessine pas, et ce que le web rend en dégradé.
> Ajouter un Grand Prix = l'ajouter **côté web**, puis rejouer le script.
>
> **Les deux familles de drapeaux ne se confondent pas.** `flag-<slug>` peint un pays
> **hôte** — il habille une carte de Grand Prix, et cinq d'entre eux sont des bandes que
> le web rend en dégradé. `drapeau-<code>` peint la **nationalité d'un pilote**, en fond
> d'une ligne de classement, et il en faut **seize** : la grille 2026 compte l'Australie,
> la Nouvelle-Zélande, le Brésil, le Mexique, le Canada, la Thaïlande et l'Argentine, sept
> drapeaux qu'aucune borne de dégradé ne sait dire, et la règle du projet interdit
> d'approximer un drapeau. `scripts/extraire-drapeaux-pilotes.sh` les prend donc dans
> `country-flag-icons`, **la bibliothèque qu'importe déjà `DrapeauxPilotes.jsx`**, sur les
> codes que `frontend/src/lib/nationalites.js` déclare. Ajouter un pilote = l'ajouter
> **côté web**, puis rejouer le script — et relire `NationalitesPilotes.swift`, qui est la
> transcription de la même table.
>
> **Un drapeau de nationalité s'étire, il ne se recadre pas.** Une ligne de classement fait
> 361 × 62 pt, soit 5,8:1 là où un drapeau en fait 1,5:1 : un `scaledToFill` recadrerait sur
> la bande centrale et l'Allemagne ressortirait entièrement rouge. `.resizable()` seul —
> le `preserveAspectRatio="none"` du web — garde toutes les bandes.

> **L'épaisseur du trait d'un circuit est calculée**, pas choisie : un SVG de catalogue
> n'a pas de `non-scaling-stroke`, donc le script l'écrit en unités de la `viewBox` à la
> valeur qui donne 3 pt dans la bande de 343 × 160 du widget. Sans ce calcul, Bakou (481
> unités de large) rendrait un cheveu là où Zandvoort (395) rendrait un câble.

> Les quatre icônes d'onglet sont découpées de `logo-02.svg` sur une **bande verticale
> commune** (`y 24`, hauteur `78`) : c'est ce qui conserve leurs tailles relatives telles
> que dessinées, comme sur la version web. Elles ne se modifient pas à la main — on corrige
> `scripts/icones.txt` et on rejoue `scripts/decouper-icones.sh`.

### Planches lues au runtime — `Greed F1/Resources/Vecteurs/`

**Six SVG embarqués comme fichiers**, pas comme `imageset`, et lus par ``PlancheSVG``.

| Fichier | Contenu |
|---|---|
| `voitures_perso.svg` | La voiture personnalisable — fenêtre « 55.08 57.74 141.12 288.09 » |
| `voitures_ecuries.svg` | Neuf livrées d'écurie |
| `VOITUREs_am.svg` | Alpine et Mercedes |
| `matti.svg` | Neuf vignettes de casque |
| `matt.svg` | Racing Bulls et Red Bull — les deux casques **corrigés** |
| `vue_piste.svg` | Le sol de la vue piste, ses kerbs, sa ligne médiane — **étiré** aux deux axes |

> **Pourquoi pas le catalogue d'assets.** Une image du catalogue se teinte d'une seule
> encre (`template`) ou d'aucune. La voiture personnalisée demande **deux** aplats
> remplacés indépendamment (`#be1622` → coque, `#ededed` → ailerons) sur une trentaine de
> formes entrelacées avec les gris mécaniques — pneus, suspensions, fond plat, casque — qui
> ne bougent pas. Le fichier est donc lu tel quel et ses `fill` sont substitués, exactement
> comme la version web remplace `cls-6` et `cls-14`.
>
> **`PlancheSVG` n'est pas un moteur SVG** : il couvre ce que ces six fichiers emploient,
> et rien de plus. Aucun arc — les six n'en contiennent pas un, vérifié fichier par
> fichier. Il ne connaît ni les `<pattern>` ni l'`opacity` : c'est pourquoi
> `extraire-fond-piste.sh` retire le motif de la planche de piste, et pourquoi les 11 %
> de sa ligne médiane passent par la **substitution d'encre** de ``VuePisteView``.
>
> **`vue_piste.svg` est la seule planche étirée** — `CadrePlanche.etiree`, l'équivalent de
> `preserveAspectRatio="none"` : le sol doit couvrir l'écran quel que soit l'iPhone. Une
> voiture, elle, ne s'étire jamais : déformée, elle cesse d'être une voiture.
>
> **Le bandeau de la planche n'y est PAS**, et c'est le seul écart avec
> `assets/vue_piste.svg` : il porte la couleur Pantone du championnat, le damier et le
> nom, donc il est peint par SwiftUI. Même écart que `frontend/src/composants/FondPiste.jsx`
> côté web.
>
> **Les fenêtres sont mesurées, jamais des tranches arithmétiques.** Les planches empilent
> leurs voitures en zigzag, ni jointives ni régulièrement espacées. Les valeurs de
> `LivreeEcurie.toutes` sont les vraies boîtes englobantes, les mêmes que
> `frontend/src/composants/VoituresEcuries.jsx`, coordonnée pour coordonnée.
>
> **`matti.svg` porte bien onze casques, mais deux sont périmés** : Red Bull et Racing
> Bulls y gardent une visière orange `#ec6408` que la livrée 2026 n'a plus. `matt.svg`
> porte les deux corrigés, et ce sont ceux-là que la table désigne.

### Sources et planches — `Greed F1/Ressources/`

Matière de travail, **exclue du bundle**. Une planche porte plusieurs icônes dans un seul
tracé : elle ne s'utilise jamais telle quelle, elle se découpe.

| Fichier | Contenu |
|---|---|
| `texture-hexa.svg` | Damier des cartes, copie d'`assets/06.svg` |
| `flags/`, `traces/` | Un fichier par Grand Prix — **écrits par `extraire-gp.mjs`** |
| `flags-pilotes/` | Un fichier par nationalité — **écrits par `extraire-drapeaux-pilotes.sh`** |
| `logo-05.svg` | Source du logo complet |
| `logo-bandeau.svg` | Le même à viewBox rognée « 0 215 894.21 243 » |
| `logo-02.svg` | **Planche** — les 4 icônes de la barre : garage, coupe, calendrier, pilote |
| `logo.svg` | **Planche** — croix + coupe (créer un championnat), deux casques (membres) |
| `logoV2.svg` | **Planche** — chronomètre, étoile, deux pilotes, drapeau à damier |
| `Screenshots/` | 28 captures de la version web — voir §7 |

Les deux logos du haut de `logo.svg` sont découpés (`icone-creer`, `icone-rejoindre`), et
l'étoile de `logoV2.svg` depuis `CotesView` (`icone-etoile`) — **sur la fenêtre de
`frontend/src/composants/icones/IconeEtoileLogo.jsx`**, qui est la vraie boîte englobante
élargie à un carré de 88 unités, jamais une tranche arithmétique de la planche. Les trois
autres dessins de `logoV2.svg` ne sont pas encore découpés : le jour où un écran en a
besoin, une ligne au manifeste suffit.

**Les trois planches ne sont jamais installées telles quelles** : `ajouter-assets.sh` les
saute, et c'est délibéré — posées dans le catalogue elles n'affichent rien d'utilisable et
pèsent pour rien dans le bundle.

---

## 7. Captures de référence

`Greed F1/Ressources/Screenshots/` — la version web **v0.75.0**, écran par écran.

| Fichier | Écran |
|---|---|
| `screen-01-landing.PNG` | Accueil non connecté — bandeau, titre, deux boutons |
| `screen-02-inscription.PNG` | Création de compte |
| `screen-03-connexion.PNG` | Connexion |
| `screen-04-accueil_haut.PNG` | Accueil connecté, haut |
| `screen-05-accueil-bas.PNG` | Accueil connecté, bas |
| `screen-06-championnats-haut.PNG` | Liste des championnats, haut |
| `screen-07-championnats-bas.PNG` | Liste des championnats, bas |
| `screen-08-calendrier-haut.PNG` | Calendrier, haut |
| `screen-09-calendrier-milieu.PNG` | Calendrier, milieu |
| `screen-10-calendrier-bas.PNG` | Calendrier, bas |
| `screen-11-creer-championnat.PNG` | Créer un championnat |
| `screen-12-rejoindre-championnat.PNG` | Rejoindre par code à 6 caractères |
| `screen-13-classement-championnat.PNG` | Classement d'un championnat |
| `screen-14-vue-piste.PNG` | Vue piste |
| `screen-15-resultats-par-gp.PNG` | Résultats par Grand Prix |
| `screen-16-mes-resultats-haut.PNG` | Mes résultats, haut |
| `screen-17-mes-resultats-bas.PNG` | Mes résultats, bas |
| `screen-18-detail-gp-haut.PNG` | Détail d'un GP, haut |
| `screen-19-detail-gp-bas.PNG` | Détail d'un GP, bas |
| `screen-20-mon-profil-haut.PNG` | Mon profil, haut |
| `screen-21-mon-profil-bas.PNG` | Mon profil, bas |
| `screen-22-profil-membre.PNG` | Profil d'un autre membre |
| `screen-23-accueil-pronos-ouverts.PNG` | Accueil, pronostics ouverts |
| `screen-24-cotes-haut.PNG` | Cotes, haut |
| `screen-25-pronos-haut.PNG` | Saisie des pronostics, haut |
| `screen-26-pronos-remplis.PNG` | Saisie des pronostics, remplie |
| `screen-27-recap-haut.PNG` | Récapitulatif, haut |
| `screen-28-recap-bas.PNG` | Récapitulatif, bas |

> **Les captures montrent le vocabulaire et les règles de la racine**, pas seulement une
> mise en page : **points entiers, jamais une cote** (« 28 pts », jamais « ×2,80 ») ;
> **championnat**, jamais « ligue » ; **calendrier**, jamais « historique ».
