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

### Bugs connus

*(Aucun.)*

### Reste à faire

Les étapes 8 et 9 de l'ordre de développement de la section 7, plus le **calendrier du championnat** (maquette 15), annoncé par l'étape 7 et non couvert : les deux vues de classement le sont, le calendrier GP par GP ne l'est pas. Il demande la liste des Grands Prix passés et à venir avec, pour chacun, ce que le championnat y a marqué. `GET /grands-prix/{id}/resultats?championnat_id=` (étape 6) sert déjà le détail d'un GP ; il manque la liste.

**Migrations à appliquer** — cette liste est à revérifier. Au cours de la version `0.5.1`, une lecture partie par erreur vers le **vrai** projet Supabase (doublure de test mal branchée) a rendu une ligne réelle de `public.grands_prix` : « GP Pays Bas », `2026-08-23T13:00:00+00:00`, statut `a_venir` — exactement ce que le scraper de l'étape 4 avait produit en local. **La migration 3 est donc appliquée et le scraper a bel et bien écrit en base**, ce qui contredit la mention ci-dessous. L'état des autres n'a pas été observé. À vérifier dans le SQL Editor avant de rejouer quoi que ce soit — les six migrations sont idempotentes, les rejouer ne casse rien.

Ordre d'application, si l'une manque :
1. `supabase/migrations/20260809191018_profils_pseudo_unique.sql` — sans elle, aucun pseudo n'est unique et la liste des membres affiche « Pilote » partout.
2. `supabase/migrations/20260810163435_championnats.sql` — sans elle, toutes les routes `/championnats` échouent.
3. `supabase/migrations/20260813174500_grands_prix_cotes.sql` — sans elle, le scraper découvre et lit correctement les cotes chez Unibet mais échoue à l'écriture, et les routes `/scraper/cotes` et `/grands-prix/{id}/cotes` répondent `422` en portant `42P01`.
4. `supabase/migrations/20260813182331_createur_nullable_championnat_vide.sql` — sans elle, supprimer un compte ayant créé un championnat échoue par contrainte de clé étrangère, et un championnat quitté par son dernier membre reste en base. **Elle suppose la 2 déjà appliquée** : elle modifie `public.championnats`, elle ne la crée pas.
5. `supabase/migrations/20260813183636_favoris_pronostics.sql` — sans elle, aucun écran de l'étape 5 ne fonctionne, et **`DELETE /championnats/{id}/quitter` échoue aussi** : il appelle désormais `quitter_championnat`. **Elle suppose les 2, 3 et 4 déjà appliquées** : elle référence `membres_championnat`, `grands_prix`, `cotes` et réutilise `est_membre` et `marquer_modification`.
6. `supabase/migrations/20260813205200_resultats_points.sql` — sans elle, aucun point n'est jamais attribué : le job de résultats échoue en portant `42P01`, `GET /grands-prix/{id}/resultats` aussi, et `POST /jobs/resultats/{id}` de même. **Elle suppose les 3 et 5 déjà appliquées** : elle modifie `pronostics` et `pronostic_podium`, référence `grands_prix`, et remplace `pronostics_du_joueur`.
7. `supabase/migrations/20260814103000_classement_championnat.sql` — sans elle, `GET /championnats/{id}/classement` répond `422` en portant `42P01`, et les deux écrans de l'étape 7 restent vides : la vue liste retombe sur la liste des membres sans points, la vue piste n'affiche aucune voiture. **Elle suppose les 2, 5 et 6 déjà appliquées** : elle lit `membres_championnat`, `profils` et `pronostics.points_gagnes`. Elle ne crée aucune table.

**Variables d'environnement du backend** — à définir sur Railway :
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`. Sans elles, `/championnats` et `POST /scraper/declencher` répondent `503` avec un message explicite, et **le scheduler de l'étape 6 ne démarre pas du tout** (il le journalise au démarrage). La clé de service ne doit jamais être exposée au frontend ni committée.
- **`ADMIN_SECRET`** — chaîne libre, choisie par toi, à garder secrète. C'est la valeur attendue dans l'en-tête `X-Admin-Secret` de `POST /scraper/declencher` **et de `POST /jobs/resultats/{gp_id}`**. **Tant qu'elle n'est pas définie, les deux routes refusent tout le monde** (`503`) : une variable absente ne doit jamais valoir accès libre. Déclenchement type :
  ```
  curl -X POST https://<railway>/scraper/declencher -H "X-Admin-Secret: <valeur>"

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
- **Scraper exercé contre le vrai Supabase** — la ligne réelle observée en version `0.5.1` (voir ci-dessus) montre que l'écriture a eu lieu au moins une fois. Reste à vérifier le contenu de `public.cotes` pour ce GP, et le comportement du scraper sur un GP déjà figé.
- **Programmation automatique du scraping, et figeage des cotes** — la règle 4.3 veut un scraping le samedi, 2h après les qualifications, puis un figeage des cotes. Aujourd'hui le déclenchement est **manuel** (`POST /scraper/declencher`) et **rien ne fait passer un GP en `cotes_figees`** : le statut existe, la protection qu'il commande est en place et testée, mais aucun code ne l'applique encore. **Le scheduler de l'étape 6 existe désormais** (`app/jobs/resultats.py`, APScheduler dans le `lifespan`) : c'est là qu'un second emploi viendra naturellement se greffer. En attendant, le job de résultats surveille aussi les GP restés `a_venir`, pour ne pas dépendre d'un figeage qui n'a jamais lieu.
- **Marchés disponibles à J-10** — au moment du développement, Unibet n'exposait que 3 marchés pour le GP Pays-Bas (vainqueur, podium, écurie gagnante). Le noyau annoncé en section 3.1 (top 6, top 10, duels…) n'apparaîtra qu'à l'approche de la course. Le scraper les découvre dynamiquement, donc rien à changer — mais **le jeu de marchés réellement obtenu après les qualifications reste à observer**. C'est le point de vigilance principal de l'étape 6 : `app/calcul/points.py` reconnaît neuf familles de marchés, mais **seules trois ont été confrontées à de vrais libellés Unibet**. Les autres (top N, abandon, safety car, drapeau rouge, meilleur tour) sont écrites d'après la section 4.4. Un marché non reconnu ne fait aucun dégât — le pronostic reste à `NULL` et les logs le disent — mais il faut **relire les avertissements `[points] … laissé(s) sans points` après le premier vrai GP** et compléter `validateur()` en conséquence, puis rejouer `POST /jobs/resultats/{gp_id}`. **Depuis la version `0.6.1`, l'attente n'est plus obligatoire** : `POST /jobs/resultats/{gp_id}/test` confronte le calcul aux vrais pronostics en base sur un classement fictif, sans rien écrire. Dès que les marchés complets apparaissent chez Unibet (après les qualifications), un essai dit immédiatement lesquels restent non reconnus.
- **Duels entre pilotes, premier abandon, marge de victoire, classement exact** — annoncés en section 4.4, **non implémentés**. Ils demandent chacun une règle explicite (égalités, pilote classé contre pilote abandonné) que le CLAUDE.md pose mais que rien ne code encore. Les cas d'égalité du « premier abandon » sont le point à trancher en premier. En l'état ils tombent dans le filet « marché non reconnu ».
- **Écran de résultats (maquette 11)** — l'étape 6 est entièrement backend et l'étape 7 ne l'a pas couvert : elle porte les deux vues de classement, pas le détail d'un Grand Prix couru. `GET /grands-prix/{id}/resultats?championnat_id=` sert déjà tout ce qu'il faut (classement de la course, pronostics des membres, points gagnés) ; il ne manque que l'écran. À faire avec le calendrier du championnat (maquette 15), auquel il se rattache naturellement — une carte de GP y mène.
- **Barre de navigation basse** — toujours pas codée. Elle attend le Calendrier et le Profil, ses deux derniers onglets sans écran. La vue piste, elle, n'en portera **jamais** : elle occupe l'écran entier par décision de l'étape 7.
- **Parcours des championnats exercé contre le vrai Supabase** — le backend a été validé contre une doublure en mémoire et la migration contre un PostgreSQL jetable, mais les deux n'ont jamais tourné ensemble contre le vrai projet.
- **Messages techniques des routes `/championnats`, `/scraper` et `/grands-prix`** — depuis la version `0.3.1`, une panne renvoie sa cause en clair (en anglais) jusque dans l'interface, et le mécanisme est partagé par les trois domaines depuis l'étape 5. C'est délibéré, le temps de la mise en service. Une fois le parcours exercé contre le vrai Supabase, remettre des messages en français dans `journal.echec_lisible` et garder la cause dans les seuls logs.
- **Effacement des pronostics au départ d'un championnat** — tranché à l'étape 5 : ils ne sont effacés que si le joueur ne fait plus partie d'aucun championnat, parce qu'un pronostic compte dans tous ses championnats à la fois. **Si le comportement voulu est autre**, c'est `public.quitter_championnat` qu'il faut reprendre, et rien d'autre.
- **Pronostics d'un GP annulé ou reporté** — la règle 4.7 veut que les pronostics enregistrés soient **effacés**. Rien ne le fait aujourd'hui : le statut `annule` n'existe pas dans la contrainte `check` de `grands_prix`, et aucun code ne l'applique. L'étape 6 apporte un demi-pas : **OpenF1 expose `is_cancelled` sur ses sessions**, et `session_de_course()` le **journalise** quand il vaut vrai — le cas se verra dans les logs au lieu de passer pour une course sans résultat. Il reste à ajouter le statut, l'effacement, et la reprise après report.
- **Marchés obligatoires liés au nom Unibet** — le vainqueur et le podium sont reconnus par les slugs `vainqueur` et `podium`, en dur à **trois** endroits depuis l'étape 6 : `backend/app/api/routes/pronostics.py`, `backend/app/calcul/points.py` et `frontend/src/lib/pronostics.js`. Si Unibet renomme un de ces marchés, la saisie s'arrête proprement en le disant, mais **les trois constantes doivent être corrigées ensemble**.
- **Scheduler et instances multiples** — le job de résultats suppose **un seul processus**. C'est le cas sur le plan gratuit de Railway. Passer à plusieurs instances ferait tourner deux schedulers : la base empêche la double attribution, mais pas les appels OpenF1 en double. Ajouter alors un `pg_try_advisory_lock` dans `surveiller()`, ou sortir le job dans un worker dédié.
- **Test sur iPhone réel** — toujours pas fait. Le rendu n'a été validé qu'en navigateur de bureau. À faire avant de considérer les contraintes iOS comme acquises.
- **Parcours d'authentification testé de bout en bout** — le code est en place et compile, mais inscription, confirmation par email, connexion et réinitialisation n'ont pas encore été exercées contre le vrai projet Supabase.
- **Clés OAuth Google et Apple** — à renseigner dans le tableau de bord Supabase. Ajouter aussi les URL de redirection autorisées : `https://mon-petit-podium.vercel.app/accueil`, `.../nouveau-mot-de-passe` et leurs équivalents `http://localhost:5173`. **Les boutons sont masqués depuis la version `0.2.2`** : une fois les clés en place, repasser `OAUTH_ACTIF` à `true` dans `frontend/src/composants/BoutonsOAuth.jsx`.
- **Variables d'environnement de production** — `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` et `VITE_API_URL` **restent à définir côté Vercel** : sans les deux premières, la production affiche l'écran de configuration manquante. Côté Railway, **`ENVIRONMENT=production` reste à ajouter** : le service répond aujourd'hui `environment: development`, ce qui laisse `/docs` accessible publiquement. `FRONTEND_URL` n'est plus bloquante depuis la version `0.1.2` (l'URL Vercel est la valeur par défaut), mais la définir explicitement reste préférable pour garder la configuration lisible sur Railway.

### Décisions validées mais non encore implémentées

- Schéma de base de données — neuf tables existent : `public.profils`, `public.championnats`, `public.membres_championnat`, `public.grands_prix`, `public.cotes`, `public.favoris`, `public.pronostics`, `public.pronostic_podium`, `public.resultats_gp`. Les points attribués ne sont **pas** une table à part : ils vivent dans la colonne `points_gagnes` de `pronostics` (étape 6). **Le classement cumulé non plus** : tranché à l'étape 7 en faveur du calcul à la volée, par `public.classement_du_championnat(uuid)`. Une table de classement serait un doublon de `points_gagnes`, à retenir cohérent à chaque attribution, à chaque départ d'un membre et à chaque rattrapage d'un `NULL`. Les migrations vivent dans `supabase/migrations/`, une par étape, à exécuter à la main dans le SQL Editor.
- Nommage des routes API — la convention est posée par `/championnats` : nom de domaine au pluriel, sous-chemin `/moi` pour ce qui appartient à l'appelant, verbe explicite pour une action qui n'est pas un CRUD (`/rejoindre`, `/{id}/quitter`, `/declencher`). L'étape 5 y ajoute la ressource imbriquée : `/grands-prix/{id}/favoris`, `/grands-prix/{id}/pronostics`. L'étape 6 y ajoute `/grands-prix/{id}/resultats` et, pour les déclenchements d'administration, le préfixe `/jobs/` : `/jobs/resultats/{id}`.
- Table statique pilote → nationalité — à créer. Sa place est **`backend/app/calcul/pilotes.py`**, créé en version `0.6.1` : il porte déjà la grille 2026 (numéro, prénom, nom, acronyme, écurie, alias Unibet) et le garde-fou de saison. Ajouter un champ `nationalite` au `dataclass` suffira, sans nouvelle table ni nouveau fichier à maintenir en parallèle.
- **Grille des pilotes à mettre à jour chaque saison** — `backend/app/calcul/pilotes.py` décrit 2026. Une table périmée ne fait pas de dégât silencieux (`alias_unibet()` exige que le nom de famille concorde avec le numéro), mais les alias cessent de s'appliquer et les pronostics concernés restent à `NULL`. Les numéros se relisent sur `/drivers` d'OpenF1, les libellés dans `public.cotes`.
- Composant React `<Voiture />` avec couleurs dynamiques — **créé à l'étape 7** (`composants/Voiture.jsx`), et utilisé sur la vue piste. Il reste à le porter dans les **profils** (étape 8), où il remplacera la pastille d'initiale de `composants/Pastille.jsx`. Cette pastille n'est plus tout à fait provisoire pour autant : depuis l'étape 7 elle porte la couleur de la voiture de son membre, ce qui suffit à le reconnaître dans une liste, là où une voiture complète serait illisible à 36px.
- **Voiture personnalisable dans le profil** (section 5) — le composant accepte déjà `couleur1`, `couleur2`, `numero` et `nom`, mais rien ne les fait choisir : les couleurs sont attribuées par ordre d'inscription (`lib/livrees.js`) et le numéro affiché est le rang au classement. La personnalisation relève de l'étape 8, et prendra la place des deux sans toucher au composant. **Deux points à trancher alors** : une voiture personnalisée étant identique dans tous les championnats de son propriétaire, deux membres d'un même championnat peuvent choisir les mêmes couleurs ou le même numéro — la livrée par ordre d'inscription, elle, garantit aujourd'hui l'unicité jusqu'à dix membres.
