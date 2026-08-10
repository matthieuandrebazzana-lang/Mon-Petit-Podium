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
      {squeletteMonte && (
        <div className="t-skel-skeleton is-pulsing" aria-hidden="true">
          {squelette}
        </div>
      )}
      <div className="t-skel-content">{children}</div>
    </div>
  );
}
