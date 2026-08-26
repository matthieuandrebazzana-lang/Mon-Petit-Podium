import { appelApi } from "./api.js";
import { etatFermeture, etatOuverture } from "./format.js";
import { chargerMesPronosticsDuGp } from "./pronostics.js";

/**
 * Calendrier d'un championnat et résultats d'un Grand Prix — étape 9.
 *
 * Les **deux chemins de données** des étapes 3, 5 et 8 restent en vigueur, et le
 * partage se fait ici encore selon la politique RLS de la donnée servie. Les
 * deux lectures principales de ce module passent **par l'API**, et pour la même
 * raison qu'au classement de l'étape 7 :
 *
 * - le calendrier agrège les `points_gagnes` de tous les membres, Grand Prix par
 *   Grand Prix. Lu depuis le client, la politique de l'étape 5 filtrerait les
 *   membres avec qui l'appelant ne partage rien d'autre : le calendrier serait
 *   **silencieusement faux** au lieu d'être refusé ;
 * - les résultats d'un Grand Prix mélangent du public (le classement de la
 *   course) et du protégé (les pronostics des membres). La route sait faire les
 *   deux ; la RLS seule ne saurait pas servir le premier sans session.
 *
 * **Une troisième lecture s'y ajoute, et elle prend l'autre chemin** : les
 * pronostics du joueur lui-même, quand l'écran de résultats est ouvert hors
 * championnat. Elle va directement à Supabase parce que la politique de
 * l'étape 5 décrit exactement ce cas — un joueur relit toujours ses propres
 * pronostics, championnat ou pas — et parce que la route, elle, ne les sert
 * qu'avec un championnat. Voir `chargerResultatsGp`.
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
 * Les cotes de ce Grand Prix sont-elles arrêtées, c'est-à-dire peut-on
 * pronostiquer dessus ?
 *
 * **Deux conditions, et les deux doivent tenir** : le statut vaut
 * `cotes_figees`, ET l'heure des qualifications est passée. C'est la règle 4.3
 * lue jusqu'au bout — les cotes ne valent quelque chose que sur une grille de
 * départ définitive, donc après les qualifications.
 *
 * **Le statut seul ne suffit pas, et ce n'est pas une précaution en l'air.**
 * `POST /scraper/declencher` fige les cotes des Grands Prix qu'il a scrapés
 * avec succès (étape 11), et il peut être appelé n'importe quand : un essai
 * passé un mardi, sans `?figer=false`, arrête les cotes sur une grille qui
 * n'existe pas encore. C'est exactement ce qui s'est produit sur le GP des
 * Pays-Bas, constaté en base à la version `0.38.0` — statut `cotes_figees`
 * deux jours avant des qualifications annoncées au 22 août. La date des
 * qualifications, elle, ne peut pas être avancée par un `curl` : elle vient du
 * programme d'Unibet, ou de l'heure écrite explicitement en base (migrations 19
 * et 20). **Elle n'est jamais dérivée de `date_course`** — le repli
 * `date_course - 22h` a été retiré du scraper en `0.57.0`, parce qu'il écrasait
 * l'heure relevée sur le calendrier officiel par une constante fausse sur neuf
 * Grands Prix de douze.
 *
 * **On se ferme sur une donnée qu'on n'a pas, jamais l'inverse.** Un
 * `date_qualifications` absent — colonne nulle, cache écrit par une version
 * antérieure, backend déployé avant la migration — rend `false`. C'est la règle
 * tenue depuis la version `0.38.0`, et le *stale-while-revalidate* corrige à la
 * première réponse fraîche.
 *
 * Elle sert les **trois** surfaces qui portent un bouton de pronostics : le
 * bloc de l'accueil et les deux calendriers. Écrite trois fois, elle aurait
 * divergé au premier ajustement, et le symptôme aurait été discret — un Grand
 * Prix pronostiquable d'un onglet et pas de l'autre.
 */
export function cotesArretees(gp, maintenant = Date.now()) {
  if (!gp || gp.statut !== "cotes_figees") return false;

  const qualifications = Date.parse(gp.date_qualifications ?? "");
  return Number.isFinite(qualifications) && qualifications <= maintenant;
}

/**
 * Ce que le compte à rebours doit dire de ce Grand Prix — **la seule source**
 * pour les trois surfaces qui en portent un : le bloc de l'accueil, l'écran de
 * saisie et le récapitulatif.
 *
 * ## Deux échéances, pas une
 *
 * Le décompte affichait toujours « Fermeture dans », y compris sur un Grand Prix
 * dont les pronostics n'étaient pas encore ouverts — il annonçait donc la
 * fermeture d'une chose qui n'avait pas commencé, et le joueur qui attendait le
 * lui voyait promettre treize jours de délai pour agir. Les deux échéances d'un
 * week-end sont distinctes et se suivent :
 *
 * | Phase | Échéance | Ce qui est dit |
 * |---|---|---|
 * | Avant le relevé des cotes | qualifications + 2h | « Ouverture dans » |
 * | Pronostics ouverts | départ − 5 min | « Fermeture dans » |
 *
 * **C'est `cotesArretees` qui départage, pas le statut brut**, et c'est ce qui
 * fait tenir l'ensemble : le bouton de pronostics du même bloc s'affiche sur
 * exactement la même condition. Un Grand Prix passé à `cotes_figees` par un
 * `POST /scraper/declencher` lancé un mardi annoncerait sinon « Fermeture dans »
 * au-dessus d'un bloc sans bouton — un compte à rebours vers une fermeture que
 * rien n'ouvrira. La règle 4.3 est lue une fois, et les deux s'accordent.
 *
 * ## Ce qui est rendu
 *
 * `label` est le titre affiché au-dessus du décompte, `texte` la phrase
 * (« 2j 14h 32min »), `restant` les millisecondes pour l'horloge à tuiles, et
 * `substitut` le mot qui prend la place du décompte quand il n'y en a pas.
 * **`texte` non nul est le seul test à faire pour savoir s'il y a quelque chose à
 * décompter** : les deux états sans échéance datée le laissent nul.
 *
 * `ferme` garde son sens d'origine — les pronostics sont fermés — et **il est
 * faux pendant toute la phase d'ouverture** : rien n'est fermé avant d'avoir été
 * ouvert, et c'est lui qui décide ailleurs du bouton « Modifier mes pronos ».
 */
export function etatPronostics(gp, maintenant = Date.now()) {
  // Aucun Grand Prix chargé : l'état d'attente des écrans, celui qu'ils
  // affichaient déjà sous leur squelette. On n'annonce ni ouverture ni
  // fermeture d'un Grand Prix qu'on n'a pas lu.
  if (!gp) {
    return {
      phase: "attente",
      ferme: false,
      restant: null,
      texte: null,
      label: "Départ",
      substitut: "À confirmer",
    };
  }

  const fermeture = etatFermeture(gp.date_course, maintenant);

  // **« Pas encore ouverts » exige les trois à la fois** : des cotes non
  // arrêtées, une heure de fermeture pas encore passée, et un Grand Prix qui
  // n'a pas couru. Le premier test suffirait un samedi matin ; il ne suffit
  // pas le dimanche soir, où un Grand Prix `termine` le passe aussi — et
  // l'écran de saisie aurait alors déverrouillé son formulaire sur une course
  // déjà courue, `ferme` étant ce qui le tient fermé. La phase d'ouverture est
  // celle qui précède, jamais celle qui suit.
  const jamaisOuverts =
    !cotesArretees(gp, maintenant) && !fermeture.ferme && gp.statut !== "termine";

  if (jamaisOuverts) {
    const ouverture = etatOuverture(gp.date_qualifications, maintenant);
    return {
      phase: "ouverture",
      ferme: false,
      restant: ouverture.restant,
      texte: ouverture.texte,
      // Sans qualifications datées, ou l'heure prévue passée sans que le
      // scraper ait figé quoi que ce soit : le titre perd son « dans », qui
      // n'introduirait plus rien.
      label: ouverture.texte ? "Ouverture dans" : "Ouverture",
      substitut: "À confirmer",
    };
  }

  if (fermeture.ferme || gp.statut === "termine") {
    return {
      phase: "fermeture",
      ferme: true,
      restant: 0,
      texte: null,
      label: "Pronostics",
      substitut: "Fermés",
    };
  }

  return {
    phase: "fermeture",
    ferme: false,
    restant: fermeture.restant,
    texte: fermeture.texte,
    // Un Grand Prix dont Unibet n'a pas annoncé l'heure de départ **reste
    // ouvert** — la règle des trois étages — mais il n'a aucune fermeture à
    // décompter : le titre annonce alors le départ, et le mot dit qu'on
    // l'attend.
    label: fermeture.texte ? "Fermeture dans" : "Départ",
    substitut: "À confirmer",
  };
}

/**
 * Résultats d'un Grand Prix.
 *
 * `championnatId` est facultatif, et c'est la route qui porte la distinction
 * (étape 6) : sans lui, le classement de la course seul, publiquement ; avec
 * lui, les pronostics de tous les membres, jeton exigé et appartenance
 * vérifiée.
 *
 * ## `mes_pronostics`, et pourquoi il ne double jamais `membres`
 *
 * On arrive maintenant sur cet écran par **deux portes** : depuis un
 * championnat, et depuis la carte d'un Grand Prix couru du calendrier. La
 * seconde n'a aucun championnat à donner, et la section « Mes résultats » y
 * restait donc vide — elle ne pouvait qu'inviter à repasser par la première.
 *
 * Les pronostics du joueur sont alors lus **directement sous RLS**
 * (`chargerMesPronosticsDuGp`), et servis à côté de la réponse de la route sous
 * la clé `mes_pronostics`. Les deux appels partent **ensemble** : la lecture
 * Supabase n'attend pas le réveil de Railway.
 *
 * > **Cette clé et `membres` sont exclusives, et c'est délibéré.** Avec un
 * > championnat, la route sert déjà les pronostics de tout le monde, celui de
 * > l'appelant compris : aller les relire serait une requête pour une donnée
 * > qu'on a en main, et surtout **une seconde valeur pour la même question** —
 * > les deux pourraient se contredire le temps d'un cache. `mes_pronostics`
 * > vaut donc `null` dès que `championnatId` est fourni, exactement comme
 * > `membres` vaut `null` quand il ne l'est pas.
 *
 * > **L'échec de la lecture Supabase n'emporte pas l'écran.** Le classement de
 * > la course est public et reste la raison principale d'ouvrir cette page ; il
 * > s'affiche, et seule la section « Mes résultats » dit qu'elle n'a pas pu
 * > charger. C'est la règle déjà appliquée au bouton de l'accueil.
 *
 * `profilId` absent — un visiteur sans compte — ne déclenche aucune lecture :
 * il n'y a personne dont montrer les pronostics, et la section le dit.
 */
export async function chargerResultatsGp(gpId, championnatId, profilId, signal) {
  const requete = championnatId
    ? `/grands-prix/${gpId}/resultats?championnat_id=${championnatId}`
    : `/grands-prix/${gpId}/resultats`;

  const solo = !championnatId && Boolean(profilId);

  const [servis, miens] = await Promise.all([
    appelApi(requete, { signal }),
    solo ? chargerMesPronosticsDuGp(gpId, profilId, signal) : null,
  ]);

  if (!servis.ok) return servis;

  return {
    ok: true,
    message: null,
    donnees: {
      ...servis.donnees,
      // `null` = pas demandé (un championnat le sert déjà, ou personne n'est
      // connecté). Un tableau = ce que le joueur a validé, vide compris.
      mes_pronostics: solo && miens.ok ? miens.donnees : null,
      // Demandé mais raté : la section le dit au lieu d'annoncer « aucun
      // pronostic », qui serait une affirmation qu'on n'a pas vérifiée.
      mes_pronostics_echec: solo && !miens.ok,
    },
  };
}

/** Clés de cache — elles portent toujours l'identifiant du compte connecté. */
export const cleCalendrier = (profilId, championnatId) =>
  `calendrier:${profilId}:${championnatId}`;
/**
 * **Le marqueur de version n'est pas décoratif**, et c'est la même leçon que
 * `cleSaison` : depuis la version `0.63.0` cette entrée porte `mes_pronostics`
 * en plus de ce que sert la route. Un cache d'avant ne l'a pas, et servi tel
 * quel il aurait fait afficher « Aucun pronostic sur ce Grand Prix » — une
 * affirmation fausse — le temps d'un aller-retour. Il est placé APRÈS
 * l'identifiant du compte pour qu'un balayage par préfixe continue de tout
 * emporter.
 */
export const cleResultats = (profilId, gpId, championnatId) =>
  `resultats:${profilId}:v2:${gpId}:${championnatId ?? "public"}`;

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
 *    à 28 points serait une information fausse. C'est la même décision que dans
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
