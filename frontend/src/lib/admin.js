import { ADMIN_SECRET } from "../config.js";
import { appelApi } from "./api.js";
import { GENRE_DONNEES } from "./erreurs.js";

/**
 * Routes d'administration — pour l'instant le seul déclenchement du scraper.
 *
 * **Ce module ne garde rien.** `is_admin` décide de l'affichage de la section,
 * le backend ne le connaît même pas : `POST /scraper/declencher` est gardée par
 * `exiger_secret`, qui compare `X-Admin-Secret` à `ADMIN_SECRET` **à temps
 * constant** (`secrets.compare_digest`, étape 4) et refuse tout le monde quand
 * la variable n'est pas définie côté Railway. Un membre qui se promeut
 * lui-même en base voit deux boutons et rien de plus.
 *
 * Le secret voyage en clair dans le bundle : voir `config.js`, qui documente ce
 * que cela protège encore et ce que cela ne protège plus.
 */

const SECRET_ABSENT =
  "Le secret d'administration n'est pas configuré pour cette version de l'app.";

/**
 * Lance un scraping Unibet.
 *
 * `figer` gouverne ce que le backend fait des cotes après un scraping réussi :
 *
 * - **`true` (le défaut du backend)** — les Grands Prix effectivement scrapés
 *   passent en `cotes_figees`. C'est le comportement du job automatique du
 *   samedi, et le bon **après** les qualifications : tout le monde pronostique
 *   alors sur les mêmes cotes, sur une grille définitive (règle 4.3).
 * - **`false`** — scraping sans figeage. C'est le mode d'essai, et il existe
 *   pour un cas précis : un déclenchement passé **avant** les qualifications
 *   arrêterait sinon les cotes sur une grille qui n'existe pas encore, et il
 *   faudrait un `update` à la main dans le SQL Editor pour les débloquer.
 *   C'est exactement le piège dans lequel le GP des Pays-Bas est tombé
 *   (version `0.38.0`).
 *
 * La route rend `202` sans attendre : le compte rendu du scraping part dans les
 * logs Railway. Un succès ici dit que le travail est **accepté**, jamais qu'il
 * est fait — et le libellé affiché à l'écran doit le dire aussi.
 */
export function declencherScraper({ figer = true } = {}) {
  // Le secret absent est traité ici et non par un aller-retour : la route
  // répondrait `401`, que `lib/api.js` traduit en « Session expirée,
  // reconnecte-toi » — un message faux, qui enverrait l'administrateur se
  // reconnecter pour rien.
  if (!ADMIN_SECRET) {
    return Promise.resolve({
      ok: false,
      message: SECRET_ABSENT,
      statut: 0,
      genre: GENRE_DONNEES,
    });
  }

  return appelApi(`/scraper/declencher${figer ? "" : "?figer=false"}`, {
    methode: "POST",
    entetes: { "X-Admin-Secret": ADMIN_SECRET },
  });
}
