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

**Version `0.55.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées. **Le backend passe à `0.54.0`** — un marché
de plus, et la première route qui défait une écriture.

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

*La version `0.54.0` avait fait payer le podium pilote par pilote, fait entrer
`gap_to_leader` dans `Ligne`, sorti le succès du bordeaux, gardé le dimanche soir sur le
Grand Prix couru et ouvert le calendrier là où il sert. La `0.53.0` avait remis le numéro du
museau à l'endroit. La `0.52.0` avait fait entrer la photo DANS le cockpit. La `0.51.0` avait
réparé les photos. La `0.45.0` avait fait passer le multiplicateur des points de 100 à 10.*

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les trois points
les plus urgents :

1. **Rejouer le GP des Pays-Bas en forçant**, une fois la `0.54.0` du backend déployée sur
   Railway :
   `curl -X POST "https://<railway>/jobs/resultats/33b835cc-5c17-40f7-a41f-3e95fc14885a?forcer=true" -H "X-Admin-Secret: <valeur>"`.
   **Sans `?forcer=true`, les demi-podiums notés `0` ne bougeront pas** — seuls les `NULL`
   se rattrapent. La réponse porte `reinitialises` (points effacés) et `en_attente` (ce que
   le calcul n'a toujours pas su juger) : **c'est cette seconde liste qu'il faut lire.**
2. **Appliquer les migrations 15, 16, 17 puis 18, dans cet ordre.** La 17 est celle sans
   laquelle **aucune photo ne s'enregistre**. La 18 est celle sans laquelle **la couleur du
   texte ne s'enregistre pas**. Si la 2, la 8, la 10, la 12 ou la 16 est rejouée un jour,
   rejouer la 18 derrière. **Aucune migration n'est requise par la version `0.55.0`** — le
   recalcul forcé n'écrit que des colonnes existantes, et la nationalité vit dans le code.
3. **Tester sur iPhone réel** — jamais fait. En priorité : **l'opacité `0,4`** des cartes
   passées, qui est un jugement de lisibilité en plein soleil autant qu'un rapport de
   contraste ; **le défilement d'ouverture du calendrier**, qui se pose sur des `offsetTop`
   mesurés pendant l'animation d'entrée ; **le sélecteur de vingt-quatre Grands Prix** ; et
   **la photo de 15px dans le cockpit**.
