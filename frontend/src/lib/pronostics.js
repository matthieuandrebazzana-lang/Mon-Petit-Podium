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
 * Le début de la journée en cours, **à l'heure du téléphone**, en ISO.
 *
 * `setHours(0, 0, 0, 0)` travaille dans le fuseau local et `toISOString()` rend
 * l'instant correspondant en UTC : c'est bien minuit *ici* qu'on envoie à
 * PostgREST, pas minuit UTC. La différence n'est pas théorique — à Paris en
 * août, minuit local est 22h00 UTC la veille, et comparer à minuit UTC ferait
 * disparaître de l'accueil un Grand Prix couru l'après-midi dès 2h du matin.
 */
function debutDuJourLocal() {
  const minuit = new Date();
  minuit.setHours(0, 0, 0, 0);
  return minuit.toISOString();
}

/**
 * Le Grand Prix couru **aujourd'hui**, ou `null`.
 *
 * Il n'y en a jamais deux : la Formule 1 ne court pas deux courses le même jour.
 * La lecture porte donc sur `termine` et sur la seule journée en cours, et rend
 * au plus une ligne.
 *
 * **`termine` implique que les résultats existent** — le job de résultats écrit
 * `resultats_gp` et passe le statut dans le même mouvement (`scraper.md` §11) —
 * donc le bouton « Voir les résultats » que l'accueil pose dessus ne mène jamais
 * à un écran vide. C'est ce qui permet de se passer ici de la jointure
 * `resultats_gp!inner` dont `chargerDernierGpCouru` a besoin, elle qui remonte
 * une saison entière.
 */
async function chargerGpDuJour(signal) {
  const requete = supabase
    .from("grands_prix")
    .select("id, nom, date_course, date_qualifications, statut")
    .eq("statut", "termine")
    .gte("date_course", debutDuJourLocal())
    .lte("date_course", new Date().toISOString())
    .order("date_course", { ascending: false })
    .limit(1)
    .maybeSingle();

  const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
  if (error) return null;
  return data ?? null;
}

/**
 * Le prochain Grand Prix : celui qui n'a pas encore couru, à la date la plus
 * proche.
 *
 * > ### Le dimanche soir appartient encore au Grand Prix du jour
 * >
 * > Un Grand Prix passe à `termine` environ une heure et demie après le départ,
 * > et l'accueil basculait aussitôt sur le suivant — deux semaines plus loin,
 * > avec un compte à rebours de treize jours. C'est **le moment précis où tout
 * > le monde ouvre l'application**, et le seul où l'écran d'entrée n'avait rien
 * > à dire de ce qui venait de se passer.
 * >
 * > La règle : le Grand Prix couru garde la place **jusqu'à minuit, heure du
 * > téléphone**. Le lendemain, le suivant la prend.
 * >
 * > **La frontière est le jour civil, pas une durée.** « Six heures après la
 * > course » aurait fait basculer l'accueil en pleine soirée pour un départ à
 * > 15h, et en pleine nuit pour Las Vegas ; minuit est la seule limite que le
 * > joueur puisse prévoir sans la calculer, et c'est la même pour tout le monde
 * > dans un fuseau donné.
 * >
 * > **Rien ne change entre l'arrivée et le passage à `termine`** : le Grand Prix
 * > est encore `cotes_figees`, donc la lecture ci-dessous le sert déjà comme le
 * > plus proche à venir. Les deux règles se rejoignent sans laisser d'intervalle
 * > — c'est ce qui fait qu'il n'y a rien à coudre entre elles.
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
 * **`date_qualifications` est servie à côté du statut**, et les deux vont
 * ensemble : le bloc n'affiche son bouton de pronostics que sur un Grand Prix
 * dont les cotes sont figées ET dont les qualifications sont passées (voir
 * `cotesArretees` dans `lib/calendrier.js`). Le statut seul se laisse avancer
 * par un `POST /scraper/declencher` passé trop tôt ; l'heure des qualifications,
 * non.
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
    // Le Grand Prix du jour passe devant, et **son échec ne compte pas** :
    // `chargerGpDuJour` rend `null` plutôt qu'une erreur, et la lecture
    // ordinaire reprend la main. Le sens du doute va vers le Grand Prix à venir,
    // qui reste vrai — jamais vers un écran d'accueil vide un dimanche soir.
    const duJour = await chargerGpDuJour(signal);
    if (duJour) return { ok: true, message: null, donnees: duJour };

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
 */
export async function chargerMesPronostics(gpId, profilId, signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };
  if (!profilId) return { ok: true, message: null, donnees: [] };

  try {
    const requete = supabase
      .from("pronostics")
      .select("id, type, id_outcome_unibet, pronostic_podium(pilote_1, pilote_2)")
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

  // **`couru` se lit sur le statut, il ne se déduit plus du chemin pris.**
  // `chargerProchainGp` peut désormais rendre un Grand Prix `termine` — celui du
  // jour, qui garde la place jusqu'à minuit — et ce bloc était le seul endroit
  // qui savait ce que « couru » voulait dire. Le figer à `false` ici aurait
  // envoyé le widget proposer des pronostics sur une course déjà courue, avec un
  // compte à rebours à zéro : le défaut exact que la version `0.53.0` vient de
  // corriger sur les deux calendriers.
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
