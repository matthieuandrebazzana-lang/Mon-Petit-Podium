import { useCallback, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import Alerte from "../composants/Alerte.jsx";
import Pastille from "../composants/Pastille.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { IconeChevronDroit, IconeMembres, IconePlus } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { listerMesChampionnats } from "../lib/championnats.js";
import { chargerProchainGp } from "../lib/pronostics.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";
import { APP_VERSION } from "../config.js";

/**
 * Bloc rouge « PROCHAIN GP » de la maquette 04.
 *
 * Le GP est lu **directement dans Supabase**, sous la politique de lecture
 * publique de l'étape 4, et non par l'API : l'accueil est le premier écran de
 * l'app, et lui faire attendre le réveil de Railway pour afficher son bloc
 * principal serait le pire endroit où payer ce délai.
 *
 * La clé de cache ne porte pas l'identifiant du compte, contrairement à celle
 * des championnats : le prochain Grand Prix est le même pour tout le monde.
 */
function BlocProchainGp() {
  const chargeur = useCallback((signal) => chargerProchainGp(signal), []);
  const { donnees: gp, chargement } = useDonnees("gp:prochain", chargeur);
  const etat = useFermeture(gp?.date_course);

  if (chargement && !gp) {
    return (
      <div className="rounded-bloc bg-primaire h-[150px] animate-pulse opacity-60" />
    );
  }

  // Aucun GP en base : le scraper n'a pas encore tourné, ou la saison est
  // terminée. Le bloc garde sa place dans la composition plutôt que de laisser
  // l'accueil s'effondrer d'un cran à chaque intersaison.
  if (!gp) {
    return (
      <div className="rounded-bloc bg-primaire p-5">
        <p className="text-label-sm uppercase text-white/60">Saison 2026</p>
        <p className="text-titre mt-2 text-white">Pronostics F1 entre amis</p>
        <p className="text-corps-sm mt-1 text-white/60">
          Aucun Grand Prix ouvert aux pronostics pour l'instant. Les cotes sont
          relevées le samedi, après les qualifications.
        </p>
      </div>
    );
  }

  const depart = formaterDepart(gp.date_course);

  return (
    <div className="rounded-bloc bg-primaire p-5">
      <div className="mb-2.5 flex items-center justify-between gap-3">
        <span className="text-label-sm rounded-full bg-white/20 px-2.5 py-1 text-white uppercase">
          Prochain GP
        </span>
        <span className="shrink-0 text-[11px] text-white/60">{depart.courte}</span>
      </div>

      <p className="truncate text-[22px] font-medium text-white">{gp.nom}</p>
      <p className="mb-4 text-[12px] text-white/60">
        {etat.ferme
          ? "Pronostics fermés"
          : etat.texte
            ? `Pronos ouverts · Fermeture dans ${etat.texte}`
            : "Pronos ouverts"}
      </p>

      <Link
        to={`/grands-prix/${gp.id}/${etat.ferme ? "recap" : "cotes"}`}
        className="rounded-champ bg-surface text-primaire pressable min-h-tactile flex items-center justify-center px-4 text-center text-[14px] font-medium"
      >
        {etat.ferme ? "Voir mes pronos" : "Pronostiquer"}
      </Link>
    </div>
  );
}

/** Carte de championnat de la maquette 04. */
function CarteChampionnat({ championnat, rang }) {
  return (
    <Link
      to={`/championnats/${championnat.id}`}
      className="rounded-carte bg-surface pressable min-h-tactile flex items-center gap-3.5 p-4"
    >
      <span
        aria-hidden="true"
        className={`flex size-[46px] shrink-0 items-center justify-center rounded-champ text-white ${
          rang % 2 === 0 ? "bg-primaire" : "bg-accent"
        }`}
      >
        <IconeMembres className="size-[22px]" />
      </span>

      <span className="min-w-0 flex-1">
        <span className="text-corps text-texte block truncate font-medium">
          {championnat.nom}
        </span>
        <span className="text-texte-doux mt-0.5 block text-[12px]">
          {championnat.nombre_membres}{" "}
          {championnat.nombre_membres > 1 ? "membres" : "membre"} · Code{" "}
          {championnat.code_invitation}
        </span>
      </span>

      <IconeChevronDroit className="text-texte-doux size-4 shrink-0" />
    </Link>
  );
}

/** Silhouette des cartes pendant le réveil du backend. */
function SqueletteChampionnats() {
  return (
    <div className="flex flex-col gap-2.5">
      {[0, 1].map((rang) => (
        <div key={rang} className="rounded-carte bg-surface flex items-center gap-3.5 p-4">
          <div className="bg-fond size-[46px] shrink-0 rounded-champ" />
          <div className="flex-1">
            <div className="bg-fond h-3.5 w-1/2 rounded-full" />
            <div className="bg-fond mt-2 h-2.5 w-3/4 rounded-full" />
          </div>
        </div>
      ))}
    </div>
  );
}

function AucunChampionnat() {
  return (
    <div className="rounded-carte bg-surface flex flex-col items-center gap-2 px-5 py-8 text-center">
      <span
        aria-hidden="true"
        className="bg-fond text-texte-doux mb-1 flex size-12 items-center justify-center rounded-champ"
      >
        <IconeMembres className="size-5" />
      </span>
      <p className="text-corps text-texte font-medium">Aucun championnat pour l'instant</p>
      <p className="text-corps-sm text-texte-doux max-w-[26ch]">
        Crée le tien et partage son code, ou rejoins celui d'un ami.
      </p>
    </div>
  );
}

/** Bouton d'action de la grille à deux colonnes de la maquette 04. */
function Action({ vers, variante, icone, children }) {
  const tons =
    variante === "principal" ? "bg-primaire text-white" : "bg-surface text-primaire";

  return (
    <Link
      to={vers}
      className={`rounded-carte-sm pressable min-h-tactile flex items-center justify-center gap-2 px-3 py-4 text-center text-[15px] font-medium ${tons}`}
    >
      {icone}
      {children}
    </Link>
  );
}

/** Maquette 04 — accueil connecté : mes championnats et les deux actions. */
export default function Accueil() {
  const { pseudo, utilisateur, deconnecter } = useAuth();
  const naviguer = useNavigate();

  // La clé porte l'identifiant du compte : deux personnes qui se relaient sur
  // le même téléphone ne doivent jamais voir la liste de l'autre, même une
  // fraction de seconde avant le rafraîchissement.
  const cle = utilisateur ? `championnats:${utilisateur.id}` : null;
  const chargeur = useCallback((signal) => listerMesChampionnats(signal), []);
  const { donnees, chargement, erreur } = useDonnees(cle, chargeur);

  const championnats = donnees ?? [];
  const [sortie, setSortie] = useState(false);

  async function seDeconnecter() {
    setSortie(true);
    const resultat = await deconnecter();
    // En cas de succès la redirection vient du contexte de session : le
    // composant est démonté, inutile de retoucher l'état.
    if (!resultat.ok) setSortie(false);
    else naviguer("/", { replace: true });
  }

  return (
    <Ecran direction="avant">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={1} className="flex items-center justify-between gap-3 py-1">
          <h1 className="text-titre text-texte min-w-0 truncate">
            {pseudo ? `Salut ${pseudo}` : "Mon Petit Podium"}
          </h1>
          <Pastille nom={pseudo} graine={utilisateur?.id ?? pseudo} taille="lg" />
        </Bloc>

        <Bloc rang={2}>
          <BlocProchainGp />
        </Bloc>

        <Bloc rang={3} className="flex flex-col gap-2.5">
          <p className="text-label text-texte-doux px-1 pt-1 uppercase">
            Mes championnats
          </p>

          {erreur && <Alerte ton="erreur">{erreur}</Alerte>}

          <ZoneChargement chargement={chargement} squelette={<SqueletteChampionnats />}>
            {championnats.length === 0 ? (
              <AucunChampionnat />
            ) : (
              <div className="flex flex-col gap-2.5">
                {championnats.map((championnat, rang) => (
                  <CarteChampionnat
                    key={championnat.id}
                    championnat={championnat}
                    rang={rang}
                  />
                ))}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        <Bloc rang={4} className="grid grid-cols-2 gap-2.5">
          <Action
            vers="/championnats/creer"
            variante="principal"
            icone={<IconePlus className="size-4" />}
          >
            Créer
          </Action>
          <Action vers="/championnats/rejoindre" variante="secondaire">
            Rejoindre
          </Action>
        </Bloc>
      </div>

      <footer className="flex flex-col items-center gap-3 pt-5">
        {/* Provisoire : la déconnexion rejoindra l'onglet Profil quand la barre
            de navigation basse existera (étape 8). */}
        <button
          type="button"
          onClick={seDeconnecter}
          disabled={sortie}
          className="text-texte-doux min-h-tactile pressable -my-2 px-3 py-2 text-[13px] font-medium"
        >
          {sortie ? "Déconnexion…" : "Se déconnecter"}
        </button>
        <span className="text-label-sm text-texte-doux uppercase">
          Version {APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
