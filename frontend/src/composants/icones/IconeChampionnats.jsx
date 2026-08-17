/**
 * Icône « trophée » de la barre de navigation basse.
 *
 * **Extraite telle quelle de `assets/logo-02.svg`** : les données de chemin
 * sont identiques au fichier d'origine, aucune coordonnée n'est réécrite. Seul
 * le cadrage bouge — c'est la méthode déjà employée pour les tracés de circuits
 * (`TracesCircuits.jsx`), et elle vaut ici pour la même raison : transcrire un
 * chemin à la main introduit des fautes invisibles à la lecture.
 *
 * **La `viewBox` est un carré de 74 unités centré sur la boîte englobante de
 * l'icône** (x 157,47 → 206,24 · y 28,21 → 101,07), mesurée en
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
export default function IconeChampionnats({ couleur = "#999999", ...reste }) {
  return (
    <svg
      viewBox="144.86 27.64 74 74"
      // Décorative : le libellé de l'onglet dit déjà où mène le lien, et un
      // lecteur d'écran n'a pas à l'entendre deux fois.
      aria-hidden="true"
      focusable="false"
      {...reste}
    >
      <path fill={couleur} d="M206.22,30.92c0,.45-.09.93-.28,1.45l-2.29,6.12c-5.03,13.32-9.14,34.97-9.14,40.33,0,5.94-4.19,9.61-5.87,10.85-.42.31-.66.81-.64,1.34h0c.04.71.55,1.3,1.25,1.44,1.59.33,6.49,4.59,8.2,4.78.95.11,1.6,1.03,1.34,1.96h0c-.31,1.11-1.32,1.88-2.47,1.88h-28.51c-1.02,0-1.95-.61-2.35-1.55l-.07-.16c-.41-.95.2-2.03,1.23-2.16,1.74-.21,6.55-4.43,8.14-4.76.7-.14,1.21-.73,1.25-1.44h0c.03-.53-.21-1.02-.64-1.34-1.68-1.23-5.87-4.91-5.87-10.85,0-6.24-5.57-34.54-11.67-46.1-1.08-2.05.4-4.5,2.71-4.5h42.93c.11,0,.22,0,.33.02.09,0,.18.02.26.04.17.04.34.08.48.13.1.03.19.07.28.12.08.03.15.07.22.12.15.1.29.21.42.33.07.06.12.12.18.18.06.07.11.14.15.21.02.03.03.05.05.08.06.08.1.17.14.26.06.12.1.25.14.38.04.14.07.28.09.42s.03.28.03.43Z" />
    </svg>
  );
}
