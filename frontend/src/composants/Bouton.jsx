import { useEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";

const VARIANTES = {
  principal: "bg-primaire text-white",
  secondaire: "bg-surface text-primaire",
  social: "bg-surface text-texte",
};

/**
 * Libellé qui se remplace en place : l'ancien sort par le haut en se floutant,
 * le nouveau entre par le bas. Utilisé pour « Se connecter » → « Connexion… »,
 * qui reste ainsi le même bouton au lieu de clignoter.
 */
function TexteEchange({ valeur, className = "" }) {
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

    const duree =
      parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue(
          "--text-swap-dur",
        ),
      ) || 150;

    noeud.classList.add("is-exit");
    const minuterie = setTimeout(() => {
      // flushSync : le nouveau texte doit être dans le DOM avant le reflow,
      // sinon la phase d'entrée s'exécute sur l'ancien libellé.
      flushSync(() => setAffiche(valeur));
      noeud.classList.remove("is-exit");
      noeud.classList.add("is-enter-start");
      void noeud.offsetHeight;
      noeud.classList.remove("is-enter-start");
    }, duree);

    return () => clearTimeout(minuterie);
  }, [valeur]);

  return (
    <span ref={element} className={`t-text-swap ${className}`}>
      {affiche}
    </span>
  );
}

/**
 * Bouton pleine largeur des maquettes 01 à 03.
 * `occupe` remplace le libellé sans changer la taille du bouton et neutralise
 * les appuis, pour qu'un double envoi soit impossible.
 */
export default function Bouton({
  variante = "principal",
  occupe = false,
  libelleOccupe = "Un instant…",
  icone = null,
  enfantsClassName = "",
  className = "",
  children,
  disabled,
  ...reste
}) {
  const inactif = disabled || occupe;

  return (
    <button
      type="button"
      disabled={inactif}
      aria-busy={occupe || undefined}
      className={`rounded-carte-sm pressable min-h-tactile flex w-full items-center justify-center gap-2.5 px-5 py-[18px] text-center text-[16px] font-medium ${
        VARIANTES[variante]
      } ${inactif ? "opacity-60" : ""} ${className}`}
      {...reste}
    >
      {icone}
      <TexteEchange
        valeur={occupe ? libelleOccupe : children}
        className={enfantsClassName}
      />
    </button>
  );
}
