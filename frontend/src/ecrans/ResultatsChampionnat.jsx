import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import Onglets from "../composants/Onglets.jsx";
import Pastille from "../composants/Pastille.jsx";
import Voiture from "../composants/Voiture.jsx";
import { Barre, Pave } from "../composants/Squelette.jsx";
import { IconeChevronAccordeon } from "../composants/Icones.jsx";
import { PastillePoints, Verdict } from "./ResultatsGp.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerCalendrier, cleCalendrier } from "../lib/calendrier.js";
import { chargerChampionnat } from "../lib/championnats.js";
import {
  chargerPronosticsChampionnat,
  choixDuPronostic,
} from "../lib/pronostics.js";
import { couleurChampionnat, tonalites } from "../lib/couleurs.js";
import { livreeDuMembre } from "../lib/palette.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterPoints } from "../lib/format.js";
import MentionProvisoire from "../composants/MentionProvisoire.jsx";
import { estProvisoire } from "../lib/resultats.js";

/**
 * Résultats par Grand Prix — qui a parié quoi, championnat par championnat.
 *
 * L'écran remplace l'entrée « Calendrier » de la vue d'un championnat. Ce que le
 * calendrier montrait — la saison, Grand Prix par Grand Prix, avec son état et
 * son bouton — est déjà l'onglet Calendrier de la barre basse ; ce que personne
 * ne montrait, c'est **ce que les autres ont joué**. C'est la seule chose qui ne
 * se lit nulle part ailleurs, et c'est ce que cet écran sert.
 *
 * > L'écran `Calendrier` d'un championnat reste en place et atteignable par son
 * > URL (`/championnats/:id/calendrier`) : c'est du code éprouvé qui redevient
 * > utile le jour où le mini-classement par Grand Prix est redemandé
 * > (`docs/composants.md` §6). Seule l'entrée depuis le championnat change.
 *
 * ## Deux chargements, et le second dépend du premier
 *
 * | Ce qui est lu | Par où | Pourquoi |
 * |---|---|---|
 * | La liste des Grands Prix | `GET /championnats/{id}/calendrier` | La même clé de cache que l'écran `Calendrier` : passer de l'un à l'autre n'attend rien |
 * | Les pronostics d'UN Grand Prix | `GET /grands-prix/{gp}/pronostics/championnat/{id}` | La route existe depuis l'étape 5 et sert exactement cette liste, membres sans pronostic compris |
 *
 * **La route sert un Grand Prix à la fois, et c'est ce qui dessine l'écran.**
 * Une saison entière demanderait vingt-quatre allers-retours Railway en série ;
 * le sélecteur du haut est donc la conséquence directe de la forme de la donnée,
 * pas un choix d'interface posé par-dessus.
 *
 * ## L'ordre de la liste est celui du Grand Prix regardé
 *
 * `classerParPointsDuGp` la retrie par `total_points` décroissant à chaque
 * changement d'option. La fonction SQL, elle, sert l'ordre d'inscription : juste
 * pour une liste de membres, muet sur un écran de résultats. **Le tri est fait
 * ici et pas en base** — la fonction est partagée avec d'autres appelants
 * (`resultats.py`), et lui imposer l'ordre d'un seul écran serait précisément la
 * source unique qu'on cherche à ne pas casser.
 *
 * ## Ce que le sélecteur réemploie
 *
 * `Onglets` — la piste blanche et la pastille bordeaux glissante de
 * transitions-dev 16, écrite pour les marchés de la maquette 08 et **restée non
 * montée** depuis (`docs/composants.md` §6). Elle répond exactement à la
 * question posée ici : un jeu d'options qui déborde la largeur d'un iPhone, dont
 * une seule est active, et qui ramène sous les yeux celle qu'on vient de choisir.
 * Aucun jeton de mouvement nouveau, aucune ligne de CSS ajoutée.
 *
 * ## Ce qui ne s'anime pas, et c'est délibéré
 *
 * **Le changement de Grand Prix ne fait aucun fondu.** La liste des membres ne
 * se transforme pas : elle est remplacée par une donnée qui arrive du réseau,
 * donc il n'y a pas d'« avant » à faire tenir — c'est le squelette qui occupe
 * l'intervalle, comme partout ailleurs dans l'app. Animer une substitution de
 * contenu asynchrone ajouterait du mouvement sans changement d'état, exactement
 * le verdict rendu sur l'en-tête de marché à la version `0.52.0`.
 */

/* -------------------------------------------------------------------------- */
/*  Le sélecteur de Grand Prix                                                */
/* -------------------------------------------------------------------------- */

/**
 * Le libellé court d'un Grand Prix dans le sélecteur.
 *
 * **Le préfixe « GP » saute, et lui seul.** Il est identique sur les
 * vingt-quatre options : il ne distingue rien et vole sa largeur au seul mot qui
 * distingue, dans un contrôle qui déborde déjà l'écran. Le nom du pays reste
 * entier — le raccourcir demanderait une table d'abréviations, donc une seconde
 * source de vérité sur des libellés qu'Unibet réécrit d'une semaine à l'autre.
 *
 * La date n'y figure pas : elle occuperait la moitié de chaque pastille pour
 * départager des noms qui ne se ressemblent pas, et l'en-tête de l'écran nomme
 * de toute façon le Grand Prix regardé en entier.
 */
export function libelleCourtGp(gp) {
  return String(gp.nom ?? "").replace(/^GP\s+/i, "").trim() || "Grand Prix";
}

/**
 * Le Grand Prix montré à l'arrivée sur l'écran.
 *
 * **Le dernier couru**, parce que c'est celui dont on vient de découvrir les
 * points et le seul sur lequel tous les pronostics sont jugés. À défaut le
 * premier dont les cotes sont en base — la saison n'a pas commencé, et un
 * Grand Prix sans cotes n'a de pronostics chez personne. À défaut le premier de
 * la liste, plutôt que rien : un écran qui s'ouvrirait sans sélection
 * demanderait un geste avant de montrer quoi que ce soit.
 *
 * La liste arrive triée par date croissante (`calendrier_du_championnat`), donc
 * « le dernier couru » est le dernier de ceux qui portent des résultats.
 */
export function gpParDefaut(grandsPrix) {
  const courus = grandsPrix.filter((gp) => gp.resultats_disponibles);
  if (courus.length > 0) return courus[courus.length - 1].gp_id;

  const avecCotes = grandsPrix.find((gp) => gp.cotes_disponibles);
  if (avecCotes) return avecCotes.gp_id;

  return grandsPrix[0]?.gp_id ?? null;
}

/**
 * Les membres, du meilleur au moins bon **sur ce Grand Prix-là**.
 *
 * La fonction SQL sert la liste par `rejoint_le`, l'ordre d'inscription — le
 * troisième critère de départage de la règle 4.6, et le seul ordre stable dont
 * elle dispose. C'est l'ordre juste pour une liste de membres ; ce n'est pas
 * celui d'un écran de résultats, où la première question est « qui a fait le
 * meilleur coup ce dimanche ? » et où la réponse se trouvait au hasard de la
 * colonne.
 *
 * > **Le tri porte sur les points du Grand Prix, jamais sur le classement
 * > général.** Les deux divergent — c'est même tout l'intérêt : un joueur dernier
 * > de la saison peut avoir signé le meilleur Grand Prix, et c'est précisément ce
 * > que cet écran existe pour montrer.
 *
 * **`null` n'est pas zéro, et il va derrière les deux.** Un membre dont rien
 * n'est encore jugé n'a pas marqué `0` : il n'a pas de score. Le placer parmi
 * les zéros dirait qu'il a raté ; le placer en tête dirait qu'il a gagné. Il
 * passe donc après, avec ceux qui n'ont rien joué — la même règle que la ligne
 * « Rien joué », qui est le cas extrême du même état.
 *
 * **À égalité, l'ordre du serveur est conservé** : le tri est stable (garanti par
 * la spécification depuis ES2019) et ne réordonne donc pas ce qu'il ne départage
 * pas. Avant la course, tout le monde est à `null` et la liste garde exactement
 * l'ordre d'inscription qu'elle avait — un `row_number` déguisé aurait inventé un
 * premier et un dernier là où personne n'a encore marqué (règle 4.7).
 */
export function classerParPointsDuGp(lignes) {
  const score = (ligne) =>
    ligne.total_points === null || ligne.total_points === undefined
      ? -1
      : ligne.total_points;
  return [...lignes].sort((a, b) => score(b) - score(a));
}

/* -------------------------------------------------------------------------- */
/*  Une rangée de membre                                                      */
/* -------------------------------------------------------------------------- */

/**
 * Un membre et le résumé de ses paris sur ce Grand Prix, dépliable.
 *
 * **Un membre sans pronostic n'est pas dépliable, et sa rangée le dit
 * directement.** Un chevron qui ouvrirait sur « rien » est une promesse fausse :
 * l'information « il n'a pas joué » est courte, elle tient sur la ligne, et
 * c'est justement celle qu'on vient chercher avant la fermeture des pronostics.
 * Cette rangée est donc un `<div>` et non un `<button>` — elle n'entre pas dans
 * l'ordre de tabulation, où elle ne mènerait nulle part.
 */
export function LigneMembrePronostics({ ligne, estMoi, avecPhotos = false }) {
  const [ouvert, setOuvert] = useState(false);

  const pronostics = ligne.pronostics ?? [];
  const aJoue = pronostics.length > 0;

  // « Ce que ça peut rapporter » tant que rien n'est jugé, « ce que ça a
  // rapporté » ensuite. `total_points` vaut `null` tant qu'aucun pronostic n'a
  // été noté : `null` et `0` ne se confondent jamais (règle 4.1), et un « 0 pt »
  // affiché avant la course annoncerait un échec qui n'a pas eu lieu.
  const juge = ligne.total_points !== null && ligne.total_points !== undefined;
  const potentiel = pronostics.reduce(
    (somme, pronostic) => somme + (pronostic.points ?? 0),
    0,
  );

  const identite = (
    <>
      {/* La vraie voiture du membre, livrée d'écurie et couleur de texte
          comprises : c'est à elle qu'on le reconnaît sur la piste, et les deux
          écrans doivent le montrer pareil. */}
      <Voiture
        {...livreeDuMembre(ligne)}
        numero={ligne.numero ?? ""}
        titre={`Voiture de ${ligne.pseudo}`}
        className="h-[34px] w-[17px] shrink-0"
      />

      {/* La colonne de pastilles n'apparaît que si quelqu'un, dans ce Grand
          Prix, a une photo — la règle des trois listes (`docs/composants.md`
          §8). Sans elle, un championnat où personne n'en a gagnerait une colonne
          d'initiales posées à côté du pseudo qu'elles abrègent. */}
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
          {aJoue
            ? `${pronostics.length} prono${pronostics.length > 1 ? "s" : ""} validé${
                pronostics.length > 1 ? "s" : ""
              }`
            : "Aucun prono sur ce Grand Prix"}
        </span>
      </span>
    </>
  );

  if (!aJoue) {
    return (
      <li className="flex min-h-tactile items-center gap-3 py-2">
        {identite}
        {/* Le mot est répété à droite, là où les autres rangées portent leur
            score : la colonne doit dire quelque chose sur toutes les lignes,
            sinon l'œil lit un score manquant plutôt qu'un joueur absent. */}
        <span className="text-texte-doux shrink-0 text-[13px]">Rien joué</span>
        {/* La place du chevron est tenue, pas le chevron : sans elle, le pseudo
            de cette rangée s'étendrait de seize pixels de plus que celui des
            autres et la colonne de gauche cesserait d'être une colonne. */}
        <span aria-hidden="true" className="size-4 shrink-0" />
      </li>
    );
  }

  return (
    <li className="t-acc" data-open={ouvert}>
      <button
        type="button"
        onClick={() => setOuvert((etat) => !etat)}
        aria-expanded={ouvert}
        className="pressable min-h-tactile flex w-full items-center gap-3 py-2 text-left"
      >
        {identite}

        {/* **Le total, et le mot qui dit lequel des deux c'est.** Avant la
            course, c'est ce que la saisie PEUT rapporter ; après, ce qu'elle a
            rapporté. Les deux sont des nombres de points du même ordre de
            grandeur, et rien ne les distinguerait sans ce qualificatif — un
            « 128 pts » lu comme un score sur un Grand Prix pas encore couru
            serait un classement inventé.

            Le nombre reste habillé par `formaterPoints`, seul propriétaire du
            « N pts » (règle 4.1) ; seul le qualificatif est écrit ici. */}
        <span className="shrink-0 text-right">
          <span className="text-primaire block text-[15px] leading-none font-medium">
            {formaterPoints(juge ? ligne.total_points : potentiel)}
          </span>
          <span className="text-label-sm text-texte-doux mt-1 block uppercase">
            {juge ? "gagnés" : "en jeu"}
          </span>
        </span>

        <IconeChevronAccordeon className="t-acc-chevron text-texte-doux size-4 shrink-0" />
      </button>

      <div className="t-acc-panel">
        <div className="t-acc-panel-inner">
          {/* Le décalage aligne la liste sur le pseudo, pas sur la voiture : les
              pronostics appartiennent à la personne nommée, et un dépli calé
              plus à gauche se lirait comme un second niveau de la liste. */}
          <ul className="mb-1 ml-8 flex flex-col">
            {pronostics.map((pronostic) => (
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
                  <PastillePoints
                    pointsGagnes={pronostic.points_gagnes}
                    points={pronostic.points}
                  />
                  <Verdict
                    pointsGagnes={pronostic.points_gagnes}
                    statut={pronostic.statut_evaluation}
                  />
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </li>
  );
}

/* -------------------------------------------------------------------------- */
/*  Squelettes                                                                */
/* -------------------------------------------------------------------------- */

/** La silhouette du sélecteur : une piste et trois pastilles de largeur
 *  plausible. Sans elle, le contenu remonterait de 52px à l'arrivée des
 *  Grands Prix, c'est-à-dire sous le doigt. */
function SqueletteSelecteur() {
  return (
    <div className="rounded-full bg-surface flex items-center gap-2 p-1">
      <Pave className="h-9 w-28" arrondi="rounded-full" />
      <Pave className="h-9 w-24" arrondi="rounded-full" />
      <Pave className="h-9 w-32" arrondi="rounded-full" />
    </div>
  );
}

function SqueletteMembres() {
  return (
    <div className="rounded-carte bg-surface shadow-carte flex flex-col gap-3 p-4">
      {[0, 1, 2, 3].map((rang) => (
        <div key={rang} className="flex items-center gap-3">
          <Pave className="h-[34px] w-[17px] shrink-0" arrondi="rounded-[4px]" />
          <div className="min-w-0 flex-1">
            <Barre largeur="w-24" />
            <Barre largeur="w-16" hauteur="h-2" className="mt-1.5" />
          </div>
          <Pave className="h-4 w-12 shrink-0" arrondi="rounded-full" />
        </div>
      ))}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  L'écran                                                                   */
/* -------------------------------------------------------------------------- */

export default function ResultatsChampionnat() {
  const { id } = useParams();
  const { utilisateur } = useAuth();

  const [tentative, setTentative] = useState(0);

  // ---- La saison, et le nom du championnat pour l'en-tête ------------------
  // Même clé que l'écran `Calendrier` : les deux lisent exactement la même
  // réponse, et une seconde clé aurait fait payer un réveil de Railway pour la
  // ressservir à l'identique.
  const cleSaison = utilisateur ? cleCalendrier(utilisateur.id, id) : null;
  const chargeurSaison = useCallback(
    async (signal) => {
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
          photo: championnat.ok ? championnat.donnees.photo_url : null,
          grandsPrix: gps.donnees,
        },
      };
    },
    [id],
  );
  const {
    donnees: saison,
    chargement: chargementSaison,
    echec: echecSaison,
    recharger: rechargerSaison,
  } = useDonnees(cleSaison, chargeurSaison);

  const grandsPrix = useMemo(() => saison?.grandsPrix ?? [], [saison]);

  // ---- Le Grand Prix regardé ----------------------------------------------
  // **Il se pose une fois et ne bouge plus.** La condition `précédent ?? …` n'est
  // pas défensive : le cache *stale-while-revalidate* rejoue ce chargeur en
  // arrière-plan, et sans elle un aller-retour Railway lent ramènerait le
  // sélecteur sur le Grand Prix par défaut pendant que le joueur en lit un
  // autre.
  const [gpChoisi, setGpChoisi] = useState(null);
  useEffect(() => {
    if (grandsPrix.length === 0) return;
    setGpChoisi((precedent) => precedent ?? gpParDefaut(grandsPrix));
  }, [grandsPrix]);

  // ---- Les pronostics du Grand Prix regardé -------------------------------
  // La clé porte le compte, le championnat ET le Grand Prix : changer d'option
  // change de clé, donc `useDonnees` ressert instantanément un Grand Prix déjà
  // consulté au lieu de le redemander. C'est ce qui rend le sélecteur agréable à
  // parcourir sur un réseau mobile.
  const clePronos =
    utilisateur && gpChoisi
      ? `pronos-gp:${utilisateur.id}:${id}:${gpChoisi}`
      : null;
  const chargeurPronos = useCallback(
    (signal) => chargerPronosticsChampionnat(gpChoisi, id, signal),
    [gpChoisi, id],
  );
  const {
    donnees: membres,
    chargement: chargementPronos,
    echec: echecPronos,
    recharger: rechargerPronos,
  } = useDonnees(clePronos, chargeurPronos);

  function reessayer() {
    setTentative((n) => n + 1);
    rechargerSaison();
    rechargerPronos();
  }

  const couleur = couleurChampionnat({ id, nom: saison?.nom });
  const teinte = {
    hex: couleur.hex,
    fond: couleur.fond,
    ton: tonalites(couleur.hex),
  };

  const options = grandsPrix.map((gp) => ({
    cle: gp.gp_id,
    libelle: libelleCourtGp(gp),
  }));
  const gpRegarde = grandsPrix.find((gp) => gp.gp_id === gpChoisi) ?? null;

  const lignes = classerParPointsDuGp(membres ?? []);
  // Une seule question pour toute la liste (`docs/composants.md` §8) : elle
  // décide de la PRÉSENCE de la colonne de pastilles, jamais de son contenu.
  const avecPhotos = lignes.some((ligne) => Boolean(ligne.avatar_url));
  const joueurs = lignes.filter(
    (ligne) => (ligne.pronostics ?? []).length > 0,
  ).length;

  // Sortie de secours : sans la saison, il n'y a rien à sélectionner, donc rien
  // à afficher. L'échec des pronostics, lui, n'emporte pas l'écran — le
  // sélecteur reste utilisable et c'est par lui qu'on réessaie.
  if (echecSaison && !saison) {
    return (
      <Ecran direction="avant">
        <EnTeteEcran
          titre="Résultats par Grand Prix"
          sousTitre="Saison 2026"
          retourVers={`/championnats/${id}`}
          libelleRetour="Championnat"
          teinte={teinte}
        />
        <Bloc rang={1} className="mt-3">
          <BlocErreur
            echec={echecSaison}
            onReessayer={reessayer}
            tentative={tentative}
          />
        </Bloc>
      </Ecran>
    );
  }

  return (
    <Ecran direction="avant">
      <EnTeteEcran
        titre="Résultats par Grand Prix"
        sousTitre={
          gpRegarde
            ? `${gpRegarde.nom} · ${joueurs} joueur${joueurs > 1 ? "s" : ""}`
            : "Saison 2026"
        }
        retourVers={`/championnats/${id}`}
        libelleRetour={saison?.nom ?? "Championnat"}
        teinte={teinte}
        photo={saison?.photo}
      />

      <div className="mt-3 flex flex-1 flex-col gap-3">
        <Bloc rang={1}>
          <ZoneChargement
            chargement={chargementSaison && !saison}
            squelette={<SqueletteSelecteur />}
          >
            {grandsPrix.length > 0 && gpChoisi && (
              <Onglets
                options={options}
                valeur={gpChoisi}
                onChange={setGpChoisi}
                etiquette="Choisir un Grand Prix"
              />
            )}
          </ZoneChargement>
        </Bloc>

        <Bloc rang={2}>
          {grandsPrix.length === 0 && !chargementSaison ? (
            /* Données manquantes, pas une erreur : le scraper n'a pas encore
               tourné, ou la saison n'a pas commencé. */
            <div className="rounded-bloc bg-surface shadow-bloc px-5 py-9 text-center">
              <p className="text-corps text-texte font-medium">
                Aucun Grand Prix au calendrier
              </p>
              <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                Les pronostics de tes amis apparaîtront ici dès que les cotes
                seront relevées, le samedi qui suit les qualifications.
              </p>
            </div>
          ) : (
            <ZoneChargement
              chargement={chargementPronos && !membres}
              squelette={<SqueletteMembres />}
            >
              {membres && (
                <div className="rounded-carte bg-surface shadow-carte p-4">
                  <div className="mb-1 flex items-baseline justify-between gap-3">
                    <p className="text-label text-texte-doux uppercase">
                      Les paris de chacun
                    </p>
                    {estProvisoire(gpRegarde?.statut_resultats) && <MentionProvisoire />}
                  </div>

                  {lignes.length === 0 ? (
                    <p className="text-corps-sm text-texte-doux py-2">
                      Ce championnat n'a aucun membre.
                    </p>
                  ) : (
                    <ul className="flex flex-col">
                      {lignes.map((ligne) => (
                        <LigneMembrePronostics
                          key={ligne.profil_id}
                          ligne={ligne}
                          estMoi={ligne.profil_id === utilisateur?.id}
                          avecPhotos={avecPhotos}
                        />
                      ))}
                    </ul>
                  )}

                  {/* Le mot qui manque quand personne n'a encore joué. Sans lui,
                      une liste de « Rien joué » se lirait comme une panne. */}
                  {lignes.length > 0 && joueurs === 0 && (
                    <p className="text-corps-sm text-secondaire mt-3">
                      Personne n'a encore pronostiqué sur ce Grand Prix.
                    </p>
                  )}
                </div>
              )}
            </ZoneChargement>
          )}
        </Bloc>

        {echecPronos && (
          <Bloc rang={3}>
            <BlocErreur
              echec={echecPronos}
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
