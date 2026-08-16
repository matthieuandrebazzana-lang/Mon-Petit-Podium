import TexteEchange from "./TexteEchange.jsx";

const VARIANTES = {
  principal: "bg-primaire text-white",
  secondaire: "bg-surface text-primaire",
  social: "bg-surface text-texte",
};

/**
 * Bouton pleine largeur des maquettes 01 à 06.
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
      className={`rounded-carte-sm shadow-carte pressable min-h-tactile flex w-full items-center justify-center gap-2.5 px-5 py-[18px] text-center text-[16px] font-medium ${
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
