import { useCallback, useEffect, useRef, useState } from "react";
import { GENRE_SERVEUR, messageDeChargement } from "./erreurs.js";

/**
 * Chargement de données avec cache localStorage en *stale-while-revalidate*
 * (note technique de la section 9 du CLAUDE.md).
 *
 * Au lancement, l'app affiche immédiatement ce qu'elle savait la dernière fois,
 * puis remplace par la réponse fraîche. C'est ce qui rend l'accueil instantané
 * malgré le réveil de Railway, qui peut prendre plusieurs secondes sur le plan
 * gratuit.
 *
 * La clé de cache doit inclure l'identifiant de l'utilisateur : deux comptes
 * sur le même téléphone ne doivent jamais voir les championnats de l'autre,
 * fût-ce le temps d'un rafraîchissement.
 */

const PREFIXE = "mpp:";

function lireCache(cle) {
  if (!cle) return undefined;
  try {
    const brut = localStorage.getItem(PREFIXE + cle);
    return brut ? JSON.parse(brut) : undefined;
  } catch {
    // Mode privé Safari, quota plein, JSON corrompu : le cache est un confort,
    // son échec ne doit jamais empêcher le chargement réel.
    return undefined;
  }
}

function ecrireCache(cle, valeur) {
  if (!cle) return;
  try {
    localStorage.setItem(PREFIXE + cle, JSON.stringify(valeur));
  } catch {
    /* voir ci-dessus */
  }
}

export function oublierCache(cle) {
  try {
    localStorage.removeItem(PREFIXE + cle);
  } catch {
    /* voir ci-dessus */
  }
}

/**
 * Oublie toutes les clés commençant par un préfixe.
 *
 * Sert au profil (étape 8) : changer les couleurs de sa voiture périme le
 * classement de **tous** ses championnats d'un coup, et l'écran ne les connaît
 * pas — il faudrait relire la liste pour cela. Le préfixe interne du cache
 * reste privé à ce module : l'écrire en dur ailleurs le ferait diverger au
 * premier renommage.
 */
export function oublierCachePrefixe(prefixe) {
  try {
    const complet = PREFIXE + prefixe;
    for (const cle of Object.keys(localStorage)) {
      if (cle.startsWith(complet)) localStorage.removeItem(cle);
    }
  } catch {
    /* voir ci-dessus */
  }
}

/**
 * @param {string|null} cle      clé de cache, ou `null` pour ne rien mémoriser
 * @param {(signal: AbortSignal) => Promise<{ok: boolean, donnees?: unknown, message?: string}>} chargeur
 */
export function useDonnees(cle, chargeur) {
  const [donnees, setDonnees] = useState(() => lireCache(cle));
  // Pas d'écran d'attente si le cache a déjà quelque chose à montrer : la
  // requête tourne en fond et le contenu se met à jour tout seul.
  const [chargement, setChargement] = useState(() => lireCache(cle) === undefined);
  // `echec` porte le genre en plus du message (étape 9) : c'est lui qui décide
  // si l'écran propose « Réessayer » et sous quelle formulation. `erreur` reste
  // la chaîne seule, pour les écrans qui n'ont besoin que de l'afficher.
  const [echec, setEchec] = useState(null);

  const chargeurRef = useRef(chargeur);
  chargeurRef.current = chargeur;

  /**
   * Remplace les données ET le cache, en une fois.
   *
   * `setDonnees` seul ne touche que l'état React : le cache `localStorage`
   * garde alors la version d'avant, et c'est lui qui est relu au montage
   * suivant. C'est exactement le défaut qui faisait réapparaître l'ancienne
   * couleur de voiture en revenant sur le profil — l'enregistrement mettait
   * l'écran à jour, puis la navigation ressortait la valeur périmée.
   *
   * À utiliser après toute écriture dont la réponse fait foi. `setDonnees`
   * reste exporté pour les mises à jour optimistes que la réponse serveur
   * confirmera de toute façon (la bascule d'un favori, par exemple).
   */
  const remplacer = useCallback(
    (valeur) => {
      setDonnees(valeur);
      ecrireCache(cle, valeur);
    },
    [cle],
  );

  const [tour, setTour] = useState(0);
  const recharger = useCallback(() => {
    // L'attente doit repartir avec la tentative, sinon le squelette ne
    // réapparaît jamais et le bouton semble n'avoir rien déclenché.
    setChargement(true);
    setTour((n) => n + 1);
  }, []);

  useEffect(() => {
    const controleur = new AbortController();
    let actif = true;

    (async () => {
      try {
        const resultat = await chargeurRef.current(controleur.signal);
        if (!actif) return;

        if (resultat.ok) {
          setDonnees(resultat.donnees);
          setEchec(null);
          ecrireCache(cle, resultat.donnees);
        } else {
          setEchec(resultat);
        }
      } catch (erreurAttrapee) {
        if (erreurAttrapee.name === "AbortError") return;
        // Jusqu'à l'étape 9, une exception inattendue remettait l'erreur à
        // `null` : l'écran restait vide, sans squelette ni message, et rien ne
        // disait au joueur quoi faire. Elle est désormais rendue comme les
        // autres, avec son bouton « Réessayer ».
        if (actif) setEchec({ ok: false, genre: GENRE_SERVEUR, message: null });
      } finally {
        if (actif) setChargement(false);
      }
    })();

    return () => {
      actif = false;
      controleur.abort();
    };
  }, [cle, tour]);

  return {
    donnees,
    chargement,
    echec,
    erreur: echec ? messageDeChargement(echec) : null,
    recharger,
    setDonnees,
    remplacer,
  };
}
