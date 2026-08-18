import { IconeEtoile } from "./Icones.jsx";

/**
 * Bouton favori de la maquette 08, avec l'échange d'icônes de
 * transitions-dev 09 : le contour et l'étoile pleine partagent la même
 * cellule, l'une entre pendant que l'autre sort.
 *
 * **L'étoile redevient un trait nu, sans sa pastille.** La version `0.12.0`
 * l'avait posée dans un disque qui virait à l'ambre, parce qu'elle vivait alors
 * au bout d'une ligne de liste où deux nuances d'étoile ne se distinguaient
 * pas. Elle vit maintenant dans le coin d'un widget de 90px, sur une surface
 * blanche qui n'appartient qu'à une seule cote : le contraste entre le contour
 * gris et l'aplat ambre suffit, et un disque de plus dans un widget déjà petit
 * mangerait la place du nom.
 *
 * **Le gris du contour est mesuré, pas choisi.** Le `texte-doux` `#999999` du
 * design system ne vaut que 2,85:1 sur du blanc, sous le plancher de 3:1 exigé
 * d'un élément graphique porteur de sens (WCAG 1.4.11) — et l'étoile est ici le
 * seul indicateur de l'état « pas en favori ». Le marron `secondaire` du design
 * system à 60 % le porte à 3,4:1 sans introduire de couleur nouvelle, et sa
 * chaleur va avec le beige de l'app.
 *
 * La zone tactile fait 44px (contrainte iOS du CLAUDE.md) pour une étoile de
 * 22 : c'est à l'appelant de la caler, d'où `className`.
 */
export default function EtoileFavori({
  favori,
  onClick,
  disabled,
  nom,
  className = "",
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={favori}
      aria-label={favori ? `Retirer ${nom} des favoris` : `Mettre ${nom} en favori`}
      className={`pressable size-tactile flex shrink-0 items-center justify-center ${className}`}
    >
      <span
        aria-hidden="true"
        className="t-icon-swap size-[22px]"
        data-state={favori ? "b" : "a"}
      >
        <IconeEtoile
          className="t-icon text-secondaire/60 size-[22px]"
          data-icon="a"
        />
        <IconeEtoile
          pleine
          className="t-icon text-accent size-[22px]"
          data-icon="b"
        />
      </span>
    </button>
  );
}
