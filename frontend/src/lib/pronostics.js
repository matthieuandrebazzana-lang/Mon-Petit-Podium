import { appelApi } from "./api.js";
import { oublierCache, oublierCachePrefixe } from "./useDonnees.js";
import { supabase } from "./supabase.js";
import { clePilote, formaterPilote } from "./format.js";
import {
  GENRE_DONNEES,
  GENRE_SESSION,
  GENRE_SUPABASE,
} from "./erreurs.js";

/**
 * Cotes, favoris et pronostics — étape 5.
 *
 * Les **deux chemins de données** de l'étape 3 restent en vigueur, pour les
 * mêmes raisons :
 *
 * - **Écritures et règles métier** (bascule d'un favori, enregistrement d'un
 *   pronostic) passent par FastAPI. La fermeture cinq minutes avant le départ,
 *   le contrôle « les bonus sont bien dans les favoris » et le remplacement
 *   atomique du jeu précédent ne peuvent pas vivre côté client.
 * - **Lectures** vont directement à Supabase quand les politiques RLS
 *   décrivent exactement le cas : le prochain GP et les cotes sont en lecture
 *   publique, et un joueur lit toujours ses propres pronostics. Passer par
 *   Railway n'y ajouterait qu'un réveil à froid, sur les écrans les plus
 *   consultés du parcours.
 *
 * Une exception assumée : le **tableau des cotes** de la maquette 08 passe par
 * `GET /grands-prix/{id}/cotes`, l'endpoint public de l'étape 4. Il sert les
 * cotes déjà groupées par marché, ce que le regroupement en base
 * (`cotes_du_grand_prix`) fait mieux que le frontend, et l'écran doit de toute
 * façon appeler l'API pour les favoris.
 */

const NON_CONFIGURE = "L'application n'est pas reliée à sa base de données.";
const LECTURE_IMPOSSIBLE =
  "Impossible de charger ces données. Réessaie dans quelques instants.";

// Marchés dont sont tirés les deux pronostics obligatoires (règle 4.2). Ce
// sont les slugs que le scraper fabrique depuis les libellés Unibet
// « Vainqueur » et « Podium ». Le backend applique exactement les mêmes ; s'ils
// changent chez Unibet, les deux refusent de leur côté et l'écran le dit.
/**
 * Le pilote — ou les deux pilotes — sur lesquels porte un pronostic.
 *
 * **Sortie de l'écran de résultats en version `0.53.0`**, parce qu'un second
 * écran pose exactement la même question (« Résultats par Grand Prix »). Écrite
 * deux fois, elle aurait divergé sur le cas qui compte : un **podium** nomme
 * DEUX pilotes, sans ordre entre eux (règle 4.2), et l'écran qui l'aurait oublié
 * n'en aurait affiché qu'un sans que rien ne le signale.
 *
 * Une cote retirée par Unibet depuis la saisie laisse `pilote` à `null` : le
 * pronostic reste affiché et le dit, plutôt que de disparaître de la liste.
 */
export function choixDuPronostic(pronostic) {
  if (pronostic.podium) {
    const deux = [pronostic.podium.nom_1, pronostic.podium.nom_2]
      .filter(Boolean)
      .map(formaterPilote);
    if (deux.length > 0) return deux.join(" + ");
  }
  return formaterPilote(pronostic.pilote) ?? "Cote retirée par le bookmaker";
}

export const MARCHE_VAINQUEUR = "vainqueur";
export const MARCHE_PODIUM = "podium";
export const BONUS_MAXIMUM = 3;

/* --------------------------------------------------------------------------
   L'ordre d'affichage des marchés — par catégorie, jamais par l'ordre
   d'Unibet.

   Le bookmaker sert ses marchés dans l'ordre de sa page, qui n'a aucune raison
   d'être celui dans lequel on les joue : les deux obligatoires peuvent s'y
   trouver entre deux duels. Cette liste est donc la **source unique** de
   l'ordre, et les deux écrans du parcours de saisie la suivent — le tableau
   des cotes pour ses sections de marché, l'écran de saisie pour la liste des
   paris bonus. Un ordre écrit dans chacun des deux aurait divergé au premier
   ajustement, et le symptôme serait discret : le même marché à deux places
   différentes selon la porte d'entrée.

   ### La reconnaissance porte sur le SLUG, et les tests sont mutuellement
   exclusifs

   Le slug est celui que `scraper.unibet.slug()` fabrique depuis le libellé
   Unibet (`marche` en base) : le libellé affiché, lui, est du texte de
   bookmaker et change de casse et de ponctuation d'un Grand Prix à l'autre.

   **Aucun test ne doit pouvoir en recouvrir un autre**, sans quoi l'ordre des
   entrées ci-dessous cesserait d'être l'ordre d'affichage pour devenir un
   ordre de priorité — deux choses qui ne veulent pas la même chose, et dont la
   confusion est exactement le piège que `calcul/points.py` documente côté
   backend : « ecurie-vainqueur » contient « vainqueur », et le triplé
   « vainqueur course + qualification + tour le plus rapide » contient à la fois
   « vainqueur » et « tour le plus rapide ». D'où l'égalité STRICTE sur les deux
   marchés obligatoires, et l'exclusion de « qualif » de la famille du tour le
   plus rapide. Cette liste est **ordonnée pour l'œil**, pas pour l'algorithme.

   **Un marché non reconnu part à la fin**, dans l'ordre où Unibet l'a servi :
   les marchés varient d'un Grand Prix à l'autre (`scraper.md` §3.1), et un
   marché inconnu doit s'afficher quand même — le taire serait pire que le mal
   placer.
   -------------------------------------------------------------------------- */

/* « Top 6 », « Top 10 », « Dans le top 3 » — le rang est dans le nom, il ne
   peut pas être connu d'avance. Même expression que le backend, au même
   endroit du raisonnement. */
function rangTop(slug) {
  const trouve = /^(?:dans-le-)?top-?(\d+)$/.exec(slug);
  return trouve ? Number(trouve[1]) : null;
}

/* « Tour le plus rapide », « Meilleur tour ». `qualif` est exclu ici et
   nulle part ailleurs : c'est ce qui laisse le triplé à sa catégorie. */
function estTourRapide(slug) {
  return (
    slug.includes("tour") &&
    (slug.includes("rapide") || slug.includes("meilleur")) &&
    !slug.includes("qualif")
  );
}

export const ORDRE_MARCHES = [
  // Obligatoires (règle 4.2) — égalité stricte, voir ci-dessus.
  { cle: "vainqueur", reconnait: (slug) => slug === MARCHE_VAINQUEUR },
  { cle: "podium", reconnait: (slug) => slug === MARCHE_PODIUM },

  // Résultat de course. La famille « top N » tient en UNE entrée et s'ordonne
  // sur son rang : « Top 6 » avant « Top 10 » n'est pas un choix éditorial,
  // c'est l'ordre des nombres, et un « Top 3 » découvert un jour se rangera de
  // lui-même devant les deux au lieu d'échouer à la fin de la liste.
  { cle: "top", reconnait: (slug) => rangTop(slug) !== null, ordonne: rangTop },
  {
    cle: "ecart-du-gagnant",
    reconnait: (slug) =>
      slug.includes("ecart") ||
      (slug.includes("marge") && slug.includes("victoire")),
  },
  {
    cle: "tour-le-plus-rapide",
    reconnait: (slug) => estTourRapide(slug) && !slug.includes("voiture"),
  },
  {
    cle: "voiture-tour-le-plus-rapide",
    reconnait: (slug) => estTourRapide(slug) && slug.includes("voiture"),
  },

  // Écurie.
  {
    cle: "ecurie-vainqueur",
    reconnait: (slug) =>
      slug.startsWith("ecurie") ||
      slug.startsWith("equipe") ||
      slug.startsWith("constructeur"),
  },

  // Anecdotique.
  {
    cle: "nationalite-du-vainqueur",
    reconnait: (slug) =>
      slug.includes("nationalite") ||
      (slug.includes("pays") &&
        (slug.includes("vainqueur") || slug.includes("gagnant"))),
  },
  {
    cle: "vainqueur-course-qualification-tour",
    reconnait: (slug) => slug.includes("qualif"),
  },

  // Duels entre coéquipiers — tous ensemble, en dernier. Il y en a jusqu'à
  // onze, un par écurie : intercalés, ils enterreraient tout le reste.
  {
    cle: "duel",
    reconnait: (slug) => slug.includes("duel") || slug.includes("coequipier"),
  },
];

/**
 * Le rang d'affichage d'un marché : `[catégorie, rang dans la catégorie]`.
 *
 * Deux nombres et non un seul, parce qu'une catégorie peut avoir un ordre
 * interne — la famille des « top N » en a un, et c'est le seul cas.
 */
export function rangMarche(marche) {
  const slug = (marche || "").trim().toLowerCase();
  if (!slug) return [ORDRE_MARCHES.length, 0];

  const rang = ORDRE_MARCHES.findIndex((categorie) =>
    categorie.reconnait(slug),
  );
  if (rang === -1) return [ORDRE_MARCHES.length, 0];
  return [rang, ORDRE_MARCHES[rang].ordonne?.(slug) ?? 0];
}

/**
 * Trie par catégorie de marché tout ce qui porte un slug `marche`.
 *
 * **Les deux formes passent par ici** : un groupe de cotes du tableau des
 * cotes (`{ marche, libelle, cotes }`) comme un pari bonus de l'écran de
 * saisie (`{ marche, libelle, pilote, points, … }`). C'est la même question
 * posée sur deux objets, donc la même fonction — et c'est ce qui garantit
 * qu'un pari bonus ne remonte pas dans la liste de saisie à une place que son
 * marché n'a pas au tableau des cotes.
 *
 * **Le tri est stable, et le rang d'origine est le dernier départage** : à
 * catégorie égale, c'est l'ordre d'Unibet qui tranche, comme pour les marchés
 * non reconnus. La liste d'entrée n'est jamais modifiée — elle vient d'un
 * cache que deux écrans se partagent.
 */
export function trierParMarche(liste) {
  return (liste ?? [])
    .map((element, rang) => ({
      element,
      rang,
      cle: rangMarche(element?.marche),
    }))
    .sort(
      (a, b) => a.cle[0] - b.cle[0] || a.cle[1] - b.cle[1] || a.rang - b.rang,
    )
    .map((entree) => entree.element);
}

// --------------------------------------------------------------------------
//  Écritures — par FastAPI
// --------------------------------------------------------------------------

export function basculerFavori(gpId, idOutcome) {
  return appelApi(`/grands-prix/${gpId}/favoris`, {
    methode: "POST",
    corps: { id_outcome_unibet: idOutcome },
  });
}

export function enregistrerPronostics(gpId, saisie) {
  return appelApi(`/grands-prix/${gpId}/pronostics`, {
    methode: "POST",
    corps: saisie,
  });
}

export function chargerPronosticsChampionnat(gpId, championnatId, signal) {
  return appelApi(
    `/grands-prix/${gpId}/pronostics/championnat/${championnatId}`,
    { signal },
  );
}

// --------------------------------------------------------------------------
//  Lectures
// --------------------------------------------------------------------------

export function chargerCotes(gpId, signal) {
  return appelApi(`/grands-prix/${gpId}/cotes`, { signal });
}

export function chargerFavoris(gpId, signal) {
  return appelApi(`/grands-prix/${gpId}/favoris`, { signal });
}

/**
 * Le prochain Grand Prix : celui qui n'a pas encore couru, à la date la plus
 * proche.
 *
 * > ### Un Grand Prix terminé n'est plus le prochain
 * >
 * > Le Grand Prix couru gardait la place du widget d'accueil **jusqu'à minuit,
 * > heure du téléphone** : une lecture supplémentaire ramenait le `termine` du
 * > jour et le servait avant les autres. La règle a été retirée. Elle laissait
 * > l'accueil sur un Grand Prix fini bien après qu'il l'était — et le défaut ne
 * > venait pas de son implémentation mais de son principe : le seul état qui
 * > dise « c'est fini » est le statut, pas l'heure qu'il est.
 * >
 * > **Dès qu'un Grand Prix passe à `termine`, le suivant prend sa place.** Il n'y
 * > a plus de fenêtre pendant laquelle l'accueil annonce une course déjà courue,
 * > donc plus rien à coudre entre deux règles : les deux statuts non courus
 * > suffisent, et le dimanche soir se lit sur l'écran de résultats, qui est fait
 * > pour ça.
 * >
 * > **Rien ne change entre l'arrivée et le passage à `termine`** : le Grand Prix
 * > est encore `cotes_figees`, donc la lecture ci-dessous le sert toujours comme
 * > le plus proche à venir, avec un compte à rebours à zéro et des pronostics
 * > fermés — ce qui est exact.
 *
 * **Les deux statuts non courus sont retenus, `a_venir` et `cotes_figees`.**
 * Le second manquait, et son absence rendait le bloc de l'accueil aveugle
 * précisément au moment où il sert le plus : dès que le job du samedi fige les
 * cotes, le Grand Prix quittait la liste des `a_venir`, la lecture ne trouvait
 * plus rien, et l'accueil retombait sur le dernier Grand Prix couru — celui de
 * la semaine d'avant — pendant tout le week-end de course. C'est aussi le
 * filtre qu'appliquent déjà `GET /championnats/moi` (étape 10) et le décompte
 * des Grands Prix restants : les trois lectures disent maintenant la même
 * chose.
 *
 * **`date_qualifications` est servie à côté du statut**, mais elle ne commande
 * plus le bouton de pronostics depuis la version `0.65.0` : `cotesArretees` ne
 * lit que le statut et l'heure de départ (`lib/calendrier.js`). Elle reste lue
 * pour le compte à rebours d'**ouverture** du bloc, qui annonce le relevé des
 * cotes deux heures après les qualifications — une prévision, jamais une
 * condition.
 *
 * Lu directement sous RLS — la politique « Grands prix lisibles par tous » de
 * l'étape 4 couvre exactement ce cas, et l'accueil est l'écran qui souffrirait
 * le plus d'un réveil de Railway.
 *
 * `nullsFirst: false` n'est pas cosmétique : un GP dont Unibet n'a pas encore
 * annoncé l'horaire passerait devant tous les autres, et l'accueil annoncerait
 * comme « prochain » un GP sans date.
 */
export async function chargerProchainGp(signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };

  try {
    const requete = supabase
      .from("grands_prix")
      .select("id, nom, date_course, date_qualifications, statut")
      .in("statut", ["a_venir", "cotes_figees"])
      .order("date_course", { ascending: true, nullsFirst: false })
      .limit(1)
      .maybeSingle();

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    // Aucun GP en base n'est un état normal tant que le scraper n'a pas tourné :
    // `null`, pas une erreur.
    return { ok: true, message: null, donnees: data ?? null };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

/**
 * Les Grands Prix sur lesquels l'appelant a déjà enregistré des pronostics.
 *
 * Une lecture, une colonne, et un `Set` en retour. C'est tout ce qu'il faut pour
 * qu'un bouton dise « Voir mes pronos » au lieu de « Pronostiquer » — la
 * question est booléenne par Grand Prix, elle n'a pas besoin du détail.
 *
 * **Lue directement sous RLS**, comme les Grands Prix pariés d'un membre : la
 * politique de l'étape 5 autorise un joueur à lire ses propres pronostics sans
 * réserve, et passer par Railway pour une colonne d'identifiants ferait payer un
 * réveil de serveur sur l'onglet Calendrier, qui est en bas de l'écran de tout
 * le monde.
 *
 * **Son échec ne se propage pas, et c'est voulu** : `ok: true` avec un ensemble
 * vide. Le calendrier retomberait alors sur « Pronostiquer », qui reste vrai —
 * un joueur peut toujours rouvrir le tableau des cotes et modifier sa saisie
 * jusqu'à la fermeture. Le sens du doute va vers le libellé qui ne ment jamais.
 */
export async function chargerMesGpPronostiques(profilId, signal) {
  if (!supabase) return { ok: true, message: null, donnees: new Set() };
  if (!profilId) return { ok: true, message: null, donnees: new Set() };

  try {
    const requete = supabase
      .from("pronostics")
      .select("gp_id")
      .eq("profil_id", profilId);

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: true, message: null, donnees: new Set() };

    return {
      ok: true,
      message: null,
      donnees: new Set((data ?? []).map((ligne) => ligne.gp_id)),
    };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: true, message: null, donnees: new Set() };
  }
}

/**
 * Les pronostics du joueur pour un GP, lus sous RLS.
 *
 * `pronostic_podium` est ramené par jointure imbriquée : la clé étrangère
 * existe, PostgREST sait donc la suivre. Les cotes, elles, n'ont aucune
 * relation déclarée avec les pronostics — le rapprochement se fait par
 * `id_outcome_unibet`, côté appelant, avec les cotes qu'il a déjà chargées.
 *
 * **`points_gagnes` voyage avec le reste depuis la version `0.63.0`**, et
 * n'ajoute aucune requête : c'est une colonne de plus sur une lecture déjà
 * filtrée par `(gp_id, profil_id)`. Les trois appelants d'avant l'ignorent —
 * la saisie et le récapitulatif n'ont rien à en faire, l'accueil ne compte que
 * les lignes. Le quatrième, « Mes résultats » sur un Grand Prix ouvert hors
 * championnat, n'existe **que** pour lui. `null` veut toujours dire « pas
 * encore jugé », jamais « raté » (règle 4.1).
 */
export async function chargerMesPronostics(gpId, profilId, signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };
  if (!profilId) return { ok: true, message: null, donnees: [] };

  try {
    const requete = supabase
      .from("pronostics")
      .select(
        "id, type, id_outcome_unibet, points_gagnes, pronostic_podium(pilote_1, pilote_2)",
      )
      .eq("gp_id", gpId)
      .eq("profil_id", profilId);

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    return { ok: true, message: null, donnees: data ?? [] };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

// --------------------------------------------------------------------------
//  Chargements composés — un seul état d'attente par écran
// --------------------------------------------------------------------------

/**
 * Combine plusieurs résultats en un seul.
 *
 * Le premier échec l'emporte : afficher un demi-écran et une erreur en même
 * temps demanderait au joueur de deviner ce qui manque.
 */
function combiner(resultats, assembler) {
  const rate = resultats.find((resultat) => !resultat.ok);
  if (rate) return rate;
  return { ok: true, message: null, donnees: assembler(...resultats.map((r) => r.donnees)) };
}

/** Maquette 08 : les cotes du GP et les favoris déjà épinglés. */
export async function chargerTableauCotes(gpId, signal) {
  const [cotes, favoris] = await Promise.all([
    chargerCotes(gpId, signal),
    chargerFavoris(gpId, signal),
  ]);
  return combiner([cotes, favoris], (gp, epingles) => ({ gp, favoris: epingles }));
}

/**
 * Maquette 04 : le prochain Grand Prix, et si le joueur y a déjà des
 * pronostics enregistrés — c'est ce qui décide où mène le bouton du bloc rouge.
 *
 * Les deux lectures sont **enchaînées, pas parallèles** : l'identifiant du GP
 * n'existe qu'une fois la première revenue. Elles vont toutes les deux
 * directement à Supabase, sous les politiques RLS qui décrivent exactement ces
 * deux cas — l'accueil ne paie donc toujours aucun réveil de Railway, et le
 * cache *stale-while-revalidate* de `useDonnees` sert l'état connu
 * immédiatement au lancement.
 *
 * **L'échec de la seconde lecture n'emporte pas la première.** Le Grand Prix
 * est l'information principale du bloc ; savoir où mène son bouton n'est qu'un
 * raccourci. En cas d'échec, le joueur est envoyé vers les cotes : l'écran de
 * saisie sait retrouver seul les pronostics déjà enregistrés, alors qu'un
 * récapitulatif vide serait un cul-de-sac.
 */
/**
 * Clé de cache du bloc « Prochain GP ».
 *
 * Écrite ici plutôt qu'à ses deux points d'usage : l'accueil la lit, l'écran de
 * saisie l'oublie après une validation. Deux chaînes en dur auraient divergé au
 * premier renommage, et le symptôme aurait été discret — un bouton qui propose
 * encore « Pronostiquer » juste après avoir enregistré.
 */
export const cleAccueilGp = (profilId) => `accueil-gp:${profilId}`;

/**
 * Le calendrier de la saison, onglet Calendrier.
 *
 * **Le marqueur de version n'est pas décoratif** : depuis la version `0.53.0`
 * cette entrée porte deux choses — les cotes en base ET les Grands Prix que
 * l'appelant a déjà joués — là où elle ne portait qu'un tableau de cotes. Servi
 * tel quel, un cache d'une version antérieure aurait rendu douze cartes sans
 * état ni bouton le temps d'un aller-retour. Il est placé APRÈS l'identifiant,
 * comme celui du classement, pour qu'un balayage par préfixe de compte continue
 * de tout emporter.
 */
export const cleSaison = (profilId) => `saison:${profilId}:v2`;

/**
 * Oublie tout ce qui décide du libellé d'un bouton de pronostics.
 *
 * **Trois surfaces portent ce bouton** — l'accueil, le calendrier de la saison,
 * le calendrier d'un championnat — et une quatrième montre les pronostics de
 * tout le monde. Toutes lisent un cache *stale-while-revalidate* : sans cet
 * oubli, revenir sur l'une d'elles juste après une validation y trouve encore
 * « Pronostiquer », c'est-à-dire le défaut exact que cette version corrige,
 * réintroduit par le cache.
 *
 * **Une seule fonction pour les quatre**, même motif qu'`oublierMesApparitions`
 * dans l'écran de profil : quatre effacements écrits séparément auraient fini
 * par en oublier un, et le symptôme — un seul écran resté en arrière — serait
 * passé inaperçu longtemps. Les deux calendriers sont balayés par préfixe :
 * l'écran de saisie ne connaît pas les championnats de l'appelant.
 */
export function oublierMesPronostics(profilId) {
  if (!profilId) return;
  oublierCache(cleAccueilGp(profilId));
  oublierCache(cleSaison(profilId));
  oublierCachePrefixe(`calendrier:${profilId}:`);
  oublierCachePrefixe(`pronos-gp:${profilId}:`);
}

/**
 * Le dernier Grand Prix **couru**, résultats compris.
 *
 * Sert de repli à l'accueil en intersaison et entre deux courses : dès que le
 * job passe un GP à `termine`, il quitte la liste des `a_venir` et le bloc
 * rouge n'avait plus rien à annoncer jusqu'au scraping du samedi suivant. Le
 * dimanche soir d'un Grand Prix, c'est précisément l'écran que tout le monde
 * ouvre.
 *
 * La lecture reste directe, sous les politiques publiques des étapes 4 et 6 :
 * `grands_prix` et `resultats_gp` sont lisibles par tous. La jointure sur
 * `resultats_gp` n'est pas décorative — un GP passé à `termine` sans résultats
 * enregistrés (course annulée, job en échec) ne doit pas envoyer l'accueil vers
 * un écran de résultats vide.
 */
export async function chargerDernierGpCouru(signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };

  try {
    const requete = supabase
      .from("grands_prix")
      .select("id, nom, date_course, statut, resultats_gp!inner(gp_id)")
      .order("date_course", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    return { ok: true, message: null, donnees: data ?? null };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

/**
 * Combien de Grands Prix restent à courir cette saison.
 *
 * Sert le bandeau de bas d'écran de l'accueil et de l'onglet Championnats : il
 * habille le blanc laissé sous une liste courte, sans rien inventer — c'est un
 * décompte, pas une phrase d'ambiance.
 *
 * **Lu directement dans Supabase, et sans jeton.** `grands_prix` est en lecture
 * publique depuis l'étape 4 : ce décompte n'apprend rien à personne que le
 * calendrier de la Formule 1 ne dise déjà. C'est aussi ce qui permet de ne pas
 * réveiller Railway pour trois mots en bas de page.
 *
 * `head: true` ne rapatrie **aucune ligne** — seul l'en-tête de comptage
 * revient. Le filtre est exactement celui du prochain GP de l'accueil : les
 * statuts non courus, et les départs pas encore passés. **Un Grand Prix dont
 * Unibet n'a pas annoncé l'horaire est compté quand même** : il reste un Grand
 * Prix à jouer, et l'écarter le ferait disparaître du décompte jusqu'au samedi
 * des qualifications. C'est le même arbitrage qu'au calendrier de l'étape 9.
 */
export async function chargerGrandsPrixRestants(signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };

  try {
    const maintenant = new Date().toISOString();
    const requete = supabase
      .from("grands_prix")
      .select("id", { count: "exact", head: true })
      .in("statut", ["a_venir", "cotes_figees"])
      .or(`date_course.is.null,date_course.gte.${maintenant}`);

    const { count, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    return { ok: true, message: null, donnees: count ?? 0 };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

export async function chargerAccueilGp(profilId, signal) {
  const prochain = await chargerProchainGp(signal);
  if (!prochain.ok) return prochain;

  let gp = prochain.donnees;

  // Aucun Grand Prix à venir : on montre le dernier couru et son bouton mène
  // aux résultats. **L'échec de ce repli n'emporte pas l'accueil** — c'est la
  // même règle que pour les pronostics ci-dessous : le bloc garde sa place et
  // dit qu'aucun Grand Prix n'est ouvert, ce qui reste vrai.
  if (!gp) {
    const dernier = await chargerDernierGpCouru(signal);
    if (dernier.ok && dernier.donnees) {
      return {
        ok: true,
        message: null,
        donnees: { gp: dernier.donnees, aPronostique: false, couru: true },
      };
    }
    return {
      ok: true,
      message: null,
      donnees: { gp: null, aPronostique: false, couru: false },
    };
  }

  // **`couru` se lit sur le statut, jamais sur le chemin pris.**
  // `chargerProchainGp` ne rend plus de Grand Prix `termine` depuis la version
  // `0.57.0`, donc ce test est aujourd'hui toujours faux sur cette branche — et
  // il reste écrit. C'est lui qui dit ce que « couru » veut dire, et le déduire
  // du chemin remettrait la question à un appelant qui, lui, ne lit pas le
  // statut : le widget proposerait des pronostics sur une course déjà courue,
  // avec un compte à rebours à zéro.
  const couru = gp.statut === "termine";
  if (couru) {
    return { ok: true, message: null, donnees: { gp, aPronostique: false, couru: true } };
  }

  const miens = await chargerMesPronostics(gp.id, profilId, signal);

  return {
    ok: true,
    message: null,
    donnees: {
      gp,
      aPronostique: miens.ok && (miens.donnees?.length ?? 0) > 0,
      couru: false,
    },
  };
}

/** Maquette 09 : tout ce qu'il faut pour saisir, y compris la saisie en cours. */
export async function chargerSaisie(gpId, profilId, signal) {
  const [cotes, favoris, miens] = await Promise.all([
    chargerCotes(gpId, signal),
    chargerFavoris(gpId, signal),
    chargerMesPronostics(gpId, profilId, signal),
  ]);
  return combiner([cotes, favoris, miens], (gp, epingles, pronostics) => ({
    gp,
    favoris: epingles,
    pronostics,
  }));
}

/** Maquette 10 : les pronostics du joueur, rapprochés des cotes pour les points. */
export async function chargerRecap(gpId, profilId, signal) {
  const [cotes, miens] = await Promise.all([
    chargerCotes(gpId, signal),
    chargerMesPronostics(gpId, profilId, signal),
  ]);
  return combiner([cotes, miens], (gp, pronostics) => ({ gp, pronostics }));
}

/**
 * « Mes résultats » sur un Grand Prix ouvert **hors championnat**.
 *
 * ## Le défaut que cela corrige
 *
 * La section « Mes résultats » de l'écran de résultats affichait « ouvre ce
 * Grand Prix depuis un championnat » dès qu'on y arrivait par le calendrier —
 * c'est-à-dire par le chemin le plus court, celui de la carte d'un Grand Prix
 * couru. Le message était exact et sans remède : `GET /grands-prix/{id}/
 * resultats` ne sert **aucun** pronostic sans `championnat_id`, et pour une
 * bonne raison (étape 6) — les pronostics d'un membre ne sortent qu'aux membres
 * de ses championnats.
 *
 * **Mais un pronostic n'appartient pas à un championnat.** La table
 * `pronostics` porte `(profil_id, gp_id)` et rien d'autre : le joueur en a
 * **un seul jeu** par Grand Prix, partagé par tous ses championnats. Le
 * championnat ne sert qu'à décider *à qui d'autre* on a le droit de le montrer.
 * Pour se le montrer **à soi-même**, il n'a jamais rien eu à dire.
 *
 * ## Pourquoi cette lecture-ci, et pas la route
 *
 * C'est le **second chemin de données** de l'étape 5, appliqué au cas qu'il
 * décrit le mieux : la politique « Pronostics visibles entre membres » ouvre
 * son premier terme sur `profil_id = auth.uid()`, et son commentaire de
 * migration dit explicitement pourquoi — « un joueur qui n'appartient encore à
 * aucun championnat doit pouvoir relire ses propres pronostics ». Un compte
 * sans championnat est précisément le cas que cette section doit servir.
 *
 * > **Écart signalé (CLAUDE.md §6) : l'alternative était backend, et elle a été
 * > écartée pour une raison de calendrier, pas de conception.** Faire servir
 * > `pronostics_du_joueur(auth, gp)` par la route sans `championnat_id` aurait
 * > gardé **un** propriétaire à la mise en forme, au lieu des deux qu'il y a
 * > maintenant (cette fonction et la fonction SQL). Mais cela déplace le
 * > correctif sur Railway, où la version `0.57.0` du backend **n'est toujours
 * > pas déployée** : la section serait restée exactement aussi vide qu'avant,
 * > jusqu'à un déploiement que ce commit ne peut pas faire. Le prix de l'écart
 * > est connu et borné — `decrirePronostics` doit rendre les mêmes champs que
 * > `pronostics_du_joueur`, et c'est écrit à côté d'elle.
 *
 * **Les deux lectures sont celles du récapitulatif, sans une de plus** : les
 * cotes publiques donnent le pilote, le marché et les points possibles, la
 * lecture RLS donne les pronostics et leurs points gagnés.
 */
export async function chargerMesPronosticsDuGp(gpId, profilId, signal) {
  const recap = await chargerRecap(gpId, profilId, signal);
  if (!recap.ok) return recap;

  return {
    ok: true,
    message: null,
    donnees: decrirePronostics(
      recap.donnees.pronostics,
      indexerCotes(recap.donnees.gp),
    ),
  };
}

// --------------------------------------------------------------------------
//  Rapprochement cotes ↔ pronostics
// --------------------------------------------------------------------------

/** Index `id_outcome_unibet` → cote, à partir de la réponse groupée par marché. */
export function indexerCotes(gp) {
  const index = new Map();
  for (const marche of gp?.marches ?? []) {
    for (const cote of marche.cotes) {
      index.set(cote.id, { ...cote, marche: marche.marche, libelle: marche.libelle });
    }
  }
  return index;
}

export function marcheDe(gp, slug) {
  return (gp?.marches ?? []).find((marche) => marche.marche === slug) ?? null;
}

/* --------------------------------------------------------------------------
   Exclusion croisée — un même pilote ne peut pas occuper deux places.

   Un pilote choisi comme vainqueur est déjà premier, donc déjà sur le podium :
   le reproposer aux deux emplacements suivants revient à proposer de miser deux
   fois sur le même événement. Même chose entre les deux emplacements du podium,
   que le schéma de l'étape 5 interdit d'ailleurs en base (`check` sur
   `pronostic_podium`). Écarter de la liste vaut mieux que laisser choisir puis
   refuser après coup.

   **La comparaison se fait sur le LIBELLÉ du pilote, jamais sur
   `id_outcome_unibet`.** C'est le point à ne pas défaire : un même pilote ne
   porte pas le même identifiant d'issue selon le marché — Antonelli vaut
   `o701093319` au marché « Vainqueur » et `o701094802` au marché « Podium » du
   même Grand Prix (relevé à la version `0.6.1`). Un filtre par identifiant
   n'exclurait donc **jamais** le vainqueur du podium, alors même qu'il
   fonctionne entre les deux emplacements du podium, tirés du même marché.
   `clePilote` normalise (minuscules, accents, espaces) : c'est la clé même dont
   `formaterPilote` se sert pour nommer, les deux ne peuvent pas diverger.

   Ces deux fonctions vivent ici et non dans l'écran parce qu'elles sont du
   rapprochement de données, pas de la mise en page — au même titre
   qu'`organiserPronostics` juste en dessous.
   -------------------------------------------------------------------------- */

/**
 * Les options d'un emplacement, débarrassées des pilotes déjà pris ailleurs.
 *
 * `conserver` est l'identifiant du choix courant de cet emplacement-là : il
 * reste dans sa propre liste quoi qu'il arrive. Sans lui, un emplacement en
 * conflit verrait sa ligne disparaître de l'accordéon ouvert, et le joueur ne
 * verrait plus ce qu'il est en train de remplacer.
 */
export function optionsDisponibles(options, prises, conserver = null) {
  const exclues = new Set(
    (prises ?? [])
      .filter((cote) => cote?.pilote)
      .map((cote) => clePilote(cote.pilote)),
  );
  return (options ?? []).filter(
    (option) =>
      option.id === conserver || !exclues.has(clePilote(option.pilote)),
  );
}

/* --------------------------------------------------------------------------
   Les bonus **encore épinglés**, et le défaut que cela corrige.

   L'écran de saisie comptait ses bonus sur l'état prérempli depuis les
   pronostics déjà enregistrés. Or **un bonus enregistré n'est pas forcément
   encore un favori** : le joueur peut avoir dépunaisé la cote dans le tableau
   des cotes après avoir validé, et le pronostic, lui, reste en base. La rangée
   correspondante n'est alors plus affichée — la liste ne montre que les favoris
   — mais son identifiant restait compté. D'où « 3 sur 3 max » avec deux cases
   cochées, et, pire, les autres favoris grisés par une saturation que rien à
   l'écran n'expliquait.

   Ce n'était pas seulement un compteur faux : **la saisie aurait été refusée**.
   La route vérifie que chaque bonus est bien dans les favoris (règle 4.2) et
   nomme la cote fautive ; le joueur aurait vu un message désignant une cote
   absente de son écran.

   Une dérivation, et non un filtrage à l'initialisation : elle reste juste
   quand `useDonnees` sert d'abord le cache puis les données fraîches, où les
   favoris peuvent changer **après** le préremplissage. Et l'état brut est
   conservé côté écran — un bonus dont la cote est réépinglée redevient coché de
   lui-même, ce qu'il est toujours en base.
   -------------------------------------------------------------------------- */
export function bonusEpingles(bonus, favoris) {
  const epingles = new Set(
    (favoris ?? []).map((favori) => favori.id_outcome_unibet),
  );
  return (bonus ?? []).filter((idOutcome) => epingles.has(idOutcome));
}

/** Un choix entre-t-il en conflit avec l'un de ceux déjà pris ailleurs ? */
export function enConflit(choix, prises) {
  if (!choix?.pilote) return false;
  const cle = clePilote(choix.pilote);
  return (prises ?? []).some(
    (cote) => cote?.pilote && clePilote(cote.pilote) === cle,
  );
}

/**
 * Les pronostics d'un joueur **dans la forme que l'API leur donne**.
 *
 * ## Ce que cette fonction doit rendre, et pourquoi ce n'est pas négociable
 *
 * Elle est la contrepartie JavaScript de `public.pronostics_du_joueur`
 * (migration `20260813205200`), la fonction SQL dont sortent les pronostics de
 * chaque membre d'un championnat. **Les deux alimentent le MÊME écran**, à deux
 * sections d'écart : « Mes résultats » quand on arrive par le calendrier,
 * « Classement ce GP » quand on arrive par un championnat. Un pronostic doit
 * s'y lire à l'identique — même marché, même sélection, même verdict.
 *
 * Les huit champs ci-dessous sont donc **exactement** ceux du `jsonb_build_object`
 * de la fonction SQL, valeur pour valeur, y compris ce qui pourrait surprendre :
 *
 * - `points` est la cote de la **première** issue seulement. Pour un podium, la
 *   seconde vit dans `podium.points_2` et n'est **pas** ajoutée ici. Ce n'est
 *   pas une omission : c'est ce que la fonction SQL rend, et sommer d'un seul
 *   côté ferait afficher deux potentiels différents pour le même pari selon la
 *   porte par laquelle on est entré. Le jour où la somme est retenue, elle se
 *   décide en SQL et se recopie ici — jamais l'inverse.
 * - `podium` reste `null` quand la ligne de détail manque, plutôt que d'être un
 *   objet aux noms nuls : `choixDuPronostic` retombe alors sur `pilote`, ce qui
 *   nomme au moins un pilote au lieu de n'en nommer aucun.
 * - `points_gagnes` est `null` tant que le calcul n'a rien tranché, `0` quand le
 *   pronostic est raté. Les deux ne se confondent jamais (règle 4.1).
 *
 * L'ordre est celui de la fonction SQL — vainqueur, podium, bonus, puis le
 * pilote — et il compte : c'est l'ordre dans lequel le joueur a saisi, donc
 * celui dans lequel il relit.
 *
 * `index` est celui d'`indexerCotes` : une cote y porte `pilote`, `points`,
 * `marche` et `libelle`, les quatre colonnes que la fonction SQL lit sur la
 * table `cotes`. Une issue retirée par Unibet depuis la saisie laisse tout à
 * `null` et le pronostic reste affiché — le faire disparaître ferait croire au
 * joueur qu'il a oublié de le saisir.
 */
export function decrirePronostics(pronostics, index) {
  const cote = (idOutcome) => index.get(idOutcome) ?? null;
  const rang = { vainqueur: 1, podium: 2, bonus: 3 };

  return (pronostics ?? [])
    .map((brut) => {
      const premiere = cote(brut.id_outcome_unibet);

      // PostgREST rend une jointure « un vers un » tantôt en objet, tantôt en
      // tableau d'un élément selon la version : les deux formes sont acceptées,
      // comme partout ailleurs dans ce module.
      const detail = Array.isArray(brut.pronostic_podium)
        ? brut.pronostic_podium[0]
        : brut.pronostic_podium;
      const seconde = detail ? cote(detail.pilote_2) : null;

      return {
        id: brut.id,
        type: brut.type,
        outcome: brut.id_outcome_unibet,
        pilote: premiere?.pilote ?? null,
        marche: premiere?.marche ?? null,
        libelle: premiere?.libelle ?? null,
        points: premiere?.points ?? null,
        points_gagnes: brut.points_gagnes ?? null,
        podium: detail
          ? {
              pilote_1: detail.pilote_1,
              pilote_2: detail.pilote_2,
              nom_1: premiere?.pilote ?? null,
              nom_2: seconde?.pilote ?? null,
              points_2: seconde?.points ?? null,
            }
          : null,
      };
    })
    .sort(
      (a, b) =>
        (rang[a.type] ?? 9) - (rang[b.type] ?? 9) ||
        // Une issue retirée par Unibet n'a plus de pilote : elle passe en
        // dernier de son groupe, comme le `nulls last` que PostgreSQL applique
        // par défaut à l'`order by x.pilote` de la fonction SQL. Sans ce test,
        // la chaîne vide la ferait remonter en tête.
        (a.pilote === null) - (b.pilote === null) ||
        String(a.pilote ?? "").localeCompare(String(b.pilote ?? ""), "fr"),
    );
}

/**
 * Met les pronostics bruts en forme d'affichage : un vainqueur, un podium à
 * deux pilotes, des bonus, tous porteurs de leurs points.
 *
 * Une cote retirée par Unibet depuis la saisie laisse le pronostic en place,
 * sans points. Le faire disparaître serait pire : le joueur croirait avoir
 * oublié de le saisir.
 */
export function organiserPronostics(pronostics, index) {
  const decrire = (idOutcome) => {
    const cote = index.get(idOutcome);
    return {
      outcome: idOutcome,
      pilote: cote?.pilote ?? null,
      points: cote?.points ?? null,
      libelle: cote?.libelle ?? null,
    };
  };

  const brut = pronostics ?? [];
  const vainqueur = brut.find((p) => p.type === "vainqueur");
  const podium = brut.find((p) => p.type === "podium");
  const bonus = brut.filter((p) => p.type === "bonus");

  // PostgREST rend une jointure « un vers un » tantôt en objet, tantôt en
  // tableau d'un élément selon la version : les deux formes sont acceptées.
  const detail = Array.isArray(podium?.pronostic_podium)
    ? podium?.pronostic_podium[0]
    : podium?.pronostic_podium;

  return {
    vainqueur: vainqueur ? decrire(vainqueur.id_outcome_unibet) : null,
    podium: detail ? [decrire(detail.pilote_1), decrire(detail.pilote_2)] : [],
    bonus: bonus.map((p) => decrire(p.id_outcome_unibet)),
    vide: brut.length === 0,
  };
}
