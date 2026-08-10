import { useEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { dureeCss } from "../lib/secousse.js";

/**
 * Libellé qui se remplace en place (transitions-dev 04) : l'ancien sort par le
 * haut en se floutant, le nouveau entre par le bas. Utilisé pour
 * « Se connecter » → « Connexion… » et « Copier le code » → « Code copié »,
 * qui restent ainsi le même bouton au lieu de clignoter.
 */
export default function TexteEchange({ valeur, className = "" }) {
  const element = useRef(null);
  const precedent = useRef(valeur);
  const [affiche, setAffiche] = useState(valeur);

  useEffect(() => {
    if (valeur === precedent.current) return undefined;
    precedent.current = valeur;

    const noeud = element.current;
    if (!noeud) {
      setAffiche(valeur);
      return undefined;
    }

    noeud.classList.add("is-exit");
    const minuterie = setTimeout(() => {
      // flushSync : le nouveau texte doit être dans le DOM avant le reflow,
      // sinon la phase d'entrée s'exécute sur l'ancien libellé.
      flushSync(() => setAffiche(valeur));
      noeud.classList.remove("is-exit");
      noeud.classList.add("is-enter-start");
      void noeud.offsetHeight;
      noeud.classList.remove("is-enter-start");
    }, dureeCss("--text-swap-dur", 150));

    return () => clearTimeout(minuterie);
  }, [valeur]);

  return (
    <span ref={element} className={`t-text-swap ${className}`}>
      {affiche}
    </span>
  );
}
