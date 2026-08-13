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

/** « 2j 14h 32min », puis « 32min 10s » dans la dernière heure. */
export function formaterRestant(millisecondes) {
  const total = Math.max(0, Math.floor(millisecondes / 1000));
  const jours = Math.floor(total / 86400);
  const heures = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secondes = total % 60;

  if (jours > 0) return `${jours}j ${heures}h ${minutes}min`;
  if (heures > 0) return `${heures}h ${minutes}min`;
  // Sous l'heure, les minutes seules ne suffisent plus à dire l'urgence.
  if (minutes > 0) return `${minutes}min ${secondes}s`;
  return `${secondes}s`;
}
