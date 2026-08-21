# Reste à faire

État au **21 août 2026**, version `0.48.0`.

Les seize maquettes sont codées, la barre de navigation est en place, les onze étapes de
développement sont livrées.

---

## 1. Priorité — avant le premier vrai Grand Prix

### 1.1 Corriger la donnée du GP des Pays-Bas

**Deux défauts sur la même ligne**, tous deux dans la base et non dans le code
(voir `bugs-connus.md` §4 et §11) :

- `statut = 'cotes_figees'` posé prématurément (qualifications le 22 août à 12h00 UTC) ;
- `date_course` fausse de deux heures (11:00 au lieu de 13:00 UTC).

Le job du samedi ne la refigera pas — il ne traite que les GP en `a_venir`.

> **Le premier défaut est réglé par la migration 15** (`20260821143000_points_diviseur_10`),
> qui repasse à `a_venir` TOUS les GP `cotes_figees` — il fallait les rouvrir de toute
> façon pour que le scraper réécrive les cotes sur la nouvelle échelle. Si elle a été
> jouée, l'`update` ci-dessous n'a plus rien à faire.

```sql
update public.grands_prix set statut = 'a_venir'
 where id = '33b835cc-5c17-40f7-a41f-3e95fc14885a' and statut = 'cotes_figees';
```

Puis `POST /scraper/declencher?figer=false` — il réécrit `date_course` et
`date_qualifications` **même pour un GP figé**, donc les deux se remettent d'aplomb en une
fois. **Ce scraping est de toute manière obligatoire après la migration 15**, qui vide
`public.cotes`.

> **Tout essai de scraper d'ici là doit porter `?figer=false`.**

> **Depuis la version `0.44.0`, il n'y a plus aucune raison d'écrire en base pour REGARDER
> l'écran des pronostics.** Le « Mode prévisualisation » de la section Administration fait
> voir l'application comme si les cotes étaient figées, sans toucher au statut. Le
> correctif ci-dessus reste nécessaire — il répare une donnée réellement fausse — mais la
> vérification qui avait causé l'accident se fait maintenant sans écrire.

### 1.2 Vérifier les migrations appliquées

**La liste des migrations appliquées est à revérifier dans le SQL Editor.** Une lecture
partie par erreur vers le vrai projet a rendu une ligne réelle de `public.grands_prix` :
la **migration 3 est appliquée** et le scraper a bel et bien écrit. L'état des treize
autres n'a pas été observé.

Elles sont idempotentes, les rejouer ne casse rien — **mais l'ordre compte** (tableau des
conflits dans `database.md` §6).

**Les migrations 12, 13 et 14 n'ont pas été jouées contre un PostgreSQL jetable** (démon
Docker indisponible), contrairement aux onze premières. La 13 a été comparée ligne à ligne
à la 10 : trois lignes de différence, toutes attendues. **À surveiller au premier passage.**

### 1.3 Variables d'environnement de production

| Où | Variable | État |
|---|---|---|
| Vercel | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL` | **à définir** |
| Vercel | `VITE_ADMIN_SECRET` | **à définir** — doit valoir exactement l'`ADMIN_SECRET` de Railway |
| Railway | `ENVIRONMENT=production` | **à ajouter** — sinon `/docs` reste public |
| Railway | `FRONTEND_URL` | non bloquante, mais préférable |

### 1.4 Rebrancher le décompte de l'accueil

`GP_RESTANTS = 12` dans `ecrans/Accueil.jsx`. La réponse existe : compter `GP_2026` filtré
par `etatDuGpSaison`, comme le fait déjà `CalendrierGlobal`.

> **Sans cela, les deux écrans se contrediront dès la première course courue** — l'accueil
> dira « 12 restants » quand le calendrier en montrera 11. Voir `calendrier.md` §10.

### 1.5 Tester sur iPhone réel

**Jamais fait.** Le rendu n'a été validé qu'en navigateur de bureau et par rendu hors
navigateur. Points à regarder en priorité :

| Quoi | Pourquoi |
|---|---|
| **Matériaux translucides** | `backdrop-filter` sur la nav et la barre d'action : saccade au défilement ? traînée quand la barre d'adresse de Safari se rétracte ? |
| **Zones sûres réelles** | `h-nav` (58 px) et `env(safe-area-inset-bottom)` face à un vrai home indicator |
| **En-têtes collants** | `--entete-hauteur` = zone sûre + 60 px, face à un vrai `env(safe-area-inset-top)` |
| **Vue piste** | hauteur ET largeur mesurées par `ResizeObserver`, qui changent quand la barre d'adresse se rétracte. La planche s'étire alors verticalement : c'est le rapport de forme des kerbs qu'il faut regarder |
| **Grain du fond** | tuile rastérisée mise en cache — à confirmer sur une longue liste de cotes |
| **`prefers-reduced-transparency`** | activer « Réduire la transparence » : les matériaux doivent devenir opaques |
| **`prefers-contrast: more`** | activer « Augmenter le contraste » : le grain disparaît, le voile s'approfondit |
| **Aplats pleine largeur** | en **paysage** sur un iPhone à encoche, où la zone sûre latérale n'est plus nulle |

---

## 2. Fonctionnalités manquantes

### 2.1 GP annulé ou reporté — la règle existe, le code non

Les pronostics doivent être **effacés**, aucun point attribué. **Rien ne le fait
aujourd'hui** : le statut `annule` n'existe pas dans la contrainte `check`, et aucun code
ne l'applique.

Demi-pas en place : OpenF1 expose `is_cancelled`, et `session_de_course()` le **journalise**
— le cas se verra dans les logs au lieu de passer pour une course sans résultat.

Reste : le statut, l'effacement, et la reprise après report.

### 2.2 Quatre marchés annoncés, non implémentés

**Duels entre pilotes**, **premier abandon**, **marge de victoire**, **classement exact**.
En l'état ils tombent dans le filet « marché non reconnu » et laissent `NULL`.

> **Le premier abandon est à trancher en premier** : `session_result` ne donne pas l'heure
> mais `number_of_laps`, et **la règle d'égalité n'est pas écrite**. C'est pour cela qu'il
> est volontairement non reconnu.

### 2.3 Confronter le calcul aux vrais marchés

`app/calcul/points.py` reconnaît neuf familles ; **trois seulement ont été confrontées à de
vrais libellés Unibet**. Les six autres sont écrites d'après le cahier des charges.

**L'attente n'est pas obligatoire** : `POST /jobs/resultats/{gp_id}/test` confronte le
calcul aux vrais pronostics en base sur un classement fictif, **sans rien écrire**. Dès que
les marchés complets apparaissent (après les qualifications), un essai dit immédiatement
lesquels restent non reconnus.

Après le premier vrai GP : relire les avertissements `[points] … laissé(s) sans points`,
compléter `validateur()`, puis rejouer `POST /jobs/resultats/{gp_id}` — qui ne remplit que
les `NULL` restants.

### 2.4 Relire les logs du premier samedi de qualifications

Unibet **n'exposait aucun événement de qualification** au 16 août : c'est le repli
`date_course − 22 h` qui s'applique. Chercher dans les logs « qualifications annoncées par
Unibet » ou « aucune épreuve de qualification trouvée ».

Vérifier aussi que **l'accueil annonce bien le GP du week-end** et non celui de la semaine
d'avant (le défaut de `chargerProchainGp` est corrigé, mais jamais exercé contre la vraie
base au moment du figeage).

### 2.5 Clés OAuth Google et Apple

À renseigner dans Supabase, avec les URL de redirection (`/accueil`,
`/nouveau-mot-de-passe`, en production **et** sur `localhost:5173`). Puis repasser
`OAUTH_ACTIF` à `true` dans `composants/BoutonsOAuth.jsx` — **rien d'autre à toucher**.

### 2.6 Parcours jamais exercés contre le vrai Supabase

- **Authentification** — inscription, confirmation par email, connexion, réinitialisation.
- **Championnats** — le backend a été validé contre une doublure et la migration contre un
  PostgreSQL jetable, **mais les deux n'ont jamais tourné ensemble** contre le vrai projet.

---

## 3. Points à arbitrer

### 3.1 Le numéro tête-bêche sur la voiture

Rendu `rotate(180)` sur les onze livrées **et** sur la voiture personnalisable. C'est le
calage de la planche d'origine, **uniforme**. À trancher si le numéro doit se lire dans le
sens de l'écran.

### 3.2 La barre de navigation sur deux écrans de détail

Le **calendrier d'un championnat** et les **Grands Prix d'un membre** ne la portent pas —
la liste de la demande initiale ne les mentionnait pas, alors qu'iOS la garde sur toute la
pile d'un onglet. **Les y ajouter, c'est une ligne dans `CHEMINS_AVEC_BARRE`.**

### 3.3 La rangée « Mes Grands Prix » du profil d'un membre

Retirée de *mon* profil, conservée sur celui d'un **autre** membre (maquette 12). C'est le
**seul chemin restant** vers `GrandsPrixDuMembre.jsx` : la retirer là aussi rendrait
l'écran inatteignable autrement que par son URL.

### 3.4 Livrées automatiques au-delà de dix membres

Elles rebouclent tous les dix (cycle **global**, par ordre d'inscription). Un championnat
de plus de dix membres dont personne n'a personnalisé verra le 11ᵉ porter les couleurs du
1ᵉʳ. **Le rendre unique par championnat est impossible en l'état** : une voiture est
identique dans tous les championnats de son propriétaire.

### 3.5 Le haut de la vue piste

**Réglé en version `0.49.0`.** La ligne d'arrivée avait été retirée en laissant le haut de
la piste sans rien pour l'ancrer ; le **bandeau du championnat** joue désormais ce rôle, et
il nomme en plus l'écran.

### 3.6 Un groupe de plus de seize voitures se recouvre

**Le plancher de `LARGEUR_MINIMALE` (18px) prime sur la garantie de non-chevauchement.**
Au-delà de seize voitures dans un même groupe géométrique — le cas d'un championnat de
plus de seize membres tous à égalité, donc avant le premier Grand Prix — les cellules
deviennent plus étroites que la voiture et les dessins se recouvrent d'un ou deux pixels.
L'alternative, descendre sans plancher, rendrait des voitures de trois pixels : un léger
recouvrement se lit encore comme une grille de départ, une tache ne se lit pas. Levier :
`LARGEUR_MINIMALE`, ou un retour aux rangées empilées si le cas devient courant.

### 3.6 bis La cascade de regroupement est sensible au pixel près

Deux voitures séparées de 121px se regroupent, de 123px non — et le regroupement se
**propage**, donc une voiture peut faire basculer tout un écran d'un groupe de deux à un
groupe de sept. C'est le comportement demandé ; il n'a pas de zone tampon, et rien ne lisse
la bascule d'un chargement à l'autre.

### 3.7 Longueur de l'onglet Calendrier

Douze cartes de 200 px font près de trois écrans, **sans en-tête collant** pour dire où
l'on est. Levier : `HAUTEUR_CARTE` (le tracé, la bande et le squelette suivent seuls).
Question voisine : faire défiler jusqu'au prochain GP à jouer à l'ouverture ? Cela demande
un `scrollIntoView` et un choix explicite sur le comportement du retour.

### 3.8 Lisibilité des tracés sur les drapeaux clairs

Le trait blanc à 60 % vaut **2,44:1 au pire** (Brésil). Lisible mais discret. Deux leviers
d'une ligne, **dans cet ordre** : monter le trait à 70 %, ou approfondir la surcouche de 15
à 25 %. **Ne pas toucher au voile** — il est calculé pour le texte.

### 3.9 Fidélité de `assets/flags.svg`

La planche est **stylisée** : sept bandes malaisiennes au lieu de quatorze, treize étoiles
américaines au lieu de cinquante, sphère brésilienne sans étoiles. Reconnaissable à 180 px,
vérifié en aperçu. **Si un drapeau doit gagner en fidélité, c'est la PLANCHE qu'il faut
reprendre**, jamais `DrapeauxSVG.jsx`.

Austin et Las Vegas sont **rigoureusement identiques** (même pays) : le tracé et le nom sont
les seuls discriminants.

### 3.10 Les trois teintes d'écurie non vérifiées

**Alpine**, **Haas** et **Cadillac** ont été appliquées telles que fournies. Haas et
Cadillac sont blanc + rouge et blanc + noir — le blanc ne peut pas teinter un widget déjà
blanc, d'où la teinte secondaire. **Si Haas doit se lire rouge plutôt que gris, c'est
`#E6002B` et c'est une ligne.**

Le rose Alpine est **le bon choix quoi qu'il en soit** : la grille compte déjà trois bleus,
un quatrième annulerait la fonction de la teinte.

### 3.11 Le tableau des cotes quand les marchés se multiplient

Les marchés sont **empilés** en sections colorées. Après les qualifications, le noyau
complet donnera un écran très long. `composants/Onglets.jsx` est **resté en place, non
monté** : c'est la réponse déjà écrite et vérifiée.

---

## 4. Dettes techniques

### 4.1 `will-change: transform` permanent sur `.t-ecran`

Sur le conteneur plein écran de chaque écran. Le navigateur promeut déjà une couche pendant
une animation active : il ne gagne rien après les 200 ms d'entrée et **garde une couche
plein cadre en mémoire pour toute la vie de l'écran**.

> **Non retiré délibérément** : `will-change` crée un **contexte d'empilement**, et
> l'empilement de cette app est documenté cas par cas (barre chassée des écrans, en-têtes
> collants, `z-index` d'un `Bloc`). Le retirer se fait avec un contrôle de tous ces cas,
> pas au détour d'une passe d'animation.

### 4.2 `--text-swap-ease` vaut `ease-in-out`

L'easing intégré, sur un échange de texte qui est une **entrée/sortie** — il devrait être
un ease-out fort. **Employé par une dizaine d'écrans** : à changer pour lui-même, avec un
contrôle visuel sur chacun.

### 4.3 Le nom npm et l'URL Vercel portent encore l'ancien nom

`frontend/package.json` (`"name": "mon-petit-podium"`) et `ORIGINE_PRODUCTION` dans
`backend/app/config.py`. **Ni l'un ni l'autre n'est du texte visible**, et la seconde est
l'**origine CORS garantie** : la changer avant que le domaine Vercel n'ait suivi **fermerait
la production à elle-même**. À renommer ensemble, avec le domaine.

### 4.4 Trois surfaces portent encore « Mon Petit Podium »

Le **titre OpenAPI** (`backend/app/main.py`, visible sur `/docs`) — une ligne, mais qui fait
bouger la version du backend et demande un déploiement Railway. Et les **quinze maquettes**,
laissées telles quelles comme le reste de leurs écarts (elles écrivent aussi « ligue » et
« historique »).

### 4.5 `frontend/public/flags.svg` n'est utilisé par rien

Les drapeaux partent en SVG inline avec le bundle. La copie sert de référence à une
ré-extraction et coûte **30 Ko au précache** du service worker. **La retirer est sans effet
sur l'application.**

### 4.6 Le croisement des chiffres de la bascule d'horloge

Pendant 260 ms deux nombres coexistent dans la tuile. **L'équilibre entre le flou,
l'opacité et la vitesse ne se règle qu'en regardant** — sur un iPhone, en ralentissant d'un
facteur 3 ou 4, et **revu le lendemain**. Deux points : que le rognage ne coupe pas le haut
des chiffres à 48 px, et que la minute qui change ne tire pas l'œil pendant qu'on lit autre
chose.

### 4.7 Le pouce de l'interrupteur admin ne parcourt que 18 px

À 180 ms, c'est court : **se perçoit-il, ou passe-t-il pour un saut ?** Le levier
`--icon-swap-dur` est **partagé avec l'étoile de favori et les icônes de la barre** — le
toucher les changerait toutes les trois. Si l'interrupteur seul doit ralentir, un jeton
propre se justifierait, **pas avant d'avoir regardé**.

**Depuis la version `0.44.0` la question porte sur DEUX interrupteurs**, celui du mode admin
et celui de la prévisualisation, qui partagent le composant `Bascule` — donc le même jeton.
C'est un argument de plus pour regarder : un défaut de perception se verrait deux fois de
suite, à un centimètre d'écart.

---

## 5. Opportunités d'animation

Résultat d'un balayage en lecture seule sur `frontend/src`.

> **Verdict : cette interface est déjà proche du compte.** Retour d'appui partout, attentes
> en silhouettes, `prefers-reduced-motion` sur toutes les transitions, aucune animation sur
> une action au clavier. **Il n'y a pas de dette de mouvement** — ce sont des finitions.

| # | Où | Fréquence | Proposition |
|---|---|---|---|
| 1 | Carte « Pronos enregistrés ! » (récap) | **rare** | *Success check* — la coche se dessine, 300 ms. **Uniquement sous `state.enregistre`** |
| 2 | Total dans la barre collée (saisie) | occasionnelle | Accordéon `0fr → 1fr` — il surgit et **pousse le bouton** |
| 3 | Confirmation « Quitter le championnat » | rare | Même accordéon, 200 ms |
| 4 | Coche du choix de couleur | rare | `scale(0.8)`, 160 ms. **Jamais `scale(0)`** |
| 5 | Changement de livrée | rare | `transition: fill 200ms ease` — un changement de couleur prend `ease` |

> **La n° 1 est la plus rentable** : c'est le seul moment franchement émotionnel de l'app,
> sur l'un de ses écrans les plus plats, et le snippet *success check* est **installé
> depuis longtemps sans avoir jamais servi**.

> **Les n° 2 et 3 n'ont plus rien à écrire.** La version `0.46.0` a empaqueté exactement
> leur mécanique dans `composants/Repli.jsx` — `grid-template-rows: 0fr → 1fr`, montage
> différé d'une image, démontage sur `--acc-collapse`. Les brancher est devenu une
> substitution de balise : `<Repli visible={…}>`. **Ne pas réécrire le mécanisme sur
> place** ; c'est la règle de la source unique par question.

### Écartés — et ce qui les a écartés

| Candidat | Pourquoi non |
|---|---|
| Échelonnement des widgets de cote | **66 widgets** : à 40 ms, le dernier arrive à 2,6 s. Un décalage ne doit jamais retarder une interaction |
| Échelonnement des lignes de classement | **Donnée fonctionnelle** — ce qu'on lit ne bouge pas pour faire joli |
| Passage d'onglet | **Des dizaines de fois par jour** : palier « quasi imperceptible ou rien ». Les 180 ms actuelles sont au plafond |
| Déplacement des voitures sur la piste | **Aucun état « avant » à l'écran** |
| Retour visuel par caractère du code | **Action au clavier** — se met en travers de la saisie |
| État vide de la liste des championnats | **Déjà couvert** par l'entrée du bloc |

### Deux mouvements refusés au moment de les écrire

**La bascule 3D façon calendrier mécanique** demande `preserve-3d` et
`backface-visibility` — or chaque bloc vit sous `.t-stagger-line`, qui porte
`will-change: transform` : **précisément la configuration où Safari iOS aplatit ou fait
clignoter les faces**. Le glissement vertical donne la même lecture sans le risque.

**Le fondu entre les deux modes de voiture** : les deux sont **la même silhouette** à la
peinture près — un fondu entre deux formes identiques se lit comme un scintillement.
