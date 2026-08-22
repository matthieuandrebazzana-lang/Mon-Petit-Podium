import { appelApi } from "./api.js";
import { supabase } from "./supabase.js";
import {
  GENRE_DONNEES,
  GENRE_SESSION,
  GENRE_SUPABASE,
} from "./erreurs.js";

/**
 * Profils, statistiques et Grands Prix pariés — étape 8.
 *
 * Les **deux chemins de données** des étapes 3 et 5 restent en vigueur, et le
 * partage se fait ici encore selon la politique RLS de la donnée servie :
 *
 * - **Le profil et ses statistiques** passent par l'API. Les statistiques
 *   agrègent les `points_gagnes` d'un membre, donc des lignes que la RLS de
 *   l'étape 5 réserve aux membres d'un championnat partagé : lues depuis le
 *   client, elles seraient silencieusement amputées au lieu d'être refusées.
 *   L'écriture (`PATCH /profils/moi`) y passe pour la même raison que toutes
 *   les autres depuis l'étape 3 : les contrôles métier ne vivent pas côté
 *   client.
 * - **Les Grands Prix pariés d'un membre** vont directement à Supabase. Voir
 *   `chargerGrandsPrixDuMembre` : la RLS y décrit exactement le cas, et le
 *   passage par l'API demanderait un appel par Grand Prix.
 */

const NON_CONFIGURE = "L'application n'est pas reliée à sa base de données.";
const LECTURE_IMPOSSIBLE =
  "Impossible de charger ces données. Réessaie dans quelques instants.";

// --------------------------------------------------------------------------
//  Par l'API
// --------------------------------------------------------------------------

export function chargerProfil(profilId, signal) {
  return appelApi(`/profils/${profilId}`, { signal });
}

export function chargerStats(profilId, signal) {
  return appelApi(`/profils/${profilId}/stats`, { signal });
}

export function enregistrerVoiture(modifications) {
  return appelApi("/profils/moi", { methode: "PATCH", corps: modifications });
}

/**
 * Enregistre — ou retire — la photo de profil de l'appelant.
 *
 * **Même route que la voiture, et c'est voulu** : `PATCH /profils/moi` est une
 * modification partielle, elle ne touche que ce qu'on lui transmet. Une route
 * dédiée aurait fait un second endroit où l'identité de l'appelant se déduit
 * d'un jeton, donc un second endroit à vérifier.
 *
 * **Le fichier, lui, n'est jamais passé ici** : il est déjà déposé dans Supabase
 * Storage (`lib/stockage.js`), et seule son URL remonte. C'est cette URL que le
 * backend confronte à celle du projet — la vérification qui empêche d'enregistrer
 * l'adresse d'un serveur tiers.
 *
 * `null` veut dire « retire ma photo », et se transmet par un drapeau explicite :
 * un `avatar_url: null` serait indiscernable d'un champ non transmis, exactement
 * comme pour le numéro de voiture.
 */
export function enregistrerAvatar(url) {
  return appelApi("/profils/moi", {
    methode: "PATCH",
    corps: url ? { avatar_url: url } : { retirer_avatar: true },
  });
}

/** Maquettes 12 et 14 : le profil et sa grille de stats, en une seule attente. */
export async function chargerProfilComplet(profilId, signal) {
  const [profil, stats] = await Promise.all([
    chargerProfil(profilId, signal),
    chargerStats(profilId, signal),
  ]);

  if (!profil.ok) return profil;

  // **L'échec des statistiques n'emporte pas le profil.** La voiture, le pseudo
  // et le numéro sont l'essentiel de l'écran ; la grille 2×2 est un
  // complément. Un écran vide serait pire qu'un écran sans ses quatre chiffres.
  return {
    ok: true,
    message: null,
    donnees: { profil: profil.donnees, stats: stats.ok ? stats.donnees : null },
  };
}

/** Clés de cache — elles portent toujours l'identifiant du compte connecté. */
export const cleProfil = (profilId, cible) => `profil:${profilId}:${cible}`;
export const cleMesGp = (profilId, cible) => `profil-gp:${profilId}:${cible}`;

// --------------------------------------------------------------------------
//  Directement dans Supabase, sous RLS
// --------------------------------------------------------------------------

/**
 * Les numéros déjà pris dans les championnats du membre.
 *
 * L'unicité du numéro est **par championnat et purement indicative** : deux
 * membres peuvent porter le 44, la sauvegarde n'est jamais bloquée. La liste
 * est donc chargée **une fois** au montage de l'écran, et la vérification « en
 * temps réel » se fait ensuite en mémoire, à chaque frappe. Un appel réseau par
 * caractère saisi serait le pire compromis possible pour un avertissement qui
 * ne bloque rien.
 *
 * Trois lectures, toutes couvertes par la RLS existante : mes adhésions
 * (politique de l'étape 3), les adhésions de mes championnats (`est_membre`),
 * les profils correspondants (« Profils lisibles par les membres connectés »).
 */
export async function chargerNumerosPris(profilId, signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };
  if (!profilId) return { ok: true, message: null, donnees: [] };

  try {
    const lire = (requete) => (signal ? requete.abortSignal(signal) : requete);

    const { data: miennes, error: erreurMiennes } = await lire(
      supabase
        .from("membres_championnat")
        .select("championnat_id")
        .eq("profil_id", profilId),
    );
    if (erreurMiennes) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    const championnats = (miennes ?? []).map((ligne) => ligne.championnat_id);
    if (championnats.length === 0) return { ok: true, message: null, donnees: [] };

    const { data: membres, error: erreurMembres } = await lire(
      supabase
        .from("membres_championnat")
        .select("profil_id")
        .in("championnat_id", championnats),
    );
    if (erreurMembres) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    // Le membre lui-même est écarté : son propre numéro n'est pas « déjà pris ».
    const autres = [
      ...new Set((membres ?? []).map((ligne) => ligne.profil_id)),
    ].filter((id) => id !== profilId);
    if (autres.length === 0) return { ok: true, message: null, donnees: [] };

    const { data: profils, error: erreurProfils } = await lire(
      supabase
        .from("profils")
        .select("id, pseudo, numero")
        .in("id", autres)
        .not("numero", "is", null),
    );
    if (erreurProfils) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    return {
      ok: true,
      message: null,
      donnees: (profils ?? []).map((p) => ({ numero: p.numero, pseudo: p.pseudo })),
    };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

/** Le pseudo qui porte déjà ce numéro, ou `null`. Vérification en mémoire. */
export function porteurDuNumero(pris, numero) {
  const valeur = Number(numero);
  if (!Number.isInteger(valeur)) return null;
  return (pris ?? []).find((ligne) => ligne.numero === valeur)?.pseudo ?? null;
}

/**
 * Maquette 13 — tous les Grands Prix pariés par un membre, avec ses pronostics.
 *
 * **Écart assumé par rapport à la demande**, et il porte sur la source, pas sur
 * le contenu. La demande dit d'appeler
 * `GET /grands-prix/{gp_id}/pronostics/championnat/{championnat_id}` en filtrant
 * sur ce membre. Cette route existe (étape 5) mais n'a pas la forme de cet
 * écran :
 *
 * - elle sert **un** Grand Prix à la fois. L'écran en liste toute une saison :
 *   il faudrait un aller-retour Railway par Grand Prix, en série, sur un écran
 *   atteint depuis un profil ;
 * - elle sert **tous** les membres du championnat. On en jetterait tout sauf
 *   un, à chaque appel ;
 * - elle ne dit pas quels Grands Prix ce membre a pariés : il faudrait déjà
 *   connaître la liste pour l'interroger.
 *
 * Les trois lectures ci-dessous font le travail en une passe, et **sous
 * exactement la même protection** : la politique de l'étape 5 n'ouvre les
 * pronostics d'autrui qu'aux membres d'un championnat partagé. Un curieux qui
 * devinerait un identifiant de profil ne lira rien — c'est la base qui refuse,
 * pas l'écran.
 *
 * Les cotes sont en lecture publique depuis l'étape 4 : ce sont elles qui
 * donnent le nom du pilote et les points possibles.
 */
export async function chargerGrandsPrixDuMembre(profilId, signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };
  if (!profilId) return { ok: true, message: null, donnees: [] };

  try {
    const lire = (requete) => (signal ? requete.abortSignal(signal) : requete);

    const { data: pronostics, error: erreurPronostics } = await lire(
      supabase
        .from("pronostics")
        .select(
          "id, gp_id, type, id_outcome_unibet, points_gagnes, pronostic_podium(pilote_1, pilote_2)",
        )
        .eq("profil_id", profilId),
    );
    if (erreurPronostics) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    const lignes = pronostics ?? [];
    if (lignes.length === 0) return { ok: true, message: null, donnees: [] };

    const gpIds = [...new Set(lignes.map((ligne) => ligne.gp_id))];

    const [{ data: gps, error: erreurGps }, { data: cotes, error: erreurCotes }] =
      await Promise.all([
        lire(
          supabase
            .from("grands_prix")
            .select("id, nom, date_course, statut")
            .in("id", gpIds)
            .order("date_course", { ascending: false, nullsFirst: false }),
        ),
        lire(
          supabase
            .from("cotes")
            .select("gp_id, id_outcome_unibet, marche, libelle_marche, pilote, valeur")
            .in("gp_id", gpIds),
        ),
      ]);

    if (erreurGps || erreurCotes) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    return {
      ok: true,
      message: null,
      donnees: assemblerGrandsPrix(lignes, gps ?? [], cotes ?? []),
    };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

/**
 * Assemble les trois lectures en une liste de Grands Prix prête à afficher.
 *
 * Exportée pour être vérifiable seule : c'est la seule vraie logique de cet
 * écran, et elle porte les deux règles qui comptent — la somme des deux cotes
 * pour un podium (règle tranchée à l'étape 6) et la distinction entre « raté »
 * (`0`) et « pas encore jugé » (`null`), qui ne doivent jamais se confondre.
 */
export function assemblerGrandsPrix(pronostics, gps, cotes) {
  const index = new Map(
    cotes.map((cote) => [`${cote.gp_id}:${cote.id_outcome_unibet}`, cote]),
  );

  const decrire = (gpId, outcome) => index.get(`${gpId}:${outcome}`) ?? null;

  const parGp = new Map();
  for (const brut of pronostics) {
    if (!parGp.has(brut.gp_id)) parGp.set(brut.gp_id, []);

    // PostgREST rend une jointure « un vers un » tantôt en objet, tantôt en
    // tableau d'un élément selon la version : les deux formes sont acceptées.
    const detail = Array.isArray(brut.pronostic_podium)
      ? brut.pronostic_podium[0]
      : brut.pronostic_podium;

    const premiere = decrire(brut.gp_id, brut.id_outcome_unibet);
    const seconde = detail ? decrire(brut.gp_id, detail.pilote_2) : null;

    const pilotes = [premiere, ...(detail ? [seconde] : [])];

    parGp.get(brut.gp_id).push({
      id: brut.id,
      type: brut.type,
      // Le libellé du marché vient du bookmaker (étape 4) : lui seul nomme
      // correctement un marché. À défaut, on retombe sur le type.
      libelle: premiere?.libelle_marche ?? etiquetteDuType(brut.type),
      // Un podium se lit « Norris + Piastri » : les deux pilotes forment un
      // seul pronostic, sans ordre entre eux (schéma de l'étape 5).
      choix: pilotes
        .map((cote) => cote?.pilote ?? null)
        .filter(Boolean)
        .join(" + ") || null,
      // Ce que le pronostic PEUT rapporter. Pour un podium, la somme des deux
      // cotes : la même règle qu'à l'étape 6 pour ce qu'il rapporte vraiment.
      points: pilotes.some((cote) => cote)
        ? pilotes.reduce((total, cote) => total + (cote?.valeur ?? 0), 0)
        : null,
      // Ce qu'il a rapporté. `null` = pas encore jugé, `0` = raté. Les deux ne
      // se confondent jamais (convention de l'étape 6).
      pointsGagnes: brut.points_gagnes ?? null,
    });
  }

  const ordre = { vainqueur: 0, podium: 1, bonus: 2 };

  return gps.map((gp) => {
    const siens = (parGp.get(gp.id) ?? []).sort(
      (a, b) => (ordre[a.type] ?? 9) - (ordre[b.type] ?? 9),
    );
    const juges = siens.filter((p) => p.pointsGagnes !== null);

    return {
      ...gp,
      termine: gp.statut === "termine",
      pronostics: siens,
      // Ces trois totaux ne valent que pour un GP jugé : avant la course, ils
      // annonceraient un score de zéro qui n'a pas encore de sens.
      total: juges.reduce((somme, p) => somme + p.pointsGagnes, 0),
      reussis: juges.filter((p) => p.pointsGagnes > 0).length,
      juges: juges.length,
    };
  });
}

function etiquetteDuType(type) {
  if (type === "vainqueur") return "Vainqueur";
  if (type === "podium") return "Podium";
  return "Bonus";
}

// --------------------------------------------------------------------------
//  L'identité courante — lue en base, jamais dans le jeton
// --------------------------------------------------------------------------

/**
 * Le pseudo **et la photo** tels qu'ils sont en base, pour ce profil.
 *
 * **Pourquoi cette lecture existe.** `useAuth().pseudo` ne lit pas la table
 * `public.profils` : il lit `user_metadata.pseudo`, c'est-à-dire une copie
 * figée dans le jeton au moment de l'inscription. Renommer quelqu'un
 * directement en base — ou par n'importe quel chemin qui ne repasse pas par
 * `auth.updateUser` — ne touche pas cette copie, et l'accueil continuait
 * d'afficher l'ancien pseudo aussi longtemps que la session vivait. C'est le
 * défaut corrigé ici.
 *
 * **Directement dans Supabase, et non par l'API**, pour les deux raisons qui
 * gouvernent ce partage depuis l'étape 3 : la politique « Profils lisibles par
 * les membres connectés » décrit exactement ce cas, et l'accueil est le premier
 * écran de l'app — lui faire attendre le réveil de Railway pour écrire « Salut
 * X » serait le pire endroit où payer ce délai.
 *
 * La lecture ne porte que les colonnes utiles : le reste du profil (couleurs,
 * numéro) a ses propres écrans, qui le chargent quand ils en ont besoin.
 *
 * > ### `avatar_url` voyage avec le pseudo, et n'ajoute AUCUNE requête
 * >
 * > La pastille de la barre d'accueil mène au profil et porte désormais la
 * > photo du compte connecté (version `0.52.0`). Elle avait besoin d'une seule
 * > chose de plus, dans la même ligne, sous la même politique RLS : une colonne
 * > ajoutée à un `select` déjà indexé sur clé primaire coûte exactement zéro
 * > aller-retour. Un second chargeur — ou pire, un `chargerProfil` complet passé
 * > par Railway — aurait fait payer un réveil de serveur au premier écran de
 * > l'app pour une vignette de 42 pixels.
 * >
 * > **Le champ est facultatif, et son absence n'est pas une panne.** Un backend
 * > ou une base d'avant la migration `20260821180000` rendent `undefined` : la
 * > pastille retombe alors sur l'initiale, ce qui est son état par défaut.
 */
export async function chargerIdentite(profilId, signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };
  if (!profilId) return { ok: true, message: null, donnees: null };

  try {
    const requete = supabase
      .from("profils")
      .select("pseudo, avatar_url")
      .eq("id", profilId)
      .maybeSingle();

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    // `maybeSingle` rend `null` plutôt que de lever quand la ligne n'existe
    // pas : un profil absent n'est pas une panne, c'est un compte dont le
    // trigger d'inscription n'a rien écrit. L'appelant retombera alors sur le
    // pseudo du jeton, qui vaut mieux que rien.
    if (!data) return { ok: true, message: null, donnees: null };

    return {
      ok: true,
      message: null,
      donnees: { pseudo: data.pseudo ?? null, avatarUrl: data.avatar_url ?? null },
    };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}

/**
 * Le drapeau d'administration de ce profil, tel qu'il est **en base**.
 *
 * **Jamais depuis un cache, et c'est la seule règle qui compte ici.** Le cache
 * *stale-while-revalidate* de `useDonnees` est le bon outil pour la liste des
 * championnats — il fait tenir l'accueil pendant le réveil de Railway — et le
 * mauvais pour un droit : une valeur écrite dans `localStorage` survit à la
 * révocation du droit, et se modifie depuis les outils de développement. Ce
 * chargeur ne passe donc pas par lui, exactement comme `chargerIdentite`.
 *
 * **Directement dans Supabase, et non par l'API**, pour la raison qui gouverne
 * ce partage depuis l'étape 3 : la politique « Profils lisibles par les membres
 * connectés » décrit exactement ce cas, et la lecture porte sur une clé
 * primaire. Passer par Railway n'ajouterait qu'un cold start à une lecture qui
 * conditionne l'affichage d'une section.
 *
 * **Le doute referme la section, il ne l'ouvre jamais.** Base non migrée, ligne
 * absente, réseau coupé, colonne renommée : tous ces cas rendent `false`. C'est
 * l'inverse du sens du doute appliqué au pseudo — un pseudo périmé vaut mieux
 * que pas de pseudo, une section d'administration affichée à tort ne vaut rien.
 *
 * Ce drapeau ne garde d'ailleurs rien : il décide d'un affichage. Le seul garde
 * réel de `POST /scraper/declencher` est le secret `X-Admin-Secret`, vérifié
 * côté backend à temps constant.
 */
export async function chargerEstAdmin(profilId, signal) {
  if (!supabase) return { ok: false, message: NON_CONFIGURE, genre: GENRE_SESSION };
  if (!profilId) return { ok: true, message: null, donnees: false };

  try {
    const requete = supabase
      .from("profils")
      .select("is_admin")
      .eq("id", profilId)
      .maybeSingle();

    const { data, error } = await (signal ? requete.abortSignal(signal) : requete);
    if (error) return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };

    // `=== true` et non une conversion en booléen : une colonne absente rend
    // `undefined`, une ligne absente rend `null`, et les deux doivent valoir
    // « non administrateur » sans que personne ait à s'en souvenir.
    return { ok: true, message: null, donnees: data?.is_admin === true };
  } catch (erreur) {
    if (erreur.name === "AbortError") throw erreur;
    return { ok: false, message: LECTURE_IMPOSSIBLE, genre: GENRE_SUPABASE };
  }
}
