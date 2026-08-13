import { useEffect, useRef } from "react";

/**
 * Nombre qui se remet en place à chaque changement (transitions-dev 02).
 *
 * Le compteur de bonus de la maquette 09 : sans mouvement, un chiffre qui
 * passe de 1 à 2 sous le doigt qui touche une autre ligne est invisible.
 *
 * Le retrait de la classe, le reflow forcé et sa remise sont les trois temps
 * qui rejouent l'animation. Sans `void offsetHeight` entre les deux, le
 * navigateur regroupe les changements et rien ne bouge.
 */
export default function Compteur({ valeur, className = "" }) {
  const groupe = useRef(null);

  useEffect(() => {
    const element = groupe.current;
    if (!element) return;
    element.classList.remove("is-animating");
    void element.offsetHeight;
    element.classList.add("is-animating");
  }, [valeur]);

  return (
    <span ref={groupe} className={`t-digit-group ${className}`}>
      {/* Un seul caractère : pas de `data-stagger`, il n'a personne derrière
          qui décaler. Le nombre de bonus ne dépasse jamais un chiffre. */}
      <span className="t-digit">{valeur}</span>
    </span>
  );
}
