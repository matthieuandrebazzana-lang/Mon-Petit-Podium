import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import Bouton from "../composants/Bouton.jsx";
import { BandeauGreedF1, IconeGreedF1 } from "../composants/LogoGreedF1.jsx";
import ApercusApp from "../composants/ApercusApp.jsx";
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
 * L'ordre des blocs suit celui de la lecture : qui c'est (l'icône et le
 * bandeau), ce que ça fait (le titre), à quoi ça ressemble (les aperçus), et
 * comment entrer (les deux boutons).
 */
export default function Landing() {
  const naviguer = useNavigate();

  return (
    <Ecran direction="arriere">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={1}>
          {/* Le conteneur flex vit **à l'intérieur** du bloc, jamais sur le bloc
              lui-même : `.t-stagger-line` pose `display: block` hors de toute
              couche Tailwind, donc `flex` et `gap` posés sur un `Bloc` sont
              inertes. C'est le piège documenté en version `0.21.1`, et il ne se
              voit pas à la lecture du JSX — ici il laissait l'icône calée à
              gauche au lieu d'être centrée. */}
          <div className="flex flex-col items-center gap-2.5 pt-2">
            <IconeGreedF1 className="size-14" />
            {/* Le bandeau garde les coins arrondis du dessin : il occupe toute
                la largeur de la colonne de contenu, jamais celle de l'écran,
                sinon l'arrondi viendrait mourir sur les deux bords. */}
            <BandeauGreedF1 className="w-full" />
          </div>
        </Bloc>

        <Bloc rang={2} className="px-1 text-center">
          <h1 className="text-titre-lg text-texte">
            Pronostique chaque Grand Prix
          </h1>
        </Bloc>

        <Bloc rang={3}>
          <p className="text-corps text-secondaire mb-2.5 px-1 text-center font-medium">
            Les cotes réelles, le classement de tes amis.
          </p>
          <ApercusApp />
        </Bloc>

        <div className="min-h-2 flex-1" />

        <Bloc rang={4}>
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
      </div>

      <footer className="pt-4 text-center">
        <span className="text-texte-doux text-[11px]">
          Greed F1 · v{APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
