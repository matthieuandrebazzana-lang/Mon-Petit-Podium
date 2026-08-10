import { API_URL } from "../config.js";
import { supabase } from "./supabase.js";

/**
 * Appels à l'API FastAPI, toujours signés par le jeton Supabase courant.
 *
 * Comme `lib/erreurs.js` pour l'authentification, ce module est le seul point
 * de traduction des échecs réseau : rien ne part dans la console, tout ressort
 * en français, prêt à être affiché.
 *
 * Le jeton est relu à chaque appel plutôt que mémorisé : supabase-js le
 * rafraîchit tout seul en arrière-plan, et un jeton capturé une fois pour
 * toutes finirait par être périmé au retour d'une longue mise en veille.
 */

const HORS_LIGNE =
  "Connexion impossible. Vérifie ta connexion internet et réessaie.";
const REPLI = "Quelque chose n'a pas fonctionné. Réessaie dans quelques instants.";
const NON_CONNECTE = "Session expirée. Reconnecte-toi.";

const echec = (message, statut = 0) => ({ ok: false, message, statut });
const succes = (donnees) => ({ ok: true, donnees, message: null, statut: 200 });

/**
 * Extrait le message d'une réponse d'erreur FastAPI.
 *
 * `detail` vaut une chaîne pour nos propres `HTTPException` — déjà en français.
 * Pour un corps refusé par la validation Pydantic, c'est une liste d'objets en
 * anglais, qu'on n'affiche jamais telle quelle.
 */
function messageDeLaReponse(corps, statut) {
  const detail = corps?.detail;
  if (typeof detail === "string" && detail.trim()) return detail;
  if (statut === 401) return NON_CONNECTE;
  return REPLI;
}

export async function appelApi(chemin, { methode = "GET", corps, signal } = {}) {
  if (!supabase) return echec(NON_CONNECTE);

  let jeton;
  try {
    const { data } = await supabase.auth.getSession();
    jeton = data.session?.access_token;
  } catch {
    return echec(NON_CONNECTE);
  }
  if (!jeton) return echec(NON_CONNECTE);

  let reponse;
  try {
    reponse = await fetch(`${API_URL}${chemin}`, {
      method: methode,
      signal,
      headers: {
        Authorization: `Bearer ${jeton}`,
        ...(corps ? { "Content-Type": "application/json" } : {}),
      },
      body: corps ? JSON.stringify(corps) : undefined,
    });
  } catch (erreur) {
    // L'annulation d'une requête n'est pas une panne : elle remonte telle
    // quelle pour que l'appelant l'ignore au lieu d'afficher une erreur.
    if (erreur.name === "AbortError") throw erreur;
    return echec(HORS_LIGNE);
  }

  // 204 sur les suppressions : pas de corps à lire.
  if (reponse.status === 204) return succes(null);

  let charge = null;
  try {
    charge = await reponse.json();
  } catch {
    charge = null;
  }

  if (!reponse.ok) {
    return echec(messageDeLaReponse(charge, reponse.status), reponse.status);
  }

  return succes(charge);
}
