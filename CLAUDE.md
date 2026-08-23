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

**Version `0.53.0`.** Les seize maquettes sont codées, la barre de navigation est en place,
les onze étapes de développement sont livrées. **Le backend bouge** — une colonne servie par
trois modèles Pydantic — il passe donc à `0.52.0`.

### Le numéro était à l'envers depuis l'origine, et le commentaire le défendait

La planche écrit le numéro du museau sous `rotate(180)`. **C'est la convention réelle d'une
monoplace** — le numéro se lit depuis la voiture qu'on double — et le code le disait en
toutes lettres, ce qui l'a fait passer pour une intention pendant douze versions. Le défaut
n'était pas dans le dessin mais dans le contexte : **toutes les vues de l'app sont des vues
de dessus.**

**Retirer la rotation ne suffisait pas.** Elle ne renversait pas seulement les glyphes, elle
renversait leur position autour de la ligne de base : sous rotation les chiffres occupent
`[yNumero, yNumero + 0,717 em]`, à l'endroit `[y − 0,717 em, y]`. La ligne de base descend
donc d'exactement une **hauteur de capitale**, et le numéro retrouve **le pixel qu'il
occupait** — sur les douze livrées à la fois, parce que le décalage est calculé et non relevé
à l'œil. Vérifié par rendu comparé, ancien et nouveau côte à côte : le calcul seul aurait
laissé passer une erreur de signe.

### La couleur du texte se choisit, et `NULL` veut dire « pas de choix »

Le numéro et le pseudo prennent désormais une couleur du membre. **La migration 18 ne
remplit pas rétroactivement la colonne**, et c'est tout son sujet : `NULL` ne veut pas dire
« pas de couleur » mais « pas de choix », auquel cas chaque texte garde l'encre **calculée**
qui contraste avec l'aplat sous lui. Un `#FFFFFF` posé d'office aurait rendu le numéro
invisible pour tout membre à coque blanche, argent, beige ou jaune. D'où **deux instructions
séparées** — `add column` sans défaut, puis `set default` — parce qu'écrites en une seule,
les deux effets seraient venus ensemble et toute la base aurait basculé au blanc.

La couleur entre dans **`livreeDuMembre`**, qui reste le seul propriétaire de « ce que porte
cette voiture » : les quatre surfaces qui en dessinent une la répandent déjà par un `spread`,
et un second chemin aurait laissé le réglage visible sur son propre profil et nulle part où
quelqu'un d'autre le voit. Le contraste, lui, **se mesure et se signale sans se refuser** :
l'écran compare la couleur choisie à l'aplat du museau de la livrée en cours et le dit sous
les 3:1 d'un grand texte.

**L'aperçu du profil porte enfin son pilote** — photo dans le cockpit, initiale à défaut,
même `clipPath` et même graine que la vue piste. C'était le seul écran où l'on règle sa
voiture, et le seul à la montrer vide.

### « Résultats par Grand Prix » — et une convention qui a payé

Le nouvel écran remplace l'entrée « Calendrier » d'un championnat et répond à la seule
question que rien ne montrait : **qu'est-ce que les autres ont joué ?** La saison Grand Prix
par Grand Prix est déjà l'onglet Calendrier de la barre basse. L'écran `Calendrier` reste en
place, non monté (§6) — son mini-classement par course n'existe nulle part ailleurs.

**Le sélecteur du haut n'est pas un choix d'interface, c'est la forme de la donnée** :
`pronostics_du_championnat` sert **un** Grand Prix à la fois, et une saison entière
demanderait vingt-quatre allers-retours Railway en série. Il réemploie **`Onglets`**, écrit
pour les marchés de la maquette 08 et gardé « pour le jour où il redevient la bonne
réponse » : ce jour est arrivé, zéro ligne de CSS ajoutée. La convention du §6 vient de
payer pour la première fois.

Un membre sans pronostic **n'est pas dépliable** et le dit sur sa ligne — un chevron qui
ouvre sur rien est une promesse fausse — mais la place du chevron reste **tenue**, sans quoi
la colonne cesserait d'être une colonne.

### « Pronostiquer » sur un Grand Prix déjà joué

Les deux calendriers proposaient encore de saisir des favoris là où le widget de l'accueil
menait au récapitulatif depuis la version `0.5.1`. **La règle avait un propriétaire pour la
condition d'existence du bouton — `cotesArretees` — et aucun pour le choix de sa
destination.** Ce sont deux questions distinctes, et les fondre aurait fait porter au mode
prévisualisation une décision qui ne le concerne pas.

Le cache pouvait réintroduire le défaut à lui seul : quatre surfaces en dépendent, une seule
était balayée après un enregistrement. **`oublierMesPronostics` les balaie ensemble** — même
motif qu'`oublierMesApparitions`, et pour la même raison : quatre effacements écrits
séparément auraient fini par en oublier un.

### Rien de nouveau côté mouvement, une fois de plus

Le portier a rejeté le seul candidat : **le changement de Grand Prix ne fait aucun fondu.**
La liste des membres ne se transforme pas, elle est remplacée par une donnée qui arrive du
réseau — il n'y a pas d'« avant » à faire tenir, et c'est le squelette qui occupe
l'intervalle. Restent la pastille glissante d'`Onglets` et l'accordéon `.t-acc`, déjà dans
le vocabulaire.

Un seul sélecteur a été **étendu**, jamais forké : `.t-voiture-teinte` couvre maintenant
`text`, dans la règle normale comme sous mouvement réduit. Parcourir la palette repeint le
numéro et le pseudo comme elle repeint déjà la coque, à la même durée et sur la même courbe.

> **Deux points à trancher restent ouverts**, écrits dans `docs/roadmap.md` §3.12 et §3.13 :
> la demande d'icône se contredisait (« la troisième icône » désigne le calendrier, le
> cadrage `322 0 161,64 133,85` désigne la silhouette de pilote — **c'est le cadrage qui a
> été suivi**, et ce glyphe est aussi celui de l'onglet Profil), et la couleur de texte
> **ne revient pas à « automatique »** une fois choisie.

*La version `0.52.0` avait fait entrer la photo DANS le cockpit — une identité intégrée au
dessin ne coûte pas un pixel, là où une pastille posée à côté coûtait trente pixels de coiffe
à tout le championnat — et corrigé `Pastille`, dont l'initiale était illisible sur une teinte
sur quatre depuis l'origine (`bugs-connus.md` §19). La `0.51.0` avait réparé les photos, qui
n'avaient jamais fonctionné : une contrainte `check` incompilable — **PostgreSQL plafonne un
compteur `{m,n}` à 255** — que la migration 17 remplace par un `char_length`. La `0.50.0`
avait livré les photos, la `0.49.0` refondu la vue piste, la `0.45.0` fait passer le
multiplicateur des points de 100 à 10. **Un scraping reste obligatoire.***

**Ce qui reste à faire est dans [`docs/roadmap.md`](docs/roadmap.md).** Les trois points
les plus urgents :

1. **Appliquer les migrations 15, 16, 17 puis 18, dans cet ordre, puis déclencher un
   scraping.** La 17 est celle sans laquelle **aucune photo ne s'enregistre**. La 18 est
   celle sans laquelle **la couleur du texte ne s'enregistre pas** — le sélecteur s'affiche,
   et « Enregistrer ma voiture » retombe en `42703`. Si la 2, la 8, la 10, la 12 ou la 16
   est rejouée un jour, rejouer la 18 derrière.
2. **Vérifier les migrations appliquées** dans le SQL Editor, définir les variables
   d'environnement de production sur Vercel et Railway, et **supprimer le compte de
   diagnostic** laissé par la localisation du défaut (`docs/roadmap.md` §1.5).
3. **Tester sur iPhone réel** — jamais fait. Quatre choses en priorité : le recadrage, qui
   est le premier geste multi-touch du projet ; **la photo de 15px dans le cockpit**, qui
   décidera si le cadrage exporté doit se resserrer sur le visage ; **le sélecteur de
   vingt-quatre Grands Prix**, dont la pastille glissante se positionne sur des `offsetLeft`
   mesurés dans un conteneur qui défile en même temps ; et **le numéro remis à l'endroit**,
   dont la compensation de ligne de base suppose la métrique d'Helvetica.
