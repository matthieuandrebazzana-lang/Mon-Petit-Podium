import { Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./auth/AuthContexte.jsx";
import { RouteProtegee, RoutePublique } from "./composants/Routes.jsx";
import Alerte from "./composants/Alerte.jsx";
import Landing from "./ecrans/Landing.jsx";
import Inscription from "./ecrans/Inscription.jsx";
import Connexion from "./ecrans/Connexion.jsx";
import MotDePasseOublie from "./ecrans/MotDePasseOublie.jsx";
import NouveauMotDePasse from "./ecrans/NouveauMotDePasse.jsx";
import Accueil from "./ecrans/Accueil.jsx";
import CreerChampionnat from "./ecrans/CreerChampionnat.jsx";
import RejoindreChampionnat from "./ecrans/RejoindreChampionnat.jsx";
import Championnat from "./ecrans/Championnat.jsx";
import Cotes from "./ecrans/Cotes.jsx";
import Pronostics from "./ecrans/Pronostics.jsx";
import RecapPronostics from "./ecrans/RecapPronostics.jsx";

/** Configuration absente : mieux vaut le dire que servir une page blanche. */
function EcranConfiguration({ message }) {
  return (
    <main className="ecran flex min-h-dvh flex-col justify-center gap-3">
      <h1 className="text-titre text-texte">Mon Petit Podium</h1>
      <Alerte ton="erreur">{message}</Alerte>
    </main>
  );
}

export default function App() {
  const { configure, erreurConfiguration } = useAuth();

  if (!configure) return <EcranConfiguration message={erreurConfiguration} />;

  return (
    <Routes>
      {/* Accueil public : un membre déjà connecté est renvoyé sur son accueil. */}
      <Route element={<RoutePublique />}>
        <Route path="/" element={<Landing />} />
        <Route path="/inscription" element={<Inscription />} />
        <Route path="/connexion" element={<Connexion />} />
        <Route path="/mot-de-passe-oublie" element={<MotDePasseOublie />} />
      </Route>

      {/* Hors des deux groupes : la session ouverte par un lien de
          réinitialisation est connectée sans donner droit à l'app, et cet écran
          doit rester atteignable dans cet entre-deux. */}
      <Route path="/nouveau-mot-de-passe" element={<NouveauMotDePasse />} />

      <Route element={<RouteProtegee />}>
        <Route path="/accueil" element={<Accueil />} />
        {/* « creer » et « rejoindre » sont déclarés avant « :id » : sans cet
            ordre, React Router ferait de « creer » un identifiant. */}
        <Route path="/championnats/creer" element={<CreerChampionnat />} />
        <Route path="/championnats/rejoindre" element={<RejoindreChampionnat />} />
        <Route path="/championnats/:id" element={<Championnat />} />

        {/* Parcours de pronostics, maquettes 08 → 09 → 10. Les trois écrans
            partagent l'identifiant du Grand Prix : la lecture des cotes est
            publique, mais les favoris et les pronostics sont nominatifs. */}
        <Route path="/grands-prix/:gpId/cotes" element={<Cotes />} />
        <Route path="/grands-prix/:gpId/pronostics" element={<Pronostics />} />
        <Route path="/grands-prix/:gpId/recap" element={<RecapPronostics />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
