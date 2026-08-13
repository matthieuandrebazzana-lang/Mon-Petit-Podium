import { IconeEtoile } from "./Icones.jsx";

/**
 * Bouton favori de la maquette 08, avec l'échange d'icônes de
 * transitions-dev 09 : le contour et l'étoile pleine partagent la même
 * cellule, l'une entre pendant que l'autre sort.
 *
 * La zone tactile fait 44px (contrainte iOS du CLAUDE.md) alors que l'étoile
 * n'en occupe que 18 : les marges négatives absorbent le surplus pour que
 * l'étoile reste calée là où la maquette la place, sur la même ligne que la
 * cote. Sans elles, chaque rangée gagnerait 26px de haut.
 */
export default function EtoileFavori({ favori, onClick, disabled, nom }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={favori}
      aria-label={favori ? `Retirer ${nom} des favoris` : `Mettre ${nom} en favori`}
      className="pressable size-tactile -my-3 -mr-2.5 flex shrink-0 items-center justify-center"
    >
      <span
        className="t-icon-swap size-[18px]"
        data-state={favori ? "b" : "a"}
        aria-hidden="true"
      >
        <IconeEtoile className="t-icon size-[18px] text-texte-doux/50" data-icon="a" />
        <IconeEtoile
          pleine
          className="t-icon size-[18px] text-accent"
          data-icon="b"
        />
      </span>
    </button>
  );
}
