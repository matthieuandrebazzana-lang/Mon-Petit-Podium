import { useCallback, useEffect, useRef, useState } from "react";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import CarteGpSaison from "../composants/CarteGpSaison.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  GP_2026,
  chargerSaison,
  enrichir,
  etatDuGpSaison,
  indexProchainGpSaison,
} from "../lib/calendrier2026.js";
import { cleSaison } from "../lib/pronostics.js";
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
/*  Le défilement d'ouverture                                                 */
/* -------------------------------------------------------------------------- */

/** Ce qu'on laisse respirer au-dessus de la carte visée, en pixels. Assez pour
 *  que le bord supérieur de la carte précédente affleure : sans ce liseré, rien
 *  ne dirait qu'il y a quelque chose au-dessus, et le défilement vers le haut
 *  n'aurait pas d'affordance. */
const MARGE_DEFILEMENT = 14;

/**
 * La position d'un élément dans la page, **en coordonnées de mise en page**.
 *
 * `getBoundingClientRect()` aurait été plus court et aurait été faux ici :
 * l'écran entre en scène sous `.t-ecran` (un `translateX`) et ses blocs sous
 * `.t-stagger-line` (un `translateY`), donc le rectangle rendu est décalé
 * pendant toute l'animation d'entrée — c'est-à-dire exactement au moment où ce
 * calcul est fait. La chaîne des `offsetTop` ignore les `transform` : elle donne
 * la position que l'élément occupera une fois posé.
 */
function positionDansLaPage(element) {
  let y = 0;
  for (let noeud = element; noeud; noeud = noeud.offsetParent) y += noeud.offsetTop;
  return y;
}

/* -------------------------------------------------------------------------- */
/*  L'écran                                                                   */
/* -------------------------------------------------------------------------- */

export default function CalendrierGlobal() {
  const { utilisateur, modePrevisualisation } = useAuth();

  // La clé porte l'identifiant du compte, comme partout ailleurs : la réponse
  // est la même pour tout le monde, mais deux personnes qui se relaient sur le
  // même téléphone ne doivent jamais hériter du cache de l'autre.
  const cle = utilisateur ? cleSaison(utilisateur.id) : null;
  // **Le chargeur vit dans `lib/calendrier2026.js`**, partagé avec l'écran de
  // détail d'un Grand Prix : les deux écrans lisent la même chose sous la même
  // clé de cache, et deux chargeurs écrits séparément auraient rangé deux
  // formes de données sous un seul nom. Voir `chargerSaison` pour les deux
  // règles qu'il porte — les lectures partent ensemble, et la seconde ne peut
  // pas faire échouer la première.
  const profilId = utilisateur?.id ?? null;
  const chargeur = useCallback(
    (signal) => chargerSaison(profilId, signal),
    [profilId],
  );
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const [tentative, setTentative] = useState(0);

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  // `joues` est sérialisé en tableau dans le cache — un `Set` ne survit pas à un
  // aller-retour JSON, et `localStorage` en est un. Il redevient un `Set` ici,
  // là où on l'interroge douze fois.
  const grandsPrix = enrichir(GP_2026, donnees?.cotes);
  const joues = new Set(donnees?.joues ?? []);
  const restants = grandsPrix.filter(
    (gp) => etatDuGpSaison(gp).cle !== "termine",
  ).length;

  // ---- L'écran s'ouvre sur le prochain Grand Prix -------------------------
  //
  // **Ce n'est pas une animation, c'est une position de départ**, et les cinq
  // skills de design l'ont écarté d'une même voix : l'onglet Calendrier est en
  // bas de l'écran de tout le monde, donc ouvert plusieurs fois par jour, et
  // faire défiler la saison sous les yeux à chaque ouverture coûterait le temps
  // du geste sans rien apprendre. Le défilement est donc **instantané**, posé
  // avant la première peinture. Rien de nouveau n'entre dans le vocabulaire de
  // mouvement.
  //
  // **Il ne se produit qu'une fois par montage**, jamais à la revalidation : le
  // cache *stale-while-revalidate* rejoue le chargeur en arrière-plan, et sans
  // ce garde-fou l'arrivée d'une réponse Railway lente arracherait l'écran des
  // mains de quelqu'un en train de lire une carte plus bas.
  //
  // Il attend les données, et c'est la seule dépendance qui compte : tant que la
  // base n'a pas répondu, aucun Grand Prix n'est `en_base`, donc aucun n'est
  // terminé (voir `estGpPasse`) et la cible serait toujours la première carte.
  const cartes = useRef([]);
  const deja = useRef(false);
  useEffect(() => {
    if (deja.current || !donnees) return;
    const rang = indexProchainGpSaison(grandsPrix);
    // `-1` : la saison est finie, il n'y a rien devant. `0` : le prochain Grand
    // Prix est déjà la première carte, et le haut de page est sa place.
    if (rang <= 0) {
      deja.current = true;
      return;
    }
    const carte = cartes.current[rang];
    if (!carte) return;
    deja.current = true;
    // `useLayoutEffect` aurait posé le défilement avant la peinture, mais il
    // n'aurait rien mesuré de plus : la hauteur des cartes est fixée en dur
    // (`HAUTEUR_CARTE`), donc la mise en page est connue sans que le drapeau,
    // le tracé ni la police soient arrivés. Un `useEffect` suffit et n'a pas
    // besoin de bloquer la peinture.
    window.scrollTo({
      top: Math.max(0, positionDansLaPage(carte) - MARGE_DEFILEMENT),
      behavior: "auto",
    });
  }, [donnees, grandsPrix]);

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

        <Bloc rang={2}>
          {/* Le conteneur flex est **à l'intérieur** du bloc, jamais le bloc
              lui-même. `.t-stagger-line` pose `display: block` hors de toute
              couche Tailwind : une classe utilitaire ne la bat pas, et un
              `gap` posé sur le `Bloc` reste inerte — les cartes se collent.
              C'est déjà le motif de l'accueil et de la liste des
              championnats ; le calendrier était le seul à mapper ses cartes
              directement dans le bloc. */}
          <div className="flex flex-col gap-3">
            {grandsPrix.map((gp, rang) => (
              /* L'enveloppe porte la référence plutôt que la carte : celle-ci
                 est une fonction de ses props et n'a aucune raison d'exposer
                 son nœud. Un `div` sans classe ne change rien à la mise en
                 page — le `gap` du conteneur flex compte les enfants, et il en
                 comptait déjà douze. */
              <div
                key={gp.slug}
                ref={(noeud) => {
                  cartes.current[rang] = noeud;
                }}
              >
                <CarteGpSaison
                  gp={gp}
                  chargement={chargement && !donnees}
                  retour="/calendrier"
                  previsualisation={modePrevisualisation}
                  aPronostique={joues.has(gp.gp_id)}
                />
              </div>
            ))}
          </div>
        </Bloc>

        <div className="min-h-3 flex-1" />
      </div>
    </Ecran>
  );
}
