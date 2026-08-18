import { useEffect, useRef, useState } from "react";

/**
 * Un nombre qui accuse son changement. Deux variantes, deux usages.
 *
 * - **`pop`** (défaut) — le nombre remonte, flouté, avec un léger dépassement
 *   (transitions-dev 02). C'est le compteur de bonus de la maquette 09 : un
 *   chiffre qui passe de 1 à 2 sous le doigt qui touche une *autre* ligne
 *   serait invisible sans mouvement. Le geste vient du joueur, il est rare, et
 *   le rebond y est à sa place.
 *
 * - **`flip`** — le chiffre sortant descend, l'entrant tombe d'au-dessus, la
 *   tuile les rogne : la lecture d'un tableau à palettes. C'est le compte à
 *   rebours de fermeture. Personne ne l'a déclenché et il se répète chaque
 *   minute : il doit dire « ce nombre a changé » puis s'effacer, sans rebond
 *   ni fanfare. Voir `.t-flip` dans `index.css` pour les valeurs et le sens.
 */
export default function Compteur({ valeur, className = "", variante = "pop" }) {
  if (variante === "flip") return <Flip valeur={valeur} className={className} />;
  return <Pop valeur={valeur} className={className} />;
}

/**
 * Le rebond d'origine.
 *
 * Le retrait de la classe, le reflow forcé et sa remise sont les trois temps
 * qui rejouent l'animation. Sans `void offsetHeight` entre les deux, le
 * navigateur regroupe les changements et rien ne bouge.
 */
function Pop({ valeur, className }) {
  const groupe = useRef(null);

  useEffect(() => {
    const element = groupe.current;
    if (!element) return;
    element.classList.remove("is-animating");
    void element.offsetHeight;
    element.classList.add("is-animating");
  }, [valeur]);

  return (
    <span ref={groupe} className={`t-digit-group ${className}`}>
      {/* Un seul caractère : pas de `data-stagger`, il n'a personne derrière
          qui décaler. Le nombre de bonus ne dépasse jamais un chiffre. */}
      <span className="t-digit">{valeur}</span>
    </span>
  );
}

/**
 * La bascule du compte à rebours.
 *
 * **Deux chiffres montés le temps du croisement, jamais plus.** Le sortant est
 * retiré une fois l'animation finie : le laisser en place empilerait une
 * ardoise de chiffres morts au fil des minutes, et chacun garderait son
 * `will-change`. La clé portée par les deux `<span>` change à chaque bascule —
 * c'est elle qui force React à remonter les nœuds, donc à rejouer les
 * animations, sans le retrait de classe et le reflow forcé qu'exige `Pop`.
 *
 * **Le sortant est `aria-hidden`.** Pendant 260ms, deux nombres coexistent
 * dans le DOM ; un lecteur d'écran annoncerait « 05 04 ». Seul l'entrant est
 * lisible, et c'est la valeur courante.
 *
 * Au premier rendu il n'y a rien à remplacer : le chiffre est posé sans
 * animation. Une tuile qui se retournerait à l'arrivée de l'écran annoncerait
 * un changement qui n'a pas eu lieu — et l'écran a déjà son entrée à lui.
 */
function Flip({ valeur, className }) {
  const [etat, setEtat] = useState({ courant: valeur, sortant: null, tour: 0 });
  const precedent = useRef(valeur);

  useEffect(() => {
    if (precedent.current === valeur) return undefined;
    const ancien = precedent.current;
    precedent.current = valeur;
    setEtat((e) => ({ courant: valeur, sortant: ancien, tour: e.tour + 1 }));

    // Le sortant ne vit que la durée de sa sortie. Le minuteur est nettoyé si
    // la valeur rechange entre-temps : la bascule suivante repart alors d'un
    // état propre au lieu de laisser tomber le chiffre du milieu.
    const minuteur = setTimeout(() => {
      setEtat((e) => (e.courant === valeur ? { ...e, sortant: null } : e));
    }, DUREE_SORTIE);
    return () => clearTimeout(minuteur);
  }, [valeur]);

  return (
    <span className={`t-flip ${className}`}>
      {etat.sortant !== null && (
        <span
          key={`s${etat.tour}`}
          aria-hidden="true"
          className="t-flip-chiffre t-flip-sortant"
        >
          {etat.sortant}
        </span>
      )}
      <span
        key={`e${etat.tour}`}
        className={`t-flip-chiffre ${etat.tour > 0 ? "t-flip-entrant" : ""}`}
      >
        {etat.courant}
      </span>
    </span>
  );
}

/**
 * Doit valoir `--flip-dur` (`index.css`). Les deux se lisent ensemble : une
 * valeur plus courte ici couperait la sortie en plein vol, une plus longue
 * laisserait le chiffre mort occuper la tuile après son animation.
 */
const DUREE_SORTIE = 260;
