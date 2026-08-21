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

**Version `0.48.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées : fondations, authentification, championnats,
scraper Unibet, pronostics, résultats OpenF1, classements, profils, finitions, navigation,
scraping automatique.

**Cette version retouche l'accueil, la liste des championnats et l'écran championnat. Rien
au backend — sa version reste `0.45.0`.**

**Les cartes de championnat affichent « 1/3 » et non plus « 1 ».** Un rang seul ne dit pas
s'il est bon : premier sur trois et premier sur douze ne valent pas la même chose.
L'effectif était déjà sur la carte, à douze pixels et à l'autre bout de la rangée — trop
loin du chiffre pour être lu avec lui. **Les deux nombres ne sont pas de même corps** (48px
pour la position, 24px pour le total) : la hiérarchie passe par la taille, pas par
l'opacité. **La fraction est `aria-hidden`** et doublée d'une phrase en `sr-only` — « 1/3 »
s'annoncerait « un barre oblique trois ». Aucun appel réseau nouveau : le total est
`nombre_membres`, déjà servi. La carte vit dans `Accueil.jsx` et sert **les deux écrans**.

**Six teintes Pantone sombres remplacent les aplats des cartes de championnat**, dans une
**liste séparée** de celle des marchés (`docs/decisions.md` §18) — la couleur d'un marché
est un repère fixe, celle d'un championnat distingue des championnats. Le gain est
**mesuré, pas esthétique** : le blanc y tient de **10,35:1** à **18,12:1**, quand le
terracotta ne valait que 4,41:1 sous le damier et que l'encre secondaire y tombait à
2,79:1. Pire cas des six, encre secondaire comprise : **4,97:1**. **L'attribution n'a pas
bougé** — toujours l'empreinte de l'identifiant, jamais le rang dans une liste, faute de
quoi l'écran de détail ne saurait pas quelle couleur peindre.

**Le damier passe à 7,5 % sur les deux cartes d'action**, et **l'opacité est une variable**
(`--damier-opacite`), pas un second `opacity:`. Un `opacity-[0.075]` de Tailwind écrirait
la même propriété dans la même couche : c'est l'**ordre de la feuille compilée** qui les
départagerait, pas l'ordre des classes du JSX. Les aplats colorés gardent les 15 % : ces
deux cartes sont les seules à poser le motif sur du blanc, où 15 % ne se lit plus comme une
texture mais comme un gris sale.

**L'icône du bouton « Vue piste » est retirée** — `IconeVoiture` dessine une cabine, une
caisse et deux roues, c'est-à-dire un **camion**, qui ne dit rien d'une vue piste. Le
libellé nomme déjà sa destination. **Le damier y était déjà**, à ses 15 % (10,89:1 pour le
blanc sur le bordeaux ainsi assombri) : seul le décentrement du libellé a disparu.
`IconeVoiture` reste dans `Icones.jsx`, simplement plus importée.

**Aucune animation n'a été ajoutée.** Une carte d'accueil se voit des dizaines de fois par
jour : le portier des skills de mouvement y ferme la porte, et le changement de format ne
signale aucun changement d'état. L'entrée échelonnée, l'appui et la jauge existants n'ont
pas bougé.

*La version `0.47.0` avait corrigé deux dessins : les vignettes Racing Bulls et Red Bull du
sélecteur de skin, reprises de `assets/matt.svg`, et Mercedes et Alpine barrées de gris —
un défaut d'**ordre de peinture**, pas de collision de classes (`docs/bugs-connus.md` §17).
`composants.md` compte depuis QUATRE règles d'extraction. La `0.46.0` avait réordonné la
personnalisation du profil et fait quitter le DOM à Coque et Ailerons sous un skin
d'écurie (`docs/decisions.md` §17). La `0.45.0` avait fait passer le multiplicateur des
points de **100 à 10** — une cote de 2,80 rapporte **28 points** — et livré la **migration
15** (`20260821143000_points_diviseur_10`), qui efface sans convertir : `points_gagnes`
repasse à `NULL`, `public.cotes` est vidée, les GP `cotes_figees` sont rouverts. **Un
scraping reste obligatoire.***

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les trois points
les plus urgents :

1. **Appliquer la migration 15, puis déclencher un scraping** — sans cotes en base, aucun
   GP n'est pronosticable. Elle règle au passage le statut figé prématurément du GP des
   Pays-Bas ; sa `date_course` fausse de deux heures se remet d'aplomb au scraping
   (`docs/bugs-connus.md` §4 et §11).
2. **Vérifier les migrations appliquées** dans le SQL Editor, et définir les variables
   d'environnement de production sur Vercel et Railway.
3. **Tester sur iPhone réel** — jamais fait.
