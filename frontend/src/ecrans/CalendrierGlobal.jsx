import { useCallback, useState } from "react";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import CarteGpSaison from "../composants/CarteGpSaison.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  GP_2026,
  chargerCotesEnBase,
  enrichir,
  etatDuGpSaison,
} from "../lib/calendrier2026.js";
import { useDonnees } from "../lib/useDonnees.js";

/**
 * Cible de l'onglet **Calendrier** de la barre basse.
 *
 * L'écran montre désormais **les Grands Prix de la saison**, et non plus la
 * liste des championnats. C'est ce qu'un onglet nommé « Calendrier » promet, et
 * la liste des championnats vivait déjà à deux endroits — l'accueil et son
 * propre onglet ; l'afficher une troisième fois n'apprenait rien à personne.
 *
 * **La liste est statique** (`lib/calendrier2026.js`), et c'est la seule façon
 * d'afficher une saison entière : `public.grands_prix` ne contient que ce que le
 * scraper a rencontré, et Unibet n'expose jamais que le Grand Prix suivant
 * (CLAUDE.md section 3.1). La base est croisée par-dessus pour ce qu'elle seule
 * sait — l'identifiant, le statut, l'existence des cotes.
 *
 * **Conséquence à ne pas défaire : les douze cartes s'affichent quoi qu'il
 * arrive.** Railway endormi, appel en échec, base vide — l'écran reste plein et
 * lisible, seuls les états et les boutons manquent. C'est l'inverse d'un écran
 * de liste ordinaire, où l'absence de données est un écran vide, et c'est
 * précisément pour cela que la liste vit côté frontend.
 *
 * Le calendrier d'**un championnat** (maquette 15), avec ses scores et son
 * mini-classement, reste un autre écran, atteint depuis le championnat.
 */

/* -------------------------------------------------------------------------- */
/*  L'écran                                                                   */
/* -------------------------------------------------------------------------- */

export default function CalendrierGlobal() {
  const { utilisateur } = useAuth();

  // La clé porte l'identifiant du compte, comme partout ailleurs : la réponse
  // est la même pour tout le monde, mais deux personnes qui se relaient sur le
  // même téléphone ne doivent jamais hériter du cache de l'autre.
  const cle = utilisateur ? `saison:${utilisateur.id}` : null;
  const chargeur = useCallback((signal) => chargerCotesEnBase(signal), []);
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const [tentative, setTentative] = useState(0);

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  const grandsPrix = enrichir(GP_2026, donnees);
  const restants = grandsPrix.filter(
    (gp) => etatDuGpSaison(gp).cle !== "termine",
  ).length;

  return (
    <Ecran direction="avant">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={1} className="pt-1 pb-1">
          <h1 className="text-titre-lg text-texte">Calendrier</h1>
          <p className="text-texte-doux mt-1 text-[13px]">
            {/* Le décompte porte sur ce que l'écran affiche vraiment, et il se
                lit sur les cartes : pas de nombre qui vienne d'ailleurs. */}
            Saison 2026 · {restants} Grand{restants > 1 ? "s" : ""} Prix restant
            {restants > 1 ? "s" : ""}
          </p>
        </Bloc>

        {/* L'échec ne vide pas l'écran : les douze cartes restent en dessous,
            avec leur date et leur circuit. Le message dit seulement que les
            états et les boutons manquent, et propose de réessayer. */}
        {echec && (
          <Bloc rang={2}>
            <BlocErreur
              echec={echec}
              onReessayer={reessayer}
              tentative={tentative}
            />
          </Bloc>
        )}

        <Bloc rang={2} className="flex flex-col gap-3">
          {grandsPrix.map((gp) => (
            <CarteGpSaison
              key={gp.slug}
              gp={gp}
              chargement={chargement && !donnees}
            />
          ))}
        </Bloc>

        <div className="min-h-3 flex-1" />
      </div>
    </Ecran>
  );
}
