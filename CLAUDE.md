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
| [`database.md`](docs/database.md) | Tables, RLS, fonctions, triggers, les 18 migrations et leurs conflits d'ordre |
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

**Version `0.54.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées. **Le calcul des points bouge** — deux marchés
sur dix ne rendaient pas ce qu'ils devaient — le backend passe donc à `0.53.0`.

### Un demi-podium ne rapportait rien, et la documentation le défendait

Le podium est **le pari le mieux doté de la grille** — le seul qui puisse rapporter la somme
de deux cotes — et il était le seul à ne jamais rien rapporter à moitié : `all(resultats)`,
les deux pilotes ou rien. Un joueur qui plaçait le bon nom finissait **à égalité exacte**
avec celui qui s'était trompé sur les deux.

**Ce n'était pas un bug de calcul.** Le code faisait exactement ce que `metier.md` §2
prescrivait, en toutes lettres, et le raisonnement d'origine tenait : payer la seule cote de
`pilote_1` ferait rapporter deux montants différents au même pari selon l'ordre de saisie,
puisque les deux emplacements n'ont aucun ordre entre eux. **La conclusion tirée était la
mauvaise sortie.** La bonne est de payer chaque cote à *son* pilote : c'est tout aussi
ordre-indépendant, et le demi-podium rapporte la même chose quel que soit l'emplacement où
le bon nom a été saisi. Le total **potentiel** ne bouge pas d'un point — il reste le maximum
atteignable, donc la somme.

**Une jambe non jugeable laisse le pronostic ENTIER à `NULL`.** La ligne ne porte qu'un seul
`points_gagnes` et `attribuer_points` n'écrit que les `NULL` : payer la seule jambe connue
figerait un total partiel que le rattrapage **ne corrigerait plus jamais**. Attendre est
réversible, écrire ne l'est pas — la même asymétrie que « un marché non reconnu vaut `NULL`,
jamais `0` ».

### « Écart du gagnant » : le champ n'était pas mal lu, il n'était pas lu

On cherche une comparaison qui échoue — un intervalle mal parsé, une virgule française, des
millisecondes. **Il n'y avait aucune comparaison.** `gap_to_leader` n'entrait jamais dans
`Ligne`, et le slug n'était pas reconnu : le marché tombait dans le filet « marché non
reconnu », qui rend `NULL`. **Le pronostic n'était pas jugé perdant, il n'était pas jugé** —
et c'est pour cela que le défaut est resté muet six versions.

La docstring d'`analyser()` le **présentait comme une décision** : « `gap_to_leader` de type
mixte (jamais lu — aucun marché validé aujourd'hui n'en dépend) ». C'était vrai à
l'écriture. Troisième fois qu'un commentaire exact fait passer un manque pour une intention,
après le numéro sous `rotate(180)` et le tout-ou-rien du podium.

**`openf1.py` n'était pas en cause et n'a pas été touché** : il conserve les lignes de
`session_result` telles quelles, donc `gap_to_leader` était déjà en base sur toutes les
courses passées. Le rattrapage se fait **sans rappeler OpenF1**. L'écart se lit sur la ligne
du **deuxième** — le champ dit « de combien ce pilote est derrière le leader », donc `null`
sur celle du premier — et les bornes sont **`[bas, haut[`**, parce que les issues forment une
partition et que deux bornes inclusives feraient gagner *deux* paris à 5,000 s exactement.

### Le succès était le seul des trois états à ne pas se voir

La pastille de points disait le contraire de ce qu'elle montrait : l'aplat **bordeaux plein**
marquait le pronostic **réussi**, et le raté comme le non-jugé prenaient tous deux le même
bordeaux sur beige. Toute la colonne était rouge, le succès y était l'état le plus sombre, et
**`null` était indistinguable de `0`** — la seule distinction qu'aucun écran n'a le droit de
perdre. `Verdict`, juste à côté, la tenait seule.

Réussi passe au **vert sauge**, raté au bordeaux plein, en attente au beige — 4,86:1, 10,88:1
et 9,32:1, mesurés. **Aucune teinte nouvelle** : c'est le vert que le design system emploie
déjà pour dire « c'est acquis ». Le bloc était **recopié à l'identique** dans les deux écrans
de résultats ; il devient `PastillePoints`, exportée à côté de `Verdict`, qui avait été
partagée une version plus tôt pour exactement la même raison.

### Le dimanche soir appartient encore au Grand Prix du jour

Le passage à `termine`, une heure et demie après le départ, faisait basculer l'accueil sur le
Grand Prix suivant — deux semaines plus loin, compte à rebours de treize jours —
**au moment précis où tout le monde ouvre l'application**. Le Grand Prix couru garde la place
jusqu'à **minuit, heure du téléphone**.

**La frontière est le jour civil, pas une durée** : « six heures après » basculerait en pleine
soirée pour un départ à 15h et en pleine nuit pour Las Vegas. Et **il n'y a rien à coudre
entre les deux règles** — entre l'arrivée et le passage à `termine`, le Grand Prix est encore
`cotes_figees`, donc déjà servi comme le plus proche à venir. `chargerProchainGp` les porte
toutes les deux, et lui seul. Conséquence : **`couru` se lit désormais sur le statut**, il ne
se déduit plus du chemin pris — le figer à `false` aurait proposé de pronostiquer sur une
course déjà courue, le défaut même que la `0.53.0` venait de corriger sur les calendriers.

### Le calendrier s'ouvre là où il sert, et l'archive recule

Une carte terminée passe à `opacity: 0,4` et l'écran défile jusqu'au premier Grand Prix qui
ne l'est pas. Une seule question, un seul propriétaire — `estGpPasse` — parce que deux
prédicats écrits séparément auraient donné un calendrier ouvert sur une carte pâle, ou une
carte vive hors de l'écran. **C'est le statut qui tranche, pas la date** : un Grand Prix couru
mais jamais scrapé n'est pas en base, reste « à venir », et reste vif.

Le défilement se calcule sur la chaîne des **`offsetTop`** et non sur
`getBoundingClientRect()` : l'écran entre en scène sous un `translateX` et ses blocs sous un
`translateY`, donc le rectangle rendu est décalé pendant toute l'entrée — exactement au
moment du calcul.

> **Écart signalé (§6).** L'opacité compose l'encre **et** son fond sur le beige : la
> pastille « Terminé » tombe de **4,86:1 à 1,74:1**, sous les 3:1 d'un grand texte porteur de
> sens. La valeur demandée a été appliquée et l'arbitrage se défend — l'archive se lit à la
> pâleur avant de se lire au mot — mais **`0,75` est le point où la pastille repasse le
> plancher**, une constante et une ligne. Tableau dans `calendrier.md` §8, arbitrage dans
> `roadmap.md` §3.14.

### Rien de nouveau côté mouvement, une troisième fois

Le portier a rejeté les trois candidats. L'opacité d'archive est un **état permanent**, pas
un changement d'état. Le réordonnancement de la liste s'applique **avant** le premier rendu
d'une donnée qui arrive du réseau : il n'y a pas d'« avant » à faire tenir, et c'est le
squelette qui occupe l'intervalle. Le défilement d'ouverture est une **position de départ**,
pas une transition — et l'onglet Calendrier est ouvert plusieurs fois par jour, ce qui le
place dans la bande où l'on retire du mouvement au lieu d'en ajouter. Il est instantané.

**Zéro jeton, zéro ligne de CSS.** Les seuls tris sont ceux de `Onglets` et de `.t-acc`, déjà
dans le vocabulaire.

*La version `0.53.0` avait remis le numéro du museau à l'endroit — la planche l'écrivait sous
`rotate(180)`, convention d'une vraie monoplace, alors que toutes les vues de l'app sont des
vues de dessus — livré « Résultats par Grand Prix » et la couleur de texte du membre, dont le
`NULL` veut dire « pas de choix » et non « pas de couleur ». La `0.52.0` avait fait entrer la
photo DANS le cockpit. La `0.51.0` avait réparé les photos (`{m,n}` plafonné à 255 par
PostgreSQL). La `0.45.0` avait fait passer le multiplicateur des points de 100 à 10.
**Un scraping reste obligatoire.***

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les trois points
les plus urgents :

1. **Appliquer les migrations 15, 16, 17 puis 18, dans cet ordre, puis déclencher un
   scraping.** La 17 est celle sans laquelle **aucune photo ne s'enregistre**. La 18 est
   celle sans laquelle **la couleur du texte ne s'enregistre pas**. Si la 2, la 8, la 10, la
   12 ou la 16 est rejouée un jour, rejouer la 18 derrière. **Aucune migration n'est requise
   par la version `0.54.0`** — les deux correctifs de calcul sont entièrement dans
   `app/calcul/points.py`, et le tri des membres est fait côté écran.
2. **Confronter « écart du gagnant » à de vrais libellés Unibet, sans attendre la course** :
   `POST /jobs/resultats/{gp_id}/test` n'écrit rien. Les formes d'issue reconnues (« moins de
   N », « N - M », « plus de N ») n'ont **jamais été vues** ; une issue non reconnue est
   journalisée en toutes lettres, c'est cette ligne-là qu'il faut chercher. Puis rejouer
   `POST /jobs/resultats/{gp_id}` sur les Grands Prix déjà courus — **les données sont déjà
   en base**, `gap_to_leader` compris, et les podiums restés à `NULL` se rattraperont avec.
3. **Tester sur iPhone réel** — jamais fait. En priorité : **l'opacité `0,4`** des cartes
   passées, qui est un jugement de lisibilité en plein soleil autant qu'un rapport de
   contraste ; **le défilement d'ouverture du calendrier**, qui se pose sur des `offsetTop`
   mesurés pendant l'animation d'entrée ; **le sélecteur de vingt-quatre Grands Prix** ; et
   **la photo de 15px dans le cockpit**.
