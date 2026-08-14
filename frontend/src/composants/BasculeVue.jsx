import { useCallback, useEffect, useRef } from "react";

/**
 * Bascule Classement / Piste des maquettes 07 et 07b.
 *
 * Deux options de largeur égale, avec la pastille glissante de
 * transitions-dev 16 — la même que les onglets de marchés de la maquette 08,
 * dont elle reprend les jetons. La différence tient au dimensionnement : les
 * onglets de marchés se mesurent à leurs libellés et débordent en défilement,
 * cette bascule occupe toute la largeur en deux moitiés fixes.
 *
 * L'option « Piste » ne change pas un état local : elle **mène à un autre
 * écran**. Le contrôle segmenté reste malgré tout la bonne affordance —
 * c'est ce que dessine la maquette, et c'est le geste que reconnaît
 * immédiatement quelqu'un qui vient d'iOS. La pastille glisse, puis l'écran
 * change : le mouvement annonce la destination au lieu de la remplacer.
 */
export default function BasculeVue({ options, valeur, onChange, etiquette }) {
  const pastille = useRef(null);
  const boutons = useRef(new Map());

  const deplacer = useCallback(
    (anime) => {
      const cible = boutons.current.get(valeur);
      const pilule = pastille.current;
      if (!cible || !pilule) return;

      if (anime) {
        pilule.style.transform = `translateX(${cible.offsetLeft}px)`;
        pilule.style.width = `${cible.offsetWidth}px`;
        return;
      }

      // Premier rendu et redimensionnement : la pastille se pose sans
      // transition, sinon elle traverse la bascule depuis translateX(0) et une
      // largeur nulle à chaque arrivée sur l'écran.
      const precedente = pilule.style.transition;
      pilule.style.transition = "none";
      pilule.style.transform = `translateX(${cible.offsetLeft}px)`;
      pilule.style.width = `${cible.offsetWidth}px`;
      void pilule.offsetWidth;
      pilule.style.transition = precedente;
    },
    [valeur],
  );

  const posee = useRef(false);
  useEffect(() => {
    const image = requestAnimationFrame(() => {
      deplacer(posee.current);
      posee.current = true;
    });
    return () => cancelAnimationFrame(image);
  }, [deplacer]);

  useEffect(() => {
    const surRedimensionnement = () => deplacer(false);
    window.addEventListener("resize", surRedimensionnement);
    return () => window.removeEventListener("resize", surRedimensionnement);
  }, [deplacer]);

  return (
    <div
      role="tablist"
      aria-label={etiquette}
      className="t-tabs rounded-carte bg-surface flex w-full"
    >
      <span
        ref={pastille}
        aria-hidden="true"
        className="t-tabs-pill rounded-champ bg-primaire"
      />
      {options.map((option) => {
        const actif = option.cle === valeur;
        return (
          <button
            key={option.cle}
            ref={(element) => {
              if (element) boutons.current.set(option.cle, element);
              else boutons.current.delete(option.cle);
            }}
            type="button"
            role="tab"
            aria-selected={actif}
            onClick={() => onChange(option.cle)}
            className={`t-tab pressable min-h-tactile rounded-champ flex-1 text-[13px] font-medium ${
              actif ? "text-white" : "text-texte-doux"
            }`}
          >
            {option.libelle}
          </button>
        );
      })}
    </div>
  );
}
