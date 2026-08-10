import { useCallback, useEffect, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import Pastille from "../composants/Pastille.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { IconeCoche, IconeCopie, IconeSortie } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerChampionnat, quitterChampionnat } from "../lib/championnats.js";
import { oublierCache, useDonnees } from "../lib/useDonnees.js";

const DUREE_CONFIRMATION = 2000;

/** Bloc rouge du code d'invitation, repris de la maquette 05. */
function BlocCode({ code, miseEnAvant }) {
  const [copie, setCopie] = useState(false);
  const [echec, setEchec] = useState(false);

  useEffect(() => {
    if (!copie) return undefined;
    const minuterie = setTimeout(() => setCopie(false), DUREE_CONFIRMATION);
    return () => clearTimeout(minuterie);
  }, [copie]);

  async function copier() {
    try {
      // `navigator.clipboard` n'existe qu'en contexte sécurisé. En HTTP simple
      // — un test depuis le réseau local, par exemple — l'appel n'existe pas :
      // on le dit au lieu de laisser un bouton qui ne fait rien.
      if (!navigator.clipboard) throw new Error("presse-papiers indisponible");
      await navigator.clipboard.writeText(code);
      setEchec(false);
      setCopie(true);
    } catch {
      setEchec(true);
    }
  }

  return (
    <div className="rounded-bloc bg-primaire p-5">
      <p className="text-label uppercase text-white/60">Code d'invitation</p>
      <p className="text-score mt-2 tracking-[6px] text-white">{code}</p>
      <p className="text-corps-sm mt-1.5 text-white/50">
        {miseEnAvant
          ? "Championnat créé. Partage ce code pour inviter tes amis."
          : "Partage ce code pour inviter tes amis."}
      </p>

      <button
        type="button"
        onClick={copier}
        className="rounded-champ pressable min-h-tactile mt-3.5 inline-flex items-center gap-2 bg-white/15 px-4 py-2.5 text-[13px] font-medium text-white"
      >
        {copie ? (
          <IconeCoche className="size-3.5" />
        ) : (
          <IconeCopie className="size-3.5" />
        )}
        <TexteEchange valeur={copie ? "Code copié" : "Copier le code"} />
      </button>

      {echec && (
        <p role="alert" className="text-corps-sm mt-2.5 text-white/70">
          Copie impossible sur cet appareil. Note le code : {code}
        </p>
      )}
    </div>
  );
}

function SqueletteChampionnat() {
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-bloc bg-primaire h-[168px]" />
      <div className="rounded-bloc bg-surface flex flex-col gap-4 p-4">
        {[0, 1, 2].map((rang) => (
          <div key={rang} className="flex items-center gap-3">
            <div className="bg-fond size-9 shrink-0 rounded-full" />
            <div className="bg-fond h-3.5 w-1/3 rounded-full" />
          </div>
        ))}
      </div>
    </div>
  );
}

/** Maquette 07 — vue d'un championnat : code d'invitation et membres. */
export default function Championnat() {
  const { id } = useParams();
  const naviguer = useNavigate();
  const emplacement = useLocation();
  const { utilisateur } = useAuth();

  const nouveau = Boolean(emplacement.state?.nouveau);

  // Comme pour l'accueil, la clé de cache porte le compte : un championnat lu
  // par quelqu'un d'autre sur le même appareil ne doit pas ressortir ici.
  const cle = utilisateur ? `championnat:${utilisateur.id}:${id}` : null;
  const chargeur = useCallback((signal) => chargerChampionnat(id, signal), [id]);
  const { donnees, chargement, erreur } = useDonnees(cle, chargeur);

  const [confirmation, setConfirmation] = useState(false);
  const [depart, setDepart] = useState(false);
  const [erreurDepart, setErreurDepart] = useState(null);
  const [tentative, setTentative] = useState(0);

  async function quitter() {
    setDepart(true);
    setErreurDepart(null);
    setTentative((n) => n + 1);

    const resultat = await quitterChampionnat(id);

    if (!resultat.ok) {
      setDepart(false);
      setConfirmation(false);
      setErreurDepart(resultat.message);
      return;
    }

    if (cle) oublierCache(cle);
    if (utilisateur) oublierCache(`championnats:${utilisateur.id}`);
    naviguer("/accueil", { replace: true });
  }

  // Sortie de secours : sans championnat lisible, il n'y a rien à afficher, et
  // l'écran ne doit surtout pas être un cul-de-sac.
  if (erreur && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Championnat" retourVers="/accueil" />
        </Bloc>
        <Bloc rang={2}>
          <Alerte ton="erreur">{erreur}</Alerte>
        </Bloc>
      </Ecran>
    );
  }

  const membres = donnees?.membres ?? [];
  const effectif = membres.length;

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre={donnees?.nom ?? "Championnat"} retourVers="/accueil" />
        <p className="text-corps-sm text-texte-doux -mt-1">
          {chargement && !donnees
            ? "Chargement…"
            : `${effectif} ${effectif > 1 ? "membres" : "membre"} · Saison 2026`}
        </p>
      </Bloc>

      <div className="mt-3 flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteChampionnat />}
          >
            {donnees && (
              <div className="flex flex-col gap-3">
                <BlocCode code={donnees.code_invitation} miseEnAvant={nouveau} />

                <div className="rounded-bloc bg-surface p-4">
                  <p className="text-label text-texte-doux mb-1 px-1 uppercase">
                    Membres
                  </p>
                  <ul>
                    {membres.map((membre) => (
                      <li
                        key={membre.id}
                        className="flex items-center gap-3 px-1 py-2.5"
                      >
                        <Pastille nom={membre.pseudo} graine={membre.id} />
                        <span className="text-corps-sm text-texte min-w-0 flex-1 truncate font-medium">
                          {membre.pseudo}
                        </span>
                        {membre.id === donnees.cree_par && (
                          <span className="text-label-sm text-texte-doux uppercase">
                            Créateur
                          </span>
                        )}
                        {membre.id === utilisateur?.id && (
                          <span className="text-label-sm text-primaire uppercase">
                            Toi
                          </span>
                        )}
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {erreurDepart && (
          <Alerte ton="erreur" tentative={tentative}>
            {erreurDepart}
          </Alerte>
        )}

        {/* Quitter demande une confirmation, mais pas une boîte de dialogue :
            l'action est réversible tant qu'on a gardé le code, et un bouton
            qui se transforme sur place reste moins brutal qu'un écran qui
            s'interpose. Le geste de retour, lui, annule tout. */}
        <Bloc rang={3}>
          {confirmation ? (
            <div className="flex flex-col gap-2.5">
              <Bouton
                variante="principal"
                onClick={quitter}
                occupe={depart}
                libelleOccupe="Départ…"
                icone={<IconeSortie className="size-4" />}
              >
                Confirmer mon départ
              </Bouton>
              <button
                type="button"
                onClick={() => setConfirmation(false)}
                disabled={depart}
                className="text-texte-doux min-h-tactile pressable py-2 text-center text-[13px] font-medium"
              >
                Annuler
              </button>
            </div>
          ) : (
            <Bouton
              variante="secondaire"
              onClick={() => setConfirmation(true)}
              disabled={!donnees}
            >
              Quitter le championnat
            </Bouton>
          )}
        </Bloc>
      </div>
    </Ecran>
  );
}
