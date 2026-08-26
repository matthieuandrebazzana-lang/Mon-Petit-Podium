import Voiture from "./Voiture.jsx";
import { FondDrapeau, drapeauDeNationalite } from "./DrapeauxGP.jsx";
import { nomSurLaVoiture } from "../lib/circuits.js";

/**
 * Les derniers vainqueurs d'un Grand Prix — une rangée qui défile à
 * l'horizontale.
 *
 * Chaque carte porte le millésime, la **voiture aux couleurs de l'écurie**
 * (`Voiture` en mode `ecurie`, avec le numéro et le nom du pilote peints
 * dessus), le nom complet à droite, et le drapeau de sa nationalité en fond très
 * discret.
 *
 * ## Le défilement est natif, jamais un carrousel
 *
 * `snap-x snap-mandatory` cale la rangée sur ses cartes : un doigt qui la
 * pousse la laisse sur une carte entière, jamais coupée en deux. C'est ce qui
 * distingue une rangée volontairement débordante d'un débordement accidentel, et
 * c'est déjà l'idiome des favoris du tableau des cotes et des aperçus de la page
 * publique (`design-system.md` §8). Le débordement de la dernière carte dit
 * qu'il y en a d'autres au-delà.
 *
 * **Aucun JavaScript ne touche à ce défilement.** L'inertie de Safari iOS est
 * meilleure que tout ce qu'un carrousel réimplémenterait, et la rangée n'est
 * nichée dans aucun accordéon — le geste ne peut pas partir au mauvais étage.
 *
 * **Les marges négatives font toucher les deux bords.** `-mx-4 px-4` : la rangée
 * déborde le rembourrage de l'écran, mais la première et la dernière carte
 * restent alignées sur le reste de la page. Sans cela, la rangée paraîtrait
 * s'arrêter avant le bord, ce qui se lit comme une liste finie.
 *
 * > ### `scroll-pl-4` — le rembourrage seul ne suffit PAS, et ça ne se voit
 * > qu'au rendu contre la feuille compilée
 * >
 * > Le `px-4` ci-dessus est **annulé par le calage lui-même**. Avec
 * > `scroll-padding: auto`, une carte `snap-start` s'aligne sur le bord du
 * > *scrollport*, c'est-à-dire la boîte de rembourrage — pas sur son contenu.
 * > Le navigateur pose donc `scrollLeft = 16` au premier calcul, et la première
 * > carte revient **coller le bord de l'écran**, seize pixels à gauche de tout
 * > le reste de la page. Mesuré : `li.left = 0` pour un `ul` dont le
 * > `padding-left` calculé vaut bien `16px`.
 * >
 * > `scroll-padding-left` déplace ce bord de référence, et les deux valeurs
 * > doivent rester égales. Un défaut de géométrie pure, invisible à la lecture
 * > du JSX comme à un rendu HTML sans CSS — la troisième fois que ce projet ne
 * > l'attrape qu'en regardant la page (CLAUDE.md §6).
 * >
 * > **Les deux rangées plus anciennes** — les favoris du tableau des cotes et
 * > les aperçus de la page publique — portent exactement le même `-mx-4 px-4`
 * > sans `scroll-pl-4`, donc très probablement le même décalage. Elles ne sont
 * > pas retouchées ici : ce sont deux écrans qui marchent, la correction leur
 * > demande le même rendu de vérification, et elle est notée dans
 * > `roadmap.md`.
 *
 * ## Le fond est un drapeau, à 9 %
 *
 * C'est une **texture**, pas une information : la nationalité est écrite en
 * toutes lettres sous le nom, et la carte se lit entièrement sans le fond. D'où
 * l'opacité très basse, et d'où le fait qu'une nationalité sans drapeau
 * (l'Australie — voir `DrapeauxSVG.jsx`) ne laisse aucun trou.
 *
 * **Le contraste tient, et c'est mesuré.** Le pire substrat est le bleu du
 * Royaume-Uni : `#012169` à 9 % sur blanc donne `#E8EBF1`, où `#1A1A1A` vaut
 * **14,9:1** et le marron `secondaire` **9,2:1**. Aucune des huit nationalités
 * ne descend sous ces valeurs — à 9 %, aucun drapeau ne déplace assez la
 * luminance pour approcher un seuil.
 *
 * > **Le fond ne passe donc PAS par le voile calculé de `DrapeauxGP.jsx`**, et
 * > c'est la seule différence avec le bloc de l'accueil et les cartes du
 * > calendrier. Là-bas le drapeau est peint à pleine intensité sous du texte
 * > blanc, et le voile est ce qui garantit les 3:1 ; ici c'est l'opacité de 9 %
 * > qui joue ce rôle, en amont, et un voile par-dessus n'assombrirait qu'un
 * > lavis déjà presque blanc. `apparence()` reste appelée pour une seule raison
 * > — que la nationalité et le pays hôte partagent exactement le même calcul, et
 * > qu'ajouter demain une carte à fond plein ne demande pas d'y revenir.
 *
 * ## Ce qui n'anime pas
 *
 * **Rien, encore.** Les cartes ne sont pas tapables — il n'y a rien derrière un
 * palmarès — donc pas de retour d'appui à donner ; elles entrent avec le bloc
 * qui les porte, sous le `.t-stagger-line` de l'écran. Un décalage carte par
 * carte aurait animé une rangée dont on ne voit que deux éléments et demi, donc
 * animé surtout du hors-champ. Aucun jeton de mouvement n'est ajouté.
 */

/** Largeur d'une carte. Écrite une fois : c'est elle qui décide de la portion de
 *  la troisième carte qu'on aperçoit, et donc de l'affordance du défilement. */
const LARGEUR_CARTE = 176;

/** Hauteur de la voiture, en classe utilitaire et non en style : `Voiture`
 *  n'accepte qu'un `className`, et c'est délibéré de sa part — un style en ligne
 *  l'emporterait sur l'`aspectRatio` que certains de ses appelants posent.
 *
 *  La planche donne 141,11 × 288,09, soit un rapport de 0,49 : à 112px de haut
 *  la voiture fait 55px de large, ce qui laisse la moitié de la carte au nom. */
const HAUTEUR_VOITURE = "h-[112px]";

/** Opacité du drapeau en fond. Voir la mesure de contraste en tête de fichier. */
const OPACITE_DRAPEAU = 0.09;

function Carte({ vainqueur }) {
  const drapeau = drapeauDeNationalite(vainqueur.nationalite);

  // Le premier mot est le prénom, le reste le nom — la même dérivation que
  // `nomSurLaVoiture`, qui prend l'autre bout. Écrire les deux champs dans la
  // table aurait répété ce que `pilote` dit déjà.
  const mots = vainqueur.pilote.trim().split(/\s+/);
  const prenom = mots.length > 1 ? mots.slice(0, -1).join(" ") : "";
  const nom = mots[mots.length - 1];

  return (
    <li
      className="snap-start shrink-0"
      style={{ width: `${LARGEUR_CARTE}px` }}
    >
      <article className="rounded-carte bg-surface shadow-carte relative overflow-hidden">
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

          <div className="mt-1.5 flex items-center gap-2.5">
            {/* `titre` remplace l'étiquette générique de `Voiture` : un lecteur
                d'écran doit entendre de qui est cette voiture, pas « Voiture de
                VERSTAPPEN » en capitales d'aileron. */}
            <Voiture
              mode="ecurie"
              ecurie={vainqueur.ecurie}
              numero={vainqueur.numero}
              nom={nomSurLaVoiture(vainqueur.pilote)}
              titre={`Voiture de ${vainqueur.pilote}`}
              className={`w-auto shrink-0 ${HAUTEUR_VOITURE}`}
            />

            <div className="min-w-0 flex-1">
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
        </div>
      </article>
    </li>
  );
}

export default function VainqueursCircuit({ vainqueurs }) {
  if (!vainqueurs?.length) return null;

  return (
    <ul className="-mx-4 flex snap-x snap-mandatory scroll-pl-4 gap-2.5 overflow-x-auto px-4 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {vainqueurs.map((vainqueur) => (
        <Carte
          key={`${vainqueur.annee}-${vainqueur.pilote}`}
          vainqueur={vainqueur}
        />
      ))}
    </ul>
  );
}
