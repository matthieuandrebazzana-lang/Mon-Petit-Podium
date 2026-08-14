import { useCallback, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import GrilleStats from "../composants/GrilleStats.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import { IconeChevronDroit, IconeDrapeau } from "../composants/Icones.jsx";
import { HeroProfil } from "./MonProfil.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerProfilComplet, cleProfil } from "../lib/profils.js";
import { useDonnees } from "../lib/useDonnees.js";

/**
 * Maquette 12 — le profil d'un autre membre, atteint depuis le classement.
 *
 * Le bloc rouge, la voiture, le numéro et la grille 2×2 sont **exactement ceux
 * de mon propre profil** : `HeroProfil` et `GrilleStats` sont les mêmes
 * composants. Deux profils qui ne se liraient pas de la même façon ne se
 * compareraient plus, ce qui est pourtant tout l'objet de cet écran.
 *
 * Ce qui change tient en une phrase : **rien n'est modifiable ici**. Aucun
 * sélecteur de couleur, aucun champ de numéro — la voiture d'un autre membre
 * n'est pas la nôtre, et la RLS le dit aussi.
 *
 * **Écart assumé** : comme sur mon profil, la grille de cartes de Grands Prix
 * illustrées par `assets/gp-cards.svg` est remplacée par une rangée qui mène à
 * l'écran listant vraiment ces Grands Prix (maquette 13).
 *
 * Si le demandeur ne partage aucun championnat avec ce membre, la route de
 * statistiques répond `403` : l'écran affiche alors le profil sans sa grille,
 * plutôt qu'une page d'erreur. Voir `chargerProfilComplet`.
 */
export default function ProfilMembre() {
  const { profilId } = useParams();
  const { utilisateur } = useAuth();

  // La clé porte le compte connecté ET la cible : deux personnes qui se
  // relaient sur le même téléphone ne doivent pas hériter du profil que l'autre
  // consultait, et un même compte peut consulter plusieurs membres.
  const cle = utilisateur ? cleProfil(utilisateur.id, profilId) : null;
  const chargeur = useCallback(
    (signal) => chargerProfilComplet(profilId, signal),
    [profilId],
  );
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayerChargement() {
    setTentativeChargement((n) => n + 1);
    recharger();
  }

  const profil = donnees?.profil ?? null;

  // Son propre profil se modifie : on renvoie sur l'écran qui sait le faire
  // plutôt que d'afficher une version en lecture seule de soi-même. La
  // redirection passe par `<Navigate>` et non par un `naviguer()` posé dans le
  // corps du composant, qui serait un effet de bord pendant le rendu.
  if (utilisateur && profilId === utilisateur.id) {
    return <Navigate to="/profil" replace />;
  }

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Profil" retourVers={-1} />
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

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete
          titre={profil?.pseudo ?? "Profil"}
          retourVers={-1}
          libelleRetour="Classement"
        />
      </Bloc>

      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={
              <div className="flex flex-col gap-3">
                <div className="rounded-bloc bg-primaire h-[104px]" />
                <div className="grid grid-cols-2 gap-2.5">
                  {[0, 1, 2, 3].map((rang) => (
                    <div
                      key={rang}
                      className="rounded-carte-sm bg-surface h-[68px]"
                    />
                  ))}
                </div>
              </div>
            }
          >
            {profil && (
              <div className="flex flex-col gap-3">
                <HeroProfil
                  pseudo={profil.pseudo}
                  voiture={profil}
                  numero={profil.numero}
                  action="Saison 2026"
                />

                <GrilleStats stats={donnees?.stats} />

                <Link
                  to={`/profils/${profilId}/grands-prix`}
                  className="rounded-carte bg-surface pressable min-h-tactile flex items-center gap-3.5 p-4"
                >
                  <span
                    aria-hidden="true"
                    className="bg-primaire rounded-champ flex size-[46px] shrink-0 items-center justify-center text-white"
                  >
                    <IconeDrapeau className="size-[22px]" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="text-corps text-texte block font-medium">
                      Ses Grands Prix
                    </span>
                    <span className="text-texte-doux mt-0.5 block text-[12px]">
                      {donnees?.stats?.gp_joues
                        ? `${donnees.stats.gp_joues} GP joué${
                            donnees.stats.gp_joues > 1 ? "s" : ""
                          } cette saison`
                        : "Ses pronostics, Grand Prix par Grand Prix"}
                    </span>
                  </span>
                  <IconeChevronDroit className="text-texte-doux size-4 shrink-0" />
                </Link>
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />
      </div>
    </Ecran>
  );
}
