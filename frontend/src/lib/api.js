import { API_URL } from "../config.js";
import { supabase } from "./supabase.js";
import {
  GENRE_RESEAU,
  GENRE_SERVEUR,
  GENRE_SESSION,
} from "./erreurs.js";

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
  "Connexion au serveur en cours… Réessaie dans quelques secondes.";
const REPLI = "Une erreur est survenue. Réessaie.";
const NON_CONNECTE = "Session expirée. Reconnecte-toi.";

const echec = (message, statut = 0, genre = GENRE_SERVEUR) => ({
  ok: false,
  message,
  statut,
  genre,
});
const succes = (donnees) => ({
  ok: true,
  donnees,
  message: null,
  statut: 200,
  genre: null,
});

/**
 * Vrai si la chaîne ressemble à un message technique plutôt qu'à du français.
 *
 * Depuis l'étape 9, le backend ne renvoie plus la cause technique : elle reste
 * dans les logs Railway (`app/api/journal.py`). Ce garde-fou n'est donc pas un
 * doublon de cette règle — il protège contre ce qui **ne vient pas de notre
 * backend** : une page d'erreur de Railway, un proxy qui s'interpose, une
 * ancienne version encore déployée. Aucun de ces textes ne doit atteindre
 * l'écran d'un joueur.
 *
 * La reconnaissance porte sur des signatures franches — code PostgreSQL,
 * vocabulaire d'exception, trace Python — et non sur « est-ce du français ? »,
 * question à laquelle une expression régulière ne sait pas répondre.
 */
const SIGNATURE_TECHNIQUE =
  /\b(?:code\s+[0-9A-Z]{5}|statut\s+\d{3}|Traceback|Error:|Exception|does not exist|permission denied|relation "|null value|Internal Server Error|Bad Gateway|Application failed)\b/i;

/**
 * Extrait le message d'une réponse d'erreur FastAPI.
 *
 * `detail` vaut une chaîne pour nos propres `HTTPException`, déjà en français.
 * Pour un corps refusé par la validation Pydantic, c'est une liste d'objets en
 * anglais, qu'on n'affiche jamais telle quelle.
 */
function messageDeLaReponse(corps, statut) {
  const detail = corps?.detail;
  if (typeof detail === "string" && detail.trim() && !SIGNATURE_TECHNIQUE.test(detail)) {
    return detail;
  }
  if (statut === 401) return NON_CONNECTE;
  return REPLI;
}

/**
 * Le genre d'échec, pour que l'écran sache quoi proposer (`lib/erreurs.js`).
 *
 * Les `502`, `503` et `504` sont classés **réseau** et non serveur : sur le plan
 * gratuit de Railway, c'est très exactement ce que rend un service encore
 * endormi. « Connexion au serveur en cours » est alors la description juste, et
 * réessayer marche.
 */
function genreDuStatut(statut) {
  if (statut === 401) return GENRE_SESSION;
  if (statut === 502 || statut === 503 || statut === 504) return GENRE_RESEAU;
  return GENRE_SERVEUR;
}

export async function appelApi(chemin, { methode = "GET", corps, signal } = {}) {
  if (!supabase) return echec(NON_CONNECTE, 0, GENRE_SESSION);

  let jeton;
  try {
    const { data } = await supabase.auth.getSession();
    jeton = data.session?.access_token;
  } catch {
    return echec(NON_CONNECTE, 0, GENRE_SESSION);
  }
  if (!jeton) return echec(NON_CONNECTE, 0, GENRE_SESSION);

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
    // `fetch` ne distingue pas « pas de réseau » de « serveur endormi » : les
    // deux lèvent la même TypeError. Le message couvre les deux cas.
    return echec(HORS_LIGNE, 0, GENRE_RESEAU);
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
    return echec(
      messageDeLaReponse(charge, reponse.status),
      reponse.status,
      genreDuStatut(reponse.status),
    );
  }

  return succes(charge);
}
