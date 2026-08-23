# Scraper Unibet et résultats OpenF1

Comment les données entrent dans la base, et pourquoi c'est écrit ainsi.

Fichiers : `backend/app/scraper/unibet.py`, `openf1.py`, `backend/app/jobs/scraper.py`,
`jobs/resultats.py`, `backend/app/calcul/points.py`, `pilotes.py`.

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

**Repli : `date_course − 22h`**, journalisé en `warning` à chaque fois. 22 h place les
qualifications le samedi après-midi pour une course le dimanche après-midi ; le scraping
tombe alors le samedi en fin de journée.

> **Les logs disent toujours lequel des deux cas s'applique** — c'est ce qui empêche le
> repli de devenir le régime normal sans que personne ne s'en aperçoive. **À relire dans
> les logs le samedi du premier vrai Grand Prix** (chercher « qualifications annoncées par
> Unibet » ou « aucune épreuve de qualification trouvée »).

*Constat de terrain, août 2026 (J-7)* : le nœud racine **n'exposait aucun événement de
qualification** — un seul événement « Course », rien d'autre, vérifié aussi dans le bloc
SSR. **C'est donc le repli qui s'applique aujourd'hui.**

---

## 6. Idempotence et robustesse

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

---

## 7. Le job de scraping

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

---

## 8. Le déclenchement manuel

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

## 9. Les résultats — OpenF1

`https://api.openf1.org/v1/` — gratuite, sans clé.

| Endpoint | Usage |
|---|---|
| `/session_result` | résultats officiels — source principale |
| `/race_control` | safety car, drapeau rouge |
| `/laps` | meilleur tour |
| `/drivers` | pilote → écurie |
| `/starting_grid` | pole position |

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

## 10. Le calcul des points

`backend/app/calcul/points.py` travaille **uniquement sur le JSON conservé**, jamais sur
l'API. C'est ce qui permet de rejouer un calcul des semaines après la course.

### Le rapprochement des noms — le point le plus fragile

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

*Note :* `_cle()` duplique volontairement `points.normaliser` en deux lignes — `points`
importe ce module, l'importer en retour ferait un cycle.

**Écart assumé** : une table `driver_number → id_outcome_unibet` **ne peut pas exister** —
`id_outcome_unibet` change à chaque GP **et à chaque marché**. Ce qui est statique, c'est
`driver_number` → **libellé Unibet**.

### Marchés reconnus

vainqueur, podium, top N (rang lu dans le nom), écurie gagnante, abandon, safety car,
safety car virtuel, drapeau rouge, meilleur tour, **écart du gagnant**,
**nationalité du vainqueur**.

> **Seuls « vainqueur », « podium » et « ecurie-vainqueur » ont été observés en vrai.**
> Les autres sont écrits d'après le cahier des charges et **restent à confronter**.
> C'est exactement pour cela qu'un marché non reconnu laisse `NULL`.

**Le podium paie pilote par pilote** (v`0.54.0`) : chaque sélection est jugée pour son
propre compte, et le pronostic rapporte la somme des cotes gagnées — deux, une, ou zéro.
Une jambe non jugeable laisse le **pronostic entier** à `NULL`, jamais un total partiel que
l'idempotence de `attribuer_points` figerait pour toujours (`bugs-connus.md` §22).

**« Écart du gagnant » est le premier marché dont l'issue n'est ni un pilote ni un
oui/non**, mais un intervalle de secondes. Slug reconnu sur « ecart », ou sur « marge » +
« victoire ». Il se juge sur le `gap_to_leader` **du deuxième**, avec des bornes
`[bas, haut[`. Formes d'issue reconnues : « moins de N », « - de N », « jusqu'à N »,
« N - M », « entre N et M », « plus de N », « + de N ». **Aucune n'a été confrontée à un
vrai libellé** : une issue non reconnue est journalisée et laisse `NULL`. Passer par
`POST /jobs/resultats/{gp_id}/test` avant le premier vrai Grand Prix.

**« Nationalité du vainqueur » est le seul marché dont la réponse n'est pas dans les
données de course** (v`0.55.0`). Elle vient de `calcul/pilotes.py`, parce que
`country_code` de `/drivers` est déprécié — le choix était déjà écrit en §9, il est
maintenant tenu. Slug reconnu sur « nationalite », ou sur « pays » + « vainqueur/gagnant » ;
le libellé accepte le peuple comme le pays (« Néerlandais », « Pays-Bas »), accents et casse
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

« premier-abandon » est volontairement **non reconnu** tant que la règle d'égalité n'est
pas écrite : il demande de savoir *qui* a abandonné le premier, pas *si*.

---

## 11. Le job de résultats

| Réglage | Valeur |
|---|---|
| Intervalle | 5 min |
| Déclenchement | départ + 1h30 |
| Fenêtre | 3 h |
| Statuts surveillés | `a_venir` **et** `cotes_figees` |

> **La fenêtre est calculée depuis `date_course`, SANS état conservé nulle part.** Un
> compteur de tentatives en base dirait la même chose au prix d'une colonne et d'une
> écriture par essai, et se désynchroniserait au premier redéploiement.

> **`a_venir` est surveillé délibérément** : le figeage peut être manqué (service endormi
> pendant les quatre heures de fenêtre), et une course dont le départ est passé de 1h30
> est terminée, que ses cotes aient été figées ou non. **C'est le filet de sécurité.**

Au-delà de la fenêtre, une alerte nommant le GP et donnant la commande de rattrapage est
journalisée **une seule fois** (garde-fou en mémoire).

**Le GP passe à `termine` même s'il reste des pronostics à `NULL`** : la course est
courue, et le laisser dans la boucle ferait rappeler OpenF1 toutes les cinq minutes pour
rien. Les `NULL` se rattrapent par un déclenchement manuel.

### Trois étages d'idempotence

1. **Récupération** — `resultats_gp.gp_id` est `unique`. Une ligne existante ⇒ OpenF1
   n'est pas rappelée, le calcul est rejoué sur le JSON conservé.
2. **Attribution** — `attribuer_points` n'écrit **que** les `points_gagnes` encore `NULL`.
   **C'est la base qui porte la garantie, pas le code appelant.**
3. **Surveillance** — un GP passé à `termine` sort du champ de la boucle.

---

## 12. Les routes de rattrapage

```bash
# Force le traitement d'un GP : résultats, points, clôture. SYNCHRONE.
curl -X POST https://<railway>/jobs/resultats/<gp_id> -H "X-Admin-Secret: <valeur>"
```

Synchrone, contrairement au scraper : c'est la route des interventions manuelles, et
savoir combien de pronostics ont été notés — **surtout lesquels sont restés en attente** —
est tout l'intérêt de l'appel. Elle ignore la fenêtre horaire, **jamais l'idempotence**.
`425 Too Early` si les résultats ne sont pas publiés.

```bash
# RECALCUL FORCÉ : efface les points du GP, puis les recalcule. SANS rappeler OpenF1.
curl -X POST "https://<railway>/jobs/resultats/<gp_id>?forcer=true" -H "X-Admin-Secret: <valeur>"
```

> ### `?forcer=true` — la seule écriture qui défait un point acquis
>
> L'idempotence protège un GP d'être noté deux fois. **C'est aussi ce qui fige un verdict
> faux** : `attribuer_points` ne réécrit que les `NULL`, donc un validateur corrigé après
> le passage du job rattrape ce qu'il n'avait pas su juger, et jamais ce qu'il avait mal
> jugé. Rien d'autre ne débloque un `0`.
>
> **Les points sont rendus à `NULL`, jamais à `0`.** `0` veut dire « raté » : une remise à
> zéro gèlerait pour de bon exactement ce qu'on veut recalculer. `pronostic_podium` suit son
> parent, sans quoi les deux colonnes divergeraient sur un podium resté non jugé.
>
> **OpenF1 n'est pas rappelée** : `resultats_gp` n'est pas touché, le calcul rejoue le JSON
> conservé — ce à quoi sert `donnees_brutes`. La réponse porte `reinitialises`.
>
> Défaut `false`, comme `?figer=false` au scraper : la porte de sortie est toujours
> explicite. **Le scheduler ne l'emprunte jamais.** Voir `bugs-connus.md` §24.

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
