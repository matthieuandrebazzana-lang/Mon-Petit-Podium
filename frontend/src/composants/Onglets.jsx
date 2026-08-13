import { useCallback, useEffect, useRef } from "react";

/**
 * Onglets de marchés de la maquette 08, avec la pastille glissante de
 * transitions-dev 16.
 *
 * *Écart assumé par rapport à la maquette 08* : elle dessine des pastilles
 * blanches séparées, dont l'active devient rouge d'un coup. Ici les onglets
 * partagent une piste blanche continue et c'est la pastille rouge qui se
 * déplace de l'une à l'autre. C'est ce que le mouvement demandé exige — une
 * pastille ne peut pas glisser derrière des fonds opaques — et c'est aussi le
 * contrôle segmenté que reconnaît immédiatement quelqu'un qui vient d'iOS.
 * Aucune couleur, aucun rayon, aucune graisse ne change.
 *
 * La position et la largeur de la pastille sont écrites en ligne : le CSS ne
 * peut pas mesurer un libellé, et coder les largeurs en dur casserait dès
 * qu'Unibet expose un marché au nom plus long.
 */
export default function Onglets({ options, valeur, onChange, etiquette }) {
  const piste = useRef(null);
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

      // Premier rendu et redimensionnement : la pastille doit se poser sans
      // transition, sinon elle traverse l'écran depuis translateX(0) et une
      // largeur nulle à chaque arrivée sur la page.
      const precedente = pilule.style.transition;
      pilule.style.transition = "none";
      pilule.style.transform = `translateX(${cible.offsetLeft}px)`;
      pilule.style.width = `${cible.offsetWidth}px`;
      void pilule.offsetWidth;
      pilule.style.transition = precedente;
    },
    [valeur],
  );

  // Pose initiale après la première peinture : avant, les libellés ne sont pas
  // encore mesurés et `offsetWidth` vaut zéro.
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

  function choisir(cle) {
    onChange(cle);
    // Un marché choisi au bord de l'écran doit revenir sous les yeux : la
    // liste des marchés déborde largement la largeur d'un iPhone.
    boutons.current
      .get(cle)
      ?.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
  }

  return (
    <div className="-mx-1 overflow-x-auto px-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      <div
        ref={piste}
        role="tablist"
        aria-label={etiquette}
        className="t-tabs rounded-full bg-surface"
      >
        <span
          ref={pastille}
          aria-hidden="true"
          className="t-tabs-pill rounded-full bg-primaire"
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
              onClick={() => choisir(option.cle)}
              className={`t-tab pressable min-h-tactile shrink-0 rounded-full px-4 text-[13px] font-medium whitespace-nowrap ${
                actif ? "text-white" : "text-texte-doux"
              }`}
            >
              {option.libelle}
            </button>
          );
        })}
      </div>
    </div>
  );
}
