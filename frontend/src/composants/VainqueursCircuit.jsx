import Voiture from "./Voiture.jsx";
import { drapeauDeNationalite } from "./DrapeauxGP.jsx";
import { nomSurLaVoiture } from "../lib/circuits.js";

/**
 * Les derniers vainqueurs d'un Grand Prix — une grille de deux colonnes.
 *
 * Chaque carte porte le millésime, la **voiture aux couleurs de l'écurie**
 * (`Voiture` en mode `ecurie`, avec le numéro et le nom du pilote peints
 * dessus), le prénom et le nom du vainqueur, puis son pays précédé de son
 * **drapeau emoji**.
 *
 * ## Une grille, et non plus une rangée qui défile (v`0.60.0`)
 *
 * La rangée `snap-x` montrait deux cartes et demie et cachait les autres
 * derrière un geste. **Ce n'était pas le bon procédé pour ce contenu** : un
 * palmarès se parcourt du regard, pas du doigt, et la question qu'on lui pose —
 * « qui gagne ici, ces dernières années ? » — se répond en voyant les
 * millésimes ENSEMBLE. Trois Verstappen d'affilée ne se remarquent pas quand il
 * faut pousser la rangée pour découvrir le troisième.
 *
 * Deux colonnes sur trois rangées, donc **six cartes visibles d'un coup**, sans
 * geste et sans hors-champ. La largeur d'une carte n'est plus écrite : elle est
 * celle de sa colonne, ce qui la fait suivre la largeur de l'écran au lieu de la
 * subir.
 *
 * ### La voiture passe AU-DESSUS du nom, et c'est la grille qui l'impose
 *
 * La carte de la rangée était large de 176 px et posait la voiture à gauche, le
 * nom à droite. Une colonne sur deux n'en fait plus que **166 px à 375** et
 * **139 px à 320** : le nom n'y disposait plus que de 77,5 px, puis 50 px, une
 * fois retirés le rembourrage, les 55 px de la voiture et leur gouttière.
 *
 * > **« Verstappen » demande 79 px**, mesuré contre la feuille compilée — le nom
 * > le plus fréquent de la table se serait donc tronqué en « Verstapp… » sur
 * > **tous** les iPhone, et pas seulement sur les étroits. Or c'est le nom de
 * > famille qui porte la reconnaissance : le tronquer vide la carte de ce
 * > qu'elle existe pour dire (/apple-design §16.6 — la chose la plus importante
 * > doit être la plus lisible ; §16.7 — un libellé principal coupé se lit comme
 * > de la négligence).
 *
 * Empilée, la ligne du nom dispose de **toute** la largeur utile de la carte —
 * 142 px à 375, 115 px à 320 — et les onze noms de la table y tiennent entiers.
 * La voiture est centrée : c'est une forme en portrait, et la laisser à gauche
 * d'un bloc vide l'aurait fait pencher. `truncate` reste sur les trois lignes,
 * en filet, pour un nom que la table n'a pas encore.
 *
 * > **Le nombre de cartes n'est PAS six partout, et la grille ne le corrige
 * > pas.** Las Vegas n'a couru que trois fois, le Qatar quatre : la dernière
 * > rangée reste incomplète, et c'est la seule chose honnête à afficher sous un
 * > titre qui dit « derniers vainqueurs » (`lib/circuits.js`). Une case vide de
 * > remplissage aurait été une donnée fausse, et une case étirée aurait fait
 * > croire à une édition plus importante que les autres.
 *
 * **Tout ce qui servait le défilement est parti avec lui** — `snap-x`,
 * `snap-mandatory`, `overflow-x-auto`, les marges négatives `-mx-4 px-4`, la
 * barre masquée, et le `scroll-pl-4` que la version `0.59.0` avait dû ajouter
 * pour que la première carte ne colle pas le bord de l'écran. C'est un défaut de
 * moins à tenir : la grille n'a pas de bord de calage, donc pas de bord de
 * calage à corriger. **Les deux rangées plus anciennes gardent le leur** — les
 * favoris des cotes et les aperçus de la page publique, notés dans `roadmap.md`
 * §3.8 ter — parce que ce sont deux écrans qui marchent, et que ce sont de
 * vraies rangées qui défilent.
 *
 * ## Le fond est blanc, partout, et le drapeau est passé dans le texte (v`0.76.0`)
 *
 * Les cartes portaient le drapeau de la nationalité en lavis à 18 %. **Six
 * cartes côte à côte en faisaient six fonds différents** : la carte 2025 d'un GP
 * gagné par Verstappen sortait rose et bleue quand sa voisine restait blanche,
 * et l'œil y lisait une mise en avant du millésime le plus récent — une
 * hiérarchie que la donnée ne porte pas. Un palmarès est une liste d'égaux ;
 * six éditions se comparent, et rien ne doit dire que l'une compte plus.
 *
 * **Le fond redevient donc `bg-surface` sur les six**, et la différence entre
 * les cartes se joue là où elle est vraie : le millésime, la livrée de la
 * voiture, le nom, le pays.
 *
 * > **La nationalité n'a rien perdu — elle a gagné son drapeau.** Ce qui était
 * > une texture derrière le texte est maintenant un **glyphe devant lui**
 * > (`emoji`, `DrapeauxGP.jsx`) : « 🇳🇱 Pays-Bas », sur la ligne du pays. Le
 * > drapeau se lit enfin au lieu de se deviner, et les deux nationalités que le
 * > lavis laissait sans rien — l'Australie et la Finlande, faute d'un dessin
 * > qu'on puisse poser sans l'approximer — sont désormais traitées comme les
 * > neuf autres.
 *
 * **Le contraste est mesuré sur le nouveau substrat, et il monte.** Le pire cas
 * n'est plus le noir de l'Allemagne composé à 18 % (`#D1D1D1`) mais le blanc
 * pur, qui est le substrat le plus clair possible :
 *
 * | Substrat | `texte` dessus | `secondaire` dessus |
 * |---|---|---|
 * | Lavis à 18 %, pire cas `#D1D1D1` | 11,40:1 | 6,91:1 |
 * | **`surface` `#FFFFFF`** | **17,40:1** | **10,56:1** |
 *
 * Les trois lignes de texte gardent donc leurs encres, et la carte n'a plus de
 * pire cas à surveiller : c'est un substrat unique, pas seize.
 *
 * > **`texte-doux` reste banni de cette carte** — 2,85:1 sur le blanc, sous le
 * > plancher de 4,5:1. Le fond plus clair ne rouvre pas ce gris : c'est la
 * > couleur qui est trop faible, pas le substrat qui était trop sombre.
 *
 * **`FondDrapeau` et `apparence()` ne sont plus appelés d'ici.** Ils restent
 * entiers dans `DrapeauxGP.jsx`, où l'accueil et les cartes du calendrier
 * peignent toujours leurs drapeaux à pleine intensité sous du texte blanc, avec
 * le voile qui leur garantit les 3:1. `drapeauDeNationalite` reste la seule
 * porte d'entrée : elle rend maintenant le glyphe en plus du reste.
 *
 * ## Ce qui n'anime pas
 *
 * **Rien, toujours pas**, et le fond uniforme ne change pas cet arbitrage : ce
 * qui a disparu est une couleur, pas un geste. Les cartes ne sont pas tapables
 * — il n'y a rien derrière un palmarès — donc pas de retour d'appui à donner ;
 * elles entrent avec le bloc qui les porte, sous le `.t-stagger-line` de
 * l'écran. Un décalage carte par carte aurait animé six vignettes qui arrivent
 * déjà ensemble, et l'œil les lit comme un tableau, pas comme une file. Aucun
 * jeton de mouvement n'est ajouté.
 */

/** Hauteur de la voiture, en classe utilitaire et non en style : `Voiture`
 *  n'accepte qu'un `className`, et c'est délibéré de sa part — un style en ligne
 *  l'emporterait sur l'`aspectRatio` que certains de ses appelants posent.
 *
 *  La planche donne 141,11 × 288,09, soit un rapport de 0,49 : à 112px de haut
 *  la voiture fait 55px de large. Elle n'a plus à partager sa rangée avec le nom
 *  depuis la version `0.60.0` (voir l'en-tête), donc cette hauteur ne borne plus
 *  rien — elle reste celle qui donnait la bonne présence dans la carte. */
const HAUTEUR_VOITURE = "h-[112px]";

function Carte({ vainqueur }) {
  const drapeau = drapeauDeNationalite(vainqueur.nationalite);

  // Le premier mot est le prénom, le reste le nom — la même dérivation que
  // `nomSurLaVoiture`, qui prend l'autre bout. Écrire les deux champs dans la
  // table aurait répété ce que `pilote` dit déjà.
  const mots = vainqueur.pilote.trim().split(/\s+/);
  const prenom = mots.length > 1 ? mots.slice(0, -1).join(" ") : "";
  const nom = mots[mots.length - 1];

  return (
    <li>
      {/* `overflow-hidden` reste alors qu'il n'y a plus de lavis à rogner : il
          garantit que ce qui dépasserait d'une carte est coupé par son rayon et
          non par un angle droit. `relative` est parti avec le lavis — plus rien
          ici n'est positionné en absolu. */}
      <article className="rounded-carte bg-surface shadow-carte h-full overflow-hidden">
        <div className="flex flex-col p-3">
          <p className="text-label-sm text-secondaire">{vainqueur.annee}</p>

          {/* `titre` remplace l'étiquette générique de `Voiture` : un lecteur
              d'écran doit entendre de qui est cette voiture, pas « Voiture de
              VERSTAPPEN » en capitales d'aileron. */}
          <Voiture
            mode="ecurie"
            ecurie={vainqueur.ecurie}
            numero={vainqueur.numero}
            nom={nomSurLaVoiture(vainqueur.pilote)}
            titre={`Voiture de ${vainqueur.pilote}`}
            className={`mt-2 w-auto self-center ${HAUTEUR_VOITURE}`}
          />

          <div className="mt-2.5 min-w-0">
            {prenom && (
              <p className="text-secondaire truncate text-[12px]">{prenom}</p>
            )}
            {/* Le nom de famille porte la reconnaissance : il est plus gros et
                plus gras que le prénom, et la hiérarchie passe par la taille
                et la graisse plutôt que par une couleur de plus. */}
            <p className="text-texte truncate text-[15px] leading-tight font-medium">
              {nom}
            </p>
            {drapeau && (
              /* Le glyphe et le nom sur une rangée plutôt que dans un même
                 texte : `truncate` ne doit ronger que le nom du pays. Écrits à
                 la suite, « 🇬🇧 Royaume-Uni » se serait coupé sur le drapeau
                 lui-même, qui est la moitié de l'information. `shrink-0` le met
                 hors d'atteinte, et il est peint deux points plus gros que le
                 texte : un emoji rendu à 11 px n'est plus reconnaissable sur un
                 écran d'iPhone.

                 **Mesuré contre la feuille compilée**, et aucun des onze pays
                 ne se tronque : le glyphe occupe 16 px, la gouttière 4, ce qui
                 laisse 122 px au nom à 375 et **94,5 px à 320**. Le plus long,
                 « Royaume-Uni », en demande 67. */
              <p className="text-secondaire mt-1.5 flex items-center gap-1 text-[11px]">
                <span aria-hidden="true" className="shrink-0 text-[13px]">
                  {drapeau.emoji}
                </span>
                <span className="truncate">{drapeau.libelle}</span>
              </p>
            )}
          </div>
        </div>
      </article>
    </li>
  );
}

export default function VainqueursCircuit({ vainqueurs }) {
  if (!vainqueurs?.length) return null;

  return (
    <ul className="grid grid-cols-2 gap-2.5">
      {vainqueurs.map((vainqueur) => (
        <Carte
          key={`${vainqueur.annee}-${vainqueur.pilote}`}
          vainqueur={vainqueur}
        />
      ))}
    </ul>
  );
}
