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
| [`database.md`](docs/database.md) | Tables, RLS, fonctions, triggers, les 14 migrations et leurs conflits d'ordre |
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

**Version `0.52.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées. **Le backend ne bouge pas** — cette version
est entièrement frontend, sa version reste `0.51.0`.

### La photo entre DANS la voiture

**Le disque noir du cockpit porte la photo du membre**, découpée par un `<clipPath>`
circulaire à l'intérieur du SVG. La pastille que la vue piste posait *au-dessus* de chaque
voiture depuis la version `0.50.0` disparaît, et avec elle la **coiffe de trente pixels**
qu'elle réservait à tout le championnat dès qu'un seul membre avait une photo : l'échelle
des scores retrouve exactement la hauteur qu'elle avait avant les photos, au pixel près.
C'est le point qui compte — **une identité intégrée au dessin ne coûte pas un pixel**, une
identité posée à côté coûte la place de tout le monde.

**La géométrie des douze cockpits a été extraite par script**, pas relevée à l'œil. Dix
livrées peignent leur casque avec un `<circle>` ; **Audi seule avec un `<path>`**, dont le
rayon se lit dans l'arc de fermeture et le centre à un rayon du point de départ. Aucune
lecture du code ne l'aurait montré. Les douze tombent sur le même point relatif — c'est le
même dessin douze fois repeint — et sont pourtant écrits **un par un** : une fraction
commune serait une tranche arithmétique, que la première livrée retouchée démentirait en
silence. Trois vérifications automatiques : le cercle tient dans son cadrage pour les
douze, les `clipPath` ont des identifiants distincts, et l'`<image>` sort en `href` moderne.

**À défaut de photo, c'est l'initiale sur la teinte du membre** — la même que sa pastille
au classement. `teinteMembre` (`lib/couleurs.js`) est désormais le **seul propriétaire** de
la question « de quelle couleur est le rond de cette personne ? », et il porte les **deux
formes** de chaque teinte : la classe Tailwind pour le HTML, le `#rrggbb` pour le SVG, où
un `fill` n'accepte pas `bg-primaire`.

> **Le cockpit fait 15,04px de diamètre à taille pleine de voiture, et moins dans un groupe
> serré.** C'est petit pour un visage, et c'est le prix de l'intégration au dessin : la
> seule façon d'avoir plus grand est de le poser à côté, ce qui est exactement ce qui
> coûtait la place. À juger **sur iPhone réel**, avec de vraies photos.

**Un défaut trouvé au passage, et il datait de l'origine.** `Pastille` écrivait
`text-white` en toutes lettres, et sa table distribue quatre teintes dont **l'amber**, où
le blanc ne vaut que **2,22:1**. Une initiale sur quatre était illisible, partout, depuis
toujours — ce qui passait pour un défaut intermittent était une fonction de hachage.
`encreSurAplat` corrige, et l'écart entre les deux helpers d'encre est maintenant écrit :
`encreSur` compare une **luminance** à 0,45, l'amber vaut **0,424** et passe juste dessous ;
`encreSurAplat` mesure le **contraste**. Devant « quelle encre sur cet aplat », c'est le
second (`bugs-connus.md` §19).

### Deux lignes pour un titre de marché, un avatar dans la barre

**Les en-têtes de marché ne tronquent plus.** Le libellé vient d'Unibet et n'a pas de
longueur convenue : « VAINQUEUR COURSE, QUALIFICATION … » sortait coupé, et **un titre
tronqué ne nomme plus son marché**, ce qui est la seule chose que cet en-tête ait à dire.
Le texte revient à la ligne, `line-clamp-2` borne la casse à deux, `break-words` protège du
mot plus large que la colonne. **Aucune hauteur fixe** n'est posée : le widget grandit avec
son titre, et l'espacement du parent tient l'écart. Tableau des cotes et bloc obligatoire
de la saisie, les deux en-têtes de marché de l'app.

**La pastille de l'accueil porte la photo du compte connecté.** Elle vient de l'état déjà
chargé, dans **la même requête que le pseudo** : une colonne ajoutée à un `select` indexé
sur clé primaire coûte zéro aller-retour, quand un second chargeur aurait fait payer un
réveil de Railway au premier écran de l'app. `usePseudoCourant` devient donc
`useIdentiteCourante`, `chargerPseudo` devient `chargerIdentite`. Sans photo, le rond rouge
à initiale est exactement celui d'avant.

### Aucun mouvement nouveau, et c'était le bon verdict

Les cinq skills de design ont été invoqués dans l'ordre. **Le portier a rejeté la seule
animation candidate** : la hauteur d'un en-tête de marché ne s'anime pas, parce qu'elle ne
change jamais *à l'écran* — le libellé arrive une fois, avec les données, et animer un
état qui n'a pas de « avant » est du mouvement sans changement d'état. Les deux photos, elles,
réemploient `.t-photo`, le fondu d'opacité déjà partagé par la pastille et la carte de
championnat. **Zéro jeton nouveau, zéro image-clé.**

Un hook nouveau, en revanche, et pour une raison de plateforme : **`usePhotoDetachee`**. Un
`<image>` SVG est un `SVGImageElement` — ni `complete`, ni `naturalWidth`, donc aucun moyen
de savoir si une image en cache est déjà décodée. On resterait suspendu à un `load` qui ne
viendra pas, et la photo tiendrait `opacity: 0` indéfiniment : exactement le défaut que
`usePhoto` avait été écrit pour corriger, sous une autre forme. La question est donc posée à
un élément **détaché**, jamais rendu, qui répond à `complete` — et le navigateur sert la
même URL depuis le même cache, sans second téléchargement.

*La version `0.51.0` avait réparé les photos, qui n'avaient jamais fonctionné : une
contrainte `check` incompilable — **PostgreSQL plafonne un compteur `{m,n}` à 255** — que la
migration 17 remplace par un `char_length`, et qui **s'éprouve elle-même** sur une URL
jetable, seul moyen de savoir en jouant une migration qu'un `check` posé sur une colonne
vide est compilable. Elle avait aussi livré `RecadragePhoto`, la première surface modale du
projet, et les deux plafonds qui ne mesurent pas la même chose — `stockage.js` juge ce qu'on
a le droit de **choisir**, `image.js` ce qu'on **dépose**. La `0.50.0` avait livré les
photos elles-mêmes, la `0.49.0` refondu la vue piste, la `0.45.0` fait passer le
multiplicateur des points de 100 à 10. **Un scraping reste obligatoire.***

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les trois points
les plus urgents :

1. **Appliquer les migrations 15, 16 puis 17, dans cet ordre, puis déclencher un scraping.**
   La 17 est celle sans laquelle **aucune photo ne s'enregistre** — la 16 seule laisse la
   fonctionnalité entière inerte. Si la 16 est rejouée un jour, rejouer la 17 derrière.
2. **Vérifier les migrations appliquées** dans le SQL Editor, définir les variables
   d'environnement de production sur Vercel et Railway, et **supprimer le compte de
   diagnostic** laissé par la localisation du défaut (`docs/roadmap.md` §1.5).
3. **Tester sur iPhone réel** — jamais fait. Trois choses en priorité : le recadrage, qui
   est le premier geste multi-touch du projet ; **la photo de 15px dans le cockpit**, qui
   décidera si le cadrage exporté doit se resserrer sur le visage ; et **l'en-tête de marché
   sur deux lignes**, qui est collant : sa hauteur est prise sur la liste pendant tout le
   défilement du marché.
