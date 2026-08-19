import { COULEURS_NOMS_ECURIES } from "./ecuries.js";

/**
 * Les onze livrées d'écurie — la partie *métadonnée*, sans le moindre dessin.
 *
 * **Pourquoi ce module existe séparément de `composants/VoituresEcuries.jsx`.**
 * Celui-ci porte les formes SVG des onze voitures, soit une cinquantaine de
 * kilo-octets de chemins. `lib/palette.js` a besoin de la *teinte* d'une livrée
 * pour la pastille du classement, et il est importé par `lib/couleurs.js`, donc
 * par presque tous les écrans de l'application — y compris ceux qui n'affichent
 * aucune voiture. Faire remonter les formes jusque-là embarquerait le dessin
 * des onze voitures dans le lot de chaque écran. Le nom `lib/livrees.js` est
 * repris à l'étape 7 : le module des livrées attribuées par ordre d'inscription
 * avait été supprimé à l'étape 8, quand la personnalisation est arrivée.
 *
 * **La teinte n'est pas écrite ici non plus.** Elle est lue dans
 * `lib/ecuries.js`, la table que le projet tient déjà pour les widgets de
 * cotes : c'est la même question — « de quelle couleur est cette écurie ? » —
 * et deux réponses écrites séparément finiraient par diverger. La couleur
 * dominante du dessin ne ferait d'ailleurs pas l'affaire : trois livrées sont à
 * dominante blanche (Racing Bulls, Haas, Cadillac) et deux à dominante grise
 * (Mercedes, Audi), soit cinq pastilles indistinguables sur onze.
 *
 * **L'ordre est celui de la planche `assets/voitures_ecuries.svg`**, de haut en
 * bas. L'identification des onze écuries a été faite en rendant les voitures
 * côte à côte, pas devinée d'après les couleurs du fichier.
 *
 * **À mettre à jour à chaque saison**, comme `lib/ecuries.js`,
 * `lib/calendrier2026.js` et `backend/app/calcul/pilotes.py`. Les slugs doivent
 * rester ceux de `composants/VoituresEcuries.jsx` : une livrée listée ici sans
 * dessin là-bas ferait retomber la voiture sur le mode personnalisé.
 */
export const LIVREES = [
  { slug: "red-bull", nom: "Red Bull" },
  { slug: "ferrari", nom: "Ferrari" },
  { slug: "mercedes", nom: "Mercedes" },
  { slug: "alpine", nom: "Alpine" },
  { slug: "aston-martin", nom: "Aston Martin" },
  { slug: "audi", nom: "Audi" },
  { slug: "mclaren", nom: "McLaren" },
  { slug: "racing-bulls", nom: "Racing Bulls" },
  { slug: "williams", nom: "Williams" },
  { slug: "haas", nom: "Haas" },
  { slug: "cadillac", nom: "Cadillac" },
];

/** Nom lisible d'une livrée — l'étiquette de sa case dans la grille de choix. */
export function nomLivree(slug) {
  return LIVREES.find((livree) => livree.slug === slug)?.nom ?? null;
}

/** Ce slug désigne-t-il une livrée connue ? Un slug inconnu n'est pas une panne. */
export function estLivree(slug) {
  return LIVREES.some((livree) => livree.slug === slug);
}

/**
 * La teinte d'une livrée, pour la pastille du classement et le filet des lignes.
 * `null` pour un slug inconnu, jamais une couleur inventée — c'est la règle
 * tenue par `aUnTrace` pour les circuits et par les drapeaux depuis la version
 * `0.15.0`.
 */
export function teinteLivree(slug) {
  const nom = nomLivree(slug);
  return nom ? (COULEURS_NOMS_ECURIES[nom] ?? null) : null;
}
