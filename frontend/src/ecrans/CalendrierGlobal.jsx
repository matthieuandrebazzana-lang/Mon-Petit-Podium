import { useCallback, useState } from "react";
import { Link } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import TraceCircuit, { traceDuGrandPrix } from "../composants/TraceCircuit.jsx";
import { Barre, Carte, Pave } from "../composants/Squelette.jsx";
import { IconeChevronDroit } from "../composants/Icones.jsx";
import { ActionsChampionnat } from "./Accueil.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { listerMesChampionnats } from "../lib/championnats.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart } from "../lib/format.js";

/**
 * Cible de l'onglet **Calendrier** de la barre basse (étape 10).
 *
 * Une vue d'ensemble : un championnat par rangée, avec le Grand Prix qui
 * l'attend. Chaque rangée mène au calendrier complet de ce championnat
 * (maquette 15), Grand Prix par Grand Prix.
 *
 * **Pourquoi cet écran existe, plutôt qu'un onglet qui ouvrirait directement un
 * calendrier.** Le calendrier de la maquette 15 est celui d'**un** championnat :
 * il porte le score du membre et le mini-classement de ses amis sur chaque
 * course. L'onglet, lui, est global. Le brancher sur un championnat choisi
 * d'office aurait fait deviner à l'application lequel compte pour son
 * propriétaire ; cette page pose la question au lieu d'y répondre à sa place.
 *
 * **Le prochain Grand Prix est le même sur toutes les rangées**, et c'est
 * normal : `public.grands_prix` est une table globale, une course n'appartient
 * à aucun championnat. Il est donc lu une seule fois côté backend et recopié
 * sur chaque championnat. La répétition dit une chose utile — ce week-end, ces
 * cinq championnats jouent tous la même course.
 */

/* -------------------------------------------------------------------------- */
/*  Une rangée de championnat                                                 */
/* -------------------------------------------------------------------------- */

export function RangeeChampionnat({ championnat }) {
  const gp = championnat.prochain_gp ?? null;
  const depart = formaterDepart(gp?.date_course);
  // Le tracé de circuit d'`assets/gp-cards.svg`, comme sur les cartes de la
  // maquette 15. Sans Grand Prix annoncé, aucun tracé : une silhouette de
  // circuit sous « Saison terminée » laisserait croire qu'il en reste un.
  const trace = gp ? traceDuGrandPrix(gp.nom) : null;

  return (
    <Link
      to={`/championnats/${championnat.id}/calendrier`}
      className="rounded-carte bg-surface shadow-carte pressable-large min-h-tactile flex items-center gap-3.5 p-4"
    >
      <span
        aria-hidden="true"
        className={`bg-fond rounded-champ flex size-11 shrink-0 items-center justify-center ${
          gp ? "text-primaire/40" : "text-texte-doux/25"
        }`}
      >
        {trace ? (
          <TraceCircuit trace={trace} className="h-5 w-8" />
        ) : (
          <span className="bg-texte-doux/30 size-2 rounded-full" />
        )}
      </span>

      <span className="min-w-0 flex-1">
        <span className="text-corps text-texte block truncate font-medium">
          {championnat.nom}
        </span>
        {/* Trois états, jamais confondus : un Grand Prix daté, un Grand Prix
            dont Unibet n'a pas encore publié l'horaire, et plus aucun Grand
            Prix. Le deuxième ne doit pas emprunter la formule du troisième — un
            GP annoncé sans date reste un GP à jouer. */}
        <span className="text-texte-doux mt-0.5 block truncate text-[12px]">
          {gp
            ? `${gp.nom} · ${depart.courte ?? "Date à confirmer"}`
            : "Saison terminée"}
        </span>
      </span>

      <IconeChevronDroit className="text-texte-doux size-4 shrink-0" />
    </Link>
  );
}

/* -------------------------------------------------------------------------- */
/*  Squelette                                                                 */
/* -------------------------------------------------------------------------- */

function SqueletteCalendrierGlobal() {
  return (
    <div className="flex flex-col gap-2.5">
      {[0, 1].map((rang) => (
        <Carte key={rang} className="flex items-center gap-3.5">
          <Pave className="size-11 shrink-0" />
          <div className="flex-1">
            <Barre largeur="w-2/5" />
            <Barre largeur="w-3/4" hauteur="h-2.5" className="mt-2" />
          </div>
        </Carte>
      ))}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  L'écran                                                                   */
/* -------------------------------------------------------------------------- */

export default function CalendrierGlobal() {
  const { utilisateur } = useAuth();

  // Même clé de cache que l'accueil et que l'onglet Championnats : les trois
  // écrans lisent la même route, et arriver ici depuis l'un des deux autres
  // n'attend rien. Une adhésion invalide les trois d'un seul coup.
  const cle = utilisateur ? `championnats:${utilisateur.id}` : null;
  const chargeur = useCallback((signal) => listerMesChampionnats(signal), []);
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const [tentative, setTentative] = useState(0);

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  const championnats = donnees ?? [];
  const prochain = championnats.find((c) => c.prochain_gp)?.prochain_gp ?? null;
  const depart = formaterDepart(prochain?.date_course);

  return (
    <Ecran direction="avant">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={1} className="pt-1 pb-1">
          <h1 className="text-titre-lg text-texte">Calendrier</h1>
          <p className="text-texte-doux mt-1 text-[13px]">
            {chargement && !donnees
              ? "Chargement…"
              : prochain
                ? `Prochain Grand Prix · ${depart.courte ?? "date à confirmer"}`
                : "Saison 2026"}
          </p>
        </Bloc>

        {echec && (
          <Bloc rang={2}>
            <BlocErreur echec={echec} onReessayer={reessayer} tentative={tentative} />
          </Bloc>
        )}

        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement}
            squelette={<SqueletteCalendrierGlobal />}
          >
            {championnats.length === 0 ? (
              <div className="rounded-bloc bg-surface shadow-bloc px-5 py-9 text-center">
                <p className="text-corps text-texte font-medium">
                  Rejoins ou crée un championnat pour voir ton calendrier
                </p>
                <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                  Le calendrier suit les Grands Prix d'un championnat : ses
                  scores, ses classements, course après course.
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-2.5">
                {championnats.map((championnat) => (
                  <RangeeChampionnat
                    key={championnat.id}
                    championnat={championnat}
                  />
                ))}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {/* Les deux actions ne s'affichent que dans l'état vide : ailleurs,
            elles doubleraient sans raison celles de l'onglet Championnats, et
            un écran de consultation n'a pas à porter les mêmes boutons qu'un
            écran de gestion. */}
        {!chargement && championnats.length === 0 && (
          <Bloc rang={3}>
            <ActionsChampionnat />
          </Bloc>
        )}
      </div>
    </Ecran>
  );
}
