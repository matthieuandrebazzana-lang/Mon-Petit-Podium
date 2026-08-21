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

**Version `0.50.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées : fondations, authentification, championnats,
scraper Unibet, pronostics, résultats OpenF1, classements, profils, finitions, navigation,
scraping automatique.

**Cette version ajoute les photos** — celle d'un joueur, celle d'un championnat. Le backend
change aussi : sa version passe à `0.50.0`.

**Rien n'est stocké en base : deux colonnes ne portent que des URL.** `profils.avatar_url`
et `championnats.photo_url` pointent vers deux compartiments **publics** de Supabase
Storage, plafonnés à **2 Mo**, limités à jpg, png et webp (migration 16). Une image de
2 Mo en base64 pèserait 2,7 Mo dans une colonne `text`, serait relue à chaque classement
et traverserait le réseau à chaque affichage.

**Le dépôt emprunte les DEUX chemins de données, et c'est le critère de la section 3
appliqué tel quel.** Le **fichier** va directement à Supabase : les politiques de
`storage.objects` décrivent exactement le cas — **le premier segment du chemin EST
l'autorisation**, comparé à `auth.uid()` pour un avatar, remonté à `cree_par` pour un
championnat. L'**URL** passe par FastAPI, parce que c'est une écriture. C'est là que
`app/api/stockage.py` vérifie qu'elle désigne bien notre projet : sans cette vérification,
une URL libre en base serait **un pixel espion posé sur l'écran des autres joueurs**, leur
photo s'affichant au classement, sur la piste et au résumé d'un GP.

**La photo est entrée DANS `Pastille`, pas dans un `Avatar` posé à côté.** « Comment
représente-t-on un joueur dans un rond » est une question posée par cinq écrans : elle a un
propriétaire. Sans photo, ce sont les initiales sur teinte dérivée du pseudo — l'affichage
d'origine, qui n'est pas un cas dégradé.

**Une seule règle gouverne les trois listes** — classement, vue piste, résumé d'un GP :
**la colonne de pastilles n'apparaît que si quelqu'un, dans cette liste, a une photo.**
Posée ligne par ligne, la question donnerait une liste ébréchée ; jamais posée, un
championnat sans photo gagnerait une colonne d'initiales posées à côté du pseudo qu'elles
abrègent. Avec elle, **un championnat sans photo dessine exactement l'écran d'avant, au
pixel près**.

**Sur la piste, la pastille est au-dessus de la voiture, jamais à sa place.** Le pseudo est
peint sur l'aileron arrière, dans le SVG : le remplacer voudrait dire un visage de douze
pixels contre le seul identifiant que la piste porte depuis la `0.39.0`. La **coiffe** de
30px est calculée une fois pour toute la piste — une hauteur réservée qui dépendrait de la
présence d'une photo donnerait des altitudes différentes pour des scores égaux
(`docs/decisions.md` §19). Elle entre dans **trois** calculs, et en oublier un se voit.

**Un seul mouvement, aucun jeton nouveau.** `.t-photo` transitionne **l'opacité seule** avec
`--duration-fast` et `--ease-smooth-out`. Pas d'échelle : la pastille est déjà là, ronde,
à sa taille — c'est son contenu qui se substitue. `.t-photo-envoi` floute le **conteneur**
pendant l'envoi, parce qu'au premier dépôt il n'y a encore aucune image à flouter.

**Un défaut qu'`onLoad` seul ne voit pas a été traité d'emblée** : une image déjà en cache
est décodée avant que React n'ait posé son gestionnaire, `onLoad` n'est jamais appelé, et
une photo animée en opacité reste **invisible pour toujours** — le cas ordinaire dès la
deuxième visite d'un écran. `lib/usePhoto.js` lit `naturalWidth` par une fonction de
référence.

**Deux écarts assumés, tous deux signalés.** Le rayon des photos de carte est
`rounded-champ` (14px) et non les 12px demandés : l'échelle des formes ne connaît pas le
12, et un `rounded-[12px]` aurait ouvert une sixième valeur de rayon pour un écart
invisible. Et sur une carte d'accueil portant une photo, **le nom du championnat tronque
plus tôt** — la photo prend 68 des 311 pixels de la rangée, au nom, qui passe d'environ
vingt-deux caractères à quinze. Cela ne touche que les championnats dont on a choisi une
photo.

*La version `0.49.0` avait refondu la vue piste de fond en comble : fond beige
`#F4EFEA` extrait de `assets/vue_piste.svg`, inversion de toute l'encre de l'écran, bandeau
portant le nom du championnat dans SA couleur sous un damier gris à 11 %, placement des
voitures séparant enfin la hauteur (le score seul) du chevauchement (mesuré à l'écran), et
score passé sous chaque voiture. La `0.48.0` avait retouché l'accueil et l'écran
championnat — « 1/3 » au lieu de « 1 », six teintes Pantone sombres
(`docs/decisions.md` §18). La `0.45.0` avait fait passer le multiplicateur des points de
**100 à 10** et livré la **migration 15**, qui efface sans convertir. **Un scraping reste
obligatoire.***

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les trois points
les plus urgents :

1. **Appliquer les migrations 15 puis 16, puis déclencher un scraping.** Sans cotes en
   base, aucun GP n'est pronosticable ; la 15 règle au passage le statut figé
   prématurément du GP des Pays-Bas (`docs/bugs-connus.md` §4 et §11). **La 16 crée les
   deux compartiments Storage en même temps que les colonnes** : sans elle, aucun dépôt de
   photo n'aboutit — mais rien ne tombe en panne, le backend servant `null` partout.
2. **Vérifier les migrations appliquées** dans le SQL Editor, et définir les variables
   d'environnement de production sur Vercel et Railway.
3. **Tester sur iPhone réel** — jamais fait. Le sélecteur de photo en particulier : c'est
   le premier `<input type="file">` du projet, et il n'a jamais rencontré Safari iOS.
