import TexteEchange from "./TexteEchange.jsx";

const VARIANTES = {
  principal: "bg-primaire text-white",
  secondaire: "bg-surface text-primaire",
  social: "bg-surface text-texte",
};

/**
 * Bouton pleine largeur des maquettes 01 a 06.
 * `occupe` remplace le libelle sans changer la taille du bouton et neutralise
 * les appuis, pour qu'un double envoi soit impossible.
 *
 * `damier` pose le motif de `assets/06.svg` par-dessus l'aplat. Il est **opt-in
 * et non un defaut** : ce composant sert tous les boutons principaux de
 * l'application — connexion, inscription, enregistrement du profil, validation
 * des pronostics — et texturer les vingt d'un coup irait bien au-dela de ce qui
 * a ete demande. Seule la « Vue piste » le porte aujourd'hui.
 */
export default function Bouton({
  variante = "principal",
  occupe = false,
  libelleOccupe = "Un instant…",
  icone = null,
  damier = false,
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
      } ${damier ? "relative overflow-hidden" : ""} ${
        inactif ? "opacity-60" : ""
      } ${className}`}
      {...reste}
    >
      {/* `overflow-hidden` n'est pose qu'avec le damier : sans lui le motif
          deborderait des coins arrondis. Le contenu passe en `relative` pour
          rester au-dessus, le motif etant en `absolute`. */}
      {damier && (
        <span
          aria-hidden="true"
          className="motif-damier pointer-events-none absolute inset-0"
        />
      )}
      {icone && <span className="relative flex">{icone}</span>}
      <TexteEchange
        valeur={occupe ? libelleOccupe : children}
        className={`relative ${enfantsClassName}`}
      />
    </button>
  );
}
