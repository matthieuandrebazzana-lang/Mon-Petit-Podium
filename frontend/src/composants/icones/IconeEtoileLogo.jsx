/**
 * L'étoile de `assets/logoV2.svg` — l'état « pas encore ajouté » du bouton de
 * pari bonus (`EtoileFavori.jsx`).
 *
 * **Extraite telle quelle de la planche** : le `d` est identique au fichier
 * d'origine à l'octet près, aucune coordonnée n'est réécrite, seul le cadrage
 * bouge — les quatre règles d'extraction de `docs/composants.md` §4. Le
 * découpage a été fait par script : c'est le deuxième des quatre dessins de la
 * planche, et le seul `<path>` enfant direct du `<svg>`.
 *
 * **La `viewBox` est la vraie boîte englobante, pas une tranche arithmétique.**
 * *Écart assumé par rapport à la demande*, qui prescrivait `155 0 154.91
 * 110.14` — le tiers du milieu d'une planche large de 464,91. L'étoile mesure
 * x 150,34 → 223,84 · y 13,55 → 83,89, extrema des cubiques résolus : ce
 * cadrage lui **couperait 4,66 unités de la pointe gauche**, la poserait
 * 45,37 unités à gauche du centre, et ne lui laisserait que 47,44 % de la
 * largeur de la boîte au lieu de 83,51 %. C'est la règle 2 de
 * `docs/composants.md` §4, et c'est l'arbitrage déjà tenu par `IconeCreer`.
 *
 * **Le carré fait 88 unités**, soit une étoile qui en occupe 83,51 % : exactement
 * la part que `IconeEtoile` (maquette 08) occupe de sa boîte de 24, 20 unités
 * sur 24. Les deux étoiles du projet pèsent donc pareil à taille de rendu
 * égale, et un cadrage serré sur la boîte l'aurait rendue d'un tiers plus
 * grosse que le `+` qu'elle remplace.
 *
 * La couleur suit le contexte — l'appelant la pose sur le conteneur, comme
 * partout ailleurs dans `Icones.jsx`. Le `#1d1d1b` de la planche ne dit rien
 * de l'état d'un bouton.
 */
export default function IconeEtoileLogo({ couleur = "currentColor", ...reste }) {
  return (
    <svg
      viewBox="143.09 4.72 88 88"
      aria-hidden="true"
      focusable="false"
      {...reste}
    >
      <path fill={couleur} d="M190.98,15.93l9.23,17.97,19.94,3.23c3.52.57,4.92,4.88,2.41,7.41l-14.23,14.33,3.09,19.96c.55,3.52-3.12,6.18-6.3,4.58l-18.03-9.11-18.03,9.11c-3.18,1.61-6.85-1.06-6.3-4.58l3.09-19.96-14.23-14.33c-2.51-2.53-1.11-6.84,2.41-7.41l19.94-3.23,9.23-17.97c1.63-3.17,6.16-3.17,7.79,0Z" />
    </svg>
  );
}
