import { useEffect, useState } from "react";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { APP_VERSION, API_URL } from "../config.js";

const ETATS = {
  verification: { libelle: "Vérification…", couleur: "bg-texte-doux" },
  enLigne: { libelle: "En ligne", couleur: "bg-accent" },
  horsLigne: { libelle: "Injoignable", couleur: "bg-primaire" },
};

/**
 * Interroge le health check du backend. Sert uniquement à valider que le
 * frontend et FastAPI se parlent — le cold start Railway peut prendre
 * plusieurs secondes au premier appel, d'où l'état de chargement explicite.
 */
function useSanteApi() {
  const [etat, setEtat] = useState("verification");

  useEffect(() => {
    const controleur = new AbortController();

    fetch(`${API_URL}/health`, { signal: controleur.signal })
      .then((reponse) => {
        if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
        return reponse.json();
      })
      .then(() => setEtat("enLigne"))
      .catch((erreur) => {
        if (erreur.name === "AbortError") return;
        setEtat("horsLigne");
      });

    return () => controleur.abort();
  }, []);

  return ETATS[etat];
}

/**
 * Accueil connecté — version d'étape 2.
 *
 * L'écran complet de la maquette 04 (prochain GP, mes championnats) arrive à
 * l'étape 3 : il dépend de données qui n'existent pas encore. On garde ici le
 * strict nécessaire pour vérifier qu'une session tient debout.
 */
export default function Accueil() {
  const { pseudo, deconnecter } = useAuth();
  const api = useSanteApi();
  const [erreur, setErreur] = useState(null);
  const [sortie, setSortie] = useState(false);

  async function seDeconnecter() {
    setSortie(true);
    setErreur(null);
    const resultat = await deconnecter();
    // En cas de succès, la redirection est portée par le contexte de session :
    // le composant est démonté, inutile de retoucher l'état.
    if (!resultat.ok) {
      setSortie(false);
      setErreur(resultat.message);
    }
  }

  return (
    <Ecran direction="avant">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={1} className="rounded-bloc bg-primaire p-5">
          <p className="text-label-sm text-white/60 uppercase">Saison 2026</p>
          <h1 className="text-titre mt-2 text-white">
            {pseudo ? `Salut ${pseudo}` : "Mon Petit Podium"}
          </h1>
          <p className="text-corps-sm mt-1 text-white/60">
            Pronostics Formule 1 entre amis.
          </p>
        </Bloc>

        <Bloc
          rang={2}
          className="rounded-carte bg-surface flex items-center justify-between p-4"
        >
          <span className="text-label text-texte-doux uppercase">Backend</span>
          <span className="text-corps-sm flex items-center gap-2">
            <span className={`size-2 rounded-full ${api.couleur}`} />
            {api.libelle}
          </span>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {erreur && <Alerte ton="erreur">{erreur}</Alerte>}

        <Bloc rang={3}>
          <Bouton
            variante="secondaire"
            onClick={seDeconnecter}
            occupe={sortie}
            libelleOccupe="Déconnexion…"
          >
            Se déconnecter
          </Bouton>
        </Bloc>
      </div>

      <footer className="pt-4 text-center">
        <span className="text-label-sm text-texte-doux uppercase">
          Version {APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
