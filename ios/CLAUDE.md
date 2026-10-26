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
| Cibles | `Greed F1` (l'app) + **`GreedF1WidgetExtension`** (`com.bazzana.greedf1.GreedF1Widget`, widgets « Prochain GP » et « Classement » ; « Mes pronos » **désactivé**, voir §3) |
| App Group | **`group.com.bazzana.greedf1`** — sur les deux cibles, seul propriétaire `DonneesWidget` (`Services/DonneesWidget.swift` + `DonneesWidgetClassement.swift` + `DonneesWidgetPronos.swift`) |
| Keychain partagé | **`$(AppIdentifierPrefix)com.bazzana.greedf1.widget`** — le jeton widget seul (`Services/JetonWidget.swift`) ; la session Supabase reste dans le groupe de l'app |
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
`Config.xcconfig → réglages de build → Info.plist → SupabaseConfig → SupabaseManager / APIClient`.
`Config.xcconfig` n'est pas versionné : au premier clone, copier `Config.xcconfig.example`.

> **Cold start Railway.** Le plan gratuit met le service en veille. `502`/`503`/`504` sont
> des **erreurs réseau**, pas des pannes : message « Connexion au serveur en cours… », et
> réessayer marche. Voir `docs/swift-app.md` §7. Un service cron (`keepalive/`) appelle
> `/ping` toutes les 5 min (`docs/architecture.md` §9).

> **Cache *stale-while-revalidate*, instantanés sur disque** (`docs/decisions.md` §27, §29).
> Une lecture d'écran passe par `CacheService.partage.charger(clé, snapshot:, forcer:,
> afficher:, lire:)` — jamais un second cache maison. `lire` rend le **JSON brut**
> (`APIClient.lireJSON`, `.execute().data`), décodé par `JSONDecoder.api` pour le réseau
> comme pour le disque. L'ancienne valeur s'affiche **toujours**, revalidée si elle a plus
> de **30 s** ; une relecture en vol n'est jamais doublée ; un échec ne remplace jamais une
> valeur affichée. `snapshot: true` (championnats, prochain GP, classement du premier plan,
> profil, ses stats, calendrier) l'écrit dans `Caches/Instantanes/<compte>/` ; un service
> **naît rempli** par `CacheService.partage.valeur(clé, snapshot:)`. Jamais de jeton ni de
> secret sur disque ; tout est effacé par `vider()` (déconnexion, suppression, `signedOut`).
> Réponse dont la forme change ? Incrémenter `SnapshotsDisque.version`. Après une écriture,
> `charger(forcer: true)` ; les écritures d'`APIClient` (et le pseudo) périment déjà tout.
> Une photo distante passe par `ImageCachee`, **jamais** `AsyncImage`.
>
> **Lancement : une session locale suffit** (`AuthViewModel.init`, `currentSession`, sans
> réseau, même expirée). Le jeton se rafraîchit en arrière-plan ; seul un **refus du
> serveur** (session effacée par `supabase-swift`, `signedOut`) déconnecte — jamais un
> réseau absent. Les lectures du lancement vivent dans `BarreNavigation`
> (`chargerAuLancement`, quatre en parallèle), pas dans leurs onglets.

## 3. Règles de développement

**Un premier chargement se dessine en silhouette, jamais en spinner** (`SkeletonView`,
`Views/Composants/`). Quatre variantes (`ligneCourte`, `ligneLongue`, `blocCarre`,
`blocRectangulaire`), tailles remplaçables ; aplat `secondaire` 15 %, bande 30 % calée sur
l'écran (`Mouvement.balayageSquelette`, 1,4 s, linéaire), absente sous mouvement réduit.
Elle ne s'affiche **qu'en `.chargement`** — le cache sert déjà ce qu'il connaît — et cède
au contenu par `fonduChargement(_:)`, **posé sur un `ZStack` autour du `switch`** : la
silhouette sort en fondu, chaque élément du contenu entre par `arriveeEnCascade(rang:)`
(fondu + 12 pt vers le haut, 300 ms, 50 ms d'écart sur 5 éléments au plus ; fondu seul
sous mouvement réduit), sa branche en `.transition(.contenuArrive)`. Chaque écran
esquisse sa propre structure (widget 360 pt, pile, liste, classement, carrousel, six
cartes GP au calendrier) ; les stats, que leurs valeurs inconnues. Les spinners restent
sur les actions ponctuelles (envoi, sauvegarde).

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

**Clair et sombre : uniquement par jetons** (`docs/decisions.md` §26, tableau dans
`docs/swift-app.md` §4.2 bis). Une couleur qui suit l'apparence se déclare dans
`Couleurs.swift` par `Color(clair:sombre:)` ; une vue ne lit **jamais** `colorScheme` pour
choisir une encre, et ne contient **aucun** `.white`, `.black` ni littéral — un `grep` doit
rester vide hors de `Couleurs.swift` et `DrapeauxGP.swift`. Trois pièges mesurés :
`primaire` est un **aplat** (`#C0182A` en sombre, 2,26:1 en texte sur une surface) — le
rouge en texte ou en trait est `encrePrimaire` ; le blanc posé sur un aplat est
`encreSurAplat`, l'encre foncée sur l'ambre `encreSurClair`, toutes deux fixes ; ce qui
est posé **sur un drapeau** (qui ne change pas) garde les valeurs claires (`…Fixe`).
L'apparence a un seul propriétaire, `Config/ThemeManager.swift` (Auto / Clair / Sombre,
`overrideUserInterfaceStyle` sur les fenêtres) ; vérifier chaque écran retouché dans les
deux modes (`xcrun simctl ui booted appearance dark`).

**Aucun texte d'interface en dur : tout passe par `t("clé")`** (`Localisation/`). Deux
dictionnaires Swift aux clés identiques, rangées par écran — `TraductionsFR.swift`,
`TraductionsEN.swift` — et **jamais** de `.strings` ni de String Catalog. Une nouvelle
chaîne = une clé ajoutée **aux deux** fichiers, au même endroit. Le pluriel passe par
`tp("clé", n)` (clés `clé.un` / `clé.plusieurs` : 0 est singulier en français, pluriel en
anglais), le rang par `ordinal(n)`, l'heure par `heureInterface(_:)`, toute date par
`.locale(localeInterface)` — **jamais `fr_FR` en dur** pour un affichage. `t()` lu dans un
`body` y inscrit la langue comme dépendance (`LanguageManager` est `@Observable`) : rien à
câbler pour que l'écran suive. Un texte **stocké** (dans un `@State`, un modèle) ne suit
pas — stocker la clé, traduire à l'affichage. Les données de l'API (marchés Unibet,
pilotes, écuries) ne se traduisent pas. **Les Grands Prix, si** : pays, nom (« GP
Malaisie » / « Malaysian GP ») et circuit sont les clés `gp.<slug>.*`, lues par
`GrandPrixSaison` — la liste statique n'écrit plus aucun nom. Vocabulaire anglais : *Championship*,
*Prediction*, *Bonus picks*, *Calendar*, *Odds*.

**Un Grand Prix de la base se reconnaît à sa date de course, le nom n'est qu'un repli.**
Le slug (drapeau, tracé, teintes, croisement avec le calendrier statique) a un seul
propriétaire : `SlugCircuit.de(_:dateCourse:)` (`Models/GrandPrix.swift`) — l'entrée de
`GrandPrixSaison.saison2026` courue à ±3 jours, sinon `SlugCircuit.de(nom)`. Ne jamais
appeler la variante sans date sur une ligne de la base : Unibet a publié « GP Bahrein » à
la place de Sepang (2026-10-04), et `bahrein` ne désigne aucun asset. Même règle que le
scraper et le web (`docs/decisions.md` §24). Deux lignes au même week-end : le calendrier
garde celle qui a des cotes. **Le nom de la base ne s'affiche jamais** : tout écran montre
`nomAffiche` (`GrandPrixSaison.nomAffiche(slug:repli:)`, le nom traduit du calendrier
statique), le nom Unibet n'étant qu'un repli hors saison — sinon l'accueil disait « GP
Bahrein » quand le calendrier disait « GP Malaisie ».

**Onze Grands Prix masqués du calendrier — à réactiver.** Australie → Hongrie n'ont encore ni
drapeau ni tracé : `GrandPrixSaison.masquesDuCalendrier` (`Models/GrandPrixSaison.swift`) les retire
de l'onglet Calendrier seul, leurs données restent dans `saison2026`. Une fois leurs SVG
extraits dans les assets, vider cet ensemble.

**Un pavé numérique n'a pas de touche de fermeture : il en reçoit une.** Champ en
`@FocusState`, barre « OK » (`clavier.ok`) en `ToolbarItemGroup(placement: .keyboard)` —
l'écran doit être dans une `NavigationStack` —, `scrollDismissesKeyboard(.immediately)` et
toucher hors du champ (geste **simultané**, ignoré dans le cadre du champ). Seul cas
aujourd'hui : le numéro de voiture (`ProfilView`).

**L'invitation au profil a un seul propriétaire, `DecouverteProfil`** (`UserDefaults`, une
clé par compte, effacée par `oublierCompte()`). `BarreNavigation` la marque sur le passage
à l'onglet Profil — jamais l'avatar ni `ProfilView` séparément. L'onde (`AnneauInvitation`,
`Mouvement.ondeInvitation` / `periodeInvitation`) est un `overlay` sans hit-test : elle ne
pousse rien et ne capte aucun tap.

**Le sélecteur de langue est un seul composant** (`SelecteurLangue`) : ses états actif /
inactif s'y règlent, jamais sur l'écran qui le monte. **Les deux options restent en couleur
pleine** — drapeaux entiers, libellé inactif en `encreSegmentInactif` (`secondaire` plein) :
l'état ne se lit **qu'à la pastille** `primaire`. Ne pas réintroduire de désaturation ni
d'opacité réduite sur l'option inactive. Taille : segments 80 × 40, drapeau 20 pt, code en
`Font.segment` (14 pt, 500).

**Les notifications push partent du backend, jamais de l'app** (`docs/decisions.md` §25).
`Services/NotificationsPush.swift` est le **seul propriétaire** du jeton APNs : permission
demandée une fois connecté (`.task` sur `BarreNavigation`), jeton reçu par
`DelegueApplication` (`@UIApplicationDelegateAdaptor`) puis envoyé à `POST /push/token` avec
`langueInterface` — c'est la langue des notifications, et un changement de langue le
renvoie. `DELETE /push/token` part **avant** `signOut()` et avant `DELETE /profils/moi` :
après, la session n'existe plus. Ne jamais ajouter de `UNNotificationRequest` local ni
d'interrupteur dans l'app (les Réglages d'iOS en tiennent lieu). L'entitlement
`aps-environment` vaut `development` ; un build TestFlight / App Store signe en
`production`, et Railway doit alors passer `APNS_ENV=production`.

**Le widget « Prochain GP » (`GreedF1Widget/`) réutilise les fichiers de l'app, il ne les
recopie pas.** Ils entrent dans sa cible par une **exception d'appartenance** du groupe
synchronisé `Greed F1` (`Exceptions for "Greed F1" folder in "GreedF1WidgetExtension"
target`, liste dans le `.pbxproj`) : couleurs, formes, matériaux, `SupabaseConfig`, langue
et traductions, `GrandPrix`, `GrandPrixSaison`, `GPRestants`, `DecodageJSON`,
`ApparenceDrapeau`, `DrapeauxGP`, `DonneesWidget` **et le catalogue `Assets.xcassets`
entier** (drapeaux, tracés, logo — le widget n'a pas de catalogue à lui). Un fichier
partagé ne doit donc rien appeler qui n'y soit pas — sinon la cible du widget ne compile
plus. Format Xcode, conservé à l'ouverture : vérifier après coup qu'il est toujours là.
Données : l'app écrit dans l'App Group le GP lu par l'accueil (`ProchainGrandPrix`) et sa
langue active (`GreedF1App`), puis recharge le widget ; le widget relit `GET /calendrier`
(publique, **jamais de session**) et passe d'état seul par sa timeline
(`TimelineProchainGP`). Il suit la langue de l'app (`LanguageManager.imposer`), jamais
celle du téléphone. Tap → `greedf1://accueil` → onglet Accueil (`BarreNavigation`).
Il n'existe pas de moyen de poser un widget au simulateur en ligne de commande : pour
voir son rendu, monter ses vues dans un harnais `DEBUG` temporaire de l'app.

**Le widget « Classement » n'a jamais la session Supabase** (`docs/decisions.md` §28) — ses
jetons de rafraîchissement sont à usage unique, un double rafraîchissement déconnecterait.
L'app (`SynchroWidgetClassement`, app seule) demande **une fois par lancement** (puis au retour au premier plan après 24 h) un **jeton widget**
(`POST /widget/token`, 30 jours, lecture seule) et le range dans le Keychain partagé
(`JetonWidget`) ; le widget ne l'envoie qu'à `GET /widget/championnats/{id}/classement`.
L'app écrit liste, premier plan de la pile (`OrdrePile.ecrire`) et profil dans l'App Group ;
`oublierCompte()` efface jeton, données et avatars. **La session Supabase est épinglée au
groupe Keychain de l'app** (`SupabaseManager.stockageSession`) : depuis `keychain-access-groups`,
un élément écrit sans groupe tombe dans le **premier** groupe listé — le partagé. Ne jamais
retirer ce stockage explicite. Lignes : petit = top 5 (+ l'utilisateur au-delà), moyen
« Classement + piste » (défaut) = top 5 (+ l'utilisateur au-delà) à gauche, piste à droite
sur toute la hauteur, moyen « Classement » = top 10 sur deux colonnes de 5 (l'utilisateur
remplace le 10e), grand = top 10 (+ l'utilisateur, 11 lignes au plus), rangs réels, corps
≥ 12 pt (`GabaritLigne`). **Le moyen a son propre réglage** (`affichageMoyen`, depuis 0.55.3) :
`affichage` ne sert plus qu'au petit — un moyen posé avant est repassé au défaut. Piste : `DispositionPiste`
(fichier propre, partagé) calculé **sur la piste de l'app** (`DispositionPiste.pisteApp`,
365,71 × 548 pt mesurés) puis réduit **uniformément**, centré au rapport de la piste — jamais
recalculé à la taille du widget —, posée directement sur le fond du widget (ni kerbs ni ligne médiane ; **jamais** `surfacePiste` — en sombre, le fond sombre ordinaire et son damier, depuis 0.57.1 ; la route grise reste propre à l'app), `VueVoiture(imagePhoto:)` avec l'avatar
réduit de l'App Group (`AvatarsWidget`, le widget ne télécharge rien au rendu). **Fond** :
`FondClassement` (beige + `Damier`) dans tous les états — **texture uniforme**, un seul
calque, ni fondu, ni masque, ni dégradé, donc continu dans « Classement + piste ». Encre :
`damierWidget` (2 % clair — plafonné par `grisSecondaire`, 4,53:1 — / 5 % sombre) dès qu'il
y a du texte de classement, `damierWidgetPiste` (8 %) quand la piste est seule
(`VueClassement.pisteSeule`). **Aucune date affichée** : périmé ou hors ligne, le widget
garde silencieusement le dernier relevé. `contentMarginsDisabled`
et les marges posées par `VueClassement` : ne pas les rendre au système. Tap →
`greedf1://championnat/<id>` → onglet Championnats, détail ouvert (`ChampionnatsView`).
**Seule exception à `t()`** : les libellés de la configuration App Intents, extraits à la
compilation et affichés par iOS dans la langue du téléphone, vivent dans
`GreedF1Widget/Intentions.xcstrings` — rien d'autre n'y entre.

> **« Mes pronos » est DÉSACTIVÉ depuis 0.57.2 — à diagnostiquer plus tard.** Posé sur
> l'écran d'accueil, il s'affichait entièrement blanc ; cause non trouvée (état du
> diagnostic : `docs/contexte-chat.md`). Retiré de `GreedF1WidgetBundle` (absent de la
> galerie), code conservé et compilé, route `/widget/pronos` en place.
> `DonneesWidget.widgetPronosActif = false` coupe les rechargements demandés par l'app et
> l'écriture de l'App Group ; l'effacement à la déconnexion reste actif. Un widget déjà
> posé n'est plus servi par l'extension : iOS le retire, aucun code de l'app ne le cherche.
> **Réactiver** : remonter `PronosWidget()` dans le bundle **et** repasser le drapeau à `true`.

**Le widget « Mes pronos » partage le jeton et l'App Group de « Classement »**
(`docs/decisions.md` §30), jamais la session. Statique (aucun réglage, donc rien dans
`Intentions.xcstrings`), petit et moyen. Il lit `GET /widget/pronos` (`prochain` + `dernier`)
et range **la réponse brute** dans l'App Group (`DonneesWidgetPronos`), décodée par
`JSONDecoder.api` : hors ligne ou jeton expiré, la dernière reçue, sans date ; sans rien,
« Ouvre l'app pour charger tes pronos ». Le slug vient de `SlugCircuit` (nom + date), jamais
du backend. `TimelinePronos` (pur) change d'état seul : avant l'ouverture / ouverts / fermés
(``EcheancePronostics``), puis « Résultats disponibles » (GP `termine`) jusqu'à départ + 36 h
(`CadenceClassement.apresDepart`), puis le GP suivant ; décompte `DecompteProchainGP`.
Cadence `CadenceClassement.prochaine(apres:departs:)` (2 h, 15 min dans les 36 h). Pastille :
« À faire » `primaireFixe`, « Pronos faits » `vertSauge`, « Résultats » `accent` +
`encreSurClair`, « Fermés » matériau du drapeau. Fond `FondPronos` (drapeau voilé, sans
tracé). L'app recharge le widget à chaque ouverture (après le jeton), après chaque
`POST …/pronostics` (`DonneesPronostics.enregistrer`) et l'efface avec le jeton
(`SynchroWidgetClassement.effacer`). Tap → `greedf1://pronos/<id>` (`EntreePronosView` :
récap ou cotes) ou `greedf1://resultats/<id>` (`MesResultatsGPView`), poussés sur la pile de
l'accueil (`EtapePronos.demandee`) ; avant l'ouverture → accueil. Les points sont habillés par
`formaterPoints` (`Models/FormatPoints.swift`, PARTAGÉ depuis 0.57.0).

## 4. Règles de commit

- **Incrémenter `MARKETING_VERSION`** dans `ios/Greed F1.xcodeproj/project.pbxproj` (deux
  occurrences, Debug et Release). C'est `CFBundleShortVersionString`, et **la seule source**
  du numéro affiché : `LandingView` et `ReglagesView` le lisent via `Bundle.main.versionAffichee`, il ne se
  recopie nulle part.
- **Une version commune à l'app et au widget.** `MARKETING_VERSION` et
  `CURRENT_PROJECT_VERSION` (le build) sont posés **au niveau du projet**, pas des cibles :
  les deux en héritent, et l'App Store refuse une extension dont les numéros diffèrent de
  l'app. Ne **jamais** les saisir dans l'onglet *General* d'une cible — Xcode les y écrirait
  au niveau de la cible et les désaligneraient. Contrôle : `grep MARKETING_VERSION` sur le
  `.pbxproj` rend exactement deux lignes. Incrémenter le build à chaque envoi TestFlight.
- **Archiver avec le schéma `Greed F1`**, pas celui du widget (la build 15 l'a été par
  `GreedF1WidgetExtension` — même `.app`, mais l'archive porte le nom du widget).
  Contrôle de l'icône après archive : `CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName =
  AppIcon` dans l'`Info.plist` du `.app`, `AppIcon60x60@2x.png` à sa racine, et
  `assetutil --info Assets.car` liste les 8 tailles `phone` + le 1024 `marketing` opaque.
- **La version web (`frontend/package.json`, `CLAUDE.md` §8) ne bouge pas** sur un commit
  iOS — la faire bouger laisserait croire à un déploiement Vercel qui n'a pas eu lieu.
  Même logique que la version backend (règle commune : `CLAUDE.md` §7).
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
│   ├── ajouter-assets.sh        SVG de Ressources/ → Assets.xcassets, récursif, hors planches ; tracés et `icon-*` en template
│   ├── decouper-icones.sh       planches → icônes individuelles, d'après le manifeste
│   ├── icones.txt               manifeste des découpes : planche, nom, fenêtre, hauteur
│   ├── extraire-gp.mjs          drapeaux + tracés + table des teintes, DEPUIS LA VERSION WEB
│   ├── extraire-fond-piste.sh   assets/vue_piste.svg → la planche du sol de la piste
│   └── extraire-drapeaux-pilotes.sh  les 17 drapeaux de NATIONALITÉ, DEPUIS LA VERSION WEB
├── GreedF1Widget/               cible GreedF1WidgetExtension (groupe synchronisé à part)
│   ├── GreedF1WidgetBundle.swift    point d'entrée, impose la langue de l'app
│   ├── GreedF1Widget.swift          configuration : petit, moyen, écran verrouillé rectangulaire
│   ├── FournisseurProchainGP.swift  App Group + `GET /calendrier`, `TimelineProchainGP` (calcul pur des entrées)
│   ├── VuesProchainGP.swift         les trois formats, fond drapeau, décompte `Text(timerInterval:)`, état neutre
│   ├── ClassementWidget.swift       widget « Classement » : petit + moyen + grand, `AppIntentConfiguration`
│   ├── IntentionClassement.swift    championnat (`nil` = premier plan de la pile) + « Affichage » : liste / piste (petit), classement + piste / liste / piste (moyen), classement + piste / piste seule (grand) ; un seul visible par format (`parameterSummary`)
│   ├── Intentions.xcstrings         libellés App Intents FR/EN — SEULE exception à `t()`
│   ├── FournisseurClassement.swift  jeton widget → `GET /widget/…/classement`, App Group, `CadenceClassement`, `AvatarsWidget`
│   ├── VuesClassement.swift         les trois formats, lignes, piste titrée (`PisteTitree`) et simplifiée (`PisteSimplifiee`), état neutre, fond damier uniforme (`FondClassement`)
│   ├── PronosWidget.swift           widget « Mes pronos » : petit + moyen, `StaticConfiguration` — NON MONTÉ (désactivé)
│   ├── FournisseurPronos.swift      jeton widget → `GET /widget/pronos`, App Group, `TimelinePronos` (calcul pur), `PhasePronos`
│   ├── VuesPronos.swift             pastille d'état, petit, moyen (obligatoires / bonus), état vide, fond drapeau (`FondPronos`)
│   └── Info.plist                   `API_BASE_URL` (Config.xcconfig, réglages du projet)
├── GreedF1WidgetExtension.entitlements  App Group + Keychain partagé
├── AuthViewModel.swift          ┐
├── ConnexionView.swift          ├ hors du groupe synchronisé, référencés un à un
├── InscriptionView.swift        ┘
└── Greed F1/
    ├── App/
    │   └── GreedF1App.swift     point d'entrée
    ├── Localisation/
    │   ├── LanguageManager.swift    langue active (détection, choix persisté), `t`, `tp`, `ordinal`, `heureInterface`
    │   ├── TraductionsFR.swift      ┐ mêmes clés, même ordre, rangées par écran
    │   ├── TraductionsEN.swift      ┘
    │   └── SelecteurLangue.swift    toggle 🇫🇷 FR / 🇬🇧 EN (drapeaux emoji, aucun asset) — Landing, Connexion, Réglages
    ├── Config/
    │   ├── Config.xcconfig          valeurs de connexion — NON VERSIONNÉ, hors bundle
    │   ├── Config.xcconfig.example  gabarit à copier — hors bundle
    │   ├── SupabaseConfig.swift     lecture d'Info.plist, rien en dur
    │   ├── Couleurs.swift           palette (jetons clair / sombre, encres fixes) + typographie du design system
    │   ├── ThemeManager.swift       apparence Auto / Clair / Sombre — seul propriétaire, `overrideUserInterfaceStyle`
    │   ├── Formes.swift             rayons + les quatre ombres
    │   ├── Materiaux.swift          damier et lumière spéculaire (les deux calques décoratifs), teintes et damier des cartes de pronostic, `damierFiligrane` (5 %)
    │   ├── Mouvement.swift          courbes, durées, StyleAppui (retour d'appui)
    │   └── LandingView.swift        écran d'accueil (non connecté)
    ├── Models/
    │   ├── DecodageJSON.swift   `JSONDecoder.api` — le décodeur unique, dates ISO 8601
    │   ├── FormatPoints.swift   `formaterPoints`, `enPoints` — le seul habillage d'un nombre de points, PARTAGÉ avec le widget
    │   ├── Profil.swift         `Profil` + `ModeLivree`
    │   ├── StatsProfil.swift    stats d'un profil + `tuiles` — seul endroit qui les met en forme
    │   ├── Championnat.swift    `Championnat`, `ProchainGP`, `PositionMembre`
    │   ├── GrandPrix.swift      `GrandPrixEnBase`, `SlugCircuit`, `EcheancePronostics` — LE calcul d'échéance
    │   ├── GrandPrixSaison.swift  `EtatGp` et `GrandPrixSaison` (liste statique, noms traduits) — sortis de `CalendrierView` pour le widget
    │   ├── GPRestants.swift     décompte des GP non terminés (statut, sinon date écrite) — accueil, championnats, calendrier
    │   ├── Membre.swift         une ligne de classement
    │   ├── ResultatsGP.swift    résultats d'une course : lignes, nom coupé, mention, livrée
    │   ├── PronosticsChampionnat.swift  GP du calendrier d'un championnat, paris de chaque membre, tri par GP
    │   └── Pronostics.swift     cotes, favoris, mes pronostics, corps du POST, `ClePilote`, `OrdreMarches`
    ├── Services/
    │   ├── SupabaseManager.swift  chemin direct, sous RLS
    │   ├── APIClient.swift        chemin Railway : Bearer, décodage, réessais, réveil
    │   ├── MesChampionnats.swift  `GET /championnats/moi` — propriétaire unique, accueil + onglet ; `premierId` → `EnvironmentValues.championnatParDefaut`
    │   ├── ClassementChampionnat.swift  `GET /championnats/{id}/classement` — un appel, deux segments
    │   ├── StatistiquesProfil.swift  `GET /profils/{id}/stats` — le sien comme celui d'un membre
    │   ├── CacheService.swift     cache stale-while-revalidate mémoire + instantanés disque (`SnapshotsDisque`) — clé compte + route, 30 s, sans doublon en vol, vidé à la déconnexion
    │   ├── CalendrierSaison.swift  `GET /calendrier` — états, `gp_id` et `a_des_cotes` du calendrier
    │   ├── ProchainGrandPrix.swift  GP suivant de l'accueil + existence d'un pronostic du joueur : UNE lecture directe `grands_prix` avec jointure `pronostics(id)` (RLS)
    │   ├── ResultatsGrandPrix.swift  `GET /grands-prix/{id}/resultats` — 404 / `disponible: false` ⇒ indisponible
    │   ├── GrandsPrixJoues.swift  « Ses / Mes Grands Prix » : calendrier du championnat, puis `GET /grands-prix/{gp}/resultats?championnat_id=` par GP terminé (podium + paris, filtrés sur le membre) ; un seul GP = un seul appel, sans calendrier
    │   ├── ResultatsParGrandPrix.swift  `GET /championnats/{id}/calendrier` puis `GET /grands-prix/{gp}/pronostics/championnat/{id}`, un GP à la fois
    │   ├── DonneesPronostics.swift  cotes + favoris (+ mes pronos en direct), bascule de favori, `POST …/pronostics`
    │   ├── Administration.swift   `POST /admin/action` — scraper sans figeage, jamais le secret
    │   ├── DepotPhoto.swift       photo réduite (800 px, JPEG 0,85) → Supabase Storage, rend l'URL `?v=`
    │   ├── DonneesWidget.swift    App Group du widget : GP à venir + langue, fusion par id, rechargement — PARTAGÉ avec le widget
    │   ├── DonneesWidgetClassement.swift  App Group du widget « Classement » : championnats, premier plan, profil, relevés, avatars — PARTAGÉ
    │   ├── DonneesWidgetPronos.swift  App Group du widget « Mes pronos » : réponse brute de `/widget/pronos`, liens `greedf1://pronos|resultats/<id>` — PARTAGÉ
    │   ├── JetonWidget.swift      jeton widget dans le Keychain partagé — PARTAGÉ
    │   ├── SynchroWidgetClassement.swift  app seule : `POST /widget/token` à chaque ouverture, publication de la liste, effacement (des deux widgets à jeton)
    │   ├── NotificationsPush.swift  permission, jeton APNs → `POST`/`DELETE /push/token`, langue ; `DelegueApplication`
    │   └── ErreurAPI.swift        réseau / session / données / serveur, message affichable
    ├── Views/
    │   ├── ContentView.swift
    │   ├── Navigation/
    │   │   ├── BarreNavigation.swift  TabView à 4 onglets + apparence de la barre
    │   │   └── EcranProvisoire.swift  gabarit d'un onglet pas encore construit
    │   ├── Accueil/
    │   │   ├── AccueilView.swift       championnats et GP suivant réels, pastille + bouton selon l’état et l’existence d’un pronostic (`ProchainGrandPrix.aDesPronostics`) : « Faire » si ouvert sans, « Voir » si ouvert ou fermé avec, rien sinon
    │   │   ├── PileChampionnats.swift  championnats en paquet de cartes : carte du dessus pleine (tap = ouvrir, swipe = réordonner), bandes réduites de 3 % par cran vers le fond (`Perspective`, plancher 44 pt) : tap = aperçu sur place, 2ᵉ tap = ouvrir ; ordre mémorisé par compte (`OrdrePile`)
    │   │   ├── ApparenceDrapeau.swift  voile et encres d'un drapeau, CALCULÉS ; `ombrePortee` (texte sur drapeau à bandes)
    │   │   └── DrapeauxGP.swift        table des teintes — GÉNÉRÉE, ne pas éditer
    │   ├── Composants/
    │   │   ├── CartesChampionnat.swift  carte de championnat, cartes d'action, chargement/échec (`EchecChargement`), PARTAGÉS
    │   │   ├── BoutonPrincipal.swift    habillage du bouton de « Créer » et « Rejoindre », PARTAGÉ
    │   │   ├── BoutonApple.swift        « Continuer avec Apple » NATIF (`SignInWithAppleButton`, style noir), jamais redessiné — Landing + Connexion ; logique dans `AuthViewModel` (`signInWithIdToken`, nonce, révocation à la suppression)
    │   │   ├── ErreurEnLigne.swift      refus d'une écriture, sous le bouton — jamais d'alerte
    │   │   ├── SelecteurSegmente.swift  sélecteur segmenté pleine largeur (une seule pastille `primaire`, ressort `Mouvement.glissement`, fond neutre + damier) — Classement / Piste
    │   │   ├── MentionProvisoire.swift  `StatutResultats` (provisoire, non évaluable) + la mention « Provisoire », PARTAGÉS
    │   │   ├── SkeletonView.swift       silhouette de premier chargement (4 variantes, balayage calé sur l'écran) + `fonduChargement(_:)`, PARTAGÉS
    │   │   ├── ImageCachee.swift        `AsyncImage` avec `NSCache` partagé par URL (`CacheImages`) — avatars, photos de championnat, cockpits
    │   │   ├── PlancheSVG.swift         lecture d'une planche SVG au runtime + rendu Canvas
    │   │   └── Voiture.swift            palette, les 11 livrées, la voiture, les vignettes
    │   ├── Championnats/
    │   │   ├── ChampionnatsView.swift       liste — données réelles (`MesChampionnats`)
    │   │   ├── ChampionnatDetailView.swift  segments Classement / Piste (`SelecteurSegmente`), menu « ⋯ » en bouton rond 44 pt (`fondSegmentInactif`) : « Inviter des amis · CODE » (`ShareLink`), « Copier le code » (haptique légère, capsule « Code copié » sous le bouton pendant `Mouvement.tenueConfirmation`), séparateur, photo si créateur, quitter — rien d'ajouté à l'en-tête ; photo 100 pt réduite jusqu'à 72 pt pour un nom long, à équidistance du titre et du menu (`DispositionEntete`) — sans photo, rien : texte + ⋯ ; la piste n'est construite qu'au premier tap sur « Piste » (`pisteVue`), puis les deux contenus restent montés, seule l'opacité bascule (0,001, pas 0) ; damier en filigrane sur le sélecteur et la carte « Résultats par Grand Prix » — réels
    │   │   ├── DispositionPiste.swift       le placement des voitures, sorti de `VuePisteView` — PARTAGÉ avec le widget
    │   │   ├── VuePisteView.swift           la piste, intégrée ou plein écran, placement des voitures ; `SolPiste(debutRoute:)` repeint la route en `surfacePiste` (sombre `#5C5C5E`, transparente en clair) entre les kerbs et sous l'en-tête seulement — haut de la zone remonté par `DebutRoutePiste` — reçoit le classement ; taille UNIFORME, la plus grande par dichotomie entre 40 et 64 pt (disposition complète refaite à chaque essai ; boîtes dessin + score écartées de 4 pt, 8 pt aux kerbs) ; décalage vertical ≤ 12 pt avant d'ouvrir une voie (ordre conservé, ex æquo à la même hauteur), nombre de voies minimal, voies d'un groupe côte à côte à pas constant (largeur + 4 pt) et centrées sur l'axe, la largeur entre kerbs n'étant qu'une limite ; mémoïsée sur classement + taille (`DispositionPiste.Memo`)
    │   │   ├── ResultatsParGPView.swift     résultats par GP : sélecteur des GP terminés, paris de chacun en accordéon ; fond `FondDrapeauFlou` du GP regardé (fondu au changement), en-tête blanc et piste du sélecteur voilée sur le drapeau, beige + encres sombres sans drapeau
    │   │   ├── CreerChampionnatView.swift   `POST /championnats` → code reçu, partage — photo pas encore envoyée
    │   │   └── RejoindreChampionnatView.swift  code à 6 cases → `POST /championnats/rejoindre` ; succès ou `409` (déjà membre, retrouvé par code) ⇒ l'écran se ferme et l'appelant pousse le détail (`ouvrir`, à `onDisappear` — jamais dans la transaction de fermeture)
    │   ├── Calendrier/
    │   │   ├── CalendrierView.swift   liste statique × états réels, `gp_id` transmis — terminé → résultats, sinon → fiche
    │   │   ├── DetailGPView.swift     fiche d'un GP à venir : séances, circuit, vainqueurs — statique, état et `gp_id` reçus
    │   │   └── FichesGrandPrix.swift  séances + fiches circuit, transcrites de `GP_2026` et `CIRCUITS`
    │   ├── Resultats/
    │   │   ├── ResultatsGPView.swift       classement officiel réel ; « Mes résultats » non monté
    │   │   ├── MesResultatsGPView.swift    « Voir mes résultats » de l'accueil : fond drapeau flouté + `ContenuDetailGrandPrix` (le détail du carrousel), repli sur le classement officiel si rien joué
    │   │   └── NationalitesPilotes.swift   pilote → pays, contrepartie de `lib/nationalites.js`
    │   ├── Pronos/
    │   │   ├── EntreePronosView.swift  porte d'entrée : récap si grille en base, sinon cotes
    │   │   ├── CotesView.swift      « Fais tes paris » : favoris, mode d'emploi, étoile = favori serveur sur tous les marchés (`EtoileParisBonus`, grise d'origine), `EtoileFavori` indicative jaune cernée (`EtoileJaune`, feuille de choix de `PronosView` seulement), `MarcheCote.exclueDesBonus` (vainqueur / podium hors de la liste bonus de `PronosView`, seul endroit), `EtapePronos` ; l'accordéon d'avant reste en place, non monté
    │   │   ├── PileMarches.swift    marchés en pile de cartes repliables (mécanique de `PileChampionnats`) : toutes fermées à l'arrivée, tap sur l'en-tête = ouvrir / fermer sur place, plusieurs ouvertes à la fois, aucun swipe ; bonus teintés dans l'ordre (`Color.teintesMarcheBonus`) ; décalage en `padding` (grille paresseuse), hauteur dépliée calculée depuis `CarteCote.hauteur`
    │   │   ├── PronosView.swift     saisie préremplie, bonus parmi les favoris, `POST` + `423`
    │   │   └── RecapView.swift      récapitulatif, après le `200` ou d'entrée (grille relue) : fond `FondDrapeauFlou`, en-tête blanc (nom, date · départ, total disponible en grand), bandeau vert + `BlocEcheance` sur le flou, une `CarteRecap` par pronostic (forme de `CarteVerdict` sans pastille d’icône, damier 6 %, fond teinté à 18 % à la couleur de la catégorie — `teinteVainqueur`, `teintePodium`, `teinteBonus` (ocre, tous les bonus) ; seconde encre `encreSurTeinte`) ; `EnteteDrapeau` et `RangeeRecap` non montés
    │   └── Profil/
    │       ├── ProfilView.swift         mon profil — stats réelles, voiture lue et enregistrée (`PATCH /profils/moi`), engrenage `icon-reglages` → Réglages
    │       ├── ReglagesView.swift       apparence, langue, notifications (Réglages d'iOS), déconnexion, suppression du compte, version
    │       ├── ProfilMembreView.swift   profil d'un autre membre, lecture seule — ligne du classement + stats réelles
    │       ├── HistoriqueGPView.swift   « Ses / Mes Grands Prix » : résumé saison en deux moitiés (total, réussis / tentés, rang à gauche ; voiture du membre à droite, reçue de l’appelant), carrousel de cartes GP (drapeau net + tracé ; drapeau clair : haut nu, voile sous le texte), fond = drapeau actif étiré et flouté, en fondu, tap → la carte se déploie en détail plein écran (`matchedGeometryEffect`) ; `ContenuDetailGrandPrix` et `CarteVerdict` (carte teintée + damier, verdict en pastille pleine) y sont PARTAGÉS avec `MesResultatsGPView` — données réelles (`GrandsPrixJoues`)
    │       └── ComposantsProfil.swift   pastille, en-tête, grille, `BlocStatistiques`, `LigneGrandsPrix`, PARTAGÉS
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
| `AppIcon` | Icône de l'app — le carré G de `assets/logo-05.svg`, dégradé bord à bord, coins carrés (iOS applique son masque), rendu depuis `assets/AppIcon-1024.png` (8 tailles iPhone 20 à 60 pt + 1024 `ios-marketing`, format classique `iphone` — le format « All Sizes » `universal` n’est pas reconnu par actool en `iphoneos` ; PNG — pas vectoriel) |
| `logo-05` | Logo complet — icône carrée + bandeau, viewBox « 0 0 894.21 520.39 » |
| `logo-bandeau` | Bandeau seul, en-tête de `LandingView` |
| `icone-accueil` | Garage — onglet **Accueil**, 25,67 × 28 pt, *template* |
| `icone-championnats` | Coupe — onglet **Championnats**, 17,86 × 28 pt, *template* |
| `icone-calendrier` | Calendrier — onglet **Calendrier**, 22,20 × 28 pt, *template* |
| `icone-profil` | Pilote casqué — onglet **Profil**, 22,42 × 28 pt, *template* |
| `icone-creer` | Croix + coupe — carte « Créer un championnat », 40 × 40 pt, *template* |
| `icone-rejoindre` | Deux casques — carte « Rejoindre un championnat », 40 × 40 pt, *template* |
| `icone-etoile` | Étoile — bouton « pari bonus » de `CotesView`, 22 × 22 pt, *template* |
| `icone-drapeau-damier` | Drapeau à damier — cellule « Mes / Ses Grands Prix » du profil, 24,22 × 22 pt, *template* |
| `icon-reglages` | Engrenage — bouton Réglages de `ProfilView`, 24 × 24 pt, trait 1,5, *template* (encre `encrePrimaire`). Source : `Ressources/icon-reglages.svg` |
| `icone-google` | Logo Google — bouton « Continuer avec Google », 24 × 24 pt. **Pas de rendu *template*** : ses quatre couleurs sont la marque, comme un drapeau. Source : `Ressources/icone-google.svg`, les mêmes tracés que `IconeGoogle` (`frontend/src/composants/Icones.jsx`) |
| `texture-hexa` | Damier en filigrane des cartes — monté par ``Damier``, jamais en direct |
| `flag-<slug>` | Les 12 drapeaux des pays hôtes. **Pas de rendu *template*** : ils gardent leurs couleurs |
| `drapeau-<code>` | Les 17 drapeaux de **nationalité** — les 16 de la grille 2026, plus l'Autriche du palmarès —, en ISO alpha-2 — `drapeau-gb`, `drapeau-nl`… Fond des lignes de résultats **et des cartes « Derniers vainqueurs »**. Pas *template* non plus |
| `trace-<slug>` | Les 12 tracés de circuits, *template* — ils prennent l'encre de l'écran |

> **Les drapeaux et les tracés viennent de la version web, pas d'une recopie.**
> `scripts/extraire-gp.mjs` lit les trois tables de `frontend/src/composants/`
> (`DRAPEAUX`, `DRAPEAUX_SVG`, `TRACES`) et en écrit les fichiers de `Ressources/flags/`
> et `Ressources/traces/`, plus la table des teintes de `DrapeauxGP.swift`. Un cadrage ou
> un chemin recopié à la main divergerait de la source au premier ajustement. **Quatre
> drapeaux sont des bandes** (Pays-Bas, Italie, Espagne, Azerbaïdjan) : c'est ce que la
> planche `assets/flags.svg` ne dessine pas, et ce que le web rend en dégradé.
> Ajouter un Grand Prix = l'ajouter **côté web**, puis rejouer le script.
>
> **Les deux familles de drapeaux ne se confondent pas.** `flag-<slug>` peint un pays
> **hôte** — il habille une carte de Grand Prix, et quatre d'entre eux sont des bandes que
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
> **Le palmarès en ajoute un.** Les cartes « Derniers vainqueurs » de `DetailGPView`
> citent des retraités hors grille — Lauda (Autriche). Leurs codes sont la liste
> `PALMARES` du même script ; un palmarès qui cite un nouveau pays = un code de plus là.
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
élargie à un carré de 88 unités, jamais une tranche arithmétique de la planche. Le drapeau
à damier l'est aussi (`icone-drapeau-damier`), sur sa boîte englobante **non carrée** : la
planche embarque une image raster à partir de x 457,38, qu'un carré centré ferait entrer.
Le chronomètre et les deux pilotes ne sont pas encore découpés : une ligne au manifeste suffit.

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
