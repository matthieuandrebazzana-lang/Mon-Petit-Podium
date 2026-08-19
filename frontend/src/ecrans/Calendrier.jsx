import { useCallback, useState } from "react";
import { Link, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import TraceCircuitGp, {
  aUnTrace,
  nomCircuit,
  paysDuCircuit,
  slugCircuit,
} from "../composants/TracesCircuits.jsx";
import {
  APPARENCE_REPLI,
  FondDrapeau,
  VoileDrapeau,
  drapeauDuGp,
} from "../composants/DrapeauxGP.jsx";
import { Barre, Pave } from "../composants/Squelette.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { ETATS_GP, chargerCalendrier, cleCalendrier } from "../lib/calendrier.js";
import { chargerChampionnat } from "../lib/championnats.js";
import { useDonnees } from "../lib/useDonnees.js";
import {
  etatFermeture,
  formaterJourMois,
  formaterPoints,
} from "../lib/format.js";

/**
 * Maquette 15 — le calendrier d'un championnat, Grand Prix par Grand Prix.
 *
 * **Le vocabulaire de la section 1 s'applique et la maquette y déroge** : son
 * titre est « Historique », et le CLAUDE.md interdit ce mot au profit de
 * **calendrier**. L'écran, la route et l'onglet disent donc « Calendrier ».
 *
 * Chaque Grand Prix est une **carte pleine largeur** en deux zones : le drapeau
 * du pays hôte et le tracé du circuit en haut, les informations en bas. Le
 * fichier de référence est `assets/calendrier.svg`, qui dessine les douze
 * widgets de la fin de saison avec leur pays, leur circuit et leur date.
 *
 * La carte reprend **exactement le mécanisme de couleur du bloc de l'accueil** :
 * même clé (`slugCircuit`), même table de drapeaux, même voile calculé, même
 * surcouche uniforme. Un Grand Prix se reconnaît donc à ses couleurs d'un écran
 * à l'autre, ce qui n'arriverait pas si le calendrier se peignait tout seul.
 */

/** Hauteur de la zone du drapeau. Écrite une fois : le squelette la reprend,
 *  sans quoi la liste sauterait de 180px par carte à l'arrivée des données. */
const HAUTEUR_DRAPEAU = 180;

/* -------------------------------------------------------------------------- */
/*  L'état d'un Grand Prix                                                    */
/* -------------------------------------------------------------------------- */

/**
 * Les quatre états d'un Grand Prix, et la pastille qui les dit.
 *
 * **Ils ne se déduisent jamais du seul statut en base** (voir la migration
 * `20260814213000`) : rien ne fait passer un GP en `cotes_figees` avant le
 * samedi des qualifications, et le job de résultats passe un GP à `termine`
 * même s'il reste des pronostics sans points. La disponibilité des cotes et
 * celle des résultats sont donc lues dans leurs tables, et la fermeture se
 * calcule sur l'heure de départ (règle 4.3).
 *
 * L'ordre des tests compte : un Grand Prix couru est « terminé » quoi qu'il
 * arrive, et une fermeture passée l'emporte sur des cotes disponibles.
 *
 * **Le mot et la couleur ne sont pas écrits ici** mais dans `ETATS_GP`
 * (`lib/calendrier.js`), partagés avec le calendrier de la saison. Les deux
 * écrans n'ont pas les mêmes données pour décider de l'état ; ils doivent en
 * revanche le dire de la même façon.
 */
export function etatDuGp(gp, maintenant = Date.now()) {
  if (gp.resultats_disponibles) return ETATS_GP.termine;

  const { ferme } = etatFermeture(gp.date_course, maintenant);
  if (ferme) return ETATS_GP.ferme;
  if (gp.cotes_disponibles) return ETATS_GP.ouvert;
  return ETATS_GP.a_venir;
}

/* -------------------------------------------------------------------------- */
/*  Une carte de Grand Prix                                                   */
/* -------------------------------------------------------------------------- */

export function CarteGrandPrix({ gp }) {
  const etat = etatDuGp(gp);
  const date = formaterJourMois(gp.date_course);

  // Le pays hôte donne à la fois les couleurs de la carte et le tracé du
  // circuit. Une seule normalisation du nom pour les deux : ils partagent la
  // même clé, et la faire deux fois laisserait les deux tables se
  // désynchroniser sur un libellé qu'Unibet aurait renommé.
  const slug = slugCircuit(gp.nom);
  const drapeau = drapeauDuGp(slug) ?? APPARENCE_REPLI;
  const trace = aUnTrace(slug);
  const circuit = nomCircuit(slug);
  const pays = paysDuCircuit(slug, gp.nom);

  // Le bouton n'existe que là où il y a quelque chose à faire. Un Grand Prix à
  // venir n'a pas encore de cotes ; un Grand Prix fermé n'accepte plus rien.
  //
  // **« Pronostiquer » exige en plus des cotes figées.** C'est la même règle que
  // sur le calendrier de la saison et sur le bloc de l'accueil, et elle est
  // écrite ici aussi parce que les deux calendriers n'ont pas les mêmes données
  // pour décider de l'état — mais doivent proposer le même geste. Sans elle, un
  // Grand Prix en `a_venir` dont quelques cotes traînent en base ouvrirait un
  // tableau que le scraper n'a pas encore arrêté.
  const action =
    etat.cle === "termine"
      ? {
          vers: `/grands-prix/${gp.gp_id}/resultats`,
          libelle: "Voir les résultats",
          // Consultation : le bordeaux sur le beige du fond, pas un aplat
          // plein. Douze cartes terminées feraient sinon douze barres rouges,
          // et l'urgence ne se distinguerait plus de l'archive.
          style: "bg-fond text-primaire",
        }
      : etat.cle === "ouvert" && gp.statut === "cotes_figees"
        ? {
            vers: `/grands-prix/${gp.gp_id}/cotes`,
            libelle: "Pronostiquer",
            style: "bg-primaire text-white",
          }
        : null;

  return (
    <article className="pleine-largeur rounded-bloc bg-surface shadow-carte overflow-hidden">
      {/* ------------------------------------------------------------------
          Zone haute — le drapeau et le tracé.

          La pile de calques est celle du bloc de l'accueil, dans le même
          ordre : lumière spéculaire, voile calculé du drapeau, surcouche
          uniforme de 15 %, puis le tracé.

          **Les 15 % demandés ne suffisent pas seuls, et c'est mesuré.** Sur la
          bande blanche d'un drapeau néerlandais, un trait blanc à 60 % posé
          sur du blanc à peine assombri reste invisible. Le voile calculé par
          drapeau (version `0.15.0`) est donc conservé dessous : il ramène cette
          bande au gris moyen, et le trait y tient alors le même 2,70:1 que sur
          l'accueil. Aucun texte ne traverse cette zone, la garantie de 3:1 de
          l'accueil n'a donc rien à protéger ici.
          ------------------------------------------------------------------ */}
      <div
        className={`relative ${drapeau.fond ? "" : "bg-primaire"}`}
        style={{
          height: `${HAUTEUR_DRAPEAU}px`,
          ...(drapeau.fond ? { background: drapeau.fond } : {}),
        }}
      >
        {/* Le drapeau dessiné, calque le plus bas : le voile et
            l'assombrissement le recouvrent, jamais l'inverse. */}
        <FondDrapeau apparence={drapeau} />
        <div
          aria-hidden="true"
          className="lueur-haute pointer-events-none absolute inset-0"
        />
        <VoileDrapeau voile={drapeau.voile} />
        {drapeau.fond && (
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 bg-black/15"
          />
        )}

        {/* `boiteLibre` coupe le rapport de forme que le composant pose en
            ligne : la bande fixe ici les deux dimensions, et c'est le travail
            de `xMidYMid meet` de mettre chaque circuit à l'échelle dedans.
            Bakou, 3,4 fois plus large que haut, remplit la largeur ;
            Zandvoort, presque carré, remplit la hauteur. Chacun garde sa vraie
            forme au lieu d'être étiré pour occuper la même surface.

            Sans tracé, la zone reste le drapeau seul : un motif de repli
            laisserait croire que ce Grand Prix se court sur cette forme-là. */}
        {trace && (
          <TraceCircuitGp
            slug={slug}
            epaisseur={3}
            boiteLibre
            className="pointer-events-none absolute inset-0 h-full w-full px-6 py-5 text-white/60"
          />
        )}
      </div>

      {/* ------------------------------------------------------------------
          Zone basse — les informations, en deux colonnes.
          ------------------------------------------------------------------ */}
      <div className="p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            {/* Le pays n'apparaît que lorsqu'il ajoute quelque chose : « GP
                Pays Bas » se court aux Pays-Bas, et l'écrire deux fois sur la
                même carte serait du bruit. Restent les deux Grands Prix
                américains, où il est une vraie information. */}
            {pays && (
              <p className="text-texte-doux truncate text-[11px]">{pays}</p>
            )}
            <h2 className="text-texte truncate text-[18px] font-medium">
              {gp.nom}
            </h2>
            {circuit && (
              <p className="text-texte-doux mt-0.5 truncate text-[11px]">
                {circuit}
              </p>
            )}
            <span
              className={`rounded-[10px] mt-2 inline-block px-2.5 py-1 text-[11px] font-medium ${etat.pastille}`}
            >
              {etat.libelle}
            </span>
          </div>

          <div className="shrink-0 text-right">
            {date ? (
              <>
                <p className="text-primaire text-[32px] leading-none font-medium tracking-[-0.025em]">
                  {date.jour}
                </p>
                <p className="text-texte-doux text-label-sm mt-1">{date.mois}</p>
              </>
            ) : (
              /* Unibet publie parfois un Grand Prix avant d'en annoncer
                 l'horaire. Aucun chiffre n'est inventé : la colonne le dit. */
              <p className="text-texte-doux max-w-[9ch] text-[11px] leading-snug">
                Date à confirmer
              </p>
            )}

            {/* Mon score sur ce Grand Prix, sous la date. `mes_points` vaut
                `null` tant qu'aucun de mes pronostics n'a été noté : « en
                attente » et « zéro » ne se disent pas pareil (convention de
                l'étape 6). */}
            {etat.cle === "termine" && (
              <p className="text-texte-doux mt-2.5 text-[11px] leading-snug">
                {gp.mes_points !== null && gp.mes_points !== undefined ? (
                  <>
                    <span className="text-primaire block text-[15px] font-medium">
                      {formaterPoints(gp.mes_points)}
                    </span>
                    {gp.mon_rang ? `${gp.mon_rang}e de ce GP` : null}
                  </>
                ) : gp.mes_pronostics > 0 ? (
                  "Pronos pas encore validés"
                ) : (
                  "Aucun prono"
                )}
              </p>
            )}
          </div>
        </div>

        {action && (
          <Link
            to={action.vers}
            className={`rounded-carte-sm pressable min-h-tactile mt-4 flex w-full items-center justify-center px-5 py-3.5 text-center text-[15px] font-medium ${action.style}`}
          >
            {action.libelle}
          </Link>
        )}
      </div>
    </article>
  );
}

/* -------------------------------------------------------------------------- */
/*  Squelette                                                                 */
/* -------------------------------------------------------------------------- */

/**
 * La silhouette de la liste. Elle suit la carte à la hauteur près : sans les
 * 180px de la zone du drapeau, l'écran sauterait à l'arrivée des données.
 *
 * La zone du drapeau y est **grise et non colorée**, contrairement aux aplats de
 * couleur des autres squelettes de l'app : on ne sait pas encore quel pays
 * arrive, et le gris est la seule réponse honnête. C'est le même arbitrage que
 * pour les cartes de championnat de l'accueil.
 */
function SqueletteCalendrier() {
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-3 p-4.5">
        <div className="flex-1">
          <div className="h-2.5 w-24 rounded-full bg-white/25" />
          <div className="mt-2.5 h-4 w-28 rounded-full bg-white/25" />
          <div className="mt-2 h-2.5 w-20 rounded-full bg-white/20" />
        </div>
        <div className="rounded-champ h-10 w-12 bg-white/15" />
      </div>

      {[0, 1].map((rang) => (
        <div
          key={rang}
          className="pleine-largeur rounded-bloc bg-surface shadow-carte overflow-hidden"
        >
          <Pave
            arrondi="rounded-none"
            className="w-full"
            style={{ height: `${HAUTEUR_DRAPEAU}px` }}
          />
          <div className="flex items-start justify-between gap-3 p-4">
            <div className="min-w-0 flex-1">
              <Barre largeur="w-2/5" />
              <Barre largeur="w-1/4" hauteur="h-2.5" className="mt-2" />
              <Pave className="mt-3 h-6 w-24" arrondi="rounded-[10px]" />
            </div>
            <Pave className="h-11 w-12 shrink-0" />
          </div>
        </div>
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
                  <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-3 p-4.5">
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
                  <div className="rounded-bloc bg-surface shadow-bloc px-5 py-9 text-center">
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
                    <CarteGrandPrix key={gp.gp_id} gp={gp} />
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
