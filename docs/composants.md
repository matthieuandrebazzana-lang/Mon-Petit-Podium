# Composants et assets

Les composants importants, leurs responsabilités, et où vivent les SVG.
**Ce n'est pas une liste exhaustive** — seulement ce qui se devine mal à la lecture.

---

## 1. Structure

```
src/
├── App.jsx              routeur + les trois groupes de routes
├── auth/AuthContexte.jsx
├── composants/          réutilisables (41 fichiers)
│   └── icones/          7 icônes extraites de planches SVG
├── ecrans/              un fichier par écran (21)
└── lib/                 accès aux données, formatage, hooks (24)
```

---

## 2. Les composants de structure

### `Ecran.jsx`

Enveloppe tout écran : zones sûres, animation d'entrée `t-ecran`, et **réservation de la
place de la barre de navigation** (`h-nav`, en fin de flux).

> **La place est réservée par un bloc en fin de flux, pas par un `padding-bottom`.** Deux
> utilitaires écrivant la même propriété se départagent par leur ordre dans la feuille
> compilée — ce n'est pas une garantie sur laquelle poser la zone sûre du home indicator.

### `Bloc` (dans `Ecran.jsx`) — le piège le plus coûteux du projet

Porte `.t-stagger-line`, l'entrée échelonnée.

> ### JAMAIS de classe de disposition sur un `<Bloc>`
> `.t-stagger-line` déclare `display: block` **hors de toute couche Tailwind**. Une règle
> non affectée à une couche l'emporte sur **toutes** les règles empilées, quelle que soit
> leur spécificité : `.flex` vit dans `@layer utilities`, elle perd.
>
> **Le bloc reste en `display: block`, où `gap`, `flex` et `justify-*` n'ont aucun effet
> — et rien dans le JSX ne le laisse voir.**
>
> **Le motif à suivre : le conteneur flex vit À L'INTÉRIEUR du bloc.** Trois occurrences
> ont été corrigées (accueil, liste des championnats, championnat) ; les cas historiques
> sont dans `bugs-connus.md`.

Il porte aussi `will-change: transform` en permanence, donc **chaque `Bloc` est un
contexte d'empilement** : tous les `z-index` posés dedans sont comparés entre eux
seulement, jamais aux barres qui vivent dehors. Monter le `z-index` d'un en-tête de marché
face à la barre de navigation ne servirait à rien.

### `EnTeteEcran.jsx` — l'en-tête à grand titre rétractable

La rangée de retour reste collée, le grand titre défile et se replace en petit dans la
barre. Deux modes : matériau translucide qui **n'apparaît qu'une fois du contenu passé
dessous**, ou **teinté** (couleur du championnat, en permanence — attendre le défilement
laisserait une bande beige au-dessus d'un aplat coloré).

**Quatre points à ne pas défaire :**

1. **La bascule passe par un `IntersectionObserver` sur une sentinelle, jamais par un
   écouteur de défilement.** Un `scroll` se déclenche à chaque image ; l'observateur ne
   rend que deux fois par écran.
2. **Le composant doit être monté en enfant DIRECT d'`Ecran`.** Un `position: sticky` posé
   dans un `Bloc` se collerait à sa boîte au lieu de la fenêtre.
3. **Seule l'opacité du matériau s'anime**, sur un calque à part. Faire varier le rayon du
   `backdrop-filter` coûterait une passe de composition par image.
4. **`--entete-hauteur` est la source unique du décalage.** Les en-têtes de marché
   collants s'y accrochent ; écrite en dur à deux endroits, elle divergerait.

**`photo` n'existe qu'en mode teinté**, et `onPhoto` en fait un bouton (version `0.75.0`) —
même règle que `HeroProfil` : sans ce rappel, rien n'y est modifiable, et un bouton qui
n'agit pas serait un bouton de trop dans l'ordre de tabulation. **C'est l'écran qui juge
qui a le droit de le voir**, jamais ce composant. Détail en §8.

**`EnTete.jsx`** (l'ancien, non collant) reste en service sur les douze autres écrans.
L'étendre est une substitution d'import.

### `NavBarre.jsx`

**Montée dans `App.jsx`, jamais dans un écran** — trois raisons :

1. `Ecran` porte un `transform` ; un `position: fixed` posé dedans se positionnerait par
   rapport à cet ancêtre et **défilerait avec la page**. La règle vaut **même pour
   `translateX(0)`**.
2. Montée une fois, elle ne se démonte pas d'un écran à l'autre : la couleur de l'onglet
   **glisse**, là où une barre remontée à chaque navigation clignoterait.
3. Un seul endroit décide où elle apparaît.

**`lib/navigation.js` est la source unique** : `NavBarre` pour s'afficher, `Ecran` pour
réserver la place. Deux listes écrites séparément divergeraient au premier écran ajouté.

> **Le piège des motifs** : `/championnats/creer` et `/championnats/rejoindre` répondent au
> motif `/championnats/:id` — React Router ne fait pas la différence, et l'ordre des routes
> d'`App.jsx` ne s'applique pas à un `matchPath` isolé. D'où `CHEMINS_SANS_BARRE`, évalué
> **en premier**.

`ongletActif` est une **fonction, pas un chemin** : un onglet reste allumé sur tout ce qui
lui appartient. Retoucher l'onglet déjà ouvert **ramène en haut de l'écran**.

---

## 3. Les composants à risque

| Composant | Pourquoi |
|---|---|
| `Bloc` | classes de disposition inertes (§2) |
| `EnTeteEcran` | doit être enfant direct d'`Ecran` |
| `Squelette` | `.t-skel-bar` peint sa couleur hors couche : une classe utilitaire ne la bat pas, il faut un style en ligne |
| `Voiture` / `VoituresEcuries` | couleurs en **attribut `fill`**, jamais par classe — sinon deux voitures de couleurs différentes ne pourraient pas coexister |
| `DrapeauxGP` | **ordre des calques** : drapeau → lueur → voile → surcouche → contenu. Tout ce qui éclaircit passe **sous** le voile |
| `TracesCircuits` | pose un `aspect-ratio` **en ligne** : à couper (`boiteLibre`) quand l'appelant fixe les deux dimensions |
| `Repli` | anime `grid-template-rows`, pas un `transform` — et **ne doit jamais employer `.t-acc`** (§5) |
| `FondPiste` | `preserveAspectRatio="none"` : la planche s'étire en hauteur. Les deux `<rect>` du bandeau en sont **volontairement absents** |
| `Icones` | les variantes `pleine` emploient **`fill-rule="evenodd"`** : la porte de la maison est un **trou dans l'aplat**, jamais un rectangle blanc posé dessus — qui se verrait le jour où le fond n'est plus blanc |
| `CarteGpSaison` | **deux `<a>` frères**, jamais imbriqués (le corps et la bande mènent ailleurs). Le `pressable-large` est sur l'`<article>` : `:active` remonte aux ancêtres, et le poser sur les deux liens composerait 0,985 × 0,985 |
| `VainqueursCircuit` | **grille 2 colonnes, plus une rangée qui défile** (v`0.60.0`) : la voiture passe AU-DESSUS du nom, sans quoi « Verstappen » (79 px) se tronque dans une colonne qui n'en laisse que 77,5 à 375 px |
| `SeancesWeekend` | c'est le **rang** qui décide de la mise en avant, pas le seuil de 24 h — un vendredi matin, les deux premières séances y tiennent. Le nombre de rangées **n'est pas fixe** : il vient des clés que `gp.seances` déclare (week-end sprint) |
| `DrapeauxPilotes` | **`preserveAspectRatio="none"`, pas `slice`** — une rangée de classement fait 5,2:1, un drapeau 1,5:1, et `slice` recadrait l'Allemagne en rouge uni. Et **aucun `fill` sur un ancêtre** : la bande noire allemande n'a pas d'attribut `fill` et l'hériterait |
| `LigneClassement` (`ResultatsGp`) | **aucun texte en `texte-doux`** : sur le lavis de drapeau à 8 %, le gris ne vaut que 2,39:1. Le prénom et l'écurie prennent le marron `secondaire` |

---

## 4. Les planches SVG

**Aucune n'est servie en production.** Tout est extrait **par script** dans un composant
React et part avec le bundle en SVG inline.

> ### Quatre règles d'extraction, tenues à chaque fois
>
> 1. **Les données de chemin sont copiées OCTET POUR OCTET.** Le découpage se fait par
>    script, jamais à la main : transcrire des chemins de plusieurs milliers de caractères
>    introduit des fautes invisibles à la lecture. Des tests comparent à la planche.
> 2. **Les `viewBox` sont les VRAIES boîtes englobantes**, mesurées en échantillonnant les
>    courbes de Bézier. **Jamais des tranches arithmétiques** — les dessins d'une planche
>    ne sont ni jointifs, ni de même taille, ni régulièrement espacés. **Aucune coordonnée
>    n'est réécrite : c'est le cadrage qui bouge.**
> 3. **Les classes `.cls-N` deviennent des attributs.** Une balise `<style>` embarquée
>    déclarerait ces classes au niveau du **document entier**.
> 4. **L'ORDRE DE DOCUMENT est conservé** — c'est l'ordre de peinture, et un SVG n'a pas
>    d'autre `z-index` que celui-là. Un fragment qui porte les bonnes formes, les bonnes
>    couleurs et le bon cadrage peut malgré tout rendre un dessin faux : il suffit qu'une
>    forme du dessous soit passée dessus. **La règle 1 ne protège pas de celle-ci** — les
>    chemins étaient exacts au caractère près quand Mercedes et Alpine se sont retrouvées
>    barrées de gris (`bugs-connus.md` §17).

| Planche | Extraite dans | Contenu |
|---|---|---|
| `logo-05.svg` | `LogoGreedF1.jsx` | icône carrée + bandeau du nom |
| `logo.svg` | `icones/IconeCreer`, `IconeRejoindre` | trophée, deux silhouettes |
| `logo-02.svg` | `icones/IconeAccueil`, `IconeChampionnats`, `IconeCalendrier`, `IconeProfil` | les 4 onglets |
| `traces.svg` + `calendrier.svg` | `TracesCircuits.jsx` | **12 tracés en TRAIT** |
| `gp-cards.svg` | `TraceCircuit.jsx` | 2 silhouettes PLEINES (Monza, Spa) |
| `flags.svg` | `DrapeauxSVG.jsx` | 6 drapeaux dessinés |
| `voitures_perso.svg` | `Voiture.jsx` | voiture colorisable |
| `voitures_ecuries.svg` + `VOITUREs_am.svg` | `VoituresEcuries.jsx` | 11 livrées |
| `matti.svg` | `SkinsEcuries.jsx` | 9 des 11 **pastilles carrées** |
| `matt.svg` | `SkinsEcuries.jsx` | pastilles **Racing Bulls et Red Bull** (`0.47.0`) |
| `06.svg` | `--motif-damier` (data-URI) | vague du damier |
| `vue_piste.svg` | `FondPiste.jsx` | **le fond de la vue piste** (`0.49.0`) |
| `voiture.svg` | — | **ancien dessin, remplacé** |
| `logoV2.svg` | `icones/IconeEtoileLogo` | **l'étoile** — le 2ᵉ de ses 4 dessins (`0.67.0`) |

### `FondPiste` — la planche qui s'étire

Le fond de la vue piste, extrait de `assets/vue_piste.svg` : le sol beige `#F4EFEA` et ses
coins arrondis, quatre segments de ligne médiane, et **deux kerbs en chemins**, pas en
dégradés répétés. Les anciennes règles `.piste-fond`, `.piste-kerb` et `.piste-axe` sont
parties avec l'asphalte qu'elles peignaient.

| Point | Pourquoi |
|---|---|
| `preserveAspectRatio="none"` | L'échelle horizontale et l'échelle verticale deviennent **indépendantes** : les kerbs gardent leur largeur proportionnelle à celle de la piste quel que soit le rapport de forme, seule la pente de leurs bandes s'incline. Sur les iPhone visés l'écart est nul à deux dixièmes près — planche 0,4604, iPhone 15 Pro 0,4613 |
| **Les deux `<rect>` du bandeau sont retirés** | Le bandeau doit porter la **couleur du championnat**, le **damier** (un utilitaire CSS) et le **nom** — qui ne peut pas se centrer dans 10,94 % de la hauteur d'écran sans tomber sous la Dynamic Island. Il vit donc dans le DOM. Rien d'autre ne bouge : l'ordre relatif du reste est intact |
| Les kerbs gardent `#7f1717` | Un kerb rouge et blanc est le signe **F1**, pas un repère de championnat. Il vaut 9,02:1 sur le beige, contre un plancher de 3:1 |
| Le sol est **aussi** peint en CSS (`--piste-sol`) | Le dessin arrondit ses coins ; sans l'aplat, les quatre angles laisseraient voir le grain du `body` sur un écran qui n'en porte pas |

> **La zone de jeu est bornée par des pourcentages mesurés sur les chemins**, 4,2205 % à
> gauche et 4,8058 % à droite — les bords intérieurs des kerbs, à 24,88 et 561,17 sur
> 589,5. Ce sont des **boîtes englobantes échantillonnées**, pas des tranches
> arithmétiques : les deux kerbs de la planche ne sont pas symétriques.

### Les deux modules de tracés — ne pas les confondre

**`TracesCircuits.jsx`** : douze circuits en **trait** (`fill: none`, `stroke`) — un `fill`
refermerait chaque circuit en tache noire. Filigrane et bandes de circuit.

**`TraceCircuit.jsx`** : deux silhouettes **pleines**. **Plus monté nulle part** depuis que
les deux calendriers sont passés aux vrais tracés — gardé parce qu'à 20 × 32 px un trait
de 1px se lit moins bien qu'un aplat.

Quatre points sur `TracesCircuits` :
- **`vector-effect="non-scaling-stroke"`** — l'épaisseur est en pixels d'écran. En unités
  du dessin, le trait sortirait deux fois plus épais sur Zandvoort que sur Bakou.
- **Le rapport de forme est porté par le `<svg>`** — l'appelant ne fixe **qu'une**
  dimension. Quand il les fixe toutes deux, `boiteLibre` coupe ce ratio.
- **Un circuit en plusieurs traits garde ses sous-tracés dans un seul `d`** (Sakhir en
  compte quatre). Sans remplissage, plusieurs `M` se rendent comme autant de `<path>`.
- **Un tracé absent est un cas NORMAL** : le composant ne rend **rien**, plutôt qu'un
  motif de repli qui laisserait croire que ce GP se court sur cette forme.

### Les drapeaux

Deux formes coexistent : **cinq en `linear-gradient` CSS** (bandes franches — le CSS le
dit parfaitement, une image demanderait un fichier par pays) et **six dessinés**.

> **Le champ `couleurs` n'est PAS décoratif : c'est la matière du calcul de contraste.**
> Le voile est dérivé de la **bande la plus claire**. Tant que les États-Unis étaient
> déclarés par leur seule dominante rouge, le calcul concluait qu'aucun voile n'était
> nécessaire — le dessin, lui, peint treize bandes blanches.
>
> **Toute forme peinte par le SVG doit avoir sa teinte dans `couleurs`.** Un test compare
> les deux tables forme par forme.

**`fond` reste toujours renseigné**, même pour un drapeau dessiné (il vaut alors `base`) :
il ne se voit jamais, mais c'est le drapeau de « ce bloc porte un drapeau », que les écrans
lisent pour savoir s'ils retombent sur le bordeaux de repli.

`preserveAspectRatio="xMidYMid slice"` — le pendant d'`object-fit: cover`.

### Les nationalités de pilotes — une seconde question, la MÊME source de couleurs (`0.59.0`)

L'écran de détail pose le drapeau du vainqueur en fond de sa carte, à **9 %**. C'est une
question distincte de celle du bloc d'un Grand Prix : `DRAPEAUX` est indexée par slug de
**circuit** (`las-vegas` et `etats-unis` sont deux entrées pour un seul pays), et
« britannique » n'y entrerait sous aucune clé.

**D'où `NATIONALITES` — mais pas une seconde liste de couleurs.** Quatre nationalités sur
huit décrivent un pays que `DRAPEAUX` peint déjà : elles le **référencent** au lieu de le
recopier. Deux jeux de bandes écrits séparément auraient divergé au premier ajustement, et
le symptôme aurait été discret — le drapeau néerlandais d'une carte de vainqueur
légèrement différent de celui du bloc de Zandvoort, sur le même écran.

`drapeauDeNationalite(cle)` rend le gentilé **et** l'apparence, calculée par le même
`apparence()` que les pays hôtes.

> **Le lavis ne passe PAS par le voile calculé**, et c'est la seule différence avec le bloc
> de l'accueil. Là-bas le drapeau est peint à pleine intensité sous du texte blanc, et le
> voile garantit les 3:1 ; ici c'est l'opacité de 9 % qui joue ce rôle, en amont. Mesuré
> sur le pire substrat (le bleu britannique) : `#012169` à 9 % sur blanc donne `#E8EBF1`,
> où `#1A1A1A` vaut **14,9:1**.

> ### Le septième drapeau dessiné ne vient pas de la planche — écart signalé
> `assets/flags.svg` ne dessine que des pays hôtes, et le Royaume-Uni n'en est pas un cette
> saison. Aucune borne de dégradé ne sait dire un sautoir contre-changé : sans dessin, six
> cartes de vainqueur sur dix seraient les seules sans fond.
>
> **La règle 1 du §4 n'est pas enfreinte, elle est appliquée à une autre source.** Ce
> drapeau a une géométrie **spécifiée** — champ 1:2, croix de Saint-Georges au 1/5 de la
> hauteur, liseré blanc au 1/15, sautoir blanc de 6 et sautoir rouge contre-changé de 4
> dans le système 60 × 30. Les quinze formes ont été **calculées par script** depuis cette
> spécification (découpe de Sutherland–Hodgman des bandes diagonales par le cadre puis par
> les quatre triangles de la contre-charge), rendues, et relues à l'image. Aucune
> coordonnée n'a été tapée à la main : c'est l'objet de la règle 1, qui écarte la
> transcription manuelle et non la géométrie exacte.
>
> **L'Australie n'entre pas**, et c'est la même règle qui le décide : sa croix du Sud n'a
> pas de spécification qu'on puisse poser sans l'approximer. Ses vainqueurs restent sans
> fond, comme n'importe quel pays absent de la table (`roadmap.md` §3.8 bis).

### Les drapeaux de pilotes — la seule bibliothèque du frontend (`0.62.0`)

`composants/DrapeauxPilotes.jsx` importe **seize** drapeaux de `country-flag-icons`, un
module par pays, indexés par code ISO 3166-1 alpha-2. C'est la seule entorse à la règle
« tout est extrait par script d'une planche » — et c'est cette règle même qui la commande.

**La grille 2026 demande seize pays.** Sept d'entre eux — Australie, Nouvelle-Zélande,
Brésil, Mexique, Canada, Thaïlande, Argentine — n'ont aucune description qu'un dégradé
sache poser sans l'approximer, et `assets/flags.svg` ne dessine que des pays **hôtes**.
Le choix était donc entre approximer sept drapeaux et en prendre seize exacts.

> **Le seizième est le Japon, entré en `0.63.0` avec Tsunoda** (`roadmap.md` §3.8 quinquies).
> C'est le premier de la planche dont l'emblème n'est pas une bande mais une **charge** : le
> disque, étiré par `preserveAspectRatio="none"` sur une rangée de 5,2:1, ressort en ellipse
> large. **C'est le rendu voulu et non un défaut** — `slice` en aurait fait une barre rouge
> centrale, exactement le recadrage que la ligne du tableau ci-dessous décrit. Vérifié à
> l'image, à 320 px, contre la feuille compilée.

| Point | Pourquoi |
|---|---|
| **`country-flag-icons`, pas `react-world-flags`** | le second embarque les 250 drapeaux en data-URI dans un lot UMD de **3,6 Mo** et les résout par `require.context`, une API propre à webpack que Vite n'implémente pas. Le premier est de l'ESM pur, `sideEffects: false` : les seize imports pèsent **+15,5 Ko** au lot, mesurés — et le contrôle du lot confirme **seize** composants pays, pas un de plus |
| **`preserveAspectRatio="none"`** | même arbitrage que `FondPiste`. Une rangée fait 5,2:1, un drapeau 1,5:1 : `slice` recadrait sur la bande centrale, et l'Allemagne ressortait rouge uni. `none` garde **toutes** les bandes. `VainqueursCircuit` garde son `slice` — ses cartes sont presque carrées |
| **Aucun `fill` ni `color` sur un ancêtre** | la bande noire allemande n'a pas d'attribut `fill` et **hérite** ; le Canada pose le piège à l'envers avec `fill="red"` en mot-clé. Invisible à la lecture du JSX |
| **Le lavis à 8 %, mesuré** | pire substrat le noir → `#EBEBEB` : `texte` **14,60:1**, `secondaire` **8,86:1**, `primaire` **9,13:1**. **`texte-doux` : 2,39:1, banni de ces lignes**. Le Japon ne déplace pas ce plancher — son `#D80027` compose `#FCEBEE`, plus clair |
| **Un pays absent ne rend rien** | la règle du projet depuis la `0.15.0`, jamais une couleur de repli |

> **Deux systèmes de drapeaux coexistent donc**, et c'est un écart assumé au principe de la
> source unique : `DRAPEAUX` garde les pays hôtes parce que son champ `couleurs` alimente
> le calcul de `voileNecessaire`, qu'un SVG importé ne peut pas nourrir. Le détail et la
> façon de le résorber sont dans `roadmap.md` §3.8 quater.

### Les voitures

**`voitures_perso.svg`** empile quatre voitures, chacune peinte par **son propre couple de
classes**. La première emploie `cls-6` (coque) et `cls-14` (ailerons) — `cls-2`, souvent
cité par erreur, appartient à la quatrième et **n'existe pas** dans la première.

**Les pièces mécaniques gardent leurs gris d'origine** (pneus, suspensions, fond plat,
casque) : les repeindre ferait perdre la lecture de l'objet — une voiture monochrome n'a
plus de roues.

**Chaque texte prend l'encre qui contraste avec l'aplat sous lui** (`encreSur`) : la planche
écrit ses deux textes en blanc, ce qui rend le pseudo illisible sur les ailerons clairs.

Deux corrections sur le dessin d'origine : `text-anchor="middle"` (le calage manuel
décentrait un numéro à deux chiffres) et **la taille du nom suit la longueur du pseudo**.

**Les onze livrées** ont toutes la même boîte (141,11 × 288,09) : elles se substituent sans
qu'une valeur de la vue piste ne bouge. Leur teinte est **lue dans `lib/ecuries.js`** —
c'est la même question, et la couleur dominante du dessin ne ferait pas l'affaire (cinq
livrées sont à dominante blanche ou grise).

**`livreeDuMembre` (`lib/palette.js`) est le SEUL endroit qui décide de ce que porte une
voiture.** Les quatre surfaces qui en affichent une y passent. Un slug inconnu retombe sur
le mode personnalisé — ce qui se voit à l'écran au lieu de planter.

---

## 5. Les modules `lib/`

| Module | Rôle |
|---|---|
| `useDonnees.js` | cache localStorage *stale-while-revalidate* |
| `api.js` | seul point de traduction des échecs réseau |
| `erreurs.js` | seul point de traduction des erreurs d'authentification |
| `format.js` | **seul endroit qui habille un nombre de points** ; `instantFermeture` (à `date_course`, sans marge depuis la `0.72.0`), `DELAI_OUVERTURE_MS`, les deux comptes à rebours |
| `useFermeture.js` | `useFermeture` (« est-ce fermé ? »), `useEtatPronostics` (le décompte du week-end) |
| `couleurs.js` | aplats de bloc, contraste, encres |
| `palette.js` | 20 couleurs de voiture, luminance, `livreeDuMembre` |
| `ecuries.js` | onze écuries, grille 2026, `ecurieDuLibelle` — voir `ecuries.md` |
| `nationalites.js` | **la nationalité des 23 pilotes**, en ISO alpha-2 — contrepartie de `pilotes.py`, dont elle **diverge** depuis la `0.63.0` (Tsunoda) |
| `calendrier.js` | `ETATS_GP`, `cotesArretees`, `etatPronostics` — **seule lectrice du statut `cotes_figees`** |
| `calendrier2026.js` | **la liste des GP** — voir `calendrier.md` |
| `navigation.js` | barre, onglets, `origineRetour` |
| `pronostics.js` | marchés, **`ORDRE_MARCHES` / `trierParMarche`**, favoris, exclusion croisée, `choixDuPronostic`, `oublierMesPronostics`, `decrirePronostics` |
| `stockage.js` | **seul juge d'un fichier CHOISI** : formats, plafond de 5 Mo, dépôt, ménage |
| `image.js` | **seul juge de ce qu'on DÉPOSE** : décodage (fichier **ou** URL), recadrage, 800 px, JPEG 0,85 |
| `usePhoto.js` | l'état de chargement d'une image, cache du navigateur compris |

**Deux ajouts en version `0.53.0`, et tous deux pour la même raison : un second consommateur.**
`choixDuPronostic` — « quel pilote, ou quels deux pilotes, ce pronostic nomme-t-il ? » —
vivait dans l'écran de résultats ; l'écran « Résultats par Grand Prix » pose la même
question. Écrite deux fois, elle aurait divergé sur le cas qui compte : un **podium** nomme
deux pilotes sans ordre entre eux (règle 4.2), et l'écran qui l'aurait oublié n'en aurait
affiché qu'un sans que rien ne le signale.

`oublierMesPronostics` balaie d'un coup les **quatre** caches dont le contenu dépend de
« ai-je déjà joué ce Grand Prix ? » : l'accueil, les deux calendriers, l'écran des paris de
chacun. Même motif qu'`oublierMesApparitions` (§5, plus bas) — quatre effacements écrits
séparément auraient fini par en oublier un, et le symptôme aurait été le défaut même que
la version corrige : « Pronostiquer » proposé juste après une validation.

Trois règles ont été **sorties des écrans** vers `lib/pronostics.js` — `optionsDisponibles`
(exclusion croisée), `enConflit` et `bonusEpingles` (les bonus encore épinglés). Raison :
**le rendu statique n'exécute aucun effet et ne rejoue aucun appui**, donc elles ne
seraient vérifiables qu'en montant un DOM que le projet n'outille pas. Sorties de là, elles
s'éprouvent directement. Même motif pour `VueAdmin`, fonction pure de ses props, séparée de
`SectionAdmin` qui porte l'état.

### `ORDRE_MARCHES` — l'ordre des marchés a un seul propriétaire (`0.66.0`)

Unibet sert ses marchés dans l'ordre de sa page : les deux obligatoires peuvent y tomber
entre deux duels de coéquipiers. L'ordre d'affichage est donc **une décision du projet**,
posée une fois dans `ORDRE_MARCHES` — obligatoires, résultat de course, écurie,
anecdotique, duels en dernier — et `trierParMarche` l'applique aux **deux** surfaces qui
montrent des marchés : les sections du tableau des cotes et la liste des paris bonus de
l'écran de saisie. Écrit dans chacun des deux, il aurait divergé, et le symptôme aurait
été discret — le même marché à deux places selon la porte d'entrée.

> **La constante vit dans `lib/`, pas dans l'écran.** La demande la voulait dans le
> fichier de l'écran de saisie ; elle a deux consommateurs, et la règle « une source
> unique par question » du CLAUDE.md §6 l'emporte — c'est déjà le motif qui a fait sortir
> `optionsDisponibles` et `bonusEpingles` des écrans (voir juste au-dessus).

**Les tests de reconnaissance sont mutuellement exclusifs, et c'est la propriété à ne pas
casser.** Sans elle, l'ordre de la liste cesserait d'être l'ordre d'affichage pour devenir
un ordre de priorité : « ecurie-vainqueur » contient « vainqueur », et le triplé
« vainqueur course + qualification + tour le plus rapide » contient à la fois « vainqueur »
et « tour le plus rapide ». D'où l'**égalité stricte** sur les deux marchés obligatoires et
l'exclusion de « qualif » de la famille du tour le plus rapide — le même piège de voisinage
que `calcul/points.py` documente côté backend.

La famille des « top N » tient en **une** entrée, ordonnée sur son rang : « Top 6 » avant
« Top 10 » n'est pas un choix éditorial mais l'ordre des nombres, et un « Top 3 » découvert
un jour se rangera de lui-même devant les deux au lieu d'échouer avec les inconnus. Un
marché non reconnu part **à la fin**, dans l'ordre d'Unibet : les marchés varient d'un
Grand Prix à l'autre, et le taire serait pire que le mal placer.

### `decrirePronostics` — la même mise en forme quelle que soit la porte (`0.63.0`)

L'écran de résultats d'un Grand Prix s'ouvre par **deux chemins** : depuis un championnat,
et depuis la carte d'un Grand Prix couru du calendrier. Le second n'a aucun championnat à
donner, et la section « Mes résultats » y affichait « ouvre ce Grand Prix depuis un
championnat ». Le message était exact et sans remède — la route ne sert **aucun** pronostic
sans `championnat_id`, et pour une bonne raison (étape 6).

**Un pronostic n'appartient pourtant pas à un championnat.** La table `pronostics` porte
`(profil_id, gp_id)` et rien d'autre : le joueur en a **un seul jeu** par Grand Prix,
partagé par tous ses championnats. Le championnat ne décide que de *qui d'autre* a le droit
de le voir — pour se le montrer à soi-même, il n'a jamais eu son mot à dire.

Sans championnat, les pronostics sont donc lus **directement sous RLS** — le second chemin
de données de l'étape 5, appliqué au cas que sa politique décrit le mieux : « un joueur qui
n'appartient encore à aucun championnat doit pouvoir relire ses propres pronostics ».
`chargerResultatsGp` les sert à côté de la réponse de la route, sous `mes_pronostics`, et
les deux appels partent **ensemble**.

| Point | Pourquoi |
|---|---|
| `mes_pronostics` et `membres` sont **exclusifs** | avec un championnat la route sert déjà le jeu de l'appelant : le relire serait une requête pour une donnée en main, et surtout **une seconde valeur pour la même question**, que deux caches pourraient faire diverger |
| `decrirePronostics` rend **exactement** les huit champs de `pronostics_du_joueur` | les deux alimentent le même écran à deux sections d'écart. `points` reste la cote de la **première** issue seulement, podium compris — sommer d'un seul côté ferait afficher deux potentiels différents pour le même pari selon la porte d'entrée |
| `classerLesMembres` reste le **seul** propriétaire du total | la ligne fabriquée hors championnat y passe comme les autres. Deux calculs séparés auraient fini par annoncer deux totaux pour le même joueur sur le même Grand Prix |
| Le **rang** ne suit pas | il n'a de sens qu'entre membres. Hors championnat la pastille disparaît plutôt que d'annoncer un « 1er » qu'on serait seul à disputer |
| L'échec de la lecture n'emporte pas l'écran | le classement de la course est public et reste la raison d'ouvrir la page. Seule la section dit qu'elle n'a pas pu charger — jamais « aucun pronostic », qui serait une affirmation non vérifiée |
| `cleResultats` porte un marqueur `v2` | l'entrée de cache porte un champ de plus : servie telle quelle, une entrée d'avant aurait fait afficher « Aucun pronostic » le temps d'un aller-retour. Même leçon que `cleSaison` |

> **Écart signalé (CLAUDE.md §6) : il y a maintenant DEUX propriétaires de cette mise en
> forme**, `decrirePronostics` et la fonction SQL `public.pronostics_du_joueur`. L'option
> propre était de faire servir la seconde par la route sans `championnat_id` — un seul
> propriétaire, et rien à recopier. Elle a été écartée pour une raison de **calendrier, pas
> de conception** : le correctif serait parti sur Railway, où la `0.57.0` du backend n'est
> toujours pas déployée, et la section serait restée aussi vide qu'avant. Le prix est écrit
> à côté des deux fonctions : **toute retouche de l'une se relit sur l'autre.**

### `Horloge` et `etatPronostics` — l'horloge ne décide plus de ce qu'elle annonce (`0.57.0`)

`composants/Horloge.jsx` fabrique les trois tuiles, en deux tailles, et **rien d'autre**.
Le titre au-dessus (« Ouverture dans », « Fermeture dans », « Pronostics »), la phrase
décomptée et le mot qui remplace le décompte quand il n'y en a pas viennent tous de
`etatPronostics` (`lib/calendrier.js`), servi par le hook `useEtatPronostics`.

> **Elle les calculait elle-même, et c'était une seconde source.** Le libellé était figé à
> « Fermeture dans » dans le composant et **une seconde fois** dans les cases de statut du
> bloc d'accueil, écrites séparément. Les deux ont annoncé la fermeture de pronostics pas
> encore ouverts pendant onze versions — le symptôme exact que le partage de `Horloge` en
> `0.18.0` cherchait à éviter, revenu par la porte du texte. Règle métier et arbitrage
> complet dans `metier.md` §3.

**Quatre surfaces, un seul état** : les deux cases du bloc d'accueil, l'horloge de l'écran
de saisie, celle du récapitulatif. `texte` non nul est **le seul test** pour savoir s'il y
a quelque chose à décompter — l'horloge n'a plus à distinguer « fermé » de « heure
inconnue » pour choisir entre les tuiles et le mot.

**`useEtatPronostics` met les trois champs du Grand Prix en dépendance un par un, jamais
l'objet.** `useDonnees` sert un objet neuf à chaque revalidation en arrière-plan, même
quand rien n'a changé : la minuterie serait détruite et réarmée sans fin.

**`useFermeture` reste en place**, pour le tableau des cotes : il n'affiche aucun décompte
et ne pose qu'une question booléenne.

### `image.js` et `stockage.js` — deux plafonds qui ne mesurent pas la même chose

Introduits séparément à la version `0.51.0`, et il faut les deux :

| Module | Question | Réponse |
|---|---|---|
| `stockage.js` | ce que le joueur a le droit de **choisir** | 5 Mo, jpg / png / webp |
| `image.js` | ce qu'on **dépose** | 800 px de côté, JPEG 0,85, toujours `.jpg` |

Rien ne va du premier au second sans passer par le recadrage : toute photo sort d'un canvas
avant d'atteindre `deposerPhoto`. C'est ce qui permet au plafond de choix d'être si large —
refuser une photo de trois mégaoctets qu'on allait de toute façon ramener à deux cents
kilo-octets n'aurait protégé personne — **et** au plafond de 2 Mo du compartiment de ne
plus jamais être approché.

> **`compresserImage` n'est pas sur le chemin ordinaire, et elle reste écrite.** Depuis la
> `0.51.0` toute photo passe par le recadrage, qui produit déjà un carré. Mais « à quelle
> taille et dans quel format une photo part-elle ? » doit avoir une réponse **indépendante
> du geste de recadrage** : sans elle, la règle des 800 px et de la qualité 0,85 n'existerait
> que comme effet de bord d'un composant d'interface.

> **Le fond est peint en blanc avant tout dessin de compression.** Une image d'origine
> transparente rendue en JPEG donnerait un fond **noir** : le format n'a pas de canal alpha,
> et le canvas rend `rgba(0,0,0,0)` sur un aplat noir.

### `RecadragePhoto` — la première surface modale du projet

Un cadre carré, glisser pour placer, pincer pour zoomer, deux boutons. **Un seul composant
pour les deux formes** : le profil découpe un rond, le championnat un carré arrondi, mais
c'est la même question posée deux fois et **le cadre est carré dans les deux cas** — le
rond n'est qu'un masque posé dessus, il ne change rien au calcul.

| Point | Pourquoi |
|---|---|
| **Monté par un portail dans `document.body`** | `Ecran` porte un `transform` : un `position: fixed` posé dedans se positionnerait par rapport à LUI et défilerait avec la page. Même piège que `NavBarre` et `BandeauPrevisualisation` (§2), et il vaut même pour un `translateX(0)` |
| **Le canvas dessine, le CSS ne transforme rien** | Une `<img>` transformée en CSS serait plus économe, mais demanderait **deux** géométries — celle qui affiche et celle qui découpe — tenues d'accord à la main. Le canvas dessine exactement ce que l'export découpera : `carreVisible` sert les deux, et l'écart devient structurellement impossible |
| **Le dessin passe par `requestAnimationFrame`** | Safari émet plusieurs `pointermove` par image sur un écran à 120 Hz ; dessiner à chacun ferait deux à trois copies pour un seul affichage |
| **La vue vit dans une `ref`, jamais dans un état** | Elle change à chaque `pointermove`. Un rendu React par image de geste ferait retomber le déplacement sous les 60 im/s sur un iPhone |
| **`clientWidth`, jamais `getBoundingClientRect`** | La surface monte sous un `scale(0.96)` le temps de son ouverture, et une boîte mesurée à travers un `transform` rend la taille RENDUE. Le canvas aurait une réserve de pixels 4 % trop petite, et le côté du cadre serait faux d'autant — donc la découpe exportée aussi |
| **`gesturestart` / `gesturechange` refusés à la main** | `touch-action: none` ne couvre pas les gestes propriétaires de Safari iOS : sans ce refus, deux doigts feraient zoomer la page ENTIÈRE sous le recadrage. React ne connaît pas ces trois noms d'événements, d'où l'écouteur natif |
| **Le zoom est ancré sur le milieu des doigts** | Ancré au centre du cadre, l'image glisserait sous les doigts dès que le milieu de la pince n'y est pas. C'est le défaut qui fait qu'un zoom « ne suit pas » |
| **Deuxième doigt ignoré au-delà de deux** | Sans cette protection, changer de doigt en cours de geste ferait bondir l'image à la nouvelle position |
| **Les bornes sont appliquées EN CONTINU** | Une image qu'on laisserait sortir puis qu'on ramènerait d'un coup ferait apparaître un trou dans le masque — exactement ce que le recadrage promet de ne jamais montrer. Pas de caoutchouc : le rebond d'iOS a sa place sur un défilement, pas sur une découpe dont le résultat serait faux |

#### La source est un fichier **ou** une URL (version `0.75.0`)

`RecadragePhoto` prend une prop **`source`** — un `File` sorti de la photothèque, ou
l'**URL d'une photo déjà déposée**. Tout ce qui suit le décodage est identique (le cadre,
les gestes, l'export) : la seule chose qui change est *d'où vient le pixel*, et c'est
`lib/image.js` qui porte les deux chemins.

| Source | Fonction | Ce qu'elle doit gérer en plus |
|---|---|---|
| `File` | `chargerImage` | la révocation de l'URL d'objet, échec compris |
| `string` | `chargerImageDepuisUrl` | **le CORS** — voir ci-dessous |

> ### Deux pièges, et le second est invisible à la lecture
>
> 1. **`crossOrigin = "anonymous"` se pose AVANT `src`.** Sans lui, l'image *altère* le
>    canvas où on la dessine : `toBlob` lève une `SecurityError`, et le recadrage échoue
>    **au moment de confirmer**, pas au chargement — donc après que le joueur a composé son
>    cadrage. Le compartiment répond bien `Access-Control-Allow-Origin: *` ; l'attribut est
>    la moitié de l'accord que le navigateur exige, le serveur en porte l'autre.
> 2. **L'URL reçoit un paramètre jetable** (`&cors={horodatage}`). La même photo vient
>    d'être affichée par l'en-tête, donc elle est dans le cache **sans** en-tête CORS, et
>    Safari sert cette réponse sans rejouer la requête : le canvas serait altéré par une
>    image pourtant servie par notre propre projet. Le coût est un téléchargement de moins
>    de deux cents kilo-octets, sur un geste explicite.

**`onChoisirAutre` n'est offert que lorsque la source est une URL.** Quand elle est le
fichier qu'on vient de choisir, « choisir une autre photo » ne remplacerait rien qui ait
été enregistré — le bouton « Annuler » dit déjà cela.

> **Les locales `source` du composant ont été renommées `pixels`.** `dessiner` et
> `recadrer` nommaient ainsi l'image déjà décodée ; la prop du même nom désigne son
> ORIGINE. Deux choses différentes sous un même nom dans un même fichier, c'est une
> confusion qui finit par produire un bug qu'on ne relit pas.

> **La géométrie est sortie du composant.** `echelleMinimale`, `bornerDecalage` et
> `carreVisible` vivent dans `lib/image.js` : ce sont des fonctions pures de quelques
> nombres, là où les vérifier dans le composant demanderait de monter un DOM et de rejouer
> des appuis, ce que le projet n'outille pas. Même motif que `lib/pronostics.js` (§5).
>
> La propriété qui compte se vérifie ainsi en une ligne : **le carré retenu ne sort jamais
> de l'image**, quel que soit le couple zoom/décalage. C'est elle qui garantit qu'aucun
> bord noir n'apparaît dans le masque.

> ### `--scale-large` — le seul jeton d'échelle du projet
> Introduit ici, avec la première surface modale. **Ce n'est pas un fork** : c'est le nom et
> la valeur (0,96) que la planche du skill Transitions.dev donne à l'ouverture et à la
> fermeture d'une modale. Les retours d'appui gardent les leurs (`pressable`,
> `pressable-large`) — ils décrivent un doigt posé, pas une surface qui arrive.
>
> Ouverture `--duration-fast`, fermeture `--duration-quick`, courbe `--ease-smooth-out` :
> l'usage exact que la table des jetons leur donne. **La sortie emprunte le chemin de
> l'entrée** — la surface se referme avant de rendre la main, y compris à la confirmation,
> ce que le composant obtient en différant l'appel de `dureeCss("--duration-quick")`.
> `transform-origin` reste au centre : c'est la seule exception à la règle d'ancrage des
> popovers, et elle vaut pour toute modale.

### `SectionAdmin` — deux interrupteurs, une seule rangée

La section porte **deux** bascules depuis la version `0.44.0` : « Mode admin actif » et
« Mode prévisualisation », la seconde subordonnée à la première et montée à l'intérieur de
ce que la première commande.

> **La rangée est écrite une seule fois** — le composant `Bascule`, dont
> `BasculeModeAdmin` et `BasculePrevisualisation` ne sont que deux habillages. Deux rangées
> écrites séparément auraient divergé au premier ajustement, et le second interrupteur
> aurait cessé de se lire comme un interrupteur. Les couleurs mesurées (pouce blanc à
> 3,41:1 sur `secondaire/60`, 10,88:1 sur `primaire`) vivent donc à un seul endroit.

### `Repli` — une région qui se replie **et quitte le DOM**

Introduit en version `0.46.0` pour Coque et Ailerons, que le profil retire dès qu'un skin
d'écurie est actif (`docs/decisions.md` §17). Le composant est générique : il prend
`visible` et des enfants.

**Second consommateur en version `0.66.0`** : la zone vide « Ajoute jusqu'à 3 paris
bonus » de l'écran de saisie, qui coiffe la liste tant qu'aucun bonus n'est retenu. Même
raison qu'au profil, et c'est la seule qui vaille ici : retirée d'un `&&`, elle
emporterait sa centaine de pixels à l'image suivante et toute la liste sauterait sous le
doigt qui vient d'ajouter son premier pari.

> **L'écart avec ce qui suit le repli est un rembourrage porté À L'INTÉRIEUR, jamais un
> `gap` sur le conteneur.** Un `gap` survit à une hauteur nulle : il laisserait une bande
> résiduelle qui disparaîtrait d'un coup au démontage — c'est-à-dire par un saut, le
> défaut même que le repli est là pour éviter. Même leçon que le rembourrage de
> `.t-repli-inner`, qui ne doit jamais monter sur la piste.

| Ce qu'il fait | Comment |
|---|---|
| Anime une hauteur inconnue | `grid-template-rows: 0fr → 1fr`, **aucune mesure en JS** |
| Monte fermé puis ouvre | `requestAnimationFrame` — ouvrir dans le rendu du montage ne transitionnerait pas, le navigateur n'ayant jamais peint l'état de départ |
| Démonte pour de bon | `setTimeout` sur `dureeCss("--acc-collapse")` |

> ### `.t-repli` reprend les jetons de l'accordéon, mais **jamais son sélecteur**
> Les règles de `.t-acc` emploient un combinateur de **descendance**
> (`.t-acc[data-open="true"] .t-acc-panel`). Envelopper les deux `SelecteurCouleur` — qui
> sont eux-mêmes des `.t-acc` — dans un `.t-acc` ouvert **ouvrirait leurs grilles de
> couleurs avec le sien**. D'où un sélecteur à part, dont les règles descendent en enfant
> **direct**, et qui **n'ajoute aucun jeton** : `--acc-expand`, `--acc-collapse` et
> `--acc-ease` sont ceux de l'accordéon.

> **La durée du démontage est lue dans la feuille compilée**, jamais recopiée en constante.
> Une constante JavaScript et un jeton CSS divergent au premier ajustement, et le symptôme
> serait discret — des enfants retirés une image trop tôt, donc un repli qui se termine par
> un saut.

**Ni `opacity: 0`, ni `hidden`, ni `disabled`** : un réglage sans effet qui reste tabulable
et lisible au lecteur d'écran est pire qu'un réglage absent.

### `BandeauPrevisualisation` — la pastille de statut

Montée dans `App.jsx` **hors de `<Routes>`**, comme `NavBarre` et pour la même raison
structurelle : `Ecran` porte un `transform`, qui ferait de lui le bloc conteneur de tout
`position: fixed` posé à l'intérieur — la pastille défilerait avec la page.

| Point | Valeur |
|---|---|
| Montage | seulement si `modeAdmin` — un membre ordinaire ne l'a jamais dans son DOM |
| Visibilité | `data-actif`, piloté par `modePrevisualisation` |
| Interaction | **aucune** : `pointer-events: none`, donc pas de cible 44 × 44 à tenir |
| Place | bas gauche, au-dessus de la barre — les deux autres coins sont pris par l'en-tête |
| Barre ou non | `barreVisible` de `lib/navigation.js`, **jamais une seconde liste d'écrans** |
| Contraste | `primaire` sur `materiau-chrome` : 10,88:1 sur blanc, **5,48:1** sur le noir de Las Vegas |

La position, la hauteur de barre et la transition vivent dans `index.css`
(`.bandeau-previsualisation`) : trois `calc()` sur les zones sûres et sur `--spacing-nav`
que des valeurs arbitraires Tailwind rendraient illisibles. Le JSX ne garde que le matériau,
l'encre et la typographie.

> **La transition porte sur `translate`, pas sur `transform`.** C'est le piège déjà
> documenté sur `.t-bascule-pouce` : en Tailwind 4 les utilitaires de translation écrivent
> la propriété indépendante `translate`, et transitionner `transform` ne ferait
> rigoureusement rien.

### `useDonnees` — `setDonnees` vs `remplacer`

| Fonction | Écrit l'état | Écrit le cache |
|---|---|---|
| `setDonnees` | oui | **non** |
| `remplacer` | oui | **oui** |

> **`setDonnees` ne sert qu'aux mises à jour optimistes que la réponse serveur confirmera
> de toute façon** (la bascule d'un favori). Toute écriture durable passe par `remplacer` :
> sinon le cache garde la version d'avant et c'est **lui** qui est servi au retour sur
> l'écran. Ce défaut a existé (voir `bugs-connus.md`).

### `origineRetour` — deux clés à ne pas confondre

| Clé | Sens |
|---|---|
| `retour` | où va **mon** bouton de retour |
| `origine` | ce que je **rends** à cet écran en y retournant |

**La seconde n'est pas un raffinement** : sans elle la chaîne se casse au premier rebond —
calendrier → cotes → pronos → retour → cotes → retour → **accueil**.

Le chemin reçu est **validé** (`/…` seulement) : l'état de navigation survit à un
rechargement, et une URL absolue glissée là ferait du bouton de retour une sortie vers
l'extérieur. Une valeur invalide retombe silencieusement sur le défaut — un bouton de
retour doit toujours mener quelque part.

### Les clés de cache — fabriquées, jamais écrites en dur

`cleAccueilGp`, `cleClassement`, `cleCalendrier`, `cleResultats`, `cleProfil`, `cleMesGp`
sont **exportées** et employées par tous leurs consommateurs.

> **Deux chaînes écrites en dur divergent au premier renommage, avec un symptôme discret** :
> un bouton proposant encore « Pronostiquer » juste après l'enregistrement, parce que
> l'écran qui oublie le cache et celui qui le lit ne fabriquent plus la même clé.

**Toute clé porte l'identifiant du compte** — deux personnes qui se relaient sur le même
téléphone ne doivent jamais voir les données de l'autre. `classement` porte en plus un
marqueur de version (`:v2:`), placé **après** l'identifiant pour que
`oublierCachePrefixe("classement:<profil>:")` continue de tout balayer.

**Les caches sont invalidés après création, adhésion, départ, modification de voiture et
changement de photo** — `MonProfil` porte pour cela une fonction unique,
`oublierMesApparitions`, qui balaie `classement:` **et** `resultats:` : la voiture comme la
photo se peignent aux deux endroits, et deux effacements écrits séparément auraient fini
par en oublier un. C'est le défaut qu'avait la version `0.49.0`, où seul `classement:`
était balayé après un changement de livrée —
sans quoi le retour sur l'accueil semblerait avoir perdu le championnat. L'accueil, la
liste des championnats et le calendrier global **partagent `championnats:{profil}`** :
passer de l'un à l'autre n'attend rien, et une adhésion les invalide tous les trois.

### `useIdentiteCourante` — jamais le jeton, jamais le cache

`useAuth().pseudo` lit `user_metadata`, une copie **figée à l'inscription** qui vit dans le
jeton. Un `update` SQL ne la change pas, et une session se rafraîchit indéfiniment.

Trois décisions : **aucun cache** (il réintroduirait la valeur périmée) ; **à chaque
montage**, pas une fois par session ; **repli sur le jeton**, jamais sur le vide.

> **Il rend le pseudo ET la photo depuis la version `0.52.0`** — le hook s'appelait
> `usePseudoCourant`, son chargeur `chargerPseudo`. La pastille de la barre d'accueil porte
> désormais la photo du compte connecté, et elle la prend dans **la même ligne, la même
> requête, la même politique RLS** : une colonne ajoutée à un `select` déjà indexé sur clé
> primaire coûte zéro aller-retour. Un second chargeur — ou un `chargerProfil` complet passé
> par Railway — aurait fait payer un réveil de serveur au premier écran de l'app pour une
> vignette de 42 pixels.
>
> **Le jeton ne sert de repli qu'au pseudo.** Il ne porte aucune copie de la photo, même
> périmée : tant que la base n'a rien dit, la pastille montre l'initiale, qui est de toute
> façon l'état par défaut de tout compte.

`chargerEstAdmin` suit la même règle mais **le sens du doute s'inverse** : tout échec rend
`false`. Une section d'administration affichée à tort ne vaut rien.

---

## 6. Composants en place, non montés

Convention du projet : **du code déjà écrit et vérifié, gardé pour le jour où il redevient
la bonne réponse.**

| Composant | Pourquoi gardé |
|---|---|
| `BoutonsOAuth` (`OAUTH_ACTIF = false`) | repasser à `true` suffit à tout réafficher |
| `ApercusApp` | poser `image` sur chaque entrée et remonter le composant |
| `TraceCircuit` | vignettes de 20 × 32 px |
| `Calendrier` (l'écran d'un championnat) | plus d'entrée depuis le championnat (`0.53.0`), route conservée : son mini-classement par Grand Prix n'existe nulle part ailleurs |

> ### La convention a payé : `Onglets` est monté (version `0.53.0`)
>
> Il a été écrit pour les marchés de la maquette 08, retiré à la refonte de la saisie, et
> gardé « pour le jour où il redevient la bonne réponse ». Ce jour est arrivé sans qu'Unibet
> ouvre dix marchés : l'écran **Résultats par Grand Prix** doit choisir parmi vingt-quatre
> Grands Prix, ce qui est exactement la question qu'il résout — un jeu d'options qui déborde
> la largeur d'un iPhone, une seule active, et celle qu'on vient de choisir ramenée sous les
> yeux. **Zéro ligne de CSS ajoutée, zéro jeton de mouvement nouveau.**

> **Le retour anticipé de `BoutonsOAuth` est placé APRÈS les hooks**, jamais avant : React
> interdit un `return` qui court-circuiterait `useState`.

### `Verdict` et `PastillePoints` — deux moitiés d'une même phrase

Les deux vivent dans `ecrans/ResultatsGp.jsx` et sont **exportées**, parce que les deux
accordéons de pronostics du projet — celui des résultats d'un Grand Prix et celui des
résultats par Grand Prix — affichent la même donnée sur la même ligne.

`Verdict` a été partagée en `0.53.0`, `PastillePoints` en `0.54.0` : jusque-là son bloc
était **recopié à l'identique** dans les deux écrans, et il disait le contraire de ce qu'il
montrait.

| État | `PastillePoints` | `Verdict` | Contraste |
|---|---|---|---|
| réussi (`> 0`) | vert sauge, encre blanche | coche vert sauge sur vert sauge 15 % | 4,86:1 · 4,01:1 |
| raté (`0`) | bordeaux, encre blanche | croix bordeaux sur bordeaux 10 % | 10,88:1 · 8,94:1 |
| en attente (`null`) | beige, encre marron | horloge grise sur beige | 9,32:1 |

> **Le succès était le seul des trois à ne pas se voir.** L'aplat plein bordeaux marquait
> le pronostic **réussi**, et le raté comme le non-jugé prenaient tous deux le même
> bordeaux sur beige : toute la colonne était rouge, le succès y était l'état le plus
> sombre, et **`null` était indistinguable de `0`** — la seule distinction que la règle 4.1
> interdit de perdre. `Verdict`, à côté, la tenait seule.

> **Le beige de l'attente n'est pas un troisième verdict, c'est l'absence de verdict.** Il
> porte le nombre de points **potentiels** ; le peindre en rouge annoncerait un échec qui
> n'a pas eu lieu. Même arbitrage que le « en jeu / gagnés » de la ligne au-dessus.

**Aucune teinte nouvelle n'entre** : le vert sauge est celui que le design system emploie
déjà pour dire « c'est acquis » — le bloc « pronostics enregistrés » du récapitulatif et la
pastille « Terminé » du calendrier.

Le bundler élimine le JSX devenu inatteignable : les chaînes concernées sont **absentes du
bundle de production**.

---

## 7. Accessibilité

- **Tout effet de profondeur est `aria-hidden` et `pointer-events-none`** : voile,
  surcouche, lueur, damier, tracé, fantôme de numéro.
- **Un SVG décoratif porte aussi `focusable="false"`** — sans quoi il ajoute un arrêt de
  tabulation muet (six sur un écran de calendrier).
- **Un SVG qui porte le nom du produit est du CONTENU** : `role="img"` +
  `aria-label`. Le bandeau du logo l'a, l'icône carrée non — sauf servie seule.
- Les nombres rendus deux fois (fantôme + lisible) : le fantôme est `aria-hidden`.
- Une attente est un **squelette**, jamais un texte. Les issues d'action sont annoncées
  par `role="alert"`, les attentes par `role="status"` (**qui ne vole pas le focus**).
- **`aria-current="page"`** sur l'onglet courant de la barre, `aria-label` sur la barre
  elle-même. Un seul `aria-current` à la fois.
- **`aria-busy`** sur le bouton qui a lancé une action, avec son libellé d'attente —
  **plutôt que de le faire disparaître**.
- **`aria-pressed`** sur les cases d'un sélecteur (livrées, skins), `role="switch"` +
  `aria-checked` sur un interrupteur, **dont le libellé dit l'état** au lieu de le laisser
  deviner à la couleur seule.
- Un compteur dont l'icône seule ne dirait rien est **nommé en `sr-only`**.
- Les éléments cliquables gardent **44 px**, absorbés par des **marges négatives** là où
  elles déplaceraient le calage — sans elles, chaque rangée de cote gagnerait 26 px.

---

## 8. Les photos — une pastille, un carré, un juge

Version `0.50.0`. Trois fichiers, et chacun répond à **une** question.

| Fichier | La question dont il est propriétaire |
|---|---|
| `composants/Pastille.jsx` | comment représente-t-on un **joueur** dans un rond ? |
| `composants/PhotoChampionnat.jsx` | comment montre-t-on la photo d'un **championnat** ? |
| `lib/stockage.js` | ce fichier est-il acceptable, et où va-t-il ? |
| `lib/usePhoto.js` | cette image est-elle chargée ? |

### Modifier la photo d'un championnat (version `0.75.0`)

Jusque-là une photo de championnat se posait **à la création, et jamais plus**. Elle se
change et se retire désormais depuis l'écran du championnat, **par son créateur seul**.

| Question | Propriétaire |
|---|---|
| Qui a le droit d'écrire cette photo | **`PATCH /championnats/{id}`** — relit `cree_par` à partir du jeton, `403` sinon |
| Qui voit le contrôle | `ecrans/Championnat.jsx` — `estCreateur`, un affichage, **jamais une autorisation** |
| À quoi ressemble le contrôle | `composants/EnTeteEcran.jsx` — `onPhoto` fait de la photo un bouton |
| D'où vient le pixel à recadrer | `lib/image.js` — fichier **ou** URL déjà déposée |
| Où va le fichier, et où va l'URL | `lib/stockage.js` puis l'API — les deux chemins d'`architecture.md` §3 |

**Le geste d'entrée dépend de ce qui existe déjà**, et c'est le seul point de conception
de cette version : sans photo, il n'y a rien à recadrer et la photothèque s'ouvre ; avec
une photo, le recadrage s'ouvre **sur elle** — refaire son cadrage est le geste le plus
fréquent une fois la photo posée, et la photothèque reste à un doigt dans le recadrage
lui-même. Ouvrir la photothèque d'abord obligerait à choisir un fichier pour découvrir
qu'on voulait seulement recadrer celui qui est déjà là.

> **Le cadre porte le voile, la pastille porte le sens.** Le bouton est un carré de 72 px
> teinté `ton.surfaceForte` sur lequel la photo se pose, plus une pastille blanche à encre
> bordeaux portant l'appareil photo — **la même qu'au profil**, un geste ne s'apprenant pas
> deux fois.
>
> **Le voile est sur le bouton, pas sur une doublure conditionnelle**, et ce n'est pas une
> économie de balise : `PhotoChampionnat` s'efface aussi quand l'objet a disparu du
> stockage (`cassee`). Écrit en `photo ? … : …`, le cadre se viderait alors entièrement et
> le bouton perdrait toute silhouette — exactement le cas où le créateur en a le plus
> besoin, puisque c'est celui où il doit reposer une photo.
>
> **Le contraste se mesure.** La pastille blanche vaut **10,88:1** sur les six aplats de
> championnat. Le voile, lui, ne descend jamais sous le plancher de 3:1 mais n'y arrive
> qu'à **3,03:1** sur le vert sauge (et 3,24 sur le terracotta) : trop juste pour un
> élément qui dirait à lui seul ce que fait le bouton. D'où la répartition ci-dessus — le
> cadre est une silhouette, la pastille est le message.

**L'ordre des opérations ne s'invente pas, il est déjà écrit au profil** : dépôt puis
enregistrement de l'URL pour poser (l'inverse laisserait en base l'adresse d'un objet
inexistant) ; enregistrement puis effacement du stockage pour retirer (c'est la colonne
qui décide de ce qui s'affiche, et un objet orphelin ne se voit nulle part).

#### Trois écrans montrent cette photo, et aucun ne se recharge

L'en-tête du championnat, la carte de l'accueil et la liste des championnats. Les deux
derniers **partagent une seule entrée de cache** (`championnats:{profil}`) : c'est le même
chargement, donc la même clé, et il n'y a qu'un endroit à retoucher pour les deux.

> **On retouche, on ne périme pas.** `oublierCache` marcherait, mais l'accueil repartirait
> alors **sans rien à montrer** et attendrait le réveil de Railway pour une photo de
> soixante-douze pixels — exactement ce que le cache *stale-while-revalidate*
> d'`architecture.md` §9 existe pour éviter. D'où **`modifierCache(cle, transformation)`**
> dans `lib/useDonnees.js` : seule la colonne qui a changé est réécrite, sur la seule ligne
> concernée. Une clé absente ne crée rien — une liste inventée à partir de rien serait lue
> au montage suivant comme si elle venait du serveur.
>
> Sur l'écran lui-même, c'est **`remplacer`** et non `setDonnees` : ce dernier ne touche que
> l'état React, et le cache relu au montage suivant ressortirait l'ancienne photo (§5).

> **Un seul état porte tous les échecs de photo de cet écran** — celui transmis par la
> création, et ceux de la modification faite ici. C'est la même phrase, au même
> emplacement, pour la même chose ; deux états auraient fini par s'afficher l'un sous
> l'autre.

> **La photo est entrée DANS `Pastille`, pas dans un `Avatar` posé à côté.** Cinq écrans
> posent la même question — accueil, classement, les deux profils, résumé d'un GP. Un
> composant concurrent aurait laissé cinq appelants à convertir un par un, et celui qu'on
> aurait oublié serait resté aux initiales sans que rien ne le signale.

> **`photo` absente n'est pas un cas dégradé.** Les initiales sur teinte dérivée du pseudo
> distinguent, sont stables d'un écran à l'autre, et se lisent à 36px. Elles restent
> l'affichage de tout compte qui n'a rien déposé.

> ### La règle « au moins une photo », et pourquoi elle vaut aux trois endroits
>
> Le classement d'un championnat et le résumé d'un Grand Prix posent la même question
> **une fois pour toute la liste** : quelqu'un a-t-il une photo ? Elle décide de la
> **présence** de la colonne, jamais de son contenu.
>
> **La vue piste ne la pose plus** (version `0.52.0`) : elle n'a pas de colonne à faire
> apparaître. Son cockpit existe sur chaque voiture, avec ou sans photo — voir ci-dessous.
>
> Posée ligne par ligne, elle donnerait une liste ébréchée — certaines rangées avec une
> pastille, d'autres sans. Jamais posée, un championnat où personne n'a de photo gagnerait
> une colonne d'initiales posées **à côté du pseudo qu'elles abrègent** : la même
> information deux fois, et quarante-huit pixels pris au seul texte de la rangée.
>
> Avec elle, l'écran d'un championnat sans photo est **exactement** celui d'avant cette
> version, au pixel près.

### Sur la piste : DANS le cockpit, jamais posée dessus

**Le disque noir du casque porte la photo du membre** (version `0.52.0`). Elle y est
découpée par un `<clipPath>` circulaire, dans le SVG même, et à défaut c'est l'initiale sur
la teinte du membre — la même que celle de sa pastille au classement, `teinteMembre` étant
désormais le seul propriétaire de cette question (`lib/couleurs.js`).

> ### La géométrie est mesurée, et la onzième livrée n'est pas comme les dix autres
>
> `geo.cockpit` porte les **coordonnées absolues** du disque, extraites **par script** des
> formes de `VoituresEcuries.jsx`. Dix livrées peignent leur casque avec un `<circle>` ;
> **Audi seule avec un `<path>`**, dont le rayon se lit dans l'arc de fermeture et le centre
> à un rayon du point de départ. Aucune lecture à l'œil ne l'aurait vu.
>
> Les douze dessins tombent sur le même point relatif — 70,68 sur 141,11 en largeur, 171,13
> sur 288,09 en hauteur, rayon 20,41 — et c'est normal, c'est le même dessin douze fois
> repeint. Ils sont malgré tout écrits **un par un** : une fraction commune serait une
> tranche arithmétique, et la première livrée dont le casque bougerait la démentirait en
> silence. Même règle que les `viewBox` (§4).

| Point | Pourquoi |
|---|---|
| **Dans le SVG, pas en HTML posé dessus** | La photo occupe une place que le dessin prenait déjà. Elle ne coûte **pas un pixel** de zone de jeu |
| **Peinte APRÈS le corps** | Un SVG n'a pas d'autre `z-index` que l'ordre de document (§4). Peinte avant, elle passerait sous le casque |
| **L'identifiant du masque vient de `useId`** | Seize voitures coexistent, chacune avec son propre `clipPath`. Un identifiant en dur les ferait toutes pointer vers le premier |
| **`usePhotoDetachee`, pas `usePhoto`** | Un `<image>` SVG est un `SVGImageElement` : ni `complete`, ni `naturalWidth`. Voir ci-dessous |
| **L'initiale prend `encreSurAplat`** | Et non `encreSur`, qui rendrait du blanc sur l'amber. Voir plus bas |

> ### Ce que la version `0.52.0` a retiré, et pourquoi c'est un gain de place
>
> La `0.50.0` posait une pastille **au-dessus** de la voiture, la `0.51.0` une photo dedans.
> Toutes deux réservaient trente pixels de coiffe **à tout le championnat** dès qu'un seul
> membre avait une photo : l'échelle des scores se tassait d'autant, au bénéfice d'une
> rangée de ronds. `coiffeDesVoitures`, `HAUTEUR_AVATAR`, `ESPACE_AVATAR` et le paramètre
> `coiffe` des trois passes sont partis avec — ce n'est pas du code éprouvé mis de côté
> (§6), c'est une correction dont il ne reste rien à corriger.
>
> **La piste dessine donc de nouveau l'échelle d'avant les photos, au pixel près.**
>
> Le cockpit fait **15,04px de diamètre** quand la voiture est à sa taille pleine (52px), et
> moins dans un groupe serré. C'est petit pour un visage, et c'est le prix de l'intégration
> au dessin : une pastille plus grande n'existe qu'en la posant à côté, ce qui est
> exactement ce qui coûtait la place.

### `usePhoto` — le défaut que `onLoad` seul ne voit pas

Une image **déjà en cache** est décodée avant que React n'ait posé son gestionnaire :
l'événement `load` part dans le vide, `onLoad` n'est jamais appelé, et une photo qui
s'anime en opacité reste **invisible pour toujours**. Ce n'est pas un cas de bord — c'est
le cas ordinaire dès la deuxième visite d'un écran.

Le remède est une **fonction de référence** : React l'appelle à l'entrée dans le DOM, et
`naturalWidth > 0` dit alors si le pixel est déjà là. `complete` seul ne suffirait pas — il
vaut `true` pour une image en échec aussi.

L'URL est retenue dans l'état et comparée **pendant le rendu** : changer de photo change
l'URL (elle porte un horodatage, voir `database.md` §9), et sans cette comparaison la
nouvelle image hériterait du `chargee` de l'ancienne. Une réinitialisation dans un effet
laisserait passer une image d'écart, donc un clignotement.

> ### `usePhotoDetachee` — le même défaut, sous une autre forme
>
> Le remède ci-dessus repose sur `complete` et `naturalWidth`, deux propriétés d'un
> `HTMLImageElement`. Un `<image>` SVG est un `SVGImageElement` : il n'en a **aucune des
> deux**, donc aucun moyen de lui demander si le pixel est déjà là. On resterait suspendu à
> un `load` qu'on ne peut pas savoir passé, et la photo du cockpit tiendrait `opacity: 0`
> indéfiniment — exactement le défaut d'origine.
>
> La question est donc posée à un **élément détaché**, jamais rendu : le navigateur sert la
> même URL depuis le même cache, et l'objet, lui, répond à `complete`. **Aucun second
> téléchargement.** Le hook rend le même couple `chargee` / `cassee`, et `cassee` couvre le
> même cas — une URL en base dont l'objet a disparu du stockage, où le cockpit redevient un
> disque teinté plutôt qu'un trou.

### Le mouvement : un fondu, aucun jeton nouveau

`.t-photo` transitionne **l'opacité seule**, avec `--duration-fast` et
`--ease-smooth-out` — deux jetons qui existaient déjà. Pas d'échelle : la pastille est
déjà là, ronde, à sa taille, avec son initiale dedans ; c'est son **contenu** qui se
substitue. Une photo montant de `scale(0.95)` se lirait comme un second objet arrivant
par-dessus le premier.

`.t-photo-envoi` pose un flou pendant que le fichier monte, et il porte sur le
**conteneur**, pas sur l'image : au premier dépôt il n'y a encore aucune image à flouter,
ce sont les initiales qui doivent dire que quelque chose se passe.

Sous `prefers-reduced-motion`, **le fondu reste** (une opacité ne déplace rien) et sa durée
tombe à `--duration-quick` ; le flou d'envoi se pose d'un coup.

### L'encre d'une pastille était fausse sur une teinte de membre sur quatre

`Pastille` écrivait `text-white` **en toutes lettres**. Sur l'amber `#E8A020`, une des
quatre teintes que la table distribue, le blanc ne vaut que **2,22:1** quand `#1A1A1A` y
monte à 7,86:1 : une initiale sur quatre était illisible depuis l'origine, et sur la moitié
d'entre elles personne ne l'avait vu parce que la plupart des comptes tombent sur les trois
autres teintes.

> **`encreSurAplat` et non `encreSur`, et l'écart n'est pas cosmétique.** Le second compare
> une **luminance** à 0,45 ; l'amber vaut 0,424, il passe donc juste sous le seuil et rend
> du blanc. Le premier mesure le **contraste** et garde le blanc tant qu'il tient 3:1. Les
> deux helpers existent tous les deux dans le design system §5, et c'est le premier qui
> répond à « quelle encre sur cet aplat ». `encreSur` reste en place pour les deux textes
> peints sur la carrosserie, où il n'a jamais rencontré l'amber.

Mesuré après correction, pour les quatre teintes : `#800111` 10,88:1 · `#E8A020` 7,86:1 ·
`#543925` 10,56:1 · `#5A000C` 14,58:1. Le casque noir de la planche, quand aucun membre ne
l'habite, tient 20,84:1.

### Écart assumé sur le rayon

La demande prescrivait `12px` sur la carte de l'accueil. L'échelle des formes du design
system ne connaît pas le 12 : elle va de 24 (bloc) à 14 (`rounded-champ`, « champs et
petits éléments »), et « tout écran puise dans ces jetons, jamais dans des valeurs en dur ».
La carte prend donc **`rounded-champ`**, à deux pixels de la valeur demandée ; l'en-tête du
championnat prend `rounded-widget`, qui vaut exactement les 16 demandés. Un
`rounded-[12px]` aurait ouvert une sixième valeur de rayon dans un projet qui en compte
cinq, pour un écart invisible à cette taille.

---

## 9. Résultats par Grand Prix — les paris de chacun (version `0.53.0`)

`ecrans/ResultatsChampionnat.jsx`, atteint depuis l'écran d'un championnat, à la place où
vivait l'entrée « Calendrier ». Il répond à la seule question que rien ne montrait :
**qu'est-ce que les autres ont joué ?** La saison Grand Prix par Grand Prix, elle, est déjà
l'onglet Calendrier de la barre basse.

| Ce qui est lu | Par où | Pourquoi |
|---|---|---|
| La liste des Grands Prix | `GET /championnats/{id}/calendrier` | **La clé de cache de l'écran `Calendrier`, à l'identique** : passer de l'un à l'autre n'attend rien |
| Les pronostics d'UN Grand Prix | `GET /grands-prix/{gp}/pronostics/championnat/{id}` | Existe depuis l'étape 5 et sert exactement cette liste, membres sans pronostic compris |

> **Le sélecteur du haut n'est pas un choix d'interface, c'est la forme de la donnée.** La
> route sert **un** Grand Prix à la fois ; une saison entière demanderait vingt-quatre
> allers-retours Railway en série, sur un écran atteint depuis un championnat. Le sélecteur
> est la conséquence, pas la cause.

**La clé du second chargement porte le Grand Prix** (`pronos-gp:{profil}:{championnat}:{gp}`).
Changer d'option change donc de clé, et `useDonnees` ressert instantanément un Grand Prix
déjà consulté au lieu de le redemander — c'est ce qui rend le sélecteur agréable à parcourir
sur un réseau mobile.

**Le Grand Prix choisi se pose une fois et ne bouge plus** (`précédent ?? gpParDefaut(…)`).
Ce n'est pas défensif : le cache *stale-while-revalidate* rejoue le chargeur en arrière-plan,
et sans cette garde un aller-retour lent ramènerait le sélecteur sur le Grand Prix par défaut
pendant que le joueur en lit un autre.

### Un membre sans pronostic n'est pas dépliable

Sa rangée n'est pas un `<button>` mais un `<li>` inerte, et elle dit « Rien joué » **sur la
ligne**. Un chevron qui ouvrirait sur rien est une promesse fausse ; et l'information est
précisément celle qu'on vient chercher avant la fermeture des pronostics, donc elle n'a pas
à se mériter d'un appui. La place du chevron est en revanche **tenue** par une boîte vide :
sans elle, le pseudo de ces rangées s'étendrait de seize pixels de plus que les autres et la
colonne cesserait d'être une colonne.

### Le total porte le mot qui dit lequel des deux c'est

Avant la course, c'est ce que la saisie **peut** rapporter ; après, ce qu'elle **a**
rapporté. Deux nombres du même ordre de grandeur que rien ne distinguerait : d'où
« gagnés » ou « en jeu » sous le chiffre. Le chiffre, lui, reste habillé par
`formaterPoints` — seul propriétaire du « N pts » (règle 4.1) ; seul le qualificatif est
écrit dans l'écran.

### Ce qui ne s'anime pas, et c'est le bon verdict

**Le changement de Grand Prix ne fait aucun fondu.** La liste des membres ne se transforme
pas : elle est remplacée par une donnée qui arrive du réseau, donc il n'y a pas d'« avant »
à faire tenir — c'est le squelette qui occupe l'intervalle. Animer une substitution de
contenu asynchrone serait du mouvement sans changement d'état, exactement le verdict rendu
sur la hauteur d'un en-tête de marché à la version `0.52.0`.

Restent deux mouvements, **tous deux déjà dans le vocabulaire** : la pastille glissante
d'`Onglets` (transitions-dev 16) et l'accordéon `.t-acc` d'une rangée de membre.

---

## 10. La voiture porte la couleur de son membre jusque dans son texte (`0.53.0`)

Trois changements sur `Voiture.jsx`, et le premier est un défaut d'origine.

### Le numéro était tête-bêche depuis toujours

La planche l'écrivait sous `rotate(180)` : c'est la convention d'un vrai museau de Formule 1,
qui se lit depuis la voiture qu'on double. **Toutes les vues de l'app sont des vues de
dessus** — profil, classement, piste, résultats — et le numéro y sortait à l'envers, sur les
douze livrées.

> **Retirer la rotation ne suffisait pas.** Elle ne renversait pas seulement les glyphes,
> elle renversait leur position autour de la ligne de base : sous `rotate(180)` les chiffres
> occupent `[yNumero, yNumero + 0,717 em]`, à l'endroit `[y − 0,717 em, y]`. La ligne de
> base descend donc d'exactement une **hauteur de capitale** (0,717, métrique d'Helvetica),
> et le numéro retrouve **le pixel qu'il occupait**. Vérifié par rendu comparé des deux
> versions, pas seulement par le calcul.
>
> C'est pour cela que le décalage est calculé et non relevé à l'œil : les douze `yNumero`
> sont mesurés séparément (`VoituresEcuries.jsx`), et douze corrections manuelles auraient
> été démenties par la première livrée retouchée.

### `couleurTexte` — et `livreeDuMembre` reste le seul propriétaire

La couleur choisie entre dans **`livreeDuMembre` (`lib/palette.js`)**, pas dans une prop de
plus passée écran par écran : « de quelle couleur est le nom sur cette voiture ? » est la
même question que « quelle est sa coque ? ». Les quatre surfaces qui dessinent une voiture y
passent déjà et la répandent par `{...livreeDuMembre(ligne)}` — un second chemin aurait
laissé le réglage visible sur l'écran de profil et nulle part où quelqu'un d'autre le voit.

**`null` n'est pas une couleur manquante, c'est une couleur non choisie** : les deux textes
reprennent alors l'encre calculée qui contraste avec l'aplat qui leur est propre, et les deux
aplats diffèrent sur neuf des onze livrées. Aucun repli sur `#FFFFFF` nulle part — il rendrait
le numéro invisible sur les quatre teintes claires de la palette.

`aplatDuNumero` et `encreParDefaut` sont exportés d'ici, et ce sont **deux** fonctions :
l'écran de profil mesure le contraste de la couleur choisie contre l'aplat, ce qui demande
l'aplat lui-même ; le rendu ne veut que l'encre.

### Les deux textes s'animent, et `.t-voiture-teinte` est ÉTENDU, jamais forké

Ils vivent désormais dans un `<g className="t-voiture-teinte">`, et le sélecteur de la règle
passe de `:is(path, polygon, rect, circle)` à `:is(path, polygon, rect, circle, text)` — dans
la règle normale **et** dans le bloc `prefers-reduced-motion`. Parcourir la palette repeint
donc le numéro et le pseudo en 200ms, comme elle repeint déjà la coque. Aucun jeton nouveau.

Le groupe est posé **après** le cockpit : dans un SVG, l'ordre de document est le seul ordre
de peinture (§4).

### Le cockpit de l'écran de personnalisation

L'aperçu du profil reçoit `photo` et `teintePilote`, exactement comme la vue piste : même
`clipPath`, même repli sur l'initiale posée sur la teinte de la pastille, même graine
(`profilId`, à défaut le pseudo). C'était le seul écran où l'on règle sa voiture, et le seul
à la montrer sans son pilote.

Le `HeroProfil`, lui, ne le reçoit pas : sa voiture fait 58px de haut, donc un cockpit d'à
peine trois pixels. Une photo qu'on ne peut pas voir n'est pas une photo.

### `IconePilote` délègue, elle ne recopie pas

L'entrée « Résultats par Grand Prix » porte la silhouette de la région x ∈ [322 ; 483,64] de
`assets/logo-02.svg`. Cette forme est **déjà extraite** dans `icones/IconeProfil.jsx` pour
l'onglet Profil : `IconePilote` (`Icones.jsx`) la délègue en lui passant `currentColor`.
Deux jeux de `d` identiques dans deux fichiers, c'est exactement ce que la règle
d'extraction interdit (§4) — la planche a un extracteur, et un seul.

### `IconeEtoileLogo` — l'étoile de `logoV2.svg`

L'état « pas encore ajouté » du bouton de pari bonus (`EtoileFavori.jsx`), là où la version
`0.66.0` mettait un `+`. C'est le **deuxième des quatre dessins** de la planche, et le seul
`<path>` enfant direct de son `<svg>` — ce qui suffit à le désigner au script d'extraction.

| Ce qui a été mesuré | Valeur |
|---|---|
| Boîte englobante réelle, extrema des cubiques résolus | x 150,34 → 223,84 · y 13,55 → 83,89 |
| `viewBox` retenue | `143.09 4.72 88 88` — carré **centré** sur cette boîte |
| Part de la boîte occupée | **83,5 %**, celle que `IconeEtoile` occupe de sa boîte de 24 |

> ### Le tiers arithmétique de la planche a été écarté — écart signalé
>
> La demande prescrivait `155 0 154.91 110.14`, le tiers du milieu d'une planche large de
> 464,91. Ce cadrage **coupe 4,66 unités de la pointe gauche** de l'étoile, la pose 45,37
> unités à gauche du centre et ne lui laisse que 47 % de la largeur de sa boîte. C'est la
> règle 2 de §4 — les `viewBox` sont les vraies boîtes englobantes, jamais des tranches
> arithmétiques — et le même arbitrage que celui déjà tenu par `IconeCreer`.

Le carré de 88 n'est pas serré sur la boîte : à 22px, une étoile pleine bord à bord pèserait
un tiers de plus que le `+` qu'elle remplace. Les 83,5 % la posent au poids optique de
l'autre étoile du projet. L'encre ne bouge pas — `text-secondaire/60`, 3,4:1 mesuré, et un
aplat couvre plus de surface qu'un trait de 2.

**Les quatre références au `+` ont suivi en `0.68.0`.** Le mode d'emploi et la zone vide de
`Cotes.jsx`, la zone vide de `Pronostics.jsx` portent l'étoile et disent « l'étoile ». La
rangée de `Pronostics.jsx` ne recopie plus l'échange d'icônes : elle passe par
`EtoileFavori`.

### `EtoileFavori` — un couple étoile → coche, deux appelants

Le composant possède seul la cellule `t-icon-swap` du pari bonus. Deux props le plient aux
deux contextes, parce qu'une seconde copie du même échange est précisément ce qui a laissé
un `+` dans `Pronostics.jsx` quand `Cotes.jsx` passait à l'étoile.

| Prop | Pourquoi | Qui l'utilise |
|---|---|---|
| `sansBouton` | La rangée de `Pronostics.jsx` **est** le bouton : elle porte l'`onClick`, l'`aria-pressed` et le nom accessible. Un `<button>` de plus dedans serait du HTML invalide. Le signe est alors rendu nu, sans la zone tactile de 44px que la rangée donne déjà. | `Pronostics.jsx` |
| `inverse` | La rangée retenue est **déjà ambre** : un aplat ambre y disparaîtrait. L'aplat devient `texte` et la coche `accent` — 7,9:1 dans les deux sens, l'ambre et l'encre foncée n'ayant pas d'ordre. | `Pronostics.jsx` |

L'étoile ne paraît **que** sur l'état non retenu, donc toujours sur du blanc : son
`text-secondaire/60` à 3,4:1 vaut dans les deux modes, `inverse` ne la touche pas.

> ### Une encre signalée : la zone vide de `Cotes.jsx`
>
> L'étoile de ce bloc garde le `text-accent` que portait le `+` — 2,2:1 sur le blanc du
> bloc, sous le plancher de 3:1. Elle est **décorative** (`aria-hidden`, la phrase juste
> dessous porte seule le sens) et l'ambre est le repère « pari bonus » de l'écran, celui
> des pastilles qui remplaceront ce bloc. La zone vide de `Pronostics.jsx`, elle, montre
> l'étoile à l'encre exacte qu'on va toucher : `text-secondaire/60`, 3,4:1.
