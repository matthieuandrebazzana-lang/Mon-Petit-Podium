import { IconeCoche } from "./Icones.jsx";
import IconeEtoileLogo from "./icones/IconeEtoileLogo.jsx";

/**
 * Bouton d'ajout d'un **pari bonus**, avec l'échange d'icônes de
 * transitions-dev 09 : les deux états partagent la même cellule, l'un entre
 * pendant que l'autre sort.
 *
 * > ### L'état non sélectionné est l'étoile de `logoV2.svg` (version `0.67.0`)
 * >
 * > La version `0.66.0` avait remplacé une étoile par un `+`, pour que le signe
 * > **nomme l'action** au lieu de dire « mis de côté ». L'étoile de la planche
 * > reprend sa place : c'est **la marque du produit**, la même que porte le
 * > logo, et elle dit ce que le `+` disait par un dessin qui appartient à
 * > l'app. Le couple étoile → coche garde la promesse du couple d'avant — un
 * > état à remplir, un état rempli.
 * >
 * > **Les trois textes qui renvoient au `+` n'ont pas suivi** : le mode
 * > d'emploi et la zone vide du tableau des cotes (`Cotes.jsx`), la zone vide
 * > de l'écran de saisie (`Pronostics.jsx`), et la rangée de `Pronostics.jsx`
 * > qui refait le même échange d'icônes en ligne. Ils disent encore « avec le
 * > + » devant une étoile — écart signalé, hors du périmètre demandé.
 * >
 * > Les noms de ce fichier, du composant et de sa prop **ne bougent pas** :
 * > c'est un changement de vocabulaire d'interface, et l'écriture en base
 * > (`POST /favoris`) est la même.
 *
 * **Le gris de l'étoile est mesuré, pas choisi.** Le `texte-doux` `#999999` du
 * design system ne vaut que 2,85:1 sur du blanc, sous le plancher de 3:1 exigé
 * d'un élément graphique porteur de sens (WCAG 1.4.11) — et le signe est ici le
 * seul indicateur de l'état « pas encore ajouté ». Le marron `secondaire` du
 * design system à 60 % le porte à 3,4:1 sans introduire de couleur nouvelle,
 * 3,16:1 au pire des onze teintes d'écurie du widget. L'encre ne change pas en
 * passant du `+` à l'étoile : l'aplat en couvre plus de surface que le trait,
 * donc le rapport tenu au trait l'est a fortiori.
 *
 * **La coche est une encre foncée sur un aplat ambre, jamais une coche ambre.**
 * `#E8A020` tracé sur le blanc du widget ne vaut que 2,2:1 ; le même ambre en
 * aplat avec l'encre `#1A1A1A` monte à 7,9:1. C'est l'arbitrage déjà tenu aux
 * versions `0.12.0`, `0.17.0` et `0.19.0`, et il rend du même coup le repère
 * ambre des pastilles « Mes paris bonus » juste au-dessus.
 *
 * > La pastille revient donc, là où la version `0.26.0` l'avait retirée — mais
 * > **sur un seul des deux états**, et dans la cellule de 22px que l'étoile
 * > occupait déjà. L'objection d'alors tenait à un disque présent dans les deux
 * > états, qui mangeait la place du nom : il n'y en a plus qu'un, et il ne
 * > prend pas un pixel de plus.
 *
 * La zone tactile fait 44px (contrainte iOS du CLAUDE.md) pour un signe de
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
      aria-label={
        favori
          ? `Retirer ${nom} de mes paris bonus`
          : `Ajouter ${nom} à mes paris bonus`
      }
      className={`pressable size-tactile flex shrink-0 items-center justify-center ${className}`}
    >
      <span
        aria-hidden="true"
        className="t-icon-swap size-[22px]"
        data-state={favori ? "b" : "a"}
      >
        <IconeEtoileLogo
          className="t-icon text-secondaire/60 size-[22px]"
          data-icon="a"
        />
        <span
          className="t-icon bg-accent flex size-[22px] items-center justify-center rounded-full"
          data-icon="b"
        >
          <IconeCoche className="text-texte size-3 [stroke-width:3]" />
        </span>
      </span>
    </button>
  );
}
