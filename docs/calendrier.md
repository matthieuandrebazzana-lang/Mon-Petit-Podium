# Calendrier

La logique du calendrier et ses particularités.

> ## ⚠️ Ce document EXPLIQUE, il ne fait pas foi
>
> **`frontend/src/lib/calendrier2026.js` est la source de vérité utilisée par
> l'application.** Ce fichier-ci ne fait que le décrire.
>
> **Ne jamais modifier l'un en croyant modifier l'autre.** Corriger une date ici ne change
> rien à ce qui s'affiche ; corriger une date là-bas sans mettre ce document à jour le
> rend menteur. En cas de divergence, **le code a raison** — et ce document est à corriger.

---

## 1. Pourquoi une liste STATIQUE côté frontend

C'est la décision structurante, et elle est contre-intuitive.

> **Unibet n'expose jamais que le Grand Prix SUIVANT.** `public.grands_prix` ne contient
> donc que ce que le scraper a rencontré — **un seul GP à ce jour**. Un calendrier lu en
> base afficherait une course au milieu d'une saison qui en compte douze.

C'est exactement le défaut qui avait figé le bandeau « Grands Prix restants » à une
constante : ici, il est poussé à sa conclusion. **Le calendrier de la Formule 1 est une
donnée publique et stable — il n'a pas à être découvert chez un bookmaker.**

**La base garde ce qu'elle seule sait** : l'identifiant du GP, son statut, l'existence de
ses cotes, la date des qualifications. `enrichir()` croise les deux ;
`chargerCotesEnBase()` appelle `GET /scraper/cotes`, la route publique.

> ### Conséquence à ne pas défaire : les douze cartes s'affichent QUOI QU'IL ARRIVE
> Railway endormi, appel en échec, base vide — l'écran reste plein et lisible, seuls les
> états et les boutons manquent. C'est **l'inverse** d'un écran de liste ordinaire.
> Le bloc d'erreur s'affiche **au-dessus** des cartes, jamais à leur place.

---

## 2. Les deux calendriers — ne pas les confondre

| | Calendrier de la **saison** | Calendrier d'un **championnat** |
|---|---|---|
| Route | `/calendrier` (onglet) | `/championnats/:id/calendrier` |
| Maquette | — | 15 |
| Source | `GP_2026` + `GET /scraper/cotes` | `GET /championnats/{id}/calendrier` |
| Contenu | les 12 GP, identiques pour tous | les mêmes + score du membre + mini-classement |
| État calculé par | `etatDuGpSaison` | `etatDuGp` |
| Carte | `CarteGpSaison.jsx` | dans `ecrans/Calendrier.jsx` |

> **Ils calculent l'état différemment parce qu'ils n'ont pas les mêmes données** — l'un
> croise la liste statique avec les cotes en base, l'autre lit `resultats_disponibles`
> servi par la fonction SQL. **Mais ils doivent dire le MÊME MOT avec la MÊME COULEUR**,
> sans quoi un GP changerait d'état en passant d'un onglet à l'autre.
>
> D'où **`ETATS_GP` dans `lib/calendrier.js`, partagé.** Deux tables écrites séparément
> auraient divergé au premier libellé retouché.

L'onglet Calendrier **ne liste plus les championnats** : cette liste vivait déjà à deux
endroits (accueil et onglet Championnats), et une troisième copie n'apprenait rien tout en
occupant l'onglet qui devait porter la saison.

---

## 3. La table `GP_2026`

Douze Grands Prix, de Zandvoort à Yas Marina. Champs : `slug`, `nom`, `pays`, `circuit`,
`date` (date nue `AAAA-MM-JJ`), `mois` (libellé court en capitales).

| slug | nom | circuit | date |
|---|---|---|---|
| `pays-bas` | GP Pays-Bas | Zandvoort | 2026-08-23 |
| `italie` | GP Italie | Monza | 2026-09-06 |
| `espagne` | GP Espagne | Madrid | 2026-09-13 |
| `azerbaidjan` | GP Azerbaïdjan | Bakou | 2026-09-26 |
| `malaisie` | GP Malaisie | Sepang | 2026-10-04 |
| `singapour` | GP Singapour | Singapour | 2026-10-11 |
| `etats-unis` | GP États-Unis | Austin | 2026-10-25 |
| `mexique` | GP Mexique | Hermanos Rodríguez | 2026-11-01 |
| `bresil` | GP Brésil | Interlagos | 2026-11-15 |
| `las-vegas` | GP Las Vegas | Las Vegas | 2026-11-21 |
| `qatar` | GP Qatar | Lusail | 2026-11-29 |
| `abu-dhabi` | GP Abu Dhabi | Yas Marina | 2026-12-06 |

> ### Les `slug` doivent rester ceux de `slugCircuit`
> Ce sont eux qui donnent **le drapeau et le tracé**. Un slug inconnu fait retomber la
> carte sur le bordeaux de la marque, sans circuit. **Trois tables doivent porter les
> mêmes clés** : `GP_2026`, `TRACES` (`TracesCircuits.jsx`) et `DRAPEAUX`
> (`DrapeauxGP.jsx`). Un test le vérifie.

**À mettre à jour chaque saison**, au même titre que `backend/app/calcul/pilotes.py` et
`lib/ecuries.js`. Elle se relit sur le calendrier officiel de la FIA. Ajouter les GP du
début de saison demande aussi **leur drapeau et leur tracé**.

---

## 4. Le quantième est lu dans la CHAÎNE, jamais dérivé

> ### `jourDe()` ne fait AUCUN `new Date`
> `date` est une date nue (`2026-08-23`), donc **minuit UTC** une fois analysée. En tirer
> le jour avec `getDate()` rendrait « 22 » pour tout lecteur situé à l'ouest de Greenwich :
> **le calendrier afficherait la veille de chaque course sur la moitié de la planète.**
>
> `jourDe()` lit donc la chaîne elle-même, et `mois` est écrit dans la table.

**L'HEURE de départ ne vient jamais d'ici** : seule la base la connaît, et c'est elle qui
décide de la fermeture.

Le zéro de tête est retiré : « 04 » se lit comme un numéro de série, « 4 » comme une date.

---

## 5. Le rapprochement — sur le slug, jamais sur le nom

`enrichir()` rapproche par `slugCircuit(nom)`, qui normalise et applique une table
d'alias. Unibet écrit « GP Pays Bas » cette semaine et « GP Pays-Bas » la suivante.

> **Le nom AFFICHÉ reste celui de la table statique** : le calendrier doit se lire pareil
> d'une semaine à l'autre, y compris quand le bookmaker change l'orthographe.

`slugCircuit` : minuscules, accents ramenés à la lettre de base, préfixe « GP » retiré
**en tête seulement** (un « GP » au milieu n'est pas un préfixe), reste en tirets.

**Les alias ne sont pas une précaution en l'air** : rien ne garantit qu'un GP soit nommé
par son pays — « GP Abou Dabi », « GP Émirats arabes unis » et « GP Yas Marina » désignent
le même circuit. Le slug direct est essayé d'abord.

---

## 6. Les quatre états

**Jamais déduits du statut en base.** `cotes_disponibles` se lit dans `public.cotes`,
`resultats_disponibles` dans `public.resultats_gp`, et la fermeture se calcule sur l'heure
de départ.

> **Le statut mentirait dans les deux sens** : rien ne fait passer un GP en `cotes_figees`
> avant le samedi des qualifications, et le job de résultats passe un GP à `termine` même
> s'il reste des pronostics sans points.

| État | Couleur | Bouton |
|---|---|---|
| À venir | gris translucide, encre marron | aucun |
| Pronos ouverts | **aplat amber**, encre `#1A1A1A` | « Pronostiquer » |
| Fermé | bordeaux | aucun |
| Terminé | vert sauge | « Voir les résultats » |

**L'ordre des tests compte** : un GP couru est « terminé » quoi qu'il arrive, et une
fermeture passée l'emporte sur des cotes disponibles.

> **Un GP absent de la base est « à venir », toujours.** On ne sait ni si ses cotes
> existent, ni à quelle heure il part : le déclarer fermé sur la foi d'une date sans heure
> le fermerait dès minuit UTC, et « terminé » supposerait des résultats que personne n'a lus.

> **Tant que la base n'a pas répondu, la pastille est une SILHOUETTE.** Une pastille
> « À venir » posée par défaut se corrigerait en « Pronos ouverts » sous les yeux du
> joueur, et lui aurait menti l'instant d'avant. La date, le nom et le circuit s'affichent
> tout de suite : ils sont vrais sans la base.

**Deux jeux de classes dans la même table** (`pastille` et `pastilleSurDrapeau`) : les
cartes de la saison posent leurs pastilles sur un drapeau, celles d'un championnat sur du
blanc. Une seconde table divergerait.

---

## 7. Le bouton n'existe que là où il y a quelque chose à faire

Un GP à venir n'a pas encore de cotes ; un GP fermé n'accepte plus rien.

> **Le bouton « Pronostiquer » exige `cotesArretees(gp)`** — statut `cotes_figees` **et**
> qualifications passées (voir `metier.md` §3). **Une carte peut donc afficher « Pronos
> ouverts » sans bouton.** C'est assumé : le geste proposé est plus exigeant que le mot
> affiché, ce qui est le bon sens du doute.

**Deux styles plutôt qu'un** : aplat plein pour « Pronostiquer », consultation pour
« Voir les résultats ». Douze cartes terminées feraient sinon douze barres rouges, et
**l'urgence ne se distinguerait plus de l'archive**.

---

## 8. La carte de la saison

Le drapeau couvre **toute la carte** (200 px), et tout le contenu est posé par-dessus en
blanc. Pile de calques identique au bloc de l'accueil : **fond du drapeau → lueur → voile
calculé → surcouche 15 % → tracé → contenu**.

> **L'ombre portée du texte devient INCONDITIONNELLE ici.** Ailleurs elle n'est posée que
> sur les drapeaux à plusieurs bandes, la couture étant la seule chose qu'un texte pouvait
> croiser. Le tracé en est une seconde, et **il existe sur les douze cartes**.

Le tracé est **borné à la zone d'informations** et ne court pas sous la bande d'action,
qui est opaque — un circuit passant dessous se lirait comme un trait coupé net.

> **La surface d'une pastille est OPAQUE, pas semi-transparente.** Le pire substrat est le
> noir de Las Vegas : une bande blanche à 85 % y poserait le vert sauge à **3,45:1**, et il
> faut **97 %** pour atteindre 4,5:1 — c'est-à-dire du blanc. La translucidité passe par
> l'encre colorée, jamais par la surface.

**`HAUTEUR_BANDE` est retranchée de la carte, jamais ajoutée dessous** : les douze cartes
gardent la même hauteur, qu'elles portent un bouton ou non.

### Une carte terminée pâlit — `opacity: 0,4` (v`0.54.0`)

Douze drapeaux pleins de la même intensité ne laissent aucun repère à l'œil, et le
calendrier ne sert à rien d'autre qu'à trouver le prochain Grand Prix. L'archive recule
donc derrière ce qui reste à jouer.

L'opacité est posée sur l'`<article>`, **jamais calque par calque** : les six couches de la
pile doivent pâlir ensemble. Appliquée séparément, chacune se composerait sur celle du
dessous au lieu du fond de l'app, et le voile — qui est justement ce qui tient le contraste
du texte — perdrait plus que le drapeau qu'il couvre.

> #### Écart mesuré, et assumé (CLAUDE.md §6)
> L'opacité compose l'encre **et** son fond sur le beige de l'app, donc elle les rapproche.
> Relevé sur le pire substrat (le noir de Las Vegas) et sur la pastille la plus serrée :
>
> | Opacité | Pastille « Terminé » | Blanc sur drapeau bordeaux |
> |---|---|---|
> | `1` | 4,86:1 | 10,88:1 |
> | `0,75` | 3,07:1 | 6,36:1 |
> | **`0,4`** | **1,74:1** | **2,49:1** |
>
> **Sous les 3:1 d'un grand texte porteur de sens.** La valeur est celle qui a été
> demandée, et l'arbitrage se défend : ces cartes sont une archive, la seule information
> qu'on y cherche est « c'est passé », et elle se lit à la pâleur avant de se lire au mot.
> **`0,75` est le point où la pastille repasse le plancher**, si la lisibilité doit primer.

Le bouton « Voir les résultats » pâlit avec le reste mais **garde sa hauteur** : une zone
tactile ne se réduit jamais.

### L'écran s'ouvre sur le prochain Grand Prix

Au montage, `CalendrierGlobal` défile jusqu'à la première carte non terminée. Les Grands
Prix passés restent accessibles **en remontant** ; ils ne sont simplement plus la première
chose qu'on voit.

- **Ce n'est pas une animation, c'est une position de départ.** Le défilement est
  instantané. L'onglet Calendrier est ouvert plusieurs fois par jour : faire défiler la
  saison sous les yeux à chaque fois coûterait le temps du geste sans rien apprendre.
- **Une seule fois par montage**, jamais à la revalidation — sans quoi une réponse Railway
  lente arracherait l'écran des mains de quelqu'un en train de lire plus bas.
- **La position se calcule sur la chaîne des `offsetTop`, pas sur
  `getBoundingClientRect()`.** L'écran entre en scène sous un `translateX` et ses blocs sous
  un `translateY` : le rectangle rendu est décalé pendant toute l'animation d'entrée,
  c'est-à-dire exactement au moment du calcul. Les `offsetTop` ignorent les `transform`.
- **`estGpPasse` est le seul propriétaire de la question**, partagé avec la carte. Deux
  prédicats écrits séparément auraient donné un calendrier ouvert sur une carte pâle, ou
  une carte vive hors de l'écran.
- **C'est le statut qui tranche, pas la date.** Un Grand Prix couru mais jamais scrapé
  n'est pas `en_base`, donc reste « à venir » et reste vif. On ne pâlit que ce dont on sait
  qu'il est joué — conséquence directe du §6, et elle vaut aussi pour le défilement.

---

## 9. Le calendrier d'un championnat

`calendrier_du_championnat(championnat, profil, saison)`, une ligne par GP.

**Trois décisions à ne pas défaire :**

1. **`rank`, pas `row_number`** — il n'y a **aucun** critère de départage sur une course
   isolée. Avant le départ, tout le monde est à zéro : `row_number` inventerait un premier
   et un dernier. **Les ex æquo s'affichent comme tels.**
2. **Un GP sans date annoncée est servi quand même**, en fin de liste, rattaché à la saison
   courante. C'est l'inverse du choix fait pour les statistiques, et pour une raison
   précise : **une moyenne fausse ne se voit pas, un Grand Prix manquant dans un
   calendrier se voit tout de suite.**
3. **`mes_points` vaut `NULL`, jamais `0`**, quand aucun pronostic n'a été noté. L'écran
   affiche l'un « Tes pronostics ne sont pas encore validés », l'autre « 0 pts ».

**Le profil transmis vient du JETON, jamais de l'URL** : « mon score sur ce GP » ne peut
désigner que l'appelant.

`SAISON_COURANTE = 2026` est écrite **en dur**, pas déduite de `datetime.now()` : le
calendrier doit rester lisible en intersaison. **À faire évoluer avec la grille de
`app/calcul/pilotes.py`**, qui décrit la même saison.

**Le mini-classement est limité à trois membres** : en servir davantage ferait transporter
tout le championnat pour chacun des douze GP.

**Le bloc « leader général » est calculé côté écran**, en additionnant les mini-classements
déjà servis. Il n'apparaît qu'une fois un GP couru : avant, il annoncerait un leader à
zéro point.

---

## 10. Le décompte de « Grands Prix restants »

Il compte **les cartes qui ne sont pas terminées**, jamais une constante.

> ⚠️ **Le bandeau de l'ACCUEIL, lui, affiche encore `GP_RESTANTS = 12`** — une constante
> posée quand `chargerGrandsPrixRestants` comptait les lignes en base, c'est-à-dire une
> seule course. **La réponse existe maintenant** : compter `GP_2026` filtré par
> `etatDuGpSaison`, comme le fait `CalendrierGlobal`.
>
> **À faire, sans quoi les deux écrans se contrediront dès la première course courue.**
> Voir `roadmap.md`.
