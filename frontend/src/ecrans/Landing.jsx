import { Link, useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import Bouton from "../composants/Bouton.jsx";
import { BandeauGreedF1 } from "../composants/LogoGreedF1.jsx";
import { APP_VERSION } from "../config.js";

/**
 * Maquette 01 — page d'accueil publique.
 *
 * Le vocabulaire de la maquette est corrigé : elle écrit « ligue », que la
 * section 1 du CLAUDE.md interdit dans toute l'interface. On dit championnat.
 *
 * **L'en-tête rouge de la maquette a disparu au profit du logo.** Il portait
 * une pastille de drapeau, le nom de l'application en petites capitales, un
 * titre et un sous-titre — soit quatre éléments pour dire ce que le bandeau du
 * logo dit d'un coup d'œil. Le nom vit maintenant dans le dessin, pas dans une
 * ligne de texte au-dessus d'un titre.
 *
 * **L'icône carrée et la rangée d'aperçus ont été retirées en version
 * `0.36.0`.** L'icône redisait ce que le bandeau dit déjà, juste au-dessus de
 * lui ; les aperçus étaient des emplacements réservés, et cinq silhouettes de
 * téléphone qui ne montrent aucune interface occupaient le tiers de l'écran
 * sans rien apprendre au visiteur. `IconeGreedF1` et `ApercusApp` restent en
 * place et simplement non montés, comme `Onglets.jsx` depuis la version
 * `0.12.0` : le jour où les vraies captures existent, il n'y a qu'à remonter le
 * composant.
 *
 * L'ordre des blocs suit celui de la lecture : qui c'est (le bandeau), ce que
 * ça fait (le titre et son sous-texte), et comment entrer (les deux boutons).
 * Le groupe est **centré verticalement** plutôt que poussé vers le bas par un
 * ressort : sans les aperçus, un `flex-1` entre le sous-texte et les boutons
 * rouvrirait exactement le vide qu'on vient de refermer.
 *
 * **Le bloc « 4 points » sous les boutons répond à l'exigence Google OAuth**
 * de décrire ce que fait l'app avant la connexion. Il porte le rang 5 du
 * stagger, un seul rang pour les quatre lignes : l'écran n'est vu qu'une fois
 * avant connexion, et /animate juge qu'un rang par puce (rangs 5 à 8)
 * retarderait la lecture sans rien communiquer de plus qu'une apparition
 * groupée. Le repère devant chaque ligne reprend le point de
 * `BandeauPrevisualisation` (`bg-primaire size-1.5 rounded-full`) — aucune
 * nouvelle couleur, aucune icône.
 */
const POINTS_APP = [
  "Pronostics jugés sur les cotes réelles des bookmakers",
  "Championnats privés à créer et partager entre amis",
  "Classement mis à jour en temps réel après chaque course",
  "Voiture personnalisable aux couleurs de ton écurie",
];

export default function Landing() {
  const naviguer = useNavigate();

  return (
    <Ecran direction="arriere">
      {/* Le conteneur flex vit **à l'intérieur** d'`Ecran`, et jamais sur un
          `Bloc` : `.t-stagger-line` pose `display: block` hors de toute couche
          Tailwind, donc `flex`, `gap` et `justify-*` posés sur un `Bloc` sont
          inertes. C'est le piège documenté en version `0.21.1`, et il ne se voit
          pas à la lecture du JSX. */}
      <div className="flex flex-1 flex-col justify-center gap-3">
        <Bloc rang={1}>
          {/* Le bandeau garde les coins arrondis du dessin : il occupe toute
              la largeur de la colonne de contenu, jamais celle de l'écran,
              sinon l'arrondi viendrait mourir sur les deux bords. */}
          <BandeauGreedF1 className="w-full" />
        </Bloc>

        <Bloc rang={2} className="px-1 text-center">
          <h1 className="text-titre-lg text-texte">
            Pronostique chaque Grand Prix entre amis.
          </h1>
        </Bloc>

        <Bloc rang={3}>
          <p className="text-corps text-secondaire px-1 text-center font-medium">
            Mise sur chaque GP. Grimpe dans le classement devant tes amis.
          </p>
        </Bloc>

        <Bloc rang={4} className="pt-2">
          <div className="flex flex-col gap-2.5">
            <Bouton
              variante="principal"
              className="text-[17px]"
              onClick={() => naviguer("/inscription")}
            >
              Créer un compte
            </Bouton>
            <Bouton
              variante="secondaire"
              className="text-[17px]"
              onClick={() => naviguer("/connexion")}
            >
              J'ai déjà un compte
            </Bouton>
          </div>
        </Bloc>

        <Bloc rang={5} className="pt-3">
          <ul className="flex flex-col gap-2.5">
            {POINTS_APP.map((point) => (
              <li key={point} className="flex items-start gap-2.5 px-1">
                <span
                  aria-hidden="true"
                  className="bg-primaire mt-[7px] size-1.5 shrink-0 rounded-full"
                />
                <span className="text-corps-sm text-secondaire">{point}</span>
              </li>
            ))}
          </ul>
        </Bloc>
      </div>

      <footer className="flex flex-col items-center gap-1.5 pt-4 text-center">
        <Link to="/privacy" className="text-texte-doux text-[11px] underline">
          Politique de confidentialité
        </Link>
        <span className="text-texte-doux text-[11px]">
          Greed F1 · v{APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
