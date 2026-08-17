/**
 * Icône « calendrier » de la barre de navigation basse.
 *
 * **Extraite telle quelle de `assets/logo-02.svg`** : les données de chemin
 * sont identiques au fichier d'origine, aucune coordonnée n'est réécrite. Seul
 * le cadrage bouge — c'est la méthode déjà employée pour les tracés de circuits
 * (`TracesCircuits.jsx`), et elle vaut ici pour la même raison : transcrire un
 * chemin à la main introduit des fautes invisibles à la lecture.
 *
 * **La `viewBox` est un carré de 74 unités centré sur la boîte englobante de
 * l'icône** (x 273,84 → 334,52 · y 28,22 → 95,84), mesurée en
 * échantillonnant les courbes de Bézier. Le côté est le même pour les quatre
 * icônes, et c'est le point à ne pas défaire : elles vivent dans le même
 * système de coordonnées dans la planche, donc leurs tailles relatives sont
 * celles que le dessin a voulues. Un cadrage serré sur chaque boîte les
 * ramènerait toutes à la même taille et écraserait cette intention.
 *
 * Les deux anneaux du haut sont des `<rect>` dans la planche, et non des
 * chemins : ils sont repris tels quels, avec leurs rayons de coin.
 *
 * La couleur est portée par le `fill` de chaque forme, jamais par
 * `currentColor` : la barre la passe explicitement (`#800111` à l'onglet actif,
 * `#999999` aux autres), et un `fill` en dur dans le fichier — le `#1d1d1b` de
 * la planche — ne se verrait pas tant que la barre est claire.
 */
export default function IconeCalendrier({ couleur = "#999999", ...reste }) {
  return (
    <svg
      viewBox="267.18 25.03 74 74"
      // Décorative : le libellé de l'onglet dit déjà où mène le lien, et un
      // lecteur d'écran n'a pas à l'entendre deux fois.
      aria-hidden="true"
      focusable="false"
      {...reste}
    >
      <path fill={couleur} d="M323.95,41.84v3.36c0,2.55-2.06,4.61-4.61,4.61h-5.35c-2.55,0-4.61-2.06-4.61-4.61v-3.36c0-2.55-2.06-4.61-4.61-4.61h-2.53c-2.55,0-4.61,2.06-4.61,4.61v3.36c0,2.55-2.06,4.61-4.61,4.61h-5.35c-2.55,0-4.61-2.06-4.61-4.61v-3.36c0-2.55-2.06-4.61-4.61-4.61h0c-2.55,0-4.61,2.06-4.61,4.61v49.39c0,2.55,2.06,4.61,4.61,4.61h51.46c2.55,0,4.61-2.06,4.61-4.61v-49.39c0-2.55-2.06-4.61-4.61-4.61h-1.37c-2.55,0-4.61,2.06-4.61,4.61ZM320.38,87.82h-32.36c-2.55,0-4.61-2.06-4.61-4.61v-20.11c0-2.55,2.06-4.61,4.61-4.61h32.36c2.55,0,4.61,2.06,4.61,4.61v20.11c0,2.55-2.06,4.61-4.61,4.61Z" />
      <rect
        fill={couleur}
        x="285.64"
        y="28.22"
        width="9.44"
        height="19.02"
        rx="4.72"
        ry="4.72"
      />
      <rect
        fill={couleur}
        x="311.95"
        y="28.22"
        width="9.44"
        height="19.02"
        rx="4.72"
        ry="4.72"
      />
    </svg>
  );
}
