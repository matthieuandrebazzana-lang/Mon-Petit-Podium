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

const PAR_CODE = {
  // — Inscription —
  email_exists: "Cette adresse est déjà utilisée. Connecte-toi plutôt.",
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
