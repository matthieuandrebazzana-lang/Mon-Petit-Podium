/**
 * Icônes extraites telles quelles des maquettes 01 à 03.
 *
 * Le skill Taste proscrit les SVG écrits à la main et impose une librairie
 * d'icônes. Ici le CLAUDE.md gagne : les maquettes font foi pour la structure
 * et fournissent déjà ces tracés. Les marques Google et Apple, en particulier,
 * doivent rester conformes aux chartes des deux fournisseurs — une icône
 * générique n'a pas le droit de les remplacer.
 *
 * `currentColor` partout où la couleur doit suivre le contexte ; les deux
 * marques gardent leurs couleurs officielles.
 */

export function IconeDrapeau(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true" {...props}>
      <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z" />
      <line x1="4" y1="22" x2="4" y2="15" />
    </svg>
  );
}

export function IconeMembres(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  );
}

export function IconeVoiture(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <rect x="1" y="3" width="15" height="13" rx="2" />
      <path d="M16 8h4l3 3v5h-7V8z" />
      <circle cx="5.5" cy="18.5" r="2.5" />
      <circle cx="18.5" cy="18.5" r="2.5" />
    </svg>
  );
}

export function IconeChevronGauche(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <polyline points="15 18 9 12 15 6" />
    </svg>
  );
}

export function IconeChevronDroit(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <polyline points="9 18 15 12 9 6" />
    </svg>
  );
}

export function IconePlus(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <line x1="12" y1="5" x2="12" y2="19" />
      <line x1="5" y1="12" x2="19" y2="12" />
    </svg>
  );
}

/* Maillon de chaîne — la carte « Rejoindre un championnat ».
   Rejoindre, c'est entrer un code reçu d'ailleurs : le maillon dit le lien vers
   un championnat qui existe déjà, là où le `+` dit la création. Les deux
   doivent se distinguer d'un coup d'œil au pouce, posées l'une sous l'autre. */
export function IconeLien(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true" {...props}>
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  );
}

/* Tracé repris de la maquette 05, bouton « Copier le code ». */
export function IconeCopie(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <rect x="9" y="9" width="13" height="13" rx="2" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </svg>
  );
}

export function IconeCoche(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );
}

export function IconeSortie(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <polyline points="16 17 21 12 16 7" />
      <line x1="21" y1="12" x2="9" y2="12" />
    </svg>
  );
}

/* Étoile de favori, reprise de la maquette 08. Deux variantes dans le même
   tracé : `pleine` remplit le contour au lieu de le dessiner seul. */
export function IconeEtoile({ pleine = false, ...props }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill={pleine ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
    </svg>
  );
}

/* ---------------------------------------------------------------------------
   Les quatre icônes de la barre de navigation basse (étape 10).

   Chacune accepte `pleine` : le contour désigne l'onglet au repos, l'aplat
   l'onglet actif. C'est le couple que l'échange d'icônes de transitions-dev 09
   fait glisser de l'un à l'autre, et c'est aussi la façon dont iOS distingue
   l'onglet courant — la couleur seule reste le signal principal, l'aplat
   l'appuie.

   Les variantes pleines sont dessinées avec `fill-rule="evenodd"` plutôt qu'en
   superposant une forme de la couleur du fond : la barre est blanche
   aujourd'hui, elle ne le sera peut-être pas toujours, et un aplat blanc en dur
   se verrait le jour où le fond change.
   --------------------------------------------------------------------------- */

/* Maison — la porte est un trou dans l'aplat, pas un rectangle blanc posé
   dessus. */
export function IconeMaison({ pleine = false, ...props }) {
  if (pleine) {
    return (
      <svg viewBox="0 0 24 24" fill="currentColor" fillRule="evenodd" aria-hidden="true" {...props}>
        <path d="M12 1.36 22 9.13V20a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3V9.13zM10 21h4v-8h-4z" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" aria-hidden="true" {...props}>
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  );
}

/* Trophée — l'onglet Championnats.

   **Écart assumé par rapport à la maquette 04**, qui y met le même tracé de
   groupe de personnes qu'`IconeMembres`. Deux raisons de ne pas le suivre : la
   maquette pose alors deux icônes de personnages côte à côte (Championnats et
   Profil), impossibles à distinguer d'un coup d'œil au pouce ; et
   `IconeMembres` sert déjà d'emblème aux cartes de championnat de l'accueil,
   où elle désigne l'effectif. La demande de l'étape 10 tranche pour le
   trophée. */
export function IconeTrophee({ pleine = false, ...props }) {
  const coupe = "M6 3h12v6a6 6 0 0 1-12 0z";
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...props}>
      <path d={coupe} fill={pleine ? "currentColor" : "none"} />
      <path d="M6 5H3.5v1.5A3.5 3.5 0 0 0 7 10" />
      <path d="M18 5h2.5v1.5A3.5 3.5 0 0 1 17 10" />
      <line x1="12" y1="15" x2="12" y2="18" />
      <path d="M8.5 21h7l-.7-3h-5.6z" fill={pleine ? "currentColor" : "none"} />
    </svg>
  );
}

/* Calendrier — quatrième onglet de la barre des maquettes, repris aussi pour le
   bouton qui mène au calendrier d'un championnat (maquette 15).

   La variante pleine ne remplit que le corps, sous la barre de titre : un
   rectangle intégralement plein ne se lirait plus comme un calendrier. */
export function IconeCalendrier({ pleine = false, ...props }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      {pleine && (
        <path d="M3 10h18v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" fill="currentColor" stroke="none" />
      )}
      <rect x="3" y="4" width="18" height="18" rx="2" />
      <line x1="16" y1="2" x2="16" y2="6" />
      <line x1="8" y1="2" x2="8" y2="6" />
      <line x1="3" y1="10" x2="21" y2="10" />
    </svg>
  );
}

/* Personne — l'onglet Profil. Tracé de la maquette 04. */
export function IconePersonne({ pleine = false, ...props }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...props}>
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" fill={pleine ? "currentColor" : "none"} />
      <circle cx="12" cy="7" r="4" fill={pleine ? "currentColor" : "none"} />
    </svg>
  );
}

/* Horloge du bloc de fermeture, maquette 09. */
export function IconeHorloge(props) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" {...props}>
      <circle cx="12" cy="12" r="10" />
      <polyline points="12 6 12 12 16 14" />
    </svg>
  );
}

/* Chevron du sélecteur qui se déplie. Le viewBox 16×16 et ce tracé viennent
   du snippet d'accordéon de transitions-dev : la bascule `scaleY(-1)` du CSS
   suppose exactement cette géométrie. Ne pas le remplacer par
   `IconeChevronDroit` pivoté. */
export function IconeChevronAccordeon(props) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      <path d="M4 6.5L8 10.5L12 6.5" />
    </svg>
  );
}

export function IconeGoogle(props) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" {...props}>
      <path
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
        fill="#4285F4"
      />
      <path
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
        fill="#34A853"
      />
      <path
        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
        fill="#FBBC05"
      />
      <path
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
        fill="#EA4335"
      />
    </svg>
  );
}

export function IconeApple(props) {
  return (
    <svg viewBox="0 0 24 24" fill="#1a1a1a" aria-hidden="true" {...props}>
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  );
}
