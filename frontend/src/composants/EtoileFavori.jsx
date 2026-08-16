import { IconeEtoile } from "./Icones.jsx";

/**
 * Bouton favori de la maquette 08, avec l'échange d'icônes de
 * transitions-dev 09 : le contour et l'étoile pleine partagent la même
 * cellule, l'une entre pendant que l'autre sort.
 *
 * **Refonte visuelle** : l'étoile n'est plus posée à nu sur la ligne, elle vit
 * dans une pastille qui passe à l'amber `#E8A020` quand la cote est épinglée et
 * reste sur le beige de l'app sinon. L'état est ainsi lisible d'un coup d'œil
 * sur une liste de vingt-deux pilotes, là où deux nuances d'étoile demandaient
 * de regarder de près. L'étoile pleine passe à l'encre foncée du design system
 * une fois sur l'amber : en blanc, elle disparaîtrait (2,2:1 de contraste).
 *
 * La zone tactile fait 44px (contrainte iOS du CLAUDE.md) alors que la pastille
 * n'en occupe que 32 : les marges négatives absorbent exactement le surplus,
 * pour que la rangée ne gagne pas 12px de haut par cote.
 */
export default function EtoileFavori({ favori, onClick, disabled, nom }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={favori}
      aria-label={favori ? `Retirer ${nom} des favoris` : `Mettre ${nom} en favori`}
      className="pressable size-tactile -my-1.5 -mr-1.5 flex shrink-0 items-center justify-center"
    >
      <span
        aria-hidden="true"
        className={`flex size-8 items-center justify-center rounded-full ${
          favori ? "bg-accent" : "bg-fond"
        }`}
      >
        <span
          className="t-icon-swap size-[18px]"
          data-state={favori ? "b" : "a"}
        >
          <IconeEtoile
            className="t-icon text-texte-doux size-[18px]"
            data-icon="a"
          />
          <IconeEtoile
            pleine
            className="t-icon text-texte size-[18px]"
            data-icon="b"
          />
        </span>
      </span>
    </button>
  );
}
