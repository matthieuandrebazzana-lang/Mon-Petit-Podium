/**
 * Livrées des voitures — dix combinaisons, attribuées par ordre d'inscription.
 *
 * Le premier membre inscrit dans un championnat prend la combinaison 1, le
 * deuxième la 2, et ainsi de suite ; au-delà de dix, on boucle. C'est
 * `ordre_inscription`, servi par `GET /championnats/{id}/classement`, qui donne
 * l'indice — jamais le rang. Deux raisons, et la seconde est la vraie :
 *
 * 1. le rang bouge après chaque Grand Prix, la couleur d'une voiture non ;
 * 2. reconnaître quelqu'un du coin de l'œil sur la vue piste n'a de sens que si
 *    sa voiture ne change jamais de couleur. Une livrée qui suit le classement
 *    ferait échanger leurs couleurs à deux membres qui se doublent.
 *
 * **Écart assumé par rapport à la section 5 du CLAUDE.md.** La palette de l'app
 * compte sept couleurs ; dix livrées distinctes n'en sortiraient pas. Les
 * couleurs ci-dessous ne sont donc pas des couleurs d'interface : elles ne
 * peignent que les voitures, jamais un fond, un bouton ou un texte d'écran. La
 * maquette 07b fait déjà ce choix, en dessinant des voitures ambre, rouge,
 * marron, bleue et violette. Les deux premières livrées reprennent d'ailleurs
 * `primaire` et `texte` du design system plutôt que d'inventer un rouge et un
 * noir de plus.
 */

export const LIVREES = [
  { nom: "Rouge et blanc", couleur1: "#800111", couleur2: "#FFFFFF" },
  { nom: "Noir et turquoise", couleur1: "#1A1A1A", couleur2: "#27F4D2" },
  { nom: "Orange et noir", couleur1: "#FF7A00", couleur2: "#1A1A1A" },
  { nom: "Bleu et jaune", couleur1: "#0055A5", couleur2: "#E8A020" },
  { nom: "Bleu et rouge", couleur1: "#16255C", couleur2: "#D42B1F" },
  { nom: "Vert et jaune", couleur1: "#00594F", couleur2: "#E8A020" },
  { nom: "Blanc et bleu", couleur1: "#FFFFFF", couleur2: "#0055A5" },
  { nom: "Blanc et rouge", couleur1: "#FFFFFF", couleur2: "#D42B1F" },
  { nom: "Bleu et blanc", couleur1: "#2E6A9E", couleur2: "#FFFFFF" },
  { nom: "Vert et noir", couleur1: "#00B24A", couleur2: "#1A1A1A" },
];

/**
 * Livrée d'un membre à partir de son rang d'inscription (1 pour le premier).
 *
 * Tolère un indice absent : un membre sans `ordre_inscription` — le temps qu'un
 * cache d'une version antérieure se renouvelle — prend la première livrée
 * plutôt que de faire tomber l'écran.
 */
export function livreePour(ordreInscription) {
  const indice = Number.isFinite(ordreInscription) ? ordreInscription : 1;
  return LIVREES[(Math.max(1, Math.trunc(indice)) - 1) % LIVREES.length];
}

/** Luminance relative (WCAG) d'une couleur `#rrggbb`. */
function luminance(hex) {
  const canal = (paire) => {
    const valeur = parseInt(paire, 16) / 255;
    return valeur <= 0.03928
      ? valeur / 12.92
      : ((valeur + 0.055) / 1.055) ** 2.4;
  };
  const propre = hex.replace("#", "");
  if (propre.length !== 6) return 0;
  return (
    0.2126 * canal(propre.slice(0, 2)) +
    0.7152 * canal(propre.slice(2, 4)) +
    0.0722 * canal(propre.slice(4, 6))
  );
}

/**
 * Encre lisible sur un aplat : le texte du design system ou le blanc.
 *
 * Un numéro de voiture blanc sur une livrée blanche serait invisible, et le
 * numéro est la seule chose qui identifie une voiture à cette taille.
 */
export function encreSur(fond) {
  return luminance(fond) > 0.45 ? "#1A1A1A" : "#FFFFFF";
}

/**
 * La couleur de la livrée qui se voit sur une carte blanche.
 *
 * Deux livrées sur dix sont à dominante blanche : posées telles quelles sur le
 * fond `surface`, leur pastille disparaîtrait. On prend alors la seconde
 * couleur, qui contraste par construction avec la première.
 */
export function couleurLisible(livree) {
  return luminance(livree.couleur1) > 0.75 ? livree.couleur2 : livree.couleur1;
}
