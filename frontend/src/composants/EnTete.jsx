import { useNavigate } from "react-router-dom";
import { IconeChevronGauche } from "./Icones.jsx";

/**
 * En-tête des maquettes 02 et 03 : lien de retour puis titre de page.
 *
 * La zone tactile du retour fait 44px de haut alors que le libellé n'en occupe
 * que 16 : les marges négatives absorbent le surplus pour que le texte reste
 * calé où la maquette le place. Un bouton de 16px de haut est intouchable au
 * pouce.
 */
export default function EnTete({ titre, retourVers }) {
  const naviguer = useNavigate();

  return (
    <div className="pt-1 pb-2">
      <button
        type="button"
        onClick={() => naviguer(retourVers)}
        className="text-primaire min-h-tactile pressable -mx-2 -my-3 flex items-center gap-1.5 px-2 py-3 text-[13px] font-medium"
      >
        <IconeChevronGauche className="size-[15px]" />
        Retour
      </button>

      <h1 className="text-titre-lg text-texte mt-3.5">{titre}</h1>
    </div>
  );
}
