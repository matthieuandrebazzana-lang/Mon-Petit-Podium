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

**Couleurs et typographie** viennent de `Config/Couleurs.swift`, seul propriétaire de la
palette (`docs/design-system.md`). Helvetica Neue, **graisses 400 et 500 uniquement**.
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
│   └── ajouter-assets.sh        SVG de Ressources/ → Assets.xcassets, en ligne de commande
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
    │   ├── Couleurs.swift           palette du design system
    │   └── LandingView.swift        écran d'accueil (non connecté)
    ├── Models/                  (vide)
    ├── Services/
    │   └── SupabaseManager.swift
    ├── Views/
    │   └── ContentView.swift
    ├── Resources/               ← EMBARQUÉ dans l'app
    │   ├── Info.plist               hors bundle (exception d'appartenance)
    │   └── Assets.xcassets/
    │       ├── AccentColor.colorset/
    │       ├── AppIcon.appiconset/
    │       ├── logo-05.imageset/        logo complet (icône carrée + bandeau)
    │       └── logo-bandeau.imageset/   bandeau seul
    └── Ressources/              ← RÉFÉRENCE, exclue du bundle
        ├── logo-05.svg              source, viewBox « 0 0 894.21 520.39 »
        ├── logo-bandeau.svg         idem à viewBox rognée « 0 215 894.21 243 »
        └── Screenshots/             28 captures de la version web
```

> **`Resources/` et `Ressources/` ne se confondent pas.** `Resources/` (un s) est ce que
> l'app embarque. `Ressources/` (deux s) est de la matière de travail : elle est retirée du
> bundle par `EXCLUDED_SOURCE_FILE_NAMES` — sans quoi les 28 captures y ajoutaient **17 Mo**.

## 6. Captures de référence

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
