/**
 * Couleur d'écurie d'un pilote — la teinte de fond d'un widget de cote.
 *
 * **Périmètre, identique à celui de `lib/palette.js`, `lib/couleurs.js` et
 * `composants/DrapeauxGP.jsx`** : ces couleurs ne peignent que le fond d'un
 * widget de cote et son liseré. Jamais un fond d'écran, jamais un texte, jamais
 * une bordure de bloc. Les sept couleurs de la section 5 gardent donc tous
 * leurs rôles — le widget reste une carte blanche, à peine teintée.
 *
 * **Deux tables et non une**, parce que les deux entrées ne se ressemblent pas :
 * le marché « Vainqueur » nomme des pilotes (« C.Leclerc »), le marché « Ecurie
 * Vainqueur » nomme des écuries (« Ferrari »). Les fondre obligerait à deviner
 * lequel des deux on regarde ; les garder séparées permet à `couleurEcurie` de
 * chercher dans les deux et de rendre `null` quand elle ne trouve rien.
 *
 * **Un libellé inconnu ne reçoit aucune teinte, jamais une couleur de repli.**
 * Le widget garde alors son blanc. Inventer une couleur pour un pilote qu'on ne
 * connaît pas ferait croire à une écurie qui n'existe pas — c'est la même règle
 * que pour les tracés de circuits (`aUnTrace`) et les drapeaux depuis la
 * version `0.15.0`.
 *
 * **À mettre à jour à chaque saison**, comme `backend/app/calcul/pilotes.py` et
 * `frontend/src/lib/calendrier2026.js`. Une table périmée ne fait aucun dégât
 * silencieux : un pilote absent ressort sans teinte, ce qui se voit.
 */

export const COULEURS_ECURIES = {
  // Ferrari
  "C.Leclerc": "#FF2800", "C.Sainz Jr": "#FF2800",
  // McLaren
  "L.Norris": "#FF8000", "O.Piastri": "#FF8000",
  // Mercedes
  "G.Russell": "#00D2BE", "L.Hamilton": "#00D2BE",
  // Aston Martin
  "F.Alonso": "#006F44", "L.Stroll": "#006F44",
  // Red Bull
  "M.Verstappen": "#1E3A8A", "S.Perez": "#1E3A8A",
  // Williams
  "A.Albon": "#37BEDD", "F.Colapinto": "#37BEDD",
  // Alpine
  "P.Gasly": "#0090FF", "E.Ocon": "#0090FF",
  // Haas
  "O.Bearman": "#212121", "N.Hulkenberg": "#212121",
  // Racing Bulls
  "I.Hadjar": "#6CBBEE", "L.Lawson": "#6CBBEE", "A.Lindblad": "#6CBBEE",
  // Audi
  "G.Bortoleto": "#FF4D4D",
  // Cadillac
  "A.Antonelli": "#9CA3AF", "AK.Antonelli": "#9CA3AF",
};

/** Pour les écuries (marché Ecurie Vainqueur). */
export const COULEURS_NOMS_ECURIES = {
  Ferrari: "#FF2800",
  McLaren: "#FF8000",
  Mercedes: "#00D2BE",
  "Aston Martin": "#006F44",
  "Red Bull": "#1E3A8A",
  Williams: "#37BEDD",
  Alpine: "#0090FF",
  Haas: "#212121",
  "Racing Bulls": "#6CBBEE",
  "Audi F1 Team": "#FF4D4D",
  Cadillac: "#9CA3AF",
};

/**
 * Orthographes qu'Unibet emploie pour les mêmes écuries.
 *
 * Elles vivent à part des deux tables exportées, qui décrivent la grille telle
 * qu'on veut la lire : le bookmaker écrit « Red Bull » un week-end et « Red Bull
 * Racing » le suivant, exactement comme il écrit « GP Pays Bas » puis « GP
 * Pays-Bas » (étape 4). C'est le même mécanisme que les alias de
 * `backend/app/calcul/pilotes.py` et ceux de `slugCircuit`.
 */
const ALIAS = {
  "Red Bull Racing": "#1E3A8A",
  "Haas F1 Team": "#212121",
  Audi: "#FF4D4D",
  "Audi Sauber": "#FF4D4D",
  "Alpine F1 Team": "#0090FF",
  "Aston Martin Aramco": "#006F44",
  "Visa Cash App RB": "#6CBBEE",
  "Cadillac F1 Team": "#9CA3AF",
};

/**
 * La clé de recherche : minuscules, accents ramenés à la lettre de base,
 * espaces fondus, points et tirets normalisés. Elle duplique volontairement
 * `clePilote` de `lib/format.js` en trois lignes — `format.js` n'importe pas ce
 * module et l'importer en retour ferait un cycle. C'est le même arbitrage que
 * `_cle()` dans `backend/app/calcul/pilotes.py`.
 */
function cle(libelle) {
  return String(libelle)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[\s.-]+/g, " ");
}

const INDEX = new Map(
  [COULEURS_ECURIES, COULEURS_NOMS_ECURIES, ALIAS].flatMap((table) =>
    Object.entries(table).map(([libelle, hex]) => [cle(libelle), hex]),
  ),
);

/**
 * La couleur d'écurie d'un libellé de cote — pilote **ou** écurie.
 *
 * Rend `null` pour tout ce qu'elle ne connaît pas : un pilote arrivé en cours de
 * saison, un marché spécial (« Safety Car », « Drapeau rouge ») dont les issues
 * ne nomment personne, ou une table périmée.
 */
export function couleurEcurie(libelle) {
  if (libelle === null || libelle === undefined || libelle === "") return null;
  return INDEX.get(cle(libelle)) ?? null;
}
