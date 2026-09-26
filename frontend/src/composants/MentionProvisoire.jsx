import { DETAIL_PROVISOIRE, MENTION_PROVISOIRE } from "../lib/resultats.js";

/**
 * La mention « Provisoire » posée sur des résultats pas encore définitifs.
 *
 * **Discrète par construction** : même encre et même corps que le label de la
 * surface qui la porte (`text-label-sm`, `text-texte-doux` par défaut). Elle ne
 * choisit donc aucune encre — celles des labels sont déjà mesurées — et ne
 * s'anime pas : c'est un statut, pas un évènement.
 *
 * Le détail (« définitifs 24 heures après la course ») passe par `title` et par
 * le lecteur d'écran : le mot seul suffit à l'œil, la phrase ne tiendrait sur
 * aucune des lignes où la mention se glisse.
 *
 * `className` remplace l'encre quand la surface n'est pas claire.
 */
export default function MentionProvisoire({ className = "text-texte-doux" }) {
  return (
    <span
      title={DETAIL_PROVISOIRE}
      className={`text-label-sm shrink-0 uppercase select-none ${className}`}
    >
      <span aria-hidden="true">{MENTION_PROVISOIRE}</span>
      <span className="sr-only">{DETAIL_PROVISOIRE}</span>
    </span>
  );
}
