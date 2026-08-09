/**
 * Contrôles de saisie effectués avant tout appel réseau.
 *
 * Ils ne remplacent pas les règles du serveur — Supabase revalide tout — mais
 * ils évitent un aller-retour pour une faute évidente et donnent un message
 * précis, attaché au bon champ, plutôt qu'une erreur globale traduite.
 *
 * Chaque fonction renvoie `null` si la valeur convient, sinon le message à
 * afficher sous le champ.
 */

export const LONGUEUR_MOT_DE_PASSE = 8;

export function validerPseudo(valeur) {
  const pseudo = valeur.trim();
  if (!pseudo) return "Choisis un pseudo.";
  if (pseudo.length < 2) return "Ton pseudo doit faire au moins 2 caractères.";
  if (pseudo.length > 20) return "Ton pseudo ne peut pas dépasser 20 caractères.";
  return null;
}

export function validerEmail(valeur) {
  const email = valeur.trim();
  if (!email) return "Entre ton adresse email.";
  // Volontairement permissif : le seul test fiable d'une adresse est l'email
  // de confirmation. On n'attrape ici que les fautes de frappe manifestes.
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return "Cette adresse email ne semble pas valide.";
  }
  return null;
}

export function validerMotDePasse(valeur) {
  if (!valeur) return "Entre un mot de passe.";
  if (valeur.length < LONGUEUR_MOT_DE_PASSE) {
    return `Ton mot de passe doit faire au moins ${LONGUEUR_MOT_DE_PASSE} caractères.`;
  }
  return null;
}

/** Sur l'écran de connexion, la longueur ne se contrôle pas : elle date d'avant. */
export function validerMotDePasseRequis(valeur) {
  return valeur ? null : "Entre ton mot de passe.";
}
