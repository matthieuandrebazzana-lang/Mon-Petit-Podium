# Composants et assets

Les composants importants, leurs responsabilités, et où vivent les SVG.
**Ce n'est pas une liste exhaustive** — seulement ce qui se devine mal à la lecture.

---

## 1. Structure

```
src/
├── App.jsx              routeur + les trois groupes de routes
├── auth/AuthContexte.jsx
├── composants/          réutilisables (37 fichiers)
│   └── icones/          6 icônes extraites de planches SVG
├── ecrans/              un fichier par écran (20)
└── lib/                 accès aux données, formatage, hooks (22)
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
| `Icones` | les variantes `pleine` emploient **`fill-rule="evenodd"`** : la porte de la maison est un **trou dans l'aplat**, jamais un rectangle blanc posé dessus — qui se verrait le jour où le fond n'est plus blanc |

---

## 4. Les planches SVG

**Aucune n'est servie en production.** Tout est extrait **par script** dans un composant
React et part avec le bundle en SVG inline.

> ### Trois règles d'extraction, tenues à chaque fois
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
| `matti.svg` | `SkinsEcuries.jsx` | 11 **pastilles carrées** |
| `06.svg` | `--motif-damier` (data-URI) | vague du damier |
| `voiture.svg` | — | **ancien dessin, remplacé** |
| `logoV2.svg` | — | inutilisé |

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
| `format.js` | **seul endroit qui habille un nombre de points** |
| `couleurs.js` | aplats de bloc, contraste, encres |
| `palette.js` | 20 couleurs de voiture, luminance, `livreeDuMembre` |
| `ecuries.js` | onze écuries, grille 2026 — voir `ecuries.md` |
| `calendrier.js` | `ETATS_GP`, `cotesArretees` — **seule lectrice du statut `cotes_figees`** |
| `calendrier2026.js` | **la liste des GP** — voir `calendrier.md` |
| `navigation.js` | barre, onglets, `origineRetour` |
| `pronostics.js` | marchés, favoris, exclusion croisée |

Trois règles ont été **sorties des écrans** vers `lib/pronostics.js` — `optionsDisponibles`
(exclusion croisée), `enConflit` et `bonusEpingles` (les bonus encore épinglés). Raison :
**le rendu statique n'exécute aucun effet et ne rejoue aucun appui**, donc elles ne
seraient vérifiables qu'en montant un DOM que le projet n'outille pas. Sorties de là, elles
s'éprouvent directement. Même motif pour `VueAdmin`, fonction pure de ses props, séparée de
`SectionAdmin` qui porte l'état.

### `SectionAdmin` — deux interrupteurs, une seule rangée

La section porte **deux** bascules depuis la version `0.44.0` : « Mode admin actif » et
« Mode prévisualisation », la seconde subordonnée à la première et montée à l'intérieur de
ce que la première commande.

> **La rangée est écrite une seule fois** — le composant `Bascule`, dont
> `BasculeModeAdmin` et `BasculePrevisualisation` ne sont que deux habillages. Deux rangées
> écrites séparément auraient divergé au premier ajustement, et le second interrupteur
> aurait cessé de se lire comme un interrupteur. Les couleurs mesurées (pouce blanc à
> 3,41:1 sur `secondaire/60`, 10,88:1 sur `primaire`) vivent donc à un seul endroit.

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

**Les caches sont invalidés après création, adhésion, départ et modification de voiture** —
sans quoi le retour sur l'accueil semblerait avoir perdu le championnat. L'accueil, la
liste des championnats et le calendrier global **partagent `championnats:{profil}`** :
passer de l'un à l'autre n'attend rien, et une adhésion les invalide tous les trois.

### `usePseudoCourant` — jamais le jeton, jamais le cache

`useAuth().pseudo` lit `user_metadata`, une copie **figée à l'inscription** qui vit dans le
jeton. Un `update` SQL ne la change pas, et une session se rafraîchit indéfiniment.

Trois décisions : **aucun cache** (il réintroduirait la valeur périmée) ; **à chaque
montage**, pas une fois par session ; **repli sur le jeton**, jamais sur le vide.

`chargerEstAdmin` suit la même règle mais **le sens du doute s'inverse** : tout échec rend
`false`. Une section d'administration affichée à tort ne vaut rien.

---

## 6. Composants en place, non montés

Convention du projet : **du code déjà écrit et vérifié, gardé pour le jour où il redevient
la bonne réponse.**

| Composant | Pourquoi gardé |
|---|---|
| `BoutonsOAuth` (`OAUTH_ACTIF = false`) | repasser à `true` suffit à tout réafficher |
| `Onglets` | redevient utile quand Unibet ouvre dix marchés |
| `ApercusApp` | poser `image` sur chaque entrée et remonter le composant |
| `TraceCircuit` | vignettes de 20 × 32 px |

> **Le retour anticipé de `BoutonsOAuth` est placé APRÈS les hooks**, jamais avant : React
> interdit un `return` qui court-circuiterait `useState`.

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
