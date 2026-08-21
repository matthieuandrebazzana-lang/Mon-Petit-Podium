import { appelApi } from "./api.js";
import { supabase } from "./supabase.js";
import {
  GENRE_DONNEES,
  GENRE_SESSION,
  GENRE_SUPABASE,
} from "./erreurs.js";

/**
 * Deux chemins de données coexistent, et c'est délibéré.
 *
 * - **Écritures et règles métier** (créer, rejoindre, quitter, lister) passent
 *   par FastAPI. Le code d'invitation s'y génère, la création y est atomique,
 *   et rejoindre suppose de retrouver un championnat dont on n'est pas encore
 *   membre — donc invisible sous RLS. Rien de tout cela n'est faisable depuis
 *   le client.
 * - **Lecture du détail** (le championnat et ses membres) va directement à
 *   Supabase. Les politiques RLS de la migration décrivent exactement ce cas :
 *   on ne lit un championnat que si on en est membre, et ses membres que si on
 *   le partage. Passer par Railway n'ajouterait qu'un cold start.
 */

const NON_CONFIGURE =
  "L'application n'est pas reliée à sa base de données.";
const INTROUVABLE =
  "Ce championnat n'existe pas, ou tu n'en fais plus partie.";
const LECTURE_IMPOSSIBLE =
  "Impossible de charger ce championnat. Réessaie dans quelques instants.";

export function listerMesChampionnats(signal) {
  return appelApi("/championnats/moi", { signal });
}

export function creerChampionnat(nom) {
  return appelApi("/championnats", { methode: "POST", corps: { nom } });
}

export function rejoindreChampionnat(code) {
  return appelApi("/championnats/rejoindre", {
    methode: "POST",
    corps: { code },
  });
}

export function quitterChampionnat(id) {
  return appelApi(`/championnats/${id}/quitter`, { methode: "DELETE" });
}

/**
 * Enregistre — ou retire — la photo d'un championnat. Créateur seul.
 *
 * **Elle s'appelle APRÈS la création, jamais pendant**, et c'est le chemin de
 * stockage qui l'impose : une photo de championnat vit sous
 * `{championnat_id}/photo.{ext}`, donc sous un identifiant que seule la création
 * rend. La transmettre à `POST /championnats` obligerait à la déposer ailleurs
 * puis à la déplacer.
 *
 * **Son échec n'annule pas la création.** L'écran de création laisse partir le
 * joueur vers son championnat même si la photo n'a pas pu être enregistrée : il
 * a un championnat sans photo, pas un formulaire à refaire.
 */
export function enregistrerPhotoChampionnat(id, url) {
  return appelApi(`/championnats/${id}`, {
    methode: "PATCH",
    corps: url ? { photo_url: url } : { retirer_photo: true },
  });
}

/**
 * Championnat + liste de ses membres, lus sous RLS.
 *
 * Deux requêtes plutôt qu'une jointure imbriquée : `membres_championnat`
 * référence `auth.users`, pas `public.profils`, donc PostgREST n'a aucune
 * relation à suivre entre les deux. Les effectifs restent petits.
 */
export async function chargerChampionnat(id, signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };

  try {
    const requete = supabase
      .from("championnats")
      .select("id, nom, code_invitation, cree_par, cree_le, photo_url")
      .eq("id", id)
      .maybeSingle();

    const { data: championnat, error: erreurChampionnat } = await (signal
      ? requete.abortSignal(signal)
      : requete);

    if (erreurChampionnat) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
    if (!championnat) return { ok: false, message: INTROUVABLE, genre: GENRE_DONNEES };

    const requeteMembres = supabase
      .from("membres_championnat")
      .select("profil_id, rejoint_le")
      .eq("championnat_id", id)
      .order("rejoint_le", { ascending: true });

    const { data: lignes, error: erreurMembres } = await (signal
      ? requeteMembres.abortSignal(signal)
      : requeteMembres);

    if (erreurMembres) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    const identifiants = (lignes ?? []).map((ligne) => ligne.profil_id);
    // La ligne entière est indexée, et non le seul pseudo : la photo s'y ajoute
    // depuis la migration `20260821180000`, et une `Map` par colonne aurait
    // demandé une lecture de plus à chaque champ affiché.
    let membres = new Map();

    if (identifiants.length > 0) {
      const { data: profils } = await supabase
        .from("profils")
        .select("id, pseudo, avatar_url")
        .in("id", identifiants);
      membres = new Map((profils ?? []).map((p) => [p.id, p]));
    }

    return {
      ok: true,
      message: null,
      donnees: {
        ...championnat,
        // Un pseudo manquant ne doit pas trouer la liste : il se peut que la
        // migration des profils n'ait pas encore tourné sur ce projet.
        membres: (lignes ?? []).map((ligne) => ({
          id: ligne.profil_id,
          pseudo: membres.get(ligne.profil_id)?.pseudo || "Pilote",
          // `?? null` et non `|| null` : une colonne absente (base non encore
          // migrée) et une photo non choisie doivent valoir la même chose, sans
          // que la pastille ait à s'en souvenir.
          avatarUrl: membres.get(ligne.profil_id)?.avatar_url ?? null,
          rejointLe: ligne.rejoint_le,
        })),
      },
    };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}
