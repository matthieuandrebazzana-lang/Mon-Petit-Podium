import { useEffect, useState } from "react";
import { dureeCss } from "../lib/secousse.js";

/**
 * Attente puis apparition du contenu (transitions-dev 14).
 *
 * Le squelette a la silhouette du contenu à venir : quand les données
 * arrivent, rien ne saute, les deux couches se croisent. C'est ce qui rend le
 * réveil de Railway supportable — l'écran a déjà sa forme avant d'avoir ses
 * données.
 *
 * Le squelette est démonté une fois la révélation terminée : superposé au
 * contenu dans la même cellule de grille, il continuerait sinon d'imposer sa
 * hauteur à un bloc dont la taille dépend du nombre de championnats.
 */
export default function ZoneChargement({ chargement, squelette, children }) {
  // Monté seulement si l'attente est réelle : quand le cache a déjà répondu,
  // il n'y a rien à révéler et le squelette n'apparaît jamais.
  const [squeletteMonte, setSqueletteMonte] = useState(chargement);

  useEffect(() => {
    if (chargement) {
      setSqueletteMonte(true);
      return undefined;
    }
    if (!squeletteMonte) return undefined;

    const minuterie = setTimeout(
      () => setSqueletteMonte(false),
      dureeCss("--reveal-dur", 400),
    );
    return () => clearTimeout(minuterie);
  }, [chargement, squeletteMonte]);

  return (
    <div className={`t-skel t-skel--flux ${chargement ? "" : "is-revealed"}`}>
      {/* `is-pulsing` du snippet n'est volontairement plus posé depuis
          l'étape 9 : les barres portent désormais leur propre balayage
          (`t-skel-bar`), et superposer la pulsation d'ensemble à la bande de
          lumière donnait deux battements de rythmes différents sur le même
          bloc. La règle CSS de la pulsation reste en place — c'est le snippet
          14 tel quel — elle n'est simplement plus appelée. */}
      {squeletteMonte && (
        <div className="t-skel-skeleton" aria-hidden="true">
          {squelette}
        </div>
      )}
      <div className="t-skel-content">{children}</div>
    </div>
  );
}
