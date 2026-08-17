import { useEffect, useRef, useState } from "react";
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
 *
 * ---------------------------------------------------------------------------
 * TEST Liquid Glass (version 0.23.0) — **tout ce qui est marqué « TEST Liquid
 * Glass » dans ce fichier est jetable.** Le retirer, avec les trois fichiers de
 * `public/` et le bloc correspondant d'`index.html`, rend la barre à son état
 * antérieur sans rien toucher d'autre : le `materiau-chrome`, les quatre
 * icônes, la logique de navigation et l'accessibilité sont inchangés.
 * ---------------------------------------------------------------------------
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

function Onglet({ onglet, actif, refCreneau }) {
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
        <span className="relative flex items-center justify-center">
          {/* TEST Liquid Glass — créneau où l'effet dépose la pastille de
              verre. **React possède ce nœud, jamais son contenu** : c'est la
              seule façon d'insérer du DOM étranger sans exposer la
              réconciliation à un `insertBefore` sur un parent qui a changé.
              Vide, il ne coûte rien et le rendu est exactement celui d'avant. */}
          <span
            ref={refCreneau}
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 flex items-center justify-center"
          />

          {/* L'icône reste dans l'arbre React et passe au-dessus du verre :
              c'est elle le contenu visible du bouton. La déplacer dans le
              `textElement` de la librairie la ferait changer de parent, et
              React ne saurait plus la retirer au démontage. */}
          <Icone
            couleur={actif ? COULEUR_ACTIF : COULEUR_INACTIF}
            className="relative size-7"
          />
        </span>

        <span className="text-label-sm text-center leading-none">
          {onglet.libelle}
        </span>
      </Link>
    </li>
  );
}

/**
 * TEST Liquid Glass — récupération des deux classes de la librairie.
 *
 * **Elles ne sont pas sur `window`, et ce n'est pas un oubli du mainteneur.**
 * `container.js` et `button.js` déclarent `class Container {}` et
 * `class Button {}` au premier niveau d'un script classique : une déclaration
 * `class` crée une liaison dans l'environnement **lexical** global, jamais une
 * propriété de l'objet global — seuls `var` et les déclarations de fonction
 * font cette dernière. Tester `window.Container` retournerait donc toujours
 * `undefined`, et le repli serait permanent, la librairie chargée ou non.
 *
 * `typeof` est la seule lecture sûre : une référence nue à un identifiant
 * absent lève une `ReferenceError`. `globalThis` est essayé d'abord, au cas où
 * une version ultérieure exporterait explicitement.
 */
function classesVerre() {
  const conteneur =
    globalThis.Container ??
    (typeof Container !== "undefined" ? Container : null);
  const bouton =
    globalThis.Button ?? (typeof Button !== "undefined" ? Button : null);

  return conteneur && bouton ? { conteneur, bouton } : null;
}

// TEST Liquid Glass — dimensions de la pastille posée sous chaque icône. Le
// bouton est de type `pill`, donc la librairie dérive son rayon de la hauteur :
// c'est une capsule, jamais un rectangle arrondi.
const PASTILLE = { largeur: 52, hauteur: 36 };

/**
 * TEST Liquid Glass — libère une instance et la retire du registre statique.
 *
 * `Container.instances` est un tableau statique que la librairie ne purge
 * jamais : sans ce retrait, chaque montage de la barre y laisserait cinq
 * entrées de plus, et le prochain recalcul de taille les parcourrait toutes.
 *
 * Le contexte WebGL, lui, est perdu explicitement. Cinq contextes par montage
 * épuiseraient le quota du navigateur en quelques allers-retours entre écrans —
 * Safari détruit alors le plus ancien, et des pastilles s'éteignent au hasard,
 * sans que rien ne le signale.
 */
function demonter(ClasseConteneur, instance) {
  const rang = ClasseConteneur.instances.indexOf(instance);
  if (rang > -1) ClasseConteneur.instances.splice(rang, 1);

  const gl = instance.gl_refs?.gl ?? instance.gl;
  gl?.getExtension("WEBGL_lose_context")?.loseContext();

  instance.element?.remove();
}

/**
 * TEST Liquid Glass — construit le fond de la barre et les quatre pastilles.
 *
 * Rend la liste des instances créées, **vide si quoi que ce soit a échoué** :
 * le repli est alors total, jamais une barre à moitié vitrée.
 */
function construire(ClasseConteneur, ClasseBouton, barre, creneaux) {
  const instances = [];

  try {
    // Le fond de la barre. Rayon nul : elle touche les deux bords et le bas de
    // l'écran, une capsule y laisserait des coins beiges.
    const fond = new ClasseConteneur({
      borderRadius: 0,
      type: "rounded",
      tintOpacity: 0.15,
    });
    instances.push(fond);

    Object.assign(fond.element.style, {
      position: "absolute",
      inset: "0",
      padding: "0",
      // La librairie pose une ombre portée de 50px sur son canevas, calibrée
      // pour une pastille flottant au milieu d'une page. Sous une barre déjà
      // élevée par `shadow-flottant`, elle noircirait le bas de l'écran.
      boxShadow: "none",
    });
    fond.canvas.style.boxShadow = "none";
    barre.prepend(fond.element);
    fond.updateSizeFromDOM();

    // Les quatre pastilles. Elles ne passent **pas** par `fond.addChild()` :
    // la méthode déplace l'élément dans le conteneur, ce qui les sortirait des
    // `<Link>` et emporterait la navigation avec elles. Elles échantillonnent
    // donc la photographie de page plutôt que la sortie du conteneur — le verre
    // imbriqué est perdu, la navigation est intacte, et c'est le bon arbitrage
    // pour un essai qu'on doit pouvoir retirer sans rien casser.
    for (const onglet of ONGLETS) {
      const creneau = creneaux[onglet.cle];
      if (!creneau) continue;

      // `text` ne peut pas être vide : la librairie écrit
      // `options.text || 'Button'`, et une chaîne vide ferait donc apparaître
      // le mot « Button » au milieu de la pastille. Une espace passe le test de
      // vérité ; le nœud de texte est retiré juste après, l'icône React
      // occupant déjà la place.
      const pastille = new ClasseBouton({
        text: " ",
        size: 16,
        type: "pill",
        tintOpacity: 0.15,
      });
      instances.push(pastille);
      pastille.textElement?.remove();

      Object.assign(pastille.element.style, {
        width: `${PASTILLE.largeur}px`,
        height: `${PASTILLE.hauteur}px`,
        minWidth: `${PASTILLE.largeur}px`,
        minHeight: `${PASTILLE.hauteur}px`,
        maxWidth: `${PASTILLE.largeur}px`,
        maxHeight: `${PASTILLE.hauteur}px`,
        boxShadow: "none",
        // `.glass-button` réactive `pointer-events` et pose un curseur de main.
        // Le lien doit rester la seule cible : c'est lui qui porte la
        // navigation, le retour tactile et le lecteur d'écran.
        pointerEvents: "none",
        cursor: "inherit",
      });
      pastille.canvas.style.boxShadow = "none";
      creneau.appendChild(pastille.element);
      // Méthode publique de la librairie : elle relit la boîte réelle, y recale
      // le canevas, le rayon de la capsule et les uniformes du shader. Sans
      // elle, la pastille garderait la taille dérivée de son texte.
      pastille.updateSizeFromDOM();
    }

    return instances;
  } catch (erreur) {
    // Repli silencieux voulu : html2canvas absent (hors ligne, CDN bloqué),
    // WebGL indisponible, contexte refusé. La barre reste exactement celle
    // d'avant. Le message ne va qu'à la console — c'est un essai, et savoir
    // pourquoi il n'a pas pris est tout l'intérêt.
    console.warn("[liquid-glass] repli sur la barre standard", erreur);
    instances.forEach((instance) => demonter(ClasseConteneur, instance));
    return [];
  }
}

export default function NavBarre() {
  const { pathname } = useLocation();
  const { utilisateur } = useAuth();

  // TEST Liquid Glass. Les trois hooks vivent **avant** le retour anticipé plus
  // bas : les règles de React interdisent un `return` qui les
  // court-circuiterait. C'est la même précaution qu'au masquage des boutons
  // OAuth (version 0.2.2).
  const refBarre = useRef(null);
  const refCreneaux = useRef({});
  // Tant que le verre n'est pas monté, la barre garde `materiau-chrome` : un
  // échec de chargement doit rendre exactement l'apparence d'avant, pas une
  // barre transparente sur laquelle le contenu de la page défilerait.
  const [verreActif, setVerreActif] = useState(false);

  // La condition d'affichage est extraite parce que l'effet en dépend, et
  // qu'un hook ne peut pas vivre après le retour anticipé qu'elle commande.
  const visible = Boolean(utilisateur) && barreVisible(pathname);

  useEffect(() => {
    if (!visible) return undefined;

    let instances = [];
    let classeConteneur = null;
    let annule = false;

    const monter = () => {
      if (annule || !refBarre.current) return;

      const classes = classesVerre();
      if (!classes) return;

      classeConteneur = classes.conteneur;
      instances = construire(
        classes.conteneur,
        classes.bouton,
        refBarre.current,
        refCreneaux.current,
      );
      setVerreActif(instances.length > 0);
    };

    // **Le verre ne peut pas être monté tout de suite, et ce n'est pas une
    // précaution en l'air.** Vite hisse le script de module dans le `<head>` ;
    // les trois scripts de la librairie vivent en fin de `<body>`. Tous étant
    // différés, ils s'exécutent dans l'ordre du document : `main.jsx` d'abord,
    // donc React rend et cet effet tourne **avant** que `Container` existe. Le
    // garde retomberait alors sur le repli à chaque fois, la librairie chargée
    // ou non.
    //
    // `load` est le seul signal qui tranche : il suit l'exécution de tous les
    // scripts différés, celui du CDN compris, et il est émis même quand l'un
    // d'eux échoue — un chargement lent est donc attendu, une absence réelle
    // est constatée. Bénéfice second : html2canvas photographie alors une page
    // rendue et stabilisée, au lieu d'un écran à moitié peint.
    if (document.readyState === "complete") monter();
    else window.addEventListener("load", monter, { once: true });

    return () => {
      annule = true;
      window.removeEventListener("load", monter);
      if (classeConteneur) {
        instances.forEach((instance) => demonter(classeConteneur, instance));
      }
      setVerreActif(false);
    };
    // Le montage suffit : la barre vit dans `App.jsx`, hors de `<Routes>`, et
    // ne se remonte qu'en entrant ou sortant des écrans qui la portent. La
    // relancer à chaque navigation rephotographierait la page pour rien.
  }, [visible]);

  // Rien à proposer à qui n'est pas connecté : les quatre onglets mènent tous à
  // des routes protégées. Le seul écran concerné est celui des résultats d'un
  // Grand Prix, public depuis l'étape 9 et partageable par lien.
  if (!visible) return null;

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
      //
      // TEST Liquid Glass : `materiau-chrome` cède la place au verre une fois
      // celui-ci monté — les deux superposés donneraient un flou par-dessus un
      // flou, et la réfraction ne se verrait plus. Il revient au moindre échec.
      ref={refBarre}
      className={`pb-safe-bottom shadow-flottant fixed inset-x-0 bottom-0 z-30 ${
        verreActif ? "" : "materiau-chrome"
      }`}
    >
      {/* `t-nav` porte la seule chose qui s'anime ici : la couleur des icônes.
          Elle est déclarée sur le conteneur pour ne pas la répéter par onglet.
          `relative` la pose au-dessus du canevas de verre, que l'effet insère
          en premier enfant du `<nav>`. */}
      <ul className="t-nav relative mx-auto flex max-w-[520px] items-stretch px-2 pt-1.5 pb-1">
        {ONGLETS.map((onglet) => (
          <Onglet
            key={onglet.cle}
            onglet={onglet}
            actif={onglet.cle === courant}
            refCreneau={(noeud) => {
              refCreneaux.current[onglet.cle] = noeud;
            }}
          />
        ))}
      </ul>
    </nav>
  );
}
