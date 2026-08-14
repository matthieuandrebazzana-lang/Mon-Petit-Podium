import { useId } from "react";
import { IconeChevronAccordeon, IconeCoche } from "./Icones.jsx";
import { PALETTE, encreSur, nomDeLaCouleur } from "../lib/palette.js";

/**
 * Choix d'une des vingt couleurs de la palette (maquette 14).
 *
 * La maquette montre une rangée « Couleur 1 » suivie d'une pastille, sans dire
 * ce qui se passe à l'appui. C'est un **accordéon** qui déplie la grille des
 * vingt teintes sous la rangée, plutôt qu'une feuille modale : le joueur garde
 * la voiture sous les yeux pendant qu'il choisit, et voit donc le résultat de
 * son choix au moment où il le fait. C'est le même arbitrage qu'à l'étape 5
 * pour le sélecteur de pilote, et la même transition (*accordion expand*,
 * transitions-dev 21).
 *
 * La couleur déjà prise par l'autre sélecteur est **désactivée, pas cachée** :
 * la disparition d'une case ferait bouger toute la grille sous le doigt, et
 * l'utilisateur ne comprendrait pas pourquoi. La contrainte
 * `profils_couleurs_distinctes` dit la même chose en base.
 */
export default function SelecteurCouleur({
  libelle,
  valeur,
  interdite,
  ouvert,
  onOuvrir,
  onChange,
}) {
  const id = useId();

  return (
    <div className="t-acc" data-open={ouvert ? "true" : "false"}>
      <button
        type="button"
        onClick={onOuvrir}
        aria-expanded={ouvert}
        aria-controls={id}
        className="pressable min-h-tactile flex w-full items-center justify-between gap-3 py-1.5"
      >
        <span className="text-corps-sm text-texte-doux">{libelle}</span>

        <span className="flex items-center gap-2.5">
          <span className="text-corps-sm text-texte font-medium">
            {nomDeLaCouleur(valeur)}
          </span>
          <span
            aria-hidden="true"
            style={{ backgroundColor: valeur }}
            className="rounded-champ size-[26px] shrink-0"
          />
          <IconeChevronAccordeon className="t-acc-chevron text-texte-doux size-4 shrink-0" />
        </span>
      </button>

      <div id={id} className="t-acc-panel">
        <div className="t-acc-panel-inner">
          <div className="grid grid-cols-5 gap-2 pt-2.5 pb-1">
            {PALETTE.map((couleur) => {
              const choisie =
                couleur.hex.toUpperCase() === String(valeur ?? "").toUpperCase();
              const bloquee =
                couleur.hex.toUpperCase() === String(interdite ?? "").toUpperCase();

              return (
                <button
                  key={couleur.hex}
                  type="button"
                  disabled={bloquee}
                  aria-pressed={choisie}
                  aria-label={
                    bloquee
                      ? `${couleur.nom} — déjà utilisée par l'autre couleur`
                      : couleur.nom
                  }
                  onClick={() => onChange(couleur.hex)}
                  style={{ backgroundColor: couleur.hex }}
                  className={`rounded-champ pressable flex aspect-square items-center justify-center ${
                    bloquee ? "opacity-25" : ""
                  }`}
                >
                  {/* La coche prend l'encre qui contraste avec la case : sur le
                      blanc et le beige de la palette, une coche blanche ne se
                      verrait pas — et c'est la seule marque du choix courant. */}
                  {choisie && (
                    <IconeCoche
                      className="size-4 [stroke-width:3]"
                      style={{ color: encreSur(couleur.hex) }}
                    />
                  )}
                </button>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
