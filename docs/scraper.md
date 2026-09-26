# Scraper Unibet et résultats OpenF1

Comment les données entrent dans la base, et pourquoi c'est écrit ainsi.

Fichiers : `backend/app/scraper/unibet.py`, `openf1.py`, `backend/app/jobs/scraper.py`,
`jobs/resultats.py`, `jobs/rattachement.py`, `backend/app/calcul/points.py`, `pilotes.py`.

---

## 1. Ce que le cahier des charges annonçait, et ce qu'Unibet fait vraiment

Trois écarts constatés en interrogeant l'API. **Ils expliquent l'essentiel du code.**

### 1.1 L'API exige un jeton

`/lvs-api/...` répond `401 {"message":"Missing X-LVS-HSToken"}` sans en-tête
`X-LVS-HSToken`. Aucun **compte** n'est nécessaire, mais l'en-tête, lui, l'est.

Le jeton est déposé en clair dans la configuration de n'importe quelle page de paris
(clés `pselNonExpiringHsToken` et `hsToken`). `jeton()` va le lire sur `/paris-formule-1`.

> **Il est relu à chaque scraping, jamais stocké** : il change à chaque déploiement
> d'Unibet.

> **La page d'accueil du site répond 403** aux clients non navigateur ; celle de la
> Formule 1 répond 200. D'où ce choix de page. Un `User-Agent` vide ou exotique se fait
> aussi refuser — les en-têtes sont ceux d'un navigateur banal.

### 1.2 `price` est une chaîne à la française

« 2,80 », pas un nombre. Un `float(price)` lève, un `price * 10` concatène.
`en_points()` est le **seul** endroit qui traite le cas.

*Cross-contrôle rassurant* : Unibet expose aussi un champ `sort` qui vaut exactement
`round(price × 100)` — zéro écart sur 44 cotes. Il n'est pas utilisé (rien ne le documente
comme tel), mais il confirme que l'arrondi tombe juste sur le leur. **Il vaut cent fois la
cote, donc dix fois les points depuis la v0.45.0** : ne jamais le prendre pour un nombre
de points tout fait.

### 1.3 L'API ne rend qu'UN marché par événement

Le marché vedette, « Vainqueur », alors que l'événement annonce `count: 3`. **Aucun
paramètre ne la fait céder** : `includeAllMarkets`, `marketTypeDisplayGroupId`, `groupId`,
`allMarkets`, `topMarketOnly` — tous essayés, sans le moindre effet. Il n'existe aucun
endpoint JSON par événement, et `next/200` est refusé.

**Les marchés complets ne sont exposés que par la page de l'événement**, rendue côté
serveur, qui embarque ses données dans `<script id="serverApp-state" type="application/json">`.

> **`marches()` lit ce bloc : c'est du JSON, avec les mêmes champs que l'API, pas du
> HTML.** Aucune balise n'est interprétée, rien ne dépend d'une classe CSS.

**Conséquence : l'URL de la page d'événement doit être exacte.** Elle s'écrit
`/paris-formule-1/{catégorie}/{gp}/{id-numérique}/course`, et **le moindre écart de slug
renvoie 404** — un identifiant numérique seul ne suffit pas. `slug()` reproduit donc la
fonction du site, retrouvée dans son bundle : minuscules, accents ramenés à la lettre de
base, reste en tirets, tirets fondus et rognés. « GP Pays Bas » → `gp-pays-bas`.

---

## 2. Structure de la réponse

**Endpoint des cotes d'un nœud :**
```
https://www.unibet.fr/lvs-api/next/50/{noeud}
  ?lineId=1&originId=2&breakdownEventsIntoDays=true&showPromotions=true&pageIndex=0
```

**Nœud racine de la Formule 1 : `p59209509`** — parent de tous les GP.

Tout se trouve dans un objet `items` dont les clés portent un préfixe :

| Préfixe | Type | Champs utiles |
|---|---|---|
| `p…` | Championnat / GP | `desc`, `parent` |
| `e…` | Événement (Course) | `desc`, `start`, `parent` |
| `m…` | Marché | `desc`, `parent` |
| `o…` | Issue / cote | `desc` (pilote), `price`, `parent` |

La hiérarchie se reconstruit via `parent` : une cote pointe vers son marché → son
événement → son GP.

> **Unibet n'affiche que le GP SUIVANT, jamais toute la saison.** Le scraper ne s'appuie
> **jamais** sur une liste codée en dur : il interroge le nœud racine, découvre ce qui est
> disponible, et traite ce qu'il trouve. C'est aussi pourquoi `public.grands_prix` ne
> contient qu'un GP à la fois, et pourquoi le calendrier de la saison vit côté frontend
> (voir `calendrier.md`).

> **Les marchés varient d'un GP à l'autre.** Le noyau (vainqueur, podium, top 6, top 10,
> duels, écurie) est presque toujours là ; les marchés spéciaux apparaissent selon le
> circuit. **Le scraper les découvre dynamiquement, jamais ne les suppose.**

---

## 3. Le nœud racine ne rend pas que des GP

Il rend aussi **« Championnat du monde »**, au même rang et avec le même `tag: "League"` —
le vainqueur du championnat, daté d'un 6 décembre de convenance. L'enregistrer créerait un
faux Grand Prix, qui deviendrait le « prochain GP » de l'accueil.

> **Le filtre porte sur l'ÉVÉNEMENT, pas sur le nom du championnat** : seuls les
> événements dont le libellé donne le slug `course` sont retenus. Le tri est
> sémantiquement juste (c'est la course qu'on valide, pas les qualifications ni le sprint)
> et il écarte le championnat sans avoir à le nommer.
>
> `eType` ne sert à rien ici : il vaut `R` pour les deux.
>
> **Tout événement écarté est journalisé avec son libellé** — si Unibet renomme
> « Course », les logs le diront au lieu de laisser le scraper ne rien trouver en silence.

---

## 4. Le fuseau horaire — le piège qui a coûté deux heures

> ### `start` est en UTC. Le lire en heure de Paris décalait TOUTE la programmation.
>
> `FUSEAU_UNIBET = ZoneInfo("UTC")`. Le champ vaut `"2608231300"` (AAMMJJHHMM) pour un
> départ que **OpenF1 — source autorisée, publiée en UTC** — donne à `13:00Z`, soit 15h00
> à Zandvoort. Les quatre séances du week-end concordent à la minute près :
>
> | Séance | Unibet `start` | OpenF1 |
> |---|---|---|
> | Essais 1 | `2608211030` | `10:30Z` |
> | Sprint | `2608221000` | `10:00Z` |
> | Qualification | `2608221400` | `14:00Z` |
> | **Course** | `2608231300` | **`13:00Z`** |
>
> **Ce n'était pas un défaut d'affichage.** `date_course` gouverne la fermeture des
> pronostics (départ − 5 min) et le job de résultats (départ + 1h30, fenêtre 3 h) : avec
> deux heures d'avance, les pronostics se fermaient à 12h55 pour une course à 15h00, et
> le job épuisait sa fenêtre **pendant que la course se courait**.
>
> Une conclusion contraire figure encore dans le commentaire de la migration 3 et dans
> `requirements.txt` : **elles sont périmées.** Voir `bugs-connus.md`.

`tzdata` reste dans `requirements.txt` : `ZoneInfo` lit la base de fuseaux du système,
que beaucoup d'images Linux minces n'embarquent pas.

---

## 5. La date des qualifications

`decouvrir()` classe les événements en trois tas : la « Course », les **qualifications**
(motif `qualif`, insensible à la casse, posé sur le libellé brut — Unibet écrit
« Qualifications », rien ne garantit qu'il n'écrira pas « Qualifying »), et les écartés.

> ### La DERNIÈRE qualification l'emporte, jamais la première
> Un week-end sprint en compte deux : celle du sprint le vendredi, et la vraie
> qualification le samedi. C'est la seconde qui arrête la grille de départ, donc la seule
> après laquelle les cotes ont un sens. Retenir la première ferait figer les cotes **un
> jour trop tôt, sur une grille qui n'existe pas encore.**

Une qualification postérieure au départ est écartée (horaire abîmé, et elle déclencherait
un scraping après la course).

### Il n'y a plus de repli (v`0.57.0`)

Le scraper retenait `date_course − 22h` quand Unibet n'annonçait rien. **Ce repli est
retiré**, et `resoudre_qualifications` ne rend plus que deux cas : `"unibet"`, ou
`"inconnue"`.

> **Il ne devinait pas seulement, il écrasait.** L'upsert écrivait
> `date_qualifications` à chaque passage. Une heure explicite posée en base par la
> migration 19 était donc remplacée par le calcul au premier scraping — et
> `seancesDuGp` (`lib/calendrier2026.js`) préfère l'heure de la base à celle de la table
> statique. La fiche du GP d'Italie annonçait 17h00 pour des qualifications à 16h00.

Et la constante était fausse. L'écart réel entre les qualifications et le départ vaut
**23 h** sur huit week-ends de 2026, **22 h** sur deux (Austin et le Mexique), **24 h** au
Brésil et **26 h** à Las Vegas, dont les qualifications se courent le vendredi soir : une
constante appliquée aux douze en manque neuf.

**Quand Unibet se tait, la clé n'est pas écrite dans `ligne`** — l'upsert ne la touche
pas, et la valeur déjà en base survit. C'est la règle « on se ferme sur une donnée qu'on
n'a pas » appliquée à l'écriture plutôt qu'à la lecture. L'heure vient alors des
migrations 19 et 20, relevée sur le calendrier officiel de la FIA.

> ### Écart signalé (CLAUDE.md §6) : ce que le retrait coûte
> Une ligne **neuve** dont Unibet ne publie pas le programme reste désormais sans heure
> de qualifications — donc **sans figeage automatique et sans bouton de pronostics**,
> jusqu'à ce qu'Unibet la publie. Avant, elle recevait une heure approchée qui finissait
> par déclencher le job.
>
> Le cas concret est **une ligne manuelle jamais adoptée** : le scraper insère alors une
> seconde ligne, qui n'hérite d'aucune heure. C'est une raison de plus de tenir le geste
> d'adoption (`adopter_grand_prix`, `roadmap.md`), pas un argument pour rendre le repli —
> une heure manquante se voit dans les logs, une heure fausse ne se voyait pas.

> **Le `warning` se lit dans les deux sens** : soit l'heure explicite est déjà en base et
> tout va bien, soit la ligne est neuve et restera muette. **À relire dans les logs le
> samedi du premier vrai Grand Prix** (chercher « qualifications annoncées par Unibet » ou
> « aucune épreuve de qualification trouvée »).

*Constat de terrain, août 2026 (J-7)* : le nœud racine **n'exposait aucun événement de
qualification** — un seul événement « Course », rien d'autre, vérifié aussi dans le bloc
SSR. **C'est donc le cas `"inconnue"` qui s'applique aujourd'hui**, et c'est exactement
pourquoi le repli faisait des dégâts : il ne se déclenchait pas à la marge, il était le
régime normal.

---

## 6. L'adoption d'une ligne posée à la main

Les onze Grands Prix de la fin de saison sont en base **avant** qu'Unibet n'ouvre leur
page — c'est ce qui fait exister le calendrier, les fiches et les horaires toute l'année.
Leur `id_unibet` est donc **inventé** : `manuel-<slug>-2026` (migration 19).

> ### Le scraper reconnaît la ligne à son NOM, et lui fait porter le vrai identifiant
>
> `_adopter`, appelé en tête de `_enregistrer`, avant toute écriture. Il cherche une ligne
> dont l'`id_unibet` commence par `manuel-` et dont le nom donne le même `slug()` que celui
> d'Unibet — **insensible à la casse, aux accents et aux séparateurs**, parce que le
> bookmaker écrit « GP Pays Bas » une semaine et « GP Pays-Bas » la suivante. S'il en
> trouve une, un `update` lui donne le vrai `id_unibet`.
>
> **L'UUID ne bouge pas.** C'est tout l'intérêt : les pronostics, les favoris et les
> résultats rattachés à cette ligne restent valides. L'upsert qui suit la retrouve par son
> identifiant tout neuf et y écrit `date_course`, `date_qualifications` et les cotes comme
> sur n'importe quelle autre ligne. Le job peut ensuite la figer, puisqu'il visait
> justement cet UUID.

**C'est le seul endroit du scraper qui rapproche par le nom**, et ce n'est pas un
relâchement de la règle : si les deux lignes avaient un identifiant commun, il n'y aurait
rien à adopter. Le nom est littéralement la seule chose qu'elles partagent. Le
rapprochement avec OpenF1 continue de se faire sur la **date** (§10), et celui du job sur le
`gp_id` (§8).

**Trois cas où l'adoption ne se fait pas**, chacun journalisé :

| Cas | Ce qui se passe |
|---|---|
| **Deux lignes manuelles de même nom** | Aucune adoption. Choisir la première venue attacherait les pronostics d'un Grand Prix à un autre — c'est la règle du rapprochement des pilotes (§11), appliquée ici. |
| **Le doublon est déjà constitué** — une ligne porte déjà le vrai `id_unibet` | Aucune fusion. Un `warning` écrit la commande `adopter_grand_prix` toute faite : seule la fonction SQL sait compter les quatre tables filles avant de supprimer quoi que ce soit. |
| **Zéro ligne touchée par l'`update`** | Quelqu'un a adopté entre la lecture et l'écriture. Le filtre porte sur le placeholder autant que sur l'identifiant — même précaution que le `PATCH` de figeage (§8). |

> **Le statut de la ligne adoptée est lu comme celui de n'importe quelle autre** : une
> ligne figée à la main garde ses cotes, l'adoption ne rouvre rien.

**`adopter_grand_prix` (migration 19) reste la voie des deux cas refusés**, et elle seule
sait résorber un doublon déjà formé. Ce qu'elle n'est plus, c'est un rendez-vous
hebdomadaire — le geste se faisait le vendredi ou le samedi matin, douze fois dans la
saison, dans une fenêtre de quelques heures. Voir `bugs-connus.md` §31.

**La convention `manuel-` est connue de deux endroits** : `PREFIXE_MANUEL` dans
`unibet.py`, et la fonction SQL. Ils doivent bouger ensemble.

---

## 7. Idempotence et robustesse

### L'upsert

`upserter()` fait un `insert … on conflict … do update` via PostgREST, sur
`(gp_id, id_outcome_unibet)`.

> Un `insert` nu échouerait au deuxième passage ; un `delete` puis `insert` laisserait le
> GP **sans aucune cote** pendant un instant, et définitivement si l'insertion échouait.

### Un GP figé n'est jamais réécrit

Avant d'écrire, le scraper lit le statut. `cotes_figees` ou `termine` → il enregistre le
GP et **s'arrête là**, en journalisant en `warning` combien de cotes il a ignorées, avec
le nom du GP et son statut. C'est **exactement ce qu'on vient chercher dans les logs**
quand on se demande pourquoi une cote n'a pas bougé.

> **Le statut n'est jamais transmis à l'upsert non plus** : le préciser remettrait à
> `a_venir` un GP figé à chaque passage.

> **Exception voulue : `date_course` et `date_qualifications` sont réécrites même pour un
> GP figé.** Ce sont des données de **programme**, pas des cotes. Les refuser priverait
> l'interface d'un horaire exact qu'Unibet vient d'annoncer — et c'est ce qui permet de
> corriger une date fausse d'un simple `?figer=false`.

### L'échec d'un GP n'emporte pas les autres

Chacun est traité pour lui-même ; celui qui échoue est journalisé, abandonné, et **rien
n'est écrit pour lui** — ses cotes déjà en base restent intactes.

**Une issue illisible est ignorée** sans emporter son marché ; **un marché entier
illisible fait échouer le GP** plutôt que d'enregistrer des cotes fausses.

Le compte rendu porte `gp_id` et `id_unibet` — c'est par `gp_id` que le job retrouve le GP
qu'il voulait figer. Se fier au nom ne tiendrait pas.

### Un marché non évaluable n'est pas enregistré (v`0.77.0`)

`unibet.filtrer_evaluables` écarte, avant l'écriture, toute cote dont le marché n'a pas
d'évaluateur. Le registre consulté est **celui du calcul** (`calcul.points.evaluable`) :
une seule source répond à « sait-on juger ce marché ? », au scraping comme après la course.

> **Pourquoi au scraping.** Jusqu'ici, un joueur pouvait parier sur un marché qu'Unibet
> venait de renommer : l'écart ne se voyait qu'après la course, pronostic à `NULL`
> (`audit-evaluation.md`, cause C1). Un marché écarté n'est plus jamais proposé.

Les marchés écartés sont journalisés en `warning`, libellé et slug :
`[scraper] GP … : 2 marché(s) écarté(s), sans évaluateur (5 cote(s)) : Premier abandon
[premier-abandon] ; …`. **C'est dans ce log qu'on repère un marché nouveau** : son slug
exact s'ajoute au registre de `points.py` et à `SLUGS_EN_BASE` des tests.

> Le filtre n'efface rien : une cote déjà en base avant la `0.77.0` y reste. Les 39 slugs
> connus ont tous un évaluateur, le cas ne concerne donc que des cotes qui n'existent pas.

---

## 8. Le job de scraping

`backend/app/jobs/scraper.py`, `AsyncIOScheduler` démarré dans le `lifespan`.

| Réglage | Valeur | Pourquoi |
|---|---|---|
| Vérification | **1 h** | Le job attend une heure **connue à l'avance** et écrite en base. Une rafale n'apporterait rien. |
| Déclenchement | **qualifs + 2 h** | Règle métier. |
| Fenêtre | **4 h** | Railway se met en veille. Un déclenchement à l'heure pile serait manqué **définitivement** si le service dort — la fenêtre laisse quatre tours pour rattraper. |
| Premier tour | **+2 min** | Le job de résultats prend le sien à 30 s ; les espacer évite de lancer de front un scraping Unibet et une rafale OpenF1 après un redéploiement. |

### Le figeage ne suit qu'un scraping RÉUSSI

Vérifié sur **trois points** : le GP visé figure dans le compte rendu, il n'était pas déjà
figé, et **au moins une cote a été écrite**. À défaut, le statut reste `a_venir` et le
tour suivant réessaie.

> Figer après un échec arrêterait les cotes sur ce que la base contenait avant — au pire,
> sur rien du tout.

> **Le scraping n'est pas ciblé, et il ne peut pas l'être** : Unibet n'expose que le GP
> suivant et ne se laisse pas interroger par identifiant. On scrape donc ce qui est
> disponible, et **on ne fige que celui qu'on visait** — un autre GP rencontré au passage
> garde son statut, ses propres qualifications n'ayant pas eu lieu.

**Deux points de mise en œuvre :**

1. **Le `PATCH` de figeage filtre sur le statut autant que sur l'identifiant**
   (`id=eq.… & statut=eq.a_venir`). Sans ce second filtre, un scraping tardif ramènerait
   à `cotes_figees` un GP que le job de résultats vient de passer à `termine`, et **le
   remettrait dans la boucle de surveillance**. Zéro ligne touchée n'est pas une panne :
   c'est l'état voulu, atteint par quelqu'un d'autre.
2. **Passé la fenêtre, aucune alerte répétée** — contrairement au job de résultats. Le GP
   resterait candidat jusqu'à ce qu'il passe à `termine`, et une erreur par heure noierait
   les logs. Le silence est rattrapable manuellement.

### Le rattachement des issues, juste après le figeage (v`0.79.0`)

Le figeage ouvre les pronostics : c'est le moment où un libellé Unibet inconnu doit se
voir. Dès que `figer` a réussi — job horaire **ou** déclenchement manuel —,
`rattachement.rattacher_sans_echec` :

1. lit les **engagés** du GP chez OpenF1 : `/drivers` de la session de qualification
   (`session_name = "Qualifying"`) la plus proche de `date_qualifications` (à défaut de
   `date_course`), refusée au-delà de 36 h (`openf1.engages`) ;
2. rattache chaque issue pilote ou écurie à un engagé (`points.correspondance`, **la même
   règle de rapprochement que le calcul**, alias de `pilotes.py` compris) ;
3. écrit `numero_pilote` / `ecurie_id` sur les cotes et remplace les alertes de libellé
   du GP, en une transaction (`rattacher_issues`, migration 26).

Ce qui ne désigne aucun engagé est journalisé
(`[rattachement] GP … : 1 issue(s) ne désignent aucun engagé : « X.Truc » [vainqueur]`) et
remonte au profil admin avec le GP et le libellé exact. **Rien de tout cela ne bloque le
figeage**, qui a déjà eu lieu : un échec d'OpenF1 laisse les cotes sans identifiant, crée
une alerte `rattachement_impossible`, et le calcul retombe sur les libellés.

Quelles issues sont rattachées — la **nature** de chaque marché — est déclarée à côté du
registre des évaluateurs (`points._NATURES_EXACTES`, `_NATURES_FAMILLES`) ; un test exige
qu'un slug exact du registre y figure.

---

## 9. Le déclenchement manuel

```
POST /scraper/declencher     en-tête X-Admin-Secret     202, asynchrone
```

**Il fige aussi** : un même scraping doit avoir le même effet, qu'il vienne d'une horloge
ou d'un `curl`.

> **Conséquence à connaître** : la route rend `202` **avant** que le scraping ne commence.
> Le refus d'un GP déjà figé **ne peut donc pas être dans la réponse** — il est dans les
> logs, explicite, avec le nom du GP et son statut.

### `?figer=false` — la porte de sortie

```bash
# Essai AVANT les qualifications — n'arrête PAS les cotes
curl -X POST "https://<railway>/scraper/declencher?figer=false" -H "X-Admin-Secret: <valeur>"
```

> **Sans lui, le premier `curl` de la saison — passé un mardi, pour vérifier que le
> scraper écrit bien — figerait des cotes de mardi, sur une grille non définitive**, et
> il faudrait un `update` à la main pour les débloquer. **C'est exactement ce qui est
> arrivé au GP des Pays-Bas** (voir `bugs-connus.md` et `roadmap.md`).
>
> Le défaut reste `true` ; la porte de sortie est explicite. La réponse porte `figera`.

**Trois points de sécurité, à ne pas défaire :**

1. `secrets.compare_digest`, **à temps constant**. Un `==` s'arrête au premier caractère
   qui diffère, et le temps de réponse laisse deviner le secret caractère par caractère.
2. **`ADMIN_SECRET` non défini FERME la route** (`503`). Le défaut d'une variable absente
   ne doit jamais être l'accès libre.
3. Les tâches lancées sont gardées dans un `set` le temps de leur exécution. **Sans
   référence forte, asyncio est en droit de ramasser une tâche en cours**, et le scraping
   s'arrêterait au milieu sans un mot.

Le secret est vérifié **avant** la configuration Supabase : répondre « Supabase n'est pas
configuré » à qui n'a pas le bon secret lui apprendrait quelque chose pour rien.

---

## 10. Les résultats — OpenF1

`https://api.openf1.org/v1/` — gratuite, sans clé.

| Endpoint | Usage |
|---|---|
| `/session_result` | résultats officiels — source principale |
| `/race_control` | safety car, drapeau rouge |
| `/laps` | meilleur tour |
| `/drivers` | pilote → écurie ; celui de la **qualification** donne les engagés au figeage (§8) |
| `/starting_grid` | grille de départ (conservée, non lue) |
| `/sessions` + `/session_result` de « Qualifying » | pole position — `donnees_brutes.qualification` |

> ### Les qualifications (v`0.77.0`)
> La pole se lit dans le **classement des qualifications**, pas dans `/starting_grid`
> (vide à Bakou) : la session est retrouvée par `meeting_key` et `session_name =
> "Qualifying"` — le nom, parce que `session_type = Qualifying` couvre aussi la
> qualification du sprint. Son `session_result` est conservé tel quel dans
> `donnees_brutes.qualification`.
>
> **Son échec n'emporte jamais la récupération** : seul le marché « triplé » en dépend,
> et il reste en attente. `completer_qualification` la retente à chaque passage de
> `traiter` sur un GP dont les données brutes ne l'ont pas — c'est ce qui la fait
> arriver sur les GP récupérés avant la `0.77.0`, Bakou compris.

### Trois écarts avec le cahier des charges

**1. On interroge par `session_key`, JAMAIS par `meeting_key`.** Un *meeting* est un
week-end entier : `?meeting_key=1264` rend les cinq sessions mélangées, donc plusieurs
lignes par pilote et un classement qui n'a aucun sens. Pire, la ligne de qualification
porte un `gap_to_leader` de type **liste** (`[0.0, 0.0, 0.0]`) — **un quatrième type non
documenté**, qui disparaît dès qu'on filtre sur la course.

**2. `dnf: true` n'implique PAS `position: null`.** Au GP des Pays-Bas 2025, **Norris
abandonne au 64ᵉ des 72 tours et finit 18ᵉ** : `dnf: true` **et** `position: 18`. Les deux
champs sont donc lus indépendamment — un « top 10 » se juge sur la position, un
« abandon » sur `dnf`, et l'un n'annule jamais l'autre.

**3. OpenF1 limite à 3 requêtes/seconde** et répond `429` au-delà. Une récupération en
enchaîne six : `_appeler` espace les appels de 0,4 s et réessaie avec attente croissante.

### Autres pièges de parsing

- **`gap_to_leader` est de type mixte** : nombre pour les pilotes dans le tour, **chaîne**
  (`"+1 LAP"`) pour les doublés, `null` pour le leader — et **chaîne numérique**
  (`"+11.536"`) selon les courses, soit quatre formes avec la liste des qualifications.
  `points._secondes()` les absorbe toutes, et **un pilote doublé vaut `math.inf`, jamais
  `None`** : son écart n'est pas illisible, il est plus grand que n'importe quel
  intervalle. Le champ est lu depuis la version `0.54.0` — il ne l'était **pas**, et c'est
  ce qui laissait « écart du gagnant » éternellement non jugé (`bugs-connus.md` §23).
- **`points`** contient les points FIA officiels (25, 18, 15…) — pratique pour détecter
  si un pilote a marqué, et réutilisable pour le vrai classement pilotes.
- **`country_code` de `/drivers` est déprécié** et disparaît fin 2026. Pour les marchés de
  nationalité, maintenir une table statique dans `app/calcul/pilotes.py`.

### Le rapprochement GP ↔ course se fait sur la DATE, jamais sur le nom

Unibet écrit « GP Pays Bas », OpenF1 « Dutch Grand Prix ». Aucune correspondance textuelle
ne tiendrait sur une saison, et une table codée en dur figerait le calendrier.

`session_de_course()` prend la session `Race` de l'année dont `date_start` est la plus
proche, et **refuse au-delà de 36 heures d'écart** : mieux vaut ne pas noter un GP que le
noter sur les résultats d'un autre.

### `ResultatsIndisponibles` n'est pas une panne

C'est l'état **normal** dans l'heure et demie qui suit un départ, et le signal que le job
attend pour réessayer.

> **Un classement dont AUCUNE ligne n'a de position est traité comme indisponible** —
> OpenF1 publie parfois les lignes avant de les remplir, et noter tout le monde perdant
> serait le pire moment pour se tromper.

---

## 11. Le calcul des points

`backend/app/calcul/points.py` travaille **uniquement sur le JSON conservé**, jamais sur
l'API. C'est ce qui permet de rejouer un calcul des semaines après la course.

### Le rapprochement des noms — le point le plus fragile

> **Depuis la `0.79.0`, l'identifiant passe avant le nom.** `rattacher_identifiants`
> enregistre dans la `Course` le `numero_pilote` et l'`ecurie_id` posés au figeage (§8) ;
> `pilote_du_libelle` et `equipe_du_libelle` les consultent d'abord. Un numéro absent des
> données de course, ou un identifiant d'écurie inconnu, rend la main au libellé — le
> verdict est alors celui d'avant. Un même libellé rattaché à deux identifiants différents
> n'est rattaché à aucun. Ce qui suit reste la règle du repli, **et celle du figeage**.

Isolé dans `Course.pilote_du_libelle`. Cinq clés sont indexées par pilote : nom complet,
nom de famille, acronyme, initiale + nom, prénom + nom.

> **Une clé revendiquée par DEUX pilotes est retirée de l'index**, jamais attribuée au
> premier venu. Deux pilotes de même nom de famille rendraient « Verstappen » ambigu, et
> le pronostic reste **non validé** au lieu d'être attribué au mauvais.

**`app/calcul/pilotes.py` complète les cinq clés par des alias**, et ce n'était pas prévu :
elles échouent sur deux pilotes, relevés sur les **vraies cotes en base** —
**`AK.Antonelli`** (OpenF1 abrège « Kimi », Unibet garde les deux initiales ; c'était le
favori du GP à 28 pts, tous ses pronostics seraient restés à `NULL`) et **`C.Sainz Jr`**.

> ### Le garde-fou de saison
> `alias_unibet()` exige le **numéro ET le nom de famille**, et ne rend rien s'ils ne
> concordent pas. Les numéros sont réattribués d'une année sur l'autre : sans cette
> vérification, une table périmée collerait les alias d'Antonelli sur le nouveau titulaire
> du 12. Avec elle, **une table périmée ne fait aucun dégât** — elle ne rend rien, et le
> pronostic reste non validé, ce qui se voit dans les logs.
>
> **À mettre à jour à chaque saison.**

> **`pilotes.py` ne dit plus qui est engagé** (v`0.79.0`) : les engagés viennent de la
> qualification OpenF1 au figeage, de `/drivers` de la course au calcul. Le module sert
> encore aux **alias** (au figeage comme au calcul), aux **nationalités** et au **banc
> d'essai**. Sa grille suit les baquets de Bakou (Hadjar chez Red Bull, Lawson chez Racing
> Bulls, Tsunoda sans volant), mais une écurie périmée n'y fausse plus aucun verdict. Après
> une alerte « libellé non reconnu », l'alias s'ajoute ici, puis
> `POST /scraper/rattacher/{gp_id}`.

*Note :* `_cle()` duplique volontairement `points.normaliser` en deux lignes — `points`
importe ce module, l'importer en retour ferait un cycle.

**Écart assumé** : une table `driver_number → id_outcome_unibet` **ne peut pas exister** —
`id_outcome_unibet` change à chaque GP **et à chaque marché**. Ce qui est statique, c'est
`driver_number` → **libellé Unibet**.

### Le registre des évaluateurs (v`0.77.0`)

`validateur(slug, options)` cherche le marché dans un **registre** : slug exact
(`_EXACTS`), puis famille déclarée en `fullmatch` (`_FAMILLES`). **Aucune reconnaissance
par préfixe ni par sous-chaîne** — c'est elle qui laissait passer les marchés renommés
(C1) et jugeait trois marchés différents comme « écurie du vainqueur » parce que leur slug
commençait par `ecurie` ou `equipe` (C3).

| Slug | Évaluateur |
|---|---|
| `vainqueur`, `podium`, `ecurie-vainqueur` | position 1, position ≤ 3, écurie du P1 |
| `ecart-du-gagnant`, `marge-du-vainqueur` | intervalle sur l'écart du P2 |
| `nationalite-du-vainqueur` | table statique, « Autres » contre les issues sœurs |
| `ecurie-qui-marque-le-plus-de-points`, `equipe-…` | somme des points FIA, **partage** en cas d'égalité |
| `tour-le-plus-rapide`, `tour-le-plus-rapide-vainqueur` | pilote du meilleur tour |
| `ecurie-realisant-le-tour-le-plus-rapide` | écurie du meilleur tour |
| `voiture-realisant-le-tour-le-plus-rapide` | pilote **ou** écurie du meilleur tour |
| `vainqueur-course-qualification-et-tour-le-plus-rapide` | oui/non : pole + victoire + meilleur tour |
| `les-2-voitures-sur-le-podium` | l'écurie désignée a ses deux voitures dans le top 3 |
| famille `top-N` | position ≤ N |
| famille `{écurie}-les-2-voitures-dans-le-top-N` | oui/non |
| famille `face-a-face-{a}-{b}` | duel, adversaires lus dans les issues sœurs ; deux non-classés à tours égaux : **partage** (÷2, v`0.78.0`) |

**Un slug absent du registre n'est pas évaluable** : le scraper ne l'enregistre pas (§7),
et un pronostic qui le porterait passe `non_evaluable`. `NON_EVALUABLES` liste les marchés
connus **volontairement** non jugés (`premier-abandon`). `_safety_car`,
`_safety_car_virtuel`, `_drapeau_rouge` et `_abandon` existent sans slug : aucun marché de
ce genre n'a été vu chez Unibet. Leur slug exact s'ajoute le jour où le scraper en écarte un.

> **`tour-le-plus-rapide-vainqueur` et `voiture-…` n'ont aucune issue relevée en base.**
> Le premier est lu comme un marché de pilotes ; une issue « Oui »/« Non » n'y serait
> rapprochée de personne et resterait en attente — jamais un `0`.

Les règles de chaque marché sont dans `metier.md` §4.

**Le podium paie pilote par pilote** (v`0.54.0`) : chaque sélection est jugée pour son
propre compte, et le pronostic rapporte la somme des cotes gagnées — deux, une, ou zéro.
Une jambe non jugeable laisse le **pronostic entier** à `NULL`, jamais un total partiel que
l'idempotence de `attribuer_points` figerait pour toujours (`bugs-connus.md` §22).

**« Écart du gagnant » est le premier marché dont l'issue n'est ni un pilote ni un
oui/non**, mais un intervalle de secondes. Slugs `ecart-du-gagnant` et
`marge-du-vainqueur` (renommage Unibet). Il se juge sur le `gap_to_leader` **du deuxième**, avec des bornes
`[bas, haut[`. Formes d'issue reconnues : « moins de N », « - de N », « jusqu'à N »,
« N - M », « entre N et M », « plus de N », « + de N ». **Aucune n'a été confrontée à un
vrai libellé** : une issue non reconnue est journalisée et laisse `NULL`. Passer par
`POST /jobs/resultats/{gp_id}/test` avant le premier vrai Grand Prix.

**« Nationalité du vainqueur » est le seul marché dont la réponse n'est pas dans les
données de course** (v`0.55.0`). Elle vient de `calcul/pilotes.py`, parce que
`country_code` de `/drivers` est déprécié — le choix était déjà écrit en §10, il est
maintenant tenu. Slug `nationalite-du-vainqueur` ; le libellé accepte le peuple comme le pays (« Néerlandais », « Pays-Bas »), accents et casse
indifférents. Les deux inconnues — nationalité du vainqueur, forme du libellé — sont
journalisées **séparément** : c'est ce qui dira s'il faut mettre la grille à jour ou ajouter
une forme à `NATIONALITES`. Le garde-fou de saison est celui d'`alias_unibet` : numéro **et**
nom de famille.

**Son issue « Autres » est la seule du système qui ne se juge pas seule** (v`0.56.0`) :
c'est un complémentaire, pas une valeur. `validateur(marche, options)` reçoit donc les
libellés de **toutes** les issues du marché pour ce Grand Prix — tirés du dictionnaire de
cotes déjà chargé par `issues_du_marche`, sans lecture supplémentaire. « Autres » est réussi
si la nationalité du vainqueur n'est dans **aucune** option listée, raté si elle est dans
l'une, et **non jugé** si une option sœur est illisible et pouvait donc être la sienne.

« premier-abandon » est volontairement **non évaluable** (`NON_EVALUABLES`) tant que la
règle d'égalité n'est pas écrite : il demande de savoir *qui* a abandonné le premier, pas *si*.

### Les tests de non-régression

Le seul code du dépôt couvert par des tests (`backend/tests/`). Ils rejouent `calculer()` sur les quatre GP
2026 terminés (Pays-Bas, Italie, Espagne, Azerbaïdjan), sans base ni réseau.

```bash
cd backend
.venv/bin/pip install -r requirements-dev.txt   # une fois
.venv/bin/python -m pytest                      # toute la suite, moins d'une seconde
.venv/bin/python -m pytest tests/test_marches.py -k egalite   # un sous-ensemble
```

| Fichier | Vérifie |
|---|---|
| `tests/test_verdicts_gp.py` | un test par GP : `calculer()` rend les verdicts de la base ; les 2 pronos de Bakou (triplé 50, marge 0) |
| `tests/test_marches.py` | les 39 slugs vus en base ont un évaluateur ou une entrée dans `points.NON_EVALUABLES` ; l'égalité McLaren/Mercedes à 33 pts des Pays-Bas, payée à partage |
| `tests/test_evaluateurs.py` | registre (aucun préfixe), marchés de la `0.77.0`, filtrage au scraping, bonus sur la même issue du même marché, face-à-face à partage |
| `tests/test_provisoire_definitif.py` | Bakou provisoire (Bortoleto 13ᵉ) puis définitif (15ᵉ) sur une base simulée : le verdict déjà écrit bascule en un seul appel à `remplacer_verdicts` ; pas de définitif avant 24 h ; plus de recalcul automatique ensuite ; recalcul admin réservé aux GP définitifs ; échecs répétés du définitif comptés puis effacés au succès |
| `tests/test_direction_de_course.py` | safety car, VSC, drapeau rouge et meilleur tour sur les vrais messages `race_control` |
| `tests/test_identifiants.py` | rattachement au figeage sur les 4 GP (`AK.Antonelli`, `C.Sainz Jr`, `Franco Colapinto`, Hadjar/Lawson selon la session), libellé inventé non reconnu, mêmes verdicts par identifiant que par libellé, identifiant prioritaire, job de rattachement et son échec OpenF1 |
| `tests/test_alertes_admin.py` | `GET /admin/alertes` : GP et libellé servis, seuil des échecs du définitif, table absente |
| `tests/fixtures/gp/*.json` | `donnees_brutes`, cotes, pronostics et verdicts attendus ; provenance dans la clé `source` |

> **Un défaut connu se marque `xfail`**, avec la cause de `audit-evaluation.md` §4.3 en
> raison. Ceux de C1, C3 et C6 ont été retirés en `0.77.0`. `pytest.ini` règle `xfail_strict = true` : un test `xfail` qui
> se met à passer **fait échouer la suite**. Corriger un défaut, c'est donc aussi retirer
> son marqueur — sinon la CI le signale.

**Un slug nouveau vu chez Unibet s'ajoute à `SLUGS_EN_BASE`** (`test_marches.py`). Le
test échoue tant que le marché n'a ni évaluateur ni entrée « non évaluable ».

**Les fixtures ne se régénèrent pas** : elles figent les verdicts corrigés à la main au
2026-09-26. Les identifiants `fixture-NNN` des cotes sont inventés (second pilote d'un
podium, issues sœurs) ; les issues pronostiquées gardent leurs identifiants réels. Les
qualifications de Bakou (`donnees_brutes.qualification`, session 11373) ont été relevées
pour l'audit ; en production, le job les ajoute au prochain passage sur ce GP.

---

## 12. Le job de résultats

Deux boucles depuis la `0.78.0` : le **provisoire** à l'arrivée, le **définitif** à J+1.

| Réglage | Provisoire (`surveiller`) | Définitif (`consolider_echus`) |
|---|---|---|
| Intervalle | 5 min | 15 min |
| Déclenchement | départ + 1h30 | **départ + 24 h** |
| Fenêtre | 3 h | aucune : réessaie jusqu'au succès |
| GP concernés | `statut` `a_venir` **et** `cotes_figees` | `statut_resultats = provisoire` |
| Écriture | `attribuer_points` (les `NULL` seuls) | `remplacer_verdicts` (tout le GP, une transaction) |
| Statut posé | `termine` + `provisoire` | `termine` + `definitif` |
| Premier tour après démarrage | 30 s | **15 s — le rattrapage** |

> ### Le définitif, et son rattrapage au démarrage
> 24 h après `date_course`, `consolider` relit **tout** chez OpenF1 — classement,
> `/drivers`, `race_control`, tours, grille, qualifications (celles déjà conservées font
> foi si OpenF1 ne les rend plus) —, puis rejuge **chaque** pronostic du GP, y compris
> ceux déjà jugés, et `remplacer_verdicts` écrit le tout d'un bloc. C'est ce qui rattrape
> les pénalités posées après l'arrivée (Bakou 2026 : Bortoleto 13ᵉ puis 15ᵉ,
> `audit-evaluation.md` C5) et les données arrivées en retard (R3).
>
> Le premier tour de cette boucle part **15 s après le démarrage du backend** : un GP
> resté provisoire pendant une veille ou un redéploiement de Railway reçoit son calcul
> définitif dès le retour du service. Un échec (OpenF1 indisponible) laisse le GP
> provisoire, ses points comptés, et le tour suivant réessaie.
>
> **Un GP `definitif` n'est plus jamais recalculé automatiquement.**
>
> **Ses échecs sont comptés** (v`0.79.0`, `roadmap.md` §3.17). Chaque échec —
> `ResultatsIndisponibles` compris, anormal à J+1 — incrémente `alertes_admin.tentatives`
> (`noter_echec_definitif`). À partir de `SEUIL_ALERTE_DEFINITIF` (3) échecs consécutifs,
> un `ALERTE` est journalisé et le GP apparaît dans le profil admin, tentatives et dernière
> erreur. La boucle continue de réessayer ; un succès efface l'alerte.

> **La fenêtre du provisoire est calculée depuis `date_course`, SANS état conservé nulle part.** Un
> compteur de tentatives en base dirait la même chose au prix d'une colonne et d'une
> écriture par essai, et se désynchroniserait au premier redéploiement.

> **`a_venir` est surveillé délibérément** : le figeage peut être manqué (service endormi
> pendant les quatre heures de fenêtre), et une course dont le départ est passé de 1h30
> est terminée, que ses cotes aient été figées ou non. **C'est le filet de sécurité.**

Au-delà de la fenêtre, une alerte nommant le GP et donnant la commande de rattrapage est
journalisée **une seule fois** (garde-fou en mémoire).

**Le GP passe à `termine` même s'il reste des pronostics à `NULL`** : la course est
courue, et le laisser dans la boucle ferait rappeler OpenF1 toutes les cinq minutes pour
rien. Le définitif, à J+1, rejugera de toute façon chaque pronostic.

> ### Le statut écrit par le job (v`0.77.0`, migration 24)
> `attribuer_points` reçoit, pour chaque pronostic sans points, soit ses points (le
> statut `gagne` / `perdu` en est **dérivé** par trigger), soit un statut :
> `non_evaluable` (aucun évaluateur) ou `en_attente` (donnée manquante). Le rapport de
> `POST /jobs/resultats/{gp_id}` liste `en_attente` et `non_evaluables` séparément.
> Détail dans `database.md`.

### Trois étages d'idempotence (provisoire)

1. **Récupération** — `resultats_gp.gp_id` est `unique`. Une ligne existante ⇒ OpenF1
   n'est pas rappelée, le calcul est rejoué sur le JSON conservé. **Seule exception : les
   qualifications**, ajoutées si elles manquent (§10) ; le reste est réécrit à l'identique.
2. **Attribution** — `attribuer_points` n'écrit **que** les `points_gagnes` encore `NULL`.
   **C'est la base qui porte la garantie, pas le code appelant.**
3. **Surveillance** — un GP passé à `termine` sort du champ de la boucle.

Le définitif est idempotent autrement : un calcul **pur** des données, des cotes et des
pronostics, et une écriture qui **remplace** — rejouée, elle écrit le même état. Un GP
`definitif` sort de sa boucle.

---

## 13. Les routes de rattrapage

```bash
# Calcul PROVISOIRE d'un GP, à la demande : résultats, points, clôture. SYNCHRONE.
curl -X POST https://<railway>/jobs/resultats/<gp_id> -H "X-Admin-Secret: <valeur>"
```

Synchrone, contrairement au scraper : c'est la route des interventions manuelles, et
savoir combien de pronostics ont été notés — **surtout lesquels sont restés en attente** —
est tout l'intérêt de l'appel. Elle ignore la fenêtre horaire, **jamais l'idempotence**.
`425 Too Early` si les résultats ne sont pas publiés, **`409` sur un GP définitif**. Même
chemin pour l'action « resultats » de `POST /admin/action`.

```bash
# RECALCUL d'un GP DÉFINITIF : rejuge TOUS ses pronostics, une transaction.
curl -X POST "https://<railway>/jobs/resultats/<gp_id>/recalcul" -H "X-Admin-Secret: <valeur>"
# … en relisant OpenF1 (décision tardive des commissaires) :
curl -X POST "https://<railway>/jobs/resultats/<gp_id>/recalcul?relire=true" -H "X-Admin-Secret: <valeur>"
```

> ### `/recalcul` — la seule route qui réécrit un verdict définitif (v`0.78.0`)
>
> Elle **remplace `?forcer=true`**, supprimé. `forcer` rendait les points à `NULL` puis
> les réécrivait en **deux appels** : entre les deux, tout le GP s'affichait « en
> attente », et un échec au milieu l'y laissait (risque R5 de l'audit). `/recalcul` passe
> par `remplacer_verdicts`, la même écriture que le définitif : résultats, verdicts,
> podiums et statut changent d'un bloc, ou pas du tout.
>
> Par défaut **OpenF1 n'est pas rappelée** (`relire=false`) : le calcul rejoue le JSON
> conservé — le cas d'un évaluateur corrigé après coup. `relire=true` relit OpenF1 et
> remplace `resultats_gp`. La réponse porte `modifies`, le nombre de verdicts changés.
>
> **`409` sur un GP qui n'est pas encore définitif** : sa boucle s'en charge, et le rendre
> définitif avant l'heure le priverait de la relecture de J+1. Le scheduler ne l'emprunte
> jamais. `POST /admin/action` ne l'expose pas : un champ `forcer` qu'un vieux client
> enverrait encore est ignoré.

```bash
# RATTACHEMENT des issues aux engagés, rejoué à la main. SYNCHRONE.
curl -X POST https://<railway>/scraper/rattacher/<gp_id> -H "X-Admin-Secret: <valeur>"
```

> Le job le fait seul après le figeage (§8). La route sert après un alias ajouté à
> `pilotes.py`, ou quand OpenF1 était muette ce jour-là. Elle remplace les identifiants et
> les alertes de libellé du GP ; `502` si OpenF1 ne répond pas. La réponse liste les
> issues non reconnues.

```bash
# BANC D'ESSAI — n'écrit RIEN. À utiliser AVANT la course.
curl -X POST https://<railway>/jobs/resultats/<gp_id>/test \
  -H "X-Admin-Secret: <valeur>" -H "Content-Type: application/json" \
  -d '[{"driver_number":12,"position":1,"dnf":false,"dns":false,
        "dsq":false,"points":25,"number_of_laps":72,"gap_to_leader":0}]'
```

> ### Les trois écritures absentes du banc d'essai sont chacune un dégât évité
>
> | Écriture du vrai job | Ce qu'elle aurait cassé |
> |---|---|
> | `resultats_gp` | `gp_id` est `unique` : un classement fictif **empêcherait définitivement** la vraie récupération le jour de la course |
> | statut → `termine` | le GP sortirait de la surveillance et ne serait **jamais** noté |
> | `points_gagnes` | `attribuer_points` n'écrit que les `NULL` : un essai les remplirait de valeurs inventées **que le vrai job ne corrigerait plus jamais** |
>
> C'est ce qui le rend reproductible. Le champ `points_en_base` de la réponse le prouve —
> il ne bouge pas.

**Tous** les pronostics sont évalués, y compris ceux qui ont déjà des points : le filtre
`points_gagnes is null` du vrai job est un mécanisme d'idempotence, pas une règle de
calcul — ici il masquerait précisément les lignes qu'on veut vérifier.

Le jugement n'est pas réécrit : la route appelle `calcul.points_du_pronostic`, **la
fonction même sur laquelle le job boucle**.

Le corps accepte le tableau nu de `session_result`, **ou** un objet portant en plus
`race_control` et `laps` — safety car, drapeau rouge et meilleur tour sont précisément les
marchés qu'aucun vrai libellé Unibet n'a jamais confrontés. Les lignes acceptent les
champs supplémentaires (`extra="allow"`) : une réponse OpenF1 réelle se colle telle quelle.

La réponse porte aussi un résumé `course` disant ce que le calcul a **compris** des
données fictives — sans lui, un safety car mal orthographié donnerait des pronostics ratés
sans qu'on sache si c'est le pronostic ou la donnée d'essai qui est en cause.
