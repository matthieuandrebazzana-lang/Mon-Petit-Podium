import { useState } from "react";
import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Champ from "../composants/Champ.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { validerMotDePasse } from "../lib/validation.js";

/**
 * Écran d'arrivée du lien de réinitialisation.
 *
 * Supabase ouvre une session dès l'ouverture du lien. Cette session ne donne
 * pas accès à l'app : `RouteProtegee` renvoie ici tant que le nouveau mot de
 * passe n'est pas choisi.
 *
 * Le lien s'échange contre une session grâce à un vérificateur stocké dans le
 * navigateur qui a fait la demande (flux PKCE). Ouvrir l'email sur un autre
 * appareil échoue donc, avec un message explicite.
 */
export default function NouveauMotDePasse() {
  const { definirMotDePasse, connecte } = useAuth();
  const naviguer = useNavigate();

  const [valeurs, setValeurs] = useState({ motDePasse: "", confirmation: "" });
  const [erreursChamps, setErreursChamps] = useState({});
  const [alerte, setAlerte] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  const [tentative, setTentative] = useState(0);

  function changer(nom) {
    return (evenement) => {
      setValeurs((precedent) => ({
        ...precedent,
        [nom]: evenement.target.value,
      }));
      setErreursChamps((precedent) =>
        precedent[nom] ? { ...precedent, [nom]: null } : precedent,
      );
      setAlerte(null);
    };
  }

  async function soumettre(evenement) {
    evenement.preventDefault();
    setTentative((n) => n + 1);

    const controles = {
      motDePasse: validerMotDePasse(valeurs.motDePasse),
      confirmation:
        valeurs.confirmation === valeurs.motDePasse
          ? null
          : "Les deux mots de passe ne correspondent pas.",
    };
    setErreursChamps(controles);
    if (Object.values(controles).some(Boolean)) {
      setAlerte(null);
      return;
    }

    if (!connecte) {
      setAlerte({
        ton: "erreur",
        texte:
          "Ce lien n'est plus valide. Ouvre-le depuis le navigateur qui a fait la demande, ou demandes-en un nouveau.",
      });
      return;
    }

    setEnvoi(true);
    setAlerte(null);
    const resultat = await definirMotDePasse(valeurs.motDePasse);

    if (!resultat.ok) {
      setEnvoi(false);
      setAlerte({ ton: "erreur", texte: resultat.message });
      return;
    }

    naviguer("/accueil", { replace: true });
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Nouveau mot de passe" retourVers="/connexion" />
      </Bloc>

      <form onSubmit={soumettre} className="flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface p-4.5">
          <div className="flex flex-col gap-3.5">
            <Champ
              label="Nouveau mot de passe"
              name="motDePasse"
              type="password"
              autoComplete="new-password"
              placeholder="8 caractères minimum"
              value={valeurs.motDePasse}
              onChange={changer("motDePasse")}
              erreur={erreursChamps.motDePasse}
              tentative={tentative}
            />
            <Champ
              label="Confirmation"
              name="confirmation"
              type="password"
              autoComplete="new-password"
              placeholder="••••••••"
              value={valeurs.confirmation}
              onChange={changer("confirmation")}
              erreur={erreursChamps.confirmation}
              tentative={tentative}
            />
          </div>
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
            Enregistrer
          </Bouton>
        </Bloc>
      </form>
    </Ecran>
  );
}
