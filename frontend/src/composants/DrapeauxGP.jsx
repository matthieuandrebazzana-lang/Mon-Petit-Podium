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
 * **Aucune image, aucune requête** : tout est en CSS pur, `linear-gradient` à
 * bandes franches. Un drapeau en image demanderait un fichier par pays, à
 * charger avant que le premier écran de l'app puisse s'afficher.
 */

import { contraste } from "../lib/couleurs.js";
import { luminance } from "../lib/palette.js";

/**
 * Les douze drapeaux, par slug de `slugCircuit`.
 *
 * - `type: "horizontal"` — bandes horizontales, le dégradé descend.
 * - `type: "vertical"` — bandes verticales, le dégradé va vers la droite.
 * - `type: "complexe"` — drapeau qu'on ne reproduit pas honnêtement en CSS pur
 *   (étoiles, sphère céleste, cantons) : **aplat uni de la couleur dominante**.
 *   Mievaut une couleur juste qu'un drapeau approximatif.
 *
 * `parts` donne le poids relatif des bandes. Il est facultatif : à défaut, les
 * bandes sont égales. Deux drapeaux en ont besoin — l'Espagne (1/2/1) et le
 * Qatar (3/1) — et sans lui il faudrait les décrire en répétant des bandes, ce
 * qui ne dirait pas la même chose.
 *
 * *Une orientation suit la demande plutôt que le drapeau réel*, et c'est signalé
 * ici pour que ce soit une décision et non un oubli : le Qatar est décrit en
 * bandes **horizontales** bordeaux/blanc, alors que le vrai drapeau porte sa
 * bande blanche à la hampe, donc verticalement. Cela se corrige en changeant le
 * seul champ `type`.
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
  // branches dans un canton bleu : hors de portée d'un dégradé honnête. Rouge
  // dominant. (Ce slug a remplacé `bahrein` : c'est Sepang, et non Sakhir, qui
  // court à cette place du calendrier — voir `TracesCircuits.jsx`.)
  malaisie: { type: "complexe", couleurs: ["#CC0001"] },
  singapour: {
    type: "horizontal",
    couleurs: ["#EF3340", "#FFFFFF"],
    parts: [1, 1],
  },
  // Bannière étoilée : cinquante étoiles dans un canton, hors de portée d'un
  // dégradé. Rouge dominant.
  "etats-unis": { type: "complexe", couleurs: ["#B22234"] },
  mexique: {
    type: "vertical",
    couleurs: ["#006847", "#FFFFFF", "#CE1126"],
  },
  // Sphère céleste, bandeau incurvé et vingt-sept étoiles. Vert dominant.
  bresil: { type: "complexe", couleurs: ["#009C3B"] },
  // Las Vegas n'est pas un pays : pas de drapeau à reproduire. Noir, la couleur
  // du circuit de nuit qui fait toute son identité.
  "las-vegas": { type: "complexe", couleurs: ["#000000"] },
  qatar: {
    type: "horizontal",
    couleurs: ["#8D1B3D", "#FFFFFF"],
    parts: [3, 1],
  },
  // Quadrillage rouge à la hampe sur trois bandes horizontales. Vert dominant.
  "abu-dhabi": { type: "complexe", couleurs: ["#00732F"] },
};

/* --------------------------------------------------------------------------
   Le voile, et pourquoi son opacité est calculée et non choisie.

   Le texte du bloc reste **blanc dans tous les cas** : c'est la demande, et
   c'est aussi la seule façon de garder un bloc reconnaissable d'un Grand Prix à
   l'autre. Mais cinq des douze drapeaux portent une bande blanche, sur laquelle
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
   2. **Les cinq drapeaux assez sombres ne reçoivent aucun voile** (États-Unis,
      Brésil hors lumière, Las Vegas, Abu Dhabi, et le repli bordeaux). Voiler
      une couleur qui tient déjà le seuil ne ferait que l'éteindre.
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
 */
function fondCss({ couleurs, type, parts }) {
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
};

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
