import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import Voiture from "../composants/Voiture.jsx";
import { IconeChevronGauche } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerChampionnat } from "../lib/championnats.js";
import { chargerClassement, cleClassement } from "../lib/classement.js";
import { messageDeChargement } from "../lib/erreurs.js";
import { livreeDuMembre } from "../lib/palette.js";
import { useDonnees } from "../lib/useDonnees.js";

/**
 * Maquette 07b — la vue piste, écran signature de l'app.
 *
 * Une route occupe tout l'écran : asphalte sombre, bordures rouge et blanc sur
 * les deux côtés, ligne pointillée centrale. Aucun fond beige n'est visible.
 * Les voitures sont réparties verticalement selon les points — le leader tout
 * en haut, le dernier en bas — et **le score seul** s'affiche à droite de
 * chaque groupe.
 *
 * **La ligne d'arrivée en damier a été retirée**, ainsi que son libellé. Elle
 * ancrait le haut de la piste, et sa disparition laisse ce rôle aux seuls
 * éléments qui restent : la position du leader et le nom du championnat qui
 * ferme l'écran en bas. La section 6 du CLAUDE.md a été mise à jour en
 * conséquence — la décrire encore aurait laissé le cahier des charges annoncer
 * un élément qui n'existe plus.
 *
 * **Écart assumé par rapport à la maquette 07b**, et il vient de la demande
 * elle-même : la maquette garde l'en-tête du championnat et la bascule
 * Classement / Piste au-dessus de la route, ainsi que la barre de navigation
 * basse. Ici la route occupe l'écran entier, et un unique bouton de retour en
 * haut à gauche ramène au classement. C'est l'écran signature : lui laisser
 * 150px de chrome au-dessus reviendrait à en faire un widget de plus.
 *
 * Le bouton nomme sa destination (« Classement ») plutôt que d'afficher un
 * « Retour » générique : c'est le seul moyen de sortir d'ici, il doit dire où
 * il mène.
 */

// Largeur de la voiture, et hauteur qui s'en déduit du rapport du viewBox
// (141.12 × 288.09). Ce sont les dimensions **à taille pleine** : la piste les
// réduit toutes les deux, du même facteur, quand elle n'a pas la place de les
// porter sans chevauchement (voir `dispositionDesVoitures`).
//
// **Les deux valeurs ont changé avec le nouveau dessin, sans que la piste
// bouge.** L'ancien `assets/voiture.svg` portait près de deux fois la largeur
// du dessin en marge vide : sa boîte de 56 × 68 ne montrait qu'une voiture de
// 29 × 59. La boîte est désormais celle du dessin, d'où 29 × 59.
const LARGEUR_VOITURE = 29;
const HAUTEUR_VOITURE = Math.round(LARGEUR_VOITURE * (288.09 / 141.12));

// Marge au-dessus de la première voiture et au-dessous de la dernière.
const MARGE_HAUTE = 16;
const MARGE_BASSE = 12;

// Gouttières entre deux voitures. Elles **s'ajoutent** à la boîte du dessin et
// ne l'entament jamais : le pas est donc toujours strictement supérieur à la
// dimension de la voiture, et deux voitures ne peuvent pas se toucher.
//
// C'est ce qui change avec cette version. L'écart vertical valait
// `0,9 × HAUTEUR_VOITURE`, soit six pixels **de moins** que la voiture
// elle-même : deux boîtes consécutives se recouvraient déjà par construction.
const GOUTTIERE_VERTICALE = 6;
const GOUTTIERE_HORIZONTALE = 10;
const PAS_VERTICAL = HAUTEUR_VOITURE + GOUTTIERE_VERTICALE;
const PAS_HORIZONTAL = LARGEUR_VOITURE + GOUTTIERE_HORIZONTALE;

// Place réservée à la légende, **de chaque côté** de la piste. Elle est prise
// symétriquement pour que la rangée reste centrée sur la route : 28px de
// décalage (`right-7`) plus la largeur maximale du texte (76px). Réservée du
// seul côté droit, elle donnerait plus de place aux voitures mais décalerait
// toute la grille vers la gauche, ce qui se lirait comme un défaut de calage.
const ZONE_LEGENDE = 104;

// Hauteur des deux formes de légende, mesurée sur le rendu : le score seul
// (15px), puis le score et son unité.
//
// **La légende ne rapetisse pas avec la voiture**, et c'est voulu : un score de
// neuf pixels de haut ne se lit plus. C'est son contenu qui se réduit quand la
// place manque — l'unité tombe en dernier. Sans ce palier, deux légendes
// voisines se recouvraient dès que les voitures se resserraient, ce que
// l'aperçu rendu avec la feuille compilée montrait sans équivoque.
//
// Il y avait un troisième palier, le plus haut, qui portait le pseudo ou le
// nombre d'ex æquo. **La légende ne dit plus que le score**, et ce palier n'a
// donc plus d'objet : la légende est deux fois plus courte, et deux groupes
// proches se recouvrent d'autant moins.
const LEGENDE_REDUITE = 33;

// En deçà, la voiture n'est plus qu'une tache. On ne descend jamais jusqu'à
// zéro, qui rendrait un SVG de taille nulle.
const ECHELLE_MINIMALE = 0.08;

// Décalage d'entrée entre deux voitures — doit rester égal à --voiture-stagger.
const RETARD_ENTREE = 100;

/**
 * Les membres regroupés par score, dans l'ordre du classement.
 *
 * Le regroupement se fait sur les **voisins immédiats** et non sur une table de
 * scores : `classement_du_championnat` trie déjà par points décroissants, donc
 * deux membres à égalité sont toujours consécutifs, et grouper les voisins
 * garantit que l'ordre affiché reste exactement celui du classement — départage
 * de la règle 4.6 compris.
 *
 * `total_points` peut valoir `null` pour qui n'a rien marqué (convention de
 * l'étape 6) : il est ramené à 0, sans quoi deux membres sans le moindre
 * pronostic noté ne seraient jamais regroupés, `null !== null` étant faux.
 * L'index d'origine voyage avec le membre — c'est lui qui donne le retard
 * d'entrée, et il doit rester celui du classement, pas celui du groupe.
 */
export function grouperParScore(lignes) {
  const groupes = [];

  lignes.forEach((ligne, index) => {
    const points = ligne.total_points ?? 0;
    const dernier = groupes[groupes.length - 1];

    if (dernier && dernier.points === points) dernier.membres.push({ ligne, index });
    else groupes.push({ points, membres: [{ ligne, index }] });
  });

  return groupes;
}

/**
 * Où se pose chaque voiture, et où se pose la légende de chaque score.
 *
 * **Un score, une hauteur.** C'est la règle qui gouverne tout le reste : la
 * position verticale dit les points, donc deux membres à égalité doivent se
 * poser à la même hauteur — et se répartir **latéralement**, côte à côte,
 * centrés sur la route. Jusqu'ici la hauteur se calculait par membre : deux
 * scores identiques donnaient deux fois la même valeur, et les voitures se
 * superposaient au pixel près, l'une masquant l'autre entièrement.
 *
 * Un groupe trop nombreux pour tenir sur une seule rangée en occupe plusieurs,
 * empilées : c'est une grille de départ, et c'est exactement l'image qu'il faut
 * — le cas se produit surtout avant le premier Grand Prix, quand tout le monde
 * est encore à zéro.
 *
 * **Aucune voiture n'en chevauche une autre, quelle que soit la configuration
 * de scores**, et c'est obtenu en deux temps :
 *
 * 1. Les pas horizontal et vertical valent la dimension du dessin **plus** une
 *    gouttière. Deux boîtes voisines ne peuvent donc pas se rencontrer.
 * 2. Quand la piste n'a pas la hauteur de porter toutes les rangées à ce
 *    pas-là, ce sont **les voitures qui rapetissent**, du même facteur en
 *    largeur et en hauteur, jamais l'écart qui se referme. C'est le seul moyen
 *    de tenir la garantie sur un championnat où chacun a son propre score
 *    (règle 4.5 : aucune limite de membres) ; le prix en est une voiture plus
 *    petite, ce qui se voit, là où un chevauchement rendait la vue muette.
 *
 * Le placement reste **proportionnel aux points** : le leader se pose tout en
 * haut, un groupe à la moitié de ses points à mi-piste. Les deux passes de
 * relaxation qui suivent imposent l'écart minimal, la descendante depuis le
 * leader, la montante en rattrapant ce qui a débordé en bas.
 */
export function dispositionDesVoitures(lignes, hauteur, largeur) {
  const vide = {
    echelle: 1,
    largeurVoiture: LARGEUR_VOITURE,
    hauteurVoiture: HAUTEUR_VOITURE,
    voitures: [],
    legendes: [],
  };
  if (lignes.length === 0 || hauteur <= 0) return vide;

  const groupes = grouperParScore(lignes);

  // Combien de voitures tiennent côte à côte, mesuré à taille pleine : le
  // nombre de rangées ne doit pas dépendre de l'échelle, qui en dépend
  // elle-même. Une largeur non encore mesurée laisse une voiture par rangée,
  // c'est-à-dire le comportement d'avant, jamais une division par zéro.
  const utile = Math.max(0, (largeur || 0) - 2 * ZONE_LEGENDE);
  const parRangee = Math.max(1, Math.floor(utile / PAS_HORIZONTAL));

  const rangees = [];
  groupes.forEach((groupe, indexGroupe) => {
    for (let debut = 0; debut < groupe.membres.length; debut += parRangee) {
      rangees.push({
        indexGroupe,
        membres: groupe.membres.slice(debut, debut + parRangee),
      });
    }
  });

  const disponible = hauteur - MARGE_HAUTE - MARGE_BASSE;
  const requis = (rangees.length - 1) * PAS_VERTICAL + HAUTEUR_VOITURE;
  const echelle = Math.min(1, Math.max(ECHELLE_MINIMALE, disponible / requis));

  const hauteurVoiture = HAUTEUR_VOITURE * echelle;
  const largeurVoiture = LARGEUR_VOITURE * echelle;
  const pasHorizontal = PAS_HORIZONTAL * echelle;

  const haut = MARGE_HAUTE + hauteurVoiture / 2;
  const bas = Math.max(haut, hauteur - MARGE_BASSE - hauteurVoiture / 2);
  const course = bas - haut;

  // L'écart tient dans la course par construction, l'échelle ayant été choisie
  // pour cela. Le plafond ne sert que dans le cas dégénéré où elle a buté sur
  // `ECHELLE_MINIMALE` : tout le monde reste alors à l'écran, ce qui vaut mieux
  // qu'une voiture invisible sortie de la piste.
  const ecart =
    rangees.length > 1
      ? Math.min(PAS_VERTICAL * echelle, course / (rangees.length - 1))
      : 0;

  const maximum = Math.max(...groupes.map((groupe) => groupe.points), 0);

  const centres = rangees.map(({ indexGroupe }) => {
    const fraction = maximum > 0 ? groupes[indexGroupe].points / maximum : 0;
    return bas - fraction * course;
  });

  for (let i = 1; i < centres.length; i += 1) {
    centres[i] = Math.max(centres[i], centres[i - 1] + ecart);
  }
  centres[centres.length - 1] = Math.min(centres[centres.length - 1], bas);
  for (let i = centres.length - 2; i >= 0; i -= 1) {
    centres[i] = Math.min(centres[i], centres[i + 1] - ecart);
  }

  // Les voitures d'une rangée sont réparties autour de son axe : le décalage du
  // j-ième d'une rangée de k vaut `(j - (k-1)/2)` pas. Une rangée seule reste
  // donc exactement au centre de la route, comme avant cette version.
  const voitures = [];
  rangees.forEach((rangee, indexRangee) => {
    const taille = rangee.membres.length;
    rangee.membres.forEach(({ ligne, index }, place) => {
      voitures.push({
        ligne,
        index,
        centre: centres[indexRangee],
        decalage: (place - (taille - 1) / 2) * pasHorizontal,
      });
    });
  });

  // Une seule légende par score — les membres d'un groupe ont le même par
  // définition, et en poser une par voiture les empilerait toutes au même
  // endroit, à droite, illisibles. Elle se cale au milieu des rangées du
  // groupe.
  const legendes = groupes.map((groupe, indexGroupe) => {
    const siennes = centres.filter(
      (_, index) => rangees[index].indexGroupe === indexGroupe,
    );
    return {
      points: groupe.points,
      membres: groupe.membres.map(({ ligne }) => ligne),
      premier: groupe.membres[0].index,
      centre: (siennes[0] + siennes[siennes.length - 1]) / 2,
    };
  });

  // Ce que chaque légende a la place de dire. La mesure porte sur l'espace
  // réellement disponible **autour d'elle**, pas sur le pas moyen : deux
  // groupes proches se réduisent, sans imposer la même réduction à tout le
  // monde. La première et la dernière n'ont qu'un voisin.
  legendes.forEach((legende, index) => {
    const avant = index > 0 ? legende.centre - legendes[index - 1].centre : Infinity;
    const apres =
      index < legendes.length - 1 ? legendes[index + 1].centre - legende.centre : Infinity;
    const espace = Math.min(avant, apres);

    legende.variante = espace >= LEGENDE_REDUITE ? "reduite" : "minimale";
  });

  return { echelle, largeurVoiture, hauteurVoiture, voitures, legendes };
}

/**
 * Une voiture sur la piste.
 *
 * L'élément animé porte `translateY` pour son entrée : le décalage latéral ne
 * peut donc pas vivre sur lui, les deux transformations s'écraseraient. Il est
 * posé sur un conteneur intérieur, en `left`, ce qui laisse l'animation
 * intacte quel que soit le nombre de voitures de la rangée.
 *
 * Exporté nommément pour pouvoir être rendu hors navigateur : le composant
 * d'écran, lui, dépend de la session, qui ne se résout que dans un effet.
 *
 * Depuis l'étape 8, la voiture porte les **vraies couleurs** du membre et le
 * **numéro qu'il a choisi** — l'une et l'autre servies par le classement. Le
 * rang ne s'affiche que faute de numéro choisi.
 *
 * `livreeDuMembre` décide de ce qui est peint : un membre qui a choisi une
 * livrée d'écurie roule ici dans cette livrée, exactement comme sur son
 * profil. C'est la même fonction des deux côtés — deux lectures séparées de
 * `livree_mode` finiraient par se contredire.
 */
export function VoitureSurPiste({
  ligne,
  centre,
  decalage,
  largeurVoiture,
  hauteurVoiture,
  hauteur,
  retard,
}) {
  const voiture = livreeDuMembre(ligne);
  const numero = ligne.numero ?? ligne.rang;

  return (
    <div
      className="t-voiture absolute inset-x-0"
      style={{
        top: `${centre - hauteurVoiture / 2}px`,
        height: `${hauteurVoiture}px`,
        // Chaque voiture part du bas de l'écran : la distance dépend de son
        // point d'arrivée, une valeur commune ferait démarrer le leader du
        // milieu de la piste.
        "--voiture-depart": `${hauteur - centre + hauteurVoiture}px`,
        "--voiture-retard": `${retard}ms`,
      }}
    >
      <div
        className="absolute top-0 -translate-x-1/2"
        style={{
          left: `calc(50% + ${decalage}px)`,
          width: `${largeurVoiture}px`,
          height: `${hauteurVoiture}px`,
        }}
      >
        <Voiture
          {...voiture}
          numero={numero}
          nom={ligne.pseudo}
          titre={`${ligne.rang}. ${ligne.pseudo}, ${ligne.total_points ?? 0} points`}
          className="h-full w-full"
        />
      </div>
    </div>
  );
}

/**
 * La légende d'un score, à droite de la rangée qu'elle chiffre.
 *
 * **Elle ne porte que le score, et aucun libellé.** Elle affichait auparavant
 * le pseudo sur un groupe d'un seul, et « N ex æquo » sur un groupe à égalité :
 * les deux sont retirés. Le premier faisait doublon — le pseudo est déjà peint
 * sur l'aileron arrière de la voiture (section 5), à quelques pixels de là. Le
 * second nommait un fait que la piste montre déjà, deux voitures posées à la
 * même hauteur, et il occupait la place au moment précis où elle manque le
 * plus. Le nom complet reste porté par chaque voiture, pour le lecteur d'écran
 * comme au survol.
 *
 * `estMoi` survit à ce retrait et garde son rôle : ma propre ligne passe au
 * blanc plein, les autres restent à 90 %. C'est le seul repère qui me situe
 * d'un coup d'œil maintenant que plus aucun nom n'est écrit ici.
 *
 * L'ombre portée n'est pas décorative : ce texte passe tantôt sur l'asphalte,
 * tantôt sur une bordure blanche, et doit rester lisible sur les deux.
 */
export function LegendeDeGroupe({ legende, hauteur, retard, moi }) {
  const estMoi = legende.membres.some((membre) => membre.profil_id === moi);

  return (
    <div
      className="t-voiture pointer-events-none absolute inset-x-0"
      style={{
        top: `${legende.centre}px`,
        "--voiture-depart": `${hauteur - legende.centre}px`,
        "--voiture-retard": `${retard}ms`,
      }}
    >
      <div className="absolute right-7 -translate-y-1/2 text-right [text-shadow:0_1px_3px_rgba(0,0,0,0.8)]">
        <p
          className={`text-[15px] leading-none font-medium ${
            estMoi ? "text-white" : "text-white/90"
          }`}
        >
          {legende.points}
        </p>
        {legende.variante !== "minimale" && (
          <p className="text-label-sm mt-1 text-white/70">pts</p>
        )}
      </div>
    </div>
  );
}

export default function Piste() {
  const { id } = useParams();
  const naviguer = useNavigate();
  const { utilisateur } = useAuth();

  const cleChamp = utilisateur ? `championnat:${utilisateur.id}:${id}` : null;
  const chargeurChamp = useCallback(
    (signal) => chargerChampionnat(id, signal),
    [id],
  );
  const { donnees: championnat } = useDonnees(cleChamp, chargeurChamp);

  const cle = utilisateur ? cleClassement(utilisateur.id, id) : null;
  const chargeur = useCallback((signal) => chargerClassement(id, signal), [id]);
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const lignes = useMemo(() => donnees ?? [], [donnees]);

  // La piste est mesurée, pas devinée : sa hauteur dépend de l'écran et, sur
  // iOS, elle change quand la barre d'adresse de Safari se rétracte.
  //
  // **Sa largeur est mesurée elle aussi depuis cette version.** C'est elle qui
  // décide combien de voitures à égalité tiennent côte à côte sur une rangée ;
  // la supposer reviendrait à en superposer deux sur un écran étroit, c'est-à-
  // dire le défaut qu'on corrige.
  const zone = useRef(null);
  const [taille, setTaille] = useState({ hauteur: 0, largeur: 0 });

  useEffect(() => {
    const element = zone.current;
    if (!element) return undefined;

    const observateur = new ResizeObserver(([entree]) => {
      setTaille({
        hauteur: entree.contentRect.height,
        largeur: entree.contentRect.width,
      });
    });
    observateur.observe(element);
    return () => observateur.disconnect();
  }, []);

  const { hauteur, largeur } = taille;

  // Les voitures montent une fois qu'elles ont une position à rejoindre :
  // les lancer avant la mesure les ferait converger vers zéro puis sauter.
  const [enPiste, setEnPiste] = useState(false);
  useEffect(() => {
    if (hauteur <= 0 || lignes.length === 0) return undefined;
    const image = requestAnimationFrame(() => setEnPiste(true));
    return () => cancelAnimationFrame(image);
  }, [hauteur, lignes.length]);

  const disposition = useMemo(
    () => dispositionDesVoitures(lignes, hauteur, largeur),
    [lignes, hauteur, largeur],
  );

  return (
    <main
      className={`piste-fond t-piste fixed inset-0 flex flex-col overflow-hidden ${
        enPiste ? "is-en-piste" : ""
      }`}
    >
      {/* Bordures et ligne médiane : posées sous tout le reste, sur toute la
          hauteur de l'écran, y compris derrière les zones sûres. Une piste qui
          s'arrêterait à la Dynamic Island se lirait comme un bandeau. */}
      <div
        aria-hidden="true"
        className="piste-kerb pointer-events-none absolute inset-y-0 left-0"
      />
      <div
        aria-hidden="true"
        className="piste-kerb pointer-events-none absolute inset-y-0 right-0"
      />
      <div
        aria-hidden="true"
        className="piste-axe pointer-events-none absolute inset-y-0 left-1/2 -translate-x-1/2"
      />

      <header
        className="relative z-10 shrink-0 px-7 pb-3"
        style={{
          // Le bouton ne doit pas venir se coller sous la Dynamic Island :
          // la zone sûre s'ajoute au rembourrage, elle ne le remplace pas.
          paddingTop: "calc(var(--spacing-safe-top) + 12px)",
        }}
      >
        <button
          type="button"
          onClick={() => naviguer(`/championnats/${id}`)}
          className="min-h-tactile pressable -mx-2 -my-2 flex items-center gap-1.5 px-2 py-2 text-[13px] font-medium text-white"
        >
          <IconeChevronGauche className="size-[15px] shrink-0" />
          <span className="truncate">Classement</span>
        </button>
      </header>

      {/* La ligne d'arrivée en damier et son libellé vivaient ici. Ils sont
          retirés : la piste va désormais du bouton de retour au nom du
          championnat sans interruption, et `MARGE_HAUTE` suffit à empêcher la
          voiture de tête de venir toucher l'en-tête. La règle CSS
          `.piste-arrivee` est partie avec eux — c'était du CSS de projet écrit
          pour cet élément-là, pas un snippet vendu, et le garder n'aurait servi
          qu'à peser dans chaque feuille. */}
      <div ref={zone} className="relative flex-1">
        {/* Les voitures d'abord, les légendes ensuite : à égalité de points
            plusieurs voitures partagent une hauteur, et une seule légende en
            chiffre le score. Le retard d'entrée reste celui du **classement** et non celui
            de la rangée, pour que la cascade suive l'ordre des rangs. */}
        {disposition.voitures.map((placement) => (
          <VoitureSurPiste
            key={placement.ligne.profil_id}
            ligne={placement.ligne}
            centre={placement.centre}
            decalage={placement.decalage}
            largeurVoiture={disposition.largeurVoiture}
            hauteurVoiture={disposition.hauteurVoiture}
            hauteur={hauteur}
            retard={placement.index * RETARD_ENTREE}
          />
        ))}

        {disposition.legendes.map((legende) => (
          <LegendeDeGroupe
            key={`${legende.points}-${legende.premier}`}
            legende={legende}
            hauteur={hauteur}
            retard={legende.premier * RETARD_ENTREE}
            moi={utilisateur?.id}
          />
        ))}

        {/* Squelette de la piste : des silhouettes de voitures aux bonnes
            hauteurs, pas un texte. Elles sont volontairement peintes en blanc
            translucide et non dans le gris `#E8E0D8` des autres écrans — c'est
            le seul écran qui sorte de la surface `fond`, et un aplat beige clair
            posé sur l'asphalte s'y lirait comme une vraie voiture blanche. La
            silhouette, elle, est la même : voiture à gauche, score à droite. */}
        {lignes.length === 0 && chargement && (
          <div aria-hidden="true" className="absolute inset-0">
            {[0.14, 0.34, 0.54, 0.74].map((fraction, rang) => (
              <div
                key={fraction}
                className="absolute right-5 left-0 flex items-center gap-3"
                style={{ top: `${fraction * 100}%` }}
              >
                <div className="flex flex-1 justify-center">
                  <div
                    className="h-[52px] w-[38px] rounded-[10px] bg-white/10"
                    style={{ animation: `t-skel-pulse 1400ms ease-in-out ${rang * 140}ms infinite` }}
                  />
                </div>
                <div className="h-3 w-12 shrink-0 rounded-full bg-white/10" />
              </div>
            ))}
          </div>
        )}

        {/* Deux situations distinctes, et les confondre serait mentir : le
            classement a échoué, ou le championnat n'a réellement personne. */}
        {lignes.length === 0 && !chargement && (
          <div className="absolute inset-x-8 top-1/2 -translate-y-1/2 text-center">
            <p className="text-corps-sm text-white/70">
              {echec
                ? messageDeChargement(echec)
                : "Aucun membre à afficher sur la piste."}
            </p>
            {echec && (
              <button
                type="button"
                onClick={recharger}
                className="rounded-champ min-h-tactile pressable mt-3 inline-flex items-center justify-center bg-white/15 px-5 text-[14px] font-medium text-white"
              >
                Réessayer
              </button>
            )}
          </div>
        )}
      </div>

      {/* Le nom du championnat ferme l'écran en bas, au-dessus du home
          indicator : il dit de quel championnat on regarde la piste, sans
          rajouter d'en-tête.

          **Il porte davantage depuis que la ligne d'arrivée est partie** : il
          est le seul texte de chrome qui reste, et le seul repère qui situe la
          piste. Il passe donc de 11px en `#999` à 15px en blanc plein et
          graisse 500. Le gain n'est pas cosmétique — `text-white/50` sur
          l'asphalte `#1A1A1A` ne vaut que 5,3:1 de contraste, le blanc plein
          17,4:1.

          Les capitales et leur crénage positif sont conservés : c'est ce que la
          section 5 prescrit pour un label, et c'est aussi la règle d'/apple-design
          §15 — on resserre les grands textes, on espace les petits. La
          hiérarchie passe par la graisse et la taille, jamais par l'opacité.

          L'ombre portée est celle des légendes, et pour la raison exacte : le
          texte est centré, donc il croise la ligne médiane pointillée de la
          piste, elle-même en blanc à 50 %. */}
      <footer
        className="relative z-10 shrink-0 px-7 pt-2"
        style={{
          // `pb-safe-bottom` et `pb-3` écriraient la même propriété : la marge
          // du home indicator s'ajoute au rembourrage, elle ne le remplace pas.
          paddingBottom: "calc(var(--spacing-safe-bottom) + 12px)",
        }}
      >
        <p className="truncate text-center text-[15px] leading-none font-medium tracking-[0.7px] text-white uppercase [text-shadow:0_1px_3px_rgba(0,0,0,0.8)]">
          {championnat?.nom ?? ""}
        </p>
      </footer>
    </main>
  );
}
