import { COULEUR1_DEFAUT, COULEUR2_DEFAUT, encreSur } from "../lib/palette.js";
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
 */

// Le nom doit tenir dans les 98px de l'aileron arrière, quel que soit le pseudo.
const NOM_MAXIMUM = 10;

/** Cadrage et ancrages de la voiture personnalisable (première de la planche). */
const PERSO = {
  viewBox: "55.08 57.74 141.12 288.09",
  cx: 125.64,
  yNumero: 129.41,
  yNom: 333.45,
};

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

export default function Voiture({
  mode = "perso",
  ecurie = null,
  couleur1 = COULEUR1_DEFAUT,
  couleur2 = COULEUR2_DEFAUT,
  numero = "",
  nom = "",
  className = "",
  titre,
}) {
  // Un slug inconnu retombe sur la voiture personnalisable plutôt que de ne
  // rien rendre : une livrée retirée d'une saison à l'autre laisserait sinon
  // un trou à la place de la voiture. Même règle que `aUnTrace` pour les
  // circuits et que les drapeaux depuis la version `0.15.0`.
  const enEcurie = mode === "ecurie" && aUneLivree(ecurie);
  const geo = enEcurie ? geometrieLivree(ecurie) : PERSO;

  const encreNumero = encreSur(enEcurie ? geo.fondNumero : couleur1);
  const encreNom = encreSur(enEcurie ? geo.fondAile : couleur1);

  const numeroAffiche = String(numero ?? "").trim().slice(0, 3);
  const nomAffiche = String(nom ?? "").trim().slice(0, NOM_MAXIMUM);

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

      {/* Numéro sur le museau. La rotation vient du fichier d'origine : le
          numéro se lit depuis l'avant de la voiture, comme en Formule 1.
          `textAnchor` remplace le calage manuel de la planche, qui décentrait
          un numéro à deux chiffres. La graisse 700 est la seule autorisée par
          la section 5, et uniquement ici. */}
      {numeroAffiche && (
        <text
          x="0"
          y="0"
          transform={`translate(${geo.cx} ${geo.yNumero}) rotate(180)`}
          textAnchor="middle"
          fill={encreNumero}
          fontFamily="Helvetica Neue, Helvetica, Arial, sans-serif"
          fontWeight="700"
          fontSize="20.54"
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
    </svg>
  );
}
