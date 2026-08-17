/**
 * Mise en forme des valeurs affichées : points, dates de course, compte à
 * rebours de fermeture.
 *
 * **Règle 4.1, appliquée ici et nulle part ailleurs.** Une cote brute ne
 * s'affiche jamais : ni « ×2,80 », ni « cote 2,80 ». Ce qui arrive du backend
 * est déjà un nombre de points entier, et `formaterPoints` est le seul endroit
 * qui l'habille. Les maquettes 08 et 09 écrivent « ×2,80 » dans leurs cases de
 * cote : le CLAUDE.md gagne, elles affichent « 280 pts ».
 */

/** Règle 4.3 : les pronostics ferment cinq minutes avant le départ. */
export const MARGE_FERMETURE_MS = 5 * 60 * 1000;

export function formaterPoints(points) {
  if (points === null || points === undefined) return "Cote retirée";
  return `${points} pts`;
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
 * `anime` dit quels blocs rejouent le mouvement à chaque changement : les
 * secondes en sont exclues, une animation par seconde étant une animation
 * perpétuelle, pas un accusé de changement.
 */
export function blocsRestant(millisecondes) {
  if (millisecondes === null || millisecondes === undefined) return null;

  const { jours, heures, minutes, secondes } = decouperRestant(millisecondes);
  const pad = (n) => String(n).padStart(2, "0");

  if (jours === 0 && heures === 0) {
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
