# Reste à faire

État au **26 août 2026**, version `0.59.0`.

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

### 1.3 ter Appliquer la migration 19 — les onze Grands Prix restants

`20260826120000_calendrier_2026_grands_prix` insère en base les onze Grands Prix restants
de 2026 (Italie → Abu Dhabi). Le GP des Pays-Bas n'y est pas : il est déjà en base.

Elle ne dépend que de la **3** et de la **11**, ne remplace aucune fonction, et n'entre
donc dans aucun conflit d'ordre. **Elle peut être jouée avant ou après les 15 à 18.**

> ### Le geste à ne pas oublier : adopter chaque ligne avant son week-end
>
> Les onze lignes portent un `id_unibet` **inventé** (`manuel-<slug>-2026`) : le vrai
> n'existe pas tant qu'Unibet n'a pas ouvert la page du Grand Prix. Or le scraper se
> rapproche sur `id_unibet` et sur rien d'autre — **il ne reconnaîtra pas la ligne et en
> insèrera une seconde.**
>
> ```sql
> select public.adopter_grand_prix('manuel-italie-2026', '<id Unibet réel>');
> ```
>
> À jouer **le vendredi ou le samedi matin** du week-end visé, avant l'ouverture de la
> fenêtre de déclenchement du job (`date_qualifications + 2h`, refermée 4h plus tard). Le
> vrai identifiant se lit dans le journal du scraper, qui écrit « nom (id) » pour chaque
> GP rencontré, ou dans l'URL de la page chez le bookmaker.
>
> Passé ce délai, rien n'est perdu : `adopter_grand_prix` résorbe aussi le doublon **après
> coup**, en gardant la ligne du scraper — celle qui porte les cotes — et en supprimant la
> ligne manuelle **si et seulement si elle est vide**.

> **Les heures de COURSE insérées sont prévisionnelles.** Elles suivent la convention des
> horaires usuels de la F1 (15h00 locale, heure habituelle pour les quatre courses de
> nuit), converties au fuseau réel de chaque circuit. **Le scraper les remplace au premier
> passage.** À surveiller d'ici là : une carte du calendrier peut passer à « Fermé » sur la
> foi d'une heure devinée.

> ### ⚠️ Ses heures de QUALIFICATIONS sont fausses — la 20 les corrige
> La 19 pose `date_qualifications = date_course − 22h`. **Neuf des onze sont fausses**, de
> une à quatre heures (`bugs-connus.md` §27). Jouer la 19 **sans** la 20 fait afficher des
> qualifications à 17h00 pour le GP d'Italie, qui les court à 16h00.
>
> **Elle n'est pas réécrite pour autant** — les migrations sont historiques (`database.md`
> §7). Enchaîner la 20 juste derrière, toujours dans cet ordre.

> **Éprouvée sur un PostgreSQL 16 jetable**, contrairement à ce qui était écrit ici : le
> démon Docker était disponible au moment de la `0.61.0`. La 19 s'exécute, ses six cas
> d'épreuve de `slug_gp` passent, elle insère onze lignes, et rejouée en insère zéro. Le
> harnais était réduit aux colonnes qu'elle touche — **ce n'est donc pas le schéma de la
> 3**, et le premier passage dans le SQL Editor reste à surveiller.

### 1.3 quater Appliquer la migration 20 — les horaires de qualifications

`20260826180000_qualifications_horaires_2026` corrige les onze `date_qualifications` que la
19 dérive de `date_course`. **À jouer juste après la 19, toujours** — jouée avant, elle ne
trouve rien à corriger et la 19 repose ensuite les heures dérivées.

Elle ne remplace aucune fonction et n'entre dans aucun conflit d'ordre avec les 15 à 18.
Elle annonce **« 9 Grand(s) Prix corrigé(s) »** au premier passage — neuf et non onze,
Austin et le Mexique ayant un écart réel de 22 h — puis « rien à corriger ». Elle rend
enfin un tableau de contrôle : **la colonne `ecart` est celle qui parle**, douze fois
« 22:00:00 » signifierait que tout est encore dérivé.

> **Elle va de pair avec la `0.57.0` du backend**, qui retire le repli du scraper. Sans ce
> déploiement Railway, le scraper réécrira `date_course − 22h` par-dessus la correction au
> premier passage, et il n'y a **pas** d'ordre à respecter entre les deux : jouer la
> migration d'abord ou déployer d'abord revient au même, mais **les deux sont nécessaires**.

> **Éprouvée sur un PostgreSQL 16 jetable.** Les deux chemins convergent, la migration est
> idempotente, une heure annoncée par Unibet n'est jamais réécrite, une ligne déjà adoptée
> est bien retrouvée, et les onze instants finaux concordent au caractère près avec
> `GP_2026.seances.qualifications` — croisés par script, pas relus à l'œil.

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

> **La migration 19 en règle la moitié.** `chargerGrandsPrixRestants` comptait les lignes
> en base et n'en trouvait qu'une ; il en trouve maintenant onze. **Mais `Accueil.jsx`
> affiche toujours la constante** — c'est le branchement de l'écran qui reste à faire, pas
> la donnée.

### 1.6 bis Vérifier « Ouverture dans » contre un vrai samedi de qualifications

La version `0.57.0` fait décompter au widget d'accueil **`date_qualifications + 2h`** tant
que les cotes ne sont pas arrêtées. Le délai est celui du job du samedi, pas une donnée
servie : c'est une **prévision**, et elle n'a jamais été confrontée à un vrai week-end.

Deux choses à regarder le premier samedi :

- **La bascule.** « Ouverture dans » doit céder la place à « Fermeture dans » quand le
  statut passe à `cotes_figees`, pas quand le décompte atteint zéro — le statut ne change
  qu'en base, et c'est le rafraîchissement du cache qui le rapporte. Un écart de quelques
  minutes entre les deux est normal ; un écran resté sur « Ouverture / À confirmer » après
  un scraping réussi ne l'est pas.
- **Le retard du job.** S'il tourne systématiquement plus de deux heures après les
  qualifications, `DELAI_OUVERTURE_MS` (`lib/format.js`) est à revoir — c'est la seule
  valeur à toucher, elle n'est écrite qu'une fois.

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
| **La rangée des derniers vainqueurs** (`0.59.0`) | quatrième rangée `snap-x` du projet, et la première à porter cinq SVG de voiture — soit cinq dessins de quarante formes qui défilent à l'inertie. C'est aussi la seule dont le calage a demandé `scroll-pl-4` : vérifier que la première carte s'aligne bien sur le reste de la page **après** un défilement puis un retour au début, pas seulement au premier rendu |
| **Les deux liens d'une carte de calendrier** (`0.59.0`) | le corps et la bande d'action sont deux `<a>` frères dans un même `<article>`. Vérifier qu'un appui sur la bande n'ouvre pas la fiche, qu'un appui près de la couture ne se trompe pas de destination, et que `pressable-large` enfonce bien la **carte entière** dans les deux cas — c'est `:active` remontant aux ancêtres, et Safari iOS est le seul juge |
| **Le lavis des drapeaux à 8 %** (`0.62.0`) | vingt-deux rangées portant chacune un SVG de drapeau en `absolute inset-0`, sous un SVG de voiture. Deux choses à regarder : le coût de composition au défilement d'une liste de vingt-deux couches superposées, et surtout **la lisibilité du lavis en plein soleil** — 8 % sur blanc est un jugement d'écran de bureau autant qu'un rapport de contraste, et c'est le même doute que l'opacité `0,4` des cartes passées (§3.14) |
| **Le drapeau japonais étiré** (`0.63.0`) | seizième drapeau de la planche, et le **premier dont l'emblème est une charge et non une bande**. `preserveAspectRatio="none"` étire son disque en ellipse large sur une rangée de 5,2:1 : vérifié à l'image en navigateur, jamais sur un écran de téléphone en plein soleil, où il ne reste qu'un lavis rosé de 8 % |
| **Les vingt-deux voitures d'un classement** (`0.62.0`) | chaque rangée dessine une livrée complète, soit quarante formes × vingt-deux sur un seul écran qui défile. La vue piste en montre seize et n'a jamais été éprouvée non plus : c'est le plus gros nombre de dessins de voiture qu'un écran du projet ait porté |

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

> ✅ **Le défilement d'ouverture est fait** (`0.54.0`), et **la profondeur aussi**
> (`0.59.0`) : chaque carte ouvre désormais quelque chose. Ce qui reste est l'en-tête
> collant — l'écran n'a toujours pas de titre qui accompagne le défilement, là où l'écran
> de détail, lui, en a un.

### 3.8 Lisibilité des tracés sur les drapeaux clairs

Le trait blanc à 60 % vaut **2,44:1 au pire** (Brésil). Lisible mais discret. Deux leviers
d'une ligne, **dans cet ordre** : monter le trait à 70 %, ou approfondir la surcouche de 15
à 25 %. **Ne pas toucher au voile** — il est calculé pour le texte.

### 3.8 bis L'Australie n'a pas de drapeau, et deux pilotes en manquent

`NATIONALITES` (`DrapeauxGP.jsx`) déclare l'Australie **sans drapeau**, délibérément : sa
croix du Sud n'a pas de description que le CSS ou une spécification simple puisse rendre
sans l'approximer, et un drapeau approximé est ce que `DrapeauxSVG.jsx` existe pour ne plus
faire (version `0.24.0`). **La Finlande a rejoint ce cas en `0.60.0`** — sa croix nordique
n'est pas davantage descriptible par un dégradé — de sorte que les cartes de Piastri, de
Ricciardo et de Bottas restent sur du blanc là où les neuf autres nationalités portent un
lavis à 18 %.

**Ce n'est pas une panne** — le gentilé est écrit sous le nom, et le fond n'a jamais porté
l'information. C'est une irrégularité visible dans une rangée, rien de plus.

Deux façons de la lever, dans cet ordre de préférence :

1. **Ajouter le drapeau à `assets/flags.svg`** et l'extraire par script, comme les six
   autres. C'est la voie du projet, et elle ne demande aucune exception.
2. **Le construire depuis la spécification officielle** (Union Jack au canton, étoile du
   Commonwealth à sept branches, cinq étoiles de la croix du Sud), comme l'a été le
   Royaume-Uni en `0.59.0`. Les coordonnées des étoiles se calculent ; **encore faut-il
   disposer du texte du Flags Act**, sans quoi on retombe dans l'approximation.

### 3.8 quater Deux systèmes de drapeaux coexistent — écart signalé (`0.62.0`)

Depuis la `0.62.0`, le projet peint des drapeaux de **deux** façons, et c'est un écart au
principe « une source unique par question » (CLAUDE.md §6) qu'il faut connaître :

| Question | Propriétaire | Comment |
|---|---|---|
| le drapeau d'un **pays hôte**, et celui d'un **vainqueur de circuit** | `DRAPEAUX` / `NATIONALITES` (`DrapeauxGP.jsx`) | dégradés CSS et sept dessins extraits de `assets/flags.svg` |
| le drapeau d'un **pilote de la grille** | `lib/nationalites.js` + `composants/DrapeauxPilotes.jsx` | seize SVG de `country-flag-icons`, par code ISO |

**Ce n'est pas une duplication gratuite.** Le champ `couleurs` de `DRAPEAUX` n'est pas
décoratif : c'est la matière du calcul de `voileNecessaire`, qui dérive l'opacité du voile
de la bande la plus claire de chaque drapeau (design-system §5). Un SVG importé d'une
bibliothèque **ne peut pas alimenter ce calcul** — il n'expose pas ses bandes. Les deux
systèmes répondent donc à deux questions qui n'ont pas les mêmes besoins : là-bas un
drapeau à pleine intensité sous du texte blanc, ici un lavis à 8 % sous du texte foncé.

**Ce que la `0.62.0` règle au passage, et qu'il faut noter :** les seize pays de la grille
2026 incluent l'Australie et la Finlande, les deux nationalités que §3.8 bis laissait sans
fond. **Elles ont maintenant un drapeau exact — mais seulement sur l'écran de résultats.**
Les cartes de vainqueur de `VainqueursCircuit` restent sur du blanc, parce qu'elles
passent par l'autre système. §3.8 bis n'est donc **pas** clos.

**La façon de le clore un jour**, et elle lève les deux points à la fois : faire de
`country-flag-icons` la source de tous les drapeaux de **nationalité** (jamais des pays
hôtes, qui ont besoin du voile), et faire pointer `NATIONALITES` vers `lib/nationalites.js`
pour le dessin en gardant ses `couleurs` pour le calcul. Le chantier touche
`VainqueursCircuit` et `DetailGp` : hors du périmètre de la `0.62.0`, qui ne devait
toucher qu'un écran.

### 3.8 quinquies `nationalites.js` et `pilotes.py` ne décrivent plus la même grille (`0.63.0`)

> ✅ **Réglé côté backend en version `0.66.0`.** `Pilote(22, "Yuki", "Tsunoda", "TSU",
> "Racing Bulls", "JPN")` est entré dans `GRILLE`, et `"JPN": ("Japonais", "Japonaise",
> "Japon")` dans `NATIONALITES` — **`JPN`, pas `JAP`**, comme l'avertissement ci-dessous le
> demandait. Une victoire Tsunoda se juge désormais. **Il reste à déployer sur Railway**
> (§1.4) : tant que ce n'est pas fait, le paragraphe ci-dessous décrit encore la
> production.
>
> **Un écart de sens inverse s'est ouvert au même moment** : `lib/ecuries.js`, lui, ne
> connaît toujours pas Tsunoda et range encore Lawson chez Racing Bulls — voir §3.8 sexies.
> Et la note d'écart en tête de `lib/nationalites.js` est à retirer quand le frontend sera
> repris.

Yuki Tsunoda a été ajouté à `lib/nationalites.js` — numéro 22, `JP`, Japon — parce qu'il
figurait au **classement** d'un Grand Prix sans y porter de drapeau. Il n'est **pas** dans
`backend/app/calcul/pilotes.py`, dont la grille tient les vingt-deux libellés relevés sur
les vraies cotes Unibet du GP Pays-Bas 2026.

Les deux tables sont documentées comme contreparties l'une de l'autre. **Elles divergent
maintenant d'une ligne**, et l'écart est délibéré :

- elles ne servent pas la même question — `nationalites.js` habille un classement déjà
  publié, `pilotes.py` rapproche des libellés Unibet pour **calculer des points** ;
- seule la seconde demande un déploiement Railway, et la `0.57.0` du backend n'y est
  toujours pas déployée (§1.4).

**Ce que l'écart coûte, précisément.** Si Tsunoda gagnait une course, le marché
« nationalité du vainqueur » ne saurait pas le juger et laisserait les pronostics à `NULL`
— donc **rattrapables par un rejeu**, jamais à `0` (règle 4.1). Ses libellés Unibet, eux,
sont retrouvés par les cinq clés dérivées de `points._indexer_pilotes` : le défaut ne
touche que la nationalité.

**Ce qu'il faut faire, avec le prochain déploiement backend :** ajouter
`Pilote(22, "Yuki", "Tsunoda", "TSU", "<écurie>", "JAP")` à `GRILLE` et
`"JAP": ("Japonais", "Japonaise", "Japon")` à `NATIONALITES` — l'écurie est à relever sur
`/drivers` d'OpenF1, elle n'est pas devinable ici. Le code CIO du Japon est `JPN` et non
`JAP` : **à vérifier sur la source avant de l'écrire**, c'est exactement le genre de
correspondance que §3.15 dit de ne pas deviner.

### 3.8 sexies `ecuries.js` ignore les remplacements Lawson / Tsunoda (`0.66.0`)

La version `0.66.0` a porté les deux remplacements temporaires dans
`backend/app/calcul/pilotes.py` — Lawson (30) chez Red Bull à la place de Hadjar (6),
Tsunoda (22) chez Racing Bulls à la place de Lawson. **Le commit est backend seul**, parce
que c'est le backend qui calcule des points et lui seul qui demande un déploiement Railway.

`frontend/src/lib/ecuries.js` range donc encore `I.Hadjar` chez Red Bull, `L.Lawson` chez
Racing Bulls, et **ne connaît pas `Y.Tsunoda` du tout**.

**Ce que l'écart coûte, précisément — il est cosmétique, jamais un point.** Aucune couleur
n'entre dans le calcul : le marché « Ecurie Vainqueur » et les marchés « les 2 voitures »
lisent l'écurie **dans le classement OpenF1**, pas dans une table statique. Reste l'écran :

- le widget de cote peindra Lawson au **cyan Racing Bulls** au lieu du bleu Red Bull —
  c'est le cas le moins bon, une teinte *fausse* plutôt qu'absente ;
- Tsunoda ressortira **sans teinte**, ce qui est le repli prévu par `couleurEcurie` et se
  voit à l'écran ;
- le classement de course n'est pas touché (il passe par `ecurieDuLibelle` sur la forme
  OpenF1), ni les drapeaux (`nationalites.js` connaît Tsunoda depuis la `0.63.0`).

**Ce qu'il faut faire :** dans `GRILLE` de `lib/ecuries.js`, `"Red Bull": ["M.Verstappen",
"L.Lawson"]` et `"Racing Bulls": ["A.Lindblad", "Y.Tsunoda"]`, en gardant les titulaires en
commentaire comme le fait `pilotes.py`. Et **retirer la note d'écart** en tête de
`lib/nationalites.js`, qui décrit un désaccord désormais refermé.

### 3.8 quater bis Aucun test ne garde la concordance des grilles

`docs/ecuries.md` décrivait un test qui lit `backend/app/calcul/pilotes.py` et compare les
pilotes ligne à ligne. **Il n'existe pas** : le dépôt ne porte aucune infrastructure de
test — ni `vitest` ni `pytest` dans les dépendances, aucun fichier de test dans l'arbre ni
dans l'historique. Vérifié, pas supposé.

C'est précisément ce trou qui a laissé §3.8 quinquies s'ouvrir, puis §3.8 sexies. Les
trois tables — `pilotes.py`, `lib/ecuries.js`, `lib/nationalites.js` — décrivent les mêmes
pilotes et sont tenues à la main, sans que rien n'annonce leur divergence.

> **Le test utile est celui qui LIT `pilotes.py`**, la seule des trois qui attribue des
> points, et qui compare écurie et nationalité pilote par pilote. Écrit en noms d'écuries
> et non en hexadécimaux, il survit à tout changement de palette.

### 3.8 ter Deux rangées horizontales calent leur première carte hors de l'alignement

Le rendu de la `0.59.0` a montré que `-mx-4 px-4` **ne suffit pas** sur une rangée
`snap-mandatory` : avec `scroll-padding: auto`, une carte `snap-start` s'aligne sur le bord
du scrollport, donc sur la boîte de rembourrage, et le navigateur pose `scrollLeft = 16` au
premier calcul. La première carte revient coller le bord de l'écran, seize pixels à gauche
de tout le reste de la page. Mesuré : `li.left = 0` pour un `ul` dont le `padding-left`
calculé vaut bien `16px`.

> **`VainqueursCircuit` n'est plus concernée depuis la `0.60.0`** : elle est devenue une
> **grille de deux colonnes**, donc elle n'a plus de bord de calage du tout. Le
> `scroll-pl-4` est parti avec le défilement. Le défaut décrit ci-dessus reste entier pour
> les deux rangées ci-dessous, et c'est chez elles qu'il faut le lire.

**Les deux rangées plus anciennes ne portent pas le correctif** :

| Où | Classe |
|---|---|
| Favoris du tableau des cotes | `ecrans/Cotes.jsx` |
| Aperçus de la page publique | `composants/ApercusApp.jsx` |

Elles portent exactement le même `-mx-4 px-4`, donc très probablement le même décalage.
**Elles n'ont pas été retouchées** : ce sont deux écrans qui marchent, et la correction
demande le même rendu de vérification contre la feuille compilée — un défaut de géométrie
pure ne se constate pas autrement.

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

### 3.15 Aucun libellé de nationalité n'a été vu en vrai — seize pays écrits à l'aveugle

`NATIONALITES` accepte le peuple et le pays (« Néerlandais », « Pays-Bas ») parce que **rien
ne dit lequel des deux Unibet écrit**. Les seize entrées couvrent la grille de
`pilotes.py` — **le Japon en fait partie depuis la `0.66.0`** (§3.8 quinquies) ; aucune
n'a été confrontée à un vrai marché. Une issue inconnue est journalisée en toutes lettres et
laisse `NULL` — **c'est cette ligne qu'il faut chercher** après le premier vrai marché de
nationalité, comme pour « écart du gagnant ».

`POST /jobs/resultats/{gp_id}/test` les confronte sans rien écrire. Et **la table est à
mettre à jour à chaque saison**, au même titre que la grille des pilotes : le garde-fou
numéro + nom de famille fait qu'une table périmée ne rend rien plutôt que de prêter au
nouveau titulaire du 12 la nationalité d'Antonelli.

**Une forme a été vue en vrai, et ce n'était pas une nationalité** : l'issue « Autres », au
GP des Pays-Bas. Elle ne se range dans aucun code et se juge contre les issues sœurs du
marché — traitée en v`0.56.0` (`bugs-connus.md` §25). Les quinze pays, eux, restent à
confronter.

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

### 4.8 Deux propriétaires pour la mise en forme d'un pronostic (`0.63.0`)

`decrirePronostics` (`lib/pronostics.js`) et `public.pronostics_du_joueur` (migration
`20260813205200`) rendent **les mêmes huit champs**, pour **le même écran**, à deux sections
d'écart : la première quand les résultats d'un Grand Prix sont ouverts depuis le calendrier,
la seconde quand ils le sont depuis un championnat. C'est un écart au principe « une source
unique par question », signalé au moment de l'écrire et documenté des deux côtés.

**Ce n'était pas le choix de conception, c'était le choix de calendrier.** L'option propre
— faire servir `pronostics_du_joueur(auth.uid(), gp)` par
`GET /grands-prix/{id}/resultats` quand aucun `championnat_id` n'est fourni — garde un seul
propriétaire et ne demande aucune recopie. Elle a été écartée parce qu'elle déplace le
correctif sur Railway, où la `0.57.0` du backend n'est toujours pas déployée : la section
serait restée exactement aussi vide qu'avant.

**Le symptôme d'une divergence serait discret** : un même pronostic affichant deux
potentiels — ou deux libellés de marché — selon la porte par laquelle on est entré. Le seul
champ qui prête déjà à confusion est `points`, la cote de la **première** issue seulement,
podium compris : les deux côtés le rendent ainsi, et le jour où la somme des deux cotes est
retenue, elle se décide **en SQL** et se recopie ici.

**À résorber au prochain déploiement backend**, en même temps que §3.8 quinquies : les deux
dettes de cette version se ferment par le même geste.

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
