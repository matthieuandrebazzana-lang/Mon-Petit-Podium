/**
 * Icône « maison » de la barre de navigation basse.
 *
 * **Extraite telle quelle de `assets/logo-02.svg`** : les données de chemin
 * sont identiques au fichier d'origine, aucune coordonnée n'est réécrite. Seul
 * le cadrage bouge — c'est la méthode déjà employée pour les tracés de circuits
 * (`TracesCircuits.jsx`), et elle vaut ici pour la même raison : transcrire un
 * chemin à la main introduit des fautes invisibles à la lecture.
 *
 * **La `viewBox` est un carré de 74 unités centré sur la boîte englobante de
 * l'icône** (x 24,36 → 94,64 · y 28,37 → 95,67), mesurée en
 * échantillonnant les courbes de Bézier. Le côté est le même pour les quatre
 * icônes, et c'est le point à ne pas défaire : elles vivent dans le même
 * système de coordonnées dans la planche, donc leurs tailles relatives sont
 * celles que le dessin a voulues. Un cadrage serré sur chaque boîte les
 * ramènerait toutes à la même taille et écraserait cette intention.
 *
 * Les deux barres du toit figurent deux fois dans la planche, à
 * l'identique : un seul exemplaire est repris, les chaînes étant
 * strictement égales.
 *
 * La couleur est portée par le `fill` de chaque forme, jamais par
 * `currentColor` : la barre la passe explicitement (`#800111` à l'onglet actif,
 * `#999999` aux autres), et un `fill` en dur dans le fichier — le `#1d1d1b` de
 * la planche — ne se verrait pas tant que la barre est claire.
 */
export default function IconeAccueil({ couleur = "#999999", ...reste }) {
  return (
    <svg
      viewBox="22.5 25.02 74 74"
      // Décorative : le libellé de l'onglet dit déjà où mène le lien, et un
      // lecteur d'écran n'a pas à l'entendre deux fois.
      aria-hidden="true"
      focusable="false"
      {...reste}
    >
      <path fill={couleur} d="M75.78,90.04c0,1.73-1.41,3.14-3.14,3.14h-26.27c-1.73,0-3.14-1.41-3.14-3.14s1.41-3.14,3.14-3.14h26.27c1.73,0,3.14,1.41,3.14,3.14Z" />
      <path fill={couleur} d="M75.78,75.19c0,1.73-1.41,3.14-3.14,3.14h-26.27c-1.73,0-3.14-1.41-3.14-3.14s1.41-3.14,3.14-3.14h26.27c1.73,0,3.14,1.41,3.14,3.14Z" />
      <path fill={couleur} d="M75.78,60.34c0,1.74-1.41,3.15-3.14,3.15h-26.27c-1.73,0-3.14-1.41-3.14-3.15s1.41-3.14,3.14-3.14h26.27c1.73,0,3.14,1.41,3.14,3.14Z" />
      <path fill={couleur} d="M90.75,38.25l-29.5-9.6c-1.14-.37-2.36-.37-3.49,0l-29.51,9.6c-2.32.76-3.89,2.92-3.89,5.36v46.43c0,3.07,2.46,5.58,5.53,5.63h0s2.94,0,2.94,0c2.98,0,5.39-2.42,5.39-5.39v-29.95c0-4.48,3.65-8.14,8.14-8.14h26.27c4.48,0,8.14,3.66,8.14,8.14v29.95c0,2.98,2.42,5.39,5.39,5.39h2.84c3.11,0,5.64-2.53,5.64-5.64v-46.43c0-2.44-1.57-4.6-3.9-5.36Z" />
    </svg>
  );
}
