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

**Version `0.51.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées.

**Cette version répare les photos, qui n'ont JAMAIS fonctionné.** Le backend change aussi :
sa version passe à `0.51.0`.

### Le défaut : une contrainte `check` incompilable

La migration 16 posait `check (colonne ~ '^https://[^[:space:]]{10,505}$')` sur
`profils.avatar_url` et `championnats.photo_url`. **PostgreSQL plafonne un compteur de
répétition `{m,n}` à 255** : l'expression n'est pas compilable, et toute écriture d'URL
retombait en `2201B`. La contrainte avait pourtant été **acceptée** à la création — un
`check` n'est évalué qu'à l'écriture, et les colonnes étaient vides.

Le diagnostic a été fait **contre la base de production**, segment par segment, et c'est ce
qui l'a rendu court : colonnes présentes, compartiments présents, politiques de stockage
correctes, dépôts en `200`, `mes_championnats` servant bien `photo_url`. Quatre segments sur
cinq étaient justes, et **aucune lecture du code ne pouvait désigner le cinquième** — la
contrainte est en base, elle n'apparaît que dans une migration déjà jouée.

**La migration 17 la remplace** : la borne de longueur sort de l'expression et devient un
`char_length`, sémantique inchangée à la lettre, plus aucun compteur. Et **elle s'éprouve
elle-même** sur une URL jetable en fin de fichier — le seul moyen de savoir, en jouant une
migration, qu'un `check` posé sur une colonne vide est compilable. C'est ce qui manquait à
la 16, et c'est désormais la règle pour tout `check` non trivial.

**Deux amplificateurs ont fait durer le défaut une version entière, tous deux corrigés.**
Le contexte de `PATCH /profils/moi` disait « Enregistrement de ta voiture » alors que la
route sert aussi le numéro, la livrée et la photo — **un contexte qui nomme la mauvaise
chose est pire qu'un contexte vague** ; il dit maintenant « ton profil ». Et l'échec de la
photo d'un championnat était **avalé en silence** par l'écran de création : la règle « une
opération secondaire en panne n'emporte jamais la principale » est bonne, mais **ne pas
bloquer sur un échec n'autorise pas à le taire**. Le message remonte désormais jusqu'à
l'écran d'arrivée.

### Le recadrage, et les deux plafonds

**Choisir un fichier n'envoie plus rien : ça ouvre un recadrage.** `RecadragePhoto` est la
première surface modale du projet — masque rond pour un avatar, carré arrondi pour un
championnat, glisser pour placer, pincer pour zoomer. **Un seul composant pour les deux
formes** : le cadre est carré dans les deux cas, le rond n'est qu'un masque posé dessus.

Il est **monté par un portail dans `document.body`** — `Ecran` porte un `transform`, et un
`position: fixed` posé dedans se positionnerait par rapport à lui. Même piège que
`NavBarre`. Il **dessine dans un canvas** plutôt que de transformer une `<img>` en CSS :
c'est plus coûteux, mais l'aperçu et l'export partagent alors **la même géométrie**
(`carreVisible`), et l'écart entre ce qu'on montre et ce qu'on découpe devient
structurellement impossible.

**Deux plafonds coexistent, et ils ne mesurent pas la même chose.** `lib/stockage.js` juge
ce qu'on a le droit de **choisir** — 5 Mo, jpg/png/webp. `lib/image.js` juge ce qu'on
**dépose** — 800 px de côté, JPEG 0,85, toujours `.jpg`. Rien ne va du premier au second
sans passer par le canvas : une photo d'iPhone de quatre mégaoctets en pèse alors moins de
deux cents kilo-octets, et le plafond de 2 Mo du compartiment n'est plus jamais approché.
C'est ce qui permet au plafond de choix d'être si large.

**Un seul jeton nouveau, `--scale-large` (0,96)**, et ce n'est pas un fork : c'est le nom et
la valeur que la planche Transitions.dev donne à l'ouverture d'une modale. Ouverture
`--duration-fast`, fermeture `--duration-quick`, courbe `--ease-smooth-out` — l'usage exact
que la table des jetons leur donne. **La sortie emprunte le chemin de l'entrée**, y compris
à la confirmation.

**La géométrie est sortie du composant** vers `lib/image.js` : trois fonctions pures de
quelques nombres, éprouvables sans monter de DOM. La propriété qui compte se vérifie alors
en une ligne — **le carré retenu ne sort jamais de l'image**, quel que soit le couple
zoom/décalage — et c'est elle qui garantit qu'aucun bord noir n'apparaît dans le masque.

*La version `0.50.0` avait livré les photos elles-mêmes : deux colonnes portant des URL,
deux compartiments Storage publics, la photo entrée DANS `Pastille` plutôt qu'un `Avatar`
posé à côté, et la règle unique des trois listes — la colonne de pastilles n'apparaît que
si quelqu'un, dans cette liste, a une photo. **Tout cet affichage était correct** ; il n'a
simplement jamais eu de photo à montrer. La `0.49.0` avait refondu la vue piste, la `0.48.0`
retouché l'accueil et l'écran championnat, la `0.45.0` fait passer le multiplicateur des
points de 100 à 10. **Un scraping reste obligatoire.***

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les trois points
les plus urgents :

1. **Appliquer les migrations 15, 16 puis 17, dans cet ordre, puis déclencher un scraping.**
   La 17 est celle sans laquelle **aucune photo ne s'enregistre** — la 16 seule laisse la
   fonctionnalité entière inerte. Si la 16 est rejouée un jour, rejouer la 17 derrière.
2. **Vérifier les migrations appliquées** dans le SQL Editor, définir les variables
   d'environnement de production sur Vercel et Railway, et **supprimer le compte de
   diagnostic** laissé par la localisation du défaut (`docs/roadmap.md` §1.5).
3. **Tester sur iPhone réel** — jamais fait. Le recadrage en particulier : c'est le premier
   geste multi-touch du projet, et le pincement doit zoomer l'image, pas la page.
