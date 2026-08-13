import { useCallback, useMemo } from "react";
import { Link, useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { IconeCoche, IconeHorloge } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerRecap, indexerCotes, organiserPronostics } from "../lib/pronostics.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";

function SqueletteRecap() {
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-bloc bg-primaire h-[88px]" />
      <div className="rounded-carte bg-surface flex flex-col gap-4 p-4">
        {[0, 1, 2, 3].map((rang) => (
          <div key={rang} className="flex items-center justify-between gap-3">
            <div className="bg-fond h-3.5 w-1/3 rounded-full" />
            <div className="bg-fond h-6 w-24 rounded-[10px]" />
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * Une ligne de pronostic : marché, choix, points et étiquette.
 *
 * Les points affichés sont ceux que ce pronostic **rapportera s'il tombe**
 * (règle 4.1). Rien n'est acquis avant la course.
 */
function Ligne({ marche, choix, obligatoire }) {
  return (
    <li className="flex items-center justify-between gap-3 py-2.5">
      <span className="min-w-0">
        <span className="text-texte-doux block truncate text-[10px] font-medium tracking-[0.3px] uppercase">
          {marche}
        </span>
        <span className="text-texte mt-0.5 block truncate text-[14px] font-medium">
          {choix.pilote ?? "Cote retirée par le bookmaker"}
        </span>
      </span>

      <span className="flex shrink-0 items-center gap-2">
        <span className="bg-fond text-primaire rounded-[10px] px-2.5 py-1.5 text-[13px] font-medium">
          {formaterPoints(choix.points)}
        </span>
        <span
          className={`rounded-md px-1.5 py-0.5 text-[9px] font-medium ${
            obligatoire
              ? "bg-accent/15 text-accent"
              : "bg-secondaire/15 text-secondaire"
          }`}
        >
          {obligatoire ? "Obligatoire" : "Bonus"}
        </span>
      </span>
    </li>
  );
}

/** Maquette 10 — récapitulatif des pronostics du joueur pour un GP. */
export default function RecapPronostics() {
  const { gpId } = useParams();
  const naviguer = useNavigate();
  const emplacement = useLocation();
  const { utilisateur } = useAuth();

  // Vrai seulement au retour de l'écran de saisie : la maquette 10 est le
  // « récap après validation », mais l'écran doit aussi tenir debout quand on
  // y arrive à froid, sans rien célébrer.
  const juste = Boolean(emplacement.state?.enregistre);

  const cle = utilisateur ? `recap:${utilisateur.id}:${gpId}` : null;
  const chargeur = useCallback(
    (signal) => chargerRecap(gpId, utilisateur?.id, signal),
    [gpId, utilisateur?.id],
  );
  const { donnees, chargement, erreur } = useDonnees(cle, chargeur);

  const gp = donnees?.gp ?? null;
  const index = useMemo(() => indexerCotes(gp), [gp]);
  const pronostics = useMemo(
    () => organiserPronostics(donnees?.pronostics, index),
    [donnees, index],
  );

  const etat = useFermeture(gp?.date_course);

  if (erreur && !donnees) {
    return (
      <Ecran direction="arriere">
        <Bloc rang={1}>
          <EnTete titre="Récap" retourVers="/accueil" />
        </Bloc>
        <Bloc rang={2}>
          <Alerte ton="erreur">{erreur}</Alerte>
        </Bloc>
      </Ecran>
    );
  }

  const depart = formaterDepart(gp?.date_course);
  const obligatoires = [
    ...(pronostics.vainqueur
      ? [{ marche: pronostics.vainqueur.libelle ?? "Vainqueur", choix: pronostics.vainqueur }]
      : []),
    ...pronostics.podium.map((choix) => ({
      marche: choix.libelle ?? "Podium",
      choix,
    })),
  ];

  // Somme de ce que le joueur peut décrocher sur ce GP, tous pronostics
  // réussis. Absent des maquettes, mais c'est la question que tout le monde
  // se pose devant un récapitulatif, et la règle 4.1 la rend calculable.
  const potentiel = [...obligatoires.map((l) => l.choix), ...pronostics.bonus]
    .map((choix) => choix.points ?? 0)
    .reduce((total, points) => total + points, 0);

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete
          titre="Récap"
          retourVers="/accueil"
          libelleRetour={gp?.nom ?? "Accueil"}
          sousTitre={
            gp
              ? depart.heure
                ? `${depart.jour} · Départ ${depart.heure}`
                : depart.jour
              : null
          }
        />
      </Bloc>

      <div className="mt-2 flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteRecap />}
          >
            {gp && (
              <div className="flex flex-col gap-3">
                {pronostics.vide ? (
                  <div className="rounded-bloc bg-surface px-5 py-9 text-center">
                    <p className="text-corps text-texte font-medium">
                      Aucun pronostic pour ce Grand Prix
                    </p>
                    <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                      {etat.ferme
                        ? "Les pronostics sont fermés : ce Grand Prix ne rapportera aucun point."
                        : "Il est encore temps : choisis ton vainqueur et ton podium."}
                    </p>
                  </div>
                ) : (
                  <>
                    <div className="rounded-bloc bg-primaire flex items-center gap-4 p-5">
                      <span
                        aria-hidden="true"
                        className="flex size-12 shrink-0 items-center justify-center rounded-full bg-white/15"
                      >
                        <IconeCoche className="size-6 text-white [stroke-width:2.5]" />
                      </span>
                      <span className="min-w-0">
                        <span className="block text-[17px] font-medium text-white">
                          {juste ? "Pronos enregistrés !" : "Tes pronos sont en place"}
                        </span>
                        <span className="mt-0.5 block text-[12px] text-white/60">
                          {etat.ferme
                            ? "Les pronostics sont fermés."
                            : "Tu peux les modifier jusqu'au départ."}
                        </span>
                      </span>
                    </div>

                    <div className="rounded-carte bg-surface p-4">
                      <p className="mb-1 text-[10px] font-medium tracking-[0.8px] text-texte-doux uppercase">
                        Obligatoires
                      </p>
                      <ul>
                        {obligatoires.map((ligne, rang) => (
                          <Ligne
                            key={`${ligne.choix.outcome}-${rang}`}
                            marche={ligne.marche}
                            choix={ligne.choix}
                            obligatoire
                          />
                        ))}
                      </ul>

                      {pronostics.bonus.length > 0 && (
                        <>
                          <div className="bg-fond my-2.5 h-px" />
                          <p className="mb-1 text-[10px] font-medium tracking-[0.8px] text-texte-doux uppercase">
                            Bonus
                          </p>
                          <ul>
                            {pronostics.bonus.map((choix, rang) => (
                              <Ligne
                                key={choix.outcome}
                                marche={choix.libelle ?? "Bonus"}
                                choix={choix}
                                obligatoire={false}
                              />
                            ))}
                          </ul>
                        </>
                      )}

                      <div className="bg-fond my-2.5 h-px" />
                      <div className="flex items-baseline justify-between gap-3 pt-0.5">
                        <span className="text-label text-texte-doux uppercase">
                          Total si tout tombe
                        </span>
                        <span className="text-primaire text-[20px] font-medium">
                          {formaterPoints(potentiel)}
                        </span>
                      </div>
                    </div>

                    <div className="rounded-carte bg-surface flex items-center justify-between gap-3 px-4 py-3.5">
                      <span className="min-w-0">
                        <span className="text-texte-doux block text-[11px]">
                          {etat.ferme ? "Pronostics" : "Fermeture dans"}
                        </span>
                        <span className="text-texte mt-0.5 block truncate text-[15px] font-medium">
                          {etat.ferme ? "Fermés" : (etat.texte ?? "Date à confirmer")}
                        </span>
                      </span>
                      {!etat.ferme && (
                        <Link
                          to={`/grands-prix/${gpId}/pronostics`}
                          className="rounded-xl bg-fond text-primaire pressable min-h-tactile flex shrink-0 items-center gap-1.5 px-3.5 text-[13px] font-medium"
                        >
                          <IconeHorloge className="size-3.5" />
                          Modifier
                        </Link>
                      )}
                    </div>
                  </>
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {pronostics.vide && !etat.ferme && (
          <Bloc rang={3}>
            <Bouton
              variante="principal"
              onClick={() => naviguer(`/grands-prix/${gpId}/cotes`)}
            >
              Faire mes pronos
            </Bouton>
          </Bloc>
        )}
      </div>
    </Ecran>
  );
}
