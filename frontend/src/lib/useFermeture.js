import { useEffect, useState } from "react";
import { etatFermeture } from "./format.js";

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
