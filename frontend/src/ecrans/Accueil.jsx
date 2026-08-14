import { useCallback, useState } from "react";
import { Link } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Pastille from "../composants/Pastille.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { Barre, Carte, Pave } from "../composants/Squelette.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import { IconeChevronDroit, IconeMembres, IconePlus } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { listerMesChampionnats } from "../lib/championnats.js";
import { chargerAccueilGp, cleAccueilGp } from "../lib/pronostics.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";
import { APP_VERSION } from "../config.js";

/**
 * Bloc rouge « PROCHAIN GP » de la maquette 04.
 *
 * Le GP et les pronostics du joueur sont lus **directement dans Supabase**,
 * sous les politiques de lecture des étapes 4 et 5, et non par l'API :
 * l'accueil est le premier écran de l'app, et lui faire attendre le réveil de
 * Railway pour afficher son bloc principal serait le pire endroit où payer ce
 * délai. Les deux lectures partagent le même passage dans le cache
 * *stale-while-revalidate* — aucun appel réseau supplémentaire ne bloque
 * l'affichage.
 *
 * **La clé de cache porte l'identifiant du compte.** Le prochain Grand Prix est
 * le même pour tout le monde, mais l'état des pronostics ne l'est pas : deux
 * personnes qui se relaient sur le même téléphone ne doivent jamais hériter du
 * bouton de l'autre, fût-ce le temps d'un rafraîchissement.
 */
export function BlocProchainGp({ profilId }) {
  const chargeur = useCallback((signal) => chargerAccueilGp(profilId, signal), [profilId]);
  const { donnees, chargement } = useDonnees(
    profilId ? cleAccueilGp(profilId) : null,
    chargeur,
  );

  const gp = donnees?.gp ?? null;
  const etat = useFermeture(gp?.date_course);

  if (chargement && !gp) {
    // Le squelette garde l'aplat rouge du bloc et n'en griser que le contenu :
    // c'est le seul aplat de couleur de l'accueil, et le voir passer au gris
    // puis revenir au rouge ferait clignoter l'écran d'entrée de l'app.
    return (
      <div className="rounded-bloc bg-primaire p-5" aria-hidden="true">
        <div className="mb-2.5 flex items-center justify-between gap-3">
          <div className="h-6 w-24 rounded-full bg-white/25" />
          <div className="h-3 w-20 rounded-full bg-white/20" />
        </div>
        <div className="h-5 w-40 rounded-full bg-white/25" />
        <div className="mt-2.5 mb-4 h-3 w-52 rounded-full bg-white/20" />
        <div className="rounded-champ h-tactile w-full bg-white/15" />
      </div>
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

  // **Trois destinations pour un même bouton**, et le libellé suit toujours la
  // destination : un bouton nommé « Pronostiquer » qui ouvre autre chose serait
  // une promesse fausse.
  //
  // - Grand Prix **couru** (étape 9) — les résultats. Il n'y a plus de
  //   pronostics à saisir, et c'est l'écran que tout le monde ouvre le dimanche
  //   soir. C'est aussi le seul cas où le bloc n'annonce pas un GP à venir : le
  //   libellé du bandeau change avec lui.
  // - Pronostics déjà enregistrés, ou fermeture passée — le récapitulatif.
  // - Sinon — le tableau des cotes.
  const couru = donnees?.couru === true;
  const versRecap = !couru && (etat.ferme || donnees?.aPronostique === true);

  const destination = couru
    ? `/grands-prix/${gp.id}/resultats`
    : `/grands-prix/${gp.id}/${versRecap ? "recap" : "cotes"}`;
  const libelle = couru
    ? "Voir les résultats"
    : versRecap
      ? "Voir mes pronos"
      : "Pronostiquer";

  return (
    <div className="rounded-bloc bg-primaire p-5">
      <div className="mb-2.5 flex items-center justify-between gap-3">
        <span className="text-label-sm rounded-full bg-white/20 px-2.5 py-1 text-white uppercase">
          {couru ? "Dernier GP" : "Prochain GP"}
        </span>
        <span className="shrink-0 text-[11px] text-white/60">{depart.courte}</span>
      </div>

      <p className="truncate text-[22px] font-medium text-white">{gp.nom}</p>
      <p className="mb-4 text-[12px] text-white/60">
        {couru
          ? "Course terminée · Points attribués"
          : etat.ferme
            ? "Pronostics fermés"
            : etat.texte
              ? `Pronos ouverts · Fermeture dans ${etat.texte}`
              : "Pronos ouverts"}
      </p>

      <Link
        to={destination}
        className="rounded-champ bg-surface text-primaire pressable min-h-tactile flex items-center justify-center px-4 text-center text-[14px] font-medium"
      >
        {/* Le cache peut avoir servi l'état d'avant la dernière validation : le
            libellé change alors sous les yeux du joueur, une fois la lecture
            fraîche revenue. TexteEchange (transitions-dev 04) le remplace en
            place plutôt que de le laisser clignoter. */}
        <TexteEchange valeur={libelle} />
      </Link>
    </div>
  );
}

/** Carte de championnat de la maquette 04.
 *
 * Exportée depuis l'étape 10 : l'écran de l'onglet Championnats sert la même
 * liste, et deux cartes dessinées séparément auraient divergé au premier
 * ajustement. C'est aussi ce qui fait qu'un championnat se reconnaît d'un écran
 * à l'autre. */
export function CarteChampionnat({ championnat, rang }) {
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
export function SqueletteChampionnats() {
  return (
    <div className="flex flex-col gap-2.5">
      {[0, 1].map((rang) => (
        <Carte key={rang} className="flex items-center gap-3.5">
          <Pave className="size-[46px] shrink-0" />
          <div className="flex-1">
            <Barre largeur="w-1/2" />
            <Barre largeur="w-3/4" hauteur="h-2.5" className="mt-2" />
          </div>
        </Carte>
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
export function Action({ vers, variante, icone, children }) {
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
  const { pseudo, utilisateur } = useAuth();

  // La clé porte l'identifiant du compte : deux personnes qui se relaient sur
  // le même téléphone ne doivent jamais voir la liste de l'autre, même une
  // fraction de seconde avant le rafraîchissement.
  const cle = utilisateur ? `championnats:${utilisateur.id}` : null;
  const chargeur = useCallback((signal) => listerMesChampionnats(signal), []);
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const [tentative, setTentative] = useState(0);

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  const championnats = donnees ?? [];

  return (
    <Ecran direction="avant">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={1} className="flex items-center justify-between gap-3 py-1">
          <h1 className="text-titre text-texte min-w-0 truncate">
            {pseudo ? `Salut ${pseudo}` : "Mon Petit Podium"}
          </h1>
          {/* La pastille mène au profil (maquette 14). C'est l'endroit où
              l'attend quelqu'un qui vient d'iOS, et c'est déjà la place que la
              maquette 04 lui donne — elle n'y était simplement reliée à rien.
              La zone tactile est portée à 44px sans déplacer la pastille de
              42px que dessine la maquette. */}
          <Link
            to="/profil"
            aria-label="Mon profil"
            className="pressable size-tactile -m-0.5 flex shrink-0 items-center justify-center"
          >
            <Pastille nom={pseudo} graine={utilisateur?.id ?? pseudo} taille="lg" />
          </Link>
        </Bloc>

        <Bloc rang={2}>
          <BlocProchainGp profilId={utilisateur?.id ?? null} />
        </Bloc>

        <Bloc rang={3} className="flex flex-col gap-2.5">
          <p className="text-label text-texte-doux px-1 pt-1 uppercase">
            Mes championnats
          </p>

          {/* Le cache a peut-être déjà servi la liste : l'échec s'ajoute alors
              sous les cartes plutôt que de les remplacer. Le bouton relance
              l'appel, ce qui est exactement le geste attendu quand Railway se
              réveille encore. */}
          {echec && (
            <BlocErreur
              echec={echec}
              onReessayer={reessayer}
              tentative={tentative}
            />
          )}

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
        {/* La déconnexion a quitté ce pied de page pour le profil (étape 8),
            comme l'annonçait l'étape 3 : c'est sa place définitive, et la
            garder ici en double aurait donné deux endroits à corriger. */}
        <span className="text-label-sm text-texte-doux uppercase">
          Version {APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
