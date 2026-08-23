# Reste à faire

État au **23 août 2026**, version `0.54.0`.

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

### 1.2 Appliquer la migration 17 — **sans elle, aucune photo ne s'enregistre**

`20260822120000_photos_contrainte_regex` remplace les deux contraintes `check` de la 16,
qui étaient **incompilables** : `{10,505}` dépasse le plafond de 255 d'un compteur de
répétition PostgreSQL, et toute écriture d'URL de photo retombait en `2201B`
(`bugs-connus.md` §18). Vérifié sur la base de production.

**C'est la migration la plus urgente du lot** : la 16 peut être appliquée sans elle sans
rien casser — l'app se comporte comme avant les photos — mais **la fonctionnalité entière
reste inerte** tant que la 17 n'est pas jouée, et elle échoue en annonçant « Enregistrement
de ton profil : impossible pour le moment », ce qui ne désigne pas la cause.

Si la 16 est rejouée un jour, **rejouer la 17 derrière** : la 16 repose les contraintes
fautives.

### 1.3 Appliquer la migration 16, et créer les deux compartiments avec elle

`20260821180000_photos_profil_championnat` ajoute `profils.avatar_url` et
`championnats.photo_url`, **et crée les compartiments `avatars` et `championnats` dans
Supabase Storage avec leurs politiques**. Tant qu'elle n'est pas jouée :

- les colonnes n'existent pas → le backend sert `null` partout (valeurs par défaut des
  modèles Pydantic, règle 3.3), donc **aucune photo, mais aucune panne** ;
- les compartiments n'existent pas → tout dépôt échoue, et l'écran le dit en français.

Elle **supprime puis recrée `mes_championnats`** (changement de type de retour) : vérifier
au passage que les `revoke`/`grant` de fin de bloc sont bien passés, sans quoi la fonction
resterait exécutable par `anon`. Voir `database.md` §6.

**Rien à convertir, rien à reprendre** : aucun compte n'a de photo avant elle.

### 1.3 bis Appliquer la migration 18 — la couleur du texte de la voiture

`20260823120000_couleur_texte_voiture` ajoute `profils.couleur_texte` et **remplace**
`classement_du_championnat` et `pronostics_du_championnat`. Tant qu'elle n'est pas jouée :

- la colonne n'existe pas → le backend sert `null` (valeurs par défaut des modèles Pydantic,
  règle 3.3), donc **l'encre calculée partout, comme avant** ;
- l'enregistrement d'une couleur de texte échoue en `42703` — le sélecteur du profil est
  visible mais le bouton « Enregistrer ma voiture » retombe en erreur.

**À jouer après la 16 et la 17.** Si la 2, la 8, la 10, la 12 ou la 16 est rejouée un jour,
**rejouer la 18 derrière** : elles restaureraient des fonctions qui ne servent pas
`couleur_texte`.

**Rien à convertir** : la colonne reste `NULL` sur toutes les lignes existantes, et c'est
volontaire (`database.md`, `public.profils`).

### 1.4 Vérifier les migrations appliquées

**La liste des migrations appliquées est à revérifier dans le SQL Editor.** Une lecture
partie par erreur vers le vrai projet a rendu une ligne réelle de `public.grands_prix` :
la **migration 3 est appliquée** et le scraper a bel et bien écrit. L'état des treize
autres n'a pas été observé.

Elles sont idempotentes, les rejouer ne casse rien — **mais l'ordre compte** (tableau des
conflits dans `database.md` §6).

**Les migrations 12, 13 et 14 n'ont pas été jouées contre un PostgreSQL jetable** (démon
Docker indisponible), contrairement aux onze premières. La 13 a été comparée ligne à ligne
à la 10 : trois lignes de différence, toutes attendues. **À surveiller au premier passage.**

### 1.5 Variables d'environnement de production

| Où | Variable | État |
|---|---|---|
| Vercel | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL` | **à définir** |
| Vercel | `VITE_ADMIN_SECRET` | **à définir** — doit valoir exactement l'`ADMIN_SECRET` de Railway |
| Railway | `ENVIRONMENT=production` | **à ajouter** — sinon `/docs` reste public |
| Railway | `FRONTEND_URL` | non bloquante, mais préférable |

> **Un compte de diagnostic subsiste en base.** Le défaut des photos a été localisé le
> 22/08/2026 en éprouvant la chaîne réelle bout en bout, ce qui a demandé un compte jetable
> (`diag-1787408037@example.com`, pseudo `pilote-e88f002b25`). Son championnat et ses objets
> de stockage ont été effacés ; **le compte et son profil ne peuvent pas l'être avec la clé
> publique** et restent à supprimer depuis le tableau de bord Supabase (Authentication puis
> Users). Sans conséquence fonctionnelle : il n'est membre d'aucun championnat. Il décale
> d'un cran l'indice de livrée du prochain inscrit (migration 9), ce qui ne se voit pas.

### 1.6 Rebrancher le décompte de l'accueil

`GP_RESTANTS = 12` dans `ecrans/Accueil.jsx`. La réponse existe : compter `GP_2026` filtré
par `etatDuGpSaison`, comme le fait déjà `CalendrierGlobal`.

> **Sans cela, les deux écrans se contrediront dès la première course courue** — l'accueil
> dira « 12 restants » quand le calendrier en montrera 11. Voir `calendrier.md` §10.

### 1.7 Tester sur iPhone réel

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
| **Le recadrage d'une photo** | le premier geste multi-touch du projet, et la première surface modale. Le pincement zoome-t-il l'image ou la PAGE ? Le refus de `gesturestart` tient-il ? Le suivi reste-t-il à 1:1 pendant un glissement, canvas compris ? |
| **Le sélecteur de fichier** | premier `<input type="file">` du projet — il n'a jamais rencontré Safari iOS. La photothèque s'ouvre-t-elle bien avant le sélecteur de fichiers du système ? |
| **Une photo de 5 Mo** | le décodage, pas l'envoi, est ce qui coûte : une image de 8000 × 6000 occupe près de 200 Mo décompressée. Safari abandonne-t-il l'onglet ? |
| **La photo dans le cockpit** | seize `<clipPath>` sur un même écran, chacun avec son `<image>` : Safari les compose-t-il sans coût au moment de l'entrée des voitures, qui anime déjà `transform` sur les seize ? Et le disque de 15px reste-t-il lisible comme un visage, ou faut-il resserrer le recadrage ? |
| **Le sélecteur de Grand Prix** | vingt-quatre pastilles dans une piste qui déborde très largement l'écran. `scrollIntoView({inline: "center"})` ramène-t-il l'option choisie sans à-coup sur Safari iOS ? Et la pastille glissante suit-elle, alors qu'elle se positionne sur des `offsetLeft` mesurés dans un conteneur qui défile en même temps ? |
| **Le numéro remis à l'endroit** | la compensation de ligne de base est calculée sur la métrique d'Helvetica. Safari iOS peut retomber sur une autre fonte système si « Helvetica Neue » n'est pas résolue : vérifier que le numéro reste centré sur le museau, pas seulement lisible |
| **Un en-tête de marché sur deux lignes** | il est **collant**, donc sa hauteur est prise sur la liste pendant tout le défilement du marché. Vérifier sur un petit écran qu'un titre long ne laisse pas moins d'une rangée et demie de widgets visibles — c'est le seul cas où deux lignes coûteraient plus qu'elles ne rapportent |

---

## 2. Fonctionnalités manquantes

### 2.1 GP annulé ou reporté — la règle existe, le code non

Les pronostics doivent être **effacés**, aucun point attribué. **Rien ne le fait
aujourd'hui** : le statut `annule` n'existe pas dans la contrainte `check`, et aucun code
ne l'applique.

Demi-pas en place : OpenF1 expose `is_cancelled`, et `session_de_course()` le **journalise**
— le cas se verra dans les logs au lieu de passer pour une course sans résultat.

Reste : le statut, l'effacement, et la reprise après report.

### 2.2 Trois marchés annoncés, non implémentés

**Duels entre pilotes**, **premier abandon**, **classement exact**. En l'état ils tombent
dans le filet « marché non reconnu » et laissent `NULL`.

> ~~**Marge de victoire**~~ — **livrée en `0.54.0`** sous son vrai nom, « écart du
> gagnant ». Elle n'était pas « à écrire » : elle était **écrite nulle part**, et le filet
> la faisait passer pour un marché en attente au lieu d'un marché manquant
> (`bugs-connus.md` §23).

> **Le premier abandon est à trancher en premier** : `session_result` ne donne pas l'heure
> mais `number_of_laps`, et **la règle d'égalité n'est pas écrite**. C'est pour cela qu'il
> est volontairement non reconnu.

### 2.3 Confronter le calcul aux vrais marchés

`app/calcul/points.py` reconnaît dix familles ; **trois seulement ont été confrontées à de
vrais libellés Unibet**. Les sept autres sont écrites d'après le cahier des charges.

> **« Écart du gagnant » est le plus urgent des sept**, et c'est le seul dont l'issue n'est
> ni un pilote ni un oui/non : `_intervalle_secondes()` doit reconnaître les vraies
> tournures d'Unibet (« moins de 5 secondes », « 5 - 10 », « plus de 10 »), qu'on n'a
> **jamais vues**. Une issue non reconnue est journalisée en toutes lettres — c'est cette
> ligne-là qu'il faut chercher après l'essai.

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

### 2.6 Les photos, ce qui reste à faire

Livrées en version `0.50.0` (dépôt, affichage, retrait). Trois manques assumés :

- ~~**Aucun recadrage ni redimensionnement.**~~ **Réglé en version `0.51.0`** :
  `RecadragePhoto` + `lib/image.js`, 800px de côté et JPEG 0,85.
- **La photo n'a jamais été vue à sa taille réelle dans le cockpit.** Depuis la version
  `0.52.0` elle y est découpée, et le disque fait **15,04px de diamètre** quand la voiture
  est à sa taille pleine — moins encore dans un groupe serré. Une photo de visage ramenée à
  800px puis rendue à 15 y perd tout sauf sa dominante de couleur : à vérifier **sur
  iPhone**, avec de vraies photos, avant de décider si le cadrage exporté doit se resserrer
  sur le visage. Levier : rien à changer côté géométrie, tout se joue au recadrage.
- **La photo d'un championnat ne se change plus après sa création.** `PATCH
  /championnats/{id}` existe et accepte le créateur ; il manque l'écran qui l'appelle.
- **Rien ne nettoie le stockage à la suppression d'un compte ou d'un championnat.** La
  ligne part par cascade, l'objet reste. Sans conséquence visible — plus rien ne le
  référence — mais le compartiment grossit indéfiniment.

### 2.7 Parcours jamais exercés contre le vrai Supabase

- **Authentification** — inscription, confirmation par email, connexion, réinitialisation.
- **Championnats** — le backend a été validé contre une doublure et la migration contre un
  PostgreSQL jetable, **mais les deux n'ont jamais tourné ensemble** contre le vrai projet.

---

## 3. Points à arbitrer

### 3.1 ~~Le numéro tête-bêche sur la voiture~~ — **TRANCHÉ (`0.53.0`)**

Le numéro se lit **dans le sens de l'écran**. La planche dessinait la convention réelle
d'un museau de Formule 1 — lisible depuis la voiture qu'on double — mais toutes les vues de
l'app sont des vues de dessus. La ligne de base descend d'une hauteur de capitale pour que
le numéro retrouve exactement le pixel qu'il occupait, sur les douze livrées à la fois
(`bugs-connus.md` §20).

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

### 3.5 bis La coiffe des pastilles est partie, l'échelle est rendue

**Réglé en version `0.52.0`.** La version `0.50.0` réservait trente pixels au-dessus de
chaque voiture pour une pastille d'identité, dès qu'un seul membre du championnat avait une
photo. La photo étant désormais découpée dans le cockpit du dessin, la zone de jeu retrouve
exactement la hauteur d'avant les photos — donc l'échelle des scores aussi.

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
complet donnera un écran très long. `composants/Onglets.jsx` est **la réponse déjà écrite et
vérifiée** — et il est désormais **monté** sur l'écran « Résultats par Grand Prix » (version
`0.53.0`), donc éprouvé en conditions réelles avant de revenir ici.

### 3.12 L'icône de « Résultats par Grand Prix » — la demande se contredisait

La demande nommait « la **troisième** icône de `logo-02.svg` » **et** donnait le cadrage
`viewBox 322 0 161.64 133.85`. Les deux ne désignent pas le même dessin :

| Lecture | Ce qu'elle donne |
|---|---|
| Troisième de gauche à droite | le **calendrier** (x 273,84 → 334,52) |
| Troisième groupe `<g>` du fichier | le **calendrier**, encore |
| La région `x ∈ [322 ; 483,64]` | la **silhouette de pilote** (x 396,2 → 456,88), seule forme de cette bande |

**Le cadrage a été suivi**, parce qu'il est la seule indication non ambiguë et parce que
garder l'icône calendrier n'aurait rien changé — l'entrée la portait déjà, ce qui rendrait
l'instruction sans objet. La silhouette est donc réemployée (`IconePilote`, qui délègue à
`icones/IconeProfil.jsx`).

> **Conséquence à arbitrer** : ce glyphe est **aussi celui de l'onglet Profil** de la barre
> basse. Deux contextes différents, mais le même dessin. Si la collision gêne,
> `Icones.jsx` porte déjà `IconeMembres` — deux silhouettes en trait, dans le style des
> autres icônes de cet écran — et le remplacement est **une ligne**.

### 3.13 La couleur du texte ne revient pas à « automatique »

Le sélecteur du profil affiche toujours une couleur : celle de la base, ou à défaut l'encre
calculée déjà à l'écran. Une fois enregistrée, elle ne suit plus la coque — repeindre sa
voiture en blanc laisse le numéro dans la couleur choisie, et c'est bien ce qu'un réglage
explicite doit faire.

**Il n'y a en revanche aucun retour à `NULL`.** L'ajouter demanderait un drapeau
`retirer_couleur_texte` dans `PATCH /profils/moi` — même motif que `retirer_numero` et
`retirer_avatar` — et une case « Automatique » dans `SelecteurCouleur`, qui n'en connaît
aujourd'hui que vingt. **Écarté volontairement** : un chemin de code que rien n'envoie n'est
éprouvé par rien, et l'avertissement de contraste couvre le cas qui comptait.

### 3.14 L'opacité des Grands Prix passés est sous le plancher de contraste

`OPACITE_PASSE = 0,4` (`CarteGpSaison`) compose l'encre **et** son fond sur le beige de
l'app. Mesuré : la pastille « Terminé » tombe de **4,86:1 à 1,74:1**, le blanc sur drapeau
bordeaux de **10,88:1 à 2,49:1** — sous les 3:1 d'un grand texte porteur de sens.

**La valeur est celle qui a été demandée**, et l'arbitrage se défend : ces cartes sont une
archive, et « c'est passé » se lit à la pâleur avant de se lire au mot. **`0,75` est le
point où la pastille repasse le plancher** — une constante, une ligne, si la lisibilité
doit primer. Tableau complet dans `calendrier.md` §8.

**À trancher sur iPhone réel**, pas sur simulateur : c'est un jugement de lisibilité en
plein soleil autant qu'un rapport de contraste.

---

### 3.15 Aucun libellé de nationalité n'a été vu en vrai — quinze pays écrits à l'aveugle

`NATIONALITES` accepte le peuple et le pays (« Néerlandais », « Pays-Bas ») parce que **rien
ne dit lequel des deux Unibet écrit**. Les quinze entrées couvrent la grille 2026 ; aucune
n'a été confrontée à un vrai marché. Une issue inconnue est journalisée en toutes lettres et
laisse `NULL` — **c'est cette ligne qu'il faut chercher** après le premier vrai marché de
nationalité, comme pour « écart du gagnant ».

`POST /jobs/resultats/{gp_id}/test` les confronte sans rien écrire. Et **la table est à
mettre à jour à chaque saison**, au même titre que la grille des pilotes : le garde-fou
numéro + nom de famille fait qu'une table périmée ne rend rien plutôt que de prêter au
nouveau titulaire du 12 la nationalité d'Antonelli.

### 3.16 Le recalcul forcé n'a pas de trace en base

`?forcer=true` efface des points acquis, et **rien n'en garde le souvenir** hors des logs
Railway, qui tournent. Un joueur dont le score baisse entre deux visites n'a aucun moyen de
savoir pourquoi, et personne n'a de moyen de reconstituer l'état d'avant.

Ce n'est pas bloquant tant que la route reste une intervention manuelle rare derrière le
secret d'admin — mais dès qu'elle servira une seconde fois, une colonne `recalcule_le` sur
`grands_prix`, ou une ligne d'audit, coûtera moins cher que la question posée le jour où un
classement bougera sans explication.

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
