import { appelApi } from "./api.js";

/**
 * Routes d'administration — pour l'instant le seul déclenchement du scraper.
 *
 * **Ce module ne garde rien, et cette fois le backend garde vraiment.** Depuis
 * la version `0.64.0`, l'action part sur `POST /admin/action` avec le seul
 * jeton Supabase que `lib/api.js` joint déjà à tous les appels. Le backend
 * relit `profils.is_admin` **en base**, avec la clé de service, et refuse en
 * `403` tout appelant qui n'y est pas administrateur.
 *
 * Ce qui a changé, et pourquoi c'est le fond du sujet : il n'y a plus rien à
 * cacher dans le bundle. `VITE_ADMIN_SECRET` y voyageait en clair — Vite inline
 * les `VITE_*` à la construction — si bien que le garde des routes
 * d'administration était lisible par n'importe qui. `ADMIN_SECRET` reste défini
 * sur Railway et garde toujours `POST /scraper/declencher` et
 * `POST /jobs/resultats/{id}`, mais **ces routes-là ne sont plus appelées depuis
 * l'application** : elles servent le `curl`, qui n'a pas de session.
 *
 * `is_admin` continue de décider de l'affichage de la section côté frontend
 * (`chargerEstAdmin`), et c'est désormais un doublon volontaire du garde
 * serveur : l'un choisit ce qu'on montre, l'autre ce qu'on autorise. Un membre
 * qui force l'affichage voit deux boutons et reçoit un `403`.
 */

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
 * La route rend `statut: "lance"` sans attendre : le compte rendu du scraping
 * part dans les logs Railway. Un succès ici dit que le travail est **accepté**,
 * jamais qu'il est fait — et le libellé affiché à l'écran doit le dire aussi.
 *
 * **Plus aucun cas « secret absent » à traiter avant l'envoi.** L'ancienne
 * version court-circuitait l'appel quand `VITE_ADMIN_SECRET` était vide, pour
 * éviter un `401` que `lib/api.js` aurait traduit en « Session expirée,
 * reconnecte-toi » — un message faux, qui envoyait l'administrateur se
 * reconnecter pour rien. Le garde vivant côté serveur, l'échec qui remonte
 * maintenant est un `403` portant son propre message en français.
 */
export function declencherScraper({ figer = true } = {}) {
  return appelApi("/admin/action", {
    methode: "POST",
    corps: { action: "scraper", figer },
  });
}

/**
 * Les alertes que l'administrateur doit voir sans lire les logs Railway
 * (`GET /admin/alertes`, backend `0.79.0`) : libellé Unibet non reconnu au
 * figeage, rattachement impossible, calcul définitif en échec répété.
 *
 * `donnees.disponible` vaut `false` tant que la migration 26 n'est pas jouée :
 * l'écran le dit, plutôt que d'afficher « aucune alerte ».
 */
export function chargerAlertes({ signal } = {}) {
  return appelApi("/admin/alertes", { signal });
}
