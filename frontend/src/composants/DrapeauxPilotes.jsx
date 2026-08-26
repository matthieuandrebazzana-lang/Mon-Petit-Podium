import AR from "country-flag-icons/react/3x2/AR";
import AU from "country-flag-icons/react/3x2/AU";
import BR from "country-flag-icons/react/3x2/BR";
import CA from "country-flag-icons/react/3x2/CA";
import DE from "country-flag-icons/react/3x2/DE";
import ES from "country-flag-icons/react/3x2/ES";
import FI from "country-flag-icons/react/3x2/FI";
import FR from "country-flag-icons/react/3x2/FR";
import GB from "country-flag-icons/react/3x2/GB";
import IT from "country-flag-icons/react/3x2/IT";
import JP from "country-flag-icons/react/3x2/JP";
import MC from "country-flag-icons/react/3x2/MC";
import MX from "country-flag-icons/react/3x2/MX";
import NL from "country-flag-icons/react/3x2/NL";
import NZ from "country-flag-icons/react/3x2/NZ";
import TH from "country-flag-icons/react/3x2/TH";

/**
 * Les drapeaux de nationalité des pilotes — seize pays, seize SVG.
 *
 * ## Pourquoi une bibliothèque, alors que le projet dessine ses drapeaux
 *
 * `DrapeauxGP.jsx` peint les pays **hôtes** : cinq en dégradés CSS et sept
 * dessinés, et son en-tête pose la règle qui gouverne les deux — **jamais un
 * drapeau approximé**. C'est cette règle qui a laissé l'Australie et la
 * Finlande sans fond en version `0.60.0` : une croix du Sud et une croix
 * nordique n'ont pas de description qu'un dégradé sache poser sans la trahir.
 *
 * La grille 2026 demande **seize** pays, dont l'Australie, la
 * Nouvelle-Zélande, le Brésil, le Mexique, le Canada, la Thaïlande et
 * l'Argentine — sept drapeaux qu'aucune borne de dégradé ne sait dire. La
 * règle n'est donc pas contournée ici, elle est **tenue** : plutôt que
 * d'approximer sept drapeaux, on prend seize dessins exacts.
 *
 * ## Ce que la bibliothèque coûte, et pourquoi c'est celle-ci
 *
 * `country-flag-icons` expose **un module par pays** en ESM pur, annoté
 * `#__PURE__` et déclaré `sideEffects: false` : les seize imports nommés
 * ci-dessus sont les seuls drapeaux qui entrent dans le lot, les 249 autres
 * sont éliminés à la compilation. Les seize fichiers 3×2 pèsent **7,0 Ko en
 * tout**, de 151 octets (Monaco) à 1,4 Ko (Australie) ; le Japon en ajoute
 * **158**, le deuxième plus petit de la planche — un aplat blanc et un disque.
 *
 * > **Écart signalé (CLAUDE.md §6).** La demande nommait `react-world-flags`
 * > « de préférence ». Il ne convient pas, pour deux raisons mesurées et non
 * > supposées : son `dist` est un lot **UMD de 3,6 Mo** qui embarque les 250
 * > drapeaux en data-URI, sans découpage possible — soit vingt fois le poids
 * > actuel de l'application pour seize pays ; et son code source résout les
 * > drapeaux par `require.context`, une API **propre à webpack** que Vite
 * > n'implémente pas. `country-flag-icons` répond à la demande telle qu'elle
 * > est formulée — « import SVG par code ISO 3166-1 alpha-2 » — sans ces deux
 * > défauts.
 *
 * ## Trois points à ne pas défaire
 *
 * 1. **Aucun `fill` ni `color` ne doit être posé sur un conteneur de ces SVG.**
 *    La bande noire du drapeau allemand n'a **pas** d'attribut `fill` : elle
 *    tient son noir du défaut SVG, donc elle **hérite** de tout `fill` qu'un
 *    ancêtre déclarerait. Le drapeau canadien pose le même piège à l'envers,
 *    avec un `fill="red"` en mot-clé. Rien ne se voit à la lecture du JSX.
 * 2. **`preserveAspectRatio="none"` — et c'est le rendu contre la feuille
 *    compilée qui l'a imposé, contre le `slice` que tout le reste du projet
 *    emploie.** Une rangée de classement fait **343 × 65,5 px**, soit un rapport
 *    de 5,2:1 là où un drapeau en fait 1,5:1. `slice` — le pendant
 *    d'`object-fit: cover` — recadre donc sur la **bande centrale** et jette
 *    tout le reste : l'Allemagne ressortait entièrement rouge, indistinguable
 *    d'un pays à drapeau rouge, et l'Espagne entièrement jaune. Le drapeau ne
 *    disait plus la nationalité, ce qui est la seule chose qu'on lui demande.
 *    `none` rend les deux échelles indépendantes : **toutes** les bandes
 *    survivent, seule leur proportion s'étire, et la signature de couleur reste
 *    juste. C'est exactement l'arbitrage de `FondPiste` (`composants.md` §4), et
 *    pour la même raison — un dessin qui doit couvrir une boîte dont le rapport
 *    de forme n'est pas le sien.
 *
 *    > Les cartes de vainqueur de `VainqueursCircuit` gardent leur `slice` et
 *    > n'ont rien à changer : elles sont presque carrées (166 × 230), le
 *    > recadrage y mord de quelques pixels. **Ce n'est pas la même boîte, donc
 *    > ce n'est pas la même réponse.**
 * 3. **Un pays absent n'est pas une panne**, c'est la règle du projet depuis la
 *    version `0.15.0` : le composant ne rend **rien**, et la ligne garde son
 *    blanc. Jamais une couleur de repli.
 *
 * ## Le lavis, et pourquoi il ne passe par aucun voile
 *
 * Le drapeau est posé à très faible opacité sous du texte foncé, comme les
 * cartes de vainqueur de `VainqueursCircuit`. Le voile calculé de
 * `DrapeauxGP.jsx` ne s'applique pas : il existe pour du texte **blanc** sur un
 * drapeau à pleine intensité, et c'est ici l'opacité elle-même qui garantit le
 * contraste, en amont.
 *
 * **Mesuré sur les seize drapeaux, couleur par couleur, à 8 % sur blanc.** Le
 * pire substrat est le noir — la bande allemande, le champ de l'Union Jack —
 * qui compose `#EBEBEB` ; l'encre `texte` y vaut **14,60:1**, l'encre
 * `secondaire` **8,86:1** et le bordeaux `primaire` **9,13:1**. Le bleu marine
 * australien, deuxième pire, ne descend pas plus bas.
 *
 * > **Le Japon n'a pas déplacé ce plancher, et c'est mesuré, pas supposé.** Le
 * > drapeau n'a que deux couleurs — le blanc, et le `#D80027` du disque, qui
 * > compose `#FCEBEE` à 8 %. C'est **plus clair** que le `#EBEBEB` du noir
 * > allemand sur les trois encres à la fois, donc le pire substrat reste le
 * > pire substrat et aucune valeur ci-dessus ne bouge.
 *
 * > **`texte-doux` n'y tient PAS : 2,39:1.** C'est le défaut que le design
 * > system signale déjà deux fois (bandeau de saison, libellé des favoris), et
 * > une rangée de classement est exactement « une phrase qu'on vient lire ».
 * > Aucun texte de ces lignes ne prend donc le gris — l'écurie et le prénom
 * > passent au marron `secondaire`.
 */
const DRAPEAUX = { AR, AU, BR, CA, DE, ES, FI, FR, GB, IT, JP, MC, MX, NL, NZ, TH };

/** Ce code ISO a-t-il un dessin ? `Object.hasOwn` et non `in` : `"toString" in
 *  DRAPEAUX` vaut vrai, et une clé héritée d'`Object` rendrait un drapeau
 *  fantôme — le même garde-fou qu'`aUneLivree`. */
export function aUnDrapeauPays(code) {
  return Object.hasOwn(DRAPEAUX, String(code ?? ""));
}

/**
 * Le drapeau d'un pays, ou rien.
 *
 * `titre` reste **facultatif et par défaut absent** : sur un fond décoratif, un
 * `<title>` ferait annoncer « Royaume-Uni » par un lecteur d'écran au milieu
 * d'une ligne qui dit déjà le pays en toutes lettres. Le `aria-hidden` du
 * calque appelant fait le reste.
 */
export default function DrapeauPays({ code, className = "", titre }) {
  const Drapeau = DRAPEAUX[String(code ?? "")];
  if (!Drapeau) return null;

  return (
    <Drapeau
      className={className}
      preserveAspectRatio="none"
      title={titre}
      aria-hidden={titre ? undefined : "true"}
      focusable="false"
    />
  );
}
