import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import FondPiste from "../composants/FondPiste.jsx";
import Voiture from "../composants/Voiture.jsx";
import { IconeChevronGauche } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerChampionnat } from "../lib/championnats.js";
import { chargerClassement, cleClassement } from "../lib/classement.js";
import { couleurChampionnat, teinteMembre } from "../lib/couleurs.js";
import { messageDeChargement } from "../lib/erreurs.js";
import { livreeDuMembre } from "../lib/palette.js";
import { useDonnees } from "../lib/useDonnees.js";

/**
 * La vue piste — l'écran signature de l'app, refondu en version `0.49.0`.
 *
 * Trois choses ont changé, et la première commande les deux autres.
 *
 * **Le fond est la planche `assets/vue_piste.svg`**, extraite dans
 * `FondPiste.jsx`. Elle pose un sol **beige** `#F4EFEA`, à un point du
 * `--color-fond` de l'app, là où cet écran peignait jusqu'ici un asphalte
 * `#1A1A1A`. Toute l'encre s'inverse donc : le blanc qui tenait 17,4:1 sur le
 * noir ne vaut plus rien sur le beige, et c'est `--color-texte` qui prend le
 * relais, à 15,23:1. Le squelette, les états vides et la légende des scores
 * suivent tous ce basculement.
 *
 * **Le bandeau porte le nom du championnat**, dans sa couleur — la même que sa
 * carte d'accueil et que l'en-tête de son écran, puisée dans
 * `couleurChampionnat`. Le nom du championnat vivait auparavant en pied
 * d'écran ; l'y laisser l'aurait écrit deux fois.
 *
 * **Le placement des voitures est entièrement neuf** — voir
 * `dispositionDesVoitures`.
 *
 * Ce qui n'a pas bougé : la piste occupe l'écran entier, sans en-tête de
 * championnat ni barre de navigation, et un unique bouton en haut à gauche
 * ramène au classement. C'est l'écran signature ; lui laisser 150px de chrome
 * au-dessus reviendrait à en faire un widget de plus. Le bouton **nomme sa
 * destination** plutôt que d'afficher un « Retour » générique : c'est le seul
 * moyen de sortir d'ici, il doit dire où il mène.
 */

// La voiture à sa taille pleine, celle d'un groupe d'une seule. La hauteur se
// déduit du rapport du viewBox du dessin (141,12 × 288,09) — les onze livrées
// partagent cette boîte, elles se substituent sans qu'une valeur ne bouge.
const LARGEUR_VOITURE = 52;
const HAUTEUR_VOITURE = Math.round(LARGEUR_VOITURE * (288.09 / 141.12));

// Le plancher de réduction. En deçà, la voiture cesse de se lire comme une
// voiture. Il est **bas exprès** : à 18px de large, seize voitures tiennent
// côte à côte sur une piste de 354px avant que le plancher ne morde.
const LARGEUR_MINIMALE = 18;

// Au-delà de combien de voitures un groupe cesse de se serrer autour de l'axe
// et s'étale d'un kerb à l'autre.
//
// **Deux régimes, et c'est une décision de composition, pas une optimisation.**
// À deux ou trois, les voitures se rangent côte à côte au milieu de la piste,
// séparées de la seule gouttière : la proximité est ce qui dit qu'elles sont à
// égalité. La version `0.49.0` n'avait qu'un régime, et posait déjà deux ex
// æquo chacune au milieu de sa demi-piste — **125px de vide entre elles**, là
// où le dessin voulait dire « ces deux-là sont au coude à coude ». Elles en
// gardent 12.
//
// À quatre et au-delà, le serrage n'a plus rien à dire : un peloton se lit
// comme une grille de départ, et la grille occupe la piste.
const GROUPE_SERRE_MAX = 3;

// Gouttière entre deux voitures d'un même groupe. Elle **s'ajoute** à la boîte
// du dessin et ne l'entame jamais.
//
// Elle sert les deux régimes, et ce n'est pas la même gouttière qui est dite
// deux fois : c'est la même distance entre deux voitures voisines, qu'elles se
// serrent au centre ou qu'elles s'étalent en cellules. Dans le régime étalé,
// les voitures étant centrées dans des cellules de largeur égale, **la moitié
// de la gouttière tient lieu de marge aux deux voitures extérieures**. À 8, la
// première d'un groupe de douze passait à quatre pixels du kerb et paraissait
// le mordre ; à 12, elle en garde six, ce qui se lit comme une marge.
const GOUTTIERE_HORIZONTALE = 12;

// Marges au-dessus de la première voiture et au-dessous de la dernière. La zone
// de jeu s'étend de l'une à l'autre : le meilleur score se pose tout en haut,
// le dernier tout en bas, et l'échelle occupe donc toujours l'écran entier.
const MARGE_HAUTE = 20;
const MARGE_BASSE = 16;

// La place que prend le score sous une voiture. Elle entre dans l'empreinte
// verticale d'une voiture — voir la note sur le seuil dans
// `regrouperParChevauchement`.
const HAUTEUR_LEGENDE = 16;

/* **Rien n'est plus réservé AU-DESSUS d'une voiture** (version `0.52.0`).

   La version `0.50.0` y posait une pastille d'identité, et la version `0.51.0`
   une photo dedans. Toutes deux coûtaient trente pixels de zone de jeu **à tout
   le championnat** dès qu'un seul membre avait une photo : les scores se
   tassaient au bénéfice d'une rangée de ronds. La photo est désormais découpée
   dans le cockpit de la voiture (`Voiture.jsx`), c'est-à-dire dans une place que
   le dessin occupait déjà — et l'échelle des scores retrouve exactement la
   hauteur qu'elle avait avant les photos, au pixel près.

   `coiffeDesVoitures`, `HAUTEUR_AVATAR` et `ESPACE_AVATAR` partent avec, ainsi
   que le paramètre `coiffe` des trois passes : ce n'est pas du code éprouvé mis
   de côté, c'est une correction dont il ne reste rien à corriger. */

// Décalage d'entrée entre deux voitures — doit rester égal à --voiture-stagger.
const RETARD_ENTREE = 100;

/** Les points d'une ligne de classement. `total_points` vaut `null` pour qui
 *  n'a rien marqué (convention de l'étape 6) : le `null` est ramené à 0, sans
 *  quoi deux membres sans le moindre pronostic noté ne se compareraient jamais,
 *  `null === null` étant vrai mais `null - null` valant 0 par accident. */
function pointsDe(ligne) {
  return ligne.total_points ?? 0;
}

/**
 * **Passe 1 — l'échelle verticale.**
 *
 * Le meilleur score se pose en haut de la zone de jeu, le moins bon en bas, et
 * chaque score intermédiaire se place proportionnellement entre les deux.
 * L'échelle est donc **tendue sur les scores réels**, jamais sur une valeur
 * fixe : la zone de jeu est intégralement utilisée quelle que soit la saison,
 * qu'elle sépare 0 et 28 points ou 1 240 et 1 260.
 *
 * **Tout le monde à égalité se pose à mi-hauteur.** C'est le cas d'avant le
 * premier Grand Prix, quand chacun est encore à zéro : il n'y a pas d'échelle à
 * tendre, et coller la grille en haut ou en bas dirait quelque chose de faux.
 *
 * Les hauteurs sortent d'ici **exactes**, sans aucune correction d'écart : rien
 * n'est repoussé, rien n'est relâché. Deux scores identiques rendent donc
 * exactement la même valeur — c'est ce qui garantit que deux ex æquo forment
 * toujours un groupe à la passe 2.
 *
 * Les bornes sont calculées à la **taille pleine** de la voiture, la seule
 * connue à ce stade : la taille se déduit des groupes, qui se déduisent des
 * hauteurs. La légende compte dans la borne basse, sinon le score du dernier
 * sortirait sous la piste. Elle vaut sa taille PLEINE ici : un groupe réduit
 * occupe moins, jamais plus, donc la borne reste juste.
 */
export function hauteursParScore(lignes, hauteur) {
  const haut = MARGE_HAUTE + HAUTEUR_VOITURE / 2;
  const bas = Math.max(
    haut,
    hauteur - MARGE_BASSE - HAUTEUR_LEGENDE - HAUTEUR_VOITURE / 2,
  );

  const points = lignes.map(pointsDe);
  const maximum = Math.max(...points);
  const minimum = Math.min(...points);

  if (maximum === minimum) return points.map(() => (haut + bas) / 2);

  return points.map(
    (valeur) => haut + ((maximum - valeur) / (maximum - minimum)) * (bas - haut),
  );
}

/**
 * **Passe 2a — le regroupement, purement géométrique.**
 *
 * Deux voitures se chevauchent quand l'écart de leurs hauteurs est plus petit
 * que l'empreinte d'une voiture. Le regroupement se propage en cascade : si A
 * chevauche B et B chevauche C, les trois n'en font qu'un, **même si A et C ne
 * se touchent pas**. C'est pour cela que la comparaison porte sur la voiture
 * précédente et non sur la première du groupe.
 *
 * > ### Un groupe dit qui se résout ensemble, **jamais combien de voies**
 * >
 * > C'est la correction de la version `0.70.0`, et la cascade en est la raison
 * > même. Jusqu'à la `0.69.0`, `dispositionDesVoitures` donnait **une place
 * > latérale par membre** du groupe, distribuée dans l'ordre du classement.
 * > Or la cascade réunit tout le plateau dès que les écarts consécutifs
 * > passent sous le seuil — ce qui arrive à partir de **sept membres** sur une
 * > piste de 700px, où l'écart moyen tombe à 85px pour un seuil de 122. Le
 * > premier partait alors à l'extrême gauche, le dernier à l'extrême droite, et
 * > l'abscisse montait avec le rang exactement comme la hauteur : **l'escalier
 * > diagonal signalé**. Huit membres se retrouvaient en prime réduits à 32px
 * > alors que la piste avait la place de les tenir tous à 52.
 * >
 * > A et C, que la cascade réunit sans qu'elles se touchent, peuvent partager
 * > la même abscisse. C'est `voiesDuGroupe` qui le voit.
 *
 * **Rien ici ne regarde les scores.** Deux scores voisins mais distincts sont
 * regroupés si et seulement si leurs voitures se rencontrent à l'écran, et deux
 * ex æquo le sont toujours, puisque la passe 1 leur rend la même hauteur au
 * flottant près.
 *
 * > ### Écart assumé par rapport à la demande : le seuil vaut la voiture **et
 * > sa légende**
 * >
 * > La demande écrit « inférieure à la hauteur d'une voiture ». Le seuil retenu
 * > est `HAUTEUR_VOITURE + HAUTEUR_LEGENDE`, parce que chaque voiture porte son
 * > score sous elle : son empreinte à l'écran est celle du dessin **plus** celle
 * > du chiffre. Au seuil littéral, deux groupes tout juste séparés se touchent
 * > par construction — la légende du groupe du dessus se poserait sur le museau
 * > de la voiture du dessous. Le seuil décrit bien « la hauteur d'une voiture »,
 * > au sens de ce qu'elle occupe.
 *
 * Les lignes arrivent triées par points décroissants
 * (`classement_du_championnat`), donc par hauteur croissante : le balayage se
 * fait dans l'ordre du classement, une seule fois.
 */
export function regrouperParChevauchement(hauteurs) {
  const seuil = HAUTEUR_VOITURE + HAUTEUR_LEGENDE;
  const groupes = [];

  hauteurs.forEach((centre, index) => {
    const dernier = groupes[groupes.length - 1];
    const precedent = dernier?.membres[dernier.membres.length - 1];

    if (precedent !== undefined && centre - hauteurs[precedent] < seuil) {
      dernier.membres.push(index);
    } else {
      groupes.push({ membres: [index] });
    }
  });

  return groupes;
}

/**
 * **Passe 2b — les voies d'un groupe : qui peut partager une abscisse.**
 *
 * Reçoit les hauteurs d'un groupe, dans l'ordre du classement, et rend pour
 * chacune l'indice de la voie où sa voiture se pose. Deux voitures d'une même
 * voie sont écartées d'au moins l'empreinte d'une voiture : elles peuvent donc
 * partager une abscisse sans se toucher.
 *
 * **C'est ici que l'escalier se défait.** Un groupe de huit voitures que la
 * cascade a réunies n'a pas besoin de huit abscisses : si chacune ne chevauche
 * que sa voisine immédiate, **deux voies suffisent**, et les voitures gardent
 * leur taille pleine au lieu d'être réduites au huitième de la piste.
 *
 * L'algorithme est le placement au premier libre, et il est **optimal** ici :
 * les hauteurs arrivant triées, le nombre de voies ouvertes à un instant donné
 * est exactement le nombre de voitures qui se chevauchent à cet endroit. Aucune
 * voie n'est ouverte sans qu'une voiture ne l'exige.
 *
 * > ### Le cycle des voies est une contrainte de géométrie, pas un défaut
 * >
 * > Douze scores réguliers demandent trois voies, et les voitures les occupent
 * > en cycle — gauche, milieu, droite, gauche… Aucun placement n'y échappe :
 * > trois voitures qui se chevauchent mutuellement **doivent** occuper trois
 * > abscisses distinctes. Ce qui est parti, c'est la rampe unique qui traversait
 * > la piste en entier ; ce qui reste dit une vérité — ces voitures-là sont
 * > serrées.
 *
 * Le seuil est celui de `regrouperParChevauchement`, et pour la même raison :
 * une voiture occupe son dessin **plus** le score écrit dessous. Il se mesure à
 * la hauteur PLEINE, la seule connue à ce stade — une voiture réduite occupe
 * moins, jamais plus, donc la voie reste libre à bon droit.
 */
export function voiesDuGroupe(hauteurs) {
  const seuil = HAUTEUR_VOITURE + HAUTEUR_LEGENDE;
  // La hauteur de la dernière voiture posée sur chaque voie. Les hauteurs étant
  // croissantes, c'est la seule dont l'écart puisse manquer.
  const dernieres = [];

  return hauteurs.map((centre) => {
    const voie = dernieres.findIndex((derniere) => centre - derniere >= seuil);

    if (voie === -1) {
      dernieres.push(centre);
      return dernieres.length - 1;
    }

    dernieres[voie] = centre;
    return voie;
  });
}

/**
 * **Passe 2c — la répartition latérale d'un groupe, et elle seule.**
 *
 * Rend la taille commune aux voitures du groupe et la fonction qui donne
 * l'abscisse d'une **voie**, comptée depuis le milieu de la piste. **Aucune
 * hauteur n'entre ici et aucune n'en sort** : la passe 1 les a fixées, elles ne
 * bougent plus d'un pixel. Deux voitures qui se rencontrent sont écartées
 * **latéralement**, jamais verticalement.
 *
 * **`nombre` est un nombre de voies, pas un nombre de membres** (version
 * `0.70.0`). Les confondre est précisément ce qui produisait l'escalier : un
 * groupe de huit peut n'ouvrir que deux voies, et il réclame alors deux
 * abscisses, pas huit. Une voie seule rend `0` — l'axe de la piste — ce qui est
 * le cas de toutes les voitures dès que les scores sont distincts **et**
 * suffisamment espacés pour que rien ne se chevauche.
 *
 * ### Deux régimes
 *
 * **Jusqu'à `GROUPE_SERRE_MAX`, les voies se serrent autour de l'axe.** Les
 * voitures gardent leur taille pleine et se rangent côte à côte, séparées de la
 * seule gouttière : deux se posent de part et d'autre du milieu, trois se
 * posent à gauche, au milieu et à droite. L'expression `place - (n - 1) / 2`
 * centre le groupe sans qu'aucun cas particulier ne soit écrit — elle vaut `0`
 * pour une voie seule, `-0,5` et `+0,5` pour deux, `-1`, `0` et `+1` pour
 * trois.
 *
 * **Au-delà, le groupe s'étale d'un kerb à l'autre**, sur des cellules de
 * largeur égale. Les centrer dans leur cellule centre le groupe sur la piste
 * sans qu'aucun calcul ne le demande, une cellule unique ayant son milieu au
 * milieu de la piste.
 *
 * ### La taille ne bouge que si la largeur manque
 *
 * La taille de base est **la même pour toute la piste**. Un groupe ne la réduit
 * que lorsque sa cellule devient plus étroite que la voiture, gouttière
 * comprise — et **seul ce groupe-là** est réduit ; les voitures qui ont la
 * place gardent leurs 52px. Sur une piste de 354px, cela n'arrive qu'à partir
 * de **six voies** : cinq tiennent encore à taille pleine
 * (5 × 52 + 4 × 12 = 308).
 *
 * > Depuis que le compte porte sur les voies et non sur les membres, la
 * > réduction est devenue **rare**. Vingt membres régulièrement espacés
 * > n'ouvrent que cinq voies sur une piste de 700px : ils tiennent tous à 52px,
 * > là où la version `0.69.0` les écrasait à 17,7. Il faut vingt voitures
 * > réellement empilées — donc vingt scores à un cheveu les uns des autres —
 * > pour retrouver ce cas.
 *
 * La réduction porte sur **les deux dimensions du même facteur** : une voiture
 * étirée cesserait d'être une voiture.
 *
 * **Le plancher peut faire déborder un groupe, et c'est le moindre mal.**
 * Les cellules d'une piste de 354px passent sous `LARGEUR_MINIMALE` à **vingt**
 * voitures dans le même groupe (354 / 20 = 17,7), et les voitures se recouvrent
 * alors de quelques dixièmes de pixel. L'alternative, descendre sans plancher,
 * rendrait des voitures de trois pixels, c'est-à-dire des taches. Un léger
 * recouvrement se lit encore comme une grille de départ ; une tache ne se lit
 * pas.
 *
 * > Le chiffre est **mesuré, pas prescrit** : la version `0.49.0` annonçait
 * > seize, où il reste en réalité 4,1px de gouttière. Le plancher lui-même
 * > mord plus tôt, dès **douze** (354 / 12 − 12 = 17,5), sans que rien ne se
 * > recouvre encore.
 *
 * > ### Le régime serré cède si la piste est trop étroite pour lui
 * >
 * > Trois voitures pleines demandent 180px. Une piste de téléphone en offre
 * > 291 au pire (un écran de 320px moins ses deux kerbs), donc le cas ne se
 * > rencontre pas sur la cible. La condition est écrite quand même : elle coûte
 * > une comparaison, et sans elle une fenêtre étroite ferait sortir les
 * > voitures de la piste au lieu de les réduire.
 */
export function repartitionLaterale(nombre, largeur) {
  const pas = LARGEUR_VOITURE + GOUTTIERE_HORIZONTALE;

  if (nombre <= GROUPE_SERRE_MAX && nombre * pas - GOUTTIERE_HORIZONTALE <= largeur) {
    return {
      largeurVoiture: LARGEUR_VOITURE,
      abscisse: (place) => (place - (nombre - 1) / 2) * pas,
    };
  }

  const cellule = largeur / nombre;
  const largeurVoiture = Math.max(
    LARGEUR_MINIMALE,
    Math.min(LARGEUR_VOITURE, cellule - GOUTTIERE_HORIZONTALE),
  );

  return {
    largeurVoiture,
    // Le milieu de la cellule, rapporté au milieu de la piste.
    abscisse: (place) => (place + 0.5) * cellule - largeur / 2,
  };
}

/**
 * **L'enchaînement des passes.**
 *
 * Elle enchaîne le regroupement géométrique, l'ouverture des voies et la
 * répartition latérale, et ne décide rien elle-même. La hauteur qu'elle recopie
 * est celle de la passe 1, **inchangée** : réduire une voiture ne la déplace
 * pas, l'écarter de l'axe non plus. Sa hauteur dit ses points, et elle seule.
 *
 * **Le décalage latéral n'a qu'une source, et c'est `repartitionLaterale`.**
 * Rien d'autre dans le fichier ni dans la feuille de style ne déplace une
 * voiture horizontalement : `.t-place` est posée à `left-1/2` et ne porte que
 * le `translate` calculé ici, `.t-voiture` n'anime qu'un `translateY`. Une
 * voiture dont la voie vaut `0` dans un groupe d'une seule voie est donc sur
 * l'axe, au pixel près.
 */
export function dispositionDesVoitures(lignes, hauteur, largeur) {
  if (lignes.length === 0 || hauteur <= 0 || largeur <= 0) return [];

  const hauteurs = hauteursParScore(lignes, hauteur);
  const placements = [];

  regrouperParChevauchement(hauteurs).forEach(({ membres }) => {
    // **Le groupe compte ses voies, jamais ses membres.** La cascade du
    // regroupement réunit des voitures qui ne se touchent pas deux à deux ;
    // leur donner une abscisse chacune est ce qui dessinait l'escalier.
    const voies = voiesDuGroupe(membres.map((index) => hauteurs[index]));
    const { largeurVoiture, abscisse } = repartitionLaterale(
      Math.max(...voies) + 1,
      largeur,
    );
    const echelle = largeurVoiture / LARGEUR_VOITURE;

    // **Le score s'efface quand la voiture a touché son plancher**, et
    // seulement là. C'est le signe que les cellules sont devenues plus étroites
    // que la voiture elle-même, donc plus étroites qu'un nombre à trois
    // chiffres : vingt scores écrits côte à côte dans dix-sept pixels chacun ne
    // font pas vingt nombres, ils font une bavure. Le classement les donne, et
    // la liste `sr-only` de cet écran aussi.
    //
    // **La photo du cockpit, elle, ne se juge plus ici.** Elle rétrécit avec la
    // voiture parce qu'elle EST la voiture : il n'y a rien à décrocher, et rien
    // à décider — le dessin décide pour elle.
    const scoreLisible = largeurVoiture > LARGEUR_MINIMALE;

    membres.forEach((index, place) => {
      placements.push({
        ligne: lignes[index],
        index,
        centre: hauteurs[index],
        decalage: abscisse(voies[place]),
        largeurVoiture,
        hauteurVoiture: HAUTEUR_VOITURE * echelle,
        // Le score ne rétrécit pas au même rythme que la voiture : sous 11px il
        // cesserait d'être lisible, et un chiffre illisible ne vaut pas mieux
        // qu'un chiffre absent.
        tailleScore: scoreLisible ? Math.max(11, Math.round(largeurVoiture * 0.26)) : 0,
      });
    });
  });

  return placements;
}

/**
 * Une voiture sur la piste, et son score sous elle.
 *
 * **Deux éléments emboîtés, deux propriétés de transformation distinctes.**
 * L'extérieur porte `translate` — sa place sur la piste, qui glisse quand les
 * scores changent. L'intérieur porte `.t-voiture`, dont l'entrée anime
 * `transform`. Posées sur un même élément, les deux s'écraseraient ; c'est le
 * piège déjà documenté pour le pouce de l'interrupteur, où Tailwind 4 écrit la
 * propriété indépendante `translate` et transitionner `transform` ne fait
 * rigoureusement rien.
 *
 * Le score est **sous chaque voiture, pas à côté du groupe**. La légende de
 * droite d'avant chiffrait un groupe, ce qui n'a plus de sens : un groupe est
 * désormais géométrique et peut réunir des scores différents. Elle occupait en
 * plus la marge que les voitures utilisent maintenant d'un kerb à l'autre.
 *
 * `estMoi` passe le score en graisse 500, les autres en 400 : la hiérarchie
 * passe par la graisse, jamais par l'opacité — les deux gardent leur 15,23:1
 * sur le beige de la piste.
 *
 * Exporté nommément pour pouvoir être rendu hors navigateur : le composant
 * d'écran, lui, dépend de la session, qui ne se résout que dans un effet.
 */
export function VoitureSurPiste({ placement, hauteur, retard, estMoi }) {
  const {
    ligne,
    centre,
    decalage,
    largeurVoiture,
    hauteurVoiture,
    tailleScore,
  } = placement;
  const voiture = livreeDuMembre(ligne);
  const numero = ligne.numero ?? ligne.rang;
  const points = pointsDe(ligne);

  return (
    <div
      className="t-place absolute top-0 left-1/2"
      style={{
        translate: `${decalage - largeurVoiture / 2}px ${
          centre - hauteurVoiture / 2
        }px`,
        width: `${largeurVoiture}px`,
      }}
    >
      <div
        className="t-voiture"
        style={{
          // Chaque voiture part du bas de l'écran : la distance dépend de son
          // point d'arrivée, une valeur commune ferait démarrer le leader du
          // milieu de la piste.
          "--voiture-depart": `${hauteur - centre + hauteurVoiture}px`,
          "--voiture-retard": `${retard}ms`,
        }}
      >
        {/* La hauteur est portée par une boîte, jamais par le SVG :
            `Voiture` ne prend pas de `style`, et la lui passer serait une
            prop muette que rien à l'écran ne signalerait. */}
        <div style={{ height: `${hauteurVoiture}px` }}>
          <Voiture
            {...voiture}
            numero={numero}
            nom={ligne.pseudo}
            /* L'identité entre DANS le dessin, dans le disque noir du casque.
               La teinte de repli est celle de `Pastille` — même graine, même
               table (`teinteMembre`) : le membre garde le rond qu'il a au
               classement, sans qu'aucune valeur ne soit recopiée ici. */
            photo={ligne.avatar_url}
            teintePilote={teinteMembre(ligne.profil_id || ligne.pseudo).hex}
            titre={`${ligne.rang}. ${ligne.pseudo}, ${points} points`}
            className="h-full w-full"
          />
        </div>
        {tailleScore > 0 && (
          <p
            aria-hidden="true"
            className={`text-texte mt-[3px] text-center tabular-nums ${
              estMoi ? "font-medium" : "font-normal"
            }`}
            style={{ fontSize: `${tailleScore}px`, lineHeight: 1 }}
          >
            {points}
          </p>
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

  // La couleur du championnat, jamais choisie ici : c'est la même que sur sa
  // carte d'accueil et que l'en-tête de son écran. Le repli sur la première
  // teinte couvre le premier rendu, avant que le championnat ne soit chargé —
  // un bandeau transparent laisserait voir le sol beige sous un texte blanc.
  const couleur = couleurChampionnat(championnat ?? { id });

  // La piste est mesurée, pas devinée. La zone de jeu est **bornée aux deux
  // kerbs** par sa feuille de style : sa largeur mesurée est donc directement
  // celle dont les voitures disposent, sans qu'aucune fraction de la planche ne
  // soit recopiée en JavaScript.
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

  // **La piste ne demande plus si quelqu'un a une photo.** La règle des trois
  // listes — la colonne de pastilles n'apparaît que si un membre en a une —
  // gouverne des LISTES, où une colonne vide se verrait. Ici il n'y a pas de
  // colonne : le cockpit existe sur chaque voiture, avec ou sans photo, et la
  // disposition ne dépend donc que des scores.
  const placements = useMemo(
    () => dispositionDesVoitures(lignes, hauteur, largeur),
    [lignes, hauteur, largeur],
  );

  return (
    <main
      className={`piste-sol t-piste fixed inset-0 flex flex-col overflow-hidden ${
        enPiste ? "is-en-piste" : ""
      }`}
    >
      {/* La planche, sous tout le reste et sur tout l'écran, zones sûres
          comprises. Une piste qui s'arrêterait à la Dynamic Island se lirait
          comme un bandeau posé de travers. */}
      <FondPiste className="pointer-events-none absolute inset-0 h-full w-full select-none" />

      {/* Le bandeau. Ordre de peinture : l'aplat, le damier, puis le contenu —
          le même ordre que les blocs de Grand Prix, et pour la même raison, un
          SVG comme un empilement de calques n'ayant pas d'autre `z-index` que
          celui-là. */}
      <header
        className="piste-bandeau relative z-10 shrink-0 overflow-hidden"
        style={{ backgroundColor: couleur.hex }}
      >
        <span
          aria-hidden="true"
          className="motif-damier pointer-events-none absolute inset-0"
        />

        {/* **Deux rangées : le retour, puis le nom centré sur ce qui reste.**
            C'est la disposition d'`EnTeteEcran`, et les deux autres ont été
            essayées puis écartées au rendu. Partager une seule rangée oblige à
            réserver les 110px du bouton **des deux côtés** pour que le nom
            reste centré sur la piste, et il ne resterait pas de quoi écrire un
            nom de championnat. Superposer le nom au bouton, lui, faisait se
            toucher les glyphes de « Classement » et ceux d'un nom long.

            Le rembourrage horizontal du nom couvre la courbe des coins bas de
            la planche : au plus bas de son corps, le coin ne mord que dix-neuf
            pixels sur les vingt-quatre réservés. */}
        <div className="relative h-full">
          <div
            className="flex shrink-0 items-center"
            style={{ height: "var(--piste-retour-h)" }}
          >
            <button
              type="button"
              onClick={() => naviguer(`/championnats/${id}`)}
              className="min-h-tactile pressable -my-1 flex items-center gap-1.5 px-4 py-1 text-[13px] font-medium text-white"
            >
              <IconeChevronGauche className="size-[15px] shrink-0" />
              <span>Classement</span>
            </button>
          </div>

          <h1
            className="text-titre absolute inset-x-6 truncate text-center text-white"
            style={{
              top: "calc(var(--piste-retour-h) + (100% - var(--piste-retour-h)) / 2)",
              transform: "translateY(-50%)",
            }}
          >
            {championnat?.nom ?? ""}
          </h1>
        </div>
      </header>

      {/* La zone de jeu, bornée aux deux kerbs de la planche : 24,88 et 561,17
          sur 589,5, mesurés sur les chemins et non déduits d'une tranche
          arithmétique. Les voitures y disposent donc de toute la largeur de la
          piste, et d'elle seule. */}
      <div
        ref={zone}
        className="relative flex-1"
        style={{ marginLeft: "4.2205%", marginRight: "4.8058%" }}
      >
        {placements.map((placement) => (
          <VoitureSurPiste
            key={placement.ligne.profil_id}
            placement={placement}
            hauteur={hauteur}
            retard={placement.index * RETARD_ENTREE}
            estMoi={placement.ligne.profil_id === utilisateur?.id}
          />
        ))}

        {/* La liste ordonnée que la piste dessine. Les voitures sont un dessin :
            leur `title` se lit au survol, pas au lecteur d'écran, et le score
            peint sous chacune est `aria-hidden` — « 28 » seul ne dit rien. */}
        {lignes.length > 0 && (
          <ol className="sr-only">
            {lignes.map((ligne) => (
              <li key={ligne.profil_id}>
                {`${ligne.rang}. ${ligne.pseudo}, ${pointsDe(ligne)} points`}
              </li>
            ))}
          </ol>
        )}

        {/* Squelette de la piste : des silhouettes aux bonnes hauteurs, pas un
            texte. Elles passent du blanc translucide au gris `squelette` du
            reste de l'app — c'est la planche beige qui le permet, là où
            l'asphalte sombre d'avant l'aurait fait lire comme une vraie
            voiture blanche. */}
        {lignes.length === 0 && chargement && (
          <div aria-hidden="true" className="absolute inset-0">
            {[0.12, 0.34, 0.56, 0.78].map((fraction, rang) => (
              <div
                key={fraction}
                className="bg-squelette absolute left-1/2 -translate-x-1/2 rounded-[12px]"
                style={{
                  top: `${fraction * 100}%`,
                  width: `${LARGEUR_VOITURE}px`,
                  height: `${HAUTEUR_VOITURE}px`,
                  animation: `t-skel-pulse 1400ms ease-in-out ${rang * 140}ms infinite`,
                }}
              />
            ))}
          </div>
        )}

        {/* Deux situations distinctes, et les confondre serait mentir : le
            classement a échoué, ou le championnat n'a réellement personne. */}
        {lignes.length === 0 && !chargement && (
          <div className="absolute inset-x-6 top-1/2 -translate-y-1/2 text-center">
            <p className="text-corps-sm text-secondaire">
              {echec
                ? messageDeChargement(echec)
                : "Aucun membre à afficher sur la piste."}
            </p>
            {echec && (
              <button
                type="button"
                onClick={recharger}
                className="rounded-champ min-h-tactile pressable bg-primaire mt-3 inline-flex items-center justify-center px-5 text-[14px] font-medium text-white"
              >
                Réessayer
              </button>
            )}
          </div>
        )}
      </div>

      {/* Le pied d'écran ne porte plus rien. Il tient la marge du home
          indicator, que la planche court sous elle mais qu'aucune voiture ne
          doit atteindre — le nom du championnat qui vivait ici est passé dans
          le bandeau, et l'écrire aux deux bouts de l'écran serait le dire deux
          fois. */}
      <div
        aria-hidden="true"
        className="shrink-0"
        style={{ height: "var(--spacing-safe-bottom)" }}
      />
    </main>
  );
}
