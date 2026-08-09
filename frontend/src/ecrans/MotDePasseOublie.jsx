import { useState } from "react";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Champ from "../composants/Champ.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { validerEmail } from "../lib/validation.js";

/**
 * Demande d'un lien de réinitialisation.
 *
 * Le message de confirmation ne dit jamais si l'adresse est connue : le faire
 * permettrait à n'importe qui de tester des adresses pour savoir qui est
 * inscrit. L'app étant ouverte au public, ce détail compte.
 */
export default function MotDePasseOublie() {
  const { envoyerLienReinitialisation } = useAuth();

  const [email, setEmail] = useState("");
  const [erreurChamp, setErreurChamp] = useState(null);
  const [alerte, setAlerte] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  const [tentative, setTentative] = useState(0);

  async function soumettre(evenement) {
    evenement.preventDefault();
    setTentative((n) => n + 1);

    const controle = validerEmail(email);
    setErreurChamp(controle);
    if (controle) {
      setAlerte(null);
      return;
    }

    setEnvoi(true);
    setAlerte(null);
    const resultat = await envoyerLienReinitialisation(email.trim());
    setEnvoi(false);

    setAlerte(
      resultat.ok
        ? {
            ton: "succes",
            texte:
              "Si un compte existe pour cette adresse, un lien de réinitialisation vient d'être envoyé.",
          }
        : { ton: "erreur", texte: resultat.message },
    );
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Mot de passe oublié" retourVers="/connexion" />
      </Bloc>

      <form onSubmit={soumettre} className="flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface p-4.5">
          <p className="text-corps-sm text-texte-doux mb-3.5">
            Entre l'adresse de ton compte. Tu recevras un lien pour choisir un
            nouveau mot de passe.
          </p>
          <Champ
            label="Email"
            name="email"
            type="email"
            inputMode="email"
            autoComplete="email"
            autoCapitalize="none"
            autoCorrect="off"
            placeholder="ton@email.com"
            value={email}
            onChange={(evenement) => {
              setEmail(evenement.target.value);
              setErreurChamp(null);
              setAlerte(null);
            }}
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
            libelleOccupe="Envoi…"
          >
            Envoyer le lien
          </Bouton>
        </Bloc>
      </form>
    </Ecran>
  );
}
