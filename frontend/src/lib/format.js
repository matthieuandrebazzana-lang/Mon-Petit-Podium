/**
 * Mise en forme des valeurs affichées : points, dates de course, compte à
 * rebours de fermeture.
 *
 * **Règle 4.1, appliquée ici et nulle part ailleurs.** Une cote brute ne
 * s'affiche jamais : ni « ×2,80 », ni « cote 2,80 ». Ce qui arrive du backend
 * est déjà un nombre de points entier, et `formaterPoints` est le seul endroit
 * qui l'habille. Les maquettes 08 et 09 écrivent « ×2,80 » dans leurs cases de
 * cote : le CLAUDE.md gagne, elles affichent « 28 pts ».
 */

/** Règle 4.3 : les pronostics ferment cinq minutes avant le départ. */
export const MARGE_FERMETURE_MS = 5 * 60 * 1000;

/**
 * Le nombre de points, découpé en sa valeur et son unité.
 *
 * Les widgets de cote écrivent les deux à deux tailles différentes — le nombre
 * en gras, « pts » en petit à côté — et ne peuvent donc pas se contenter de la
 * chaîne toute faite. Le découpage vit ici plutôt que dans l'écran pour que la
 * règle 4.1 continue de n'avoir qu'un seul point d'application : un écran qui
 * fabriquerait `${points} pts` lui-même finirait un jour par écrire la cote.
 *
 * `retiree` est le troisième état, celui d'une issue qu'Unibet a retirée depuis
 * la saisie : il n'y a alors ni valeur ni unité, et c'est à l'appelant de le
 * dire à sa manière — jamais à cette fonction d'inventer un zéro.
 */
export function decouperPoints(points) {
  if (points === null || points === undefined) {
    return { retiree: true, valeur: null, unite: null };
  }
  return { retiree: false, valeur: String(points), unite: "pts" };
}

export function formaterPoints(points) {
  const decoupe = decouperPoints(points);
  if (decoupe.retiree) return "Cote retirée";
  return `${decoupe.valeur} ${decoupe.unite}`;
}

/**
 * Le libellé d'un pilote, tel qu'on veut le lire.
 *
 * **Unibet n'écrit pas tous ses pilotes de la même façon.** La quasi-totalité
 * de la grille arrive en « initiale + nom » — « M.Verstappen », « C.Leclerc »,
 * « AK.Antonelli ». Quelques-uns arrivent en nom complet, et se lisent alors
 * comme des intrus dans une liste de vingt-deux lignes : « Franco Colapinto »
 * fait deux fois la largeur de ses voisins, déborde du widget qui l'affiche, et
 * casse l'alignement de la grille.
 *
 * C'est le même mécanisme que les `alias` de `backend/app/calcul/pilotes.py`,
 * et il est ici pour la même raison : ces écarts sont **irréductibles par une
 * règle**. On ne peut pas abréger automatiquement tout libellé à deux mots —
 * « Red Bull » et « Aston Martin » sont des écuries, et le marché « Ecurie
 * Vainqueur » les nomme exactement comme ça. Les cas sont donc listés un par
 * un, et **tout ce qui n'est pas dans la table ressort intact**.
 *
 * La clé est normalisée (minuscules, accents ramenés à la lettre de base,
 * espaces fondus) : Unibet écrit tantôt « Pays Bas » tantôt « Pays-Bas » sur ses
 * Grands Prix, rien ne garantit qu'il soit plus régulier sur ses pilotes.
 */
const LIBELLES_PILOTES = {
  "franco colapinto": "F.Colapinto",
};

/**
 * La clé de comparaison d'un libellé de pilote.
 *
 * Exportée parce qu'elle sert à **deux** choses, et que les deux doivent se
 * faire sur exactement la même clé : nommer un pilote (`formaterPilote`), et le
 * reconnaître d'un marché à l'autre.
 *
 * Ce second usage n'est pas un raffinement. **Un même pilote ne porte pas le
 * même `id_outcome_unibet` selon le marché** — Antonelli vaut `o701093319` au
 * marché « Vainqueur » et `o701094802` au marché « Podium » du même Grand Prix
 * (relevé à la version `0.6.1`). Comparer deux identifiants d'issue pour savoir
 * s'il s'agit du même pilote ne marcherait donc jamais entre deux marchés : la
 * seule chose que les deux partagent est le libellé.
 */
export function clePilote(nom) {
  if (nom === null || nom === undefined) return "";
  return String(nom)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

export function formaterPilote(nom) {
  if (nom === null || nom === undefined || nom === "") return nom;
  return LIBELLES_PILOTES[clePilote(nom)] ?? nom;
}

/** Date de départ en heure locale, découpée pour la sous-ligne des maquettes. */
export function formaterDepart(iso) {
  if (!iso) return { jour: "Date à confirmer", heure: null, courte: null };

  const depart = new Date(iso);
  if (Number.isNaN(depart.getTime())) {
    return { jour: "Date à confirmer", heure: null, courte: null };
  }

  const jour = new Intl.DateTimeFormat("fr-FR", {
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(depart);

  const heure = new Intl.DateTimeFormat("fr-FR", {
    hour: "2-digit",
    minute: "2-digit",
  })
    .format(depart)
    // « 15:00 » → « 15h00 », l'écriture des maquettes.
    .replace(":", "h");

  const courte = new Intl.DateTimeFormat("fr-FR", {
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(depart);

  // La première lettre du jour est en minuscule en français ; les maquettes
  // l'écrivent en capitale en tête de ligne.
  return { jour: jour.charAt(0).toUpperCase() + jour.slice(1), heure, courte };
}

/**
 * Le jour et le mois d'un départ, séparés — la date en gros chiffre des cartes
 * de Grand Prix, avec son mois en dessous.
 *
 * `null` quand l'horaire n'est pas encore annoncé : c'est à l'appelant de dire
 * « date à confirmer » à sa manière, jamais à cette fonction d'inventer un
 * chiffre. C'est la même règle que `formaterDepart`, qui rend `courte: null`
 * dans ce cas.
 *
 * Le mois est capitalisé ici et non par une classe `uppercase` : `août` porte un
 * accent que `text-transform` gère bien, mais le rendre en JavaScript garde le
 * texte lisible tel quel pour un lecteur d'écran.
 */
export function formaterJourMois(iso) {
  if (!iso) return null;
  const depart = new Date(iso);
  if (Number.isNaN(depart.getTime())) return null;

  const jour = new Intl.DateTimeFormat("fr-FR", { day: "numeric" }).format(depart);
  const mois = new Intl.DateTimeFormat("fr-FR", { month: "short" })
    .format(depart)
    // « août » → « AOÛT ». Le point de « sept. » n'apporte rien sous un chiffre.
    .replace(".", "")
    .toUpperCase();

  return { jour, mois };
}

/** Instant de fermeture des pronostics, ou `null` si l'heure est inconnue. */
export function instantFermeture(iso) {
  if (!iso) return null;
  const depart = new Date(iso).getTime();
  if (Number.isNaN(depart)) return null;
  return depart - MARGE_FERMETURE_MS;
}

/**
 * État de la fermeture à l'instant `maintenant`.
 *
 * Un GP dont l'heure de départ n'est pas connue reste **ouvert** : c'est la
 * même règle que côté backend et côté base, et refuser tout le monde parce
 * qu'Unibet n'a pas encore annoncé l'horaire serait le mauvais sens du doute.
 */
export function etatFermeture(iso, maintenant = Date.now()) {
  const fermeture = instantFermeture(iso);
  if (fermeture === null) return { ferme: false, restant: null, texte: null };

  const restant = fermeture - maintenant;
  if (restant <= 0) return { ferme: true, restant: 0, texte: null };

  return { ferme: false, restant, texte: formaterRestant(restant) };
}

/** Le temps restant découpé en unités. Une seule source pour les deux
 *  présentations : la phrase et les blocs du compte à rebours. */
export function decouperRestant(millisecondes) {
  const total = Math.max(0, Math.floor(millisecondes / 1000));
  return {
    jours: Math.floor(total / 86400),
    heures: Math.floor((total % 86400) / 3600),
    minutes: Math.floor((total % 3600) / 60),
    secondes: total % 60,
  };
}

/**
 * Le compte à rebours en trois blocs, pour l'affichage horloge de l'écran
 * récapitulatif. `null` tant que la fermeture n'est pas datée.
 *
 * **Trois blocs, toujours, mais pas toujours les trois mêmes unités.** Au-delà
 * d'une heure ce sont les jours, les heures et les minutes. En deçà, l'horloge
 * glisse d'un cran vers les secondes : à quinze minutes du départ, un bloc
 * « jours » figé à zéro ne dit rien, et un compte à rebours dont la plus petite
 * unité ne bouge plus qu'une fois par minute paraît arrêté. C'est déjà la règle
 * de `formaterRestant`, qui passe à « 32min 10s » dans la dernière heure.
 *
 * **`avecSecondes: false` interdit ce glissement** : les trois blocs restent
 * alors toujours jours / heures / minutes. C'est ce que demande l'écran de
 * saisie, dont l'horloge est un repère de planification — on y vient pour
 * savoir s'il reste du temps, pas pour compter les dernières secondes, et une
 * unité qui change de nature sous les yeux y serait un mouvement pour rien.
 *
 * `anime` dit quels blocs rejouent le mouvement à chaque changement : les
 * secondes en sont exclues, une animation par seconde étant une animation
 * perpétuelle, pas un accusé de changement.
 */
export function blocsRestant(millisecondes, { avecSecondes = true } = {}) {
  if (millisecondes === null || millisecondes === undefined) return null;

  const { jours, heures, minutes, secondes } = decouperRestant(millisecondes);
  const pad = (n) => String(n).padStart(2, "0");

  if (avecSecondes && jours === 0 && heures === 0) {
    return [
      { cle: "h", valeur: pad(heures), label: "Heures", anime: true },
      { cle: "m", valeur: pad(minutes), label: "Minutes", anime: true },
      { cle: "s", valeur: pad(secondes), label: "Secondes", anime: false },
    ];
  }

  return [
    { cle: "j", valeur: pad(jours), label: "Jours", anime: true },
    { cle: "h", valeur: pad(heures), label: "Heures", anime: true },
    { cle: "m", valeur: pad(minutes), label: "Minutes", anime: true },
  ];
}

/** « 2j 14h 32min », puis « 32min 10s » dans la dernière heure. */
export function formaterRestant(millisecondes) {
  const { jours, heures, minutes, secondes } = decouperRestant(millisecondes);

  if (jours > 0) return `${jours}j ${heures}h ${minutes}min`;
  if (heures > 0) return `${heures}h ${minutes}min`;
  // Sous l'heure, les minutes seules ne suffisent plus à dire l'urgence.
  if (minutes > 0) return `${minutes}min ${secondes}s`;
  return `${secondes}s`;
}
