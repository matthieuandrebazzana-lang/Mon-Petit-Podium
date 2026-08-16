import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import { Pave } from "../composants/Squelette.jsx";
import Compteur from "../composants/Compteur.jsx";
import {
  IconeChevronAccordeon,
  IconeCoche,
  IconeHorloge,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { couleurBloc, tonalites } from "../lib/couleurs.js";
import {
  BONUS_MAXIMUM,
  MARCHE_PODIUM,
  MARCHE_VAINQUEUR,
  chargerSaisie,
  cleAccueilGp,
  enregistrerPronostics,
  indexerCotes,
  marcheDe,
  organiserPronostics,
} from "../lib/pronostics.js";
import { oublierCache, useDonnees } from "../lib/useDonnees.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";

// Les trois aplats de l'écran, et leurs encres, calculés une fois pour toutes :
// ils ne dépendent d'aucune donnée. Les recalculer à chaque rendu ne coûterait
// pas cher, mais les écrire ici dit clairement qu'ils sont fixes.
const COULEUR_VAINQUEUR = couleurBloc("rouge");
const COULEUR_PODIUM = couleurBloc("bleu-ardoise");
const COULEUR_BONUS = couleurBloc("amber");
const tonVainqueur = tonalites(COULEUR_VAINQUEUR.hex);
const tonPodium = tonalites(COULEUR_PODIUM.hex);
const tonBonus = tonalites(COULEUR_BONUS.hex);

function SqueletteSaisie() {
  return (
    <div className="flex flex-col gap-3">
      {/* Les blocs gardent leurs aplats de couleur : c'est la surface, pas le
          contenu, et les voir virer au gris puis revenir ferait clignoter
          l'écran au lieu de le remplir. */}
      <div className="rounded-carte bg-primaire shadow-carte flex items-center justify-between gap-3 px-4.5 py-3.5">
        <div className="flex-1">
          <div className="h-2.5 w-24 rounded-full bg-white/25" />
          <div className="mt-2 h-4 w-32 rounded-full bg-white/25" />
        </div>
        <div className="rounded-champ size-8 bg-white/15" />
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

/** Bloc rouge du compte à rebours, maquette 09. */
function BlocFermeture({ etat }) {
  return (
    <div className="rounded-carte bg-primaire shadow-carte flex items-center justify-between gap-3 px-4.5 py-3.5">
      <div className="min-w-0">
        <p className="text-label uppercase text-white/60">
          {etat.ferme ? "Pronostics" : "Fermeture dans"}
        </p>
        <p className="mt-0.5 truncate text-[20px] font-medium text-white">
          {etat.ferme ? "Fermés" : (etat.texte ?? "Date à confirmer")}
        </p>
      </div>
      <span
        aria-hidden="true"
        className="flex size-9 shrink-0 items-center justify-center rounded-full bg-white/15"
      >
        <IconeHorloge className="size-[18px] text-white" />
      </span>
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
  etiquette,
  ton,
  couleur,
  verrouille,
}) {
  // Le choix, ou son absence, dit toujours la même chose au même endroit : une
  // étiquette de place à gauche (elle seule distingue les deux pilotes du
  // podium), la valeur au centre, les points à droite.
  const valeur = (
    <span className="flex min-w-0 flex-1 items-center gap-2">
      {etiquette && (
        <span
          className={`shrink-0 rounded-md px-1.5 py-0.5 text-[11px] font-medium ${ton.surfaceForte} ${ton.texte}`}
        >
          {etiquette}
        </span>
      )}
      <span
        className={`min-w-0 flex-1 truncate text-[15px] ${
          choisi ? `font-medium ${ton.texte}` : ton.texteDoux
        }`}
      >
        {choisi ? choisi.pilote : "Non sélectionné"}
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
                      {option.pilote}
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
      className={`rounded-carte shadow-carte flex flex-col gap-2.5 p-4 ${couleur.fond}`}
    >
      <div className="flex items-center justify-between gap-2">
        <p
          className={`min-w-0 truncate text-[12px] font-medium tracking-[0.5px] uppercase ${ton.texte}`}
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
  );
}

/** Maquette 09 — saisie et modification des pronostics. */
export default function Pronostics() {
  const { gpId } = useParams();
  const naviguer = useNavigate();
  const { utilisateur } = useAuth();

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
      // rien plutôt que de remplacer en douce un bonus déjà choisi.
      if (actuel.length >= BONUS_MAXIMUM) return actuel;
      return [...actuel, idOutcome];
    });
  }

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

    setEnvoi(true);
    const resultat = await enregistrerPronostics(gpId, {
      vainqueur,
      podium: { pilote_1: podium[0], pilote_2: podium[1] },
      bonus,
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
      // Le bloc « Prochain GP » de l'accueil décide de sa destination sur
      // l'existence de ces pronostics : sans cet oubli, un retour immédiat sur
      // l'accueil proposerait encore « Pronostiquer » le temps du
      // rafraîchissement, juste après une validation.
      oublierCache(cleAccueilGp(utilisateur.id));
    }
    naviguer(`/grands-prix/${gpId}/recap`, { state: { enregistre: true } });
  }

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Mes pronos" retourVers={`/grands-prix/${gpId}/cotes`} />
        </Bloc>
        <Bloc rang={2}>
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

  // Le second pilote du podium ne peut pas être le premier : l'écarter de la
  // liste vaut mieux que de le laisser choisir puis de le refuser.
  const optionsPodium = (place) =>
    (marchePodium?.cotes ?? []).filter((option) => option.id !== podium[1 - place]);

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete
          titre="Mes pronos"
          retourVers={`/grands-prix/${gpId}/cotes`}
          libelleRetour={gp?.nom ?? "Les cotes"}
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
                      titre={marchePodium.libelle}
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
                          etiquette={place === 0 ? "1er" : "2e"}
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
                          valeur={bonus.length}
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
                          const actif = bonus.includes(favori.id_outcome_unibet);
                          const sature = !actif && bonus.length >= BONUS_MAXIMUM;
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
                                  {favori.pilote ?? favori.id_outcome_unibet}
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
