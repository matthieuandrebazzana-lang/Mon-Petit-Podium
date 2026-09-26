# App native Swift / SwiftUI

Référence complète pour développer le client iOS natif de **Greed F1**.

> **Portée.** Ce document est écrit pour un développeur qui connaît Swift mais pas le
> projet. Il ne doit jamais avoir à ouvrir le code FastAPI ni le code React. Tout ce qui
> suit est **tiré du code existant** (`backend/app/`, `frontend/src/`) et des autres
> fichiers `docs/`. Ce qui n'est pas vérifiable dans le code est explicitement marqué
> **« à vérifier »**.

---

## 1. Vue d'ensemble

**Greed F1** est une application de pronostics de Formule 1 entre amis. Un utilisateur crée
un **championnat**, partage un code à 6 caractères, ses amis le rejoignent. Avant chaque
Grand Prix chacun saisit ses pronostics ; les points rapportés valent **la cote Unibet ×
10, arrondie à l'entier**. Après la course, les résultats sont récupérés automatiquement
depuis OpenF1 et les points attribués. L'application est **ouverte au public**.

| Couche | Techno | Adresse |
|---|---|---|
| Backend métier | FastAPI + APScheduler, sur **Railway** | `https://mon-petit-podium-production.up.railway.app` |
| Base + Auth + Storage | PostgreSQL, sur **Supabase** | `https://ycsxcythvtcruiomrgvv.supabase.co` |
| Client web existant | React 19 + Vite, sur Vercel | `https://mon-petit-podium.vercel.app` |

**SDK à utiliser : [`supabase-swift`](https://github.com/supabase/supabase-swift)**
(Swift Package Manager). Il porte l'authentification, les lectures PostgREST directes et
le dépôt de fichiers dans Storage. Les appels à Railway se font au `URLSession` ordinaire.

> **Les trois valeurs ci-dessus sont publiques par conception**, ainsi que la clé anonyme
> Supabase (`VITE_SUPABASE_ANON_KEY`, à récupérer dans le tableau de bord Supabase). C'est
> la **RLS** qui protège les données, jamais l'obscurité de la clé. La clé
> **`service_role`**, elle, ne quitte jamais Railway et **ne doit sous aucun prétexte être
> embarquée dans l'app iOS**.

> **Cold start Railway.** Le plan gratuit met le service en veille. Un premier appel après
> une période d'inactivité peut prendre plusieurs secondes ou rendre `502`/`503`/`504`. Ces
> trois statuts sont des **erreurs réseau**, pas des pannes serveur : le bon message est
> « Connexion au serveur en cours… », et réessayer marche. Voir §7.

### 1.1 Le projet Xcode

Le projet vit dans **`ios/`**, à la racine du monorepo, séparé du code web.

```
ios/
├── Greed F1.xcodeproj/
└── Greed F1/
    ├── App/          GreedF1App.swift
    ├── Config/       SupabaseConfig.swift · Couleurs.swift · Config.xcconfig
    ├── Services/     SupabaseManager.swift
    ├── Views/        ContentView.swift
    ├── Models/
    └── Resources/    Info.plist · Assets.xcassets
```

| Réglage | Valeur |
|---|---|
| Bundle identifier | `com.bazzana.greedf1` |
| Cible de déploiement | iOS 17.0 |
| Familles d'appareils | iPhone seulement (`TARGETED_DEVICE_FAMILY = 1`) |
| Orientation | Portrait seulement |
| `supabase-swift` | `2.55.2`, épinglé dans `Package.resolved` (produits `Supabase` et `Auth`) |

Le dossier `Greed F1/` est un **groupe synchronisé** (`PBXFileSystemSynchronizedRootGroup`,
Xcode 16+) : un fichier ajouté sur le disque entre dans la cible sans toucher au
`.pbxproj`. Trois fichiers en sont exclus explicitement — les deux `.xcconfig` et
`Info.plist` — pour qu'ils ne partent pas dans le bundle.

### 1.2 Configuration : `Config.xcconfig`

**Aucune valeur de connexion n'est écrite en dur dans le code.** Le chemin est :

```
Config.xcconfig  →  réglages de build  →  Info.plist  →  SupabaseConfig  →  SupabaseManager
```

`Config.xcconfig` n'est **pas versionné** (`.gitignore` racine). Au premier clone :

```sh
cd "ios/Greed F1/Config" && cp Config.xcconfig.example Config.xcconfig
# puis renseigner SUPABASE_ANON_KEY (tableau de bord Supabase, ou frontend/.env.local)
```

Une valeur manquante arrête l'app au démarrage sur un message qui nomme la clé absente,
plutôt que de la laisser échouer plus tard sur un appel réseau incompréhensible.

> **Les deux barres d'une URL dans un `.xcconfig`.** `//` y ouvre un commentaire, y compris
> au milieu d'une URL. Le retrait des commentaires est **lexical et précède la substitution
> des variables** : l'astuce répandue `https:$()//hôte` ne suffit donc pas — elle laisse
> `https:` tout court, et le défaut ne se voit qu'en lisant l'`Info.plist` du bundle
> **construit**. La seule forme qui survive passe les barres par une variable :
> ```
> SLASH = /
> SUPABASE_URL = https:$(SLASH)$(SLASH)ycsxcythvtcruiomrgvv.supabase.co
> ```

### 1.3 Clients partagés

Deux points d'entrée, un par chemin de données (§3.9) — **aucun écran n'ouvre de
`URLSession` ni de requête PostgREST de lui-même.**

| Singleton | Chemin | Ce qu'il porte |
|---|---|---|
| `SupabaseManager.partage` (`Services/`) | **(B)** Supabase direct, sous RLS | Le client `supabase-swift` · `jetonAcces()`, relu à chaque appel |
| `APIClient.partage` (`Services/`) | **(A)** Railway | `Bearer`, décodage, classement des erreurs, réveil |

Le client Supabase n'est construit qu'une fois : il persiste la session dans le Keychain et
rafraîchit le jeton tout seul, mais un second client ferait travailler deux rafraîchisseurs
sur le même Keychain.

**`APIClient`** — `requete<T>(_ chemin:, methode:, corps:, parametres:)` rend un modèle
décodé ou lève une **`ErreurAPI`** dont le `message` est déjà affichable (§7.2) ;
`envoyer(…)` pour une route dont la réponse ne sert à rien. Quatre comportements à
connaître :

- **Les lectures (`GET`) sont rejouées deux fois** sur un échec réseau (1,5 s puis 3 s) :
  c'est le cold start Railway, et il se résorbe seul. **Les écritures ne le sont jamais** :
  rejouer un `POST` dont on ignore s'il a abouti n'est pas une décision de la couche réseau.
- **Un `401` purge la session** (`signOut`, §7.3). `AuthViewModel` écoute `signedOut` sur
  `authStateChanges` et revient à l'accueil non connecté — un seul propriétaire, quelle que
  soit l'origine de la déconnexion. Un `503` ne déconnecte jamais.
- **Une annulation n'est pas un échec** : un écran quitté en cours d'appel reçoit
  `CancellationError`, et rien ne doit s'afficher.
- **`reveiller()`** tire `GET /health` sans attendre la réponse. Appelé au `onAppear` de la
  racine (`GreedF1App`).

**`JSONDecoder.api`** (`Models/DecodageJSON.swift`) est le **décodeur unique**, pour Railway
**et** pour les lectures directes (`execute().data` puis `JSONDecoder.api`) : dates ISO 8601
avec ou sans fraction (§7.4 — les six décimales de PostgreSQL passent). Les clés ne sont
**pas** converties : chaque modèle déclare ses `CodingKeys` en `snake_case`.

**Règles des modèles `Codable`** (`Models/`) :

- **Un champ qui a une valeur par défaut côté backend en a une ici** (`decodeIfPresent ??`).
  C'est le corollaire de la règle Pydantic de la racine : un backend déployé avant sa
  migration perd un champ, il ne fait pas échouer le décodage de toute la réponse.
- **Un sous-objet secondaire se décode en `try?`** (`prochain_gp`, `position` d'un
  `Championnat`) : il fait perdre son rang à une carte, jamais la liste.
- **Les énumérations ont un repli** : `ModeLivree` inconnu ⇒ `.perso`.
- **Les URL d'image sont des `URL?`** ; une chaîne vide vaut `nil`.
- **`is_admin` retombe sur `false`** à l'absence comme à l'échec.

| Modèle | Route | Nom backend |
|---|---|---|
| `Profil` | `GET /profils/{id}`, `PATCH /profils/moi`, lecture directe de `profils` | `ProfilServi` |
| `Championnat` (+ `ProchainGP`, `PositionMembre`) | `GET /championnats/moi`, `POST /championnats`, `/rejoindre`, `PATCH` | `Championnat` |
| `Membre` | `GET /championnats/{id}/classement` | `LigneClassement` |

**Le profil du compte connecté** se lit **en direct dans `public.profils`**
(`AuthViewModel.chargerProfil`, colonnes nommées par `Profil.colonnes`), **jamais dans les
métadonnées du jeton**, figées à l'inscription. Au lancement, à la connexion et à
l'inscription. En cas d'échec, le profil déjà connu est gardé (un pseudo périmé vaut mieux
que rien) et `estAdmin` retombe à `false`.

---

---

## 2. Authentification

Toute l'authentification passe par **Supabase Auth**, jamais par Railway. Railway ne fait
que **vérifier** le jeton qu'on lui présente.

### 2.1 Initialisation du client

```swift
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://ycsxcythvtcruiomrgvv.supabase.co")!,
    supabaseKey: "<clé anonyme>"
)
```

`supabase-swift` **persiste la session dans le Keychain et rafraîchit le jeton tout seul** :
aucune gestion manuelle du refresh token n'est nécessaire. Le comportement attendu est
celui du client web (`frontend/src/lib/supabase.js`) : `persistSession`,
`autoRefreshToken`, flux **PKCE**.

### 2.2 Inscription email / mot de passe

Le **pseudo** part dans les métadonnées de l'utilisateur. C'est le trigger
`on_auth_user_created` en base qui crée la ligne `public.profils` à partir de là, avec sa
livrée initiale.

```swift
try await supabase.auth.signUp(
    email: email,
    password: motDePasse,
    data: ["pseudo": .string(pseudo)]
)
```

Trois comportements à reproduire, tous documentés dans `frontend/src/auth/AuthContexte.jsx` :

1. **Vérifier la disponibilité du pseudo AVANT de demander le mot de passe.** La fonction
   `pseudo_disponible` est appelable **sans être connecté** :

   ```swift
   let libre: Bool = try await supabase
       .rpc("pseudo_disponible", params: ["pseudo_a_tester": pseudo])
       .execute().value
   ```

   **Si l'appel échoue, considérer le pseudo comme disponible et continuer** : la garantie
   réelle est l'index unique en base, pas ce test.

2. **Un pseudo explicitement choisi n'est jamais remplacé en douce.** S'il est déjà pris,
   l'inscription entière échoue avec un message qu'il faut traduire en
   « Ce pseudo est déjà pris ».

3. **Adresse déjà inscrite : l'inscription RÉUSSIT en apparence.** Quand la confirmation
   par email est active, Supabase protège la liste de ses inscrits en renvoyant un
   utilisateur **sans identité** plutôt qu'une erreur. Sans ce test, l'utilisateur
   attendrait indéfiniment un email qui n'arrivera jamais. Le test côté web est
   `emailDejaInscrit` : l'utilisateur rendu a une liste `identities` **vide**. Message à
   afficher : « Cette adresse est déjà utilisée. Connecte-toi plutôt. »

   > **À vérifier** : l'exposition exacte du champ `identities` dans `supabase-swift`.

**Absence de session dans la réponse** ⇒ la confirmation par email est active : l'écran doit
inviter à relever sa boîte mail, pas router vers l'accueil.

### 2.3 Connexion

```swift
try await supabase.auth.signIn(email: email, password: motDePasse)
```

### 2.4 Récupération du jeton JWT

**Le jeton est relu à chaque appel, jamais mémorisé** — c'est la règle de
`frontend/src/lib/api.js`, et elle vaut telle quelle ici : un jeton capturé une fois pour
toutes serait périmé au retour d'une longue mise en veille.

```swift
let jeton = try await supabase.auth.session.accessToken
```

### 2.5 Appels à Railway

**Toute requête vers Railway porte l'en-tête `Authorization: Bearer {jwt}`**, sauf les trois
routes publiques listées au §3. Le corps de la requête **ne dit jamais qui est l'appelant** :
le backend ne travaille qu'avec l'identifiant extrait du jeton vérifié.

```swift
var requete = URLRequest(url: URL(string: "\(apiURL)\(chemin)")!)
requete.httpMethod = methode
requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
requete.setValue("application/json", forHTTPHeaderField: "Content-Type") // si corps
```

Le backend valide le jeton en le présentant à Supabase (`/auth/v1/user`), avec un cache de
60 s. Un jeton invalide ou expiré rend **`401`** ; une panne du service d'authentification
rend **`503`** — les deux ne se traitent pas pareil (§7.3).

### 2.6 Déconnexion

```swift
try await supabase.auth.signOut()
```

**Vider tout cache local à ce moment.** La règle du projet : *toute clé de cache porte
l'identifiant du compte*. Deux personnes qui se relaient sur le même téléphone ne doivent
jamais voir les données de l'autre, fût-ce une fraction de seconde.

### 2.7 Google OAuth

```swift
try await supabase.auth.signInWithOAuth(provider: .google) { config in
    config.redirectURL = URL(string: "greedf1://auth-callback")
}
```

Points à connaître :

- **Le flux est PKCE**, et `supabase-swift` sait consommer le jeton au retour via
  `supabase.auth.session(from: url)` dans le handler d'URL de l'app. Il faut déclarer un
  **schéma d'URL personnalisé** dans `Info.plist` et l'ajouter aux *Redirect URLs* du
  tableau de bord Supabase.
- **Une inscription OAuth ne transmet aucun pseudo.** Le trigger
  `gerer_nouvel_utilisateur` fabrique alors un pseudo de la forme `pilote-xxxxxxxxxx`
  avec incrémentation : une inscription Google ne doit jamais échouer pour cause de
  pseudo pris. L'app doit proposer de le changer ensuite.
- **`ASWebAuthenticationSession` est le chemin recommandé sur iOS.**
  `supabase-swift` peut aussi consommer un `idToken` natif obtenu via *Sign in with
  Google* (`signInWithIdToken`) — c'est le geste le plus propre sur iOS, et il évite
  l'aller-retour navigateur.

> ### État réel côté production — à traiter avant de coder l'écran
> **Les clés OAuth ne sont PAS renseignées dans le tableau de bord Supabase** au moment où
> ces lignes sont écrites : `frontend/src/composants/BoutonsOAuth.jsx` porte
> `OAUTH_ACTIF = false` et masque les boutons Google et Apple, précisément parce qu'ils
> échoueraient systématiquement. **Renseigner les clés dans Supabase est un préalable**,
> pas une conséquence du code iOS. Apple Sign-In est prévu dans le même module et suit
> exactement le même flux (`provider: .apple`), et il est **obligatoire sur l'App Store**
> dès lors que Google est proposé.

### 2.8 Réinitialisation du mot de passe

`supabase.auth.resetPasswordForEmail(_:redirectTo:)`. Le lien reçu par email **ouvre une
session** : l'utilisateur est techniquement connecté sans avoir le droit d'entrer dans
l'app. Le client web traite ce cas par une route hors des gardes, déclenchée par
l'événement `PASSWORD_RECOVERY` du flux `onAuthStateChange`. **Reproduire cette séparation** :
un utilisateur arrivé par ce lien doit atterrir sur l'écran de nouveau mot de passe, pas
sur l'accueil.

---

## 3. Les endpoints

**Base URL : `https://mon-petit-podium-production.up.railway.app`**

Conventions de l'API : domaine au **pluriel**, sous-chemin **`/moi`** pour ce qui appartient
à l'appelant, **verbe explicite** pour ce qui n'est pas un CRUD (`/rejoindre`, `/quitter`,
`/declencher`), préfixe **`/jobs/`** pour les déclenchements d'administration.

### 3.0 Codes d'erreur — la grammaire commune

Tout le backend partage le même vocabulaire de statuts. À connaître avant la liste des
routes :

| Statut | Sens dans ce projet |
|---|---|
| `401` | Jeton absent, invalide ou expiré. `detail` : « Authentification requise. » ou « Session expirée. Reconnecte-toi. » |
| `403` | Identifié, mais pas le droit : pas membre du championnat, pas créateur, pas administrateur |
| `404` | La ressource n'existe pas |
| `409` | Conflit — uniquement sur `POST /championnats/rejoindre` (déjà membre) |
| `422` | **Deux cas distincts, même statut.** Refus métier en français, OU panne interne rendue lisible |
| `423` | Pronostics fermés : la course est partie |
| `425` | Résultats pas encore publiés par OpenF1 (« Too Early ») |
| `503` | Supabase non configuré ou injoignable, ou `ADMIN_SECRET` absent |

> **Le `422` est un choix de TRANSPORT, jamais de sémantique.** Le backend ne rend jamais
> de message technique : il journalise la cause dans les logs Railway et renvoie un
> `detail` **en français**, prêt à afficher. Corollaire pour le diagnostic : **une panne ne
> se lit plus à l'écran, il faut ouvrir les logs Railway.**

**Deux formes de corps d'erreur**, et elles ne s'affichent pas pareil :

```jsonc
// Nos propres refus — `detail` est une CHAÎNE française, affichable telle quelle
{ "detail": "Tu ne fais pas partie de ce championnat." }

// Validation Pydantic (corps mal formé) — `detail` est une LISTE d'objets EN ANGLAIS
{ "detail": [ { "type": "string_too_short", "loc": ["body", "nom"], "msg": "...", ... } ] }
```

**Ne jamais afficher la seconde forme.** Le client web retombe dans ce cas sur un message
générique (« Une erreur est survenue. Réessaie. »). Faire de même.

```swift
enum DetailErreur: Decodable {
    case message(String)
    case validation           // liste Pydantic : on n'affiche jamais son contenu

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let texte = try? c.decode(String.self) { self = .message(texte) }
        else { self = .validation }
    }
}
```

---

### 3.1 Système

#### `GET /health`

Publique. Sert aussi de **ping de réveil** après une mise en veille Railway — à appeler au
lancement de l'app, sans attendre sa réponse pour afficher l'écran.

**Réponse `200`**
```json
{ "status": "ok", "version": "0.66.0", "environment": "production" }
```

---

### 3.2 Profils

#### `GET /profils/{profil_id}`

Jeton requis. Ouverte à **tout compte connecté**, alignée sur la politique RLS « Profils
lisibles par les membres connectés ».

**Réponse `200`**
```json
{
  "id": "uuid",
  "pseudo": "MaxV33",
  "couleur1": "#800111",
  "couleur2": "#FFFFFF",
  "numero": 33,
  "livree_mode": "perso",
  "livree_ecurie": null,
  "is_admin": false,
  "avatar_url": null,
  "couleur_texte": null,
  "cree_le": "2026-08-13T18:23:31+00:00"
}
```

| Champ | Type | Note |
|---|---|---|
| `couleur1` | `String` | Coque de la voiture, `#RRGGBB` |
| `couleur2` | `String` | Ailerons, `#RRGGBB` |
| `numero` | `Int?` | 1 à 99. **`nil` = pas de numéro choisi**, jamais `0` — c'est alors le rang au classement qui s'affiche sur la voiture |
| `livree_mode` | `String` | `perso` ou `ecurie` |
| `livree_ecurie` | `String?` | Slug de livrée (§5.3). Un slug inconnu **retombe sur `perso`**, ce n'est pas une panne |
| `is_admin` | `Bool` | **Servi, jamais reçu** : impossible de se promouvoir par `PATCH` |
| `avatar_url` | `String?` | URL publique Storage. `nil` ⇒ afficher les initiales du pseudo |
| `couleur_texte` | `String?` | **`nil` veut dire « pas de choix », jamais « pas de couleur »** — voir §6.6 |

**Erreurs** : `401` · `404` « Ce membre n'existe pas. » · `503`

#### `GET /profils/{profil_id}/stats`

Jeton requis **et** au moins un championnat partagé avec la cible. Son propre profil passe
toujours.

**Réponse `200`**
```json
{
  "paris_gagnes_pct": 42,
  "pts_moyen_gp": 87,
  "meilleur_coup": 95,
  "cote_moy_tentee": 31,
  "pronostics_notes": 12,
  "gp_joues": 3,
  "total_points": 261,
  "saison": 2026
}
```

**Tous des entiers, jamais de décimale** — y compris `cote_moy_tentee`, qui s'affiche
« 31 » et **jamais** « ×3,1 » (§6.1). La saison est **l'année civile en UTC**.

Les trois derniers compteurs (`pronostics_notes`, `gp_joues`, `total_points`) ne
s'affichent pas tels quels : ils disent à l'interface **si la saison a commencé**. Sans eux,
« meilleur coup 0 » et « 0 % » s'afficheraient avant le premier Grand Prix, ce qui se lit
comme un mauvais bilan alors qu'il n'y a pas encore de bilan.

**Erreurs** : `401` · `403` « Tu ne partages aucun championnat avec ce membre. » (**rendu
AVANT de lire le profil visé** — répondre « ce membre n'existe pas » à un inconnu lui
apprendrait quels identifiants sont de vrais comptes) · `404` · `503`

#### `PATCH /profils/moi`

Jeton requis. **Aucun identifiant dans le chemin** : c'est ce qui empêche de repeindre la
voiture de quelqu'un d'autre. Modification **partielle** — ce qui n'est pas transmis n'est
pas touché.

**Corps** — tous les champs sont facultatifs :
```json
{
  "couleur1": "#800111",
  "couleur2": "#FFFFFF",
  "couleur_texte": "#FFFFFF",
  "numero": 33,
  "retirer_numero": false,
  "livree_mode": "ecurie",
  "livree_ecurie": "ferrari",
  "avatar_url": "https://….supabase.co/storage/v1/object/public/avatars/{profil_id}/avatar.jpg?v=1758000000",
  "retirer_avatar": false
}
```

Six règles que le client doit respecter :

1. **`retirer_numero` et `retirer_avatar` sont des drapeaux EXPLICITES.** Les champs étant
   tous facultatifs, `numero: null` serait indiscernable de « champ non transmis ». Sans
   ces drapeaux, un membre ne pourrait **plus jamais** revenir à l'état sans numéro ni
   retirer sa photo. **Le retrait l'emporte sur l'envoi** dans un même corps.
2. **Les deux couleurs doivent différer**, à la casse près. La comparaison porte sur le
   couple **résultant** : n'envoyer que `couleur1` égale à la `couleur2` déjà en base est
   refusé. Message : « Choisis deux couleurs différentes pour ta voiture. »
3. **`couleur_texte` n'entre PAS dans ce contrôle** : le texte est posé *sur* la
   carrosserie, pas à côté.
4. **`couleur_texte` ne part que si elle a été CHOISIE.** Le sélecteur affiche toujours une
   couleur — à défaut l'encre calculée. L'envoyer inconditionnellement figerait cette encre
   en base au premier enregistrement, et le membre repartirait avec un numéro blanc sur une
   coque devenue blanche sans avoir rien demandé.
5. **`livree_mode: "ecurie"` exige une `livree_ecurie`** (résultante, pas transmise).
   Message : « Choisis une livrée d'écurie avant de l'appliquer. »
6. **`avatar_url` est vérifiée en cinq points** (§3.8). Le dossier doit être **l'identifiant
   du jeton** : `avatars/{mon id}/avatar.jpg`.

Formats : couleurs `^#[0-9A-Fa-f]{6}$` (normalisées en majuscules) · `numero` 1–99 ·
`livree_ecurie` `^[a-z0-9-]{2,32}$` · `avatar_url` ≤ 512 caractères.

**Réponse `200`** : le `ProfilServi` complet (même forme que `GET /profils/{id}`).
Un corps sans aucun champ exploitable rend l'état courant, sans écriture.

**Erreurs** : `401` · `422` (refus métier, message français affichable) · `404` « Ton profil
est introuvable. » · `503`

---

### 3.3 Championnats

#### `POST /championnats`

Jeton requis.

**Corps** : `{ "nom": "Les Boss du Paddock" }` — **2 à 40 caractères** après `strip()`.

**Réponse `201`** : un objet `Championnat` (voir ci-dessous), `nombre_membres: 1`.
**Le créateur rejoint automatiquement son championnat**, dans la même transaction.

Le code d'invitation est tiré de `secrets` : **6 caractères alphanumériques majuscules,
sans séparateur** (`F1X7K2`). Cinq tentatives en cas de collision, puis échec franc.

**Erreurs** : `401` · `422` « Le nom du championnat doit faire entre 2 et 40 caractères. » ·
`503` « Impossible de générer un code d'invitation. Réessaie. »

#### `GET /championnats/moi`

Jeton requis. **La route la plus sollicitée de l'app.**

**Réponse `200`** — une liste de :
```json
[{
  "id": "uuid",
  "nom": "Les Boss du Paddock",
  "code_invitation": "F1X7K2",
  "cree_par": "uuid-ou-null",
  "cree_le": "2026-08-13T18:23:31+00:00",
  "nombre_membres": 7,
  "est_createur": true,
  "photo_url": null,
  "prochain_gp": {
    "id": "uuid",
    "nom": "GP Pays-Bas",
    "date_course": "2026-08-23T13:00:00+00:00",
    "statut": "cotes_figees"
  },
  "position": { "mon_rang": 3, "mes_points": 187, "points_leader": 342 }
}]
```

| Champ | Type | Note |
|---|---|---|
| `cree_par` | `UUID?` | **Nullable** : le championnat survit à la suppression du compte de son créateur. Un type strict ferait échouer le décodage de TOUTE la liste dès qu'un championnat est orphelin |
| `est_createur` | `Bool` | Calculé côté serveur à partir du jeton |
| `prochain_gp` | objet `?` | **Le même pour tous les championnats** — `grands_prix` est une table globale. `nil` si plus aucun GP à venir, **ou si sa lecture a échoué** |
| `position` | objet `?` | `nil` si le classement n'a pas pu être lu, ou **au-delà du 12ᵉ championnat** (`LIMITE_CLASSEMENTS = 12`) : les cartes suivantes s'affichent sans rang |

> **L'échec d'une lecture secondaire n'emporte jamais la liste.** Un classement en panne
> fait perdre son rang à une carte, pas la liste. **Une liste vide serait un cul-de-sac.**
> Le client doit donc traiter `prochain_gp` et `position` comme facultatifs en toute
> circonstance.

`points_leader` est **le plus haut total du championnat**, pas celui du premier de la liste
— c'est ce qui remplit la jauge de progression.

**Erreurs** : `401` · `422` · `503`

#### `POST /championnats/rejoindre`

Jeton requis.

**Corps** : `{ "code": "f1x7k2" }` — **le code est normalisé côté serveur** : majuscules,
espaces et tirets retirés. Accepter « f1 x7-k2 » saisi à la main est le comportement voulu ;
inutile de le nettoyer côté client.

**Réponse `200`** : l'objet `Championnat` (sans `prochain_gp` ni `position` — l'écran
d'arrivée n'en affiche pas).

**Erreurs** : `401` · `422` « Un code d'invitation compte 6 caractères. » ·
`404` « Aucun championnat ne correspond à ce code. » ·
`409` « Tu fais déjà partie de ce championnat. » · `503`

#### `PATCH /championnats/{championnat_id}`

Jeton requis **et créateur**. Aujourd'hui : **la photo seule** (le nom n'est pas modifiable).

**Corps**
```json
{ "photo_url": "https://….supabase.co/storage/v1/object/public/championnats/{championnat_id}/photo.jpg?v=1758000000" }
```
ou `{ "retirer_photo": true }`. **Le retrait l'emporte sur l'envoi.**

Le dossier attendu est **l'identifiant du championnat modifié** (§3.8). Sert **à la création
comme après** : l'écran crée le championnat, dépose la photo sous l'identifiant obtenu, puis
appelle cette route.

> **Son échec n'annule pas la création.** L'écran d'arrivée affiche le championnat sans sa
> photo plutôt que de perdre le championnat.

**Réponse `200`** : l'objet `Championnat`.

**Erreurs** : `401` · `403` « Seul le créateur du championnat peut changer sa photo. »
(**jamais `404`** : le championnat existe, l'appelant en est peut-être membre) · `404`
« Ce championnat n'existe pas. » · `422` · `503`

#### `GET /championnats/{championnat_id}/classement`

Jeton requis **et membre**.

**Réponse `200`** — une liste triée et déjà rangée :
```json
[{
  "profil_id": "uuid",
  "pseudo": "MaxV33",
  "total_points": 342,
  "pronostics_reussis": 18,
  "meilleure_cote": 95,
  "rang": 1,
  "ordre_inscription": 2,
  "couleur1": "#800111",
  "couleur2": "#FFFFFF",
  "couleur_texte": null,
  "numero": 33,
  "livree_mode": "perso",
  "livree_ecurie": null,
  "avatar_url": null
}]
```

- `total_points` vaut **`0`, jamais `null`**, quand rien n'est encore noté : un classement
  à blanc se lit « tout le monde à zéro », pas « on ne sait pas ».
- `meilleure_cote` est **`nil`** tant que le membre n'a rien réussi — `0` dirait que son
  meilleur coup vaut zéro.
- `rang` va de 1 à N **sans ex æquo** : les quatre critères de départage (§6.5) départagent
  toujours.
- `ordre_inscription` est le rang d'adhésion, **4ᵉ critère de départage** — c'est lui qui
  doit servir à attribuer une couleur ou un repère stable à un membre, jamais l'index dans
  le tableau.

Un membre qui n'a jamais pronostiqué figure au classement avec 0 point.

**Erreurs** : `401` · `403` « Tu ne fais pas partie de ce championnat. » · `422` · `503`

#### `GET /championnats/{championnat_id}/calendrier?saison=2026`

Jeton requis **et membre**. `saison` est facultative, **défaut `2026`** (constante
`SAISON_COURANTE`, écrite en dur plutôt que déduite de l'horloge : le calendrier doit
rester lisible en intersaison).

> **Le profil vient du jeton, jamais de l'URL.** « Mon score sur ce GP » ne peut désigner
> que l'appelant.

**Réponse `200`**
```json
[{
  "gp_id": "uuid",
  "nom": "GP Pays-Bas",
  "date_course": "2026-08-23T13:00:00+00:00",
  "date_qualifications": "2026-08-22T13:00:00+00:00",
  "statut": "termine",
  "cotes_disponibles": true,
  "resultats_disponibles": true,
  "vainqueur": "M.Verstappen",
  "mes_points": 187,
  "mon_rang": 3,
  "mes_pronostics": 5,
  "classement": [
    { "profil_id": "uuid", "pseudo": "MaxV33", "points": 187, "rang": 1,
      "couleur1": "#800111", "couleur2": "#FFFFFF" }
  ]
}]
```

- `date_course` et `date_qualifications` sont **nullables** : Unibet publie parfois un GP
  avant d'en annoncer le programme. **Le GP est servi quand même**, en fin de liste.
- `cotes_disponibles` / `resultats_disponibles` sont lus dans les tables `cotes` et
  `resultats_gp`, **jamais déduits du statut** — le statut peut mentir dans les deux sens.
- `mes_points` / `mon_rang` sont **`nil`** tant qu'aucun pronostic n'est noté — jamais `0`,
  qui se lirait « tout raté ».
- **Sur le classement d'UN Grand Prix, `rang` est un `rank`, pas un `row_number`** : les ex
  æquo s'affichent comme tels (§6.5).

Aucun Grand Prix en base est un état normal : la réponse est alors `[]`, jamais un `404`.

**Erreurs** : `401` · `403` · `422` · `503`

#### `DELETE /championnats/{championnat_id}/quitter`

Jeton requis.

**Réponse `204 No Content`** — pas de corps.

- Le créateur peut partir comme n'importe quel membre ; le championnat lui survit sans
  créateur.
- **Un championnat vidé de ses membres est supprimé automatiquement** par un trigger.
- **Les pronostics ne sont effacés que s'il ne reste au joueur AUCUNE adhésion** : un
  pronostic compte dans tous ses championnats à la fois (§6.4).

**Erreurs** : `401` · `404` « Tu ne fais pas partie de ce championnat. » · `422` · `503`

---

### 3.4 Grands Prix et cotes

#### `GET /grands-prix/{gp_id}/cotes` — **publique**

Aucun jeton requis.

**Réponse `200`**
```json
{
  "id": "uuid",
  "nom": "GP Pays-Bas",
  "date_course": "2026-08-23T13:00:00+00:00",
  "date_qualifications": "2026-08-22T13:00:00+00:00",
  "statut": "cotes_figees",
  "marches": [{
    "marche": "vainqueur",
    "libelle": "Vainqueur",
    "cotes": [
      { "pilote": "M.Verstappen", "points": 28, "id": "o701093319" }
    ]
  }]
}
```

| Champ | Note |
|---|---|
| `marche` | **Slug**, fabriqué à partir du libellé Unibet. C'est la clé technique |
| `libelle` | Le nom du marché **tel que le bookmaker l'écrit**. C'est ce qui s'affiche |
| `points` | **Déjà un nombre de points entier**, jamais une cote. Ne rien diviser (§6.1) |
| `id` | `id_outcome_unibet` — **la clé de toute la saisie**. C'est elle qu'on envoie en favori et en pronostic |

> **Le même pilote ne porte PAS le même `id` selon le marché.** Antonelli vaut
> `o701093319` au marché « Vainqueur » et `o701094802` au marché « Podium » du même GP.
> Toute logique d'exclusion croisée doit donc porter sur **le libellé du pilote**, jamais
> sur l'identifiant d'issue (§6.3).

**Erreurs** : `404` « Ce Grand Prix n'existe pas. » · `422` · `503`

#### `GET /scraper/cotes` — **publique**

Toutes les cotes en base, une liste d'objets de la forme ci-dessus, triés par
`date_course` croissante. Unibet n'expose que le GP suivant, la liste reste courte.

---

### 3.5 Favoris et pronostics

#### `POST /grands-prix/{gp_id}/favoris`

Jeton requis. **Bascule** : épingle la cote, ou la retire si elle l'était déjà.

**Corps** : `{ "id_outcome_unibet": "o701093319" }`
**Réponse `200`** : `{ "favori": true }` — l'état **après** la bascule.

C'est la base qui tranche (suppression, puis insertion si rien n'a été supprimé) : deux
appuis rapprochés ne peuvent pas retomber du même côté.

**Erreurs** : `401` · `404` « Ce Grand Prix n'existe pas. » ·
`422` « Cette cote n'existe pas pour ce Grand Prix (favori). » · `503`

#### `GET /grands-prix/{gp_id}/favoris`

Jeton requis. Les favoris de l'appelant pour ce GP, **dans l'ordre où il les a épinglés**.

**Réponse `200`**
```json
[{ "id_outcome_unibet": "o701093319", "marche": "vainqueur",
   "libelle": "Vainqueur", "pilote": "M.Verstappen", "points": 28 }]
```

**Les quatre derniers champs sont `nil` quand la cote a disparu du GP depuis l'épinglage.**
Le favori reste servi : le supprimer en douce ferait disparaître une ligne de l'écran sans
explication. **Les favoris sont strictement privés** (RLS).

**Erreurs** : `401` · `404` · `422` · `503`

#### `POST /grands-prix/{gp_id}/pronostics`

Jeton requis. **Remplace le jeu complet** de l'appelant pour ce GP, dans une seule
transaction : le pronostic précédent n'est effacé que si le nouveau s'écrit en entier.

**Corps**
```json
{
  "vainqueur": "o701093319",
  "podium": { "pilote_1": "o701094802", "pilote_2": "o701094803" },
  "bonus": ["o701095001", "o701095002", "o701095003"]
}
```

Toutes les valeurs sont des **`id_outcome_unibet`**, 1 à 64 caractères.

Contrôles appliqués, dans l'ordre :

| Règle | Message de refus |
|---|---|
| Pronostics ouverts | **`423`** « Les pronostics de ce Grand Prix sont fermés : la course est partie. » |
| `pilote_1 ≠ pilote_2` | « Choisis deux pilotes différents pour le podium. » |
| Bonus tous distincts | « Chaque pronostic bonus doit porter sur une cote différente. » |
| **3 bonus maximum** | « Trois pronostics bonus au maximum (N reçus). » |
| Chaque issue existe sur ce GP | « Cette cote n'existe pas pour ce Grand Prix (rôle). » |
| `vainqueur` vient du marché **`vainqueur`** | « Le pronostic « vainqueur » doit être choisi dans le marché « vainqueur » (reçu : « X »). » |
| Les deux du podium viennent du marché **`podium`** | idem, marché « podium » |
| **Les bonus sont parmi les FAVORIS** | « Les pronostics bonus se choisissent parmi tes favoris. À mettre en favori d'abord : *noms*. » |

> **Trois bonus est un maximum, pas un quota.** Zéro, un ou deux sont acceptés : le joueur
> peut enregistrer ses obligatoires et compléter plus tard, jusqu'à la fermeture. Le bouton
> de validation **reste actif** même avec une saisie incomplète (§7.1).

> **La fermeture est vérifiée deux fois, et ce n'est pas une redondance.** La route refuse
> en `423` avant de solliciter la base ; la fonction SQL revérifie au moment d'écrire.
> **C'est la vérification en base qui fait foi** — un `423` peut donc arriver alors que le
> client croyait le GP encore ouvert. L'écran doit le gérer proprement.

**Réponse `200`** — le jeu enregistré :
```json
[{
  "id": "uuid",
  "type": "podium",
  "outcome": "o701094802",
  "pilote": "AK.Antonelli",
  "marche": "podium",
  "libelle": "Podium",
  "points": 44,
  "points_gagnes": null,
  "podium": {
    "pilote_1": "o701094802", "pilote_2": "o701094803",
    "nom_1": "AK.Antonelli", "nom_2": "G.Russell", "points_2": 51
  }
}]
```

| Champ | Note |
|---|---|
| `type` | `vainqueur` · `podium` · `bonus` |
| `points` | Ce que le pronostic **peut** rapporter (cote figée) |
| `points_gagnes` | Ce qu'il **a** rapporté. **`nil` ≠ `0`** — voir §6.2 |
| `podium` | Présent uniquement sur `type: "podium"`. Le **potentiel total d'un podium est `points + points_2`** |

**Erreurs** : `401` · `404` · `422` · **`423`** · `503`

#### `GET /grands-prix/{gp_id}/pronostics/championnat/{championnat_id}`

Jeton requis **et membre**. L'appartenance est vérifiée **avant l'existence du GP**.

**Réponse `200`** — tous les membres, y compris **ceux sans pronostic** (liste vide) :
l'interface doit pouvoir montrer qui manque à l'appel, pas seulement qui a joué.

```json
[{
  "profil_id": "uuid",
  "pseudo": "MaxV33",
  "rejoint_le": "2026-08-13T18:23:31+00:00",
  "couleur1": "#800111",
  "couleur2": "#FFFFFF",
  "couleur_texte": null,
  "numero": 33,
  "livree_mode": "perso",
  "livree_ecurie": null,
  "avatar_url": null,
  "total_points": 187,
  "pronostics": [ /* PronosticServi, même forme que ci-dessus */ ]
}]
```

`total_points` est **`nil`** tant qu'aucun pronostic du membre n'est noté — jamais `0`.

**Erreurs** : `401` · `403` · `404` · `422` · `503`

---

### 3.6 Résultats

#### `GET /grands-prix/{gp_id}/resultats?championnat_id={uuid}` — **mixte**

**Sans `championnat_id`** : publique, aucun jeton. Le classement de la course seul.
**Avec `championnat_id`** : jeton **et** appartenance exigés.

> **Un en-tête `Authorization` présent mais INVALIDE rend `401`, même sans
> `championnat_id`.** Accepter en silence un jeton expiré servirait la partie publique à
> quelqu'un qui se croit connecté. Corollaire iOS : ne joindre le jeton que si on en a un
> valide, ou traiter le `401` comme une invitation à se reconnecter (§7.3).

**Réponse `200`**
```json
{
  "grand_prix": { "id": "uuid", "nom": "GP Pays-Bas",
                  "date_course": "2026-08-23T13:00:00+00:00", "statut": "termine" },
  "disponible": true,
  "recupere_le": "2026-08-23T15:12:04+00:00",
  "classement": [{
    "position": 1,
    "driver_number": 1,
    "pilote": "Max Verstappen",
    "equipe": "Red Bull Racing",
    "points_fia": 25,
    "nombre_de_tours": 72,
    "abandon": false,
    "non_partant": false,
    "disqualifie": false
  }],
  "membres": null
}
```

| Champ | Note |
|---|---|
| `disponible` | **`false` tant que le job n'a pas récupéré la course.** L'écran affiche alors « résultats en attente », **jamais un classement vide** — qui se lirait comme une course où personne n'aurait fini. Un `404` serait faux : le GP existe |
| `position` | **Nullable** — abandon non classé |
| `abandon` | Un pilote peut abandonner **et** rester classé : les deux champs sont indépendants |
| `points_fia` | **Points du championnat du monde** (25, 18, 15…), **jamais les points de l'app**. S'écrit « 25 pts » et **ne passe JAMAIS par le formateur de points** (§6.1) |
| `membres` | `nil` veut dire **« pas demandé »**, jamais « championnat vide ». Renseigné seulement avec `championnat_id` + appartenance |

**Erreurs** : `401` « Connecte-toi pour voir les pronostics de ce championnat. » (rendu
**avant** de dire quoi que ce soit du championnat) · `403` · `404` · `422` · `503`

---

### 3.7 Administration

Trois surfaces, **deux régimes de garde**. Seule la première concerne l'app iOS.

#### `POST /admin/action` — jeton + `is_admin` relu en base

**La seule route d'administration appelable depuis une application cliente.** Le garde
enchaîne la validation du jeton puis **relit `profils.is_admin` en base** avec la clé de
service : le jeton dit *qui* appelle, et rien d'autre.

**Corps**
```json
{ "action": "scraper",   "figer": true }
{ "action": "resultats", "gp_id": "uuid", "forcer": false }
```

`action` est un `Literal` : toute autre valeur est refusée par la validation **avant**
d'entrer dans le handler.

**Réponse `200`**
```json
{ "action": "scraper", "statut": "lance", "figera": true, "rapport": null }
{ "action": "resultats", "statut": "traite", "figera": true,
  "rapport": { "gp": "GP Pays-Bas", "gp_id": "uuid", "statut": "termine",
               "deja_recupere": false, "pronostics_a_noter": 42, "reinitialises": 0,
               "attribues": 38, "restants": 4, "en_attente": ["…"], "erreur": null } }
```

> **`statut` est le seul champ qui compte à l'écran.** `lance` = **accepté**, le travail
> part en arrière-plan et son compte rendu va dans les logs Railway. `traite` = **fait**.
> Annoncer « cotes mises à jour » sur un `lance` serait une promesse que la réponse ne
> porte pas. Le statut HTTP est `200` dans les deux cas, jamais `202` — une route dont une
> action sur deux est synchrone mentirait une fois sur deux.

**`?forcer=true` sur l'action `resultats` est la SEULE écriture du système qui efface un
point acquis.** Elle rend les `points_gagnes` du GP à `NULL` avant de recalculer. À
n'exposer que derrière une confirmation explicite (§7.1 : sur place, jamais en boîte de
dialogue).

**Erreurs** : `401` · `403` « Cette action est réservée aux administrateurs. » (ligne
absente, colonne absente, base non migrée : **le doute refuse, il n'accorde jamais**) ·
`422` « Cette action demande l'identifiant d'un Grand Prix. » · `425` (résultats non
publiés) · `404` · `503` (Supabase injoignable — **jamais `403`** : « tu n'es pas
administrateur » serait faux)

#### Les trois routes au secret — `curl` uniquement, **jamais depuis l'app**

Fermées par l'en-tête `X-Admin-Secret`, dont la valeur **ne quitte jamais Railway**. Elles
sont documentées ici pour que personne ne les câble par erreur dans le client iOS.

| Route | Comportement |
|---|---|
| `POST /scraper/declencher?figer=true` | **`202`, asynchrone.** `{"statut":"lance","figera":true}` |
| `POST /jobs/resultats/{gp_id}?forcer=false` | **Synchrone**, rend le `RapportJob` complet. `425` si non publiés |
| `POST /jobs/resultats/{gp_id}/test` | **Banc d'essai — n'écrit RIEN.** Rejoue le calcul sur des résultats fictifs |

> **iOS (0.31.0).** Un seul bouton, « Scraper les cotes », qui envoie
> `{"action":"scraper","figer":false}` (`Services/Administration.swift`) : sans écran de
> confirmation, il n'écrit que ce qui se rattrape — le figeage reste au job du samedi.
> L'interrupteur « Mode admin actif » (`AuthViewModel.modeAdminActif`, état de session) vaut
> **prévisualisation** : `modePrevisualisation = estAdmin && modeAdminActif` descend par
> l'environnement et lève la seule condition `cotesArretees` du widget « Pronostiquer »
> de l'accueil, avec la pastille « Prévisualisation » sur les cotes et la saisie.
> Écart assumé avec le web, qui a deux interrupteurs : ici un seul, faute d'autres outils à
> masquer.

> **Ne jamais embarquer `ADMIN_SECRET` dans un binaire iOS.** C'est exactement la faute
> corrigée à la version `0.64.0` côté web, où Vite inlinait le secret dans le bundle
> public. Un binaire iOS se décompile aussi bien qu'un bundle JavaScript se lit.

---

### 3.8 Le dépôt des photos — Storage direct, URL par l'API

**Le fichier n'atteint jamais Railway.** Il n'existe aucune route d'upload dans le backend.
Le dépôt se fait **directement dans Supabase Storage** (les politiques `storage.objects`
décrivent exactement le cas), et seule l'**URL** est ensuite enregistrée par l'API.

```swift
// 1. Réduire l'image AVANT l'envoi : recadrage carré, 800 px de côté, JPEG qualité 0,85.
//    Une photo d'iPhone de 4 Mo pèse alors moins de 200 Ko.
let donnees = imageReduite.jpegData(compressionQuality: 0.85)!

// 2. Déposer. Le chemin est STABLE, `upsert: true` écrase la précédente.
let chemin = "\(profilId)/avatar.jpg"
try await supabase.storage.from("avatars").upload(
    chemin, data: donnees,
    options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: true)
)

// 3. URL publique + péremptoire de cache — INDISPENSABLE : le chemin étant stable,
//    sans lui le CDN continuerait de servir l'ancienne image et rien en base ne changerait.
let publique = try supabase.storage.from("avatars").getPublicURL(path: chemin)
let url = "\(publique.absoluteString)?v=\(Int(Date().timeIntervalSince1970 * 1000))"

// 4. Enregistrer l'URL par l'API — c'est LÀ que le backend vérifie qu'elle est bien nôtre.
// PATCH /profils/moi  { "avatar_url": url }
```

**Les deux compartiments**

| Compartiment | Dossier | Nom de base | Enregistrée par |
|---|---|---|---|
| `avatars` | `{profil_id}` | `avatar` | `PATCH /profils/moi` → `avatar_url` |
| `championnats` | `{championnat_id}` | `photo` | `PATCH /championnats/{id}` → `photo_url` |

**Les cinq conditions de `url_de_photo_valide`** (backend) — une URL qui en manque une seule
est refusée en `422` :

1. l'URL commence par celle du **projet Supabase configuré** ;
2. elle désigne le **bon compartiment** ;
3. elle porte un **chemin** après le compartiment, ≤ **512 caractères**, sans `..` ;
4. le **premier segment du chemin est le propriétaire** — l'identifiant du jeton pour un
   avatar, celui du championnat pour une photo de championnat (comparaison insensible à la
   casse) ;
5. le reste est un **nom simple portant une extension d'image** :
   `^[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$`, éventuellement suivi du seul paramètre
   `?v={chiffres}`. **Pas de sous-dossier, pas de `%`, pas de `.svg`.**

**Ce que le compartiment garde lui-même**, et qu'il est donc inutile de reproduire côté app :
type MIME (`image/jpeg`, `image/png`, `image/webp` — refus `415`), taille (**2 Mo**), droit
d'écrire dans le dossier (RLS : premier segment = `auth.uid()`), type servi à l'affichage.

Ce que l'app vérifie avant l'envoi ne garde **rien** : c'est un refus immédiat pour ne pas
faire monter un fichier voué au rejet sur un réseau mobile.

**Ménage** : le chemin porte l'extension. Changer de format écrit un objet **à côté** de
l'ancien. Après un dépôt réussi, supprimer les mêmes chemins sous les autres extensions
(`jpg`, `jpeg`, `png`, `webp`), **jamais avant** : effacer d'abord laisserait le membre sans
photo si l'envoi échouait ensuite. L'échec de ce ménage s'ignore.

---

### 3.9 Ce qui NE passe PAS par FastAPI

**C'est la décision d'architecture la plus structurante du projet, et elle s'applique
telle quelle à l'app iOS.** Le client parle à Supabase par **deux chemins délibérément
différents** :

- **(A) par FastAPI** — toute écriture, et toute lecture qui **agrège les données
  d'autrui** : classement, statistiques, calendrier d'un championnat, pronostics des
  membres. Ces fonctions SQL sont `security definer` et réservées à `service_role` ;
  l'autorisation est portée par la route.
- **(B) en direct à Supabase, sous RLS** — les lectures qu'une politique décrit déjà
  exactement.

> **Le critère est la politique RLS, pas la commodité.** Si la RLS décrit le cas, on lit en
> direct — passer par Railway n'ajouterait qu'un **cold start**. C'est pour cette raison
> que l'accueil doit lire en direct son bloc principal : c'est le premier écran de l'app,
> et il ne doit pas attendre le réveil de Railway.

Les lectures directes à implémenter avec `supabase-swift`, telles que le client web les
fait :

| Ce qu'on lit | Requête PostgREST |
|---|---|
| **Le prochain GP** (accueil) | `grands_prix` · `in("statut", ["a_venir","cotes_figees"])` · `order("date_course", ascending: true, nullsFirst: false)` · `limit(1)` |
| **Le dernier GP couru** (repli d'intersaison) | `grands_prix` · `select("…, resultats_gp!inner(gp_id)")` · `order("date_course", ascending: false, nullsFirst: false)` · `limit(1)` |
| **GP restants** (bandeau) | `grands_prix` · `head` + `count: .exact` · mêmes filtres que le prochain GP, plus `or("date_course.is.null,date_course.gte.{now}")` |
| **Mes pronostics d'un GP** | `pronostics` · `select("id, type, id_outcome_unibet, points_gagnes, pronostic_podium(pilote_1, pilote_2)")` · `eq("gp_id",…)` · `eq("profil_id",…)` |
| **Les GP que j'ai pronostiqués** | `pronostics` · `select("gp_id")` · `eq("profil_id",…)` |
| **Mon pseudo + ma photo** | `profils` · `select("pseudo, avatar_url")` · `eq("id",…)` |
| **Mon drapeau `is_admin`** | `profils` · `select("is_admin")` · `eq("id",…)` |
| **Un championnat + ses membres** | `championnats` puis `membres_championnat` puis `profils` — **trois requêtes**, pas une jointure : `membres_championnat` référence `auth.users`, pas `public.profils`, PostgREST n'a donc aucune relation à suivre |
| **Les numéros déjà pris** | `membres_championnat` (les miens) → `membres_championnat` (leurs membres) → `profils(id, pseudo, numero)` avec `numero not null` |
| **Une saison entière de pronostics d'un membre** | `pronostics` → `grands_prix` → `cotes`, en une passe |

**`nullsFirst: false` n'est pas cosmétique** : sans lui, PostgreSQL place les `NULL` en tête
et un GP dont Unibet n'a pas encore annoncé l'horaire passerait **devant la course de
dimanche**.

Quatre sens du doute, tous différents, tous délibérés :

| Lecture | En cas d'échec | Pourquoi |
|---|---|---|
| Prochain GP | erreur affichée | c'est le contenu principal de l'écran |
| GP déjà pronostiqués | **succès, ensemble vide** | le bouton retombe sur « Pronostiquer », qui reste vrai |
| Pseudo / photo | valeur périmée acceptable | un pseudo périmé vaut mieux que pas de pseudo |
| **`is_admin`** | **`false`, toujours** | une section d'administration affichée à tort ne vaut rien |

> **`is_admin` ne se lit JAMAIS depuis un cache ni depuis le jeton.** Le jeton porte une
> copie figée à l'inscription : une révocation ne prendrait effet qu'au prochain
> renouvellement de session. Ce drapeau décide d'un **affichage**, jamais d'un droit —
> c'est `POST /admin/action` qui autorise, et les deux peuvent diverger sans dommage.

---

## 4. Design system pour SwiftUI

> **Portée.** La **palette et la typographie** ne se négocient pas. Rayons, espacements,
> ombres et mouvement sont des **valeurs par défaut** issues du design system web, à
> réinterpréter selon les conventions natives d'iOS quand elles s'y opposent.

### 4.1 L'extension `Color(hex:)`

```swift
extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255,
                  opacity: 1)
    }
}
```

### 4.2 Palette de base — les huit intouchables

```swift
enum Palette {
    static let fond           = Color(hex: "#F5F0EB")  // fond de l'app
    static let primaire       = Color(hex: "#800111")  // rouge profond
    static let primaireFonce  = Color(hex: "#5A000C")
    static let secondaire     = Color(hex: "#543925")  // marron
    static let accent         = Color(hex: "#E8A020")  // amber
    static let texte          = Color(hex: "#1A1A1A")
    static let texteDoux      = Color(hex: "#999999")
    static let surface        = Color(hex: "#FFFFFF")  // cartes
    static let squelette      = Color(hex: "#E8E0D8")  // silhouettes de chargement UNIQUEMENT
}
```

### 4.3 Palette élargie — quatre teintes, périmètre borné

```swift
static let vertSauge    = Color(hex: "#4A7C59")
static let bleuArdoise  = Color(hex: "#2C4A6E")
static let terracotta   = Color(hex: "#C4622D")
static let violet       = Color(hex: "#5C3D7A")
```

> **Elles ne peignent QUE des aplats de bloc** — en-tête de marché, bloc de pronostic — et
> le texte posé dessus. **Jamais un fond d'écran, jamais un texte sur le beige, jamais une
> bordure.** Les huit couleurs de base gardent tous leurs rôles.

#### `vertSauge` en encre — extension bornée au blanc

`CalendrierView` lui ajoute un second rôle, et un seul : **l'encre de ce qui est
consultable et derrière nous**, la pastille « Terminé » et la bande « Voir les résultats ».
Les deux sont posées **sur du blanc**, où elle tient **4,86:1** — le plus serré des quatre
états de Grand Prix, et c'est lui qui a fixé l'opacité de la bande.

**Sur le beige de l'app, elle tombe à 4,34:1** et ne passe plus le plancher d'un texte
ordinaire : l'interdiction d'écrire sur le beige tient, elle est mesurée, pas de principe.

#### `accent` en aplat — une seule encre l'accompagne

La pastille « Pronos ouverts » est la seule des quatre à garder un fond coloré sur un
drapeau, parce qu'**une encre ambre ne tient pas sur du blanc** (2,2:1). L'inverse, lui,
passe : `texte` sur `accent` vaut **7,86:1**. C'est la seule encre que cet aplat accepte —
du blanc dessus retomberait à 2,2:1.

#### Les encres de second rang sur un aplat — trois, et chacune a son aplat

`encreSecondaire` (blanc à 70 %) est **réglée sur `primaire`**, le plus sombre des aplats.
Elle ne se transpose pas telle quelle sur les deux autres familles, et c'est mesuré :

| Aplat | Surface la plus claire du bloc | Encre | Rapport |
|---|---|---|---|
| `primaire` `#800111` | champ à 15 % de blanc → `#932734` | `encreSecondaire` (70 %) | **4,69:1** |
| `bleuArdoise` `#2C4A6E` | champ à 15 % de blanc → `#4C6584` | `encreSecondaire` (70 %) | 3,86:1 ✗ |
| `bleuArdoise` | idem | **`encreSecondaireClaire` (85 %)** | **4,82:1** |
| `accent` `#E8A020` | l'aplat lui-même | `texte` à 70 % → `#58421C` | 4,28:1 ✗ |
| `accent` | idem | **`encreSecondaireAmbre` (`texte` à 75 %)** | **4,84:1** |

```swift
static let encreSecondaire       = Color.white.opacity(0.70)   // sur primaire
static let encreSecondaireClaire = Color.white.opacity(0.85)   // sur bleuArdoise
static let encreSecondaireAmbre  = Color.texte.opacity(0.75)   // sur accent
```

> **Le choix ne revient jamais à l'écran.** C'est le marché (`MarcheCote`) qui porte son
> aplat ET son encre douce : un écran qui les choisirait séparément finirait par poser un
> blanc à 70 % sur le bleu. Une question, un propriétaire.

**Sur un champ REMPLI (22 % de blanc), l'encre douce ne suffit plus** — 3,84:1 sur le bleu.
Les points y passent en **blanc plein** (4,61:1), et ce sont la taille et la graisse qui les
distinguent du nom, pas l'opacité. Le chevron, lui, est un élément graphique (plancher 3:1)
et garde l'encre douce.

### 4.4 Les six teintes de championnat — palette Pantone sombre

```swift
static let azurite       = Color(hex: "#1D2941")  // Azurite
static let mure          = Color(hex: "#2A1F21")  // Blackberry Syrup
static let aubergine     = Color(hex: "#301729")  // Aubergine Gleam
static let terreau       = Color(hex: "#54392D")  // Potting Soil
static let tomateSechee  = Color(hex: "#752329")  // Sun-Dried Tomato
static let minuit        = Color(hex: "#16151D")  // Midnight Sky
```

**Elles ne peignent QUE une carte de championnat et l'en-tête de son écran.** Six teintes
couvrent six championnats distincts ; au-delà, le cycle recommence. **La teinte se tire
d'une empreinte de l'identifiant du championnat, jamais du rang dans une liste** — sinon la
couleur d'un championnat changerait quand un autre est rejoint ou quitté.

**Le texte reste blanc sur les six, et c'est mesuré** : de 10,35:1 (tomate séchée) à
18,12:1 (minuit). L'encre secondaire à 70 % ne descend jamais sous 4,97:1.

### 4.5 Typographie

**Helvetica Neue partout. Graisses 400 et 500 uniquement.**

```swift
extension Font {
    static let titre    = Font.custom("HelveticaNeue-Medium",  size: 28)
    static let titreLg  = Font.custom("HelveticaNeue-Medium",  size: 30)
    static let score    = Font.custom("HelveticaNeue-Medium",  size: 32)
    static let scoreLg  = Font.custom("HelveticaNeue-Medium",  size: 44)
    static let corps    = Font.custom("HelveticaNeue",         size: 15)
    static let corpsSm  = Font.custom("HelveticaNeue",         size: 14)
    static let label    = Font.custom("HelveticaNeue-Medium",  size: 11)
    static let labelSm  = Font.custom("HelveticaNeue-Medium",  size: 10)
}
```

**Le crénage (`.tracking`) est spécifique à la taille** — et il est **positif** sur les
petits labels :

| Style | Taille | Graisse | `.tracking` | Note |
|---|---|---|---|---|
| `titre` | 28 | 500 | `-0.02 × 28 = -0.56` | |
| `titreLg` | 30 | 500 | `-0.60` | |
| `score` | 32 | 500 | `-0.025 × 32 = -0.80` | |
| `scoreLg` | 44 | 500 | `-0.03 × 44 = -1.32` | |
| `corps` | 15 | 400 | `0` | |
| `corpsSm` | 14 | 400 | `0` | |
| `label` | 11 | 500 | **`+0.7`** | `.textCase(.uppercase)` |
| `labelSm` | 10 | 500 | **`+0.7`** | `.textCase(.uppercase)` |

> **Les grands chiffres ont plus besoin du crénage négatif que les titres** : un chiffre n'a
> ni jambage ni hampe, donc rien qui vienne remplir l'espace.

**La graisse 700 (`HelveticaNeue-Bold`) est réservée aux numéros de voiture**, plus quatre
écarts explicites, chacun limité à un chiffre : tuiles du compte à rebours (30 px au
récapitulatif, 48 px à la saisie), quantième d'une carte de calendrier (64 px), points d'un
widget de cote (18 px). Deux tailles hors échelle : **26 px** (nom du GP sur le bloc
d'accueil) et **64 px**.

### 4.6 Formes et espacements

```swift
enum Rayon {
    static let bloc     : CGFloat = 24  // blocs principaux
    static let carte    : CGFloat = 20
    static let carteSm  : CGFloat = 18
    static let widget   : CGFloat = 16  // widgets de cote
    static let champ    : CGFloat = 14  // champs, petits éléments
}
```

Espacement entre blocs : **12 pt**. Padding intérieur : **16 à 20 pt**.
Changement de sujet dans un écran : **24 pt** au-dessus du titre de section.

> **Sur iOS, préférer `RoundedRectangle(cornerRadius:style: .continuous)`** — le squircle
> d'Apple, qui est exactement l'intention derrière ces rayons.

**Les bordures fines sont proscrites.** Deux exceptions : l'encadré « mode d'emploi » du
tableau des cotes (bordure ambre sur `#FDF3E0`), et le **filet de 4 pt** d'une ligne de
classement — qui n'est pas une bordure au sens de la règle : c'est un aplat posé *à
l'intérieur*, pas un trait qui cerne le bloc. Le même filet sépare deux sections d'un écran.
**Jamais une règle horizontale.**

### 4.7 Élévation

**Un seul principe : plus une surface est grande, plus elle est épaisse.** Les deux premiers
niveaux superposent **deux couches** — une ombre de contact serrée qui pose l'objet, une
ombre ambiante large qui l'éloigne du fond. **Une seule couche donne l'un ou l'autre, jamais
les deux.**

**La teinte est le marron `secondaire` (`#543925`) en très faible opacité, jamais un noir** :
une ombre noire sur un fond beige tire vers le gris et salit la couleur.

Les valeurs exactes, transposées de `frontend/src/index.css`. **Le rayon SwiftUI vaut la
moitié du flou CSS** (`shadowRadius = blur / 2`) :

| Jeton | CSS | SwiftUI |
|---|---|---|
| `shadow-carte` | `0 1px 2px / 4 %` + `0 4px 12px / 6 %` | `radius: 1, y: 1` (4 %) + `radius: 6, y: 4` (6 %) |
| `shadow-bloc` | `0 2px 4px / 5 %` + `0 10px 28px / 9 %` | `radius: 2, y: 2` (5 %) + `radius: 14, y: 10` (9 %) |
| `shadow-flottant` | `0 -1px 24px / 10 %` | `radius: 12, y: -1` (10 %) — **une seule couche, et vers le HAUT** |
| `shadow-aplat` | `0 2px 6px / 10 %` + `0 14px 34px / 16 %` | `radius: 3, y: 2` (10 %) + `radius: 17, y: 14` (16 %) |

```swift
extension View {
    func ombreCarte() -> some View {
        self.shadow(color: Palette.secondaire.opacity(0.04), radius: 1,  y: 1)
            .shadow(color: Palette.secondaire.opacity(0.06), radius: 6,  y: 4)
    }
    func ombreBloc() -> some View {
        self.shadow(color: Palette.secondaire.opacity(0.05), radius: 2,  y: 2)
            .shadow(color: Palette.secondaire.opacity(0.09), radius: 14, y: 10)
    }
    /// Barres de navigation et d'action collées : l'ombre remonte, elle ne descend pas.
    func ombreFlottant() -> some View {
        self.shadow(color: Palette.secondaire.opacity(0.10), radius: 12, y: -1)
    }
    /// Pour les APLATS DE COULEUR seulement — voir ci-dessous.
    func ombreAplat() -> some View {
        self.shadow(color: Palette.secondaire.opacity(0.10), radius: 3,  y: 2)
            .shadow(color: Palette.secondaire.opacity(0.16), radius: 17, y: 14)
    }
}
```

> **`shadow-aplat` existe parce que les trois autres sont réglées pour du BLANC.** Sous un
> bloc rouge, violet ou sombre, un marron clair ne se voit plus : celle-ci est plus profonde
> et plus contrastée. Plus la surface est dense, plus elle doit peser sur le fond.

**Règle d'attribution** : rayon `bloc` → `ombreBloc`, rayon `carte` → `ombreCarte`,
**rayon `champ` → aucune ombre** (ce sont les surfaces posées *à l'intérieur* d'un bloc, qui
ne cassent jamais leur plan), aplat de couleur → `ombreAplat`.

**`lueur-haute`** pose en plus un galbe de lumière très doux sur les aplats de couleur — du
blanc à très faible opacité, **aucune couleur nouvelle**.

### 4.8 Contraste — le calcul, jamais le goût

**C'est la règle de méthode la plus importante du design system.**

| Cas | Plancher |
|---|---|
| Texte ordinaire | **4,5:1** |
| Grand texte (≥ 24 pt, ou gras ≥ 19 pt) | **3:1** |
| Élément graphique porteur de sens | **3:1** (WCAG 1.4.11) |

**Les écrans ne choisissent jamais leur encre eux-mêmes.** Porter en Swift l'équivalent des
quatre helpers du web :

```swift
/// Luminance relative WCAG.
func luminance(_ c: Color) -> Double { /* 0.2126 R + 0.7152 G + 0.0722 B, canaux linéarisés */ }

/// Ratio de contraste entre deux couleurs.
func contraste(_ a: Color, _ b: Color) -> Double { /* (L1+0.05)/(L2+0.05) */ }

/// Blanc tant qu'il tient 3:1 sur cet aplat, encre foncée en dessous.
func encreSurAplat(_ aplat: Color) -> Color {
    contraste(.white, aplat) >= 3 ? .white : Palette.texte
}

/// La couleur si elle tient 4,5:1 sur blanc, sinon l'encre par défaut.
func encreSurBlanc(_ c: Color) -> Color {
    contraste(c, .white) >= 4.5 ? c : Palette.texte
}
```

Deux pièges déjà rencontrés en production, à ne pas refaire :

> **`encreSur` (seuil de luminance) et `encreSurAplat` (seuil de contraste) ne sont PAS
> interchangeables, et c'est l'amber qui les départage.** L'amber a une luminance de 0,424,
> juste sous le seuil de 0,45 : un test par luminance rend du **blanc**, à **2,2:1**. Un
> test par contraste bascule sur l'encre foncée. **Devant « quelle encre sur cet aplat ? »,
> c'est toujours le test par CONTRASTE.** Le test par luminance ne reste juste que pour les
> deux textes peints sur une carrosserie de voiture, qui ne rencontrent jamais l'amber.

> **L'amber est le cas d'école.** Sur `#E8A020`, le blanc tombe à **2,2:1** quand `#1A1A1A`
> monte à **7,9:1**. Toute surface amber prend donc l'encre foncée, sans exception.
> **Corollaire : l'amber n'existe QUE comme aplat, jamais comme encre** — en texte sur
> blanc il ne vaut que 2,2:1.

> **`texteDoux` (`#999999`) sur le beige ne vaut que 2,0:1.** Il convient à côté d'un numéro
> de version que personne ne lit, **pas à une phrase qu'on vient lire**. Le marron
> `secondaire` la porte à 9,4:1. Corrigé deux fois déjà côté web.

**Sur un fond changeant, la hiérarchie passe par la taille et la graisse, jamais par
l'opacité** : une fois la bande la plus claire d'un drapeau ramenée au gris moyen, aucune
opacité intermédiaire n'atteint 3:1.

### 4.9 Matériaux

Le web pose un chrome blanc à 72 % avec `blur(24px) saturate(180%)` sur la barre de
navigation et la barre d'action. **L'équivalent natif est `.ultraThinMaterial` /
`.regularMaterial`**, qui fait le même travail mieux et gratuitement.

> **Le matériau d'un en-tête n'apparaît qu'une fois du contenu passé dessous** — c'est le
> *scroll edge effect*, qu'iOS gère nativement via `.toolbarBackground(.visible, for:)`
> piloté par la position de défilement. Une barre translucide posée sur du vide se lit
> comme un bandeau.

Deux textures du web, à transposer ou à abandonner selon le rendu :

- **`--grain-fond`** : bruit gris à **4 %** en image de fond, tuile de 160 px. Sur iOS, une
  image tuilée en `Image(…).resizable(resizingMode: .tile)` avec `.opacity(0.04)`.
- **`--motif-damier`** : la vague de `assets/06.svg`, à **15 %** sur les aplats colorés,
  **7,5 %** sur du blanc (où 15 % ne se lit plus comme une texture mais comme un gris sale),
  **11 %** sur le bandeau de la vue piste. Le damier est **gris `#616160`**, jamais blanc :
  c'est le gris qui contraste le mieux — sous lui l'encre blanche ne descend jamais sous
  9,99:1 sur les six teintes de championnat, contre 7,56:1 sous un damier blanc.

**Accessibilité** : respecter `accessibilityReduceTransparency` (matériaux opaques) et
`colorSchemeContrast == .increased` (grain supprimé, voiles approfondis).

### 4.10 Mouvement

| Rôle | Courbe web | Équivalent SwiftUI |
|---|---|---|
| Entrées, sorties | `cubic-bezier(0.22, 1, 0.36, 1)` | `.timingCurve(0.22, 1, 0.36, 1, duration: …)` |
| **Déplacements** | `cubic-bezier(0.77, 0, 0.175, 1)` | `.timingCurve(0.77, 0, 0.175, 1, duration: …)` |
| Relâchement d'un appui | `cubic-bezier(0.34, 1.36, 0.64, 1)` | `.spring(response: 0.3, dampingFraction: 0.6)` |

| Durée | Emploi |
|---|---|
| **180 ms** | échange d'icône (étoile de favori, icônes de nav, interrupteur) |
| **240 / 170 ms** | accordéon (ouverture / fermeture — l'ouverture est plus lente) |
| **260 ms** | tuiles du compte à rebours |
| **200 ms** | passage d'écran |

**Les valeurs imposées**, qui valent aussi en natif :

- jamais `scale(0)` — une chose doit avoir une silhouette avant d'être remplie ;
- jamais d'`ease-in` sur une interface ;
- **sous les 300 ms** ;
- le repli `accessibilityReduceMotion` livré **avec** l'animation, jamais après.

> **Le retour d'appui a DEUX courbes.** L'enfoncement est immédiat (100 ms, `ease-out`) —
> c'est la réponse au doigt. Le **relâchement** remonte sur le ressort et dépasse
> légèrement. Une courbe unique donne l'un ou l'autre, jamais les deux.

> **Deux amplitudes** : `0.97` pour les boutons, `0.985` pour les grandes surfaces — 3 % sur
> une carte pleine largeur déplacent une dizaine de points, et l'appui devient une secousse.

> **Le ressort ne s'emploie QUE là où un geste a précédé le mouvement**, jamais sur une
> apparition automatique, où le dépassement se lirait comme une erreur.

**Mouvement réduit ≠ moins de sens.** Sous `reduceMotion`, ce qui **informe** reste : le
chiffre entrant d'une tuile est montré sans voyager, la piste d'un interrupteur garde sa
transition de couleur, la jauge d'une carte reste à sa bonne longueur.

---

## 5. Assets

### 5.1 Le principe, et ce qu'il implique pour iOS

**Aucune planche SVG n'est servie en production côté web.** Tout est extrait **par script**
dans un composant React et part inline avec le bundle. Les sources vivent dans `assets/`.

**iOS 16+ rend nativement le SVG** via `Image(…)` sur un asset vectoriel importé dans un
*Asset Catalog* (« Preserve Vector Data »), ou via `SVGKit`/une `WKWebView` pour les cas
dynamiques. Deux familles à distinguer, et le critère est unique : **un dessin dont les
couleurs changent à l'exécution ne peut pas être un asset statique.**

### 5.2 Les planches et leur destin en SwiftUI

| Planche source | Usage | Traitement iOS |
|---|---|---|
| `logo-05.svg` | Logo Greed F1 (icône carrée + bandeau du nom) | **Asset statique** |
| `logo.svg` | Icônes « Créer » (trophée), « Rejoindre » (deux silhouettes) | **Asset statique** |
| `logo-02.svg` | Les 4 icônes d'onglet : Accueil, Championnats, Calendrier, Profil | **Asset statique** — ou, mieux, `Image(systemName:)` si l'équivalent SF Symbol convient |
| `logoV2.svg` | L'étoile (2ᵉ des 4 dessins de la planche) | **Asset statique** |
| `traces.svg` + `calendrier.svg` | **12 tracés de circuits, en TRAIT** | **À recréer en `Path`/`Shape`** — voir §5.4 |
| `gp-cards.svg` | 2 silhouettes **pleines** (Monza, Spa) | Asset statique. **Plus monté nulle part** côté web |
| `flags.svg` | 6 drapeaux de pays hôtes, dessinés | Asset statique (mais voir §5.5) |
| `voitures_perso.svg` | **La voiture personnalisable** | **À recréer en SwiftUI** — §5.3 |
| `voitures_ecuries.svg` + `VOITUREs_am.svg` | **Les 11 livrées d'écurie** | Assets statiques (couleurs figées) |
| `matti.svg` | 9 des 11 pastilles carrées d'écurie | Asset statique |
| `matt.svg` | Pastilles Racing Bulls et Red Bull | Asset statique |
| `06.svg` | La vague du **motif damier** | Image tuilée, opacité variable (§4.9) |
| `vue_piste.svg` | **Le fond de la vue piste** | **À recréer** — §5.6 |
| `voiture.svg` | Ancien dessin, **remplacé** | Ne pas utiliser |

### 5.3 La voiture personnalisable — le seul dessin vraiment dynamique

`voitures_perso.svg` empile quatre voitures ; **seule la première est utilisée**. Elle est
peinte par **son propre couple de classes** : `cls-6` (coque) et `cls-14` (ailerons).
*`cls-2`, souvent cité par erreur, appartient à la quatrième et n'existe pas dans la
première.*

Quatre règles à tenir en SwiftUI :

1. **Les pièces mécaniques gardent leurs gris d'origine** — pneus, suspensions, fond plat,
   casque. Les repeindre ferait perdre la lecture de l'objet : **une voiture monochrome n'a
   plus de roues.**
2. **Chaque texte prend l'encre qui contraste avec l'aplat sous lui.** La planche écrit ses
   deux textes en blanc, ce qui rend le pseudo illisible sur les ailerons clairs. Le numéro
   est sur la coque (`couleur1`), le pseudo sur l'aileron arrière (`couleur2`) : **deux
   aplats différents, donc potentiellement deux encres différentes** — sauf si le membre a
   choisi une `couleur_texte`, qui peint alors **les deux ensemble**.
3. **Le numéro se lit du DESSUS, pas de l'avant.** La planche l'écrit sous `rotate(180)` —
   la convention d'un vrai museau de F1, qui se lit depuis la voiture qu'on double. **Toutes
   les vues de l'app sont des vues de dessus** : sans correction, le numéro sort tête-bêche.
   Retirer la rotation ne suffit pas, elle renverse aussi la position des glyphes autour de
   leur ligne de base : celle-ci doit descendre d'exactement une **hauteur de capitale
   (0,717 em)**. Calculé, jamais relevé à l'œil.
4. **Le texte est centré (`text-anchor: middle`) et la taille du pseudo suit sa longueur.**
   Le calage manuel de la planche décentrait un numéro à deux chiffres.

**Les onze livrées ont toutes la même boîte (141,11 × 288,09)** : elles se substituent à la
voiture personnalisée sans qu'aucune valeur de mise en page ne bouge.

**Les onze slugs** (`frontend/src/lib/livrees.js`, ordre de la planche, de haut en bas) :

```
red-bull · ferrari · mercedes · alpine · aston-martin · audi
mclaren · racing-bulls · williams · haas · cadillac
```

> **Un slug inconnu n'est PAS une panne** : la voiture retombe sur le mode personnalisé, ce
> qui se voit à l'écran au lieu de planter. **À mettre à jour à chaque saison.**

**Un seul endroit décide de ce que porte une voiture** (l'équivalent de `livreeDuMembre`) :
`livree_mode == "ecurie"` **et** `livree_ecurie` connue ⇒ la livrée ; sinon les deux
couleurs personnalisées. Les quatre surfaces qui affichent une voiture y passent.

### 5.4 Les tracés de circuits — deux modules à ne pas confondre

**Douze circuits en TRAIT** (`fill: none`, `stroke`) : un remplissage refermerait chaque
circuit en tache noire. En SwiftUI : `Path` + `.stroke()`, jamais `.fill()`.

Quatre points :

- **L'épaisseur du trait est en points d'écran, pas en unités du dessin.** C'est ce que fait
  `vector-effect="non-scaling-stroke"` en SVG ; en SwiftUI, tracer le `Path` dans son espace
  puis appliquer `.stroke(lineWidth:)` **après** la mise à l'échelle. Sans cela, le trait
  sortirait deux fois plus épais sur Zandvoort que sur Bakou.
- **Le rapport de forme est porté par le dessin** : l'appelant ne fixe **qu'une** dimension.
- **Un circuit en plusieurs traits garde ses sous-tracés dans un seul chemin** (Sakhir en
  compte quatre).
- **Un tracé absent est un cas NORMAL** : ne rien rendre, jamais un motif de repli qui
  laisserait croire que ce GP se court sur cette forme.

### 5.5 Les drapeaux — trois systèmes, et c'est assumé

1. **Cinq drapeaux en dégradé linéaire** (bandes franches) — le CSS le dit parfaitement ;
   en SwiftUI, `LinearGradient` avec des `stops` francs, ou un simple `HStack`/`VStack` de
   rectangles.
2. **Six drapeaux dessinés** dans `flags.svg` (pays hôtes) + **un septième calculé**, le
   Royaume-Uni, dont la géométrie est **spécifiée** (champ 1:2, croix de Saint-Georges au
   1/5 de la hauteur, liseré blanc au 1/15, sautoir blanc de 6 et sautoir rouge
   contre-changé de 4 dans le système 60 × 30).
3. **Seize drapeaux de pilotes** importés de `country-flag-icons`, indexés par code
   **ISO 3166-1 alpha-2**. C'est la grille 2026 qui en demande seize : sept pays (Australie,
   Nouvelle-Zélande, Brésil, Mexique, Canada, Thaïlande, Argentine) n'ont aucune description
   qu'un dégradé sache poser sans l'approximer. **Sur iOS, la voie la plus simple est un
   Asset Catalog de seize PDF/SVG vectoriels**, ou un paquet équivalent.

Trois règles de rendu, toutes issues de bugs réels :

- **Étirer, ne pas recadrer.** Une rangée de classement fait 5,2:1, un drapeau 1,5:1 : un
  recadrage type `.aspectRatio(contentMode: .fill)` + `.clipped()` garde la bande centrale
  et **l'Allemagne ressort rouge uni**. Utiliser `.resizable()` **sans** `aspectRatio`
  (l'équivalent de `preserveAspectRatio="none"`). *Le Japon fait exception visuelle : son
  disque ressort en ellipse large — c'est le rendu voulu, pas un défaut.*
  Les cartes presque carrées (vainqueur d'un circuit) gardent au contraire le recadrage.
- **Aucune teinte héritée sur un ancêtre.** La bande noire allemande n'a pas d'attribut de
  remplissage et **hérite** ; le Canada pose le piège à l'envers. Ne jamais poser de
  `.foregroundStyle` au-dessus d'un drapeau.
- **Un pays absent ne rend RIEN**, jamais une couleur de repli.

**Le lavis de drapeau en fond d'une ligne de classement est à 8 %** — pire substrat le noir,
qui compose `#EBEBEB`. Sur ce fond : `texte` **14,60:1**, `secondaire` **8,86:1**,
`primaire` **9,13:1**, **`texteDoux` 2,39:1 — banni de ces lignes.** Le prénom et l'écurie
prennent donc le marron `secondaire`.

**Le drapeau du vainqueur en fond de sa carte est à 9 %** : mesuré sur le pire substrat (le
bleu britannique `#012169`), qui compose `#E8EBF1`, où `#1A1A1A` vaut 14,9:1.

### 5.6 La vue piste

Le fond (`vue_piste.svg`) : sol beige `#F4EFEA` à coins arrondis, quatre segments de ligne
médiane, **deux kerbs en chemins** (pas en dégradés répétés).

- **Le fond s'étire indépendamment en X et en Y** (`preserveAspectRatio="none"`) : les kerbs
  gardent leur largeur proportionnelle quel que soit le rapport de forme, seule la pente de
  leurs bandes s'incline. L'écart est nul à deux dixièmes près sur les iPhone visés.
- **Les kerbs gardent `#7f1717`** : un kerb rouge et blanc est le signe **F1**, pas un
  repère de championnat. Il vaut 9,02:1 sur le beige.
- **Le sol est peint DEUX fois** — par le dessin et par un aplat derrière lui : le dessin
  arrondit ses coins, et sans l'aplat les quatre angles laisseraient voir le grain du fond.
- **Le bandeau de titre ne fait PAS partie du dessin.** Il porte la couleur du championnat,
  le damier et le nom, et vit dans la couche d'interface. **Sa hauteur est un plancher, pas
  une proportion** : `max(10,9427 % de la hauteur d'écran, safeAreaTop + 92 pt)`. Les 92 pt
  sont mesurés — 38 pour la rangée du bouton de retour, 54 pour celle du nom. **À 80 pt les
  deux rangées se touchaient.** Le rayon des coins suit la **largeur**
  (`min(10,6361 % de la largeur, 62,7 pt)`) pour rester **circulaire** : un rayon en
  pourcentage de la hauteur rendrait une ellipse, qui se lit comme une faute.
- **La zone de jeu est bornée par des pourcentages mesurés** : 4,2205 % à gauche, 4,8058 % à
  droite (bords intérieurs des kerbs, non symétriques).

#### La piste est un **segment** de `ChampionnatDetailView`

Un `Picker` segmenté natif, sous l'en-tête, bascule entre **Classement** et **Piste**. La
piste s'affiche **en place** (`VuePisteView(…, integree: true)`) : sans bandeau — l'en-tête
de l'écran porte déjà le nom du championnat — et sans masquer la barre de navigation ni la
barre d'onglets. Le passage d'un segment à l'autre est un fondu de 200 ms ; les voitures
rejouent leur entrée à chaque affichage de la piste.

L'**écran plein** (`integree: false`) reste en place, non monté, avec son bandeau et son
retour « ‹ Classement » ; le bouton pleine largeur qui le poussait (`lienPiste`) aussi. La
règle précédente — « jamais un segment de bascule » — est levée : il n'y a plus qu'un
chemin vers la piste, le segment.

**Seul le sol franchit les zones sûres** — la couleur passe sous la barre d'état, le texte
jamais. En bas, la zone de jeu s'arrête au-dessus de l'indicateur d'accueil : sans cela le
score de la dernière voiture passerait dessous. La piste mesure alors **686 pt** de haut sur
un iPhone 17 Pro, pas 778.

> **Le damier ne se pose pas dans une pile.** `scaledToFill` y impose sa *taille de
> remplissage* : proposé 402 pt de large, un dessin de 542 × 420 en réclame 311 de haut, et
> le fond du bandeau débordait de 104 pt par-dessus le haut de la piste. L'aplat de couleur
> porte donc ses deux calques décoratifs en `overlay`, qui ne change pas la taille de son
> hôte. Défaut mesuré au simulateur, invisible à la lecture du code.

#### Toutes les voitures ont la même taille

**52 × 106, sans exception** — ni le score, ni le rang, ni l'encombrement de son groupe ne
change la taille d'une voiture, et le score sous elle fait toujours 14 pt. Ce qui se resserre
quand un groupe s'élargit, c'est le **pas** de l'éventail, jamais le dessin : deux voitures
voisines à deux tailles différentes laissaient croire que la taille voulait dire quelque
chose.

#### L'échelle est tendue sur les scores réels — comme `Piste.jsx`

```
y = bas − (points − minimum) / (maximum − minimum) × (bas − haut)
```

Le meilleur tient **toujours** le haut de la zone de jeu, le moins bon **toujours** le bas,
et un score élevé donne un `y` petit. `haut` et `bas` tombent autour de 10 % et 90 % de la
piste, mais ils sont **calculés** : la place d'une voiture et de son score, en haut comme en
bas.

**Un seul membre** se pose en haut : il mène. **Tout le monde à égalité** (avant le premier
Grand Prix) se pose à mi-hauteur, et la résolution des chevauchements en fait une grille de
départ sur plusieurs voies.

> **Jusqu'à la version iOS `0.39.3`, le bas de la piste valait zéro point** : un dernier à
> 24 sur 168 restait aux sept huitièmes de la piste, et à 93 sur 168 vers le milieu. Le web
> tendait déjà sur le minimum ; iOS s'aligne. Seul écart restant : le web centre un membre
> seul (`maximum === minimum`), iOS le pose en haut.

> **Jeu d'essai** : `168, 93, 66, 50, 47, 26, 24, 0`, les scores de
> `maquettes_V2/screen-14-vue-piste.PNG`. Ils restent dans `MembreMock.exemples`, qui ne sert
> plus qu'aux aperçus Xcode depuis l'étape 3, et ils couvrent les trois cas qui comptent — un écart
> énorme en tête, un peloton qui se chevauche, un membre à zéro.

**La vue piste identifie chacun par sa livrée, son numéro, et le pseudo peint sur l'aileron
arrière.** La légende de droite n'affiche que le score, sans libellé — c'est pour cela que
les pastilles carrées (`matti.svg`) **ne remplacent pas** les voitures : une pastille n'a
nulle part où écrire le pseudo.

### 5.7 Icône de l'app

Les icônes web sont regénérées **par script** depuis `assets/logo-05.svg`. Deux points
transposables tels quels à l'icône iOS : rendue **à fond perdu et sans canal alpha** (iOS
applique son propre masque arrondi et rendrait la transparence en noir), et **sans conserver
l'arrondi du dessin** — ce qui donnerait un arrondi dans un arrondi, avec des coins noirs.

---

## 6. Règles métier critiques

### 6.1 Les points sont des entiers — jamais une cote

> **Points = cote Unibet × 10, arrondie à l'entier.** Une cote de 2,80 rapporte **28
> points**. Une cote de 9,50 rapporte **95 points**.

**On n'affiche JAMAIS une cote brute.** Nulle part on n'écrit « ×2,80 » ni « cote 2,80 » —
on écrit **« 28 pts »**. Sans exception : tableau des cotes, saisie, récapitulatif,
résultats, profils, statistiques, calendrier. Y compris pour une statistique comme la cote
moyenne tentée, qui s'affiche « 31 » et non « ×3,1 ».

**Rien en base ne stocke une cote.** Toutes les valeurs servies par l'API sont déjà des
points : **ne jamais diviser, ne jamais multiplier.**

**Un seul endroit habille un nombre de points** — l'équivalent Swift de `formaterPoints` :

```swift
/// Le SEUL point d'application de la règle. Un écran qui fabriquerait "\(points) pts"
/// lui-même finirait un jour par écrire la cote.
func formaterPoints(_ points: Int?) -> String {
    guard let points else { return "Cote retirée" }   // issue retirée par Unibet
    return "\(points) pts"
}
```

Trois états, jamais deux : une valeur, **ou** « Cote retirée » quand l'issue a disparu
depuis la saisie. **Jamais un zéro inventé.**

> **Une seule exception, et elle porte un autre nom.** `points_fia` sur l'écran de résultats
> (25, 18, 15…) est le championnat du monde, pas des points de pronostic. Il s'écrit
> « 25 pts » et **ne passe JAMAIS par `formaterPoints`**. Les deux unités cohabitent sur le
> même écran — c'est un écart signalé et assumé.

### 6.2 `NULL` et `0` ne se confondent jamais

C'est **la convention la plus structurante du projet**, tenue partout.

| Valeur de `points_gagnes` | Sens |
|---|---|
| `nil` | Résultat inconnu, **ou marché que le calcul n'a pas su valider** |
| `0` | Pronostic **raté** |
| `> 0` | Pronostic **réussi** |

**`nil` s'affiche « en attente » et se rattrape** par un second passage du calcul.
**`0` est définitif et ne se rattrape jamais.** Afficher `0` avant la course annoncerait un
échec qui n'a pas eu lieu ; afficher « en attente » sur un `0` cacherait un échec réel.

La même règle vaut sur tous les champs facultatifs de l'API : `total_points`, `mes_points`,
`mon_rang`, `meilleure_cote`. **Un `Int?` en Swift, jamais un `Int` avec défaut à 0.**

### 6.3 Structure d'un pronostic, et la règle du podium

Pour chaque Grand Prix :

- **2 obligatoires** — le **vainqueur**, et le **podium** (2 pilotes à placer) ;
- **3 bonus au choix**, sélectionnés **parmi ses favoris**.

> **Les deux pilotes du podium n'ont AUCUN ordre entre eux.** La validation demande
> « ces deux pilotes sont-ils sur le podium ? », jamais « lequel devant ».

> ### Chaque pilote du podium est jugé pour son propre compte
> **Le podium n'est pas un pari en deux jambes solidaires : ce sont deux paris saisis dans
> le même bloc.** Un pilote qui monte sur le podium rapporte sa cote, **que l'autre y monte
> ou non**. Les deux, un seul, ou aucun. Un podium entièrement réussi rapporte donc la
> **somme** des deux cotes.
>
> **Une jambe non jugeable laisse le pronostic ENTIER à `nil`.** La ligne ne porte qu'un
> seul `points_gagnes`, et le calcul n'écrit que les `nil` : payer la seule jambe connue
> figerait un total partiel que le rattrapage ne corrigerait plus jamais.
>
> **Le total POTENTIEL ne change pas** — il reste la somme des deux cotes, parce que c'est
> toujours le maximum atteignable. La même règle vaut partout où un podium est chiffré
> *avant* la course : total potentiel, cote moyenne tentée, récapitulatif.

**Le vainqueur est déjà sur le podium** : le bloc de saisie s'intitule **« 2e et 3e du
podium »**, et un pilote choisi comme vainqueur **disparaît** des deux emplacements suivants
(exclusion croisée).

> **L'exclusion se compare sur le LIBELLÉ du pilote, jamais sur `id_outcome_unibet`.** Un
> même pilote ne porte pas le même identifiant d'issue selon le marché. Un filtre par
> identifiant marche entre les deux emplacements du podium et **n'exclut jamais le
> vainqueur**.

> **L'exclusion est réactive et NON destructive.** Changer de vainqueur rend aussitôt
> l'ancien aux listes, **sans vider les sélections déjà faites**. Une sélection devenue
> conflictuelle reste affichée, et la validation la nomme.

**Le contrôle des marchés obligatoires est strict** : le vainqueur vient du marché
`vainqueur`, les deux du podium du marché `podium`. Un pronostic « vainqueur » qui
désignerait en réalité une écurie serait impossible à valider, et le joueur ne le
découvrirait qu'après la course.

### 6.4 Le calendrier d'un week-end, et la fermeture

| Moment | Ce qui se passe |
|---|---|
| **Samedi, qualifications + 2 h** | Scraping Unibet. Grille définitive. **Les cotes sont figées** |
| Samedi soir → dimanche | Saisie libre. **Les pronostics sont visibles par les autres membres dès leur saisie** |
| **Dimanche, au départ** | **Fermeture.** Plus aucune modification |
| **Départ + 1 h 30** | Job de résultats toutes les 5 min, puis calcul et attribution. Statut → `termine` |
| **Dès `termine`** | Le widget de l'accueil bascule sur le **Grand Prix suivant** |

**Les quatre états d'un Grand Prix** à l'écran :

| État | Libellé | Condition |
|---|---|---|
| `termine` | « Terminé » | statut `termine` |
| `ferme` | « Fermé » | fermeture passée |
| `ouvert` | « Pronos ouverts » | **cotes arrêtées** |
| `a_venir` | « À venir » | tout le reste |

> ### « Cotes arrêtées » exige DEUX conditions, et rien d'autre
> Statut **`cotes_figees`** ET fermeture pas encore passée (`date_course` devant nous).
> **Surtout pas `date_qualifications`** : cette heure est `NULL` sur toute ligne qu'aucune
> migration n'a posée et qu'Unibet n'a pas programmée — et Unibet **n'expose aucun événement
> de qualification** dans le régime constaté. L'exiger fermait l'application entière, sans
> un mot à l'écran.
>
> **Ce test doit vivre à UN SEUL endroit**, et servir les **quatre** surfaces qui portent un
> bouton de pronostics : accueil, calendrier de la saison, calendrier d'un championnat,
> fiche d'un Grand Prix. Écrit quatre fois, il divergerait au premier ajustement, et le
> symptôme serait discret — un GP pronostiquable d'un onglet et pas de l'autre.

> ### La fermeture est `date_course`, SANS marge
> Une marge de cinq minutes tenait ce rôle jusqu'à la `0.71.0`, à trois étages (base,
> backend, frontend). **Les trois ont été retirées ensemble** : c'est une seule règle à
> trois étages, et un étage laissé en arrière aurait ouvert le formulaire sur une écriture
> que la base refuse. **Ne réintroduire aucune marge côté iOS.**

> ### Un GP dont l'heure de départ est INCONNUE reste OUVERT
> Aux trois étages. Refuser tout le monde parce qu'Unibet n'a pas annoncé l'horaire serait
> le mauvais sens du doute.

> ### Le compte à rebours a DEUX échéances, pas une
> | Phase | Échéance décomptée | Ce qui est écrit |
> |---|---|---|
> | Avant le relevé des cotes | `date_qualifications` + 2 h | **« Ouverture dans »** |
> | Pronostics ouverts | `date_course` | **« Fermeture dans »** |
> | Après la fermeture | — | **« Pronostics / Fermés »** |
>
> **C'est « cotes arrêtées » qui départage les deux premières phases, jamais le statut
> brut** — et c'est ce qui fait tenir l'ensemble : le bouton de pronostics s'affiche sur
> exactement la même condition. Une case « Fermeture dans » au-dessus d'un bloc **sans
> bouton** serait un décompte vers une fermeture que rien n'ouvrira.
>
> **« Pas encore ouverts » exige les TROIS à la fois** : cotes non arrêtées, heure de
> fermeture pas encore passée, et GP non `termine`. Le premier test suffit un samedi matin ;
> il ne suffit pas le dimanche soir, où un GP couru le passe aussi.
>
> **Les deux heures après les qualifications sont une PRÉVISION, pas une garantie** : c'est
> le délai du job du samedi, qui peut prendre du retard. **Le décompte se tait dès que
> l'heure prévue est passée sans que le statut ait bougé** — « Ouverture / À confirmer ».
> Mieux vaut ne plus rien promettre que promettre une ouverture déjà en retard.

> **Une seule source pour ces décisions**, servant les quatre surfaces qui portent un
> décompte : les deux cases du bloc d'accueil, l'horloge de l'écran de saisie, celle du
> récapitulatif. **L'horloge ne décide jamais de ce qu'elle annonce.**

### 6.5 Points cloisonnés ? Non — et départage

> **Un joueur remplit UN pronostic par Grand Prix, qui compte dans TOUS ses championnats à
> la fois.** Le championnat dit **qui** classer, pas quels pronostics compter.

**Conséquence** : quitter un championnat n'efface les pronostics que **s'il ne reste au
joueur aucune adhésion**. Les effacer au départ d'un seul détruirait son classement dans les
autres.

**Départage des égalités, dans l'ordre :**

1. le plus grand **nombre de pronostics réussis** ;
2. la **meilleure cote réussie** (le plus gros coup) ;
3. l'**ordre d'inscription** au championnat (`rejoint_le`) ;
4. l'identifiant du profil — sans quoi la numérotation serait instable d'un appel à
   l'autre, **et deux membres échangeraient leurs couleurs entre deux rafraîchissements**.

Les quatre réunis départagent **toujours** : le classement général n'a **aucun ex æquo**.

> **Sur le classement d'UN Grand Prix, c'est l'inverse : les ex æquo s'affichent comme
> tels.** Cette règle régit le classement général, pas une course isolée — avant le départ
> tout le monde est à zéro, et un rang strict inventerait un premier et un dernier.

**Le classement arrive déjà trié et rangé par le serveur.** Ne jamais le retrier côté
client : `ordre_inscription` est là pour tout ce qui doit rester stable (couleur, repère).

### 6.6 La voiture

Chaque utilisateur possède **une seule voiture, identique dans tous ses championnats** :
deux couleurs, une **couleur de texte**, un numéro libre, son pseudo sur l'aileron arrière.

> **`couleur_texte` — `nil` veut dire « pas de choix », jamais « pas de couleur ».** Elle
> peint **le numéro du museau ET le pseudo de l'aileron**, les deux ensemble : c'est une
> seule décision du membre. Sans choix, chaque texte reprend l'**encre calculée** qui
> contraste avec l'aplat qui lui est propre — et les deux aplats diffèrent sur neuf des onze
> livrées d'écurie.

> **Le contraste se mesure et se signale, il ne se refuse pas.** L'écran de profil compare
> la couleur choisie à l'aplat du museau de la livrée en cours, et le dit sous les **3:1**
> d'un grand texte porteur de sens. **Il ne bloque jamais l'enregistrement** : la voiture
> appartient au membre.

> **`numero` n'a AUCUNE contrainte d'unicité, et c'est délibéré.** Une voiture étant la même
> dans tous les championnats de son propriétaire, un numéro unique globalement voudrait dire
> **99 comptes maximum sur toute l'application**. L'avertissement affiché est **purement
> indicatif** : il nomme le porteur, il ne bloque jamais la sauvegarde. La liste des numéros
> pris se charge **une fois** au montage de l'écran, et la vérification se fait **en
> mémoire** à chaque frappe — un appel réseau par caractère saisi serait le pire compromis
> possible pour un avertissement qui ne bloque rien.

Chaque profil naît avec une **livrée distincte**, attribuée par ordre d'inscription global
(dix livrées, cyclique). Le membre l'écrase dès qu'il personnalise.

### 6.7 Championnats

- Code d'invitation : **6 caractères alphanumériques, sans séparateur** (`F1X7K2`).
- **Aucune limite** de membres. Un utilisateur peut appartenir à plusieurs championnats.
- **Le créateur rejoint automatiquement son championnat.**
- **Le championnat survit à son créateur** (`cree_par` passe à `nil`). **Conséquence
  assumée** : plus personne ne peut alors le supprimer.
- **Un championnat vidé de ses membres est supprimé automatiquement.**

### 6.8 Vocabulaire imposé

| Utiliser | Ne jamais utiliser |
|---|---|
| **championnat** | ~~ligue~~ |
| **calendrier** | ~~historique~~ |

Vérifié par des tests côté web. **La même règle vaut pour tout texte de l'app iOS**, y
compris les identifiants de vues, les clés de localisation et les commentaires visibles.

### 6.9 Ce qui n'est PAS implémenté

- **Grand Prix annulé ou reporté** : le statut `annule` n'existe pas et aucun code ne
  l'applique. Ne pas supposer son existence.
- **Premier abandon** : marché volontairement non implémenté tant que la règle d'égalité
  n'est pas écrite.
- **Les pronostics « visibles dès la saisie »** : la règle métier est en vigueur côté écran,
  mais la politique RLS, elle, ne laisse lire les pronostics d'un autre qu'**après** la
  fermeture. Les écrans passent donc par l'API (chemin A), qui contourne la RLS. **Une
  lecture directe des pronostics d'autrui rendrait des lignes manquantes, en silence.**

---

## 7. Points d'attention iOS

### 7.1 Safe areas, zones tactiles, et wayfinding

- **`env(safe-area-inset-*)` sur tous les écrans** côté web ; en SwiftUI, `safeAreaInset` et
  `.ignoresSafeArea(edges:)` **maîtrisés**, jamais globaux.
- **Zone tactile minimale 44 × 44 pt** — un **plancher**, pas une hauteur fixe : la rangée
  doit pouvoir grandir si le corps de texte est agrandi (Dynamic Type).
- **Les aplats de couleur coiffent l'écran, le texte reste dans la zone sûre.** Une couleur
  qui s'arrêterait sous la Dynamic Island se lirait comme un bandeau posé de travers.
- **Les zones sûres se traitent SÉPARÉMENT du rembourrage**, jamais additionnées.
- **`.userSelectDisabled` sur les éléments graphiques** (équivalent de `user-select: none`).
- **Tester sur iPhone réel**, pas seulement au simulateur.

**Wayfinding — quatre questions auxquelles un écran doit répondre** : *où suis-je*, *ce
qu'est cet écran*, *comment j'en sors*, *où mène ce bouton*.

> **Un bouton NOMME sa destination** — « Accueil », « Classement », « Voir les résultats ».
> Un chevron muet ne dit rien, et un bouton « Pronostiquer » qui débouche sur un
> récapitulatif est une promesse fausse. **Quand un même bouton mène à deux écrans, son
> libellé suit sa destination.**

> **Le bouton de retour natif échappe à cette règle sous iOS 26.** Mesuré au simulateur :
> le Liquid Glass le rend en pastille de verre, **chevron seul**, quel que soit le titre de
> l'écran précédent — comme il reprend la main sur la barre d'onglets (`ios/CLAUDE.md` §3).
> Le titre reste posé sur l'écran d'origine, parce qu'iOS 17 et 18, la cible de
> déploiement, l'affichent bien ; et il se masque sur place par un `ToolbarItem(placement:
> .principal)` vide, `navigationTitle("")` retirant du même coup le titre **et** le libellé
> du retour. Un retour qui doit se nommer sur les trois versions se pose donc **dans le
> contenu**, la barre masquée — c'est ce que fait `RecapView`, et c'est ce qui préserve en
> prime le retour par glissement.

> **Un bouton reste ACTIF même quand la saisie est incomplète.** Un bouton grisé ne dit pas
> ce qui manque ; l'appui pose le message à l'endroit exact à corriger.

> **Une confirmation se fait SUR PLACE, jamais en boîte de dialogue** : le geste de retour
> d'iOS l'annule, et aucune couche ne s'interpose.

> **Une attente est une SILHOUETTE, jamais un texte.** Et la silhouette suit la hauteur
> réelle de ce qui arrive — sans quoi l'écran sursaute à l'arrivée des données. La couleur
> est `squelette` (`#E8E0D8`), et elle ne sert **qu'à cela**.

**Rangées horizontales** (favoris, livrées) : calées sur leurs éléments — l'équivalent de
`snap-x`, soit `.scrollTargetBehavior(.viewAligned)` sur iOS 17+. Un doigt qui les pousse
les laisse sur un élément entier, jamais coupé en deux, et le débordement volontaire du
dernier élément dit qu'il y en a d'autres au-delà. **Ne jamais nicher un conteneur
défilable horizontalement dans un accordéon lui-même dans une page qui défile** : le geste
part au mauvais étage une fois sur deux.

### 7.2 Hors ligne

**L'app doit afficher un état propre sans réseau.** Le client web applique une stratégie
*stale-while-revalidate* : il **affiche immédiatement ce qu'il savait**, puis se met à jour.
À reproduire, et pour la même raison — le cold start Railway.

```swift
// Toute clé de cache porte l'identifiant du compte. Deux personnes qui se relaient
// sur le même téléphone ne doivent jamais voir les données de l'autre.
let cle = "championnats:\(profilId)"
```

**Trois genres d'échec, trois traitements** (l'équivalent de `lib/erreurs.js`) :

| Genre | Statuts | Message | Ce que l'écran propose |
|---|---|---|---|
| **Réseau** | `502`, `503`, `504`, timeout, pas de connexion | « Connexion au serveur en cours… Réessaie dans quelques secondes. » | **Réessayer** — et ça marche |
| **Session** | `401` | « Session expirée. Reconnecte-toi. » | Router vers la connexion (§7.3) |
| **Serveur** | le reste | le `detail` français du backend, ou « Une erreur est survenue. Réessaie. » | Réessayer |

> **`502`, `503` et `504` sont classés RÉSEAU et non serveur**, et ce n'est pas une
> approximation : sur le plan gratuit de Railway, c'est très exactement ce que rend un
> service endormi.

**Ne jamais afficher un message technique.** Le backend n'en renvoie plus, mais il faut se
garder de ce qui **ne vient pas de lui** : page d'erreur Railway, proxy qui s'interpose,
ancienne version encore déployée. Reconnaître des **signatures franches** (code PostgreSQL à
5 caractères, `Traceback`, `Error:`, `does not exist`, `permission denied`,
`Internal Server Error`, `Bad Gateway`) et remplacer par le message générique. **Ne pas
tenter de répondre à « est-ce du français ? »**, question à laquelle aucune heuristique ne
sait répondre.

**Les lectures directes Supabase fonctionnent pendant que Railway dort** : c'est tout
l'intérêt du chemin (B). L'accueil doit rester utilisable sur ce seul chemin.

### 7.3 Jeton expiré

`supabase-swift` rafraîchit le jeton automatiquement. Un `401` malgré cela veut dire que la
session est **réellement** perdue :

```swift
if statut == 401 {
    try? await supabase.auth.signOut()   // purge la session locale incohérente
    viderCache(pour: profilId)           // §2.6
    router.vers(.connexion)
}
```

**Distinguer `401` de `503`.** Un `503` sur une route protégée veut dire « Supabase
injoignable », pas « déconnecte-toi » : déconnecter l'utilisateur sur une panne réseau lui
ferait perdre sa session pour rien.

**Tant que la session initiale n'est pas résolue, afficher l'écran d'attente** — jamais
l'écran de connexion. Rediriger pendant ce laps **ferait clignoter la connexion à chaque
lancement**.

### 7.4 Dates — tout est UTC en base, tout s'affiche en heure locale

**Toutes les dates de l'API et de la base sont en UTC** (`timestamptz`). Elles arrivent en
ISO 8601, sous l'une des deux formes `2026-08-23T13:00:00+00:00` ou `2026-08-23T13:00:00Z`,
**avec ou sans fraction de seconde** selon la source (PostgREST ou Pydantic).

```swift
let decodeur = JSONDecoder()
decodeur.dateDecodingStrategy = .custom { d in
    let texte = try d.singleValueContainer().decode(String.self)
    let avecFraction = ISO8601DateFormatter()
    avecFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let sansFraction = ISO8601DateFormatter()
    sansFraction.formatOptions = [.withInternetDateTime]
    if let date = avecFraction.date(from: texte) ?? sansFraction.date(from: texte) {
        return date
    }
    throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(),
                                          debugDescription: "Date illisible : \(texte)")
}
```

> **À vérifier** : la présence effective de fractions de seconde selon les routes. Le
> décodeur ci-dessus accepte les deux formes, ce qui rend la question sans conséquence.

**L'affichage est en heure locale du téléphone**, en français :

```swift
// « Dimanche 23 août » + « 15h00 » — l'écriture du projet, avec le « h » et non « : »
let jour = date.formatted(.dateTime.weekday(.wide).day().month(.wide)
                          .locale(Locale(identifier: "fr_FR")))
// La première lettre du jour est minuscule en français ; le projet la capitalise en tête
// de ligne.
```

**Trois règles de comparaison à ne pas transgresser :**

1. **L'instant de comparaison se calcule en UTC**, jamais laissé à une conversion implicite.
2. **Une date `nil` n'est PAS une date passée.** Un GP sans `date_course` **reste ouvert**
   (§6.4), reste servi dans le calendrier, et **reste compté** dans les GP restants.
   Le tri le place **en fin de liste**, jamais en tête.
3. **La saison est l'année civile en UTC.** Prendre l'heure locale ferait basculer la saison
   une ou deux heures trop tôt le 31 décembre.

Un GP sans horaire **n'appartient à aucune saison** et n'entre dans aucune statistique —
mais il **est servi quand même** dans le calendrier. *C'est un arbitrage délibéré : une
moyenne fausse ne se voit pas, un Grand Prix manquant dans un calendrier se voit tout de
suite.*

### 7.5 Divers

- **Les libellés de pilotes d'Unibet ne sont pas homogènes** : la quasi-totalité arrive en
  « initiale + nom » (`M.Verstappen`), quelques-uns en nom complet (`Franco Colapinto`), qui
  fait deux fois la largeur de ses voisins et casse l'alignement d'une grille. Le web
  normalise via une table de correspondance. **Prévoir la même normalisation**, ou une mise
  en page qui absorbe l'écart.
- **Aucun écran ne doit inventer de donnée absente** : pas de tracé de repli pour un circuit
  inconnu, pas de couleur de repli pour un drapeau absent, pas de zéro à la place d'un `nil`.
  C'est la règle la plus constante du projet.

### 7.6 Branchement des données — état et ordre

L'app a été construite écran par écran sur des **mocks**. Leur remplacement suit l'ordre
ci-dessous ; chaque étape ne dépend que des précédentes.

| Étape | Contenu | État |
|---|---|---|
| **0** | Fondations : `APIClient`, `ErreurAPI`, `JSONDecoder.api`, réveil, `Profil` / `Championnat` / `Membre`, profil courant en direct | **Fait** (iOS 0.20.0) |
| **1** | `GET /championnats/moi` — **un seul propriétaire** pour l'accueil et l'onglet Championnats. L'`id` devient un UUID : la teinte Pantone, tirée de l'id, changera une fois | **Fait** (iOS 0.21.0) |
| **2** | Créer / rejoindre, puis la photo (Storage + `PATCH`). Navigation vers le championnat obtenu, liste de l'étape 1 invalidée | **Créer / rejoindre faits** (iOS 0.22.0) — photo à faire |
| **3** | Détail : `classement` remplace `MembreMock`, **la piste reçoit le même tableau** · menu « ⋯ » (code, `quitter`) · widget GP = `prochain_gp` de l'étape 1 | **Fait** (iOS 0.24.0) |
| **4** | Profils : `GET /profils/{id}` + `/stats` (membre et moi), `PATCH /profils/moi`, avatar, Administration (`POST /admin/action`), « Ses Grands Prix » en dernier | **Stats (moi et membre) faites** (iOS 0.25.0) · **Administration faite** (iOS 0.31.0 : scraper sans figeage, mode admin = prévisualisation) — `PATCH` voiture fait · **avatar déposé** (iOS 0.39.7 : `DepotPhoto` → `PATCH /profils/moi`), retrait à faire · **« Ses Grands Prix » : fait** (iOS 0.40.0, `HistoriqueGPView` + `GrandsPrixJoues`) — sans route dédiée : `GET /championnats/{id}/calendrier`, puis pour chaque GP terminé `GET /grands-prix/{gp}/pronostics/championnat/{id}` filtré sur le `profil_id` et `GET /grands-prix/{gp}/resultats` pour le podium. Un pronostic n'appartient à aucun championnat : depuis son propre profil, le premier de `GET /championnats/moi` suffit |
| **5** | Calendrier : liste statique **croisée** avec `GET /scraper/cotes` → états réels **et `gp_id`** · GP suivant de l'accueil en lecture directe · **un seul calcul d'échéance** (§6.4) | **Fait** (iOS 0.26.0) |
| **6** | Résultats : `GET /grands-prix/{id}/resultats` + mes pronostics en direct, puis `?championnat_id=` | **Classement de course fait** (iOS 0.27.0) — mes pronostics et `?championnat_id=` à faire |
| **7** | Pronostics : `EtapePronos` porte le `gp_id` · cotes réelles · bonus = favoris serveur · `POST …/pronostics` avec `423` · destination du widget d'accueil | **Fait** (iOS 0.28.0) · mode prévisualisation admin (iOS 0.31.0) |

**Pourquoi cet ordre.** Les championnats d'abord : les écrans les plus vus, une seule route,
de quoi éprouver la couche réseau sur un cas simple. Le calendrier avant résultats et
pronostics : **c'est lui qui fournit le `gp_id`**, sans lequel aucun écran de course ne sait
quel GP demander. Les pronostics en dernier : trois écrans, deux changements de modèle et le
`423`.

**Écarts de modèle déjà repérés entre les mocks et le contrat serveur :**

- **`EtapePronos` ne transporte pas l'identifiant du GP** (nom, slug, sous-titre seulement).
- **Le calendrier n'a pas de `gp_id`** : seul le slug existe. Le rattacher par le nom du GP
  depuis `GET /scraper/cotes`. Les 12 cartes s'affichent **quoi qu'il arrive** — l'échec de
  l'appel fait perdre les états, jamais la liste.
- **`MarcheCote` ne connaît que vainqueur et podium** : les bonus portent les marchés
  **découverts par le scraper** (`marche` + `libelle`), le modèle doit devenir dynamique.
- **Le panier local de paris bonus doit devenir les favoris serveur** : le serveur exige
  que les bonus soient parmi les favoris.
- **Les statistiques d'un membre ne se dérivent plus du classement** : `GET /profils/{id}/stats`.
- **L'écurie d'un pilote n'est pas servie** : table pilote → écurie côté client (pendant de
  `lib/ecuries.js`).
- **Le bandeau « Pronos enregistrés ! »** ne s'affiche qu'après un `200`.
- **`GET /grands-prix/{id}/resultats` avec `disponible: false`** ⇒ « résultats en attente »,
  jamais un classement vide.

**Ce qui reste statique — ne pas brancher** : `FichesGrandPrix` (séances hors qualifs et
course, circuits, palmarès), la liste des 12 GP, `NationalitesPilotes`, `DrapeauxGP`,
`LivreeEcurie`, la table pilote → écurie.

**Tranché avant l'étape 1 :**

- **« 12 Grands Prix restants » reste une constante fixe** — pas de comptage en base.
- **Pas de cache de session** : chaque écran recharge ses données à chaque ouverture. La
  liste déjà affichée reste visible pendant le rechargement ; le spinner ne sert qu'au
  premier chargement et après un échec (`MesChampionnats`).
- **Le hors ligne (§7.2) est hors périmètre** de ce chantier : il viendra après.

**Étape 1, mise en œuvre.** `Services/MesChampionnats.swift` est le propriétaire unique :
une instance créée par `BarreNavigation`, passée à `AccueilView` et `ChampionnatsView`,
rechargée par leur `.task`. `CarteChampionnat` lit le vrai `Championnat` ; le rang absent
(`position` nulle) s'affiche « – », jamais « 0 ». Spinner et message d'`ErreurAPI` (avec
« Réessayer » si `estRejouable`) vivent dans `EtatMesChampionnats`, partagé par les deux
écrans. Le détail reçoit encore un `ChampionnatMock`, projeté du réel avec la même clé de
teinte (UUID en minuscules) — jusqu'à l'étape 3.


**Étape 2, mise en œuvre (créer / rejoindre).** Les deux écrans reçoivent ``MesChampionnats``
par ``ActionsChampionnat`` et appellent `APIClient` directement. **Le succès ne quitte pas
l'écran** : « Créer » remplit l'aplat rouge avec le code reçu (entrée décalée, bouton de
partage système), « Rejoindre » écrit « Bienvenue dans « nom » ! » ; dans les deux cas le
bouton devient « Voir le championnat » (`ChampionnatDetailView`, encore sur
`ChampionnatMock`). Un refus (`422`, `404` code inconnu, `409` déjà membre) s'écrit sous le
bouton via `ErreurEnLigne` — **jamais d'alerte système** — et s'efface à la frappe suivante.
Le rechargement passe par `charger(forcer: true)` : sans lui, un chargement déjà en vol,
lancé **avant** l'écriture, absorberait la demande et le championnat manquerait à la liste.
L'appel n'est pas lié à l'écran : le quitter en cours de route n'annule ni l'écriture ni le
rechargement. Le nom est borné à **2–40 caractères** côté client, comme le serveur.
**Reste de l'étape 2 : la photo** — choisie et vérifiée (2 Mo), mais pas encore déposée.

**Étape 3, mise en œuvre (classement et piste).** `ChampionnatDetailView` reçoit le vrai
`Championnat` ; `ChampionnatMock` n'est plus monté. `Services/ClassementChampionnat.swift`,
possédé par l'écran (`@StateObject`), appelle `GET /championnats/{id}/classement` à chaque
apparition — **un seul appel pour les deux segments** : la piste reçoit le tableau déjà
chargé, basculer de segment ne rappelle rien. Spinner puis `EchecChargement` (message
d'`ErreurAPI`, « Réessayer » si `estRejouable`) — le bloc d'échec est désormais **partagé**
avec `EtatMesChampionnats`. L'effectif de l'en-tête est celui du classement dès qu'il est
lu. `meilleure_cote` nulle ⇒ le sous-titre tait le meilleur coup, jamais « 0 pts » ;
`numero` nul ⇒ la voiture porte le rang. Le profil d'un membre est projeté de sa ligne :
**les statistiques que le classement ne sert pas s'affichent « – »** jusqu'à l'étape 4.
`MembreMock` ne sert plus qu'aux aperçus (jeu d'essai de la piste, §5.6).

**Étape 3, fin (menu « ⋯ » et widget GP).** Le menu est un `Menu` natif à deux entrées.
« Code d'invitation » ouvre une feuille compacte (`.height(300)`) : le code en grand, et le
même `ShareLink` que « Créer », phrase comprise. « Quitter le championnat » passe par une
**alerte de confirmation** — la seule de l'écran, parce que c'est la seule action
destructive —, puis `DELETE /championnats/{id}/quitter`, `charger(forcer: true)` et le
retour à l'écran précédent ; un refus s'affiche en alerte, faute de bouton sous lequel
l'écrire. L'écran reçoit donc `MesChampionnats` de ses quatre appelants. Le widget lit
`prochain_gp` : **absent ⇒ pas de widget**. Son slug vient de `ProchainGP.slug`,
transcription de `slugCircuit` (alias compris), et **le bouton « Pronostiquer » n'existe
que si `pronosticsOuverts`** — `cotesArretees` du web : `cotes_figees` et départ pas encore
passé, départ inconnu ⇒ ouvert. Sinon le widget annonce « Course le … » ou « Pronostics
fermés » sans mener nulle part. Le calcul d'échéance reste local au widget jusqu'à
l'étape 5, qui en fera **un seul**.

**Menu « ⋯ », photo ; widget GP retiré (iOS 0.39.8).** Une troisième entrée, « Modifier la
photo », **visible du seul créateur** (`est_createur`), ouvre la photothèque
(`.photosPicker`, images seules). La photo passe par `DepotPhoto` (compartiment
`championnats`, dossier = id du championnat), puis `PATCH /championnats/{id}` avec
`photo_url`, puis `charger(forcer: true)` — ce sont les cartes qui la peignent. Un refus
s'affiche en alerte, comme le départ. Le widget GP de l'onglet Classement est **démonté**
sans remplacement (`WidgetGrandPrixSuivant` reste en place, non monté). À l'accueil,
l'avatar bascule sur l'onglet Profil (`BarreNavigation.Onglet`, sélection explicite).

> **iOS 0.36.1 — le widget du championnat n'est plus cliquable.** Plus de bouton
> « Pronostiquer » ni de lien : il annonce le Grand Prix et son échéance, rien d'autre. Le
> chemin vers les pronostics passe par l'accueil. Les avatars du classement sont des
> `PastilleProfil` — la photo si le membre en a une, l'initiale sur sa teinte sinon.


**Étape 4, statistiques.** **Une seule route pour les deux profils** : `GET /profils/{id}/stats`,
chargée par `Services/StatistiquesProfil.swift`, possédé par chaque écran (`@StateObject`),
rappelé à chaque apparition. **`GET /profils/moi` n'existe pas** (seul `PATCH /moi`) :
mon profil demande `/profils/{mon id}/stats`. Son identité **n'est pas relue par Railway** —
le profil lu en direct par `AuthViewModel` reste le propriétaire unique du compte connecté ;
la voiture et le numéro de l'onglet en sont recopiés (jamais par-dessus un réglage en cours).
La mise en forme des quatre tuiles a **un seul propriétaire**, `StatsProfil.tuiles`, pendant
de `GrilleStats.jsx` : avant le premier pronostic jugé, trois tuiles disent « – », la
quatrième dès que `cote_moy_tentee > 0`. `BlocStatistiques` porte le spinner, posé **sur la
grille provisoire** pour que rien ne saute, et `EchecChargement`. Le profil d'un membre
s'affiche d'abord de sa ligne de classement (meilleur coup compris), seules les stats font
un appel ; `gp_joues` remplit « Ses Grands Prix » (`0` ⇒ « Saison 2026 »). Profil illisible
au lancement ⇒ relu une fois, puis échec rejouable plutôt qu'un spinner sans fin.


**Étape 5, mise en œuvre (calendrier, GP suivant, échéance).** **Il n'existe pas de
`GET /gp`** : la liste statique ``GrandPrixSaison.saison2026`` est croisée avec
`GET /scraper/cotes` (publique) par `Services/CalendrierSaison.swift`, possédé par
`CalendrierView` et rappelé à chaque apparition. Les statuts en base sont `a_venir`,
`cotes_figees` et `termine` (contrainte `check`) — **pas d'`en_cours`** ; les quatre états
affichés en sont dérivés par `EtatGp.pour`, pendant d'`etatDuGpSaison` (absent de la base ⇒
« À venir », `date_course` passée ⇒ « Fermé », cotes présentes ⇒ « Pronos ouverts »). Le
rapprochement se fait par `SlugCircuit` (`Models/GrandPrix.swift`), désormais **seul
propriétaire** du slug — `ProchainGP.slug` y délègue. Les douze cartes s'affichent toujours :
pendant le premier chargement un spinner au-dessus de la liste, après un échec
`EchecChargement` au même endroit, et **aucune pastille tant que l'état est inconnu** — un
« À venir » par défaut mentirait sur un GP ouvert. Le défilement vers le prochain GP attend
les états. `GrandPrixSaison.gpId` (l'`id` réel, `nil` hors base) est transmis à
`DetailGPView` et à `ResultatsGPView` (`ResultatGPMock.gpId`) pour les étapes 6 et 7 ; fiches
circuit et séances restent statiques.
**Un seul calcul d'échéance** : `EcheancePronostics` (`Models/GrandPrix.swift`), pendant
d'`etatPronostics` + `cotesArretees` — deux phases, décompte « 2j 14h 32min » puis
« 32min 10s », `phrase` pour les surfaces à une ligne. Le widget d'un championnat
(`phrase`) et celui de l'accueil (deux cases, `TimelineView` à la seconde, aucune animation)
le lisent ; `ProchainGP.pronosticsOuverts` y délègue. `/championnats/moi` ne sert pas
`date_qualifications` : avant l'ouverture, le widget d'un championnat dit donc « Ouverture à
confirmer » (il disait « Course le … »). Le GP suivant de l'accueil est lu **directement**
dans `grands_prix` (`Services/ProchainGrandPrix.swift`, `a_venir`/`cotes_figees`, départ
croissant, inconnu en dernier), silhouette rouge de même hauteur pendant le chargement ;
aucun GP à venir ⇒ pas de widget (le repli web sur le dernier GP couru n'est pas repris).
Le widget ne mène aux cotes **que si `cotesArretees`**.

**Étape 6, classement de course.** `Services/ResultatsGrandPrix.swift`, possédé par
`ResultatsGPView` (`@StateObject`), appelle `GET /grands-prix/{id}/resultats` **sans**
`championnat_id` à chaque apparition ; `Models/ResultatsGP.swift` ne décode que
`disponible`, `recupere_le` et `classement` (champs à défaut Pydantic). **Ni pole ni meilleur
tour** : la route ne les sert pas, l'écran ne les affiche pas. Abandon, non-partant et
disqualifié donnent la mention de la ligne, `position` nulle un tiret. `disponible: false`,
classement vide, `404` ou `gp_id` nul ⇒ « Résultats non disponibles » (pas un échec, pas de
« Réessayer ») ; les autres erreurs passent par `EchecChargement`. Le nom OpenF1
(« Max VERSTAPPEN ») est coupé comme `couperLeNom` ; l'écurie OpenF1 → livrée par
`LivreeEcurie.duLibelle`, transcription de `ALIAS_ECURIES` — **à tenir avec le web**.
**« Mes résultats » n'est plus monté** (`SectionMesResultats`, code conservé) : il
attend la lecture directe de mes pronostics ; `ResultatGPMock` est supprimé.

**Étape 7, pronostics.** `EtapePronos` porte un `GrandPrixPronos` (`id`, nom, slug,
sous-titre) ; l'accueil et le widget d'un championnat y mettent l'`id` réel. Un seul
chargeur, `Services/DonneesPronostics.swift`, possédé par chaque écran (`@StateObject`,
rappelé à chaque apparition) : `GET /grands-prix/{id}/cotes` + `GET …/favoris`, et pour la
saisie **mes pronostics lus en direct** (`pronostics` + `pronostic_podium`, sous RLS) —
premier échec l'emporte, spinner puis `EchecChargement`. `Models/Pronostics.swift` porte
les modèles, ``ClePilote`` (exclusion croisée par libellé) et ``OrdreMarches``,
transcription d'`ORDRE_MARCHES` — **à tenir avec le web**. Le tableau des cotes montre
**tous les marchés** (aplat `secondaire` pour les bonus) ; l'étoile bascule un **favori
serveur**, en optimiste avec retour arrière et `ErreurEnLigne`, **sans plafond**. La saisie
se préremplit **une seule fois** ; les bonus se choisissent parmi les favoris encore
épinglés (3 au maximum). Le bouton reste actif : fermeture (`EcheancePronostics.ferme`),
vainqueur manquant, podium incomplet et conflit sont dits au-dessus de lui, puis
`POST …/pronostics` ; un `423` affiche le message du serveur. **Le récapitulatif n'est
empilé qu'après le `200`** (`avancer`, passé par `etapesPronos`), avec la grille envoyée ;
`BlocEcheance` lit `EcheancePronostics` (`TimelineView` à la seconde). `GrilleMock`,
`PariBonus` et `EcheanceMock` sont supprimés ; il reste `GrillePilotes`, la table
pilote → écurie.
**Porte d'entrée** (iOS 0.32.0) : les widgets empilent `EtapePronos.entree`, et
`EntreePronosView` choisit le premier écran — **récapitulatif** si vainqueur et podium sont
déjà en base (`GrilleEnregistree(relue:)`, mêmes rapprochements que le préremplissage),
**tableau des cotes** sinon. Le choix est figé au premier chargement ; le récapitulatif se
relit à chaque retour. Ouvert d'entrée, son « Modifier mes pronos » empile `.cotes` puis la
saisie ; après un `200`, il ferme l'écran comme avant. Le chargeur est passé à `CotesView`.
**Accordéon des cotes** (iOS 0.35.0) : dans `CotesView`, chaque marché Unibet est une
section dépliante. L'en-tête coloré (libellé, pastille du nombre de favoris, chevron) se
touche ; la grille de ses cotes se déplie dessous. **Un seul marché ouvert**, aucun à
l'arrivée. `Mouvement.accordeonOuverture` / `accordeonFermeture` (240 / 170 ms, courbe
d'entrée), chevron pivoté à 90°, rien d'animé sous mouvement réduit.
---

## 8. Références

| Besoin | Document |
|---|---|
| Deux chemins de données, CORS, journalisation, schedulers | [`architecture.md`](architecture.md) |
| Tables, RLS, fonctions, triggers, migrations | [`database.md`](database.md) |
| Points, pronostics, calendrier, validation, départage | [`metier.md`](metier.md) |
| Vocabulaire canonique | [`glossary.md`](glossary.md) |
| Palette, typographie, formes, contraste, mouvement | [`design-system.md`](design-system.md) |
| Unibet, OpenF1, calcul des points, rattrapage | [`scraper.md`](scraper.md) |
| Composants, planches SVG, modules `lib/` | [`composants.md`](composants.md) |
| Les deux calendriers, les quatre états | [`calendrier.md`](calendrier.md) |
| Onze écuries, grille 2026, couleurs, livrées | [`ecuries.md`](ecuries.md) |
| **Symptôme, cause réelle, correctif** | [`bugs-connus.md`](bugs-connus.md) |
| Pourquoi les choix ont été faits | [`decisions.md`](decisions.md) |

**Avant de coder un écran**, ouvrir la maquette correspondante dans `maquettes/` (16 écrans
HTML autonomes). *Elles emploient encore les termes interdits du §6.8 : elles ont tort.*
