/**
 * Aperçus de l'application — la rangée de mockups de la page d'accueil publique.
 *
 * **Ce sont des emplacements réservés, et ils ne prétendent pas être autre
 * chose.** Les vraies captures d'écran arriveront plus tard : d'ici là, chaque
 * carte est une silhouette de téléphone qui **nomme l'écran qu'elle montrera**,
 * jamais une fausse interface reconstituée en `<div>`. C'est la règle que le
 * projet tient depuis l'étape 9 — une attente est une silhouette, pas un faux
 * contenu — et c'est aussi ce qui évite le pire défaut d'une landing : un écran
 * produit inventé, que le visiteur ne retrouvera jamais dans l'application.
 *
 * **Le passage aux vraies captures est une prop, pas une réécriture.** Poser
 * `image` sur une entrée d'`APERCUS` remplace la silhouette par la capture, à
 * la même place et à la même taille. Rien d'autre ne bouge.
 *
 * La rangée défile à l'horizontale, calée sur les cartes (`snap-x`), comme la
 * rangée « Mes favoris » du tableau des cotes (version `0.26.0`) et les livrées
 * d'écurie du profil (`0.33.0`). Le débordement volontaire de la dernière carte
 * dit qu'il y en a d'autres au-delà — c'est le « wayfinding » d'/apple-design
 * §16, et c'est ce qu'une grille de cinq cartes ne dirait pas.
 */

/* Le ratio d'un iPhone (390 × 844) et la hauteur de la rangée. La largeur s'en
   déduit : la carte doit avoir la forme d'un téléphone, pas celle qu'un
   arrondi de pixels lui donnerait. `HAUTEUR` est partagée avec la silhouette
   de chargement pour que l'écran ne sursaute pas à l'arrivée des captures. */
export const HAUTEUR_APERCU = 240;
const RATIO = "390 / 844";

const APERCUS = [
  { cle: "accueil", titre: "Le prochain Grand Prix" },
  { cle: "cotes", titre: "Le tableau des cotes" },
  { cle: "pronos", titre: "Tes pronostics" },
  { cle: "classement", titre: "Le classement" },
  { cle: "piste", titre: "La vue piste" },
];

/**
 * Une carte. Sans `image`, elle rend la silhouette et son libellé.
 *
 * Le dégradé va du charbon `texte` au bordeaux `primaire`, les deux couleurs du
 * design system. Le libellé est blanc : il tient **10,9:1 au pire**, c'est-à-dire
 * sur l'extrémité bordeaux, et 17,4:1 sur l'autre. Un gris clair au départ du
 * dégradé aurait été plus proche du mot « gris » mais y aurait posé du blanc à
 * 2,5:1, sous le plancher AA.
 */
function CarteApercu({ titre, image }) {
  return (
    <li className="snap-start shrink-0">
      <div
        className="rounded-bloc shadow-aplat relative overflow-hidden"
        style={{ height: HAUTEUR_APERCU, aspectRatio: RATIO }}
      >
        {image ? (
          <img
            src={image}
            alt={`Aperçu : ${titre}`}
            className="size-full object-cover"
          />
        ) : (
          <>
            <div
              className="absolute inset-0"
              style={{
                backgroundImage:
                  "linear-gradient(155deg, var(--color-texte), var(--color-primaire))",
              }}
            />
            {/* Le galbe de lumière des aplats de couleur (version `0.13.0`).
                Décoratif : rien à annoncer d'un effet de profondeur. */}
            <div
              className="lueur-haute pointer-events-none absolute inset-0"
              aria-hidden="true"
            />
            <p className="text-label absolute inset-x-3 bottom-4 text-center text-white uppercase">
              {titre}
            </p>
          </>
        )}
      </div>
    </li>
  );
}

export default function ApercusApp() {
  return (
    <ul className="-mx-4 flex snap-x snap-mandatory gap-2.5 overflow-x-auto px-4 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {APERCUS.map((apercu) => (
        <CarteApercu key={apercu.cle} {...apercu} />
      ))}
    </ul>
  );
}
