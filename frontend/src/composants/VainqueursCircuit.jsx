import Voiture from "./Voiture.jsx";
import { FondDrapeau, drapeauDeNationalite } from "./DrapeauxGP.jsx";
import { nomSurLaVoiture } from "../lib/circuits.js";

/**
 * Les derniers vainqueurs d'un Grand Prix — une grille de deux colonnes.
 *
 * Chaque carte porte le millésime, la **voiture aux couleurs de l'écurie**
 * (`Voiture` en mode `ecurie`, avec le numéro et le nom du pilote peints
 * dessus), le nom complet à droite, et le drapeau de sa nationalité en fond
 * discret.
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
 * ## Le fond est un drapeau, à 18 %
 *
 * C'est une **texture**, pas une information : la nationalité est écrite en
 * toutes lettres sous le nom, et la carte se lit entièrement sans le fond. D'où
 * le fait qu'une nationalité sans drapeau — l'Australie, la Finlande (voir
 * `DrapeauxGP.jsx`) — ne laisse aucun trou.
 *
 * **9 % ne se voyait pas** sur une carte devenue deux fois plus large qu'un
 * timbre. Doubler l'opacité rend le drapeau lisible comme fond ; **le contraste
 * tient largement**, et c'est mesuré sur les seize teintes que les onze
 * nationalités peignent. Le pire substrat est le noir de l'Allemagne :
 *
 * | Opacité | `#000000` composé | `#1A1A1A` dessus | `secondaire` dessus |
 * |---|---|---|---|
 * | `0,09` | `#E8E8E8` | 14,20:1 | 8,62:1 |
 * | **`0,18`** | **`#D1D1D1`** | **11,40:1** | **6,91:1** |
 * | `0,20` | `#CCCCCC` | 10,84:1 | 6,57:1 |
 *
 * Les deux valeurs demandées passent donc le plancher de 4,5:1 avec une marge
 * confortable : **le choix entre elles est esthétique, pas de lisibilité**, et
 * c'est la plus discrète des deux qui est retenue — un palmarès n'est pas ce
 * qu'on regarde en premier sur cet écran.
 *
 * > **Le fond ne passe donc PAS par le voile calculé de `DrapeauxGP.jsx`**, et
 * > c'est la seule différence avec le bloc de l'accueil et les cartes du
 * > calendrier. Là-bas le drapeau est peint à pleine intensité sous du texte
 * > blanc, et le voile est ce qui garantit les 3:1 ; ici c'est l'opacité qui
 * > joue ce rôle, en amont, et un voile par-dessus n'assombrirait qu'un lavis
 * > déjà très clair. `apparence()` reste appelée pour une seule raison — que la
 * > nationalité et le pays hôte partagent exactement le même calcul, et
 * > qu'ajouter demain une carte à fond plein ne demande pas d'y revenir.
 *
 * ## Ce qui n'anime pas
 *
 * **Rien, encore.** Les cartes ne sont pas tapables — il n'y a rien derrière un
 * palmarès — donc pas de retour d'appui à donner ; elles entrent avec le bloc
 * qui les porte, sous le `.t-stagger-line` de l'écran. Un décalage carte par
 * carte aurait animé six vignettes qui arrivent déjà ensemble, et l'œil les lit
 * comme un tableau, pas comme une file. Aucun jeton de mouvement n'est ajouté.
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

/** Opacité du drapeau en fond. Voir la mesure de contraste en tête de fichier. */
const OPACITE_DRAPEAU = 0.18;

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
      <article className="rounded-carte bg-surface shadow-carte relative h-full overflow-hidden">
        {/* Le lavis. `absolute inset-0` plutôt qu'un pseudo-élément, comme
            `lueur-haute` : un pseudo-élément obligerait chaque appelant à poser
            `relative` et `overflow-hidden` lui-même. Il porte le dégradé du
            drapeau, et `FondDrapeau` pose par-dessus le dessin quand il y en a
            un — c'est le même composant que les cartes de Grand Prix, jamais
            une seconde façon de peindre un drapeau. */}
        {drapeau?.fond && (
          <span
            aria-hidden="true"
            className="pointer-events-none absolute inset-0"
            style={{ background: drapeau.fond, opacity: OPACITE_DRAPEAU }}
          >
            <FondDrapeau apparence={drapeau} />
          </span>
        )}

        <div className="relative flex flex-col p-3">
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
              <p className="text-secondaire mt-1.5 truncate text-[11px]">
                {drapeau.libelle}
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
