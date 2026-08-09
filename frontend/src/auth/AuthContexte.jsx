import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { supabase, supabaseConfigure, urlDeRetour } from "../lib/supabase.js";
import { emailDejaInscrit, messageErreur } from "../lib/erreurs.js";

const AuthContexte = createContext(null);

const CONFIG_MANQUANTE =
  "L'application n'est pas reliée à son serveur d'authentification. " +
  "Les variables VITE_SUPABASE_URL et VITE_SUPABASE_ANON_KEY sont absentes.";

/** Toutes les méthodes renvoient cette forme : jamais d'exception, jamais de console. */
const echec = (message) => ({ ok: false, message });
const succes = (extra = {}) => ({ ok: true, message: null, ...extra });

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  // Tant que la session initiale n'est pas résolue, on ne sait pas si
  // l'utilisateur est connecté : rediriger maintenant ferait clignoter l'écran
  // de connexion devant quelqu'un qui a déjà une session valide.
  const [chargement, setChargement] = useState(supabaseConfigure);
  // Passe à vrai quand l'utilisateur arrive par un lien de réinitialisation.
  const [recuperation, setRecuperation] = useState(false);

  useEffect(() => {
    if (!supabase) return undefined;

    let actif = true;

    supabase.auth
      .getSession()
      .then(({ data }) => {
        if (!actif) return;
        setSession(data.session ?? null);
        setChargement(false);
      })
      .catch(() => {
        // Réseau coupé au démarrage : on considère l'utilisateur déconnecté
        // plutôt que de bloquer l'app sur un écran de chargement infini.
        if (!actif) return;
        setSession(null);
        setChargement(false);
      });

    const { data: abonnement } = supabase.auth.onAuthStateChange(
      (evenement, sessionCourante) => {
        setSession(sessionCourante ?? null);
        setChargement(false);
        if (evenement === "PASSWORD_RECOVERY") setRecuperation(true);
      },
    );

    return () => {
      actif = false;
      abonnement.subscription.unsubscribe();
    };
  }, []);

  const inscrire = useCallback(async ({ pseudo, email, motDePasse }) => {
    if (!supabase) return echec(CONFIG_MANQUANTE);
    try {
      const { data, error } = await supabase.auth.signUp({
        email,
        password: motDePasse,
        // Le pseudo part dans les métadonnées de l'utilisateur : il sera repris
        // par la table `profils` à l'étape 3.
        options: { data: { pseudo }, emailRedirectTo: urlDeRetour("/accueil") },
      });
      if (error) return echec(messageErreur(error));
      if (emailDejaInscrit(data)) {
        return echec("Cette adresse est déjà utilisée. Connecte-toi plutôt.");
      }
      // Sans session, c'est que la confirmation par email est active côté
      // Supabase : l'écran doit inviter à aller relever sa boîte mail.
      return succes({ confirmationRequise: !data.session });
    } catch (erreur) {
      return echec(messageErreur(erreur));
    }
  }, []);

  const connecter = useCallback(async ({ email, motDePasse }) => {
    if (!supabase) return echec(CONFIG_MANQUANTE);
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password: motDePasse,
      });
      if (error) return echec(messageErreur(error));
      return succes();
    } catch (erreur) {
      return echec(messageErreur(erreur));
    }
  }, []);

  /** `fournisseur` vaut "google" ou "apple". */
  const connecterAvec = useCallback(async (fournisseur) => {
    if (!supabase) return echec(CONFIG_MANQUANTE);
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: fournisseur,
        options: { redirectTo: urlDeRetour("/accueil") },
      });
      // Tant que les clés OAuth ne sont pas renseignées dans le tableau de bord
      // Supabase, l'appel échoue proprement ici : le message reste lisible au
      // lieu de laisser un bouton mort.
      if (error) return echec(messageErreur(error));
      return succes();
    } catch (erreur) {
      return echec(messageErreur(erreur));
    }
  }, []);

  const envoyerLienReinitialisation = useCallback(async (email) => {
    if (!supabase) return echec(CONFIG_MANQUANTE);
    try {
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: urlDeRetour("/nouveau-mot-de-passe"),
      });
      if (error) return echec(messageErreur(error));
      return succes();
    } catch (erreur) {
      return echec(messageErreur(erreur));
    }
  }, []);

  const definirMotDePasse = useCallback(async (motDePasse) => {
    if (!supabase) return echec(CONFIG_MANQUANTE);
    try {
      const { error } = await supabase.auth.updateUser({ password: motDePasse });
      if (error) return echec(messageErreur(error));
      setRecuperation(false);
      return succes();
    } catch (erreur) {
      return echec(messageErreur(erreur));
    }
  }, []);

  const deconnecter = useCallback(async () => {
    if (!supabase) return echec(CONFIG_MANQUANTE);
    try {
      const { error } = await supabase.auth.signOut();
      if (error) return echec(messageErreur(error));
      return succes();
    } catch (erreur) {
      return echec(messageErreur(erreur));
    }
  }, []);

  const valeur = useMemo(() => {
    const utilisateur = session?.user ?? null;
    return {
      session,
      utilisateur,
      // Le pseudo saisi à l'inscription ; Google et Apple ne le fournissent pas,
      // on retombe alors sur le nom du compte puis sur la partie locale de l'email.
      pseudo:
        utilisateur?.user_metadata?.pseudo ||
        utilisateur?.user_metadata?.full_name ||
        utilisateur?.email?.split("@")[0] ||
        "",
      connecte: Boolean(session),
      chargement,
      recuperation,
      configure: supabaseConfigure,
      erreurConfiguration: supabaseConfigure ? null : CONFIG_MANQUANTE,
      inscrire,
      connecter,
      connecterAvec,
      envoyerLienReinitialisation,
      definirMotDePasse,
      deconnecter,
    };
  }, [
    session,
    chargement,
    recuperation,
    inscrire,
    connecter,
    connecterAvec,
    envoyerLienReinitialisation,
    definirMotDePasse,
    deconnecter,
  ]);

  return <AuthContexte value={valeur}>{children}</AuthContexte>;
}

export function useAuth() {
  const contexte = useContext(AuthContexte);
  if (!contexte) {
    throw new Error("useAuth doit être utilisé à l'intérieur d'un AuthProvider.");
  }
  return contexte;
}
