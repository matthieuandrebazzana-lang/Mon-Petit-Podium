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

**Version `0.59.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées. **Le backend reste à `0.56.0`** — ni la
`0.57.0`, ni la `0.58.0`, ni la `0.59.0` ne touchent à son code.

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

*La version `0.58.0` avait posé les onze Grands Prix restants en base. La `0.57.0` avait
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
   qui ne dépend que de la 3 et de la 11 et ne remplace aucune fonction : elle peut se jouer
   avant ou après les quatre autres. Les `0.56.0` et `0.57.0`, elles, n'exigeaient rien.
3. **Adopter chaque ligne manuelle avant son week-end**, une fois la 19 jouée :
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
   l'animation d'entrée ; **le sélecteur de vingt-quatre Grands Prix** ; et **la photo de
   15px dans le cockpit**.
