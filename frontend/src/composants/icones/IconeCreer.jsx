/**
 * Logo de la carte d'action « Créer un championnat ».
 *
 * **Extrait tel quel de `assets/logo.svg`** — moitié supérieure de la
 * planche : les données de chemin sont identiques au fichier d'origine, aucune
 * coordonnée n'est réécrite. Seul le cadrage bouge. C'est la méthode déjà
 * employée pour les tracés de circuits (`TracesCircuits.jsx`), les icônes de la
 * barre de navigation (`IconeAccueil.jsx`) et les drapeaux (`DrapeauxSVG.jsx`),
 * et elle vaut ici pour la même raison : transcrire un chemin à la main
 * introduit des fautes invisibles à la lecture. Le découpage a été fait par
 * script.
 *
 * **La `viewBox` est un carré de 106 unités centré sur la boîte englobante du
 * logo** (x 12,23 → 115,80 · y 18,42 → 91,28), mesurée en échantillonnant les courbes
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
export default function IconeCreer({ couleur = "#800111", ...reste }) {
  return (
    <svg
      viewBox="11.02 1.85 106 106"
      // Décorative : le titre de la carte dit déjà ce qu'elle fait, et un
      // lecteur d'écran n'a pas à l'entendre deux fois.
      aria-hidden="true"
      focusable="false"
      {...reste}
    >
      <path fill={couleur} d="M63.72,51.83h0s-.04.11-.04.11v.03s-2.22,5.93-2.22,5.93c0,0,0,.01,0,.02,0,0,0,.01,0,.02-.05.12-.09.23-.14.34-.06.13-.12.26-.2.37-.21.37-.47.72-.76,1.03-1.04,1.14-2.52,1.92-3.92,1.97-.04,0-.09,0-.12,0h-8.83s-.05,0-.07,0c-1.02.01-2.08.43-3,1.09-.91.67-1.68,1.58-2.07,2.59,0,.02-.02.05-.03.07l-.04.1-2.22,5.95s0,.01,0,.02c0,0,0,.01,0,.02-.05.12-.09.23-.14.34-.06.13-.12.26-.2.37-.21.37-.47.72-.76,1.03-1.04,1.14-2.52,1.92-3.92,1.97-.04,0-.09,0-.12,0h-8.83c-.06,0-.12,0-.18,0-.01,0-.03,0-.03,0-.05,0-.11,0-.15-.01-.07,0-.14-.01-.2-.02-.05-.01-.11-.03-.16-.04s-.11-.03-.15-.04c-.04-.01-.08-.03-.12-.03-.02,0-.04,0-.05-.01,0,0-.01,0-.01,0-.06-.02-.12-.04-.18-.07-.06-.03-.12-.06-.18-.09-.06-.03-.11-.07-.16-.1-.06-.03-.11-.07-.16-.11-.18-.14-.33-.3-.45-.49-.04-.06-.08-.12-.12-.19,0,0,0-.01,0-.02-.02-.04-.05-.09-.07-.13-.05-.1-.08-.2-.11-.3-.03-.08-.05-.16-.06-.24-.05-.26-.06-.53-.03-.82.03-.32.12-.66.24-1.01l2.26-6.05s.01-.05.02-.07c.08-.21.14-.41.17-.61.12-.6.07-1.15-.12-1.62-.03-.07-.06-.14-.1-.22-.11-.2-.24-.39-.42-.55-.05-.05-.11-.11-.18-.16-.06-.05-.12-.09-.2-.14-.2-.12-.43-.22-.69-.29-.26-.07-.54-.11-.84-.11h-8.83c-.39,0-.74-.06-1.05-.17-.52-.18-.93-.51-1.19-.93-.16-.26-.27-.55-.32-.87-.04-.21-.05-.43-.03-.67.02-.35.11-.73.25-1.12l2.26-6.05c.78-2.08,3.08-3.75,5.16-3.75h8.83c2.05,0,4.33-1.65,5.13-3.69.01-.02.02-.05.03-.07l2.26-6.05h0c.78-2.08,3.08-3.75,5.16-3.75h8.83s.05,0,.07,0c2.03.04,3.05,1.71,2.28,3.75h0s-.04.11-.04.11v.03s-2.22,5.93-2.22,5.93c0,0,0,.01,0,.02,0,0,0,.01,0,.02-.75,2.05.3,3.71,2.36,3.71h8.83c.2,0,.39.02.57.05.09.02.18.04.27.06.09.02.16.05.24.08.04.01.07.03.11.05.07.03.13.05.19.09.03.01.06.03.09.05.09.05.18.11.26.17.07.05.12.1.18.16.06.05.11.11.16.17.15.18.27.38.35.6.03.07.05.14.08.22h0c.16.6.12,1.31-.16,2.06Z" />
      <path fill={couleur} d="M115.78,21.13c0,.45-.09.93-.28,1.45l-2.29,6.12c-5.03,13.32-9.14,34.97-9.14,40.33,0,5.94-4.19,9.61-5.87,10.85-.42.31-.66.81-.64,1.34h0c.04.71.55,1.3,1.25,1.44,1.59.33,6.49,4.59,8.2,4.78.95.11,1.6,1.03,1.34,1.96h0c-.31,1.11-1.32,1.88-2.47,1.88h-28.51c-1.02,0-1.95-.61-2.35-1.55l-.07-.16c-.41-.95.2-2.03,1.23-2.16,1.74-.21,6.55-4.43,8.14-4.76.7-.14,1.21-.73,1.25-1.44h0c.03-.53-.21-1.02-.64-1.34-1.68-1.23-5.87-4.91-5.87-10.85,0-6.24-5.57-34.54-11.67-46.1-1.08-2.05.4-4.5,2.71-4.5h42.93c.11,0,.22,0,.33.02.09,0,.18.02.26.04.17.04.34.08.48.13.1.03.19.07.28.12.08.03.15.07.22.12.15.1.29.21.42.33.07.06.12.12.18.18.06.07.11.14.15.21.02.03.03.05.05.08.06.08.1.17.14.26.06.12.1.25.14.38.04.14.07.28.09.42s.03.28.03.43Z" />
    </svg>
  );
}
