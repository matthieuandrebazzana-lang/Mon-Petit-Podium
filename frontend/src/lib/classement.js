import { appelApi } from "./api.js";

/**
 * Classement d'un championnat.
 *
 * Contrairement au détail du championnat et à ses membres, qui se lisent
 * directement dans Supabase sous RLS (`lib/championnats.js`), le classement
 * passe **par l'API**. Ce n'est pas une incohérence :
 *
 * - il agrège les `points_gagnes` de tous les membres, donc des lignes que la
 *   politique RLS de l'étape 5 ne montre qu'entre membres d'un championnat
 *   partagé. Lu depuis le client, un membre qui ne partage rien d'autre avec
 *   les autres verrait un classement silencieusement amputé, ce qui est pire
 *   qu'un refus ;
 * - l'agrégation se fait en base (`classement_du_championnat`), donc en une
 *   requête au lieu d'une centaine de lignes par membre à rapatrier et
 *   additionner dans le navigateur.
 *
 * Le cache *stale-while-revalidate* de `useDonnees` absorbe le réveil de
 * Railway : le classement précédent s'affiche pendant que le nouveau arrive.
 */

export function chargerClassement(championnatId, signal) {
  return appelApi(`/championnats/${championnatId}/classement`, { signal });
}

/**
 * Version de la **forme** des lignes mises en cache.
 *
 * À incrémenter dès qu'un champ nouveau apparaît dans le classement, et c'est
 * ce qui vient de se passer : les lignes écrites avant la version `0.40.0` ne
 * portent ni `livree_mode` ni `livree_ecurie` — le modèle FastAPI les filtrait
 * avant qu'elles n'atteignent le client. Sans ce marqueur, un téléphone qui a
 * déjà ouvert la vue piste continuerait de peindre les voitures en mode
 * `perso` au premier rendu, à partir d'un cache que rien n'invalide, et le skin
 * n'apparaîtrait qu'après le retour du réseau.
 *
 * Le marqueur est placé **après l'identifiant du compte** pour que
 * `oublierCachePrefixe("classement:<profil>:")`, appelé par « Mon profil » à
 * chaque enregistrement de voiture, continue de tout balayer d'un coup.
 */
const SCHEMA_CLASSEMENT = "v2";

/**
 * Clé de cache du classement, fabriquée ici et non écrite en dur à ses points
 * d'usage — la vue liste et la vue piste lisent le même cache, et deux chaînes
 * séparées divergeraient au premier renommage.
 *
 * Elle porte l'identifiant du compte, comme toutes les autres depuis l'étape 3 :
 * deux personnes qui se relaient sur le même téléphone ne doivent jamais voir,
 * fût-ce une fraction de seconde, le championnat de l'autre.
 */
export function cleClassement(profilId, championnatId) {
  return `classement:${profilId}:${SCHEMA_CLASSEMENT}:${championnatId}`;
}

/** Somme des points du championnat : sert à savoir si la saison a commencé. */
export function saisonCommencee(lignes) {
  return (lignes ?? []).some((ligne) => (ligne.total_points ?? 0) > 0);
}
