import { appelApi } from "./api.js";

/**
 * Calendrier d'un championnat et résultats d'un Grand Prix — étape 9.
 *
 * Les **deux chemins de données** des étapes 3, 5 et 8 restent en vigueur, et le
 * partage se fait ici encore selon la politique RLS de la donnée servie. Les
 * deux lectures de ce module passent **par l'API**, et pour la même raison
 * qu'au classement de l'étape 7 :
 *
 * - le calendrier agrège les `points_gagnes` de tous les membres, Grand Prix par
 *   Grand Prix. Lu depuis le client, la politique de l'étape 5 filtrerait les
 *   membres avec qui l'appelant ne partage rien d'autre : le calendrier serait
 *   **silencieusement faux** au lieu d'être refusé ;
 * - les résultats d'un Grand Prix mélangent du public (le classement de la
 *   course) et du protégé (les pronostics des membres). La route sait faire les
 *   deux ; la RLS seule ne saurait pas servir le premier sans session.
 *
 * Le cache *stale-while-revalidate* de `useDonnees` absorbe le réveil de
 * Railway : le calendrier précédent s'affiche pendant que le nouveau arrive.
 */

export function chargerCalendrier(championnatId, signal) {
  return appelApi(`/championnats/${championnatId}/calendrier`, { signal });
}

/**
 * Résultats d'un Grand Prix.
 *
 * `championnatId` est facultatif, et c'est la route qui porte la distinction
 * (étape 6) : sans lui, le classement de la course seul, publiquement ; avec
 * lui, les pronostics de tous les membres, jeton exigé et appartenance
 * vérifiée. L'écran appelle toujours avec, puisqu'on y arrive depuis un
 * championnat — mais la forme sans reste possible sans changer une ligne.
 */
export function chargerResultatsGp(gpId, championnatId, signal) {
  const requete = championnatId
    ? `/grands-prix/${gpId}/resultats?championnat_id=${championnatId}`
    : `/grands-prix/${gpId}/resultats`;
  return appelApi(requete, { signal });
}

/** Clés de cache — elles portent toujours l'identifiant du compte connecté. */
export const cleCalendrier = (profilId, championnatId) =>
  `calendrier:${profilId}:${championnatId}`;
export const cleResultats = (profilId, gpId, championnatId) =>
  `resultats:${profilId}:${gpId}:${championnatId ?? "public"}`;

/**
 * Le classement des membres sur ce Grand Prix, tiré de leurs pronostics.
 *
 * Exportée pour être vérifiable seule : c'est la seule vraie logique de l'écran
 * de résultats, et elle porte les deux règles qui comptent.
 *
 * 1. **Le total d'un membre ignore les pronostics non jugés, sans les compter
 *    zéro.** `points_gagnes` nul veut dire « le calcul n'a pas su valider ce
 *    marché » (convention de l'étape 6), jamais « raté ». Le backend calcule
 *    déjà ce total ; il est recalculé ici en repli pour les réponses qui ne le
 *    portent pas encore — un backend déployé avant la migration de l'étape 9.
 * 2. **Le rang est un `rank`, pas un `row_number` :** deux membres à égalité sur
 *    un Grand Prix le sont vraiment. La règle 4.6 départage le classement de la
 *    saison, pas une course isolée, et inventer ici un ordre entre deux joueurs
 *    à 280 points serait une information fausse. C'est la même décision que dans
 *    `calendrier_du_championnat`.
 */
export function classerLesMembres(membres) {
  const lignes = (membres ?? []).map((membre) => {
    const juges = (membre.pronostics ?? []).filter(
      (pronostic) => pronostic.points_gagnes !== null &&
        pronostic.points_gagnes !== undefined,
    );

    return {
      ...membre,
      // Le total du backend fait foi dès qu'il est là ; le repli n'existe que
      // pour la compatibilité décrite ci-dessus.
      total:
        membre.total_points ??
        (juges.length > 0
          ? juges.reduce((somme, p) => somme + p.points_gagnes, 0)
          : null),
      juges: juges.length,
      reussis: juges.filter((pronostic) => pronostic.points_gagnes > 0).length,
      // Un membre qui n'a rien saisi n'est pas « à zéro », il n'a pas joué.
      aJoue: (membre.pronostics ?? []).length > 0,
    };
  });

  lignes.sort((a, b) => (b.total ?? 0) - (a.total ?? 0));

  let rangPrecedent = 0;
  let valeurPrecedente = null;
  lignes.forEach((ligne, index) => {
    const valeur = ligne.total ?? 0;
    if (valeur !== valeurPrecedente) {
      rangPrecedent = index + 1;
      valeurPrecedente = valeur;
    }
    ligne.rang = rangPrecedent;
  });

  return lignes;
}

/**
 * Le podium de la course, dans l'ordre d'affichage de la maquette 11 :
 * deuxième, **premier au centre**, troisième. C'est la marche d'un vrai podium,
 * pas un tri décroissant.
 *
 * Une course sans première place — classement publié mais pas encore rempli,
 * cas que le job traite comme « indisponible » (étape 6) — rend une liste vide
 * plutôt qu'un podium bancal.
 */
export function podiumDeLaCourse(classement) {
  const parPosition = (rang) =>
    (classement ?? []).find((ligne) => ligne.position === rang) ?? null;

  const premier = parPosition(1);
  if (!premier) return [];

  return [parPosition(2), premier, parPosition(3)].filter(Boolean);
}
