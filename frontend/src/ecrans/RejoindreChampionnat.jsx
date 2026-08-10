import { useState } from "react";
import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import ChampCode, { LONGUEUR_CODE } from "../composants/ChampCode.jsx";
import { rejoindreChampionnat } from "../lib/championnats.js";
import { oublierCache } from "../lib/useDonnees.js";
import { useAuth } from "../auth/AuthContexte.jsx";

/** Maquette 06 — rejoindre un championnat avec son code. */
export default function RejoindreChampionnat() {
  const naviguer = useNavigate();
  const { utilisateur } = useAuth();

  const [code, setCode] = useState("");
  const [erreurCode, setErreurCode] = useState(null);
  const [alerte, setAlerte] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  const [tentative, setTentative] = useState(0);

  const complet = code.length === LONGUEUR_CODE;

  async function soumettre(evenement) {
    evenement.preventDefault();
    setTentative((n) => n + 1);

    if (!complet) {
      setErreurCode(`Un code d'invitation compte ${LONGUEUR_CODE} caractères.`);
      setAlerte(null);
      return;
    }

    setEnvoi(true);
    setErreurCode(null);
    setAlerte(null);

    const resultat = await rejoindreChampionnat(code);
    setEnvoi(false);

    if (!resultat.ok) {
      // Code inconnu : le reproche porte sur le champ, pas sur l'écran.
      // Toute autre erreur (réseau, déjà membre) reste un message global.
      if (resultat.statut === 404) setErreurCode(resultat.message);
      else setAlerte(resultat.message);
      return;
    }

    if (utilisateur) oublierCache(`championnats:${utilisateur.id}`);

    naviguer(`/championnats/${resultat.donnees.id}`, { replace: true });
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Rejoindre un championnat" retourVers="/accueil" />
        <p className="text-corps-sm text-texte-doux -mt-1">
          Entre le code à {LONGUEUR_CODE} caractères reçu.
        </p>
      </Bloc>

      <form onSubmit={soumettre} className="mt-3 flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface p-5">
          <ChampCode
            valeur={code}
            onChange={(valeur) => {
              setCode(valeur);
              if (erreurCode) setErreurCode(null);
              setAlerte(null);
            }}
            erreur={erreurCode}
            tentative={tentative}
            autoFocus
          />
        </Bloc>

        {alerte && (
          <Alerte ton="erreur" tentative={tentative}>
            {alerte}
          </Alerte>
        )}

        <Bloc rang={3}>
          {/* Le bouton reste actif tant que le code est incomplet : un bouton
              grisé ne dit pas ce qui manque. L'appui pose le message sous les
              cases, à l'endroit exact qu'il faut corriger. */}
          <Bouton
            type="submit"
            variante="principal"
            occupe={envoi}
            libelleOccupe="Vérification…"
            className={complet ? "" : "opacity-60"}
          >
            Rejoindre le championnat
          </Bouton>
        </Bloc>
      </form>
    </Ecran>
  );
}
