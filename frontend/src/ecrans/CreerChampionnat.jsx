import { useState } from "react";
import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Champ from "../composants/Champ.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import { creerChampionnat } from "../lib/championnats.js";
import { oublierCache } from "../lib/useDonnees.js";
import { useAuth } from "../auth/AuthContexte.jsx";

const LONGUEUR_MIN = 2;
const LONGUEUR_MAX = 40;

function validerNom(valeur) {
  const nom = valeur.trim();
  if (!nom) return "Donne un nom à ton championnat.";
  if (nom.length < LONGUEUR_MIN) {
    return `Le nom doit faire au moins ${LONGUEUR_MIN} caractères.`;
  }
  if (nom.length > LONGUEUR_MAX) {
    return `Le nom ne peut pas dépasser ${LONGUEUR_MAX} caractères.`;
  }
  return null;
}

/** Maquette 05 — création d'un championnat. */
export default function CreerChampionnat() {
  const naviguer = useNavigate();
  const { utilisateur } = useAuth();

  const [nom, setNom] = useState("");
  const [erreurNom, setErreurNom] = useState(null);
  const [alerte, setAlerte] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  const [tentative, setTentative] = useState(0);

  async function soumettre(evenement) {
    evenement.preventDefault();
    setTentative((n) => n + 1);

    const probleme = validerNom(nom);
    setErreurNom(probleme);
    if (probleme) {
      setAlerte(null);
      return;
    }

    setEnvoi(true);
    setAlerte(null);

    const resultat = await creerChampionnat(nom.trim());
    setEnvoi(false);

    if (!resultat.ok) {
      setAlerte(resultat.message);
      return;
    }

    // La liste de l'accueil vient d'un cache : sans cette invalidation, le
    // championnat tout juste créé n'y apparaîtrait qu'au rafraîchissement
    // suivant, et le retour depuis l'écran du championnat semblerait l'avoir
    // perdu.
    if (utilisateur) oublierCache(`championnats:${utilisateur.id}`);

    // `nouveau` fait mettre le code d'invitation en avant à l'arrivée, et
    // `replace` retire cet écran de l'historique : le geste de retour ramène
    // sur l'accueil, pas sur un formulaire déjà validé.
    naviguer(`/championnats/${resultat.donnees.id}`, {
      replace: true,
      state: { nouveau: true },
    });
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Créer un championnat" retourVers="/accueil" />
      </Bloc>

      <form onSubmit={soumettre} className="flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface p-4.5">
          <Champ
            label="Nom du championnat"
            name="nom"
            type="text"
            autoComplete="off"
            placeholder="Les Potes F1"
            maxLength={LONGUEUR_MAX}
            value={nom}
            onChange={(evenement) => {
              setNom(evenement.target.value);
              if (erreurNom) setErreurNom(null);
              setAlerte(null);
            }}
            erreur={erreurNom}
            tentative={tentative}
          />
        </Bloc>

        {/* Le code n'existe pas encore : il est tiré par le serveur à la
            création, et il serait malhonnête d'en afficher un avant qu'il soit
            réservé en base. Le bloc garde sa place et son rôle dans la
            composition de la maquette, et annonce ce qui va s'y inscrire. */}
        <Bloc rang={3} className="rounded-bloc bg-primaire p-5">
          <p className="text-label uppercase text-white/60">Code d'invitation</p>
          <p
            aria-hidden="true"
            className="text-score mt-2 tracking-[6px] text-white/25"
          >
            ——————
          </p>
          <p className="text-corps-sm mt-1.5 text-white/50">
            Généré automatiquement à la création.
          </p>
        </Bloc>

        {alerte && (
          <Alerte ton="erreur" tentative={tentative}>
            {alerte}
          </Alerte>
        )}

        <Bloc rang={4}>
          <Bouton
            type="submit"
            variante="principal"
            occupe={envoi}
            libelleOccupe="Création…"
          >
            Créer le championnat
          </Bouton>
        </Bloc>
      </form>
    </Ecran>
  );
}
