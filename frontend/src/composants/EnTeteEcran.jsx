import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { IconeAppareilPhoto, IconeChevronGauche } from "./Icones.jsx";
import PhotoChampionnat from "./PhotoChampionnat.jsx";

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
 * **`photo` n'existe qu'en mode teinté**, et c'est un choix de portée : seul
 * l'écran d'un championnat a une photo à montrer. En mode ordinaire elle serait
 * une image posée à côté d'un grand titre beige, sans rien à quoi se rattacher.
 *
 * **`onPhoto` fait de cette photo un bouton, et c'est le seul écart** — même
 * règle que `HeroProfil` (`ecrans/MonProfil.jsx`), et pour la même raison : sans
 * lui, rien n'y est modifiable, et un bouton qui n'agit pas serait un bouton de
 * trop dans l'ordre de tabulation. Il n'est passé que par le créateur du
 * championnat ; c'est l'écran qui juge, jamais ce composant.
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
  photo = null,
  onPhoto = null,
  envoiPhoto = false,
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
          {/* La photo est en haut à droite, et le titre coule à sa gauche :
              `items-start` les aligne par le haut, ce qui met le carré au niveau
              de la première ligne du nom plutôt qu'au milieu d'un nom qui en
              prend deux. Le `line-clamp-2` du titre gagne ici son utilité — un
              nom de quarante caractères dispose de quatre-vingt-quatre pixels de
              moins, et se coupe au lieu de pousser la photo hors du bloc. */}
          <div className="relative flex items-start gap-3">
            <div className="min-w-0 flex-1">
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

            {/* 72px et `rounded-widget` (16px), la valeur demandée. Le composant
                s'efface tout seul quand il n'y a pas de photo : l'en-tête
                retrouve alors exactement sa composition d'avant, le titre
                occupant toute la largeur. */}
            {onPhoto ? (
              <button
                type="button"
                onClick={onPhoto}
                disabled={envoiPhoto}
                /* Le libellé porte l'action ET son état courant : la photo est
                   `aria-hidden`, c'est donc la seule chose annoncée. « Changer »
                   plutôt que « Ajouter » quand il y en a déjà une — un libellé
                   qui décrit mal ce qui va se passer est pire qu'un libellé
                   générique. */
                aria-label={
                  photo
                    ? "Changer la photo du championnat"
                    : "Ajouter une photo au championnat"
                }
                /* **Le voile est porté par le BOUTON, pas par une doublure
                   conditionnelle**, et ce n'est pas qu'une économie de balise :
                   `PhotoChampionnat` s'efface aussi quand l'objet a disparu du
                   stockage (`cassee`). Posé à côté d'un `photo ? … : …`, le
                   cadre se viderait alors complètement et le bouton perdrait
                   toute silhouette — exactement le cas où le créateur en a le
                   plus besoin, puisque c'est celui où il doit reposer une
                   photo. Le voile est donc toujours là, la photo se pose
                   dessus. Il prend l'encre de l'aplat (`surfaceForte`) et non
                   un gris écrit de mémoire : `bg-black/15` sur l'amber,
                   `bg-white/25` sur le bordeaux, et jamais l'inverse. */
                className={`rounded-widget pressable relative size-[72px] shrink-0 ${teinte.ton.surfaceForte}`}
              >
                <span className={envoiPhoto ? "t-photo-envoi block" : "block"}>
                  <PhotoChampionnat
                    url={photo}
                    nom={titre}
                    taille={72}
                    arrondi="rounded-widget"
                  />
                </span>

                {/* **C'est cette pastille qui porte le sens, pas le cadre.**
                    Blanche à encre bordeaux, elle vaut 10,88:1 sur les six
                    aplats — le voile du cadre vide, lui, ne descend jamais sous
                    3:1 mais n'y arrive qu'à 3,03 sur le vert sauge, trop juste
                    pour un élément qui devrait dire à lui seul ce que fait le
                    bouton. Le cadre est donc une silhouette, la pastille est le
                    message. Même dessin et même taille qu'au profil : le geste
                    « changer ma photo » ne doit pas s'apprendre deux fois. */}
                <span
                  aria-hidden="true"
                  className="bg-surface text-primaire shadow-carte absolute -right-1 -bottom-1 flex size-[22px] items-center justify-center rounded-full"
                >
                  <IconeAppareilPhoto className="size-[13px]" />
                </span>
              </button>
            ) : (
              <PhotoChampionnat
                url={photo}
                nom={titre}
                taille={72}
                arrondi="rounded-widget"
              />
            )}
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
