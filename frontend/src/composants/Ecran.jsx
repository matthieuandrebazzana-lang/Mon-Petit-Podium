import { useEffect, useRef } from "react";
import { useLocation } from "react-router-dom";
import { barreVisible } from "../lib/navigation.js";

/**
 * Enveloppe commune à tous les écrans.
 *
 * - `ecran` applique les zones sûres iOS sur les quatre côtés : le titre ne
 *   passe jamais sous la Dynamic Island, les boutons du bas jamais sous le
 *   home indicator.
 * - `t-ecran` joue l'entrée directionnelle. `direction` doit décrire le sens
 *   du déplacement dans la hiérarchie, pas le bouton qui a été touché :
 *   « avant » pour un écran qui s'enfonce, « arrière » pour un retour. Une
 *   chose qui disparaît d'un côté doit revenir du même côté.
 * - `t-stagger` orchestre l'apparition échelonnée des blocs enfants, qui
 *   portent `t-stagger-line t-stagger-line--N`.
 */
export default function Ecran({
  direction = "avant",
  className = "",
  children,
}) {
  const racine = useRef(null);
  const { pathname } = useLocation();
  // La barre de navigation basse est `position: fixed` : elle ne pousse rien.
  // C'est donc à l'écran de réserver sa hauteur, sans quoi elle recouvrirait le
  // dernier bloc — souvent un bouton. La réponse vient de `lib/navigation.js`,
  // le même module que celui qui décide de l'afficher.
  const reserverBarre = barreVisible(pathname);

  useEffect(() => {
    const element = racine.current;
    if (!element) return undefined;
    // Une image doit être peinte à l'état de départ avant de basculer vers
    // l'état de repos, sinon le navigateur regroupe les deux et rien ne bouge.
    const image = requestAnimationFrame(() => element.classList.add("is-shown"));
    return () => cancelAnimationFrame(image);
  }, []);

  return (
    <main
      ref={racine}
      data-direction={direction}
      className={`t-ecran t-stagger ecran flex min-h-dvh flex-col ${className}`}
    >
      {children}

      {/* Un bloc en fin de flux plutôt qu'un rembourrage qui viendrait écraser
          celui d'`ecran` : deux utilitaires écrivant la même propriété se
          départagent par leur ordre dans la feuille compilée, ce qui n'est pas
          une garantie sur laquelle poser la zone sûre du home indicator. */}
      {reserverBarre && <div className="h-nav shrink-0" aria-hidden="true" />}
    </main>
  );
}

/** Bloc d'un écran : porte le décalage d'apparition. `rang` commence à 1. */
export function Bloc({ rang = 1, className = "", children, ...reste }) {
  return (
    <div
      className={`t-stagger-line t-stagger-line--${rang} ${className}`}
      {...reste}
    >
      {children}
    </div>
  );
}
