import { appelApi } from "./api.js";
import { supabase } from "./supabase.js";

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
 * Le prochain Grand Prix : celui en statut `a_venir` dont la date est la plus
 * proche.
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
  if (!supabase) return { ok: false, message: NON_CONFIGURE };

  try {
    const requete = supabase
      .from("grands_prix")
      .select("id, nom, date_course, statut")
      .eq("statut", "a_venir")
      .order("date_course", { ascending: true, nullsFirst: false })
      .limit(1)
      .maybeSingle();

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE };

    // Aucun GP en base n'est un état normal tant que le scraper n'a pas tourné :
    // `null`, pas une erreur.
    return { ok: true, message: null, donnees: data ?? null };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE };
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
  if (!supabase) return { ok: false, message: NON_CONFIGURE };
  if (!profilId) return { ok: true, message: null, donnees: [] };

  try {
    const requete = supabase
      .from("pronostics")
      .select("id, type, id_outcome_unibet, pronostic_podium(pilote_1, pilote_2)")
      .eq("gp_id", gpId)
      .eq("profil_id", profilId);

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE };

    return { ok: true, message: null, donnees: data ?? [] };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE };
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
