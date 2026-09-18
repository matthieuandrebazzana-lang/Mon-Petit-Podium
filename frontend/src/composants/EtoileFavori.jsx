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
 * > **Les quatre références au `+` ont suivi en `0.68.0`** : le mode d'emploi
 * > et la zone vide du tableau des cotes (`Cotes.jsx`), la zone vide de
 * > l'écran de saisie (`Pronostics.jsx`) disent maintenant « l'étoile » devant
 * > une étoile. La rangée de `Pronostics.jsx`, qui refaisait le même échange
 * > d'icônes en ligne, passe par ce composant — d'où `sansBouton`.
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
 *
 * ### `sansBouton` — le signe seul, sans son bouton
 *
 * La rangée « Mes paris bonus » de `Pronostics.jsx` **est déjà un bouton** : la
 * ligne entière bascule le pari au doigt. Y monter ce composant tel quel
 * imbriquerait un `<button>` dans un `<button>` — HTML invalide, et Safari iOS
 * n'en tire rien de bon. `sansBouton` rend donc le signe nu : le parent garde
 * son `onClick`, son `aria-pressed` et son nom accessible, et c'est la même
 * cellule d'échange qui sert aux deux appelants. L'alternative — recopier les
 * 18 lignes du `t-icon-swap` en ligne — est exactement ce que la section 6 du
 * CLAUDE.md proscrit : une question, un propriétaire.
 *
 * ### `inverse` — la coche sur une rangée déjà ambre
 *
 * Le couple par défaut est une coche `texte` sur aplat `accent` (7,9:1), posé
 * sur du blanc. Mais la rangée de `Pronostics.jsx` **devient ambre** quand le
 * pari est retenu : l'aplat ambre y disparaîtrait dans le fond. `inverse`
 * échange les deux encres — aplat `texte`, coche `accent` — ce qui tient le
 * même 7,9:1 mesuré, l'ambre et l'encre foncée n'ayant pas d'ordre. L'étoile,
 * elle, ne paraît **que** sur l'état non retenu, donc toujours sur du blanc :
 * son `text-secondaire/60` à 3,4:1 vaut dans les deux modes.
 */
export default function EtoileFavori({
  favori,
  onClick,
  disabled,
  nom,
  className = "",
  sansBouton = false,
  inverse = false,
}) {
  const signe = (
    <span
      aria-hidden="true"
      className={`t-icon-swap size-[22px] ${sansBouton ? className : ""}`}
      data-state={favori ? "b" : "a"}
    >
      <IconeEtoileLogo
        className="t-icon text-secondaire/60 size-[22px]"
        data-icon="a"
      />
      <span
        className={`t-icon flex size-[22px] items-center justify-center rounded-full ${
          inverse ? "bg-texte" : "bg-accent"
        }`}
        data-icon="b"
      >
        <IconeCoche
          className={`size-3 [stroke-width:3] ${
            inverse ? "text-accent" : "text-texte"
          }`}
        />
      </span>
    </span>
  );

  /* Le parent porte déjà le bouton : pas de second `<button>`, et pas de zone
     tactile de 44px non plus — c'est la rangée entière qui la donne. */
  if (sansBouton) return signe;

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
      {signe}
    </button>
  );
}
