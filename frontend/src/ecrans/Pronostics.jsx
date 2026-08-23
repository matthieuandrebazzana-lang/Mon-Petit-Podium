import { useCallback, useEffect, useMemo, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import { Pave } from "../composants/Squelette.jsx";
import Compteur from "../composants/Compteur.jsx";
import Horloge from "../composants/Horloge.jsx";
import {
  IconeChevronAccordeon,
  IconeCoche,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { couleurBloc, tonalites } from "../lib/couleurs.js";
import {
  BONUS_MAXIMUM,
  bonusEpingles,
  MARCHE_PODIUM,
  MARCHE_VAINQUEUR,
  chargerSaisie,
  enregistrerPronostics,
  enConflit,
  indexerCotes,
  marcheDe,
  optionsDisponibles,
  organiserPronostics,
  oublierMesPronostics,
} from "../lib/pronostics.js";
import { oublierCache, useDonnees } from "../lib/useDonnees.js";
import {
  formaterDepart,
  formaterPilote,
  formaterPoints,
} from "../lib/format.js";
import { origineRetour } from "../lib/navigation.js";
import { useFermeture } from "../lib/useFermeture.js";

// Les trois aplats de l'écran, et leurs encres, calculés une fois pour toutes :
// ils ne dépendent d'aucune donnée. Les recalculer à chaque rendu ne coûterait
// pas cher, mais les écrire ici dit clairement qu'ils sont fixes.
const COULEUR_VAINQUEUR = couleurBloc("rouge");
const COULEUR_PODIUM = couleurBloc("bleu-ardoise");
const COULEUR_BONUS = couleurBloc("amber");

/**
 * Le titre du bloc podium, et pourquoi il n'est plus celui du bookmaker.
 *
 * Unibet intitule son marché « Podium », et l'écran servait ce libellé tel
 * quel. Il était trompeur : le vainqueur est déjà sur le podium, et un bloc
 * « Podium » posé sous un bloc « Vainqueur » se lit comme s'il fallait y
 * remettre les trois places — dont la première, déjà jouée juste au-dessus.
 * Les deux emplacements sont en réalité les **deuxième et troisième** de la
 * course.
 *
 * C'est le seul libellé de marché que l'écran réécrit, et le seul qu'il peut
 * réécrire sans risque : `MARCHE_PODIUM` est une constante partagée avec le
 * backend (règle 4.2), donc ce bloc-là ne peut désigner que ce marché-là. Les
 * autres marchés continuent d'afficher le nom du bookmaker, seule source
 * légitime du nom d'un marché découvert dynamiquement.
 */
const TITRE_PODIUM = "2e et 3e du podium";
const tonVainqueur = tonalites(COULEUR_VAINQUEUR.hex);
const tonPodium = tonalites(COULEUR_PODIUM.hex);
const tonBonus = tonalites(COULEUR_BONUS.hex);

function SqueletteSaisie() {
  return (
    <div className="flex flex-col gap-3">
      {/* Les blocs gardent leurs aplats de couleur : c'est la surface, pas le
          contenu, et les voir virer au gris puis revenir ferait clignoter
          l'écran au lieu de le remplir. */}
      {/* L'horloge, à sa silhouette réelle : la carte beige, son label centré et
          ses trois tuiles à leur hauteur. Sans elle, l'écran sauterait d'une
          centaine de pixels à l'arrivée des données — le défaut déjà corrigé
          sur les cartes de championnat en version `0.14.0`. Les tuiles gardent
          leur aplat sombre, comme les blocs de couleur ci-dessous : seul leur
          contenu est grisé. */}
      <div className="rounded-bloc bg-fond shadow-bloc p-5">
        <div className="bg-squelette mx-auto h-2.5 w-28 rounded-full" />
        <div className="mt-3 flex items-start justify-center gap-2.5">
          {[0, 1, 2].map((rang) => (
            <div
              key={rang}
              className="bg-texte shadow-carte rounded-widget flex flex-1 flex-col items-center gap-2 py-4"
            >
              <div className="h-[48px] w-12 rounded-lg bg-white/15" />
              <div className="h-2 w-12 rounded-full bg-white/15" />
            </div>
          ))}
        </div>
      </div>

      <div className="rounded-carte bg-primaire shadow-carte p-4">
        <div className="h-3 w-24 rounded-full bg-white/25" />
        <div className="rounded-champ mt-3 h-[50px] bg-white/15" />
      </div>
      <div className="rounded-carte bg-bleu-ardoise shadow-carte p-4">
        <div className="h-3 w-20 rounded-full bg-white/25" />
        <div className="rounded-champ mt-3 h-[50px] bg-white/15" />
        <div className="rounded-champ mt-2 h-[50px] bg-white/15" />
      </div>
      <Pave className="h-[62px]" arrondi="rounded-carte" />
    </div>
  );
}

/**
 * Le compte à rebours, en horloge à trois tuiles.
 *
 * Il tenait jusqu'ici sur une ligne d'un aplat rouge — « 2j 14h 32min »,
 * tronqué au besoin —, ce qui demandait de lire une phrase pour en extraire
 * trois nombres. Les tuiles les posent chacun sous son unité : c'est le même
 * arbitrage qu'au bloc d'accueil et à l'écran récapitulatif, et c'est
 * désormais **la même composition**, partagée (`composants/Horloge.jsx`).
 *
 * **La carte prend le beige du fond**, pas le blanc des autres cartes : sur une
 * surface blanche, trois aplats presque noirs se découpent comme des trous. Sur
 * le beige ils se lisent comme des objets posés, et c'est `shadow-bloc` qui dit
 * alors que la carte est une carte. Même traitement qu'au récapitulatif.
 *
 * **Sans secondes** : cet écran est celui où l'on compose ses pronostics, on y
 * vient savoir s'il reste du temps. Le récapitulatif, lui, garde le glissement
 * vers les secondes — c'est l'écran où l'on revient vérifier juste avant la
 * fermeture.
 */
function BlocFermeture({ etat }) {
  return (
    <div className="rounded-bloc bg-fond shadow-bloc p-5">
      <Horloge etat={etat} taille="grande" avecSecondes={false} />
    </div>
  );
}

/**
 * Un emplacement à remplir, qui déplie la liste des cotes du marché
 * (transitions-dev 21).
 *
 * L'accordéon plutôt qu'une feuille modale : la liste tient sous
 * l'emplacement, le joueur garde ses autres choix sous les yeux, et le geste
 * de retour ne se fait pas voler par une couche qui s'interpose.
 */
function Emplacement({
  choisi,
  options,
  onChoisir,
  ouvert,
  onBasculer,
  ton,
  couleur,
  verrouille,
}) {
  // Le choix, ou son absence, dit toujours la même chose au même endroit : la
  // valeur à gauche, les points à droite.
  //
  // **Les deux emplacements du podium ne sont plus numérotés.** Ils portaient
  // une pastille « 1er » et « 2e », qui désignaient leur rang dans le bloc et
  // non dans la course — alors qu'ils valent les 2e et 3e places. Les numéroter
  // laissait croire à un ordre à respecter, que le schéma de l'étape 5 exclut
  // explicitement : il n'y a **aucun ordre** entre `pilote_1` et `pilote_2`, et
  // la validation de l'étape 6 demande « ces deux pilotes sont-ils sur le
  // podium ? », jamais « lequel devant ». Rien ne les distingue donc, et rien
  // ne doit prétendre le contraire.
  const valeur = (
    <span className="flex min-w-0 flex-1 items-center gap-2">
      <span
        className={`min-w-0 flex-1 truncate text-[15px] ${
          choisi ? `font-medium ${ton.texte}` : ton.texteDoux
        }`}
      >
        {choisi ? formaterPilote(choisi.pilote) : "Non sélectionné"}
      </span>
    </span>
  );

  if (verrouille) {
    return (
      <div
        className={`rounded-champ flex items-center justify-between gap-3 px-4 py-3.5 ${ton.surface}`}
      >
        {valeur}
        {choisi && (
          <span className={`shrink-0 text-[13px] ${ton.texteDoux}`}>
            {formaterPoints(choisi.points)}
          </span>
        )}
      </div>
    );
  }

  return (
    <div className="t-acc" data-open={ouvert ? "true" : "false"}>
      <button
        type="button"
        onClick={onBasculer}
        aria-expanded={ouvert}
        className={`rounded-champ pressable min-h-tactile flex w-full items-center justify-between gap-3 px-4 py-3.5 text-left ${
          choisi ? ton.surfaceForte : ton.surface
        }`}
      >
        {valeur}
        <span className="flex shrink-0 items-center gap-2.5">
          {choisi && (
            <span className={`text-[13px] ${ton.texteDoux}`}>
              {formaterPoints(choisi.points)}
            </span>
          )}
          <span className="t-acc-chevron">
            <IconeChevronAccordeon className={`size-4 ${ton.texteDoux}`} />
          </span>
        </span>
      </button>

      <div className="t-acc-panel">
        <div className="t-acc-panel-inner">
          <ul className="flex flex-col gap-1.5 pt-1.5">
            {options.map((option) => {
              const actif = choisi?.id === option.id;
              return (
                <li key={option.id}>
                  {/* Le pilote retenu passe en négatif — surface pleine, texte
                      à la couleur du bloc. C'est le seul contraste franc
                      disponible à l'intérieur d'un aplat déjà coloré. */}
                  <button
                    type="button"
                    onClick={() => onChoisir(option)}
                    aria-pressed={actif}
                    style={actif ? { color: couleur.hex } : undefined}
                    className={`rounded-champ pressable min-h-tactile flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left ${
                      actif ? "bg-surface" : `${ton.surface} ${ton.texte}`
                    }`}
                  >
                    <span className="min-w-0 flex-1 truncate text-[14px] font-medium">
                      {formaterPilote(option.pilote)}
                    </span>
                    <span
                      className={`shrink-0 text-[12px] font-medium ${
                        actif ? "" : ton.texteDoux
                      }`}
                    >
                      {formaterPoints(option.points)}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </div>
  );
}

/**
 * Bloc d'un marché obligatoire, désormais en aplat de couleur : rouge pour le
 * vainqueur, bleu ardoise pour le podium. Les deux pronostics que la règle 4.2
 * impose se distinguent ainsi au premier coup d'œil des bonus facultatifs, qui
 * sont ambre et plus petits.
 */
function BlocObligatoire({ titre, couleur, ton, children }) {
  return (
    <div
      className={`rounded-carte shadow-aplat relative overflow-hidden ${couleur.fond}`}
    >
      <span
        aria-hidden="true"
        className="lueur-haute pointer-events-none absolute inset-0"
      />
      <div className="relative flex flex-col gap-2.5 p-4">
        <div className="flex items-center justify-between gap-2">
          {/* Deux lignes, même règle qu'au tableau des cotes : le titre est
              celui d'Unibet, et tronqué il ne nomme plus son marché. Le bloc
              n'a pas de hauteur fixe — c'est le `flex-col gap-2.5` qui tient
              l'écart avec les emplacements en dessous, quelle que soit la
              hauteur prise ici. */}
          <p
            className={`line-clamp-2 min-w-0 leading-[1.25] break-words text-[12px] font-medium tracking-[0.5px] uppercase ${ton.texte}`}
          >
            {titre}
          </p>
          <span
            className={`shrink-0 rounded-lg px-2 py-0.5 text-[10px] font-medium ${ton.surfaceForte} ${ton.texte}`}
          >
            Obligatoire
          </span>
        </div>
        {children}
      </div>
    </div>
  );
}

/** Maquette 09 — saisie et modification des pronostics. */
export default function Pronostics() {
  const { gpId } = useParams();
  const naviguer = useNavigate();
  const { state } = useLocation();
  const { utilisateur } = useAuth();

  // Le tableau des cotes est la destination hiérarchique : on y choisit ses
  // favoris avant de saisir. Un appelant peut la remplacer par `retour`.
  const retour = origineRetour(state, {
    vers: `/grands-prix/${gpId}/cotes`,
    libelle: "Les cotes",
  });
  // Ce que le tableau des cotes nous a confié de sa propre origine : on le lui
  // rend en repartant, pour que son bouton de retour ramène toujours au même
  // endroit qu'à l'aller.
  const origine = origineRetour(
    { retour: state?.origine },
    { vers: null, libelle: null },
  ).vers;

  const cle = utilisateur ? `saisie:${utilisateur.id}:${gpId}` : null;
  const chargeur = useCallback(
    (signal) => chargerSaisie(gpId, utilisateur?.id, signal),
    [gpId, utilisateur?.id],
  );
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayerChargement() {
    setTentativeChargement((n) => n + 1);
    recharger();
  }

  const gp = donnees?.gp ?? null;
  const index = useMemo(() => indexerCotes(gp), [gp]);
  const marcheVainqueur = useMemo(() => marcheDe(gp, MARCHE_VAINQUEUR), [gp]);
  const marchePodium = useMemo(() => marcheDe(gp, MARCHE_PODIUM), [gp]);

  const [vainqueur, setVainqueur] = useState(null);
  const [podium, setPodium] = useState([null, null]);
  const [bonus, setBonus] = useState([]);
  const [ouvert, setOuvert] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  const [erreurEnvoi, setErreurEnvoi] = useState(null);
  const [tentative, setTentative] = useState(0);
  const [prerempli, setPrerempli] = useState(false);

  const etat = useFermeture(gp?.date_course);

  // Préremplissage depuis les pronostics déjà enregistrés, une seule fois : un
  // rafraîchissement en arrière-plan ne doit pas écraser une saisie en cours.
  useEffect(() => {
    if (prerempli || !donnees) return;
    const organises = organiserPronostics(donnees.pronostics, index);
    if (!organises.vide) {
      setVainqueur(organises.vainqueur?.outcome ?? null);
      setPodium([
        organises.podium[0]?.outcome ?? null,
        organises.podium[1]?.outcome ?? null,
      ]);
      setBonus(organises.bonus.map((choix) => choix.outcome));
    }
    setPrerempli(true);
  }, [donnees, index, prerempli]);

  const favoris = donnees?.favoris ?? [];
  const cote = (id) => (id ? (index.get(id) ?? null) : null);

  // Le compteur, la saturation et l'envoi ne comptent que les bonus **encore
  // épinglés** : un bonus enregistré dont la cote a été dépunaisée depuis
  // n'occupe aucune des trois places. La règle et sa raison vivent dans
  // `lib/pronostics.js`, avec la fonction qui la porte.
  const bonusRetenus = useMemo(
    () => bonusEpingles(bonus, favoris),
    [bonus, favoris],
  );

  function choisirVainqueur(option) {
    setVainqueur(option.id);
    setOuvert(null);
    setErreurEnvoi(null);
  }

  function choisirPodium(place, option) {
    setPodium((actuel) => {
      const suivant = [...actuel];
      suivant[place] = option.id;
      return suivant;
    });
    setOuvert(null);
    setErreurEnvoi(null);
  }

  function basculerBonus(idOutcome) {
    setErreurEnvoi(null);
    setBonus((actuel) => {
      if (actuel.includes(idOutcome)) {
        return actuel.filter((choix) => choix !== idOutcome);
      }
      // Le maximum est une limite, pas un quota : au-delà, l'appui ne fait
      // rien plutôt que de remplacer en douce un bonus déjà choisi. Il se
      // compte sur les seuls bonus **encore épinglés**, pour la même raison que
      // le compteur : un bonus orphelin ne remplit aucune des trois places, il
      // ne peut donc pas en bloquer une.
      if (bonusEpingles(actuel, favoris).length >= BONUS_MAXIMUM) return actuel;
      return [...actuel, idOutcome];
    });
  }

  /* ------------------------------------------------------------------------
     Exclusion croisée — un pilote déjà pris ailleurs ne se propose plus.

     La règle et sa raison vivent dans `lib/pronostics.js`, avec les deux
     fonctions qui la portent : c'est du rapprochement de données, et l'écran
     n'a plus qu'à dire *quelles* places s'excluent.

     L'exclusion est **réactive et non destructive** : elle se recalcule à
     chaque rendu, si bien que changer de vainqueur rend aussitôt l'ancien aux
     listes du podium et en retire le nouveau, sans toucher aux sélections déjà
     faites. Une sélection devenue conflictuelle n'est pas effacée en silence —
     elle reste affichée et c'est `conflits` qui la signale à la validation.
     Vider un choix que le joueur a fait, sans rien dire, serait pire que le lui
     montrer.
     ------------------------------------------------------------------------ */
  const prisesAilleurs = (place) => [cote(vainqueur), cote(podium[1 - place])];

  const optionsPodium = (place) =>
    optionsDisponibles(
      marchePodium?.cotes ?? [],
      prisesAilleurs(place),
      podium[place],
    );

  const conflits = [0, 1].some((place) =>
    enConflit(cote(podium[place]), prisesAilleurs(place)),
  );

  async function valider() {
    setErreurEnvoi(null);

    if (!vainqueur) {
      setTentative((n) => n + 1);
      setErreurEnvoi("Choisis d'abord ton vainqueur.");
      return;
    }
    if (!podium[0] || !podium[1]) {
      setTentative((n) => n + 1);
      setErreurEnvoi("Le podium demande deux pilotes.");
      return;
    }
    // Le joueur a changé de vainqueur après avoir rempli son podium. La base
    // refuserait de toute façon deux fois le même pilote ; le dire ici évite
    // l'aller-retour et nomme le geste à faire.
    if (conflits) {
      setTentative((n) => n + 1);
      setErreurEnvoi(
        "Ton vainqueur est déjà sur le podium : choisis deux autres pilotes.",
      );
      return;
    }

    setEnvoi(true);
    const resultat = await enregistrerPronostics(gpId, {
      vainqueur,
      podium: { pilote_1: podium[0], pilote_2: podium[1] },
      bonus: bonusRetenus,
    });
    setEnvoi(false);

    if (!resultat.ok) {
      setTentative((n) => n + 1);
      setErreurEnvoi(resultat.message);
      return;
    }

    if (cle) oublierCache(cle);
    if (utilisateur) {
      oublierCache(`recap:${utilisateur.id}:${gpId}`);
      // **Les quatre surfaces qui décident de leur libellé sur l'existence de
      // ces pronostics**, oubliées ensemble : l'accueil, les deux calendriers et
      // l'écran des paris de chacun. Sans cet oubli, un retour immédiat y
      // trouverait encore « Pronostiquer » le temps du rafraîchissement, juste
      // après une validation — le défaut que la version `0.53.0` vient de
      // corriger, réintroduit par le cache. Une seule fonction pour les quatre
      // (`lib/pronostics.js`) : écrits séparément, l'un d'eux aurait fini par
      // être oublié.
      oublierMesPronostics(utilisateur.id);
    }
    naviguer(`/grands-prix/${gpId}/recap`, { state: { enregistre: true } });
  }

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <EnTeteEcran
          titre="Mes pronos"
          retourVers={retour.vers}
          libelleRetour={retour.libelle}
          retourEtat={origine ? { retour: origine } : null}
        />
        <Bloc rang={1} className="mt-3">
          <BlocErreur
            echec={echec}
            onReessayer={reessayerChargement}
            tentative={tentativeChargement}
          />
        </Bloc>
      </Ecran>
    );
  }

  const depart = formaterDepart(gp?.date_course);
  const marchesManquants = gp && (!marcheVainqueur || !marchePodium);

  // Ce que la saisie en cours rapporterait si tout tombait. Même règle qu'au
  // récapitulatif : chaque pronostic compte pour sa cote, et le podium pour la
  // somme de ses deux pilotes (règle tranchée à l'étape 6). Il est affiché dans
  // la barre collée plutôt qu'en fin de page — c'est le chiffre qui fait
  // changer d'avis, il doit bouger sous les yeux au moment du choix.
  const potentiel = [vainqueur, ...podium, ...bonusRetenus]
    .map((id) => cote(id)?.points ?? 0)
    .reduce((total, points) => total + points, 0);

  return (
    <Ecran direction="avant">
      <EnTeteEcran
        titre="Mes pronos"
        retourVers={retour.vers}
        libelleRetour={gp?.nom ?? retour.libelle}
        retourEtat={origine ? { retour: origine } : null}
        sousTitre={
          gp
            ? depart.heure
              ? `${depart.jour} · Départ ${depart.heure}`
              : depart.jour
            : null
        }
      />

      <div className="mt-3 flex flex-1 flex-col gap-3">
        <Bloc rang={1}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteSaisie />}
          >
            {gp && (
              <div className="flex flex-col gap-3">
                <BlocFermeture etat={etat} />

                {etat.ferme && (
                  <p className="rounded-carte bg-surface shadow-carte text-texte-doux text-corps-sm px-4 py-3">
                    Le départ est imminent : les pronostics sont figés et ne
                    peuvent plus être modifiés.
                  </p>
                )}

                {marchesManquants ? (
                  <div className="rounded-carte bg-surface shadow-carte px-5 py-8 text-center">
                    <p className="text-corps text-texte font-medium">
                      Pronostics indisponibles
                    </p>
                    <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                      Les marchés « Vainqueur » et « Podium » ne sont pas encore
                      ouverts chez le bookmaker pour ce Grand Prix.
                    </p>
                  </div>
                ) : (
                  <>
                    <p className="text-label text-texte-doux px-1 uppercase">
                      Obligatoires
                    </p>

                    <BlocObligatoire
                      titre={marcheVainqueur.libelle}
                      couleur={COULEUR_VAINQUEUR}
                      ton={tonVainqueur}
                    >
                      <Emplacement
                        choisi={cote(vainqueur)}
                        options={marcheVainqueur.cotes}
                        onChoisir={choisirVainqueur}
                        ouvert={ouvert === "vainqueur"}
                        onBasculer={() =>
                          setOuvert(ouvert === "vainqueur" ? null : "vainqueur")
                        }
                        couleur={COULEUR_VAINQUEUR}
                        ton={tonVainqueur}
                        verrouille={etat.ferme}
                      />
                    </BlocObligatoire>

                    <BlocObligatoire
                      titre={TITRE_PODIUM}
                      couleur={COULEUR_PODIUM}
                      ton={tonPodium}
                    >
                      {[0, 1].map((place) => (
                        <Emplacement
                          key={place}
                          choisi={cote(podium[place])}
                          options={optionsPodium(place)}
                          onChoisir={(option) => choisirPodium(place, option)}
                          ouvert={ouvert === `podium-${place}`}
                          onBasculer={() =>
                            setOuvert(
                              ouvert === `podium-${place}` ? null : `podium-${place}`,
                            )
                          }
                          couleur={COULEUR_PODIUM}
                          ton={tonPodium}
                          verrouille={etat.ferme}
                        />
                      ))}
                    </BlocObligatoire>

                    <div className="mt-1 flex items-end justify-between gap-3 px-1">
                      <p className="text-label text-texte-doux uppercase">
                        Bonus — mes favoris
                      </p>
                      <p className="text-texte-doux text-[12px]">
                        <Compteur
                          valeur={bonusRetenus.length}
                          className="text-primaire font-medium"
                        />{" "}
                        sur {BONUS_MAXIMUM} max
                      </p>
                    </div>

                    {favoris.length === 0 ? (
                      <div className="rounded-carte bg-surface shadow-carte px-5 py-7 text-center">
                        <p className="text-corps text-texte font-medium">
                          Aucun favori pour l'instant
                        </p>
                        <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                          Les bonus se choisissent parmi les cotes que tu as
                          épinglées dans le tableau des cotes.
                        </p>
                      </div>
                    ) : (
                      // Chaque bonus est son propre bloc, ambre une fois retenu
                      // et blanc tant qu'il ne l'est pas. La demande décrit les
                      // « 3 bonus dans des blocs amber » : c'est donc la
                      // sélection que l'ambre désigne, sinon une liste de vingt
                      // favoris serait un mur ambre où plus rien ne se
                      // distingue. L'encre reste `#1A1A1A` sur l'ambre, comme
                      // demandé, et pour la raison que la demande donne
                      // elle-même : le blanc y tombe à 2,2:1 de contraste.
                      <div className="flex flex-col gap-2">
                        {favoris.map((favori) => {
                          const actif = bonusRetenus.includes(
                            favori.id_outcome_unibet,
                          );
                          const sature =
                            !actif && bonusRetenus.length >= BONUS_MAXIMUM;
                          return (
                            <button
                              key={favori.id_outcome_unibet}
                              type="button"
                              onClick={() => basculerBonus(favori.id_outcome_unibet)}
                              disabled={etat.ferme || sature}
                              aria-pressed={actif}
                              className={`rounded-carte-sm shadow-carte pressable min-h-tactile flex w-full items-center justify-between gap-3 px-4 py-3 text-left ${
                                actif ? COULEUR_BONUS.fond : "bg-surface"
                              } ${sature ? "opacity-50" : ""}`}
                            >
                              <span className="min-w-0">
                                <span
                                  className={`block truncate text-[10px] font-medium tracking-[0.4px] uppercase ${
                                    actif ? tonBonus.texteDoux : "text-texte-doux"
                                  }`}
                                >
                                  {favori.libelle ?? "Cote retirée"}
                                </span>
                                <span
                                  className={`mt-0.5 block truncate text-[14px] font-medium ${
                                    actif ? tonBonus.texte : "text-texte"
                                  }`}
                                >
                                  {formaterPilote(favori.pilote) ??
                                    favori.id_outcome_unibet}
                                </span>
                              </span>

                              <span className="flex shrink-0 items-center gap-2">
                                <span
                                  className={`rounded-lg px-2 py-1 text-[12px] font-medium ${
                                    actif
                                      ? `${tonBonus.surfaceForte} ${tonBonus.texte}`
                                      : "bg-fond text-texte"
                                  }`}
                                >
                                  {formaterPoints(favori.points)}
                                </span>
                                <span
                                  aria-hidden="true"
                                  className={`flex size-[22px] items-center justify-center rounded-full ${
                                    actif
                                      ? "bg-texte"
                                      : "border-2 border-texte-doux/35"
                                  }`}
                                >
                                  {actif && (
                                    <IconeCoche className="text-accent size-3 [stroke-width:3]" />
                                  )}
                                </span>
                              </span>
                            </button>
                          );
                        })}
                      </div>
                    )}
                  </>
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {/* La validation est collée en bas : sur un écran qui déroule trois
            blocs et jusqu'à vingt favoris, un bouton en fin de page obligerait
            à redescendre à chaque changement d'avis. La barre rend elle-même la
            zone sûre du home indicator (voir `barre-collee` dans index.css).
            Le message d'erreur voyage avec elle, sinon il resterait hors de
            l'écran au moment précis où il compte. */}
        <div className="barre-collee pleine-largeur flex flex-col gap-2.5 px-4">
          {erreurEnvoi && (
            <Alerte ton="erreur" tentative={tentative}>
              {erreurEnvoi}
            </Alerte>
          )}

          {/* Le total potentiel vit dans la barre, au-dessus du bouton : c'est
              le chiffre qui fait changer d'avis, il doit bouger sous les yeux
              au moment du choix et non attendre le récapitulatif. Il n'apparaît
              qu'une fois quelque chose de choisi — « 0 pts » avant le premier
              pilote se lirait comme un mauvais départ. */}
          {!marchesManquants && potentiel > 0 && (
            <div className="flex items-baseline justify-between gap-3 px-1">
              <span className="text-label text-texte-doux uppercase">
                Total si tout tombe
              </span>
              <span className="text-primaire text-[17px] font-medium">
                <TexteEchange valeur={formaterPoints(potentiel)} />
              </span>
            </div>
          )}

          {etat.ferme ? (
            <Bouton
              variante="secondaire"
              onClick={() => naviguer(`/grands-prix/${gpId}/recap`)}
            >
              Voir le récapitulatif
            </Bouton>
          ) : (
            // Actif même quand la saisie est incomplète : un bouton grisé ne
            // dit pas ce qui manque, l'appui pose le message juste au-dessus.
            <Bouton
              variante="principal"
              onClick={valider}
              occupe={envoi}
              libelleOccupe="Enregistrement…"
              disabled={!gp || marchesManquants}
            >
              Valider mes pronos
            </Bouton>
          )}
        </div>
      </div>
    </Ecran>
  );
}
