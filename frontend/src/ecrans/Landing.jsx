import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import Bouton from "../composants/Bouton.jsx";
import { IconeDrapeau, IconeMembres, IconeVoiture } from "../composants/Icones.jsx";
import { APP_VERSION } from "../config.js";

/**
 * Maquette 01 — page d'accueil publique.
 *
 * Le vocabulaire de la maquette est corrigé : elle écrit « ligue », que la
 * section 1 du CLAUDE.md interdit dans toute l'interface. On dit championnat.
 */

const ATOUTS = [
  {
    Icone: IconeMembres,
    titre: "Championnats privés",
    detail: "Rejoins avec un code à 6 caractères",
  },
  {
    Icone: IconeVoiture,
    titre: "Ta voiture, ton style",
    detail: "Personnalise couleurs et numéro",
  },
];

export default function Landing() {
  const naviguer = useNavigate();

  return (
    <Ecran direction="arriere">
      <div className="flex flex-1 flex-col gap-3">
        <Bloc
          rang={1}
          className="rounded-bloc bg-primaire shadow-bloc px-6 pt-9 pb-8 text-center"
        >
          <div className="mx-auto mb-4.5 flex size-[68px] items-center justify-center rounded-[20px] bg-white/15">
            <IconeDrapeau className="size-8 text-white" />
          </div>
          <p className="text-label mb-3 text-white/70 uppercase [letter-spacing:2.5px]">
            Mon Petit Podium
          </p>
          <h1 className="text-titre-lg mb-3 text-white">
            Pronostique chaque Grand Prix
          </h1>
          <p className="text-corps leading-relaxed text-white/65">
            Crée ton championnat, invite tes amis, et grimpe au classement à
            chaque course.
          </p>
        </Bloc>

        <Bloc rang={2} className="rounded-bloc bg-surface shadow-bloc p-5">
          <div className="flex flex-col gap-4">
            {ATOUTS.map(({ Icone, titre, detail }) => (
              <div key={titre} className="flex items-center gap-3.5">
                <div className="bg-fond flex size-tactile shrink-0 items-center justify-center rounded-[13px]">
                  <Icone className="text-primaire size-5" />
                </div>
                <div>
                  <p className="text-corps text-texte font-medium">{titre}</p>
                  <p className="text-texte-doux mt-0.5 text-[12px]">{detail}</p>
                </div>
              </div>
            ))}
          </div>
        </Bloc>

        {/* L'espace disponible est absorbé ici pour que les deux boutons
            restent à portée de pouce sur les grands écrans, sans changer
            l'ordre des blocs de la maquette. */}
        <div className="min-h-3 flex-1" />

        <Bloc rang={3}>
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
          Mon Petit Podium · v{APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
