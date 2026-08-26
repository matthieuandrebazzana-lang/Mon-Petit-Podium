import { useEffect, useState } from "react";
import { etatFermeture } from "./format.js";
import { etatPronostics } from "./calendrier.js";

/**
 * Compte à rebours de la fermeture des pronostics (règle 4.3).
 *
 * La cadence s'adapte au temps restant : une fois par seconde dans la
 * dernière heure, une fois par demi-minute au-delà. Un compte à rebours qui
 * affiche « 2j 14h 32min » n'a rien à gagner à se recalculer soixante fois par
 * minute, et l'écran entier se rendrait à nouveau à chaque battement.
 *
 * Un `setTimeout` réarmé, plutôt qu'un `setInterval` : la cadence change en
 * cours de route, à l'entrée dans la dernière heure.
 *
 * **Ne sert plus qu'à répondre « les pronostics sont-ils fermés ? »** — le
 * tableau des cotes, qui n'affiche aucun décompte. Les trois écrans qui en
 * affichent un prennent `useEtatPronostics` ci-dessous : il connaît les deux
 * échéances du week-end, là où celui-ci ne connaît que la seconde.
 */
export function useFermeture(dateCourse) {
  const [etat, setEtat] = useState(() => etatFermeture(dateCourse));

  useEffect(() => {
    setEtat(etatFermeture(dateCourse));
    if (!dateCourse) return undefined;

    let minuterie;

    const battre = () => {
      const suivant = etatFermeture(dateCourse);
      setEtat(suivant);
      // Fermé : plus rien à décompter, la minuterie s'arrête d'elle-même.
      if (suivant.ferme || suivant.restant === null) return;
      minuterie = setTimeout(battre, suivant.restant < 3_600_000 ? 1000 : 30_000);
    };

    battre();
    return () => clearTimeout(minuterie);
  }, [dateCourse]);

  return etat;
}

/**
 * Le compte à rebours du week-end, **quelle que soit son échéance** :
 * l'ouverture des pronostics tant qu'elle n'a pas eu lieu, leur fermeture
 * ensuite. La règle vit dans `etatPronostics` (`lib/calendrier.js`) ; ce hook
 * n'apporte que le battement.
 *
 * **Les trois champs du Grand Prix sont mis en dépendance un par un, jamais
 * l'objet.** `useDonnees` sert un objet neuf à chaque revalidation en
 * arrière-plan, y compris quand rien n'a changé : l'effet se relancerait alors
 * à chaque passage du cache, et la minuterie serait détruite puis rearmée sans
 * fin. Trois chaînes se comparent par valeur.
 *
 * La minuterie s'arrête dès qu'il n'y a plus rien à décompter — pronostics
 * fermés, heure de départ inconnue, ou heure d'ouverture prévue déjà passée
 * sans que le scraper ait figé les cotes. Dans ce dernier cas c'est le
 * rafraîchissement des données qui fera basculer l'affichage, pas le temps qui
 * passe : le statut ne change qu'en base.
 */
export function useEtatPronostics(gp) {
  const statut = gp?.statut ?? null;
  const dateCourse = gp?.date_course ?? null;
  const dateQualifications = gp?.date_qualifications ?? null;
  const connu = Boolean(gp);

  const [etat, setEtat] = useState(() =>
    etatPronostics(
      connu
        ? {
            statut,
            date_course: dateCourse,
            date_qualifications: dateQualifications,
          }
        : null,
    ),
  );

  useEffect(() => {
    const lu = connu
      ? {
          statut,
          date_course: dateCourse,
          date_qualifications: dateQualifications,
        }
      : null;

    let minuterie;

    const battre = () => {
      const suivant = etatPronostics(lu);
      setEtat(suivant);
      if (!suivant.restant) return;
      minuterie = setTimeout(battre, suivant.restant < 3_600_000 ? 1000 : 30_000);
    };

    battre();
    return () => clearTimeout(minuterie);
  }, [connu, statut, dateCourse, dateQualifications]);

  return etat;
}
