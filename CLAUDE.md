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

> **Le design system ci-dessus n'est pas négociable.** Les couleurs, la police Helvetica Neue, les rayons de coins, l'échelle typographique et l'esprit widget sont des décisions déjà validées. Aucun skill ne doit les remplacer ni les réinterpréter.

**`/apple-design` doit être invoqué sur chaque écran codé, sans exception.** Son périmètre : les principes iOS — zones sûres, animations fluides de facture native, hiérarchie visuelle, gestes, home indicator. Il ne contredit pas le design system existant, il l'**enrichit** de la sensibilité iOS. En cas de conflit avec la section 5, **le CLAUDE.md gagne**.

Cette règle s'applique **rétroactivement** : l'écran d'accueil minimal déjà codé devra être repassé sous `/apple-design` lors d'une prochaine session.

**Taste** intervient comme directeur artistique **à l'intérieur** de ces contraintes, jamais au-dessus. Son périmètre : hiérarchie visuelle, rythme des espacements, qualité des micro-détails, équilibre des compositions, choix des proportions. Il ne propose jamais une autre palette ni une autre typographie.

**Transitions.dev** intervient uniquement sur le mouvement : transitions d'écran, apparition des blocs, changements d'onglet, états de chargement, retours tactiles. Aucune influence sur les couleurs ou les formes.

Ordre d'invocation avant de coder un écran : **`/apple-design`, puis `/design-taste-frontend`, puis `/transitions-dev`.**

Si un skill suggère quelque chose qui contredit ce fichier, **ce fichier gagne**. Le signaler plutôt que de trancher seul.

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

### Bugs connus

*(Aucun.)*

### Reste à faire

Les étapes 4 à 9 de l'ordre de développement de la section 7.

**Migrations à appliquer** — **aucune des deux migrations n'a encore été exécutée** sur le projet Supabase, dans cet ordre :
1. `supabase/migrations/20260809191018_profils_pseudo_unique.sql` — sans elle, aucun pseudo n'est unique et la liste des membres affiche « Pilote » partout.
2. `supabase/migrations/20260810163435_championnats.sql` — sans elle, toutes les routes `/championnats` échouent.

**Variables Supabase du backend** — `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` **restent à définir sur Railway**. Sans elles, les routes `/championnats` répondent `503` avec un message explicite. La clé de service ne doit jamais être exposée au frontend ni committée.

Points non couverts, à traiter le moment venu :
- **Parcours des championnats exercé contre le vrai Supabase** — le backend a été validé contre une doublure en mémoire et la migration contre un PostgreSQL jetable, mais les deux n'ont jamais tourné ensemble contre le vrai projet.
- **Messages techniques des routes `/championnats`** — depuis la version `0.3.1`, une panne renvoie sa cause en clair (en anglais) jusque dans l'interface. C'est délibéré, le temps de la mise en service. Une fois le parcours exercé contre le vrai Supabase, remettre des messages en français dans `echec_lisible` et garder la cause dans les seuls logs.
- **Suppression d'un compte ayant créé un championnat** — échoue aujourd'hui par contrainte de clé étrangère, faute de règle métier. À trancher : transférer la propriété au plus ancien membre, ou anonymiser `cree_par`.
- **Championnat vide** — rien ne le supprime quand son dernier membre part. Il reste en base, inaccessible mais rejoignable par son code.
- **Test sur iPhone réel** — toujours pas fait. Le rendu n'a été validé qu'en navigateur de bureau. À faire avant de considérer les contraintes iOS comme acquises.
- **Parcours d'authentification testé de bout en bout** — le code est en place et compile, mais inscription, confirmation par email, connexion et réinitialisation n'ont pas encore été exercées contre le vrai projet Supabase.
- **Clés OAuth Google et Apple** — à renseigner dans le tableau de bord Supabase. Ajouter aussi les URL de redirection autorisées : `https://mon-petit-podium.vercel.app/accueil`, `.../nouveau-mot-de-passe` et leurs équivalents `http://localhost:5173`. **Les boutons sont masqués depuis la version `0.2.2`** : une fois les clés en place, repasser `OAUTH_ACTIF` à `true` dans `frontend/src/composants/BoutonsOAuth.jsx`.
- **Variables d'environnement de production** — `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` et `VITE_API_URL` **restent à définir côté Vercel** : sans les deux premières, la production affiche l'écran de configuration manquante. Côté Railway, **`ENVIRONMENT=production` reste à ajouter** : le service répond aujourd'hui `environment: development`, ce qui laisse `/docs` accessible publiquement. `FRONTEND_URL` n'est plus bloquante depuis la version `0.1.2` (l'URL Vercel est la valeur par défaut), mais la définir explicitement reste préférable pour garder la configuration lisible sur Railway.

### Décisions validées mais non encore implémentées

- Schéma de base de données — trois tables existent : `public.profils`, `public.championnats`, `public.membres_championnat`. Restent à concevoir celles des cotes, des pronostics et des résultats. Les migrations vivent dans `supabase/migrations/`, une par étape, à exécuter à la main dans le SQL Editor.
- Nommage des routes API — la convention est posée par `/championnats` : nom de domaine au pluriel, sous-chemin `/moi` pour ce qui appartient à l'appelant, verbe explicite pour une action qui n'est pas un CRUD (`/rejoindre`, `/{id}/quitter`).
- Table statique pilote → nationalité — à créer
- Composant React `<Voiture />` avec couleurs dynamiques — à créer. Il remplacera la pastille d'initiale de `composants/Pastille.jsx`, provisoire, dans la liste des membres et les cartes.
