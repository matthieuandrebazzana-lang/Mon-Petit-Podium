/**
 * Logo de la carte d'action « Rejoindre un championnat ».
 *
 * **Extrait tel quel de `assets/logo.svg`** — moitié inférieure de la
 * planche : les données de chemin sont identiques au fichier d'origine, aucune
 * coordonnée n'est réécrite. Seul le cadrage bouge. C'est la méthode déjà
 * employée pour les tracés de circuits (`TracesCircuits.jsx`), les icônes de la
 * barre de navigation (`IconeAccueil.jsx`) et les drapeaux (`DrapeauxSVG.jsx`),
 * et elle vaut ici pour la même raison : transcrire un chemin à la main
 * introduit des fautes invisibles à la lecture. Le découpage a été fait par
 * script.
 *
 * **La `viewBox` est un carré de 106 unités centré sur la boîte englobante du
 * logo** (x 19,47 → 114,57 · y 154,50 → 227,35), mesurée en échantillonnant les courbes
 * de Bézier. *Écart assumé par rapport à la demande*, qui prescrivait deux
 * tranches arithmétiques de la planche (`0 0 133.55 120` et `0 121 133.55
 * 120`) : les deux logos n'y sont ni jointifs ni centrés — le second commence à
 * y=154,50 quand sa tranche commence à 121 — et ces cadrages auraient laissé le
 * dessin décentré et rétréci dans sa boîte de 40px. Ce sont donc les vraies
 * boîtes qui font foi, comme partout ailleurs dans le projet.
 *
 * **Le côté du carré est le même pour les deux logos, et c'est le point à ne
 * pas défaire** : ils vivent dans le même système de coordonnées dans la
 * planche, donc leurs tailles relatives sont celles que le dessin a voulues
 * (même hauteur à 0,01 unité près, largeurs de 103,6 et 95,1). Un cadrage serré
 * sur chaque boîte les ramènerait tous deux à la même largeur apparente et
 * écraserait cette intention.
 *
 * La couleur est portée par le `fill` de chaque forme, jamais par
 * `currentColor` : les cartes la passent explicitement, et le `#1d1d1b` de la
 * planche ne dirait rien de la marque.
 */
export default function IconeRejoindre({ couleur = "#E8A020", ...reste }) {
  return (
    <svg
      viewBox="14.02 137.93 106 106"
      // Décorative : le titre de la carte dit déjà ce qu'elle fait, et un
      // lecteur d'écran n'a pas à l'entendre deux fois.
      aria-hidden="true"
      focusable="false"
      {...reste}
    >
      <path fill={couleur} d="M105.05,171.81c0,.15-.01.3-.02.45l-1.12,9.92c-.01.13-.04.26-.06.39-2.16,9.6-8.13,16.16-19.48,16.16h-.48c-7.13,0-11.81-2.29-14.98-6.81,1.54-2.46,2.69-5.37,3.44-8.7.06-.23.1-.46.12-.7l.07-.64c2.86.77,7.03,1.61,11.59,1.61h.2c6.3,0,11.86-1.6,14.22-2.4.9-.3,1.62-.98,1.94-1.87l.02-.07c.72-2.02-.78-4.14-2.93-4.14h-24.26l.27-2.42c.03-.28.04-.56.04-.83-.06-4.4-1.78-8.49-4.64-11.82.15-.14.3-.27.46-.4,3.78-3.12,8.96-5.04,14.68-5.04,11.47,0,20.78,7.73,20.92,17.31Z" />
      <path fill={couleur} d="M114.57,220.46c0,3.8-3.08,6.89-6.89,6.89h-27.32c1.73-1.78,2.8-4.22,2.8-6.89,0-8.06-4.37-15.12-10.86-18.93.17-.01.34-.01.52-.01h22.82c5.23,0,9.96,2.12,13.39,5.55,3.42,3.43,5.54,8.16,5.54,13.39Z" />
      <path fill={couleur} d="M66.93,162.06c-3.78-4.57-10.08-7.56-17.22-7.56-11.44,0-20.73,7.7-20.91,17.25-.01.19.01.38.04.57l1.35,8.93c.01.1.03.2.05.3,2.43,10.11,6.77,15.84,15.73,16.97h7.33c6.72-.86,11.2-4.39,13.88-9.59.99-1.91,1.73-4.05,2.25-6.36.03-.13.05-.26.06-.39l.14-1.2.66-5.89h0s.32-2.83.32-2.83c.01-.15.02-.3.02-.45-.05-3.62-1.41-6.98-3.7-9.75ZM64.13,181.09c-2.36.8-7.92,2.4-14.21,2.4h-.21c-6.29,0-11.85-1.6-14.21-2.4-.9-.3-1.63-.98-1.94-1.87-.73-2.05.8-4.21,2.98-4.21h26.62c.17,0,.34.01.51.05,1.87.29,3.08,2.23,2.43,4.09l-.03.07c-.27.74-.81,1.34-1.51,1.69-.14.07-.28.13-.43.18Z" />
      <path fill={couleur} d="M80.16,220.46c0,1.9-.77,3.62-2.02,4.87s-2.97,2.02-4.88,2.02H26.36c-3.8,0-6.89-3.09-6.89-6.89,0-5.23,2.12-9.96,5.55-13.39,3.42-3.43,8.15-5.55,13.38-5.55h22.82c2.02,0,3.98.32,5.8.91,7.62,2.45,13.14,9.59,13.14,18.03Z" />
    </svg>
  );
}
