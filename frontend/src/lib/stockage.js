import { supabase } from "./supabase.js";
import { GENRE_DONNEES, GENRE_SESSION, GENRE_SUPABASE } from "./erreurs.js";

/**
 * Dépôt des photos dans Supabase Storage — avatars et photos de championnat.
 *
 * **Le fichier va DIRECTEMENT à Supabase, il ne passe jamais par Railway**, et
 * c'est le critère de `docs/architecture.md` §3 appliqué tel quel : les
 * politiques de `storage.objects` (migration `20260821180000`) décrivent
 * exactement le cas — le premier segment du chemin est l'identifiant du
 * propriétaire, et la politique le compare à `auth.uid()`. Faire transiter deux
 * mégaoctets par le plan gratuit de Railway n'ajouterait qu'un cold start et un
 * aller-retour, pour une autorisation que la base porte déjà.
 *
 * **L'URL obtenue, elle, s'enregistre par l'API** (`PATCH /profils/moi`,
 * `PATCH /championnats/{id}`). C'est une écriture en base, donc le chemin (A) du
 * même document, et surtout : c'est là que `url_de_photo_valide` vérifie que
 * l'adresse est bien celle de NOTRE projet. Une URL libre en base deviendrait un
 * pixel espion posé sur l'écran des autres joueurs (`backend/app/api/stockage.py`).
 *
 * **Toutes les vérifications faites ici sont faites deux fois.** Le compartiment
 * porte son propre plafond de taille et sa propre liste de types : c'est LUI qui
 * garde. Ce qui suit ne sert qu'à dire non tout de suite — deux mégaoctets
 * montés sur un réseau mobile avant d'être refusés seraient deux mégaoctets
 * perdus.
 */

const NON_CONFIGURE = "L'application n'est pas reliée à sa base de données.";
const DEPOT_IMPOSSIBLE =
  "Impossible d'envoyer cette photo. Réessaie dans quelques instants.";

/** Les deux compartiments de la migration `20260821180000`. */
export const COMPARTIMENT_AVATARS = "avatars";
export const COMPARTIMENT_CHAMPIONNATS = "championnats";

/** 2 Mo, la valeur exacte du plafond posé sur les deux compartiments. */
export const TAILLE_MAXIMALE = 2 * 1024 * 1024;

/**
 * Les trois types acceptés, et l'extension sous laquelle chacun se range.
 *
 * **Le HEIC de l'appareil photo d'un iPhone n'y est pas, et ce n'est pas un
 * oubli** : Safari convertit en JPEG à la sélection d'un fichier dans un
 * `<input type="file">`, si bien que le type reçu ici est déjà `image/jpeg`.
 * L'accepter obligerait à décoder du HEIC dans le navigateur pour rien.
 */
const TYPES_ACCEPTES = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

/**
 * Valeur de l'attribut `accept` du sélecteur de fichier.
 *
 * **Les types MIME, pas les extensions.** Sur iOS, `accept=".jpg,.png"` fait
 * ouvrir le sélecteur de fichiers du système au lieu de la photothèque ; une
 * liste de types MIME d'images fait proposer les photos en premier, ce qui est
 * le geste attendu. Elle est dérivée de `TYPES_ACCEPTES`, jamais réécrite : deux
 * listes séparées divergeraient au premier format ajouté, et l'écart se lirait
 * « ce fichier est refusé alors que le sélecteur me l'a proposé ».
 */
export const TYPES_ACCEPTES_ATTRIBUT = Object.keys(TYPES_ACCEPTES).join(",");

/** Les extensions possibles d'une même photo — voir `nettoyerAutresFormats`. */
const EXTENSIONS = Object.values(TYPES_ACCEPTES);

/** Taille lisible d'un plafond exprimé en octets : « 2 Mo ». */
function enMegaoctets(octets) {
  return `${Math.round(octets / (1024 * 1024))} Mo`;
}

/**
 * Le fichier est-il acceptable ? Rend `null`, ou un refus en français.
 *
 * **Une seule question, un seul propriétaire.** L'écran de profil et celui de
 * création d'un championnat posent la même question et doivent recevoir le même
 * refus, mot pour mot. Deux vérifications écrites séparément auraient divergé,
 * et celle qu'on aurait oublié de resserrer serait devenue la porte d'entrée.
 */
export function refusDuFichier(fichier) {
  if (!fichier) return "Aucun fichier sélectionné.";
  if (!TYPES_ACCEPTES[fichier.type]) {
    return "Choisis une image au format JPG, PNG ou WEBP.";
  }
  if (fichier.size > TAILLE_MAXIMALE) {
    return `Cette image dépasse ${enMegaoctets(TAILLE_MAXIMALE)}. Choisis-en une plus légère.`;
  }
  return null;
}

/**
 * Efface la même photo rangée sous une AUTRE extension.
 *
 * Le chemin d'une photo porte son format (`{dossier}/avatar.png`). Quelqu'un qui
 * remplace un PNG par un JPEG écrit donc un objet neuf **à côté** de l'ancien :
 * la base ne pointe plus que sur le nouveau, mais l'ancien resterait en
 * stockage, indéfiniment et invisible.
 *
 * Le ménage se fait **après** le dépôt, jamais avant : effacer d'abord
 * laisserait le membre sans photo si l'envoi échouait ensuite. Son propre échec
 * est ignoré — un objet orphelin est un défaut d'exploitation, pas une raison de
 * refuser à quelqu'un la photo qu'il vient de déposer.
 */
async function nettoyerAutresFormats(compartiment, dossier, base, gardee) {
  const autres = EXTENSIONS.filter((extension) => extension !== gardee).map(
    (extension) => `${dossier}/${base}.${extension}`,
  );
  try {
    await supabase.storage.from(compartiment).remove(autres);
  } catch {
    /* voir ci-dessus */
  }
}

/**
 * Dépose une photo et rend son URL publique.
 *
 * `upsert` est vrai : le chemin est **stable** (`{dossier}/{base}.{ext}`), donc
 * changer de photo écrase la précédente au lieu d'accumuler un objet par essai.
 * C'est aussi ce qui rend l'opération rejouable : un envoi interrompu puis
 * relancé aboutit au même état.
 *
 * **L'URL rendue porte un horodatage, et il n'est pas décoratif.** Le chemin
 * étant stable, l'URL publique l'est aussi : sans lui, le navigateur et le CDN
 * de Supabase continueraient de servir l'ANCIENNE image après un remplacement,
 * et rien en base ne changerait — donc aucun écran ne se redessinerait. Le
 * paramètre change à chaque dépôt : il périme le cache et fait changer la
 * colonne, deux effets pour un.
 */
export async function deposerPhoto({ compartiment, dossier, base, fichier }) {
  if (!supabase) {
    return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };
  }

  const refus = refusDuFichier(fichier);
  if (refus) return { ok: false, message: refus, genre: GENRE_DONNEES };

  const extension = TYPES_ACCEPTES[fichier.type];
  const chemin = `${dossier}/${base}.${extension}`;

  try {
    const { error } = await supabase.storage
      .from(compartiment)
      .upload(chemin, fichier, {
        upsert: true,
        contentType: fichier.type,
        // Une année de cache côté navigateur, sans risque : l'URL enregistrée
        // change à chaque dépôt (voir ci-dessus), donc l'image mise en cache
        // n'est jamais celle qu'on cherche à remplacer.
        cacheControl: "31536000",
      });

    if (error) {
      return { ok: false, message: DEPOT_IMPOSSIBLE, genre: GENRE_SUPABASE };
    }

    await nettoyerAutresFormats(compartiment, dossier, base, extension);

    const { data } = supabase.storage.from(compartiment).getPublicUrl(chemin);
    if (!data?.publicUrl) {
      return { ok: false, message: DEPOT_IMPOSSIBLE, genre: GENRE_SUPABASE };
    }

    return {
      ok: true,
      message: null,
      donnees: `${data.publicUrl}?v=${Date.now()}`,
    };
  } catch {
    return { ok: false, message: DEPOT_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

/**
 * Efface la photo d'un dossier, quel qu'ait été son format.
 *
 * **Son échec n'empêche jamais de retirer l'URL en base.** L'appelant efface la
 * colonne dans tous les cas : une photo qui reste en stockage sans être
 * référencée n'est plus affichée nulle part, alors qu'une colonne qui garderait
 * l'URL d'un objet supprimé afficherait une image cassée sur l'écran de tous les
 * membres du championnat.
 */
export async function supprimerPhoto({ compartiment, dossier, base }) {
  if (!supabase) return;
  try {
    await supabase.storage
      .from(compartiment)
      .remove(EXTENSIONS.map((extension) => `${dossier}/${base}.${extension}`));
  } catch {
    /* voir ci-dessus */
  }
}
