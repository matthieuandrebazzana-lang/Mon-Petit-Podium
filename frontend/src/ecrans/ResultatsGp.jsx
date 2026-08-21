import { useCallback, useState } from "react";
import { useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import Pastille from "../composants/Pastille.jsx";
import Voiture from "../composants/Voiture.jsx";
import { livreeDuMembre } from "../lib/palette.js";
import { Barre, Carte, Pave, Rangee } from "../composants/Squelette.jsx";
import {
  IconeChevronAccordeon,
  IconeCoche,
  IconeHorloge,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerResultatsGp,
  classerLesMembres,
  cleResultats,
  podiumDeLaCourse,
} from "../lib/calendrier.js";
import { useDonnees } from "../lib/useDonnees.js";
import {
  formaterDepart,
  formaterPilote,
  formaterPoints,
} from "../lib/format.js";

/**
 * Maquette 11 — les résultats d'un Grand Prix couru.
 *
 * **Deux blocs, deux régimes d'accès, et la frontière est celle de la route**
 * (`GET /grands-prix/{id}/resultats`, étape 6) :
 *
 * - le **classement de la course** est public. Un résultat de Formule 1 l'est
 *   partout ailleurs, et l'écran s'affiche sans session — c'est pour cela que sa
 *   route vit hors des groupes public et protégé de `App.jsx`, comme
 *   `/nouveau-mot-de-passe` ;
 * - le **classement du championnat** n'apparaît qu'avec un `championnat_id`,
 *   donc uniquement quand on arrive ici depuis un championnat dont on est
 *   membre. La route exige le jeton et vérifie l'appartenance ; l'écran ne
 *   décide rien, il affiche ce qu'on lui sert.
 *
 * **Un Grand Prix non couru n'est pas une erreur.** La route rend
 * `disponible: false` plutôt qu'un `404` (étape 6), et l'écran le dit avec la
 * date et l'heure du départ. Un écran vide laisserait croire à une panne.
 */

/* -------------------------------------------------------------------------- */
/*  Le classement de la course                                                */
/* -------------------------------------------------------------------------- */

/** Une marche du podium. Le vainqueur est au centre, comme dans la maquette. */
function Marche({ ligne, premier }) {
  const rang = premier ? "1er" : `${ligne.position}e`;

  return (
    <div
      className={`rounded-champ flex-1 px-2 py-2.5 text-center ${
        premier ? "bg-accent/15" : "bg-fond"
      }`}
    >
      <p
        className={`text-label-sm ${premier ? "text-accent" : "text-texte-doux"} uppercase`}
      >
        {premier ? `🏆 ${rang}` : rang}
      </p>
      <p className="text-texte mt-1 truncate text-[13px] font-medium">
        {ligne.pilote}
      </p>
      <p className="text-texte-doux mt-0.5 truncate text-[10px]">
        {ligne.equipe ?? "—"}
      </p>
    </div>
  );
}

/**
 * Une ligne du classement complet.
 *
 * `points_fia` est le seul nombre de l'application qui ne soit pas des points au
 * sens de la règle 4.1 : ce sont les points du championnat du monde (25, 18,
 * 15…). Il est donc écrit « 25 pts FIA » et jamais avec `formaterPoints`, qui
 * habille les points de l'app. Les confondre ferait lire le classement F1 comme
 * un classement de pronostics.
 */
function LignePilote({ ligne }) {
  const classe = ligne.position !== null && ligne.position !== undefined;

  return (
    <li className="flex items-center gap-3 py-2">
      <span
        className={`w-6 shrink-0 text-center text-[14px] font-medium ${
          ligne.position <= 3 && classe ? "text-primaire" : "text-texte-doux"
        }`}
      >
        {classe ? ligne.position : "—"}
      </span>

      <span className="min-w-0 flex-1">
        <span className="text-texte block truncate text-[14px] font-medium">
          {ligne.pilote}
        </span>
        <span className="text-texte-doux block truncate text-[11px]">
          {[ligne.equipe, ligne.abandon ? "Abandon" : null]
            .filter(Boolean)
            .join(" · ") || " "}
        </span>
      </span>

      {ligne.points_fia > 0 && (
        <span className="bg-fond text-secondaire rounded-[10px] px-2 py-1 text-[12px] font-medium">
          {ligne.points_fia} pts FIA
        </span>
      )}
    </li>
  );
}

/**
 * Le bloc de course : le podium en vedette, le classement complet replié.
 *
 * La maquette 11 ne montre que le podium ; la demande veut tout le classement.
 * Les deux tiennent parce que le reste est **replié dans un accordéon**
 * (transitions-dev 21, déjà installé) plutôt qu'étalé : vingt-deux lignes
 * posées d'emblée noieraient le podium, qui est ce qu'on vient lire en premier.
 */
function BlocCourse({ classement }) {
  const [ouvert, setOuvert] = useState(false);
  const podium = podiumDeLaCourse(classement);

  return (
    <div className="rounded-carte bg-surface shadow-carte t-acc p-4" data-open={ouvert}>
      <p className="text-label text-texte-doux mb-2.5 uppercase">
        Résultats de la course
      </p>

      {podium.length > 0 ? (
        <div className="flex items-end gap-2">
          {podium.map((ligne) => (
            <Marche
              key={ligne.driver_number ?? ligne.pilote}
              ligne={ligne}
              premier={ligne.position === 1}
            />
          ))}
        </div>
      ) : (
        <p className="text-corps-sm text-texte-doux">
          Le classement publié ne comporte encore aucune position.
        </p>
      )}

      <button
        type="button"
        onClick={() => setOuvert((etat) => !etat)}
        aria-expanded={ouvert}
        className="text-primaire min-h-tactile pressable -mb-2 mt-1 flex w-full items-center justify-center gap-1.5 text-[13px] font-medium"
      >
        {ouvert ? "Masquer le classement" : "Classement complet"}
        <IconeChevronAccordeon className="t-acc-chevron size-4" />
      </button>

      <div className="t-acc-panel">
        <div className="t-acc-panel-inner">
          <ul className="pt-1">
            {(classement ?? []).map((ligne) => (
              <LignePilote
                key={ligne.driver_number ?? `${ligne.position}-${ligne.pilote}`}
                ligne={ligne}
              />
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Le classement du championnat                                              */
/* -------------------------------------------------------------------------- */

/** Verdict d'un pronostic. Repris de la maquette 13, mêmes trois états. */
function Verdict({ pointsGagnes }) {
  if (pointsGagnes === null || pointsGagnes === undefined) {
    return (
      <span
        aria-label="En attente de validation"
        className="bg-fond flex size-[22px] shrink-0 items-center justify-center rounded-full"
      >
        <IconeHorloge className="text-texte-doux size-2.5" />
      </span>
    );
  }

  const reussi = pointsGagnes > 0;
  return (
    <span
      aria-label={reussi ? "Pronostic réussi" : "Pronostic raté"}
      className={`flex size-[22px] shrink-0 items-center justify-center rounded-full ${
        reussi ? "bg-accent/20" : "bg-primaire/10"
      }`}
    >
      {reussi ? (
        <IconeCoche className="text-secondaire size-2.5 [stroke-width:3]" />
      ) : (
        <span aria-hidden="true" className="text-primaire text-[12px] font-medium">
          ×
        </span>
      )}
    </span>
  );
}

/** Le pilote (ou les deux pilotes) sur lesquels porte un pronostic. */
function choixDuPronostic(pronostic) {
  if (pronostic.podium) {
    const deux = [pronostic.podium.nom_1, pronostic.podium.nom_2]
      .filter(Boolean)
      .map(formaterPilote);
    if (deux.length > 0) return deux.join(" + ");
  }
  return formaterPilote(pronostic.pilote) ?? "Cote retirée par le bookmaker";
}

/**
 * Une rangée de membre, dépliable sur ses pronostics.
 *
 * La maquette pose un chevron au bout de la ligne sans dire ce qu'il ouvre. Il
 * déplie ici les pronostics **sous** la ligne, comme le sélecteur de pilote de
 * l'étape 5 : le joueur garde le reste du classement sous les yeux, et le geste
 * de retour ne se fait pas voler par une couche qui s'interpose.
 */
function LigneMembre({ ligne, estMoi, avecPhotos = false }) {
  const [ouvert, setOuvert] = useState(false);

  return (
    <li className="t-acc" data-open={ouvert}>
      <button
        type="button"
        onClick={() => setOuvert((etat) => !etat)}
        aria-expanded={ouvert}
        className="pressable min-h-tactile flex w-full items-center gap-3 py-2 text-left"
      >
        <span
          className={`w-5 shrink-0 text-center text-[14px] font-medium ${
            ligne.rang <= 3 ? "text-primaire" : "text-texte-doux"
          }`}
        >
          {ligne.rang}
        </span>

        {/* La vraie voiture du membre (étape 8), servie par la route depuis
            l'étape 9, livrée d'écurie comprise. La largeur suit la boîte
            englobante du dessin : l'ancienne `viewBox` portait sa moitié en
            marge vide, et 28px n'en montraient que 14. */}
        <Voiture
          {...livreeDuMembre(ligne)}
          numero={ligne.numero ?? ""}
          titre={`Voiture de ${ligne.pseudo}`}
          className="h-[34px] w-[17px] shrink-0"
        />

        {/* La pastille d'identité, collée au pseudo. Elle est en `xs` — 28px —
            parce que cette rangée porte déjà cinq choses : un rang, une voiture,
            un nom, un score et un chevron. À 36px elle prendrait sa place sur le
            seul élément qui en manque, le pseudo.

            Même règle qu'au classement du championnat : la colonne n'apparaît
            que si quelqu'un, dans ce Grand Prix, a une photo — sinon la rangée
            reste exactement celle d'avant cette version. */}
        {avecPhotos && (
          <Pastille
            nom={ligne.pseudo}
            graine={ligne.profil_id}
            photo={ligne.avatar_url}
            taille="xs"
          />
        )}

        <span className="min-w-0 flex-1">
          <span className="text-texte block truncate text-[14px] font-medium">
            {ligne.pseudo}
            {estMoi && <span className="text-primaire"> · Toi</span>}
          </span>
          <span className="text-texte-doux block truncate text-[11px]">
            {ligne.aJoue
              ? `${ligne.reussis} réussi${ligne.reussis > 1 ? "s" : ""} sur ${ligne.juges}`
              : "Pas de pronostic sur ce GP"}
          </span>
        </span>

        <span className="text-primaire shrink-0 text-[15px] font-medium">
          {ligne.total === null || ligne.total === undefined
            ? "En attente"
            : formaterPoints(ligne.total)}
        </span>

        <IconeChevronAccordeon className="t-acc-chevron text-texte-doux size-4 shrink-0" />
      </button>

      <div className="t-acc-panel">
        <div className="t-acc-panel-inner">
          {ligne.aJoue ? (
            <ul className="mb-1 ml-8 flex flex-col">
              {ligne.pronostics.map((pronostic) => (
                <li
                  key={pronostic.id}
                  className="flex items-center justify-between gap-2 py-1.5"
                >
                  <span className="min-w-0">
                    <span className="text-texte-doux block truncate text-[10px] font-medium tracking-[0.3px] uppercase">
                      {pronostic.libelle ?? pronostic.type}
                    </span>
                    <span className="text-texte block truncate text-[13px]">
                      {choixDuPronostic(pronostic)}
                    </span>
                  </span>

                  <span className="flex shrink-0 items-center gap-2">
                    <span
                      className={`rounded-[10px] px-2 py-1 text-[12px] font-medium ${
                        pronostic.points_gagnes > 0
                          ? "bg-primaire text-white"
                          : "bg-fond text-primaire"
                      }`}
                    >
                      {/* Après la course, ce qu'il a rapporté ; tant qu'il n'est
                          pas jugé, ce qu'il pouvait rapporter. Les deux ne
                          s'affichent jamais ensemble. */}
                      {formaterPoints(
                        pronostic.points_gagnes ?? pronostic.points,
                      )}
                    </span>
                    <Verdict pointsGagnes={pronostic.points_gagnes} />
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-texte-doux mb-1 ml-8 py-1.5 text-[13px]">
              Ce membre n'a rien pronostiqué sur ce Grand Prix.
            </p>
          )}
        </div>
      </div>
    </li>
  );
}

/* -------------------------------------------------------------------------- */
/*  Squelette                                                                 */
/* -------------------------------------------------------------------------- */

function SqueletteResultats() {
  return (
    <div className="flex flex-col gap-3">
      {/* Le bloc rouge garde sa couleur : c'est la surface, pas le contenu, et
          la voir changer au moment de la révélation ferait clignoter l'écran. */}
      <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-3 p-5">
        <div className="flex-1">
          <div className="h-2.5 w-24 rounded-full bg-white/25" />
          <div className="mt-3 h-9 w-20 rounded-champ bg-white/25" />
          <div className="mt-2.5 h-2.5 w-32 rounded-full bg-white/20" />
        </div>
        <div className="h-14 w-16 rounded-champ bg-white/15" />
      </div>

      <Carte>
        <Barre largeur="w-2/5" hauteur="h-2.5" />
        <div className="mt-3 flex items-end gap-2">
          <Pave className="h-[68px] flex-1" />
          <Pave className="h-[68px] flex-1" />
          <Pave className="h-[68px] flex-1" />
        </div>
      </Carte>

      <Carte>
        {[0, 1, 2, 3].map((rang) => (
          <Rangee key={rang} />
        ))}
      </Carte>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  L'écran                                                                   */
/* -------------------------------------------------------------------------- */

export default function ResultatsGp() {
  const { id: championnatId, gpId } = useParams();
  const { utilisateur } = useAuth();

  const [tentative, setTentative] = useState(0);

  const cle = utilisateur
    ? cleResultats(utilisateur.id, gpId, championnatId)
    : null;
  const chargeur = useCallback(
    (signal) => chargerResultatsGp(gpId, championnatId, signal),
    [gpId, championnatId],
  );
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const gp = donnees?.grand_prix ?? null;
  const depart = formaterDepart(gp?.date_course);
  const retour = championnatId ? `/championnats/${championnatId}` : "/accueil";

  const membres = classerLesMembres(donnees?.membres);
  // Une seule question pour toute la liste, la même qu'au classement du
  // championnat et qu'à la vue piste : quelqu'un a-t-il une photo ?
  const avecPhotos = membres.some((ligne) => Boolean(ligne.avatar_url));
  const moi = membres.find((ligne) => ligne.profil_id === utilisateur?.id) ?? null;

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  // Sortie de secours : sans résultats lisibles, l'écran ne doit surtout pas
  // être un cul-de-sac. Le cache déjà servi l'emporte sur l'échec.
  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Résultats" retourVers={retour} />
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
          titre={gp?.nom ?? "Résultats"}
          retourVers={retour}
          libelleRetour={championnatId ? "Championnat" : "Accueil"}
          sousTitre={
            gp
              ? [
                  donnees?.disponible ? "Terminé" : "À venir",
                  depart.courte,
                ]
                  .filter(Boolean)
                  .join(" · ")
              : null
          }
        />
      </Bloc>

      <div className="mt-1 flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteResultats />}
          >
            {donnees && (
              <div className="flex flex-col gap-3">
                {!donnees.disponible ? (
                  /* Données manquantes, pas une erreur : la course n'a pas
                     encore de classement publié. Le message dit quand revenir
                     plutôt que de laisser l'écran vide. */
                  <div className="rounded-bloc bg-primaire shadow-bloc p-5">
                    <p className="text-label-sm uppercase text-white/60">
                      Résultats
                    </p>
                    <p className="mt-2 text-[20px] font-medium text-white">
                      Résultats pas encore disponibles
                    </p>
                    <p className="text-corps-sm mt-1.5 text-white/60">
                      {depart.heure
                        ? `Départ ${depart.jour.toLowerCase()} à ${depart.heure}. Les points sont attribués dans les deux heures qui suivent.`
                        : "L'horaire de la course n'est pas encore annoncé. Les points sont attribués dans les deux heures qui suivent le départ."}
                    </p>
                  </div>
                ) : (
                  <>
                    {/* Bloc rouge de la maquette : mes points sur ce GP. Il
                        n'existe que si l'on regarde depuis un championnat —
                        sans championnat, personne n'est « moi » ici. */}
                    {moi && (
                      <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-3 p-5">
                        <div className="min-w-0">
                          <p className="text-label-sm uppercase text-white/60">
                            Mes points ce GP
                          </p>
                          <p className="text-score-lg mt-1.5 text-white">
                            {moi.total ?? "—"}
                          </p>
                          <p className="mt-1 text-[11px] text-white/50">
                            {moi.aJoue
                              ? `${moi.reussis} prono${moi.reussis > 1 ? "s" : ""} réussi${moi.reussis > 1 ? "s" : ""} sur ${moi.pronostics.length}`
                              : "Aucun pronostic sur ce Grand Prix"}
                          </p>
                        </div>

                        <div className="rounded-champ shrink-0 bg-white/15 px-4 py-2.5 text-center">
                          <p className="text-[26px] leading-none font-medium text-white">
                            {moi.rang}
                            <span className="text-[15px]">e</span>
                          </p>
                          <p className="text-label-sm mt-1 text-white/50 uppercase">
                            ce GP
                          </p>
                        </div>
                      </div>
                    )}

                    <BlocCourse classement={donnees.classement} />

                    {donnees.membres === null || donnees.membres === undefined ? (
                      /* Arrivé ici sans championnat : la partie publique est
                         servie, et on dit pourquoi le reste manque plutôt que
                         de laisser croire que le championnat est vide. */
                      <div className="rounded-carte bg-surface shadow-carte px-5 py-6 text-center">
                        <p className="text-corps text-texte font-medium">
                          Les pronostics de tes amis
                        </p>
                        <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                          Ouvre ce Grand Prix depuis un championnat pour voir ce
                          que chaque membre y a marqué.
                        </p>
                      </div>
                    ) : (
                      <>
                        <p className="text-label text-texte-doux px-1 uppercase">
                          Classement ce GP
                        </p>
                        <div className="rounded-carte bg-surface shadow-carte px-4 py-2">
                          <ul>
                            {membres.map((ligne) => (
                              <LigneMembre
                                key={ligne.profil_id}
                                ligne={ligne}
                                estMoi={ligne.profil_id === utilisateur?.id}
                                avecPhotos={avecPhotos}
                              />
                            ))}
                          </ul>
                        </div>
                      </>
                    )}
                  </>
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        {/* Un échec survenu alors que le cache avait déjà quelque chose : le
            contenu reste, l'échec s'ajoute dessous avec son bouton. */}
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
