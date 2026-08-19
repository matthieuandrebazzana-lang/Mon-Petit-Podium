import { useEffect, useState } from "react";
import { chargerPseudo } from "./profils.js";

/**
 * Le pseudo courant du compte connecté, relu **en base à chaque montage**.
 *
 * Le défaut qu'il corrige : `useAuth().pseudo` ne lit pas `public.profils`, il
 * lit `user_metadata.pseudo` — une copie figée dans le jeton à l'inscription.
 * Renommer quelqu'un directement en base ne touche pas cette copie, et
 * l'accueil affichait donc « Salut <ancien pseudo> » aussi longtemps que la
 * session vivait. Le jeton ne peut pas savoir : seule la table le sait.
 *
 * **Trois décisions, et aucune n'est arbitraire :**
 *
 * 1. **Aucun cache.** Ce chargeur ne passe volontairement pas par `useDonnees`,
 *    qui mémorise en `localStorage` en *stale-while-revalidate*. Ce cache est
 *    exactement le bon outil pour la liste des championnats — il fait tenir
 *    l'accueil pendant le réveil de Railway — et exactement le mauvais ici :
 *    il réintroduirait au montage suivant la valeur périmée qu'on vient de
 *    corriger. Un pseudo est un mot ; le relire coûte une requête indexée sur
 *    clé primaire.
 *
 * 2. **À chaque montage, et non une fois par session.** Poser la lecture dans
 *    `AuthProvider` la ferait tourner une seule fois, au moment où la session
 *    se résout : un pseudo changé en cours de session resterait périmé jusqu'au
 *    prochain rafraîchissement du jeton. Le montage de l'accueil est le bon
 *    déclencheur — c'est l'écran où le pseudo s'affiche, et on y revient à
 *    chaque passage par l'onglet.
 *
 * 3. **Repli sur le jeton, jamais sur le vide.** Pendant la lecture et si elle
 *    échoue, c'est `replier` qui est rendu. Un pseudo légèrement périmé vaut
 *    mieux qu'un « Salut  » vide ou qu'un titre qui clignote de
 *    « Greed F1 » vers « Salut X » à chaque arrivée. C'est le bon sens
 *    du doute, celui déjà appliqué au bloc du prochain Grand Prix depuis la
 *    version `0.5.1` : l'échec d'une lecture de confort ne casse pas l'écran.
 *
 * @param {string|null} profilId  l'identifiant du compte connecté
 * @param {string}      replier   le pseudo du jeton, servi tant que la base n'a rien dit
 */
export function usePseudoCourant(profilId, replier = "") {
  const [pseudo, setPseudo] = useState(null);

  useEffect(() => {
    // Le compte a changé : la valeur de l'ancien ne doit pas survivre une seule
    // image à l'écran. Deux personnes qui se relaient sur le même téléphone ne
    // doivent jamais lire le pseudo de l'autre — c'est la règle posée à
    // l'étape 3 pour les clés de cache, et elle vaut aussi sans cache.
    setPseudo(null);

    if (!profilId) return undefined;

    const controleur = new AbortController();
    let actif = true;

    (async () => {
      try {
        const resultat = await chargerPseudo(profilId, controleur.signal);
        // Un profil sans ligne rend `donnees: null` sans être une erreur : on
        // reste alors sur le repli plutôt que d'effacer le titre.
        if (actif && resultat.ok && resultat.donnees) setPseudo(resultat.donnees);
      } catch {
        /* Abandon au démontage, ou panne réseau : le repli fait le travail. */
      }
    })();

    return () => {
      actif = false;
      controleur.abort();
    };
  }, [profilId]);

  return pseudo ?? replier;
}
