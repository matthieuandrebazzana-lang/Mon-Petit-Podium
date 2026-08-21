import { useLocation } from "react-router-dom";
import { useAuth } from "../auth/AuthContexte.jsx";
import { barreVisible } from "../lib/navigation.js";

/**
 * La pastille « Prévisualisation » — le rappel permanent que ce qu'on voit
 * n'est pas ce que voient les autres.
 *
 * ## Pourquoi elle existe
 *
 * Le mode prévisualisation montre volontairement quelque chose de faux : des
 * Grands Prix ouverts aux pronostics alors que leurs cotes ne sont pas figées.
 * Sans marque à l'écran, rien ne distingue cette vue de la vraie — et
 * l'administrateur qui a allumé l'interrupteur trois écrans plus tôt conclurait
 * de bonne foi que le job du samedi a tourné. C'est le seul défaut qu'un mode
 * de vérification puisse avoir, et cette pastille est ce qui l'empêche.
 *
 * C'est un **retour de statut** au sens d'`/apple-design` §16 (« expose ongoing
 * status ») : elle dit où l'on est, pas ce qu'il faut faire.
 *
 * ## Montée dans `App.jsx`, hors de `<Routes>`
 *
 * Exactement pour les trois raisons de `NavBarre`, et la première est
 * structurelle : `Ecran` porte un `transform` (son animation d'entrée), et un
 * élément `position: fixed` posé à l'intérieur se positionne alors par rapport
 * à cet ancêtre et non à la fenêtre — la pastille défilerait avec la page. Elle
 * ne se démonte pas non plus d'un écran à l'autre, ce qui est le point : le
 * mode traverse toute l'application, sa marque aussi.
 *
 * ## Non intrusive, au sens propre
 *
 * `pointer-events: none`. Ce n'est pas un contrôle, et elle ne doit jamais
 * intercepter un appui destiné à ce qu'elle recouvre — l'exigence des 44 × 44 px
 * ne la concerne donc pas, faute de cible. Elle s'éteint là où on l'allume,
 * dans le profil, ce qui est aussi la règle de mapping : le contrôle vit près
 * de ce qu'il commande, et il n'y en a qu'un.
 *
 * ## Sa place à l'écran
 *
 * **En bas à gauche, au-dessus de la barre de navigation.** Les deux autres
 * coins sont pris : l'en-tête collant occupe toute la bande haute — titre à
 * gauche, pastille de profil à droite — et poser quoi que ce soit dessus
 * masquerait l'un ou l'autre. Le bas gauche est le seul coin qu'aucun écran
 * n'utilise.
 *
 * La hauteur de la barre est **lue à la même source qu'elle** (`barreVisible`,
 * `lib/navigation.js`) : une seconde liste d'écrans aurait divergé au premier
 * ajouté, et le symptôme aurait été une pastille posée sur l'onglet Accueil.
 * Sur les écrans sans barre, elle redescend contre la zone sûre.
 *
 * ## Matériau et encre
 *
 * `materiau-chrome`, comme la barre de navigation : une pastille opaque
 * poserait un second bloc plein en concurrence avec elle, là où le matériau se
 * lit comme une couche flottante (/apple-design §12). Le contraste est mesuré
 * et non choisi, sur la feuille compilée et pour les deux fonds extrêmes : le
 * bordeaux `primaire` (#800111) sur le matériau posé sur blanc tient
 * **10,88:1**, et sur le pire fond de l'application — le noir du drapeau de Las
 * Vegas, qui ramène le matériau à rgb(184,184,184) — encore **5,48:1**. Les
 * 4,5:1 d'un texte ordinaire sont donc tenus partout, sans que le mot ait
 * besoin de son propre aplat. Sous `prefers-reduced-transparency`,
 * `materiau-chrome` redevient blanc opaque et le rapport remonte à 10,88:1.
 *
 * Le point coloré est décoratif (`aria-hidden`) : le mot « Prévisualisation »
 * porte déjà toute l'information, et un signal qui ne tiendrait qu'à une
 * couleur ne dirait rien à qui ne la distingue pas.
 */
export default function BandeauPrevisualisation() {
  const { modeAdmin, modePrevisualisation } = useAuth();
  const { pathname } = useLocation();

  // **Le montage suit `modeAdmin`, la visibilité suit `modePrevisualisation`.**
  // Un membre ordinaire n'a donc jamais cet élément dans son DOM ; un
  // administrateur, lui, le garde monté le temps de sa session admin, ce qui
  // est ce qui permet à la pastille de transitionner dans les deux sens au lieu
  // d'apparaître d'un coup à chaque montage.
  if (!modeAdmin) return null;

  return (
    <div
      // `role="status"` : le changement s'annonce sans voler le focus, comme
      // l'indicateur d'envoi de la section d'administration.
      role="status"
      aria-hidden={modePrevisualisation ? undefined : "true"}
      data-actif={modePrevisualisation ? "vrai" : "faux"}
      data-barre={barreVisible(pathname) ? "vrai" : "faux"}
      // La position, la hauteur de barre et la transition vivent dans
      // `index.css` : elles tiennent à des `calc()` sur les zones sûres et sur
      // `--spacing-nav`, que des valeurs arbitraires Tailwind rendraient
      // illisibles et fragiles. Ne restent ici que le matériau, l'encre et la
      // typographie.
      className="bandeau-previsualisation materiau-chrome shadow-carte flex items-center gap-2 rounded-full py-1.5 pr-3.5 pl-3 select-none"
    >
      <span
        aria-hidden="true"
        className="bg-primaire size-1.5 shrink-0 rounded-full"
      />
      {/* `font-semibold` plutôt que le 500 du jeton : sur un matériau
          translucide, /apple-design §12 demande une graisse un peu supérieure
          et un léger surplus d'interlettrage — le jeton `text-label` porte déjà
          les 0,7px. */}
      <span className="text-label text-primaire font-semibold uppercase">
        Prévisualisation
      </span>
    </div>
  );
}
