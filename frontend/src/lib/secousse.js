import { useEffect, useRef } from "react";

/** Lit une durée du thème, en millisecondes, pour garder JS et CSS synchrones. */
export function dureeCss(nom, repli) {
  const valeur = parseFloat(
    getComputedStyle(document.documentElement).getPropertyValue(nom),
  );
  return Number.isFinite(valeur) ? valeur : repli;
}

/**
 * Rejoue la secousse d'erreur (transitions-dev 12) sur l'élément référencé.
 *
 * `.is-shaking` est volontairement séparée de `.is-error` : c'est ce qui permet
 * de relancer l'animation — retirer, forcer un reflow, remettre — sans faire
 * clignoter tout le traitement d'erreur au passage.
 *
 * @param {unknown} actif     message d'erreur, ou toute valeur non vide
 * @param {number}  tentative compteur à incrémenter pour rejouer sur un message identique
 */
export function useSecousse(actif, tentative = 0) {
  const cible = useRef(null);

  useEffect(() => {
    const element = cible.current;
    if (!element || !actif) return undefined;

    element.classList.remove("is-shaking");
    void element.offsetWidth;
    element.classList.add("is-shaking");

    const duree =
      dureeCss("--shake-dur-a", 80) * 2 + dureeCss("--shake-dur-b", 60) * 2;
    const minuterie = setTimeout(
      () => element.classList.remove("is-shaking"),
      duree + 20,
    );
    return () => clearTimeout(minuterie);
  }, [actif, tentative]);

  return cible;
}
