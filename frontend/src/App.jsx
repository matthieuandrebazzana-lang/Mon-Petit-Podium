import { useEffect, useState } from "react";
import { APP_VERSION, API_URL } from "./config.js";

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

export default function App() {
  const api = useSanteApi();

  return (
    <main className="ecran flex min-h-dvh flex-col">
      <div className="flex flex-1 flex-col justify-center gap-3">
        <section className="rounded-bloc bg-primaire p-5">
          <p className="text-label-sm text-white/60 uppercase">Saison 2026</p>
          <h1 className="mt-2 text-titre text-white">Mon Petit Podium</h1>
          <p className="mt-1 text-corps-sm text-white/60">
            Pronostics Formule 1 entre amis.
          </p>
        </section>

        <section className="rounded-carte bg-surface flex items-center justify-between p-4">
          <span className="text-label text-texte-doux uppercase">Backend</span>
          <span className="flex items-center gap-2 text-corps-sm">
            <span className={`size-2 rounded-full ${api.couleur}`} />
            {api.libelle}
          </span>
        </section>
      </div>

      <footer className="pt-4 text-center">
        <span className="text-label-sm text-texte-doux uppercase">
          Version {APP_VERSION}
        </span>
      </footer>
    </main>
  );
}
