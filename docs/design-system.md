# Design system

À quoi doit ressembler l'application.

> **Portée.** Ce document fixe **la palette et la typographie**, qui ne se négocient pas.
> Le reste — compositions, espacements, ombres, matériaux, animations, hiérarchie — est
> sous l'autorité des skills de design (voir CLAUDE.md pour la règle de priorité et
> l'ordre d'invocation). Les rayons et l'échelle d'espacement sont des **valeurs par
> défaut**, pas des contraintes.

Tout vit dans le bloc `@theme` de `frontend/src/index.css`. **Tout écran puise dans ces
jetons, jamais dans des valeurs en dur.**

---

## 1. Palette

### Couleurs de base — les sept intouchables

| Rôle | Hex | Jeton |
|---|---|---|
| Fond de l'app | `#F5F0EB` | `fond` |
| Principal (rouge profond) | `#800111` | `primaire` |
| Principal foncé | `#5A000C` | `primaire-fonce` |
| Secondaire (marron) | `#543925` | `secondaire` |
| Accent (amber) | `#E8A020` | `accent` |
| Texte | `#1A1A1A` | `texte` |
| Texte secondaire | `#999999` | `texte-doux` |
| Surfaces / cartes | `#FFFFFF` | `surface` |

### Palette élargie — quatre teintes, périmètre borné

| Hex | Jeton |
|---|---|
| `#4A7C59` | `vert-sauge` |
| `#2C4A6E` | `bleu-ardoise` |
| `#C4622D` | `terracotta` |
| `#5C3D7A` | `violet` |

> **Elles ne peignent QUE des aplats de bloc** — en-tête de marché, bloc de pronostic —
> et le texte posé dessus. Jamais un fond d'écran, jamais un texte sur le beige, jamais
> une bordure. Les sept couleurs de base gardent tous leurs rôles.

### Les six teintes de championnat — palette Pantone sombre

| Hex | Jeton | Pantone |
|---|---|---|
| `#1D2941` | `azurite` | Azurite |
| `#2A1F21` | `mure` | Blackberry Syrup |
| `#301729` | `aubergine` | Aubergine Gleam |
| `#54392D` | `terreau` | Potting Soil |
| `#752329` | `tomate-sechee` | Sun-Dried Tomato |
| `#16151D` | `minuit` | Midnight Sky |

> **Elles ne peignent QUE une carte de championnat et l'en-tête de son écran.** Même
> périmètre borné que la palette élargie, et **une liste séparée d'elle** : la couleur
> d'un marché est un repère fixe (rouge = vainqueur), celle d'un championnat sert à
> distinguer des championnats entre eux. Deux questions, deux listes — `COULEURS_BLOC` et
> `COULEURS_CHAMPIONNAT`, toutes deux dans `lib/couleurs.js`.

Six teintes couvrent six championnats distincts ; au-delà, le cycle recommence.
`couleurChampionnat` y puise par **empreinte de l'identifiant**, jamais par le rang dans
une liste — voir `decisions.md` §18.

> ### Le texte reste blanc sur les six, et c'est mesuré
> L'encre blanche y tient de **10,35:1** (tomate séchée) à **18,12:1** (minuit) : aucune
> ne demande l'encre foncée, là où l'amber de la palette élargie l'imposait. Les dérivées
> de `tonalites` gagnent d'autant. **Pire cas de l'encre secondaire à 70 %, sous le damier
> et sous la lueur : 4,97:1 sur le terreau** — au-dessus du plancher AA d'un texte
> ordinaire, quand le terracotta n'y valait que 2,79:1. Le rang à 80 % ne descend jamais
> sous 5,92:1, contre 3,15:1 auparavant.

**`#E8E0D8` (`squelette`)** ne peint jamais qu'une silhouette de chargement.

### Les palettes hors thème

Cinq familles de couleurs vivent **hors du bloc `@theme`**, chacune dans son module, et
partagent toutes le même périmètre : elles ne peignent que l'objet qu'elles décrivent.

| Module | Ce qu'elles peignent |
|---|---|
| `lib/palette.js` | les 20 couleurs de voiture personnalisable |
| `lib/ecuries.js` | fond (9,4 %) et liseré (60 %) d'un widget de cote |
| `composants/DrapeauxGP.jsx` | le fond d'un bloc de Grand Prix |
| `composants/DrapeauxPilotes.jsx` | le lavis de drapeau d'une ligne de classement |
| `lib/livrees.js` | teintes des livrées, **lues dans `ecuries.js`** |

**`teinteMembre` (`lib/couleurs.js`) est une cinquième liste**, et elle ne sort pas du bloc
`@theme` : ce sont **quatre des sept couleurs de base**, dans leur rôle d'aplat, réparties
par empreinte de l'identifiant d'un membre. Elle porte **les deux formes** de chaque teinte
— la classe Tailwind pour la pastille en HTML, le `#rrggbb` pour le cockpit de la voiture
en SVG, où un `fill` n'accepte pas `bg-primaire`. Une seule question, un seul propriétaire.

> **`DrapeauxPilotes` est le seul de ces modules dont les couleurs ne sont pas écrites
> dans le dépôt** : ce sont les seize SVG de `country-flag-icons`. Le périmètre est le
> même que les autres — il ne peint qu'un lavis à 8 % en fond d'une ligne de classement —
> mais le **calcul de contraste ne pouvait pas être dérivé** comme celui de
> `voileNecessaire` : un SVG importé n'expose pas ses bandes. Les seize drapeaux ont donc
> été mesurés **couleur par couleur, par script**, et c'est le noir qui décide (`#EBEBEB`
> composé) : `texte` 14,60:1, `secondaire` 8,86:1, `primaire` 9,13:1, **`texte-doux`
> 2,39:1 — hors de question**. Voir `composants.md` §4.

**Aucune ne peint un fond d'écran, un bouton ou un texte d'interface.** Des tests
vérifient le cloisonnement.

---

## 2. Typographie

**Helvetica Neue** partout. Graisses **400 et 500 uniquement**.

| Jeton | Taille | Graisse | Crénage |
|---|---|---|---|
| `text-titre` | 28px | 500 | −0,02em |
| `text-titre-lg` | 30px | 500 | −0,02em |
| `text-score` | 32px | 500 | −0,025em |
| `text-score-lg` | 44px | 500 | −0,03em |
| `text-corps` | 15px | — | — |
| `text-corps-sm` | 14px | — | — |
| `text-label` | 11px | 500 | **+0,7px**, majuscules |
| `text-label-sm` | 10px | 500 | **+0,7px**, majuscules |

> **Le crénage est spécifique à la taille : négatif sur les grands textes, POSITIF sur
> les petits labels.** Les grands chiffres en ont plus besoin encore que les titres — un
> chiffre n'a ni jambage ni hampe, donc rien qui vienne remplir l'espace.

### La graisse 700 — six exceptions, toutes bornées

Réservée aux **numéros de voiture**. Six écarts explicites, chacun limité à un chiffre :

| Où | Taille |
|---|---|
| Tuiles du compte à rebours (récap) | 30px |
| Tuiles du compte à rebours (saisie) | 48px |
| Quantième d'une carte de calendrier | 64px |
| Points d'un widget de cote | 18px |

Deux tailles hors échelle avec elles : **26px** (nom du GP sur le bloc d'accueil) et
**64px**. Elles n'ont pas de jeton, délibérément.

---

## 3. Formes

| Élément | Rayon | Jeton |
|---|---|---|
| Blocs principaux | 24px | `rounded-bloc` |
| Cartes | 20px | `rounded-carte` |
| Cartes secondaires | 18px | `rounded-carte-sm` |
| **Widgets de cote** | 16px | `rounded-widget` |
| Champs, petits éléments | 14px | `rounded-champ` |

Espacement entre blocs : **12px**. Padding intérieur : **16–20px**.

> **La section 5 du CLAUDE.md proscrit les bordures fines.** Deux exceptions explicites :
> l'encadré « mode d'emploi » du tableau des cotes (une bordure ambre sur fond `#FDF3E0`,
> demandée, et c'est elle qui dit où commence l'encadré), et le **filet de 4px** d'une
> ligne de classement — qui n'est pas une bordure au sens de la règle : c'est un aplat
> posé **à l'intérieur**, pas un trait qui cerne le bloc.
>
> **Ce filet est aussi ce qui sépare deux sections d'un écran** (`TitreSection`, version
> `0.62.0`) : la demande voulait « un séparateur visuel marqué », et le seul trait que la
> palette autorise est celui-là. Le séparateur est donc **l'espace d'abord** — 24px au
> lieu de 12 au-dessus d'un changement de sujet — et le filet ensuite, qui donne à l'œil
> un point d'accroche à gauche du titre. Jamais une règle horizontale.

---

## 4. Élévation

Trois niveaux, plus un. **Un seul principe : plus une surface est grande, plus elle est
épaisse.**

| Jeton | Pour |
|---|---|
| `shadow-carte` | cartes et rangées (`rounded-carte`) |
| `shadow-bloc` | blocs principaux (`rounded-bloc`) |
| `shadow-flottant` | ce qui survole vraiment : barres de navigation et d'action |
| `shadow-aplat` | **les aplats de couleur** |

> **Deux points à ne pas défaire.** Chaque niveau superpose **deux couches** — une ombre
> de contact serrée qui pose l'objet, une ombre ambiante large qui l'éloigne du fond ;
> une seule couche donne l'un ou l'autre, jamais les deux. Et la teinte est le **marron
> `secondaire`** en faible opacité, jamais un noir : une ombre noire sur un fond beige
> tire vers le gris et salit la couleur.

> **`shadow-aplat` existe parce que les trois autres sont réglées pour du blanc.** Sous
> un bloc rouge ou violet, un marron clair ne se voit plus.

**Règle d'attribution** : `rounded-bloc` → `shadow-bloc`, `rounded-carte` →
`shadow-carte`, **`rounded-champ` → rien** (ce sont les surfaces posées *à l'intérieur*
d'un bloc, qui ne cassent jamais leur plan).

**`lueur-haute`** pose un galbe de lumière très doux sur les aplats de couleur — du blanc
à très faible opacité, aucune couleur nouvelle.

---

## 5. Contraste — le calcul, jamais le goût

**C'est la règle de méthode la plus importante de ce document.** Chaque fois qu'un texte
ou un élément graphique est posé sur une surface, le contraste est **mesuré** :

| Cas | Plancher |
|---|---|
| Texte ordinaire | 4,5:1 |
| Grand texte (≥ 24px ou gras ≥ 19px) | 3:1 |
| Élément graphique porteur de sens | 3:1 (WCAG 1.4.11) |

**Les écrans ne choisissent jamais leur encre eux-mêmes.** Trois helpers la calculent :

| Fonction | Rend |
|---|---|
| `encreSurAplat(hex)` | blanc tant qu'il tient 3:1, encre foncée en dessous |
| `encreSurBlanc(couleur)` | la couleur si elle tient **4,5:1** sur blanc, sinon `texte` |
| `tonalites(hex)` | le jeu complet : encre, encre secondaire, surfaces, fantôme |
| `encreSur(fond)` | luminance WCAG → `#1A1A1A` ou `#FFFFFF` |

> ### `encreSur` et `encreSurAplat` ne sont PAS interchangeables
> Les deux rendent une encre, et **l'amber les départage**. `encreSur` compare une
> **luminance** à 0,45 ; l'amber vaut **0,424**, il passe donc juste sous le seuil et rend
> du blanc, à 2,22:1. `encreSurAplat` mesure le **contraste** et bascule sur l'encre foncée
> dès qu'on descend sous 3:1.
>
> **Devant « quelle encre sur cet aplat ? », c'est `encreSurAplat`.** `encreSur` reste juste
> là où il sert — les deux textes peints sur une carrosserie de voiture, qui ne rencontrent
> jamais l'amber. La pastille d'un membre, elle, l'a rencontré : elle écrivait `text-white`
> en dur, et une initiale sur quatre y était illisible (`bugs-connus.md` §19).

> ### L'amber est le cas d'école
> Sur `#E8A020`, le **blanc tombe à 2,2:1** quand `#1A1A1A` monte à **7,9:1**. Toute
> surface amber prend donc l'encre foncée — sans exception, et c'est `tonalites` qui le
> garantit. Un écran qui écrirait `text-white` de mémoire produirait un libellé illisible.
>
> **Corollaire** : l'amber n'existe **que comme aplat**, jamais comme encre — en texte
> sur blanc il ne vaut que 2,2:1.

> ### `#999999` sur le beige ne vaut que 2,0:1
> `texte-doux` convient à côté d'un numéro de version que personne ne lit, **pas à une
> phrase qu'on vient lire**. Le marron `secondaire` la porte à 9,4:1. Corrigé deux fois
> déjà (bandeau de saison, libellé de section des favoris).

> ### Le voile des drapeaux est DÉRIVÉ, jamais écrit à la main
> `voileNecessaire` calcule l'opacité depuis la **bande la plus claire** de chaque
> drapeau, par pas de 0,05. Un drapeau ajouté demain reçoit le bon voile sans que
> personne ne refasse le calcul — c'est ce qui a fait passer les États-Unis de 0,00 à
> 0,45 tout seuls quand leurs treize bandes blanches ont été dessinées.

> ### La règle de vibrance
> Sur un fond changeant, la hiérarchie passe par la **taille et la graisse**, jamais par
> l'opacité : une fois la bande la plus claire ramenée au gris moyen, aucune opacité
> intermédiaire n'atteint 3:1. L'encre secondaire passe alors au **blanc plein en graisse
> 500**, et les surfaces translucides posées dedans passent du blanc au noir.

---

## 6. Matériaux et textures

**`materiau-chrome`** — blanc à 72 %, `blur(24px) saturate(180%)`. Barre de navigation et
barre d'action collée. Le contenu passe **sous** elles et reste deviné. La saturation
compense le lavage des couleurs par le flou.

> **Le matériau d'un en-tête n'apparaît qu'une fois du contenu passé dessous** — c'est le
> *scroll edge effect* : le chrome ne se matérialise que là où il recouvre vraiment quelque
> chose. Une barre translucide posée sur du vide se lit comme un bandeau.
>
> Le **dégradé au-dessus d'une barre collée** relève du même principe : le contenu se
> dissipe en passant dessous au lieu d'être coupé par un trait, que la palette proscrit.
>
> **Le liseré blanc** que le snippet pose sur l'arête haute d'un matériau **n'est pas
> repris** : le design system proscrit les traits fins, et sur une barre déjà blanche il ne
> se verrait pas.

**`--grain-fond`** — bruit gris à **4 %**, en image de fond sur `body`, tuile de 160px.
Trois points : c'est une **image rastérisée** (jamais un filtre vivant ni
`background-attachment: fixed`, que Safari iOS gère mal) ; `stitchTiles="stitch"`, sans
quoi la répétition se voit en damier ; le contraste du bruit est **étiré dans le filtre**
(`feComponentTransfer`, pente 1,8) — sans lui, 4 % ne donnent rien à voir.

**`--motif-damier`** — la vague de `assets/06.svg`, à **15 %**, en data-URI. La planche
répète quatorze fois la même forme : elle est écrite **une fois** dans un `<defs>` et
reprise par `<use>`, ce qui la ramène de 91 Ko à 7 Ko.

> **Trois opacités, et les deux dernières passent par la VARIABLE.**
> `motif-damier-doux` ramène le motif à **7,5 %** sur les deux cartes d'action — les seules à le poser sur du blanc, où
> 15 % ne se lit plus comme une texture mais comme un gris sale (#E7E7E7 contre #F3F3F3).
> Les aplats colorés gardent les 15 %.
>
> Le **bandeau de la vue piste** est le troisième cas, à **11 %** — la valeur de sa
> planche. Il ne passe par aucun utilitaire nouveau : `.piste-bandeau` pose
> `--damier-opacite: 0.11`, que le calque hérite. Le damier reste celui du projet, **gris
> `#616160`**, là où la planche l'écrivait en blanc : c'est le gris qui contraste le mieux
> — sous lui l'encre blanche ne descend jamais sous **9,99:1** sur les six teintes de
> championnat, contre 7,56:1 sous un damier blanc.
>
> L'opacité est écrite `opacity: var(--damier-opacite, 0.15)`, et l'utilitaire doux ne
> pose **que la variable**. Un `opacity-[0.075]` de Tailwind écrirait la même propriété
> que `motif-damier`, dans la même couche : c'est alors leur **ordre dans la feuille
> compilée** qui les départage, pas l'ordre des classes dans le JSX. Même piège que la
> place de la barre de navigation. Deux propriétés différentes ne peuvent pas se disputer.

> **Les 15 % du damier ASSOMBRISSENT les deux aplats les plus clairs** (terracotta
> 4,09 → 4,41, vert sauge 4,86 → 5,06) et retirent au plus un point aux autres. Pire cas
> pour du texte plein : **4,41:1**. Il se pose sur un `<span>` décoratif en
> `absolute inset-0`, **comme `lueur-haute`** — un pseudo-élément obligerait chaque
> appelant à ajouter `relative` et `overflow-hidden`.

**Accessibilité** : `prefers-reduced-transparency: reduce` rend les matériaux opaques ;
`prefers-contrast: more` fait de même, **supprime le grain** et **approfondit le voile
des drapeaux d'un cran**.

---

## 7. Mouvement

Les jetons vivent dans `index.css`. **La règle des skills est d'étendre le vocabulaire du
projet, jamais de le forker.**

| Jeton | Valeur | Emploi |
|---|---|---|
| `--ease-smooth-out` | `cubic-bezier(0.22, 1, 0.36, 1)` | entrées, sorties |
| `--ease-in-out-fort` | `cubic-bezier(0.77, 0, 0.175, 1)` | **déplacements** |
| `--ease-ressort` | `cubic-bezier(0.34, 1.36, 0.64, 1)` | relâchement d'un appui |
| `--icon-swap-dur` | 180ms | étoile de favori, icônes de nav, interrupteur |
| `--acc-expand` / `--acc-collapse` | 240 / 170ms | accordéons |
| `--flip-dur` | 260ms | tuiles du compte à rebours |
| `--page-slide-dur` | 200ms | passage d'écran |

Vingt-et-une transitions du skill Transitions.dev sont installées avec leurs jetons.

> **Étendre le vocabulaire, jamais le forker — le cas `.t-repli` (version `0.46.0`).** Le
> repli conditionnel du profil avait besoin de la mécanique de l'accordéon 21 sans son
> en-tête, et **sans hériter de ses sélecteurs** : les règles de `.t-acc` descendent par
> combinateur de descendance, donc un `.t-acc` ouvert autour d'autres `.t-acc` ouvrirait
> leurs panneaux avec le sien. La réponse a été un sélecteur distinct qui **réemploie
> `--acc-expand`, `--acc-collapse` et `--acc-ease` sans en ajouter un seul**. C'est la forme
> que doit prendre toute extension : des règles nouvelles, des jetons existants.

> **Étendre le vocabulaire, jamais le forker — le cas `.t-place` (version `0.49.0`).** Le
> déplacement d'une voiture sur la piste, quand un classement rejoué change les scores,
> **n'ajoute aucun jeton** : la durée est `--voiture-dur` (celle de l'entrée déjà
> installée, même objet, même écran) et la courbe `--ease-in-out-fort`, que ce tableau
> réserve aux **déplacements**. Elle porte sur `translate`, la propriété indépendante, et
> non sur `transform` — `.t-voiture` anime déjà `transform` sur l'élément intérieur, et les
> deux s'écraseraient sur un même élément. **La taille d'une voiture, elle, ne s'anime
> pas** : elle change quand la mise en page se recalcule, ce qui n'est pas un changement
> d'état, et `width` n'est de toute façon pas une propriété à animer.

**Les valeurs imposées** : jamais `scale(0)` (une chose doit avoir une silhouette avant
d'être remplie), jamais d'`ease-in` sur une interface, jamais `transition: all`,
`transform` et `opacity` seuls, sous les 300 ms, et le repli `prefers-reduced-motion`
livré **avec** l'animation.

> **Le retour d'appui a deux courbes.** L'enfoncement est immédiat (100ms, `ease-out`) —
> c'est la réponse au doigt. Le **relâchement** remonte sur le ressort et dépasse
> légèrement. Une courbe unique donne l'un ou l'autre, jamais les deux.

> **Deux amplitudes** : `pressable` (`scale(0.97)`) pour les boutons, `pressable-large`
> (`scale(0.985)`) pour les grandes surfaces — 3 % sur une carte pleine largeur déplacent
> une dizaine de pixels, et l'appui devient une secousse.

> **Le ressort ne s'emploie QUE là où un geste a précédé le mouvement**, jamais sur une
> apparition automatique, où le dépassement se lirait comme une erreur.

**Mouvement réduit ≠ moins de sens.** Sous `prefers-reduced-motion`, ce qui **informe**
reste : le chiffre entrant d'une tuile est montré sans voyager, la piste d'un interrupteur
garde sa transition de couleur, la jauge d'une carte reste à sa bonne longueur.

---

## 8. Contraintes iOS

- `env(safe-area-inset-*)` sur tous les écrans (utilitaire `ecran`)
- `user-select: none` sur les éléments graphiques
- Zone tactile minimale : **44 × 44 px** (`min-h-tactile`, un **plancher** et non une
  hauteur fixe — la rangée doit pouvoir grandir si le corps de texte est agrandi)
- `viewport-fit=cover`
- Tester sur **iPhone réel**, pas seulement au simulateur

### Wayfinding

Un écran doit répondre à quatre questions : **où suis-je**, **ce qu'est cet écran**,
**comment j'en sors**, **où mène ce bouton**.

> **Un bouton NOMME sa destination** — « Accueil », « Classement », « Voir les résultats ».
> Un chevron muet ne dit rien, et un bouton « Pronostiquer » qui débouche sur un
> récapitulatif est une promesse fausse. **Quand un même bouton mène à deux écrans, son
> libellé suit sa destination.**

> **Un bouton reste ACTIF même quand la saisie est incomplète.** Un bouton grisé ne dit pas
> ce qui manque ; l'appui pose le message à l'endroit exact à corriger.

> **Une confirmation se fait SUR PLACE, jamais en boîte de dialogue** : le geste de retour
> d'iOS l'annule, et aucune couche ne s'interpose.

> **Une attente est une silhouette, jamais un texte.** Et la silhouette suit la hauteur
> réelle de ce qui arrive — sans quoi l'écran sursaute à l'arrivée des données.

### Rangées qui défilent à l'horizontale

Favoris du tableau des cotes, livrées du profil, aperçus de la page publique : elles sont
calées sur leurs éléments (**`snap-x`**) — un doigt qui les pousse les laisse sur un élément
entier, jamais coupé en deux. C'est ce qui les distingue d'un débordement accidentel, et le
débordement volontaire du dernier élément dit qu'il y en a d'autres au-delà.

> **Elles s'appuient sur le défilement natif et son inertie**, jamais sur un carrousel en
> JavaScript. Et **on ne niche pas un conteneur scrollable dans un accordéon** lui-même
> dans une page qui défile : le geste part au mauvais étage une fois sur deux.

Deux utilitaires pour les aplats plein cadre : **`pleine-largeur`** (touche les deux
bords) et **`coiffe-ecran`** (la couleur court sous la zone sûre, **jamais le texte**).

> **Une couleur qui s'arrêterait sous la Dynamic Island se lirait comme un bandeau posé de
> travers.** L'aplat la coiffe donc, et seul le texte reste dans la zone sûre. Même règle
> pour la vue piste, qui court **sous** les zones sûres.

> ### Le bandeau de la vue piste : la hauteur est un plancher, pas une proportion
> La planche donne le bandeau à 140,13 sur 1280,4, soit **10,94 %** de la hauteur d'écran.
> Un nom centré dans ces 10,94 % tombe **sous la Dynamic Island** — 93px de bandeau sur un
> iPhone 15 Pro, dont 59 pris par la zone sûre. La hauteur est donc
> `max(10.9427%, safe-top + 92px)`, et les 92px sont mesurés : 38 pour la rangée du bouton
> de retour, 54 pour celle du nom. **À 80px les deux rangées se touchaient** — les glyphes
> de « Classement » et ceux d'un nom long se croisaient dans la bande 79-103, ce que seul
> le rendu contre la feuille compilée a montré.
>
> Le **rayon des coins** suit la largeur (`min(10.6361vw, 62.7px)`) pour rester
> **circulaire** : un rayon en pourcentage rendrait une ellipse, qui se lit comme une
> faute. Le rembourrage horizontal du nom (24px) couvre la courbe du coin bas, qui ne mord
> au plus que 19px.

> **Les zones sûres se traitent séparément du rembourrage.** `pt-safe-top` et `pb-3`
> écriraient la même propriété : la marge du home indicator **s'ajouterait** au
> rembourrage au lieu de le remplacer.

> **`barre-collee` rend elle-même `env(safe-area-inset-bottom)`** et annule celui
> d'`ecran` par une marge négative — deux rembourrages superposés laisseraient une bande
> beige morte sous la barre.
