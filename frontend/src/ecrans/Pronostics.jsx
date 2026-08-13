import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import Compteur from "../composants/Compteur.jsx";
import {
  IconeChevronAccordeon,
  IconeCoche,
  IconeHorloge,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
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

function SqueletteSaisie() {
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-carte bg-primaire h-[68px]" />
      {[0, 1].map((rang) => (
        <div key={rang} className="rounded-carte bg-surface flex flex-col gap-2.5 p-4">
          <div className="bg-fond h-3 w-24 rounded-full" />
          <div className="bg-fond rounded-champ h-[46px]" />
        </div>
      ))}
    </div>
  );
}

/** Bloc rouge du compte à rebours, maquette 09. */
function BlocFermeture({ etat }) {
  return (
    <div className="rounded-carte bg-primaire flex items-center justify-between gap-3 px-4.5 py-3.5">
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
  placeholder,
  verrouille,
}) {
  if (verrouille) {
    return choisi ? (
      <div className="rounded-champ bg-primaire flex items-center justify-between gap-3 px-4 py-3.5">
        <span className="min-w-0 flex-1 truncate text-[15px] font-medium text-white">
          {choisi.pilote}
        </span>
        <span className="shrink-0 text-[13px] text-white/70">
          {formaterPoints(choisi.points)}
        </span>
      </div>
    ) : (
      <div className="rounded-champ bg-fond px-4 py-3.5">
        <span className="text-texte-doux text-[14px]">Aucun pronostic</span>
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
          choisi ? "bg-primaire" : "bg-fond"
        }`}
      >
        <span className="min-w-0 flex-1 truncate text-[15px] font-medium">
          <span className={choisi ? "text-white" : "text-texte-doux font-normal text-[14px]"}>
            {choisi ? choisi.pilote : placeholder}
          </span>
        </span>
        <span className="flex shrink-0 items-center gap-2.5">
          {choisi && (
            <span className="text-[13px] text-white/70">
              {formaterPoints(choisi.points)}
            </span>
          )}
          <span className="t-acc-chevron">
            <IconeChevronAccordeon
              className={`size-4 ${choisi ? "text-white/70" : "text-texte-doux"}`}
            />
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
                  <button
                    type="button"
                    onClick={() => onChoisir(option)}
                    aria-pressed={actif}
                    className={`rounded-champ pressable min-h-tactile flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left ${
                      actif ? "bg-primaire text-white" : "bg-fond text-texte"
                    }`}
                  >
                    <span className="min-w-0 flex-1 truncate text-[14px] font-medium">
                      {option.pilote}
                    </span>
                    <span
                      className={`shrink-0 text-[12px] font-medium ${
                        actif ? "text-white/70" : "text-secondaire"
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

/** Carte blanche d'un marché obligatoire : titre, étiquette, emplacements. */
function BlocObligatoire({ titre, children }) {
  return (
    <div className="rounded-carte bg-surface flex flex-col gap-2.5 p-4">
      <div className="flex items-center justify-between gap-2">
        <p className="text-primaire text-[12px] font-medium tracking-[0.5px] uppercase">
          {titre}
        </p>
        <span className="text-accent bg-accent/15 rounded-lg px-2 py-0.5 text-[10px] font-medium">
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
  const { donnees, chargement, erreur } = useDonnees(cle, chargeur);

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

  if (erreur && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Mes pronos" retourVers={`/grands-prix/${gpId}/cotes`} />
        </Bloc>
        <Bloc rang={2}>
          <Alerte ton="erreur">{erreur}</Alerte>
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
                  <p className="rounded-carte bg-surface text-texte-doux text-corps-sm px-4 py-3">
                    Le départ est imminent : les pronostics sont figés et ne
                    peuvent plus être modifiés.
                  </p>
                )}

                {marchesManquants ? (
                  <div className="rounded-carte bg-surface px-5 py-8 text-center">
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

                    <BlocObligatoire titre={marcheVainqueur.libelle}>
                      <Emplacement
                        choisi={cote(vainqueur)}
                        options={marcheVainqueur.cotes}
                        onChoisir={choisirVainqueur}
                        ouvert={ouvert === "vainqueur"}
                        onBasculer={() =>
                          setOuvert(ouvert === "vainqueur" ? null : "vainqueur")
                        }
                        placeholder="Choisis le vainqueur..."
                        verrouille={etat.ferme}
                      />
                    </BlocObligatoire>

                    <BlocObligatoire titre={marchePodium.libelle}>
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
                          placeholder={
                            place === 0
                              ? "1er pilote sur le podium..."
                              : "2e pilote sur le podium..."
                          }
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
                      <div className="rounded-carte bg-surface px-5 py-7 text-center">
                        <p className="text-corps text-texte font-medium">
                          Aucun favori pour l'instant
                        </p>
                        <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                          Les bonus se choisissent parmi les cotes que tu as
                          épinglées dans le tableau des cotes.
                        </p>
                      </div>
                    ) : (
                      <div className="rounded-carte bg-surface flex flex-col gap-2 p-4">
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
                              className={`rounded-champ pressable min-h-tactile flex w-full items-center justify-between gap-3 px-3 py-2.5 text-left ${
                                actif ? "bg-primaire" : "bg-fond"
                              } ${sature ? "opacity-50" : ""}`}
                            >
                              <span className="min-w-0">
                                <span
                                  className={`block truncate text-[10px] font-medium tracking-[0.4px] uppercase ${
                                    actif ? "text-white/60" : "text-texte-doux"
                                  }`}
                                >
                                  {favori.libelle ?? "Cote retirée"}
                                </span>
                                <span
                                  className={`mt-0.5 block truncate text-[14px] font-medium ${
                                    actif ? "text-white" : "text-texte"
                                  }`}
                                >
                                  {favori.pilote ?? favori.id_outcome_unibet}
                                </span>
                              </span>

                              <span className="flex shrink-0 items-center gap-2">
                                <span
                                  className={`rounded-lg px-2 py-1 text-[12px] font-medium ${
                                    actif
                                      ? "bg-white/20 text-white"
                                      : "bg-surface text-secondaire"
                                  }`}
                                >
                                  {formaterPoints(favori.points)}
                                </span>
                                <span
                                  aria-hidden="true"
                                  className={`flex size-[22px] items-center justify-center rounded-full ${
                                    actif
                                      ? "bg-white"
                                      : "border-2 border-texte-doux/35"
                                  }`}
                                >
                                  {actif && (
                                    <IconeCoche className="text-primaire size-3 [stroke-width:3]" />
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

        {erreurEnvoi && (
          <Alerte ton="erreur" tentative={tentative}>
            {erreurEnvoi}
          </Alerte>
        )}

        <Bloc rang={3}>
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
        </Bloc>
      </div>
    </Ecran>
  );
}
