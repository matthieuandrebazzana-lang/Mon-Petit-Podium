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
import Piste from "./ecrans/Piste.jsx";
import Cotes from "./ecrans/Cotes.jsx";
import Pronostics from "./ecrans/Pronostics.jsx";
import RecapPronostics from "./ecrans/RecapPronostics.jsx";
import MonProfil from "./ecrans/MonProfil.jsx";
import ProfilMembre from "./ecrans/ProfilMembre.jsx";
import GrandsPrixDuMembre from "./ecrans/GrandsPrixDuMembre.jsx";
import Calendrier from "./ecrans/Calendrier.jsx";
import ResultatsGp from "./ecrans/ResultatsGp.jsx";

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

      {/* Résultats d'un Grand Prix, hors des deux groupes pour la même raison
          que l'écran ci-dessus : le classement de la course est **public**
          (étape 6, et la maquette 11 le montre comme tel). Dans le groupe
          public, `RoutePublique` renverrait un membre connecté sur son accueil ;
          dans le groupe protégé, un visiteur sans compte ne pourrait pas le
          lire. La variante avec championnat est déclarée à côté : c'est la même
          route côté API, avec `?championnat_id=`, et c'est elle qui ajoute le
          classement des membres — que la route refuse à qui n'en est pas. */}
      <Route path="/grands-prix/:gpId/resultats" element={<ResultatsGp />} />
      <Route
        path="/championnats/:id/grands-prix/:gpId/resultats"
        element={<ResultatsGp />}
      />

      <Route element={<RouteProtegee />}>
        <Route path="/accueil" element={<Accueil />} />
        {/* « creer » et « rejoindre » sont déclarés avant « :id » : sans cet
            ordre, React Router ferait de « creer » un identifiant. */}
        <Route path="/championnats/creer" element={<CreerChampionnat />} />
        <Route path="/championnats/rejoindre" element={<RejoindreChampionnat />} />
        <Route path="/championnats/:id" element={<Championnat />} />
        {/* Vue piste : le même championnat, vu de la route (maquette 07b). */}
        <Route path="/championnats/:id/piste" element={<Piste />} />
        {/* Calendrier du championnat (maquette 15). Le mot « historique » de la
            maquette est écarté par le vocabulaire imposé de la section 1. */}
        <Route path="/championnats/:id/calendrier" element={<Calendrier />} />

        {/* Parcours de pronostics, maquettes 08 → 09 → 10. Les trois écrans
            partagent l'identifiant du Grand Prix : la lecture des cotes est
            publique, mais les favoris et les pronostics sont nominatifs. */}
        <Route path="/grands-prix/:gpId/cotes" element={<Cotes />} />
        <Route path="/grands-prix/:gpId/pronostics" element={<Pronostics />} />
        <Route path="/grands-prix/:gpId/recap" element={<RecapPronostics />} />

        {/* Profils, maquettes 14 → 12 → 13. « /profil » au singulier est le
            mien, le seul qui se modifie ; « /profils/:id » celui d'un autre
            membre. Deux écrans distincts et non un seul paramétré : l'un porte
            des sélecteurs et un bouton d'enregistrement, l'autre non, et les
            confondre reviendrait à cacher la moitié d'un écran sur deux. */}
        <Route path="/profil" element={<MonProfil />} />
        <Route path="/profils/:profilId" element={<ProfilMembre />} />
        <Route
          path="/profils/:profilId/grands-prix"
          element={<GrandsPrixDuMembre />}
        />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
