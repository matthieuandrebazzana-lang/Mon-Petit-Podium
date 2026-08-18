# CLAUDE.md — Mon Petit Podium

> Contexte permanent du projet. À lire **en premier** à chaque session.
> Le nom de l'app est temporaire et susceptible de changer.

---

## 1. Vue d'ensemble

**Mon Petit Podium** est une PWA de pronostics Formule 1 entre amis, sur le modèle de "Mon Petit Prono" appliqué à la F1.

Un utilisateur crée un **championnat**, partage un code d'invitation à 6 caractères, et ses amis le rejoignent. Avant chaque Grand Prix, chaque membre fait ses pronostics. Les points rapportés dépendent des **cotes réelles des bookmakers** : plus un pronostic est improbable, plus il rapporte. Après la course, les résultats sont récupérés automatiquement et les points attribués. Un classement se construit tout au long de la saison.

L'app est **ouverte au public**, pas seulement à un cercle d'amis. L'authentification et la sécurité doivent être traitées en conséquence.

### Vocabulaire imposé dans toute l'interface

| Utiliser | Ne jamais utiliser |
|---|---|
| **championnat** | ligue |
| **calendrier** | historique |

---

## 2. Architecture technique

| Couche | Techno | Hébergement |
|---|---|---|
| Frontend | React + Vite + Tailwind CSS (PWA) | Vercel |
| Backend | FastAPI (Python) | Railway |
| Base de données | PostgreSQL | Supabase |
| Authentification | Supabase Auth | Supabase |

**Supabase** gère l'authentification (email + mot de passe, Google, Apple) et stocke toutes les données.
**Railway / FastAPI** exécute le scraping des cotes Unibet, la récupération des résultats OpenF1 et le calcul des points. Il porte aussi les cron jobs.
**Vercel / React** sert l'interface, installable sur iPhone via Safari.

Le **schéma de base de données** et le **nommage des routes** ne sont pas imposés : à concevoir de façon cohérente en respectant les règles métier de la section 4.

---

## 3. Sources de données

### 3.1 Cotes — scraping Unibet

Les cotes F1 d'Unibet sont accessibles via des endpoints JSON non documentés, **sans authentification** et **sans cookie obligatoire**.

**Endpoint des cotes d'un GP :**
```
https://www.unibet.fr/lvs-api/next/50/{id_gp}?lineId=1&originId=2&breakdownEventsIntoDays=true&showPromotions=true&pageIndex=0
```

**ID racine de la section Formule 1 :** `p59209509` — parent de tous les GP. Interroger ce nœud retourne la liste des GP actuellement disponibles.

**Structure de la réponse.** Tout se trouve dans un objet `items` dont les clés portent un préfixe indiquant le type :

| Préfixe | Type | Champs utiles |
|---|---|---|
| `p...` | Championnat / GP | `desc`, `parent` |
| `e...` | Événement (Course) | `desc`, `start`, `parent` |
| `m...` | Marché de pari | `desc` (ex : "Vainqueur"), `parent` |
| `o...` | Issue / cote | `desc` (nom du pilote), `price` (la cote), `parent` |

La hiérarchie se reconstruit via le champ `parent` : une cote pointe vers son marché, qui pointe vers son événement, qui pointe vers son GP.

**Point critique :** Unibet n'affiche que le **GP suivant**, jamais toute la saison. Le scraper ne doit jamais s'appuyer sur une liste de GP codée en dur. Il interroge le nœud racine, découvre ce qui est disponible, et traite ce qu'il trouve.

**Les marchés varient d'un GP à l'autre.** Le noyau (vainqueur, podium, top 6, top 10, duels, écurie gagnante) est presque toujours présent, mais les marchés spéciaux (safety car, drapeau rouge, abandons) apparaissent selon le circuit et le contexte. Le scraper doit découvrir les marchés dynamiquement, jamais les supposer.

### 3.2 Résultats — OpenF1

API gratuite, sans clé, testée et fonctionnelle : `https://api.openf1.org/v1/`

| Endpoint | Usage |
|---|---|
| `/session_result` | Résultats officiels de la course — source principale |
| `/race_control` | Safety car, drapeau rouge, incidents |
| `/laps` | Meilleur tour en course |
| `/drivers` | Correspondance pilote → écurie |
| `/starting_grid` | Pole position |

**Exemple de réponse `session_result` :**
```json
{
  "position": 1, "driver_number": 1, "number_of_laps": 70,
  "points": 25, "dnf": false, "dns": false, "dsq": false,
  "duration": 5996.18, "gap_to_leader": 0,
  "meeting_key": 1291, "session_key": 11342
}
```

**Pièges de parsing — à traiter impérativement :**

1. **Les pilotes abandonnés ont `position: null`**, pas une position numérique. Ne jamais supposer qu'une position existe pour tous les pilotes. Toujours filtrer sur le champ `dnf`.

2. **`gap_to_leader` est de type mixte** : un nombre (`15.08`) pour les pilotes dans le tour du leader, une chaîne (`"+1 LAP"`, `"+2 LAPS"`) pour les pilotes doublés, `null` pour le leader. Le parsing doit gérer les trois cas.

3. **Le champ `points`** contient les points championnat officiels FIA (25, 18, 15…). Pratique pour détecter si un pilote a marqué (`points > 0`), et réutilisable pour afficher le vrai classement pilotes.

4. **`country_code` de l'endpoint `/drivers` est déprécié** et disparaîtra fin 2026. Pour les marchés liés à la nationalité, maintenir une table statique pilote → nationalité dans le projet.

---

## 4. Règles métier

### 4.1 Le système de points — règle centrale

> **Les points valent la cote Unibet multipliée par 100, arrondie à l'entier.**
> Une cote de 2,80 rapporte **280 points**. Une cote de 9,50 rapporte **950 points**.

**Conséquence sur toute l'interface : on n'affiche jamais une cote brute à l'utilisateur.** Nulle part on n'écrit "×2,80" ou "cote 2,80" — on écrit toujours "280 pts". Sans exception : tableau des cotes, saisie des pronostics, récapitulatif, résultats, profils, statistiques, calendrier. Y compris pour une statistique comme la cote moyenne tentée, qui s'affiche "310" et non "×3,1".

Un pronostic raté rapporte 0 point. Il n'y a pas de points négatifs.

### 4.2 Structure d'un pronostic

Pour chaque Grand Prix, un joueur remplit :

- **2 pronostics obligatoires** : le vainqueur, et le podium (2 pilotes à placer)
- **3 pronostics bonus** au choix, sélectionnés parmi ses favoris

Le joueur explore les cotes disponibles, met en favori celles qui l'intéressent, puis choisit ses 3 bonus dans cette sélection.

### 4.3 Calendrier d'un week-end de course

| Moment | Ce qui se passe |
|---|---|
| **Samedi, 2h après les qualifications** | Scraping des cotes Unibet. Les pénalités sont confirmées, la grille est définitive. **Les cotes sont figées** et ne bougent plus. |
| Samedi soir → dimanche | Les joueurs pronostiquent et modifient librement. Les pronostics sont **visibles par les autres membres dès leur saisie**. |
| **Dimanche, 5 min avant le départ** | Fermeture des pronostics. Plus aucune modification possible. |
| **Dimanche, 1h30 après le départ** | Démarrage du job de résultats : appel de `/session_result` toutes les 5 minutes jusqu'à obtenir des données, puis calcul et attribution des points. |

Figer les cotes juste après les qualifications garantit que **tous les joueurs pronostiquent avec exactement les mêmes cotes**, sur une grille déjà définitive.

### 4.4 Validation des pronostics

Tous les marchés se valident automatiquement, sans intervention humaine.

**Via `session_result` :** vainqueur (`position == 1`), podium (`position <= 3`), top 6 et top 10, duels entre pilotes, écurie gagnante, double podium d'écurie, les deux pilotes dans les points, abandon d'un pilote (`dnf == true`), nombre de voitures classées, dernier classé, marge de victoire, classement exact, trio gagnant, pilote le mieux classé d'un groupe.

**Via `race_control` :** safety car et drapeau rouge.

**Via `laps` :** meilleur tour, minimum de `lap_duration`.

**Cas particuliers nécessitant une règle explicite :**

- **Safety Car vs Virtual Safety Car** — les deux remontent avec `category=SafetyCar`. Seul le contenu du champ `message` les distingue ("VIRTUAL SAFETY CAR" ou "SAFETY CAR"). C'est le seul point du système qui repose sur du parsing de texte : le traiter avec soin et journaliser les messages non reconnus.

- **Premier abandon** — `session_result` ne donne pas l'heure de l'abandon mais donne `number_of_laps`. Le pilote abandonné avec le moins de tours a abandonné en premier. Gérer le cas d'égalité.

- **Duel entre pilotes avec abandon** — un pilote classé bat toujours un pilote abandonné. Si les deux abandonnent, celui qui a parcouru le plus de tours l'emporte.

### 4.5 Championnats

- Code d'invitation : **6 caractères alphanumériques, sans tiret ni séparateur** (ex : `F1X7K2`)
- **Aucune limite** de membres
- Un utilisateur peut appartenir à plusieurs championnats simultanément

### 4.6 Départage des égalités au classement

Dans l'ordre :

1. Le plus grand **nombre de pronostics réussis**
2. La **meilleure cote réussie** (le plus gros coup)
3. L'**ordre d'inscription** au championnat

### 4.7 Grand Prix annulé ou reporté

Les pronostics enregistrés sont **effacés**. Aucun point n'est attribué. Si le GP est reporté, les joueurs refont leurs pronostics pour la nouvelle date, avec de nouvelles cotes scrapées selon le calendrier normal.

---

## 5. Design system

### Inspiration

Style **widget** : blocs autonomes très arrondis, beaucoup d'espace, aplats de couleur pleins, aucune bordure fine. Chaque section de contenu est un bloc indépendant, jamais une liste plate posée sur le fond.

### Couleurs

| Rôle | Hex |
|---|---|
| Fond de l'app | `#F5F0EB` |
| Principal (rouge profond) | `#800111` |
| Principal foncé | `#5A000C` |
| Secondaire (marron) | `#543925` |
| Accent (amber) | `#E8A020` |
| Texte | `#1A1A1A` |
| Texte secondaire | `#999999` |
| Surfaces / cartes | `#FFFFFF` |

### Typographie

**Helvetica Neue** partout, graisses 400 et 500 uniquement (700 réservé aux numéros de voiture).

- Titres de page : 28–30px, graisse 500
- Grands chiffres (scores, statistiques) : 32–44px, graisse 500
- Corps de texte : 14–15px
- Labels de section : 10–11px, majuscules, `letter-spacing` ≈ 0,7px, couleur `#999`

### Formes et espacements

- Blocs principaux : `border-radius: 24px`
- Blocs secondaires et cartes : `border-radius: 18-20px`
- Champs de saisie et petits éléments : `border-radius: 14px`
- Espacement entre blocs : 12px
- Padding intérieur des blocs : 16–20px

### Voiture personnalisable

Chaque utilisateur possède **une seule voiture**, identique dans tous ses championnats :

- **2 couleurs** au choix (principale et secondaire)
- Un **numéro libre**
- Son **nom affiché sur l'aileron arrière**

Modifiable à tout moment depuis le profil.

### Navigation

Barre de navigation basse à 4 onglets : **Accueil**, **Championnats**, **Calendrier**, **Profil**.

### Skills de design installés — règle de priorité

Trois skills sont installés sur ce projet : **Apple Design**, **Taste** et **Transitions.dev**.

> **Règle de priorité pour le chantier design en cours** : les skills `/apple-design`, `/design-taste-frontend` et `/transitions-dev` ont la main sur les **compositions, espacements, ombres, matériaux, animations et hiérarchie visuelle**. Le design system de la section 5 reste la référence pour la **palette de couleurs et la typographie uniquement**. Claude Code applique les suggestions des skills **sans demander de validation ni signaler de conflit** — il tranche seul en faveur des skills sur tout ce qui n'est pas couleur ou typographie.

**`/apple-design` doit être invoqué sur chaque écran codé, sans exception.** Son périmètre : les principes iOS — zones sûres, élévation, matériaux, animations fluides de facture native, hiérarchie visuelle, gestes, home indicator.

**Taste** intervient comme directeur artistique sur la hiérarchie visuelle, le rythme des espacements, la qualité des micro-détails, l'équilibre des compositions et le choix des proportions. Il ne propose jamais une autre palette ni une autre typographie — c'est la seule borne.

**Transitions.dev** intervient sur le mouvement : transitions d'écran, apparition des blocs, changements d'onglet, états de chargement, retours tactiles.

Ordre d'invocation avant de coder un écran : **`/apple-design`, puis `/design-taste-frontend`, puis `/transitions-dev`.**

Les rayons de coins, l'échelle des espacements et l'esprit widget de la section 5 sont désormais des **valeurs par défaut**, pas des contraintes : les skills peuvent s'en écarter quand la composition le demande. Seules la palette et la typographie ne bougent pas.

---

## 6. Ressources du projet

### `/maquettes/`

Les écrans de la v1, en fichiers HTML autonomes avec SVG intégrés.

> **Règle : avant de coder un écran, ouvrir et lire la maquette correspondante.**

| Fichier | Écran |
|---|---|
| `maquette-01-landing.html` | Page d'accueil publique |
| `maquette-02-inscription.html` | Inscription |
| `maquette-03-connexion.html` | Connexion |
| `maquette-04-accueil.html` | Accueil connecté — prochain GP et mes championnats |
| `maquette-05-creer-championnat.html` | Création d'un championnat |
| `maquette-06-rejoindre-championnat.html` | Rejoindre via code |
| `maquette-07-championnat.html` | Championnat — vue classement |
| `maquette-07b-piste.html` | Championnat — vue piste |
| `maquette-08-cotes.html` | Tableau des cotes et favoris |
| `maquette-09-pronos.html` | Saisie et modification des pronostics |
| `maquette-10-recap.html` | Récapitulatif après validation |
| `maquette-11-resultats-gp.html` | Résultats d'un GP terminé |
| `maquette-12-profil-membre.html` | Profil d'un autre membre |
| `maquette-13-resume-gp-profil.html` | Détail d'un GP depuis un profil |
| `maquette-14-mon-profil.html` | Mon profil et personnalisation |
| `maquette-15-historique.html` | Calendrier du championnat, GP par GP |

Les maquettes définissent la **structure et la hiérarchie de l'information**. Pour le style précis, c'est la section 5 qui fait foi.

### `/assets/`

**`voiture.svg`** — la voiture vue du dessus. À transformer en composant React acceptant les props `couleur1`, `couleur2`, `numero`, `nom`. Les couleurs sont actuellement codées en dur dans le fichier : les remplacer par des valeurs dynamiques. Utilisé dans la vue piste, les profils et les cartes de membres.

**`gp-cards.svg`** — planche contenant les tracés de circuits. En extraire chaque tracé pour illustrer les cartes de Grand Prix dans les profils et le calendrier.

### La vue piste

Écran signature de l'app, à soigner particulièrement. Une route occupe **toute la largeur de l'écran** : asphalte sombre, bordures rouge et blanc sur les deux côtés, ligne pointillée centrale. Aucun fond beige visible. Les voitures des membres sont réparties verticalement selon leur nombre de points — le leader près de la ligne d'arrivée en damier tout en haut, le dernier en bas. Les scores s'affichent en légende sur la droite, alignés avec chaque voiture.

---

## 7. Ordre de développement

1. **Fondations** — scaffold React + Vite + Tailwind, connexion Supabase, configuration PWA
2. **Authentification** — inscription, connexion, Google et Apple, sessions
3. **Championnats** — création, code d'invitation, adhésion, liste des membres
4. **Scraper Unibet** — découverte des GP, extraction des marchés et cotes, stockage
5. **Pronostics** — tableau des cotes, favoris, saisie, modification, récapitulatif
6. **Résultats OpenF1** — récupération, validation des pronostics, calcul des points
7. **Classements** — vue liste et vue piste, calendrier du championnat
8. **Profils** — statistiques, personnalisation de la voiture, cartes de GP
9. **Finitions** — états de chargement, gestion d'erreurs, tests sur iPhone réel

Chaque étape doit être testée avant de passer à la suivante. Ne jamais déployer un backend non testé localement.

---

## 8. Règles permanentes

### Numéro de version

À chaque commit qui modifie l'application, **incrémenter le numéro de version affiché dans l'interface** (en bas de l'écran d'accueil). Cela permet de vérifier visuellement qu'un déploiement Vercel a bien pris en compte les changements.

### Mise à jour de ce fichier

Après chaque tâche terminée, **mettre à jour la section « État d'avancement »** ci-dessous : ajouter ce qui vient d'être implémenté, retirer les bugs corrigés. Cette mise à jour doit être **dans le même commit que le code**, jamais dans un commit séparé.

### Git

- **Ne jamais ajouter de ligne `Co-Authored-By: Claude`** dans les commits. Vercel bloque les déploiements automatiques sur le plan Hobby lorsqu'un collaborateur externe est détecté.
- Messages de commit concis, en français.
- Vérifier que `git config user.name` et `git config user.email` sont définis localement.
- Après chaque commit, **pousser automatiquement sur GitHub** avec `git push origin main`. Ne jamais attendre de feu vert de l'utilisateur pour pousser — chaque commit doit être immédiatement sur le remote.

### Contraintes iOS

- `env(safe-area-inset-top)` sur tous les écrans, pour éviter que le contenu passe sous la Dynamic Island
- `user-select: none` sur les éléments graphiques, pour éviter la sélection de texte au toucher
- Taille minimale des zones tactiles : 44 × 44 px
- Tester systématiquement sur iPhone réel, pas seulement sur simulateur

---

## 9. Notes techniques

**Cold start Railway.** Le plan gratuit met le service en veille. Prévoir des états de chargement côté frontend et une tolérance sur le premier appel après une période d'inactivité.

**Robustesse du scraper Unibet.** Les endpoints sont non documentés et peuvent changer sans préavis. Le scraper doit échouer proprement, journaliser précisément ce qui n'a pas fonctionné, et ne jamais corrompre les cotes déjà enregistrées en base.

**Idempotence des jobs.** Le job de résultats tourne en boucle toutes les 5 minutes. Il doit pouvoir s'exécuter plusieurs fois sans attribuer les points en double.

**Cache frontend.** Utiliser un hook de fetch avec cache localStorage en stale-while-revalidate, pour un affichage instantané au lancement de l'app.

---

## 10. État d'avancement

### Déjà implémenté

**Étape 1 — Fondations** (version `0.1.0`)

Structure monorepo : `frontend/` et `backend/` à la racine, aux côtés de `maquettes/` et `assets/`.

*Frontend* — React 19 + Vite 8 + Tailwind CSS 4, PWA installable.
- Le design system de la section 5 est intégralement transcrit en variables de thème dans `frontend/src/index.css`, via le bloc `@theme` de Tailwind 4. Couleurs (`bg-primaire`, `text-texte-doux`…), échelle typographique (`text-titre`, `text-score`, `text-corps`, `text-label`), rayons (`rounded-bloc`, `rounded-carte`, `rounded-champ`). **Tout nouvel écran puise dans ces tokens, jamais dans des valeurs en dur.**
- Contraintes iOS en place : `viewport-fit=cover`, utilitaire `ecran` qui applique les zones sûres sur les quatre côtés, espacement `tactile` (44px), `user-select: none` sur les éléments graphiques, désactivation du surlignage au toucher et de la détection de numéros de téléphone.
- PWA via `vite-plugin-pwa` : manifest, service worker `autoUpdate`, icônes 192/512/maskable/apple-touch générées aux couleurs de la marque.
- Écran d'accueil minimal (nom de l'app, version en bas, état du backend). **Aucun écran métier n'est encore codé.**

*Backend* — FastAPI, structure `app/` avec `config.py` (pydantic-settings), `api/router.py` agrégateur et `api/routes/`. Endpoint `GET /health`, `Procfile` pour Railway.

*CORS* (version `0.1.2`) — **deux origines sont garanties quelle que soit la configuration de l'environnement** : la production `https://mon-petit-podium.vercel.app` et le serveur de dev Vite (`localhost:5173` et `127.0.0.1:5173`). L'origine de production reste pilotable par la variable d'environnement **`FRONTEND_URL`**, mais celle-ci a désormais l'URL Vercel pour **valeur par défaut** (constante `ORIGINE_PRODUCTION` dans `config.py`) : si la variable manque ou est vidée sur Railway, le frontend de production continue d'être autorisé au lieu de tomber en erreur CORS. Définir `FRONTEND_URL` sur une autre URL (préproduction, domaine personnalisé) l'**ajoute** aux origines, sans jamais retirer les deux garanties. `CORS_ORIGINS` reste disponible pour d'éventuelles origines supplémentaires, séparées par des virgules. Les deux variables sont typées `str` et non `list[str]` : pydantic-settings exigerait du JSON strict sur un champ complexe et **planterait au démarrage** sur une valeur simple. La barre oblique finale est retirée automatiquement, l'en-tête `Origin` n'en comportant jamais. Le `CORSMiddleware` est monté au niveau de l'application : il couvre toutes les routes, présentes et à venir, préflights `OPTIONS` compris — ne jamais gérer le CORS route par route. La liste des origines chargées est journalisée au démarrage (via le logger `uvicorn.error`, le seul disposant d'un handler sous Railway) : en cas de nouvelle erreur CORS, les logs Railway la donnent immédiatement.

*Vérifié en local* : `npm run build` passe, l'accueil affiche « En ligne » et la mise en page est fluide sans largeur fixe. Côté API, serveur lancé **sans aucune variable d'environnement** (le cas défavorable) :

| Test | Résultat |
|---|---|
| `GET /health` | `200` — `{"status":"ok","version":"0.1.2","environment":"development"}` |
| `GET /health` avec `Origin` Vercel | `200` + `access-control-allow-origin: https://mon-petit-podium.vercel.app` |
| `GET /health` avec `Origin: http://localhost:5173` | `200` + en-tête correspondant |
| Préflight `OPTIONS` depuis Vercel et depuis localhost | `200` + `allow-methods`, `allow-headers`, `max-age` |
| Préflight `OPTIONS` sur `/championnats` (route non encore codée) | `200` + en-têtes CORS |
| `GET` sur une route inexistante avec `Origin` autorisée | `404` **avec** en-tête CORS |
| `GET` / préflight depuis une origine inconnue | en-tête `allow-origin` **absent** / `400 Disallowed CORS origin` |
| `FRONTEND_URL` surchargée avec barre oblique finale + `CORS_ORIGINS` | barre retirée, origines ajoutées, les deux garanties conservées |

Les deux dernières lignes prouvent respectivement que le middleware couvre **toutes les routes, y compris celles qui n'existent pas encore**, et que la surcharge par variables d'environnement n'écrase jamais les origines garanties.

**Workflow Git** — le dépôt était déjà initialisé et relié à `matthieuandrebazzana-lang/Mon-Petit-Podium`. Le `.gitignore` racine couvre Node, Python, `.env`, builds et fichiers d'éditeur. Le push automatique sur `main` après chaque commit est désormais la règle (section 8) : plus aucune validation n'est demandée avant de pousser.

---

**Étape 2 — Authentification Supabase** (version `0.2.0`)

*Client Supabase* — `frontend/src/lib/supabase.js` lit `VITE_SUPABASE_URL` et `VITE_SUPABASE_ANON_KEY`. Si l'une manque, le client vaut `null` au lieu de lever une exception au chargement du module : l'app affiche alors un message explicite plutôt qu'une page blanche, seul échec vraiment illisible sur mobile. Session persistée en `localStorage`, rafraîchissement automatique du jeton, `detectSessionInUrl` et flux **PKCE** (indispensable au retour de Google, d'Apple et des liens envoyés par email).

*Routage* — `react-router-dom`. Trois groupes : **public** (`/`, `/inscription`, `/connexion`, `/mot-de-passe-oublie`), **protégé** (`/accueil`), et `/nouveau-mot-de-passe` **hors des deux**. Ce dernier point n'est pas un oubli : un lien de réinitialisation ouvre une session, donc l'utilisateur est techniquement connecté sans avoir le droit d'entrer dans l'app. `RouteProtegee` le renvoie sur cet écran tant que le mot de passe n'est pas choisi. Tant que la session initiale n'est pas résolue, les deux gardes affichent l'écran d'attente : rediriger pendant ce laps ferait clignoter la connexion devant quelqu'un déjà connecté à chaque lancement. `frontend/vercel.json` réécrit toutes les URL vers `index.html`, sans quoi un lien profond renverrait un 404 avant l'installation du service worker.

*Écrans* — maquettes 01, 02 et 03 suivies à la lettre, aux trois écarts près listés plus bas : landing, inscription (pseudo, email, mot de passe), connexion, mot de passe oublié, nouveau mot de passe, plus l'accueil connecté (salutation, état du backend, déconnexion). Le pseudo part dans les métadonnées de l'utilisateur, prêt pour la table `profils` de l'étape 3. Google et Apple sont câblés via `signInWithOAuth` : **les clés OAuth restent à renseigner dans le tableau de bord Supabase**, d'ici là les boutons échouent proprement avec un message lisible au lieu de rester muets. *(Depuis la version `0.2.2`, ces deux boutons sont masqués — voir plus bas.)*

*Erreurs* — `frontend/src/lib/erreurs.js` est le **seul** point de traduction : tout ce qui remonte de `supabase.auth.*` y passe et ressort en français dans l'interface, jamais dans la console. Reconnaissance par `code` d'abord (`invalid_credentials`, `weak_password`, `email_exists`…), repli par expression régulière sur le message anglais pour les chemins qui ne renvoient pas de code. Cas particulier traité : quand la confirmation par email est active, une inscription sur une adresse déjà prise **réussit en apparence** et renvoie un utilisateur sans identité — Supabase protège ainsi la liste de ses inscrits. Sans le test `emailDejaInscrit`, l'utilisateur attendrait indéfiniment un email qui n'arrivera jamais.

*Mouvement* — quatre transitions du skill Transitions.dev, avec leurs jetons, dans `index.css` : *texts reveal* (apparition échelonnée des blocs), *error state shake* (secousse du champ fautif), *text states swap* (libellé de bouton pendant l'envoi), *shimmer text* (attente de session). Le passage d'écran reprend les jetons de *page side-by-side* sur la seule apparition — avec un routeur, l'écran sortant est démonté avant que l'entrant n'existe — et **omet volontairement le flou à l'échelle de l'écran**, trop coûteux en composition plein cadre sur iPhone ; il reste appliqué aux blocs. La revert automatique de la secousse (`--revert-hold`) n'est pas utilisée : dans un formulaire, l'erreur doit rester tant que la saisie n'est pas corrigée. Elle s'efface donc à la frappe.

*Écarts assumés par rapport aux maquettes* — trois, tous tranchés en faveur de ce fichier :
1. La maquette 01 écrit « Crée ta ligue » et « Ligues privées ». Le vocabulaire de la section 1 interdit « ligue » : l'interface dit **championnat**.
2. La maquette 01 donne 28px de rayon au bloc héros et 32px à son titre. La section 5 impose 24px et 28–30px : ce sont ces valeurs qui s'appliquent.
3. Les champs portent une bordure **transparente au repos**, colorée seulement au focus et en erreur. La section 5 proscrit les bordures fines, et aucune n'est visible au repos ; sa largeur est constante dans tous les états pour que la coloration ne décale jamais le texte saisi d'un pixel.

*Apport d'/apple-design* — zones sûres déjà en place, complétées par : retour tactile à l'appui (`pressable`, `scale(0.97)` en 100ms) et non au relâchement, zones tactiles portées à 44px sur les petits liens (« Retour », « Mot de passe oublié ? ») via des marges négatives qui préservent le calage visuel de la maquette, crénage négatif sur les titres au-delà de 24px, cohérence spatiale des entrées d'écran (un écran qui s'enfonce entre par la droite, un retour par la gauche), et `prefers-reduced-motion` couvrant toutes les animations ajoutées.

*Vérifié en local* : `npm run build` passe, chaque module se transforme sans erreur, et les utilitaires du thème (`size-tactile`, `rounded-bloc`, `p-4.5`…) sont bien générés dans le CSS de production.

---

**Unicité du pseudo** (version `0.2.1`)

*Constat de départ* — il n'existait **aucune table de profils**. Le pseudo ne vivait que dans `auth.users.raw_user_meta_data`, un JSON sans la moindre contrainte : deux membres pouvaient porter le même pseudo, ce qui rend un classement illisible. La contrainte demandée ne pouvait donc pas être « ajoutée » à une colonne existante, il a fallu créer la colonne qui la porte.

*Migration* — `supabase/migrations/20260809191018_profils_pseudo_unique.sql`. **À exécuter à la main dans le SQL Editor de Supabase** (ou via la CLI) : la clé anonyme ne peut pas toucher au schéma `auth`. Elle est idempotente, la rejouer ne casse rien.

Table `public.profils` : `id` référence `auth.users` avec suppression en cascade, `pseudo`, `cree_le`, `modifie_le`. Volontairement limitée à ça — championnats, pronostics et cotes relèvent de l'étape 3.

*La contrainte* — un **index unique sur `lower(pseudo)`**, pas un `unique` nu sur la colonne. Un UNIQUE ordinaire laisserait coexister « MaxV33 » et « maxv33 », que tout le monde lirait comme la même personne. L'extension `citext` ferait le même travail au prix d'une extension à gérer. Une contrainte `check` réplique en base les bornes 2–20 caractères du frontend, qui peut être contourné.

*Alimentation* — un trigger `on_auth_user_created` crée le profil à l'inscription. Deux comportements distincts, et c'est délibéré :
- **Pseudo choisi explicitement** : jamais remplacé en douce. S'il est pris, l'insertion échoue et l'inscription entière est annulée. Renommer discrètement le pseudo de quelqu'un serait pire qu'un refus.
- **Aucun pseudo transmis** (Google et Apple n'en envoient pas) : un pseudo `pilote-xxxxxxxxxx` est fabriqué, avec incrémentation en cas de collision. Une inscription OAuth ne doit jamais échouer pour cette raison.

*Reprise de l'existant* — les comptes antérieurs sont rattrapés en dédoublonnant : à pseudo identique, le plus ancien le garde, les suivants sont suffixés `-2`, `-3`. Sans ce dédoublonnage, l'index unique ferait échouer toute la migration.

*Côté frontend* — la fonction `public.pseudo_disponible(text)` est appelable **sans être connecté** (`security definer`), ce qui permet au formulaire de refuser un pseudo pris **avant** l'envoi, sous le champ concerné, plutôt qu'après la saisie du mot de passe. Elle révèle qu'un pseudo est utilisé, sans dire par qui : c'est le compromis normal d'un champ de pseudo, ces pseudos étant de toute façon affichés dans les classements. **À ne jamais transposer aux emails.**

Si l'appel échoue — migration pas encore appliquée, réseau coupé — la réponse est « disponible » et l'inscription continue : bloquer tout le monde parce qu'une vérification de confort ne répond pas serait disproportionné. La garantie reste l'index en base.

Le doublon détecté au dernier moment (deux inscriptions à quelques millisecondes d'intervalle) remonte par `erreurs.js` : GoTrue renvoie alors « Database error saving new user », traduit en « Ce pseudo est déjà pris. Choisis-en un autre. » et reposé sous le champ pseudo. **Ce raccourci ne tient que parce que ce trigger est le seul posé sur `auth.users`** — en ajouter un autre obligera à revoir ce message.

*Vérifié* — la migration a été exécutée sur un PostgreSQL 16 jetable (Docker), avec un doublon minimal du schéma `auth` de Supabase. Douze contrôles passent : création du profil depuis les métadonnées ; refus d'un doublon en casse différente et avec espaces autour ; pseudo fabriqué pour une inscription sans pseudo ; refus d'un pseudo trop court ; `pseudo_disponible` insensible à la casse et aux espaces ; droits d'exécution pour `anon` et `authenticated` ; refus d'un renommage vers un pseudo pris ; horodatage de `modifie_le` ; suppression du profil en cascade ; RLS active avec ses deux politiques ; définition de l'index conforme. Reprise et idempotence vérifiées séparément : cinq comptes antérieurs dont trois en conflit, correctement dédoublonnés, et deuxième passage de la migration sans erreur.

---

**Google et Apple masqués temporairement** (version `0.2.2`)

*Décision* — les boutons « Continuer avec Google » et « Continuer avec Apple », ainsi que le séparateur « ou continuer avec », sont **retirés de l'interface** sur l'inscription et la connexion. Les clés OAuth ne sont pas encore renseignées côté Supabase : offrir deux boutons qui échouent à chaque appui vaut moins que ne pas les offrir du tout. **À réactiver quand l'app passera en production**, une fois les clés et les URL de redirection en place.

*Le code OAuth est intact* — rien n'est supprimé : `connecterAvec` dans `AuthContexte.jsx`, `signInWithOAuth`, les icônes, la variante `social` du bouton, le flux PKCE du client Supabase, tout reste en place et compile. Seul le rendu est coupé.

*Mécanisme* — une constante `OAUTH_ACTIF = false` en tête de `frontend/src/composants/BoutonsOAuth.jsx`. **La repasser à `true` suffit à tout réafficher**, sans toucher aux écrans. Deux points de mise en œuvre à ne pas défaire :
- Le retour anticipé est placé **après** les hooks, jamais avant : les règles de React interdisent un `return` qui court-circuiterait `useState` ou `useAuth`.
- Les deux écrans appellent le composant dans un conteneur `flex flex-col gap-3`. Ne rien rendre y **referme l'espacement de lui-même** — aucun blanc résiduel, donc aucune marge à retoucher dans les écrans, et rien à défaire à la réactivation.

*Portée* — seul le frontend change. `backend/app/config.py` reste en `0.2.1`, aucun code backend n'étant touché : faire bouger la version renvoyée par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu.

*Vérifié en local* : `npm run build` passe (88 modules). Le drapeau étant une constante, le bundler élimine le JSX devenu inatteignable — les chaînes « ou continuer avec » et « Continuer avec Google » sont **absentes du bundle de production**, preuve que les boutons ne sont pas seulement invisibles mais bel et bien non rendus. Le code, lui, reste entier dans les sources.

---

**Étape 3 — Championnats** (version `0.3.0`)

Création, code d'invitation, adhésion, liste des membres. Quatre écrans, quatre routes d'API, deux tables.

*Schéma* — `supabase/migrations/20260810163435_championnats.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, comme la précédente. Idempotente.

`public.championnats` : `id`, `nom`, `code_invitation` (unique), `cree_par`, `cree_le`. Deux contraintes `check` doublent en base les contrôles de saisie du frontend, qui peut être contourné : le nom fait 2 à 40 caractères, le code respecte `^[A-Z0-9]{6}$`. `cree_par` **ne cascade pas** — supprimer le compte du créateur emporterait le championnat de tous les autres membres. Tant que ce cas n'a pas de règle explicite, la suppression d'un tel compte échoue franchement plutôt que de détruire les données des autres.

`public.membres_championnat` : clé primaire `(championnat_id, profil_id)`, cascade sur les deux références, `rejoint_le` (qui servira au 3ᵉ critère de départage de la règle 4.6). Un index sur `profil_id` s'ajoute à la clé primaire : celle-ci couvre les recherches par championnat, mais « mes championnats » part du profil et balaierait toute la table sans lui.

*Le piège de la RLS, et sa sortie* — les politiques de lecture demandées se formulent « il existe une ligne dans `membres_championnat` avec ce `championnat_id` et `profil_id = auth.uid()` ». Écrite telle quelle dans une politique **de** `membres_championnat`, la condition interroge la table que la politique protège : PostgreSQL détecte la récursion et refuse la requête (`42P17`). La politique de `championnats` tombe dans le même piège, une sous-requête sur `membres_championnat` déclenchant à son tour la politique de cette table. La fonction `public.est_membre(uuid)`, en `security definer`, casse la boucle en lisant sans repasser par les politiques. **La sémantique est exactement celle demandée** ; seule l'écriture change. Ne jamais réinsérer la sous-requête littérale dans ces politiques.

*Deux fonctions réservées au backend* — `creer_championnat(nom, code, createur)` insère le championnat **et** son créateur dans la même transaction : deux appels REST séparés laisseraient, en cas d'échec du second, un championnat sans aucun membre, donc invisible de tous — y compris de celui qui vient de le créer — et impossible à rejoindre puisque personne n'en connaît le code. `mes_championnats(profil)` renvoie les championnats d'un membre avec leur effectif en une requête. Les deux prennent l'identifiant en **paramètre** : appelables par un client authentifié, elles permettraient d'agir au nom de quelqu'un d'autre. Elles sont donc révoquées pour `public`, `anon` et `authenticated`, et accordées au seul `service_role`. Les droits de table sont écrits explicitement dans la migration plutôt que laissés aux privilèges par défaut de Supabase ; `anon` n'est jamais servi.

*Backend* — `backend/app/supabase_client.py` (client HTTP partagé, appels PostgREST, validation des jetons), `backend/app/api/deps.py` (dépendance `utilisateur_courant`), `backend/app/api/routes/championnats.py` (les quatre routes).

**Deux clés Supabase, deux usages à ne jamais confondre.** La clé **anonyme** ne sert qu'à valider le jeton de l'appelant. La clé **de service** sert aux lectures et écritures et **contourne la RLS**, ce qui est voulu : retrouver un championnat par son code alors qu'on n'en est pas encore membre est impossible sous RLS. L'autorisation est alors portée par le code des routes, qui ne travaille jamais qu'avec l'identifiant issu du jeton vérifié — **le corps de la requête ne dit jamais qui est l'appelant**. Les politiques RLS ne sont pas rendues inutiles pour autant : elles protègent l'autre chemin, celui du frontend qui lit directement Supabase.

Le jeton est validé en le présentant à Supabase (`/auth/v1/user`) plutôt que vérifié localement : aucun secret de signature à gérer, et la validation reste valable quelle que soit la clé avec laquelle le projet signe. Un cache de 60 secondes évite un aller-retour par appel.

| Route | Comportement |
|---|---|
| `POST /championnats` | Code tiré de `secrets`, 5 tentatives en cas de collision (`23505`), puis échec franc. Retourne le championnat créé. |
| `GET /championnats/moi` | Championnats de l'appelant, avec leur effectif. |
| `POST /championnats/rejoindre` | Code normalisé (minuscules, espaces et tirets acceptés). `404` si inconnu, `409` si déjà membre — c'est la clé primaire qui répond, pas une lecture préalable qui laisserait passer deux appels simultanés. |
| `DELETE /championnats/{id}/quitter` | `204`, ou `404` si non membre. Le créateur peut partir, le championnat lui survit. **Un `TODO` marque l'endroit où effacer les pronostics** (table absente jusqu'à l'étape 5) : la suppression devra se faire dans la même transaction que le retrait. |

Le générateur de code écarte les caractères non conformes du jeton plutôt que de le passer en majuscules : « a » et « A » tomberaient sur la même lettre et les lettres sortiraient deux fois plus souvent que les chiffres. Le service démarre sans les clés Supabase — `/health` doit rester joignable pour diagnostiquer — mais journalise un avertissement et répond `503` sur les routes métier.

*Frontend* — **deux chemins de données coexistent, délibérément.** Écritures et règles métier passent par FastAPI ; la **lecture du détail** d'un championnat et de ses membres va directement à Supabase, sous les politiques RLS qui décrivent exactement ce cas. Passer par Railway n'y ajouterait qu'un cold start. `lib/api.js` est le seul point de traduction des échecs réseau, comme `lib/erreurs.js` l'est pour l'authentification.

`lib/useDonnees.js` implémente le cache localStorage en *stale-while-revalidate* de la section 9 : l'accueil affiche immédiatement ce qu'il savait, puis se met à jour. C'est ce qui rend le réveil de Railway supportable. **La clé de cache porte toujours l'identifiant du compte** — deux personnes qui se relaient sur le même téléphone ne doivent jamais voir la liste de l'autre, fût-ce une fraction de seconde. Le cache est invalidé après création, adhésion et départ, sans quoi le retour sur l'accueil semblerait avoir perdu le championnat.

Écrans : accueil (maquette 04), création (05), adhésion (06), vue championnat (07). La saisie du code se fait dans **une seule zone de saisie transparente posée sur six cases** : six champs séparés obligeraient à gérer à la main le retour arrière, le collage d'un code entier et le curseur, et sur iOS chaque changement de champ fait sursauter le clavier. Les cases portent `aria-hidden`, le lecteur d'écran n'entend que le champ.

*Écarts assumés par rapport aux maquettes* — la maquette montre des données qui n'existent pas encore ; les inventer serait mentir :
1. **Bloc « Prochain GP » (04)** — aucun GP en base avant l'étape 4. Le bloc rouge garde sa place dans la composition et annonce ce qui va s'y trouver.
2. **Classement sur les cartes (04)** — aucun point avant l'étape 6. Remplacé par le code d'invitation (utile pour partager) et un chevron.
3. **Grille d'actions (04)** — libellés ramenés à « Créer » et « Rejoindre » : « Créer un championnat » sur une demi-largeur d'iPhone passe à la ligne, ce qu'`/apple-design` et le skill Taste proscrivent tous deux.
4. **Photo de championnat (05)** — pas de colonne ni de stockage. Bloc retiré.
5. **Code affiché avant création (05)** — le code est tiré par le serveur. Le bloc affiche six tirets et « Généré automatiquement à la création », plutôt qu'un code qui n'est réservé nulle part.
6. **Aperçu du championnat avant adhésion (06)** — impossible : sous RLS, on ne voit pas un championnat dont on n'est pas membre, et aucune route ne l'expose (ce serait révéler l'existence d'un championnat à qui devine un code).
7. **Bascule Classement / Piste et bloc « prochain GP » (07)** — relèvent des étapes 6 et 7.
8. **Barre de navigation basse** — non codée : trois de ses quatre onglets (Championnats, Calendrier, Profil) n'ont pas encore d'écran. Elle arrivera avec eux. En attendant, la déconnexion est un lien discret en bas de l'accueil.

*Apport d'/apple-design* — retour tactile à l'appui sur toutes les cartes et actions, zones tactiles à 44px partout (y compris sur « Annuler » et « Se déconnecter », via des marges négatives qui préservent le calage visuel), et **confirmation sur place plutôt qu'en boîte de dialogue** pour quitter un championnat : l'action est réversible tant qu'on a gardé le code, et le geste de retour annule tout. Le bouton « Rejoindre » reste actif même quand le code est incomplet — un bouton grisé ne dit pas ce qui manque ; l'appui pose le message sous les cases, à l'endroit exact à corriger.

*Mouvement* — ajout du *skeleton loader and reveal* (transitions-dev 14) pour l'attente de l'accueil et du détail. Une **variante `.t-skel--flux`** est ajoutée sous le snippet, non à sa place : le snippet superpose ses deux couches en `absolute`, ce qui suppose un conteneur déjà dimensionné, alors que la hauteur de la liste dépend du nombre de championnats. Les deux couches partagent donc une cellule de grille, et le squelette est démonté à la fin de la révélation. `TexteEchange` (transitions-dev 04) est sorti de `Bouton.jsx` dans son propre module pour servir aussi au bouton « Copier le code » → « Code copié ».

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Migration sur PostgreSQL 16 jetable (Docker), avec doublure du schéma `auth` | **50 contrôles passent** — structure, contraintes de format, atomicité de `creer_championnat`, absence de ligne résiduelle après échec, cascades, refus de suppression du compte créateur, RLS sous trois identités, droits des fonctions |
| Absence de récursion RLS (`42P17`) | vérifiée explicitement, lecture réussie sous l'identité d'un membre |
| Rejeu de la migration sur une base peuplée | aucune erreur, aucune donnée modifiée |
| Routes API contre un faux Supabase (auth + PostgREST en mémoire) | **39 contrôles passent** — rejet des appels non authentifiés sur les quatre routes, jeton inconnu, en-tête sans `Bearer` ; création, format et unicité de 31 codes tirés ; retry sur 4 collisions forcées puis échec franc à la 5ᵉ ; validation du nom ; adhésion, doublon, code inconnu, code en minuscules avec tiret et espaces ; cloisonnement entre deux comptes ; départ, double départ, survie du championnat au départ de son créateur ; préflight CORS |
| Rendu des quatre écrans hors navigateur (`react-dom/server`) | **12 contrôles passent** — aucun écran ne lève au montage, six cases rendues, normalisation du code, pastille déterministe |
| `npm run build` | passe, 98 modules, utilitaires du thème bien générés |

---

**Logs explicites sur les routes championnats** (version `0.3.1`)

*Constat de départ* — les routes `/championnats` répondaient `502` sans qu'aucune ligne n'apparaisse dans les logs Railway. Deux causes se confondaient sous ce même statut : les échecs Supabase attrapés par les routes, convertis en `502` avec un message générique (« La création du championnat a échoué. Réessaie. ») qui perdait la cause réelle ; et les exceptions Python non capturées, rendues en `500`/`502` par Railway. **Aucune des deux n'était journalisée**, et le diagnostic — clé absente, table non créée, Supabase injoignable — se faisait à l'aveugle.

*Ce qui change* — **rien à la logique métier.** Les quatre handlers sont enrobés, les statuts métier sont inchangés.

`backend/app/api/routes/championnats.py` :
- `echec_lisible(contexte, erreur)` journalise via `logger.exception` (donc **avec la trace Python**) et renvoie un `422` dont le `detail` porte le contexte et la cause : message Supabase, **code PostgreSQL** (`42P01` table absente, `42501` droits, `23505` doublon) et statut HTTP. Les quatre `raise HTTPException(502, …)` sont remplacés par cet appel.
- `journaliser_echecs(contexte)` décore chaque handler : les `HTTPException` traversent **intactes** (`404` code inconnu, `409` déjà membre, `422` nom invalide, `401`, `503`) — ce sont des réponses voulues, pas des pannes ; tout le reste est journalisé puis rendu en `422` lisible.

`backend/app/api/deps.py` — la dépendance `utilisateur_courant` s'exécute **avant** le handler : son échec échappe au décorateur. Elle journalise donc elle-même, en gardant ses `503` : panne du service d'authentification (`[auth]`, avec trace), exception inattendue (le type et le message sont renvoyés au lieu d'un `500` muet), et refus faute de configuration Supabase (l'avertissement de démarrage est trop loin dans l'historique Railway au moment où le problème se voit).

*Trois points à ne pas défaire* :
1. **`logger = logging.getLogger("uvicorn.error")`** — sous Railway c'est le seul logger doté d'un handler, comme pour le journal CORS de la version `0.1.2`. Un `getLogger(__name__)` écrirait dans le vide.
2. **`functools.wraps` dans le décorateur** — FastAPI lit la signature du handler pour construire ses dépendances et son modèle de réponse, et `inspect.signature` suit `__wrapped__`. Sans lui, la route recevrait `(*args, **kwargs)` et **perdrait `Depends(utilisateur_courant)`** : les routes s'ouvriraient aux appels anonymes. Un contrôle du jeu de tests couvre précisément ce cas.
3. **`echec_lisible` s'appelle depuis un bloc `except`** — `logger.exception` n'a de trace à joindre que là.

*Le `422` est un choix de diagnostic, pas de sémantique.* Ces erreurs ne sont pas des erreurs de validation. Ce statut est retenu parce que `frontend/src/lib/api.js` affiche déjà tel quel un `detail` de type chaîne, et qu'il ne se confond ni avec le `503` d'une configuration absente ni avec le `500` d'un plantage non capturé. **Conséquence assumée : un message technique en anglais peut s'afficher à l'écran** — c'est le but, le temps de la mise en service. À revoir une fois le parcours exercé contre le vrai Supabase : messages remis en français, cause gardée dans les seuls logs.

*Vérifié en local* : **41 contrôles passent** contre des doublures Supabase en mémoire — les quatre routes servent toujours leur chemin nominal (`201`, `200`, `200`, `204`), `401` sans jeton (preuve que la signature survit au décorateur), les cinq réponses métier traversent intactes avec leur message, une table absente sort en `422` portant `42P01` et sa trace, une base injoignable sort en clair, un `KeyError`, un `RuntimeError` et un `ValueError` sortent en `422` typé au lieu d'un `500` muet, les deux pannes de la dépendance d'authentification sortent en `503` journalisé, le refus faute de clés est tracé, et `/health` comme le préflight CORS sont inchangés. Vérifié aussi sous un vrai `uvicorn`, Supabase pointé sur un port mort : la **trace complète apparaît sur la sortie standard**, exactement ce que Railway affichera. `npm run build` passe.

---

**Étape 4 — Scraper Unibet** (version `0.4.0`)

Découverte des GP, extraction des marchés et cotes, stockage. Deux tables, trois routes, un module de scraping. **Vérifié contre les vraies données du GP Pays-Bas** (23 août 2026) : 3 marchés, 55 cotes.

*Trois écarts entre la section 3.1 et ce qu'Unibet fait aujourd'hui.* Ils ont été constatés en interrogeant l'API, ils expliquent l'essentiel du code, et **la section 3.1 n'a pas été réécrite** : elle reste le cahier des charges, ce paragraphe dit ce que la réalité y oppose.

1. **L'API exige un jeton.** `/lvs-api/...` répond `401 {"message":"Missing X-LVS-HSToken"}` sans en-tête `X-LVS-HSToken`. Le CLAUDE.md annonçait « sans authentification et sans cookie obligatoire » : c'est toujours vrai au sens où aucun compte n'est nécessaire, mais l'en-tête, lui, l'est. Le jeton est déposé en clair dans la configuration de n'importe quelle page de paris (clés `pselNonExpiringHsToken` et `hsToken`, les deux acceptées) ; `jeton()` va le lire sur `/paris-formule-1`. Il est relu à chaque scraping, jamais stocké : il change à chaque déploiement d'Unibet. **La page d'accueil du site répond 403** aux clients non navigateur, pas celle de la Formule 1 — d'où ce choix de page.

2. **`price` est une chaîne à la française** (« 2,80 »), pas un nombre. Un `float(price)` lève, un `price * 100` concatène. `en_points()` est le seul endroit qui traite le cas. Cross-contrôle rassurant : Unibet expose aussi un champ `sort` qui vaut exactement `round(price × 100)` — vérifié sur les 44 cotes du nœud racine, zéro écart. Il n'est pas utilisé (rien ne le documente comme tel), mais il confirme que la règle 4.1 tombe juste sur leurs propres arrondis.

3. **L'API ne rend qu'un seul marché par événement** — le marché vedette, « Vainqueur ». L'événement annonce pourtant `count: 3`. Aucun paramètre ne la fait céder : `includeAllMarkets`, `marketTypeDisplayGroupId`, `groupId`, `allMarkets`, `topMarketOnly` ont tous été essayés, sans le moindre effet ; il n'existe aucun endpoint JSON par événement (`/lvs-api/event/...` et une dizaine de variantes répondent 500), et `next/200` est refusé. **Les marchés complets ne sont exposés que par la page de l'événement**, rendue côté serveur. Cette page embarque ses données dans une balise `<script id="serverApp-state" type="application/json">` — l'état Angular du rendu serveur. `marches()` lit ce bloc : **c'est du JSON, avec les mêmes champs que l'API, pas du HTML.** Aucune balise n'est interprétée, rien ne dépend d'une classe CSS.

*Conséquence : l'URL de la page d'événement doit être exacte.* Elle s'écrit `/paris-formule-1/{catégorie}/{gp}/{id-numérique}/course`, et **le moindre écart de slug renvoie 404** — un identifiant numérique seul ne suffit pas, un slug approximatif non plus (vérifié). `slug()` reproduit donc la fonction du site, retrouvée dans son bundle : minuscules, accents ramenés à la lettre de base, tout le reste en tirets, tirets fondus et rognés. « GP Pays Bas » → `gp-pays-bas`.

*Schéma* — `supabase/migrations/20260813174500_grands_prix_cotes.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, comme les deux précédentes. Idempotente.

`public.grands_prix` : `id`, `id_unibet` (unique), `nom`, `date_course`, `statut`, `cree_le`. `id_unibet` est la clé de rapprochement du scraper — jamais le nom, dont l'orthographe bouge (« GP Pays Bas » aujourd'hui, « GP Pays-Bas » demain). Le statut est une contrainte `check` (`a_venir`, `cotes_figees`, `termine`) plutôt qu'un type `enum` : ajouter une valeur à un enum est une migration à part entière, et les états d'un week-end ne sont pas encore tous arrêtés.

`public.cotes` : `id`, `gp_id` (cascade), `marche`, `libelle_marche`, `pilote`, `valeur`, `id_outcome_unibet`, `cree_le`. **Deux écarts assumés par rapport aux colonnes demandées** :
- `id_outcome_unibet` est **`not null`**, alors que rien ne l'imposait. C'est ce qui fait tenir l'idempotence : sous PostgreSQL, deux `NULL` sont distincts, et un index unique sur une colonne nullable n'empêcherait plus rien. Une issue sans identifiant est ignorée plutôt qu'insérée.
- **`libelle_marche` est ajouté.** `marche` porte le slug (`ecurie-vainqueur`), qui sert de clé de regroupement ; sans le libellé d'origine, l'interface devrait le reconstituer et afficherait « Ecurie vainqueur » au mieux, « Top x » au pire. Le bookmaker est la seule source légitime du nom d'un marché.

Index unique sur `(gp_id, id_outcome_unibet)` — c'est lui, et lui seul, qui porte l'idempotence. Second index sur `(gp_id, marche)` : le tableau des cotes de l'étape 5 lit toujours « toutes les cotes d'un GP, groupées par marché ».

*RLS* — **lecture ouverte à tous, `anon` compris** : les cotes ne sont un secret pour personne, elles sont affichées telles quelles chez le bookmaker, et la landing pourra annoncer le prochain GP sans session ouverte. Aucune politique d'écriture n'est créée, et c'est le point important : sous RLS, ce qu'aucune politique n'autorise est refusé. Aucun droit d'écriture n'est accordé non plus à `anon` ni `authenticated` — double verrou, l'un antérieur à l'autre. `service_role` contourne la RLS et reste seul à écrire.

`cotes_du_grand_prix(uuid)` renvoie les cotes déjà groupées par marché, en JSON. Regrouper en base évite de transporter une cinquantaine de lignes par GP pour les réassembler en Python. Elle est **`security invoker`**, contrairement aux fonctions de l'étape 3 : elle lit sous l'identité de l'appelant, donc sous les politiques ci-dessus, et n'ouvre aucun accès que la RLS n'accorde déjà.

*Le scraper* — `backend/app/scraper/unibet.py`. Rien n'est codé en dur, ni la liste des GP, ni celle des marchés : le nœud racine est interrogé, ce qu'il rend est traité.

**Le nœud racine ne rend pas que des GP.** Il rend aussi « Championnat du monde », au même rang et avec le même `tag: "League"` — le vainqueur du championnat, daté d'un 6 décembre de convenance. L'enregistrer créerait un faux Grand Prix, qui deviendrait le « prochain GP » de l'accueil. Le filtre retenu ne porte pas sur le nom du championnat mais sur l'événement : **seuls les événements dont le libellé donne le slug `course` sont retenus.** Le tri est sémantiquement juste (c'est la course que valide l'étape 6, pas les qualifications ni le sprint) et il écarte le championnat sans avoir à le nommer. `eType` ne sert à rien ici : il vaut `R` pour les deux. **Tout événement écarté est journalisé avec son libellé** — si Unibet renomme « Course », les logs le diront au lieu de laisser le scraper ne rien trouver en silence.

**Les horaires d'Unibet sont en heure de Paris**, sans que rien ne le dise : `start` vaut « 2608231500 » (AAMMJJHHMM) pour un départ annoncé à 15h00, soit 13h00 UTC. Les stocker tels quels décalerait d'une à deux heures toute la programmation de l'étape 6 (fermeture 5 min avant le départ, résultats 1h30 après). La conversion est faite au scraping ; `date_course` est en UTC.

**Un GP figé n'est jamais réécrit.** Avant d'écrire, le scraper lit le statut : `cotes_figees` ou `termine`, il enregistre le GP et **s'arrête là**, en journalisant combien de cotes il a ignorées. C'est la règle 4.3 — après les qualifications, tout le monde pronostique sur les mêmes cotes, et un scraping tardif ne doit pas les faire bouger sous les pronostics déjà saisis. Le statut n'est jamais transmis à l'upsert non plus : le préciser remettrait à `a_venir` un GP figé à chaque passage.

**L'échec d'un GP n'emporte pas les autres.** Chacun est traité pour lui-même ; celui qui échoue est journalisé, abandonné, et **rien n'est écrit pour lui** — ses cotes déjà en base restent intactes. Le compte rendu porte les réussites comme les échecs. Une issue illisible est ignorée sans emporter son marché ; un marché entier illisible fait échouer le GP plutôt que d'enregistrer des cotes fausses.

`upserter()` est ajouté à `supabase_client.py` : un `insert … on conflict … do update` via PostgREST. Un `insert` nu échouerait au deuxième passage ; un `delete` suivi d'un `insert` laisserait le GP sans aucune cote pendant un instant, et définitivement si l'insertion échouait.

*Routes* — `backend/app/api/routes/scraper.py`.

| Route | Comportement |
|---|---|
| `POST /scraper/declencher` | En-tête `X-Admin-Secret`. Lance le scraping en tâche de fond et rend `202 {"statut":"lance"}` sans attendre. Le compte rendu part dans les logs Railway. |
| `GET /scraper/cotes` | **Publique.** Toutes les cotes en base, groupées par GP puis par marché. |
| `GET /grands-prix/{id}/cotes` | **Publique.** Les cotes d'un GP, groupées par marché. `404` si le GP n'existe pas. |

**Trois points de mise en œuvre à ne pas défaire :**
1. La comparaison du secret passe par `secrets.compare_digest`, **à temps constant**. Un `==` sur des chaînes s'arrête au premier caractère qui diffère, et le temps de réponse laisse alors deviner le secret caractère par caractère.
2. **`ADMIN_SECRET` non défini ferme la route** (`503`), il ne l'ouvre pas. Le défaut d'une variable absente ne doit jamais être l'accès libre.
3. Les tâches lancées sont gardées dans un `set` le temps de leur exécution. Sans référence forte, asyncio est en droit de ramasser une tâche en cours, et le scraping s'arrêterait au milieu sans un mot.

Le secret est vérifié **avant** la configuration Supabase : répondre « Supabase n'est pas configuré » à qui n'a pas donné le bon secret lui apprendrait quelque chose sur l'état du serveur pour rien. La configuration est vérifiée ensuite, pour ne pas aller solliciter Unibet en pure perte.

`journaliser_echecs` reprend le décorateur de la version `0.3.1`, avec `functools.wraps` pour la même raison exactement : sans lui, `POST /scraper/declencher` **perdrait son en-tête `X-Admin-Secret` et s'ouvrirait à tous**. Un contrôle du jeu de tests couvre ce cas.

*`tzdata` est ajouté à `requirements.txt`* — et ce n'est pas décoratif. `ZoneInfo("Europe/Paris")` lit la base de fuseaux du système ; macOS en a une, beaucoup d'images Linux minces n'en ont aucune, et le scraper planterait sur Railway alors qu'il passe en local.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Scraping réel du GP Pays-Bas | **3 marchés, 55 cotes** — Vainqueur (22), Podium (22), Ecurie Vainqueur (11). Date : 15h00 Paris → `2026-08-23T13:00:00Z`. Championnat du monde écarté et journalisé. |
| Migration sur PostgreSQL 16 jetable (Docker) | **30 contrôles** — structure, `not null` sur `id_outcome_unibet`, statut hors liste refusé, unicité de `id_unibet`, doublon `(gp_id, id_outcome)` refusé, `valeur` nulle refusée, clé étrangère, upsert qui met à jour sans dupliquer, cascade, regroupement par marché, RLS active, une seule politique (SELECT) par table, droits |
| RLS sous les vraies identités | `anon` lit ; `authenticated` ne peut ni insérer ni modifier une cote (`42501`) ; `anon` ne peut pas supprimer de GP ; `service_role` écrit ; `cotes_du_grand_prix` s'appelle sans être connecté |
| Rejeu de la migration | aucune erreur, aucune donnée modifiée |
| Idempotence, contre le vrai Unibet | **21 contrôles** — deuxième scraping : 55 cotes avant, 55 après, mêmes issues mises à jour et non recréées ; GP `cotes_figees` puis `termine` : **aucune cote réécrite**, 0 enregistrée, statut jamais remis à `a_venir` |
| Pannes | **25 contrôles** — page F1 en 403, page sans jeton, réseau coupé, jeton refusé par l'API, réponse non JSON, `items` vide, nœud ne contenant que le championnat, événement renommé, page d'événement en 404, page sans bloc SSR, bloc SSR cassé, aucun événement, toutes les cotes illisibles ; une issue illisible n'emporte pas son marché ; un GP en échec n'empêche pas l'autre d'être enregistré ; la tâche de fond n'avale rien en silence ; l'upsert part bien avec `on_conflict` et `merge-duplicates`, et n'appelle pas Supabase pour une liste vide |
| Routes contre une doublure Supabase | **30 contrôles** — `401` sans en-tête et sur secret erroné, `202` sur secret correct (casse et espaces tolérés), `503` si `ADMIN_SECRET` absent, la signature survit au décorateur, lecture publique sans jeton, marchés groupés, points servis tels quels, `404` sur GP inconnu, `422` sur identifiant mal formé, table absente rendue avec `42P01`, panne inattendue typée au lieu d'un `500` muet, `/health` en `0.4.0`, préflight CORS, routes championnats toujours protégées |
| Sous un vrai `uvicorn` | Les 8 routes sont servies. Déclenchement réel, Supabase absent : le scraping va au bout côté Unibet et **la panne d'écriture sort avec sa trace complète sur la sortie standard** — exactement ce que Railway affichera. |
| `npm run build` | passe |

---

**Créateur supprimé et championnat vide** (version `0.4.1`)

Deux règles laissées ouvertes par l'étape 3 sont tranchées. Elles vivent **entièrement en base** : un `alter table` et un trigger, aucune logique applicative.

*Migration* — `supabase/migrations/20260813182331_createur_nullable_championnat_vide.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les trois précédentes. Idempotente.

**1. Le championnat survit à son créateur.** `cree_par` devient nullable et sa clé étrangère passe en `on delete set null`. Supprimer un compte n'échoue plus par contrainte : le championnat reste, sans créateur. L'ancienne règle — un RESTRICT implicite, faute de clause `on delete` — était un garde-fou volontaire en attendant cette décision, pas un oubli.

L'ordre des deux opérations n'est pas indifférent : `on delete set null` sur une colonne restée `not null` est **accepté à la création de la contrainte** et n'échoue qu'à la suppression du compte, des mois plus tard. Le `not null` est donc levé en premier.

La contrainte de clé étrangère avait été posée en ligne (`references auth.users`) et porte un nom attribué par PostgreSQL. La migration ne le suppose pas : elle retrouve la contrainte **par la colonne qu'elle porte**, et laisse en place celle qui a déjà la bonne règle (`confdeltype = 'n'`). C'est ce qui la rend rejouable sans rien reconstruire.

**2. Un championnat vidé de ses membres est supprimé.** Trigger `membres_championnat_supprime_vide`, `after delete ... for each row` sur `membres_championnat` : si plus aucune ligne ne reste pour ce `championnat_id`, le championnat est effacé. Jusqu'ici il devenait un fantôme — invisible de tous, puisque la lecture exige d'en être membre, mais toujours rejoignable par son code.

Quatre points de mise en œuvre à ne pas défaire :
- **`security definer`** est indispensable. Le trigger s'exécute sous l'identité de celui qui quitte le championnat, et la politique « Seul le createur supprime » l'empêcherait d'en effacer la ligne — le dernier membre d'un championnat n'en est pas toujours le créateur. La fonction appartient au rôle qui joue la migration, propriétaire des tables, donc non soumis à la RLS. Elle n'ouvre aucun droit nouveau : elle ne supprime qu'un championnat déjà vide, et seulement en réaction à un départ.
- **`after`, jamais `before`** : un trigger `before` compterait les membres avant le retrait de la ligne, le dernier départ trouverait toujours quelqu'un, et rien ne serait jamais supprimé.
- **`for each row`** : une suppression peut porter sur plusieurs championnats à la fois (compte supprimé, membre de plusieurs championnats). Chacun doit être jugé pour lui-même.
- **Aucun garde-fou `pg_trigger_depth()`** : la suppression d'un compte fait cascader `membres_championnat` puis déclenche ce trigger au niveau 1 — le brider sur la profondeur empêcherait précisément le cas qui l'a motivé. La récursion s'arrête d'elle-même : supprimer le championnat cascade ses membres, le trigger se redéclenche, et son `delete` ne trouve plus la ligne, déjà effacée par la commande en cours.

*Reprise de l'existant* — les championnats déjà sans membre au moment de la migration sont effacés une fois, à la main, avec le compte journalisé en `notice`.

*Conséquence côté RLS, assumée* — sur un championnat orphelin, `cree_par` vaut NULL, la politique « Seul le createur supprime » ne vaut jamais vrai, et plus personne ne peut le supprimer depuis le frontend. C'est le comportement voulu : un membre ordinaire n'a pas à emporter le championnat des autres. Le championnat disparaîtra de lui-même au départ du dernier membre.

*La seule ligne de code applicative touchée, et pourquoi elle l'est* — le modèle de réponse `Championnat` de `backend/app/api/routes/championnats.py` déclarait `cree_par: UUID`. Un championnat orphelin aurait fait échouer la validation de la réponse, donc rendu **toute** la liste `GET /championnats/moi` en `500`. Le champ passe à `UUID | None`, et `est_createur` teste explicitement le NULL au lieu de se reposer sur le fait que `str(None)` ne ressemble à aucun identifiant. Côté frontend, rien à changer : `membre.id === donnees.cree_par` vaut simplement `false` et l'étiquette « Créateur » ne s'affiche plus — ce qui est exact, il n'y en a plus.

*Vérifié sur PostgreSQL 16 jetable (Docker), avec doublure du schéma `auth`* :

| Contrôle | Résultat |
|---|---|
| État antérieur reconstitué puis migration appliquée | **16 contrôles passent** |
| Structure | `cree_par` nullable, clé étrangère unique en `on delete set null`, trigger bien `AFTER DELETE FOR EACH ROW`, fonction `security definer` et non appelable par `public`, `anon` ni `authenticated` |
| Référence avant migration | la suppression du créateur échoue bien en `foreign_key_violation` — l'ancien comportement est celui qu'on corrige |
| Suppression du créateur | championnat conservé, `cree_par` à NULL, adhésion du compte cascadée, membres restants intacts ; un championnat dont il n'était pas membre n'est pas touché |
| Reprise de l'existant | le championnat sans membre antérieur est effacé, les autres restent |
| Départ d'un membre non final | championnat conservé |
| Départ du dernier membre, **sous l'identité `authenticated` d'un non-créateur** | championnat supprimé — preuve que le `security definer` fait bien son office là où la RLS refuserait |
| Suppression directe du championnat | membres cascadés, trigger redéclenché, aucune récursion infinie |
| Compte membre de deux championnats, supprimé | l'un est effacé (vidé), l'autre survit en orphelin |
| Parcours de l'étape 3 | `creer_championnat` intacte ; son créateur seul quitte → championnat supprimé ; un membre lit toujours son championnat orphelin sous RLS ; `mes_championnats` le sert sans broncher |
| Rejeu de la migration corrective sur base peuplée | **aucune notice, aucune erreur, données inchangées** — la clé étrangère n'est ni retirée ni recréée |
| Rejeu de la migration de l'étape 3 par-dessus | ne restaure ni le `not null` ni l'ancienne règle de suppression |
| Modèle de réponse backend | un championnat à `cree_par` NULL se sérialise, `est_createur` vaut `false` ; le cas nominal reste `true` |
| `npm run build` | passe, version `0.4.1` présente dans le bundle |

---

**Étape 5 — Pronostics** (version `0.5.0`)

Tableau des cotes, favoris, saisie, modification, récapitulatif. Trois tables, quatre routes d'API, trois écrans — plus le bloc « Prochain GP » de l'accueil et le `TODO` de l'étape 3 refermé.

*Schéma* — `supabase/migrations/20260813183636_favoris_pronostics.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les quatre précédentes. Idempotente.

`public.favoris` : clé primaire `(profil_id, gp_id, id_outcome_unibet)`, cascade sur les deux références. **La cote n'est pas référencée par une clé étrangère vers `public.cotes`, et c'est délibéré** : le scraper réécrit les cotes tant qu'elles ne sont pas figées, et une issue qu'Unibet retire ferait alors échouer son upsert, ou emporterait les favoris des joueurs par cascade. Le rapprochement se fait à la lecture, sur `(gp_id, id_outcome_unibet)` ; un favori orphelin est servi sans points plutôt qu'effacé. Une colonne `cree_le` est ajoutée au strict nécessaire : la rangée « MES FAVORIS » de la maquette 08 se lit dans l'ordre où le joueur a épinglé, pas dans celui que PostgreSQL décide.

`public.pronostics` : `id`, `profil_id`, `gp_id`, `id_outcome_unibet`, `type` (contrainte `check` sur `vainqueur | podium | bonus`), `cree_le`, `modifie_le`.

**L'unicité demandée ne peut pas s'écrire telle quelle.** Un index unique sur `(profil_id, gp_id, type)` interdirait aussi d'avoir plus d'un bonus, alors que la règle 4.2 en demande trois. Trois index **partiels** disent exactement ce qui était voulu :
- `(profil_id, gp_id) where type = 'vainqueur'` — un seul vainqueur par GP ;
- `(profil_id, gp_id) where type = 'podium'` — un seul podium, son détail vivant dans la table dédiée ;
- `(profil_id, gp_id, id_outcome_unibet) where type = 'bonus'` — trois bonus, mais trois **cotes différentes** : sans lui, un joueur miserait trois fois la même issue et triplerait ses points sur un seul événement.

Le maximum de trois bonus ne peut pas s'écrire en `check` — la contrainte porte sur plusieurs lignes. Un trigger `pronostics_max_trois_bonus` le fait respecter quel que soit le chemin d'écriture.

`public.pronostic_podium` : `pronostic_id` (clé primaire, cascade), `pilote_1`, `pilote_2`, avec un `check` interdisant deux fois le même pilote — miser deux fois le même reviendrait à ne remplir qu'une moitié du pronostic tout en encaissant deux fois la cote. **Aucun ordre entre les deux** : la validation de l'étape 6 demandera « ces deux pilotes sont-ils sur le podium ? », jamais « lequel devant ».

*La redondance du podium, et comment elle est tenue* — `pronostics.id_outcome_unibet` est `not null` ; pour un podium, il faut bien y mettre quelque chose. Il porte `pilote_1`, et `pronostic_podium` fait foi. Plutôt que de laisser cet accord à une convention, le trigger `pronostic_podium_coherent` en fait un invariant vérifié : il refuse un détail dont `pilote_1` diverge de l'issue du parent, et refuse d'accrocher un détail de podium à un pronostic qui n'en est pas un.

*RLS* — `public.est_membre(uuid)` de l'étape 3 est **réutilisée telle quelle**, et c'est elle qui casse la récursion. La politique de lecture des pronostics s'écrit « les miens, ou ceux d'un membre d'un championnat que je partage » ; sa sous-requête porte sur `membres_championnat`, dont la propre politique appelle `est_membre` — une fonction `security definer`, qui lit sans repasser par les politiques. **Ne jamais y réinsérer la sous-requête littérale** : PostgreSQL refuserait la requête entière (`42P17`). Le premier terme n'est pas redondant : un joueur qui n'appartient encore à aucun championnat doit pouvoir relire ses propres pronostics.

`pronostic_podium` **ne redit pas** la condition : sa politique de lecture ne teste que l'existence du pronostic parent, et cette sous-requête est elle-même filtrée par la politique ci-dessus. Écrire la règle une seconde fois créerait deux textes à maintenir en parallèle.

Les **favoris sont strictement privés**, une seule politique pour toutes les opérations. Ce sont les brouillons d'un joueur : la maquette 08 les intitule « MES FAVORIS », et les laisser lire reviendrait à annoncer ses pronostics avant de les avoir saisis.

*Quatre fonctions réservées au backend* (révoquées pour `public`, `anon` et `authenticated`, accordées au seul `service_role`) :

| Fonction | Rôle |
|---|---|
| `enregistrer_pronostics(...)` | Efface le jeu précédent et écrit le nouveau **dans une seule transaction**. Revérifie la fermeture et lève `PT423`. |
| `pronostics_du_joueur(profil, gp)` | Les pronostics d'un joueur, déjà rapprochés des cotes : pilote, marché, points. `left join` — une issue retirée depuis la saisie laisse le pronostic visible, sans points. |
| `pronostics_du_championnat(championnat, gp)` | Tous les membres, y compris ceux qui n'ont pas joué (liste vide), triés par `rejoint_le`. |
| `quitter_championnat(profil, championnat)` | Le retrait et l'effacement des pronostics, atomiques. |

`public.pronostics_fermes(uuid)` est `security invoker` et exécutable par `authenticated` : elle ne lit que `grands_prix`, déjà public.

*Le `TODO` de l'étape 3, et l'écart assumé* — il demandait d'effacer les pronostics du membre qui quitte un championnat, « dans la même transaction que le retrait ». D'où la fonction. **Mais les pronostics ne sont pas rattachés à un championnat** : un joueur remplit **un** pronostic par Grand Prix, qui compte dans **tous** ses championnats à la fois. Les effacer au départ d'un seul détruirait son classement dans les autres. Ils ne sont donc effacés que **lorsqu'il ne lui reste aucune adhésion** — l'intention du TODO (aucun pronostic orphelin ne survit à un départ) sans le dommage collatéral. Si cette lecture ne convient pas, c'est le seul point de l'étape à revoir. `DELETE /championnats/{id}/quitter` appelle désormais la fonction au lieu d'un `delete` REST ; ses statuts (`204`, `404`) sont inchangés.

*Backend* — `backend/app/api/routes/pronostics.py`, quatre routes, toutes protégées.

| Route | Comportement |
|---|---|
| `POST /grands-prix/{gp_id}/favoris` | Bascule. Retourne `{favori: true/false}`. `422` si l'issue n'existe pas pour ce GP. |
| `GET /grands-prix/{gp_id}/favoris` | Favoris de l'appelant, enrichis (pilote, marché, points), dans l'ordre d'épinglage. |
| `POST /grands-prix/{gp_id}/pronostics` | Remplace le jeu complet. `423` si la fermeture est passée. |
| `GET /grands-prix/{gp_id}/pronostics/championnat/{championnat_id}` | Pronostics de tous les membres. `403` si le demandeur n'est pas membre. |

`GET /grands-prix/{id}/cotes` **existait déjà** depuis l'étape 4 et reste dans `routes/scraper.py`, où elle est publique. Elle n'est pas redéfinie : deux handlers sur un même chemin, et c'est le premier routeur monté qui gagne, silencieusement.

**La bascule d'un favori est une suppression puis, si rien n'a été supprimé, une insertion.** Lire d'abord pour décider ensuite laisserait deux appuis rapprochés se croiser et retomber du même côté ; ici c'est la base qui tranche, et la clé primaire qui arbitre l'insertion concurrente — un `23505` signifie « l'autre a gagné la course, la cote est bien en favori », donc l'état demandé, pas une erreur.

**Le contrôle des marchés est strict, et c'est un choix.** Le vainqueur doit venir du marché `vainqueur`, les deux pilotes du podium du marché `podium`. Un pronostic « vainqueur » désignant en réalité une écurie serait impossible à valider à l'étape 6, et le joueur ne le découvrirait qu'après la course. Si Unibet renomme ces marchés, la saisie est refusée franchement, avec un message qui nomme le marché attendu, et l'écran de saisie affiche « Pronostics indisponibles » au lieu de proposer des choix invalides. Les constantes sont côté backend (`MARCHE_VAINQUEUR`, `MARCHE_PODIUM`) **et** côté frontend (`lib/pronostics.js`) : elles doivent bouger ensemble.

**Trois bonus est un maximum, pas un quota** — la maquette 09 écrit « sur 3 max » et son bouton de validation reste actif. Zéro, un ou deux bonus sont acceptés : le joueur peut enregistrer ses obligatoires et compléter plus tard, jusqu'à la fermeture. Le contrôle « les bonus sont dans les favoris » (règle 4.2) est fait par la route, pas en base, pour pouvoir **nommer la cote fautive** : « ce pronostic n'est pas dans tes favoris » sans dire lequel n'aide personne.

**La fermeture est vérifiée deux fois, et ce n'est pas une redondance.** La route refuse en `423` avant même de solliciter la base ; la fonction la revérifie au moment d'écrire. Entre les deux, quelques dizaines de millisecondes passent — et c'est précisément à cinq minutes du départ que la course aux dernières secondes a lieu. C'est la vérification en base qui fait foi ; celle de la route évite un aller-retour inutile et donne le message. **Un GP dont l'heure de départ est inconnue reste ouvert**, aux trois étages (base, backend, frontend) : refuser tout le monde parce qu'Unibet n'a pas annoncé l'horaire serait le mauvais sens du doute.

*`journaliser_echecs` est mis en commun* — le décorateur de la version `0.3.1` existait en deux copies au moment d'en écrire une troisième. Elles sont réunies dans `backend/app/api/journal.py`, avec un préfixe de domaine en paramètre (`[championnats]`, `[scraper-api]`, `[pronostics]`). **Comportement inchangé**, y compris `functools.wraps` et pour la même raison : sans lui, les routes perdraient `Depends(utilisateur_courant)` et l'en-tête `X-Admin-Secret`, et s'ouvriraient à tous. Deux contrôles du jeu de tests couvrent ce cas.

*Frontend* — trois écrans, `frontend/src/lib/pronostics.js` (accès aux données), `lib/format.js` (points, dates, compte à rebours), `lib/useFermeture.js`, et trois composants : `Onglets`, `EtoileFavori`, `Compteur`.

Les **deux chemins de données** de l'étape 3 restent en vigueur. Écritures par FastAPI. Lectures directes à Supabase là où la RLS décrit exactement le cas : le **prochain GP** de l'accueil (politique de lecture publique de l'étape 4) et les **pronostics du joueur** (politique de l'étape 5). L'accueil est le premier écran de l'app : lui faire attendre le réveil de Railway pour afficher son bloc principal serait le pire endroit où payer ce délai. Le tableau des cotes, lui, passe par l'API — elle sert les cotes déjà groupées par marché, et l'écran doit de toute façon l'appeler pour les favoris.

**`lib/format.js` est le seul endroit qui habille un nombre de points** (règle 4.1). Les maquettes 08 et 09 écrivent « ×2,80 » dans leurs cases de cote : le CLAUDE.md gagne, l'interface affiche « 280 pts ». Trois contrôles du jeu de tests vérifient qu'aucun « ×N » ne sort des trois écrans.

*Écarts assumés par rapport aux maquettes* :
1. **« ×2,80 » → « 280 pts »** (maquettes 08 et 09), règle 4.1. Sans exception.
2. **Onglets de marchés (08)** — la maquette dessine des pastilles blanches séparées dont l'active devient rouge d'un coup. Elles partagent ici une piste blanche continue, et c'est la pastille rouge qui glisse de l'une à l'autre. Une pastille ne peut pas glisser derrière des fonds opaques ; et c'est le contrôle segmenté que reconnaît immédiatement quelqu'un qui vient d'iOS. Aucune couleur, aucun rayon, aucune graisse ne change.
3. **Sélection d'un pilote (09)** — la maquette montre un emplacement vide avec un chevron, sans dire ce qu'il ouvre. C'est un accordéon qui déplie la liste des cotes du marché sous l'emplacement, plutôt qu'une feuille modale : le joueur garde ses autres choix sous les yeux, et le geste de retour ne se fait pas voler par une couche qui s'interpose.
4. **Total potentiel (10)** — ajouté sous les pronostics, absent de la maquette. C'est la question que tout le monde se pose devant un récapitulatif, et la règle 4.1 la rend calculable.
5. **Bloc de confirmation (10)** — « Pronos enregistrés ! » n'est écrit qu'au retour de l'écran de saisie. Arrivé à froid sur le récapitulatif, l'écran dit « Tes pronos sont en place » : rien ne vient d'être enregistré, le célébrer serait faux.
6. **Barre de navigation basse** — toujours pas codée, deux de ses quatre onglets n'ayant pas encore d'écran.

*Apport d'/apple-design* — zones tactiles de 44px sur l'étoile de favori et les lignes de bonus, absorbées par des marges négatives pour que l'étoile reste calée sur la ligne de la cote (sans elles, chaque rangée gagnerait 26px) ; retour tactile à l'appui sur toutes les lignes sélectionnables ; **le bouton de validation reste actif même quand la saisie est incomplète** — un bouton grisé ne dit pas ce qui manque, l'appui pose le message juste au-dessus ; le marché choisi au bord de l'écran revient sous les yeux (`scrollIntoView` centré) ; et `prefers-reduced-motion` couvre les quatre transitions ajoutées.

*Mouvement* — quatre transitions de plus, avec leurs jetons, dans `index.css` : *tabs sliding* (16) pour les onglets de marchés, *accordion expand* (21) pour le sélecteur de pilote, *icon swap* (09) pour l'étoile de favori, *number pop-in* (02) pour le compteur de bonus. Deux points à ne pas défaire : le chevron de l'accordéon **bascule** (`scaleY(-1)`) au lieu de morpher son tracé — l'interpolation CSS de `d:` n'existe que sous Chromium, et cette app vise Safari iOS ; et la pastille des onglets doit être **posée sans transition** au premier rendu, sinon elle traverse l'écran depuis `translateX(0)` et une largeur nulle à chaque arrivée.

*Accueil* — le bloc rouge annonce le prochain GP, sa date, la fermeture, et mène au tableau des cotes. Le GP retenu est celui en statut `a_venir` à la `date_course` la plus proche ; `nullsFirst: false` n'est pas cosmétique, un GP sans horaire annoncé passerait sinon devant tous les autres. Aucun GP en base est un état normal tant que le scraper n'a pas tourné : le bloc garde sa place et l'explique. Une fois la fermeture passée, le bouton mène au récapitulatif au lieu des cotes.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Migration sur PostgreSQL 16 jetable (Docker), les cinq migrations dans l'ordre, avec doublure du schéma `auth` | **70 contrôles passent** |
| Structure et contraintes | clé primaire des favoris, `check` sur le type, cascade du détail de podium, les trois index partiels, trigger `modifie_le` |
| Fermeture (règle 4.3) | ouvert à 3 jours, fermé à 2 minutes, **ouvert si la date est inconnue** |
| Enregistrement | 4 lignes écrites, détail du podium, points remontés des cotes, ordre vainqueur → podium → bonus, réenregistrement qui **remplace** sans dupliquer |
| Refus | GP fermé (`PT423`) **sans que rien n'ait été écrit malgré le `delete` initial**, quatre bonus (`PT403`) sans laisser de pronostic partiel, podium en double, type hors liste, deux vainqueurs, deux fois le même bonus, détail de podium sur un pronostic de type vainqueur, `pilote_1` divergent du parent |
| RLS sous trois identités | Alice lit les siens et ceux de Bob (même championnat), **ne voit rien de Carol** (autre championnat) ni ses détails de podium ; les favoris de Bob lui restent invisibles ; elle ne peut ni écrire, ni supprimer, ni réattribuer au nom d'un autre ; les quatre fonctions réservées lui sont refusées (`42501`) ; **aucune récursion `42P17`** |
| Départ d'un championnat | sur deux championnats : **les pronostics survivent** ; sur le dernier : pronostics et favoris effacés, détail du podium cascadé, ceux d'Alice intacts ; non-membre : `false`, rien d'effacé ; dernier membre : championnat supprimé par le trigger de la migration précédente |
| Cascades | suppression du GP et suppression du compte emportent pronostics, favoris et détails de podium |
| Rejeu des cinq migrations sur base peuplée | aucune erreur, **empreinte des pronostics identique avant et après** |
| Routes contre une doublure Supabase (auth + PostgREST en mémoire) | **49 contrôles passent** — `401` sans jeton et sur jeton inconnu pour les quatre routes (preuve que la signature survit au décorateur), en-tête sans `Bearer` ; bascule dans les deux sens, cote inexistante, GP inconnu, insertion concurrente rendue comme un ajout, favoris enrichis, ordonnés, cloisonnés entre comptes, favori dont la cote a disparu ; enregistrement nominal, zéro bonus accepté, identité prise dans le jeton et non dans le corps ; `423` avant appel et `423` gagné de vitesse en base, GP sans date ouvert, bonus hors favoris nommant la cote, podium en double, bonus en double, quatrième bonus, vainqueur et podium hors marché ; membres du championnat servis y compris sans pronostic, `403` pour un non-membre **vérifié avant l'existence du GP** ; départ atomique, effacement conditionné à la dernière adhésion ; table absente rendue avec `42P01`, panne inattendue typée, identifiant mal formé ; `/health` en `0.5.0`, cotes publiques sans jeton, routes des étapes 3 et 4 toujours protégées, préflight CORS |
| Rendu des écrans hors navigateur (`react-dom/server`, cache localStorage pré-rempli) | **66 contrôles passent** — mise en forme des points et du compte à rebours, index des cotes, organisation des pronostics (jointure PostgREST en objet **comme en tableau**, cote retirée) ; les quatre écrans se rendent sans lever, avec leurs vraies données ; **aucun « ×N » nulle part** ; GP fermé : étoiles retirées, saisie en lecture seule, plus de bouton « Modifier » ; états vides : aucun marché, aucun favori, marchés obligatoires absents, aucun pronostic, aucun GP en base ; l'accueil mène aux cotes quand c'est ouvert, au récapitulatif quand c'est fermé |
| Sous un vrai `uvicorn`, sans Supabase | les **11 routes** sont servies, `/health` en `0.5.0`, les pannes sortent avec leur trace complète sur la sortie standard |
| `npm run build` | passe, 107 modules |

**Un défaut trouvé et corrigé par ces contrôles** : le marché affiché dans le tableau des cotes était posé par un `useEffect`. Une première image se rendait donc sans aucune cote, puis la liste apparaissait d'un coup — un sursaut à chaque arrivée sur l'écran, y compris quand le cache avait déjà tout. Seul le choix explicite du joueur est désormais mémorisé ; le marché affiché s'en déduit, avec le premier pour défaut.

---

**Destination du bouton du bloc « Prochain GP »** (version `0.5.1`)

Le bouton du bloc rouge de l'accueil mène désormais à **deux écrans selon l'état du joueur** : le tableau des cotes (maquette 08) tant qu'aucun pronostic n'est enregistré pour ce GP, le récapitulatif (maquette 10) dès qu'il y en a un. Le comportement antérieur — récapitulatif une fois la fermeture passée — est conservé tel quel.

*Écart assumé sur la source de données* — la demande disait d'appeler `GET /grands-prix/{gp_id}/pronostics`. **Cette route n'existe pas** : l'étape 5 expose `POST /grands-prix/{gp_id}/pronostics` (enregistrement) et `GET /grands-prix/{gp_id}/pronostics/championnat/{championnat_id}` (tous les membres), jamais un GET des seuls pronostics de l'appelant. Le frontend les lit déjà **directement dans Supabase** via `chargerMesPronostics`, sous la politique RLS « les miens, ou ceux d'un membre d'un championnat que je partage ». C'est ce chemin qui est réutilisé, et non une nouvelle route :
- l'accueil lit déjà le prochain GP en direct **précisément** pour ne pas payer le réveil de Railway sur le premier écran de l'app — y ajouter un aller-retour Railway aurait annulé ce choix ;
- une route servant un cas déjà couvert par la RLS aurait été du code mort côté backend.

**Aucun code backend n'est touché**, `backend/app/config.py` reste donc en `0.5.0` : faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'à la version `0.2.2`).

*Ce qui change* — `chargerAccueilGp(profilId, signal)` dans `frontend/src/lib/pronostics.js` remplace l'appel direct à `chargerProchainGp` dans le bloc. Les deux lectures sont **enchaînées et non parallèles** (l'identifiant du GP n'existe qu'une fois la première revenue), et passent dans le **même passage du cache *stale-while-revalidate*** : aucun appel réseau supplémentaire ne bloque l'affichage, et l'état connu est servi immédiatement au lancement.

Trois points de mise en œuvre à ne pas défaire :

1. **L'échec de la lecture des pronostics n'emporte pas celle du GP.** Le bloc reste affiché et la destination retombe sur les cotes. C'est le bon sens du doute : l'écran de saisie sait retrouver seul les pronostics déjà enregistrés, alors qu'un récapitulatif vide serait un cul-de-sac.
2. **La clé de cache porte l'identifiant du compte** — `accueil-gp:{profil}`, au lieu de `gp:prochain`. Le prochain Grand Prix est le même pour tout le monde, l'état des pronostics ne l'est pas : deux personnes qui se relaient sur le même téléphone ne doivent jamais hériter du bouton de l'autre. C'est la règle déjà posée à l'étape 3 pour la liste des championnats.
3. **La clé est fabriquée par `cleAccueilGp(profilId)`, exportée**, et non écrite en dur à ses deux points d'usage (l'accueil la lit, `Pronostics.jsx` l'oublie après une validation réussie). Deux chaînes en dur auraient divergé au premier renommage, avec un symptôme discret : un bouton proposant encore « Pronostiquer » juste après l'enregistrement.

*Le libellé suit la destination* — « Pronostiquer » quand il reste à saisir, « Voir mes pronos » quand le bouton ouvre le récapitulatif. Un bouton nommé « Pronostiquer » qui débouche sur un récapitulatif serait une promesse fausse, et l'écran d'arrivée porte déjà son propre bouton « Modifier ». Le changement de libellé passe par `TexteEchange` (transitions-dev 04, déjà installé) : le cache peut avoir servi l'état d'avant la dernière validation, le libellé se remplace alors en place au lieu de clignoter.

*Apport d'/apple-design* — le bouton conserve sa zone tactile de 44px et son retour à l'appui. Le point traité ici relève du **wayfinding** : un même bouton mène à deux écrans, son libellé doit dire lequel. Le squelette du bloc reste affiché tant que la lecture n'a rien rendu, plutôt que d'afficher une destination devinée puis corrigée.

*Vérifié* — rendu hors navigateur (`react-dom/server`), Supabase doublé, cache localStorage pré-rempli : **26 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| `chargerAccueilGp` | GP + pronostics → destination récap ; GP sans pronostic → cotes ; **échec de la lecture des pronostics → le bloc tient debout, GP servi, destination cotes** ; échec de la lecture du GP → échec remonté ; aucun GP en base → `gp: null` sans erreur et **aucune lecture de pronostics inutile** ; session non résolue → cotes |
| Rendu du bloc | GP ouvert sans pronostic → `/cotes` et « Pronostiquer » ; GP ouvert avec pronostics → `/recap` et « Voir mes pronos » ; **GP fermé → `/recap` dans les deux cas** (comportement antérieur conservé) ; GP sans horaire annoncé → reste ouvert, destination selon l'état ; aucun GP → bloc de repli sans lien ; libellé bien porté par `TexteEchange` |
| Cloisonnement | le cache d'un compte ne fuit pas vers l'autre ; compte sans cache → silhouette, aucune destination devinée |
| Clé partagée | l'accueil et l'écran de saisie fabriquent la même clé, et l'oubli après validation vide bien le bon cache |
| `npm run build` | passe, version `0.5.1` présente dans le bundle |

`BlocProchainGp` est désormais **exporté nommément** depuis `Accueil.jsx` (l'export par défaut de l'écran est inchangé) : sans cela, le rendre hors navigateur imposait de monter `AuthProvider`, dont la session n'est résolue que dans un effet — jamais exécuté en rendu serveur.

---

**Étape 6 — Résultats OpenF1 et calcul des points** (version `0.6.0`)

Récupération des résultats, validation des pronostics, attribution des points, job automatique. Une migration, trois modules, deux routes. **Étape entièrement backend** : l'écran de résultats (maquette 11) relève de l'étape 7, avec les classements.

*Trois écarts entre la section 3.2 et ce qu'OpenF1 rend aujourd'hui.* Constatés en interrogeant l'API, ils expliquent l'essentiel du code, et **la section 3.2 n'a pas été réécrite** : elle reste le cahier des charges.

1. **On interroge par `session_key`, jamais par `meeting_key`.** La demande disait « appeler `/session_result` avec le `meeting_key` du GP ». Un *meeting* est un week-end entier : `?meeting_key=1264` rend les cinq sessions mélangées — essais, qualifications, course — donc plusieurs lignes par pilote et un classement qui n'a aucun sens. Pire, la ligne de qualification porte un `gap_to_leader` de type **liste** (`[0.0, 0.0, 0.0]`, un temps par segment Q1/Q2/Q3), **un quatrième type que la section 3.2 ne mentionne pas** et qui disparaît dès qu'on filtre sur la session de course.

2. **`dnf: true` n'implique pas `position: null`.** La section 3.2 affirme que les pilotes abandonnés ont une position nulle. C'est vrai des abandons précoces, faux de ceux qui restent classés : au GP des Pays-Bas 2025, **Norris abandonne au 64ᵉ des 72 tours et finit 18ᵉ**, `dnf: true` et `position: 18`. Les deux champs sont donc lus indépendamment — un « top 10 » se juge sur la position, un « abandon » sur `dnf`, et l'un n'annule jamais l'autre. Un test le vérifie sur les vraies données.

3. **OpenF1 limite à 3 requêtes par seconde** et répond `429` au-delà. Une récupération en enchaîne six : sans pause, les trois dernières étaient refusées et le job repassait toutes les cinq minutes sur le même mur. `_appeler` espace les appels de 0,4 s et réessaie un `429` avec une attente croissante.

*Le rapprochement GP ↔ course OpenF1 se fait sur la DATE, jamais sur le nom.* Unibet écrit « GP Pays Bas », OpenF1 « Dutch Grand Prix » : aucune correspondance textuelle ne tiendrait sur une saison, et une table de correspondance codée en dur figerait le calendrier — exactement ce que la section 3.1 interdit. `session_de_course()` prend la session `Race` de l'année dont `date_start` est la plus proche, et **refuse au-delà de 36 heures d'écart** : mieux vaut ne pas noter un GP que le noter sur les résultats d'un autre.

*Schéma* — `supabase/migrations/20260813205200_resultats_points.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les cinq précédentes. Idempotente.

`points_gagnes` (integer, nullable) sur `pronostics` et sur `pronostic_podium`, plus une contrainte `check (>= 0)` (règle 4.1 : jamais de points négatifs). **Trois états, et le troisième est le seul qui demande une convention :**

| Valeur | Sens |
|---|---|
| `NULL` | résultat inconnu, **ou marché que le calcul n'a pas su valider** |
| `0` | pronostic raté |
| `> 0` | pronostic réussi |

**`NULL` et `0` ne doivent jamais être confondus, et c'est la décision structurante de l'étape.** Un marché que le code ne sait pas juger reste à `NULL` au lieu d'être mis à `0` : marquer « raté » un pronostic qu'on n'a pas su valider volerait le joueur en silence, et rien à l'écran ne permettrait de s'en apercevoir. Les marchés Unibet varient d'un GP à l'autre (section 3.1) — ce cas n'est pas une hypothèse d'école. `NULL` se voit dans les logs, s'affiche « en attente », et se rattrape par un second passage.

**La colonne de `pronostic_podium` est redondante** avec celle du parent, et c'est assumé : elle était demandée pour que le détail d'un podium se suffise à lui-même. La redondance est tenue **par la base et non par une convention** — `attribuer_points` la dérive systématiquement de la colonne parente, dans la même transaction. Ne jamais l'écrire depuis le code applicatif, elle divergerait au premier oubli.

`public.resultats_gp` : `id`, `gp_id` (unique, cascade), `recupere_le`, `donnees_brutes` (jsonb). Lecture publique comme `grands_prix` et `cotes`, aucune politique d'écriture, aucun droit d'écriture pour `anon` ni `authenticated` — réécrire un résultat de course, c'est réécrire le classement. Un index partiel `pronostics_a_calculer_idx ... where points_gagnes is null` sert la seule requête du job et se vide de lui-même à mesure que les points sont attribués.

**`donnees_brutes` n'est pas un cache de confort** : c'est ce qui permet de rejouer le calcul **sans rappeler l'API**, donc de corriger un validateur ou d'en ajouter un pour un marché resté à `NULL`, des semaines après la course. Un seul écart au « stocker tel quel » demandé : **`/laps` est réduit au meilleur tour de chaque pilote**. La réponse complète pèse 654 Ko par GP — une ligne par pilote et par tour — à retransporter à chaque lecture. Seul le meilleur tour sert (règle 4.4). Un index `pilotes` (`{numéro → nom, écurie}`) est ajouté au même endroit : sans lui, le SQL du classement parcourrait le tableau `drivers` à chaque ligne.

*Trois étages d'idempotence*, chacun couvrant ce que les autres ne couvrent pas (section 9) :

1. **La récupération** — `resultats_gp.gp_id` est `unique`. Une ligne existante ⇒ OpenF1 n'est pas rappelée, le calcul est rejoué sur le JSON conservé.
2. **L'attribution** — `public.attribuer_points` n'écrit **que** les pronostics dont `points_gagnes` est encore `NULL`. Appelée dix fois avec des valeurs différentes, elle n'attribue rien deux fois. **C'est la base qui porte la garantie, pas le code appelant.** Un rattrapage ultérieur ne remplit que les `NULL` restants.
3. **La surveillance** — un GP passé à `termine` sort du champ de la boucle.

`attribuer_points` est réservée à `service_role` : ouverte à `authenticated`, elle laisserait n'importe qui s'attribuer le score de son choix. **C'est la fonction la plus sensible du projet.** Elle refuse aussi de noter un pronostic qui n'appartient pas au GP annoncé.

*Récupération* — `backend/app/scraper/openf1.py`. Le module ne fait que **récupérer et conserver** ; il ne juge aucun pronostic. `ResultatsIndisponibles` est distinguée d'une panne : c'est l'état normal dans l'heure et demie qui suit un départ, et le signal que le job attend pour réessayer. Un classement dont **aucune** ligne n'a de position est traité comme indisponible — OpenF1 publie parfois les lignes avant de les remplir, et noter tout le monde perdant serait le pire moment pour se tromper.

*Calcul* — `backend/app/calcul/points.py`. Il travaille **uniquement** sur le JSON conservé, jamais sur l'API.

Le **rapprochement des noms** est le point le plus fragile, et il est isolé dans `Course.pilote_du_libelle`. Unibet écrit « M.Verstappen », OpenF1 rend un `driver_number`. Cinq clés sont indexées par pilote (nom complet, nom de famille, acronyme, initiale + nom, prénom + nom). **Une clé revendiquée par deux pilotes est retirée de l'index** plutôt qu'attribuée au premier venu : deux pilotes de même nom de famille rendraient « Verstappen » ambigu, et le pronostic reste non validé au lieu d'être attribué au mauvais.

Le **safety car** est le seul point du système qui repose sur du parsing de texte, et le CLAUDE.md le signale comme tel. Deux précautions : le test « VIRTUAL » passe **avant** celui du safety car ordinaire (la chaîne « SAFETY CAR » est contenue dans « VIRTUAL SAFETY CAR ») ; et **seuls les messages `DEPLOYED` comptent** — la séquence complète est « DEPLOYED », « IN THIS LAP », « ENDING », et compter les trois ferait croire à trois interventions. Tout message de catégorie `SafetyCar` non reconnu est journalisé.

**Marchés reconnus** : vainqueur, podium, top N (rang lu dans le nom), écurie gagnante, abandon, safety car, safety car virtuel, drapeau rouge, meilleur tour. Seuls « vainqueur », « podium » et « ecurie-vainqueur » ont été **observés en vrai** — Unibet n'ouvre les marchés complets qu'à l'approche de la course. Les autres reconnaissances sont écrites d'après les libellés de la section 4.4 et **restent à confronter aux vrais marchés**. C'est exactement pour cela qu'un marché non reconnu laisse le pronostic à `NULL`. « premier-abandon » est volontairement **non reconnu** tant que la règle d'égalité de la section 4.4 n'est pas écrite : il demande de savoir *qui* a abandonné le premier, pas *si* un pilote a abandonné.

*Ce que rapporte un podium réussi : **la somme des deux cotes**.* La demande disait « points_gagnes = valeur de la cote » sans dire laquelle. Le schéma de l'étape 5 pose qu'il n'y a **aucun ordre** entre `pilote_1` et `pilote_2` ; payer la seule cote de `pilote_1` ferait donc rapporter deux montants différents au même pari selon l'ordre de saisie (280 ou 350 pour le même couple de pilotes). **Tranché en faveur de la somme**, ordre-indépendante. Un test vérifie que l'inversion des deux pilotes donne le même total. Les deux pilotes doivent être sur le podium : un seul des deux ne rapporte rien — ce n'est pas un demi-pronostic, c'est un pronostic raté.

*Job* — `backend/app/jobs/resultats.py`, scheduler APScheduler (`AsyncIOScheduler`, ajouté à `requirements.txt`) démarré dans le `lifespan` de FastAPI. Aucun processus ni thread supplémentaire, ce qui compte sur le plan gratuit. Il n'est **pas** démarré sans configuration Supabase : il journaliserait une panne toutes les cinq minutes en noyant les logs Railway, là où un avertissement au démarrage dit déjà tout.

La fenêtre de la règle 4.3 est calculée à partir de `date_course`, **sans état conservé nulle part** : un GP est à traiter entre `départ + 1h30` et `départ + 1h30 + 3h`. Un compteur de tentatives en base dirait la même chose au prix d'une colonne et d'une écriture par essai, et se désynchroniserait au premier redéploiement. Au-delà, une alerte nommant le GP et donnant la commande de rattrapage est journalisée **une seule fois** (garde-fou en mémoire ; une alerte de plus après un redéploiement est sans gravité).

**Écart assumé sur les statuts surveillés.** La demande disait « les GP en statut `cotes_figees` ». Le job surveille aussi **`a_venir`**, et c'est délibéré : **aujourd'hui rien ne fait passer un GP en `cotes_figees`** (voir « Reste à faire »), et s'en tenir à la lettre rendrait le job inopérant en pratique. Une course dont l'heure de départ est passée de 1h30 est terminée, que ses cotes aient été figées ou non.

Le GP passe à `termine` **même s'il reste des pronostics sans points** : la course est courue, et le laisser dans la boucle ferait rappeler OpenF1 toutes les cinq minutes pour rien. Les `NULL` restants sont rattrapables par un déclenchement manuel, une fois le validateur manquant écrit.

**Un seul processus doit porter ce scheduler.** Sur le plan gratuit de Railway le service tourne en un exemplaire, c'est le cas aujourd'hui. Le jour où il passe à plusieurs instances, deux schedulers tourneront en parallèle : la base empêcherait la double attribution (étage 2), mais pas les appels OpenF1 en double. Il faudra alors un `pg_try_advisory_lock` ou un worker dédié.

*Routes* — `backend/app/api/routes/resultats.py`.

| Route | Comportement |
|---|---|
| `GET /grands-prix/{id}/resultats` | **Publique** pour le classement. Avec `?championnat_id=`, exige un jeton **et** l'appartenance. `disponible: false` tant que la course n'est pas récupérée — jamais un `404`, qui ferait croire que le GP n'existe pas. |
| `POST /jobs/resultats/{id}` | En-tête `X-Admin-Secret`. **Synchrone**, avec le compte rendu complet. `425 Too Early` si les résultats ne sont pas publiés, `404` si le GP est inconnu. |

**Écart assumé sur la route de consultation, et c'est le point important.** Elle devait être « publique » et rendre « pour chaque membre du championnat ses pronostics ». Les deux ensemble sont contradictoires : la route ne reçoit aucun championnat par défaut, et surtout la politique RLS de l'étape 5 réserve la lecture des pronostics aux membres des championnats partagés. Une route publique qui les servirait ouvrirait à quiconque devine un identifiant les pronostics de n'importe quel championnat — elle contournerait, depuis le backend et avec la clé de service, **la protection même que l'étape 5 a mise en place**. Le partage retenu : classement public, pronostics des membres sur `?championnat_id=` avec jeton et appartenance vérifiée.

Le déclenchement manuel est **synchrone**, contrairement au scraper : c'est la route des tests et des interventions manuelles, et savoir combien de pronostics ont été notés — surtout lesquels sont restés en attente — est tout l'intérêt de l'appel. Il ignore la fenêtre horaire, **jamais l'idempotence**.

*Deux mises en commun* — `exiger_secret` vivait dans `routes/scraper.py` ; elle passe dans `api/deps.py` avec le domaine en paramètre, le job de résultats en ayant besoin aussi. Comportement inchangé, `secrets.compare_digest` et secret absent ⇒ route fermée compris. `utilisateur_optionnel` y est ajouté pour les routes mixtes : en-tête absent ⇒ `None`, en-tête **présent mais invalide** ⇒ `401` — accepter en silence un jeton expiré servirait la partie publique à quelqu'un qui se croit connecté. `mettre_a_jour` (PATCH) est ajouté à `supabase_client.py`.

`public.pronostics_du_joueur` est remplacée pour porter `points_gagnes` ; `pronostics_du_championnat` en hérite sans être touchée, comme les routes de l'étape 5. `PronosticServi` gagne le champ correspondant. **`points` reste ce que le pronostic PEUT rapporter (la cote), `points_gagnes` ce qu'il a rapporté** — les confondre ferait afficher un score avant la course.

*Vérifié* — **188 contrôles passent**, dont 61 contre les **vraies données du GP des Pays-Bas 2025**.

| Contrôle | Résultat |
|---|---|
| Calcul contre les vrais résultats OpenF1 (Zandvoort 2025) | **47 contrôles** — Piastri vainqueur devant Verstappen et Hadjar ; **Norris abandonne ET reste classé 18ᵉ** ; Leclerc abandonne sans position ; safety car et VSC détectés ; rapprochement de « M.Verstappen », « Verstappen », « Max Verstappen », « VER », « K.Antonelli », « Red Bull » → « Red Bull Racing » ; nom inconnu → `None` ; vainqueur, podium, top 6, top 10, écurie, abandon, safety car, drapeau rouge notés juste ; **marché inconnu non noté, avec sa raison** ; podium ordre-indépendant |
| Migration sur PostgreSQL 16 jetable (Docker), les six dans l'ordre | **53 contrôles** — structure, points négatifs refusés, un seul jeu de résultats par GP, index partiel ; **le `0` d'un raté n'est jamais réécrit** (le cas critique de l'idempotence), rattrapage d'un `NULL` sans toucher au reste, un autre GP ne peut pas noter ces pronostics, détail du podium dérivé du parent ; classement trié avec les abandons non classés en fin et les abandons classés à leur rang ; RLS, une seule politique (SELECT), `attribuer_points` refusée à `anon` et `authenticated` **sous leur vraie identité** |
| Rejeu des six migrations sur base peuplée | empreinte des pronostics, résultats bruts, points du podium et statut du GP **identiques** ; contraintes non dupliquées |
| Routes contre une doublure Supabase | **47 contrôles** — classement public sans jeton, `disponible: false` sans résultat, `404` GP inconnu, `422` identifiant mal formé ; `401` sans jeton et `403` non-membre sur `?championnat_id=`, `401` sur jeton invalide, `points_gagnes` porté jusqu'au client ; `401` sans secret et sur mauvais secret, `503` si `ADMIN_SECRET` absent, **secret vérifié avant la configuration Supabase**, `425` si les résultats ne sont pas publiés, `422` typé sur panne inattendue ; **OpenF1 n'est appelée qu'une fois**, le second déclenchement rejoue le JSON conservé ; `/health` en `0.6.0`, 13 routes, étapes 3/4/5 toujours protégées, cotes toujours publiques, préflight CORS |
| Fenêtre horaire et scheduler | **23 contrôles** — pas traité à 30 min ni à 1h29, traité à 1h31 et à 4h, plus traité à 5h ; **alerte émise une seule fois**, nommant le GP et donnant la commande de rattrapage ; `termine` hors du champ, `a_venir` et `cotes_figees` traités ; **l'échec d'un GP n'emporte pas le suivant** ; GP sans date ignoré ; scheduler démarré, un seul emploi, second démarrage sans doublon, arrêt idempotent |
| Bout en bout : vraies données OpenF1 → calcul Python → vraie base | **14 contrôles** — 5 pronostics lus comme le job les lit, 4 notés et 1 laissé à `NULL`, écriture par la **vraie** fonction SQL, points vérifiés ligne à ligne en base, second passage complet à 0 attribué et total inchangé |
| Sous un vrai `uvicorn` | scheduler démarré et journalisé, premier tour à 30 s, **la panne Supabase sort avec sa trace complète sur la sortie standard** sans casser la boucle |
| `npm run build` | passe, version `0.6.0` présente dans le bundle |

**Banc d'essai du calcul des points** (version `0.6.1`)

Le GP des Pays-Bas se court le **23 août 2026**. Le calcul de l'étape 6 devait être validé **avant**, pas découvert après : `app/calcul/points.py` reconnaît neuf familles de marchés dont **trois seulement** ont été confrontées à de vrais libellés Unibet, et un marché non reconnu laisse les points à `NULL` en silence jusqu'à ce qu'on relise les logs. Une route de test injecte donc des résultats fictifs et rend le verdict ligne à ligne, sur les **vrais pronostics déjà saisis en base**.

*Route* — `POST /jobs/resultats/{gp_id}/test`, en-tête `X-Admin-Secret`, dans `backend/app/api/routes/resultats.py`. Le secret est vérifié **avant** la configuration Supabase, comme sur les deux autres routes d'administration.

**Elle n'écrit rien, et les trois écritures absentes sont chacune un dégât évité** :

| Écriture du vrai job | Ce qu'elle aurait cassé |
|---|---|
| `resultats_gp` | `gp_id` est `unique` : un classement fictif enregistré **empêcherait définitivement** la vraie récupération OpenF1 le jour de la course. |
| statut → `termine` | Le GP sortirait de la surveillance du scheduler et ne serait **jamais** noté. |
| `points_gagnes` | `attribuer_points` n'écrit que les `NULL` : un essai les remplirait avec des valeurs inventées **que le vrai job ne corrigerait plus jamais**. |

C'est ce qui rend l'essai reproductible : on le rejoue autant de fois qu'on veut, avec des classements différents. Le champ `points_en_base` de la réponse le prouve — il ne bouge pas.

**Tous** les pronostics du GP sont évalués, y compris ceux qui ont déjà des points. Le filtre `points_gagnes is null` du vrai job est un mécanisme d'idempotence, pas une règle de calcul : ici il masquerait précisément les lignes qu'on veut vérifier.

Le jugement n'est pas réécrit : la route appelle `calcul.points_du_pronostic`, **la fonction même sur laquelle `calculer()` boucle** dans le job, et lit les cotes par `jobs.resultats.cotes_du_gp` (passée de privée à publique pour cela). Ce qui est validé ici est bien ce qui tournera dimanche.

*Corps de la requête — deux formes acceptées.* Le tableau nu de `session_result` documenté :

```bash
curl -X POST https://<railway>/jobs/resultats/<gp_id>/test \
  -H "X-Admin-Secret: <valeur>" -H "Content-Type: application/json" \
  -d '[{"driver_number":12,"position":1,"dnf":false,"dns":false,"dsq":false,
        "points":25,"number_of_laps":72,"gap_to_leader":0}]'
```

…ou un objet portant en plus `race_control` et `laps`. Ce n'est pas un supplément gratuit : **safety car, drapeau rouge et meilleur tour sont les marchés annoncés en section 4.4 qu'aucun vrai libellé Unibet n'a jamais confrontés**, et sans ces deux tableaux ils resteraient les seuls impossibles à essayer avant la course. Les lignes acceptent les champs supplémentaires (`extra="allow"`) : une réponse OpenF1 réelle se colle telle quelle.

*Réponse* — par pronostic : `profil_id`, `type`, `id_outcome_unibet`, `marche`, `pilote`, `points` (le potentiel), **`points_gagnes` (le calculé)**, `reussi`, `detail`, `raison` si le marché n'est pas reconnu, et `points_en_base`. Plus un `course` disant ce que le calcul a **compris** des données fictives (vainqueur, classés, abandons, safety car, VSC, drapeau rouge, meilleur tour) : sans lui, un safety car mal orthographié dans le corps donnerait des pronostics ratés sans qu'on sache si c'est le pronostic ou la donnée d'essai qui est en cause.

`points` d'un podium est la **somme des deux cotes**, pas celle de `pilote_1` : c'est la règle tranchée à l'étape 6, et afficher la seule cote du parent montrerait un potentiel deux fois trop faible.

---

*`backend/app/calcul/pilotes.py` — la grille 2026, et le trou qu'elle bouche.*

Unibet nomme ses issues par un libellé de pilote, OpenF1 par un `driver_number`. Le module ne fait pas le rapprochement — c'est `points.py` qui le fait — il fournit **la matière** : qui court en 2026, sous quel numéro, sous quels libellés Unibet. Deux usages : fabriquer l'index de pilotes du banc d'essai sans appeler OpenF1, et **compléter le rapprochement de noms du vrai calcul**.

Ce second usage n'était pas prévu, et il corrige un défaut réel. Les cinq clés dérivées de chaque pilote (nom complet, nom de famille, acronyme, initiale + nom, prénom + nom) couvrent 20 des 22 pilotes. Elles échouent sur deux, relevés sur les **vraies cotes en base** :

- **`AK.Antonelli`** — OpenF1 abrège son prénom en « Kimi », Unibet garde les deux initiales d'« Andrea Kimi ». C'est le **favori du GP à 280 pts** : sans alias, tous les pronostics le désignant seraient restés à `NULL`.
- **`C.Sainz Jr`** — Unibet suffixe, OpenF1 non.

Les alias passent par la **même mise en concurrence** que les autres clés : un alias qui entrerait en collision avec un pilote existant serait retiré comme n'importe quelle ambiguïté, jamais imposé.

**Le garde-fou de saison est le point à ne pas défaire.** `alias_unibet()` exige le **numéro et le nom de famille**, et ne rend rien s'ils ne concordent pas avec la table. Les numéros sont réattribués d'une année sur l'autre (Norris porte le 1 en 2026, Verstappen l'avait avant) : sans cette vérification, une table périmée collerait les alias d'Antonelli sur le nouveau titulaire du 12. Avec elle, une table périmée ne fait aucun dégât — elle ne rend rien, et le pronostic reste non validé, ce qui se voit dans les logs. **À mettre à jour à chaque saison.**

`_cle()` duplique volontairement `points.normaliser` en deux lignes : `points` importe ce module, l'importer en retour ferait un cycle.

*Écart assumé par rapport à la demande* — elle demandait « une table de correspondance `driver_number` → `id_outcome_unibet` ». **Cette table ne peut pas exister** : `id_outcome_unibet` change à chaque Grand Prix (Antonelli vaut `o701093319` au marché « Vainqueur » du GP Pays-Bas et `o701094802` au marché « Podium » du même GP). Ce qui est statique, c'est `driver_number` → **libellé Unibet** ; l'identifiant d'issue se retrouve ensuite dans `public.cotes`, qui le porte déjà. C'est donc cette table-là qui est écrite, et le second paragraphe de la demande la décrivait exactement ainsi.

*Vérifié* — **83 contrôles passent** contre une doublure Supabase en mémoire, avec les **vraies cotes du GP Pays-Bas 2026** relevées chez Unibet (22 pilotes) et les **vrais numéros OpenF1 2026**.

| Contrôle | Résultat |
|---|---|
| Grille | 22 pilotes, index à clés chaînes et de la même forme qu'OpenF1 ; alias servis pour Antonelli et Sainz, aucun pour les 20 autres ; **numéro réattribué → alias refusé**, numéro inconnu → rien |
| Rapprochement des 16 libellés Unibet réels | tous retrouvés, `AK.Antonelli` et `C.Sainz Jr` compris ; libellé inconnu → `None` ; six écuries dont « Red Bull » → Red Bull Racing, « Haas » → Haas F1 Team, « Audi F1 Team » → Audi |
| Protection | `401` sans secret et sur mauvais secret (**la signature survit au décorateur**), `404` GP inconnu, `422` identifiant mal formé, `422` classement vide |
| **Aucune écriture** | ni RPC, ni upsert, ni PATCH après trois essais successifs ; `ecrit_en_base: false` ; `points_en_base` inchangé pour le pronostic déjà noté ; **le filtre `points_gagnes is null` n'est jamais envoyé** |
| Verdicts | Antonelli vainqueur → 280 pts ; Verstappen vainqueur → **0, jamais NULL** ; podium Antonelli + Norris → **297 = 135 + 162**, identique en ordre inversé ; écurie Mercedes → 215, Red Bull → 0 ; **marché non reconnu → `NULL` avec sa raison nommant le marché** ; compteurs et total justes |
| Résumé de course | vainqueur, 5 classés, 2 abandons, **Verstappen abandonne ET reste classé 15ᵉ** (le cas Norris/Zandvoort 2025) |
| Forme étendue | safety car, VSC et drapeau rouge détectés séparément, meilleur tour attribué, verdicts identiques à la forme nue |
| Reproductibilité | second appel strictement identique ; un autre classement donne un autre verdict (Verstappen 950, Antonelli 0) ; toujours rien d'écrit |
| Routes existantes | `/health` en `0.6.1`, 14 routes, le vrai job exige toujours son secret, `/championnats/moi` toujours protégée, cotes toujours publiques |
| Sous un vrai `uvicorn` | route servie, `401` sans secret **avant** le contrôle de configuration, `503` explicite ensuite |
| `npm run build` | passe, version `0.6.1` présente dans le bundle |

---

**Étape 7 — Classements** (version `0.7.0`)

Vue liste et vue piste. Une migration, une route d'API, un composant `<Voiture />`, deux écrans. Le calendrier du championnat (maquette 15) reste à faire — voir « Reste à faire ».

*Schéma* — `supabase/migrations/20260814103000_classement_championnat.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les six précédentes. Idempotente. Elle ne crée **aucune table** : le classement se calcule à la volée, il ne se matérialise pas.

C'est la question laissée ouverte par la section « Décisions validées » et elle est tranchée en faveur du calcul à la volée. Une table de classement serait un doublon de `points_gagnes`, à retenir cohérent à chaque attribution, à chaque départ d'un membre et à chaque rattrapage d'un `NULL` — trois occasions de diverger pour un gain nul à cette échelle. Un index partiel suffit : `pronostics_notes_par_profil_idx on (profil_id, points_gagnes) where points_gagnes is not null`. Il ne porte que sur les lignes déjà notées et complète, sans le remplacer, `pronostics_a_calculer_idx` de l'étape 6, qui porte exactement sur les lignes inverses.

`public.classement_du_championnat(uuid)` rend une ligne par membre, **déjà triée et déjà rangée** : `profil_id`, `pseudo`, `total_points`, `pronostics_reussis`, `meilleure_cote`, `ordre_inscription`, `rang`. Agréger en base n'est pas un raffinement — sans cela il faudrait transporter tous les pronostics notés de tous les membres, une centaine de lignes par personne sur une saison, pour n'en tirer que trois nombres.

**Les points ne sont pas cloisonnés par championnat**, et c'est la règle posée à l'étape 5 : un joueur remplit **un** pronostic par Grand Prix, qui compte dans **tous** ses championnats à la fois. La somme porte donc sur tous ses pronostics notés ; le championnat dit **qui** classer, pas quels pronostics compter. Un test le vérifie explicitement : le même joueur retrouve ses 700 points dans son second championnat.

**Trois points de mise en œuvre à ne pas défaire :**

1. **`row_number` et non `rank`** pour le rang. Les quatre critères de la règle 4.6 réunis départagent toujours ; `rank` afficherait « 1, 1, 3 » sur une égalité que le classement sait pourtant trancher.
2. **`left join lateral` et non un `group by`** sur une jointure. Un membre qui n'a jamais pronostiqué doit apparaître avec 0 point, pas disparaître de la liste des membres.
3. **`ordre_inscription` départage par `profil_id` à `rejoint_le` égal.** Deux adhésions au même instant donneraient sinon une numérotation instable d'un appel à l'autre — et deux membres échangeraient leurs couleurs de voiture entre deux rafraîchissements.

**`meilleure_cote` vaut `NULL`, jamais `0`, pour qui n'a rien réussi.** C'est la même convention qu'à l'étape 6 : `0` dirait « son meilleur coup vaut zéro », ce qui n'est pas « il n'a pas encore de meilleur coup ». Le tri, lui, ramène le `NULL` à `0` — un membre sans réussite ne peut pas passer devant.

*La fonction est `security definer` et réservée à `service_role`.* Elle est paramétrée par un championnat, donc elle lit forcément les pronostics d'autrui. Sous l'identité de l'appelant, la politique RLS de l'étape 5 filtrerait les membres avec qui il ne partage rien — exactement ce qu'il faut protéger, mais qui rendrait ici un classement **silencieusement amputé** au lieu d'un refus franc. L'autorisation est donc portée par la route, qui vérifie l'appartenance **avant** l'appel.

*Backend* — `GET /championnats/{id}/classement`, dans `routes/championnats.py`. Authentifiée, l'appelant doit être membre. `exiger_membre` est **réutilisée telle quelle** depuis `routes/pronostics.py`, comme le fait déjà `routes/resultats.py` depuis l'étape 6 : une troisième copie du même contrôle d'appartenance serait une occasion de plus de le corriger à un seul endroit. Le décorateur `journaliser_echecs` est celui de la version `0.3.1`.

Le modèle `LigneClassement` déclare `meilleure_cote: int | None` et non `int` : un championnat où personne n'a encore marqué ferait sinon échouer la validation de la réponse, donc rendre **toute** la liste en `500` — le même piège que `cree_par` à la version `0.4.1`.

*Le composant `<Voiture />`* — `frontend/src/composants/Voiture.jsx`, tiré de `assets/voiture.svg`. Props `couleur1`, `couleur2`, `numero`, `nom`. Le fichier d'origine codait en dur un rouge Ferrari décliné en cinq nuances ; elles sont réparties sur **deux** couleurs, ce que demande la section 5 :

- `couleur1` peint la coque — la plus grande surface, celle qui se reconnaît de loin ;
- `couleur2` peint les deux ailerons, avant et arrière, seuls éléments dont la forme reste lisible à 56px de large.

**Les pièces mécaniques gardent leurs gris d'origine** (pneus, suspensions, fond plat, casque). Les repeindre ferait perdre la lecture de l'objet : une voiture entièrement monochrome n'a plus de roues.

Le numéro s'écrit sur le museau, le nom sur l'aileron arrière, **chacun dans l'encre qui contraste avec l'aplat qui est sous lui** — un numéro blanc sur une livrée blanche ne dirait plus rien, et le numéro est la seule chose qui identifie une voiture à cette taille. `encreSur()` calcule la luminance relative WCAG et rend `#1A1A1A` ou `#FFFFFF`.

Deux corrections par rapport au SVG d'origine : le numéro passe en `text-anchor="middle"` (le calage manuel décentrait un numéro à deux chiffres), et **la taille du nom suit la longueur du pseudo** — à taille fixe, « Alexandrin » débordait des deux côtés de l'aileron. La graisse 700 n'apparaît que là, comme le veut la section 5.

*Les livrées* — `frontend/src/lib/livrees.js`, dix combinaisons attribuées **par ordre d'inscription** : le premier membre prend la première, le deuxième la deuxième, et au-delà de dix on boucle.

**C'est `ordre_inscription` qui donne l'indice, jamais le rang**, et c'est le point à ne pas défaire : une livrée qui suivrait le classement ferait échanger leurs couleurs à deux membres qui se doublent. Reconnaître quelqu'un du coin de l'œil sur la piste n'a de sens que si sa voiture ne change jamais de couleur.

*Écart assumé par rapport à la section 5* — la palette de l'app compte sept couleurs ; dix livrées distinctes n'en sortiraient pas. Ces couleurs **ne peignent que les voitures**, jamais un fond, un bouton ou un texte d'écran, et la maquette 07b fait déjà ce choix en dessinant des voitures ambre, rouge, marron, bleue et violette. Les deux premières livrées reprennent d'ailleurs `primaire` et `texte` du design system plutôt que d'inventer un rouge et un noir de plus.

`couleurLisible()` traite les deux livrées à dominante blanche : posée telle quelle sur une carte `surface`, leur pastille disparaîtrait, on prend alors la seconde couleur. C'est ce qui permet à `Pastille` de porter la couleur de la voiture de son membre — **la même personne se reconnaît du même coup d'œil au classement et sur la piste**.

*Vue liste (maquette 07)* — l'écran de l'étape 3 est enrichi. Bascule segmentée Classement / Piste, puis le classement réel : rang, pastille à la couleur de la livrée, pseudo, total en points, et une sous-ligne portant les deux critères de départage suivants.

**La sous-ligne s'écarte de la maquette**, qui y répète le total déjà affiché à droite. Elle dit « 4 réussis · meilleur coup 950 pts » : ce qui sépare deux joueurs à égalité de points est plus utile que le même nombre écrit deux fois. Avant le premier Grand Prix, elle dit « En attente du premier Grand Prix » plutôt que d'afficher un meilleur coup qui n'existe pas.

**Le classement remplace la liste des membres, mais ne l'efface pas.** Les deux chargements sont indépendants : le championnat et ses membres se lisent directement dans Supabase sous RLS (étape 3), le classement passe par l'API. Tant que Railway se réveille — ou même s'il échoue — la liste des membres tient sa place, avec les mêmes personnes et sans les points. Un bloc vide serait pire, et c'est la seule raison pour laquelle l'ancienne liste est conservée dans le code.

*Vue piste (maquette 07b)* — `frontend/src/ecrans/Piste.jsx`, route `/championnats/:id/piste`. Asphalte `#1A1A1A` plein cadre, bordures rouge et blanc de 20px sur les deux côtés (rectangles de 20px de haut), ligne pointillée centrale, ligne d'arrivée en damier tout en haut. **Aucun fond beige n'est visible** : c'est le seul écran de l'app qui sorte de la surface `fond`.

Bordures, ligne médiane et damier sont des **dégradés répétés**, pas des séries de blocs : la cadence reste la même quelle que soit la hauteur d'écran, et le motif ne coûte aucun nœud du DOM.

*Écart assumé par rapport à la maquette 07b*, et il vient de la demande : la maquette garde l'en-tête du championnat, la bascule et la barre de navigation basse autour de la route. Ici la route occupe l'écran entier et un unique bouton de retour, en haut à gauche sous la zone sûre, ramène au classement. C'est l'écran signature — lui laisser 150px de chrome au-dessus en ferait un widget de plus. Le bouton **nomme sa destination** (« Classement ») : c'est le seul moyen de sortir d'ici, il doit dire où il mène.

**Le placement des voitures** est proportionnel aux points — le leader tout en haut, quelqu'un à la moitié de ses points à mi-piste — puis corrigé par **deux passes de relaxation**. Elles ne sont pas un ornement : sans elles, deux membres séparés de dix points verraient leurs voitures se superposer et la vue ne dirait plus rien. La passe descendante impose l'écart minimal depuis le leader, la passe montante rattrape ce qui a débordé en bas. L'écart minimal est **plafonné à la place réellement disponible**, ce qui garantit que tout le monde tient à l'écran quel que soit le nombre de membres (règle 4.5 : aucune limite). Vérifié à 25 membres.

**Si personne n'a marqué, la fraction vaut zéro pour tout le monde et les voitures se regroupent en bas** — la grille de départ avant le premier Grand Prix. C'est la passe montante qui produit ce résultat, en les empilant depuis le bas dans l'ordre du classement.

La hauteur de la piste est **mesurée** (`ResizeObserver`), pas devinée : sur iOS elle change quand la barre d'adresse de Safari se rétracte. Les voitures ne s'élancent qu'une fois la mesure faite — les lancer avant les ferait converger vers zéro puis sauter.

Voiture et légende vivent dans **une seule rangée** positionnée en absolu. Deux éléments placés séparément, l'un au centre et l'autre à droite, finiraient par se décaler d'un pixel ou deux ; ici l'alignement est une conséquence de la structure. L'ombre portée de la légende n'est pas décorative : ce texte passe tantôt sur l'asphalte, tantôt sur une bordure blanche.

**Le numéro affiché sur la voiture est le rang**, comme dans la maquette. C'est provisoire : la section 5 prévoit un numéro libre choisi dans le profil, qui arrivera avec l'étape 8 et prendra sa place sans toucher au composant.

*Mouvement* — une transition de plus, d'après *texts reveal* (transitions-dev 18), avec ses jetons dans `index.css`. Le snippet monte des lignes de texte de 12px avec 40ms de décalage ; ici chaque voiture part du bas de l'écran, d'une **distance qui lui est propre** (`--voiture-depart`, écrite en ligne : elle dépend de la position d'arrivée), et le décalage passe à **100ms** pour que les voitures se suivent au lieu de monter en bloc. Structure, propriétés animées et garde-fou `prefers-reduced-motion` sont ceux du snippet.

Le retard est écrit en ligne plutôt que par des classes `--N` : **le nombre de membres n'est pas borné**, on ne peut pas déclarer une classe par rang.

La bascule Classement / Piste reprend *tabs sliding* (16), déjà installé pour les onglets de marchés de la maquette 08. `BasculeVue` est un composant à part et non un paramètre d'`Onglets` : les onglets de marchés se mesurent à leurs libellés et débordent en défilement, la bascule occupe toute la largeur en deux moitiés fixes. La pastille doit y être **posée sans transition au premier rendu**, exactement pour la même raison qu'à l'étape 5.

*Apport d'/apple-design* — bouton de retour à 44px avec retour tactile à l'appui, et zones sûres traitées séparément du rembourrage : `pt-safe-top` et `pb-3` écriraient la même propriété, la marge du home indicator **s'ajoute** au rembourrage au lieu de le remplacer. La piste, elle, court **sous** les zones sûres : une piste qui s'arrêterait à la Dynamic Island se lirait comme un bandeau. Le nom du championnat ferme l'écran en bas — il dit de quel championnat on regarde la piste sans rajouter d'en-tête. Le mouvement d'entrée des voitures est intégralement couvert par `prefers-reduced-motion`.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Migration sur PostgreSQL 16 jetable (Docker), les sept dans l'ordre, avec doublure du schéma `auth` | **28 contrôles passent** |
| Règle 4.6, critère par critère | égalité de points départagée par les **réussis** ; à points et réussis égaux, la **meilleure cote** tranche — et l'ordre d'inscription est vérifié comme ne pouvant pas l'expliquer ; à tout égal, l'**ordre d'inscription** départage ; rangs sans ex æquo (1, 2, 3, 4) |
| Comptage | un pronostic à `0` compte dans le total mais pas dans les réussis ; un pronostic à `NULL` ne compte nulle part ; membre sans aucun pronostic servi à `0` et non exclu ; `meilleure_cote` **NULL et non 0** pour qui n'a rien réussi |
| Cloisonnement | **les points suivent le joueur dans tous ses championnats** ; championnat inconnu → tableau vide, jamais une erreur ; classement à blanc → tout le monde à 0 |
| Droits | `anon` et `authenticated` refusés **sous leur vraie identité** (`42501`), `service_role` sert ; fonction bien `security definer` ; index partiel créé, celui de l'étape 6 intact |
| Rejeu des sept migrations sur base peuplée | aucune erreur, **empreinte des pronostics et classement rendu identiques avant et après** |
| Route contre une doublure Supabase (auth + PostgREST en mémoire) | **26 contrôles passent** — `401` sans jeton, sur jeton inconnu et sur en-tête sans `Bearer` (preuve que la signature survit au décorateur) ; **`403` pour un non-membre, vérifié avant tout appel à la fonction de classement** ; `422` sur identifiant mal formé ; ordre, rang, total, réussis, meilleure cote et ordre d'inscription portés jusqu'au client ; membre sans point servi à `0` ; classement vide en `200` ; table absente rendue en `422` portant `42P01` ; `/health` en `0.7.0`, 15 routes, routes des étapes 3 à 6 intactes, préflight CORS |
| Rendu hors navigateur (`react-dom/server`) | **77 contrôles passent** |
| Livrées | dix combinaisons distinctes, deux couleurs par livrée ; 1ᵉʳ → 1ʳᵉ, 10ᵉ → 10ᵉ, **11ᵉ et 21ᵉ bouclent sur la 1ʳᵉ** ; ordre absent → repli sans lever ; encre contrastée sur clair comme sur sombre ; livrée blanche servie par sa seconde couleur sur carte blanche |
| Voiture | se rend sans lever ; `couleur1` sur la coque, `couleur2` sur les ailerons, **aucune des cinq couleurs d'origine ne subsiste** ; pneus toujours sombres ; numéro et nom écrits, encre du nom contrastée avec l'aileron ; pseudo tronqué à 10 caractères, numéro à 3 ; **taille du nom décroissante et tenant dans l'aileron** ; sans nom ni numéro, aucun `<text>` |
| Placement | leader le plus haut, dernier le plus bas, ordre croissant, tout le monde dans la piste, **aucun chevauchement**, hauteur proportionnelle aux points ; **tous à zéro → regroupées en bas, non superposées, la dernière touchant le bas** ; 25 membres tiennent tous à l'écran et restent dans l'ordre ; un seul membre, aucun membre, hauteur non mesurée → aucune division par zéro |
| Écrans | la rangée porte sa classe d'entrée, son retard et sa distance de départ calculée ; **la livrée suit l'ordre d'inscription et non le rang** ; ligne de classement complète (rang, pseudo, total, « pts », réussis, meilleur coup, « Toi », « Créateur », pastille à la couleur de la livrée) ; saison non commencée → aucun meilleur coup inventé ; singulier/pluriel de « réussi » ; **aucun « ×N » nulle part** (règle 4.1) ; les deux écrans se montent sans lever, bascule rendue en contrôle segmenté accessible |
| Sous un vrai `uvicorn` | `/health` en `0.7.0`, `401` sans jeton sur la nouvelle route, `503` avec **trace complète sur la sortie standard** quand Supabase est injoignable |
| `npm run build` | passe, 112 modules |

---

**Étape 8 — Profils, statistiques et personnalisation de la voiture** (version `0.8.0`)

Trois colonnes sur `profils`, une fonction de statistiques, trois routes d'API, trois écrans. Les livrées automatiques de l'étape 7 disparaissent : chacun choisit désormais ses couleurs et son numéro, et c'est cette voiture-là qui roule sur la piste.

*Schéma* — `supabase/migrations/20260814162200_profil_voiture_stats.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les sept précédentes. Idempotente. Elle ne crée **aucune table** : elle altère `profils`, ajoute une fonction et en remplace une.

`public.profils` gagne `couleur1` (défaut `#800111`), `couleur2` (défaut `#FFFFFF`) et `numero` (nullable). Ces trois colonnes vivent sur le **profil** et non sur l'adhésion à un championnat : la section 5 dit « une seule voiture, identique dans tous ses championnats », et les poser sur `membres_championnat` autoriserait exactement ce qu'elle exclut.

**Trois contraintes, dont deux au-delà de ce qui était demandé.**
- `profils_numero_valide` — le numéro va de 1 à 99, comme un vrai numéro de Formule 1. C'est la contrainte demandée.
- `profils_couleurs_hex` — format `#RRGGBB`. Ces deux valeurs partent **telles quelles dans l'attribut `fill` d'un SVG** côté frontend. Le contrôle de la route peut être contourné : la politique RLS « Chacun modifie son profil » porte sur la **ligne**, pas sur la colonne, donc n'importe quel client Supabase peut écrire ces colonnes sans passer par `PATCH /profils/moi`. La base, elle, ne se contourne pas.
- `profils_couleurs_distinctes` — les deux couleurs diffèrent, à la casse près. Ce n'est pas du confort : la seconde peint les ailerons, seuls éléments dont la forme reste lisible à 56px de large sur la vue piste, et le nom écrit sur l'aileron arrière perdrait son fond.

**Aucune contrainte d'unicité sur `numero`, et c'est délibéré.** Une voiture étant identique dans tous les championnats de son propriétaire, un numéro unique globalement voudrait dire **99 comptes maximum sur toute l'application** — absurde pour une app ouverte au public (section 1). L'unicité se juge par championnat, à l'affichage, et reste **indicative** : le frontend avertit, il ne bloque jamais.

*RLS* — les deux politiques demandées existaient déjà depuis la migration des profils (étape 2) et couvrent exactement ce cas : lecture ouverte à tout membre connecté (les classements et les profils ont besoin des pseudos et des voitures des autres), écriture réservée au propriétaire de la ligne. Elles sont **réaffirmées à l'identique** dans cette migration pour qu'elle décrive complètement l'état qu'elle suppose. Conséquence : deux fichiers déclarent les mêmes politiques, et rejouer l'ancien par-dessus le nouveau les rétablirait telles quelles — ce qui est sans effet ici, les deux textes étant identiques.

*`public.stats_du_profil(uuid, integer)`* — les quatre chiffres de la grille 2×2 des maquettes 12 et 14, calculés en base pour la même raison que le classement de l'étape 7 : sans cela il faudrait transporter tous les pronostics d'une saison, plus les cotes correspondantes, pour n'en tirer que quatre entiers.

| Champ | Calcul |
|---|---|
| `paris_gagnes_pct` | pronostics réussis ÷ pronostics **notés**, en pourcentage entier |
| `pts_moyen_gp` | somme des `points_gagnes` ÷ nombre de **GP joués** (ceux où au moins un pronostic est noté) |
| `meilleur_coup` | plus fort `points_gagnes` sur un seul pronostic |
| `cote_moy_tentee` | moyenne des cotes tentées, tous GP confondus, jugés ou non |

**La saison est l'année civile du Grand Prix, lue en UTC.** `date_course` est stockée en UTC depuis l'étape 4 ; l'ancrer explicitement (`at time zone 'UTC'`) évite que le résultat dépende du fuseau de la session PostgreSQL. Un GP dont l'horaire n'est pas encore annoncé n'appartient à aucune saison et n'entre dans aucune statistique — le rattacher à l'année courante serait une supposition.

**Un podium compte pour la SOMME de ses deux cotes** dans `cote_moy_tentee`. C'est la règle tranchée à l'étape 6 pour ce qu'un podium *rapporte* ; comparer une moyenne de cotes tentées à des points gagnés calculés autrement n'aurait aucun sens. Une cote retirée par Unibet depuis la saisie est **écartée de la moyenne, jamais comptée zéro** : le joueur n'a rien tenté de tel.

Trois compteurs sont servis en plus des quatre demandés — `pronostics_notes`, `gp_joues`, `total_points`. Ils ne s'affichent pas tels quels : ils disent à l'interface **si la saison a commencé pour ce membre**. Sans eux, « meilleur coup 0 » et « 0 % de paris gagnés » s'afficheraient avant le premier Grand Prix, ce qui se lit comme un mauvais bilan alors qu'il n'y a pas encore de bilan du tout.

La fonction est `security definer` et réservée à `service_role`, pour la raison exacte du classement de l'étape 7 : paramétrée par un profil, elle lit forcément les pronostics d'autrui, et sous l'identité de l'appelant la politique RLS de l'étape 5 rendrait une moyenne **silencieusement fausse** au lieu d'un refus franc. **Aucun index nouveau** : les deux index partiels de l'étape 6 et de l'étape 7 (`points_gagnes is null` et `is not null`) portent ensemble sur toutes les lignes et commencent tous deux par `profil_id`.

*`classement_du_championnat` porte désormais la voiture* — trois champs de plus (`couleur1`, `couleur2`, `numero`), le reste du corps est inchangé. Un profil manquant retombe sur les défauts de la colonne : sans ce `coalesce`, le SVG afficherait des aplats transparents. `ordre_inscription` reste servi — il est le 4ᵉ critère de départage de la règle 4.6, ce que la personnalisation ne change pas.

*Backend* — `backend/app/api/routes/profils.py`, trois routes, toutes protégées.

| Route | Comportement |
|---|---|
| `GET /profils/{id}` | Pseudo, couleurs, numéro, date de création. `404` sur profil inconnu. |
| `GET /profils/{id}/stats` | Statistiques de la saison en cours. `403` si l'appelant n'est ni le membre lui-même ni membre d'un de ses championnats. |
| `PATCH /profils/moi` | Modifie couleurs et numéro. Partiel : ce qui n'est pas transmis n'est pas touché. Rend le profil à jour. |

**Deux niveaux d'autorisation, et la différence est voulue : chaque route est alignée sur la politique RLS de la donnée qu'elle sert.** `GET /profils/{id}` reste ouvert à tout appelant authentifié, comme la politique « Profils lisibles par les membres connectés » qui sert déjà ces colonnes au frontend en lecture directe — restreindre la route serait du théâtre, et empêcherait d'afficher une voiture dans un classement. `GET /profils/{id}/stats` agrège en revanche des `points_gagnes`, que la politique de l'étape 5 réserve aux membres d'un championnat partagé : servie sans contrôle avec la clé de service — qui contourne la RLS — elle donnerait le résumé de saison de n'importe qui à n'importe quel inscrit. C'est le raisonnement de l'étape 6 sur `?championnat_id=`, appliqué ici.

**Le refus précède l'existence.** Sur `/stats`, l'appartenance est vérifiée **avant** de lire le profil visé : un `404` sur un identifiant inconnu apprendrait à un curieux lesquels sont de vrais comptes. Un identifiant inconnu sort donc en `403`. Son propre profil, lui, passe sans aucune lecture d'adhésion — quelqu'un qui n'appartient encore à aucun championnat doit pouvoir consulter ses statistiques.

**`retirer_numero` est un drapeau explicite, et il n'est pas décoratif.** Les trois champs du corps étant facultatifs, `numero: null` serait indiscernable de « champ non transmis » : sans ce drapeau, un membre ne pourrait **plus jamais** revenir à l'état sans numéro une fois qu'il en a choisi un.

**La comparaison des deux couleurs porte sur le couple résultant, pas sur ce qui a été transmis.** N'envoyer que `couleur1`, égale à la `couleur2` déjà en base, produirait sinon une voiture monochrome sans que rien ne soit refusé. Les couleurs sont normalisées en majuscules ; le profil rendu par la route fait foi côté frontend, pas la saisie.

*Frontend* — `lib/palette.js` (les vingt couleurs et les helpers de contraste), `lib/profils.js` (accès aux données), `composants/GrilleStats.jsx`, `composants/SelecteurCouleur.jsx`, et trois écrans : `MonProfil.jsx` (14), `ProfilMembre.jsx` (12), `GrandsPrixDuMembre.jsx` (13).

**`lib/livrees.js` est supprimé.** Les dix livrées attribuées par ordre d'inscription n'avaient de raison d'être que tant que rien ne permettait de choisir. Les trois helpers de couleur qu'il portait (`encreSur`, `couleurLisible`, la luminance WCAG) vivent désormais dans `palette.js`, et `couleurLisible` accepte n'importe quel objet `{couleur1, couleur2}` — une ligne de classement comme un profil.

*Écart assumé par rapport à la section 5, le même qu'à l'étape 7* — la palette de l'app compte sept couleurs, vingt teintes n'en sortiraient pas. Celles-ci **ne peignent que les voitures**, jamais un fond, un bouton ou un texte d'écran. Quatre reprennent le design system plutôt que d'inventer un ton de plus : bordeaux `#800111`, marron `#543925`, amber `#E8A020`, beige `#F5F0EB`.

**Conséquence assumée de la personnalisation, et c'est le point à surveiller.** Les livrées garantissaient dix voitures distinctes dans un championnat ; les défauts, eux, sont les mêmes pour tout le monde. Tant que personne n'a personnalisé sa voiture, la vue piste montre donc **N voitures identiques** — là où l'étape 7 en montrait dix différentes. Le pseudo écrit sur l'aileron arrière reste le seul discriminant. C'est le prix de la décision « les vraies couleurs du membre », prise dans le chat principal ; si la lisibilité de la piste prime, c'est le **défaut de la colonne** qu'il faut reprendre (une livrée dérivée de l'ordre d'inscription à la création du profil), pas le code des écrans.

*Les deux chemins de données restent en vigueur*, et le partage se fait ici encore selon la politique RLS de la donnée servie. Profil et statistiques passent par l'API (elles agrègent des pronostics). Les **numéros déjà pris** et les **Grands Prix pariés** vont directement à Supabase.

**Écart assumé sur la source des Grands Prix pariés.** La demande disait d'appeler `GET /grands-prix/{gp_id}/pronostics/championnat/{championnat_id}` en filtrant sur ce membre. Cette route existe (étape 5) mais n'a pas la forme de cet écran : elle sert **un** GP à la fois — il faudrait un aller-retour Railway par Grand Prix, en série —, elle sert **tous** les membres du championnat dont on jetterait tout sauf un, et elle ne dit pas quels Grands Prix ce membre a pariés (il faudrait déjà connaître la liste pour l'interroger). Trois lectures directes font le travail en une passe et **sous exactement la même protection** : la politique de l'étape 5 n'ouvre les pronostics d'autrui qu'aux membres d'un championnat partagé, et un curieux qui devinerait un identifiant obtient une liste vide. C'est la base qui refuse, pas l'écran.

**La vérification du numéro déjà pris est chargée une seule fois**, au montage de l'écran ; le contrôle « en temps réel » se fait ensuite en mémoire, à chaque frappe. Un appel réseau par caractère saisi serait le pire compromis possible pour un avertissement qui ne bloque rien.

*Écarts assumés par rapport aux maquettes* :
1. **Grille « MES GRANDS PRIX » (12 et 14)** — les maquettes dessinent des cartes illustrées par les tracés de `assets/gp-cards.svg`. L'extraction de ces tracés n'est pas au programme de l'étape 8 ; une rangée mène à l'écran qui liste vraiment ces Grands Prix, avec les pronostics dedans.
2. **Podium réel de la course (13)** — la maquette montre le classement de la course, servi par `GET /grands-prix/{id}/resultats`. L'écran de résultats (maquette 11) reste au « Reste à faire » : mieux vaut ne pas dessiner le bloc que le remplir de rien.
3. **Sélection d'une couleur (14)** — la maquette montre une rangée suivie d'une pastille, sans dire ce qui se passe à l'appui. C'est un **accordéon** qui déplie les vingt teintes sous la rangée, pas une feuille modale : le joueur garde la voiture sous les yeux et voit le résultat de son choix au moment où il le fait. Même arbitrage qu'à l'étape 5 pour le sélecteur de pilote, et même transition.
4. **Statistiques avant le premier Grand Prix** — trois cases sur quatre affichent « — » et non « 0 ». « Meilleur coup 0 » se lit comme un bilan ; il n'y a pas encore de bilan.
5. **Barre de navigation basse** — toujours pas codée : l'onglet Calendrier n'a pas d'écran. La **déconnexion quitte l'accueil pour le profil**, comme l'annonçait l'étape 3 — c'est sa place définitive — et la pastille d'avatar de l'accueil, que la maquette 04 dessinait sans la relier à rien, mène désormais au profil.

*Apport d'/apple-design* — zone tactile de 44px sur la pastille d'avatar de l'accueil, sur chaque rangée de classement devenue cliquable, sur les deux sélecteurs de couleur et sur le champ numéro, absorbée par des marges négatives là où elle déplacerait le calage des maquettes ; retour tactile à l'appui partout ; **une couleur déjà prise par l'autre sélecteur est désactivée, pas cachée** — la disparition d'une case ferait bouger toute la grille sous le doigt ; le champ numéro utilise `inputMode="numeric"` et non `type="number"`, qui sur iOS ouvre un clavier à flèches, accepte le « e » et affiche des incrémenteurs dont personne n'a besoin pour deux chiffres ; et son propre profil atteint par `/profils/{soi}` redirige vers l'écran modifiable au lieu d'en montrer une version en lecture seule.

*Mouvement* — aucune transition nouvelle. Les quatre écrans réutilisent celles déjà installées : *accordion expand* (21) pour les sélecteurs de couleur, *texts reveal* (18) pour l'entrée des blocs, *skeleton loader and reveal* (14) pour l'attente, *text states swap* (04) pour le libellé du bouton d'enregistrement. Un jeton de plus aurait été un jeton à maintenir sans rien gagner.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Migration sur PostgreSQL 16 jetable (Docker), les huit dans l'ordre, avec doublure du schéma `auth` | **47 contrôles passent** |
| Structure | trois colonnes au bon type, défauts appliqués, `numero` nullable, **aucun index unique global sur `numero`**, les trois contraintes posées |
| Bornes et refus | `0`, `100` et un négatif refusés, `1` et `99` acceptés ; **deux membres peuvent porter le même numéro** ; un membre peut retirer le sien ; couleur non hexadécimale, hex à 3 chiffres et `url(#x)` refusés ; deux couleurs identiques refusées, **y compris à la casse près** |
| RLS **sous la vraie identité `authenticated`** | un membre lit tous les profils, modifie le sien, et **ne modifie pas celui d'un autre** (0 ligne touchée) ; deux politiques exactement |
| `stats_du_profil` | `67 %` de paris gagnés (2/3), `340` pts/GP (680/2), meilleur coup `400`, **cote moyenne `482` avec le podium compté pour la somme de ses deux cotes** ; entier sans aucune décimale ; le GP d'une autre saison et le GP sans date sont exclus ; le `NULL` n'est pas compté ; une saison vide et un profil inconnu rendent des zéros, jamais une erreur ; **une cote disparue est écartée de la moyenne, pas comptée 0** ; `security definer` et refusée à `anon` comme à `authenticated` |
| Classement enrichi | les trois champs servis, couleurs et numéro du profil, **un membre sans profil retombe sur les défauts**, un membre sans numéro rend `null` ; rang, total et ordre d'inscription de l'étape 7 intacts ; toujours refusée à `anon` et `authenticated` |
| Rejeu des huit migrations sur base peuplée | **profils, pronostics, classement rendu et statistiques rendues identiques** ; contraintes ni dupliquées ni perdues |
| Routes contre une doublure Supabase (auth + PostgREST en mémoire) | **62 contrôles passent** |
| Protection | `401` sans jeton, sur jeton inconnu et sur en-tête sans `Bearer`, sur les **trois** routes (preuve que la signature survit au décorateur) ; `403` sans championnat partagé, **rendu avant tout appel à `stats_du_profil` et avant même de lire le profil visé** ; ses propres statistiques passent sans lire aucune adhésion ; `403` et non `404` sur un identifiant inconnu |
| Écriture | les trois champs enregistrés, couleur en minuscules normalisée en majuscules, modification partielle qui ne touche pas le reste, numéro retirable, `retirer_numero` prioritaire, corps vide sans écriture ; **l'identifiant modifié vient du jeton — un `id`, un `profil_id` et un `pseudo` glissés dans le corps sont ignorés** ; `422` en français sur numéro hors bornes, couleur mal formée et couleurs identiques, **y compris quand une seule couleur est transmise et qu'elle égale celle déjà en base**, sans rien écrire |
| Compatibilité | un classement servi **sans** les trois nouveaux champs (backend déployé avant la migration) retombe sur les défauts au lieu d'un `500` |
| Non-régression | `/health` en `0.8.0`, 18 chemins exposés, routes des étapes 3 à 7 intactes et toujours protégées, préflight CORS |
| Rendu hors navigateur (`react-dom/server`, cache localStorage et Supabase doublés) | **112 contrôles passent** |
| Palette | 20 couleurs, **exactement les vingt valeurs demandées et dans l'ordre**, toutes distinctes, toutes au format `#RRGGBB`, quatre venues du design system ; encre contrastée définie pour chacune, sombre sur blanc, beige et jaune |
| Voiture | `couleur1` sur la coque, `couleur2` sur les ailerons, **plus aucune trace de `#800111` ni de blanc sur une forme** ; pneus toujours sombres ; sans couleurs, elle se rend quand même |
| Grille de stats | les quatre chiffres et leurs libellés, **aucune décimale, aucun « ×N »** ; trois tirets avant le premier GP jugé mais la cote moyenne conservée ; quatre tirets sans aucun pronostic ; statistiques absentes → un message, pas quatre cases à zéro |
| Grands Prix d'un membre | un élément par GP, pronostics rangés vainqueur → podium → bonus, **podium réuni en une ligne valant la somme de ses deux cotes** ; GP terminé → points **gagnés** et verdicts ; GP à venir → points **possibles**, aucun verdict, aucun total ; **un pronostic non jugé reste « en attente », jamais raté** ; jointure PostgREST acceptée en objet **comme en tableau** ; une cote disparue laisse le pronostic visible sans effacer les points déjà gagnés |
| Classement et piste | pastille et voiture aux vraies couleurs, **une voiture blanche donne une pastille lisible sur carte blanche** ; la rangée mène au profil ; le numéro choisi remplace le rang sur la piste, **et le rang reprend sa place à défaut** ; entrée échelonnée conservée ; aucun « ×N » |
| Cache | changer sa voiture oublie **tous** les classements du membre, sans toucher à ceux d'un autre compte ni à ses autres caches |
| Écrans | les trois se montent sans lever, avec leurs zones sûres, et aucun n'affiche de cote brute |
| Sous un vrai `uvicorn` | `/health` en `0.8.0`, `401` sans jeton sur les trois routes, **trace complète sur la sortie standard** quand Supabase est injoignable |
| `npm run build` | passe, 118 modules |

---

**Livrée automatique distincte à la création du profil** (version `0.8.1`)

L'étape 8 a retiré les livrées attribuées par ordre d'inscription au profit des vraies couleurs du membre, et a laissé le défaut de colonne inchangé : `#800111` / `#FFFFFF` **pour tout le monde**. Conséquence relevée au « Reste à faire » de cette étape — tant que personne n'a personnalisé sa voiture, la vue piste d'un championnat neuf montre **N voitures identiques**, seul le pseudo écrit sur l'aileron arrière les distinguant. C'est ce point qui est corrigé.

Il l'est **là où l'étape 8 disait qu'il devait l'être** : sur le défaut, à la création du profil, et non dans le code des écrans — qui lit déjà les vraies couleurs et n'a donc rien à changer. **Aucun fichier frontend ni backend n'est touché**, la migration est le seul livrable. `backend/app/config.py` reste en `0.8.0` : faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2` et `0.5.1`). Seule la version du frontend est incrémentée, pour que le déploiement Vercel se vérifie visuellement.

*Migration* — `supabase/migrations/20260814183000_livree_automatique.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les huit précédentes. Idempotente. Elle ne crée **aucune table** : une fonction, le trigger de l'étape 2 remplacé, et une reprise de l'existant.

`public.livree_par_indice(integer)` porte les dix livrées de la grille — Ferrari, Mercedes, McLaren, Renault, Red Bull, Aston Martin, Williams, Haas, Racing Bulls, Audi — et rend le couple `(couleur1, couleur2)` d'un rang donné, cycliquement.

*Écart assumé par rapport à la section 5, le même qu'aux étapes 7 et 8* — la palette de l'app compte sept couleurs, dix livrées distinctes n'en sortiraient pas. Ces couleurs **ne peignent que les voitures**, jamais un fond, un bouton ou un texte d'écran. Elles sont portées par une fonction et non par une table : ces dix couples ne sont ni administrables ni interrogeables par l'application, ils sont une constante du schéma — une table demanderait des droits, une politique RLS et une migration de plus pour chaque retouche.

Le modulo est ramené dans `[0, 9]` par `((i % 10) + 10) % 10` : en PostgreSQL, `(-1) % 10` vaut `-1`, et l'indice tomberait à côté de la table. Aucun appel du schéma ne passe de négatif, mais une fonction qui rendrait `NULL` en silence est exactement le genre de défaut qu'on ne voit qu'une fois la voiture affichée sans couleur.

*Attribution à la création* — `public.gerer_nouvel_utilisateur()` (migration de l'étape 2) est remplacée. **Le reste de son corps est inchangé**, y compris ses deux comportements distincts : un pseudo choisi explicitement n'est jamais remplacé en douce et son doublon annule l'inscription ; une inscription sans pseudo (Google, Apple) reçoit un pseudo fabriqué avec incrémentation en cas de collision.

**Trois points de mise en œuvre à ne pas défaire :**

1. **Le rang est compté AVANT l'insertion.** Le nouveau profil est le (N+1)ᵉ quand la table en compte N, donc son indice de livrée est `N % 10` — le premier inscrit prend la première livrée, le onzième reboucle dessus. Compter après décalerait tout le monde d'un cran et le premier inscrit porterait la livrée Mercedes.
2. **Le compte est fait une seule fois, hors de la boucle de collision de pseudo.** La livrée d'un membre ne dépend pas du nombre d'essais qu'il a fallu pour lui trouver un pseudo libre.
3. **Le trigger reste `after insert on auth.users`.** Il ne se déclenche donc qu'à la création : un membre qui personnalise sa voiture depuis « Mon profil » ne la voit **jamais** réécrite. C'est aussi pour cela que la livrée est posée ici et non par un `default` de colonne calculé, qui ne saurait pas compter les profils existants.

*Reprise de l'existant* — les profils créés avant cette migration portent tous les défauts de colonne ; ils reçoivent une livrée rétroactivement, par ordre de `cree_le`.

**Le rang est calculé sur TOUS les profils, pas seulement sur ceux à reprendre.** C'est ce qui donne exactement la répartition que le trigger aurait produite si la livrée avait existé depuis le début : un membre déjà personnalisé **occupe** son rang, il ne le libère pas. Ranger les seuls profils par défaut donnerait deux livrées identiques à deux voisins dès qu'un troisième s'est personnalisé entre eux. `id` départage à `cree_le` égal, sans quoi la numérotation serait instable d'un rejeu à l'autre et deux membres échangeraient leurs couleurs.

*Limite assumée du critère de reprise* — il porte sur la paire de couleurs par défaut, comme demandé. Un membre qui aurait délibérément choisi le bordeaux de la marque sur coque blanche est donc indiscernable d'un membre qui n'a rien touché, et se verrait attribuer une livrée. C'est le prix de ne rien avoir en base qui distingue « valeur par défaut » de « valeur choisie » ; le cas est sans gravité (deux couleurs re-choisissables en deux appuis) et disparaît dès ce premier passage — les rejeux suivants ne trouvent plus personne. La comparaison se fait en majuscules : `profils_couleurs_hex` accepte les deux casses et un client Supabase écrivant en direct pourrait poser du minuscule.

**Les défauts de colonne sont volontairement laissés en place** (`#800111` / `#FFFFFF`). Ils ne servent plus qu'à deux choses, toutes deux hors du chemin d'inscription : le repli de `classement_du_championnat` pour un membre sans profil, et une éventuelle insertion directe en base. Les remplacer par une livrée fixe ferait apparaître cette livrée-là deux fois dans un championnat.

*Vérifié sur PostgreSQL 16 jetable (Docker), avec doublure du schéma `auth`* — **41 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Les neuf migrations dans l'ordre | s'appliquent sans erreur |
| Structure | fonction `immutable` ; **dix livrées deux à deux distinctes**, toutes au format `#RRGGBB`, **les deux couleurs de chacune différant** (donc toutes acceptables par `profils_couleurs_distinctes`) ; livrée 0 Ferrari, livrée 9 Audi ; `10 → 0` et `21 → 1` ; **un indice négatif ne rend jamais NULL** |
| Attribution à l'inscription | 12 comptes créés, **les dix premiers portent dix livrées distinctes** ; 1ᵉʳ → Ferrari, 2ᵉ → Mercedes, 10ᵉ → Audi, **11ᵉ et 12ᵉ rebouclent** ; plus aucun profil aux couleurs par défaut |
| Inscription sans pseudo (Google, Apple) | reçoit sa livrée **et** garde son pseudo fabriqué |
| Personnalisation | un profil personnalisé n'est pas réécrit par une inscription ultérieure, **et il occupe toujours son rang** (le 15ᵉ inscrit prend bien la 15ᵉ livrée) ; **une mise à jour du profil ne déclenche pas le trigger** |
| Collision de pseudo | la boucle de rattrapage **ne décale pas la livrée**, et le pseudo est bien incrémenté |
| Non-régression de l'étape 2 | un pseudo en doublon fait toujours échouer l'inscription ; les trois contraintes de l'étape 8 sont en place |
| Reprise sur une base montée avec les **huit** migrations précédentes | 12 comptes aux défauts dont 3 personnalisés : plus aucun profil aux couleurs par défaut, **les trois personnalisés intacts** (y compris celui écrit en minuscules), 1ᵉʳ → Ferrari, 2ᵉ → Mercedes, **4ᵉ → Renault — le rang du 3ᵉ, personnalisé, n'a pas été libéré**, 10ᵉ → Audi, 11ᵉ et 12ᵉ rebouclés ; **chaque profil repris porte exactement la livrée de son rang par `cree_le`** ; dix livrées distinctes sur les dix premiers inscrits, personnalisés compris ; numéro et pseudos non touchés |
| Idempotence | rejeu des **neuf** migrations sur base peuplée : **empreinte des profils identique** ; trois rejeux de la seule migration 9 : aucun profil touché |
| Étape 7 et étape 8 | `classement_du_championnat` sert **trois livrées distinctes** pour trois membres |
| `npm run build` | passe, version `0.8.1` présente dans le bundle |

**Un piège d'ordre confirmé par ces contrôles, et documenté au « Reste à faire »** : rejouer la migration 1 **après** la 9 restaure l'ancien `gerer_nouvel_utilisateur`, et les inscriptions suivantes repartent aux couleurs par défaut. C'est le même cas de figure que « rejouer la 7 après la 8 » relevé à l'étape 8 — les migrations sont idempotentes chacune pour elle-même, pas dans le désordre.

---

**Étape 9 — Résultats GP, calendrier, squelettes, gestion d'erreurs** (version `0.9.0`)

Les deux derniers écrans des maquettes, plus deux chantiers transversaux. Une migration, une route d'API, cinq composants, deux écrans, et une reprise de **tous** les écrans existants.

*Schéma* — `supabase/migrations/20260814213000_calendrier_championnat.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les neuf précédentes. Idempotente. Elle ne crée **aucune table** : une fonction nouvelle, une fonction remplacée, un index.

`public.calendrier_du_championnat(championnat, profil, saison)` rend une ligne par Grand Prix de la saison avec, pour chacun, ce que le championnat y a marqué : disponibilité des cotes et des résultats, vainqueur de la course, score et rang du membre, et le mini-classement à trois de la maquette 15. Agréger en base pour la même raison qu'au classement de l'étape 7 — sans cela il faudrait rapatrier tous les pronostics notés de tous les membres, sur toute la saison, pour n'en tirer qu'un score et un rang par Grand Prix.

**Trois décisions à ne pas défaire :**

1. **Le rang d'un Grand Prix se calcule avec `rank`, pas `row_number`.** L'étape 7 avait tranché l'inverse pour le classement de la saison, parce que les quatre critères de la règle 4.6 réunis départagent toujours. Ici il n'y a **aucun** critère de départage : la règle 4.6 régit le classement général, pas une course isolée. Avant le départ, tout le monde est à zéro — `row_number` inventerait un premier et un dernier là où il n'y en a pas. Les ex æquo sont donc affichés comme tels, et un test le vérifie sur un GP à venir.
2. **Un Grand Prix sans date annoncée est servi quand même**, en fin de liste, et rattaché à la saison courante. Unibet publie parfois un GP avant d'en annoncer l'horaire (étape 4) ; l'écarter le rendrait invisible jusqu'au samedi des qualifications. C'est l'inverse du choix fait pour les statistiques de l'étape 8, et pour une raison précise : **une moyenne fausse ne se voit pas, un Grand Prix manquant dans un calendrier se voit tout de suite.**
3. **`mes_points` vaut `NULL`, jamais `0`, quand aucun pronostic du membre n'a été noté.** Convention de l'étape 6, tenue depuis : « pas encore jugé » et « raté » ne se confondent jamais. L'écran affiche l'un « Tes pronostics ne sont pas encore validés », l'autre « 0 pts ».

**Ni les cotes ni les résultats ne se déduisent du statut du GP**, et c'est le point à ne pas simplifier. `cotes_disponibles` se lit dans `public.cotes`, `resultats_disponibles` dans `public.resultats_gp`. Le statut mentirait dans les deux sens : **rien ne fait passer un GP en `cotes_figees` aujourd'hui** (voir « Reste à faire »), et le job de l'étape 6 passe un GP à `termine` même s'il reste des pronostics sans points.

La fonction est `security definer` et réservée à `service_role`, pour la raison exacte du classement de l'étape 7 : paramétrée par un championnat, elle lit forcément les pronostics d'autrui, et sous l'identité de l'appelant la politique RLS de l'étape 5 rendrait un calendrier **silencieusement faux** au lieu d'un refus franc. L'autorisation est portée par la route. Un index `grands_prix_date_idx` est ajouté : il sert le tri du calendrier **et** la lecture du prochain GP par l'accueil, le chemin le plus emprunté de l'application.

*`pronostics_du_championnat` est remplacée* pour porter la **voiture** du membre (`couleur1`, `couleur2`, `numero`) et son **total sur ce GP**. Le reste du corps est inchangé, ordre par `rejoint_le` compris. `total_points` est calculé en base et non additionné côté frontend pour une raison de convention, pas de performance : la somme doit compter `0` pour un raté et **ignorer** un pronostic non jugé, jamais le compter zéro. Écrire cette règle une fois en base vaut mieux que la réécrire dans chaque écran qui affiche un total.

*Backend* — une seule route nouvelle : `GET /championnats/{id}/calendrier`, authentifiée, appartenance vérifiée **avant** toute lecture (`exiger_membre`, réutilisée telle quelle pour la quatrième fois). **Le profil transmis à la fonction vient du jeton, jamais de l'URL** : « mon score sur ce GP » ne peut désigner que l'appelant, et un identifiant reçu dans le chemin laisserait un membre demander le calendrier vu par un autre. Un contrôle du jeu de tests couvre ce point. `saison` est un paramètre de requête dont le défaut est la constante `SAISON_COURANTE = 2026`, écrite en dur plutôt que déduite de `datetime.now()` : le calendrier doit rester lisible en intersaison, où l'année courante n'a encore aucun Grand Prix en base. **À faire évoluer avec la grille de `app/calcul/pilotes.py`**, qui décrit la même saison.

`GET /grands-prix/{id}/resultats` **existait déjà** depuis l'étape 6 et n'est pas redéfinie : elle sert déjà le classement de la course publiquement et les pronostics des membres sur `?championnat_id=`. Seul son modèle `MembrePronostics` gagne quatre champs, **tous avec une valeur par défaut** — un backend déployé avant la migration recevrait sinon des lignes sans voiture et rendrait `500` sur **toute** la liste, le piège déjà rencontré avec `cree_par` à la version `0.4.1`. Un contrôle vérifie précisément ce cas.

---

***Les messages techniques ne quittent plus le serveur.*** C'est le point de l'étape qui referme une dette explicite du « Reste à faire ».

Depuis la version `0.3.1`, `journal.echec_lisible` renvoyait la cause en clair jusque dans l'interface : message Supabase, code PostgreSQL, statut HTTP. C'était délibéré, le temps de la mise en service, et le CLAUDE.md l'inscrivait comme à corriger. Une chaîne du genre `relation "public.cotes" does not exist · code 42P01` n'apprend rien à un joueur et lui fait croire que l'application est cassée pour de bon.

Ce qui change : l'appelant reçoit le **contexte en français** (« Chargement du classement : impossible pour le moment. Réessaie dans quelques instants. »), les logs Railway reçoivent **exactement ce qu'ils recevaient avant** — message, code, statut, trace complète. Rien n'est perdu au diagnostic ; seul l'endroit où on le lit change. Le `422` est conservé : il reste un choix de transport, jamais de sémantique, et ne se confond ni avec le `503` d'une configuration absente ni avec le `500` d'un plantage non capturé. **Vérifié sous un vrai `uvicorn`, Supabase pointé sur un port mort** : la réponse est en français, la trace complète est sur la sortie standard.

`lib/api.js` garde un garde-fou par-dessus, et **ce n'est pas un doublon de cette règle** : il protège contre ce qui ne vient pas de notre backend — page d'erreur de Railway, proxy qui s'interpose, ancienne version encore déployée. `SIGNATURE_TECHNIQUE` reconnaît des signatures franches (code PostgreSQL, `Traceback`, `does not exist`, `Bad Gateway`) et non « est-ce du français ? », question à laquelle une expression régulière ne sait pas répondre.

---

*Gestion d'erreurs — trois cas, dits différemment parce qu'ils n'appellent pas le même geste.* `lib/erreurs.js` est étendu de quatre **genres** qui voyagent avec le résultat des chargeurs, jamais devinés d'après le texte du message — deviner à partir d'une chaîne déjà traduite ferait dépendre le comportement de la formulation.

| Genre | Message | Bouton |
|---|---|---|
| `reseau` | « Connexion au serveur en cours… Réessaie dans quelques secondes. » | Réessayer |
| `supabase` / `serveur` | « Une erreur est survenue. Réessaie. » | Réessayer |
| `session` | « Session expirée. Reconnecte-toi. » | **aucun** |
| `donnees` | message contextuel propre à l'écran | **aucun** |

**Les `502`, `503` et `504` sont classés réseau et non serveur**, et c'est le détail qui compte : sur le plan gratuit de Railway, c'est exactement ce que rend un service encore endormi. « Connexion au serveur en cours » est alors la description juste, et réessayer marche. Les deux genres sans bouton ne se réparent pas en réessayant : une session morte rejouerait le même jeton en boucle, une donnée absente ne réapparaîtra pas parce qu'on redemande.

`composants/BlocErreur.jsx` rend l'ensemble, avec la secousse d'`Alerte` (transitions-dev 12) rejouée à chaque tentative — sans elle, réessayer et retomber sur le même message donnerait l'impression que le bouton n'a rien fait.

**Deux corrections dans `useDonnees`**, toutes deux visibles à l'écran :
1. Une exception inattendue remettait l'erreur à `null` : l'écran restait **vide, sans squelette ni message**, et rien ne disait quoi faire. Elle est désormais rendue comme les autres.
2. `recharger()` ne remettait pas l'attente : le squelette ne réapparaissait jamais et le bouton semblait inerte.

Le hook rend désormais `echec` (l'objet, avec son genre) **et** `erreur` (la chaîne seule), pour ne rien casser des écrans qui n'affichaient qu'un message.

*États de chargement — des squelettes partout, plus un seul texte d'attente.* `--color-squelette: #E8E0D8` entre dans le bloc `@theme`. Ce n'est pas une couleur nouvelle du design system au sens de la section 5 : **elle ne peint jamais un fond, un bouton ni un texte**, seulement des silhouettes. C'est le beige `fond` assombri juste ce qu'il faut pour se détacher d'une carte blanche **comme** du fond de l'app — les squelettes vivent sur les deux.

`composants/Squelette.jsx` fournit quatre primitives (`Barre`, `Pave`, `Carte`, `Rangee`) et **les écrans n'écrivent donc jamais cette couleur eux-mêmes**. Le balayage `.t-skel-bar` est un croisement assumé de deux snippets déjà installés : structure du *skeleton loader* (14), lumière de *shimmer text* (15) avec ses jetons inchangés. Le snippet 15 clippe sa bande sur des glyphes ; ici il n'y a pas de texte, la bande est peinte sur l'aplat.

**`is-pulsing` n'est plus posé par `ZoneChargement`** : superposer la pulsation d'ensemble du snippet 14 au balayage par barre donnait deux battements de rythmes différents sur le même bloc. La règle CSS reste en place — c'est le snippet tel quel — elle n'est simplement plus appelée.

**Les aplats de couleur des squelettes gardent leur couleur.** Un bloc rouge dont le squelette serait gris virerait au gris puis reviendrait au rouge : l'écran clignoterait au lieu de se remplir. Seul le contenu à l'intérieur est grisé, en blanc translucide. Même raison sur la vue piste, où le squelette est en blanc translucide et non dans le gris des autres écrans : un aplat beige clair posé sur l'asphalte s'y lirait comme une vraie voiture blanche.

*Extraction de `assets/gp-cards.svg` — ce que la planche contient vraiment.* Elle dessine six cartes mais **seulement deux tracés distincts** : Monza et Spa, répétés trois fois chacun sous des aplats différents, avec la même date sur les six. C'est une planche de maquette, pas un jeu de vingt-quatre circuits.

Les deux vrais tracés sont extraits **tels quels** dans `composants/TraceCircuit.jsx`, sans être redessinés, et rattachés aux Grands Prix qu'ils représentent (Monza → GP Italie, Spa → GP Belgique). Tous les autres reçoivent le **tracé générique**, ce que la demande prévoyait. Les `viewBox` sont les boîtes englobantes réelles, mesurées en échantillonnant les courbes de Bézier : **aucune coordonnée n'est réécrite**, c'est le cadrage qui bouge, pas le dessin. Le rapprochement se fait sur un nom normalisé (accents et casse ramenés), jamais sur l'égalité stricte : Unibet écrit « GP Pays Bas » aujourd'hui et « GP Pays-Bas » demain.

*Écrans* — `ecrans/ResultatsGp.jsx` (maquette 11), `ecrans/Calendrier.jsx` (maquette 15), `lib/calendrier.js`.

**Deux routes mènent à l'écran de résultats, et il vit hors des deux groupes de `App.jsx`** — comme `/nouveau-mot-de-passe`, et pour une raison analogue. Le classement de la course est **public** (étape 6, et la maquette 11 le montre comme tel) : dans le groupe public, `RoutePublique` renverrait un membre connecté sur son accueil ; dans le groupe protégé, un visiteur sans compte ne pourrait pas le lire. `/grands-prix/:gpId/resultats` sert la partie publique, `/championnats/:id/grands-prix/:gpId/resultats` y ajoute le classement des membres — que la route refuse à qui n'en est pas.

**Le classement complet de la course est replié dans un accordéon** (transitions-dev 21, déjà installé). La maquette 11 ne montre que le podium, la demande veut tout le classement : les deux tiennent parce que les vingt-deux lignes ne sont pas étalées d'emblée, ce qui noierait le podium — la seule chose qu'on vient lire en premier. Même geste pour les pronostics d'un membre, dépliés **sous** sa ligne : la maquette pose un chevron sans dire ce qu'il ouvre, et un accordéon garde le reste du classement sous les yeux là où une feuille modale volerait le geste de retour.

**`points_fia` est le seul nombre de l'application qui ne soit pas des points au sens de la règle 4.1.** Ce sont les points du championnat du monde (25, 18, 15…). Il s'écrit donc « 25 pts FIA » et **jamais** via `formaterPoints` : les confondre ferait lire le classement F1 comme un classement de pronostics.

*Écarts assumés par rapport aux maquettes et à la demande* :
1. **« Historique » → « Calendrier » (maquette 15)** — le vocabulaire imposé de la section 1 interdit le premier mot. L'écran, la route et le bouton disent « calendrier ». Un test vérifie que le mot « Historique » n'apparaît nulle part.
2. **Le vert de « terminé » n'existe pas dans la section 5.** La demande veut « à venir (gris), cotes disponibles (amber), terminé (vert) ». Le gris et l'amber sont ceux du design system ; le vert n'y est pas et la palette n'est pas négociable. « Terminé » prend donc le bordeaux `primaire`, déjà la couleur des points et des scores dans toute l'application — un Grand Prix terminé est précisément celui qui en a rapporté. Les trois états restent francs, ce que la demande cherchait.
3. **Le mini-classement de la maquette 15 est limité à trois membres**, comme la maquette le dessine : en servir davantage ferait transporter tout le championnat pour chacun des vingt-quatre Grands Prix de la saison.
4. **Le bloc « leader général » est calculé côté écran**, en additionnant les mini-classements déjà servis, plutôt qu'en appelant le classement de l'étape 7. L'écran a déjà tout ce qu'il faut ; un second aller-retour Railway pour trois nombres serait un réveil de plus. Il n'apparaît qu'une fois un Grand Prix couru : avant, il annoncerait un leader à zéro point, c'est-à-dire un classement inventé.
5. **Le calendrier n'entre pas dans la bascule Classement / Piste** de la maquette 07, mais dans une carte sous le classement. La bascule oppose deux vues du **même** classement ; le calendrier est un autre écran, et un troisième segment aurait mis trois libellés dans la largeur d'un iPhone.
6. **Barre de navigation basse** — toujours pas codée. Ses quatre onglets ont désormais tous un écran, mais elle ne peut pas être posée sur la vue piste, qui occupe l'écran entier par décision de l'étape 7. À traiter comme un chantier à part.

*L'accueil retombe sur le dernier Grand Prix couru.* Jusqu'ici le bloc rouge ne montrait que le prochain GP en statut `a_venir` : dès que le job passait un GP à `termine`, le bloc n'avait plus rien à annoncer jusqu'au scraping du samedi suivant — c'est-à-dire précisément le dimanche soir, quand tout le monde ouvre l'app. `chargerDernierGpCouru` prend le relais, avec une **jointure interne sur `resultats_gp`** qui n'est pas décorative : un GP passé à `termine` sans résultats enregistrés (course annulée, job en échec) n'enverrait pas vers un écran de résultats vide. Le bouton a donc désormais **trois destinations** et son libellé suit toujours : « Voir les résultats », « Voir mes pronos », « Pronostiquer ». **L'échec de ce repli n'emporte pas l'accueil** — même règle que pour les pronostics depuis la version `0.5.1`.

*`AuthContexte` est exporté nommément*, pour la même raison que `BlocProchainGp` à la version `0.5.1` : rendre un écran hors navigateur imposerait sinon de monter `AuthProvider`, dont la session ne se résout que dans un effet — jamais exécuté en rendu serveur.

*Apport d'/apple-design* — zones tactiles de 44px sur le bouton « Réessayer », sur chaque rangée de membre dépliable et sur le bouton « Classement complet » ; retour tactile à l'appui partout ; **une attente est toujours une silhouette, jamais un texte** (le seul « Chargement… » restant, sur la piste, est remplacé par des voitures fantômes aux bonnes hauteurs) ; le bouton du calendrier **nomme sa destination** plutôt que d'afficher un chevron muet ; et l'écran de résultats reste atteignable sans session, ce qu'une PWA partagée par lien doit permettre.

*Mouvement* — **aucune transition nouvelle**, et c'est délibéré. Les deux écrans réutilisent celles déjà installées : *accordion expand* (21) pour le classement complet et les pronostics d'un membre, *texts reveal* (18) pour l'entrée des blocs, *skeleton loader and reveal* (14) pour l'attente, *shimmer text* (15) dont les jetons alimentent le balayage des squelettes, *error state shake* (12) pour la nouvelle tentative. Un jeton de plus aurait été un jeton à maintenir sans rien gagner.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Migration sur PostgreSQL 16 jetable (Docker), les **dix** dans l'ordre, avec doublure du schéma `auth` | **44 contrôles passent** |
| Périmètre de la saison | 4 GP servis, le GP d'une autre saison écarté, **le GP sans date servi quand même et placé en dernier**, ordre par date vérifié |
| Disponibilité | cotes et résultats lus dans leurs tables ; GP couru → vainqueur nommé ; GP sans résultat → aucun vainqueur ; GP à venir avec cotes correctement distingué |
| Mes points | 500 sur un GP à deux pronostics dont un raté ; **un raté vaut 0, un non-jugé vaut NULL** ; rang 1 puis rang 2 selon le GP |
| Classement d'un GP | 3 membres dont un qui n'a rien joué, servi à 0 et non exclu ; livrée du membre servie ; **avant la course, tout le monde est 1ᵉʳ ex æquo** — preuve que c'est bien `rank` et non `row_number` |
| Cloisonnement | un membre d'un autre championnat n'entre jamais au classement ; championnat inconnu → les GP restent servis, **sans aucun score** |
| Droits | `security definer`, refusée à `anon` et `authenticated`, accordée à `service_role` ; index de date créé |
| `pronostics_du_championnat` | voiture et total servis, ordre d'inscription conservé, **total NULL pour qui n'a rien joué**, pronostics de l'étape 5 intacts |
| Non-régression | `classement_du_championnat` et `stats_du_profil` rendent exactement la même chose |
| Rejeu des dix migrations sur base peuplée | **empreinte des pronostics, calendrier rendu et `pronostics_du_championnat` identiques** |
| **Piège d'ordre, reproduit puis réparé** | rejouer la 5 après la 10 retire bien la voiture du tableau des résultats ; rejouer la 10 derrière répare tout |
| Routes contre une doublure Supabase (auth + PostgREST en mémoire) | **46 contrôles passent** |
| Protection | `401` sans jeton, sur jeton inconnu et sur en-tête sans `Bearer` (preuve que la signature survit au décorateur) ; **`403` pour un non-membre, rendu avant tout appel à la fonction de calendrier** ; `422` sur identifiant mal formé |
| Contenu | les huit champs portés jusqu'au client, GP sans date servi, **`mes_points` NULL et non 0** ; **le profil transmis vient du jeton, jamais de l'URL** ; saison surchargeable |
| **Message technique** | une panne sort en `422` **en français**, sans code PostgreSQL ni vocabulaire anglais dans la réponse |
| Résultats | classement de la course servi **sans jeton**, `401` puis `403` sur la partie championnat, voiture et total du membre portés, **un membre servi sans voiture retombe sur les défauts au lieu d'un 500** |
| Non-régression | `/health` en `0.9.0`, **19 chemins exposés**, routes des étapes 3 à 8 intactes, préflight CORS |
| Rendu hors navigateur (`react-dom/server`, cache localStorage doublé) | **85 contrôles passent** |
| Tracés | Italie → Monza, Belgique → Spa, insensibilité aux accents et à la casse, **GP inconnu → générique** ; les deux tracés se rendent, `currentColor`, `aria-hidden`, **viewBox = vraies boîtes englobantes** |
| Squelettes | barres en `t-skel-bar`, **aucune couleur en dur dans les primitives**, silhouette de rangée conforme, gris déclaré une seule fois dans le thème, balayage bâti sur les jetons du shimmer, **coupé sous `prefers-reduced-motion`** |
| Erreurs | les quatre genres rendent le bon message ; **le genre l'emporte sur un message technique reçu** ; un message métier français est conservé ; bouton présent pour réseau et Supabase, **absent pour session et donnée absente** |
| Classement d'un GP | tri décroissant, **ex æquo au même rang**, rang qui saute après, membre sans pronostic servi et non exclu, réussis sans les ratés ; repli de total **ignorant le non-jugé** ; **aucun jugé → NULL, jamais 0** ; podium rendu 2ᵉ / 1ᵉʳ / 3ᵉ, course sans vainqueur → aucun podium bancal |
| Cartes de Grand Prix | les trois états rendus avec leur étiquette, leur destination et leur tracé ; **« Date à confirmer » plutôt qu'une date inventée** ; GP couru sans pronostic et GP couru non validé distingués, **sans jamais afficher « 0 pts »** |
| Écrans | les deux se montent sans lever ; **le mot « Historique » n'apparaît nulle part** ; leader général juste et absent avant le premier GP ; calendrier vide → message contextuel ; résultats absents → date et heure du départ ; **sans championnat, on explique pourquoi les pronostics manquent** ; podium, points FIA, abandon classé, pronostic non jugé « en attente », podium « A + B » |
| Règle 4.1 | **aucun « ×N » nulle part**, sur les trois surfaces |
| Sous un vrai `uvicorn`, Supabase pointé sur un port mort | `/health` en `0.9.0`, `401` sans jeton sur le calendrier, **réponse en français et trace complète sur la sortie standard** |
| `npm run build` | passe, 124 modules, version `0.9.0` et gris de squelette présents dans le bundle |

---

**Étape 10 — Barre de navigation basse et calendrier global** (version `0.10.0`)

Le dernier écart de structure par rapport aux maquettes est refermé. **Aucune migration** : la barre est du frontend, et le seul changement backend est un enrichissement de `GET /championnats/moi`. Un composant, un module de navigation, deux écrans, un enrichissement de route.

*La barre, et pourquoi elle est montée dans `App.jsx` et non dans chaque écran.* C'est la décision structurante de l'étape, et elle n'est pas un choix de style :

1. **`Ecran` porte un `transform`** — l'animation d'entrée `t-ecran` de l'étape 2. Un élément `position: fixed` placé à l'intérieur se positionne alors par rapport à cet ancêtre et non à la fenêtre : la barre défilerait avec la page. C'est la règle des blocs conteneurs de CSS, et elle vaut **même pour `translateX(0)`**, l'état de repos de l'animation. Une barre posée dans chaque écran aurait donc glissé vers le haut au premier défilement, sur tous les écrans à la fois.
2. Montée une seule fois, elle **ne se démonte pas d'un écran à l'autre** : la couleur de l'onglet glisse de l'ancien au nouveau, là où une barre remontée à chaque navigation repart de zéro et clignote.
3. Un seul endroit décide où elle apparaît.

*`frontend/src/lib/navigation.js` est cette source unique.* Deux consommateurs ont besoin de la même réponse : `NavBarre` pour savoir si elle s'affiche, et `Ecran` pour **réserver la hauteur qu'elle occupe** — elle est `fixed`, donc elle ne pousse rien. Deux listes écrites séparément auraient divergé au premier écran ajouté, avec un symptôme discret : une barre posée sur le dernier bouton d'un écran, ou 58px de blanc sous un écran qui n'en porte pas.

**Le piège des motifs de route, et sa sortie.** `/championnats/creer` et `/championnats/rejoindre` répondent au motif `/championnats/:id` — React Router ne fait pas la différence, et l'ordre des routes de `App.jsx` ne s'applique pas à un `matchPath` isolé. Sans une liste d'exclusions évaluée **en premier**, les deux écrans de saisie que la demande exclut auraient hérité de la barre. Les motifs sont écrits en clair plutôt que testés par préfixe : un futur `/championnats/:id/quelque-chose` ne l'héritera pas sans qu'on l'ait décidé.

La place est réservée par **un bloc en fin de flux** (`h-nav`), pas par un rembourrage qui viendrait écraser celui d'`ecran`. Deux utilitaires écrivant `padding-bottom` se départagent par leur ordre dans la feuille compilée — ce n'est pas une garantie sur laquelle poser la zone sûre du home indicator.

*Les quatre onglets* — Accueil (`/accueil`), Championnats (`/championnats`), Calendrier (`/calendrier`), Profil (`/profil`), dans l'ordre de la maquette 04. **`actif` est une fonction, pas un chemin** : un onglet reste allumé sur tout ce qui lui appartient. Le classement d'un championnat, sa vue piste et son calendrier sont tous « Championnats » ; le profil d'un autre membre est toujours « Profil ». Un onglet qui s'éteindrait au premier écran de détail ne dirait plus où l'on se trouve.

*Écrans qui la portent*, exactement la liste de la demande : accueil, championnat (vue liste), mon profil, calendrier global, résultats d'un GP, profil d'un membre — plus la liste des championnats, qui est la racine de son propre onglet. **Elle est absente** de la vue piste (plein écran, décision de l'étape 7), des trois écrans de pronostics, de la création et de l'adhésion.

**Deux écrans de détail restent volontairement sans barre** et méritent d'être signalés : le **calendrier d'un championnat** (`/championnats/:id/calendrier`) et les **Grands Prix d'un membre** (maquette 13). La liste de la demande est exhaustive et ne les mentionne pas ; iOS, lui, garde la barre sur toute la pile d'un onglet. **Si la barre doit y apparaître un jour, c'est une ligne à ajouter dans `CHEMINS_AVEC_BARRE`** et rien d'autre — ni les écrans ni `Ecran` n'ont à changer.

*Écart assumé par rapport à la maquette 04* — elle met le **même tracé de groupe de personnes** sur Championnats et sur Profil. Deux raisons de suivre la demande, qui veut un trophée : la maquette pose alors deux icônes de personnages côte à côte, indistinguables d'un coup d'œil au pouce ; et ce tracé (`IconeMembres`) sert déjà d'emblème aux cartes de championnat de l'accueil, où il désigne l'effectif.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Les icônes passent du contour à l'aplat par l'échange de transitions-dev 09, déjà installé pour l'étoile de favori. Il ne restait qu'à interpoler la couleur, **sur la durée et la courbe de cet échange** (`--icon-swap-dur`, `--icon-swap-ease`) : la teinte et le dessin doivent changer ensemble, sinon l'œil voit deux événements là où il n'y en a qu'un. `prefers-reduced-motion` couvre les deux.

Les variantes pleines sont dessinées avec `fill-rule="evenodd"` — la porte de la maison est un **trou dans l'aplat**, pas un rectangle blanc posé dessus. La barre est blanche aujourd'hui ; un aplat blanc en dur se verrait le jour où elle ne l'est plus. Le calendrier plein ne remplit que son corps, sous la barre de titre : un rectangle intégralement plein ne se lirait plus comme un calendrier.

*Apport d'/apple-design* — zone tactile de 44px sur chaque onglet (`min-h-tactile` et non `h-tactile` : la contrainte est un plancher, la rangée doit pouvoir grandir si le corps de texte est agrandi dans les réglages) ; retour tactile à l'appui ; `env(safe-area-inset-bottom)` sous la rangée, jamais à la place de son rembourrage ; `aria-current="page"` sur l'onglet courant et `aria-label` sur la barre ; et **retoucher l'onglet déjà ouvert ramène en haut de l'écran**, comme partout sur iOS — sans cela l'appui ne fait rien du tout, React Router considérant qu'on est déjà arrivé. Aucune bordure, une ombre remontante très douce teintée de la couleur du texte : la section 5 proscrit les traits fins, et la demande dit la même chose.

---

*Écran `/championnats` — la racine de l'onglet.* L'accueil montre déjà cette liste, sous le bloc du prochain Grand Prix ; ici elle occupe l'écran, ce qui est la différence entre un extrait et la destination d'un onglet. **Les cartes sont exactement celles de l'accueil** (`CarteChampionnat`, `SqueletteChampionnats` et `Action` y sont désormais exportés), et non redessinées : un championnat doit se reconnaître d'un écran à l'autre. **Aucun bouton de retour** — sur iOS, la racine d'un onglet ne remonte nulle part, on en sort par un autre onglet.

*Écran `/calendrier` — la vue globale.* Un championnat par rangée, avec le Grand Prix qui l'attend ; la rangée mène au calendrier complet de ce championnat (maquette 15). C'est la réponse au point laissé ouvert à l'étape 9 : le calendrier de la maquette 15 est celui d'**un** championnat, il porte le score du membre et le mini-classement de ses amis. Le brancher d'office sur un championnat choisi par l'application aurait fait deviner lequel compte pour son propriétaire ; cet écran pose la question au lieu d'y répondre à sa place.

**Trois états par rangée, jamais confondus** : un Grand Prix daté, un Grand Prix annoncé **dont Unibet n'a pas encore publié l'horaire** (« Date à confirmer »), et plus aucun Grand Prix (« Saison terminée »). Le deuxième ne doit pas emprunter la formule du troisième — un GP sans date reste un GP à jouer. Sans Grand Prix, aucun tracé de circuit n'est dessiné : une silhouette sous « Saison terminée » laisserait croire qu'il en reste un.

Les deux boutons d'action **ne s'affichent que dans l'état vide**, avec le message demandé. Ailleurs, ils doubleraient sans raison ceux de l'onglet Championnats.

Les trois écrans — accueil, liste des championnats, calendrier global — **partagent la clé de cache `championnats:{profil}`**. Passer de l'un à l'autre n'attend rien, et une adhésion les invalide tous les trois d'un coup.

---

*Backend — `GET /championnats/moi` porte le prochain Grand Prix.* Un objet `prochain_gp` (identifiant, nom, date, statut) sur chaque championnat, `null` si aucun n'est à venir.

**Il est lu une seule fois pour toute la liste**, et c'est le point à ne pas défaire. `public.grands_prix` est une table **globale** : une course n'appartient à aucun championnat, le prochain GP est donc le même pour tout le monde. Une lecture par championnat, ou une jointure ajoutée à `mes_championnats`, referait N fois le même travail. C'est aussi pourquoi **aucune migration n'est nécessaire** : une seule lecture PostgREST suffit, là où une fonction SQL nouvelle aurait demandé un passage par le SQL Editor.

Trois points de mise en œuvre :

1. **Un GP sans horaire annoncé reste servi**, mais après les autres (`nullslast`). Sans cette clause, PostgreSQL place les NULL en tête et un GP dont Unibet n'a pas publié la date passerait devant la course de dimanche — le piège déjà traité par `nullsFirst: false` à l'accueil.
2. **L'instant de comparaison est calculé en Python, en UTC**, et non laissé à un `now` interprété par PostgreSQL : le résultat ne dépend alors ni du fuseau de la session, ni de la façon dont PostgREST transmet la valeur. Le suffixe `Z` est préféré à `+00:00`, dont le `+` se confond avec une espace une fois la requête encodée.
3. **L'échec de cette lecture n'emporte pas la liste.** Un championnat sans Grand Prix annoncé reste un championnat lisible ; une liste vide serait un cul-de-sac. La panne part dans les logs Railway avec sa cause — même arbitrage qu'à la version `0.5.1` pour les pronostics de l'accueil.

Le champ a une **valeur par défaut** dans le modèle `Championnat` : les routes de création et d'adhésion construisent le même objet et n'ont pas à s'en soucier, et un frontend déployé avant le backend n'y perd rien. Aucune lecture de Grand Prix n'est faite quand l'appelant n'a aucun championnat.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Route contre une doublure Supabase (auth + PostgREST en mémoire) | **49 contrôles passent** |
| Protection | `401` sans jeton, sur jeton inconnu et sur en-tête sans `Bearer` (la signature survit au décorateur) ; **aucune lecture pour un appel refusé** |
| Contenu | les quatre champs du GP portés jusqu'au client ; champs de l'étape 3 intacts ; **championnat orphelin toujours sérialisé** (version `0.4.1`) ; l'identité vient du jeton |
| Requête | **une seule lecture de `grands_prix` pour toute la liste** ; statuts `a_venir` et `cotes_figees` seuls ; GP sans date non exclu ; GP déjà partis écartés ; instant en UTC finissant par `Z` et proche de maintenant ; `nullslast` ; `limit 1` ; seules les colonnes servies |
| États | saison terminée → `null` sans casser la liste ; **aucun championnat → liste vide et aucune lecture de GP inutile** |
| Robustesse | table `grands_prix` absente (`42P01`) et panne inattendue → **la liste est quand même servie**, `prochain_gp` à `null`, rien de technique dans la réponse ; l'échec de la liste, lui, sort en `422` **en français**, sans code PostgreSQL |
| Non-régression | `/health` en `0.10.0`, les 19 chemins toujours exposés, classement et calendrier toujours protégés, cotes toujours publiques, préflight CORS |
| Rendu hors navigateur (`react-dom/server`, cache localStorage doublé) | **104 contrôles passent** |
| Chemins | barre présente sur les 8 chemins voulus, absente sur les 12 autres ; **`creer` et `rejoindre` exclus avant le motif d'identifiant** |
| Onglet actif | un par écran, la piste et le calendrier d'un championnat restent dans « Championnats », le profil d'un membre dans « Profil » ; **les résultats publics n'allument aucun onglet** |
| Barre | quatre libellés, quatre destinations, **un seul `aria-current`**, 44px et retour tactile sur chacun, zone sûre en bas, fond blanc, **aucune bordure**, échange d'icônes installé, barre nommée pour le lecteur d'écran |
| Absences | **rien sans session**, rien sur les cotes, la piste ni la création ; les résultats gardent la barre pour un membre connecté, **pas pour un visiteur sans compte** |
| Icônes | les quatre se rendent dans leurs deux variantes, l'aplat diffère du contour et est peint en `currentColor`, **aucune couleur en dur**, décoratives ; le calendrier plein garde sa barre de titre |
| Place réservée | `h-nav` présent là où la barre l'est, **absent ailleurs**, en fin de flux et invisible du lecteur d'écran ; zones sûres conservées |
| Liste des championnats | les deux championnats, leurs destinations, leur code, leurs effectifs accordés ; **aucun bouton de retour** ; liste vide → un message, pas une erreur, et les deux actions |
| Calendrier global | une rangée par championnat, chacune vers son calendrier ; GP nommé et daté ; **le mot « Historique » n'apparaît nulle part** ; sans GP → « Saison terminée » et **aucune date inventée** ; sans horaire → « Date à confirmer », jamais « Saison terminée » ; aucun championnat → le message demandé et les deux boutons |
| Règle 4.1 | **aucun « ×N » nulle part** |
| Sous un vrai `uvicorn` | `/health` en `0.10.0`, la route répond, le `503` de configuration absente est journalisé |
| `npm run build` | passe, **128 modules**, version `0.10.0` dans le bundle |

**Étape 11 — Scraping automatique 2h après les qualifications** (version `0.11.0`)

Le déclenchement du scraper cesse d'être manuel, et le statut `cotes_figees` cesse d'être un statut que rien ne pose. Une migration, une colonne, un second scheduler. **Aucun changement frontend** hormis la version.

C'est le point le plus ancien du « Reste à faire » qui se referme : depuis l'étape 4, la protection commandée par `cotes_figees` était en place et testée, mais **aucun code ne l'appliquait jamais**. Le job de résultats compensait en surveillant aussi les GP restés `a_venir` — ce contournement reste en place, il ne coûte rien et couvre le cas d'un scraping manqué.

*Schéma* — `supabase/migrations/20260816120000_date_qualifications.sql`, **à exécuter à la main dans le SQL Editor de Supabase**, après les dix précédentes. Idempotente. Elle ne crée **aucune table** : une colonne, un index partiel, une reprise de l'existant. Elle ne remplace **aucune fonction**, donc elle est la seule migration depuis la 7 qui ne puisse pas entrer en conflit d'ordre avec une migration antérieure rejouée par-dessus.

`public.grands_prix` gagne `date_qualifications` (timestamptz, **nullable**). Nullable et pas seulement par prudence : Unibet publie parfois un Grand Prix avant d'en annoncer le programme — le CLAUDE.md le note dès l'étape 4 pour `date_course`. Un `not null` obligerait le scraper à inventer une date pour pouvoir écrire la ligne, ou à ne pas écrire la ligne du tout, c'est-à-dire à **faire disparaître le Grand Prix de l'accueil et du calendrier**. En pratique la colonne est presque toujours remplie : à défaut d'événement de qualification, le scraper retient `date_course - 22h`.

L'index `grands_prix_qualifs_a_venir_idx` est **partiel sur `statut = 'a_venir'`**, le seul statut que le job interroge. Il se vide de lui-même à mesure que la saison avance, exactement comme `pronostics_a_calculer_idx` de l'étape 6.

*Reprise de l'existant* — les Grands Prix déjà en base ont été scrapés avant l'existence de la colonne et ne seraient donc **jamais figés automatiquement**. Ils reçoivent le même repli. Le filtre `date_qualifications is null` rend l'opération à la fois idempotente et non destructive : un horaire déjà connu — annoncé par Unibet, ou corrigé à la main — n'est jamais réécrit. Les GP `termine` et `cotes_figees` sont laissés tels quels : leur scraping a eu lieu ou n'aura plus lieu.

---

*Scraper — l'heure des qualifications est relevée au passage.* `decouvrir()` classait jusqu'ici les événements en deux tas : la « Course », et les écartés. Un troisième apparaît, reconnu par le motif `qualif` (insensible à la casse, posé sur le libellé brut : Unibet écrit « Qualifications », rien ne garantit qu'il n'écrira pas « Qualifying »). Les horaires trouvés sont rangés sur le GP, puis `resoudre_qualifications()` tranche.

**La DERNIÈRE qualification l'emporte, jamais la première**, et c'est le point à ne pas défaire. Un week-end sprint en compte deux : la qualification du sprint le vendredi, et la vraie qualification le samedi. C'est la seconde qui arrête la grille de départ, donc la seule après laquelle les cotes ont un sens (règle 4.3). Retenir la première ferait figer les cotes **un jour trop tôt, sur une grille qui n'existe pas encore**. Une qualification qui tomberait après le départ est écartée — horaire abîmé, et il déclencherait un scraping après la course.

**Le repli est `date_course - 22h`**, et il est journalisé en `warning` à chaque fois. 22h place les qualifications le samedi après-midi pour une course le dimanche après-midi ; le scraping tombe alors deux heures après, le samedi en fin de journée. Les logs disent toujours lequel des deux cas s'applique — c'est ce qui empêche le repli de devenir le régime normal sans que personne ne s'en aperçoive.

**Constat de terrain, et il compte.** Interrogé le 16 août 2026 (J-7 du GP Pays-Bas), le nœud racine d'Unibet **n'expose aucun événement de qualification** : un seul événement « Course » sous le GP, et rien d'autre — vérifié aussi dans le bloc SSR de la page d'événement, qui n'en contient pas davantage. **C'est donc le repli qui s'applique aujourd'hui.** Les épreuves annexes apparaîtront peut-être à l'approche de la course, comme le font les marchés (point de vigilance de l'étape 6) ; le code traite les deux cas et dit lequel. **À relire dans les logs le samedi du premier vrai Grand Prix.**

`_enregistrer` écrit l'horaire **même pour un GP figé** : c'est une donnée de programme, pas une cote. La refuser à un GP déjà figé priverait l'interface d'un horaire exact qu'Unibet vient d'annoncer. Le compte rendu du scraping porte désormais `gp_id` et `id_unibet` — c'est par `gp_id` que le job retrouve le Grand Prix qu'il voulait figer. Se fier au nom ne tiendrait pas : Unibet en change l'orthographe d'une semaine à l'autre, ce qui est déjà la raison d'être de `id_unibet` en base.

**Le refus d'un GP figé devient explicite.** Il était jusqu'ici une ligne `info` discrète ; c'est maintenant un `warning` nommant le Grand Prix, son statut et le nombre de cotes ignorées, et le message part aussi dans le compte rendu (`refus`). C'est exactement ce qu'on vient chercher dans les logs quand on se demande pourquoi une cote n'a pas bougé.

*Job* — `backend/app/jobs/scraper.py`, second `AsyncIOScheduler` démarré dans le `lifespan` à côté de celui de l'étape 6. Aucun processus ni thread supplémentaire, ce qui compte sur le plan gratuit. Il n'est pas démarré sans configuration Supabase, pour la même raison exactement que l'autre.

| Réglage | Valeur | Pourquoi |
|---|---|---|
| Vérification | **1h** | Le job de résultats court après une donnée qui paraît d'un instant à l'autre ; celui-ci attend une heure connue à l'avance et écrite en base. Une rafale n'apporterait rien. |
| Déclenchement | **qualifs + 2h** | Règle 4.3. |
| Fenêtre | **4h** | Sur le plan gratuit, Railway se met en veille (section 9). Un déclenchement à l'heure pile serait manqué **définitivement** si le service dort à cet instant, et le Grand Prix n'aurait jamais de cotes. La fenêtre laisse quatre tours pour rattraper — dont trois après un premier échec. |
| Premier tour | **+2 min** | Le job de résultats prend le sien à 30 s ; les espacer évite qu'un redéploiement ne lance de front un scraping Unibet et une rafale d'appels OpenF1. |

**Le figeage ne suit qu'un scraping réussi**, et « réussi » est vérifié sur trois points : le GP visé figure dans le compte rendu, il n'était pas déjà figé, et **au moins une cote a été écrite**. À défaut, le statut reste `a_venir` et le tour suivant réessaie tant que la fenêtre est ouverte. Figer après un échec arrêterait les cotes sur ce que la base contenait avant — au pire, sur rien du tout.

**Le scraping n'est pas ciblé, et il ne peut pas l'être** : Unibet n'expose que le Grand Prix suivant et ne se laisse pas interroger par identifiant (section 3.1). On scrape donc ce qui est disponible, et **on ne fige que celui qu'on visait** — un autre Grand Prix rencontré au passage garde son statut, ses propres qualifications n'ayant pas eu lieu.

Deux points de mise en œuvre :

1. **Le `PATCH` de figeage filtre sur le statut autant que sur l'identifiant** (`id=eq.… & statut=eq.a_venir`). Sans ce second filtre, un scraping tardif ramènerait à `cotes_figees` un GP que le job de résultats vient de passer à `termine`, et **le remettrait dans la boucle de surveillance**. Zéro ligne touchée n'est pas une panne : c'est l'état voulu, atteint par quelqu'un d'autre.
2. **Passé la fenêtre, aucune alerte répétée.** Contrairement au job de résultats, qui alerte une fois puis se tait, celui-ci se tait tout de suite : le Grand Prix resterait dans la liste des candidats jusqu'à ce que le job de résultats le passe à `termine`, et une erreur par heure jusque-là noierait les logs. Le silence est rattrapable — `POST /scraper/declencher` reste disponible.

Comme le job de résultats, ce module suppose **un seul processus**. À plusieurs instances, deux schedulers scraperaient en parallèle : l'upsert des cotes est idempotent, les appels à Unibet ne le sont pas. Même remède que pour l'étape 6 : `pg_try_advisory_lock` ou worker dédié.

*`POST /scraper/declencher` fige aussi.* Un même scraping doit avoir le même effet, qu'il vienne d'une horloge ou d'un `curl` : après succès, les Grands Prix effectivement scrapés passent en `cotes_figees`. La route reste **asynchrone et `202`** — son contrat ne change pas —, ce qui a une conséquence à connaître : **le refus d'un GP déjà figé ne peut pas être renvoyé dans la réponse**, qui part avant que le scraping n'ait commencé. Il est dans les logs, explicite, avec le nom du Grand Prix et son statut.

**`?figer=false` est un ajout par rapport à la demande, et il évite un vrai piège.** Sans lui, le premier `curl` de la saison — passé un mardi, pour vérifier que le scraper écrit bien — figerait des cotes de mardi, sur une grille non définitive, et il faudrait un `update` à la main dans le SQL Editor pour les débloquer. Le défaut reste `true`, donc le comportement demandé ; la porte de sortie est explicite. La réponse porte `figera` pour que l'appelant sache ce qu'il vient de lancer.

`scraper_en_tache_de_fond()` disparaît de `app/scraper/unibet.py` : `app/jobs/scraper.declencher_en_tache_de_fond()` la remplace exactement, en ajoutant le figeage. Le module de scraping ne décide plus jamais de figer quoi que ce soit — il découvre, il écrit, il rend compte ; la décision appartient au job ou à la route.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Migration sur PostgreSQL 16 jetable (Docker), les **onze** dans l'ordre, avec doublure du schéma `auth` | s'appliquent sans erreur |
| Structure | colonne `timestamptz` **nullable** sans défaut, index bien **partiel** sur `statut = 'a_venir'`, contraintes de `grands_prix` intactes, une seule politique RLS |
| RLS | `anon` **lit** la nouvelle colonne (les horaires ne sont un secret pour personne), `authenticated` ne peut pas l'écrire |
| Reprise, sur une base montée avec les **dix** migrations précédentes puis peuplée | le GP `a_venir` daté reçoit `date_course - 22h` ; le GP **sans date** reste NULL, jamais une date inventée ; les GP `termine` et `cotes_figees` ne sont pas touchés |
| Rejeu | horaire corrigé à la main **conservé**, aucune notice de reprise au second passage ; rejeu des onze migrations sur base peuplée : **calendrier, classement et statistiques rendent exactement la même chose**, données inchangées |
| Résolution de l'heure des qualifications | **69 contrôles passent** (avec le reste de l'étape) — qualif Unibet retenue ; **week-end sprint : la dernière l'emporte**, quel que soit l'ordre d'arrivée ; qualif postérieure au départ écartée ; aucune qualif → repli de 22h ; **ni qualif ni course → « inconnue », jamais une date inventée** ; qualif connue sans heure de course retenue quand même ; motif reconnaissant « Qualifications », « QUALIFYING », « Qualif. Sprint » et ne prenant pas « Course » pour une qualification |
| Découverte | les deux qualifications d'un week-end sprint relevées, le « Championnat du monde » toujours écarté, dates converties de Paris vers UTC |
| Enregistrement | colonne écrite à la bonne valeur ; compte rendu portant `gp_id` et `id_unibet` ; **GP `cotes_figees` et GP `termine` : aucune cote écrite, refus explicite dans le compte rendu, horaire des qualifs quand même tenu à jour, statut jamais transmis à l'upsert** |
| Fenêtre du job | rien à 30 min ni à 1h59 ; déclenché à 2h01 **et cotes figées** ; encore dans la fenêtre à 5h59, plus rien à 6h01 ; requête filtrant sur `a_venir` et sur une date connue ; GP sans date de qualifications jamais déclenché |
| Figeage | le `PATCH` vise `id=eq.… & statut=eq.a_venir` ; **scraping en échec → pas figé** ; **GP absent du compte rendu → pas figé, et l'autre GP rencontré non plus** ; **aucune cote enregistrée → pas figé** ; une panne de base ne fait pas tomber la boucle |
| Déclenchement manuel | scraping puis figeage ; `?figer=false` : scraping sans figeage ; GP déjà figé → aucun `PATCH` inutile ; la tâche de fond n'avale rien en silence et ne lève pas |
| Route et non-régression | `401` sans secret et sur mauvais secret (**la signature survit au décorateur**), `202` sur bon secret, `figera` porté jusqu'à la réponse ; **19 chemins toujours exposés**, `/health` en `0.11.0`, routes des étapes précédentes toujours protégées, cotes toujours publiques |
| Scheduler | démarré, **un seul emploi nommé « scraper »**, `max_instances=1`, `coalesce`, un tour par heure, second démarrage sans doublon, arrêt idempotent ; le `lifespan` le démarre et l'arrête, **et seulement si Supabase est configuré** |
| Contre le **vrai** Unibet | jeton obtenu, GP Pays-Bas découvert, date de course `2026-08-23T13:00Z` ; **aucun événement de qualification exposé aujourd'hui** → repli appliqué et journalisé, scraping automatique calé au 2026-08-22 17:00 UTC |
| Sous un vrai `uvicorn` | les **deux** schedulers démarrent et se journalisent ; sans configuration Supabase, les deux refusent de démarrer avec un avertissement explicite ; `?figer=false` journalisé |
| `npm run build` | passe, version `0.11.0` dans le bundle |

---

**Refonte visuelle des quatre écrans principaux** (version `0.12.0`)

Interface plus vivante, à blocs de couleur pleins. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.11.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1` et `0.8.1`). Quatre jetons de couleur, un module partagé, quatre écrans refondus.

*Palette élargie* — `--color-vert-sauge: #4A7C59`, `--color-bleu-ardoise: #2C4A6E`, `--color-terracotta: #C4622D`, `--color-violet: #5C3D7A` entrent dans le bloc `@theme` d'`index.css`, avec leurs utilitaires Tailwind (`bg-vert-sauge`, `text-bleu-ardoise`…).

**Elles ne remplacent rien et leur périmètre est borné** : elles ne peignent que des **aplats de bloc** — carte de championnat, en-tête de section de marché, bloc de pronostic — et le texte posé dessus. Jamais un fond d'écran, jamais un texte sur le beige, jamais une bordure. C'est exactement le périmètre déjà accordé à la palette des voitures (étape 8) et aux livrées (étape 7), et c'est ce qui fait que les sept couleurs de la section 5 gardent tous leurs rôles.

---

*`frontend/src/lib/couleurs.js` — le seul endroit qui choisit une couleur de bloc.* Six aplats : rouge `primaire`, amber `accent`, et les quatre nouveaux. Deux viennent donc du design system plutôt que d'inventer un rouge et un orange de plus.

**Le conflit de la demande, et comment il est tranché.** Elle écrit « le texte sur ces cartes est toujours blanc » pour les cartes de championnat — qui incluent l'amber — **et** « texte noir `#1A1A1A` sur amber (meilleur contraste) » pour les blocs de bonus. Les deux règles se contredisent sur l'amber, et c'est la seconde qui gagne : sur `#E8A020`, le blanc tombe à **2,2:1** de contraste quand `#1A1A1A` monte à **7,7:1**.

`encreSurAplat(hex)` porte cet arbitrage une fois pour toutes : **le blanc est conservé tant qu'il tient le plancher AA des grands textes (3:1), et lâché en dessous.** C'est un seuil, pas un goût. Les cinq autres aplats gardent le blanc, l'amber passe à l'encre foncée — soit exactement ce que la demande décrit pour les bonus, appliqué partout. `tonalites(hex)` en dérive le jeu de classes complet (encre, encre secondaire, deux surfaces, fantôme à 40 %) : **les écrans ne choisissent jamais `text-white` eux-mêmes**, sans quoi un bloc amber finirait par recevoir du texte blanc parce qu'un écran l'a écrit de mémoire. L'encre secondaire est à 70 % et non 60 % : sur les deux aplats les plus clairs, 60 % passe sous le seuil de lisibilité à 12px.

*Écart assumé sur l'attribution de la couleur d'un championnat, et c'est le point à ne pas défaire.* La demande voulait « par ordre d'inscription modulo 6, même logique que les livrées de voiture ». Les livrées disposent d'un `ordre_inscription` servi par la base (étape 7) ; **un championnat n'a pas d'équivalent** — le seul rang disponible serait sa position dans *ma* liste, qui n'est pas une propriété du championnat. Deux conséquences, toutes deux fausses : l'écran de détail, atteint par lien direct, ne connaît aucune liste et ne saurait pas quelle couleur peindre ; et deux membres du même championnat le verraient de deux couleurs différentes, alors que la demande parle bien de « **la** couleur du championnat ».

`couleurChampionnat` prend donc l'empreinte de l'identifiant : même couleur partout, pour tout le monde, sans transporter la moindre donnée entre écrans. **Le prix est assumé** : avec six teintes, deux championnats d'une même liste peuvent tomber sur la même, là où un modulo sur le rang aurait garanti six cartes distinctes. Reconnaître un championnat à sa couleur d'un écran à l'autre vaut mieux que les distinguer deux à deux sur un seul.

---

*Écran 1 — Accueil.* Le bloc du Grand Prix garde son rouge `#800111`, c'est l'élément signature. Le **tracé du circuit** y est posé en filigrane à droite, à 8 % de blanc : il réutilise `TraceCircuit` (étape 9), donc le GP d'Italie montre Monza, celui de Belgique Spa, les autres le tracé générique. `overflow-hidden` le laisse déborder par la droite plutôt que de le contraindre à tenir en entier, ce qui l'écraserait.

Les cartes de championnat deviennent des aplats pleins, avec leur numéro en grand à droite : le même chiffre deux fois, le grand à 40 % derrière le petit en encre pleine. Le fantôme est `aria-hidden` — un lecteur d'écran n'a pas à entendre le numéro en double. Le chevron de la maquette disparaît : la carte entière est devenue une surface tactile, et le coin droit est désormais occupé.

**Ce numéro est la position de la carte dans la liste, pas un rang de classement**, et c'est la limite à connaître. Le vrai rang du joueur dans chaque championnat existe depuis l'étape 7, mais il coûterait **un appel Railway par championnat** — `GET /championnats/{id}/classement` n'agrège qu'un championnat à la fois. Aucune étiquette ne le présente comme un classement ; si le vrai rang devient souhaitable, c'est une route qui les servirait tous d'un coup qu'il faut ajouter, pas du code d'écran. **Fait en version `0.14.0`** : `GET /championnats/moi` porte désormais `position` (rang, points, points du leader), et la carte affiche le vrai rang.

Le squelette des cartes devient un aplat plein à la hauteur exacte de la carte (16 + 46 + 16), et non plus une carte blanche à barres. Sa **couleur**, elle, ne peut pas être devinée — on ne sait pas encore quels championnats vont arriver — et le gris des squelettes reste la seule réponse honnête. C'est le seul endroit de l'app où un aplat de couleur naît d'un squelette gris ; ailleurs la règle de l'étape 9 tient toujours.

*Écran 2 — Championnat.* En-tête coloré plein cadre à la couleur du championnat : il touche les deux bords et **court sous la zone sûre haute** (`pleine-largeur` + `coiffe-ecran`, deux utilitaires ajoutés à `index.css`). Une couleur qui s'arrêterait sous la Dynamic Island se lirait comme un bandeau posé de travers ; le texte, lui, reste rendu dans la zone sûre. Le bouton de retour vit dans la bande plutôt qu'au-dessus : deux en-têtes empilés auraient mangé 150px avant le premier contenu utile.

Trois écarts assumés :
1. **Le bloc du code d'invitation passe de l'aplat rouge à une carte blanche** dont seul le code prend la couleur du championnat. Deux aplats pleins à la suite se seraient disputé le même écran, et le rouge de la marque sous un en-tête violet aurait donné deux couleurs concurrentes sur une même page.
2. **La bascule segmentée Classement / Piste disparaît** au profit du bouton « Vue piste » rouge pleine largeur demandé. Les deux ensemble auraient offert deux chemins vers le même écran à trois centimètres l'un de l'autre. L'aller-retour reste symétrique : la vue piste ramène ici par son propre bouton de retour. `composants/BasculeVue.jsx` et `composants/Onglets.jsx` ne sont plus montés nulle part ; **les deux fichiers et leurs transitions restent en place**, comme le code OAuth depuis la version `0.2.2` — le contrôle segmenté est déjà écrit et vérifié, et il redevient la bonne réponse le jour où Unibet ouvre dix marchés.
3. **« Quitter le championnat » devient un lien discret** au lieu d'un bouton blanc pleine largeur : deux boutons pleine largeur empilés se seraient concurrencés, et c'est déjà le traitement de « Se déconnecter » ailleurs dans l'app.

Chaque ligne de classement devient sa **propre carte blanche à filet coloré de 4px**. Le filet porte la couleur de la **voiture du membre**, pas celle du championnat : c'est la personne qu'on cherche à reconnaître dans une liste, et c'est la même couleur qu'elle porte sur la vue piste et sur son profil. Ce n'est pas une bordure au sens de la section 5 — celle-ci proscrit les traits fins qui *cernent* un bloc ; celui-ci est un aplat posé à l'intérieur, et il remplace la pastille d'initiale qui tenait ce rôle avant.

*Écran 3 — Cotes.* Les marchés ne sont plus derrière des onglets : ils sont **tous empilés**, chacun sous son en-tête coloré. Vainqueur en rouge, Podium en bleu ardoise, Écurie Vainqueur en vert sauge, comme demandé. Les marchés que le scraper **découvre dynamiquement** (section 3.1) ne peuvent pas être nommés d'avance : ils prennent à tour de rôle les trois teintes restantes (terracotta, violet, amber), et **jamais celle d'un des trois marchés du noyau** — le repère couleur → marché tient donc quoi qu'Unibet ouvre. Le libellé affiché reste celui du bookmaker, jamais un slug reconstitué.

**Conséquence à surveiller** : au jour de la refonte Unibet n'expose que trois marchés, et l'empilement se lit d'un défilement. Après les qualifications, le noyau complet annoncé en section 3.1 (top 6, top 10, duels…) fera un écran très long, à vingt-deux pilotes par section. C'est le moment où `Onglets.jsx` redevient utile.

L'étoile de favori devient une **pastille** : ambre quand la cote est épinglée, beige sinon. L'état est ainsi lisible d'un coup d'œil sur vingt-deux lignes, là où deux nuances d'étoile demandaient de regarder de près. L'étoile pleine passe à l'encre foncée une fois sur l'ambre — en blanc, elle disparaîtrait. L'échange d'icônes (transitions-dev 09) est conservé tel quel, et les marges négatives sont recalculées pour que la rangée ne gagne pas 12px par cote.

*Écran 4 — Pronostics.* Les deux pronostics obligatoires prennent leurs aplats : **vainqueur en rouge, podium en bleu ardoise**, ce qui les distingue au premier coup d'œil des bonus, ambre et plus petits. Les emplacements vides annoncent « Non sélectionné » dans l'encre secondaire du bloc ; le podium ajoute une étiquette « 1er » / « 2e », faute de quoi ses deux emplacements diraient exactement la même chose. Le pilote retenu dans la liste dépliée passe en négatif — surface blanche, texte à la couleur du bloc : c'est le seul contraste franc disponible à l'intérieur d'un aplat déjà coloré.

**L'ambre désigne la sélection, pas la liste**, et c'est un écart de lecture assumé. La demande parle des « 3 bonus dans des blocs amber » : peindre les vingt favoris en ambre aurait donné un mur où plus rien ne se distingue. Un bonus retenu est donc un bloc ambre à encre `#1A1A1A`, un favori non retenu une carte blanche.

Le bouton de validation est **collé en bas** (`barre-collee`, utilitaire ajouté) avec la zone sûre iOS. Trois points portés par l'utilitaire : il **rend lui-même** `env(safe-area-inset-bottom)` et annule celui d'`ecran` par une marge négative — deux rembourrages superposés laisseraient une bande beige morte sous la barre une fois la page défilée à fond ; le dégradé au-dessus est le *scroll edge effect* d'`/apple-design`, le contenu se dissipe en passant dessous au lieu d'être coupé par un trait que la section 5 proscrit ; le message d'erreur voyage **avec** la barre, sinon il resterait hors de l'écran au moment précis où il compte. La barre n'est **pas** enveloppée dans un `Bloc` : `t-stagger-line` porte un `transform`, et un ancêtre transformé est exactement ce qui a chassé la barre de navigation des écrans à l'étape 10.

*Apport d'`/apple-design`* — zones tactiles de 44px et retour tactile à l'appui conservés partout (cartes, étoiles, emplacements, onglets de bas d'écran) ; l'en-tête coloré laisse la couleur passer sous la zone sûre mais jamais le texte ; le bouton de validation reste sous le pouce sur un écran qui déroule trois blocs et jusqu'à vingt favoris ; le fantôme du numéro et le tracé du circuit sont `aria-hidden`, un lecteur d'écran n'a rien à annoncer d'un effet de profondeur.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Les quatre écrans réutilisent celles déjà installées : *icon swap* (09) pour l'étoile, *accordion expand* (21) pour les emplacements, *texts reveal* (18) pour l'entrée des blocs, *skeleton loader* (14) et *shimmer* (15) pour les attentes, *text states swap* (04) pour les libellés qui changent. Un jeton de plus aurait été un jeton à maintenir sans rien gagner.

*Signalé plutôt que tranché seul, comme le demande la section 5* : rien dans les suggestions des trois skills n'a été appliqué contre ce fichier. Le skill Taste proscrit l'em-dash et les pastilles de statut décoratives — sans objet ici, l'app n'en emploie pas ; il recommande aussi une bibliothèque d'icônes tierce, ce que le projet ne fera pas, `composants/Icones.jsx` étant tiré des maquettes. Le seul point où un skill et la demande se rejoignaient contre la lettre de la demande est le contraste de l'amber, traité ci-dessus.

*Vérifié* — rendu hors navigateur (`react-dom/server`, cache localStorage doublé) : **101 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Module de couleurs | six aplats distincts au format `#RRGGBB`, les quatre teintes demandées présentes ; **encre foncée sur l'amber, blanche sur les cinq autres** ; couleur d'un championnat stable et indépendante du reste de la ligne ; championnat sans identifiant → aucun plantage ; vainqueur → rouge, podium → bleu ardoise, écurie → vert sauge ; **un marché découvert ne prend jamais la couleur d'un marché du noyau**, quel que soit son rang |
| Carte de championnat | aplat porté, **plus aucune surface blanche**, nom, effectif accordé, code, destination ; **numéro rendu deux fois**, fantôme à 40 % et `aria-hidden` ; zone tactile et retour à l'appui conservés |
| Ligne de classement | carte blanche, **filet à la couleur de la voiture du membre**, rang, points, critères de départage, « Toi », « Créateur », destination profil ; saison non commencée → aucun meilleur coup inventé ; **voiture blanche → filet servi par la seconde couleur** |
| Accueil | se rend ; bloc GP toujours rouge, **tracé du circuit posé à 8 % et décoratif** ; destination et libellé du bouton inchangés ; cartes colorées ; actions conservées |
| Championnat | en-tête à la couleur du championnat, **plein cadre et coiffant la zone sûre**, 120px, nom en grand, effectif dessous ; code servi **à la couleur du championnat** ; les deux membres classés ; **bouton « Vue piste » rouge plein**, plus aucune bascule segmentée ; calendrier et départ conservés ; **le mot « ligue » n'apparaît pas** |
| Cotes | **quatre sections empilées, plus aucun onglet** ; rouge, bleu ardoise et vert sauge sur les trois marchés nommés, teinte de repli sur le marché découvert ; libellés du bookmaker servis tels quels ; points affichés ; **étoile ambre à l'état actif, beige sinon**, échange d'icônes conservé ; GP fermé → plus d'étoile, sections toujours lisibles ; aucun marché → message et non écran vide |
| Pronostics | vainqueur en rouge, podium en bleu ardoise ; **trois emplacements « Non sélectionné »**, podium distinguant « 1er » et « 2e » ; étiquette « Obligatoire » conservée ; bonus proposés ; **bouton collé en bas, pleine largeur** ; accordéon conservé ; bloc bonus ambre et **encre foncée imposée par `tonalites`** |
| Règle 4.1 | **aucun « ×N » nulle part**, sur les quatre écrans |
| Bundle CSS | les quatre couleurs, les trois utilitaires et toutes les opacités employées (`text-white/8`, `bg-black/10`, `text-texte/40`…) sont bien générés |
| `npm run build` | passe, 127 modules, version `0.12.0` dans le bundle |

**Une limite du banc d'essai, à connaître** : le rendu statique n'exécute aucun effet. L'état « bonus retenu » de l'écran de saisie, qui vient du préremplissage posé dans un `useEffect`, ne peut donc pas être rendu ici — le couplage ambre + encre foncée est vérifié sur `tonalites`, qui le porte, et non sur le HTML.

---

**Passe de finition `/apple-design` — élévation, matériaux, typographie** (version `0.12.1`)

Le rendu de la refonte manquait de tenue : des aplats posés sur un fond, sans épaisseur. **Aucun écran n'est redessiné, aucune couleur ne change, aucune composition ne bouge** — la passe ne porte que sur ce que la section 5 laisse ouvert et sur ce qu'`/apple-design` gouverne. Frontend uniquement, `backend/app/config.py` reste en `0.11.0`.

*Élévation — le manque principal, et le plus visible.* L'app n'avait **aucune ombre** nulle part, hors la barre de navigation. Le style widget de la section 5 suppose des blocs autonomes **posés sur** un fond, pas des aplats découpés dedans : sans ombre, une carte blanche sur le beige n'a pas d'épaisseur, et rien ne dit ce qui flotte et ce qui est le fond.

Trois niveaux dans le bloc `@theme`, et un seul principe pour les distinguer — **plus une surface est grande, plus elle est épaisse** (`/apple-design` §12) :

| Jeton | Pour |
|---|---|
| `shadow-carte` | cartes et rangées (rayon 18–20px) |
| `shadow-bloc` | blocs principaux (rayon 24px) |
| `shadow-flottant` | ce qui survole vraiment : barre de navigation, barre d'action collée |

**Deux points à ne pas défaire.** Chaque niveau superpose **deux couches** : une ombre de contact très serrée, qui pose l'objet, et une ombre ambiante large, qui l'éloigne du fond ; une seule couche donne toujours l'un ou l'autre, jamais les deux. Et la teinte n'est pas un noir mais le **marron `secondaire` `#543925`** en très faible opacité : une ombre noire sur un fond beige tire vers le gris et salit la couleur. **Aucune couleur nouvelle n'entre par cette porte** — c'est une teinte du design system, en opacité.

L'échelle des rayons de la section 5 sert de grille d'attribution : un `rounded-bloc` reçoit `shadow-bloc`, un `rounded-carte` reçoit `shadow-carte`, et **`rounded-champ` ne reçoit rien** — ce sont les surfaces posées *à l'intérieur* d'un bloc (emplacements, pastilles, champs), qui ne cassent jamais leur plan. C'est la règle à suivre pour tout écran nouveau.

*Matériaux translucides* — la barre de navigation basse et la barre d'action collée cessent d'être des aplats opaques. `materiau-chrome` (blanc à 72 %, `blur(24px) saturate(180%)`) pour la barre, une version beige pour la barre collée : le contenu passe **sous** elles et reste deviné, ce qui dit à la fois qu'elles flottent et que la page continue. Une barre opaque, elle, ampute définitivement une bande d'écran. La saturation compense le lavage des couleurs par le flou.

Le **liseré blanc** que le snippet d'`/apple-design` pose sur l'arête haute d'un matériau n'est **pas repris** : la section 5 proscrit les traits fins, et sur une barre déjà blanche il ne se verrait pas. Signalé plutôt que tranché seul, comme le demande la section 5 — le CLAUDE.md gagne.

*Deux réglages d'accessibilité nouveaux*, indépendants de `prefers-reduced-motion` déjà couvert : **`prefers-reduced-transparency: reduce`** rend les deux matériaux opaques et coupe le flou, **`prefers-contrast: more`** fait de même sur la barre de navigation. Un matériau translucide sans repli est illisible pour qui a demandé le contraire.

*Typographie* — le crénage devient **spécifique à la taille**, ce qu'il n'était qu'à moitié. Les titres avaient déjà `-0.02em` (étape 1) ; les **grands chiffres** (32–44px) ne l'avaient pas alors qu'ils en ont plus besoin encore : un chiffre n'a ni jambage ni hampe, donc rien qui vienne remplir l'espace entre deux caractères. `--text-score` passe à `-0.025em`, `--text-score-lg` à `-0.03em`. Le crénage **positif** des petits labels (`0.7px`, section 5) est conservé tel quel : c'est exactement ce que demande `/apple-design` §15 pour du petit texte.

*Retour tactile dosé* — `pressable` (`scale(0.97)`) reste pour les boutons. `pressable-large` (`scale(0.985)`) est ajouté pour les **grandes surfaces** : 3 % sur une carte pleine largeur déplacent une dizaine de pixels, et le geste devient une secousse au lieu d'un appui. La règle d'`/apple-design` est que le retour soit *perçu*, pas qu'il ait partout la même amplitude — un objet lourd s'enfonce moins qu'un bouton. Les deux sont coupés sous `prefers-reduced-motion`.

*Ce qui n'a **pas** été fait, et pourquoi.* Le fond de l'app reste un aplat beige uni. Lui donner un très léger dégradé ajouterait de la profondeur derrière les blocs — c'est ce que fait un fond d'écran iOS sous les widgets — mais la section 5 fixe « Fond de l'app `#F5F0EB` », et un dégradé n'est plus cette couleur-là. **À arbitrer explicitement avant de le tenter.** De même, le haut des écrans n'a pas de *scroll edge effect* : il faudrait un élément fixe, donc monté dans `App.jsx` et non dans `Ecran` — c'est la leçon de l'étape 10 sur les ancêtres transformés.

*Vérifié* — rendu hors navigateur (`react-dom/server`, cache localStorage doublé) : **77 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Jetons | trois niveaux déclarés ; **teintés du marron, aucun noir pur** ; carte et bloc superposent bien deux couches ; **le bloc est plus épais que la carte** ; matériau translucide déclaré, barre collée translucide aussi |
| Accessibilité | `prefers-reduced-transparency` coupe le flou, `prefers-contrast` existe, **les deux retours tactiles sont coupés en mouvement réduit** |
| Typographie | crénage négatif sur les deux tailles de grands chiffres, **crénage positif conservé sur les petits labels** |
| Barre de navigation | matériau translucide, `shadow-flottant`, **plus aucune ombre écrite en dur ni aplat blanc opaque**, aucune bordure, zone sûre conservée, quatre onglets, un seul `aria-current`, échange d'icônes conservé, **rien sans session** |
| Composants partagés | bouton principal et alerte élevés |
| Cartes | carte de championnat et ligne de classement élevées, **et portant `pressable-large` et non `pressable`** ; filet coloré, fantôme à 40 %, numéro rendu deux fois |
| Écrans | les quatre se rendent ; bloc GP en `shadow-bloc`, en-tête de championnat en `shadow-bloc` plein cadre coiffant la zone sûre, quatre sections de marché élevées, blocs de pronostic élevés ; **aucune carte plate ne subsiste sur les quatre écrans** |
| Non-régression | couleurs, encres, marchés, destinations, « Vue piste », barre collée, emplacements « Non sélectionné », **aucun « ×N » nulle part**, le mot « ligue » toujours absent |
| `npm run build` | passe, 127 modules, version `0.12.1` dans le bundle |

---

**Refonte visuelle sans restriction des skills** (version `0.13.0`)

Les skills `/apple-design`, `/design-taste-frontend` et `/transitions-dev` ont eu la main sur les compositions, espacements, ombres, matériaux, animations et hiérarchie visuelle des quatre écrans principaux. La règle de priorité de la section 5 a été réécrite en conséquence : seules la **palette** et la **typographie** restent hors de leur portée, plus le vocabulaire de la section 1. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.11.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1` et `0.12.x`).

*Lecture du brief, telle que la pose le skill Taste* — PWA iOS de pronostics F1 entre amis, langage widget chaleureux, orientée matériaux translucides, navigation à grand titre rétractable et mouvement à ressort. Dials retenus : `DESIGN_VARIANCE 6`, `MOTION_INTENSITY 7`, `VISUAL_DENSITY 4`. Six est en deçà du 8 de base du skill parce qu'il s'agit d'une **application**, pas d'une page d'atterrissage : une composition asymétrique change de sens quand on revient sur le même écran vingt fois par week-end.

---

***L'en-tête à grand titre rétractable — l'apport principal de la passe.***

C'était le plus gros écart avec une application native, et il touchait **tous** les écrans : l'en-tête défilait avec le contenu, et le titre de la page disparaissait dès le premier mouvement du pouce. Sur le tableau des cotes, qui empile trois marchés de vingt-deux pilotes, on ne savait plus ni où l'on était ni comment sortir — les deux premières questions du « wayfinding » d'`/apple-design` §16.

`frontend/src/composants/EnTeteEcran.jsx` : la rangée de retour reste collée en haut, le grand titre défile dessous et se replace en petit dans la barre. **Le matériau translucide n'apparaît qu'une fois du contenu passé dessous** — c'est la règle des *scroll edge effects* du §12, le chrome ne se matérialise que là où il recouvre vraiment quelque chose. Une barre translucide posée sur du vide se lit comme un bandeau.

**Quatre points de mise en œuvre à ne pas défaire :**

1. **La bascule passe par un `IntersectionObserver` sur une sentinelle, jamais par un écouteur de défilement.** Un `scroll` se déclenche à chaque image et repasserait par l'état React à chaque fois ; l'observateur ne rend que deux fois par écran, aux deux franchissements. C'est aussi une interdiction franche du skill Taste (§5.D).
2. **Le composant doit être monté en enfant direct d'`Ecran`.** Les blocs `t-stagger-line` portent un `transform` et un `filter` pendant leur entrée : un `position: sticky` posé à l'intérieur se collerait à leur boîte au lieu de la fenêtre, et l'en-tête défilerait avec la page. C'est le cousin exact du piège qui a chassé la barre de navigation basse des écrans à l'étape 10 — à ceci près que `sticky`, contrairement à `fixed`, n'est cassé que par un ancêtre *scrollable*, pas par un ancêtre transformé ; ici c'est bien la boîte de référence qui change.
3. **Seule l'opacité du matériau s'anime**, sur un calque à part. Faire varier le rayon du `backdrop-filter` coûterait une passe de composition par image sur un élément pleine largeur.
4. **`--entete-hauteur` est la source unique du décalage.** Les en-têtes de marché collants s'y accrochent ; écrite en dur à deux endroits, la valeur aurait divergé au premier ajustement de la barre, et les deux en-têtes se seraient recouverts.

*Mode teinté, pour l'écran d'un championnat* — la barre porte la couleur du championnat **en permanence** et l'aplat du nom la prolonge juste dessous, les deux se lisant comme un seul bloc. Attendre le défilement pour la colorer laisserait une bande beige au-dessus d'un aplat de couleur, ce qui se lit comme un défaut de calage et non comme une intention. Le `-mt-2` qui referme le rembourrage bas de la barre n'est pas un ajustement à l'œil : sans lui, une ligne de fond apparaît entre les deux surfaces au premier pixel de défilement.

**`composants/EnTete.jsx` reste en place et en service** sur les douze autres écrans. Le nouvel en-tête n'a été posé que sur les quatre écrans du périmètre ; l'étendre aux autres est une substitution d'import, sans autre changement.

---

*Élévation et matière* — `--shadow-aplat` s'ajoute aux trois niveaux de la version `0.12.1`. Les ombres existantes sont réglées pour une **surface blanche** ; sous un bloc rouge, violet ou bleu ardoise, un marron clair ne se voit plus. Celle-ci est plus profonde et plus contrastée, ce qui est la règle d'`/apple-design` §12 sur l'ombre sensible au contexte : plus la surface est dense, plus elle doit peser sur le fond. Elle porte les aplats de couleur — bloc du prochain GP, cartes de championnat, en-tête de championnat, blocs de pronostic obligatoires.

`lueur-haute` pose sur ces mêmes aplats un galbe de lumière très doux, en haut. Un aplat plein est une surface morte : rien n'y dit d'où vient la lumière. **Aucune couleur n'entre par cette porte** — c'est du blanc à très faible opacité, la teinte du bloc reste exactement la sienne. L'overlay est `aria-hidden` : un lecteur d'écran n'a rien à annoncer d'un effet de profondeur.

---

*Retour tactile — l'aller et le retour cessent d'avoir la même courbe.* `--ease-ressort` entre dans les jetons de mouvement (l'équivalent CSS d'un amortissement ~0,8 d'`/apple-design` §4). L'enfoncement reste immédiat (100ms, `ease-out`), c'est la réponse au doigt et elle ne doit rien faire attendre ; le **relâchement** remonte sur le ressort et dépasse très légèrement avant de se poser. C'est ce qui distingue un objet physique qui se détend d'un rectangle qui reprend sa taille. Une courbe unique dans les deux sens donne toujours l'un ou l'autre, jamais les deux. Les deux amplitudes de la version `0.12.1` (`pressable`, `pressable-large`) sont conservées telles quelles, et les deux restent coupées sous `prefers-reduced-motion`.

Le ressort ne s'emploie **que là où un geste a précédé le mouvement**, jamais sur une apparition automatique, où le dépassement se lirait comme une erreur.

---

*Écran 1 — Accueil.* Grand titre « Salut *pseudo* » rétractable, l'avatar passe dans la barre collante : c'est le seul élément qui doit rester atteignable quel que soit le défilement.

Le bloc du prochain Grand Prix est recomposé autour de **deux cases de statut** (Départ, Fermeture dans) au lieu d'une phrase. Un chiffre posé sous son label se lit d'un coup d'œil, là où « Pronos ouverts · Fermeture dans 2j 14h 32min » demande de lire une ligne entière pour en extraire la même information. Le **nom du Grand Prix passe à l'échelle des titres de page** : c'est ce qu'on vient lire, il doit être le plus gros élément de l'écran. Les trois destinations du bouton et leurs libellés sont inchangés (versions `0.5.1` et `0.9.0`).

*Écran 2 — Championnat.* En-tête teinté rétractable (voir plus haut). **Le rang des trois premiers passe dans une pastille à la couleur de la voiture du membre**, les autres restent en chiffre nu : le podium doit se repérer sans lire les nombres. L'encre de la pastille est calculée par `encreSur` (étape 8), donc lisible quelle que soit la livrée choisie — y compris une voiture blanche.

*Écran 3 — Cotes.* **Les en-têtes de marché deviennent collants.** C'est le vrai apport sur cet écran : à mi-liste d'un marché de vingt-deux pilotes, plus rien ne disait ce qu'on lisait, et il fallait remonter pour le savoir. Le compteur de l'en-tête cède la place au **nombre de favoris épinglés dans ce marché** dès qu'il y en a — « 22 » ne dit rien qu'on ne voie en défilant, « 3 en favoris » dit où en est le joueur. La case de points de la ligne se teinte d'ambre une fois la cote épinglée : la ligne entière dit « retenue », pas seulement l'étoile de 18px posée au bout. Le bouton de validation passe en **barre collée en bas** et compte les favoris.

*Écran 4 — Pronostics.* La barre collée porte désormais le **total potentiel**, au-dessus du bouton. C'est le chiffre qui fait changer d'avis : il doit bouger sous les yeux au moment du choix, pas attendre le récapitulatif. Il applique la règle tranchée à l'étape 6 — chaque pronostic compte pour sa cote, le podium pour la somme de ses deux pilotes — la même que `RecapPronostics.jsx`, pour que les deux écrans ne puissent pas annoncer deux totaux différents. **Il n'apparaît qu'une fois quelque chose de choisi** : « 0 pts » avant le premier pilote se lirait comme un mauvais départ.

---

*Mouvement* — **aucune transition nouvelle, aucun jeton de transitions-dev nouveau.** Le compte à rebours de l'accueil et du bloc de fermeture passent par *text states swap* (04), déjà installé : ils changent toutes les secondes dans la dernière heure, et un remplacement de texte nu les ferait clignoter. Le seul jeton ajouté est `--ease-ressort`, qui relève du retour tactile et non d'un snippet.

*Accessibilité* — `prefers-reduced-motion` couvre les trois nouvelles transitions ; sous ce réglage **le titre compact reste montré sans glisser** plutôt que de disparaître, la navigation n'étant pas de la décoration. `prefers-reduced-transparency` et `prefers-contrast: more` rendent le matériau de l'en-tête opaque, avec `--entete-opaque` pour que la version teintée retombe sur sa couleur et non sur le beige.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage pré-rempli) : **68 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| En-tête rétractable | présent sur les quatre écrans, **déplié au premier rendu**, titre compact rendu ; l'accueil n'a **aucun bouton de retour** (racine d'onglet) ; les cotes nomment le Grand Prix dans leur retour |
| Mode teinté | le championnat porte `data-materiau="fixe"` et sa couleur en variable CSS ; les cotes et les pronostics restent en matériau au défilement ; en-tête pleine largeur et arrondi en bas |
| Rendu isolé | `EnTeteEcran` se rend **sans `IntersectionObserver`** (rendu serveur), sentinelle bien placée après le grand titre |
| Élévation | bloc GP, blocs obligatoires et cartes en `shadow-aplat` ; **au moins trois lumières spéculaires sur l'accueil** ; plus aucune carte de championnat plate |
| Accueil | nom du GP à l'échelle des titres, cases Départ et Fermeture, destination et libellé inchangés, tracé de circuit décoratif, les deux championnats avec codes et effectifs accordés |
| Championnat | filet à la couleur de la voiture, pastille de podium, les trois membres classés, saison non commencée dite, « Vue piste » conservé, **le mot « ligue » absent** |
| Cotes | **quatre en-têtes de marché collants**, libellés du bookmaker servis tels quels, compteur de favoris par marché, cote épinglée teintée, barre collée, bouton comptant les favoris, **plus aucun onglet**, rangée de favoris calée au défilement |
| Pronostics | trois emplacements « Non sélectionné », podium distinguant 1er et 2e, barre collée, **aucun total avant le premier choix**, échange de texte et accordéon conservés |
| Règle 4.1 | **aucune cote brute « ×N »** sur les quatre écrans, points bien habillés |
| CSS compilé | `.entete-collante`, `.entete-titre-compact`, `.section-collante`, `.lueur-haute`, `--shadow-aplat`, `--ease-ressort`, `--entete-hauteur` générés ; la barre teintée force son matériau ; **repli transparence réduite et mouvement réduit présents** |
| `npm run build` | passe, 128 modules, version `0.13.0` dans le bundle |

---

**Fond texturé, cartes de championnat enrichies, boutons intégrés au flux** (version `0.14.0`)

Deux défauts relevés sur **iPhone réel** — le premier essai sur appareil, jamais fait jusqu'ici. Le fond trop uniforme et plat ; les cartes de championnat trop minces et vides, une ligne de texte sur un aplat. Quatre corrections, dont une qui demande une donnée que l'API ne servait pas encore.

**Aucune migration.** Le seul changement de base serait une fonction SQL, et il n'en faut pas : le classement existe depuis l'étape 7, il suffisait de l'appeler.

---

***Correction 1 — le grain du fond.***

Le beige `#F5F0EB` en aplat uni lit comme un vide : rien n'y accroche la lumière, et les blocs paraissent découpés dedans plutôt que posés dessus. Un bruit gris à **4 %**, en image de fond sur `body`, lui donne la matière d'un papier légèrement texturé. Il couvre **tous les écrans à la fois**, sans qu'aucun ait à le savoir.

**Aucune couleur nouvelle n'entre par cette porte** : la couleur de fond reste exactement celle de la section 5, le grain est du gris à 4 % par-dessus.

Trois points de mise en œuvre à ne pas défaire :

1. **C'est une image de fond, pas un filtre vivant ni un calque fixe.** Le motif est rastérisé une fois puis répété en tuile de 160px, et le navigateur le met en cache. Un `filter` SVG appliqué à un conteneur qui défile, ou un `background-attachment: fixed` — que Safari iOS gère mal — repeindraient à chaque image. C'est la contrainte de performance que le skill Taste pose explicitement sur les grains, et la raison pour laquelle celui-ci vit sur `body` plutôt que sur un calque `fixed`.
2. **`stitchTiles="stitch"`** dans le `feTurbulence` : sans lui, la turbulence recommence sa séquence à chaque tuile et la répétition se voit en damier de 160px.
3. **Le contraste du bruit est étiré dans le filtre** (`feComponentTransfer`, pente 1,8) avant d'être ramené à 4 %. `fractalNoise` sort une valeur très resserrée autour du gris moyen : sans cet étirement, 4 % ne donnent littéralement rien à voir, et il aurait fallu monter l'opacité — donc assombrir le fond — pour obtenir la même texture. La demande disait 3-4 % ; c'est bien 4 %, et c'est l'étirement qui les rend visibles.

Sous **`prefers-contrast: more`**, le grain disparaît et le fond redevient un aplat pur : une texture, même à 4 %, retire un peu de contraste effectif au texte posé dessus, ce que ce réglage demande précisément d'éviter. La vue piste, qui peint son propre asphalte par-dessus, n'est pas concernée.

---

***Correction 2 — les cartes de championnat, et la donnée qui leur manquait.***

La carte passe de 78px à **120px minimum** : nom du championnat à 20px, effectif et saison en dessous, **rang du membre en 48px** à droite avec « classement » sous lui, et une **jauge de 4px** en bas disant où il en est par rapport au leader.

**Le chiffre affiché est désormais le vrai rang**, et non plus la position de la carte dans la liste. C'est le point que la version `0.12.0` laissait explicitement ouvert : le rang existait depuis l'étape 7, mais `GET /championnats/{id}/classement` n'agrège qu'un championnat à la fois — l'afficher aurait coûté **un appel Railway par carte**, en série, sur le premier écran de l'app.

*La réponse, et pourquoi elle ne demande aucune migration.* `GET /championnats/moi` porte un objet `position` par championnat (`mon_rang`, `mes_points`, `points_leader`), obtenu en appelant `classement_du_championnat` **une fois par championnat, en parallèle** (`asyncio.gather`). Une fonction SQL nouvelle aurait fait le même travail au prix d'un passage par le SQL Editor, sur une liste de migrations dont le CLAUDE.md dit déjà qu'elle est à revérifier.

C'est aussi **la fonction même** que sert `GET /championnats/{id}/classement` : le rang lu sur une carte et celui lu sur l'écran du championnat ne peuvent donc pas diverger, et les quatre critères de départage de la règle 4.6 s'appliquent ici sans être réécrits. Les reprogrammer en Python aurait créé un second classement à tenir d'accord avec le premier.

Quatre points de mise en œuvre :

1. **`points_leader` est le plus haut total du championnat, pas celui de la première ligne.** Les deux coïncident aujourd'hui, la fonction SQL triant d'abord par points ; dériver la jauge d'une hypothèse d'ordre la ferait mentir le jour où le tri changerait. Un contrôle sert volontairement un classement dans le désordre pour le vérifier.
2. **L'échec d'un classement n'emporte ni les autres ni la liste.** Une carte sans rang reste une carte utile ; une liste vide serait un cul-de-sac. Même arbitrage que pour le prochain Grand Prix depuis l'étape 10, et les pannes partent dans les logs Railway avec leur cause.
3. **`LIMITE_CLASSEMENTS = 12`.** La règle 4.5 ne borne pas le nombre d'adhésions : au-delà de douze championnats, les cartes suivantes s'affichent **sans** rang plutôt que d'allonger indéfiniment la route la plus sollicitée de l'application. L'ordre venant de `mes_championnats`, ce sont toujours les mêmes qui le portent d'un chargement à l'autre.
4. **`position` a une valeur par défaut** dans le modèle `Championnat`. La création et l'adhésion rendent un championnat qu'on vient tout juste de rejoindre, où le classement n'a rien à dire, et un frontend déployé avant le backend n'y perd rien — le piège déjà rencontré avec `cree_par` à la version `0.4.1`.

**Le rang n'est rendu que s'il est connu.** Un tiret sous le mot « classement » ne dirait rien de plus qu'une colonne absente, et laisserait croire à une donnée manquante là où c'est le réveil de Railway qui n'a pas encore répondu.

*Écart assumé, et c'est le seul de la refonte.* La demande décrit le rang « semi-transparent à 30 % ». **À 30 %, le blanc sur le bordeaux `#800111` tombe à 1,6:1 de contraste** : le rang deviendrait un ornement illisible, alors que c'est la deuxième chose qu'on vient lire sur la carte. `tonalites` sert donc une encre à **80 %**, et cette valeur est mesurée, pas choisie à l'œil. L'aplat qui contraint est le **terracotta `#C4622D`**, le plus clair des cinq à encre blanche : l'encre pleine n'y vaut déjà que 4,1:1, et 80 % la ramènent à **3,20:1**, juste au-dessus du plancher AA des grands textes ; **à 75 % elle tombe à 2,99:1**, sous le seuil. Les cinq autres aplats sont plus confortables (3,77:1 sur le vert sauge, 7,20:1 sur le bordeaux). Le chiffre reste nettement en retrait de l'encre pleine, ce que la demande cherchait, sans cesser d'être lisible.

*La jauge.* Piste blanche à 30 %, remplissage blanc plein — ou l'encre foncée sur l'amber, `tonalites` portant les deux couches pour la même raison que les encres : un écran qui écrirait `bg-white` de mémoire donnerait une jauge invisible sur l'ambre. **Elle est vide avant le premier Grand Prix**, quand tout le monde est encore à zéro : c'est exact, et bien plus honnête qu'une barre à moitié pleine posée là pour faire joli. La division n'a alors jamais lieu.

*Le code d'invitation quitte la carte* au profit de la saison, comme la demande le prescrit. Il reste sur l'écran du championnat, où l'on va quand on veut le partager.

---

***Correction 3 — les deux actions entrent dans le flux.***

« Créer » et « Rejoindre » quittent la grille à deux colonnes collée au bas de l'écran pour devenir **deux cartes de la liste** : surface blanche, même hauteur et même rayon que les cartes de championnat, pastille d'icône à gauche, titre, sous-titre, chevron. La liste se lit alors d'un seul mouvement du pouce, du dernier championnat aux deux façons d'en avoir un de plus, au lieu de sauter par-dessus un blanc de plusieurs centimètres.

*Écart assumé sur la pastille d'icône.* La demande décrit « une icône `+` en rouge dans un cercle rouge » et « une icône de lien en amber ». Une icône ambre sur une pastille ambre pâle tombe à **2,2:1** de contraste sur une carte blanche, sous le plancher de 3:1 exigé d'un élément graphique porteur de sens. La pastille prend donc l'aplat plein et l'icône l'encre que `encreSurAplat` calcule pour lui — blanche sur le bordeaux, foncée sur l'ambre. C'est le même arbitrage, et le même seuil, que celui déjà tranché pour les blocs de bonus à la version `0.12.0`.

`IconeLien` est ajoutée à `composants/Icones.jsx` : rejoindre, c'est entrer un code reçu d'ailleurs, et le maillon dit ce lien là où le `+` dit la création. Les deux doivent se distinguer d'un coup d'œil au pouce, posées l'une sous l'autre.

**`Action` disparaît**, et avec elle sa dernière utilisation : l'état vide du calendrier global (étape 10) montre désormais les mêmes deux cartes. Cet écran pose exactement la même question — « tu n'as aucun championnat, voici comment en avoir un » — et deux réponses dessinées séparément auraient divergé au premier ajustement. `ActionsChampionnat` les sert d'un bloc aux **trois** écrans : aucun n'a à se souvenir des libellés.

---

***Correction 4 — le bandeau de saison.***

Sous une liste d'un ou deux championnats, le bas de l'écran restait vide sur toute sa moitié. « Saison 2026 · 8 Grands Prix restants » le ferme, en gris clair, centré, **sans aplat ni ombre** : ce n'est pas un bloc, c'est la même graisse et le même gris que la ligne de version, quelques pixels plus haut.

Le décompte est **lu directement dans Supabase, sans jeton** : `grands_prix` est en lecture publique depuis l'étape 4, et ce nombre n'apprend rien que le calendrier de la Formule 1 ne dise déjà. C'est aussi ce qui permet de ne pas réveiller Railway pour trois mots en bas de page. `head: true` ne rapatrie **aucune ligne** — seul l'en-tête de comptage revient.

Le filtre est exactement celui du prochain GP de l'accueil : les statuts non courus, les départs pas encore passés. **Un Grand Prix dont Unibet n'a pas annoncé l'horaire est compté quand même** : il reste un Grand Prix à jouer, et l'écarter le ferait disparaître du décompte jusqu'au samedi des qualifications. C'est l'arbitrage du calendrier de l'étape 9, pas celui des statistiques de l'étape 8.

**Rien ne s'affiche tant que le décompte n'est pas connu**, ni si sa lecture échoue. Un bandeau annonçant « 0 Grand Prix restant » pendant le réveil de la base dirait le contraire de la vérité, sur le seul élément de l'écran dont personne n'attend qu'il se corrige. Zéro Grand Prix se dit « Saison 2026 terminée », jamais « 0 Grand Prix restant ».

---

*Mouvement* — **aucune transition nouvelle, aucun jeton de transitions-dev nouveau.** La jauge se remplit sur la durée et la courbe de *texts reveal* (18), celles-là mêmes qui font entrer le bloc qui la porte : la carte et sa jauge arrivent comme un seul geste, au lieu de deux mouvements de rythmes différents sur la même surface. Deux points : c'est un `transform: scaleX` et jamais une `width` — seules les propriétés composables s'animent (`/apple-design` §11) ; et la valeur de repos vit sur la règle de base, l'animation ne fait que la rejoindre depuis zéro, si bien que sous `prefers-reduced-motion` la jauge reste à sa bonne longueur. L'information demeure, seul le mouvement disparaît.

*Apport d'`/apple-design`* — le retour tactile des grandes surfaces (`pressable-large`, 1,5 %) passe des cartes de championnat aux cartes d'action, qui font désormais la même taille ; les deux chiffres et la jauge sont `aria-hidden` ou lus une seule fois, un lecteur d'écran n'ayant rien à annoncer d'un effet de profondeur ; le squelette suit la carte à 120px, sans quoi l'écran sauterait de 42px par carte à l'arrivée des données ; et le grain respecte `prefers-contrast: more`.

*Vérifié* :

| Contrôle | Résultat |
|---|---|
| Route contre une doublure Supabase (auth + PostgREST en mémoire) | **50 contrôles passent** |
| Protection | `401` sans jeton, sur jeton inconnu et sur en-tête sans `Bearer` ; **aucune lecture pour un appel refusé** |
| Contenu | les trois champs de `position` portés jusqu'au client ; nom, code, effectif, `est_createur` et prochain GP de l'étape 10 intacts ; **un classement demandé par championnat, sur les bons identifiants**, une seule lecture de `grands_prix` pour toute la liste |
| Leader | **classement servi dans le désordre → le leader reste le plus haut total**, pas la première ligne |
| Cas limites | saison non commencée : rang servi, 0 point, leader à 0 ; **appelant absent du classement → aucune position inventée** ; classement vide → position nulle |
| Robustesse | un classement en panne : **liste servie, ce championnat perd son rang, l'autre garde le sien** ; tous en panne : liste servie sans position ; `grands_prix` en panne : rang quand même servi ; **rien de technique dans la réponse** (`42P01` reste dans les logs) |
| Plafond | 20 championnats → **12 classements demandés**, les 20 cartes servies, les 8 dernières sans rang |
| Non-régression | championnat orphelin (`0.4.1`) toujours sérialisé et **portant son rang** ; création `201` **sans position et sans classement demandé** ; `/health` en `0.14.0`, 19 chemins, classement et calendrier toujours protégés, préflight CORS |
| Rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage doublé) | **102 contrôles passent** |
| Contraste, calculé sur les six aplats | l'encre à 80 % tient **≥ 3:1 sur les six**, terracotta compris ; jauge déclarée pour chacun ; **amber servi en encre foncée**, bordeaux en blanc ; le fantôme décoratif à 40 % reste distinct du chiffre lisible |
| Carte de championnat | 120px, aplat conservé, **aucune surface blanche**, élévation et lumière spéculaire ; nom à 20px, effectif accordé, saison ; rang à 48px en encre 80 % ; jauge à la bonne fraction ; **le code d'invitation a quitté la carte** ; destination et retour tactile |
| Jauge | saison non commencée → **vide** ; leader → pleine ; points aberrants → **bornée à 1** ; rang inconnu → aucune colonne, **aucun tiret inventé**, carte entière quand même |
| Cartes d'action | les deux titres et sous-titres demandés, fond blanc, **même hauteur et même rayon que les cartes de championnat**, pastille rouge et pastille amber, **encre foncée sur l'amber**, chevron, élévation, retour tactile |
| Bandeau de saison | décompte servi, **singulier et pluriel accordés**, zéro → « Saison 2026 terminée » et **jamais « 0 Grand Prix »**, décompte inconnu → **rien du tout**, ni aplat ni ombre |
| Écrans | accueil, liste et calendrier global se rendent ; les deux rangs et les deux jauges ; **plus aucun bouton court « Créer » / « Rejoindre »** ; bandeau présent sur les deux écrans ; liste vide → message et les deux cartes ; calendrier global → cartes seulement dans l'état vide |
| Vocabulaire et règle 4.1 | **aucune cote brute « ×N »**, ni « ligue », ni « historique », sur les trois écrans |
| Squelette | à la hauteur réelle de la carte (120px), aucune couleur en dur, balayage conservé |
| Sous un vrai `uvicorn`, Supabase pointé sur un port mort | `/health` en `0.14.0`, 19 chemins, `401` sans jeton, **réponse en français et trace complète sur la sortie standard** |
| `npm run build` | passe, 128 modules ; grain, jauge et les quatre opacités nouvelles bien générés dans le CSS |

---

**Bandeau « Grands Prix restants » — lisibilité et décompte figé** (version `0.14.1`)

Deux corrections sur le bandeau de bas d'écran introduit en version `0.14.0`, partagé par l'accueil et l'onglet Championnats (`BlocSaison`, exporté depuis `Accueil.jsx`). **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1` et `0.12.x`).

*Lisibilité* — le bandeau reprenait le gris `texte-doux` et la graisse 400 de la ligne de version. Posé sur le beige `#F5F0EB`, `#999999` tombe à **2,0:1** de contraste : c'était lisible à côté d'un numéro de version, que personne ne lit, pas pour une phrase qu'on vient lire. Il passe au **marron `secondaire` `#543925`** — couleur du design system, section 5 — en graisse 500, ce qui le porte à **9,4:1**. La taille reste à 13px, valeur qu'il avait déjà. Toujours aucun aplat ni ombre : ce n'est pas un bloc.

*Décompte* — il comptait les lignes de `public.grands_prix`, et c'était le mauvais dénombrement. **Unibet n'expose jamais que le Grand Prix suivant** (section 3.1) : la table ne contient que ce que le scraper a rencontré, soit **un seul GP à ce jour**. Le bandeau annonçait donc « 1 Grand Prix restant » au milieu d'une saison qui en compte douze — l'exact contraire de ce qu'il devait dire, sur la seule ligne de l'écran dont personne n'attend qu'elle se corrige.

La constante `GP_RESTANTS = 12` la remplace (des Pays-Bas à Abu Dhabi), avec un `TODO` à ses deux points d'usage. **`chargerGrandsPrixRestants` reste en place** dans `lib/pronostics.js`, comme le code OAuth depuis la version `0.2.2` et `Onglets.jsx` depuis la `0.12.0` : la lecture est déjà écrite et vérifiée, et elle redevient la bonne réponse le jour où le calendrier complet est en base — il n'y aura qu'à la rebrancher, avec le repli « rien tant que le décompte est inconnu » qu'elle servait.

**Conséquence assumée : le bandeau ne se vide plus de lui-même.** Il affichera « 12 Grands Prix restants » jusqu'à ce que la constante bouge, y compris après le GP des Pays-Bas. C'est le prix d'un nombre juste aujourd'hui contre un nombre faux ; les branches singulier / pluriel et « Saison 2026 terminée » sont conservées telles quelles, pour que le rebranchement n'ait rien à réécrire.

*Vérifié* : `npm run build` passe, 128 modules ; la constante est bien inlinée à 12 dans le bundle, l'utilitaire `text-secondaire` est généré, et la version `0.14.1` est présente.

---

**Tracés de circuits et drapeaux des pays hôtes sur le bloc GP** (version `0.15.0`)

Le bloc « Prochain GP » de l'accueil portait un aplat rouge `#800111` et un ovale décoratif, identiques du premier au dernier Grand Prix de la saison. Il porte désormais **le vrai tracé du circuit** et **les couleurs du drapeau du pays hôte** : c'est la seule chose de l'écran d'entrée qui change d'un week-end à l'autre, et elle se reconnaît avant d'avoir lu le nom. Deux composants nouveaux, un utilitaire CSS, une fonction exportée. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x` et `0.14.1`).

---

***Les douze tracés — `assets/traces.svg` découpé en composant.***

`frontend/src/composants/TracesCircuits.jsx`. La planche empile les douze circuits de la fin de saison, de Zandvoort à Yas Marina, dans un seul système de coordonnées de 669 × 5107 unités. Chacun est extrait **tel quel** : les données de chemin sont identiques au fichier d'origine, **aucune coordonnée n'est réécrite**. Le fichier a été découpé par un script, pas à la main — une transcription manuelle de douze chemins de 2 Ko chacun aurait introduit des fautes invisibles à la lecture.

Quatre points de mise en œuvre à ne pas défaire :

1. **Ce sont des traits, pas des silhouettes.** La planche les dessine en `fill: none` avec un contour de 2px : ils se rendent en `stroke`, jamais en `fill`, qui refermerait chaque circuit en tache noire. C'est la différence avec `composants/TraceCircuit.jsx` (planche `gp-cards.svg`), dont les deux tracés sont, eux, de vraies silhouettes pleines. **Les deux modules coexistent** et ne se remplacent pas : l'ancien sert les vignettes de 20 × 32px des deux calendriers, le nouveau le filigrane pleine hauteur du bloc de l'accueil.
2. **Les `viewBox` sont les boîtes englobantes réelles**, mesurées en échantillonnant les courbes de Bézier (même méthode qu'à l'étape 9), élargies de 4 unités pour que le trait ne soit pas rogné par sa propre demi-épaisseur. Un cadrage arrondi à la main aurait décentré les circuits les plus étirés : **Bakou fait 3,4 fois plus large que haut, Zandvoort à peine 1,1**.
3. **`vector-effect="non-scaling-stroke"`** — l'épaisseur du trait est en pixels d'écran, pas en unités du dessin. Avec une épaisseur exprimée en unités, le même trait sortirait deux fois plus épais sur Zandvoort que sur Bakou, les deux cadrages n'ayant pas du tout la même échelle.
4. **Le rapport de forme est porté par le `<svg>` lui-même** (`aspect-ratio`), à la valeur du cadrage. C'est ce qui permet à l'écran de ne fixer **qu'une** dimension et de laisser l'autre suivre : une boîte aux proportions arbitraires laisserait `meet` centrer le dessin dans du vide, et le filigrane changerait de taille d'un circuit à l'autre sans raison visible.

**Un circuit dessiné en plusieurs traits garde ses sous-tracés dans un seul `d`.** Sakhir en compte quatre, dont la voie des stands. Sans remplissage, un `d` qui enchaîne plusieurs `M` se rend exactement comme autant de `<path>` séparés — ce qui permet à la table de tenir la forme demandée (un chemin par circuit) sans rien perdre du dessin.

*`slugCircuit(nomGp)`* fait le rapprochement : minuscules, accents ramenés à la lettre de base, préfixe « GP » retiré **en tête seulement** (un « GP » au milieu d'un libellé n'est pas un préfixe), tout le reste en tirets. « GP Azerbaïdjan » → `azerbaidjan`, « GP États-Unis » → `etats-unis`.

**Une table d'alias complète la normalisation, et ce n'est pas une précaution en l'air.** Unibet écrit « GP Pays Bas » cette semaine et « GP Pays-Bas » la suivante — c'est déjà la raison pour laquelle `grands_prix` se rapproche par `id_unibet` et non par le nom (étape 4). Rien ne garantit non plus qu'un Grand Prix soit nommé par son pays : « GP Abou Dabi », « GP Émirats arabes unis » et « GP Yas Marina » désignent le même circuit, et la normalisation seule n'en retrouverait aucun. Les alias couvrent les orthographes et les noms de circuit ; le slug direct reste essayé d'abord.

**Un tracé absent est un cas normal, pas une panne** : la planche ne couvre que la fin de saison, et le composant ne rend **rien du tout** plutôt qu'un motif de repli — celui-ci laisserait croire que ce Grand Prix se court sur cette forme-là. C'est exactement ce que la demande prescrivait.

---

***Les drapeaux — CSS pur, et un voile calculé.***

`frontend/src/composants/DrapeauxGP.jsx`. Douze drapeaux, trois formes : `horizontal` (bandes horizontales, le dégradé descend), `vertical` (bandes verticales, il va vers la droite) et `complexe` — un drapeau qu'on ne reproduit pas honnêtement en CSS (étoiles, sphère céleste, quadrillage) devient un **aplat uni de sa couleur dominante**. Mieux vaut une couleur juste qu'un drapeau approximatif.

**Périmètre, identique à celui de `lib/palette.js` et de `lib/couleurs.js`** : ces couleurs ne peignent que l'aplat de ce bloc. Jamais un fond d'écran, jamais un texte, jamais une bordure. Les sept couleurs de la section 5 gardent donc tous leurs rôles, et le bordeaux de la marque reste le repli. Un contrôle du jeu de tests vérifie qu'**aucune couleur de drapeau ne vit ailleurs que dans ce fichier**.

**Aucune image, aucune requête** : tout est en `linear-gradient`. Un drapeau en image demanderait un fichier par pays, à charger avant que le premier écran de l'app puisse s'afficher.

Deux points de mise en œuvre :
- **Les bandes sont écrites en paires de bornes** (`#A 0%, #A 33.33%, #B 33.33%`) et non avec la syntaxe à double position (`#A 0% 33.33%`). Les deux disent la même chose, la première est comprise partout, et cette app vise Safari iOS.
- **`parts` porte les ratios inégaux** — Espagne 1/2/1, Bahreïn 1/4, Qatar 3/1. Sans ce champ il faudrait les décrire en répétant des bandes, ce qui ne dirait pas la même chose.

---

***Le voile, et pourquoi `0,30` ne pouvait pas suffire.*** C'est le point de la version.

Le texte du bloc reste **blanc dans tous les cas**, comme demandé : c'est aussi la seule façon de garder un bloc reconnaissable d'un Grand Prix à l'autre. Mais **sept des douze drapeaux portent une bande blanche**, sur laquelle du texte blanc ne se voit pas du tout. D'où le voile noir.

La demande annonçait `rgba(0, 0, 0, 0.3)`. **Mesuré, 0,30 ne suffit pas** : un noir à 30 % sur une bande blanche la ramène à `#B2B2B2`, où le blanc plein ne vaut que **2,11:1** — sous le plancher AA des grands textes. Il faut **0,42** pour atteindre 3:1, et un cran de plus en tenant compte de la lumière spéculaire posée par-dessus. L'opacité est donc **dérivée de la bande la plus claire de chaque drapeau**, par pas de 0,05, exactement comme `encreSurAplat` dérive l'encre d'un aplat depuis la version `0.12.0`. Un drapeau ajouté demain reçoit le bon voile sans que personne n'ait à refaire le calcul.

| Drapeaux | Voile | Blanc plein |
|---|---|---|
| Pays-Bas, Italie, Bahreïn, Singapour, Mexique, Qatar | 0,45 | 3,36:1 |
| Espagne | 0,30 | 3,11:1 |
| Azerbaïdjan | 0,15 | 3,17:1 |
| Brésil | 0,05 | 3,00:1 |
| États-Unis, Las Vegas, Abu Dhabi, **repli bordeaux** | aucun | 3,86 à 11,73:1 |

**Quatre conséquences à ne pas défaire :**

1. **Le voile est le calque le plus haut du bloc, sous le seul contenu.** Tout ce qui éclaircit la surface — le tracé du circuit, la lumière spéculaire — passe **dessous**. C'est ce qui rend la garantie inconditionnelle : si le tracé était posé par-dessus, ses 15 % de blanc ramèneraient une bande voilée de `#8C8C8C` à `#9D9D9D`, où le blanc **retombe à 2,71:1**, précisément là où le texte le croise. Le jeu de tests affiche cette valeur pour chaque drapeau, pour que l'ordre des calques reste une décision visible.
2. **Les cinq fonds assez sombres ne reçoivent aucun voile.** Voiler une couleur qui tient déjà le seuil ne ferait que l'éteindre. Le repli bordeaux passe par **le même calcul** que les drapeaux plutôt que d'être décrété conforme : il ressort sans voile et avec ses surfaces blanches, donc le bloc « aucun Grand Prix » et la silhouette de chargement gardent **exactement** l'aspect qu'ils avaient.
3. **Sur un drapeau voilé, l'encre secondaire passe au blanc plein et à la graisse 500** au lieu des 70 % habituels. Ce n'est pas un choix esthétique : une fois la bande la plus claire ramenée au gris moyen, **aucune opacité intermédiaire n'atteint 3:1** — seul le blanc plein y arrive. C'est la règle de vibrance d'`/apple-design` §12, qui demande sur un fond changeant un texte plus contrasté et légèrement plus gras plutôt qu'un gris translucide. La hiérarchie passe donc par la taille et la graisse, pas par l'opacité.
4. **Les surfaces posées dans le bloc suivent la même règle que l'encre.** La pastille « Prochain GP » et les deux cases de statut étaient des voiles **blancs** ; elles vivent dans le contenu, donc au-dessus du voile, et un blanc translucide y annulerait localement ce que le voile venait de gagner — une case `bg-white/12` sur une bande blanche voilée **redescend à 2,81:1**. Sur un drapeau voilé elles passent au noir translucide, qui va dans le même sens que le voile ; sur les fonds sombres et sur le repli elles restent blanches.

L'écran ne choisit donc **jamais** `text-white/70` ni `bg-white/12` lui-même : il lit l'objet que sert `drapeauDuGp`, exactement comme `tonalites()` le garantit pour les aplats depuis la version `0.12.0`.

*L'ombre portée du titre, et pourquoi elle est conditionnelle.* Le nom du Grand Prix occupe toute la largeur du bloc : il **traverse** une frontière de bandes, et une lettre posée pile sur la couture perd son contour d'un côté ou de l'autre. C'est exactement la situation que la vue piste résout déjà de la même manière depuis l'étape 7 — sa légende passe tantôt sur l'asphalte, tantôt sur une bordure blanche. **Un aplat uni n'a pas de couture, donc pas d'ombre** : le bloc bordeaux garde son texte parfaitement net.

*`.voile-drapeau` dans `index.css`* porte son opacité en variable CSS (`--voile`) et jamais en dur : une valeur écrite dans la feuille voilerait tous les drapeaux de la même quantité, donc trop les uns et pas assez les autres. Sous **`prefers-contrast: more`** le voile s'approfondit d'un cran — pendant exact du grain de fond, qui disparaît sous ce même réglage (`/apple-design` §14) — et `clamp` borne le résultat, un voile opaque effaçant le drapeau.

*Deux orientations suivent la demande plutôt que le drapeau réel*, et c'est signalé pour que ce soit une décision et non un oubli : le **Qatar** est décrit en bandes **horizontales** bordeaux/blanc, alors que le vrai drapeau porte sa bande blanche à la hampe, donc verticalement. Bahreïn, lui, est bien vertical. Les deux se corrigent en changeant le seul champ `type` de la table.

*Conséquence visuelle assumée* — sur les sept drapeaux à bande blanche, cette bande se lit **gris argent** et non blanc. C'est inhérent au couple « texte blanc partout » + « bande blanche » : la seule autre issue serait de l'encre foncée sur ces bandes-là, ce que la demande exclut explicitement. Les drapeaux restent reconnaissables ; Bahreïn (1/4) et Singapour (1/1) sont les deux où la bande grise pèse le plus.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau**, et c'est un choix. Le fond d'un Grand Prix ne change pas sous les yeux du joueur : il n'y a aucun changement d'état à accompagner, et le skill Transitions.dev n'a pas de correspondance pour une surface statique. Le bloc conserve celles qu'il portait — *texts reveal* (18) pour son entrée, *text states swap* (04) pour le compte à rebours et le libellé du bouton.

*Apport d'`/apple-design`* — la vibrance du §12 sur fond changeant (point 3 ci-dessus) est l'apport principal ; s'y ajoutent le tracé et le voile posés `aria-hidden` et `pointer-events-none`, un lecteur d'écran n'ayant rien à annoncer d'un effet de profondeur, et le repli `prefers-contrast: more`. Les trois destinations du bouton, son libellé et sa zone tactile de 44px sont inchangés (versions `0.5.1` et `0.9.0`).

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage pré-rempli) : **167 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Tracés | douze tracés, **les douze slugs demandés dans l'ordre**, deux à deux distincts ; `viewBox` à quatre nombres et ratio concordant ; **aucune commande de chemin non gérée** ; Sakhir réunit bien ses quatre sous-tracés, les onze autres n'en ont qu'un |
| `slugCircuit` | les douze noms de pays résolus, accents et casse compris ; « GP Pays Bas » **comme** « GP Pays-Bas » ; huit alias résolus (Abou Dabi, Émirats, Monza, Zandvoort, Bakou, Sao Paulo, Lusail, Austin) ; **un GP hors planche ne tombe sur aucun tracé** ; nom vide sans plantage ; **un « GP » au milieu d'un libellé n'est pas retiré** |
| Composant | trait et non aplat (`fill="none"`, `stroke="currentColor"`, `non-scaling-stroke`), décoratif ; **rapport de forme porté par le `<svg>`** ; **circuit absent → rien du tout** ; les douze se rendent sans lever |
| Drapeaux | douze entrées, une par tracé ; types attendus ; **les couleurs exactes de la demande, hexadécimal par hexadécimal** ; les trois ratios inégaux ; toutes au format `#RRGGBB` |
| CSS pur | **aucune `url()`, aucun `http`** ; bandes horizontales → `to bottom`, verticales → `to right` ; bandes franches à deux bornes par couleur ; Espagne 25→75 %, Bahreïn 0→20 %, Qatar 0→75 %, Singapour 50 % ; dernière borne à 100 % ; `complexe` → aplat uni sans dégradé |
| **Contraste, mesuré sur les treize fonds** | **blanc plein ≥ 3:1 partout** ; l'encre secondaire annoncée tient le seuil ; **le blanc posé dans la pastille et dans les deux cases tient le seuil** ; `0,30` prouvé insuffisant sur une bande blanche ; aucun voile sur les fonds sombres, ≥ 0,42 sur les sept bandes blanches ; **aucun voile n'atteint l'opacité** |
| Ordre des calques | pour chaque drapeau voilé, le jeu de tests affiche ce que **vaudrait** le contraste si le tracé passait au-dessus du voile (2,52 à 2,71:1) — la démonstration que l'ordre n'est pas indifférent |
| Ombre portée | présente sur les drapeaux à bandes, **absente sur les aplats unis et sur le repli** |
| Bloc de l'accueil | le drapeau peint le bloc et **l'aplat rouge disparaît** ; voile rendu à la bonne opacité ; tracé de Zandvoort rendu, à 15 % de blanc, débordant par la droite ; surfaces sombres et encre secondaire en blanc plein sur drapeau voilé ; lumière spéculaire, élévation, nom, cases de statut et bouton conservés |
| Repli | **pays hors table → aplat `bg-primaire`, aucun tracé, aucun voile, aucune ombre**, `text-white/70` et `bg-white/12` — le bloc d'avant, à l'identique ; drapeau `complexe` → aplat uni et surfaces claires conservées ; GP sans horaire → drapeau quand même et « Date à confirmer », **aucune date inventée** |
| Cloisonnement | **les couleurs de drapeau ne vivent que dans `DrapeauxGP.jsx`** |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique », sur les trois cas |
| CSS | `.voile-drapeau` déclarée, opacité lue en variable, repli `prefers-contrast: more` présent et **borné** |
| Aperçu rendu avec la feuille compilée | les treize cas dessinés à 390px de large : les douze drapeaux reconnaissables, les douze tracés lisibles en filigrane, aucun texte perdu sur une couture |
| `npm run build` | passe, **130 modules**, version `0.15.0` et ombre portée présentes dans le bundle |

---

**Bloc GP recomposé, tracé de circuit en premier plan** (version `0.16.0`)

Le tracé du circuit cesse d'être un filigrane à 15 % posé derrière le texte : il devient une **bande réservée de 160px, pleine largeur du bloc**, en trait blanc à 60 %. Le bloc du prochain Grand Prix passe d'une composition en trois étages à cinq zones verticales. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1` et `0.15.0`).

*Les cinq zones*, de haut en bas : en-tête (pastille « Prochain GP » à gauche, date à droite), nom du Grand Prix centré, bande du tracé, les deux cases de statut, le bouton. Les zones 1, 4 et 5 sont **inchangées** — mêmes libellés, mêmes trois destinations, même zone tactile de 44px (versions `0.5.1` et `0.9.0`). Le drapeau du pays hôte continue de peindre tout le bloc, bandes de couleur comprises, derrière la composition entière.

---

***Le tracé est passé au-dessus du voile, et ce n'est pas un contournement de la garantie de contraste — c'est sa conséquence.*** C'est le point de la version.

La version `0.15.0` avait posé une règle explicite : le voile noir est le calque le plus haut du bloc, sous le seul contenu, et **tout ce qui éclaircit la surface passe dessous**. Elle documentait précisément le dégât évité — si le tracé passait par-dessus, ses 15 % de blanc ramèneraient une bande voilée de `#8C8C8C` à `#9D9D9D`, où le blanc du texte **retombe à 2,71:1**, sous le plancher AA des grands textes.

Ce risque n'a plus de support. Le tracé occupe désormais **sa propre bande** : il ne croise plus aucun texte, ni le nom du Grand Prix au-dessus, ni les cases de statut en dessous. Le voile continue de peindre la bande du tracé, et c'est précisément ce qui rend le trait blanc lisible sur les drapeaux clairs. **La garantie de 3:1 sur le texte est intacte et vérifiée sur les treize fonds** ; ce qui a changé, c'est qu'elle n'a plus à protéger une zone que le tracé traverse.

*Le fond assombri de la bande, et ce qu'il vaut.* Les 15 % de noir demandés sont appliqués tels quels, et ils font un vrai travail — mesuré sur les treize fonds :

| Fond | Voile | Trait blanc à 60 % |
|---|---|---|
| Las Vegas | aucun | 5,81:1 |
| Repli bordeaux | aucun | 4,09:1 |
| États-Unis | aucun | 3,11:1 |
| Abu Dhabi | aucun | 2,91:1 |
| Pays-Bas, Italie, Bahreïn, Singapour, Mexique, Qatar | 0,45 | 2,70:1 |
| Espagne | 0,30 | 2,55:1 |
| Azerbaïdjan | 0,15 | 2,54:1 |
| **Brésil** | 0,05 | **2,44:1** |

**Contrairement à la version `0.15.0`, le chiffre demandé n'est pas relevé, et la différence de traitement est délibérée.** Là, `0,30` était refusé parce qu'il laissait du **texte** à 2,11:1, sous un plancher d'accessibilité qui ne se négocie pas. Ici il s'agit d'un élément **illustratif** — le nom du Grand Prix porte le sens, le circuit l'accompagne — et les 15 % atteignent l'objectif visé : le trait passe d'environ 1,1:1 en filigrane à 2,44:1 au minimum, soit **deux fois plus de séparation qu'avant** sur le pire fond. Mesurer avant d'accepter, et non seulement avant de refuser, c'est ce qui permet de dire lequel des deux cas s'applique.

**Le repli `prefers-contrast: more` aide le tracé sans qu'une ligne ait été ajoutée.** Le voile s'y approfondit d'un cran (règle de la version `0.15.0`) et il est peint **sous** la bande : le substrat devient plus sombre, donc le trait blanc s'en détache davantage. Vérifié : Pays-Bas passe de 2,70 à 3,80:1.

*Trois points de mise en œuvre à ne pas défaire :*

1. **`boiteLibre` coupe le rapport de forme que `TracesCircuits.jsx` posait en ligne.** Ce ratio existait pour que l'appelant ne fixe **qu'une** dimension et laisse l'autre suivre — c'est ce que veut un filigrane. Ici la bande fixe les **deux** (pleine largeur × 160px), et `xMidYMid meet` fait alors le travail pour lequel il est là : mettre chaque circuit à l'échelle dans cette boîte et le centrer. Bakou, 3,4 fois plus large que haut, remplit la largeur ; Zandvoort, presque carré, remplit la hauteur. **Chacun garde sa vraie forme** au lieu d'être étiré pour occuper la même surface que son voisin. Le style en ligne devait sauter : il l'emporte sur toute classe utilitaire, donc la hauteur demandée aurait été ignorée en silence.
2. **`aUnTrace(slug)` est exporté, et la bande entière est conditionnée à lui.** Le composant savait déjà ne rien rendre faute de circuit, ce qui suffisait à un filigrane. Ça ne suffit plus à une bande réservée : un Grand Prix hors planche — tout le début de saison — laisserait **160px de fond assombri vide** au milieu du bloc. Un prédicat exporté plutôt qu'un `Object.hasOwn(TRACES, slug)` chez l'appelant : la façon de stocker les tracés reste l'affaire de ce module.
3. **`HAUTEUR_TRACE` est écrite une fois et partagée avec le squelette.** Sans cela l'accueil sursauterait de 160px à l'arrivée des données, sur le premier écran de l'app — exactement le défaut corrigé sur les cartes de championnat en version `0.14.0`, où la silhouette a dû suivre la carte à 120px. La silhouette du nom est centrée pour la même raison, à l'horizontale.

*Le nom du Grand Prix* passe de `text-titre-lg` (30px, aligné à gauche) à **26px centré**, au-dessus de son circuit : les deux se lisent alors comme un seul objet, titre et illustration, ce qu'un nom aligné à gauche au-dessus d'un dessin centré ne donnerait pas. **26px est la taille demandée et n'a pas de jeton** : l'échelle de la section 5 passe de 15px (corps) à 28px (titre de page), et celui-ci n'est pas un titre de page — l'écran en a déjà un, porté par l'en-tête rétractable. Le crénage négatif est celui qu'`/apple-design` §15 impose au-delà de 24px. L'ombre portée conditionnelle de la version `0.15.0` est conservée : le nom traverse toujours la couture des bandes du drapeau.

*Ce qui n'a **pas** été ajouté, et pourquoi.* Le tracé devenu central appelait un **stroke-draw** — le circuit se dessinant comme un tour bouclé, mécanisme disponible dans *success check* (transitions-dev 10). Il est écarté pour deux raisons, dans cet ordre :

1. **C'est l'écran d'entrée d'une app qu'on ouvre vingt fois par week-end.** Un circuit qui se redessine à chaque lancement est joli une fois et pesant ensuite. C'est le raisonnement qui avait déjà fixé `DESIGN_VARIANCE` à 6 plutôt qu'à 8 en version `0.13.0`, appliqué ici au mouvement.
2. **Le mécanisme aurait été fragile.** `stroke-dasharray` se calcule en unités du dessin, alors que le composant porte `vector-effect="non-scaling-stroke"` pour que l'épaisseur reste identique d'un cadrage à l'autre — et ce même effet fait interpréter le motif de tirets dans l'espace écran, différemment selon les navigateurs. Le contourner demandait soit de mesurer les douze chemins, soit un `pathLength`, dans les deux cas sans garantie sur Safari iOS, qui est la cible.

Le bloc conserve donc les transitions qu'il portait — *texts reveal* (18) pour son entrée, *text states swap* (04) pour le compte à rebours et le libellé du bouton. **Aucune transition nouvelle, aucun jeton nouveau**, comme aux versions `0.14.0` et `0.15.0` : la bande arrive avec le bloc, en un seul geste.

*Apport d'`/apple-design`* — la bande et son fond sont `aria-hidden` et `pointer-events-none`, un lecteur d'écran n'ayant rien à annoncer d'une illustration ; la silhouette de chargement suit la hauteur réelle du bloc (§7, cohérence spatiale) ; le crénage négatif du nom relève du §15 ; et le bouton garde sa zone tactile de 44px et son retour à l'appui.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage pré-rempli) : **164 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| `aUnTrace` | douze tracés reconnus, GP hors planche et slug vide → `false`, **clé héritée d'`Object` (`toString`) → `false`** |
| **Contraste du trait, mesuré sur les treize fonds** | **2,44:1 au pire (Brésil), 5,81:1 au mieux (Las Vegas)** ; les 15 % de la bande améliorent le trait sur les six drapeaux clairs ; `prefers-contrast: more` l'améliore encore (Pays-Bas 2,70 → 3,80:1) |
| Garantie de la version `0.15.0` | **le texte blanc tient toujours ≥ 3:1 sur les douze drapeaux**, hors de la bande |
| Ordre des calques | lueur, puis voile, puis bande du tracé, puis contenu ; **le tracé n'est plus en position absolue** ; voile rendu à l'opacité calculée du drapeau |
| Les cinq zones | pastille et date ; nom **centré, 26px, graisse 500, crénage négatif** ; bande à 160px assombrie à 15 % et pleine largeur ; deux cases ; bouton à 44px ; **ordre vérifié par position dans le DOM** |
| Bande du tracé | trait et non aplat (`fill="none"`, `stroke="currentColor"`), 60 % de blanc, épaisseur 3px, `non-scaling-stroke` conservé, `xMidYMid meet`, **aucun `aspect-ratio` en ligne**, svg remplissant la bande, décoratif |
| Les douze circuits | chacun rendu avec sa vraie `viewBox`, sa bande et son nom |
| GP hors planche | **ni tracé, ni bande, ni hauteur de 160px** — aucun trou ; bloc, cases et bouton quand même servis ; repli bordeaux sans voile |
| Drapeaux `complexe` | bande et tracé présents, **aucune ombre portée** (aplat uni) |
| Squelette | bande à 160px et assombrie **à l'identique**, silhouette du nom centrée, deux cases, bouton, aucun tracé |
| États | GP couru → « Dernier GP », cases Course/Points, bouton résultats, **tracé conservé** ; pronos saisis → « Voir mes pronos » ; GP sans horaire → « Date à confirmer », **aucune date inventée**, tracé et bande quand même |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique », sur les six cas rendus |
| CSS de production | `bg-black/15`, `text-white/60`, `text-[26px]`, `tracking-[-0.02em]`, `-mx-5`, `mx-auto` générés ; `voile-drapeau`, `lueur-haute` et le repli `prefers-contrast` conservés |
| Aperçu rendu avec la feuille compilée | les treize cas dessinés à 390px de large : **les douze circuits lisibles au premier plan**, chacun à sa vraie forme, aucun texte perdu sur une couture, et le repli Monaco sans bande |
| `npm run build` | passe, 130 modules, version `0.16.0` dans le bundle |

---

**Voile uniforme sur le bloc GP** (version `0.16.1`)

Correction d'un défaut relevé à l'œil sur le bloc du prochain Grand Prix. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0` et `0.16.0`).

*Le défaut* — l'assombrissement de 15 % introduit en version `0.16.0` ne peignait que la **bande du tracé**, 160px au milieu du bloc. Sur un drapeau à bande répétée, il coupait la surface en deux : les Pays-Bas en sont le cas d'école — rouge, blanc, bleu, puis rouge à nouveau — et la bande rouge du haut paraissait **plus vive que celle du bas**, alors que c'est la même couleur. L'œil y lisait un défaut de calage, pas une intention.

*La correction* — les 15 % passent du conteneur de la bande au **conteneur du bloc**. Une seule surcouche uniforme, la zone du tracé n'a plus son propre assombrissement. Le drapeau reste d'une seule pièce et chaque couleur garde exactement la même valeur du haut au bas du bloc.

**Trois points de mise en œuvre à ne pas défaire :**

1. **La surcouche est posée au-dessus du voile et sous le contenu**, à la place exacte qu'occupait celle de la bande. L'ordre des calques reste donc celui que la version `0.15.0` a fixé et documenté — lueur spéculaire, voile du drapeau, assombrissement, contenu — et rien de ce qui éclaircit la surface ne remonte au-dessus du texte.
2. **Elle ne s'applique qu'aux blocs peints par un drapeau.** Le repli bordeaux n'a ni bande ni rupture à corriger, et le CLAUDE.md demande depuis la version `0.15.0` qu'il garde *exactement* l'aspect qu'il avait ; le voiler d'un cran de plus l'éteindrait pour rien. Table des drapeaux et table des tracés portant les mêmes douze slugs, « peint par un drapeau » et « a un tracé » désignent le même ensemble — la condition est donc aussi celle qui existait avant, simplement remontée d'un niveau.
3. **Le squelette suit.** Sa bande de 160px n'est plus assombrie non plus : un rectangle sombre y annoncerait une rupture que la surface d'arrivée n'a pas. Elle garde une silhouette claire (`bg-white/10`), comme les autres formes du squelette, et surtout **sa hauteur** — c'est elle qui empêche l'accueil de sursauter de 160px à l'arrivée des données.

*Ce que la correction fait au contraste, mesuré.* Elle ne peut que l'améliorer : on ajoute du noir sous le texte, jamais du blanc.

- **Le texte** gagne un cran sur tous les drapeaux. Le pire cas passe de **3,36:1 à 4,48:1** (Pays-Bas, Italie, Bahreïn, Singapour, Mexique, Qatar), le meilleur reste à 21:1 (Las Vegas). Le repli bordeaux, non voilé, reste à 10,88:1. Les seuils calculés par `apparence()` — encre secondaire à 70 % ou blanc plein, surfaces claires ou sombres — sont mesurés sur le substrat **sans** cette surcouche : ils sont donc désormais conservateurs, jamais optimistes, et n'avaient pas à être recalculés.
- **Le trait du tracé est inchangé au bit près.** Il voit la même pile qu'avant — drapeau, voile, 15 % de noir — dans le même ordre : les valeurs du tableau de la version `0.16.0` (2,44:1 au pire sur le Brésil, 5,81:1 sur Las Vegas) restent exactes.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Une surcouche fixe n'accompagne aucun changement d'état.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage pré-rempli) : **24 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Surcouche | **une seule occurrence sur tout le bloc**, en `absolute inset-0`, décorative (`aria-hidden`, `pointer-events-none`) |
| Ordre des calques | **lueur → voile → surcouche → contenu**, vérifié par position dans le DOM ; voile du drapeau conservé et rendu à son opacité calculée (0,45 pour les Pays-Bas) |
| Bande du tracé | toujours présente et **sans aucun assombrissement propre** ; 160px conservés ; tracé toujours rendu en trait (`fill="none"`, `stroke="currentColor"`) à 60 % de blanc |
| Repli bordeaux | **aucune surcouche, aucun voile**, aplat `bg-primaire` conservé, aucune bande de 160px — le bloc d'avant, à l'identique |
| Squelette | **aucune surcouche sombre**, bande à 160px conservée, silhouette claire |
| Contraste, calculé sur les treize fonds | blanc plein : pire cas **3,36 → 4,48:1**, aucun fond en recul ; substrat du trait **identique à la version `0.16.0`** |
| Non-régression | nom centré à 26px, les deux cases de statut, bouton et destination, **aucune cote brute « ×N »**, ni « ligue », ni « historique » |
| CSS de production | `bg-black/15` et `bg-white/10` générés |
| `npm run build` | passe, 130 modules, version `0.16.1` dans le bundle |

---

**Refonte de l'écran Récap** (version `0.17.0`)

La maquette 10 recomposée en quatre zones : hero au drapeau du pays hôte, carte de statut colorée, compte à rebours de fermeture, et une carte unique pour tous les pronostics. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0` et `0.16.x`).

*Zone 1 — le hero, et pourquoi il est aussi la barre de navigation.* Il porte le drapeau du pays hôte par le **même chemin exactement** que le bloc du prochain Grand Prix de l'accueil : même clé (`slugCircuit`), même table (`DrapeauxGP`), même voile calculé, et la même surcouche uniforme de 15 % introduite en version `0.16.1`. Le récap et l'accueil parlent alors du même Grand Prix avec les mêmes couleurs, et la reconnaissance se fait avant d'avoir lu le nom.

**Le bouton de retour vit dans le hero**, et non dans un en-tête au-dessus. Un bandeau beige portant « Récap » posé sur un hero qui nomme déjà le Grand Prix aurait donné **deux titres empilés pour un seul écran**, et 150px de chrome avant le premier contenu utile. C'est l'arbitrage déjà tranché pour l'en-tête teinté d'un championnat, à ceci près que la teinte y est une couleur unie que `EnTeteEcran` sait rendre, alors qu'ici c'est un drapeau — d'où un hero écrit sur place. `pleine-largeur` + `coiffe-ecran` laissent la couleur courir jusqu'aux deux bords et derrière la Dynamic Island, sans jamais y pousser de texte.

**Conséquence assumée** : l'en-tête n'est plus collant sur cet écran, le bouton de retour défile donc avec la page. L'écran tient en quatre blocs, le défilement est court, et c'est le prix d'un hero qui porte une image plein cadre. `EnTeteEcran` reste en service sur les quatre écrans qui l'ont ; l'étendre ici demanderait qu'il sache rendre un fond en `style` et non en classe.

Le nom du Grand Prix prend l'échelle des **titres de page** (`text-titre-lg`) et non les 26px du bloc de l'accueil : ici il n'y a pas d'autre titre, c'est lui le titre de l'écran. L'ombre portée conditionnelle de la version `0.15.0` est conservée — il traverse toujours la couture des bandes du drapeau, et un aplat uni n'en reçoit aucune.

---

***Zone 2 — la carte de statut, et l'écart d'encre.*** C'est le seul point où la demande est corrigée, et c'est le même arbitrage qu'en version `0.12.0`.

Elle écrit « texte en blanc » pour les **deux** variantes. Sur le vert sauge `#4A7C59`, le blanc tient **4,72:1** et il est conservé tel quel. Sur l'amber `#E8A020`, il tombe à **2,17:1** — sous le plancher AA des grands textes — quand l'encre `#1A1A1A` monte à 7,72:1. `tonalites()` porte ce seuil une fois pour toutes : **l'écran ne choisit jamais `text-white` lui-même, il lit l'objet**. C'est ce qui empêche une carte amber de recevoir du texte blanc parce qu'un écran l'a écrit de mémoire, et un contrôle du jeu de tests vérifie qu'aucun `text-white` ne suit un `bg-accent`.

Le sous-titre dit **le geste possible**, pas l'état déjà lu dans le titre. Une fois la fermeture passée il n'y a plus de geste : il annonce alors ce qui a changé plutôt que d'inviter à une modification impossible. La célébration « Pronos enregistrés ! » au retour de l'écran de saisie (écart 5 de l'étape 5) est **conservée** : elle ne s'affiche qu'avec `state.enregistre`, et l'arrivée à froid dit bien « Tes pronos sont en place ».

*Zone 3 — le compte à rebours.* Carte blanche, label gris, temps restant en grand chiffre au rouge de la marque (`text-score`, 32px, graisse 500), bouton rouge plein pleine largeur. **Trois états, et ils ne disent pas la même chose** : un décompte quand la fermeture approche ; « Fermés » et **plus aucun bouton** une fois passée, puisqu'il n'y a plus rien à modifier ; et « À confirmer » pour un Grand Prix dont Unibet n'a pas publié l'horaire — qui **reste ouvert**, règle tenue aux trois étages depuis l'étape 5, mais n'a aucune durée à afficher. Écrire « 0s » y serait faux dans les deux sens. Le libellé du bouton suit sa destination, comme partout : « Modifier mes pronos » vers la saisie, « Faire mes pronos » vers le tableau des cotes quand rien n'est encore joué.

*Zone 4 — une seule carte pour tous les pronostics.* Deux sections, un séparateur fin entre elles, et le total en bas.

**Les deux étiquettes « Obligatoire » et « Bonus » qui suivaient chaque ligne sont supprimées** : elles répétaient mot pour mot le titre de la section juste au-dessus. C'est la **pastille de points** qui porte désormais le marché — rouge pour le vainqueur, bleu ardoise pour le podium, amber pour un bonus — et sa couleur est prise à la **même source que les en-têtes du tableau des cotes** (`couleurMarche`). Le rouge du vainqueur est donc exactement celui de sa section là-bas, et les deux ne peuvent pas diverger. La pastille amber reçoit son encre foncée du même `tonalites` que la carte de statut.

Les points affichés restent ceux que le pronostic rapportera **s'il tombe** (règle 4.1) ; une cote retirée par le bookmaker laisse le pronostic visible sans inventer de montant, et sort du total. Le total (« Total si tout tombe ») est conservé de la version précédente et passe en grand chiffre rouge — c'est la question que tout le monde se pose devant un récapitulatif.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** L'écran réutilise celles déjà installées : *texts reveal* (18) pour l'entrée des blocs, *text states swap* (04) pour le décompte (il change toutes les secondes dans la dernière heure, un remplacement de texte nu le ferait clignoter), *skeleton loader and reveal* (14) pour l'attente. Un jeton de plus aurait été un jeton à maintenir sans rien gagner.

*Le squelette suit la nouvelle silhouette.* La carte de statut y garde son aplat vert et n'en grise que le contenu, en blanc translucide — c'est la règle de l'étape 9 sur les aplats de couleur, et le gris des squelettes s'y lirait comme une tache. Les deux cartes blanches, elles, passent par les primitives partagées (`Barre`, `Pave`) : **la couleur des squelettes ne s'écrit toujours qu'à un seul endroit**. Le bouton garde sa hauteur tactile dans la silhouette, sans quoi l'écran sauterait de 44px à l'arrivée des données.

*`IconeAlerte` est ajoutée à `composants/Icones.jsx`*, dans le style des autres (tracé au trait, `currentColor`, décorative). Le point du bas est un segment de longueur nulle rendu par `strokeLinecap="round"` plutôt qu'un `<circle>` de plus, pour que son diamètre suive l'épaisseur du trait. Le skill Taste proscrit les icônes dessinées à la main et recommande une bibliothèque tierce : c'est le point où le CLAUDE.md gagne, `Icones.jsx` étant tiré des maquettes depuis l'étape 2 — même arbitrage qu'en version `0.12.0`.

*Apport d'`/apple-design`* — le hero répond aux quatre questions du wayfinding (§16) : où je suis (le nom du GP en titre), ce qu'est cet écran (le label « Récap »), et comment sortir (un bouton qui **nomme sa destination**, à 44px avec retour à l'appui). **Le hero est rendu même en attente et même en erreur** : une barre de retour qui disparaîtrait pendant le réveil de Supabase enfermerait le joueur. La lumière spéculaire du §12 est posée sur les deux aplats de couleur, tracé et voile restent `aria-hidden`, et l'ombre portée du titre suit la règle de vibrance sur fond changeant.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage pré-rempli) : **86 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Hero | peint par le **dégradé du drapeau** et non par un aplat rouge ; `pleine-largeur` + `coiffe-ecran`, arrondi en bas seulement, `shadow-aplat`, lumière spéculaire ; voile rendu à **l'opacité calculée** du drapeau ; surcouche uniforme de la `0.16.1` présente |
| Contenu du hero | label « Récap » sur la pastille calculée ; nom du GP en `<h1>` à l'échelle des titres et centré ; date et heure de départ dessous en encre secondaire ; **ombre portée présente** (drapeau à bandes) ; sortie nommée « Accueil », 44px et retour à l'appui |
| Statut, pronos en place | carte **verte**, titre et sous-titre demandés, blanc conservé (**4,72:1**), icône de coche |
| Statut, aucun prono | carte **amber**, titre demandé, icône d'alerte ; **le blanc y serait à 2,17:1** donc `tonalites` impose l'encre foncée, et **aucun `text-white` ne suit un `bg-accent`** |
| Compte à rebours | label en petit gris, temps en `text-score` rouge **centré**, échange de texte (transitions-dev 04) ; bouton rouge plein, pleine largeur, 44px ; « Faire mes pronos » quand rien n'est joué |
| GP fermé | label « Pronostics », valeur « Fermés », **aucun bouton de modification**, statut cohérent, pronostics toujours lisibles |
| GP sans horaire | **reste ouvert**, aucune durée fabriquée, « À confirmer » et « Date à confirmer » |
| Pronostics | deux sections titrées, séparateur fin, marché au-dessus du pilote, les quatre choix rendus |
| Pastilles | vainqueur → `#800111`, podium → `#2C4A6E`, bonus → `#E8A020` ; **les mêmes couleurs que les en-têtes du tableau des cotes** ; encre foncée sur l'amber ; points habillés |
| Étiquettes retirées | **plus aucun « Obligatoire »**, et « Bonus » n'apparaît plus qu'en titre de section |
| Total | libellé demandé en petit gris, **792 pts = 280 + 135 + 162 + 215** (podium compté pour ses deux cotes), en grand chiffre rouge |
| Cote retirée | pronostic visible, **aucun montant inventé**, exclu du total |
| États | aucun pronostic → message explicite et **aucun total à zéro** ; hero rendu **même sans donnée en cache** ; GP hors table de drapeaux → repli bordeaux sans voile |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique » ; entrée échelonnée conservée ; effets de profondeur décoratifs |
| `npm run build` | passe, 130 modules, version `0.17.0` dans le bundle |

---

**Récap — hero plein cadre, titre dans la bande du drapeau, compte à rebours en horloge** (version `0.18.0`)

Cinq corrections ciblées sur l'écran récapitulatif, relevées à l'œil sur le rendu de la version précédente. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x` et `0.17.0`).

*Correction 1 — le hero touche les trois bords.* Aucun arrondi en haut ni sur les côtés, les 24px du design system conservés en bas pour la transition vers le contenu. La composition portait déjà `pleine-largeur` et `coiffe-ecran` ; `rounded-t-none` rend l'intention explicite plutôt que de la laisser reposer sur l'absence d'une classe, qu'un ajout ultérieur suffirait à défaire.

---

***Correction 2 — le nom du Grand Prix se pose dans une bande, pas au milieu du drapeau.*** C'est le point de la version.

Centré sur toute la hauteur du hero, le titre tombait là où le hasard des bandes le mettait : sur les Pays-Bas, à cheval sur la couture rouge/blanc, avec une moitié de lettre sur chaque couleur. `bandeTitre` est ajouté à `composants/DrapeauxGP.jsx` et rend, pour chaque drapeau **horizontal**, les bornes de la bande à viser en pourcentages de la hauteur du bloc.

**La bande retenue est la plus claire, et ce n'est pas un choix esthétique** : c'est déjà elle qui détermine le voile depuis la version `0.15.0`, donc la seule dont on ait mesuré qu'elle porte du texte blanc à 3:1. Viser la plus sombre poserait le titre sur une couleur que personne n'a éprouvée.

Un drapeau **vertical** (Italie, Bahreïn, Mexique) ou un aplat uni rend `null` : ses bandes sont côte à côte, il n'existe aucune bande horizontale à viser, et l'écran garde son centrage habituel. Le repli bordeaux aussi — le bloc « Grand Prix hors table » est donc rigoureusement celui d'avant.

**Le calage est borné par deux `clamp`, et ces bornes ne sont pas de la prudence décorative** — sans elles, trois des douze drapeaux cassent la composition :

| Borne | Ce qu'elle empêche |
|---|---|
| Titre ≥ `safe + 106px` | le titre remonterait dans la rangée de retour sur un drapeau à bande claire en haut |
| Titre ≤ `100% - 110px` | **Azerbaïdjan (bande verte en bas), Singapour et Qatar** : centré sur leur bande, le titre sortirait du hero |
| Date ≥ `titre + 42px` | la date passerait **au-dessus** du titre dès que celui-ci est rabattu par la borne précédente |
| Date ≤ `100% - 42px` | la date sortirait du bloc pour les trois mêmes drapeaux, dont la bande claire finit à 100 % |

**La date est ancrée au bas de la bande visée, et non laissée dans le flux sous le titre.** C'est ce qui la fait tomber dans la bande *suivante* — le bleu, sur les Pays-Bas. Dans le flux, elle retombait à cheval sur la couture, à 205px pour une frontière à 218px. Sans bande visée, `fin` vaut le centre : la borne basse l'emporte alors, et la date reprend exactement la place qu'elle occupait — un seul jeu d'expressions couvre les treize cas, sans branche.

La borne basse de la date est calculée **depuis la position du titre**, `clamp` imbriqué dans le `calc` : quel que soit le rabattement imposé au titre, la date reste dessous. La recalculer à partir du pourcentage de bande aurait été fausse dans exactement les cas où la borne joue.

*Le hero prend donc une hauteur fixe* — `HAUTEUR_HERO = 280px`, plus la zone sûre. C'est ce qui donne un sens aux pourcentages : la boîte du bloc est celle-là même sur laquelle le dégradé du drapeau s'étale, si bien que « 50 % de la hauteur » désigne le même endroit pour le titre et pour la bande blanche. La zone sûre s'ajoute aux deux à la fois.

*Conséquence sur la rangée du haut* — le bouton de retour et la pastille « Récap » passent **sur une seule ligne**, la sortie à gauche et le nom de l'écran à droite. Ils tenaient l'un sous l'autre tant que le titre suivait dans le flux ; empiler trois éléments au-dessus d'un titre désormais calé sur une bande l'aurait forcé à les rejoindre. C'est aussi la disposition d'une barre de navigation iOS (`/apple-design` §16), et la sortie garde ses 44px et son retour à l'appui.

---

***Correction 4 — le compte à rebours devient une horloge.***

« 5j 23h 53min » demande d'être lu en entier pour en extraire trois nombres. Trois tuiles sombres (`#1A1A1A`, rayon 12px, ombre de carte) posent chacune son nombre sous son unité, séparées par un « : » gris décoratif. **La carte qui les porte prend le beige du fond** et non le blanc des autres cartes : sur du blanc, trois aplats presque noirs se découpent comme des trous ; sur le beige ils se lisent comme des objets posés, et c'est `shadow-bloc` qui dit alors que la carte est une carte.

**Deux écarts au design system, tous deux demandés explicitement et tous deux bornés à ces trois tuiles** : la graisse **700**, que la section 5 réserve aux numéros de voiture, et le rayon de **12px**, absent de l'échelle (14px est le plus petit). Le second reste dans l'esprit de la section — plus l'élément est petit, plus son rayon l'est.

**Trois blocs, toujours, mais pas toujours les trois mêmes unités.** Au-delà d'une heure : jours, heures, minutes. En deçà, l'horloge glisse d'un cran vers les secondes. Ce n'est pas une liberté prise avec la demande : à quinze minutes du départ, un bloc « jours » figé à zéro ne dit rien, et un compte à rebours dont la plus petite unité ne bouge qu'une fois par minute paraît arrêté — au moment précis où il compte le plus. C'est déjà la règle de `formaterRestant`, qui passe à « 32min 10s » dans la dernière heure, et celle de `useFermeture`, qui bat à la seconde à partir de là.

`blocsRestant` et `decouperRestant` sont ajoutés à `lib/format.js`, où vit déjà toute la mise en forme. `formaterRestant` est réécrite par-dessus `decouperRestant` : les deux présentations du même compte à rebours ne peuvent pas diverger.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Les nombres se remettent en place par *number pop-in* (transitions-dev 02), déjà installé pour le compteur de bonus de la maquette 09, et réutilisé tel quel via `composants/Compteur.jsx`. **Les secondes en sont exclues** : une animation par seconde n'accuse plus un changement, elle tourne en boucle — c'est la règle « le mouvement doit être motivé » du skill Taste. Les deux états sans décompte (« Fermés », « À confirmer ») gardent l'échange en place (transitions-dev 04) : le passage de l'horloge à « Fermés » se produit sous les yeux du joueur, à cinq minutes du départ.

*Le squelette suit la nouvelle silhouette* : carte beige, trois tuiles de 72px, bouton à sa hauteur tactile. Sans elles, l'écran sauterait d'une soixantaine de pixels à l'arrivée des données — le défaut déjà corrigé sur les cartes de championnat en version `0.14.0`.

---

*Corrections 3 et 5 — deux libellés.* « Tes pronos sont en place » devient « Tes pronos sont validés » ; « Total si tout tombe » devient « Total de points disponibles ». La célébration « Pronos enregistrés ! » au retour de l'écran de saisie est **conservée** : elle ne s'affiche qu'avec `state.enregistre`, et l'arrivée à froid dit bien l'état, sans rien célébrer.

*Apport d'`/apple-design`* — la rangée de navigation répond aux quatre questions du wayfinding (§16) sur une seule ligne ; le hero est rendu **même en attente et même en erreur**, une barre de retour qui disparaîtrait pendant le réveil de Supabase enfermerait le joueur ; les tuiles sont des surfaces de lecture et non des cibles, donc sans retour tactile ; le voile, la lueur et les séparateurs restent `aria-hidden`.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage pré-rempli) : **335 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Découpage du temps | jours, heures, minutes, secondes justes ; **`formaterRestant` rend exactement la même chose qu'avant** ; valeurs paddées à deux chiffres ; aucun bloc sans fermeture datée ; zéro reste lisible (`00:00:00`) |
| Glissement des unités | J/H/M au-delà d'une heure, **H/M/S en deçà** ; **les secondes ne sont jamais animées**, les deux autres le sont |
| Bande visée | Pays-Bas → la bande blanche du milieu (33,33–66,67 %), Espagne → la bande jaune deux fois plus large (25–75 %), Qatar → la bande blanche du bas (75–100 %) ; **pour chacun des cinq drapeaux horizontaux, la bande visée est bien la plus claire**, vérifié par le calcul ; drapeau vertical, aplat uni et repli → aucune bande, centrage conservé |
| **Géométrie, simulée comme le ferait le moteur de rendu** | les deux `clamp` évalués pour les **treize** fonds, **trois zones sûres** (0, 47, 59px) et **deux hauteurs de titre** (une et deux lignes) : le titre passe toujours sous la rangée de retour, la date reste toujours sous le titre, et tout tient dans le hero — **78 contrôles** ; le titre tombe dans sa bande chaque fois que la borne le permet |
| Contraste | chiffres blancs sur la tuile (17,4:1), libellé à 60 % sur la tuile (6,6:1), tuile détachée du beige de la carte, bordeaux toujours lisible sur la carte beige |
| Hero | pleine largeur, sous la zone sûre, arrondi haut retiré (le bas suivra en `0.18.1`), hauteur assise sur la zone sûre, drapeau en dégradé, voile et surcouche de la `0.16.1` conservés |
| Titre et date | titre calé par `clamp` et remonté d'une demi-hauteur, `<h1>` à l'échelle des titres, centré, ombre portée conservée sur drapeau à bandes ; **date ancrée à 66,67 % sur les Pays-Bas, donc dans le bleu** ; Qatar → date retenue dans le bloc ; repli → date à sa place d'avant |
| Navigation | sortie nommée « Accueil » à 44px, pastille « Récap » sur la même ligne |
| Horloge | carte beige, **trois tuiles sombres**, rayon 12px, graisse 700, chiffres blancs, libellés en gris clair letterspacés, **deux séparateurs décoratifs**, *number pop-in* branché, **plus aucune phrase de compte à rebours** |
| États | GP fermé → aucune tuile, « Fermés », aucun bouton de modification, hero toujours rendu ; sans horaire → **reste ouvert**, aucune durée fabriquée, « À confirmer » ; aucun pronostic → carte amber, **encre foncée imposée par `tonalites`**, aucun total à zéro, horloge quand même ; retour de saisie → célébration conservée |
| Libellés | « Tes pronos sont validés » et « Total de points disponibles » servis, **les deux anciens absents** ; total juste (**792 pts**) |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique », sur les sept cas rendus |
| CSS de production | `border-radius:12px`, `bg-texte`, `text-white/60`, `font-bold`, `text-[30px]` et `tabular-nums` bien générés |
| `npm run build` | passe, 130 modules, version `0.18.0` dans le bundle |

---

**Hero du récap — une image, plus un widget** (version `0.18.1`)

Correction de la version précédente, relevée à l'œil. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, pour la raison désormais habituelle.

*Le défaut* — la version `0.18.0` avait retiré les arrondis du haut et des côtés mais **gardé les 24px du bas et l'élévation `shadow-aplat`**. Le drapeau se lisait donc encore comme un bloc du design system posé sur le fond : un rectangle aux coins ronds, avec un halo sur le beige juste dessous. Ce n'est pas ce qu'est ce hero — c'est l'**image d'ouverture de l'écran**, elle doit toucher les quatre bords.

*La correction* — aucun arrondi nulle part (`rounded-none`), aucune ombre. **Les deux sautent ensemble, et c'est le point à ne pas défaire à moitié** : un aplat sans ombre mais aux coins arrondis flotterait encore, une ombre sans arrondi ne ferait que souligner une coupe franche. C'est aussi ce qui distingue ce hero de l'en-tête coloré d'un championnat (version `0.12.0`), qui reste un bloc — arrondi et élevé — parce qu'il n'a jamais prétendu être autre chose.

Rien d'autre ne bouge : `pleine-largeur` et `coiffe-ecran` étaient déjà en place, la couleur courait déjà jusque derrière la Dynamic Island, et le calage du titre sur la bande du drapeau, le voile calculé et la surcouche uniforme de la `0.16.1` sont conservés tels quels. Le contenu de l'écran reprend franchement sous l'image, à 12px, comme tous les blocs entre eux.

*Vérifié* — rendu hors navigateur : **335 contrôles passent**, dont trois refaits sur le hero — aucun arrondi (ni `rounded-b-bloc`, ni `rounded-carte`, ni aucun autre), **aucune classe d'ombre**, et le drapeau, le voile, la surcouche, le titre calé, la date ancrée et l'horloge inchangés. `npm run build` passe, 130 modules, version `0.18.1` dans le bundle.

---

**Calendrier — cartes de Grand Prix pleine largeur, drapeau et tracé de circuit** (version `0.19.0`)

L'écran de calendrier d'un championnat (maquette 15) passe de rangées blanches à **une carte pleine largeur par Grand Prix**, en deux zones : le drapeau du pays hôte et le tracé du circuit en haut, les informations en bas. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x` et `0.18.x`).

*La référence est `assets/calendrier.svg`* — la planche des douze widgets de la fin de saison, avec pour chacun son pays, son circuit, sa date et son tracé. Elle a servi à la fois de référence visuelle et de **source de données**.

---

***Bahreïn sort du calendrier, la Malaisie y entre.*** C'est la correction que la planche a révélée, et elle touche les deux tables.

`assets/traces.svg` (version `0.15.0`) et `assets/calendrier.svg` donnent la même liste de circuits, dans le même ordre, à un près : **à la cinquième place, la nouvelle planche porte Sepang là où la première portait Sakhir**. C'est le calendrier réel de la fin de saison 2026 qui tranche, et Sakhir n'y figure pas.

- `DrapeauxGP.jsx` : `bahrein` devient **`malaisie`**, en aplat uni **`#CC0001`**. Le drapeau malaisien porte quatorze bandes, un croissant et une étoile à quatorze branches dans un canton bleu : c'est un `type: "complexe"` au sens de la version `0.15.0` — mieux vaut une couleur juste qu'un drapeau approximatif.
- `TracesCircuits.jsx` : le tracé de Sakhir est remplacé par celui de **Sepang**, extrait tel quel de la nouvelle planche, avec sa boîte englobante mesurée en échantillonnant les courbes de Bézier (même méthode qu'à l'étape 9). **Ses coordonnées sont celles de l'autre planche** — 1078 unités de large au lieu de 669 — et c'est sans importance : chaque entrée porte son propre cadrage.
- `slugCircuit` reconnaît « GP Malaisie », « GP Sepang », « Malaysian Grand Prix » et « GP Kuala Lumpur ».

**Les deux tables devaient bouger ensemble**, et un contrôle le vérifie désormais : `TRACES` et `DRAPEAUX` portent exactement les mêmes douze slugs. Laisser un drapeau sans tracé donnerait une bande de 180px vide au milieu de la carte ; laisser un tracé sans drapeau donnerait un circuit posé sur le bordeaux de repli au milieu de onze cartes colorées.

---

*`IDENTITES` — le pays et le circuit de chaque Grand Prix.* Une table à part dans `TracesCircuits.jsx`, et non deux champs de plus dans `TRACES` : celle-ci est purement géométrique (cadrage et chemin), celle-là purement éditoriale. Les deux ne bougent jamais ensemble — un tracé se remesure, un libellé se corrige — et les mélanger obligerait à relire un chemin de 2 Ko pour changer un accent.

**Trois libellés s'écartent de la planche, et c'est signalé pour que ce soit une décision.** Elle est dessinée en anglais par endroits (« Azerbaijan », « Baku ») là où toute l'interface est en français : ils sont francisés. Et elle nomme le circuit de Singapour « Singapour », ce qui ferait une carte disant trois fois le même mot : c'est **Marina Bay**, le vrai nom du tracé, qui est retenu.

***Le pays ne s'affiche que lorsqu'il ajoute quelque chose.*** La demande veut trois lignes à gauche — pays en petit gris, nom du GP en 18px, circuit en petit gris. Mais le nom d'un Grand Prix **est** son pays : « GP Pays Bas » au-dessus de « Pays-Bas » écrit deux fois la même chose. `paysDuCircuit` le tait dans ce cas, et le sert quand il apprend quelque chose — « GP Las Vegas » se court aux États-Unis, « GP Sepang » en Malaisie.

**La comparaison passe par la normalisation nue et non par `slugCircuit`**, dont ce serait pourtant l'usage évident : `slugCircuit` applique les alias, donc ramène « GP Sepang » à `malaisie`, les deux chaînes deviendraient égales et le pays serait tu précisément là où il compte. La normalisation nue compare bien ce qui est écrit, tout en rapprochant « GP Pays Bas » de « Pays-Bas ».

---

***La carte, et le voile qui ne pouvait pas être uniforme tout seul.***

Elle touche les deux bords (`pleine-largeur`), porte les 24px de rayon du design system et 12px de gouttière (`gap-3`) — c'est cette gouttière, et non un trait, qui sépare deux cartes. `overflow-hidden` rend au drapeau les coins arrondis de la carte.

**Zone haute — 180px de drapeau.** La pile de calques est **exactement celle du bloc de l'accueil**, dans le même ordre : lumière spéculaire, voile calculé du drapeau, surcouche uniforme de 15 %, puis le tracé. Le tracé est centré par `xMidYMid meet` en trait blanc à 60 %, avec `boiteLibre` — la bande fixant les deux dimensions, le rapport de forme que le composant pose en ligne devait sauter. Chaque circuit garde donc sa vraie forme : Bakou, 3,4 fois plus large que haut, remplit la largeur ; Zandvoort, presque carré, remplit la hauteur.

**Les 15 % demandés ne suffisent pas seuls, et c'est mesuré.** Sur la bande blanche d'un drapeau néerlandais, un blanc à 60 % posé sur du blanc assombri de 15 % ne vaut que **1,24:1** — le tracé serait invisible. Le voile calculé par drapeau (version `0.15.0`) est donc conservé **dessous** : il ramène cette bande au gris moyen, et le trait y tient alors le même **2,70:1** que sur l'accueil, **5,81:1** sur Las Vegas. Aucun texte ne traverse cette zone, la garantie de 3:1 de l'accueil n'a donc rien à y protéger — elle sert ici le seul tracé.

**Sans tracé, la zone reste le drapeau seul.** Contrairement au bloc de l'accueil, où l'absence de tracé retire la bande entière, ici elle ne peut pas disparaître : c'est elle qui porte la couleur du Grand Prix. Un motif de repli, lui, laisserait croire que ce circuit ressemble à ça. Le repli bordeaux (Grand Prix hors planche) garde exactement l'aspect qu'il a partout ailleurs : ni voile, ni surcouche.

**Zone basse — deux colonnes.** À gauche le pays (quand il ajoute quelque chose), le nom du Grand Prix en 18px, le circuit, puis la pastille de statut. À droite le jour en grand chiffre bordeaux et le mois dessous.

*Un Grand Prix dont Unibet n'a pas annoncé l'horaire n'a pas de date à afficher* : la colonne dit « Date à confirmer » plutôt que d'inventer un chiffre. C'est la règle tenue depuis l'étape 9 — un Grand Prix sans date reste servi, en fin de liste, parce qu'un Grand Prix manquant dans un calendrier se voit tout de suite.

---

***Quatre états, jamais déduits du statut en base.*** `cotes_disponibles` et `resultats_disponibles` sont lus dans leurs tables, et la fermeture se calcule sur l'heure de départ (règle 4.3) : rien ne fait passer un Grand Prix en `cotes_figees` avant le samedi des qualifications, et le job de résultats passe un Grand Prix à `termine` même s'il reste des pronostics sans points. L'ordre des tests compte — un Grand Prix couru est « terminé » quoi qu'il arrive, et une fermeture passée l'emporte sur des cotes disponibles.

| État | Pastille | Contraste mesuré | Bouton |
|---|---|---|---|
| À venir | gris translucide, encre marron | 8,46:1 | aucun |
| Pronos ouverts | amber `#E8A020`, **encre `#1A1A1A`** | 7,86:1 | « Pronostiquer » |
| Fermé | bordeaux `#800111` | 10,88:1 | aucun |
| Terminé | vert sauge `#4A7C59` | 4,86:1 | « Voir les résultats » |

**Deux écarts de couleur, tous deux mesurés.** La demande écrit les quatre pastilles sans dire leur encre : sur l'amber, le blanc tombe à **2,22:1** quand `#1A1A1A` monte à 7,86:1 — c'est le même arbitrage qu'aux versions `0.12.0` et `0.17.0`, et `#999999` en texte plein ne valant que 2,0:1 sur une carte blanche, l'état « à venir » prend un gris translucide avec le marron `secondaire` du design system pour encre. **Le vert `#4A7C59` est celui du design system depuis la version `0.12.0`** : la remarque de l'étape 9, qui notait qu'aucun vert n'existait dans la section 5, n'a plus lieu d'être.

**L'état ne se rafraîchit pas tout seul, et c'est voulu.** La carte lit `etatFermeture` au rendu, sans minuterie : elle n'affiche pas de compte à rebours, seulement un état qui bascule une fois. Douze cartes portant chacune leur `useFermeture` feraient douze minuteries pour une information qui ne change qu'une fois par week-end.

*Le bouton n'existe que là où il y a quelque chose à faire* — c'est la demande, et elle se tient : un Grand Prix à venir n'a pas encore de cotes, un Grand Prix fermé n'accepte plus rien. **Deux styles plutôt qu'un** : « Pronostiquer » est un aplat bordeaux plein, « Voir les résultats » du bordeaux sur le beige du fond. Douze cartes terminées feraient sinon douze barres rouges, et l'urgence ne se distinguerait plus de l'archive.

*Le score du membre* s'affiche sous la date pour un Grand Prix terminé. `mes_points` vaut `null` tant qu'aucun de ses pronostics n'a été noté : la carte dit alors « Pronos pas encore validés », et « Aucun prono » s'il n'a rien joué — jamais « 0 pts ». C'est la convention de l'étape 6, tenue depuis.

---

*Écarts assumés par rapport à la version précédente* :

1. **Le mini-classement à trois membres disparaît de la carte.** La maquette 15 le dessine, et la composition demandée ne lui laisse pas de place — trois rangées sous un hero de 180px donneraient une carte de 400px, soit deux tiers d'un iPhone SE pour un seul Grand Prix. **L'information n'est pas perdue** : « Voir les résultats » ouvre l'écran de résultats (maquette 11), qui sert le classement complet des membres avec leurs pronostics. Le bloc « leader général » de l'écran, lui, est conservé — il s'additionne toujours à partir des mêmes `classement`, servis par la route.
2. **Les cartes ne mènent plus nulle part par elles-mêmes** : seul le bouton est un lien. Un Grand Prix fermé n'a donc plus d'accès direct à son récapitulatif depuis le calendrier ; il en garde un depuis l'accueil, dont le bloc rouge mène au récap dès que la fermeture est passée (version `0.5.1`).
3. **La zone du drapeau est grise dans le squelette**, là où les autres squelettes de l'app gardent la couleur de leur aplat (règle de l'étape 9). On ne sait pas encore quel pays arrive : le gris est la seule réponse honnête. C'est le même arbitrage que pour les cartes de championnat de la version `0.14.0`.

*`Pave` accepte désormais le reste de ses propriétés* (`Squelette.jsx`) : c'est ce qui permet au squelette de fixer sa hauteur depuis `HAUTEUR_DRAPEAU`, la constante que la carte réelle utilise, plutôt que depuis une classe qui la dupliquerait. Sans cette hauteur partagée, la liste sauterait de 180px par carte à l'arrivée des données — le défaut déjà corrigé sur les cartes de championnat en version `0.14.0`.

*`formaterJourMois` entre dans `lib/format.js`*, où vit toute la mise en forme. Elle rend `null` quand l'horaire n'est pas annoncé, comme `formaterDepart` rend `courte: null` : ce n'est pas à une fonction de mise en forme d'inventer un chiffre.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Les cartes entrent avec le bloc qui les porte (*texts reveal*, transitions-dev 18) et l'attente passe par *skeleton loader and reveal* (14), toutes deux déjà installées. Une carte de calendrier ne change pas d'état sous les yeux du joueur : il n'y a aucun changement à accompagner, et un jeton de plus aurait été un jeton à maintenir sans rien gagner.

*Apport d'`/apple-design`* — le bouton garde ses 44px et son retour à l'appui ; le drapeau, le voile, la surcouche et le tracé sont `aria-hidden` et `pointer-events-none`, un lecteur d'écran n'ayant rien à annoncer d'une illustration ; le nom du Grand Prix est un `<h2>`, ce qui donne à la liste une vraie structure de titres ; et le squelette suit la silhouette réelle (§7, cohérence spatiale).

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage doublé) : **148 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Les deux tables | 12 tracés, 12 drapeaux, **exactement les mêmes slugs**, les douze attendus dans l'ordre ; **`bahrein` a disparu des deux** |
| Sepang | `viewBox` à quatre nombres et ratio concordant, chemin non vide, **aucune commande de chemin non gérée**, un seul sous-tracé ; les douze tracés restent deux à deux distincts |
| Malaisie | aplat uni, `#CC0001` exact, servi sans dégradé ; toutes les couleurs de drapeau au format `#RRGGBB` |
| `slugCircuit` | les onze libellés éprouvés résolus, « GP Sepang » et « Malaysian Grand Prix » compris ; **« GP Bahreïn » et « GP Sakhir » ne tombent plus sur aucun tracé** ; GP hors planche → rien ; clé héritée d'`Object` → `false` |
| Pays et circuits | les douze circuits nommés et distincts, Marina Bay et Hermanos Rodríguez servis ; **le pays est tu quand il redit le nom du GP** (Pays-Bas, Malaisie, Abou Dabi) et **dit quand il ajoute quelque chose** (Las Vegas, Sepang) ; slug inconnu → `null` |
| Jour et mois | 23 août → « 23 » / « AOÛT », 6 septembre → « SEPT » **sans point** ; date absente ou illisible → `null` |
| Les quatre états | ni cotes ni résultats → à venir ; cotes et départ à venir → ouvert ; départ passé → fermé ; **résultats → terminé même après fermeture** ; **GP sans horaire reste ouvert** ; les quatre libellés demandés |
| Contraste | les quatre pastilles ≥ 4,5:1 ; **le blanc serait à 2,22:1 sur l'amber**, d'où l'encre foncée |
| Tracé | **≥ 2,4:1 sur les treize fonds**, 2,70:1 au pire ; **les 15 % seuls resteraient à 1,24:1** sur une bande blanche |
| Structure de la carte | pleine largeur, 24px de rayon, élevée, sur surface blanche, débordement coupé, **zone du drapeau à 180px**, aucun rayon latéral propre |
| Drapeau | dégradé néerlandais rendu, **voile calculé à 0,45**, surcouche de 15 %, lumière spéculaire ; Malaisie en aplat rouge sans dégradé ; **GP hors table → repli bordeaux, ni voile ni surcouche** |
| Tracé rendu | trait et non aplat, `currentColor`, 60 % de blanc, décoratif, `xMidYMid meet`, **aucun `aspect-ratio` en ligne** ; Sepang rendu pour le GP de Malaisie ; **GP hors table → aucun `<svg>`, mais la zone garde ses 180px** |
| Informations | nom en `<h2>` à 18px, circuit nommé, **le pays n'est pas répété** ; jour en grand chiffre bordeaux, mois en petit ; **sans horaire → « Date à confirmer » et aucun grand chiffre** |
| Pastilles | les quatre rendues avec leur aplat, **`bg-accent text-texte` sur l'amber** |
| Score | 792 pts et « 2e de ce GP » ; **non jugés → « pas encore validés », jamais « 0 pts »** ; aucun pronostic dit comme tel ; **aucun score sur un GP non terminé** |
| Bouton | « Pronostiquer » vers les cotes, « Voir les résultats » vers les résultats, **aucun bouton à venir ni fermé** ; pleine largeur, 44px, retour à l'appui |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique », sur les six cartes rendues |
| Écran | se rend sans lever, **le mot « Historique » n'apparaît nulle part**, squelette pleine largeur **à la hauteur réelle de la carte** |
| CSS de production | `bg-vert-sauge`, `text-white/60`, `bg-black/15`, `font-size:32px`, `letter-spacing:-.025em`, `border-radius:10px`, `rounded-carte-sm` et `min-h-tactile` bien générés |
| `npm run build` | passe, version `0.19.0` dans le bundle |

---

**Calendrier global — les douze Grands Prix de la saison, en cartes widget** (version `0.20.0`)

L'onglet **Calendrier** cesse d'afficher la liste des championnats et affiche ce que son nom promet : les douze Grands Prix restants de la saison 2026, un par carte. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x` et `0.18.x`). Un module de données, un composant, un écran réécrit.

Le fichier de référence est `assets/calendrier.svg`, la planche des douze widgets — pays en haut à gauche, quantième en très grand sous lui, circuit à droite, tracé posé sur l'aplat.

*Ce qui disparaît* — la liste des championnats, son état vide et ses deux cartes d'action. Elle vivait déjà à deux endroits, l'accueil et son propre onglet ; une troisième copie n'apprenait rien à personne, et elle occupait l'onglet qui devait porter la saison. Le calendrier d'**un championnat** (maquette 15), avec ses scores et son mini-classement, reste un autre écran, atteint depuis le championnat.

---

***La liste est statique, et c'est la seule façon d'afficher une saison.***

`frontend/src/lib/calendrier2026.js` porte les douze Grands Prix : slug, nom, pays, circuit, date, mois. C'est la **source de vérité** de l'écran, et le point de la version.

`public.grands_prix` ne contient que ce que le scraper a rencontré, et **Unibet n'expose jamais que le Grand Prix suivant** (section 3.1) : la table n'en porte qu'un seul à ce jour. Un calendrier lu en base afficherait une course au milieu d'une saison qui en compte douze. C'est exactement le défaut qui avait figé le bandeau « Grands Prix restants » à la version `0.14.1`, ici poussé à sa conclusion : le calendrier de la Formule 1 est une donnée publique et stable, il n'a pas à être découvert chez un bookmaker.

**La base garde ce qu'elle seule sait** — l'identifiant du Grand Prix, son statut, l'existence de ses cotes. `enrichir()` croise les deux ; `chargerCotesEnBase()` appelle `GET /scraper/cotes`, la route publique de l'étape 4.

**Conséquence à ne pas défaire : les douze cartes s'affichent quoi qu'il arrive.** Railway endormi, appel en échec, base vide — l'écran reste plein et lisible, seuls les états et les boutons manquent. C'est l'inverse d'un écran de liste ordinaire, où l'absence de données donne un écran vide, et c'est précisément pour cela que la liste vit côté frontend. Le bloc d'erreur s'affiche **au-dessus** des cartes, jamais à leur place.

**Le rapprochement se fait sur le slug de circuit, jamais sur le nom.** Unibet écrit « GP Pays Bas » cette semaine et « GP Pays-Bas » la suivante — c'est déjà la raison pour laquelle `grands_prix` se rapproche par `id_unibet` (étape 4). `slugCircuit` ramène les deux à la même clé, alias compris. Le nom **affiché** reste celui de la table statique : le calendrier doit se lire pareil d'une semaine à l'autre, y compris quand le bookmaker change l'orthographe d'un pays.

***Le quantième est lu dans la chaîne, jamais dérivé.*** `date` est une date nue (`2026-08-23`), donc **minuit UTC** une fois analysée par `new Date` : en tirer le jour avec `getDate()` rendrait « 22 » pour tout lecteur situé à l'ouest de Greenwich, et le calendrier afficherait la veille de chaque course sur la moitié de la planète. `jourDe()` lit donc la chaîne elle-même, et le champ `mois` est écrit dans la table. L'**heure** de départ, elle, ne vient jamais d'ici : seule la base la connaît, et c'est elle qui décide de la fermeture (règle 4.3).

*Comme `backend/app/calcul/pilotes.py`, cette table décrit une saison* et se relit sur le calendrier officiel de la FIA. Les `slug` doivent rester ceux de `slugCircuit` : ce sont eux qui donnent le drapeau et le tracé, et un slug inconnu ferait retomber la carte sur le bordeaux de la marque, sans circuit. Un contrôle vérifie que les douze en ont un des deux côtés.

---

*Les quatre états, désormais partagés.* `ETATS_GP` entre dans `lib/calendrier.js` et porte le mot et la couleur de chaque état ; `Calendrier.jsx` (calendrier d'un championnat) et `calendrier2026.js` (calendrier de la saison) y lisent tous les deux. Les deux écrans **calculent** l'état différemment, parce qu'ils n'ont pas les mêmes données — l'un lit `resultats_disponibles` servi par la fonction SQL, l'autre croise la liste statique avec `GET /scraper/cotes` — mais ils doivent dire le même mot avec la même couleur, sans quoi un Grand Prix changerait d'état en passant d'un onglet à l'autre. Deux tables écrites séparément auraient divergé au premier libellé retouché. **Aucun comportement du calendrier d'un championnat ne change** : `etatDuGp` rend exactement les mêmes objets, un contrôle le vérifie.

**Un Grand Prix absent de la base est « à venir », toujours.** On ne sait ni si ses cotes existent, ni à quelle heure il part : le déclarer fermé sur la foi d'une date sans heure le fermerait dès minuit UTC le jour de la course, et « terminé » supposerait des résultats que personne n'a lus. C'est le bon sens du doute, et c'est ce que la demande prescrit.

***Tant que la base n'a pas répondu, la pastille est une silhouette.*** Une pastille « À venir » posée par défaut se corrigerait en « Pronos ouverts » sous les yeux du joueur, et lui aurait menti l'instant d'avant. La date, le nom et le circuit, eux, s'affichent tout de suite : ils sont vrais sans la base. C'est le squelette appliqué à la bonne granularité — la seule information inconnue, et rien d'autre.

*Le bouton n'existe que là où il y a quelque chose à faire.* « Pronostiquer » vers les cotes, « Voir les résultats » vers les résultats ; rien sur un Grand Prix à venir, qui n'a pas encore de cotes, ni sur un Grand Prix fermé, qui n'accepte plus rien. Les deux états qui portent un bouton exigent tous deux un identifiant venu de la base : il ne peut donc jamais manquer. **Deux styles plutôt qu'un** — aplat bordeaux plein pour « Pronostiquer », bordeaux sur le beige du fond pour « Voir les résultats » : douze cartes terminées feraient sinon douze barres rouges, et l'urgence ne se distinguerait plus de l'archive.

---

*La carte* — `frontend/src/composants/CarteGpSaison.jsx`.

**Elle n'est pas pleine largeur**, contrairement à celles du calendrier d'un championnat : elle garde les 16px de marge latérale d'`ecran` et les 24px de rayon du design system sur ses **quatre** coins. C'est ce qui la met à la largeur des autres widgets de l'application — cartes de championnat, blocs de l'accueil — au lieu d'en faire un bandeau à part.

**Zone haute, 180px** : la pile de calques est **exactement celle du bloc de l'accueil**, dans le même ordre — lumière spéculaire, voile calculé du drapeau, surcouche uniforme de 15 %, puis le tracé en trait blanc à 60 %, centré par `xMidYMid meet`. Un Grand Prix se reconnaît donc à ses couleurs d'un écran à l'autre. Les 15 % demandés **ne suffisent pas seuls, et c'est mesuré** : sur la bande blanche d'un drapeau néerlandais, un trait blanc à 60 % posé sur du blanc à peine assombri reste invisible ; le voile calculé par drapeau (version `0.15.0`) est conservé dessous et ramène cette bande au gris moyen, où le trait tient 2,70:1. Aucun texte ne traverse cette zone — la garantie de 3:1 de l'accueil n'a rien à y protéger, elle sert ici le seul tracé.

**Zone basse, deux colonnes** : à gauche le pays en petit gris, le quantième en très grand, le mois dessous ; à droite le nom du Grand Prix, le circuit, la pastille de statut.

Trois points de mise en œuvre :

1. **`items-baseline` et non `items-start`.** Le pays (11px) et le nom du Grand Prix (18px) n'ont pas la même taille : deux colonnes calées par le haut feraient partir leurs premières lignes sur deux lignes de base distinctes, à quelques pixels l'une de l'autre. C'est le genre d'écart qu'on ne nomme pas mais qu'on voit.
2. **Le zéro de tête est retiré du quantième.** « 04 » se lit comme un numéro de série, « 4 » comme une date.
3. **`HAUTEUR_DRAPEAU` est écrite une fois** et exportée : elle sert la carte et servira le squelette. Sans hauteur partagée, la liste sauterait de 180px par carte à l'arrivée des données — le défaut déjà corrigé sur les cartes de championnat en version `0.14.0`.

*Écart assumé sur la typographie, et c'est le seul.* Le quantième est demandé en **48px, graisse 700**. La section 5 réserve le 700 aux numéros de voiture et son échelle s'arrête à 44px : l'écart est explicite, borné à ce seul chiffre, et c'est le même arbitrage qu'aux tuiles du compte à rebours de la version `0.18.0`. Le crénage négatif suit `/apple-design` §15 — un chiffre n'a ni jambage ni hampe, rien ne vient remplir l'espace entre deux caractères.

*Écart assumé sur les couleurs de pastille* — la demande ne dit pas leur encre. Sur l'amber, le blanc tombe à **2,2:1** quand `#1A1A1A` monte à 7,9:1 : c'est le même arbitrage qu'aux versions `0.12.0`, `0.17.0` et `0.19.0`, et il est désormais écrit une seule fois dans `ETATS_GP`.

*Le décompte de l'en-tête se lit sur les cartes* — « Saison 2026 · N Grands Prix restants » compte les cartes qui ne sont pas terminées, et non une constante. Aucun nombre de cet écran ne vient d'ailleurs que de ce qu'il affiche.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Les cartes entrent avec le bloc qui les porte (*texts reveal*, transitions-dev 18) et la silhouette de pastille reprend le balayage de *skeleton loader and reveal* (14), toutes deux déjà installées. Une carte de calendrier ne change pas d'état sous les yeux du joueur : il n'y a aucun changement à accompagner, et un jeton de plus aurait été un jeton à maintenir sans rien gagner. Les douze cartes partagent un seul rang d'apparition — `index.css` n'en déclare que cinq, et le nombre de Grands Prix n'a pas à s'y plier.

*Apport d'`/apple-design`* — le bouton garde ses 44px et son retour à l'appui ; le drapeau, le voile, la surcouche, le tracé et la silhouette sont `aria-hidden` et `pointer-events-none`, un lecteur d'écran n'ayant rien à annoncer d'une illustration ; le nom du Grand Prix est un `<h2>`, ce qui donne à la liste une vraie structure de titres ; et l'écran ne dit jamais un état qu'il ne connaît pas (§16, feedback : un statut est une information, pas une décoration).

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage doublé) : **103 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Liste statique | 12 Grands Prix, **les douze slugs demandés dans l'ordre**, dates strictement croissantes, tous les champs remplis ; **chaque slug a un tracé ET un drapeau** ; `slugCircuit(nom)` retrouve bien le slug des douze |
| `jourDe` | 23 août → « 23 », **4 octobre → « 4 » sans zéro de tête** ; date absente → `null` ; **indépendant du fuseau**, aucun `new Date` sur le chemin |
| Enrichissement | identifiant, statut et cotes portés ; **rapprochement malgré l'orthographe** (« GP Pays Bas ») ; marchés vides → aucune cote ; **GP absent de la base servi quand même** ; le nom affiché reste celui de la table statique ; base absente, vide ou `undefined` → **les 12 cartes** |
| États | quatre états, libellés attendus, **encre foncée sur l'amber** ; **le calendrier d'un championnat lit la même table** ; hors base → à venir **et jamais fermé** ; cotes + départ à venir → ouvert ; départ passé → fermé ; `termine` l'emporte sur tout ; **date de départ inconnue → reste ouvert** (règle 4.3) |
| Bouton | terminé → résultats, ouvert → cotes, **aucun bouton à venir ni fermé**, **aucun sans identifiant** ; les deux styles diffèrent |
| Structure de la carte | **pas `pleine-largeur`**, 24px de rayon, surface blanche, élévation, débordement coupé ; zone du drapeau à 180px ; dégradé néerlandais, voile calculé, surcouche de 15 %, lumière spéculaire ; tracé en trait et non en aplat, blanc à 60 %, **aucun `aspect-ratio` en ligne** |
| Zone basse | pays en petit gris ; **quantième à 48px, graisse 700, bordeaux, crénage négatif** ; mois dessous ; nom en `<h2>` 18px graisse 500 ; circuit ; **colonnes alignées sur la ligne de base** ; pastille et bouton pleine largeur à 44px |
| Autres états | terminé → pastille verte, bouton résultats, **style consultation et non aplat rouge** ; hors base → « À venir », **aucun bouton**, carte complète, drapeau et tracé quand même |
| Attente | **silhouette au lieu d'un « À venir » posé d'office** ; date, nom et circuit affichés pendant l'attente ; un GP déjà connu garde son état pendant un rechargement |
| Repli | GP hors table → aplat bordeaux, **ni voile, ni tracé inventé**, zone gardant ses 180px, carte lisible |
| Écran | 12 cartes rendues, les douze noms et circuits ; **plus aucune liste de championnats**, aucun bouton « Créer » ni « Rejoindre » ; décompte juste et **excluant le GP terminé** ; **sans cache : les 12 cartes quand même**, silhouettes d'état, aucun état inventé ; sans session → se rend sans lever ; entrée échelonnée, place de la barre basse et zones sûres conservées |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique » |
| CSS de production | 48px, graisse 700, crénage `-.03em`, rayon 10px de la pastille, vert sauge et `bg-black/15` bien générés ; version `0.20.0` et les douze Grands Prix dans le bundle |
| Aperçu rendu avec la feuille compilée | les douze cartes dessinées à 390px de large : drapeaux reconnaissables, **tracés lisibles et à leur vraie forme**, colonnes alignées, les trois états distincts au premier coup d'œil |
| `npm run build` | passe, version `0.20.0` dans le bundle |

---

**Carte GP du calendrier — drapeau pleine carte, fidèle au SVG** (version `0.21.0`)

La carte de l'onglet Calendrier passe de deux zones — 180px de drapeau puis les informations sur fond blanc — à **une seule surface** : le drapeau couvre toute la carte, et tout le contenu est posé par-dessus en blanc. C'est ce que `assets/calendrier.svg` dessine, et la version `0.20.0` ne le suivait qu'à moitié : le drapeau n'y était qu'une vignette de tête. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x` et `0.18.x`).

*Ce que la planche dessine, et ce que la carte reprend* — un aplat plein de 810 × 400 unités aux coins arrondis (soit très exactement le rapport d'une carte de 200px à la largeur d'un iPhone), le pays en haut à gauche, le quantième en très grand en bas à gauche avec son mois dessous, le circuit en bas à droite, et le tracé du circuit posé **à travers toute la surface**. La pastille de statut et la bande d'action n'existent pas dans la planche : ce sont les deux ajouts, et ce sont eux qui ont demandé le plus de mesure.

*La pile de calques est celle du bloc de l'accueil, dans le même ordre* : fond du drapeau, lumière spéculaire, **voile calculé** du drapeau, surcouche uniforme de 15 %, tracé, contenu. Ce n'est pas indifférent — le voile est ce qui garantit que du texte blanc tient 3:1 sur les sept drapeaux à bande claire, et tout ce qui éclaircit la surface doit donc passer **dessous**. La surcouche peint **toute** la carte et non une bande, comme la correction de la version `0.16.1` : assombrir une zone seulement coupait un drapeau à bande répétée en deux et faisait paraître le rouge du haut plus vif que celui du bas.

---

***Le texte croise maintenant le tracé, et c'est ce qui change tout le reste.***

Tant que le tracé avait sa propre zone, aucun texte ne le rencontrait. Ici il traverse la carte entière, et une lettre blanche posée pile sur un trait blanc à 60 % perd son contour. L'**ombre portée devient inconditionnelle** — `apparence()` ne la pose que sur les drapeaux à plusieurs bandes, parce que la couture était jusqu'ici la seule chose qu'un texte pouvait croiser ; le tracé en est une seconde, et il existe sur les douze cartes. Même valeur que celle du drapeau, pour que les deux écrans ne divergent pas. C'est le traitement que la vue piste applique déjà à sa légende, qui passe tantôt sur l'asphalte et tantôt sur une bordure blanche.

Le tracé est **borné à la zone d'informations** et ne court pas sous la bande d'action : celle-ci est opaque, et un circuit qui passerait dessous se lirait comme un trait coupé net.

---

***Pastille et bande d'action : la surface est blanche, la couleur est dans l'encre.*** C'est la demande, et elle tient — à deux mesures près, toutes deux documentées ici plutôt que découvertes à l'écran.

Sur une carte blanche, la pastille pouvait être un aplat coloré. Sur un drapeau, non : le gris translucide de l'état « à venir » prendrait la couleur du drapeau dessous, donc une couleur différente sur chacune des douze cartes ; et quatre aplats colorés posés sur douze drapeaux colorés font douze fois deux couleurs qui se disputent le même coin d'écran. D'où la pastille blanche à encre colorée, et la bande d'action de même.

**Premier écart : la surface est opaque, pas semi-transparente.** Le pire substrat est le noir de Las Vegas ; une bande blanche à 85 % y poserait le vert sauge `#4A7C59` à **3,45:1**, et il faut **97 %** de blanc pour atteindre 4,5:1 — c'est-à-dire du blanc. La translucidité demandée est donc rendue par l'encre colorée, qui laisse la carte respirer, et non par une surface qui rendrait le libellé illisible une carte sur douze.

**Second écart : « Pronos ouverts » garde son aplat amber.** Sur du blanc, l'amber `#E8A020` ne vaut que **2,22:1** en encre, et aucun ton chaud du design system ne tient 4,5:1 (le terracotta `#C4622D` plafonne à 4,09:1, même sur du blanc pur). L'amber n'existe que comme aplat — c'est déjà ce que les versions `0.12.0`, `0.17.0` et `0.19.0` avaient tranché, ici poussé à sa conséquence. **Et la conséquence tombe juste** : c'est le seul état sur lequel il y a quelque chose à faire, il est donc le seul à ressortir dans une liste de douze cartes, et la bande d'action juste en dessous le redit. Trois pastilles blanches informatives, une pastille amber actionnable : c'est une hiérarchie, pas une incohérence.

| Élément | Surface | Encre | Contraste |
|---|---|---|---|
| Pastille « À venir » | blanc | `secondaire` `#543925` | 10,56:1 |
| Pastille « Fermé » | blanc | `primaire` `#800111` | 10,88:1 |
| Pastille « Terminé » | blanc | `vert-sauge` `#4A7C59` | 4,86:1 |
| Pastille « Pronos ouverts » | **amber** `#E8A020` | `texte` `#1A1A1A` | 7,86:1 |
| Bande « Pronostiquer » | blanc | `primaire` | 10,88:1 |
| Bande « Voir les résultats » | blanc | `vert-sauge` | 4,86:1 |

C'est le vert sauge, à 4,86:1 sur blanc pur, qui a fixé l'opacité des surfaces : il n'a aucune marge.

**Les deux jeux de classes vivent dans la même table.** `ETATS_GP` (`lib/calendrier.js`) gagne un champ `pastilleSurDrapeau` à côté de `pastille`, plutôt qu'une seconde table : les deux calendriers doivent dire le même mot, et deux tables écrites séparément auraient divergé au premier libellé retouché. **`pastille` est inchangée** — le calendrier d'un championnat, qui pose ses pastilles sur des cartes blanches, ne bouge pas d'un pixel.

Les deux bandes d'action gardent leur distinction : l'aplat bordeaux plein contre le bordeaux sur beige de la version `0.19.0` devient bordeaux contre vert, **par l'encre**. La raison est inchangée — douze cartes terminées feraient sinon douze barres identiques, et l'urgence ne se distinguerait plus de l'archive.

---

*Trois points de mise en œuvre à ne pas défaire :*

1. **`HAUTEUR_BANDE` est retranchée de la carte, jamais ajoutée dessous.** Les douze cartes gardent la même hauteur, qu'elles portent un bouton ou non, comme sur la planche. 46px, donc au-dessus du plancher tactile de 44px.
2. **La silhouette d'attente porte sa couleur en style en ligne.** `.t-skel-bar` peint elle-même `--color-squelette`, et cette règle n'est pas dans une couche Tailwind : une classe utilitaire ne la battrait pas. Le blanc translucide est obligatoire ici — sur un drapeau, le beige clair des autres squelettes se lirait comme une vraie pastille (règle de l'étape 9, celle de la vue piste).
3. **L'interlignage du quantième est `leading-none` et non plus serré.** À 0,85 les chiffres ronds débordent leur boîte par le bas, et le « 13 » de l'Espagne comme le « 26 » de l'Azerbaïdjan venaient toucher le mois. Un chiffre plat comme le « 1 » du Mexique ne le montrait pas : **c'est le genre de défaut qu'on ne voit que sur la bonne date**, et il n'a été trouvé qu'en dessinant les douze cartes avec la feuille compilée.

*Écart assumé sur la typographie, le même qu'en version `0.20.0`* — le quantième passe de 48 à **64px, graisse 700**. La section 5 réserve le 700 aux numéros de voiture et son échelle s'arrête à 44px. L'écart est borné à ce seul chiffre, et c'est la planche qui le demande : il est le repère par lequel on cherche « le prochain ».

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Les cartes entrent avec le bloc qui les porte (*texts reveal*, transitions-dev 18), la silhouette de pastille reprend le balayage de *skeleton loader and reveal* (14), et la bande prend `pressable-large` et non `pressable` : une bande pleine largeur est une grande surface, où 3 % déplacent une dizaine de pixels et transforment l'appui en secousse (règle de la version `0.12.1`). Une carte de calendrier ne change pas d'état sous les yeux du joueur — il n'y a aucun changement à accompagner.

*Apport d'`/apple-design`* — la bande garde ses 44px et son retour à l'appui ; drapeau, voile, surcouche et tracé restent `aria-hidden` et `pointer-events-none`, un lecteur d'écran n'ayant rien à annoncer d'une illustration ; le nom du Grand Prix est un `<h2>`, ce qui donne à la liste une vraie structure de titres ; et l'écran ne dit jamais un état qu'il ne connaît pas (§16 : un statut est une information, pas une décoration).

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage doublé) : **96 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Structure | carte à 200px, 24px de rayon, débordement coupé, `shadow-aplat` ; **le dégradé néerlandais peint toute la carte** ; **aucune surface blanche de zone basse**, plus aucune zone de 180px |
| Calques | **lueur → voile → surcouche → tracé → contenu**, vérifié par position dans le DOM ; voile rendu à l'opacité calculée (0,45), surcouche en `inset-0` |
| Contenu | pays à 12px en haut à gauche ; quantième à 64px graisse 700 avec crénage négatif, mois dessous ; nom en `<h2>` 16px et circuit en bas à droite ; texte blanc ; **ombre portée sur tout le texte** ; encre secondaire venue du drapeau |
| Tracé | trait et non aplat, `currentColor`, blanc à 60 %, centré, **aucun `aspect-ratio` en ligne**, décoratif ; **GP hors planche → aucun `<svg>`**, repli bordeaux sans voile ni surcouche, carte quand même complète |
| Pastilles | les quatre variantes drapeau ; blanc + marron, blanc + bordeaux, blanc + vert ; **« ouvert » garde son aplat amber** ; **la variante carte blanche du calendrier d'un championnat est intacte** |
| **Contraste, mesuré** | les trois encres ≥ 4,5:1 sur blanc, encre foncée sur amber à 7,86:1 ; **l'amber en encre échoue à 2,22:1** et le terracotta plafonne à 4,09:1 — d'où l'aplat conservé ; **une bande à 85 % laisserait le vert à 3,45:1** — d'où l'opacité |
| Garantie de la version `0.15.0` | **le texte blanc tient toujours ≥ 3:1 sur les douze drapeaux**, voile et surcouche compris |
| Bande | « Pronostiquer » blanc + bordeaux vers les cotes, « Voir les résultats » blanc + vert vers les résultats ; pleine largeur, 46px ≥ 44px tactile, `pressable-large` ; **aucune bande à venir ni fermé** ; **le tracé ne court pas sous la bande** |
| Attente | silhouette au lieu d'un état posé d'office ; **blanc translucide, jamais le gris des squelettes** ; date, nom et circuit affichés pendant l'attente ; un GP déjà connu garde son état pendant un rechargement |
| Les douze cartes | chacune se rend avec son drapeau, son tracé, son nom et son circuit |
| Écran et règles permanentes | l'écran se monte sans lever, les douze noms présents, **aucune cote brute « ×N »**, ni « ligue », ni « historique » |
| CSS de production | `font-size:64px`, `line-height:1`, `letter-spacing:-.03em`, `pressable-large`, `shadow-aplat`, `text-vert-sauge`, `text-secondaire`, `bg-accent`, `text-white/60`, `bg-black/15`, rayon 10px bien générés |
| Aperçu rendu avec la feuille compilée | les douze cartes dessinées à 390px de large : drapeaux reconnaissables, **tracés lisibles et à leur vraie forme**, quantièmes séparés de leur mois, les quatre états distincts au premier coup d'œil |
| `npm run build` | passe, version `0.21.0` dans le bundle |

---

**Espacement des cartes du calendrier, et retour contextuel** (version `0.21.1`)

Deux corrections relevées à l'usage. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x`, `0.18.x` et `0.20.0`).

---

***Correction 1 — un `gap` posé sur un `Bloc` est inerte.*** C'est le point de la version, et il ne se voyait pas à la lecture du code.

Les douze cartes de l'onglet Calendrier se touchaient. Le `gap-3` était pourtant bien écrit — `<Bloc rang={2} className="flex flex-col gap-3">` — et c'est précisément ce qui rendait le défaut illisible : **la classe était là, elle ne s'appliquait pas**.

`.t-stagger-line` (index.css) pose `display: block`, et cette règle est déclarée **hors de toute couche Tailwind**. En CSS en cascade par couches, une règle non affectée à une couche l'emporte sur **toutes** les règles empilées, quelle que soit leur spécificité : `.flex { display: flex }` vit dans `@layer utilities`, elle perd. Le bloc reste donc en `display: block`, où `gap` n'a aucun effet — vérifié sur la feuille compilée, la couche `utilities` se referme bien avant la déclaration.

**C'est la même mécanique que celle déjà documentée pour `.t-skel-bar`** à la version `0.21.0`, où le style en ligne avait dû battre la classe utilitaire. Elle vaut pour **toute** propriété que ces règles hors couche écrivent, pas seulement `display`.

*La correction* — le conteneur flex passe **à l'intérieur** du bloc. C'est déjà le motif de l'accueil et de la liste des championnats, qui enveloppent leurs cartes dans un `div` interne ; le calendrier global était le seul à mapper ses cartes directement dans le `Bloc`, et donc le seul à en souffrir. **Rien n'est touché à `index.css`** : déplacer `.t-stagger-line` dans une couche changerait la précédence de toutes les transitions de l'app d'un coup, pour réparer une gouttière.

*Un cas restant, signalé plutôt que corrigé* — `Championnat.jsx` porte lui aussi un `gap-2.5` sur un `Bloc` dont les enfants sont directs (les deux boutons de la confirmation de départ). La gouttière y est donc morte elle aussi. C'est hors du périmètre demandé et sans conséquence visible sur un bouton principal suivi d'un lien discret ; **à reprendre avec le même motif** si l'empilement paraît serré sur un appareil réel.

---

***Correction 2 — le bouton de retour ramène d'où l'on vient.***

Le tableau des cotes s'ouvre depuis l'accueil **et** depuis le calendrier, et son retour ramenait toujours à l'accueil : qui parcourait la saison y perdait sa place. L'origine voyage désormais dans l'état de navigation de React Router.

`origineRetour(etat, defaut)` entre dans `frontend/src/lib/navigation.js`, **le module qui connaît déjà les quatre onglets** — c'est de là que vient le libellé du bouton. Un bouton doit nommer sa destination (règle tenue depuis l'étape 7) : « Accueil » posé sur un retour vers le calendrier serait une promesse fausse. Une origine inconnue des onglets garde le libellé par défaut plutôt que d'en inventer un.

**Deux clés distinctes, et il ne faut pas les confondre :**

| Clé | Sens |
|---|---|
| `retour` | où va **mon** bouton de retour |
| `origine` | ce que je **rends** à cet écran en y retournant, pour qu'il retrouve la sienne |

La seconde n'est pas un raffinement : sans elle la chaîne se casse au premier rebond — calendrier → cotes → pronos → retour → cotes → retour → **accueil**, c'est-à-dire l'exact défaut qu'on corrige, réapparu un écran plus loin. Le tableau des cotes confie donc son origine à l'écran de saisie, qui la lui rend en repartant. `EnTeteEcran` gagne pour cela une prop `retourEtat`, passée telle quelle à `navigate`.

**Le chemin reçu est validé, et ce n'est pas décoratif.** `origineRetour` n'accepte qu'un chemin interne (`/…`) : l'état de navigation est écrit par les écrans, mais il survit à un rechargement et vit dans l'historique du navigateur — une URL absolue glissée là ferait du bouton de retour une sortie vers l'extérieur. Une valeur invalide retombe silencieusement sur la destination par défaut, jamais sur une erreur : un bouton de retour doit toujours mener quelque part.

**Les destinations par défaut sont inchangées** — l'accueil pour les cotes, le tableau des cotes pour la saisie. C'est la hiérarchie de l'application, et c'est ce qui s'applique quand on arrive par un lien direct. `CarteGpSaison` reçoit son origine en prop plutôt que de l'écrire en dur : la carte ne sait pas d'où on la regarde, c'est l'écran qui la monte qui le sait.

*Le libellé du retour reste le nom du Grand Prix* sur les deux écrans (`gp?.nom ?? retour.libelle`), comportement posé à la version `0.13.0` et non touché ici : le nom de l'origine ne sert que de repli, quand le Grand Prix n'est pas encore chargé.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.**

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite) : **26 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| `origineRetour` | état absent, état sans `retour` → destination par défaut ; `/calendrier` retenu **et nommé « Calendrier »** ; `/championnats` nommé ; **chemin inconnu des onglets → libellé par défaut conservé** |
| Validation | **URL absolue, `javascript:`, chemin relatif et valeur non-chaîne rejetés**, tous quatre retombant sur la destination par défaut sans lever |
| Carte de Grand Prix | bande d'action rendue, lien vers les cotes conservé, origine transmise en prop |
| Écran de calendrier | **le conteneur flex est un `div` interne, plus aucun `gap` posé sur un `Bloc`** ; origine passée aux douze cartes |
| Les deux écrans | lisent l'état de navigation, passent par `origineRetour`, **n'écrivent plus aucune destination en dur dans leur en-tête** ; les cotes confient leur origine à la saisie, la saisie la rend en repartant ; les deux se montent sans lever |
| `npm run build` | passe, version `0.21.1` dans le bundle |

---

**Drapeaux manquants et incorrects — Malaisie, États-Unis, Brésil, Qatar, Abu Dhabi** (version `0.21.2`)

Cinq drapeaux relus contre le drapeau réel, dans `frontend/src/composants/DrapeauxGP.jsx`. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x`, `0.18.x` et `0.20.0`). **Un seul fichier change**, et rien d'autre : ni les écrans, ni le calcul du voile, ni les tracés.

| Grand Prix | Avant | Après |
|---|---|---|
| **Malaisie** | aplat rouge `#CC0001` | horizontal, `#CC0001` / `#FFFFFF`, bandes égales |
| **Abu Dhabi** | aplat vert `#00732F` | horizontal, `#00732F` / `#FFFFFF`, bandes égales |
| **Qatar** | **horizontal** `#8D1B3D` / `#FFFFFF`, 3/1 | **vertical**, mêmes couleurs, mêmes parts |
| **Las Vegas** | aplat noir `#000000` | aplat rouge `#B22234` |
| **États-Unis** | aplat rouge `#B22234` | inchangé — déjà conforme |
| **Brésil** | aplat vert `#009C3B` | inchangé — déjà conforme |

*Ce que la relecture a corrigé, cas par cas.*

**Malaisie et Abu Dhabi passaient pour des drapeaux « complexes ».** Ils le sont — quatorze bandes, un croissant et une étoile à quatorze branches dans un canton bleu pour l'un ; trois bandes et un quadrillage rouge à la hampe pour l'autre — mais la couleur dominante seule taisait **la bande blanche qui fait la moitié de leur lecture**, et donnait un aplat rouge ou vert que rien ne distinguait des autres cartes. La frontière entre `complexe` et une paire de bandes n'est donc pas le nombre de bandes : c'est **l'honnêteté du rendu**. Un drapeau qui se laisse ramener à deux bandes dominantes le devient ; la bannière étoilée et la sphère céleste brésilienne, qui n'ont pas de bandes dominantes à extraire, restent des aplats. Quatorze bandes de 7 % chacune se liraient d'ailleurs comme un motif de rayures, pas comme un drapeau, sur une carte de 200px.

**Le Qatar redresse un écart signalé depuis la version `0.15.0`.** Il y était décrit en bandes horizontales, et le fichier le disait explicitement : « une orientation suit la demande plutôt que le drapeau réel […] cela se corrige en changeant le seul champ `type` ». C'est ce qui est fait — le vrai drapeau porte sa bande blanche **à la hampe**, donc verticalement. Le commentaire qui annonçait l'écart disparaît avec lui.

**Las Vegas cesse d'être noir, et c'est le seul changement qui n'est pas une correction de fidélité.** Le noir était la couleur du circuit de nuit, une couleur d'ambiance et non un drapeau. Or **deux Grands Prix d'un même pays doivent porter la même couleur** : Austin et Las Vegas se courent tous deux aux États-Unis, et deux fonds différents pour un même drapeau font perdre le repère que ces couleurs existent pour donner. Les deux slugs restent distincts — ils ont deux tracés de circuit et deux dates — mais rendent désormais **exactement le même fond**, ce qu'un contrôle vérifie plutôt que de le supposer.

---

***Le voile n'a pas eu à être touché, et c'est la démonstration que le calcul de la version `0.15.0` fait son travail.***

C'était le point à vérifier : trois drapeaux gagnent une bande blanche, sur laquelle du texte blanc ne se voit pas. Aucune valeur n'a été écrite à la main pour autant. `voileNecessaire` **dérive** l'opacité de la bande la plus claire, par pas de 0,05, en tenant compte de la lumière spéculaire posée par-dessus : la Malaisie, Abu Dhabi et le Qatar reçoivent donc `0,45` d'eux-mêmes, exactement comme les Pays-Bas et l'Italie, et le blanc y tient **3,36:1** — **4,48:1** une fois la surcouche uniforme de 15 % de la version `0.16.1` prise en compte. C'est précisément ce que l'en-tête du module annonçait : « un drapeau ajouté demain reçoit le bon voile sans que personne n'ait à refaire le calcul ».

**Une conséquence à connaître, et elle est mesurée.** Le voile de 0,42 minimum n'est pas déclenché par la présence d'un `#FFFFFF` dans la table, mais par la luminance : le **vert du Brésil est assez clair pour demander 0,05** alors qu'il n'a aucune bande blanche. La règle n'est donc pas « une bande blanche ⇒ un voile », c'est « le calcul tranche ». Un contrôle du jeu de tests éprouvait initialement la mauvaise règle et échouait sur le Brésil — c'est l'assertion qui était fausse, pas le code.

Deux effets secondaires, tous deux issus du même mécanisme et tous deux voulus :

1. **Las Vegas passe d'un texte secondaire à 70 % au blanc plein en graisse 500.** Sur le noir, 70 % de blanc tenaient largement le seuil ; sur le rouge `#B22234`, ils tombent à 2,97:1 et `apparence()` bascule alors sur la règle de vibrance d'`/apple-design` §12 — la hiérarchie passe par la graisse, pas par l'opacité. Ses surfaces (pastille, cases de statut) restent claires, le rouge étant assez sombre : 3,22:1 sur la plus claire des deux.
2. **La bande de titre du Qatar devient `null`** (écran Récap, version `0.18.0`). Un drapeau vertical n'a aucune bande horizontale à viser : le titre reprend le centrage habituel, cas déjà prévu et déjà couvert par les deux `clamp`. La Malaisie et Abu Dhabi, à l'inverse, en gagnent une — leur bande blanche du bas, centre à 75 %.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Un fond de drapeau ne change pas sous les yeux du joueur.

*Vérifié* — modules chargés par le chargeur SSR de Vite, contrastes recalculés sur les treize fonds : **tous les contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Couverture | **les douze slugs du calendrier ont un drapeau ET un tracé** ; `etats-unis` et `las-vegas` servis tous les deux |
| Couleurs | les six drapeaux du périmètre portent **exactement** le type, les couleurs et les parts demandés ; toutes les couleurs de la table au format `#RRGGBB` |
| **Contraste du texte blanc** | **≥ 3:1 sur les douze drapeaux et sur le repli**, voile calculé compris ; pire cas 3,00:1 (Brésil), 3,36:1 sur les sept drapeaux à bande blanche, 4,44:1 sur les deux Grands Prix américains, 6,81:1 sur le repli ; la surcouche de 15 % porte le pire cas à 4,02:1 |
| Voile | 0,45 sur Malaisie, Abu Dhabi et Qatar **sans qu'aucune valeur soit écrite à la main** ; 0 sur les deux fonds américains ; **0,05 sur le Brésil malgré l'absence de blanc** ; contrôle de non-régression : 0,30 sur une bande blanche resterait à 2,10:1 |
| Deux GP, un pays | **`las-vegas` et `etats-unis` rendent le même fond et le même voile** |
| Fonds CSS | **aucune `url()`, aucun `http`** ; Malaisie et Abu Dhabi en `to bottom` avec bornes à 50 % ; **Qatar en `to right`** avec bornes à 75 % et dernière borne à 100 % ; Las Vegas et États-Unis en aplat uni sans dégradé |
| Ombre portée | présente sur les drapeaux à bandes (Malaisie, Abu Dhabi et Qatar l'acquièrent), **absente sur les aplats unis et sur le repli** |
| Bande de titre | Malaisie et Abu Dhabi → bande blanche du bas (centre 75) ; **Qatar → `null`, le vertical n'a pas de bande à viser** ; Las Vegas → `null` |
| Repli | fond `null`, aucun voile, surfaces claires, aucune ombre — **le bloc bordeaux garde exactement l'aspect qu'il avait** ; GP hors table → `null` |
| `npm run build` | passe, version `0.21.2` et les six couleurs présentes dans le bundle |

---

**Icônes custom SVG dans la barre de navigation** (version `0.22.0`)

Les quatre icônes de la barre de navigation basse viennent désormais de `assets/logo-02.svg`, la planche dessinée pour le projet, et non plus de `composants/Icones.jsx`, tiré des maquettes. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x`, `0.18.x` et `0.20.0`).

*Extraction, jamais reproduction.* Un nouveau dossier `frontend/src/composants/icones/` porte un composant par icône : `IconeAccueil` (maison), `IconeChampionnats` (trophée), `IconeCalendrier`, `IconeProfil` (personne). **Les données de chemin sont identiques à la planche, octet pour octet** — un contrôle du jeu de tests compare les huit chemins aux huit de `logo-02.svg` et vérifie l'égalité stricte. Le découpage a été fait par script, comme pour les tracés de circuits de la version `0.15.0` et pour la même raison : transcrire à la main huit chemins de plusieurs centaines de caractères introduit des fautes invisibles à la lecture.

***La `viewBox` est un carré de 74 unités, le même pour les quatre, et c'est le point à ne pas défaire.*** Les boîtes englobantes réelles ont été mesurées en échantillonnant les courbes de Bézier :

| Icône | Boîte englobante | Largeur × hauteur |
|---|---|---|
| Accueil | x 24,36 → 94,64 · y 28,37 → 95,67 | 70,28 × 67,30 |
| Championnats | x 157,47 → 206,24 · y 28,21 → 101,07 | 48,77 × 72,86 |
| Calendrier | x 273,84 → 334,52 · y 28,22 → 95,84 | 60,68 × 67,62 |
| Profil | x 396,20 → 456,88 · y 25,98 → 98,83 | 60,68 × 72,85 |

Un cadrage serré sur chaque boîte aurait été le réflexe — et il aurait été faux. Les quatre icônes vivent dans **le même système de coordonnées** dans la planche : leurs tailles relatives sont celles que le dessin a voulues, un trophée étroit et haut à côté d'une maison large et basse. Serrer chaque cadrage les ramènerait toutes à la même taille apparente et écraserait cette intention. Le carré de 74 unités — la plus grande dimension rencontrée, 72,86, plus un souffle — est donc **centré sur la boîte de chaque icône** : le cadrage bouge, aucune coordonnée n'est réécrite, et les proportions relatives sont exactement celles de la planche.

**Les deux barres du toit de la maison figurent deux fois dans le fichier, à l'identique** (lignes 17-18 puis 19-20 de la planche). Un seul exemplaire est repris : les chaînes sont strictement égales, le dessin est rigoureusement le même, et le contrôle d'égalité octet pour octet couvre les quatre chemins restants. Les deux anneaux du calendrier sont des `<rect>` et non des chemins ; ils sont repris tels quels, rayons de coin compris.

*La couleur passe par une prop, jamais par `currentColor`.* Chaque composant accepte `couleur` (défaut `#999999`) et la pose sur le `fill` de **toutes** ses formes — un contrôle vérifie que le compte de `fill` colorés égale le compte de formes, sur chacune des quatre. La barre passe `#800111` à l'onglet actif et `#999999` aux autres, les deux couleurs du design system (section 5). Le `#1d1d1b` de la planche ne survit nulle part : il ne se verrait pas tant que la barre est claire, et il ne dirait rien de l'onglet actif.

**Une seconde règle CSS accompagne ce changement, et elle n'est pas décorative.** Depuis l'étape 10, `.t-nav .t-nav-onglet` interpole `color` — ce qui suffisait tant que les tracés étaient en `currentColor` et que le libellé et le dessin héritaient tous deux du lien. Ce n'est plus le cas : le libellé hérite encore, le dessin reçoit un `fill`. Sans une transition posée sur les formes, la couleur du texte glisserait pendant que celle de l'icône basculerait d'un coup, et l'œil verrait deux événements là où il n'y en a qu'un. `.t-nav .t-nav-onglet :is(path, rect)` interpole donc `fill` **sur la même durée et la même courbe** (`--icon-swap-dur`, `--icon-swap-ease`). Un `fill` posé en attribut de présentation entre bien dans la cascade, donc il s'interpole comme une propriété ordinaire. Les deux règles sont coupées ensemble sous `prefers-reduced-motion`.

*Écart assumé — l'échange contour ↔ aplat disparaît.* La barre montait chaque icône deux fois, en contour et en aplat, et les échangeait par transitions-dev 09 (version `0.10.0`). **Les icônes de la planche n'existent qu'en une seule forme** : il n'y a plus rien à échanger, et la couleur redevient le signal unique — ce qu'elle était déjà à titre principal. Le snippet reste installé et sert toujours à l'étoile de favori du tableau des cotes.

*Les quatre anciennes icônes restent dans `composants/Icones.jsx`* (`IconeMaison`, `IconeTrophee`, `IconeCalendrier`, `IconePersonne`) : elles servent ailleurs — `IconeMembres` aux cartes de championnat, les autres à divers écrans — et le fichier n'est pas touché. Attention au nom : `IconeCalendrier` existe désormais **des deux côtés**, dans `composants/Icones.jsx` (contour, avec variante `pleine`) et dans `composants/icones/IconeCalendrier.jsx` (planche, avec prop `couleur`). Ce sont deux dessins différents et l'import doit dire lequel.

*Taille* — 28 × 28px (`size-7`), contre 22px auparavant. La rangée gagne donc 6px ; `min-h-tactile` étant un plancher et non une hauteur fixe, elle grandit d'elle-même et la zone tactile de 44px est conservée.

*Apport d'`/apple-design`* — les quatre icônes sont `aria-hidden` et `focusable="false"` : le libellé de l'onglet dit déjà où mène le lien, et un lecteur d'écran n'a pas à l'entendre deux fois. Zone tactile de 44px, retour tactile à l'appui, `aria-current` sur l'onglet courant, zone sûre basse et matériau translucide sont inchangés (version `0.10.0`), et retoucher l'onglet déjà ouvert ramène toujours en haut de l'écran.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** La règle ajoutée réutilise les deux jetons de l'échange d'icônes déjà installé.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite) : **48 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Fidélité à la planche | **les 8 chemins sont strictement identiques à `logo-02.svg`**, octet pour octet ; les 2 doublons exacts de la maison fondus en un |
| Les quatre composants | chacun se rend ; **`viewBox` carrée de 74 unités**, la même pour les quatre ; décoratives (`aria-hidden`, `focusable="false"`) ; défaut `#999999` ; **aucun `#1d1d1b` ni aucune classe `cls-1` héritée** ; `className` transmis ; **la couleur atteint toutes les formes**, rects du calendrier compris |
| Barre | quatre onglets, quatre icônes, **un seul `aria-current`** ; l'onglet actif en `#800111` et les autres en `#999999`, vérifié écran par écran sur les quatre onglets ; icônes à 28px ; **plus aucun `t-icon-swap`** ; les quatre libellés ; zone tactile, retour à l'appui, matériau, zone sûre, aucune bordure |
| Absences | **rien sans session**, rien sur la vue piste |
| Bundle de production | les quatre `viewBox`, les deux couleurs, la transition du `fill`, l'utilitaire 28px et le repli mouvement réduit bien générés ; **aucun `#1d1d1b`** |
| Aperçu rendu | les quatre icônes dessinées à six fois la taille réelle **et** à 28px : chacune reconnaissable, bien cadrée, et les tailles relatives de la planche conservées |
| `npm run build` | passe, version `0.22.0` dans le bundle |

---

**Drapeaux SVG réels pour six pays hôtes** (version `0.24.0`)

Les six drapeaux que le CSS ne reproduisait pas honnêtement sont désormais **dessinés**, extraits de `assets/flags.svg` : Malaisie, États-Unis (donc aussi Las Vegas), Mexique, Brésil, Qatar et Abu Dhabi. Les cinq autres du calendrier — Pays-Bas, Italie, Espagne, Azerbaïdjan, Singapour — **gardent leur `linear-gradient`** : deux ou trois bandes franches sont exactement ce que le CSS sait dire, et un dessin n'y apporterait rien. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x`, `0.18.x` et `0.20.0`).

*Le traitement `complexe` disparaît.* Ramener la bannière étoilée à un aplat rouge, ou la Malaisie à deux bandes égales, était le compromis qu'on faisait **faute de dessin** — la version `0.15.0` l'énonçait ainsi (« mieux vaut une couleur juste qu'un drapeau approximatif ») et la `0.21.2` l'avait déjà entamé en rendant leur bande blanche à trois d'entre eux. Le dessin existe maintenant : l'approximation n'a plus de raison d'être, et `type: "complexe"` n'a plus aucun porteur.

*Extraction, jamais reproduction* — `frontend/src/composants/DrapeauxSVG.jsx`. Chemins, rectangles et polygones sont ceux de la planche, coordonnée pour coordonnée ; seule la couleur change de porteur, de la classe `cls-N` de la feuille de style vers un attribut `fill`. Le découpage a été fait **par script**, comme les tracés de circuits de la version `0.15.0` et les icônes de la `0.22.0`, et pour la même raison : transcrire à la main quarante-huit formes de plusieurs milliers de caractères introduit des fautes invisibles à la lecture. Les formes en `fill: none` de la planche sont écartées — elles ne peignent rien, et les garder aurait chargé le DOM de nœuds sans effet.

***Écart assumé sur les `viewBox`, et c'est le point de la version.*** La demande donnait six tranches égales de 463 unités (`0 0 1017.37 463`, `0 463 …`, et ainsi de suite), la planche faisant 2779,75 de haut pour six drapeaux. **Les drapeaux n'y sont ni jointifs, ni de même hauteur, ni régulièrement espacés** :

| Slug | `viewBox` mesurée | Hauteur | Rapport |
|---|---|---|---|
| `malaisie` | `277.76 104.27 585.18 353.48` | 353 | 1,655 |
| `etats-unis` | `277.76 513.87 585.18 353.48` | 353 | 1,655 |
| `mexique` | `272.27 937.41 587.46 335.49` | 335 | 1,751 |
| `bresil` | `265.12 1333.34 612 417` | 417 | 1,468 |
| `qatar` | `272.42 1847.44 590.52 345.14` | 345 | 1,711 |
| `abu-dhabi` | `269.67 2288 611.49 305.49` | 305 | 2,002 |

Les tranches arithmétiques auraient coupé les uns et laissé du vide autour des autres — le drapeau brésilien commence à 1333 quand sa tranche commence à 1389, et celui d'Abu Dhabi finit à 2593 quand sa tranche va jusqu'à 2779. Ce sont donc les **vraies boîtes englobantes** qui font foi, mesurées en échantillonnant les courbes de Bézier, exactement comme les tracés de circuits de la version `0.15.0` et les icônes de la `0.22.0` : **aucune coordonnée n'est réécrite, c'est le cadrage qui bouge**. Aucune marge n'est ajoutée, les formes étant des aplats sans contour.

*`xMidYMid slice` fait le reste.* Chaque drapeau garde son rapport de forme, du 1,47 brésilien au 2,00 émirati, et couvre toute la surface de son conteneur, rogné sur son plus grand côté, jamais déformé. C'est le pendant exact d'`object-fit: cover`.

---

***`couleurs` n'est pas décoratif : c'est la matière du calcul de contraste.*** C'est la conséquence la plus importante du passage au dessin, et celle qu'on ne voit pas en relisant le JSX.

Le voile noir de la version `0.15.0` est **dérivé de la bande la plus claire** du drapeau. Tant que les États-Unis et le Brésil étaient déclarés `complexe` avec une seule couleur dominante (`#B22234`, `#009C3B`), le calcul concluait qu'aucun voile — ou presque — n'était nécessaire. **Le dessin, lui, peint treize bandes blanches sur la bannière étoilée.** Servi sous l'ancienne déclaration, il aurait porté du texte blanc sur du blanc pur.

La table porte donc désormais **toutes** les teintes que le SVG peint, et pas seulement les dominantes. Le voile s'ajuste de lui-même, sans qu'une valeur soit écrite à la main :

| Slug | Voile avant | Voile après | Blanc plein |
|---|---|---|---|
| `etats-unis`, `las-vegas` | **0,00** | **0,45** | 3,45:1 |
| `bresil` | **0,05** | **0,45** | 3,36:1 |
| `malaisie` | 0,45 | 0,45 | 3,45:1 |
| `mexique` | 0,45 | 0,45 | 3,36:1 |
| `qatar`, `abu-dhabi` | 0,45 | 0,45 | 3,36:1 |

Avec la surcouche uniforme de 15 % de la version `0.16.1`, le pire cas monte à **4,48:1**. **Règle à ne pas défaire : toute forme peinte par le SVG doit avoir sa teinte dans `couleurs`.** Un contrôle du jeu de tests compare les deux tables forme par forme et échoue sur la moindre teinte tue.

*`fond` reste toujours renseigné*, et c'est ce qui évite de toucher aux quatre écrans plus qu'il ne faut. Pour un drapeau dessiné il vaut `base`, un aplat pris dans les teintes du drapeau. **Il ne se voit jamais** — le SVG couvre tout — mais il porte deux rôles : filet de sécurité si le fragment manquait, et surtout **le drapeau de « ce bloc porte un drapeau »**, celui que les écrans lisent depuis la version `0.15.0` pour savoir s'ils doivent retomber sur le bordeaux de la marque et s'ils doivent poser l'assombrissement uniforme. Le rendre `null` aurait fait basculer les six blocs sur le repli.

*`FondDrapeau` vit dans `DrapeauxGP.jsx`*, à côté de `VoileDrapeau`, et non chez les écrans : un écran qui monterait `DrapeauSVG` lui-même devrait savoir quel fragment demander, donc relire la table — et deux lectures finiraient par diverger. Le slug est **vérifié contre `DrapeauxSVG.jsx`** (`aUnDrapeauSvg`) plutôt que recopié de confiance : une faute de frappe laisserait sinon le bloc sur son aplat de repli sans que rien ne le signale.

***Le drapeau est le calque le plus bas des quatre blocs***, et c'est la seule chose que les écrans avaient à apprendre. L'ordre devient : **drapeau → lueur spéculaire → voile calculé → surcouche de 15 % → contenu**. Posé plus haut, il repeindrait ses bandes claires par-dessus le voile et le texte retomberait sous les 3:1 — exactement le dégât que la version `0.15.0` décrit pour le tracé du circuit. Un contrôle vérifie l'ordre par position dans le DOM.

*`bandeTitre` passe à `null` pour les six.* La Malaisie et Abu Dhabi, qui visaient leur bande blanche tant qu'ils étaient décrits en CSS, la perdent — et pour une raison de plus que les drapeaux verticaux : **leurs bandes ne sont plus une donnée mais un dessin**, et `slice` les décale dès que le conteneur n'a pas le rapport de forme du drapeau. Viser une bande qu'on ne sait pas placer poserait le titre du récap n'importe où ; le centrage, lui, est juste dans tous les cas, et le voile calculé continue seul de garantir la lisibilité.

*Las Vegas et Austin partagent le fragment `etats-unis`*, dans le prolongement de la version `0.21.2` : deux Grands Prix d'un même pays portent le même drapeau, sinon le repère se perd. Les deux slugs restent distincts — deux tracés, deux dates.

---

*Limite de la planche, à connaître.* `assets/flags.svg` est un dessin **stylisé**, pas une reproduction officielle : la Malaisie y porte sept bandes et non quatorze, la bannière étoilée treize étoiles et non cinquante, et la sphère céleste brésilienne n'a ni étoiles ni devise. C'est la planche du projet, elle est extraite telle quelle et rien n'y est ajouté — chaque drapeau reste parfaitement reconnaissable à la taille où il est servi (180 à 280px de haut), ce qu'un aperçu rendu à 358 × 180px confirme.

*`assets/flags.svg` est copié dans `frontend/public/flags.svg`*, comme demandé. **Il n'est utilisé par aucun écran** : les drapeaux partent avec le bundle en SVG inline, précisément pour n'ajouter aucun aller-retour réseau avant le premier affichage. La copie sert de référence à une ré-extraction et coûte 30 Ko au précache du service worker (17 entrées au lieu de 16). **La retirer est sans effet sur l'application** si ce poids n'est pas souhaité.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** Un fond de drapeau ne change pas d'état sous les yeux du joueur : il n'y a rien à accompagner, et le skill Transitions.dev n'a pas de correspondance pour une surface statique. Les quatre blocs conservent celles qu'ils portaient — *texts reveal* (18) pour leur entrée, *text states swap* (04) pour les libellés qui changent, *skeleton loader* (14) pour l'attente.

*Apport d'`/apple-design`* — les six drapeaux sont `aria-hidden` et `focusable="false"`, le nom du Grand Prix étant écrit juste à côté : un lecteur d'écran n'a rien à annoncer d'un fond, et un SVG focusable ajouterait six arrêts de tabulation muets sur le seul écran de calendrier. `pointer-events: none` les tient hors du chemin du bouton d'action. La règle de vibrance du §12 continue de s'appliquer telle quelle : sur les six drapeaux voilés, l'encre secondaire est en blanc plein et graisse 500, jamais en gris translucide.

*Vérifié* — modules chargés par le chargeur SSR de Vite, contrastes recalculés sur les treize fonds, rendu hors navigateur (`react-dom/server`) : **tous les contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Fragments | 6 fragments, les six slugs attendus ; `viewBox` à quatre nombres ; **une seule géométrie par forme** ; couleurs toutes en `#RRGGBB` majuscules ; **aucune classe `cls-N` de la planche ne subsiste**, aucune forme `fill: none` |
| Table | les sept slugs en `type: "svg"` avec un fragment existant ; **toute teinte peinte par le SVG est déclarée dans `couleurs`**, vérifié forme par forme ; `base` prise dans le dessin ; **plus aucun `type: "complexe"`** ; les cinq drapeaux CSS intacts et sans fragment |
| Couverture | les douze Grands Prix du calendrier ont un drapeau ; `slugCircuit(nom)` retrouve les douze slugs ; clé héritée d'`Object` → `false` |
| **Contraste** | **blanc plein ≥ 3:1 sur les douze drapeaux et sur le repli**, pire cas 3,11:1 (Espagne), 3,36:1 sur les drapeaux dessinés à bande blanche ; **États-Unis et Brésil reçoivent bien 0,45 là où ils n'avaient rien**, sans qu'aucune valeur soit écrite à la main ; repli bordeaux inchangé (0,00 et 6,81:1) |
| Rendu isolé | les six se rendent ; `preserveAspectRatio="xMidYMid slice"`, `width`/`height` à 100 %, posés en `absolute inset-0`, décoratifs ; **le compte de formes rendues égale le compte de la table** ; slug sans fragment → **rien du tout** ; repli → aucun drapeau |
| **Ordre des calques** | **drapeau → lueur → voile → surcouche → contenu**, vérifié par position dans le DOM ; voile rendu à l'opacité calculée (0,45) ; aplat `base` peint dessous ; aucun repli bordeaux sur un pays connu |
| Non-régression | GP hors table → repli bordeaux, aucun voile, carte quand même complète ; **Pays-Bas toujours en `linear-gradient`, sans aucun drapeau dessiné** ; `bandeTitre` conservée pour les Pays-Bas et l'Espagne (centre 50), `null` pour les sept slugs dessinés |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique », sur les trois cartes rendues |
| Aperçu rendu à 358 × 180px, voile et surcouche compris | les six drapeaux **reconnaissables**, chacun à sa vraie forme, cadrage juste, aucun vide ni coupe ; l'aigle mexicain, la sphère brésilienne, le croissant malaisien et la dentelure qatarie lisibles |
| `npm run build` | passe, version `0.24.0` dans le bundle |

---

**Suppression du test Liquid Glass — retour à la barre de navigation standard** (version `0.25.0`)

Le test visuel de la version `0.23.0` **n'est pas conservé**. La barre de navigation basse revient à son état de la version `0.22.0` : matériau translucide `materiau-chrome`, `shadow-flottant`, et les quatre icônes SVG custom tirées de `assets/logo-02.svg`. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x`, `0.18.x` et `0.20.0`).

*Ce qui est retiré* — les trois fichiers de la librairie (`frontend/public/{container,button,glass.css}`), le `<link>` et les trois `<script>` d'`index.html` (html2canvas par CDN, `container.js`, `button.js`), et tout ce que `NavBarre.jsx` portait sous le commentaire `TEST Liquid Glass` : les imports de `useEffect`/`useRef`/`useState`, `classesVerre`, `PASTILLE`, `demonter`, `construire`, l'effet, la variable `visible`, le `ref`, le ternaire du `className`, le `<span>` créneau et le `relative` de l'icône.

***Le `git revert` annoncé à la version `0.23.0` n'était plus la bonne manœuvre***, et c'est le seul point de méthode à retenir. Le commit du test n'était plus en tête : la version `0.24.0` (drapeaux SVG) avait atterri par-dessus, et les deux commits touchent **les deux mêmes fichiers** — `CLAUDE.md` et `frontend/package.json`. Un `git revert` s'y serait arrêté en conflit, et le résoudre à la main aurait risqué d'emporter la version `0.24.0` avec le test. La restauration est donc **ciblée** : `git checkout <commit-du-test>^ -- frontend/src/composants/NavBarre.jsx frontend/index.html`, suppression des trois fichiers, puis reprise à la main de la version et de ce fichier. Vérifié : la version `0.24.0` ne touchait ni `NavBarre.jsx`, ni `index.html`, ni les trois fichiers de `public/` — le découpage était donc sans recouvrement.

*Deux points restent vrais de la librairie, et ils valent d'être gardés* si l'effet est retenté un jour — ils ont coûté du temps à trouver et ne se lisent pas dans le code :

1. **`Container` et `Button` ne sont pas sur `window`.** Ce sont des déclarations `class` au premier niveau d'un script classique : elles créent une liaison dans l'environnement **lexical** global, jamais une propriété de l'objet global — seuls `var` et les déclarations de fonction font cette dernière. Un garde écrit `window.Container` est donc faux en permanence, librairie chargée ou non, et le repli se déclenche à chaque fois **sans que rien ne le signale**. La seule lecture sûre est `typeof Container !== "undefined"`, une référence nue levant une `ReferenceError`.
2. **L'ordre d'exécution joue contre l'effet.** Vite hisse le script de module dans le `<head>` ; les scripts de la librairie vivent en fin de `<body>`. Tous étant différés, React rend **avant** que `Container` existe — second chemin vers un repli permanent, indépendant du premier. Il faut attendre `window.load`, seul signal qui suit l'exécution de tous les scripts différés et qui est émis **même quand l'un d'eux échoue**.

*Trois réserves de la version `0.23.0` tombent avec le test*, et c'est autant de gagné : les replis **`prefers-reduced-transparency` et `prefers-contrast: more`** de la version `0.12.1` s'appliquent de nouveau à la barre, que le verre court-circuitait ; l'app **ne dépend plus d'un CDN** (html2canvas), donc plus de comportement dégradé hors ligne ; et les cinq contextes WebGL vivant en permanence sous une barre fixe disparaissent. La réserve principale, elle, n'a pas été levée et reste la raison de se méfier d'un second essai : `Container.pageSnapshot` est **statique et capturé une seule fois**, la librairie ne rephotographie jamais la page — le verre aurait réfracté l'écran du premier montage, pas celui qu'on regarde.

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** L'échange de couleur des icônes de la version `0.22.0` (`--icon-swap-dur`, `--icon-swap-ease` sur `color` et sur `fill`) est conservé tel quel, avec son repli `prefers-reduced-motion`.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite) : **26 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Restauration | **`materiau-chrome` de retour**, `shadow-flottant`, zone sûre basse, aucune bordure ; **aucune trace de verre, de canvas ni de html2canvas** dans le rendu |
| Structure | quatre onglets, **un seul `aria-current`**, 44px et retour tactile sur chacun, barre nommée pour le lecteur d'écran, les quatre libellés |
| Icônes de la version `0.22.0` | les quatre rendues, **`viewBox` carrée de 74 unités** sur chacune, 28px, décoratives ; actif en `#800111` et inactifs en `#999999`, vérifié écran par écran sur les quatre onglets |
| Résidus | **aucun `<span>` créneau vide**, aucun `ref` orphelin |
| Absences | **rien sans session**, rien sur la vue piste, les cotes ni la création |
| `index.html` généré | **ni `glass.css`, ni `container.js`, ni `button.js`, ni html2canvas** |
| Service worker | précache **de 17 à 14 entrées** — les trois fichiers de la librairie ne sont plus servis |
| `npm run build` | passe, **136 modules**, version `0.25.0` dans le bundle, `materiau-chrome` toujours présent dans le CSS |

---

---

**Refonte de l'écran des cotes — grille à deux colonnes, section favoris, mode d'emploi** (version `0.26.0`)

Le tableau des cotes passe d'une liste de vingt-deux lignes par marché à une **grille de widgets à deux colonnes**, précédée d'une section « MES FAVORIS » et d'un mode d'emploi en trois gestes. **Aucune migration, aucun changement backend** : `backend/app/config.py` reste en `0.14.0`, faire bouger la version rendue par `/health` laisserait croire à un déploiement Railway qui n'a pas eu lieu (même raison qu'aux versions `0.2.2`, `0.5.1`, `0.8.1`, `0.12.x`, `0.14.1`, `0.15.0`, `0.16.x`, `0.18.x` et `0.20.0`).

*Lecture du brief, telle que la pose le skill Taste* — écran-outil d'une PWA iOS, parcouru plusieurs fois par week-end, langage widget de la section 5. Dials : `DESIGN_VARIANCE 5`, `MOTION_INTENSITY 5`, `VISUAL_DENSITY 6`. La variance est basse et c'est délibéré : une composition asymétrique change de sens quand on revient sur le même écran vingt fois, et une grille régulière est ici la réponse juste. La densité, elle, monte — c'est tout l'objet de la grille.

---

***Le nom des pilotes est normalisé avant d'être affiché.***

Unibet n'écrit pas tous ses pilotes de la même façon. La quasi-totalité de la grille arrive en « initiale + nom » (« M.Verstappen », « AK.Antonelli ») ; **Franco Colapinto arrive en nom complet**. Dans une liste il passait ; dans un widget de 173px de large, il fait deux fois la largeur de ses voisins et se fait tronquer.

`formaterPilote` entre dans `frontend/src/lib/format.js`, où vit déjà toute la mise en forme, avec une table de correspondance. **C'est le même mécanisme que les `alias` de `backend/app/calcul/pilotes.py`**, et il est là pour la même raison : ces écarts sont **irréductibles par une règle**. Abréger automatiquement tout libellé à deux mots casserait le marché « Ecurie Vainqueur », où « Red Bull » et « Aston Martin » sont les bonnes réponses. Les cas sont donc listés un par un, et **tout ce qui n'est pas dans la table ressort intact**. La clé est normalisée (minuscules, accents ramenés à la lettre de base, espaces fondus) : Unibet écrit tantôt « Pays Bas » tantôt « Pays-Bas » sur ses Grands Prix, rien ne garantit qu'il soit plus régulier sur ses pilotes.

**Elle est appliquée aux libellés venus des COTES, et à eux seuls** : le tableau des cotes, l'écran de saisie, le récapitulatif, et les pronostics de l'écran de résultats. Les lignes du **classement de course** de ce dernier viennent d'OpenF1 et gardent leur nom complet — les normaliser y donnerait « F.Colapinto » au milieu de « Max VERSTAPPEN », c'est-à-dire l'incohérence qu'on cherche à corriger, remise à l'envers.

---

*La section « MES FAVORIS », en tête d'écran.* C'est le panier du joueur : ce qu'il a mis de côté, et ce dans quoi il choisira ses trois bonus à l'écran suivant. Elle est donc **avant** le catalogue, et non reléguée sous soixante-six widgets.

Sans favori, un message centré dit à quoi sert la section. Avec, une **rangée de pastilles qui défile à l'horizontale**, calée sur les pastilles (`snap-x`) : un doigt qui la pousse la laisse sur une pastille entière, jamais coupée en deux — c'est ce qui la distingue d'un débordement accidentel. Chaque pastille porte le nom, les points et une croix de retrait.

**Trois décisions de contraste, toutes mesurées, toutes documentées dans le code :**

1. **Les points d'une pastille sont un aplat ambre à encre foncée, jamais du texte ambre.** `#E8A020` écrit sur le blanc de la pastille ne vaut que **2,2:1** ; le même ambre en aplat avec l'encre `#1A1A1A` monte à **7,9:1**. C'est le même arbitrage qu'aux versions `0.12.0`, `0.17.0`, `0.19.0` et `0.21.0`, et il donne bien le repère ambre que la demande cherche.
2. **Le libellé de section quitte le gris `texte-doux` du design system.** Sur le beige `#F5F0EB`, `#999999` ne vaut que **2,5:1** : tenable pour une étiquette qu'on ne lit pas, pas pour celle que la demande veut « bien visible ». Le marron `secondaire` le porte à **9,3:1**, sans introduire de couleur nouvelle. Même correction qu'au bandeau de saison en version `0.14.1`.
3. **La croix de retrait fait ses 44px** alors qu'elle n'en occupe que 14 : dans une rangée qui défile sous le pouce, une cible étroite se rate. `IconeCroix` est ajoutée à `composants/Icones.jsx`, deux segments et rien d'autre — à 14px, un tracé plus travaillé ne se lit plus.

La croix passe par **le même chemin que l'étoile du widget** (`basculer`), vue de l'autre bout : deux chemins d'écriture séparés auraient fini par diverger sur la mise à jour optimiste.

---

*Le mode d'emploi.* Trois gestes, dans l'ordre où on les fait, posés à l'endroit exact où l'on passe de « ce que j'ai retenu » à « ce que le bookmaker propose ». Sans lui, rien à l'écran ne dit qu'épingler une cote sert à quelque chose plus tard. Il disparaît une fois les pronostics fermés : il n'y a plus de geste à faire.

**Deux écarts au design system, tous deux demandés explicitement.** La section 5 proscrit les bordures fines : celle-ci est réclamée par la demande, et elle fait un vrai travail — sur un fond ambre très pâle posé sur du beige, c'est le trait qui dit où commence l'encadré. Et `#FDF3E0` est une teinte nouvelle : elle est écrite en **valeur littérale plutôt qu'ajoutée aux jetons du thème**, parce qu'elle ne peint que cet encadré et rien d'autre — un jeton inviterait à la réutiliser ailleurs. Contraste mesuré : `#543925` sur `#FDF3E0` vaut **9,6:1**, et les pastilles numérotées reprennent l'encre foncée sur ambre (**7,9:1**).

---

***La grille de widgets.*** Deux colonnes, 12px de gouttière, 16px de marge latérale — ces derniers viennent d'`ecran`, qui les applique déjà à tout l'écran ; les redéclarer les doublerait.

Chaque widget : surface blanche, **90px de haut**, rayon de 16px, nom du pilote en haut sur une seule ligne, points en bas à gauche, étoile en bas à droite.

**Quatre points de mise en œuvre à ne pas défaire :**

1. **La hauteur est fixe, et c'est ce qui fait la grille.** Deux widgets d'une même rangée doivent finir à la même ligne quel que soit le nom qu'ils portent : une hauteur libre donnerait des rangées en dents de scie dès qu'un pilote a un nom plus long que son voisin. Le nom est donc sur une seule ligne et tronqué au-delà — ce qui est aussi la raison d'être de la normalisation ci-dessus.
2. **`HAUTEUR_WIDGET` est écrite une fois et partagée avec le squelette.** Sans hauteur commune, la grille sauterait de 90px par rangée à l'arrivée des données — le défaut déjà corrigé sur les cartes de championnat en version `0.14.0`.
3. **L'étoile est posée en absolu dans le coin, pas dans le flux.** Sa zone tactile de 44px est plus haute que la ligne des points : dans le flux, elle ferait grandir le widget de 20px pour rien. Elle chevauche le rembourrage, jamais le texte, à qui les points laissent la place.
4. **`--radius-widget: 16px`** entre dans le bloc `@theme`, entre `carte-sm` (18px) et `champ` (14px). C'est la valeur demandée, et elle se tient : une grille de vingt-deux tuiles de 90px ne supporte pas les 18px d'une carte pleine largeur, qui y font des coins mous. L'écart est **borné à ces widgets**, et la règle de forme de l'écran est donc explicite : sections et encadré en `rounded-carte`, widgets en `rounded-widget`, pastilles en pilule.

*Écart assumé sur la typographie, le même qu'aux versions `0.18.0` et `0.20.0`* — les points sont demandés en **graisse 700**, que la section 5 réserve aux numéros de voiture. L'écart est borné à ce seul chiffre, et c'est le nombre qu'on vient lire. Le rouge `#800111` sur le blanc du widget vaut **10,9:1**.

*L'étoile redevient un trait nu.* La version `0.12.0` l'avait posée dans un disque qui virait à l'ambre, parce qu'elle vivait alors au bout d'une ligne de liste où deux nuances d'étoile ne se distinguaient pas. Elle vit maintenant dans le coin d'un widget qui n'appartient qu'à une seule cote : le contraste entre le contour et l'aplat ambre suffit, et un disque de plus dans un widget de 90px mangerait la place du nom.

**Le gris du contour est mesuré, pas choisi.** Le `texte-doux` `#999999` du design system ne vaut que **2,85:1** sur du blanc, sous le plancher de 3:1 exigé d'un élément graphique porteur de sens (WCAG 1.4.11) — et l'étoile est ici le **seul** indicateur de l'état « pas en favori ». Le marron `secondaire` à 60 % le porte à **3,4:1** sans introduire de couleur nouvelle.

---

*Les en-têtes de marché.* Ils restent **collants** (`section-collante`, version `0.13.0`) et gardent leur couleur : rouge pour Vainqueur, bleu ardoise pour Podium, vert sauge pour Écurie Vainqueur, et les trois teintes restantes à tour de rôle pour les marchés que le scraper découvre — **jamais celle d'un marché du noyau**, ce qui garde le repère quoi qu'Unibet ouvre. Le libellé affiché est celui du bookmaker, jamais un slug reconstitué.

Ils gagnent une **pastille blanche** portant le nombre de favoris épinglés dans ce marché, et deux points la gouvernent :

1. **Elle est toujours rendue, y compris à zéro.** Une pastille qui apparaîtrait au premier favori ferait sauter un en-tête collant sous le doigt qui vient d'épingler.
2. **Son encre est calculée**, par `encreSurBlanc` (ajoutée à `lib/couleurs.js`, à côté d'`encreSurAplat`). Le chiffre doit porter la couleur du marché — c'est ce qui fait qu'il appartient visiblement à sa section — mais **deux des six teintes ne tiennent pas sur du blanc** : l'ambre à 2,2:1 et le terracotta à 4,1:1, tous deux sous le plancher AA d'un texte ordinaire. Elles retombent sur l'encre du design system ; les quatre autres gardent la leur, du 4,9:1 du vert sauge au 10,9:1 du bordeaux. Le seuil retenu est **4,5:1 et non 3:1** : ce chiffre est du petit texte, pas un grand titre. Un aplat ajouté demain reçoit la bonne réponse sans que personne n'ait à refaire le calcul.

---

*Mouvement* — **aucune transition nouvelle, aucun jeton nouveau.** L'écran réutilise celles déjà installées : *icon swap* (09) pour l'étoile, *texts reveal* (18) pour l'entrée des blocs, *skeleton loader and reveal* (14) pour l'attente, *text states swap* (04) pour le libellé du bouton, et **_number pop-in_ (02)** pour le compteur de la pastille — un chiffre qui change sous le doigt qui vient d'épingler est exactement le cas que ce snippet couvre, et c'est du mouvement motivé au sens du skill Taste (retour d'action). Un jeton de plus aurait été un jeton à maintenir sans rien gagner.

*Apport d'`/apple-design`* — zone tactile de 44px sur l'étoile et sur chaque croix de retrait, retour tactile à l'appui partout ; l'en-tête collant répond au « où suis-je » du §16 sur un écran qui empile désormais soixante-six widgets ; la pastille de compteur est nommée pour le lecteur d'écran (`sr-only`) là où l'icône seule ne dirait rien ; la lumière spéculaire du §12 est conservée sur les aplats de couleur ; et le squelette suit la silhouette réelle, hauteur de widget comprise (§7, cohérence spatiale).

*Signalé plutôt que tranché seul, comme le demande la section 5* : le skill Taste recommande une bibliothèque d'icônes tierce et proscrit les SVG écrits à la main. C'est le point où le CLAUDE.md gagne, `composants/Icones.jsx` étant tiré des maquettes depuis l'étape 2 — même arbitrage qu'aux versions `0.12.0` et `0.17.0`.

*Vérifié* — rendu hors navigateur (`react-dom/server` via le chargeur SSR de Vite, cache localStorage pré-rempli) : **89 contrôles passent**.

| Contrôle | Résultat |
|---|---|
| Normalisation des noms | « Franco Colapinto » → « F.Colapinto », **insensible à la casse et aux espaces** ; les autres pilotes ressortent intacts ; **« Red Bull » n'est pas abrégé** ; `null` et chaîne vide traversent sans lever |
| Points | 280 découpé en valeur + unité, `null` → retirée **sans valeur inventée**, `formaterPoints` inchangé |
| **Encre du compteur, mesurée sur les six aplats** | **≥ 4,5:1 partout** ; l'ambre et le terracotta retombent sur l'encre du design system, le vert sauge garde la sienne ; **l'ambre en encre échouerait à 2,2:1** |
| Contrastes | étoile au repos **3,42:1** (et `#999999` prouvé à 2,85:1, sous le seuil) ; points rouges 10,88:1 ; encadré 9,59:1 ; pastille ambre 7,86:1 ; libellé de section 9,32:1 (et `texte-doux` prouvé à 2,52:1 sur le beige) |
| Grille | deux colonnes, gouttière de 12px, **sept widgets à 90px exactement**, rayon propre, surface blanche et ombre ; nom sur une ligne tronquée ; points en rouge graisse 700 à 18px avec leur suffixe ; **cote retirée sans montant inventé** ; une étoile par cote, 44px chacune, contour et aplat aux bonnes couleurs |
| Colapinto | « F.Colapinto » affiché, **« Franco Colapinto » absent du rendu** |
| Favoris, vide | titre rendu, **libellé en marron et non en gris**, message explicatif exact, centré, **aucun compteur à zéro** |
| Favoris, rempli | rangée calée sur les pastilles, deux pastilles, nom normalisé, **points en aplat ambre à encre foncée**, bouton de retrait nommé, 44px, compteur « 2 cotes » accordé, message d'invitation retiré |
| Encadré | liste ordonnée, fond `#FDF3E0`, bordure ambre, texte marron, **les trois étapes au mot près**, trois pastilles numérotées à encre foncée |
| En-têtes | **quatre en-têtes collants**, les trois couleurs du noyau, **teinte de repli sur le marché découvert**, libellé du bookmaker servi tel quel, pastille blanche, compteur animé et nommé, **compteur à 2 dans le marché Vainqueur**, lumière spéculaire |
| GP fermé | message de fermeture, **plus aucune étoile, plus de mode d'emploi**, widgets toujours lisibles, bouton « Voir mes pronos » |
| États | aucun marché → message et **ni grille ni favoris** ; squelette à la silhouette de la grille, **huit widgets à la hauteur réelle**, en-têtes gardant leur aplat, silhouettes de pastilles, **aucun état inventé** |
| Règles permanentes | **aucune cote brute « ×N »**, ni « ligue », ni « historique », ni tiret cadratin, sur les cinq rendus ; barre collée et entrée échelonnée conservées |
| `npm run build` | passe, 136 modules ; `--radius-widget`, `#FDF3E0`, `.border-accent`, `text-secondaire/60` et les quatre encres de marché bien générés ; version `0.26.0` dans le bundle |

### Bugs connus

*(Aucun.)*

### Reste à faire

**Les seize maquettes sont codées, et la barre de navigation basse avec elles.** L'étape 9 a livré les deux derniers écrans (11 et 15), les squelettes de chargement et la gestion d'erreurs ; l'étape 10 a posé la barre à quatre onglets, dernier écart de structure par rapport aux maquettes. Ce qui reste de la section 7 tient en un point : **les tests sur iPhone réel**, jamais faits — le rendu n'a été validé qu'en navigateur de bureau et par rendu hors navigateur.

**Migrations à appliquer** — cette liste est à revérifier. Au cours de la version `0.5.1`, une lecture partie par erreur vers le **vrai** projet Supabase (doublure de test mal branchée) a rendu une ligne réelle de `public.grands_prix` : « GP Pays Bas », `2026-08-23T13:00:00+00:00`, statut `a_venir` — exactement ce que le scraper de l'étape 4 avait produit en local. **La migration 3 est donc appliquée et le scraper a bel et bien écrit en base**, ce qui contredit la mention ci-dessous. L'état des autres n'a pas été observé. À vérifier dans le SQL Editor avant de rejouer quoi que ce soit — les onze migrations sont idempotentes, les rejouer ne casse rien.

Ordre d'application, si l'une manque :
1. `supabase/migrations/20260809191018_profils_pseudo_unique.sql` — sans elle, aucun pseudo n'est unique et la liste des membres affiche « Pilote » partout.
2. `supabase/migrations/20260810163435_championnats.sql` — sans elle, toutes les routes `/championnats` échouent.
3. `supabase/migrations/20260813174500_grands_prix_cotes.sql` — sans elle, le scraper découvre et lit correctement les cotes chez Unibet mais échoue à l'écriture, et les routes `/scraper/cotes` et `/grands-prix/{id}/cotes` répondent `422` en portant `42P01`.
4. `supabase/migrations/20260813182331_createur_nullable_championnat_vide.sql` — sans elle, supprimer un compte ayant créé un championnat échoue par contrainte de clé étrangère, et un championnat quitté par son dernier membre reste en base. **Elle suppose la 2 déjà appliquée** : elle modifie `public.championnats`, elle ne la crée pas.
5. `supabase/migrations/20260813183636_favoris_pronostics.sql` — sans elle, aucun écran de l'étape 5 ne fonctionne, et **`DELETE /championnats/{id}/quitter` échoue aussi** : il appelle désormais `quitter_championnat`. **Elle suppose les 2, 3 et 4 déjà appliquées** : elle référence `membres_championnat`, `grands_prix`, `cotes` et réutilise `est_membre` et `marquer_modification`.
6. `supabase/migrations/20260813205200_resultats_points.sql` — sans elle, aucun point n'est jamais attribué : le job de résultats échoue en portant `42P01`, `GET /grands-prix/{id}/resultats` aussi, et `POST /jobs/resultats/{id}` de même. **Elle suppose les 3 et 5 déjà appliquées** : elle modifie `pronostics` et `pronostic_podium`, référence `grands_prix`, et remplace `pronostics_du_joueur`.
7. `supabase/migrations/20260814103000_classement_championnat.sql` — sans elle, `GET /championnats/{id}/classement` répond `422` en portant `42P01`, et les deux écrans de l'étape 7 restent vides : la vue liste retombe sur la liste des membres sans points, la vue piste n'affiche aucune voiture. **Elle suppose les 2, 5 et 6 déjà appliquées** : elle lit `membres_championnat`, `profils` et `pronostics.points_gagnes`. Elle ne crée aucune table.
8. `supabase/migrations/20260814162200_profil_voiture_stats.sql` — sans elle, aucune voiture n'est personnalisable : `PATCH /profils/moi` et `GET /profils/{id}` répondent `422` en portant `42703` (colonne absente), `GET /profils/{id}/stats` `42883` (fonction absente), et le classement ne sert plus de couleurs — les écrans retombent alors sur les défauts, sans planter. **Elle suppose les 1, 5, 6 et 7 déjà appliquées** : elle altère `public.profils`, lit `pronostics.points_gagnes` et `cotes`, et **remplace** `classement_du_championnat`. Elle ne crée aucune table. **Attention à l'ordre si une migration antérieure est rejouée après elle** : la 1 et la 7 déclarent respectivement les mêmes politiques RLS de `profils` et la même fonction de classement, dans leur version d'avant. Rejouer la 1 est sans effet (textes identiques) ; **rejouer la 7 après la 8 retirerait les trois champs de voiture du classement**.
9. `supabase/migrations/20260814183000_livree_automatique.sql` — sans elle, tous les profils naissent avec les mêmes couleurs (`#800111` / `#FFFFFF`) et la vue piste d'un championnat neuf montre N voitures identiques. Rien ne plante : c'est un défaut de lisibilité, pas une panne. **Elle suppose les 1 et 8 déjà appliquées** : elle remplace `public.gerer_nouvel_utilisateur` (migration 1) et écrit `profils.couleur1` / `couleur2` (migration 8). Elle ne crée aucune table. **Attention à l'ordre, vérifié en test** : **rejouer la 1 après la 9 restaure l'ancien trigger** et les inscriptions suivantes repartent aux couleurs par défaut. Si la 1 est rejouée pour une raison quelconque, rejouer la 9 derrière — la reprise de l'existant, elle, ne retouchera personne.

10. `supabase/migrations/20260814213000_calendrier_championnat.sql` — sans elle, `GET /championnats/{id}/calendrier` répond `422` en portant `42883` (fonction absente) et l'écran de calendrier (maquette 15) reste vide ; le tableau des résultats (maquette 11), lui, s'affiche mais sans les voitures des membres, qui retombent sur les défauts. **Elle suppose les 3, 5, 6 et 8 déjà appliquées** : elle lit `grands_prix`, `cotes`, `resultats_gp`, `pronostics.points_gagnes` et `profils.couleur1` / `couleur2` / `numero`, et **remplace** `public.pronostics_du_championnat` (migration 5). Elle ne crée aucune table. **Attention à l'ordre, vérifié en test** : **rejouer la 5 après la 10 retire les voitures du tableau des résultats**. Si la 5 est rejouée pour une raison quelconque, rejouer la 10 derrière.

11. `supabase/migrations/20260816120000_date_qualifications.sql` — sans elle, `POST /scraper/declencher` et le job automatique répondent `42703` (colonne absente) à l'écriture d'un Grand Prix : **le scraper ne peut plus rien enregistrer du tout**, ni GP ni cotes. Le job horaire, lui, échoue à sa lecture et le journalise à chaque tour. **Elle suppose la 3 déjà appliquée** : elle altère `public.grands_prix`. Elle ne crée aucune table et **ne remplace aucune fonction** — c'est la seule migration depuis la 7 qui ne puisse pas entrer en conflit d'ordre avec une migration antérieure rejouée par-dessus.

**Variables d'environnement du backend** — à définir sur Railway :
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`. Sans elles, `/championnats` et `POST /scraper/declencher` répondent `503` avec un message explicite, et **le scheduler de l'étape 6 ne démarre pas du tout** (il le journalise au démarrage). La clé de service ne doit jamais être exposée au frontend ni committée.
- **`ADMIN_SECRET`** — chaîne libre, choisie par toi, à garder secrète. C'est la valeur attendue dans l'en-tête `X-Admin-Secret` de `POST /scraper/declencher` **et de `POST /jobs/resultats/{gp_id}`**. **Tant qu'elle n'est pas définie, les deux routes refusent tout le monde** (`503`) : une variable absente ne doit jamais valoir accès libre. Déclenchement type :
  ```
  # Depuis l'étape 11, ce déclenchement FIGE les cotes des GP scrapés avec
  # succès (statut `cotes_figees`), comme le fait le job automatique.
  curl -X POST https://<railway>/scraper/declencher -H "X-Admin-Secret: <valeur>"

  # Essai AVANT les qualifications : scrape sans figer. Sans ce paramètre, les
  # cotes sont arrêtées pour de bon et il faut un `update` à la main pour les
  # débloquer.
  curl -X POST "https://<railway>/scraper/declencher?figer=false" \
    -H "X-Admin-Secret: <valeur>"

  # Étape 6 — force le traitement d'un GP : résultats, points, clôture.
  # Synchrone : la réponse porte le compte rendu, dont les pronostics restés
  # sans points. Idempotent, on peut le rejouer sans risque.
  curl -X POST https://<railway>/jobs/resultats/<gp_id> -H "X-Admin-Secret: <valeur>"

  # Version 0.6.1 — banc d'essai : injecte un classement fictif et rend le
  # verdict du calcul sur les vrais pronostics en base. N'ÉCRIT RIEN.
  # À utiliser AVANT la course pour valider les marchés jamais confrontés.
  curl -X POST https://<railway>/jobs/resultats/<gp_id>/test \
    -H "X-Admin-Secret: <valeur>" -H "Content-Type: application/json" \
    -d '[{"driver_number":12,"position":1,"dnf":false,"dns":false,
          "dsq":false,"points":25,"number_of_laps":72,"gap_to_leader":0}]'
  ```

Points non couverts, à traiter le moment venu :
- **Décompte des Grands Prix restants figé à 12 — sur l'accueil uniquement, et la réponse existe désormais.** Depuis la version `0.14.1`, le bandeau de bas d'écran (`GP_RESTANTS` dans `frontend/src/ecrans/Accueil.jsx`) affiche une constante, parce que `public.grands_prix` ne contient que le Grand Prix suivant. **La version `0.20.0` a créé la liste qui manquait** : `frontend/src/lib/calendrier2026.js` porte les douze Grands Prix de la saison, et l'onglet Calendrier en tire déjà un décompte qui **exclut les courses terminées**. Le bandeau de l'accueil, lui, n'a pas été rebranché — c'est hors du périmètre de cette version, et c'est désormais quelques lignes : compter `GP_2026` filtré par `etatDuGpSaison`, exactement comme le fait `CalendrierGlobal`. **À faire, sans quoi les deux écrans se contrediront dès la première course courue** — l'accueil dira « 12 restants » quand le calendrier en montrera 11. `chargerGrandsPrixRestants` (`lib/pronostics.js`) reste en place mais n'est plus la bonne réponse : elle compte les lignes en base, c'est-à-dire une seule course.
- **La liste statique des Grands Prix est à mettre à jour chaque saison** — `frontend/src/lib/calendrier2026.js`, au même titre que `backend/app/calcul/pilotes.py`. Elle se relit sur le calendrier officiel de la FIA. Les `slug` doivent rester ceux de `slugCircuit` : un slug inconnu fait retomber la carte sur le bordeaux de la marque, sans tracé. Ajouter les Grands Prix du début de saison demande aussi leur drapeau (`DrapeauxGP.jsx`) et leur tracé (`TracesCircuits.jsx`), les trois tables devant porter les mêmes clés.
- **Scraper exercé contre le vrai Supabase** — la ligne réelle observée en version `0.5.1` (voir ci-dessus) montre que l'écriture a eu lieu au moins une fois. Reste à vérifier le contenu de `public.cotes` pour ce GP, et le comportement du scraper sur un GP déjà figé.
- **Programmation automatique du scraping, et figeage des cotes** — **faite à l'étape 11** (`app/jobs/scraper.py`, second emploi APScheduler dans le `lifespan`). Le scraping se déclenche tout seul 2h après les qualifications, et le statut `cotes_figees` est enfin posé par du code. Trois points restent à surveiller : **(1)** Unibet n'exposait aucun événement de qualification au 16 août 2026, c'est donc le repli `date_course - 22h` qui s'applique — **relire les logs du samedi du premier vrai Grand Prix** pour voir si une vraie heure de qualifications est apparue (chercher « qualifications annoncées par Unibet » ou « aucune épreuve de qualification trouvée ») ; **(2)** le job de résultats continue de surveiller les GP restés `a_venir`, ce qui reste le bon filet si un figeage est manqué ; **(3)** `POST /scraper/declencher` fige désormais lui aussi — utiliser `?figer=false` pour un essai avant les qualifications, sans quoi les cotes sont arrêtées pour de bon et il faut un `update` à la main pour les débloquer.
- **Tableau des cotes quand les marchés se multiplient** — depuis la refonte visuelle (`0.12.0`), les marchés sont **empilés** en sections colorées au lieu d'être derrière des onglets. La grille à deux colonnes de la version `0.26.0` **divise par deux** la longueur de chaque section, et les en-têtes collants disent en permanence où l'on est. Après les qualifications, le noyau complet de la section 3.1 (top 6, top 10, duels…) donnera malgré tout un écran très long, à onze rangées par marché. `frontend/src/composants/Onglets.jsx` et sa transition *tabs sliding* sont **restés en place, simplement non montés** : c'est la réponse déjà écrite et vérifiée le jour où l'empilement devient impraticable.
- **Marchés disponibles à J-10** — au moment du développement, Unibet n'exposait que 3 marchés pour le GP Pays-Bas (vainqueur, podium, écurie gagnante). Le noyau annoncé en section 3.1 (top 6, top 10, duels…) n'apparaîtra qu'à l'approche de la course. Le scraper les découvre dynamiquement, donc rien à changer — mais **le jeu de marchés réellement obtenu après les qualifications reste à observer**. C'est le point de vigilance principal de l'étape 6 : `app/calcul/points.py` reconnaît neuf familles de marchés, mais **seules trois ont été confrontées à de vrais libellés Unibet**. Les autres (top N, abandon, safety car, drapeau rouge, meilleur tour) sont écrites d'après la section 4.4. Un marché non reconnu ne fait aucun dégât — le pronostic reste à `NULL` et les logs le disent — mais il faut **relire les avertissements `[points] … laissé(s) sans points` après le premier vrai GP** et compléter `validateur()` en conséquence, puis rejouer `POST /jobs/resultats/{gp_id}`. **Depuis la version `0.6.1`, l'attente n'est plus obligatoire** : `POST /jobs/resultats/{gp_id}/test` confronte le calcul aux vrais pronostics en base sur un classement fictif, sans rien écrire. Dès que les marchés complets apparaissent chez Unibet (après les qualifications), un essai dit immédiatement lesquels restent non reconnus.
- **Duels entre pilotes, premier abandon, marge de victoire, classement exact** — annoncés en section 4.4, **non implémentés**. Ils demandent chacun une règle explicite (égalités, pilote classé contre pilote abandonné) que le CLAUDE.md pose mais que rien ne code encore. Les cas d'égalité du « premier abandon » sont le point à trancher en premier. En l'état ils tombent dans le filet « marché non reconnu ».
- **Écran de résultats (maquette 11) et calendrier (maquette 15)** — **faits à l'étape 9.** Les seize maquettes du projet sont désormais codées.
- **Barre de navigation basse** — **faite à l'étape 10.** Les deux points qui restaient à trancher le sont : l'onglet Calendrier ouvre un **écran global** (`/calendrier`) qui liste les championnats du membre avec le Grand Prix qui les attend, plutôt que d'en choisir un d'office ; et la **vue piste n'en porte pas**, comme prévu depuis l'étape 7. Ce qui reste ouvert tient en une ligne de `frontend/src/lib/navigation.js` : le **calendrier d'un championnat** et les **Grands Prix d'un membre** n'ont pas la barre, la liste exhaustive de la demande ne les mentionnant pas, alors qu'iOS la garde sur toute la pile d'un onglet. Les y ajouter, c'est une entrée de plus dans `CHEMINS_AVEC_BARRE` et rien d'autre.
- **Voitures identiques tant que personne ne personnalise** — **corrigé en version `0.8.1`** : chaque profil naît désormais avec une livrée distincte, attribuée par ordre d'inscription global dans `gerer_nouvel_utilisateur`. Reste un cas non couvert, et il est assumé : les livrées **rebouclent tous les dix membres**, donc un championnat de plus de dix membres dont personne n'a personnalisé sa voiture verra le 11ᵉ porter les couleurs du 1ᵉʳ. Le cycle est global (ordre d'inscription sur toute l'application) et non par championnat — le rendre unique par championnat est impossible en l'état, une voiture étant identique dans tous les championnats de son propriétaire (section 5), exactement le même raisonnement que pour le numéro ci-dessous.
- **Numéro de voiture unique par championnat** — l'unicité est aujourd'hui purement **indicative** : l'écran de profil avertit que le numéro est déjà porté, et laisse enregistrer. C'est un choix, pas un oubli — une voiture est identique dans tous les championnats de son propriétaire (section 5), et rendre le numéro bloquant dans l'un le rendrait impossible à choisir dans un autre. Si le blocage devient souhaitable, il ne peut pas s'écrire en contrainte de base : il faudrait le porter par `PATCH /profils/moi`, et décider quoi faire d'un conflit qui apparaît **après coup**, quand quelqu'un rejoint un championnat où le numéro est déjà pris.
- **Parcours des championnats exercé contre le vrai Supabase** — le backend a été validé contre une doublure en mémoire et la migration contre un PostgreSQL jetable, mais les deux n'ont jamais tourné ensemble contre le vrai projet.
- **Messages techniques des routes `/championnats`, `/scraper` et `/grands-prix`** — **corrigé à l'étape 9.** `journal.echec_lisible` rend désormais un message français et garde message, code PostgreSQL, statut HTTP et trace complète dans les seuls logs Railway. `lib/api.js` filtre par-dessus ce qui viendrait d'ailleurs (page d'erreur Railway, proxy). **Conséquence à connaître pour le diagnostic** : une panne ne se lit plus à l'écran, il faut ouvrir les logs Railway. Le contexte affiché (« Chargement du classement ») dit au moins quelle opération a échoué.
- **Effacement des pronostics au départ d'un championnat** — tranché à l'étape 5 : ils ne sont effacés que si le joueur ne fait plus partie d'aucun championnat, parce qu'un pronostic compte dans tous ses championnats à la fois. **Si le comportement voulu est autre**, c'est `public.quitter_championnat` qu'il faut reprendre, et rien d'autre.
- **Pronostics d'un GP annulé ou reporté** — la règle 4.7 veut que les pronostics enregistrés soient **effacés**. Rien ne le fait aujourd'hui : le statut `annule` n'existe pas dans la contrainte `check` de `grands_prix`, et aucun code ne l'applique. L'étape 6 apporte un demi-pas : **OpenF1 expose `is_cancelled` sur ses sessions**, et `session_de_course()` le **journalise** quand il vaut vrai — le cas se verra dans les logs au lieu de passer pour une course sans résultat. Il reste à ajouter le statut, l'effacement, et la reprise après report.
- **Marchés obligatoires liés au nom Unibet** — le vainqueur et le podium sont reconnus par les slugs `vainqueur` et `podium`, en dur à **trois** endroits depuis l'étape 6 : `backend/app/api/routes/pronostics.py`, `backend/app/calcul/points.py` et `frontend/src/lib/pronostics.js`. Si Unibet renomme un de ces marchés, la saisie s'arrête proprement en le disant, mais **les trois constantes doivent être corrigées ensemble**.
- **Schedulers et instances multiples** — les **deux** jobs (résultats, étape 6 ; scraper, étape 11) supposent **un seul processus**. C'est le cas sur le plan gratuit de Railway. Passer à plusieurs instances ferait tourner deux schedulers de chaque : la base empêche la double attribution des points, mais **ni les appels OpenF1 ni les appels Unibet en double**. Ajouter alors un `pg_try_advisory_lock` dans les deux `surveiller()`, ou sortir les jobs dans un worker dédié.
- **Test sur iPhone réel** — toujours pas fait, et c'est ce qui reste de plus important. Le rendu n'a été validé qu'en navigateur de bureau et par rendu hors navigateur. **Un point nouveau depuis la passe de finition (`0.12.1`)** : les deux **matériaux translucides** (`backdrop-filter`) — barre de navigation et barre d'action collée. Safari iOS les compose sur le GPU, mais c'est le genre d'effet qui coûte à chaque image de défilement : regarder que la page ne saccade pas sous la barre, et que le flou ne laisse pas de traînée quand la barre d'adresse se rétracte. Vérifier aussi le repli `prefers-reduced-transparency` en activant « Réduire la transparence » dans les réglages d'accessibilité d'iOS.

**Trois points depuis les versions `0.20.0` et `0.21.0`**, tous sur l'onglet Calendrier. **La longueur de l'écran** : la refonte de la `0.21.0` ramène la carte de ~300px à **200px**, ce qui divise le défilement par une fois et demie, mais douze cartes font toujours près de trois écrans sans en-tête collant pour dire où l'on est — c'est le premier point à juger au pouce, et le levier est `HAUTEUR_CARTE` (`frontend/src/composants/CarteGpSaison.jsx`), que le tracé, la bande d'action et le squelette suivent tout seuls. **L'entrée dans la saison** : l'écran s'ouvre sur le premier Grand Prix de la liste, y compris quand il est terminé ; faire défiler jusqu'au prochain à jouer serait plus juste, mais demande un `scrollIntoView` à l'arrivée, donc un choix explicite sur le comportement du retour. Et **le décompte de l'en-tête**, qui contredira le bandeau de l'accueil dès la première course courue tant que celui-ci n'est pas rebranché (voir plus haut).

**Trois points depuis la `0.24.0` — les six drapeaux dessinés.** Malaisie, États-Unis, Las Vegas, Mexique, Brésil, Qatar et Abu Dhabi portent désormais leur vrai dessin, extrait de `assets/flags.svg`. Les contrastes sont mesurés et tiennent partout (≥ 3:1, ≥ 4,48:1 surcouche comprise), mais **la reconnaissance d'un drapeau ne se juge qu'à l'œil sur un vrai écran** :

1. **Le voile pèse plus qu'avant sur deux d'entre eux.** Les États-Unis et le Brésil passent de 0,00 et 0,05 à **0,45** — le prix de leurs bandes claires enfin dessinées. Sur ces deux cartes, le drapeau est nettement plus sombre qu'avant, et le blanc s'y lit **gris argent**. C'est inhérent au couple « texte blanc partout » + « bande blanche », relevé dès la version `0.15.0` ; la seule autre issue serait de l'encre foncée sur les bandes claires, ce que la demande d'origine exclut. **À trancher explicitement si le rendu paraît éteint**, pas à corriger en baissant le voile — il est calculé pour le texte.
2. **La planche est stylisée** (sept bandes malaisiennes au lieu de quatorze, treize étoiles américaines au lieu de cinquante, sphère brésilienne sans étoiles). Chaque drapeau reste reconnaissable à 180px, vérifié en aperçu — mais c'est le genre de chose qui se confirme sur un iPhone, pas sur un écran de bureau. Si un drapeau doit gagner en fidélité, c'est **la planche** qu'il faut reprendre, jamais `DrapeauxSVG.jsx`, qui n'en est que le découpage.
3. **Austin et Las Vegas sont désormais rigoureusement identiques** — même fragment, même voile. C'est voulu, ce sont deux courses d'un même pays, mais le tracé de circuit et le nom sont alors les seuls discriminants. Si l'un des deux doit se distinguer, c'est une décision à prendre explicitement.

Point secondaire : `frontend/public/flags.svg` **n'est utilisé par aucun écran** (les drapeaux partent en SVG inline avec le bundle) et coûte 30 Ko au précache du service worker. Le retirer est sans effet sur l'application.

**Un point depuis la `0.21.1` — le piège des règles hors couche.** `.t-stagger-line` et `.t-skel-bar` sont déclarées hors de toute couche Tailwind : **elles battent n'importe quelle classe utilitaire**, quelle que soit sa spécificité. Un `flex`, un `gap` ou un `bg-*` posé sur un élément qui porte l'une de ces classes ne s'applique pas, et rien dans le JSX ne le laisse voir. Le motif à suivre est celui de l'accueil : **le conteneur flex vit à l'intérieur du `Bloc`, jamais sur le `Bloc` lui-même**. Un cas subsiste, sans conséquence visible : `Championnat.jsx` porte un `gap-2.5` mort sur le `Bloc` des deux boutons de confirmation de départ — à reprendre avec le même motif si l'empilement paraît serré sur un appareil réel.

**Deux points propres à la `0.21.0`**, tous deux sur la lisibilité du tracé maintenant qu'il traverse le texte. **Sur les neuf drapeaux à bande claire** (la Malaisie et Abu Dhabi les ont rejoints en version `0.21.2`), le trait blanc à 60 % passe sur une bande ramenée au gris moyen par le voile : mesuré à 2,70:1 pour eux et 2,44:1 au pire (Brésil) — les valeurs n'ont pas bougé depuis la `0.21.0`, seul Las Vegas descend de 5,81 à 3,11:1 en passant du noir au rouge, ce qui reste au-dessus des neuf autres. Lisible, donc, mais discret — s'il paraît fantomatique sur un vrai écran, deux leviers d'une ligne, dans cet ordre : monter le trait de 60 à 70 % de blanc, ou approfondir la surcouche de 15 à 25 % (elle assombrit alors aussi le fond du texte, ce qui ne fait que renforcer sa lisibilité). **Ne pas toucher au voile**, calculé pour le texte. Et **le croisement texte / tracé** : l'ombre portée le rend lisible en rendu statique, mais c'est exactement le genre de détail qui se juge à la lumière du jour, sur les cartes où le tracé passe pile derrière le quantième (Espagne, Azerbaïdjan, Brésil).

**Trois points depuis la version `0.19.0`**, tous sur les cartes du calendrier d'un championnat. **La hauteur des cartes** : 180px de drapeau plus une zone d'informations portent chaque carte à environ 300px, et douze Grands Prix font un écran très long — à juger au pouce, et si c'est trop, c'est `HAUTEUR_DRAPEAU` (`frontend/src/ecrans/Calendrier.jsx`) qu'il faut baisser, le squelette suivra tout seul. **La lisibilité du tracé** sur les drapeaux les plus clairs, mesurée à 2,70:1 au pire (Pays-Bas, Italie, Singapour, Mexique, Qatar) : deux leviers d'une ligne s'il paraît fantomatique — monter le trait de 60 à 70 % de blanc, ou approfondir la surcouche de 15 à 25 % — mais **ne pas toucher au voile**, calculé pour le texte. Et **les cartes pleine largeur** (`pleine-largeur`), à vérifier en paysage sur un iPhone à encoche, où la zone sûre latérale n'est plus nulle.

**Trois points depuis la version `0.18.0`**, tous sur l'écran Récap. **La hauteur du hero** — 280px plus la zone sûre, soit près de 330px sur un iPhone à encoche : c'est la valeur qui donne au titre la place de tomber dans sa bande sans heurter la rangée de retour, mais elle ne se juge qu'au pouce. Si l'écran demande trop de défilement avant la carte de statut, c'est `HAUTEUR_HERO` (`frontend/src/ecrans/RecapPronostics.jsx`) qu'il faut baisser — **et il faut alors revérifier les deux bornes des `clamp`**, calibrées sur cette hauteur ; la simulation du jeu de contrôles les éprouve pour trois zones sûres et deux hauteurs de titre, il suffit de la rejouer. Ensuite : **le calage du titre dans sa bande**, à confronter aux vrais drapeaux — les Pays-Bas sont le cas d'école, l'Azerbaïdjan, Singapour et le Qatar les trois cas où la borne basse rabat le titre hors de sa bande, ce qui est voulu mais se voit. Enfin : **la lisibilité des tuiles sombres** sur la carte beige, et surtout le glissement des unités à T-1h, qui fait passer le premier bloc de « Jours » à « Heures » — un changement d'unité sous les yeux du joueur, à vérifier une fois en conditions réelles.

**Deux points depuis la version `0.17.0`**, tous deux sur l'écran Récap et tous deux liés au hero. **Le bouton de retour n'est plus collant** : il vit dans le hero, qui porte un drapeau qu'une barre translucide ne saurait pas reproduire, et il défile donc avec la page. L'écran tient en quatre blocs et le défilement est court — mais c'est exactement le genre de chose qui se juge au pouce, sur un appareil réel : si sortir de l'écran demande de remonter, la réponse est d'apprendre à `EnTeteEcran` à rendre un fond en `style` plutôt qu'en classe, pas de recoller le hero entier. Ensuite : **le hero coiffe la zone sûre** (`pleine-largeur` + `coiffe-ecran`), donc la couleur du drapeau court derrière la Dynamic Island — à vérifier en portrait **et en paysage** sur un iPhone à encoche, où la zone sûre latérale n'est plus nulle. Point secondaire : le nom du Grand Prix est en `line-clamp-2` et non tronqué sur une ligne, « GP Émirats arabes unis » est le cas à confronter à un iPhone étroit.

**Trois points depuis la version `0.16.0`**, tous sur le bloc GP recomposé, et le premier est le plus important : **la hauteur du bloc**. La bande de 160px le porte à environ 380px, soit plus de la moitié de la hauteur utile d'un iPhone SE — les cartes de championnat passent nettement sous la ligne de flottaison. C'est la conséquence assumée de « le bloc est plus haut qu'actuellement », mais elle ne se juge que sur un appareil réel : si l'accueil demande trop de défilement avant la première carte, c'est `HAUTEUR_TRACE` (`frontend/src/ecrans/Accueil.jsx`) qu'il faut baisser, et le squelette suivra tout seul. Ensuite : **la lisibilité du trait sur les trois fonds les plus faibles** — Brésil 2,44:1, Azerbaïdjan 2,54:1, Espagne 2,55:1 (voir le tableau de la version `0.16.0`). Si le circuit y paraît fantomatique, deux leviers d'une ligne, dans cet ordre de préférence : monter le trait de 60 à 70 % de blanc (`text-white/60` dans la zone 3), ou approfondir la surcouche de 15 à 25 % (`bg-black/15`) — **depuis la version `0.16.1` elle peint tout le bloc et non plus la seule bande**, donc l'approfondir assombrit aussi le fond du texte, ce qui ne fait que renforcer sa lisibilité. Ne pas toucher au voile, calculé lui pour le texte. Enfin : **le nom du Grand Prix reste tronqué** (`truncate`) et il est maintenant centré à 26px — « GP Émirats arabes unis » est le cas à confronter à un iPhone étroit.

**Trois points depuis la version `0.15.0`**, tous liés aux drapeaux du bloc GP, qui ne se jugent qu'à l'œil : **la force du voile** — elle est calculée pour tenir 3:1 et ne doit pas être baissée, mais si un drapeau à bande blanche paraît trop éteint, c'est la seule autre issue qui est à arbitrer (encre foncée sur les bandes claires, ce que la demande excluait) ; **la lisibilité du tracé à 15 % de blanc** sur les fonds les plus clairs, où il peut disparaître sous le voile — le monter à 20 % ne coûte rien à la garantie, le tracé passant sous le voile ; et le **repli `prefers-contrast: more`**, qui approfondit le voile d'un cran et qu'il faut vérifier avec « Augmenter le contraste » activé, en même temps que celui du grain de fond. Point secondaire : le nom du Grand Prix est tronqué (`truncate`) et les libellés d'Unibet peuvent s'allonger (« GP Émirats arabes unis ») — à confronter à un iPhone étroit.

**Deux points depuis la version `0.14.0`**, tous deux liés au grain du fond, qui ne se juge qu'à l'œil sur un écran réel : **l'intensité du grain** — 4 % avec un contraste étiré dans le filtre, c'est le réglage qui devrait donner « du papier légèrement texturé » sans jamais salir le beige ; si le rendu paraît trop faible, monter `opacity` dans le SVG de `--grain-fond` plutôt que la taille de tuile, et si le grain se remarque, la descendre à 0,03 ; et le **coût au défilement** — le motif est une tuile rastérisée mise en cache, il ne devrait rien coûter, mais c'est exactement le genre d'effet qui se juge en faisant défiler une longue liste de cotes sur un vrai iPhone. Vérifier aussi le repli `prefers-contrast: more` (« Augmenter le contraste » dans les réglages d'accessibilité), qui doit rendre le fond parfaitement uni. Point secondaire : les **cartes de 120px** portent maintenant deux fois plus de contenu, à confronter à un pseudo de championnat long sur un iPhone étroit.

**Quatre points depuis la refonte sans restriction (`0.13.0`)**, tous liés au collage et aux matériaux, c'est-à-dire à ce qui ne se vérifie pas au simulateur : l'**en-tête à grand titre rétractable** — regarder que la barre ne saute pas quand la barre d'adresse de Safari se rétracte, que le matériau apparaisse bien au bon moment (la marge de déclenchement est fixée à 64px, à réajuster si la zone sûre d'un modèle la décale), et que le flou d'un élément pleine largeur ne fasse pas saccader le défilement ; les **en-têtes de marché collants** du tableau des cotes, dont le décalage repose sur `--entete-hauteur` = zone sûre + 60px — à confronter à un vrai `env(safe-area-inset-top)` ; l'**en-tête teinté du championnat**, où la couleur de la barre et celle de l'aplat doivent se toucher sans laisser de ligne au premier pixel de défilement ; et les deux **nouvelles barres collées en bas** (cotes et pronostics), à vérifier avec un vrai home indicator. Vérifier aussi le repli `prefers-reduced-transparency` sur l'en-tête, en plus des deux matériaux déjà signalés.

**Trois points depuis la refonte visuelle (`0.12.0`)** : l'**en-tête coloré du championnat**, qui remonte sous la zone sûre haute (`coiffe-ecran`) et dont la couleur doit courir jusque derrière la Dynamic Island sans y pousser de texte ; le **bouton de validation collé en bas** de l'écran de pronostics (`barre-collee`), qui rend lui-même `env(safe-area-inset-bottom)` et annule celui d'`ecran` — c'est exactement le genre de calage qui ne se vérifie qu'avec un vrai home indicator, et il faut aussi regarder qu'il ne saute pas quand la barre d'adresse de Safari se rétracte ; et les **aplats pleine largeur** (`pleine-largeur`), à vérifier en paysage sur un iPhone à encoche, où la zone sûre latérale n'est plus nulle. Point à regarder ensuite, hérité de l'étape 10 : la **barre de navigation basse**, dont la zone sûre (`env(safe-area-inset-bottom)`) et la hauteur réservée (`h-nav`, 58px) n'ont jamais été confrontées à un vrai home indicator — c'est exactement le genre de calage qui ne se vérifie pas au simulateur. Regarder aussi qu'elle **ne bouge pas quand la barre d'adresse de Safari se rétracte**, et que les 44px de chaque onglet tombent bien sous le pouce. Points hérités de l'étape 9 : le **balayage des squelettes** (une animation permanente sur plusieurs blocs à la fois, à surveiller côté fluidité), la **vue piste** dont la hauteur est mesurée et change quand la barre d'adresse de Safari se rétracte, et les **accordéons** de l'écran de résultats, dont le chevron bascule en `scaleY(-1)` précisément parce que l'interpolation de `d:` n'existe pas sous Safari.
- **Parcours d'authentification testé de bout en bout** — le code est en place et compile, mais inscription, confirmation par email, connexion et réinitialisation n'ont pas encore été exercées contre le vrai projet Supabase.
- **Clés OAuth Google et Apple** — à renseigner dans le tableau de bord Supabase. Ajouter aussi les URL de redirection autorisées : `https://mon-petit-podium.vercel.app/accueil`, `.../nouveau-mot-de-passe` et leurs équivalents `http://localhost:5173`. **Les boutons sont masqués depuis la version `0.2.2`** : une fois les clés en place, repasser `OAUTH_ACTIF` à `true` dans `frontend/src/composants/BoutonsOAuth.jsx`.
- **Variables d'environnement de production** — `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` et `VITE_API_URL` **restent à définir côté Vercel** : sans les deux premières, la production affiche l'écran de configuration manquante. Côté Railway, **`ENVIRONMENT=production` reste à ajouter** : le service répond aujourd'hui `environment: development`, ce qui laisse `/docs` accessible publiquement. `FRONTEND_URL` n'est plus bloquante depuis la version `0.1.2` (l'URL Vercel est la valeur par défaut), mais la définir explicitement reste préférable pour garder la configuration lisible sur Railway.

### Décisions validées mais non encore implémentées

- Schéma de base de données — neuf tables existent, et l'étape 8 n'en ajoute aucune : `public.profils` (qui porte désormais la voiture : `couleur1`, `couleur2`, `numero`), `public.championnats`, `public.membres_championnat`, `public.grands_prix`, `public.cotes`, `public.favoris`, `public.pronostics`, `public.pronostic_podium`, `public.resultats_gp`. **Les statistiques d'un membre ne sont pas une table** non plus : elles se calculent à la volée par `public.stats_du_profil(uuid, integer)`, pour la même raison que le classement — une table serait un doublon de `points_gagnes`, à retenir cohérent à chaque attribution. Les points attribués ne sont **pas** une table à part : ils vivent dans la colonne `points_gagnes` de `pronostics` (étape 6). **Le classement cumulé non plus** : tranché à l'étape 7 en faveur du calcul à la volée, par `public.classement_du_championnat(uuid)`. **Le calendrier d'un championnat non plus** : l'étape 9 ajoute `public.calendrier_du_championnat(uuid, uuid, integer)`, qui l'agrège à la volée pour les mêmes raisons — une table serait un troisième doublon de `points_gagnes` à retenir cohérent. Une table de classement serait un doublon de `points_gagnes`, à retenir cohérent à chaque attribution, à chaque départ d'un membre et à chaque rattrapage d'un `NULL`. Les migrations vivent dans `supabase/migrations/`, une par étape, à exécuter à la main dans le SQL Editor.
- Nommage des routes API — la convention est posée par `/championnats` : nom de domaine au pluriel, sous-chemin `/moi` pour ce qui appartient à l'appelant, verbe explicite pour une action qui n'est pas un CRUD (`/rejoindre`, `/{id}/quitter`, `/declencher`). L'étape 5 y ajoute la ressource imbriquée : `/grands-prix/{id}/favoris`, `/grands-prix/{id}/pronostics`. L'étape 6 y ajoute `/grands-prix/{id}/resultats` et, pour les déclenchements d'administration, le préfixe `/jobs/` : `/jobs/resultats/{id}`. L'étape 8 confirme le sous-chemin `/moi` en l'appliquant à une écriture : `PATCH /profils/moi` ne prend **aucun** identifiant, précisément pour qu'on ne puisse pas modifier le profil d'un autre.
- Table statique pilote → nationalité — à créer. Sa place est **`backend/app/calcul/pilotes.py`**, créé en version `0.6.1` : il porte déjà la grille 2026 (numéro, prénom, nom, acronyme, écurie, alias Unibet) et le garde-fou de saison. Ajouter un champ `nationalite` au `dataclass` suffira, sans nouvelle table ni nouveau fichier à maintenir en parallèle.
- **Grille des pilotes à mettre à jour chaque saison** — `backend/app/calcul/pilotes.py` décrit 2026. Une table périmée ne fait pas de dégât silencieux (`alias_unibet()` exige que le nom de famille concorde avec le numéro), mais les alias cessent de s'appliquer et les pronostics concernés restent à `NULL`. Les numéros se relisent sur `/drivers` d'OpenF1, les libellés dans `public.cotes`.
- Composant React `<Voiture />` avec couleurs dynamiques — **créé à l'étape 7** (`composants/Voiture.jsx`), **porté dans les profils à l'étape 8** (bloc rouge d'en-tête des maquettes 12 et 14, et aperçu de la personnalisation). Il n'a pas eu à changer : il acceptait déjà `couleur1`, `couleur2`, `numero` et `nom`. `composants/Pastille.jsx` reste en place et n'est pas remplacée : elle porte la couleur de la voiture de son membre, ce qui suffit à le reconnaître dans une liste, là où une voiture complète serait illisible à 36px.
- **`assets/gp-cards.svg` extrait en composant** — **fait à l'étape 9** (`composants/TraceCircuit.jsx`). La planche ne contenait que **deux tracés distincts** (Monza et Spa) répétés six fois, et non un circuit par Grand Prix : les deux sont extraits tels quels, les autres Grands Prix reçoivent un tracé générique. Si de vrais tracés arrivent un jour, ils s'ajoutent à la table `TRACES` et au tableau `PAR_MOTIF` du même fichier, sans toucher aux écrans.
- **`assets/traces.svg` extrait en composant** — **fait en version `0.15.0`** (`composants/TracesCircuits.jsx`), et c'est le jeu de tracés qui manquait : **douze vrais circuits**, de Zandvoort à Yas Marina. Les deux modules coexistent et ne se remplacent pas — celui de l'étape 9 dessine des **silhouettes pleines** (vignettes de 20 × 32px des deux calendriers), celui-ci des **traits** (bande du bloc de l'accueil, où il est passé du filigrane au premier plan en version `0.16.0`). Les tracés qui manquent encore sont ceux du début de saison ; ils s'ajoutent à la table `TRACES` du nouveau fichier, avec leur `viewBox` mesurée, sans toucher aux écrans — **`aUnTrace` fait alors disparaître la bande d'elle-même** pour un Grand Prix qui n'y est pas encore. Le **calendrier d'un championnat** est passé aux douze vrais tracés en version `0.19.0`, et le **calendrier global** en version `0.20.0`. **`TraceCircuit.jsx` n'est donc plus monté nulle part** : le fichier et ses deux silhouettes restent en place, comme `Onglets.jsx` depuis la version `0.12.0` et le code OAuth depuis la `0.2.2` — c'est la seule réponse déjà écrite et vérifiée le jour où une vignette de 20 × 32px redevient nécessaire, taille à laquelle un trait de 1px se lit moins bien qu'un aplat.
- **Voiture personnalisable dans le profil** (section 5) — **fait à l'étape 8** : deux couleurs choisies parmi vingt, un numéro libre de 1 à 99, modifiables à tout moment depuis `/profil`. Le rang affiché sur la voiture a disparu ; il ne sert plus que de repli tant qu'aucun numéro n'est choisi. Les livrées, elles, ont changé de place plutôt que de disparaître : le calcul frontend par ordre d'inscription (`lib/livrees.js`) est bien supprimé, mais la **version `0.8.1` les a reposées en base**, comme valeur initiale des deux colonnes à la création du profil. Le membre les écrase dès qu'il personnalise. Les deux points laissés ouverts sont tranchés et documentés au « Reste à faire » : deux membres d'un même championnat **peuvent** choisir les mêmes couleurs (conséquence assumée) et le même numéro (avertissement non bloquant).
