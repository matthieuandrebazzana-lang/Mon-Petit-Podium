import { matchPath } from "react-router-dom";

/**
 * Les quatre onglets de la barre basse, et les écrans qui la portent.
 *
 * **Une seule source de vérité, et c'est le point de ce module.** Deux endroits
 * ont besoin de la même réponse : `NavBarre` pour savoir si elle s'affiche, et
 * `Ecran` pour réserver la hauteur qu'elle occupe. Deux listes écrites
 * séparément auraient divergé au premier écran ajouté, avec un symptôme
 * discret — une barre posée sur le dernier bouton d'un écran, ou un blanc de
 * 56px sous un écran qui n'en a pas.
 */

/* Écrans qui portent la barre. Les motifs sont ceux de `App.jsx` : les écrire
   en clair plutôt que de tester des préfixes évite qu'un futur
   `/championnats/:id/quelque-chose` l'hérite sans qu'on l'ait décidé. */
const CHEMINS_AVEC_BARRE = [
  "/accueil",
  "/championnats",
  "/championnats/:id",
  "/calendrier",
  // La fiche d'un Grand Prix : elle appartient à l'onglet Calendrier, comme
  // l'écran d'un championnat appartient au sien. On y consulte, on n'y saisit
  // rien — et retirer la barre obligerait à ressortir par le bouton de retour
  // pour changer d'onglet.
  "/calendrier/:slug",
  "/profil",
  "/profils/:profilId",
  // Les résultats d'un Grand Prix, dans leurs deux formes (étape 9). La barre
  // ne s'affiche que pour un membre connecté — `NavBarre` le vérifie — mais
  // l'écran reste public.
  "/grands-prix/:gpId/resultats",
  "/championnats/:id/grands-prix/:gpId/resultats",
];

/* `/championnats/creer` et `/championnats/rejoindre` répondent au motif
   `/championnats/:id` : React Router ne fait pas la différence, et l'ordre des
   routes de `App.jsx` ne s'applique pas ici. Ce sont deux écrans de saisie, la
   demande les exclut explicitement — d'où cette liste, qui passe en premier. */
const CHEMINS_SANS_BARRE = ["/championnats/creer", "/championnats/rejoindre"];

function correspond(motif, chemin) {
  return matchPath({ path: motif, end: true }, chemin) !== null;
}

/**
 * La barre s'affiche-t-elle sur ce chemin ?
 *
 * Ne dit rien de la session : `NavBarre` y ajoute la condition d'être connecté.
 * `Ecran`, lui, réserve la place dans les deux cas — 56px de blanc en bas d'un
 * écran de résultats consulté sans compte ne se remarquent pas, une barre posée
 * par-dessus le contenu, si.
 */
export function barreVisible(chemin) {
  if (CHEMINS_SANS_BARRE.some((motif) => correspond(motif, chemin))) return false;
  return CHEMINS_AVEC_BARRE.some((motif) => correspond(motif, chemin));
}

/**
 * Les quatre onglets, dans l'ordre de la maquette 04.
 *
 * `actif` est une fonction et non un simple chemin : un onglet reste allumé sur
 * tout ce qui lui appartient. Le classement d'un championnat, sa vue piste et
 * son calendrier sont tous « Championnats », et le profil d'un autre membre est
 * toujours l'onglet Profil. Un onglet qui s'éteindrait dès le premier écran de
 * détail ne dirait plus où l'on se trouve.
 */
export const ONGLETS = [
  {
    cle: "accueil",
    libelle: "Accueil",
    vers: "/accueil",
    actif: (chemin) => chemin === "/accueil",
  },
  {
    cle: "championnats",
    libelle: "Championnats",
    vers: "/championnats",
    actif: (chemin) => chemin === "/championnats" || chemin.startsWith("/championnats/"),
  },
  {
    cle: "calendrier",
    libelle: "Calendrier",
    vers: "/calendrier",
    // La fiche d'un Grand Prix allume l'onglet qui la porte : « un onglet reste
    // allumé sur tout ce qui lui appartient », comme le classement et la vue
    // piste d'un championnat gardent le leur.
    actif: (chemin) =>
      chemin === "/calendrier" || chemin.startsWith("/calendrier/"),
  },
  {
    cle: "profil",
    libelle: "Profil",
    vers: "/profil",
    actif: (chemin) => chemin === "/profil" || chemin.startsWith("/profils/"),
  },
];

/** La clé de l'onglet courant, ou `null` si aucun ne revendique ce chemin. */
export function ongletActif(chemin) {
  return ONGLETS.find((onglet) => onglet.actif(chemin))?.cle ?? null;
}

/* -------------------------------------------------------------------------- */
/*  Retour contextuel                                                         */
/* -------------------------------------------------------------------------- */

/**
 * Un même écran est atteint depuis plusieurs endroits, et son bouton de retour
 * doit ramener d'où l'on vient. Le tableau des cotes s'ouvre depuis l'accueil
 * **et** depuis le calendrier ; un retour qui ramènerait toujours à l'accueil
 * ferait perdre sa place à qui parcourait la saison.
 *
 * L'origine voyage dans l'état de navigation de React Router, sous **deux clés
 * distinctes qu'il ne faut pas confondre** :
 *
 * - `retour` — où va MON bouton de retour ;
 * - `origine` — ce que je rends à cet écran quand j'y retourne, pour qu'il
 *   retrouve sa propre origine. Sans elle, la chaîne se casse au premier
 *   rebond : calendrier → cotes → pronos → retour → cotes → retour → **accueil**.
 */

/* Un chemin interne, et rien d'autre. L'état de navigation est écrit par les
   écrans, mais il survit à un rechargement et se retrouve dans l'historique du
   navigateur : une URL absolue glissée là ferait du bouton de retour une sortie
   vers l'extérieur. */
const CHEMIN_INTERNE = /^\/[\w\-/]*$/;

/**
 * La destination du bouton de retour, et son libellé.
 *
 * `defaut` est la destination hiérarchique de l'écran — celle qui s'applique
 * quand on y arrive par un lien direct. Le libellé d'une origine connue vient
 * des onglets : un bouton doit **nommer sa destination**, et « Accueil » posé
 * sur un retour vers le calendrier serait une promesse fausse.
 */
export function origineRetour(etat, defaut) {
  const vers = etat?.retour;
  if (typeof vers !== "string" || !CHEMIN_INTERNE.test(vers)) return defaut;
  const onglet = ONGLETS.find((element) => element.vers === vers);
  return { vers, libelle: onglet?.libelle ?? defaut.libelle };
}
