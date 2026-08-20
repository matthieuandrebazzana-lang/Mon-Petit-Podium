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
import { chargerEstAdmin } from "../lib/profils.js";

/**
 * Exporté nommément depuis l'étape 9, pour la même raison que `BlocProchainGp`
 * à la version 0.5.1 : rendre un écran hors navigateur (`react-dom/server`)
 * imposerait sinon de monter `AuthProvider`, dont la session ne se résout que
 * dans un effet — jamais exécuté en rendu serveur. L'application, elle, passe
 * toujours par `useAuth`.
 */
export const AuthContexte = createContext(null);

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
  // Drapeau d'administration, relu **en base** à chaque changement de compte.
  const [estAdmin, setEstAdmin] = useState(false);
  /**
   * Mode admin — l'interrupteur de la section « Administration » du profil.
   *
   * **État de session, jamais persisté**, et les trois conséquences se
   * tiennent :
   *
   * 1. **Il repart éteint à chaque rechargement.** Un administrateur voit donc
   *    l'application telle que la voient les autres tant qu'il n'a rien
   *    allumé — c'est exactement ce qu'on veut d'un mode de vérification, qui
   *    doit demander un geste explicite plutôt que d'être l'état par défaut de
   *    quelqu'un.
   * 2. **Ni base, ni `localStorage`, ni jeton.** Persister ce drapeau lui
   *    donnerait les défauts déjà documentés sur `pseudo` et sur `is_admin` :
   *    une valeur qui survit à ce qu'elle décrit. Ici il n'y a rien à faire
   *    survivre — c'est une préférence d'affichage valable le temps qu'on
   *    regarde.
   * 3. **Il est remis à zéro au changement de compte**, avec `estAdmin` et dans
   *    le même effet : deux personnes qui se relaient sur le même téléphone ne
   *    doivent hériter ni du droit de l'autre, ni de son mode.
   */
  const [modeAdminActif, setModeAdminActif] = useState(false);

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

  const compte = session?.user?.id ?? null;

  /**
   * Lecture du drapeau d'administration, **jamais depuis un cache**.
   *
   * Trois décisions, et aucune n'est arbitraire :
   *
   * 1. **Ici et non dans un écran.** C'est le « store global » de la demande :
   *    le projet n'a pas de Zustand, et ce contexte est déjà le seul endroit
   *    qui sait qui est connecté. Un droit lu dans chaque écran qui l'affiche
   *    finirait par être lu de deux façons différentes.
   *
   * 2. **En base, jamais dans le jeton ni dans `localStorage`.** Le jeton porte
   *    une copie figée à l'inscription — c'est tout le piège documenté sur
   *    `pseudo` juste plus bas, et il serait bien pire sur un drapeau
   *    d'administration : une révocation ne prendrait effet qu'au prochain
   *    renouvellement de session. Le cache *stale-while-revalidate* a le même
   *    défaut, en plus modifiable depuis les outils de développement.
   *
   * 3. **Le doute referme, il n'ouvre jamais.** Base non migrée, ligne absente,
   *    réseau coupé, session en cours de résolution : tous ces cas laissent
   *    `false`. C'est l'inverse du sens du doute appliqué au pseudo, où une
   *    valeur périmée vaut mieux que rien — une section d'administration
   *    affichée à tort ne vaut rien.
   *
   * La lecture est relancée à chaque changement de compte et remise à `false`
   * **avant** de repartir : deux personnes qui se relaient sur le même
   * téléphone ne doivent jamais hériter du drapeau de l'autre, fût-ce une
   * image (règle posée à l'étape 3 pour les clés de cache, et qui vaut aussi
   * sans cache).
   */
  useEffect(() => {
    setEstAdmin(false);
    // Le mode retombe avec le droit : sans cela, un administrateur qui se
    // déconnecte laisserait son mode allumé au compte suivant, qui le
    // retrouverait actif à la seconde où son propre `is_admin` reviendrait vrai.
    setModeAdminActif(false);
    if (!compte) return undefined;

    const controleur = new AbortController();
    let actif = true;

    (async () => {
      try {
        const resultat = await chargerEstAdmin(compte, controleur.signal);
        if (actif && resultat.ok) setEstAdmin(resultat.donnees === true);
      } catch {
        /* Abandon au démontage, ou panne réseau : on reste non administrateur. */
      }
    })();

    return () => {
      actif = false;
      controleur.abort();
    };
  }, [compte]);

  /**
   * Teste la disponibilité d'un pseudo avant l'inscription, via la fonction
   * `pseudo_disponible` de la base. Sans ce test, le doublon ne serait détecté
   * qu'à l'insertion, donc après que l'utilisateur a saisi son mot de passe.
   *
   * En cas d'échec de l'appel — migration pas encore appliquée, réseau coupé —
   * on répond « disponible » et l'inscription continue. Bloquer tout le monde
   * parce qu'une vérification de confort ne répond pas serait disproportionné :
   * la garantie réelle est l'index unique en base, pas ce test.
   */
  const pseudoDisponible = useCallback(async (pseudo) => {
    if (!supabase) return { verifie: false, disponible: true };
    try {
      const { data, error } = await supabase.rpc("pseudo_disponible", {
        pseudo_a_tester: pseudo,
      });
      if (error) return { verifie: false, disponible: true };
      return { verifie: true, disponible: data !== false };
    } catch {
      return { verifie: false, disponible: true };
    }
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
      const { error } = await supabase.auth.updateUser({
        password: motDePasse,
      });
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
      //
      // **C'est une copie figée dans le jeton, pas la valeur en base.** Elle est
      // écrite à l'inscription et ne bouge plus : renommer quelqu'un dans
      // `public.profils` — à la main, ou par tout chemin qui ne repasse pas par
      // `auth.updateUser` — ne la met pas à jour, et elle reste périmée aussi
      // longtemps que la session vit. Tout écran qui **affiche** le pseudo doit
      // donc passer par `usePseudoCourant` (`lib/usePseudo.js`), qui relit la
      // table ; celui-ci ne sert plus que de repli le temps de cette lecture.
      pseudo:
        utilisateur?.user_metadata?.pseudo ||
        utilisateur?.user_metadata?.full_name ||
        utilisateur?.email?.split("@")[0] ||
        "",
      connecte: Boolean(session),
      // Gouverne **l'affichage** de la section d'administration du profil, et
      // rien d'autre : ce n'est pas un droit, le seul garde des routes
      // d'administration est le secret `X-Admin-Secret` vérifié côté backend.
      //
      // **`estAdmin` ne se lit plus qu'à un seul endroit** — la section du
      // profil, qui reste visible quel que soit l'interrupteur, puisque c'est
      // de là qu'on le rallume. Partout ailleurs, c'est `modeAdmin` qu'il faut
      // lire, jamais `estAdmin`.
      estAdmin,
      // L'interrupteur nu, pour la section qui le porte et lui seule.
      modeAdminActif,
      setModeAdminActif,
      /**
       * **Le drapeau que toute autre surface doit lire.**
       *
       * C'est la conjonction `estAdmin && modeAdminActif`, nommée une fois
       * plutôt que réécrite à chaque point d'usage. La raison est mécanique :
       * une conjonction qu'on recopie finit par être écrite à moitié, et la
       * moitié qui saute est toujours la même — le mode, parce qu'il est le
       * terme récent. On obtiendrait alors une surface qui reste visible
       * interrupteur éteint, c'est-à-dire le défaut même que ce mode existe
       * pour supprimer. Ici il n'y a rien à recopier.
       *
       * Il vaut `false` pour tout le monde sauf un administrateur qui a allumé
       * son interrupteur dans la session courante.
       */
      modeAdmin: estAdmin && modeAdminActif,
      chargement,
      recuperation,
      configure: supabaseConfigure,
      erreurConfiguration: supabaseConfigure ? null : CONFIG_MANQUANTE,
      pseudoDisponible,
      inscrire,
      connecter,
      connecterAvec,
      envoyerLienReinitialisation,
      definirMotDePasse,
      deconnecter,
    };
  }, [
    session,
    estAdmin,
    modeAdminActif,
    chargement,
    recuperation,
    pseudoDisponible,
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
    throw new Error(
      "useAuth doit être utilisé à l'intérieur d'un AuthProvider.",
    );
  }
  return contexte;
}
