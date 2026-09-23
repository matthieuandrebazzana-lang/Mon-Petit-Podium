# Audit — données mockées vs API réelles (iOS)

> Photographie de l'app iOS **0.19.0** avant le branchement réseau. Rien n'est encore branché :
> ce fichier sert à **valider l'ordre** avant de commencer. Les contrats d'API cités sont
> ceux de `docs/swift-app.md` §3, qui fait foi.
>
> Légende de la colonne **Source** : **API** = FastAPI sur Railway (jeton Supabase en
> `Bearer`) · **SB** = lecture directe Supabase sous RLS (`supabase-swift`) · **Storage** =
> dépôt direct dans Supabase Storage · **Statique** = reste dans l'app, ne vient pas du réseau.

---

## 1. Ce qui existe déjà

| Élément | État |
|---|---|
| `SupabaseManager` | Client unique, `jetonAcces()` relu à chaque appel, `requeteAPI(_:methode:)` qui pose le `Bearer`. **Rien ne décode une réponse** : pas de `JSONDecoder`, pas de gestion d'erreur |
| `AuthViewModel` | Connexion, inscription, déconnexion, session au lancement — **réels**. Le pseudo et la photo viennent des **métadonnées du jeton**, pas de la table `profils` |
| `Models/` | **Vide.** Aucun type `Codable` |
| `ConnexionView` | `TODO` sur la réinitialisation du mot de passe (`docs/swift-app.md` §2.8) — hors périmètre données, cité pour mémoire |

---

## 2. Inventaire vue par vue

### Accueil — `Views/Accueil/AccueilView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| GP suivant (nom, slug, date, heure, échéance) | `GrandPrixMock` en dur (Azerbaïdjan, « 4j 14h 48min ») | **SB** `grands_prix` · `in(statut, [a_venir, cotes_figees])` · `order(date_course, nullsFirst: false)` · `limit(1)` — repli d'intersaison : dernier GP couru (`resultats_gp!inner`). Lecture **directe** : c'est le premier écran, il ne doit pas attendre le réveil de Railway (§3.9) |
| Échéance « Ouverture / Fermeture dans » | Texte figé | **Calculée** depuis `date_qualifications` / `date_course` (§6.4, §7.4) |
| Destination du widget (Cotes, Récap ou Résultats) | Toujours `EtapePronos.cotes` | **SB** `pronostics` · `select(gp_id)` · `eq(profil_id)` → « déjà pronostiqué » ; `statut` du GP → résultats |
| Cartes championnats (nom, membres, rang, jauge) | `ChampionnatMock` × 2 | **API** `GET /championnats/moi` — `nombre_membres`, `position.mon_rang`, `mes_points / points_leader` |
| « 12 Grands Prix restants » | Constante `grandsPrixRestants = 12` | **À trancher** : constante (choix actuel, aligné sur le web) ou **SB** `count` sur `grands_prix` — possible depuis la migration 19, qui a peuplé les 12 GP |
| Pseudo de la salutation | `AuthViewModel.pseudo` (métadonnées) | **SB** `profils` · `select(pseudo, avatar_url)` — les métadonnées sont figées à l'inscription |

### Championnats — `Views/Championnats/ChampionnatsView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Liste des championnats | `ChampionnatMock` × 3 | **API** `GET /championnats/moi` (même appel que l'accueil — un seul propriétaire à prévoir) |
| « 12 Grands Prix restants » | Constante | Même décision que l'accueil |
| Photo de championnat | `photo: nil` partout | `photo_url` de `GET /championnats/moi` |

### Détail d'un championnat — `Views/Championnats/ChampionnatDetailView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Classement | `MembreMock.exemples` tronqué à l'effectif | **API** `GET /championnats/{id}/classement` — déjà trié et rangé, livrée et avatar inclus |
| Widget GP suivant | `"GP Pays-Bas"`, `"Fermeture dans 3 jours"` en dur (l. 167) | Le `prochain_gp` de `GET /championnats/moi` + échéance calculée |
| Menu « ⋯ » (partager le code, quitter) | Bouton vide | `code_invitation` de `GET /championnats/moi` · **API** `DELETE /championnats/{id}/quitter` |
| Statistiques transmises au profil membre (`reussis`, `tentes`, `meilleurCoup`, `moyenneTentee`) | Calculées depuis `MembreMock` | **API** `GET /profils/{id}/stats` — **ne plus les dériver du classement** : le serveur les calcule |

### Vue piste — `Views/Championnats/VuePisteView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Membres, points, livrées, numéros | `[MembreMock]` reçu du détail | Le **même** tableau que le classement (`GET /championnats/{id}/classement`) : aucun appel propre, la piste le reçoit de son parent |

### Créer un championnat — `Views/Championnats/CreerChampionnatView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Création | Alerte « Championnat créé ! » | **API** `POST /championnats` `{ nom }` → `201` avec `code_invitation` |
| Photo | Chargée et contrôlée (2 Mo), jamais envoyée | **Storage** `championnats/{id}/photo.jpg` (après création, id obtenu) puis **API** `PATCH /championnats/{id}` `{ photo_url }` — son échec n'annule pas la création |
| Arrivée | Rien | Navigation vers le détail du championnat créé, liste `/moi` invalidée |

### Rejoindre un championnat — `Views/Championnats/RejoindreChampionnatView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Adhésion | Alerte « Championnat rejoint ! » | **API** `POST /championnats/rejoindre` `{ code }` — `404` code inconnu, `409` déjà membre, messages français affichables tels quels |

### Calendrier — `Views/Calendrier/CalendrierView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Les 12 GP (pays, circuit, jour, mois) | `GrandPrixSaisonMock` en dur | **Statique — reste statique** (`docs/calendrier.md` §1 : la base ne porte ni pays, ni circuit, ni drapeau) |
| État de chaque GP (`etat: .termine` en dur) | Écrit à la main | **Calculé** : liste statique **croisée** avec **API** `GET /scraper/cotes` (publique) — `id`, `statut`, cotes présentes, `date_qualifications`. Pendant de `etatDuGpSaison` côté web |
| Identifiant du GP | **Absent** (seul le slug existe) | `id` de `GET /scraper/cotes`, rattaché par le nom du GP. **Bloquant pour tout le reste** : résultats, cotes et pronostics sont indexés par `gp_id` |

> Les 12 cartes s'affichent **quoi qu'il arrive** (`docs/calendrier.md` §1) : l'échec de
> l'appel fait perdre les états, jamais la liste.

### Détail d'un GP — `Views/Calendrier/DetailGPView.swift` + `FichesGrandPrix.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Séances EL1–EL3, sprint | `FichesGrandPrix.horaires` | **Statique** (transcription de `GP_2026.seances`) |
| Heures des qualifications et de la course | Idem, en dur | **Base** : `date_qualifications` / `date_course` du GP (règle `seancesDuGp`) |
| Fiche circuit, derniers vainqueurs | `FichesGrandPrix.circuits` | **Statique** (transcription de `CIRCUITS`) — ne change pas |
| Bouton « Voir les cotes » | Absent | À poser quand le GP a des cotes arrêtées (même croisement que le calendrier) |

### Résultats d'un GP — `Views/Resultats/ResultatsGPView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Classement de la course | `ResultatGPMock.gpEspagne`, **le même pour les 3 GP courus** | **API** `GET /grands-prix/{id}/resultats` (publique sans `championnat_id`) — `disponible: false` ⇒ « résultats en attente », jamais un classement vide |
| Prénom / nom séparés, écurie, slug de livrée | Écrits à la main | `pilote` (full_name OpenF1, nom en capitales) + `equipe` à découper et rattacher à `LivreeEcurie` côté client |
| Mes pronostics et leurs points | `PronosticJoueMock` | **SB** `pronostics` · `select(id, type, id_outcome_unibet, points_gagnes, pronostic_podium(...))` + `cotes` pour pilote / marché / points — `points_gagnes: nil` ≠ `0` |
| Section « membres du championnat » (3ᵉ section web) | Absente | **API** même route **avec** `?championnat_id=` → champ `membres`. Seulement quand on arrive depuis un championnat |

### Cotes — `Views/Pronos/CotesView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Grille des pilotes et leurs points | `GrilleMock.pilotes` (22 pilotes, écurie en dur) | **API** `GET /grands-prix/{id}/cotes` (publique) — `marches[].cotes[]` avec `pilote`, `points`, `id` (= `id_outcome_unibet`) |
| Marchés | `MarcheCote` : **deux cas seulement** (vainqueur, podium) | Les marchés **découverts par le scraper** (`marche` slug + `libelle` Unibet) — le modèle doit devenir dynamique pour les bonus ; vainqueur et podium gardent leur habillage |
| Écurie d'un pilote | Champ du mock | Non servie par l'API : table pilote → écurie côté client (pendant de `lib/ecuries.js`) |
| Paris bonus « mis de côté » | `@State parisBonus` local | **API** `POST /grands-prix/{id}/favoris` (bascule) + `GET /grands-prix/{id}/favoris`. **Écart de modèle** : le serveur exige que les bonus soient **parmi les favoris** — le panier local doit devenir les favoris serveur |
| Mode admin (« Prévisualisation ») | `modeAdmin = false` | **SB** `profils.is_admin` — jamais depuis le jeton ni un cache (§3.9) |

### Saisie des pronos — `Views/Pronos/PronosView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Pilotes proposés | `GrilleMock.pilotes` | Marchés `vainqueur` et `podium` de `GET /grands-prix/{id}/cotes` |
| Compte à rebours | `EcheanceMock` : « 04 / 14 / 34 » figé | **Calculé** depuis la fermeture (§6.4) — un seul propriétaire pour saisie et récap |
| Validation | Alerte | **API** `POST /grands-prix/{id}/pronostics` `{ vainqueur, podium, bonus }` en `id_outcome_unibet` — gérer le `423` (course partie) même quand le client croyait le GP ouvert |
| Saisie existante (modification) | Toujours vide | **SB** mes pronostics du GP (pré-remplissage) |

### Récapitulatif — `Views/Pronos/RecapView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Grille validée | Transmise par `PronosView`, rien n'est enregistré | Réponse `200` de `POST /pronostics` (le jeu enregistré), ou **SB** mes pronostics à l'ouverture directe |
| Bandeau « Pronos enregistrés ! » | Annonce un enregistrement qui n'a pas eu lieu | Affiché **seulement** après un `200` |
| Compte à rebours | `EcheanceMock` | Même calcul que la saisie |

> **`EtapePronos` ne transporte pas l'identifiant du GP** (`nom`, `slug`, `sousTitre`
> seulement). Les trois écrans du parcours en ont besoin : c'est le premier changement de
> structure du bloc pronostics.

### Mon profil — `Views/Profil/ProfilView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Quatre statistiques | `StatistiqueProfil` en dur (33 %, 31, 25, 46) | **API** `GET /profils/{mon id}/stats` — masquer tant que `pronostics_notes == 0` |
| Livrée, couleurs, numéro | `Livree(#CC0000, #003087…)`, `"33"` en dur | **API** `GET /profils/{mon id}` |
| « Enregistrer ma voiture » | Recopie l'état local | **API** `PATCH /profils/moi` — `couleur_texte` seulement si choisie, `retirer_numero` explicite (§3.2, six règles) |
| Photo : changer / supprimer | Lecture des métadonnées, aucune écriture | **Storage** `avatars/{mon id}/avatar.jpg` + `PATCH /profils/moi` `{ avatar_url }` ou `{ retirer_avatar: true }` |
| Section Administration | `estAdmin = false` | **SB** `profils.is_admin` (échec ⇒ `false`) · actions **API** `POST /admin/action` |

### Profil d'un membre — `Views/Profil/ProfilMembreView.swift`

| Donnée mockée | Aujourd'hui | Source réelle |
|---|---|---|
| Identité, livrée, photo | `MembreProfil` construit depuis `MembreMock` | La ligne du classement suffit pour l'en-tête ; **API** `GET /profils/{id}` si l'écran est ouvert ailleurs |
| Quatre statistiques, GP joués | Calculées depuis le mock | **API** `GET /profils/{id}/stats` (`403` si aucun championnat partagé) |
| « Ses Grands Prix » | `SesGrandsPrixView` provisoire | **SB** `pronostics` → `grands_prix` → `cotes` en une passe (pendant de `GrandsPrixDuMembre.jsx`) |

### Ce qui reste statique — **ne pas brancher**

`FichesGrandPrix` (séances hors qualifs/course, circuits, palmarès) · la liste des 12 GP du
calendrier · `NationalitesPilotes` · `DrapeauxGP` (généré) · `LivreeEcurie` · la table
pilote → écurie. Ce sont des actifs du client, pas des données de la base.

---

## 3. Ordre d'implémentation proposé

Chaque étape ne dépend que des précédentes. La flèche dit ce qu'une étape **débloque**.

### Étape 0 — Fondations *(ne montre rien, débloque tout)*

1. **Couche réseau** : décodage JSON (dates ISO 8601 avec fuseau), grammaire d'erreurs
   `DetailErreur` (§3.0 : chaîne française affichable ou liste Pydantic jamais affichée),
   `401` ⇒ reconnexion (§7.3), `502/503/504` ⇒ « Connexion au serveur en cours… » +
   nouvel essai (cold start Railway).
2. **`GET /health` au lancement**, sans attendre la réponse — ping de réveil.
3. **Modèles `Codable`** dans `Models/` : `Championnat`, `LigneClassement`, `ProfilServi`,
   `StatsProfil`, `GrandPrixServi` (+ marchés, cotes), `PronosticServi`, `ResultatsServis`,
   `FavoriServi`. Tous les champs documentés nullables le sont (`cree_par`, `prochain_gp`,
   `position`, `meilleure_cote`, `date_course`…).
4. **Profil courant** : lecture **SB** de `profils` (pseudo, photo, `is_admin`) dans
   `AuthViewModel`, à la place des métadonnées du jeton.

→ débloque les étapes 1 à 6.

### Étape 1 — Mes championnats *(le cœur de l'app)*

`GET /championnats/moi`, **un seul propriétaire** partagé par l'accueil et l'onglet
Championnats. Remplace `ChampionnatMock` (l'`id` devient un UUID : la teinte Pantone, tirée
de l'id, changera une fois — attendu).

→ débloque 2 et 3.

### Étape 2 — Créer et rejoindre

`POST /championnats`, `POST /championnats/rejoindre`, puis la photo (Storage + `PATCH`).
Navigation vers le championnat obtenu, liste de l'étape 1 invalidée.

→ permet de fabriquer de vrais jeux d'essai pour la suite.

### Étape 3 — Détail d'un championnat et vue piste

`GET /championnats/{id}/classement` remplace `MembreMock` ; la piste reçoit le même
tableau. Menu « ⋯ » : partager le code, `DELETE …/quitter`. Widget GP suivant : le
`prochain_gp` de l'étape 1.

→ débloque 4.

### Étape 4 — Profils

`GET /profils/{id}` + `GET /profils/{id}/stats` pour le profil d'un membre **et** le mien ;
puis les écritures de Mon profil (`PATCH /profils/moi`, avatar en Storage) et la section
Administration (`is_admin` en direct, `POST /admin/action`). « Ses Grands Prix » en dernier.

### Étape 5 — Calendrier et GP suivant *(débloque tout le bloc course)*

1. `GET /scraper/cotes` croisé avec la liste statique : états réels et **`gp_id`** pour
   chaque carte.
2. GP suivant de l'accueil en lecture **SB** directe.
3. **Calcul d'échéance unique** (ouverture / fermeture, §6.4, heures en local §7.4) — il
   remplace `EcheanceMock` et les textes en dur de l'accueil et du détail championnat.
4. Détail GP : heures de qualifs et de course depuis la base.

→ débloque 6 et 7 (les deux exigent un `gp_id`).

### Étape 6 — Résultats d'un GP

`GET /grands-prix/{id}/resultats` + mes pronostics en **SB**. Puis la 3ᵉ section
(`?championnat_id=`) quand on arrive depuis un championnat.

### Étape 7 — Parcours de pronostics *(le plus lourd, en dernier)*

1. `EtapePronos` porte le `gp_id`.
2. `GET /grands-prix/{id}/cotes` remplace `GrilleMock` ; `MarcheCote` s'ouvre aux marchés
   découverts pour les bonus.
3. Paris bonus = **favoris serveur** (`POST`/`GET …/favoris`) au lieu du panier local.
4. `POST /grands-prix/{id}/pronostics` avec gestion du `423` ; récap alimenté par la
   réponse ; pré-remplissage depuis mes pronostics existants.
5. Destination du widget de l'accueil (Cotes / Récap / Résultats) selon « déjà
   pronostiqué ».

### Pourquoi cet ordre

- **Championnats avant GP** : ce sont les écrans les plus vus, et ils ne dépendent que
  d'une route. Ils valident la couche réseau sur un cas simple avant les cas à règles.
- **Calendrier avant résultats et pronos** : c'est lui qui fournit le `gp_id`. Sans lui,
  aucun écran de course ne sait quel GP demander.
- **Pronostics en dernier** : trois écrans, deux changements de modèle (marchés dynamiques,
  bonus = favoris), le `423` et le calcul d'échéance. C'est là que les écarts entre le
  mock et le contrat serveur sont les plus grands.

---

## 4. Points à trancher avant de commencer

1. **« 12 Grands Prix restants »** : garder la constante ou compter en base (possible depuis
   la migration 19) ?
2. **Cache** : garder les réponses en mémoire le temps de la session (accueil ⇄ onglet
   Championnats sans nouvel appel), ou recharger à chaque apparition ?
3. **Hors ligne** (`docs/swift-app.md` §7.2) : dans le périmètre de ce chantier ou après ?
