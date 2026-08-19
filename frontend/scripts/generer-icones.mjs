/**
 * Génère les icônes PNG de l'application à partir de `assets/logo-05.svg`.
 *
 *   node scripts/generer-icones.mjs      (ou : npm run icones)
 *
 * La planche porte l'icône carrée dans le rectangle
 * `379.88 51.62 126.29 126.29` — le même que sert `composants/LogoGreedF1.jsx`.
 * Le SVG source n'est jamais réécrit : le script en relit les arrêts du
 * dégradé, les neuf tracés de la tuile de texture et le « G », et les
 * recompose dans un SVG autonome que sharp rastérise. Refaire tourner le
 * script après une retouche de la planche suffit à régénérer les quatre PNG.
 *
 * ── Deux écarts par rapport au dessin, et ce sont eux qui font une icône ──
 *
 * 1. **Les coins arrondis sautent : l'icône est rendue à fond perdu.** Le
 *    dessin porte un `rx` de 29,47 (23 % du côté), mais iOS **applique déjà**
 *    son propre masque arrondi à `apple-touch-icon`, et Android le sien. Garder
 *    l'arrondi donnerait un arrondi dans un arrondi — un liseré transparent
 *    visible tout autour — et surtout, **iOS rend en noir la transparence**
 *    d'une `apple-touch-icon`. Les quatre coins seraient noirs. Le dégradé, la
 *    texture et le « G » sont intacts : seul l'arrondi est délégué au système,
 *    ce que fait toute icône d'application.
 *
 * 2. **La variante `maskable` réduit le contenu à la zone sûre.** Android
 *    découpe une icône `maskable` dans un cercle ou un squircle et peut manger
 *    les 10 % de chaque bord. Le fond continue donc de couvrir tout le carré,
 *    mais le « G » est ramené à 80 % **autour du centre du carré** : un tracé
 *    qui tenait dans le carré tient alors forcément dans les 80 % centraux.
 *    Sans cette variante, Android poserait l'icône dans une pastille blanche
 *    au lieu de la servir bord à bord.
 */

import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const ici = dirname(fileURLToPath(import.meta.url));
const PLANCHE = resolve(ici, "../../assets/logo-05.svg");
const SORTIE = resolve(ici, "../public/icons");

/* Le cadrage de l'icône dans la planche. */
const X = 379.88;
const Y = 51.62;
const COTE = 126.29;
const CX = X + COTE / 2;
const CY = Y + COTE / 2;

/* Part du carré que le contenu occupe sur la variante `maskable`. La zone sûre
   d'Android est le disque central de 80 % : on s'y tient exactement. */
const ZONE_SURE = 0.8;

const planche = readFileSync(PLANCHE, "utf-8");

/* Extraction — aucune coordonnée n'est réécrite, on relit ce que le dessin dit. */
const stops = [...planche.matchAll(/<stop offset="([^"]*)" stop-color="([^"]*)"\/>/g)]
  .map(([, offset, couleur]) => `<stop offset="${offset}" stop-color="${couleur}"/>`)
  .join("");

const blocMotif = planche.slice(
  planche.indexOf('<pattern id="Nouveau_motif"'),
  planche.indexOf('<pattern id="Nouveau_motif-2"'),
);
const tuile = [...blocMotif.matchAll(/<path class="cls-4" d="([^"]*)"\/>/g)]
  .map(([, d]) => `<path fill="#fff" d="${d}"/>`)
  .join("");

/* Le « G » de l'icône : la seule forme de la planche portant la classe cls-3. */
const g = planche.match(/<path class="cls-3" d="([^"]*)"\/>/)[1];

if (!stops || tuile.length === 0 || !g) {
  throw new Error("Extraction incomplète : la planche a changé de structure.");
}

/** Compose le SVG autonome. `maskable` réduit le contenu à la zone sûre. */
function svg({ maskable }) {
  const echelle = maskable
    ? ` transform="translate(${CX} ${CY}) scale(${ZONE_SURE}) translate(${-CX} ${-CY})"`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${X} ${Y} ${COTE} ${COTE}">
  <defs>
    <linearGradient id="d" x1="${X}" y1="${CY}" x2="506.17" y2="${CY}" gradientUnits="userSpaceOnUse">${stops}</linearGradient>
    <pattern id="t" x="0" y="0" width="154.17" height="206.24" patternTransform="translate(-6174.0847 -2365.6679) scale(.5)" patternUnits="userSpaceOnUse" viewBox="0 0 154.17 206.24">
      <rect fill="none" y="0" width="154.17" height="206.24"/>${tuile}
    </pattern>
  </defs>
  <rect fill="url(#d)" x="${X}" y="${Y}" width="${COTE}" height="${COTE}"/>
  <rect fill="url(#t)" opacity=".11" x="${X}" y="${Y}" width="${COTE}" height="${COTE}"/>
  <path fill="#fff" opacity=".85" d="${g}"${echelle}/>
</svg>`;
}

const CIBLES = [
  { fichier: "icon-180.png", taille: 180, maskable: false },
  { fichier: "icon-192.png", taille: 192, maskable: false },
  { fichier: "icon-512.png", taille: 512, maskable: false },
  { fichier: "icon-512-maskable.png", taille: 512, maskable: true },
];

mkdirSync(SORTIE, { recursive: true });

for (const { fichier, taille, maskable } of CIBLES) {
  // `density` est ce qui fait rastériser le SVG à la bonne finesse : sans elle,
  // sharp le rend à 72 ppp puis agrandit un bitmap flou.
  const densite = Math.ceil((taille / COTE) * 96);
  await sharp(Buffer.from(svg({ maskable })), { density: densite })
    .resize(taille, taille, { fit: "fill" })
    // Une `apple-touch-icon` transparente est rendue **noire** par iOS. Le fond
    // couvre déjà tout le carré ; on retire le canal alpha pour en être sûr.
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toFile(resolve(SORTIE, fichier));
  console.log(`✓ public/icons/${fichier}  ${taille}×${taille}${maskable ? "  (maskable)" : ""}`);
}
