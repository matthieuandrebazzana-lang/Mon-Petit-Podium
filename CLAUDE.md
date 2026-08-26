# CLAUDE.md — Greed F1

> Contexte permanent. À lire **en premier** à chaque session.
> Le détail vit dans `docs/` — voir la section « Documentation ».

---

## 1. Le projet

**Greed F1** est une PWA de pronostics Formule 1 entre amis. Un utilisateur crée un
**championnat**, partage un code à 6 caractères, et ses amis le rejoignent. Avant chaque
Grand Prix chacun fait ses pronostics ; les points rapportés dépendent des **cotes réelles
des bookmakers**. Après la course les résultats sont récupérés automatiquement et les
points attribués.

L'app est **ouverte au public**, pas seulement à un cercle d'amis : l'authentification et
la sécurité doivent être traitées en conséquence. La cible est **Safari iOS** — toutes les
décisions techniques s'y arbitrent.

*L'app s'appelait « Mon Petit Podium » jusqu'à la version `0.34.0`.*

## 2. Stack et déploiement

| Couche | Techno | Hébergement |
|---|---|---|
| Frontend | React 19 + Vite 8 + Tailwind CSS 4 (PWA) | **Vercel** — `https://mon-petit-podium.vercel.app` |
| Backend | FastAPI + APScheduler | **Railway** (plan gratuit, un seul processus) |
| Base + Auth | PostgreSQL | **Supabase** |

Monorepo : `frontend/`, `backend/`, `supabase/migrations/`, `assets/`, `maquettes/`, `docs/`.

---

## 3. Règles critiques

Ce qui doit être su avant de toucher au code, quel que soit le sous-système.

### 3.1 Les points sont des entiers — jamais une cote

> **Points = cote × 10, arrondie.** Une cote de 2,80 rapporte **28 points**.

**On n'affiche JAMAIS une cote brute.** Nulle part on n'écrit « ×2,80 » — on écrit
« 28 pts ». Sans exception. `cotes.valeur` est déjà le nombre de points : **rien en base
ne stocke une cote**. `lib/format.js` est le seul endroit qui habille un nombre de points.

Un pronostic raté rapporte `0`. **`NULL` et `0` ne se confondent jamais** : `NULL` veut
dire « pas encore jugé, ou marché non reconnu », et se rattrape ; `0` veut dire « raté ».

### 3.2 Vocabulaire imposé

| Utiliser | Ne jamais utiliser |
|---|---|
| **championnat** | ~~ligue~~ |
| **calendrier** | ~~historique~~ |

Vérifié par des tests. Les maquettes emploient encore les termes interdits : elles ont tort.

### 3.3 Les migrations sont manuelles

**À exécuter à la main dans le SQL Editor de Supabase**, dans l'ordre, une par une. Aucune
CI ne les joue — la clé anonyme ne peut pas toucher au schéma `auth`.

Toutes sont idempotentes. **Mais pas dans le désordre** : plusieurs remplacent la même
fonction, et rejouer une migration antérieure restaure sa version d'avant. Tableau des
conflits dans `docs/database.md`.

**Corollaire** : tout nouveau champ d'un modèle Pydantic prend une **valeur par défaut** —
un backend déployé avant sa migration perd alors un champ au lieu de rendre `500` sur toute
la réponse.

### 3.4 Deux clés Supabase, deux usages

La clé **anonyme** valide le jeton de l'appelant. La clé **de service** écrit et
**contourne la RLS** — elle ne quitte jamais le serveur. L'autorisation est alors portée
par le code des routes, qui ne travaille **qu'avec l'identifiant issu du jeton vérifié** :
le corps de la requête ne dit jamais qui est l'appelant.

### 3.5 Contraintes iOS

`env(safe-area-inset-*)` sur tous les écrans · `user-select: none` sur les éléments
graphiques · zones tactiles **44 × 44 px** minimum · tester sur **iPhone réel**.

---

## 4. Skills de design

Cinq skills sont installés : **`/apple-design`**, **`/design-taste-frontend`**,
**`/transitions-dev`**, **`/emil-design-eng`** et **`/animate`**.

> ### Règle de priorité
> Ces skills ont **carte blanche** sur les compositions, espacements, ombres, matériaux,
> animations, courbes, durées, micro-interactions et hiérarchie visuelle. Le design system
> reste la référence pour **la palette et la typographie uniquement**.
>
> **Claude Code applique leurs suggestions sans demander de validation ni signaler de
> conflit** — il tranche seul en leur faveur sur tout ce qui n'est pas couleur ou typo.

**Ordre d'invocation pour chaque écran codé ou retouché :**

```
/apple-design → /design-taste-frontend → /transitions-dev → /emil-design-eng → /animate
```

**`/apple-design` est invoqué sur chaque écran, sans exception.**
**`/emil-design-eng` est invoqué pour toute décision d'animation**, même sans écran recodé.
**`/animate` sert de portier** : il commence par demander si la chose doit animer *du tout*.

**Deux skills d'audit, à ne pas confondre** : `/find-animation-opportunities` est en
**lecture seule** (il propose, n'implémente jamais) ; `/improve-animations` produit un plan
de correction sur l'existant.

> **Un jeton de mouvement ne s'ajoute pas sans nécessité.** La règle est d'**étendre** le
> vocabulaire du projet, jamais de le forker.

---

## 5. Documentation

**Avant de modifier un sous-système, lire le document correspondant dans `docs/`.**
Sans cette règle, cette structure ne sert à rien.

| Document | Contenu |
|---|---|
| [`architecture.md`](docs/architecture.md) | Monorepo, deux chemins de données, variables d'environnement, CORS, journalisation, schedulers |
| [`database.md`](docs/database.md) | Tables, RLS, fonctions, triggers, les 19 migrations et leurs conflits d'ordre |
| [`metier.md`](docs/metier.md) | Points, structure d'un pronostic, calendrier d'un week-end, validation, départage |
| [`glossary.md`](docs/glossary.md) | Vocabulaire canonique et termes à ne jamais renommer |
| [`design-system.md`](docs/design-system.md) | Palette, typographie, formes, élévation, contraste, matériaux, mouvement |
| [`scraper.md`](docs/scraper.md) | Unibet, OpenF1, idempotence, jobs, calcul des points, routes de rattrapage |
| [`composants.md`](docs/composants.md) | Composants importants, composants à risque, planches SVG, modules `lib/` |
| [`calendrier.md`](docs/calendrier.md) | Les deux calendriers, la liste statique, les quatre états |
| [`ecuries.md`](docs/ecuries.md) | Onze écuries, grille 2026, couleurs, livrées et skins |
| [`bugs-connus.md`](docs/bugs-connus.md) | Symptôme, cause **réelle**, correctif, ce qu'il ne faut pas refaire |
| [`decisions.md`](docs/decisions.md) | Pourquoi les choix ont été faits, alternatives écartées, conséquences |
| [`roadmap.md`](docs/roadmap.md) | Ce qui reste à faire |

**Autres ressources** : `maquettes/` (16 écrans HTML de la v1 — **ouvrir la maquette avant
de coder un écran**) et `assets/` (planches SVG source, extraites **par script**, jamais
recopiées à la main).

---

## 6. Méthode de travail

**Avant de coder.** Lire le document `docs/` du sous-système concerné, et la maquette si
c'est un écran. Vérifier dans `bugs-connus.md` que le défaut visé n'a pas déjà une cause
documentée — **elle est rarement celle qu'on croit**.

**Une source unique par question.** Toute question à laquelle plusieurs endroits doivent
répondre de la même façon a exactement **un** propriétaire. Deux textes écrits séparément
divergent au premier ajustement, et le symptôme est toujours discret.

**Le contraste se mesure, il ne se choisit pas.** Les valeurs prescrites à l'œil se sont
révélées fausses plus souvent que justes. Texte ordinaire 4,5:1 · grand texte 3:1 ·
élément graphique porteur de sens 3:1. Les écrans ne choisissent jamais leur encre
eux-mêmes.

**Vérifier avec la feuille CSS compilée.** Un rendu HTML vérifie la structure et le
contenu, **jamais la mise en page**. Deux classes de défauts lui échappent par
construction : les règles CSS qui ne s'appliquent pas, et tout ce qui tient à la géométrie.
Six défauts n'ont été trouvés qu'ainsi.

**Signaler plutôt que trancher seul** quand une demande contredit ce fichier ou qu'une
valeur mesurée contredit une valeur prescrite. Écrire l'écart et sa raison.

**Ne pas supprimer le code qui redevient utile.** Le code remplacé mais éprouvé reste en
place, simplement non monté — le bundler l'élimine du build.

---

## 7. Règles permanentes

### Version

À **chaque commit qui modifie l'application**, incrémenter la version affichée en bas de
l'accueil (`frontend/package.json`).

> **La version du backend (`backend/app/config.py`) ne bouge QUE si du code backend
> change.** La faire bouger sur un commit frontend laisserait croire à un déploiement
> Railway qui n'a pas eu lieu.

### Documentation

Après chaque tâche terminée, mettre à jour **le document `docs/` concerné** et
`docs/roadmap.md`. **Dans le même commit que le code**, jamais dans un commit séparé.

### Git

- **Ne jamais ajouter de ligne `Co-Authored-By`** — Vercel bloque les déploiements
  automatiques sur le plan Hobby lorsqu'un collaborateur externe est détecté.
- Messages de commit **concis, en français**.
- Après chaque commit, **pousser immédiatement** : `git push origin main`. Ne jamais
  attendre de feu vert.

---

## 8. État d'avancement

**Version `0.62.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées. **Le backend reste à `0.57.0`** — la
`0.62.0` ne touche que le frontend, et la route des résultats servait déjà tout ce que
l'écran refondu affiche. **La `0.57.0` du backend reste à déployer sur Railway**, sans quoi
le scraper réécrira l'heure que la migration 20 vient de corriger.

### Un écran de résultats qui répond aux deux questions dans l'ordre où on se les pose

L'écran des résultats d'un Grand Prix ouvrait sur le podium de la course et enterrait les
pronostics du joueur dans un accordéon, sous le classement des membres. Il ouvre maintenant
sur **« Mes résultats »** — le total, puis un widget par pronostic avec son marché, sa
sélection et son verdict — puis sur **« Résultats du GP »**, le classement complet, une
ligne par pilote avec sa position, la voiture de son écurie, son nom, ses points FIA et
**le drapeau de sa nationalité en fond à 8 %**.

**Le seul vrai changement de comportement est que « Mes résultats » ne dépend plus de
`disponible`.** La route sert les pronostics des membres qu'un classement ait été récupéré
ou non ; l'ancien écran les cachait tous derrière ce drapeau et laissait le joueur, avant
la course, sans aucune trace de ce qu'il avait validé. Les points s'y affichent alors comme
**potentiels**, ce que `PastillePoints` savait déjà dire — son troisième état, le beige,
existait pour exactement ça et n'avait jamais servi ici.

### Quinze drapeaux exacts valent mieux que sept approximés

`assets/flags.svg` ne dessine que des pays **hôtes**, et la grille 2026 demande **quinze**
pays. Sept d'entre eux — l'Australie, la Nouvelle-Zélande, le Brésil, le Mexique, le
Canada, la Thaïlande, l'Argentine — n'ont aucune description qu'un dégradé sache poser sans
l'approximer. C'est la règle de `DrapeauxSVG.jsx` qui tranche, et elle tranche **pour** la
bibliothèque : le choix était entre approximer sept drapeaux et en prendre quinze exacts.

> **Écart signalé (§6) : ce n'est pas `react-world-flags`.** La demande le nommait « de
> préférence », et il ne convient pas pour deux raisons **mesurées** : son `dist` est un
> lot UMD de **3,6 Mo** qui embarque les 250 drapeaux en data-URI sans découpage possible,
> et son code les résout par `require.context`, une API propre à **webpack** que Vite
> n'implémente pas. `country-flag-icons` fait ce que la demande décrit — « import SVG par
> code ISO 3166-1 alpha-2 » — en ESM pur et `sideEffects: false` : le lot passe de 818 724
> à 834 181 octets, soit **+15,5 Ko pour quinze pays**, et le contrôle confirme qu'aucun
> des 250 autres n'entre.

> **Second écart (§6) : il y a une TROISIÈME section, et elle est conservée.** La demande
> décrit deux sections et ne dit rien du classement des membres du championnat — ni de le
> garder, ni de le retirer. Le retirer aurait supprimé, sur la foi d'un silence, la seule
> surface où l'on voit ce que ses amis ont pronostiqué. « Mes résultats » répond à « qu'ai-je
> marqué », pas à « qui a gagné entre nous ».

> **Troisième écart (§6) : ni « 20 pilotes », ni le barème en dur.** La grille 2026 en
> compte **vingt-deux**, et l'écran rend toutes les lignes que la course a publiées :
> couper à vingt aurait effacé deux classés, compléter à vingt aurait inventé des lignes.
> Et `points_fia` arrive d'OpenF1 plutôt que d'être déduit de la position, parce qu'il sait
> ce que la position seule ne dit pas — le point du sprint, une pénalité appliquée après
> l'arrivée, une disqualification. **Le barème aurait eu tort d'abord sur le week-end
> sprint de Singapour.**

### Le rendu contre la feuille compilée a trouvé deux défauts, et le second est le drapeau

Neuvième fois, et cette fois avec un vrai navigateur : les composants réels rendus sous la
feuille compilée, mesurés à 320, 375 et 430 px, puis **regardés en image**.

**`preserveAspectRatio="slice"` était le mauvais réflexe, et il venait du reste du projet.**
Une rangée de classement fait **343 × 65,5 px**, soit un rapport de **5,2:1**, là où un
drapeau en fait 1,5:1. `slice` — le pendant d'`object-fit: cover`, la valeur que
`DrapeauxSVG` et `VainqueursCircuit` emploient — recadre donc sur la **bande centrale** et
jette tout le reste : l'Allemagne ressortait **entièrement rouge**, indistinguable d'un pays
à drapeau rouge, et l'Espagne entièrement jaune. Le drapeau ne disait plus la nationalité,
ce qui est la seule chose qu'on lui demande. **Rien dans le JSX ne le laissait deviner**, et
la mesure de contraste, elle, passait très bien.

`none` rend les deux échelles indépendantes : toutes les bandes survivent, seule leur
proportion s'étire. **C'est exactement l'arbitrage de `FondPiste`** — un dessin qui doit
couvrir une boîte dont le rapport de forme n'est pas le sien. Et **`VainqueursCircuit` garde
son `slice`** : ses cartes sont presque carrées, le recadrage y mord de quelques pixels. Ce
n'est pas la même boîte, donc ce n'est pas la même réponse.

Le premier défaut était plus ordinaire et ne se voyait pas davantage : **à 320 px, le
sous-titre de « Mes résultats » se tronquait.** Les trois sous-titres ont été raccourcis
jusqu'à tenir sur le plus petit iPhone.

### Le contraste d'un lavis importé ne se dérive pas, il se mesure

`voileNecessaire` calcule l'opacité d'un voile depuis la bande la plus claire de chaque
drapeau — **et il ne peut rien faire ici** : un SVG importé d'une bibliothèque n'expose pas
ses bandes. Les quinze drapeaux ont donc été ouverts et mesurés **couleur par couleur, par
script**, y compris les deux que la lecture rate — le `fill="red"` en mot-clé du Canada, et
la bande noire allemande qui **n'a aucun attribut `fill`** et tient son noir du défaut SVG.

Le pire substrat est ce noir, composé à 8 % sur blanc en `#EBEBEB` : l'encre `texte` y vaut
**14,60:1**, le marron `secondaire` **8,86:1**, le bordeaux `primaire` **9,13:1**.

> **`texte-doux` n'y tient pas — 2,39:1**, et c'est ce qui décide de la ligne : le prénom et
> l'écurie passent au marron `secondaire`. Le design system signale déjà ce défaut deux
> fois, et une rangée de classement est exactement « une phrase qu'on vient lire ».

> **La bande allemande sans `fill` est le piège du fichier.** Elle **hérite** de tout `fill`
> qu'un ancêtre déclarerait : poser une couleur sur le calque du lavis repeindrait le noir
> allemand sans qu'aucune ligne de JSX ne le laisse voir. Aucun `fill` ni `color` ne doit
> donc être posé sur un conteneur de ces SVG.

### Deux tables de plus, et aucune n'est une seconde source

`lib/nationalites.js` est la **contrepartie frontend** du champ `nationalite` de
`backend/app/calcul/pilotes.py`, comme `lib/ecuries.js` l'est déjà de sa grille. Les codes
ne peuvent pas être les mêmes — le backend emploie le CIO à trois lettres parce que c'est la
langue du sport, le frontend l'ISO alpha-2 parce que c'est ce qu'une planche de drapeaux
comprend — et la conversion est écrite pilote par pilote plutôt que dérivée d'une table CIO
→ ISO : quinze correspondances ne valent pas une seconde table à tenir, et trois ne se
devinent pas (NED → NL, GER → DE, MON → MC).

**Elle porte le garde-fou de saison d'`alias_unibet`, transposé** : numéro **et** nom de
famille doivent concorder. Si le 12 n'est plus Antonelli, la table périmée ne collera pas le
drapeau italien sur son successeur — elle ne rendra rien. **Une ligne sans drapeau se voit ;
une ligne sous le mauvais drapeau ne se voit pas.**

`ecurieDuLibelle` (`lib/ecuries.js`) et `livreeDeLEcurie` (`lib/livrees.js`) répondent au
troisième consommateur d'une question que le module traitait déjà : le classement sert
l'écurie **dans la forme d'OpenF1** — « Red Bull Racing », « Haas F1 Team » — et la ligne
doit en tirer la livrée à dessiner. Le rapprochement n'est pas réécrit : il part des **mêmes
trois tables** que la couleur, si bien qu'une douzième orthographe d'Unibet demandera une
seule ligne pour les deux réponses.

> **Vérifié par script, pas à l'œil** : les onze écuries d'OpenF1 rendent bien onze slugs de
> livrée, les vingt-deux pilotes rendent bien leur pays, les six cas du garde-fou tombent
> juste, et les quinze codes déclarés sont exactement les quinze drapeaux dessinés.

### Rien n'anime, et c'est la décision

L'écran entre sous `.t-ecran` et ses sections sous `.t-stagger-line` ; l'accordéon des
membres garde son `.t-acc`. **C'est tout, et aucun jeton de mouvement n'entre.** Le verdict
d'un pronostic est **déjà calculé quand l'écran s'ouvre** : le révéler par une animation
raconterait un suspense qui n'existe pas, et le joueur revient sur cette page plusieurs fois
dans la semaine. Vingt-deux lignes de classement qui entreraient en cascade mettraient plus
d'une seconde à se poser sur une liste qu'on vient parcourir de haut en bas.

### `0.61.0` — une heure devinée chassait une heure relevée, et la table juste était sous les yeux

La fiche du GP d'Italie annonçait des qualifications à **17h00** pour une séance qui se
court à **16h00**. Neuf des onze Grands Prix restants étaient touchés, de une à quatre
heures.

**`GP_2026` était déjà juste** — la `0.60.0` avait relevé ces onze heures — et les corriger
n'aurait rien corrigé du tout. `seancesDuGp` **préfère l'heure de la base** à celle de la
table statique pour les deux séances que la base connaît : c'est la règle voulue de la
`0.59.0`, et elle suppose que la base dise vrai. La base disait faux par **deux chemins qui
se renforçaient** — la migration 19 insérait `date_course − 22h`, et le scraper
réappliquait le même calcul à chaque passage. Corriger l'un sans l'autre ne suffisait pas.

**Le motif d'origine était bon, la règle était fausse.** La migration 19 réutilisait
délibérément le repli du scraper pour n'avoir qu'une seule règle et un seul propriétaire —
la bonne réaction, appliquée à une valeur qui ne la méritait pas. **Partager une constante
fausse la propage au lieu de la corriger.** Et l'écart réel n'est pas une constante : 23 h
sur huit week-ends, 22 h sur deux (Austin et le Mexique), 24 h au Brésil, **26 h à Las
Vegas** dont les qualifications se courent le vendredi soir.

**Un repli qui s'applique tout le temps n'est plus un repli.** Il était écrit pour le cas
rare et journalisé en `warning` ; le constat de terrain d'août 2026 dit qu'Unibet n'expose
aucun événement de qualification, donc il était le **régime normal**. Un avertissement qui
sort à chaque passage ne se lit plus comme une alerte.

**Le dommage n'était pas la devinette, c'était l'écriture.** L'upsert écrivait
`date_qualifications` à chaque scraping, donc remplaçait une heure relevée à la main par un
calcul. Le correctif n'écrit plus rien quand Unibet se tait : la clé est absente de la
ligne, et la valeur en base survit. C'est « on se ferme sur une donnée qu'on n'a pas »
appliqué à l'**écriture** plutôt qu'à la lecture.

> **Écart signalé (§6) : le retrait a un prix, et il est réel.** Une ligne **neuve** dont
> Unibet ne publie pas le programme n'a plus d'horaire de qualifications — donc pas de
> figeage automatique, pas de bouton de pronostics. Le cas concret est une ligne manuelle
> **jamais adoptée**, pour laquelle le scraper insère une seconde ligne qui n'hérite
> d'aucune heure. C'est une raison de plus de tenir le geste d'adoption, pas un argument
> pour rendre le repli : **une heure manquante se voit dans les logs, une heure fausse ne
> se voyait pas.**

> **Second écart signalé (§6).** La demande donnait pour Austin « 23h00 heure française »
> **et** « UTC 22h00 » — les deux ne s'accordent pas, la France étant encore à UTC+2 le
> samedi 24 octobre 2026 (le changement d'heure tombe le 25). **L'UTC explicitement demandé
> a été retenu** : c'est celui que la table portait déjà, et il place la séance à 17h00
> heure d'Austin, le créneau habituel d'une qualification. Les dix autres conversions sont
> exactes, et les onze heures rendent toutes un créneau plausible en heure locale.

**Aucune des onze valeurs de `GP_2026` n'a bougé** — c'est le résultat, pas un raccourci :
elles étaient justes, et la vérification les a confrontées une par une à l'heure française
demandée. Le fichier ne change que par ses commentaires.

**La migration 19 n'a pas été réécrite.** Les migrations de ce dépôt sont historiques
(`database.md` §7). La **20** corrige derrière elle, et l'ordre `19 → 20` devient un piège
d'ordre à part entière — **le premier qui porte sur des données** et non sur une fonction
remplacée. Rejouer la 19 après la 20 est sans danger : son garde-fou sur le slug l'empêche
de réinsérer quoi que ce soit.

### Les migrations ont enfin été jouées sur un vrai PostgreSQL

Le démon Docker était disponible cette fois — ce qui n'avait pas été le cas pour les
migrations 12, 13, 14 ni 19. Les 19 et 20 ont tourné sur un PostgreSQL 16 jetable, contre
un harnais réduit aux colonnes qu'elles touchent : **ce n'est pas le schéma de la migration
3**, et ce contrôle ne remplace donc pas le premier passage dans le SQL Editor.

Six choses ont été vérifiées, et deux n'auraient pas été trouvées autrement : que la 20
retrouve bien une ligne **déjà adoptée** (dont l'`id_unibet` n'est plus le placeholder),
et qu'elle **ne réécrit jamais** une heure qu'Unibet aurait annoncée entre-temps. Les onze
instants finaux ont été croisés **par script** avec `GP_2026.seances.qualifications`, pas
relus à l'œil.

*La version `0.61.0` avait rendu leur heure aux qualifications. La `0.60.0` avait repris dix
horaires de séances et fermé la grille de statistiques en carré. La `0.59.0` avait ouvert
l'écran de détail d'un Grand Prix.*

### Un week-end n'a pas toujours les mêmes cinq séances

La demande corrigeait des libellés — « EL1 » en « Essais Libres 1 » — et donnait au passage
deux horaires pour Singapour que la table ne pouvait pas porter : **une qualification de
sprint et un sprint**. Le calendrier 2026 le confirme, Singapour est le seul week-end
sprint des douze restants, et un week-end sprint **n'a qu'une séance d'essais libres**.
Corriger les seuls libellés aurait laissé l'écran annoncer des EL2 et des EL3 qui n'auront
pas lieu.

**Aucun drapeau `sprint: true` n'a été ajouté.** `SEANCES` déclare les **sept** clés
possibles dans l'ordre chronologique — la fusion des deux formats — et c'est la **présence**
d'une clé dans `gp.seances` qui décide de la rangée. Le format se lit donc dans les heures
elles-mêmes, et il n'y a pas un second endroit à tenir en accord avec elles le jour où la
FIA déplace un sprint. Deux listes séparées, une par format, auraient divergé au premier
libellé retouché : c'est exactement ce qui était arrivé aux deux libellés d'`Horloge`, qui
ont dit la même chose fausse pendant onze versions.

Le repli — les cinq séances du format ordinaire, sans leurs heures — **vit désormais dans
`calendrier2026.js` seul**, à côté de l'ordre qu'il suppose. `SeancesWeekend` le recopiait ;
il appelle maintenant `seancesDuGp(null)`, qui rend exactement la même chose.

> **Écart signalé (§6).** La demande disait « six derniers vainqueurs par GP ». **Deux
> Grands Prix ne peuvent pas en avoir six** — Las Vegas a couru trois fois, le Qatar quatre
> — et inventer une ligne pour tenir un gabarit aurait posé une donnée fausse sous un titre
> qui dit « derniers vainqueurs ». Les deux listes restent courtes, la dernière rangée de la
> grille reste incomplète. C'est le refus déjà opposé à cinq entrées en `0.59.0`.

**Remonter d'une édition ne rajoute pas un nom du même cercle.** Six listes sautent une
année blanche, et **le GP des Pays-Bas saute quarante ans** : absent du calendrier de 1986 à
2020, sa sixième édition la plus récente est celle de 1985, gagnée par Lauda. Trois
nationalités sont entrées avec ces lignes — la France, l'Autriche, la Finlande — et la
Finlande rejoint l'Australie parmi **les nationalités déclarées sans drapeau** : une croix
nordique n'est pas plus descriptible par un dégradé qu'une croix du Sud, et un drapeau
approximé est ce que `DrapeauxSVG.jsx` existe pour ne plus faire.

`ecurie` est **la seule exception à la règle du millésime**, et elle est structurelle :
`lib/livrees.js` ne dessine que les onze écuries de 2026, donc une victoire de 2021 sortait
déjà aux couleurs d'aujourd'hui. La table nomme la **continuation directe** de l'écurie qui
a gagné — Racing Bulls pour l'AlphaTauri de Gasly, McLaren pour la McLaren-TAG de Lauda.

### Le rendu contre la feuille compilée a écarté la grille que le JSX trouvait évidente

Huitième fois, et cette fois sur une case de statistiques.

**« Distance totale de course » retirée, il reste quatre chiffres**, et trois colonnes
paraissaient les ranger le plus proprement — une rangée de trois courtes, le record sur
toute la largeur. **À 320 px, une colonne sur trois ne laisse que 71 px de contenu, et
« 6,003 km » s'y casse en deux lignes.** Le libellé, lui, tenait : rien dans le JSX ne
laissait deviner que c'était la valeur qui manquerait de place. À deux colonnes la même
valeur dispose de 111 px et tient partout — d'où le **carré de 2 × 2**, sans le moindre
`col-span`, que la disparition de la cinquième case rendait justement possible.

**Le palmarès a demandé de recomposer la carte, pas seulement la liste.** En rangée qui
défile, la carte faisait 176 px et posait la voiture à gauche du nom. Une colonne sur deux
n'en fait plus que 166 à 375 px : le nom n'y disposait que de 77,5 px une fois retirés le
rembourrage, les 55 px de la voiture et leur gouttière — et **« Verstappen » en demande
79**, mesuré. Le nom le plus fréquent de la table se serait tronqué sur **tous** les iPhone.
Or c'est le nom de famille qui porte la reconnaissance : la voiture passe donc **au-dessus**,
centrée, et la ligne du nom prend toute la largeur utile. Les onze noms de la table y
tiennent entiers dès 320 px.

> **Deux compromis mesurés et assumés, tous deux à 320 px seulement** (§6). Le détail du
> record — « Charles Leclerc · 2019 » — demande 120 px et n'en a que 111 : il se tronque là,
> et `truncate` est déjà ce que cette ligne secondaire porte. Et « Qualifications Sprint »
> se replie sur deux lignes quand la pastille « Bientôt » l'accompagne. Dès 375 px, tout
> tient sur une ligne.

**Le drapeau de fond passe de 9 % à 18 %**, et le contraste a été remesuré sur les seize
teintes que les onze nationalités peignent. Le pire substrat est le noir de l'Allemagne :
`#D1D1D1` composé, où l'encre vaut **11,40:1** et le marron `secondaire` **6,91:1**. Les
deux valeurs demandées passent le plancher avec marge — `0,20` donne encore 10,84:1 — donc
**le choix entre elles est esthétique, pas de lisibilité**, et c'est la plus discrète qui
est retenue.

**`scroll-pl-4` est parti avec le défilement.** La `0.59.0` avait dû l'ajouter pour qu'une
carte `snap-start` ne colle pas le bord de l'écran ; une grille n'a pas de bord de calage,
donc pas de bord de calage à corriger. **Les deux rangées plus anciennes gardent le leur** —
favoris des cotes, aperçus de la page publique : `roadmap.md` §3.8 ter, toujours ouvert.

### Dix horaires corrigés, et rien de ce qui décide n'a changé de main

Six Grands Prix sur douze avaient au moins une séance à la mauvaise heure — Italie,
Singapour, Austin, Mexique, Brésil, Las Vegas ; les six autres étaient déjà justes. Les
heures restent écrites en **instants UTC complets** et restent **prévisionnelles** : le
scraper écrase les deux qu'il connaît au premier passage, et **la fermeture des pronostics
lit toujours `gp.date_course`, et rien d'autre.**

### Le calendrier a une profondeur : chaque carte ouvre quelque chose

Les douze cartes portaient une date, un drapeau et un tracé, et **n'ouvraient rien** tant
que les cotes n'étaient pas arrêtées. Onze sur douze étaient, la plupart du temps, des
vignettes. `/calendrier/:slug` est la fiche qui manquait — le programme du week-end, le
circuit, le palmarès. Un Grand Prix **couru** n'y va pas : il ouvre ses résultats, parce
que la question qu'on se pose devant une course passée est « qui a gagné », pas « à quelle
heure sont les EL1 ». `destinationDuGp` tranche sur `etatDuGpSaison`, la fonction qui décide
déjà de la pastille et de la pâleur — une seconde lecture du statut aurait pu envoyer aux
résultats une carte affichée « À venir ».

**Le corps de la carte et sa bande d'action sont deux `<a>` FRÈRES**, jamais imbriqués : ils
mènent ailleurs dès que les cotes sont arrêtées, et un `<a>` dans un `<a>` est un balisage
que les navigateurs défont en silence. Mais **un seul `pressable-large`, monté sur
l'`<article>`** — `:active` s'applique à l'élément activé *et à ses ancêtres*, donc la carte
s'enfonce entière quel que soit le lien pressé. Posé sur les deux, le retour aurait
désolidarisé la zone d'informations de la bande, et un appui sur la bande aurait composé
0,985 dans une carte déjà à 0,985 : les 3 % que `pressable-large` existe pour éviter.

> **Trois écarts signalés (§6).** `GP_2026` porte désormais `seances`, ce qui contredit
> « l'heure ne vient jamais d'ici » — **la règle est bornée, pas levée** : la base ne
> connaît que `date_course` et `date_qualifications`, les trois essais libres n'existent
> nulle part côté serveur, et `seancesDuGp` laisse la base écraser les deux qu'elle porte.
> **La fermeture des pronostics lit toujours `gp.date_course`, et rien d'autre.** Ensuite,
> le bouton du bas teste `cotesArretees` et non le statut `cotes_figees` que la demande
> nommait : un `POST /scraper/declencher` lancé un mardi aurait sinon posé un bouton vers
> une grille de départ inexistante — le défaut de la `0.38.0`, rouvert par la lettre de la
> demande. Enfin l'opacité `0,5` d'une séance passée donne **3,07:1**, sous le plancher
> d'un texte ordinaire ; `0,65` le repasse. C'est l'arbitrage déjà retenu pour les cartes
> terminées, et il est écrit là où il se lit.

**`lib/circuits.js` est une donnée de référence saisie à la main**, comme la grille de
`pilotes.py` : aucune route ne la sert, aucun test ne peut la démentir, elle se relit sur
les fiches de la FIA une fois par saison. Deux entrées demandent une lecture attentive —
Madrid n'a jamais couru (`record_tour` vaut `null`, le nombre de tours est prévisionnel), et
`derniers_vainqueurs` liste **le Grand Prix, pas le circuit** : le palmarès d'Espagne s'est
joué à Barcelone, celui de Malaisie date de 2013-2017. Les listes ne font pas toutes cinq
entrées — Las Vegas en a trois, le Qatar quatre — et **on ne les complète pas**.

### Le rendu contre la feuille compilée a trouvé les deux seuls vrais défauts

Ni l'un ni l'autre ne se voyait dans le JSX, et c'est la septième fois.

**`-mx-4 px-4` ne suffit pas sur une rangée `snap-mandatory`.** Avec `scroll-padding: auto`,
une carte `snap-start` s'aligne sur le bord du *scrollport* — la boîte de rembourrage — donc
le navigateur pose `scrollLeft = 16` au premier calcul et la première carte revient coller
le bord de l'écran, seize pixels à gauche de tout le reste. Mesuré : `li.left = 0` pour un
`ul` dont le `padding-left` calculé vaut bien `16px`. `scroll-pl-4` déplace ce bord, et les
deux valeurs doivent rester égales. **Les deux rangées plus anciennes portent le même
`-mx-4 px-4` sans lui** — favoris des cotes, aperçus de la page publique : notées dans
`roadmap.md` §3.8 ter, pas retouchées, ce sont deux écrans qui marchent.

**Un seuil de vingt-quatre heures allume DEUX séances**, pas une. Le vendredi matin, EL1 et
EL2 y tiennent toutes les deux, et deux mises en avant n'en sont plus une. Le délai dit
« est-ce proche ? » ; c'est le **rang** qui dit laquelle. `seancesDuGp` ne marque donc que
la première séance non passée, et seulement si elle tient dans le seuil — une seule pastille
amber par écran, comme partout ailleurs.

### Le Royaume-Uni est le premier drapeau que la planche ne donne pas

`assets/flags.svg` ne dessine que des pays **hôtes**, et six vainqueurs sur dix de la table
des circuits sont britanniques. Aucune borne de dégradé ne sait dire un sautoir
contre-changé : sans dessin, ces six cartes seraient les seules sans fond.

**La règle d'extraction n'est pas enfreinte, elle est appliquée à une autre source.** Ce
drapeau a une géométrie **spécifiée** — croix de Saint-Georges au 1/5 de la hauteur, liseré
blanc au 1/15, sautoir blanc de 6 et sautoir rouge de 4 dans le système 60 × 30. Les quinze
formes ont été **calculées par script** depuis cette spécification, rendues, et relues à
l'image. Aucune coordonnée n'a été tapée à la main : c'est l'objet de la règle 1, qui écarte
la transcription manuelle et non la géométrie exacte.

> **L'Australie n'entre pas**, et c'est la même règle qui le décide : sa croix du Sud n'a
> pas de description que je puisse poser sans l'approximer, et un drapeau approximé est ce
> que `DrapeauxSVG.jsx` existe pour ne plus faire. Piastri et Ricciardo restent donc sur du
> blanc — leur gentilé est écrit sous leur nom, et le fond n'a jamais porté l'information.
> `roadmap.md` §3.8 bis.

**Une seule liste de couleurs pour deux questions** : `NATIONALITES` **référence**
`DRAPEAUX` pour les quatre pays qu'elle décrit déjà, au lieu de les recopier. Sans quoi le
drapeau néerlandais d'une carte de vainqueur aurait fini par différer de celui du bloc de
Zandvoort, sur le même écran.

### Rien n'anime, et c'est la décision

L'écran entre sous `.t-ecran` et ses blocs sous `.t-stagger-line`. **C'est tout.** Aucun de
ses éléments ne change d'état sous les yeux du joueur ; le tracé du circuit ne se dessine
pas — ce serait joli la première fois et une attente les vingt suivantes, sur une fiche
qu'on ouvre plusieurs fois dans la semaine qui précède la course. La mise en avant d'une
séance ne pulse pas et ne porte pas de compte à rebours, qui demanderait une horloge vivante
sur un écran de consultation. **Aucun jeton de mouvement n'entre avec cette version.**

### La saison entière est en base, sous un identifiant qui n'est pas encore le sien

`public.grands_prix` ne contenait qu'une course. La **migration 19** y pose les onze Grands
Prix restants de 2026, ce qui rend enfin vraies deux requêtes qui mentaient déjà :
`chargerProchainGp` rendait `null` depuis que les Pays-Bas sont `termine`, et
`chargerGrandsPrixRestants` comptait une ligne pour une saison qui en a douze.

**Cela ne déplace pas la source de vérité du calendrier.** `GP_2026` la garde, et pour la
raison d'origine : la base ne porte ni le pays, ni le circuit, ni le drapeau, ni le tracé —
ce sont des actifs du frontend. La migration ne fait exister pour douze courses que ce que
la base savait déjà dire pour une : **l'identifiant, le statut, les deux heures.**

> **Trois écarts signalés (§6), tous portés par l'en-tête de la migration.** `pays` et
> `ville` n'existent pas dans la table et ne sont pas insérés — le frontend en est déjà le
> propriétaire unique. Les heures sont **prévisionnelles** : `calendrier2026.js` ne
> contient aucune heure, et son en-tête le dit — « seule la base la connaît ». Elles
> suivent la convention des horaires usuels de la F1, converties au fuseau réel de chaque
> circuit, et **le scraper les écrase au premier passage**.

**Le troisième écart est celui qui demande un geste.** `id_unibet` est `not null unique` et
porte à lui seul l'idempotence du scraper. Les identifiants des Grands Prix à venir
n'existent pas : ils sont attribués quand Unibet ouvre la page. Les onze lignes portent donc
un placeholder, `manuel-<slug>-2026`, et **chacune doit être adoptée avant son week-end** —
`select public.adopter_grand_prix('manuel-italie-2026', '<id réel>');`. Sans ce geste, le
scraper ne reconnaît pas la ligne et **en insère une seconde**. Le symptôme serait discret :
`enrichir` rapproche par slug et construit une `Map`, donc la dernière ligne servie
l'emporte — le calendrier pourrait s'accrocher à celle qui n'a **pas** les cotes.

> **L'idempotence de la migration ne pouvait pas reposer sur `id_unibet`.** Un `on conflict
> (id_unibet) do nothing` aurait été le piège exact : une fois la ligne adoptée, son
> identifiant n'est plus le placeholder, la clause ne trouverait plus de conflit, et la
> migration rejouée **réinsérerait le doublon qu'elle existe pour éviter**. Le garde-fou
> porte donc sur `public.slug_gp(nom)`, une empreinte qui survit à l'adoption comme au
> changement d'orthographe. **Une clé d'idempotence doit survivre à ce que la migration
> elle-même rend possible** — c'est le seul point de cette migration qui ne se voyait pas.

`slug_gp` est la contrepartie SQL de `slugCircuit`, et **s'éprouve elle-même** sur six cas
dans un bloc `do $$` — la leçon de la 17. Elle ramène les accents par `translate` et non par
`unaccent` : l'extension n'est pas garantie active, et une migration qui échoue sur un
`create extension` refusé ne s'exécute pas du tout. **Elle ne remplace jamais `id_unibet`
comme clé de rapprochement** : un slug est une empreinte, pas une identité.

> **Non éprouvée sur un PostgreSQL jetable** — ni Docker ni `psql` disponibles, comme pour
> les migrations 12, 13 et 14. Ce qui a pu être vérifié hors PostgreSQL l'a été : les six
> cas d'épreuve, l'égalité des longueurs de la table `translate`, et la concordance des
> onze noms insérés avec les slug de `GP_2026` — **des deux côtés**, `slug_gp` et
> `slugCircuit`, puisque ce sont eux qui donnent le drapeau et le tracé.

### Un Grand Prix terminé n'est plus le prochain, et le décompte a deux échéances

Le widget d'accueil gardait le GP des Pays-Bas, en statut `termine`, à la place du prochain
Grand Prix. La règle en cause est celle de la `0.53.0` : « le Grand Prix couru garde la place
jusqu'à minuit, heure du téléphone ». **Elle faisait ce qui était écrit — c'est son principe
qui était faux.** Elle faisait dépendre « ce Grand Prix est-il fini ? » de l'heure qu'il est,
là où le statut le dit déjà, seul et sans ambiguïté. `chargerGpDuJour` est supprimée : dès
qu'un Grand Prix passe à `termine`, le suivant prend sa place.

Ce que cette règle voulait éviter — « Fermeture dans 13j » sur l'écran d'entrée le dimanche
soir — est **précisément le second défaut**, et il se corrigeait mieux de front. Le compte à
rebours n'annonçait qu'une échéance alors que le week-end en a deux : il promettait la
fermeture de pronostics **pas encore ouverts**, sous une case sans bouton, sans dire quand ils
ouvriraient. Il décompte maintenant `date_qualifications + 2h` avant l'ouverture, et
`date_course − 5 min` après.

**C'est `cotesArretees` qui départage les deux phases, jamais le statut brut** — la fonction
qui décide déjà du bouton juste dessous. Un `POST /scraper/declencher` lancé un mardi ferait
sinon annoncer « Fermeture dans » au-dessus d'un bloc sans bouton, le défaut de la `0.38.0`
vu depuis le texte. Et **« pas encore ouverts » exige les trois à la fois** : cotes non
arrêtées, fermeture pas passée, statut différent de `termine` — sans le troisième test, un
Grand Prix couru retombait en phase d'ouverture et **l'écran de saisie déverrouillait son
formulaire sur une course déjà courue**.

**Le libellé était écrit deux fois** : dans `Horloge.jsx` et dans les cases de l'accueil.
`Horloge` avait pourtant été extraite en `0.18.0` pour qu'une composition ne soit pas écrite
deux fois — mais son **texte** était resté dupliqué, et les deux ont dit la même chose fausse
pendant onze versions. **Le partage d'un composant ne couvre que ce qu'on lui a confié.**
Source unique désormais : `etatPronostics` (`lib/calendrier.js`), pour les quatre surfaces.
Détail dans `bugs-connus.md` §26.

> **Les deux heures après les qualifications sont une prévision, pas une garantie** : c'est le
> délai du job du samedi, qui peut prendre du retard. Passée l'heure prévue sans que le statut
> ait bougé, le décompte se tait — « Ouverture / À confirmer ». Jamais un délai négatif, jamais
> une ouverture promise en retard. `DELAI_OUVERTURE_MS` est la seule valeur à revoir si le job
> traîne, et elle n'est écrite qu'une fois.

### « Autres » n'est pas une nationalité, c'est le complémentaire des autres issues

Au GP des Pays-Bas, les pronostics « nationalité du vainqueur » posés sur l'issue **« Autres »**
restaient en attente, avec en journal « ne correspond à aucune nationalité connue ». Le message
invite à ajouter une quinzième forme à `NATIONALITES` — **il n'y a rien à y ajouter.** Sous quel
code aurait-on rangé « Autres » ? Elle ne nomme aucun peuple, aucun pays.

**Toutes les autres issues du système se jugent seules.** « Néerlandais » est vrai ou faux sans
qu'on sache ce que le marché proposait à côté ; « Entre 5 et 10 secondes » aussi ; « Oui »
aussi. « Autres » est la **première** qui n'est pas une valeur mais un **complémentaire** : elle
veut dire « une nationalité qu'Unibet n'a pas listée ce jour-là », et cette liste change à
chaque Grand Prix. Avec `(course, libelle)` pour tout contexte, elle était **indécidable** — et
le filet a fait son travail : `NULL`, jamais `0`.

`validateur(marche, options)` reçoit donc les libellés de **toutes** les issues du marché pour
ce Grand Prix, tirés par `issues_du_marche` du dictionnaire de cotes **déjà chargé** : aucune
lecture de plus, et la liste est celle que le scraper a réellement enregistrée. Rien n'est écrit
en dur, donc la règle vaut pour tous les Grands Prix à venir. Le validateur devient une fabrique
qui capture ses options — l'idiome de `_top(rang)`, déjà en place.

**L'ordre des trois tests porte tout le raisonnement.** La nationalité du vainqueur figure parmi
les options **lues** → raté, et c'est définitif, même s'il reste des libellés illisibles à côté.
Sinon une option est illisible → **non jugé**, elle pouvait être précisément la sienne. Sinon →
réussi. **Une option illisible ne fait pas gagner « Autres », mais ne l'empêche pas de perdre** :
on refuse d'inventer un gain, pas de constater un fait. Détail dans `bugs-connus.md` §25.

### Le calcul était déjà juste : c'est l'idempotence qui gardait le mauvais verdict

Au GP des Pays-Bas, le podium « C.Leclerc + AK.Antonelli » affichait **0 pts** alors
qu'Antonelli était monté sur le podium, et « écart du gagnant » restait en attente. Les deux
correctifs de la `0.54.0` paraissaient donc n'avoir servi à rien.

**Ils servaient.** Rejouer le calcul sur les données du GP le montre en une commande : le
demi-podium rend 28 pts, « Entre 5 et 10 secondes » rend sa cote, et les trois libellés
exacts d'Unibet se parsent tous les trois. **Le code n'était pas en cause — la chronologie
l'était.** Le job a tourné à `départ + 1h30` avec le backend d'avant ; le correctif est
arrivé le soir même, après. Et `attribuer_points` n'écrit que les `NULL`.

**Les deux symptômes n'avaient donc pas la même gravité, alors qu'ils se présentaient
identiques à l'écran** : le `NULL` de l'écart était rattrapable par un simple rejeu, le `0`
du demi-podium était **définitivement figé**. C'est le filet « `NULL` jamais `0` » vu depuis
l'autre côté — il protège d'un verdict inventé, pas d'un verdict faux mais assumé, parce
qu'un `0` est une décision et que l'idempotence défend les décisions.

D'où `POST /jobs/resultats/{gp_id}?forcer=true` : les points du GP retournent à `NULL`, puis
le calcul reprend. **OpenF1 n'est pas rappelée** — `resultats_gp` est intact, c'est
exactement ce que `donnees_brutes` conserve pour. Défaut `false`, secret d'admin exigé, et
**le scheduler ne l'emprunte jamais** : le job automatique reste strictement idempotent.

> **Écart signalé (§6).** La demande disait « mettre à zéro `points_gagnes` ». Appliquée à la
> lettre, elle aurait produit **exactement le bug qu'elle corrigeait** : `0` veut dire
> « raté », `attribuer_points` ne réécrit que les `NULL`, donc le GP serait ressorti avec les
> mêmes zéros — cette fois pour toujours. La remise est donc à `NULL`, seul état depuis
> lequel un calcul peut reprendre. Détail dans `bugs-connus.md` §24.

### La nationalité du vainqueur n'est pas dans les résultats de la course

Troisième marché dont l'issue n'est ni un pilote ni un oui/non, et le premier dont la
réponse **ne se trouve nulle part dans `session_result`** : `country_code` de `/drivers` est
déprécié et disparaît fin 2026. La nationalité vient donc d'une table statique dans
`calcul/pilotes.py` — le choix était déjà écrit dans `scraper.md` §9, il est maintenant tenu.

Sous le **même garde-fou de saison que les alias** : numéro **et** nom de famille doivent
concorder, sinon rien n'est rendu. Une table périmée ne prêtera pas la nationalité
d'Antonelli au prochain titulaire du 12 — elle laissera le pronostic non jugé, ce qui se voit
dans les logs. Les deux formes sont acceptées (« Néerlandais » et « Pays-Bas »), rien ne
disant laquelle Unibet écrit, et **les deux inconnues sont journalisées séparément** : c'est
ce qui dira s'il faut corriger la grille ou ajouter une forme.

### Vérifier le calcul avant de conclure à un bug de calcul

Trois lignes de Python sur les données du GP ont écarté deux des trois pistes signalées.
Sans elles, deux validateurs **déjà justes** auraient été « corrigés », et le vrai défaut —
une chronologie de déploiement — serait resté entier. Quatrième fois qu'une cause supposée
n'était pas la vraie, après le numéro sous `rotate(180)`, le tout-ou-rien du podium et le
`gap_to_leader` jamais lu.

*La version `0.59.0` avait ouvert l'écran de détail d'un Grand Prix. La `0.58.0` avait posé
les onze Grands Prix restants en base. La `0.57.0` avait
retiré la règle du dimanche soir et donné deux échéances au décompte. La `0.56.0` avait fait
juger « Autres » contre ses issues sœurs. La `0.55.0` avait
sorti la nationalité du vainqueur d'une table statique et ouvert le recalcul forcé. La `0.54.0`
avait fait payer le podium pilote par pilote, fait entrer `gap_to_leader` dans `Ligne`, sorti
le succès du bordeaux, gardé le dimanche soir sur le Grand Prix couru — règle **retirée par la
`0.57.0`** — et ouvert le calendrier là où il sert. La `0.53.0` avait remis le numéro du
museau à l'endroit. La `0.52.0` avait fait entrer la photo DANS le cockpit. La `0.51.0` avait
réparé les photos. La `0.45.0` avait fait passer le multiplicateur des points de 100 à 10.*

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les cinq points
les plus urgents :

1. **Rejouer le GP des Pays-Bas en forçant**, une fois la `0.56.0` du backend déployée sur
   Railway — **pas avant** : sur l'ancien backend, le rejeu reproduirait les mêmes `NULL`.
   `curl -X POST "https://<railway>/jobs/resultats/33b835cc-5c17-40f7-a41f-3e95fc14885a?forcer=true" -H "X-Admin-Secret: <valeur>"`.
   **Sans `?forcer=true`, les demi-podiums notés `0` ne bougeront pas** — seuls les `NULL`
   se rattrapent. Les pronostics « Autres », eux, sont restés à `NULL` : ils se rattraperaient
   sans forcer, la commande les couvre au passage. La réponse porte `reinitialises` (points
   effacés) et `en_attente` (ce que le calcul n'a toujours pas su juger) : **c'est cette
   seconde liste qu'il faut lire** — elle dira si « Autres » est enfin jugé, ou si une option
   sœur du marché reste illisible.
2. **Appliquer les migrations 15, 16, 17 puis 18, dans cet ordre.** La 17 est celle sans
   laquelle **aucune photo ne s'enregistre**. La 18 est celle sans laquelle **la couleur du
   texte ne s'enregistre pas**. Si la 2, la 8, la 10, la 12 ou la 16 est rejouée un jour,
   rejouer la 18 derrière. **La `0.58.0` apporte la 19** — les onze Grands Prix restants —
   et **la `0.61.0` apporte la 20**, qui corrige ses horaires de qualifications. Les deux
   ne dépendent que de la 3 et de la 11 et ne remplacent aucune fonction : elles se jouent
   avant ou après les quatre autres, **mais la 19 avant la 20, toujours**. Jouer la 19
   seule fait afficher des qualifications à 17h00 pour un GP d'Italie qui les court à 16h00.
   **Déployer la `0.57.0` du backend avec elles** : sans ce déploiement, le scraper
   réécrira `date_course − 22h` par-dessus la correction au premier passage.
3. **Adopter chaque ligne manuelle avant son week-end**, une fois les 19 et 20 jouées :
   `select public.adopter_grand_prix('manuel-italie-2026', '<id Unibet réel>');`, le vendredi
   ou le samedi matin. **Sans ce geste, le scraper insère une seconde ligne pour la même
   course** — il se rapproche sur `id_unibet`, jamais sur le nom. Le prochain à adopter est
   **le GP d'Italie, couru le 6 septembre 2026**. `adopter_grand_prix` résorbe aussi le
   doublon après coup, en gardant la ligne du scraper et en supprimant la manuelle **si elle
   est vide**.
4. **Vérifier « Ouverture dans » le premier samedi de qualifications** — le délai de deux
   heures est une prévision jamais confrontée à un vrai week-end. La bascule vers « Fermeture
   dans » doit suivre le **statut**, pas le décompte qui atteint zéro (`roadmap.md` §1.6 bis).
5. **Tester sur iPhone réel** — jamais fait. En priorité : **l'opacité `0,4`** des cartes
   passées, qui est un jugement de lisibilité en plein soleil autant qu'un rapport de
   contraste ; **les deux liens d'une carte de calendrier**, où un appui près de la couture
   ne doit pas se tromper de destination ; **la rangée des derniers vainqueurs**, cinq SVG
   de voiture qui défilent à l'inertie et dont le calage a demandé `scroll-pl-4` ; **le
   défilement d'ouverture du calendrier**, qui se pose sur des `offsetTop` mesurés pendant
   l'animation d'entrée ; **le sélecteur de vingt-quatre Grands Prix** ; **la photo de
   15px dans le cockpit** ; et, depuis la `0.62.0`, **le lavis de drapeau à 8 %** — même
   jugement de plein soleil que l'opacité `0,4` — sur un écran qui dessine désormais
   **vingt-deux voitures d'écurie** en une seule liste.
