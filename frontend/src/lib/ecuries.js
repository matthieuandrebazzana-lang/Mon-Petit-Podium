/**
 * Couleur d'écurie d'un pilote — la teinte de fond d'un widget de cote.
 *
 * **Périmètre, identique à celui de `lib/palette.js`, `lib/couleurs.js` et
 * `composants/DrapeauxGP.jsx`** : ces couleurs ne peignent que le fond d'un
 * widget de cote et son liseré. Jamais un fond d'écran, jamais un texte, jamais
 * une bordure de bloc. Les sept couleurs de la section 5 gardent donc tous
 * leurs rôles — le widget reste une carte blanche, à peine teintée.
 *
 * **Deux tables exportées, mais une seule source de couleurs.** Les deux entrées
 * ne se ressemblent pas — le marché « Vainqueur » nomme des pilotes
 * (« C.Leclerc »), le marché « Ecurie Vainqueur » nomme des écuries
 * (« Ferrari ») — et les fondre obligerait à deviner lequel des deux on regarde.
 * Elles dérivent en revanche toutes les deux de `ECURIES`, où chaque teinte est
 * écrite **une seule fois** : une écurie ne peut donc plus recevoir deux
 * couleurs différentes selon le libellé qui la désigne, ce qui était le cas
 * quand les trois tables étaient tenues à la main.
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

/**
 * Les onze écuries de la grille 2026 et leur teinte. Une couleur par écurie,
 * écrite **une seule fois** : les deux tables exportées et les alias y puisent, si bien qu'aucune
 * écurie ne peut recevoir deux teintes différentes selon le libellé qui la
 * désigne. C'était le cas avant, et c'est ce qui avait laissé passer huit
 * pilotes rangés dans la mauvaise écurie.
 */
const ECURIES = {
  Ferrari: "#FF2800",
  McLaren: "#FF8000",
  Mercedes: "#00D2BE",
  "Aston Martin": "#006F44",
  "Red Bull": "#1E3A8A",
  Williams: "#37BEDD",
  Alpine: "#0090FF",
  Haas: "#212121",
  "Racing Bulls": "#6CBBEE",
  // La clé canonique reste « Audi », la forme qu'écrit
  // `backend/app/calcul/pilotes.py` ; « Audi F1 Team » est servie par les alias
  // juste en dessous et rend exactement la même teinte.
  Audi: "#FF4D4D",
  Cadillac: "#9CA3AF",
};

/**
 * La grille 2026, écurie par écurie, dans les libellés qu'Unibet emploie.
 *
 * **Elle est identique à celle de `backend/app/calcul/pilotes.py`**, et ce n'est
 * pas une coïncidence à entretenir à la main : c'est cette table-là qui valide
 * le marché « Ecurie Vainqueur » et attribue les points. Les deux doivent dire
 * la même chose, sans quoi un widget peindrait un pilote aux couleurs d'une
 * écurie qui ne le paie pas. Toute correction ici se relit là-bas, et
 * réciproquement.
 */
const GRILLE = {
  Mercedes: ["AK.Antonelli", "A.Antonelli", "G.Russell"],
  Ferrari: ["L.Hamilton", "C.Leclerc"],
  "Red Bull": ["M.Verstappen", "I.Hadjar"],
  McLaren: ["L.Norris", "O.Piastri"],
  Alpine: ["F.Colapinto", "P.Gasly"],
  Audi: ["G.Bortoleto", "N.Hulkenberg"],
  "Racing Bulls": ["A.Lindblad", "L.Lawson"],
  "Aston Martin": ["F.Alonso", "L.Stroll"],
  Haas: ["E.Ocon", "O.Bearman"],
  Williams: ["A.Albon", "C.Sainz Jr"],
  Cadillac: ["S.Perez", "V.Bottas"],
};

/** Pilote → couleur (marchés « Vainqueur », « Podium », duels…). */
export const COULEURS_ECURIES = Object.fromEntries(
  Object.entries(GRILLE).flatMap(([ecurie, pilotes]) =>
    pilotes.map((pilote) => [pilote, ECURIES[ecurie]]),
  ),
);

/** Écurie → couleur (marché « Ecurie Vainqueur »). */
export const COULEURS_NOMS_ECURIES = { ...ECURIES };

/**
 * Orthographes qu'Unibet emploie pour les mêmes écuries.
 *
 * Elles vivent à part des deux tables exportées, qui décrivent la grille telle
 * qu'on veut la lire : le bookmaker écrit « Red Bull » un week-end et « Red Bull
 * Racing » le suivant, exactement comme il écrit « GP Pays Bas » puis « GP
 * Pays-Bas » (étape 4). C'est le même mécanisme que les alias de
 * `backend/app/calcul/pilotes.py` et ceux de `slugCircuit`.
 *
 * **Les formes d'OpenF1 y figurent aussi** — « Red Bull Racing », « Haas F1
 * Team », « Audi » — parce que ce sont elles que `pilotes.py` écrit et que le
 * marché « Ecurie Vainqueur » doit retrouver de part et d'autre.
 */
const ALIAS_ECURIES = {
  "Red Bull Racing": "Red Bull",
  "Oracle Red Bull Racing": "Red Bull",
  "Haas F1 Team": "Haas",
  "MoneyGram Haas": "Haas",
  "Audi F1 Team": "Audi",
  "Audi Sauber": "Audi",
  Sauber: "Audi",
  "Alpine F1 Team": "Alpine",
  "BWT Alpine": "Alpine",
  "Aston Martin Aramco": "Aston Martin",
  "Visa Cash App RB": "Racing Bulls",
  RB: "Racing Bulls",
  "Cadillac F1 Team": "Cadillac",
  "Scuderia Ferrari": "Ferrari",
  "Mercedes AMG": "Mercedes",
  "Williams Racing": "Williams",
};

const ALIAS = Object.fromEntries(
  Object.entries(ALIAS_ECURIES).map(([libelle, ecurie]) => [
    libelle,
    ECURIES[ecurie],
  ]),
);

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
