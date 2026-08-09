import { useEffect, useId, useState } from "react";
import { dureeCss, useSecousse } from "../lib/secousse.js";

/**
 * Champ de saisie des maquettes 02 et 03 : label 11px en capitales au-dessus,
 * saisie sur fond beige, message d'erreur en dessous.
 *
 * La section 5 interdit les bordures fines, et la maquette n'en montre aucune.
 * Le champ en porte pourtant une, transparente au repos : elle ne se colore
 * qu'au focus et en erreur. Sa largeur reste constante dans tous les états,
 * sinon la coloration décalerait le texte saisi d'un pixel.
 *
 * `tentative` doit être incrémenté à chaque soumission pour que la secousse
 * rejoue même si le message d'erreur est identique au précédent.
 */
export default function Champ({
  label,
  erreur = null,
  tentative = 0,
  className = "",
  ...proprietesInput
}) {
  const idAuto = useId();
  const id = proprietesInput.id ?? idAuto;
  const idErreur = `${id}-erreur`;
  const boite = useSecousse(erreur, tentative);

  // Le message survit à l'effacement de l'erreur le temps du fondu. Le démonter
  // aussitôt le ferait disparaître d'un coup ; le garder monté en permanence
  // réserverait une ligne vide sous chaque champ.
  const [message, setMessage] = useState(erreur);
  useEffect(() => {
    if (erreur) {
      setMessage(erreur);
      return undefined;
    }
    const minuterie = setTimeout(
      () => setMessage(null),
      dureeCss("--revert-dur", 280),
    );
    return () => clearTimeout(minuterie);
  }, [erreur]);

  return (
    <div className={`t-input-wrap ${erreur ? "is-error" : ""} ${className}`}>
      <label
        htmlFor={id}
        className="text-label text-texte-doux mb-1.5 block uppercase"
      >
        {label}
      </label>

      <div
        ref={boite}
        className={`t-input rounded-champ bg-fond border-[1.5px] ${
          erreur
            ? "is-error border-primaire"
            : "focus-within:border-texte/15 border-transparent"
        }`}
      >
        <input
          id={id}
          aria-invalid={erreur ? "true" : undefined}
          aria-describedby={erreur ? idErreur : undefined}
          className="text-corps text-texte placeholder:text-texte-doux w-full bg-transparent px-4 py-3.5 outline-none"
          {...proprietesInput}
        />
      </div>

      {message && (
        <p
          id={idErreur}
          role="alert"
          className="t-error-msg text-corps-sm text-primaire mt-1.5 px-1"
        >
          {message}
        </p>
      )}
    </div>
  );
}
