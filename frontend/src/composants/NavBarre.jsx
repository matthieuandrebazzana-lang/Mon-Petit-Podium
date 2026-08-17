import { Link, useLocation } from "react-router-dom";
import { useAuth } from "../auth/AuthContexte.jsx";
import { ONGLETS, barreVisible, ongletActif } from "../lib/navigation.js";
import IconeAccueil from "./icones/IconeAccueil.jsx";
import IconeCalendrier from "./icones/IconeCalendrier.jsx";
import IconeChampionnats from "./icones/IconeChampionnats.jsx";
import IconeProfil from "./icones/IconeProfil.jsx";

/**
 * Barre de navigation basse à quatre onglets (maquette 04).
 *
 * **Montée une seule fois, dans `App.jsx`, hors de `<Routes>`.** Trois raisons,
 * dans l'ordre d'importance :
 *
 * 1. `Ecran` porte l'animation d'entrée `t-ecran`, donc un `transform`. Un
 *    élément `position: fixed` placé à l'intérieur se positionne alors par
 *    rapport à cet ancêtre et non à la fenêtre : la barre défilerait avec la
 *    page. Ce n'est pas un détail de style, c'est la règle des blocs conteneurs
 *    de CSS, et elle vaut même pour `translateX(0)`.
 * 2. Elle ne se démonte pas d'un écran à l'autre : la couleur de l'onglet
 *    glisse de l'ancien au nouveau au lieu de repartir de zéro à chaque
 *    navigation, ce que fait une barre remontée à chaque écran.
 * 3. Un seul endroit décide où elle apparaît, et c'est `lib/navigation.js`.
 *
 * La place qu'elle occupe est réservée par `Ecran`, à partir de la même
 * fonction `barreVisible`.
 */

const ICONES = {
  accueil: IconeAccueil,
  championnats: IconeChampionnats,
  calendrier: IconeCalendrier,
  profil: IconeProfil,
};

// Les deux couleurs sont celles du design system (section 5) : le bordeaux de
// la marque et le gris du texte secondaire. Elles sont écrites en clair et non
// lues dans un jeton Tailwind parce qu'elles partent dans un attribut `fill`,
// que les utilitaires de couleur ne touchent pas.
const COULEUR_ACTIF = "#800111";
const COULEUR_INACTIF = "#999999";

function Onglet({ onglet, actif }) {
  const Icone = ICONES[onglet.cle];

  return (
    <li className="flex-1">
      <Link
        to={onglet.vers}
        aria-current={actif ? "page" : undefined}
        // `min-h-tactile` et non `h-tactile` : la contrainte iOS est un
        // plancher, et la rangée doit pouvoir grandir si le corps de texte est
        // agrandi dans les réglages du téléphone.
        //
        // La couleur du **libellé** reste posée sur le lien. Celle de l'icône
        // voyage par une prop, les tracés de `logo-02.svg` portant un `fill` et
        // non `currentColor` ; les deux se rejoignent dans `.t-nav`, qui
        // interpole `color` et `fill` sur la même durée et la même courbe —
        // sinon l'œil voit le texte virer avant le dessin.
        className={`t-nav-onglet pressable min-h-tactile flex flex-col items-center justify-center gap-1 px-1 py-1.5 ${
          actif ? "text-primaire" : "text-texte-doux"
        }`}
        onClick={(evenement) => {
          // Retoucher l'onglet déjà ouvert ramène en haut de l'écran, comme
          // partout sur iOS. Sans cela l'appui ne fait rien du tout : React
          // Router considère qu'on est déjà arrivé.
          if (!actif) return;
          evenement.preventDefault();
          window.scrollTo({ top: 0, behavior: "smooth" });
        }}
      >
        {/* L'échange contour ↔ aplat (transitions-dev 09) n'a plus d'objet :
            les icônes de `logo-02.svg` n'existent qu'en une seule forme. La
            couleur redevient donc le signal unique, comme elle l'était déjà à
            titre principal. Le snippet reste installé, et sert toujours à
            l'étoile de favori. */}
        <Icone
          couleur={actif ? COULEUR_ACTIF : COULEUR_INACTIF}
          className="size-7"
        />

        <span className="text-label-sm text-center leading-none">
          {onglet.libelle}
        </span>
      </Link>
    </li>
  );
}

export default function NavBarre() {
  const { pathname } = useLocation();
  const { utilisateur } = useAuth();

  // Rien à proposer à qui n'est pas connecté : les quatre onglets mènent tous à
  // des routes protégées. Le seul écran concerné est celui des résultats d'un
  // Grand Prix, public depuis l'étape 9 et partageable par lien.
  if (!utilisateur || !barreVisible(pathname)) return null;

  const courant = ongletActif(pathname);

  return (
    <nav
      aria-label="Navigation principale"
      // Aucune bordure (section 5 : jamais de trait fin). La barre est un
      // **matériau translucide** (/apple-design §12) : le contenu passe dessous
      // et reste deviné, ce qui dit à la fois qu'elle flotte et que la page
      // continue — une barre opaque, elle, ampute définitivement l'écran.
      // `shadow-flottant` l'éloigne du fond ; sa teinte est le marron du design
      // system, pas un noir pur, qui grisaillerait le beige.
      //
      // Le liseré blanc que le snippet d'/apple-design pose sur l'arête haute
      // n'est pas repris : la section 5 proscrit les traits fins, et sur une
      // barre déjà blanche il ne se verrait pas. Le CLAUDE.md gagne.
      className="materiau-chrome pb-safe-bottom shadow-flottant fixed inset-x-0 bottom-0 z-30"
    >
      {/* `t-nav` porte la seule chose qui s'anime ici : la couleur des icônes.
          Elle est déclarée sur le conteneur pour ne pas la répéter par onglet. */}
      <ul className="t-nav mx-auto flex max-w-[520px] items-stretch px-2 pt-1.5 pb-1">
        {ONGLETS.map((onglet) => (
          <Onglet
            key={onglet.cle}
            onglet={onglet}
            actif={onglet.cle === courant}
          />
        ))}
      </ul>
    </nav>
  );
}
