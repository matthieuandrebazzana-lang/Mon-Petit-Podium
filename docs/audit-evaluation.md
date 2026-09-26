# Audit de l'évaluation des pronostics

Diagnostic du 2026-09-26, fait **sans modifier de code**. Périmètre : `app/calcul/points.py`,
`app/calcul/pilotes.py`, `app/jobs/resultats.py`, `app/scraper/openf1.py`,
`app/scraper/unibet.py`, et les quatre Grands Prix 2026 courus depuis la mise en service
(Pays-Bas, Italie, Espagne, Azerbaïdjan).

> **Méthode.** Les verdicts en base ont été corrigés à la main au fil de la saison : les
> erreurs passées n'y sont plus visibles. Trois sources ont donc été croisées :
>
> 1. l'état de la base (requêtes SQL en lecture seule, lancées dans le SQL Editor) ;
> 2. les résultats **définitifs** relus chez OpenF1 le 2026-09-26 ;
> 3. le **code actuel rejoué** sur ces résultats pour les 72 pronostics des quatre GP, puis
>    l'historique git de `points.py` pour dater ce que les versions précédentes faisaient.
>
> Résultat du rejeu : **le code actuel rend exactement les 70 verdicts corrigés à la main**
> et laisse les deux mêmes pronostics en attente. Les erreurs constatées pendant la saison
> viennent donc de versions antérieures, ou de défauts latents que les quatre GP n'ont pas
> encore déclenchés. Les deux cas sont traités ci-dessous.

---

## 1. Types de marchés et évaluateurs

`validateur(slug)` (`points.py`) choisit l'évaluateur **à partir du slug** du marché, par
égalité stricte, par expression régulière ou par recherche de sous-chaîne. Le tableau
ci-dessous vient de l'exécution de `validateur()` sur les 39 slugs présents dans `cotes`.

| Marché (slug) | GP | Pronos | Évaluateur | Verdict |
|---|---|---|---|---|
| `vainqueur` | 4 | 20 | `_vainqueur` | ✅ |
| `podium` | 4 | 20 | `_podium` / `points_du_podium` | ✅ |
| `top-6`, `top-10` | 4 | 2 + 4 | `_top(n)` | ✅ |
| `ecurie-vainqueur` | 4 | 6 | `_ecurie_gagnante` | ✅ |
| `ecart-du-gagnant` | 3 | 7 | `_ecart_du_gagnant` | ✅ |
| `nationalite-du-vainqueur` | 4 | 4 | `_nationalite_du_vainqueur` | ✅ |
| `{écurie}-les-2-voitures-dans-le-top-10` (11 slugs) | 1–2 | 3 | `_les_deux_voitures_dans_le_top` | ✅ |
| `ecurie-qui-marque-le-plus-de-points` | 1 | 2 | `_ecurie_gagnante` | ❌ **mauvais évaluateur** |
| `equipe-qui-marque-le-plus-de-points` | 1 | 1 | `_ecurie_gagnante` | ❌ **mauvais évaluateur** |
| `ecurie-realisant-le-tour-le-plus-rapide` | 1 | 0 | `_ecurie_gagnante` | ❌ **mauvais évaluateur** |
| `marge-du-vainqueur` | 1 | 1 | — | ⛔ aucun |
| `vainqueur-course-qualification-et-tour-le-plus-rapide` | 3 | 1 | — | ⛔ aucun |
| `tour-le-plus-rapide` | 1 | 0 | — | ⛔ aucun |
| `tour-le-plus-rapide-vainqueur` | 3 | 0 | — | ⛔ aucun |
| `voiture-realisant-le-tour-le-plus-rapide` | 3 | 0 | — | ⛔ aucun |
| `les-2-voitures-sur-le-podium` | 2 | 0 | — | ⛔ aucun |
| `face-a-face-*` (12 slugs, un par duel) | 1 | 0 | — | ⛔ aucun |

**Marchés sans évaluateur : 18 slugs.** Il s'agit de `marge-du-vainqueur`,
`vainqueur-course-qualification-et-tour-le-plus-rapide`, `tour-le-plus-rapide`,
`tour-le-plus-rapide-vainqueur`, `voiture-realisant-le-tour-le-plus-rapide`,
`les-2-voitures-sur-le-podium` et les douze `face-a-face-*`. À ces 18 s'ajoutent **3 slugs
évalués par le mauvais évaluateur**, plus dangereux parce qu'ils écrivent un verdict (voir
cause C3).

**Évaluateurs sans marché réel.** `_safety_car`, `_safety_car_virtuel`, `_drapeau_rouge`,
`_meilleur_tour` et `_abandon` existent, mais aucun marché présent en base ne les
atteint. `_meilleur_tour` n'est reconnu que sur « meilleur » + « tour », alors qu'Unibet
écrit « Tour le plus rapide ».

> **Écart avec l'énoncé de la demande, signalé.** `ecurie-qui-marque-le-plus-de-points` et
> `equipe-qui-marque-le-plus-de-points` ne sont pas *sans* évaluateur : le préfixe
> `startswith(("ecurie", "equipe", "constructeur"))` les capture et les juge comme
> « écurie du vainqueur ». Le doublon de nom est réel (Unibet a changé le libellé), mais
> le défaut est plus grave qu'un marché en attente : un verdict est écrit, et un `0` ne se
> rattrape pas.

---

## 2. Correspondance des noms Unibet ↔ OpenF1

Rien n'est rapproché au scraping : `cotes` ne stocke que des **libellés** (`pilote`), et
tout se joue au moment du calcul, dans `Course` (`points.py`).

**Pilotes — `pilote_du_libelle`.** L'index est construit à partir de `/drivers` du GP
(`donnees_brutes.pilotes`). Chaque pilote y revendique cinq clés normalisées (minuscules,
sans accent ni ponctuation) : nom complet, nom de famille, acronyme, initiale + nom
(`M.Verstappen` → `mverstappen`) et prénom + nom. S'y ajoutent les alias de `pilotes.py`
(`AK.Antonelli`, `C.Sainz Jr`), servis seulement si numéro **et** nom de famille
concordent. Une clé revendiquée par deux pilotes est retirée.

**Écuries — `equipe_du_libelle`.** On tente d'abord l'égalité, puis l'inclusion par
préfixe dans un sens ou dans l'autre (`redbull` ⊂ `redbullracing`,
`audif1team` ⊃ `audi`), retenue seulement si elle ne désigne qu'une écurie. La paire de
voitures d'une écurie se lit dans les résultats (`voitures_de`), pas dans la grille
statique.

**Nationalités.** Table statique `NATIONALITES` et `nationalite_du_pilote` (numéro + nom
de famille). « Autres » se juge contre les issues sœurs.

**Écarts.** `_intervalle_secondes` lit « Moins de 5 », « Entre 5 et 10 », « Plus de 10 »
(bornes `[bas, haut[`), confronté à `gap_to_leader` du P2 (`_secondes` absorbe
`"+1 LAP"` → `inf`).

**Sur les quatre GP, tous les libellés présents ont été rapprochés** (rejeu : aucun
« non rapproché »), `I.Hadjar` et `Franco Colapinto` compris. Cas où la comparaison peut
échouer :

| Cas | Effet | Gravité |
|---|---|---|
| Libellé Unibet non dérivable (deux initiales, suffixe « Jr », surnom) sans alias | `NULL` | faible, rattrapable |
| Deux pilotes partageant une clé (même initiale + nom) | clé retirée → `NULL` | faible |
| Pilote engagé mais **absent de `session_result`** | `_numero_au_plus` rend `False` → **`0` définitif** | **élevée** si le classement est incomplet |
| Libellé d'écurie ambigu par préfixe (une future « Red Bull » face à « Red Bull Racing » et « RB ») | `NULL` + avertissement | faible |
| **Slug** reconnu par sous-chaîne au lieu du libellé exact | mauvais évaluateur → verdict faux | **élevée** — cause C3 |
| Nationalité d'un pilote absent de `GRILLE` (remplaçant) | `NULL` | faible |
| Issue « Oui/Non » d'un marché inconnu | `NULL` | faible |

La **grille statique est de nouveau périmée** : à Bakou, Hadjar (#6) est revenu chez Red
Bull et Lawson (#30) chez Racing Bulls, alors que `GRILLE` écrit l'inverse. Aucun verdict
n'en dépend aujourd'hui : l'équipe est lue dans `/drivers`, et la nationalité ne regarde
que le numéro et le nom. Seul le banc d'essai (`index_pilotes`) est faussé.

---

## 3. Moment du calcul

**Déclenchement.** `surveiller()` tourne toutes les 5 min (APScheduler, `max_instances=1`).
Un GP `a_venir` ou `cotes_figees` est traité entre `date_course + 1h30` et
`date_course + 4h30`. Au-delà, une alerte est journalisée une fois et le GP n'est plus
tenté ; seul `POST /jobs/resultats/{gp_id}` le reprend.

**Résultats incomplets.** `recuperer()` lève `ResultatsIndisponibles` (nouvel essai 5 min
plus tard) dans deux cas seulement : `session_result` vide, ou **aucune** ligne avec une
position. Dès qu'une seule position est renseignée, tout est accepté : classement,
`race_control` et `laps` sont écrits dans `resultats_gp`, et **plus jamais relus chez
OpenF1** (`gp_id` unique, `forcer=true` ne les rafraîchit pas non plus). Le GP passe
ensuite à `termine`, même s'il reste des pronostics à `NULL`.

**Relance.** Elle est idempotente à trois étages : résultats non re-téléchargés,
`attribuer_points` qui n'écrit que les `NULL`, GP `termine` sorti de la boucle. Relancer
sans `forcer` ne fait donc que remplir les `NULL`. Elle n'a qu'un effet de bord : le
passage à `termine`. **Avec `forcer=true`**, `reinitialiser_points` puis
`attribuer_points` sont deux appels distincts, sans transaction commune. Entre les deux,
tout le GP s'affiche « en attente », et un échec au milieu le laisse ainsi jusqu'à une
nouvelle relance, qui le répare.

**Ce que les données disent de la chronologie.**

| GP | Départ (UTC) | Damier OpenF1 | Job possible dès | `recupere_le` |
|---|---|---|---|---|
| Pays-Bas | 13:00 | 15:08 | 14:30 | 15:41 |
| Italie | 13:00 | 14:54 | 14:30 | 15:31 |
| Espagne | 13:00 | 14:38 | 14:30 | 15:47 |
| Azerbaïdjan | 11:00 | 12:41 | 12:30 | 13:31 |

**Sur 16 courses 2026, 13 ont duré plus de 1h30** (Monaco : 2h27). Sur les quatre GP de
l'app, le job a pourtant attendu la fin : OpenF1 n'a publié `session_result` qu'après
l'arrivée, 30 à 50 min après le damier. **La piste d'un classement capturé en pleine
course n'est pas la cause observée** : c'est un **risque du code**, qui ne tient qu'au
comportement actuel d'OpenF1 (voir R1).

**En revanche, un classement capturé est figé avant les décisions des commissaires.** À
Bakou, le classement stocké (13:31) place Bortoleto 13ᵉ à +34,230 s. Le classement
OpenF1 actuel le place 15ᵉ à +44,230 s : c'est une pénalité de 10 s appliquée après la
capture. Aucun pronostic n'en dépendait. Sur un pilote du top 10 ou du podium, le verdict
serait resté faux.

---

## 4. Anomalies réelles — GP terminés de 2026

### 4.1 Pronostics encore en attente

| GP | Prono | Marché | Issue | Cote | Cause | Verdict attendu |
|---|---|---|---|---|---|---|
| Azerbaïdjan | `80cc59ee` | `vainqueur-course-qualification-et-tour-le-plus-rapide` | Oui | 50 | aucun évaluateur | **gagné, 50 pts** — Russell : pole (Q 11373), victoire, meilleur tour |
| Azerbaïdjan | `8cd836f1` | `marge-du-vainqueur` | Plus de 10 secondes | 38 | aucun évaluateur (le code exige « marge » + « victoire ») | **raté, 0** — écart P2 : 0,196 s |

Aucun autre pronostic des GP terminés n'est à `NULL`.

### 4.2 Recalcul complet de l'Azerbaïdjan

Résultats définitifs : 1. Russell, 2. Verstappen (+0,196), 3. Hadjar, 4. Leclerc,
5. Antonelli, 6. Hamilton, 7. Lindblad, 8. Ocon, 9. Bearman, 10. Sainz ; Norris
abandonne ; safety car oui, VSC non, drapeau rouge non ; meilleur tour Russell ; points
par écurie : Mercedes 35, Red Bull 33, Ferrari 20.

| Prono | Type | Pronostic | Base | Recalcul | |
|---|---|---|---|---|---|
| `c8f732df` | vainqueur | Russell (13) | 13 | 13 | ✅ |
| `adb50bea` | vainqueur | Sainz (5000) | 0 | 0 | ✅ |
| `909b75e6` | vainqueur | Leclerc (120) | 0 | 0 | ✅ |
| `31b772fa` | vainqueur | Antonelli (66) | 0 | 0 | ✅ |
| `60677f4d` | podium | Norris (30) + Hadjar (54) | 54 | 54 | ✅ |
| `493727ff` | podium | Norris (30) + Hadjar (54) | 54 | 54 | ✅ |
| `75907af8` | podium | Antonelli (15) + Verstappen (26) | 26 | 26 | ✅ |
| `633c9c7e` | podium | Piastri (22) + Leclerc (20) | 0 | 0 | ✅ |
| `32b03d07` | bonus · vainqueur | Antonelli (66) | 0 | 0 | ✅ (voir C4) |
| `806ff1b4` | bonus · top 6 | Ocon (220) | 0 | 0 | ✅ |
| `2c5c6c30` | bonus · top 10 | Ocon (36) | 36 | 36 | ✅ |
| `8ba4adb5` | bonus · écurie + de points | McLaren (45) | 0 | 0 | ✅ **par coïncidence** (C3) |
| `d2ab4712` | bonus · écurie + de points | Red Bull (140) | 0 | 0 | ✅ **par coïncidence** (C3) |
| `80cc59ee` | bonus · triplé | Oui (50) | NULL | **50** | ⛔ C1 |
| `8cd836f1` | bonus · marge | Plus de 10 s (38) | NULL | **0** | ⛔ C1 |

Le même rejeu sur les Pays-Bas, l'Italie et l'Espagne ne donne **aucun écart** avec la
base.

### 4.3 Causes, classées par nombre de pronostics touchés

Les comptes réunissent ce qui a été touché pendant la saison, reconstitué à partir de git
et de la chronologie des jobs, et ce qui l'est encore aujourd'hui.

#### C1 — Marché sans évaluateur au moment du job → en attente · **11 pronos**

| GP | Pronos | Marché | Évaluateur livré |
|---|---|---|---|
| Pays-Bas | `82e66047`, `a956e108`, `fe876f13`, `b35445c5` | `ecart-du-gagnant` | `bf56853`, 23/08 19:35 CEST, après le job (17:41 CEST) |
| Pays-Bas | `45f47ab9`, `7c9506f1` | `nationalite-du-vainqueur` (« Autres » compris) | `4d17910` le 23/08 à 23:45, puis `2975a16` le 24/08 pour « Autres » |
| Italie | `67766978` | `alpine-les-2-voitures-dans-le-top-10` | `1685f59`, 19/09 |
| Espagne | `e3043847`, `2cafc792` | `red-bull-…`, `alpine-…-top-10` | `1685f59`, 19/09 |
| Azerbaïdjan | `80cc59ee` | `vainqueur-course-qualification-et-tour-le-plus-rapide` | **aucun** |
| Azerbaïdjan | `8cd836f1` | `marge-du-vainqueur` | **aucun** |

**Cause exacte.** Unibet ouvre des marchés nouveaux, ou renomme des marchés existants
(`ecart-du-gagnant` → `marge-du-vainqueur`), et la reconnaissance par sous-chaîne ne les
prend pas. Rien n'empêche le joueur de parier sur un marché que le backend ne sait pas
juger : l'écart n'apparaît qu'après la course. 18 slugs présents en base sont dans ce
cas.

**Correctif proposé.**
- Un **registre explicite** slug → évaluateur (§5.2), avec `marge-du-vainqueur` rattaché
  à l'évaluateur de l'écart.
- Écrire les évaluateurs manquants :
  - `tour-le-plus-rapide` et `tour-le-plus-rapide-vainqueur` → `_meilleur_tour` ;
  - `voiture-…` / `ecurie-realisant-le-tour-le-plus-rapide` → écurie du meilleur tour ;
  - `face-a-face-*` → duel (règle déjà écrite, `metier.md` §4) ;
  - `les-2-voitures-sur-le-podium` ;
  - le triplé, qui demande d'**ajouter le résultat des qualifications** à `donnees_brutes`
    (`starting_grid` est vide pour Bakou).
- **Au scraping**, marquer chaque cote « évaluable ou non ». L'écran de saisie ne propose
  pas en bonus un marché non évaluable, et le log du samedi liste ces marchés.
- **Rattrapage immédiat** : `80cc59ee` → 50, `8cd836f1` → 0, à la main, ou par
  `POST /jobs/resultats/3bf1ef36-f97c-446c-a8c6-e605f9750cd4` une fois les évaluateurs
  livrés (sans `forcer` : ils sont à `NULL`).

#### C2 — Verdict faux figé par l'idempotence → perdus à tort · **4 pronos**

Pays-Bas : `1d3106d8`, `3f490a79`, `6ac8c822`, `e1f9b002`, soit quatre demi-podiums.

**Cause exacte.** Le job du 23/08 a tourné avec le code `86e2c03`, où `points_du_podium`
testait `all(resultats)`. Il a écrit `0` sur chaque podium dont un seul pilote était
juste. Le correctif `bf56853` est arrivé deux heures après. `attribuer_points` n'écrit
que les `NULL` : le `0` restait donc figé jusqu'au rejeu `?forcer=true`
(`bugs-connus.md` §22 et §24).

**Correctif proposé.** Il est déjà en place (0.54.0, `forcer=true`), mais la mécanique
reste : **toute correction d'évaluateur livrée après un job ne s'applique pas toute
seule** aux verdicts déjà écrits. Il faudrait un statut d'évaluation (§5.2) et un
recalcul complet déterministe (§5.4). Tant que ce n'est pas fait, chaque livraison sur
`points.py` doit s'accompagner d'un `forcer=true` sur les GP déjà courus.

#### C3 — Mauvais évaluateur choisi par préfixe · **3 pronos** (justes par coïncidence)

Italie `8ad3c37f` (`equipe-qui-marque-le-plus-de-points`, Ferrari) ; Azerbaïdjan
`8ba4adb5` et `d2ab4712` (`ecurie-qui-marque-le-plus-de-points`, McLaren et Red Bull).

**Cause exacte.** `validateur()` finit par
`slug.startswith(("ecurie", "equipe", "constructeur"))` → `_ecurie_gagnante`. Trois
marchés différents tombent dedans : l'écurie du **vainqueur**, l'écurie qui **marque le
plus de points**, et l'écurie du **meilleur tour**. Sur les quatre GP, l'écurie du
vainqueur a toujours été aussi la plus marquante, d'où des verdicts justes. Ce n'est
qu'une coïncidence : aux Pays-Bas, McLaren et Mercedes finissent **à égalité à 33
points**. Un pari « Mercedes » y aurait été déclaré perdu, alors que l'issue dépend de la
règle d'égalité d'Unibet, qu'aucun code n'écrit.

**Correctif proposé.** Supprimer la reconnaissance par préfixe : `ecurie-vainqueur` en
égalité stricte. Écrire `_ecurie_la_plus_marquante`, qui somme `points_fia` par écurie,
avec une **règle d'égalité à décider**. Tant qu'elle n'est pas décidée, une égalité vaut
`NULL`, jamais `0`.

#### C4 — Même issue pariée deux fois (bonus = pronostic obligatoire) · **3 pronos**

Pays-Bas `48f08402` (bonus Antonelli sur le marché `podium`, même issue `o701094802` que
le podium `3f490a79` du même joueur, **payé deux fois**) ; Espagne `76b78d5c` (bonus
Verstappen sur `vainqueur`, même issue que son vainqueur `0559c6c2`) ; Azerbaïdjan
`32b03d07` (bonus Antonelli sur `vainqueur`, même issue que `31b772fa`).

**Cause exacte.** Ce n'est pas un défaut de l'évaluateur, qui juge juste. La route de
saisie refuse deux bonus identiques, mais pas un bonus identique au vainqueur ou à un
pilote du podium. Un joueur peut ainsi doubler sa mise sur un même événement : c'est
le seul chemin du code actuel qui produise un gain « en trop » sans erreur de jugement.

**Correctif proposé.** C'est une **décision métier**, que `metier.md` ne tranche pas.
Si le doublon est interdit, `enregistrer` refuse un bonus dont l'issue est celle du
vainqueur ou d'un pilote du podium, en comparant les **libellés** (`metier.md` §2 : les
identifiants diffèrent d'un marché à l'autre).

#### C5 — Classement figé avant les pénalités · **0 prono** (constaté sur Bakou)

**Cause exacte.** `resultats_gp` est écrit une fois et jamais rafraîchi (§3). La
pénalité de Bortoleto à Bakou n'y figure pas.

**Correctif proposé.** Une évaluation provisoire, puis définitive (§5.3).

#### C6 — VSC jamais détecté · **0 prono** (latent)

**Cause exacte.** `_lire_direction_de_course` cherche « VIRTUAL SAFETY CAR ». Or OpenF1
écrit **`VSC DEPLOYED` / `VSC ENDING`** : ces messages, présents dans les données 2026
rejouées, tombent dans les « non reconnus ». `virtual_safety_car` reste donc toujours
`False`. Un pari « VSC : Oui » serait déclaré perdu, définitivement, et un pari « Non »
gagné à tort.

**Correctif proposé.** Reconnaître aussi `VSC DEPLOYED`, et ajouter un test sur les vrais
messages.

### 4.4 Risques du code, non constatés sur les quatre GP

| # | Risque | Effet possible |
|---|---|---|
| R1 | Job dès départ + 1h30, alors que 13 courses sur 16 durent plus longtemps. La garde « au moins une position » est faible, et la capture est définitive | Si OpenF1 publie un classement partiel en cours de course : vainqueur, podium et top N jugés sur un classement intermédiaire, `0` figés |
| R2 | Pilote absent de `session_result` → `False` (`_numero_au_plus`) | Classement incomplet → pronos perdus à tort, définitivement |
| R3 | `laps` et `race_control` lus au même instant que le classement, jamais relus | Meilleur tour ou safety car manquant si les données arrivent en retard |
| R4 | `session_de_course` choisit parmi `session_type=Race`, qui inclut les **sprints**, la plus proche de `date_course` | `date_course` fausse d'un jour (cf. `bugs-connus.md` §11) → GP jugé sur le sprint |
| R5 | `forcer=true` non transactionnel | GP affiché entièrement « en attente » si un appel échoue entre la remise à `NULL` et l'écriture |

> **Sur le meilleur tour stocké — écart signalé.** La demande indiquait qu'il n'est pas
> fiable : 21 ou 22 entrées dans `laps`, dont la requête d'audit prend la première. La
> mesure dit autre chose. `laps` est **réduit volontairement à un meilleur tour par
> pilote** (`_meilleurs_tours`) : 22 entrées pour 22 pilotes, 21 aux Pays-Bas où
> Verstappen n'a bouclé aucun tour. La liste est triée du plus rapide au plus lent, et le
> calcul prend de toute façon le `min`. Le pilote retenu concorde avec OpenF1 sur les
> quatre GP (#16, #12, #63, #63). Le seul défaut réel sur le meilleur tour est C1 : aucun
> marché « tour le plus rapide » n'atteint `_meilleur_tour`. Reste le risque R3.

---

## 5. Pertinence des solutions envisagées

### 5.1 Identifiants canoniques stockés au scraping — **pertinent, priorité moyenne**

Le rapprochement par nom n'a produit **aucune** erreur sur les quatre GP : les 72
pronostics ont été rapprochés. Stocker `numero_pilote` ou `ecurie_id` dans `cotes` au
scraping ne corrige donc aucune cause observée. Son vrai gain est **le moment** : un
libellé non rapproché se verrait le samedi, avant l'ouverture des pronostics, et non le
dimanche soir. Il permettrait aussi de fonder l'exclusion croisée et la règle C4 sur
autre chose qu'un libellé.

Limite : au scraping, OpenF1 ne connaît pas encore les engagés de la course. La
correspondance viendrait donc de `pilotes.py`, qu'il faut tenir à jour à chaque GP
(périmée aujourd'hui, §2). Le calcul doit garder le rapprochement par libellé en repli.

### 5.2 Un évaluateur par type de marché, statut « non évaluable » — **très pertinent, priorité 1**

C'est le cœur de C1 et C3, qui totalisent 14 pronostics. La reconnaissance par
sous-chaîne (`startswith("ecurie")`, `"marge" and "victoire"`) est ce qui laisse passer
les marchés renommés et capture les marchés voisins. À faire :

- un registre `slug exact → évaluateur`, plus les familles déclarées par `fullmatch`
  (`{écurie}-les-2-voitures-dans-le-top-N`, `face-a-face-{a}-{b}`, `top-N`) ;
- aucune correspondance partielle ;
- un **statut distinct** de `points_gagnes` : `en_attente` (données manquantes,
  rattrapable), `non_evaluable` (pas d'évaluateur, visible et listé), `gagne`, `perdu`.
  Aujourd'hui `NULL` confond « pas encore » et « jamais », et la documentation demande de
  relire les logs pour les distinguer ;
- le même registre consulté **au scraping**, pour marquer ou filtrer les marchés non
  évaluables avant qu'on puisse parier dessus.

### 5.3 Évaluation provisoire puis définitive le lundi — **pertinent, priorité 2**

C'est la réponse à C5, R1 et R3 : la capture unique et définitive de `resultats_gp` est
ce qui fige les classements d'avant les commissaires. À faire :

- évaluer à la publication du classement, avec un statut `provisoire` ;
- relire OpenF1 **à J+1 ou J+2**, et non « le lundi » : Bakou 2026 se court un samedi ;
- écraser `resultats_gp`, puis recalculer tout le GP.

Le recalcul définitif doit **réécrire** les verdicts provisoires, donc sortir de la règle
« n'écrire que les `NULL` ». Il suppose §5.4.

### 5.4 Job idempotent — **déjà en place ; c'est la forme d'idempotence qu'il faut changer**

Le job est idempotent à trois étages (§3). C'est justement ce qui a figé C2 : il
**protège le premier verdict écrit**, y compris quand il est faux. La propriété utile
n'est pas « n'écrire qu'une fois », mais « rejouer donne toujours le même résultat » :

- un calcul **pur** de `(données, cotes, pronostics)` vers les verdicts, ce que
  `calculer()` est déjà ;
- une écriture qui **remplace** les verdicts du GP dans une seule transaction.

Cela rend `forcer=true` inutile et supprime R5. La sécurité aujourd'hui assurée par
« `NULL` seulement » passe alors par le statut de §5.2 et par les tests de §5.5.

### 5.5 Tests pytest à partir des résultats réels des GP passés — **très pertinent, priorité 1**

Le backend n'a **aucun test**. Le rejeu fait pour cet audit en est la preuve de
faisabilité : 72 pronostics, 4 GP, le code actuel rend exactement les verdicts corrigés
à la main. Il suffit de le figer :

- en fixtures : le JSON OpenF1 des quatre GP, les cotes et les verdicts attendus (ceux de
  la base, désormais justes). Un test par GP compare `calculer()` à ces verdicts ;
- un test qui parcourt **tous les slugs vus en base** et exige pour chacun un évaluateur,
  ou une entrée explicite `non_evaluable`. Ce test aurait fait échouer la CI sur C1 et C3
  avant chaque GP ;
- des tests sur les vrais messages `race_control` (C6) et sur une égalité de points par
  écurie (Pays-Bas, C3).

Ces tests sont le filet qui rend sûres les priorités 2 et 3. Ils se font donc
**en premier**.

### Ordre proposé

1. Tests pytest de non-régression (§5.5).
2. Registre d'évaluateurs, statut, filtrage au scraping (§5.2) ; évaluateurs manquants
   (C1), correction de C3 et de C6.
3. Recalcul déterministe et réécrivant (§5.4), puis provisoire → définitif (§5.3).
4. Identifiants canoniques (§5.1) et décision métier sur C4.
