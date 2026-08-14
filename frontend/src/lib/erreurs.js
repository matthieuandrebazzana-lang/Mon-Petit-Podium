/**
 * Traduction des erreurs Supabase Auth en messages français affichables.
 *
 * Règle du projet : une erreur ne part JAMAIS dans la console, elle est
 * toujours rendue dans l'interface. Ce module est donc le seul point de
 * passage — tout appel à `supabase.auth.*` fait transiter son erreur ici.
 *
 * Supabase expose depuis 2024 un champ `code` stable (`invalid_credentials`,
 * `weak_password`…). Les projets plus anciens et certains chemins d'erreur ne
 * renvoient que `message`, en anglais. On teste donc le code d'abord, puis on
 * retombe sur une reconnaissance par sous-chaîne.
 */

/** Message unique, réutilisé par les deux chemins qui détectent un doublon. */
export const PSEUDO_DEJA_PRIS = "Ce pseudo est déjà pris. Choisis-en un autre.";

const PAR_CODE = {
  // — Inscription —
  email_exists: "Cette adresse est déjà utilisée. Connecte-toi plutôt.",
  // Violation d'unicité PostgreSQL, remontée telle quelle par PostgREST lors
  // d'un renommage de profil vers un pseudo déjà occupé.
  23505: PSEUDO_DEJA_PRIS,
  user_already_exists: "Cette adresse est déjà utilisée. Connecte-toi plutôt.",
  weak_password: "Mot de passe trop faible : 8 caractères minimum.",
  signup_disabled: "Les inscriptions sont momentanément fermées.",
  email_address_invalid: "Cette adresse email n'est pas valide.",
  email_address_not_authorized: "Cette adresse email n'est pas autorisée.",

  // — Connexion —
  invalid_credentials: "Email ou mot de passe incorrect.",
  email_not_confirmed:
    "Confirme d'abord ton adresse : le lien t'a été envoyé par email.",
  user_banned: "Ce compte est suspendu.",
  user_not_found: "Aucun compte ne correspond à cette adresse.",

  // — Liens et codes à usage unique —
  otp_expired: "Ce lien a expiré. Demande-en un nouveau.",
  same_password: "Choisis un mot de passe différent de l'ancien.",
  reauthentication_needed: "Reconnecte-toi pour modifier ton mot de passe.",

  // — Fournisseurs externes —
  provider_disabled:
    "Cette méthode de connexion n'est pas encore activée. Utilise ton email.",
  validation_failed: "Certaines informations sont incomplètes ou invalides.",

  // — Limites —
  over_email_send_rate_limit:
    "Trop de demandes d'affilée. Patiente une minute avant de réessayer.",
  over_request_rate_limit:
    "Trop de tentatives d'affilée. Patiente une minute avant de réessayer.",
};

/** Reconnaissance de secours, sur le message anglais brut. */
const PAR_MESSAGE = [
  // Le trigger `on_auth_user_created` échoue quand le pseudo est déjà pris, ce
  // que GoTrue renvoie sous cette formule générique, sans le détail SQL. C'est
  // le filet de sécurité pour la course entre deux inscriptions simultanées :
  // le formulaire teste la disponibilité en amont, mais ne peut pas la
  // garantir jusqu'à l'insertion.
  //
  // Ce raccourci ne tient que parce que ce trigger est le seul posé sur
  // `auth.users`. En ajouter un autre obligerait à revoir ce message.
  [/database error saving new user/i, PSEUDO_DEJA_PRIS],
  [/duplicate key value|profils_pseudo_unique/i, PSEUDO_DEJA_PRIS],
  [/already registered|already been registered|already exists/i, PAR_CODE.email_exists],
  [/invalid login credentials/i, PAR_CODE.invalid_credentials],
  [/email not confirmed/i, PAR_CODE.email_not_confirmed],
  [/password should be at least|password is too short|weak password/i, PAR_CODE.weak_password],
  [/should be different from the old password/i, PAR_CODE.same_password],
  [/expired|invalid token|token has expired/i, PAR_CODE.otp_expired],
  [/provider is not enabled|unsupported provider/i, PAR_CODE.provider_disabled],
  [/rate limit|only request this after|too many requests/i, PAR_CODE.over_request_rate_limit],
  [/unable to validate email|invalid format/i, PAR_CODE.email_address_invalid],
  [
    /failed to fetch|network|load failed|timeout/i,
    "Connexion impossible. Vérifie ta connexion internet et réessaie.",
  ],
];

const REPLI =
  "Quelque chose n'a pas fonctionné. Réessaie dans quelques instants.";

/**
 * @param {unknown} erreur  erreur renvoyée par supabase-js (ou un throw réseau)
 * @returns {string} message français, toujours non vide, prêt à être affiché
 */
export function messageErreur(erreur) {
  if (!erreur) return REPLI;

  const code = typeof erreur.code === "string" ? erreur.code : "";
  if (PAR_CODE[code]) return PAR_CODE[code];

  const message = typeof erreur.message === "string" ? erreur.message : "";

  // supabase-js enveloppe les coupures réseau dans une erreur dédiée.
  if (erreur.name === "AuthRetryableFetchError" && !message) {
    return "Connexion impossible. Vérifie ta connexion internet et réessaie.";
  }

  for (const [motif, traduction] of PAR_MESSAGE) {
    if (motif.test(message)) return traduction;
  }

  return REPLI;
}

/* ==========================================================================
   Étape 9 — les trois cas d'échec des écrans de données
   ==========================================================================

   L'authentification n'est plus le seul chemin qui échoue. Chaque écran lit des
   données, et trois situations doivent être dites différemment parce qu'elles
   n'appellent pas le même geste :

   - **Réseau / réveil de Railway** — le plan gratuit met le service en veille
     (note technique de la section 9 du CLAUDE.md). Ce n'est pas une panne :
     c'est une attente. Le message le dit, et le bouton relance l'appel.
   - **Supabase** — la base a répondu autre chose que ce qu'on attendait.
     Réessayer a du sens, le message reste sobre.
   - **Données manquantes** — aucune cote, championnat vide, aucun Grand Prix.
     Ce n'est pas une erreur du tout : chaque écran écrit son propre message,
     et il n'y a rien à réessayer.

   Les genres voyagent avec le résultat des chargeurs (`lib/api.js`,
   `lib/pronostics.js`, `lib/profils.js`, `lib/championnats.js`) plutôt que
   d'être devinés d'après le texte du message : deviner à partir d'une chaîne
   déjà traduite en français ferait dépendre le comportement de la formulation. */

export const GENRE_RESEAU = "reseau";
export const GENRE_SUPABASE = "supabase";
export const GENRE_SESSION = "session";
export const GENRE_SERVEUR = "serveur";
// Ce qui est demandé n'existe pas : championnat effacé, Grand Prix inconnu.
// Réessayer ne changera rien, et l'écran doit proposer une sortie plutôt qu'un
// bouton qui rejoue le même refus.
export const GENRE_DONNEES = "donnees";

const PAR_GENRE = {
  [GENRE_RESEAU]:
    "Connexion au serveur en cours… Réessaie dans quelques secondes.",
  [GENRE_SUPABASE]: "Une erreur est survenue. Réessaie.",
  [GENRE_SERVEUR]: "Une erreur est survenue. Réessaie.",
  [GENRE_SESSION]: "Session expirée. Reconnecte-toi.",
  [GENRE_DONNEES]: "Ce contenu n'existe pas ou n'est plus accessible.",
};

/**
 * Le message à afficher pour un échec de chargement.
 *
 * Le genre l'emporte sur le message reçu pour les deux cas où le texte du
 * serveur n'aide personne : une coupure réseau et une panne Supabase. Pour tout
 * le reste, le message du serveur est déjà en français et plus précis que le
 * générique (« Tu ne fais pas partie de ce championnat », « Ce Grand Prix
 * n'existe pas ») : il est conservé.
 *
 * @param {{genre?: string, message?: string}|string|null} echec
 */
export function messageDeChargement(echec) {
  if (!echec) return PAR_GENRE[GENRE_SERVEUR];

  if (typeof echec === "string") return echec;

  const { genre, message } = echec;
  if (genre === GENRE_RESEAU || genre === GENRE_SUPABASE) return PAR_GENRE[genre];
  if (message) return message;
  return PAR_GENRE[genre] ?? PAR_GENRE[GENRE_SERVEUR];
}

/**
 * Vrai si l'échec vaut la peine d'être retenté.
 *
 * Deux genres ne se réparent pas en réessayant, et le bouton disparaît pour
 * eux : une **session expirée** rejouerait le même jeton mort en boucle (le
 * garde-fou de `RouteProtegee` fait le reste), et une **donnée absente** ne
 * réapparaîtra pas parce qu'on redemande.
 */
export function estRejouable(echec) {
  if (typeof echec !== "object" || echec === null) return true;
  return echec.genre !== GENRE_SESSION && echec.genre !== GENRE_DONNEES;
}

/**
 * Détecte le cas « email déjà inscrit » que Supabase ne signale pas comme une
 * erreur. Quand la confirmation par email est active — le réglage par défaut —
 * une inscription sur une adresse existante réussit en apparence et renvoie un
 * utilisateur factice sans identité, précisément pour ne pas révéler qui est
 * inscrit. Sans ce test, l'utilisateur attendrait un email qui n'arrivera
 * jamais.
 */
export function emailDejaInscrit(donnees) {
  const utilisateur = donnees?.user;
  return Boolean(
    utilisateur &&
      Array.isArray(utilisateur.identities) &&
      utilisateur.identities.length === 0,
  );
}
