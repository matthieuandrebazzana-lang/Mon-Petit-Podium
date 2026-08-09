import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Champ from "../composants/Champ.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import BoutonsOAuth from "../composants/BoutonsOAuth.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { validerEmail, validerMotDePasseRequis } from "../lib/validation.js";

/** Maquette 03 — connexion. */
export default function Connexion() {
  const { connecter } = useAuth();
  const naviguer = useNavigate();
  const emplacement = useLocation();

  const [valeurs, setValeurs] = useState({ email: "", motDePasse: "" });
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
      email: validerEmail(valeurs.email),
      motDePasse: validerMotDePasseRequis(valeurs.motDePasse),
    };
    setErreursChamps(controles);
    if (Object.values(controles).some(Boolean)) {
      setAlerte(null);
      return;
    }

    setEnvoi(true);
    setAlerte(null);
    const resultat = await connecter({
      email: valeurs.email.trim(),
      motDePasse: valeurs.motDePasse,
    });

    if (!resultat.ok) {
      setEnvoi(false);
      setAlerte({ ton: "erreur", texte: resultat.message });
      return;
    }

    // Retour à l'écran demandé avant la redirection vers la connexion, s'il y
    // en avait un. `replace` retire la connexion de l'historique : le geste de
    // retour ne doit pas y ramener une fois connecté.
    const destination = emplacement.state?.depuis?.pathname ?? "/accueil";
    naviguer(destination, { replace: true });
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Bon retour !" retourVers="/" />
      </Bloc>

      <form onSubmit={soumettre} className="flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface p-4.5">
          <div className="flex flex-col gap-3.5">
            <Champ
              label="Email"
              name="email"
              type="email"
              inputMode="email"
              autoComplete="email"
              autoCapitalize="none"
              autoCorrect="off"
              placeholder="ton@email.com"
              value={valeurs.email}
              onChange={changer("email")}
              erreur={erreursChamps.email}
              tentative={tentative}
            />
            <div>
              <Champ
                label="Mot de passe"
                name="motDePasse"
                type="password"
                autoComplete="current-password"
                placeholder="••••••••"
                value={valeurs.motDePasse}
                onChange={changer("motDePasse")}
                erreur={erreursChamps.motDePasse}
                tentative={tentative}
              />
              <div className="flex justify-end">
                <Link
                  to="/mot-de-passe-oublie"
                  className="text-primaire min-h-tactile -my-2.5 flex items-center py-2.5 text-[12px] font-medium"
                >
                  Mot de passe oublié ?
                </Link>
              </div>
            </div>
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
            libelleOccupe="Connexion…"
          >
            Se connecter
          </Bouton>
        </Bloc>
      </form>

      <Bloc rang={4} className="mt-3">
        <div className="flex flex-col gap-3">
          <BoutonsOAuth
            onErreur={(message) =>
              setAlerte(message ? { ton: "erreur", texte: message } : null)
            }
          />

          <p className="text-texte-doux pt-1 text-center text-[13px]">
            Pas encore de compte ?{" "}
            <Link to="/inscription" className="text-primaire font-medium">
              S'inscrire
            </Link>
          </p>
        </div>
      </Bloc>
    </Ecran>
  );
}
