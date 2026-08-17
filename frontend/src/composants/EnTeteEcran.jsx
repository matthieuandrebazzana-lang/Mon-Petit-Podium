import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { IconeChevronGauche } from "./Icones.jsx";

/**
 * En-tête à grand titre rétractable — le geste de navigation d'iOS.
 *
 * Le grand titre vit dans le flux et défile normalement ; la rangée de retour,
 * elle, est collée en haut de la fenêtre. Quand le grand titre passe dessous,
 * la barre se matérialise et reprend le titre en petit. On sait donc en
 * permanence où l'on est et comment sortir — le « wayfinding » d'/apple-design
 * §16, et sa règle §12 sur le chrome qui ne se matérialise que là où il
 * recouvre vraiment du contenu.
 *
 * **La bascule est détectée par un `IntersectionObserver` sur une sentinelle**,
 * jamais par un écouteur de défilement. Un `scroll` se déclenche à chaque image
 * et repasserait par l'état React à chaque fois ; l'observateur, lui, ne rend
 * que deux fois par écran, aux deux franchissements.
 *
 * **Ce composant doit être monté en enfant direct d'`Ecran`.** Les blocs
 * `t-stagger-line` portent un `transform` et un `filter` pendant leur entrée :
 * un `position: sticky` posé à l'intérieur se collerait à leur boîte plutôt
 * qu'à la fenêtre, et l'en-tête défilerait avec la page.
 *
 * **`teinte` bascule l'en-tête en mode coloré** (l'écran d'un championnat).
 * La barre porte alors sa couleur en permanence et le grand titre devient un
 * aplat pleine largeur qui la prolonge : les deux se lisent comme un seul bloc,
 * et le titre glisse dessous au défilement. C'est la barre de navigation teintée
 * d'iOS. Attendre le défilement pour colorer la barre laisserait une bande
 * beige au-dessus d'un aplat de couleur, ce qui se lit comme un défaut de
 * calage.
 */
export default function EnTeteEcran({
  titre,
  sousTitre,
  retourVers,
  libelleRetour = "Retour",
  /* État de navigation rendu à l'écran de retour. Il sert à lui restituer sa
     propre origine : sans lui, un écran atteint depuis le calendrier puis
     revisité par un rebond retomberait sur sa destination par défaut. */
  retourEtat = null,
  action = null,
  teinte = null,
  children,
}) {
  const naviguer = useNavigate();
  const sentinelle = useRef(null);
  const [condense, setCondense] = useState(false);

  useEffect(() => {
    const cible = sentinelle.current;
    // `IntersectionObserver` n'existe pas en rendu hors navigateur : le
    // composant doit s'y rendre quand même, à l'état déplié.
    if (!cible || typeof IntersectionObserver === "undefined") return undefined;

    const observateur = new IntersectionObserver(
      ([entree]) => setCondense(!entree.isIntersecting),
      // La sentinelle est jugée sortie dès qu'elle passe sous la hauteur de la
      // barre elle-même, pas sous le haut de la fenêtre : sans cette marge, le
      // matériau n'apparaîtrait qu'une fois le titre déjà caché.
      { threshold: 0, rootMargin: "-64px 0px 0px 0px" },
    );
    observateur.observe(cible);
    return () => observateur.disconnect();
  }, []);

  const encre = teinte ? teinte.ton.texte : "text-primaire";
  const variables = teinte
    ? { "--entete-materiau": teinte.hex, "--entete-opaque": teinte.hex }
    : undefined;

  return (
    <>
      <div
        className="entete-collante"
        data-condense={condense ? "true" : "false"}
        data-materiau={teinte ? "fixe" : "au-defilement"}
        style={variables}
      >
        <div className="min-h-tactile flex items-center gap-3">
          {retourVers ? (
            <button
              type="button"
              onClick={() =>
                naviguer(retourVers, retourEtat ? { state: retourEtat } : undefined)
              }
              className={`pressable min-h-tactile -my-3 -ml-2 flex min-w-0 shrink items-center gap-1.5 py-3 pl-2 text-[13px] font-medium ${encre}`}
            >
              <IconeChevronGauche className="size-[15px] shrink-0" />
              <span className="truncate">{libelleRetour}</span>
            </button>
          ) : (
            <span aria-hidden="true" className="min-w-0 shrink" />
          )}

          {/* Le titre compact ne prend la vedette qu'une fois le grand titre
              parti. Il est placé après le retour et avant l'action : c'est
              l'ordre de lecture d'une barre de navigation iOS. */}
          <span
            className={`entete-titre-compact text-corps-sm min-w-0 flex-1 truncate font-medium ${encre} ${
              retourVers ? "text-center" : "text-left"
            }`}
          >
            {titre}
          </span>

          {action ? (
            <span className="shrink-0">{action}</span>
          ) : (
            <span aria-hidden="true" className="w-8 shrink-0" />
          )}
        </div>
      </div>

      {teinte ? (
        // Le `-mt-2` referme exactement le rembourrage bas de la barre : les
        // deux surfaces sont de la même couleur et doivent se toucher, sinon
        // une ligne de fond apparaît entre elles au premier pixel de défilement.
        <div
          className={`pleine-largeur rounded-b-bloc shadow-aplat relative -mt-2 overflow-hidden px-4 pt-1 pb-5 ${teinte.fond}`}
        >
          <span
            aria-hidden="true"
            className="lueur-haute pointer-events-none absolute inset-0"
          />
          <div className="relative">
            <h1 className={`text-titre-lg line-clamp-2 ${teinte.ton.texte}`}>
              {titre}
            </h1>
            {sousTitre && (
              <p className={`mt-1 text-[13px] ${teinte.ton.texteDoux}`}>
                {sousTitre}
              </p>
            )}
            {children}
          </div>
        </div>
      ) : (
        <div className="pt-1">
          <h1 className="text-titre-lg text-texte">{titre}</h1>
          {sousTitre && (
            <p className="text-texte-doux mt-1 text-[13px]">{sousTitre}</p>
          )}
          {children}
        </div>
      )}

      {/* La sentinelle marque le bas du grand titre. Elle ne mesure rien
          elle-même : c'est sa sortie de l'écran qui déclenche la bascule. */}
      <div ref={sentinelle} aria-hidden="true" className="h-px shrink-0" />
    </>
  );
}
