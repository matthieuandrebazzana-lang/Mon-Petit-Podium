import { Navigate, Outlet, useLocation } from "react-router-dom";
import { useAuth } from "../auth/AuthContexte.jsx";
import Chargement from "./Chargement.jsx";

/**
 * Route réservée aux membres connectés.
 *
 * Tant que la session initiale n'est pas résolue on affiche l'attente : rediriger
 * pendant ce laps de temps ferait passer un utilisateur déjà connecté par un
 * aller-retour visible sur l'écran de connexion à chaque lancement de l'app.
 *
 * `state` mémorise l'écran demandé pour y revenir après la connexion, et
 * `replace` évite d'empiler la redirection dans l'historique — sinon le geste
 * de retour ramènerait sur la page protégée.
 */
export function RouteProtegee() {
  const { connecte, chargement, recuperation } = useAuth();
  const emplacement = useLocation();

  if (chargement) return <Chargement />;

  // Une session ouverte par un lien de réinitialisation ne donne pas accès à
  // l'app : elle ne sert qu'à choisir un nouveau mot de passe.
  if (recuperation) return <Navigate to="/nouveau-mot-de-passe" replace />;

  if (!connecte) {
    return <Navigate to="/connexion" replace state={{ depuis: emplacement }} />;
  }

  return <Outlet />;
}

/**
 * Route d'accueil public : landing, inscription, connexion.
 * Un membre déjà connecté n'a rien à y faire, on l'envoie sur son accueil.
 */
export function RoutePublique() {
  const { connecte, chargement, recuperation } = useAuth();

  if (chargement) return <Chargement />;
  if (recuperation) return <Navigate to="/nouveau-mot-de-passe" replace />;
  if (connecte) return <Navigate to="/accueil" replace />;

  return <Outlet />;
}
