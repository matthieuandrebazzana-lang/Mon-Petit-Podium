/**
 * Drapeaux des pays hôtes — le fond du bloc « Prochain GP » de l'accueil.
 *
 * Le bloc portait un aplat rouge `#800111` quel que soit le Grand Prix. Il porte
 * désormais les couleurs du pays qui l'accueille : c'est la seule chose de
 * l'écran d'entrée qui change d'un week-end à l'autre, et elle se reconnaît avant
 * d'avoir lu le nom.
 *
 * **Périmètre, identique à celui de `lib/palette.js` et de `lib/couleurs.js`** :
 * ces couleurs ne peignent que l'aplat de ce bloc. Jamais un fond d'écran,
 * jamais un texte, jamais une bordure. Les sept couleurs de la section 5 du
 * CLAUDE.md gardent donc tous leurs rôles — et le rouge de la marque reste le
 * repli quand le pays n'est pas dans la table.
 *
 * **Aucune requête réseau, jamais.** Deux traitements coexistent, et la frontière
 * entre les deux est celle de l'honnêteté du rendu :
 *
 * - **`horizontal` / `vertical`** — deux ou trois bandes franches, en
 *   `linear-gradient`. C'est exactement ce que le CSS sait dire, et un dessin
 *   n'y apporterait rien.
 * - **`svg`** — le drapeau **dessiné**, extrait de `assets/flags.svg` et servi
 *   en SVG inline par `DrapeauxSVG.jsx`. C'est ce qui remplace le traitement
 *   `complexe` : ramener la bannière étoilée à un aplat rouge, ou la Malaisie à
 *   deux bandes, était le compromis qu'on faisait faute de dessin. Le dessin
 *   existe désormais pour six pays, et l'approximation n'a plus de raison d'être.
 *
 * Un drapeau en **image** (PNG, ou SVG chargé par `url()`) demanderait un fichier
 * par pays, donc autant d'allers-retours réseau avant que le premier écran de
 * l'app puisse s'afficher. Le SVG inline, lui, part avec le bundle.
 */

import { contraste } from "../lib/couleurs.js";
import { luminance } from "../lib/palette.js";
import DrapeauSVG, { aUnDrapeauSvg } from "./DrapeauxSVG.jsx";

/**
 * Les douze drapeaux, par slug de `slugCircuit`.
 *
 * - `type: "horizontal"` — bandes horizontales, le dégradé descend.
 * - `type: "vertical"` — bandes verticales, le dégradé va vers la droite.
 * - `type: "svg"` — le drapeau **dessiné**, servi par `DrapeauxSVG.jsx`. `svg`
 *   nomme le fragment, `base` donne l'aplat peint dessous.
 *
 * `parts` donne le poids relatif des bandes. Il est facultatif : à défaut, les
 * bandes sont égales. Deux drapeaux ne peuvent pas s'en passer — l'Espagne
 * (1/2/1) et le Qatar (3/1) — et sans lui il faudrait les décrire en répétant
 * des bandes, ce qui ne dirait pas la même chose.
 *
 * **`couleurs` n'est pas décoratif : c'est la matière du calcul de contraste.**
 * Pour un drapeau dessiné, il porte **toutes** les teintes que le SVG peint, et
 * pas seulement les dominantes — c'est de sa bande la plus claire que le voile
 * est dérivé. Un drapeau dont on tairait le blanc recevrait un voile trop léger,
 * et le texte blanc du bloc disparaîtrait dessus. C'est précisément ce qui
 * arrivait aux États-Unis et au Brésil tant qu'ils étaient ramenés à un aplat
 * uni : la table disait une seule couleur sombre, le calcul concluait qu'aucun
 * voile n'était nécessaire, et la bannière étoilée dessinée aurait porté ses
 * treize bandes blanches sous un texte blanc. **Toute forme peinte par le SVG
 * doit avoir sa teinte ici.**
 *
 * **`base` est un filet de sécurité, pas une couleur visible.** Le SVG couvre
 * toute la surface (`slice`), donc cet aplat ne se voit jamais ; il ne sert que
 * si le fragment manquait. Il est choisi dans les teintes du drapeau, pour que
 * l'accident reste plausible plutôt que bordeaux.
 *
 * **Deux Grands Prix d'un même pays portent le même drapeau** : Austin et Las
 * Vegas se courent tous deux aux États-Unis, donc tous deux la bannière étoilée.
 * Le noir du circuit de nuit, qui tenait cette place, était une couleur
 * d'ambiance et non un drapeau.
 */
export const DRAPEAUX = {
  "pays-bas": {
    type: "horizontal",
    couleurs: ["#AE1C28", "#FFFFFF", "#21468B"],
  },
  italie: {
    type: "vertical",
    couleurs: ["#009246", "#FFFFFF", "#CE2B37"],
  },
  espagne: {
    type: "horizontal",
    couleurs: ["#AA151B", "#F1BF00", "#AA151B"],
    parts: [1, 2, 1],
  },
  azerbaidjan: {
    type: "horizontal",
    couleurs: ["#0092BC", "#E8192C", "#00B050"],
  },
  // Quatorze bandes rouges et blanches, un croissant et une étoile à quatorze
  // branches dans un canton bleu. Deux bandes égales n'en disaient rien.
  // (Ce slug a remplacé `bahrein` : c'est Sepang, et non Sakhir, qui court à
  // cette place du calendrier — voir `TracesCircuits.jsx`.)
  malaisie: {
    type: "svg",
    svg: "malaisie",
    base: "#CC3128",
    couleurs: ["#CC3128", "#F8F9FB", "#262956", "#F3C839"],
  },
  singapour: {
    type: "horizontal",
    couleurs: ["#EF3340", "#FFFFFF"],
    parts: [1, 1],
  },
  // Bannière étoilée : treize bandes et cinquante étoiles dans un canton.
  "etats-unis": {
    type: "svg",
    svg: "etats-unis",
    base: "#B42C47",
    couleurs: ["#B42C47", "#F8F9FB", "#23365C"],
  },
  // Trois bandes verticales que le CSS savait dire — mais pas l'aigle et le
  // serpent au centre, qui sont l'essentiel de ce drapeau.
  mexique: {
    type: "svg",
    svg: "mexique",
    base: "#036939",
    couleurs: ["#036939", "#FEFEFE", "#D02E26", "#AC692B"],
  },
  // Losange jaune, sphère céleste et vingt-sept étoiles.
  bresil: {
    type: "svg",
    svg: "bresil",
    base: "#408C43",
    couleurs: ["#408C43", "#F9DF3B", "#0C5282", "#FFFFFF"],
  },
  // Las Vegas n'est pas un pays, mais la course se court **aux États-Unis** :
  // c'est la même bannière étoilée qu'à Austin, au fragment près. Deux Grands
  // Prix d'un même pays doivent porter le même drapeau, sans quoi le repère se
  // perd — le noir du circuit de nuit, qui tenait cette place avant, était une
  // couleur d'ambiance.
  "las-vegas": {
    type: "svg",
    svg: "etats-unis",
    base: "#B42C47",
    couleurs: ["#B42C47", "#F8F9FB", "#23365C"],
  },
  // Bordeaux à la volée, bande blanche à la hampe, et la **dentelure** entre les
  // deux : c'est elle qui identifie ce drapeau, et aucune borne de dégradé ne
  // sait la dessiner. Les bandes verticales franches qui tenaient cette place la
  // taisaient entièrement.
  qatar: {
    type: "svg",
    svg: "qatar",
    base: "#8B253D",
    couleurs: ["#8B253D", "#FFFFFF"],
  },
  // Trois bandes horizontales (vert, blanc, noir) et le quadrillage rouge à la
  // hampe, que deux bandes égales taisaient entièrement.
  "abu-dhabi": {
    type: "svg",
    svg: "abu-dhabi",
    base: "#078544",
    couleurs: ["#078544", "#FFFFFF", "#C92F35", "#010101"],
  },
};

/* --------------------------------------------------------------------------
   Le voile, et pourquoi son opacité est calculée et non choisie.

   Le texte du bloc reste **blanc dans tous les cas** : c'est la demande, et
   c'est aussi la seule façon de garder un bloc reconnaissable d'un Grand Prix à
   l'autre. Mais sept des douze drapeaux portent une bande blanche, sur laquelle
   du texte blanc ne se voit pas du tout. D'où le voile noir.

   **La demande annonçait `rgba(0, 0, 0, 0.3)` ; 0,30 ne suffit pas, et c'est
   mesuré.** Un noir à 30 % sur une bande blanche la ramène à `#B2B2B2`, où le
   blanc plein ne vaut que **2,11:1** — sous le plancher AA des grands textes.
   Il faut **0,42** pour atteindre 3:1, et davantage encore si l'on tient compte
   de la lumière spéculaire posée par-dessus. L'opacité est donc dérivée de la
   bande la plus clairedu drapeau, par pas de 0,05, exactement comme
   `encreSurAplat` dérive l'encre d'un aplat dans `lib/couleurs.js`. Un drapeau
   ajouté demain reçoit le bon voile sans que personne n'ait à refaire le calcul.

   Trois conséquences à ne pas défaire :

   1. **Le voile est le calque le plus haut du bloc, sous le seul contenu.** Tout
      ce qui éclaircit la surface — le tracé du circuit en filigrane, la lumière
      spéculaire — passe donc **dessous**. C'est ce qui rend la garantie
      inconditionnelle : si le tracé était posé par-dessus, ses 15 % de blanc
      ramèneraient une bande voilée de `#8C8C8C` à `#9D9D9D`, où le blanc
      retombe à 2,71:1, précisément là où le texte le croise.
   2. **Les fonds assez sombres ne reçoivent aucun voile** (les deux Grands Prix
      américains et le repli bordeaux). Voiler une couleur qui tient déjà le
      seuil ne ferait que l'éteindre. Et **l'absence de bande blanche n'implique
      pas l'absence de voile** : le vert du Brésil est assez clair pour en
      demander 0,05. C'est le calcul qui tranche, jamais la lecture de la table.
   3. **Sur un drapeau voilé, l'encre secondaire passe au blanc plein** au lieu
      des 70 % habituels. Ce n'est pas un choix esthétique : une fois la bande la
      plus claire ramenée au gris moyen, *aucune* opacité intermédiaire n'atteint
      3:1 — seul le blanc plein y arrive. C'est la règle de vibrance
      d'/apple-design §12, qui demande sur un fond changeant un texte plus
      contrasté et légèrement plus gras plutôt qu'un gris translucide. La
      hiérarchie passe donc par la taille et la graisse, pas par l'opacité.
   4. **Les surfaces posées dans le bloc suivent la même règle que l'encre.**
      La pastille « Prochain GP » et les deux cases de statut étaient des voiles
      **blancs** ; elles vivent dans le contenu, donc au-dessus du voile noir, et
      un blanc translucide y annulerait localement ce que le voile venait de
      gagner — une case `bg-white/12` sur une bande blanche voilée redescend à
      2,81:1. Sur un drapeau voilé, ces surfaces passent donc au noir
      translucide, qui va dans le même sens que le voile. Sur les drapeaux
      sombres et sur le repli bordeaux, elles restent blanches : le bloc garde
      exactement l'aspect qu'il avait.
   -------------------------------------------------------------------------- */

/** Plancher AA des grands textes. Le texte du bloc est à 15px et au-delà. */
const CONTRASTE_CIBLE = 3;

/** Opacité maximale de `lueur-haute` (utilitaire d'`index.css`). Elle éclaircit
 *  le haut du bloc, donc elle joue contre le contraste : le calcul l'inclut au
 *  lieu de la découvrir à l'écran. */
const LUEUR_MAX = 0.22;

/** Pas du voile. Assez fin pour ne jamais voiler un drapeau plus que nécessaire,
 *  assez gros pour que les valeurs restent lisibles dans le DOM. */
const PAS_VOILE = 0.05;

function composer(hex, vers, alpha) {
  const canal = (i) => {
    const bas = parseInt(hex.slice(i, i + 2), 16);
    const haut = parseInt(vers.slice(i, i + 2), 16);
    return Math.round(bas * (1 - alpha) + haut * alpha)
      .toString(16)
      .padStart(2, "0");
  };
  return `#${canal(1)}${canal(3)}${canal(5)}`;
}

/** La bande la plus claire d'un drapeau : c'est elle qui contraint, le texte
 *  pouvant tomber n'importe où sur le bloc. */
function bandeLaPlusClaire(couleurs) {
  return couleurs.reduce((pire, c) => (luminance(c) > luminance(pire) ? c : pire));
}

/** Ce que le blanc rencontre vraiment : la bande la plus claire, éclaircie par
 *  la lumière spéculaire, puis assombrie par le voile. */
function substrat(couleurs, voile) {
  const clair = composer(bandeLaPlusClaire(couleurs), "#FFFFFF", LUEUR_MAX);
  return voile > 0 ? composer(clair, "#000000", voile) : clair;
}

function voileNecessaire(couleurs) {
  let voile = 0;
  while (
    voile < 0.9 &&
    contraste("#FFFFFF", substrat(couleurs, voile)) < CONTRASTE_CIBLE
  ) {
    voile = Math.round((voile + PAS_VOILE) * 100) / 100;
  }
  return voile;
}

/** Le dégradé d'un drapeau.
 *
 * Les bandes sont écrites en **paires de bornes** (`#A 0%, #A 33.33%, #B 33.33%`)
 * plutôt qu'avec la syntaxe à double position (`#A 0% 33.33%`) : les deux disent
 * la même chose, la première est comprise partout, et cette app vise Safari iOS.
 *
 * Un drapeau à une seule couleur rend cette couleur telle quelle, sans dégradé :
 * un dégradé d'une couleur vers elle-même serait un calque à composer pour rien.
 *
 * Un drapeau **dessiné** rend son aplat de repli : le SVG le couvre entièrement,
 * cette couleur ne se voit donc pas. Elle est là pour que le bloc reste peint si
 * le fragment venait à manquer, et surtout pour que `fond` reste **toujours
 * renseigné** — c'est lui qui dit aux écrans « ce bloc porte un drapeau », donc
 * qu'ils ne doivent ni retomber sur le bordeaux de la marque ni sauter
 * l'assombrissement uniforme.
 */
function fondCss({ couleurs, type, parts, base }) {
  if (type === "svg") return base;
  if (couleurs.length === 1) return couleurs[0];

  const sens = type === "vertical" ? "to right" : "to bottom";
  const poids = parts ?? couleurs.map(() => 1);
  const total = poids.reduce((somme, p) => somme + p, 0);

  const bornes = [];
  let debut = 0;
  couleurs.forEach((couleur, i) => {
    const fin = debut + (poids[i] / total) * 100;
    const arrondi = (v) => `${Math.round(v * 100) / 100}%`;
    bornes.push(`${couleur} ${arrondi(debut)}`, `${couleur} ${arrondi(fin)}`);
    debut = fin;
  });

  return `linear-gradient(${sens}, ${bornes.join(", ")})`;
}

/**
 * La bande sur laquelle poser le titre d'un écran, en pourcentages de la hauteur
 * du bloc.
 *
 * Un titre centré sur toute la hauteur d'un drapeau tombe là où le hasard des
 * bandes le met : sur les Pays-Bas, il chevauche la couture rouge/blanc. Posé au
 * milieu de la bande la plus claire, il tient dans une seule couleur, et le
 * sous-titre descend naturellement dans la bande suivante.
 *
 * **La bande retenue est la plus claire**, et c'est le même critère que celui du
 * voile : c'est elle qui contraint le contraste, donc c'est elle que le voile a
 * calibrée pour porter du texte blanc. Choisir la plus sombre placerait le titre
 * sur une couleur que personne n'a mesurée.
 *
 * `null` pour un drapeau **vertical** ou un aplat uni : ses bandes sont
 * côte à côte, ou il n'y en a qu'une — il n'existe aucune bande horizontale à
 * viser, et l'appelant garde son centrage habituel.
 *
 * `null` aussi pour un drapeau **dessiné**, et pour une raison de plus : ses
 * bandes ne sont pas une donnée mais un dessin, et `slice` les décale dès que le
 * conteneur n'a pas le rapport de forme du drapeau. Viser une bande qu'on ne
 * sait pas placer poserait le titre n'importe où ; le centrage, lui, est juste
 * dans tous les cas. La Malaisie et Abu Dhabi, qui portaient une bande visée
 * tant qu'ils étaient décrits en CSS, la perdent donc — le voile calculé
 * continue seul de garantir la lisibilité du titre, comme sur les sept autres.
 */
function bandeTitre({ couleurs, type, parts }) {
  if (type !== "horizontal" || couleurs.length < 2) return null;

  const poids = parts ?? couleurs.map(() => 1);
  const total = poids.reduce((somme, p) => somme + p, 0);

  let debut = 0;
  let choisie = null;
  couleurs.forEach((couleur, i) => {
    const fin = debut + (poids[i] / total) * 100;
    const lum = luminance(couleur);
    if (!choisie || lum > choisie.lum) choisie = { lum, debut, fin };
    debut = fin;
  });

  const arrondi = (v) => Math.round(v * 100) / 100;
  return {
    debut: arrondi(choisie.debut),
    fin: arrondi(choisie.fin),
    centre: arrondi((choisie.debut + choisie.fin) / 2),
  };
}

/**
 * Tout ce qu'un bloc a besoin de savoir pour se peindre aux couleurs d'un pays.
 *
 * Le calcul est fait **une fois au chargement du module** et figé : douze
 * drapeaux, quelques dizaines d'itérations chacun, et le résultat ne dépend de
 * rien d'autre que de la table ci-dessus. Le refaire à chaque rendu de l'accueil
 * serait du travail repayé à chaque réveil de l'app.
 */
const APPARENCES = Object.fromEntries(
  Object.entries(DRAPEAUX).map(([slug, drapeau]) => [
    slug,
    {
      ...apparence(drapeau.couleurs),
      fond: fondCss(drapeau),
      bandeTitre: bandeTitre(drapeau),
      // Le fragment à dessiner par-dessus l'aplat, ou `null` pour un drapeau
      // décrit en CSS. Vérifié contre `DrapeauxSVG.jsx` plutôt que recopié de
      // confiance : une faute de frappe dans la table laisserait sinon le bloc
      // sur son aplat de repli, sans que rien ne le signale.
      svg: drapeau.svg && aUnDrapeauSvg(drapeau.svg) ? drapeau.svg : null,
    },
  ]),
);

/** Les classes qui découlent d'un jeu de bandes. Elles ne sont écrites qu'ici :
 *  l'écran lit cet objet plutôt que de choisir `text-white/70` ou `bg-white/12`
 *  lui-même, exactement comme `tonalites()` le garantit pour les aplats. */
function apparence(couleurs) {
  const voile = voileNecessaire(couleurs);
  const sol = substrat(couleurs, voile);

  // Deux questions, deux mesures sur ce même substrat.
  // 1. Un blanc à 70 % s'y détache-t-il encore ?
  const douxTient =
    contraste(composer(sol, "#FFFFFF", 0.7), sol) >= CONTRASTE_CIBLE;
  // 2. Une surface blanche translucide y laisse-t-elle son texte blanc lisible ?
  //    On éprouve la plus claire des deux (20 %) : si elle passe, l'autre passe.
  const surfacesClaires =
    contraste("#FFFFFF", composer(sol, "#FFFFFF", 0.2)) >= CONTRASTE_CIBLE;

  return {
    voile,
    texte: "text-white",
    // Blanc plein et graisse 500 dès que 70 % ne tient plus le seuil
    // (/apple-design §12) : la hiérarchie passe alors par la graisse.
    texteDoux: douxTient ? "text-white/70" : "text-white font-medium",
    pastille: surfacesClaires ? "bg-white/20" : "bg-black/25",
    surface: surfacesClaires ? "bg-white/12" : "bg-black/20",
    /* Ombre portée, et seulement sur les drapeaux à plusieurs bandes.
       Le nom du Grand Prix occupe toute la largeur du bloc : il **traverse** une
       frontière de bandes, et une lettre posée pile sur la couture perd son
       contour d'un côté ou de l'autre. C'est exactement la situation que la vue
       piste résout déjà de la même manière — sa légende passe tantôt sur
       l'asphalte, tantôt sur une bordure blanche.
       Un aplat uni n'a pas de couture, donc pas d'ombre : le bloc bordeaux garde
       son texte parfaitement net, comme avant les drapeaux. */
    ombreTexte:
      couleurs.length > 1 ? "[text-shadow:0_1px_3px_rgba(0,0,0,0.45)]" : "",
  };
}

/**
 * L'apparence du bloc pour un Grand Prix donné, ou `null` si son pays n'est pas
 * dans la table — l'appelant garde alors l'aplat rouge de la marque.
 *
 * @param {string} slug  clé rendue par `slugCircuit`
 */
export function drapeauDuGp(slug) {
  return APPARENCES[slug] ?? null;
}

/** L'apparence de repli : le bordeaux de la marque, pour un Grand Prix dont le
 *  pays n'est pas dans la table, pour le bloc « aucun Grand Prix » et pour la
 *  silhouette de chargement.
 *
 *  Elle passe par le **même calcul** que les drapeaux, plutôt que d'être écrite à
 *  la main : le bordeaux tient 6,8:1 en blanc plein et 4,2:1 à 70 %, donc il
 *  ressort sans voile et avec ses surfaces blanches — le bloc garde exactement
 *  l'aspect qu'il avait. Le vérifier par le calcul plutôt que l'affirmer, c'est
 *  ce qui empêche les deux chemins de diverger si le seuil bougeait un jour.
 *
 *  `fond: null` est ce qui dit à l'écran de garder sa classe `bg-primaire` : la
 *  couleur de la marque reste dans le thème Tailwind, elle n'est pas recopiée
 *  ici en hexadécimal. */
export const APPARENCE_REPLI = {
  ...apparence(["#800111"]),
  fond: null,
  // Un aplat uni n'a pas de bande à viser : l'appelant garde son centrage.
  bandeTitre: null,
  svg: null,
};

/**
 * Le drapeau dessiné, quand il y en a un.
 *
 * Il vit ici et non chez les écrans pour la même raison que `VoileDrapeau` : un
 * écran qui monterait `DrapeauSVG` lui-même devrait savoir quel fragment
 * demander, donc relire la table — et deux lectures finiraient par diverger.
 *
 * **C'est le calque le plus bas du bloc.** Il se pose avant la lumière
 * spéculaire, avant le voile et avant l'assombrissement uniforme : ce sont eux
 * qui doivent le recouvrir, jamais l'inverse. Posé plus haut, il repeindrait ses
 * bandes blanches par-dessus le voile et le texte du bloc y retomberait sous le
 * seuil des 3:1 — exactement le dégât que la version `0.15.0` décrit pour le
 * tracé du circuit.
 */
export function FondDrapeau({ apparence: drapeau }) {
  if (!drapeau?.svg) return null;
  return <DrapeauSVG slug={drapeau.svg} />;
}

/**
 * Le voile lui-même. Rien à l'écran ne le désigne, il n'a pas de contenu, et un
 * lecteur d'écran n'a rien à en dire — d'où `aria-hidden`.
 *
 * Il porte son opacité par variable CSS et non en `background-color` en ligne :
 * c'est ce qui permet à `index.css` de la renforcer sous
 * `prefers-contrast: more`, où le grain du fond disparaît pour la même raison.
 */
export function VoileDrapeau({ voile }) {
  if (!voile) return null;
  return (
    <span
      aria-hidden="true"
      className="voile-drapeau pointer-events-none absolute inset-0"
      style={{ "--voile": voile }}
    />
  );
}

/* --------------------------------------------------------------------------
   Les nationalités de pilotes — une seconde question, la MÊME source de
   couleurs.

   L'écran « Détail GP » pose le drapeau du vainqueur en fond de sa carte, à
   très faible opacité. C'est une question distincte de celle du bloc d'un Grand
   Prix : `DRAPEAUX` est indexée par slug de CIRCUIT (`las-vegas` et
   `etats-unis` sont deux entrées pour un seul pays), et « britannique » n'y
   entrerait sous aucune clé. Une table à part était donc nécessaire.

   **Mais pas une seconde liste de couleurs.** Quatre nationalités sur huit
   décrivent un pays que `DRAPEAUX` peint déjà : elles le RÉFÉRENCENT au lieu de
   le recopier, et c'est tout l'objet de la table ci-dessous. Deux jeux de
   bandes écrits séparément auraient divergé au premier ajustement, et le
   symptôme aurait été discret — le drapeau néerlandais d'une carte de
   vainqueur légèrement différent de celui du bloc de Zandvoort, sur le même
   écran.

   **Une nationalité sans drapeau n'est pas une panne**, c'est la règle du
   module depuis la version `0.15.0` : aucune teinte de repli, jamais. La carte
   garde alors son blanc, et son libellé de pays continue de dire la
   nationalité — qui n'a jamais reposé sur le fond.
   -------------------------------------------------------------------------- */

/**
 * Les huit nationalités que la table des circuits nomme, et le drapeau de
 * chacune.
 *
 * `pays` renvoie vers `DRAPEAUX` quand le pays y est déjà décrit ; sinon
 * l'entrée porte ses propres bandes, dans la forme exacte de `DRAPEAUX`.
 * `libelle` est le gentilé affiché — c'est lui qui porte le sens, le fond n'est
 * qu'une texture.
 *
 * `australie` est déclarée **sans drapeau**, et c'est délibéré : sa croix du Sud
 * n'a pas de description que le CSS ou une spécification puisse rendre sans
 * l'approximer (voir l'en-tête de `DrapeauxSVG.jsx`). La déclarer ici lui donne
 * son gentilé ; l'absence de `pays` et de `drapeau` lui retire son fond.
 */
export const NATIONALITES = {
  neerlandaise: { libelle: "Pays-Bas", pays: "pays-bas" },
  espagnole: { libelle: "Espagne", pays: "espagne" },
  mexicaine: { libelle: "Mexique", pays: "mexique" },
  italienne: { libelle: "Italie", pays: "italie" },
  britannique: {
    libelle: "Royaume-Uni",
    drapeau: {
      type: "svg",
      svg: "royaume-uni",
      base: "#012169",
      couleurs: ["#012169", "#FFFFFF", "#C8102E"],
    },
  },
  monegasque: {
    libelle: "Monaco",
    drapeau: { type: "horizontal", couleurs: ["#CE1126", "#FFFFFF"] },
  },
  allemande: {
    libelle: "Allemagne",
    drapeau: {
      type: "horizontal",
      couleurs: ["#000000", "#DD0000", "#FFCE00"],
    },
  },
  australienne: { libelle: "Australie" },
};

/** Le même calcul que pour les Grands Prix, figé au chargement du module.
 *  Les entrées qui renvoient à un pays réutilisent l'apparence **déjà
 *  calculée** : une nationalité ne peut donc pas recevoir un voile différent de
 *  celui du drapeau qu'elle désigne. */
const APPARENCES_NATIONALITE = Object.fromEntries(
  Object.entries(NATIONALITES).map(([cle, entree]) => {
    const drapeau = entree.pays ? DRAPEAUX[entree.pays] : entree.drapeau;
    if (!drapeau) return [cle, { libelle: entree.libelle, fond: null, svg: null }];
    return [
      cle,
      {
        libelle: entree.libelle,
        ...apparence(drapeau.couleurs),
        fond: fondCss(drapeau),
        svg: drapeau.svg && aUnDrapeauSvg(drapeau.svg) ? drapeau.svg : null,
      },
    ];
  }),
);

/**
 * Le drapeau d'une nationalité, ou `null` si elle n'est pas dans la table.
 *
 * `fond` peut valoir `null` sur une nationalité pourtant connue — l'Australie :
 * l'appelant a son gentilé mais n'a rien à peindre. Les deux cas se traitent
 * pareil chez lui, il suffit de tester `fond`.
 */
export function drapeauDeNationalite(cle) {
  return APPARENCES_NATIONALITE[cle] ?? null;
}
