/**
 * Icône « personne » de la barre de navigation basse.
 *
 * **Extraite telle quelle de `assets/logo-02.svg`** : les données de chemin
 * sont identiques au fichier d'origine, aucune coordonnée n'est réécrite. Seul
 * le cadrage bouge — c'est la méthode déjà employée pour les tracés de circuits
 * (`TracesCircuits.jsx`), et elle vaut ici pour la même raison : transcrire un
 * chemin à la main introduit des fautes invisibles à la lecture.
 *
 * **La `viewBox` est un carré de 74 unités centré sur la boîte englobante de
 * l'icône** (x 396,2 → 456,88 · y 25,98 → 98,83), mesurée en
 * échantillonnant les courbes de Bézier. Le côté est le même pour les quatre
 * icônes, et c'est le point à ne pas défaire : elles vivent dans le même
 * système de coordonnées dans la planche, donc leurs tailles relatives sont
 * celles que le dessin a voulues. Un cadrage serré sur chaque boîte les
 * ramènerait toutes à la même taille et écraserait cette intention.
 *
 * La couleur est portée par le `fill` de chaque forme, jamais par
 * `currentColor` : la barre la passe explicitement (`#800111` à l'onglet actif,
 * `#999999` aux autres), et un `fill` en dur dans le fichier — le `#1d1d1b` de
 * la planche — ne se verrait pas tant que la barre est claire.
 */
export default function IconeProfil({ couleur = "#999999", ...reste }) {
  return (
    <svg
      viewBox="389.54 25.41 74 74"
      // Décorative : le libellé de l'onglet dit déjà où mène le lien, et un
      // lecteur d'écran n'a pas à l'entendre deux fois.
      aria-hidden="true"
      focusable="false"
      {...reste}
    >
      <path fill={couleur} d="M426.2,70.22h.48c11.35,0,17.32-6.56,19.47-16.17.03-.13.05-.25.06-.38l1.12-9.93c.02-.15.03-.3.02-.45-.14-9.58-9.45-17.31-20.92-17.31h0c-11.44,0-20.73,7.7-20.92,17.25,0,.19.01.38.04.57l1.35,8.94c.02.1.04.2.06.3,2.73,11.34,7.86,17.18,19.23,17.18ZM426.44,46.5h13.45c2.14,0,3.64,2.12,2.93,4.14l-.02.07c-.32.89-1.04,1.57-1.94,1.87-2.36.79-7.92,2.4-14.22,2.4h-.2c-6.29,0-11.85-1.6-14.22-2.4-.9-.3-1.62-.98-1.94-1.87h0c-.72-2.06.8-4.21,2.98-4.21h13.17Z" />
      <path fill={couleur} d="M437.95,73.01h-22.82c-10.46,0-18.93,8.48-18.93,18.93h0c0,3.81,3.09,6.89,6.89,6.89h46.9c3.81,0,6.89-3.09,6.89-6.89h0c0-10.46-8.48-18.93-18.93-18.93Z" />
    </svg>
  );
}
