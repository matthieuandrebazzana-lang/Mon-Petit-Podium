import { useId } from "react";
import { IconeChevronAccordeon, IconeCoche } from "./Icones.jsx";
import SkinEcurie, { SKINS_DISPONIBLES } from "./SkinsEcuries.jsx";

/**
 * Choix d'un skin d'écurie (maquette 14, refonte de la version `0.40.0`).
 *
 * **Un accordéon et non un second contrôle segmenté.** L'écran opposait jusqu'ici
 * « Ma livrée » et « Livrée écurie » dans une bascule : les deux moitiés
 * s'excluaient, et choisir une écurie faisait disparaître les sélecteurs de
 * couleur sous le doigt. Le skin est désormais **une ligne de plus**, au même
 * rang que « Coque » et « Ailerons » et rendue exactement comme elles — même
 * rangée, même chevron, même transition (*accordion expand*, transitions-dev
 * 21, déjà installée). Le joueur garde la voiture sous les yeux et voit le
 * résultat de son choix au moment où il le fait.
 *
 * **La première case rend les couleurs, elle ne les efface pas.** Sans elle, un
 * membre qui a essayé un skin n'aurait plus aucun moyen de revenir à sa livrée :
 * c'est le pendant du drapeau `retirer_numero` de l'étape 8, où `null` seul
 * aurait été indiscernable d'un champ non transmis. Elle montre les deux
 * couleurs du membre, ce qui dit ce vers quoi on revient plutôt que « Aucun ».
 *
 * **Les vignettes sont les pastilles carrées de `assets/matti.svg`**, pas les
 * voitures. Elles ne portent ni numéro ni pseudo — voir `SkinsEcuries.jsx` — et
 * ne servent qu'ici : la voiture réellement dessinée reste celle de
 * `VoituresEcuries.jsx`.
 *
 * La grille tient en trois rangées de quatre et **ne défile pas dans son
 * propre cadre** : un conteneur scrollable niché dans un accordéon lui-même
 * dans une page qui défile est exactement ce qu'`/apple-design` proscrit — le
 * geste part au mauvais étage une fois sur deux. C'est la page qui défile.
 */
export default function SelecteurSkin({
  valeur,
  couleur1,
  couleur2,
  ouvert,
  onOuvrir,
  onChange,
}) {
  const id = useId();
  const choisi = SKINS_DISPONIBLES.find((skin) => skin.slug === valeur) ?? null;

  return (
    <div className="t-acc" data-open={ouvert ? "true" : "false"}>
      <button
        type="button"
        onClick={onOuvrir}
        aria-expanded={ouvert}
        aria-controls={id}
        className="pressable min-h-tactile flex w-full items-center justify-between gap-3 py-1.5"
      >
        <span className="text-corps-sm text-texte-doux">Skin</span>

        <span className="flex items-center gap-2.5">
          <span className="text-corps-sm text-texte font-medium">
            {choisi ? choisi.nom : "Ma livrée"}
          </span>
          {choisi ? (
            <SkinEcurie
              slug={choisi.slug}
              className="rounded-champ size-[26px] shrink-0"
            />
          ) : (
            <ApercuCouleurs couleur1={couleur1} couleur2={couleur2} />
          )}
          <IconeChevronAccordeon className="t-acc-chevron text-texte-doux size-4 shrink-0" />
        </span>
      </button>

      <div id={id} className="t-acc-panel">
        <div className="t-acc-panel-inner">
          <div className="grid grid-cols-4 gap-2 pt-2.5 pb-1">
            <Case
              nom="Ma livrée"
              choisie={!choisi}
              onChoisir={() => onChange(null)}
              vignette={
                <ApercuCouleurs
                  couleur1={couleur1}
                  couleur2={couleur2}
                  className="size-full"
                />
              }
            />

            {SKINS_DISPONIBLES.map((skin) => (
              <Case
                key={skin.slug}
                nom={skin.nom}
                choisie={choisi?.slug === skin.slug}
                onChoisir={() => onChange(skin.slug)}
                vignette={<SkinEcurie slug={skin.slug} className="size-full" />}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

/** Les deux couleurs du membre, en diagonale : la case « pas de skin ». */
function ApercuCouleurs({ couleur1, couleur2, className = "" }) {
  return (
    <span
      aria-hidden="true"
      className={`rounded-champ block size-[26px] shrink-0 overflow-hidden ${className}`}
      style={{
        background: `linear-gradient(135deg, ${couleur1} 0%, ${couleur1} 50%, ${couleur2} 50%, ${couleur2} 100%)`,
      }}
    />
  );
}

/**
 * Une case de la grille. La coche reprend l'aplat bordeaux du design system
 * plutôt qu'un filet : la section 5 proscrit les traits fins, et c'est déjà la
 * marque de la sélection partout ailleurs dans l'application.
 */
function Case({ nom, choisie, onChoisir, vignette }) {
  return (
    <button
      type="button"
      aria-pressed={choisie}
      aria-label={nom}
      onClick={onChoisir}
      className={`pressable rounded-widget relative flex flex-col items-center gap-1 p-1.5 ${
        choisie ? "bg-primaire" : "bg-fond"
      }`}
    >
      <span className="rounded-champ block w-full overflow-hidden">
        {vignette}
      </span>

      {choisie && (
        <span
          aria-hidden="true"
          className="t-coche absolute top-1 right-1 flex size-4 items-center justify-center rounded-full bg-white"
        >
          <IconeCoche className="text-primaire size-2.5 [stroke-width:3]" />
        </span>
      )}

      <span
        className={`w-full truncate text-center text-[10px] font-medium ${
          choisie ? "text-white" : "text-texte-doux"
        }`}
      >
        {nom}
      </span>
    </button>
  );
}
