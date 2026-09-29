import { Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./auth/AuthContexte.jsx";
import { RouteProtegee, RoutePublique } from "./composants/Routes.jsx";
import Alerte from "./composants/Alerte.jsx";
import NavBarre from "./composants/NavBarre.jsx";
import BandeauPrevisualisation from "./composants/BandeauPrevisualisation.jsx";
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
import ResultatsChampionnat from "./ecrans/ResultatsChampionnat.jsx";
import CalendrierGlobal from "./ecrans/CalendrierGlobal.jsx";
import DetailGp from "./ecrans/DetailGp.jsx";
import ListeChampionnats from "./ecrans/ListeChampionnats.jsx";
import ResultatsGp from "./ecrans/ResultatsGp.jsx";
import Privacy from "./ecrans/Privacy.jsx";
import Terms from "./ecrans/Terms.jsx";

/** Configuration absente : mieux vaut le dire que servir une page blanche. */
function EcranConfiguration({ message }) {
  return (
    <main className="ecran flex min-h-dvh flex-col justify-center gap-3">
      <h1 className="text-titre text-texte">Greed F1</h1>
      <Alerte ton="erreur">{message}</Alerte>
    </main>
  );
}

export default function App() {
  const { configure, erreurConfiguration } = useAuth();

  if (!configure) return <EcranConfiguration message={erreurConfiguration} />;

  return (
    <>
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

        {/* Politique de confidentialité et CGU, hors des deux groupes pour la
            même raison que les résultats d'un GP ci-dessous : Google (OAuth) et
            l'App Store doivent pouvoir les atteindre sans session, et un membre
            déjà connecté doit pouvoir les relire sans être renvoyé sur son
            accueil. */}
        <Route path="/privacy" element={<Privacy />} />
        <Route path="/terms" element={<Terms />} />

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
          {/* Cible de l'onglet Championnats de la barre basse (étape 10). */}
          <Route path="/championnats" element={<ListeChampionnats />} />
          {/* Cible de l'onglet Calendrier : la vue globale, tous championnats
              confondus. Le calendrier d'un championnat, lui, reste sous
              « /championnats/:id/calendrier » — c'est là qu'il appartient. */}
          <Route path="/calendrier" element={<CalendrierGlobal />} />
          {/* La fiche d'un Grand Prix, atteinte en touchant sa carte. Elle est
              indexée par le **slug de la liste statique** et non par
              l'identifiant en base, et c'est structurel : onze des douze Grands
              Prix de la saison n'ont pas encore d'identifiant, et ce sont
              précisément ceux-là que cet écran sert. `GP_2026` est la seule
              autorité sur ce qu'est un slug valide — `DetailGp` renvoie au
              calendrier pour tout le reste. */}
          <Route path="/calendrier/:slug" element={<DetailGp />} />
          {/* « creer » et « rejoindre » sont déclarés avant « :id » : sans cet
              ordre, React Router ferait de « creer » un identifiant. */}
          <Route path="/championnats/creer" element={<CreerChampionnat />} />
          <Route path="/championnats/rejoindre" element={<RejoindreChampionnat />} />
          <Route path="/championnats/:id" element={<Championnat />} />
          {/* Vue piste : le même championnat, vu de la route (maquette 07b). */}
          <Route path="/championnats/:id/piste" element={<Piste />} />
          {/* Résultats par Grand Prix : ce que chaque membre a joué, GP par GP.
              C'est l'entrée que porte désormais l'écran d'un championnat. */}
          <Route
            path="/championnats/:id/resultats"
            element={<ResultatsChampionnat />}
          />
          {/* Calendrier du championnat (maquette 15). Le mot « historique » de la
              maquette est écarté par le vocabulaire imposé de la section 1.

              **Plus d'entrée depuis le championnat depuis la version `0.53.0`**,
              et la route reste : c'est du code éprouvé qu'on ne supprime pas
              (CLAUDE.md §6). Son mini-classement par Grand Prix n'existe nulle
              part ailleurs, et l'écran redevient la bonne réponse le jour où on
              le redemande. */}
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

      {/* Hors de <Routes>, et c'est structurel : la barre est `position:
          fixed`, or `Ecran` porte un `transform` (son animation d'entrée) qui
          en ferait le bloc conteneur — la barre défilerait avec la page. Montée
          ici, elle ne se démonte pas d'un écran à l'autre : la couleur de
          l'onglet glisse au lieu de repartir de zéro à chaque navigation. Elle
          décide seule de s'afficher ou non, à partir du chemin courant et de la
          session. */}
      <NavBarre />

      {/* Hors de <Routes> pour la raison exacte de la barre ci-dessus : la
          pastille est `position: fixed`, et `Ecran` porte un `transform` qui en
          ferait le bloc conteneur. Montée ici, elle traverse toute
          l'application — ce qui est le point, puisque le mode qu'elle annonce
          la traverse aussi. Elle décide seule de s'afficher, à partir du mode
          admin et du mode prévisualisation. */}
      <BandeauPrevisualisation />
    </>
  );
}
