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
 * Les quatre états d'un Grand Prix, avec le mot et la couleur qui les disent.
 *
 * **Une seule table pour les deux calendriers** — celui d'un championnat
 * (maquette 15) et celui de la saison (onglet Calendrier). Les deux écrans
 * calculent l'état différemment, parce qu'ils ne disposent pas des mêmes
 * données : l'un lit `resultats_disponibles` servi par la fonction SQL, l'autre
 * croise une liste statique avec `GET /scraper/cotes`. Mais ils doivent dire le
 * même mot avec la même couleur, sans quoi un Grand Prix changerait d'état en
 * passant d'un onglet à l'autre. Deux tables écrites séparément auraient divergé
 * au premier libellé retouché.
 *
 * **Les couleurs sont mesurées, pas choisies.** Chaque pastille est un aplat
 * plein portant l'encre qui contraste avec lui : `#1A1A1A` sur l'amber (7,9:1,
 * là où le blanc tomberait à 2,2:1), blanc sur le bordeaux et sur le vert sauge.
 * L'état « à venir » est le seul sans couleur propre — il n'annonce rien — et
 * prend un gris translucide avec le marron du design system pour encre,
 * `#999999` en texte plein ne valant que 2,0:1 sur une carte blanche.
 *
 * ## Deux jeux de classes, parce qu'il y a deux fonds
 *
 * `pastille` est la version posée sur une **carte blanche** — celle du calendrier
 * d'un championnat. `pastilleSurDrapeau` est la version posée sur un **drapeau**,
 * celle de la carte de l'onglet Calendrier, et elle ne pouvait pas être la même :
 *
 * - le gris translucide de l'état « à venir » prendrait la couleur du drapeau
 *   dessous, donc une couleur différente sur chacune des douze cartes ;
 * - les aplats pleins, eux, tiennent leur contraste partout, mais quatre aplats
 *   colorés posés sur douze drapeaux colorés font douze fois deux couleurs qui se
 *   disputent le même coin d'écran.
 *
 * D'où la pastille blanche à encre colorée. **Trois états sur quatre l'adoptent ;
 * « Pronos ouverts » garde son aplat amber, et c'est mesuré :** sur du blanc,
 * l'amber `#E8A020` ne vaut que **2,22:1**, et aucun ton chaud du design system
 * ne tient 4,5:1 en encre (le terracotta `#C4622D` plafonne à 4,09:1). L'amber
 * n'existe que comme aplat. La conséquence tombe juste — c'est le seul état sur
 * lequel il y a quelque chose à faire, et il est le seul à ressortir dans une
 * liste de douze cartes.
 *
 * **La surface blanche est opaque, et c'est également mesuré.** Une pastille
 * franchement translucide poserait le vert sauge `#4A7C59` à **3,45:1** sur le
 * pire substrat (le noir de Las Vegas) : il faut 97 % de blanc pour atteindre
 * 4,5:1, c'est-à-dire du blanc. La translucidité demandée est donc rendue par
 * l'encre colorée, qui laisse le drapeau se lire à travers le sens de la carte,
 * pas par une surface qui rendrait le libellé illisible une carte sur douze.
 */
export const ETATS_GP = {
  termine: {
    cle: "termine",
    libelle: "Terminé",
    pastille: "bg-vert-sauge text-white",
    // 4,86:1 — le plus serré des quatre, et c'est lui qui a fixé l'opacité.
    pastilleSurDrapeau: "bg-white text-vert-sauge",
  },
  ferme: {
    cle: "ferme",
    libelle: "Fermé",
    pastille: "bg-primaire text-white",
    pastilleSurDrapeau: "bg-white text-primaire", // 10,88:1
  },
  ouvert: {
    cle: "ouvert",
    libelle: "Pronos ouverts",
    pastille: "bg-accent text-texte",
    // Seul état à garder son aplat : l'amber ne tient pas en encre sur blanc.
    pastilleSurDrapeau: "bg-accent text-texte", // 7,86:1
  },
  a_venir: {
    cle: "a_venir",
    libelle: "À venir",
    pastille: "bg-texte-doux/25 text-secondaire",
    pastilleSurDrapeau: "bg-white text-secondaire", // 10,56:1
  },
};

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
