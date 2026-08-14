import { useCallback } from "react";
import { useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Alerte from "../composants/Alerte.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { IconeCoche, IconeHorloge } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerGrandsPrixDuMembre,
  chargerProfil,
  cleMesGp,
} from "../lib/profils.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";

/**
 * Maquette 13 — les Grands Prix pariés par un membre, du plus récent au plus
 * ancien, avec ses pronostics.
 *
 * **Les pronostics d'un membre sont visibles par les autres membres de ses
 * championnats dès leur saisie** (règle 4.3). Cet écran est l'endroit où cela
 * se voit, et c'est la base qui l'autorise, pas lui : la politique RLS de
 * l'étape 5 n'ouvre les pronostics d'autrui qu'aux membres d'un championnat
 * partagé. Un curieux qui devinerait un identifiant de profil obtient une liste
 * vide.
 *
 * Deux états par carte, et la distinction est la seule vraie règle de l'écran :
 *
 * - **Grand Prix non terminé** — les pronostics s'affichent avec ce qu'ils
 *   *peuvent* rapporter, sans aucun verdict. Rien n'est joué, afficher une
 *   croix rouge serait un mensonge.
 * - **Grand Prix terminé** — chaque pronostic porte son verdict et ses points
 *   gagnés, et la carte porte le total. Un pronostic qu'aucun validateur n'a su
 *   juger (`points_gagnes` nul, convention de l'étape 6) reste « en attente »
 *   au lieu d'être compté perdant : le marquer raté volerait le joueur en
 *   silence.
 *
 * **Écart assumé par rapport à la maquette 13** : elle montre aussi le podium
 * réel de la course, servi par `GET /grands-prix/{id}/resultats`. L'écran de
 * résultats d'un Grand Prix (maquette 11) n'est pas au programme de l'étape 8 —
 * il reste au « Reste à faire » du CLAUDE.md, avec le calendrier du
 * championnat — et le bloc n'est donc pas repris ici : mieux vaut ne pas le
 * dessiner que le remplir de rien.
 */

const ETIQUETTES = { vainqueur: "Obligatoire", podium: "Obligatoire", bonus: "Bonus" };

/** Pastille de verdict de la maquette 13 : coche verte, croix rouge, ou attente. */
function Verdict({ pointsGagnes }) {
  if (pointsGagnes === null) {
    return (
      <span
        aria-label="En attente de validation"
        className="bg-fond flex size-[26px] shrink-0 items-center justify-center rounded-full"
      >
        <IconeHorloge className="text-texte-doux size-3" />
      </span>
    );
  }

  const reussi = pointsGagnes > 0;
  return (
    <span
      aria-label={reussi ? "Pronostic réussi" : "Pronostic raté"}
      className={`flex size-[26px] shrink-0 items-center justify-center rounded-full ${
        reussi ? "bg-accent/20" : "bg-primaire/10"
      }`}
    >
      {reussi ? (
        <IconeCoche className="text-secondaire size-3 [stroke-width:3]" />
      ) : (
        <span aria-hidden="true" className="text-primaire text-[13px] font-medium">
          ×
        </span>
      )}
    </span>
  );
}

/** Une ligne de pronostic dans une carte de Grand Prix. */
function Ligne({ pronostic, termine }) {
  return (
    <li className="flex items-center justify-between gap-3 py-2.5">
      <span className="min-w-0">
        <span className="text-texte-doux block truncate text-[10px] font-medium tracking-[0.3px] uppercase">
          {pronostic.libelle}
        </span>
        <span className="text-texte mt-0.5 block truncate text-[14px] font-medium">
          {pronostic.choix ?? "Cote retirée par le bookmaker"}
        </span>
      </span>

      <span className="flex shrink-0 items-center gap-2">
        {/* Avant la course : ce que le pronostic peut rapporter. Après : ce
            qu'il a rapporté. Les deux ne s'affichent jamais ensemble — le
            joueur lirait deux nombres sans savoir lequel compte. */}
        <span
          className={`rounded-[10px] px-2.5 py-1.5 text-[13px] font-medium ${
            termine && pronostic.pointsGagnes > 0
              ? "bg-primaire text-white"
              : "bg-fond text-primaire"
          }`}
        >
          {termine && pronostic.pointsGagnes !== null
            ? formaterPoints(pronostic.pointsGagnes)
            : formaterPoints(pronostic.points)}
        </span>

        {!termine && (
          <span className="bg-accent/15 text-accent rounded-md px-1.5 py-0.5 text-[9px] font-medium">
            {ETIQUETTES[pronostic.type] ?? "Bonus"}
          </span>
        )}

        {termine && <Verdict pointsGagnes={pronostic.pointsGagnes} />}
      </span>
    </li>
  );
}

/** Une carte de Grand Prix : son en-tête, ses pronostics, son total. */
export function CarteGrandPrix({ gp }) {
  const depart = formaterDepart(gp.date_course);
  const attente = gp.pronostics.filter((p) => p.pointsGagnes === null).length;

  return (
    <div className="rounded-carte bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-corps text-texte truncate font-medium">{gp.nom}</p>
          <p className="text-texte-doux mt-0.5 text-[12px]">
            {gp.termine ? "Terminé" : "À venir"}
            {depart.courte ? ` · ${depart.courte}` : ""}
          </p>
        </div>

        {gp.termine && (
          <div className="shrink-0 text-right">
            <p className="text-primaire text-[22px] leading-none font-medium">
              {gp.total}
            </p>
            <p className="text-label-sm text-texte-doux mt-1 uppercase">pts</p>
          </div>
        )}
      </div>

      <div className="bg-fond my-2 h-px" />

      <ul>
        {gp.pronostics.map((pronostic) => (
          <Ligne key={pronostic.id} pronostic={pronostic} termine={gp.termine} />
        ))}
      </ul>

      {gp.termine && (
        <p className="text-texte-doux mt-1.5 text-[12px]">
          {gp.reussis} pronostic{gp.reussis > 1 ? "s" : ""} réussi
          {gp.reussis > 1 ? "s" : ""} sur {gp.juges}
          {attente > 0
            ? ` · ${attente} en attente de validation`
            : ""}
        </p>
      )}
    </div>
  );
}

function SqueletteGp() {
  return (
    <div className="flex flex-col gap-3">
      {[0, 1].map((rang) => (
        <div key={rang} className="rounded-carte bg-surface flex flex-col gap-3 p-4">
          <div className="bg-fond h-4 w-1/2 rounded-full" />
          {[0, 1, 2].map((ligne) => (
            <div key={ligne} className="flex items-center justify-between gap-3">
              <div className="bg-fond h-3.5 w-1/3 rounded-full" />
              <div className="bg-fond h-6 w-20 rounded-[10px]" />
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

export default function GrandsPrixDuMembre() {
  const { profilId } = useParams();
  const { utilisateur } = useAuth();

  const estMoi = utilisateur?.id === profilId;

  const cle = utilisateur ? cleMesGp(utilisateur.id, profilId) : null;
  const chargeur = useCallback(
    async (signal) => {
      // Le pseudo et les Grands Prix se chargent ensemble : l'en-tête doit
      // pouvoir dire de qui l'on regarde les pronostics dès la première image.
      const [profil, gps] = await Promise.all([
        chargerProfil(profilId, signal),
        chargerGrandsPrixDuMembre(profilId, signal),
      ]);
      if (!gps.ok) return gps;
      return {
        ok: true,
        message: null,
        donnees: {
          pseudo: profil.ok ? profil.donnees.pseudo : null,
          grandsPrix: gps.donnees,
        },
      };
    },
    [profilId],
  );
  const { donnees, chargement, erreur } = useDonnees(cle, chargeur);

  const pseudo = donnees?.pseudo ?? null;
  const grandsPrix = donnees?.grandsPrix ?? [];

  if (erreur && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Grands Prix" retourVers={-1} />
        </Bloc>
        <Bloc rang={2}>
          <Alerte ton="erreur">{erreur}</Alerte>
        </Bloc>
      </Ecran>
    );
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete
          titre={estMoi ? "Mes Grands Prix" : "Ses Grands Prix"}
          retourVers={-1}
          libelleRetour={pseudo ? `${pseudo} · Profil` : "Profil"}
          sousTitre="Saison 2026"
        />
      </Bloc>

      <div className="mt-1 flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteGp />}
          >
            {donnees && (
              <div className="flex flex-col gap-3">
                {grandsPrix.length === 0 ? (
                  <div className="rounded-bloc bg-surface px-5 py-9 text-center">
                    <p className="text-corps text-texte font-medium">
                      Aucun Grand Prix pour l'instant
                    </p>
                    <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                      {estMoi
                        ? "Tes pronostics apparaîtront ici, Grand Prix par Grand Prix."
                        : "Ce membre n'a encore pronostiqué sur aucun Grand Prix, ou tu ne partages aucun championnat avec lui."}
                    </p>
                  </div>
                ) : (
                  grandsPrix.map((gp) => <CarteGrandPrix key={gp.id} gp={gp} />)
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />
      </div>
    </Ecran>
  );
}
