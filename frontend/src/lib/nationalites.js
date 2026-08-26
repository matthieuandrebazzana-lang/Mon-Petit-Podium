/**
 * La nationalité d'un pilote de la grille 2026, en code ISO 3166-1 alpha-2.
 *
 * **Pourquoi ce module existe.** L'écran de résultats pose le drapeau du pilote
 * en fond de sa ligne de classement, et rien de ce que le serveur envoie ne dit
 * de quel pays il est : le classement porte un numéro de voiture, un nom
 * complet et une écurie, jamais un pays. `country_code` de `/drivers` d'OpenF1
 * est déprécié et disparaît fin 2026 (`scraper.md` §9) — la nationalité ne peut
 * donc venir que d'une table statique, et c'est celle-ci.
 *
 * **C'est la contrepartie frontend du champ `nationalite` de
 * `backend/app/calcul/pilotes.py`**, exactement comme `lib/ecuries.js` est la
 * contrepartie de sa grille. Les deux tables décrivent les mêmes pilotes et
 * doivent dire la même chose : toute correction ici se relit là-bas, et
 * réciproquement.
 *
 * > **Écart signalé (CLAUDE.md §6) : elles ne disent PLUS la même chose.**
 * > Tsunoda est ici et pas dans `pilotes.py`. Les deux tables ne servent pas
 * > la même question — celle-ci habille un classement déjà publié, celle
 * > là-bas rapproche des libellés Unibet pour **calculer des points** — et
 * > seule la seconde demande un déploiement Railway, que ce commit ne porte
 * > pas. La conséquence de l'écart est bornée et connue : si Tsunoda gagnait,
 * > le marché « nationalité du vainqueur » resterait `NULL`, donc rattrapable,
 * > jamais `0`. `roadmap.md`.
 *
 * **Les codes, en revanche, ne sont pas les mêmes et ne
 * peuvent pas l'être** — `pilotes.py` emploie les codes CIO à trois lettres
 * (« GBR », « NED », « MON ») parce que c'est la langue du sport ; ce module
 * emploie l'ISO 3166-1 alpha-2 (« GB », « NL », « MC ») parce que c'est la clé
 * qu'une planche de drapeaux comprend. La conversion est écrite pilote par
 * pilote plutôt que dérivée par une table CIO → ISO : seize correspondances ne
 * valent pas une seconde table à tenir, et trois d'entre elles ne se devinent
 * pas (NED → NL, GER → DE, MON → MC).
 *
 * **Aucun dessin n'entre ici.** Les formes vivent dans
 * `composants/DrapeauxPilotes.jsx`, pour la raison qui sépare déjà
 * `lib/livrees.js` de `composants/VoituresEcuries.jsx` : ce module est une
 * table de vingt-trois lignes, et le faire porter les drapeaux embarquerait leur
 * dessin dans le lot de tout écran qui voudrait seulement savoir de quel pays
 * est un pilote.
 *
 * **À mettre à jour à chaque saison**, comme `lib/ecuries.js`,
 * `lib/calendrier2026.js` et `backend/app/calcul/pilotes.py`. Une table périmée
 * ne fait aucun dégât silencieux : le garde-fou ci-dessous laisse la ligne sans
 * drapeau, ce qui se voit, plutôt que de prêter la nationalité d'un pilote à
 * son successeur.
 */

/** Saison décrite par la table — la même mention que `pilotes.py`, et pour la
 *  même raison : lire « 2026 » en 2027 dit immédiatement ce qu'il y a à faire. */
export const SAISON = 2026;

/**
 * Les vingt-trois pilotes que la saison 2026 a fait courir.
 *
 * `nom` est écrit **dans la forme d'OpenF1** (`full_name`, « Lando Norris ») :
 * c'est elle que `classement_du_grand_prix` sert sous la clé `pilote`, et c'est
 * sur son dernier mot que porte le garde-fou. `unibet` reprend le libellé de
 * `lib/ecuries.js`, pour que la même question posée depuis un widget de cote
 * trouve la même réponse. `pays` est le libellé français affiché — le drapeau
 * n'est qu'une texture, c'est le mot qui porte le sens.
 */
const PILOTES = [
  { numero: 1, nom: "Lando Norris", unibet: "L.Norris", code: "GB", pays: "Royaume-Uni" },
  { numero: 3, nom: "Max Verstappen", unibet: "M.Verstappen", code: "NL", pays: "Pays-Bas" },
  { numero: 5, nom: "Gabriel Bortoleto", unibet: "G.Bortoleto", code: "BR", pays: "Brésil" },
  { numero: 6, nom: "Isack Hadjar", unibet: "I.Hadjar", code: "FR", pays: "France" },
  { numero: 10, nom: "Pierre Gasly", unibet: "P.Gasly", code: "FR", pays: "France" },
  { numero: 11, nom: "Sergio Perez", unibet: "S.Perez", code: "MX", pays: "Mexique" },
  // Les deux libellés d'Antonelli sont ceux que `pilotes.py` liste en alias :
  // OpenF1 abrège « Andrea Kimi » en « Kimi », Unibet garde les deux initiales.
  {
    numero: 12,
    nom: "Kimi Antonelli",
    unibet: "AK.Antonelli",
    alias: ["A.Antonelli", "Andrea Kimi Antonelli"],
    code: "IT",
    pays: "Italie",
  },
  { numero: 14, nom: "Fernando Alonso", unibet: "F.Alonso", code: "ES", pays: "Espagne" },
  { numero: 16, nom: "Charles Leclerc", unibet: "C.Leclerc", code: "MC", pays: "Monaco" },
  { numero: 18, nom: "Lance Stroll", unibet: "L.Stroll", code: "CA", pays: "Canada" },
  // Tsunoda n'est pas dans les vingt-deux libellés relevés sur les cotes du GP
  // Pays-Bas 2026, d'où son absence jusqu'ici — mais il figure au CLASSEMENT
  // servi par OpenF1, et c'est ce classement que cette table habille. Une ligne
  // sans drapeau se voyait ; elle n'avait pas de raison d'être.
  { numero: 22, nom: "Yuki Tsunoda", unibet: "Y.Tsunoda", code: "JP", pays: "Japon" },
  { numero: 23, nom: "Alexander Albon", unibet: "A.Albon", code: "TH", pays: "Thaïlande" },
  { numero: 27, nom: "Nico Hulkenberg", unibet: "N.Hulkenberg", code: "DE", pays: "Allemagne" },
  { numero: 30, nom: "Liam Lawson", unibet: "L.Lawson", code: "NZ", pays: "Nouvelle-Zélande" },
  { numero: 31, nom: "Esteban Ocon", unibet: "E.Ocon", code: "FR", pays: "France" },
  { numero: 41, nom: "Arvid Lindblad", unibet: "A.Lindblad", code: "GB", pays: "Royaume-Uni" },
  { numero: 43, nom: "Franco Colapinto", unibet: "F.Colapinto", code: "AR", pays: "Argentine" },
  { numero: 44, nom: "Lewis Hamilton", unibet: "L.Hamilton", code: "GB", pays: "Royaume-Uni" },
  // Unibet suffixe « Jr », OpenF1 non — le même écart que traite `pilotes.py`.
  {
    numero: 55,
    nom: "Carlos Sainz",
    unibet: "C.Sainz Jr",
    alias: ["Carlos Sainz Jr"],
    code: "ES",
    pays: "Espagne",
  },
  { numero: 63, nom: "George Russell", unibet: "G.Russell", code: "GB", pays: "Royaume-Uni" },
  { numero: 77, nom: "Valtteri Bottas", unibet: "V.Bottas", code: "FI", pays: "Finlande" },
  { numero: 81, nom: "Oscar Piastri", unibet: "O.Piastri", code: "AU", pays: "Australie" },
  { numero: 87, nom: "Oliver Bearman", unibet: "O.Bearman", code: "GB", pays: "Royaume-Uni" },
];

/**
 * Minuscules, accents ôtés, ponctuation fondue en espace. Elle duplique
 * volontairement `clePilote` de `lib/format.js` en trois lignes, pour la raison
 * déjà retenue par `lib/ecuries.js` : ce module ne doit rien importer qui
 * puisse un jour l'importer en retour.
 */
function cle(texte) {
  return String(texte ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[\s.-]+/g, " ");
}

/** Le dernier mot d'un nom complet — « Lando Norris » → « norris ». */
function nomDeFamille(nom) {
  const mots = cle(nom).split(" ").filter(Boolean);
  return mots[mots.length - 1] ?? "";
}

const PAR_NUMERO = new Map(PILOTES.map((pilote) => [pilote.numero, pilote]));

/**
 * Index { libellé normalisé → pilote }, pour les appelants qui n'ont qu'un nom.
 *
 * **Une clé revendiquée par deux pilotes est retirée plutôt qu'attribuée au
 * premier venu** — la règle de `pilotes._indexer_nationalites` et de
 * `points._indexer_pilotes`. Le cas n'existe pas dans la grille 2026 ; il
 * existera le jour où deux frères courront ensemble, et mieux vaut alors ne
 * poser aucun drapeau que le mauvais.
 */
const PAR_LIBELLE = (() => {
  const vus = new Map();
  const ambigus = new Set();

  for (const pilote of PILOTES) {
    const libelles = [
      pilote.nom,
      pilote.unibet,
      ...(pilote.alias ?? []),
      nomDeFamille(pilote.nom),
    ];
    for (const libelle of libelles) {
      const k = cle(libelle);
      if (!k) continue;
      if (vus.has(k) && vus.get(k) !== pilote) ambigus.add(k);
      else vus.set(k, pilote);
    }
  }

  for (const k of ambigus) vus.delete(k);
  return vus;
})();

/**
 * La nationalité d'un pilote : `{ code, pays }`, ou `null`.
 *
 * **Le numéro ET le nom de famille doivent concorder**, et c'est tout le
 * garde-fou du module — celui d'`alias_unibet` dans `pilotes.py`, transposé.
 * Les numéros sont réattribués d'une saison à l'autre : si le 12 n'est plus
 * Antonelli, une table périmée ne collera pas le drapeau italien sur son
 * successeur, elle ne rendra rien. Une ligne sans drapeau se voit ; une ligne
 * sous le mauvais drapeau ne se voit pas.
 *
 * Le nom seul reste accepté quand le numéro manque ou n'est pas dans la table —
 * c'est le cas d'un pilote remplaçant, où le nom est la seule chose qu'on ait.
 * Il ne rend jamais qu'un pilote **non ambigu** (voir `PAR_LIBELLE`).
 */
export function nationaliteDuPilote(numero, nom) {
  const parNumero = PAR_NUMERO.get(Number(numero));
  if (parNumero) {
    const attendu = nomDeFamille(parNumero.nom);
    const recu = nomDeFamille(nom);
    // Pas de nom fourni : le numéro suffit, l'appelant n'a rien à confronter.
    if (!recu) return { code: parNumero.code, pays: parNumero.pays };
    // Un nom fourni qui ne concorde pas : la table est périmée, on se tait.
    if (recu !== attendu) return null;
    return { code: parNumero.code, pays: parNumero.pays };
  }

  const parNom = PAR_LIBELLE.get(cle(nom));
  return parNom ? { code: parNom.code, pays: parNom.pays } : null;
}

/** Les codes ISO que la grille 2026 emploie, sans doublon. Sert au contrôle de
 *  concordance avec la planche de drapeaux — un code déclaré ici sans dessin
 *  là-bas laisserait une ligne sans fond, ce qui n'est pas une panne mais se
 *  vérifie mieux en une ligne qu'à l'œil. */
export const CODES_PAYS = [...new Set(PILOTES.map((pilote) => pilote.code))].sort();
