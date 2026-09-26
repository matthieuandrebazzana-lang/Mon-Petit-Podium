/**
 * Le statut des résultats d'un Grand Prix, et celui d'un pronostic.
 *
 * **Un seul propriétaire pour les deux questions** que plusieurs écrans posent
 * de la même façon : « ces résultats sont-ils encore provisoires ? » et « ce
 * pronostic sans points est-il en attente, ou non évaluable ? ».
 *
 * - `grands_prix.statut_resultats` (migration 25) : `provisoire` dès la
 *   publication du classement, `definitif` après la relecture d'OpenF1 24 h
 *   après la course. Les points d'un GP provisoire comptent déjà partout ; ils
 *   peuvent encore bouger une fois.
 * - `pronostics.statut_evaluation` (migration 24) : `non_evaluable` quand aucun
 *   évaluateur ne porte le marché. `points_gagnes` est nul dans les deux cas,
 *   il ne suffit donc pas à les distinguer.
 */

export const PROVISOIRE = "provisoire";
export const NON_EVALUABLE = "non_evaluable";

/** Le mot affiché, partout le même. */
export const MENTION_PROVISOIRE = "Provisoire";

/** Ce que la mention veut dire, pour les lecteurs d'écran et l'infobulle. */
export const DETAIL_PROVISOIRE =
  "Résultats provisoires : ils deviennent définitifs 24 heures après la course.";

export function estProvisoire(statutResultats) {
  return statutResultats === PROVISOIRE;
}

export function estNonEvaluable(statutEvaluation) {
  return statutEvaluation === NON_EVALUABLE;
}
