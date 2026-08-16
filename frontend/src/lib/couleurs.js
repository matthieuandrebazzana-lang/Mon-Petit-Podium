/**
 * Couleurs de bloc — refonte visuelle des quatre écrans principaux.
 *
 * Six aplats, et **un seul endroit qui décide lequel** : une carte de
 * championnat, l'en-tête coloré de son écran, un en-tête de marché, un bloc de
 * pronostic. Écrire la teinte à la main dans chaque écran la ferait diverger au
 * premier ajustement, et un championnat changerait de couleur d'un écran à
 * l'autre — exactement ce que la refonte cherche à éviter.
 *
 * **Périmètre, identique à celui de `lib/palette.js`** : ces couleurs ne
 * peignent que des aplats de bloc et le texte posé dessus. Jamais un fond
 * d'écran, jamais un texte sur le beige, jamais une bordure. La section 5 du
 * CLAUDE.md garde donc tous ses rôles ; deux des six teintes en viennent
 * d'ailleurs (`primaire` et `accent`) plutôt que d'inventer un rouge et un
 * orange de plus.
 */

import { luminance } from "./palette.js";

/** Les six aplats, dans l'ordre. Les classes sont écrites **en toutes lettres**
 *  : Tailwind lit les fichiers source et ne verrait pas une classe assemblée à
 *  l'exécution (`bg-${cle}`). */
export const COULEURS_BLOC = [
  { cle: "rouge", hex: "#800111", fond: "bg-primaire" },
  { cle: "amber", hex: "#E8A020", fond: "bg-accent" },
  { cle: "vert-sauge", hex: "#4A7C59", fond: "bg-vert-sauge" },
  { cle: "bleu-ardoise", hex: "#2C4A6E", fond: "bg-bleu-ardoise" },
  { cle: "terracotta", hex: "#C4622D", fond: "bg-terracotta" },
  { cle: "violet", hex: "#5C3D7A", fond: "bg-violet" },
];

const PAR_CLE = new Map(COULEURS_BLOC.map((couleur) => [couleur.cle, couleur]));

/** Un aplat par sa clé, avec repli sur le rouge de la marque. */
export function couleurBloc(cle) {
  return PAR_CLE.get(cle) ?? COULEURS_BLOC[0];
}

/**
 * Contraste WCAG entre deux couleurs `#rrggbb`.
 * Le `+ 0.05` des deux côtés est celui de la formule, il évite aussi la
 * division par zéro sur du noir pur.
 */
function contraste(a, b) {
  const clair = Math.max(luminance(a), luminance(b));
  const sombre = Math.min(luminance(a), luminance(b));
  return (clair + 0.05) / (sombre + 0.05);
}

/**
 * L'encre d'un aplat : le blanc, ou le texte du design system.
 *
 * **Le blanc est conservé tant qu'il tient le plancher AA des grands textes
 * (3:1), et lâché en dessous.** C'est ce seuil, et pas un goût, qui décide.
 *
 * Il départage exactement le cas que la demande signale elle-même : sur l'amber
 * `#E8A020`, le blanc tombe à 2,2:1 — illisible — quand le texte `#1A1A1A`
 * monte à 7,7:1. La demande écrit « texte toujours blanc » pour les cartes de
 * championnat **et** « texte noir sur amber » pour les blocs de bonus : les deux
 * règles se contredisent sur l'amber, et c'est la seconde qui gagne, parce que
 * c'est celle qui reste lisible. Les cinq autres aplats gardent le blanc.
 */
export function encreSurAplat(hex) {
  return contraste(hex, "#FFFFFF") >= 3 ? "#FFFFFF" : "#1A1A1A";
}

/**
 * Le jeu de classes qui va avec un aplat : encre principale, encre secondaire,
 * et les deux surfaces posées dessus (une pastille, un emplacement à remplir).
 *
 * Les écrans lisent cet objet plutôt que de choisir `text-white` ou `text-texte`
 * eux-mêmes : c'est ce qui garantit qu'un bloc amber ne se retrouve jamais avec
 * du texte blanc parce qu'un écran l'a écrit de mémoire.
 *
 * L'encre secondaire reste à 70 % et non 60 % : sur les aplats les plus clairs
 * de la série (amber, terracotta), 60 % passe sous le seuil de lisibilité d'un
 * texte de 12px.
 */
export function tonalites(hex) {
  const claire = encreSurAplat(hex) === "#FFFFFF";
  return {
    encre: claire ? "#FFFFFF" : "#1A1A1A",
    texte: claire ? "text-white" : "text-texte",
    texteDoux: claire ? "text-white/70" : "text-texte/70",
    surface: claire ? "bg-white/15" : "bg-black/10",
    surfaceForte: claire ? "bg-white/25" : "bg-black/15",
    /* Le fantôme de profondeur des cartes de championnat : 40 % comme demandé,
       mais dans l'encre de l'aplat, sinon il disparaît sur l'amber. */
    fantome: claire ? "text-white/40" : "text-texte/40",
    /* Même effet de retrait, mais pour un chiffre qui **porte une
       information** — le rang du membre sur sa carte de championnat.

       **80 % est un plancher mesuré, pas un goût**, et c'est la valeur à ne pas
       baisser. La demande décrivait ce chiffre « semi-transparent à 30 % » : à
       30 %, le blanc sur le bordeaux `#800111` tombe à 1,6:1 de contraste, et le
       rang devient un ornement illisible.

       L'aplat qui contraint est le **terracotta `#C4622D`**, le plus clair des
       cinq à encre blanche : l'encre pleine n'y vaut déjà que 4,1:1, et 80 % la
       ramènent à 3,20:1 — juste au-dessus du plancher AA des grands textes. À
       75 % elle tombe à 2,99:1, sous le seuil. Les cinq autres aplats sont plus
       confortables (3,77:1 sur le vert sauge, jusqu'à 7,20:1 sur le bordeaux).
       C'est donc bien 80 %, et non un chiffre rond choisi à l'œil. */
    fantomeLisible: claire ? "text-white/80" : "text-texte/80",
    /* Les deux couches de la jauge de progression : la piste, et ce qui la
       remplit. Elles vivent ici plutôt que dans l'écran, pour la même raison
       que les encres — un aplat amber recevrait sinon une jauge blanche
       invisible, parce qu'un écran l'a écrite de mémoire. */
    jaugePiste: claire ? "bg-white/30" : "bg-black/15",
    jaugePleine: claire ? "bg-white" : "bg-texte",
  };
}

/** Empreinte stable d'une chaîne. Le 31 est le multiplicateur habituel des
 *  fonctions de hachage de chaînes : il répartit mieux qu'une simple somme de
 *  codes, qui donnerait la même valeur à deux anagrammes. */
function empreinte(valeur) {
  const texte = String(valeur ?? "");
  let total = 0;
  for (let i = 0; i < texte.length; i += 1) {
    total = (total * 31 + texte.charCodeAt(i)) % 1000003;
  }
  return total;
}

/**
 * La couleur d'un championnat.
 *
 * **Écart assumé par rapport à la demande, et c'est le point à ne pas défaire.**
 * Elle demandait une attribution « par ordre d'inscription modulo 6, même
 * logique que les livrées de voiture ». Les livrées disposent d'un
 * `ordre_inscription` servi par la base (étape 7) ; un championnat n'a pas
 * d'équivalent — le seul rang disponible serait **sa position dans ma liste**,
 * qui n'est pas une propriété du championnat. Deux conséquences, toutes deux
 * fausses : l'écran de détail, atteint par lien direct, ne connaît aucune liste
 * et ne saurait pas quelle couleur peindre ; et deux membres du même
 * championnat le verraient de deux couleurs différentes, alors que la demande
 * parle bien de « la couleur du championnat ».
 *
 * L'empreinte de l'identifiant donne la même couleur partout, pour tout le
 * monde, sans aucun transport de données entre écrans. Le prix est assumé :
 * avec six teintes, deux championnats d'une même liste peuvent tomber sur la
 * même — là où un modulo sur le rang aurait garanti six cartes distinctes.
 * Reconnaître un championnat à sa couleur d'un écran à l'autre vaut mieux que
 * les distinguer deux à deux sur un seul.
 */
export function couleurChampionnat(championnat) {
  const graine =
    championnat?.id || championnat?.code_invitation || championnat?.nom || "";
  return COULEURS_BLOC[empreinte(graine) % COULEURS_BLOC.length];
}

/**
 * La couleur d'un marché de paris.
 *
 * Les trois marchés du noyau sont nommés explicitement, comme la demande le
 * prescrit. Les autres sont **découverts dynamiquement** chez Unibet (section
 * 3.1 du CLAUDE.md) : ils ne peuvent pas être nommés d'avance, et ils prennent
 * les trois teintes restantes à tour de rôle. Aucun marché découvert ne peut
 * donc emprunter la couleur d'un des trois marchés du noyau, ce qui garde le
 * repère : rouge = vainqueur, bleu = podium, vert = écurie.
 */
const COULEUR_PAR_MARCHE = {
  vainqueur: "rouge",
  podium: "bleu-ardoise",
  "ecurie-vainqueur": "vert-sauge",
};

const MARCHES_DECOUVERTS = ["terracotta", "violet", "amber"];

export function couleurMarche(marche, rang = 0) {
  const nommee = COULEUR_PAR_MARCHE[marche];
  if (nommee) return couleurBloc(nommee);
  return couleurBloc(MARCHES_DECOUVERTS[rang % MARCHES_DECOUVERTS.length]);
}
