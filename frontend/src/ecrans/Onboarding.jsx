import { useState } from "react";
import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import Champ from "../composants/Champ.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { PSEUDO_DEJA_PRIS } from "../lib/erreurs.js";
import { validerPseudo } from "../lib/validation.js";

/**
 * Écran d'onboarding — un premier compte Google (ou Apple, une fois activé)
 * n'a transmis aucun pseudo ; `gerer_nouvel_utilisateur` en a fabriqué un
 * provisoire (`pilote-xxxxxxxxxx`, `docs/database.md`). Cet écran le remplace
 * avant de laisser entrer dans le reste de l'application — `RouteProtegee` y
 * redirige tant que `pseudoAConfigurer` vaut vrai.
 *
 * **Pas de bouton retour** : il n'y a nulle part d'utile où revenir tant que
 * le pseudo n'est pas choisi, un retour ramènerait ici aussitôt. La seule
 * sortie est `deconnecter`, offerte en pied de page comme sur Mon Profil.
 */
export default function Onboarding() {
  const { definirPseudo, deconnecter } = useAuth();
  const naviguer = useNavigate();

  const [pseudo, setPseudo] = useState("");
  const [erreurChamp, setErreurChamp] = useState(null);
  const [alerte, setAlerte] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  const [tentative, setTentative] = useState(0);

  function changer(evenement) {
    setPseudo(evenement.target.value);
    setErreurChamp(null);
    setAlerte(null);
  }

  async function soumettre(evenement) {
    evenement.preventDefault();
    setTentative((n) => n + 1);

    const valeur = pseudo.trim();
    const controle = validerPseudo(valeur);
    if (controle) {
      setErreurChamp(controle);
      setAlerte(null);
      return;
    }

    setEnvoi(true);
    setAlerte(null);
    const resultat = await definirPseudo(valeur);
    setEnvoi(false);

    if (!resultat.ok) {
      // Le doublon — quelqu'un d'autre a pris ce pseudo entre-temps — se pose
      // sous le champ pour désigner ce qu'il faut corriger ; tout le reste
      // (session expirée, panne) va dans le bandeau global.
      if (resultat.message === PSEUDO_DEJA_PRIS) {
        setErreurChamp(PSEUDO_DEJA_PRIS);
        return;
      }
      setAlerte({ ton: "erreur", texte: resultat.message });
      return;
    }

    naviguer("/accueil", { replace: true });
  }

  async function seDeconnecter() {
    const resultat = await deconnecter();
    if (resultat.ok) naviguer("/", { replace: true });
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1} className="pt-1 pb-2">
        <h1 className="text-titre-lg text-texte mt-3.5">Choisis ton pseudo</h1>
        <p className="text-texte-doux mt-1 text-[13px]">
          Il te reste une chose à faire : c'est lui que tes amis verront dans
          les championnats et les classements.
        </p>
      </Bloc>

      <form onSubmit={soumettre} className="flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface shadow-bloc p-4.5">
          <Champ
            label="Pseudo"
            name="pseudo"
            type="text"
            autoComplete="nickname"
            autoCapitalize="none"
            placeholder="MaxV33"
            maxLength={20}
            value={pseudo}
            onChange={changer}
            erreur={erreurChamp}
            tentative={tentative}
          />
        </Bloc>

        {alerte && (
          <Alerte ton={alerte.ton} tentative={tentative}>
            {alerte.texte}
          </Alerte>
        )}

        <Bloc rang={3}>
          <Bouton
            type="submit"
            variante="principal"
            occupe={envoi}
            libelleOccupe="Enregistrement…"
          >
            Continuer
          </Bouton>
        </Bloc>
      </form>

      <footer className="flex flex-1 flex-col items-center justify-end gap-3 pt-5">
        <button
          type="button"
          onClick={seDeconnecter}
          className="text-texte-doux min-h-tactile pressable -my-2 px-3 py-2 text-[13px] font-medium"
        >
          Se déconnecter
        </button>
      </footer>
    </Ecran>
  );
}
