import { encreSur } from "../lib/livrees.js";

/**
 * La voiture vue du dessus — `assets/voiture.svg` transformé en composant.
 *
 * Les couleurs du fichier d'origine étaient codées en dur (un rouge Ferrari
 * décliné en cinq nuances). Elles sont ici réparties sur **deux** couleurs, ce
 * que demande le CLAUDE.md (section 5, « 2 couleurs au choix ») :
 *
 * - `couleur1` peint la coque, la partie qui occupe le plus de surface et qui
 *   se reconnaît de loin sur la piste ;
 * - `couleur2` peint les deux ailerons, avant et arrière, seuls éléments dont
 *   la forme reste lisible à 50px de large.
 *
 * Les pièces mécaniques — pneus, suspensions, fond plat, casque — gardent leurs
 * gris d'origine. Les repeindre ferait perdre la lecture de l'objet : une
 * voiture entièrement monochrome n'a plus de roues.
 *
 * Le numéro s'écrit sur le museau, le nom sur l'aileron arrière, chacun dans
 * l'encre qui contraste avec l'aplat qu'il recouvre — un numéro blanc sur une
 * livrée blanche ne dirait plus rien, et le numéro est la seule chose qui
 * identifie une voiture à cette taille.
 */

// Le museau est peint par la coque (`couleur1`), l'aileron arrière par les
// ailerons (`couleur2`) : chaque texte prend son encre de l'aplat qui est sous
// lui, pas d'une couleur choisie une fois pour toutes.
const NOM_MAXIMUM = 10;

/** Le nom doit tenir dans les 98px de l'aileron arrière, quel que soit le pseudo. */
function tailleDuNom(nom) {
  // Helvetica Neue Bold fait environ 0,58 em de large par caractère : 94px
  // utiles divisés par cette largeur donnent la taille maximale tenable.
  return Math.min(17.5, Math.round((162 / Math.max(nom.length, 1)) * 10) / 10);
}

export default function Voiture({
  couleur1 = "#800111",
  couleur2 = "#FFFFFF",
  numero = "",
  nom = "",
  className = "",
  titre,
}) {
  const encreNumero = encreSur(couleur1);
  const encreNom = encreSur(couleur2);

  const numeroAffiche = String(numero ?? "").trim().slice(0, 3);
  const nomAffiche = String(nom ?? "").trim().slice(0, NOM_MAXIMUM);

  return (
    <svg
      viewBox="0 0 275.12 332.75"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      role="img"
      aria-label={titre ?? (nomAffiche ? `Voiture de ${nomAffiche}` : "Voiture")}
    >
      {/* Fond plat et diffuseur — gris d'origine. */}
      <polygon
        fill="#3c3c3b"
        points="135.5 159.96 135.5 276.97 184.54 276.97 184.54 237.27 192.01 161.42 135.5 159.96"
      />
      <polygon
        fill="#3c3c3b"
        points="86.47 237.27 86.47 276.97 135.5 276.97 135.5 159.96 78.99 162.29 86.47 237.27"
      />

      {/* Aileron avant : plans intérieurs puis dérives. */}
      <polygon
        fill={couleur2}
        points="194.54 41.81 135.5 25.71 135.5 63.41 194.54 79.51 194.54 41.81"
      />
      <polygon
        fill={couleur2}
        points="76.46 41.81 135.5 25.71 135.5 63.41 76.46 79.51 76.46 41.81"
      />
      <polygon
        fill={couleur2}
        points="206.06 44.5 186.23 36.85 186.23 82.21 206.06 82.21 206.06 44.5"
      />
      <polygon
        fill={couleur2}
        points="64.95 44.5 84.78 36.85 84.78 82.21 64.95 82.21 64.95 44.5"
      />

      {/* Capot moteur et pontons. */}
      <path
        fill={couleur1}
        d="M180.1,233.41c-13.84,58.83-35.05.39-35.26,27.97h-18.68c-.21-27.58-21.42,30.86-35.26-27.97-13.84-58.83,28.25-65.5,28.25-65.5l5.18-55.38s4.18-65.9,4.91-73.71c.5-5.46,3.36-7.21,5.03-7.77.23-.07.44-.13.61-.17.38-.08.62-.09.62-.09,0,0,5.54.22,6.27,8.03.72,7.81,4.9,73.71,4.9,73.71l5.18,55.38s42.1,6.67,28.25,65.5Z"
      />

      {/* Les quatre pneus. */}
      <rect fill="#1c0709" x="170.71" y="234.88" width="35.29" height="60.34" rx="5.18" ry="5.18" />
      <rect fill="#1c0709" x="174.74" y="87.51" width="31.32" height="55.29" rx="5.18" ry="5.18" />
      <rect fill="#1c0709" x="65" y="87.51" width="31.32" height="55.29" rx="5.18" ry="5.18" />
      <rect
        fill="#1c0709"
        x="65"
        y="234.88"
        width="35.29"
        height="60.34"
        rx="5.18"
        ry="5.18"
        transform="translate(165.29 530.1) rotate(-180)"
      />

      {/* Aileron arrière — c'est lui qui porte le nom. */}
      <rect fill={couleur2} x="86.47" y="276.97" width="98.06" height="36.83" />

      {/* Suspensions avant et arrière — gris d'origine. */}
      <path
        fill="#706f6f"
        d="M149.95,240c-1.09,2.32-2.03,4.62-2.8,7l14.38,14.38h-52.06l14.38-14.38c-.77-2.38-1.71-4.68-2.8-7l-20.76,20.76v10.04h70.42v-10.04l-20.76-20.76Z"
      />
      <path
        fill="#706f6f"
        d="M174.74,109.75v10.04l-25.69,21.44-.89-9.5,19.39-15.6-1.12-.18-19.33,4.43-.24-2.59,12.73-2.92-13.11-2.07c-.13-2.1-.33-5.22-.57-9l28.83,5.95Z"
      />
      <path
        fill="#706f6f"
        d="M96.26,109.75v10.04l25.69,21.44.89-9.5-19.39-15.6,1.12-.18,19.33,4.43.24-2.59-12.73-2.92,13.11-2.07c.13-2.1.33-5.22.57-9l-28.83,5.95Z"
      />

      {/* Coque : museau, cockpit, capot. */}
      <path
        fill={couleur1}
        d="M158.13,167.91l-7.17-55.38s-5.79-65.9-6.78-73.71c-1.01-7.79-8.63-8.03-8.67-8.03h0s0,0,0,0h0s0,0,0,0c-.04,0-7.67.24-8.67,8.03-1,7.81-6.78,73.71-6.78,73.71l-7.17,55.38s-20.97,22.74-3.54,54.06c7.6,13.66,11.09,22.89,12.61,28.97,1.97,7.87.64,10.44.64,10.44h25.85s-1.33-2.57.64-10.44c1.52-6.08,5.01-15.31,12.61-28.97,17.43-31.32-3.54-54.06-3.54-54.06Z"
      />
      <circle fill="#020102" cx="135.63" cy="196.84" r="20.41" />

      {/* Numéro sur le museau. La rotation vient du fichier d'origine : le
          numéro se lit depuis l'avant de la voiture, comme en Formule 1.
          `text-anchor` remplace le calage manuel du SVG, qui décentrait un
          numéro à deux chiffres. La graisse 700 est la seule autorisée par la
          section 5, et uniquement ici. */}
      {numeroAffiche && (
        <text
          x="0"
          y="0"
          transform="translate(135.5 40.38) rotate(180)"
          textAnchor="middle"
          fill={encreNumero}
          fontFamily="Helvetica Neue, Helvetica, Arial, sans-serif"
          fontWeight="700"
          fontSize="20.54"
        >
          {numeroAffiche}
        </text>
      )}

      {/* Nom sur l'aileron arrière. La taille suit la longueur du pseudo : à
          taille fixe, « Alexandre » débordait des deux côtés de l'aileron. */}
      {nomAffiche && (
        <text
          x="135.5"
          y="301.4"
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
