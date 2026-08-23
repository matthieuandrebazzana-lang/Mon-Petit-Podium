import { useId } from "react";
import { encreSurAplat } from "../lib/couleurs.js";
import { COULEUR1_DEFAUT, COULEUR2_DEFAUT, encreSur } from "../lib/palette.js";
import { usePhotoDetachee } from "../lib/usePhoto.js";
import {
  aUneLivree,
  formesLivree,
  geometrieLivree,
} from "./VoituresEcuries.jsx";

/**
 * La voiture vue du dessus, dans ses deux modes.
 *
 * - **Ma livrée** (`mode: "perso"`) — la première voiture de
 *   `assets/voitures_perso.svg`, repeinte par les deux couleurs du membre.
 * - **Livrée écurie** (`mode: "ecurie"`) — l'une des onze voitures de
 *   `assets/voitures_ecuries.svg`, dont les couleurs sont fixes.
 *
 * **Extraction, jamais reproduction.** Les géométries sont celles des planches,
 * coordonnée pour coordonnée ; seule la couleur change de porteur, de la classe
 * `cls-N` de la feuille de style vers un attribut `fill`. Même méthode que les
 * tracés de circuits (version `0.15.0`), les icônes de la barre (`0.22.0`) et
 * les drapeaux (`0.24.0`).
 *
 * **Les deux classes colorisables sont celles de la PREMIÈRE voiture de la
 * planche, et c'est un écart assumé par rapport à la demande.** Elle nommait
 * `cls-6` pour la couleur 1 et `cls-2` pour la couleur 2 ; or la planche
 * empile **quatre** voitures, chacune peinte par son propre couple de classes
 * (`cls-6`/`cls-14`, `cls-13`/`cls-10`, `cls-8`/`cls-3`, `cls-12`/`cls-2`).
 * `cls-2` appartient à la quatrième et **n'existe pas** dans la première :
 * suivre la lettre de la demande aurait laissé la couleur 2 sans porteur. Ce
 * sont donc `cls-6` (la carrosserie principale, celle que la demande nomme) et
 * `cls-14` (la surface secondaire de la même voiture) qui sont branchées.
 *
 * **Les pièces mécaniques gardent leurs gris d'origine** — pneus `#1D1D1B`,
 * suspensions `#706F6F`, fond plat `#3C3C3B`, casque `#020102`. Les repeindre
 * ferait perdre la lecture de l'objet : une voiture entièrement monochrome n'a
 * plus de roues.
 *
 * **La `viewBox` est la boîte englobante réelle**, mesurée en échantillonnant
 * les courbes de Bézier. Celle de l'ancien `assets/voiture.svg` portait près de
 * deux fois la largeur du dessin en marge vide : à hauteur CSS égale, la
 * voiture paraît donc plus grande qu'avant. Les appelants qui tenaient à leur
 * gabarit (la vue piste, le tableau des résultats) ont été ajustés en
 * conséquence.
 *
 * **Chaque texte prend l'encre qui contraste avec l'aplat qui est sous lui.**
 * Sur la voiture personnalisée, le numéro et le nom reposent tous deux sur
 * `couleur1` — c'est elle qui peint le museau et l'aileron arrière. Sur une
 * livrée d'écurie, les deux aplats diffèrent et sont lus dans la table. La
 * planche, elle, écrit les deux textes en blanc, ce qui rend le pseudo
 * illisible sur les ailerons clairs de Haas et de Cadillac : calculer l'encre
 * corrige un défaut du fichier source.
 *
 * ### Le cockpit porte l'identité du membre (version `0.52.0`)
 *
 * Le disque noir du casque n'est plus seulement un casque : quand l'appelant
 * transmet `photo` ou `teintePilote`, **la photo du membre y est découpée par un
 * `<clipPath>` circulaire**, et à défaut son initiale sur sa teinte. La pastille
 * que la vue piste posait AU-DESSUS de la voiture depuis la version `0.50.0`
 * disparaît avec.
 *
 * | Point | Pourquoi |
 * |---|---|
 * | **Dans le SVG, jamais en HTML posé dessus** | Une pastille absolue au-dessus du dessin demandait de réserver sa hauteur dans la disposition de la piste, donc de comprimer la zone de jeu de tout le monde. Découpée dans le cockpit, elle ne coûte pas un pixel : elle occupe une place que la voiture prenait déjà |
 * | **La géométrie vient de la planche, mesurée** | `geo.cockpit` — voir `VoituresEcuries.jsx`. À l'échelle près, le disque et la photo partagent exactement le cercle que le dessin peint : l'écart entre le masque et le casque est structurellement nul, quelle que soit la taille rendue |
 * | **Peint APRÈS le corps, avant les deux textes** | Un SVG n'a pas d'autre `z-index` que l'ordre de document (`docs/composants.md` §4). Peinte avant, la photo passerait sous le casque, c'est-à-dire nulle part |
 * | **L'identifiant du `clipPath` vient de `useId`** | Seize voitures coexistent sur la piste, chacune avec son propre masque. Un identifiant écrit en dur les ferait toutes pointer vers le premier — et rien à l'écran ne dirait laquelle |
 * | **L'initiale prend `encreSurAplat`, jamais le blanc** | Et non `encreSur`, qui sert aux deux textes de la carrosserie : celui-ci compare une luminance à 0,45, or l'amber des teintes de membre vaut 0,424 — il rendrait du blanc à **2,22:1**. `encreSurAplat` mesure le contraste et bascule sur l'encre foncée, qui y tient 7,86:1 |
 *
 * > **La photo ne s'anime pas autrement qu'en fondu.** Elle réemploie `.t-photo`,
 * > la transition d'opacité que `Pastille` et `PhotoChampionnat` partagent déjà —
 * > l'URL arrive avec les données, le pixel plus tard, et c'est le seul moment
 * > où il y a quelque chose à faire tenir. Aucun jeton nouveau, aucune image-clé.
 */

// Le nom doit tenir dans les 98px de l'aileron arrière, quel que soit le pseudo.
const NOM_MAXIMUM = 10;

/** Corps du numéro peint sur le museau. Valeur de la planche, inchangée. */
const TAILLE_NUMERO = 20.54;

/**
 * Hauteur de capitale d'Helvetica, en fraction du corps — 717/1000 dans les
 * métriques de la fonte.
 *
 * **Elle sert à REMETTRE LE NUMÉRO À L'ENDROIT sans déplacer le dessin.** La
 * planche écrivait le numéro sous `rotate(180)` : les chiffres étaient donc
 * lisibles depuis l'avant de la voiture, tête-bêche pour qui la regarde du
 * dessus — c'est-à-dire dans toutes les vues de l'app, qui sont toutes des vues
 * de dessus.
 *
 * Retirer la rotation ne suffit pas : elle ne renversait pas seulement les
 * glyphes, elle renversait aussi leur position autour de la ligne de base. Sous
 * `rotate(180)`, les chiffres occupent `[yNumero, yNumero + 0,717 em]` ; à
 * l'endroit, ils occupent `[y - 0,717 em, y]`. La ligne de base descend donc
 * d'exactement une hauteur de capitale pour que le numéro retrouve **le pixel
 * qu'il occupait**, sur les douze livrées à la fois.
 *
 * C'est pour cela que le décalage est calculé et non relevé à l'œil : douze
 * `yNumero` mesurés séparément (`VoituresEcuries.jsx`) auraient demandé douze
 * corrections, et la première retouchée aurait démenti les onze autres.
 */
const HAUTEUR_CAPITALE = 0.717;

/** Cadrage et ancrages de la voiture personnalisable (première de la planche).
 *  `cockpit` est le `<circle fill="#020102">` du casque, relevé dans `CorpsPerso`
 *  ci-dessous — pas déduit de `cx`, dont il s'écarte de 0,13 unité. */
const PERSO = {
  viewBox: "55.08 57.74 141.12 288.09",
  cockpit: { cx: 125.77, cy: 228.87, r: 20.41 },
  cx: 125.64,
  yNumero: 129.41,
  yNom: 333.45,
};

// La taille de l'initiale, en fraction du DIAMÈTRE du cockpit. C'est le rapport
// exact que `Pastille` applique déjà à son diamètre explicite (0,44) : une
// initiale dans un rond est la même question, elle garde la même proportion.
const INITIALE_SUR_DIAMETRE = 0.44;

/** Le noir du casque, quand l'appelant ne donne pas de teinte : c'est celui de
 *  la planche, donc le cockpit reste exactement ce qu'il était. */
const CASQUE = "#020102";

/**
 * L'encre que le numéro prendrait sans choix du membre.
 *
 * **Le sélecteur « Couleur du texte » du profil en a besoin, et lui seul.** Il
 * doit afficher une couleur dès le premier montage, y compris pour un profil
 * dont `couleur_texte` vaut `null` — c'est-à-dire tous ceux d'avant la migration
 * 18. Afficher `#FFFFFF` par défaut ferait mentir la rangée : la voiture, elle,
 * dessine encore l'encre calculée. Le sélecteur montre donc ce qui est à
 * l'écran, et le premier enregistrement ne change rien de visible.
 *
 * Elle est lue **sur l'aplat du museau**, jamais sur celui de l'aileron : les
 * deux diffèrent sur neuf livrées, et le numéro est ce qui identifie une voiture
 * à la taille où on la regarde sur la piste.
 *
 * Exportée d'ici et non recalculée dans l'écran : c'est la même question que
 * celle des deux `encreSur` du rendu ci-dessous, et deux réponses écrites
 * séparément auraient divergé au premier ajustement.
 */
export function aplatDuNumero({ mode, ecurie, couleur1 = COULEUR1_DEFAUT }) {
  const enEcurie = mode === "ecurie" && aUneLivree(ecurie);
  return enEcurie ? geometrieLivree(ecurie).fondNumero : couleur1;
}

/** L'encre qui en découle. Deux fonctions et non une : l'écran de profil mesure
 *  le contraste de la couleur CHOISIE contre l'aplat, ce qui demande l'aplat
 *  lui-même ; le rendu, lui, ne veut que l'encre. */
export function encreParDefaut(livree) {
  return encreSur(aplatDuNumero(livree));
}

/** La taille du nom suit la longueur du pseudo : à taille fixe, « Alexandre » débordait. */
function tailleDuNom(nom) {
  // Helvetica Neue Bold fait environ 0,58 em de large par caractère : 94px
  // utiles divisés par cette largeur donnent la taille maximale tenable.
  return Math.min(17.5, Math.round((162 / Math.max(nom.length, 1)) * 10) / 10);
}

/** Les formes de la voiture personnalisable, repeintes par les deux couleurs. */
function CorpsPerso({ couleur1, couleur2 }) {
  return (
    <>
      <g>
      <polygon fill="#3C3C3B" points="125.64 192.02 125.64 191.99 125.15 192.01 124.35 191.99 124.35 192.04 69.13 194.31 76.61 269.3 76.61 308.99 124.35 308.99 125.64 308.99 174.5 308.99 174.5 269.3 182.15 193.45 125.64 192.02"/>
      <g>
      <polygon fill={couleur1} points="184.68 73.84 184.68 98.12 125.64 82.02 125.64 57.74 184.68 73.84"/>
      <polygon fill={couleur1} points="125.64 57.74 125.64 82.02 66.6 98.12 66.6 73.84 125.64 57.74"/>
      </g>
      <polygon fill={couleur2} points="125.64 77.11 66.6 93.21 66.6 111.54 125.64 95.44 184.68 111.54 184.68 93.21 125.64 77.11"/>
      <g>
      <polygon fill={couleur2} points="196.19 76.53 176.37 68.88 176.37 114.24 196.19 114.24 196.19 76.53"/>
      <polygon fill={couleur2} points="55.08 76.53 74.91 68.88 74.91 114.24 55.08 114.24 55.08 76.53"/>
      </g>
      <path fill={couleur2} d="M170.24,265.43c-13.84,58.83-35.05.39-35.26,27.97h-18.68c-.21-27.58-21.42,30.86-35.26-27.97-13.84-58.83,28.25-65.5,28.25-65.5l5.18-55.38s4.18-65.9,4.91-73.71c.5-5.46,3.36-7.21,5.03-7.77.23-.07.44-.13.61-.17.38-.08.62-.09.62-.09,0,0,5.54.22,6.27,8.03.72,7.81,4.9,73.71,4.9,73.71l5.18,55.38s42.1,6.67,28.25,65.5Z"/>
      <rect fill="#1D1D1B" x="164.88" y="119.53" width="31.32" height="55.29" rx="5.18" ry="5.18"/>
      <rect fill="#1D1D1B" x="55.14" y="119.53" width="31.32" height="55.29" rx="5.18" ry="5.18"/>
      <path fill="#706F6F" d="M140.09,272.03c-1.09,2.32-2.03,4.62-2.8,7l14.38,14.38h-52.06l14.38-14.38c-.77-2.38-1.71-4.68-2.8-7l-20.76,20.76v10.04h70.42v-10.04l-20.76-20.76Z"/>
      <path fill="#706F6F" d="M164.88,141.78v10.04l-25.69,21.44-.89-9.5,19.39-15.6-1.12-.18-19.33,4.43-.24-2.59,12.73-2.92-13.11-2.07c-.13-2.1-.33-5.22-.57-9l28.83,5.95Z"/>
      <path fill="#706F6F" d="M86.4,141.78v10.04l25.69,21.44.89-9.5-19.39-15.6,1.12-.18,19.33,4.43.24-2.59-12.73-2.92,13.11-2.07c.13-2.1.33-5.22.57-9l-28.83,5.95Z"/>
      <path fill={couleur1} d="M148.27,199.93l-7.17-55.38s-5.79-65.9-6.78-73.71c-1.01-7.79-8.63-8.03-8.67-8.03h0s0,0,0,0h0s0,0,0,0c-.04,0-7.67.24-8.67,8.03-1,7.81-6.78,73.71-6.78,73.71l-7.17,55.38s-20.97,22.74-3.54,54.06c7.6,13.66,11.09,22.89,12.61,28.97,1.97,7.87.64,10.44.64,10.44h25.85s-1.33-2.57.64-10.44c1.52-6.08,5.01-15.31,12.61-28.97,17.43-31.32-3.54-54.06-3.54-54.06Z"/>
      <path fill={couleur2} d="M121.45,161.18c-2.76,0-5.19,1.83-5.96,4.48-3.92,13.56-15.24,54.14-14.68,69.14.5,13.39,13.8,28.75,20.72,35.87,2.25,2.32,5.96,2.32,8.21,0,6.92-7.12,20.22-22.49,20.72-35.87.56-15-10.76-55.59-14.68-69.14-.77-2.65-3.19-4.48-5.96-4.48h-8.37Z"/>
      <circle fill="#020102" cx="125.77" cy="228.87" r="20.41"/>
      <path fill={couleur2} d="M133.23,86.79s.07-1.8-.04-4.35c-.28-6.19-1.59-16.79-7.42-16.79s-7.15,10.62-7.42,16.8c-.11,2.55-.04,4.34-.04,4.34.35,35.29-15.05,113.14-15.05,113.14l-.22-.26,7.14-55.12s2.87-32.68,4.92-54.74c.86-9.27,1.57-16.66,1.86-18.97.51-3.89,2.66-5.9,4.7-6.94,2.04-1.03,3.95-1.09,3.98-1.09.04,0,7.67.24,8.67,8.03.29,2.25.97,9.31,1.8,18.22,2.05,22.06,4.99,55.49,4.99,55.49l7.15,55.26c-.68-3.47-15.36-78.55-15.02-113.02Z"/>
      <g>
      <rect fill={couleur1} x="145.59" y="91.31" width="21.5" height="6.96" transform="translate(30.25 -37.6) rotate(15.17)"/>
      <rect fill={couleur1} x="86.12" y="91.31" width="21.5" height="6.96" transform="translate(215.16 160.94) rotate(164.83)"/>
      </g>
      <rect fill={couleur2} x="119.16" y="116.06" width="12.94" height="6.96" rx="3.48" ry="3.48"/>
      <g>
      <path fill={couleur1} d="M170.23,265.53c-.37,1.58-.75,3.08-1.13,4.5-3.01-15.27-6.46-37.82-5.13-56.25,7.44,9.51,12.47,25.39,6.26,51.75Z"/>
      <path fill={couleur1} d="M81.04,265.53c.37,1.58.75,3.08,1.13,4.5,3.01-15.27,6.46-37.82,5.13-56.25-7.44,9.51-12.47,25.39-6.26,51.75Z"/>
      </g>
      <rect fill="#1D1D1B" x="160.85" y="266.91" width="35.29" height="60.34" rx="5.18" ry="5.18"/>
      <rect fill="#1D1D1B" x="55.14" y="266.91" width="35.29" height="60.34" rx="5.18" ry="5.18" transform="translate(145.56 594.16) rotate(-180)"/>
      <rect fill={couleur1} x="76.61" y="309" width="98.06" height="36.83"/>
      </g>
    </>
  );
}

/**
 * @param {string} [photo] URL publique de la photo du membre. Découpée dans le
 *   cockpit. Absente — ou cassée — ce sont les initiales, qui ne sont pas un cas
 *   dégradé mais l'état par défaut de tout compte.
 * @param {string} [teintePilote] la teinte du disque sous l'initiale, en
 *   `#rrggbb` (`teinteMembre`, `lib/couleurs.js`). **C'est elle qui allume le
 *   cockpit** : sans elle ni photo, le casque reste le noir de la planche et
 *   aucun écran n'y voit de différence.
 * @param {string} [couleurTexte] la couleur choisie par le membre pour son
 *   numéro et son pseudo (`profils.couleur_texte`, migration 18). **`null` n'est
 *   pas « pas de couleur » mais « pas de choix »** : les deux textes reprennent
 *   alors l'encre calculée qui contraste avec l'aplat sous chacun d'eux, ce qui
 *   est le comportement d'origine et reste celui de tout profil qui n'a rien
 *   choisi.
 */
export default function Voiture({
  mode = "perso",
  ecurie = null,
  couleur1 = COULEUR1_DEFAUT,
  couleur2 = COULEUR2_DEFAUT,
  numero = "",
  nom = "",
  className = "",
  titre,
  photo = null,
  teintePilote = null,
  couleurTexte = null,
}) {
  // Un slug inconnu retombe sur la voiture personnalisable plutôt que de ne
  // rien rendre : une livrée retirée d'une saison à l'autre laisserait sinon
  // un trou à la place de la voiture. Même règle que `aUnTrace` pour les
  // circuits et que les drapeaux depuis la version `0.15.0`.
  const enEcurie = mode === "ecurie" && aUneLivree(ecurie);
  const geo = enEcurie ? geometrieLivree(ecurie) : PERSO;

  // La couleur choisie l'emporte sur l'encre calculée, et elle vaut pour les
  // DEUX textes : c'est une seule décision du membre, « de quelle couleur est
  // écrit mon nom sur ma voiture ». Sans choix, chaque texte reprend l'encre qui
  // contraste avec l'aplat qui lui est propre — le museau et l'aileron n'ont pas
  // la même couleur sur neuf des onze livrées.
  const encreNumero = couleurTexte ?? encreSur(enEcurie ? geo.fondNumero : couleur1);
  const encreNom = couleurTexte ?? encreSur(enEcurie ? geo.fondAile : couleur1);

  const numeroAffiche = String(numero ?? "").trim().slice(0, 3);
  const nomAffiche = String(nom ?? "").trim().slice(0, NOM_MAXIMUM);

  // Le cockpit ne s'allume que si on lui a donné de quoi : un écran qui affiche
  // une voiture sans membre derrière (le sélecteur de couleurs du profil, la
  // silhouette d'un chargement) garde le casque noir de la planche.
  const cockpit = geo.cockpit;
  const identite = Boolean(photo || teintePilote);
  const fondCockpit = teintePilote ?? CASQUE;
  const initiale = String(nom ?? "").trim().charAt(0).toUpperCase() || "?";

  // `useId` rend `«r3»` en React 19 et `:r3:` en 18 ; les deux se réfèrent sans
  // problème dans un `url(#…)`, mais pas dans un sélecteur CSS le jour où l'on
  // voudrait styler le masque. On les rabote donc dès la source.
  const masque = `cockpit-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;

  // Le fondu d'arrivée, et la reprise du disque teinté quand l'URL en base ne
  // pointe plus sur rien. `usePhotoDetachee` et non `usePhoto` : un `<image>`
  // SVG n'a ni `complete` ni `naturalWidth`, donc rien à interroger sur une
  // image déjà en cache — voir la note du module.
  const { chargee, cassee } = usePhotoDetachee(photo);
  const photoAffichable = Boolean(photo) && !cassee;

  return (
    <svg
      viewBox={geo.viewBox}
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      role="img"
      aria-label={titre ?? (nomAffiche ? `Voiture de ${nomAffiche}` : "Voiture")}
    >
      {/* Le groupe porte la transition de couleur : sur la voiture
          personnalisable, les aplats se remplacent en 200ms au lieu de sauter
          d'une teinte à l'autre pendant qu'on parcourt la palette. Un
          changement de couleur prend `ease`, jamais `ease-out`. */}
      <g className={enEcurie ? undefined : "t-voiture-teinte"}>
        {enEcurie ? (
          formesLivree(ecurie)
        ) : (
          <CorpsPerso couleur1={couleur1} couleur2={couleur2} />
        )}
      </g>

      {/* Le cockpit, peint APRÈS le corps : dans un SVG, l'ordre de document est
          le seul ordre de peinture. Le disque teinté est posé sous la photo et
          reste visible tant qu'elle charge — c'est lui qui tient la place, avec
          l'initiale dessus, exactement comme une pastille. */}
      {identite && (
        <>
          <defs>
            <clipPath id={masque}>
              <circle cx={cockpit.cx} cy={cockpit.cy} r={cockpit.r} />
            </clipPath>
          </defs>
          <g clipPath={`url(#${masque})`}>
            <circle
              cx={cockpit.cx}
              cy={cockpit.cy}
              r={cockpit.r}
              fill={fondCockpit}
            />
            {/* L'initiale tient la place jusqu'à ce que le pixel arrive, et
                s'efface une fois qu'il est là — exactement la règle de
                `Pastille`. Elle a la bonne taille et la bonne forme, donc
                l'arrivée est un fondu et non un saut. */}
            {!chargee && (
              <text
                x={cockpit.cx}
                y={cockpit.cy}
                dy="0.35em"
                textAnchor="middle"
                fill={encreSurAplat(fondCockpit)}
                fontFamily="Helvetica Neue, Helvetica, Arial, sans-serif"
                fontWeight="500"
                fontSize={cockpit.r * 2 * INITIALE_SUR_DIAMETRE}
              >
                {initiale}
              </text>
            )}
            {photoAffichable && (
              <image
                href={photo}
                x={cockpit.cx - cockpit.r}
                y={cockpit.cy - cockpit.r}
                width={cockpit.r * 2}
                height={cockpit.r * 2}
                /* Le pendant SVG d'`object-fit: cover` : la photo sort déjà
                   carrée du recadrage, mais une URL posée en base avant la
                   version `0.51.0` ne l'est pas forcément. */
                preserveAspectRatio="xMidYMid slice"
                className="t-photo"
                data-chargee={chargee ? "true" : "false"}
              />
            )}
          </g>
        </>
      )}

      {/* Les deux textes de la carrosserie, dans un groupe qui porte la
          transition de couleur — la même que les aplats du corps, `.t-voiture-teinte`
          (dont le sélecteur couvre `text` depuis cette version). Parcourir la
          palette du profil repeint donc le numéro et le pseudo en 200ms, comme
          elle repeint déjà la coque : un seul réglage, un seul mouvement.

          Le groupe est posé APRÈS le cockpit : dans un SVG, l'ordre de document
          est le seul ordre de peinture (`docs/composants.md` §4). */}
      <g className="t-voiture-teinte">
        {/* Numéro sur le museau, **à l'endroit depuis la version `0.53.0`**.
            La planche l'écrivait sous `rotate(180)` — lisible depuis l'avant de
            la voiture, donc tête-bêche dans toutes les vues de l'app, qui sont
            toutes des vues de dessus. La ligne de base descend d'une hauteur de
            capitale pour que le numéro retrouve exactement le pixel qu'il
            occupait ; voir `HAUTEUR_CAPITALE`.

            `textAnchor` remplace le calage manuel de la planche, qui décentrait
            un numéro à deux chiffres. La graisse 700 est la seule autorisée par
            la section 5, et uniquement ici. */}
        {numeroAffiche && (
          <text
            x={geo.cx}
            y={geo.yNumero + TAILLE_NUMERO * HAUTEUR_CAPITALE}
            textAnchor="middle"
            fill={encreNumero}
            fontFamily="Helvetica Neue, Helvetica, Arial, sans-serif"
            fontWeight="700"
            fontSize={TAILLE_NUMERO}
          >
            {numeroAffiche}
          </text>
        )}

        {/* Nom sur l'aileron arrière. */}
        {nomAffiche && (
          <text
            x={geo.cx}
            y={geo.yNom}
            textAnchor="middle"
            fill={encreNom}
            fontFamily="Helvetica Neue, Helvetica, Arial, sans-serif"
            fontWeight="700"
            fontSize={tailleDuNom(nomAffiche)}
          >
            {nomAffiche}
          </text>
        )}
      </g>
    </svg>
  );
}
