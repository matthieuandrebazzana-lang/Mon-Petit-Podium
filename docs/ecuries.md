# Écuries, pilotes et voitures

Les onze écuries de 2026, leurs pilotes, leurs couleurs, et les planches SVG.

---

## 1. Une source unique de couleurs, trois tables dérivées

`frontend/src/lib/ecuries.js` portait autrefois **trois tables parallèles** — pilotes,
écuries, alias — chacune répétant les hexadécimaux. C'est ce qui avait laissé passer huit
pilotes rangés dans la mauvaise écurie, et deux écuries portant deux teintes différentes
selon le libellé qui les désignait.

```
ECURIES  ──┬──►  COULEURS_ECURIES        (pilote  → couleur)
   ▲       ├──►  COULEURS_NOMS_ECURIES   (écurie  → couleur)
   │       └──►  ALIAS                   (formes longues)
GRILLE ────┘
```

**`ECURIES` porte les onze couleurs, écrites une seule fois. Tout le reste en dérive** —
les tables ne peuvent plus se contredire.

> **Les deux tables restent exportées SÉPARÉMENT** : le marché « Vainqueur » nomme des
> pilotes, le marché « Ecurie Vainqueur » nomme des écuries. Les fondre obligerait à
> deviner lequel on regarde.

`couleurEcurie(libelle)` cherche dans les deux, applique les alias, et **rend `null` pour
tout ce qu'elle ne connaît pas** — jamais une couleur de repli. Inventer une teinte pour
un pilote inconnu ferait croire à une écurie qui n'existe pas. Les issues des marchés
spéciaux (« Safety Car ») tombent naturellement dans ce cas.

---

## 2. Les onze écuries et leurs teintes

| Écurie | Hex | Slug de livrée |
|---|---|---|
| Ferrari | `#FF2800` | `ferrari` |
| McLaren | `#FF8000` | `mclaren` |
| Mercedes | `#00D2BE` | `mercedes` |
| Aston Martin | `#006F44` | `aston-martin` |
| Red Bull | `#1E3A8A` | `red-bull` |
| Williams | `#37BEDD` | `williams` |
| Alpine | `#0090FF` | `alpine` |
| Haas | `#212121` | `haas` |
| Racing Bulls | `#6CBBEE` | `racing-bulls` |
| Audi | `#FF4D4D` | `audi` |
| Cadillac | `#9CA3AF` | `cadillac` |

> **La clé canonique d'Audi est « Audi », pas « Audi F1 Team »** — c'est la forme qu'écrit
> `backend/app/calcul/pilotes.py`, donc celle que le marché « Ecurie Vainqueur » doit
> retrouver des deux côtés. « Audi F1 Team » est servie par les alias et rend **exactement
> la même teinte**.

### Périmètre — ces couleurs ne peignent que deux choses

**Le fond d'un widget de cote (9,4 %) et son liseré (60 %).** Jamais un fond d'écran,
jamais un texte, jamais une bordure de bloc. Même périmètre que `lib/palette.js`,
`lib/couleurs.js` et `DrapeauxGP.jsx`.

> **La teinte est un DÉGRADÉ PLAT, pas une couleur de fond.** Un `background-color`
> semi-transparent posé en ligne **remplacerait** le blanc de `bg-surface` et laisserait
> passer le beige de la page : le widget cesserait d'être une carte blanche et **tous les
> contrastes mesurés changeraient**. Un `linear-gradient` se pose **par-dessus** le blanc.

### Contrastes mesurés

| Élément | Pire cas | Écurie |
|---|---|---|
| Nom du pilote `#1A1A1A` | **14,48:1** | Haas |
| Points `#800111` | **9,05:1** | Haas |
| Étoile au repos `secondaire/60` | **3,17:1** | Haas |

> **L'étoile est le point à vérifier à chaque changement de palette** : elle est le **seul**
> indicateur de l'état « pas en favori », donc soumise au plancher de 3:1 (WCAG 1.4.11).
> Le `texte-doux` du design system n'aurait donné que 2,85:1 — d'où `secondaire/60`.

### Collisions connues, et pourquoi elles sont tolérées

À 9,4 %, quatre écuries se regroupent dans les cyans et les bleus : Mercedes/Williams
(5 niveaux sur 255), Williams/Alpine (5), Williams/Racing Bulls (5), Mercedes/Alpine (6).
Le liseré à 60 % les écarte de 34 à 42 niveaux.

> **La teinte est un RENFORT, jamais le seul porteur de l'information** : le nom du pilote
> est écrit juste dessous.

> **Le liseré reste à 60 %, et c'est mesuré, pas subi.** Sur les livrées claires il est
> très discret (1,47:1 sur le turquoise Mercedes), et **aucune opacité n'y change rien** :
> à 100 % il ne monterait qu'à 1,78:1, la couleur étant intrinsèquement pâle, pendant que
> les livrées sombres passeraient de 3,24 à 8,78:1 (Red Bull) — c'est-à-dire se mettraient
> à crier.

---

## 3. La grille 2026 — pilote → écurie

| Écurie | Pilotes (libellés Unibet) |
|---|---|
| Mercedes | `AK.Antonelli` / `A.Antonelli`, `G.Russell` |
| Ferrari | `L.Hamilton`, `C.Leclerc` |
| Red Bull | `M.Verstappen`, `I.Hadjar` |
| McLaren | `L.Norris`, `O.Piastri` |
| Alpine | `F.Colapinto`, `P.Gasly` |
| Audi | `G.Bortoleto`, `N.Hulkenberg` |
| Racing Bulls | `A.Lindblad`, `L.Lawson` |
| Aston Martin | `F.Alonso`, `L.Stroll` |
| Haas | `E.Ocon`, `O.Bearman` |
| Williams | `A.Albon`, `C.Sainz Jr` |
| Cadillac | `S.Perez`, `V.Bottas` |

### Le désaccord frontend / backend — historique, RÉSOLU, et gardé par un test

> **Un désaccord a existé sur HUIT pilotes**, et l'enjeu n'était pas cosmétique : si
> `pilotes.py` avait eu tort, **le calcul des points du marché « Ecurie Vainqueur » aurait
> été faux**, ce qui est autrement plus grave qu'une couleur.
>
> **`pilotes.py` avait raison sur les vingt-deux.** C'est `ecuries.js` qui était faux, et
> il a été corrigé. **Aucun point n'a jamais été mal attribué.**

| Pilote | `ecuries.js` (faux) | Grille réelle = `pilotes.py` |
|---|---|---|
| AK.Antonelli | Cadillac | **Mercedes** |
| C.Sainz Jr | Ferrari | **Williams** |
| L.Hamilton | Mercedes | **Ferrari** |
| F.Colapinto | Williams | **Alpine** |
| N.Hulkenberg | Haas | **Audi** |
| E.Ocon | Alpine | **Haas** |
| S.Perez | Red Bull | **Cadillac** |
| I.Hadjar | Racing Bulls | **Red Bull** |

> ### Le garde-fou
> Un test **lit `backend/app/calcul/pilotes.py`** et compare les vingt-deux pilotes ligne à
> ligne. Les deux fichiers **ne peuvent plus diverger en silence**. Il est écrit en noms
> d'écuries et non en hexadécimaux : il survit donc à tout changement de palette.

**Les deux fichiers sont à mettre à jour chaque saison, ensemble.** Une table périmée ne
fait aucun dégât silencieux : un pilote absent ressort **sans teinte**, ce qui se voit à
l'écran, et `alias_unibet()` refuse de servir un alias dont le numéro ne concorde plus.

### Les alias

Ils couvrent ce que la normalisation ne peut pas déduire :

- **Les formes longues** — « Red Bull Racing », « Oracle Red Bull Racing », « Haas F1
  Team », « MoneyGram Haas », « Audi F1 Team », « Audi Sauber », « Alpine F1 Team »,
  « BWT Alpine », « Aston Martin Aramco », « Visa Cash App RB », « Cadillac F1 Team »,
  « Scuderia Ferrari », « Mercedes AMG », « Williams Racing ».
- **Les formes d'OpenF1** — ce sont elles qu'écrit `pilotes.py` (« Red Bull Racing »,
  « Haas F1 Team », « Audi »), et le marché « Ecurie Vainqueur » doit les retrouver des
  deux côtés.
- **`A.Antonelli`** à côté d'`AK.Antonelli`.

La clé est normalisée : minuscules, accents ramenés à la lettre de base, espaces fondus
(« S.Pérez » comme « S.Perez »).

> **La teinte suit le libellé AFFICHÉ, pas le libellé brut d'Unibet.** Le widget peint
> `formaterPilote(cote.pilote)` — donc « F.Colapinto » et non « Franco Colapinto », qui est
> ce qu'Unibet écrit et ce qu'on lit à l'écran.

---

## 4. `formaterPilote` — pourquoi une table, pas une règle

Unibet n'écrit pas tous ses pilotes de la même façon : la quasi-totalité arrive en
« initiale + nom », **Franco Colapinto arrive en nom complet**. Dans une liste il passait ;
dans un widget de 173 px de large, il fait deux fois la largeur de ses voisins et se fait
tronquer.

> **Ces écarts sont IRRÉDUCTIBLES par une règle.** Abréger automatiquement tout libellé à
> deux mots casserait le marché « Ecurie Vainqueur », où « Red Bull » et « Aston Martin »
> sont les bonnes réponses. **Les cas sont listés un par un, et tout ce qui n'est pas dans
> la table ressort intact.**

Même mécanisme que les `alias` de `pilotes.py`, et pour la même raison.

**Appliquée aux libellés venus des COTES, et à eux seuls** : tableau des cotes, saisie,
récapitulatif, pronostics de l'écran de résultats. **Les lignes du classement de course
viennent d'OpenF1 et gardent leur nom complet** — les normaliser donnerait
« F.Colapinto » au milieu de « Max VERSTAPPEN », c'est-à-dire l'incohérence qu'on corrige,
remise à l'envers.

`clePilote` est **exportée** : c'est la même clé qui sert à nommer un pilote et à le
reconnaître d'un marché à l'autre (exclusion croisée) — les deux ne peuvent pas diverger.

---

## 5. Les livrées de voiture

`frontend/src/lib/livrees.js` — onze slugs et leurs noms.
`frontend/src/composants/VoituresEcuries.jsx` — les onze dessins.

> **Deux modules, et la séparation compte.** `lib/livrees.js` porte les slugs, les noms et
> les teintes, **sans une ligne de SVG** ; le composant porte les formes, cinquante
> kilo-octets de chemins. `lib/palette.js` a besoin de la teinte pour la pastille du
> classement, et il est importé par `lib/couleurs.js`, donc par presque tous les écrans —
> y compris ceux qui n'affichent aucune voiture. **Faire remonter les formes jusque-là
> embarquerait le dessin des onze voitures dans le lot de chaque écran.**

**Les teintes sont lues dans `lib/ecuries.js`** — c'est la même question. La couleur
dominante du dessin ne ferait pas l'affaire : trois livrées sont à dominante blanche
(Racing Bulls, Haas, Cadillac) et deux à dominante grise (Mercedes, Audi), soit **cinq
pastilles indistinguables sur onze**.

### Les planches et leurs classes CSS

| Planche | Contenu | Classes colorisables |
|---|---|---|
| `voitures_perso.svg` | 4 voitures, une seule utilisée | **`cls-6`** (coque), **`cls-14`** (ailerons) |
| `voitures_ecuries.svg` | 9 livrées, en zigzag sur 2 colonnes | — (couleurs figées) |
| `VOITUREs_am.svg` | Alpine et Mercedes | — |
| `matti.svg` | 11 **pastilles carrées** | — |

> **`cls-2` n'existe pas dans la première voiture.** La planche empile quatre voitures,
> chacune peinte par **son propre couple de classes** (`cls-6`/`cls-14`, `cls-13`/`cls-10`,
> `cls-8`/`cls-3`, `cls-12`/`cls-2`). `cls-2` appartient à la **quatrième** : la brancher
> laisserait la couleur 2 sans porteur.

**Les couleurs sont posées en attribut `fill` sur chaque forme, jamais par classe** : un
`class="cls-6"` obligerait à injecter une feuille de style par voiture, et **deux voitures
de couleurs différentes ne pourraient pas coexister sur la vue piste**.

**Les onze livrées font exactement 141,11 × 288,09** — c'est le même dessin, onze fois
repeint. Elles se substituent sans qu'une valeur de la vue piste ne bouge.

**L'identification des écuries a été faite en RENDANT les onze voitures côte à côte**, pas
devinée d'après les couleurs du fichier. C'est ainsi qu'une inversion Cadillac ↔ Haas a
été trouvée : la voiture nommée `haas` portait le noir et blanc de Cadillac. **Les clés ont
été échangées, aucune coordonnée réécrite.**

### Les skins ne sont PAS des voitures

`assets/matti.svg` porte onze **pastilles carrées** (255,70 × 255,70) montrant le motif
d'une livrée : ni roues, ni ailerons, ni museau.

> **Elles servent UNIQUEMENT de vignettes dans le sélecteur du profil.** La voiture
> réellement dessinée reste celle de `VoituresEcuries.jsx`, et la raison n'est pas
> esthétique : **le pseudo peint sur l'aileron arrière est le seul moyen de distinguer
> deux membres sur la piste**, la légende n'y affichant plus que le score. Une pastille
> carrée n'a nulle part où l'écrire — l'écran signature deviendrait muet.

### Le mode est déduit du skin, jamais choisi à la main

`livree_ecurie = null` vaut « ma livrée ». **Les deux ne peuvent donc pas se contredire.**

**Les couleurs restent réglables quand un skin est actif** : elles ne peignent alors plus
rien, mais ce sont elles qu'on retrouve en le retirant, et la base les garde en colonnes
distinctes. La première case du sélecteur rend les couleurs du membre plutôt que
d'afficher « Aucun » — elle montre ce vers quoi on revient.

**Le numéro reste hors des deux modes** : il s'écrit sur le museau quelle que soit la
livrée.

---

## 6. `livreeDuMembre` — le seul arbitre

`lib/palette.js`. **Les quatre surfaces qui affichent une voiture y passent** : mon profil,
le profil d'un membre, la vue piste, le tableau des résultats.

> Sans lui, chaque écran relirait `livree_mode` à sa façon, et un membre pourrait
> apparaître en livrée Ferrari au classement et aux couleurs de son choix sur la piste.

**Un slug inconnu n'est pas une panne** : la voiture retombe sur le mode personnalisé, ce
qui **se voit à l'écran** au lieu de planter. Une ligne sans `livree_mode` (cache d'une
version antérieure, backend déployé avant la migration) retombe de même.

`couleurLisible` suit : **une livrée d'écurie rend la teinte de son écurie**, pas les
couleurs personnelles, qui ne peignent alors plus rien. C'est elle qui porte la pastille du
classement et le filet des lignes — **la même personne doit se reconnaître du même coup
d'œil au classement, sur la piste et sur son profil.**

---

## 7. Le numéro tête-bêche

Le numéro peint sur le museau est rendu **`rotate(180)`**, sur les onze livrées comme sur
la voiture personnalisable. C'est le calage de la planche d'origine, **uniforme**.

**À trancher** si le numéro doit se lire dans le sens de l'écran. Voir `roadmap.md`.
