#!/usr/bin/env node
//
// Drapeaux et tracés de circuits : de la version web vers « Greed F1/Ressources/ ».
//
//   node ios/scripts/extraire-gp.mjs
//
// **Extraction, jamais reproduction.** Les trois tables de la version web sont les
// seules sources : `DRAPEAUX` (bandes et teintes), `DRAPEAUX_SVG` (les six drapeaux
// dessinés, extraits d'`assets/flags.svg`) et `TRACES` (les douze circuits). Recopier
// à la main un cadrage ou un chemin de deux kilo-octets, c'est se garantir une
// divergence silencieuse au premier ajustement — la règle « une source unique par
// question » du CLAUDE.md.
//
// Les tables sont lues par découpage du texte source plutôt qu'importées : les trois
// fichiers sont des `.jsx`, que Node ne sait pas charger. Le littéral d'objet, lui,
// n'a rien de JSX et s'évalue tel quel.
//
// Trois sorties :
//   Ressources/flags/flag-<slug>.svg    un drapeau par Grand Prix
//   Ressources/traces/trace-<slug>.svg  un circuit par Grand Prix
//   Views/Accueil/DrapeauxGP.swift      la table des teintes, pour le calcul du voile
//
// Puis `ios/scripts/ajouter-assets.sh` les installe dans le catalogue.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const RACINE = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const IOS = join(RACINE, "ios");
const RESSOURCES = join(IOS, "Greed F1", "Ressources");

/** Le littéral d'objet qui suit `export const <nom> = ` dans un module. */
function tableDe(fichier, nom) {
  const source = readFileSync(join(RACINE, fichier), "utf8");
  const debut = source.indexOf(`export const ${nom} = {`);
  if (debut === -1) throw new Error(`Table ${nom} introuvable dans ${fichier}`);
  const ouvrante = source.indexOf("{", debut);

  // Comptage d'accolades : les tables portent des objets imbriqués, et une simple
  // recherche de « \n}; » tomberait sur la première accolade fermante de colonne zéro
  // d'un commentaire.
  let profondeur = 0;
  for (let i = ouvrante; i < source.length; i += 1) {
    if (source[i] === "{") profondeur += 1;
    else if (source[i] === "}") {
      profondeur -= 1;
      if (profondeur === 0) {
        // eslint-disable-next-line no-eval
        return eval(`(${source.slice(ouvrante, i + 1)})`);
      }
    }
  }
  throw new Error(`Table ${nom} non refermée dans ${fichier}`);
}

const DRAPEAUX = tableDe("frontend/src/composants/DrapeauxGP.jsx", "DRAPEAUX");
const DRAPEAUX_SVG = tableDe("frontend/src/composants/DrapeauxSVG.jsx", "DRAPEAUX_SVG");
const TRACES = tableDe("frontend/src/composants/TracesCircuits.jsx", "TRACES");

const entete = '<?xml version="1.0" encoding="UTF-8"?>\n';

// ---------------------------------------------------------------------------
// Drapeaux
// ---------------------------------------------------------------------------

/** Un drapeau à bandes : autant de rectangles que de bandes, pondérés par `parts`.
 *
 *  Le cadrage 300 × 200 est arbitraire et sans conséquence : le drapeau est affiché
 *  en `.fill`, donc mis à l'échelle pour couvrir la carte. Seul compte le rapport des
 *  bandes entre elles. */
function drapeauBandes({ couleurs, type, parts }) {
  const L = 300;
  const H = 200;
  const poids = parts ?? couleurs.map(() => 1);
  const total = poids.reduce((somme, p) => somme + p, 0);
  const vertical = type === "vertical";

  let debut = 0;
  const rects = couleurs.map((couleur, i) => {
    const taille = (poids[i] / total) * (vertical ? L : H);
    const rect = vertical
      ? `<rect x="${arrondi(debut)}" y="0" width="${arrondi(taille)}" height="${H}" fill="${couleur}"/>`
      : `<rect x="0" y="${arrondi(debut)}" width="${L}" height="${arrondi(taille)}" fill="${couleur}"/>`;
    debut += taille;
    return rect;
  });

  return `${entete}<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${L} ${H}">\n  ${rects.join("\n  ")}\n</svg>\n`;
}

/** Un drapeau dessiné : les formes de la planche, coordonnée pour coordonnée.
 *
 *  `r` est un rectangle, `p` un polygone, `d` un chemin — les trois formes que
 *  `DrapeauxSVG.jsx` produit. La couleur est portée par un attribut `fill`, jamais par
 *  une classe : le catalogue d'assets d'Xcode ne lit pas de feuille de style interne. */
function drapeauDessine(fragment) {
  const formes = fragment.formes.map(({ f, r, p, d }) => {
    if (r) return `<rect x="${r[0]}" y="${r[1]}" width="${r[2]}" height="${r[3]}" fill="${f}"/>`;
    if (p) return `<polygon points="${p}" fill="${f}"/>`;
    return `<path d="${d}" fill="${f}"/>`;
  });

  return `${entete}<svg xmlns="http://www.w3.org/2000/svg" viewBox="${fragment.viewBox}">\n  ${formes.join("\n  ")}\n</svg>\n`;
}

// ---------------------------------------------------------------------------
// Tracés de circuits
// ---------------------------------------------------------------------------

/** La bande du widget, en points : c'est elle qui fixe l'épaisseur du trait.
 *
 *  La version web pose un trait de 3 px d'écran (`non-scaling-stroke`), constant d'un
 *  circuit à l'autre quel que soit son cadrage. Un SVG de catalogue n'a pas cet
 *  attribut : l'épaisseur est donc écrite en unités de la `viewBox`, à la valeur qui
 *  donne 3 pt une fois le tracé mis à l'échelle dans cette bande. Sans ce calcul,
 *  Bakou (481 unités de large) rendrait un cheveu là où Zandvoort (395) rendrait un
 *  câble. */
const BANDE = { largeur: 343, hauteur: 160, trait: 3 };

function traceCircuit({ viewBox, d }) {
  const [, , largeur, hauteur] = viewBox.split(/\s+/).map(Number);
  // `xMidYMid meet` : le tracé est contraint par son plus grand côté relatif.
  const echelle = Math.min(BANDE.largeur / largeur, BANDE.hauteur / hauteur);
  const epaisseur = arrondi(BANDE.trait / echelle);

  // `stroke="#000"` et non `currentColor` : un asset de catalogue est teinté par son
  // rendu `template`, qui ne lit que l'alpha. La couleur écrite ici ne se voit jamais.
  return (
    `${entete}<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">\n` +
    `  <path d="${d}" fill="none" stroke="#000" stroke-width="${epaisseur}"` +
    ` stroke-linecap="round" stroke-linejoin="round"/>\n</svg>\n`
  );
}

function arrondi(valeur) {
  return Math.round(valeur * 100) / 100;
}

// ---------------------------------------------------------------------------
// Écriture
// ---------------------------------------------------------------------------

mkdirSync(join(RESSOURCES, "flags"), { recursive: true });
mkdirSync(join(RESSOURCES, "traces"), { recursive: true });

let drapeaux = 0;
let traces = 0;
const teintes = [];

for (const [slug, drapeau] of Object.entries(DRAPEAUX)) {
  const fragment = drapeau.type === "svg" ? DRAPEAUX_SVG[drapeau.svg] : null;
  if (drapeau.type === "svg" && !fragment) {
    throw new Error(`Fragment « ${drapeau.svg} » absent de DRAPEAUX_SVG (${slug})`);
  }

  const svg = fragment ? drapeauDessine(fragment) : drapeauBandes(drapeau);
  writeFileSync(join(RESSOURCES, "flags", `flag-${slug}.svg`), svg);
  drapeaux += 1;

  // Les teintes partent vers Swift : c'est d'elles que se calcule le voile, et la
  // table iOS ne doit pas en être une seconde copie écrite à la main.
  teintes.push([slug, drapeau.couleurs]);
  console.log(`✓ flag-${slug}`);
}

for (const [slug, trace] of Object.entries(TRACES)) {
  writeFileSync(join(RESSOURCES, "traces", `trace-${slug}.svg`), traceCircuit(trace));
  traces += 1;
  console.log(`✓ trace-${slug}`);
}

const swift =
  `// Généré par « ios/scripts/extraire-gp.mjs » — ne pas modifier à la main.\n` +
  `//\n` +
  `// Les teintes de chaque drapeau, reprises de \`frontend/src/composants/DrapeauxGP.jsx\`.\n` +
  `// Elles ne peignent rien : c'est de la bande la plus claire que \`ApparenceDrapeau\`\n` +
  `// dérive le voile du widget. **Toute forme peinte par le drapeau doit avoir sa teinte\n` +
  `// ici** — un drapeau dont on tairait le blanc recevrait un voile trop léger, et le\n` +
  `// texte blanc du widget y disparaîtrait.\n\n` +
  `enum TeintesDrapeaux {\n` +
  `    static let table: [String: [UInt32]] = [\n` +
  teintes
    .map(([slug, couleurs]) => {
      const liste = couleurs.map((c) => `0x${c.replace("#", "").toUpperCase()}`).join(", ");
      return `        "${slug}": [${liste}],`;
    })
    .join("\n") +
  `\n    ]\n}\n`;

writeFileSync(join(IOS, "Greed F1", "Views", "Accueil", "DrapeauxGP.swift"), swift);

console.log(`\n${drapeaux} drapeau(x), ${traces} tracé(s), 1 table Swift.`);
console.log("Installer dans le catalogue :");
console.log("  ./ios/scripts/ajouter-assets.sh");
