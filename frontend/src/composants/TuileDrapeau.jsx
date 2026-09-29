import { IconeDrapeau } from "./Icones.jsx";

/**
 * Le drapeau blanc sur sa tuile bordeaux — l'icône des cellules qui ouvrent des
 * **Grands Prix** : « Ses Grands Prix » d'un profil, « Résultats par Grand
 * Prix » d'un championnat. **Un seul habillage**, pour que les deux cellules ne
 * divergent pas. Contrepartie de `TuileDrapeauDamier` de l'app iOS.
 */
export default function TuileDrapeau() {
  return (
    <span
      aria-hidden="true"
      className="bg-primaire rounded-champ flex size-[46px] shrink-0 items-center justify-center text-white"
    >
      <IconeDrapeau className="size-[22px]" />
    </span>
  );
}
