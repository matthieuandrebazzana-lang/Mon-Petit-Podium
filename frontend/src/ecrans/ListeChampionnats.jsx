import { useCallback, useState } from "react";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { IconePlus } from "../composants/Icones.jsx";
import {
  Action,
  CarteChampionnat,
  SqueletteChampionnats,
} from "./Accueil.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { listerMesChampionnats } from "../lib/championnats.js";
import { useDonnees } from "../lib/useDonnees.js";

/**
 * Cible de l'onglet **Championnats** de la barre basse (étape 10).
 *
 * L'accueil montre déjà cette liste, sous le bloc du prochain Grand Prix. Ici
 * elle occupe l'écran : c'est la destination d'un onglet, pas un extrait, et
 * quelqu'un qui appartient à huit championnats doit tous les voir sans avoir à
 * passer sous un bloc rouge.
 *
 * **Les cartes sont exactement celles de l'accueil**, importées et non
 * redessinées. Le même championnat doit se reconnaître d'un écran à l'autre, et
 * deux dessins parallèles auraient divergé au premier ajustement.
 *
 * **Aucun bouton de retour**, et c'est volontaire : c'est la racine d'un
 * onglet. Sur iOS, la racine d'un onglet ne remonte nulle part — on en sort par
 * un autre onglet. Un « Retour » y donnerait une profondeur qui n'existe pas.
 *
 * Le cache est partagé avec l'accueil (`championnats:{profil}`) : arriver ici
 * depuis l'accueil affiche la liste sans un seul aller-retour, et une adhésion
 * faite ailleurs invalide les deux écrans d'un coup.
 */
export default function ListeChampionnats() {
  const { utilisateur } = useAuth();

  const cle = utilisateur ? `championnats:${utilisateur.id}` : null;
  const chargeur = useCallback((signal) => listerMesChampionnats(signal), []);
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const [tentative, setTentative] = useState(0);

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  const championnats = donnees ?? [];

  return (
    <Ecran direction="avant">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={1} className="pt-1 pb-1">
          <h1 className="text-titre-lg text-texte">Championnats</h1>
          <p className="text-texte-doux mt-1 text-[13px]">
            {chargement && !donnees
              ? "Chargement…"
              : championnats.length === 0
                ? "Saison 2026"
                : `${championnats.length} championnat${
                    championnats.length > 1 ? "s" : ""
                  } · Saison 2026`}
          </p>
        </Bloc>

        {echec && (
          <Bloc rang={2}>
            <BlocErreur echec={echec} onReessayer={reessayer} tentative={tentative} />
          </Bloc>
        )}

        <Bloc rang={2}>
          <ZoneChargement chargement={chargement} squelette={<SqueletteChampionnats />}>
            {championnats.length === 0 ? (
              /* Pas une erreur : un compte neuf n'appartient à rien. Le message
                 dit quoi faire, et les deux actions sont juste en dessous. */
              <div className="rounded-bloc bg-surface px-5 py-9 text-center">
                <p className="text-corps text-texte font-medium">
                  Aucun championnat pour l'instant
                </p>
                <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                  Crée le tien et partage son code à six caractères, ou rejoins
                  celui d'un ami.
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-2.5">
                {championnats.map((championnat, rang) => (
                  <CarteChampionnat
                    key={championnat.id}
                    championnat={championnat}
                    rang={rang}
                  />
                ))}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        <Bloc rang={3} className="grid grid-cols-2 gap-2.5">
          <Action
            vers="/championnats/creer"
            variante="principal"
            icone={<IconePlus className="size-4" />}
          >
            Créer
          </Action>
          <Action vers="/championnats/rejoindre" variante="secondaire">
            Rejoindre
          </Action>
        </Bloc>
      </div>
    </Ecran>
  );
}
