import { useCallback, useState } from "react";
import { Navigate, useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Bouton from "../composants/Bouton.jsx";
import SeancesWeekend from "../composants/SeancesWeekend.jsx";
import VainqueursCircuit from "../composants/VainqueursCircuit.jsx";
import TraceCircuitGp, { aUnTrace } from "../composants/TracesCircuits.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { cotesArretees } from "../lib/calendrier.js";
import {
  chargerSaison,
  enrichir,
  etatDuGpSaison,
  gpParSlug,
} from "../lib/calendrier2026.js";
import { ficheCircuit } from "../lib/circuits.js";
import { origineRetour } from "../lib/navigation.js";
import { cleSaison } from "../lib/pronostics.js";
import { useDonnees } from "../lib/useDonnees.js";

/**
 * La fiche d'un Grand Prix — le programme du week-end, le circuit et son
 * palmarès.
 *
 * On y arrive **en touchant une carte du calendrier**, et c'est le geste qui
 * manquait : les douze cartes portaient une date, un drapeau et un tracé, et
 * n'ouvraient rien tant que les cotes n'étaient pas arrêtées. Onze Grands Prix
 * sur douze étaient donc, la plupart du temps, des vignettes sans profondeur.
 *
 * **Un Grand Prix couru n'ouvre PAS cet écran, il ouvre ses résultats.** La
 * question qu'on se pose devant une course passée est « qui a gagné, et combien
 * j'ai marqué », pas « à quelle heure sont les EL1 ». C'est `CarteGpSaison` qui
 * fait ce départage, sur `etatDuGpSaison` — la seule fonction qui décide déjà de
 * la pastille et de la pâleur de la carte, et il n'en fallait pas une seconde.
 *
 * ## Trois blocs, et ils ne se disputent rien
 *
 * 1. **Le programme** — cinq séances en heure locale (`SeancesWeekend`). C'est
 *    ce qu'on vient chercher pendant la semaine qui précède, donc c'est en
 *    haut.
 * 2. **Le circuit** — le tracé en grand, puis cinq chiffres. C'est ce qu'on
 *    regarde une fois, la première année.
 * 3. **Le palmarès** — les derniers vainqueurs (`VainqueursCircuit`). C'est ce
 *    qu'on parcourt sans but précis, donc c'est en bas, et c'est le seul bloc
 *    qui défile à l'horizontale.
 *
 * ## Les données viennent d'où elles savent
 *
 * **Trois sources, et chacune reste propriétaire de ce qu'elle sait.**
 * `GP_2026` donne le nom, le pays, le circuit et les séances prévisionnelles ;
 * `CIRCUITS` donne la fiche et le palmarès ; la base, croisée par `enrichir`,
 * donne l'identifiant, le statut et les deux heures qu'elle seule connaît. Rien
 * n'est recopié d'une table à l'autre.
 *
 * **Le chargeur et la clé de cache sont ceux de l'onglet Calendrier**
 * (`chargerSaison`, `cleSaison`) : la réponse est déjà en cache quand on arrive
 * ici, donc l'écran s'ouvre plein. C'est le point du partage, et c'est aussi ce
 * qui garantit que les deux écrans ne peuvent pas dire deux choses de l'état
 * d'un même Grand Prix.
 *
 * **Et l'écran reste lisible sans la base**, exactement comme les douze cartes
 * (`calendrier.md` §1) : le nom, le circuit, le tracé, la fiche, le palmarès et
 * les trois essais libres sont vrais sans elle. Railway endormi ne retire que la
 * pastille d'état, l'heure confirmée des deux dernières séances et le bouton.
 *
 * ## Le bouton du bas
 *
 * > ### Écart signalé (CLAUDE.md §6)
 * >
 * > La demande dit « les GP en `cotes_figees` ». L'écran teste `cotesArretees`,
 * > pas le statut brut — et c'est la même correction que la version `0.38.0` a
 * > apportée aux trois autres surfaces qui portent un bouton de pronostics.
 * > `POST /scraper/declencher` fige les cotes des Grands Prix qu'il a scrapés,
 * > **et il peut être appelé un mardi** : le statut seul aurait posé ici un
 * > bouton « Voir les cotes » vers une grille de départ qui n'existe pas encore.
 * > Suivre la lettre de la demande aurait donc rouvert un défaut déjà corrigé
 * > ailleurs.
 *
 * Le libellé nomme sa destination (`design-system.md` §8) : on va **voir les
 * cotes**, pas pronostiquer — c'est le tableau des cotes qui, lui, mène à la
 * saisie. Le bouton est en `secondaire` et non en aplat rouge : cet écran est
 * une consultation, et l'urgence d'un aplat plein appartient au calendrier, qui
 * porte déjà « Pronostiquer » sur la même carte.
 *
 * ## Ce qui n'anime pas
 *
 * L'écran entre sous `.t-ecran` en direction `avant` — il s'enfonce dans la
 * hiérarchie — et ses trois blocs sous `.t-stagger-line`. **C'est tout, et c'est
 * délibéré** : aucun de ses éléments ne change d'état sous les yeux du joueur,
 * et le tracé du circuit n'a pas à se dessiner. Un tracé qui se dessinerait
 * serait joli la première fois et une attente les vingt suivantes — la fiche
 * d'un Grand Prix s'ouvre plusieurs fois dans la semaine qui précède sa course.
 * Aucun jeton de mouvement n'entre avec cet écran.
 */

/** Hauteur de la bande du tracé, en classe utilitaire — `TraceCircuitGp`
 *  n'accepte qu'un `className`, et c'est délibéré de sa part : un style en ligne
 *  l'emporterait sur l'`aspectRatio` qu'il pose lui-même hors `boiteLibre`.
 *
 *  **Une hauteur FIXE, et c'est le point.** Les douze cadrages vont de 1,13
 *  (Zandvoort, presque carré) à 3,4 (Bakou) : laisser la hauteur suivre le
 *  cadrage ferait sauter la position des chiffres d'un Grand Prix à l'autre.
 *  À hauteur fixe, `xMidYMid meet` centre chaque circuit dedans — Bakou remplit
 *  la largeur, Zandvoort la hauteur — et chacun garde sa vraie forme. */
const HAUTEUR_TRACE = "h-[190px]";

/** Ce qu'on écrit là où la fiche n'a rien. Jamais un zéro : « 0 tour » se lit
 *  comme une donnée, « — » comme une donnée manquante. C'est la règle que
 *  `GrilleStats` applique déjà à ses quatre cases. */
const ABSENT = "—";

/** Les décimales d'une distance. Trois, comme les fiches officielles : c'est au
 *  millimètre que se mesure un tracé, et « 4,26 km » aurait l'air arrondi. */
const distance = new Intl.NumberFormat("fr-FR", {
  minimumFractionDigits: 3,
  maximumFractionDigits: 3,
});

/**
 * Une case de la grille de statistiques.
 *
 * Elle reprend la forme de `GrilleStats` — `rounded-carte-sm`, surface blanche,
 * `shadow-carte` — **avec une seule différence, et elle est mesurée** : le
 * libellé est en `secondaire` (9,4:1 sur blanc) et non en `texte-doux`, qui n'y
 * vaut que 2,85:1. C'est la correction que le design system a déjà appliquée
 * deux fois ailleurs (`design-system.md` §5) ; l'appliquer ici plutôt que de
 * recopier le composant existant évite de propager un défaut connu.
 *
 * Le contenu est aligné à gauche et non centré : les valeurs vont de « 53 » à
 * « 306,720 km », et cinq longueurs différentes centrées ne laissent aucune
 * colonne à l'œil.
 */
function Stat({ libelle, valeur, detail = null, className = "" }) {
  return (
    <div
      className={`rounded-carte-sm bg-surface shadow-carte px-3.5 py-3 ${className}`}
    >
      <p className="text-label-sm text-secondaire">{libelle}</p>
      <p className="text-primaire mt-1.5 text-[19px] leading-none font-medium">
        {valeur}
      </p>
      {detail && (
        <p className="text-secondaire mt-1.5 truncate text-[12px]">{detail}</p>
      )}
    </div>
  );
}

export default function DetailGp() {
  const { slug } = useParams();
  const { state } = useLocation();
  const naviguer = useNavigate();
  const { utilisateur, modePrevisualisation } = useAuth();

  // Le slug vient de l'URL, donc de personne. `GP_2026` est la seule autorité
  // sur ce qu'est un Grand Prix de la saison : un slug inconnu n'a pas d'écran,
  // et le renvoi vers le calendrier vaut mieux qu'une fiche vide. `replace`
  // évite d'empiler la redirection, sans quoi le geste de retour d'iOS y
  // reviendrait en boucle.
  const statique = gpParSlug(slug);

  // D'où l'on vient. Le calendrier reste la destination par défaut : c'est de
  // là que l'écran s'ouvre, et un lien direct ne doit jamais laisser le bouton
  // de retour sans destination.
  const retour = origineRetour(state, {
    vers: "/calendrier",
    libelle: "Calendrier",
  });

  const cle = utilisateur ? cleSaison(utilisateur.id) : null;
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

  if (!statique) return <Navigate to="/calendrier" replace />;

  // Le même croisement que le calendrier, sur la même réponse : l'écran ne
  // refait pas le travail d'`enrichir`, il le rejoue sur une seule ligne.
  const [gp] = enrichir([statique], donnees?.cotes);
  const etat = etatDuGpSaison(gp);
  const fiche = ficheCircuit(gp.slug);

  // Le mode prévisualisation lève la condition des qualifications, jamais celle
  // des cotes en base — même arbitrage que `actionDuGp` : montrer l'app comme si
  // les cotes étaient arrêtées ne va pas jusqu'à prétendre qu'un Grand Prix sans
  // cotes en ait. Sans `gp_id`, il n'y a de toute façon rien à ouvrir.
  const versLesCotes =
    gp.gp_id && (cotesArretees(gp) || (modePrevisualisation && gp.cotes_disponibles));

  return (
    <Ecran direction="avant">
      {/* **En enfant direct d'`Ecran`, jamais dans un `Bloc`.** La rangée de
          retour est `position: sticky` ; les blocs `t-stagger-line` portent un
          `transform` pendant leur entrée, et un ancêtre transformé devient le
          bloc conteneur — l'en-tête se collerait à la boîte du bloc au lieu de
          la fenêtre, et défilerait avec la page. C'est la contrainte que le
          composant énonce lui-même, et c'est ce que fait déjà `Cotes.jsx`. */}
      <EnTeteEcran
        titre={gp.nom}
        sousTitre={`${gp.circuit} · ${gp.pays}`}
        retourVers={retour.vers}
        libelleRetour={retour.libelle}
        /* Notre propre origine, rendue à l'écran de retour : sans elle, la
           chaîne se casse au premier rebond (`navigation.js`). */
        retourEtat={state?.origine ? { retour: state.origine } : null}
      >
        {/* Tant que la base n'a pas répondu, l'état est **inconnu**, et une
            pastille « À venir » posée par défaut se corrigerait en « Pronos
            ouverts » sous les yeux du joueur — la règle des douze cartes,
            appliquée ici au singulier. Une silhouette dit la même chose sans
            rien affirmer, et elle a la hauteur de ce qui arrive pour que le
            titre ne sursaute pas.

            La pastille prend le jeu `pastille` d'`ETATS_GP` et non
            `pastilleSurDrapeau` : elle est posée sur le fond de l'app, pas sur
            un drapeau. Le gris translucide de « À venir » y donne `#DEDAD7`,
            où le marron `secondaire` vaut 7,57:1. */}
        <div className="mt-2.5">
          {chargement && !gp.en_base ? (
            <span
              aria-hidden="true"
              className="t-skel-bar inline-block h-[24px] w-28 rounded-[10px]"
            />
          ) : (
            <span
              className={`inline-block rounded-[10px] px-2.5 py-1 text-[11px] font-medium ${etat.pastille}`}
            >
              {etat.libelle}
            </span>
          )}
        </div>
      </EnTeteEcran>

      <div className="mt-3 flex flex-1 flex-col gap-3">
        {/* L'échec ne vide pas l'écran : les trois blocs restent en dessous, et
            seuls la pastille, l'heure confirmée des deux dernières séances et le
            bouton manquent. Le message se pose **au-dessus**, jamais à leur
            place (`calendrier.md` §1). */}
        {echec && (
          <Bloc rang={1}>
            <BlocErreur
              echec={echec}
              onReessayer={reessayer}
              tentative={tentative}
            />
          </Bloc>
        )}

        {/* ---- 1. Le programme du week-end ------------------------------- */}
        <Bloc rang={1}>
          <h2 className="text-label text-secondaire mb-2">Week-end</h2>
          <SeancesWeekend gp={gp} />
        </Bloc>

        {/* ---- 2. Le circuit et ses chiffres ------------------------------
            Le bloc entier disparaît sans fiche : quatre tirets et un tracé
            absent n'apprendraient rien, et c'est déjà la règle d'`aUnTrace` —
            un motif de repli laisserait croire que ce Grand Prix se court sur
            cette forme-là. */}
        {(fiche || aUnTrace(gp.slug)) && (
          <Bloc rang={2}>
            <h2 className="text-label text-secondaire mb-2">Circuit</h2>

            {aUnTrace(gp.slug) && (
              <div className="rounded-bloc bg-surface shadow-bloc mb-2.5 px-5 py-4">
                {/* `boiteLibre` coupe le rapport de forme que le composant pose
                    en ligne : la bande fixe les deux dimensions, et c'est le
                    travail de `xMidYMid meet` de mettre chaque circuit à
                    l'échelle dedans. Bakou remplit la largeur, Zandvoort la
                    hauteur — chacun garde sa vraie forme au lieu d'être étiré
                    pour occuper la même surface.

                    Le trait est en `secondaire` : c'est un élément graphique
                    porteur de sens, donc il lui faut 3:1, et le marron en vaut
                    9,4:1 sur blanc. `texte-doux` n'y aurait valu que 2,85:1. */}
                <TraceCircuitGp
                  slug={gp.slug}
                  epaisseur={2}
                  boiteLibre
                  className={`text-secondaire w-full ${HAUTEUR_TRACE}`}
                />
              </div>
            )}

            {fiche && (
              /* Cinq chiffres, cinq cases : deux rangées de deux, puis le
                 record sur toute la largeur — il porte trois informations
                 (le temps, le pilote, l'année) là où les autres n'en portent
                 qu'une. Aucune case vide, et aucune case inventée pour tenir
                 un gabarit. */
              <div className="grid grid-cols-2 gap-2.5">
                <Stat
                  libelle="Longueur"
                  valeur={`${distance.format(fiche.longueur_km)} km`}
                />
                <Stat libelle="Tours" valeur={fiche.nombre_tours ?? ABSENT} />
                <Stat
                  libelle="Distance"
                  valeur={`${distance.format(fiche.distance_km)} km`}
                />
                <Stat libelle="Premier GP" valeur={fiche.premier_gp ?? ABSENT} />
                <Stat
                  className="col-span-2"
                  libelle="Record du tour"
                  valeur={fiche.record_tour?.temps ?? ABSENT}
                  detail={
                    fiche.record_tour
                      ? `${fiche.record_tour.pilote} · ${fiche.record_tour.annee}`
                      : "Circuit jamais couru"
                  }
                />
              </div>
            )}
          </Bloc>
        )}

        {/* ---- 3. Le palmarès -------------------------------------------- */}
        {fiche?.derniers_vainqueurs?.length > 0 && (
          <Bloc rang={3}>
            <h2 className="text-label text-secondaire mb-2">
              Derniers vainqueurs
            </h2>
            <VainqueursCircuit vainqueurs={fiche.derniers_vainqueurs} />
          </Bloc>
        )}

        <div className="min-h-3 flex-1" />
      </div>

      {/* La barre collée rend elle-même la zone sûre du home indicator et n'est
          pas enveloppée dans un `Bloc` : `t-stagger-line` porte un `transform`,
          et un ancêtre transformé casse le collage (voir `Cotes.jsx`). */}
      {versLesCotes && (
        <div className="barre-collee pleine-largeur px-4">
          <Bouton
            variante="secondaire"
            onClick={() =>
              naviguer(`/grands-prix/${gp.gp_id}/cotes`, {
                // Deux clés distinctes : `retour` dit où va SON bouton de
                // retour, `origine` lui dit quoi nous rendre quand il nous y
                // ramène — sans quoi ce second passage retomberait sur
                // l'accueil.
                state: { retour: `/calendrier/${gp.slug}`, origine: retour.vers },
              })
            }
          >
            Voir les cotes
          </Bouton>
        </div>
      )}
    </Ecran>
  );
}
