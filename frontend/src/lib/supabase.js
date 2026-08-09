import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const cleAnonyme = import.meta.env.VITE_SUPABASE_ANON_KEY;

/**
 * Vrai uniquement si les deux variables d'environnement sont présentes.
 * Sans elles, `createClient` lève une exception au chargement du module et
 * l'app entière affiche une page blanche — un écran noir muet est le pire
 * échec possible sur mobile. On préfère un client absent et un message lisible
 * dans l'interface (voir `AuthContexte`).
 */
export const supabaseConfigure = Boolean(url && cleAnonyme);

export const supabase = supabaseConfigure
  ? createClient(url, cleAnonyme, {
      auth: {
        // Persistance de la session entre les visites : le jeton est écrit en
        // localStorage et rechargé au démarrage. C'est ce qui permet à la PWA
        // installée de rouvrir directement sur l'accueil.
        persistSession: true,
        autoRefreshToken: true,
        // Indispensable pour Google, Apple et les liens de réinitialisation :
        // le jeton revient dans l'URL de redirection et doit être consommé.
        detectSessionInUrl: true,
        flowType: "pkce",
      },
    })
  : null;

/** URL de retour après un aller-retour OAuth ou un lien envoyé par email. */
export function urlDeRetour(chemin = "/") {
  return new URL(chemin, window.location.origin).toString();
}
