import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Champ from "../composants/Champ.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import BoutonsOAuth from "../composants/BoutonsOAuth.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { PSEUDO_DEJA_PRIS } from "../lib/erreurs.js";
import {
  validerEmail,
  validerMotDePasse,
  validerPseudo,
} from "../lib/validation.js";

const VIDE = { pseudo: "", email: "", motDePasse: "" };

/** Maquette 02 — création de compte. */
export default function Inscription() {
  const { inscrire, pseudoDisponible } = useAuth();
  const naviguer = useNavigate();

  const [valeurs, setValeurs] = useState(VIDE);
  const [erreursChamps, setErreursChamps] = useState({});
  const [alerte, setAlerte] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  // Incrémenté à chaque soumission : c'est lui qui relance la secousse quand
  // le message d'erreur est identique à celui du coup précédent.
  const [tentative, setTentative] = useState(0);

  function changer(nom) {
    return (evenement) => {
      setValeurs((precedent) => ({
        ...precedent,
        [nom]: evenement.target.value,
      }));
      // Corriger sa saisie efface immédiatement le reproche : on ne laisse pas
      // un champ en rouge pendant que l'utilisateur le répare.
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
      pseudo: validerPseudo(valeurs.pseudo),
      email: validerEmail(valeurs.email),
      motDePasse: validerMotDePasse(valeurs.motDePasse),
    };
    setErreursChamps(controles);
    if (Object.values(controles).some(Boolean)) {
      setAlerte(null);
      return;
    }

    setEnvoi(true);
    setAlerte(null);

    const pseudo = valeurs.pseudo.trim();

    // Le pseudo est contrôlé avant l'inscription pour que le refus s'affiche
    // sous le champ fautif, et non sous forme d'échec global après coup. La
    // garantie d'unicité reste l'index en base : entre ce test et l'insertion,
    // rien n'empêche quelqu'un d'autre de prendre le même pseudo.
    const disponibilite = await pseudoDisponible(pseudo);
    if (!disponibilite.disponible) {
      setEnvoi(false);
      setErreursChamps({ pseudo: PSEUDO_DEJA_PRIS });
      return;
    }

    const resultat = await inscrire({
      pseudo,
      email: valeurs.email.trim(),
      motDePasse: valeurs.motDePasse,
    });
    setEnvoi(false);

    if (!resultat.ok) {
      // Le doublon détecté au dernier moment (course entre deux inscriptions)
      // revient ici : on le repose sous le champ pseudo plutôt que dans le
      // bandeau global, pour désigner ce qu'il faut corriger.
      if (resultat.message === PSEUDO_DEJA_PRIS) {
        setErreursChamps({ pseudo: PSEUDO_DEJA_PRIS });
        return;
      }
      setAlerte({ ton: "erreur", texte: resultat.message });
      return;
    }

    if (resultat.confirmationRequise) {
      // Sans session, le compte existe mais dort : inutile de rediriger vers un
      // accueil qui renverrait aussitôt sur la connexion.
      setValeurs(VIDE);
      setAlerte({
        ton: "succes",
        texte:
          "Compte créé. Ouvre le lien de confirmation envoyé par email pour activer ton compte.",
      });
      return;
    }

    naviguer("/accueil", { replace: true });
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Créer un compte" retourVers="/" />
      </Bloc>

      <form onSubmit={soumettre} className="flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface shadow-bloc p-4.5">
          <div className="flex flex-col gap-3.5">
            <Champ
              label="Pseudo"
              name="pseudo"
              type="text"
              autoComplete="nickname"
              autoCapitalize="none"
              placeholder="MaxV33"
              maxLength={20}
              value={valeurs.pseudo}
              onChange={changer("pseudo")}
              erreur={erreursChamps.pseudo}
              tentative={tentative}
            />
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
            <Champ
              label="Mot de passe"
              name="motDePasse"
              type="password"
              autoComplete="new-password"
              placeholder="8 caractères minimum"
              value={valeurs.motDePasse}
              onChange={changer("motDePasse")}
              erreur={erreursChamps.motDePasse}
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
            libelleOccupe="Création…"
          >
            Créer mon compte
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
            Déjà un compte ?{" "}
            <Link to="/connexion" className="text-primaire font-medium">
              Se connecter
            </Link>
          </p>
        </div>
      </Bloc>
    </Ecran>
  );
}
