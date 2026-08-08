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

*(Rien pour l'instant — projet en cours d'initialisation.)*

### Bugs connus

*(Aucun.)*

### Reste à faire

L'intégralité de l'ordre de développement de la section 7.

### Décisions validées mais non encore implémentées

- Schéma de base de données — à concevoir
- Nommage des routes — à concevoir
- Table statique pilote → nationalité — à créer
- Composant React `<Voiture />` avec couleurs dynamiques — à créer
