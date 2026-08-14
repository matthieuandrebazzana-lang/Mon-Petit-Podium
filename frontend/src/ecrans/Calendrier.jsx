import { useCallback, useState } from "react";
import { Link, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import Pastille from "../composants/Pastille.jsx";
import TraceCircuit, { traceDuGrandPrix } from "../composants/TraceCircuit.jsx";
import { Barre, Carte, Pave } from "../composants/Squelette.jsx";
import { IconeChevronDroit } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerCalendrier, cleCalendrier } from "../lib/calendrier.js";
import { chargerChampionnat } from "../lib/championnats.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";
import { couleurLisible } from "../lib/palette.js";

/**
 * Maquette 15 — le calendrier d'un championnat, Grand Prix par Grand Prix.
 *
 * **Le vocabulaire de la section 1 s'applique et la maquette y déroge** : son
 * titre est « Historique », et le CLAUDE.md interdit ce mot au profit de
 * **calendrier**. L'écran, la route et l'onglet disent donc « Calendrier ». Le
 * contenu ne change pas pour autant : ce sont bien les Grands Prix passés et à
 * venir de la saison, dans l'ordre.
 *
 * **Trois états par carte**, et ils ne se déduisent jamais du seul statut du
 * Grand Prix (voir la migration `20260814213000`) :
 *
 * - **terminé** — `resultats_disponibles`. La carte porte le vainqueur de la
 *   course, le mini-classement du championnat et mène aux résultats ;
 * - **cotes disponibles** — `cotes_disponibles`. La carte mène au tableau des
 *   cotes ;
 * - **à venir** — ni l'un ni l'autre. La carte reste sobre et ne mène nulle
 *   part : il n'y a rien à y faire tant que le scraper n'a pas tourné.
 *
 * Un statut ne suffirait pas : rien ne fait passer un GP en `cotes_figees`
 * aujourd'hui, et le job de résultats passe un GP à `termine` même s'il reste
 * des pronostics sans points.
 */

/* -------------------------------------------------------------------------- */
/*  États visuels                                                             */
/* -------------------------------------------------------------------------- */

/**
 * L'état d'un Grand Prix, et la couleur qui le dit.
 *
 * **Écart assumé sur les couleurs demandées.** La demande veut « à venir
 * (gris), cotes disponibles (amber), terminé (vert) ». Le gris et l'amber sont
 * ceux du design system (`texte-doux`, `accent`). Le **vert n'existe pas dans
 * la section 5** et la palette n'est pas négociable : « terminé » prend donc le
 * bordeaux `primaire`, qui est déjà la couleur des points et des scores dans
 * toute l'application — un Grand Prix terminé est précisément celui qui en a
 * rapporté. La distinction reste franche entre les trois états, ce qui est ce
 * que la demande cherchait.
 */
function etatDuGp(gp) {
  if (gp.resultats_disponibles) {
    return {
      cle: "termine",
      libelle: "Terminé",
      pastille: "bg-primaire/10 text-primaire",
      trace: "text-primaire/30",
    };
  }
  if (gp.cotes_disponibles) {
    return {
      cle: "cotes",
      libelle: "Cotes dispo",
      pastille: "bg-accent/20 text-secondaire",
      trace: "text-accent/40",
    };
  }
  return {
    cle: "a_venir",
    libelle: "À venir",
    pastille: "bg-fond text-texte-doux",
    trace: "text-texte-doux/25",
  };
}

/* -------------------------------------------------------------------------- */
/*  Une carte de Grand Prix                                                   */
/* -------------------------------------------------------------------------- */

/** Une ligne du mini-classement de la maquette : rang, pastille, pseudo, points. */
function MiniLigne({ ligne, estMoi }) {
  return (
    <li className="flex items-center gap-2.5 py-1.5">
      <span
        className={`w-4 shrink-0 text-center text-[13px] font-medium ${
          ligne.rang <= 2 ? "text-primaire" : "text-texte-doux"
        }`}
      >
        {ligne.rang}
      </span>
      <Pastille
        nom={ligne.pseudo}
        graine={ligne.profil_id}
        taille="sm"
        couleur={couleurLisible(ligne)}
      />
      <span className="text-texte min-w-0 flex-1 truncate text-[13px] font-medium">
        {ligne.pseudo}
      </span>
      <span className="text-primaire shrink-0 text-[13px] font-medium">
        {formaterPoints(ligne.points)}
      </span>
      {/* Le point ambré de la maquette : il repère l'utilisateur dans la liste
          sans écrire son pseudo deux fois. */}
      {estMoi && (
        <span
          aria-label="Toi"
          className="bg-accent size-1.5 shrink-0 rounded-full"
        />
      )}
    </li>
  );
}

export function CarteGrandPrix({ gp, championnatId, profilId }) {
  const etat = etatDuGp(gp);
  const depart = formaterDepart(gp.date_course);

  // Le tracé de circuit, extrait de `assets/gp-cards.svg`. La planche n'en
  // contient que deux (Monza et Spa) : tous les autres Grands Prix reçoivent le
  // tracé générique, ce qui garde la même silhouette d'une carte à l'autre.
  const trace = traceDuGrandPrix(gp.nom);

  const destination = gp.resultats_disponibles
    ? `/championnats/${championnatId}/grands-prix/${gp.gp_id}/resultats`
    : gp.cotes_disponibles
      ? `/grands-prix/${gp.gp_id}/cotes`
      : null;

  const entete = (
    <div className="flex items-start gap-3">
      {/* Le tracé est décoratif : il porte `aria-hidden` et n'entre pas dans le
          nom accessible de la carte, qui est déjà celui du Grand Prix. */}
      <span
        className={`bg-fond rounded-champ flex size-11 shrink-0 items-center justify-center ${etat.trace}`}
      >
        <TraceCircuit trace={trace} className="h-5 w-8" />
      </span>

      <span className="min-w-0 flex-1">
        <span className="text-corps text-texte block truncate font-medium">
          {gp.nom}
        </span>
        <span className="text-texte-doux mt-0.5 block truncate text-[11px]">
          {depart.courte ?? "Date à confirmer"}
          {gp.vainqueur ? ` · ${gp.vainqueur}` : ""}
        </span>
      </span>

      <span
        className={`rounded-[10px] shrink-0 px-2.5 py-1 text-[11px] font-medium ${etat.pastille}`}
      >
        {etat.libelle}
      </span>
    </div>
  );

  return (
    <div className="rounded-carte bg-surface overflow-hidden">
      <div className="p-4">{entete}</div>

      {/* Mini-classement : seulement pour un Grand Prix couru. Avant la course,
          tout le monde est à zéro et la liste ne dirait rien. */}
      {gp.resultats_disponibles && gp.classement.length > 0 && (
        <div className="px-4">
          <div className="bg-fond h-px" />
          <ul className="py-1">
            {gp.classement.map((ligne) => (
              <MiniLigne
                key={ligne.profil_id}
                ligne={ligne}
                estMoi={ligne.profil_id === profilId}
              />
            ))}
          </ul>
        </div>
      )}

      {/* Mon score sur ce GP. `mes_points` vaut `null` tant qu'aucun de mes
          pronostics n'a été noté : « en attente » et « zéro » ne se disent pas
          pareil (convention de l'étape 6). */}
      {gp.resultats_disponibles && (
        <div className="text-texte-doux px-4 pb-1 text-[11px]">
          {gp.mes_points !== null && gp.mes_points !== undefined
            ? `Toi : ${formaterPoints(gp.mes_points)}${gp.mon_rang ? ` · ${gp.mon_rang}e de ce GP` : ""}`
            : gp.mes_pronostics > 0
              ? "Tes pronostics ne sont pas encore validés."
              : "Tu n'as rien pronostiqué sur ce Grand Prix."}
        </div>
      )}

      {destination && (
        <Link
          to={destination}
          className="pressable min-h-tactile text-primaire flex items-center justify-center gap-1.5 px-4 py-3 text-[14px] font-medium"
        >
          {gp.resultats_disponibles ? "Résultats" : "Pronostiquer"}
          <IconeChevronDroit className="size-3.5" />
        </Link>
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Squelette                                                                 */
/* -------------------------------------------------------------------------- */

function SqueletteCalendrier() {
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-bloc bg-primaire flex items-center justify-between gap-3 p-4.5">
        <div className="flex-1">
          <div className="h-2.5 w-24 rounded-full bg-white/25" />
          <div className="mt-2.5 h-4 w-28 rounded-full bg-white/25" />
          <div className="mt-2 h-2.5 w-20 rounded-full bg-white/20" />
        </div>
        <div className="h-10 w-12 rounded-champ bg-white/15" />
      </div>

      {[0, 1, 2].map((rang) => (
        <Carte key={rang}>
          <div className="flex items-start gap-3">
            <Pave className="size-11 shrink-0" />
            <div className="min-w-0 flex-1">
              <Barre largeur="w-2/5" />
              <Barre largeur="w-3/5" hauteur="h-2.5" className="mt-2" />
            </div>
            <Pave className="h-6 w-16 shrink-0" arrondi="rounded-[10px]" />
          </div>
        </Carte>
      ))}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  L'écran                                                                   */
/* -------------------------------------------------------------------------- */

export default function Calendrier() {
  const { id } = useParams();
  const { utilisateur } = useAuth();

  const [tentative, setTentative] = useState(0);

  const cle = utilisateur ? cleCalendrier(utilisateur.id, id) : null;
  const chargeur = useCallback(
    async (signal) => {
      // Le nom du championnat et son calendrier arrivent ensemble : l'en-tête
      // doit pouvoir dire d'où l'on vient dès la première image. Le nom se lit
      // directement dans Supabase sous RLS (étape 3), le calendrier par l'API.
      const [championnat, gps] = await Promise.all([
        chargerChampionnat(id, signal),
        chargerCalendrier(id, signal),
      ]);
      if (!gps.ok) return gps;
      return {
        ok: true,
        message: null,
        donnees: {
          nom: championnat.ok ? championnat.donnees.nom : null,
          grandsPrix: gps.donnees,
        },
      };
    },
    [id],
  );
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const grandsPrix = donnees?.grandsPrix ?? [];
  const courus = grandsPrix.filter((gp) => gp.resultats_disponibles);

  // Le bloc rouge de la maquette : le leader du championnat sur la saison. Il
  // s'additionne ici plutôt que d'appeler le classement de l'étape 7 — l'écran
  // a déjà, Grand Prix par Grand Prix, tout ce qu'il faut pour le calculer, et
  // un second aller-retour Railway pour trois nombres serait un réveil de plus.
  const cumul = new Map();
  for (const gp of courus) {
    for (const ligne of gp.classement) {
      const total = cumul.get(ligne.profil_id) ?? {
        pseudo: ligne.pseudo,
        points: 0,
      };
      total.points += ligne.points;
      cumul.set(ligne.profil_id, total);
    }
  }
  const leader = [...cumul.values()].sort((a, b) => b.points - a.points)[0] ?? null;

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Calendrier" retourVers={`/championnats/${id}`} />
        </Bloc>
        <Bloc rang={2}>
          <BlocErreur echec={echec} onReessayer={reessayer} tentative={tentative} />
        </Bloc>
      </Ecran>
    );
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete
          titre="Calendrier"
          retourVers={`/championnats/${id}`}
          libelleRetour={donnees?.nom ?? "Championnat"}
          sousTitre={`Saison 2026 · ${courus.length} GP terminé${courus.length > 1 ? "s" : ""}`}
        />
      </Bloc>

      <div className="mt-1 flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteCalendrier />}
          >
            {donnees && (
              <div className="flex flex-col gap-3">
                {/* Le bloc « leader général » n'apparaît qu'une fois un Grand
                    Prix couru : avant, il annoncerait un leader à zéro point,
                    ce qui est un classement inventé. */}
                {leader && (
                  <div className="rounded-bloc bg-primaire flex items-center justify-between gap-3 p-4.5">
                    <div className="min-w-0">
                      <p className="text-label-sm uppercase text-white/60">
                        Leader général
                      </p>
                      <p className="mt-1 truncate text-[18px] font-medium text-white">
                        🏆 {leader.pseudo}
                      </p>
                      <p className="mt-0.5 text-[13px] text-white/60">
                        {formaterPoints(leader.points)} cumulés
                      </p>
                    </div>
                    <div className="shrink-0 text-right">
                      <p className="text-[11px] text-white/50">GP joués</p>
                      <p className="text-[24px] font-medium text-white">
                        {courus.length}
                      </p>
                    </div>
                  </div>
                )}

                {grandsPrix.length === 0 ? (
                  /* Données manquantes, pas une erreur : le scraper n'a pas
                     encore tourné, ou la saison n'a pas commencé. */
                  <div className="rounded-bloc bg-surface px-5 py-9 text-center">
                    <p className="text-corps text-texte font-medium">
                      Aucun Grand Prix au calendrier
                    </p>
                    <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                      Les Grands Prix apparaissent ici dès que les cotes sont
                      relevées, le samedi qui suit les qualifications.
                    </p>
                  </div>
                ) : (
                  grandsPrix.map((gp) => (
                    <CarteGrandPrix
                      key={gp.gp_id}
                      gp={gp}
                      championnatId={id}
                      profilId={utilisateur?.id}
                    />
                  ))
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        {echec && donnees && (
          <Bloc rang={3}>
            <BlocErreur
              echec={echec}
              onReessayer={reessayer}
              tentative={tentative}
            />
          </Bloc>
        )}

        <div className="min-h-3 flex-1" />
      </div>
    </Ecran>
  );
}
