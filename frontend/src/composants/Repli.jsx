import { useEffect, useState } from "react";
import { dureeCss } from "../lib/secousse.js";

/**
 * Une région qui se replie **et quitte le DOM** quand elle cesse d'être
 * pertinente (transitions-dev 21, même mécanique que l'accordéon).
 *
 * **Pourquoi un composant plutôt qu'un `&&` dans l'écran.** Un `&&` retire les
 * enfants à l'image suivante : la carte perd sa hauteur d'un coup, et tout ce
 * qui la suit — l'avertissement de numéro, le bouton d'enregistrement — saute
 * sous le doigt. C'est le cas que le design system nomme « changement
 * brutal » : la seule raison d'animer ici, et elle suffit. Le repli emprunte
 * donc le `grid-template-rows: 0fr → 1fr` de l'accordéon, qui anime une hauteur
 * inconnue sans jamais la mesurer en JavaScript.
 *
 * **Le démontage est différé, pas supprimé.** Les enfants restent montés le
 * temps du repli, puis disparaissent vraiment : ni `opacity: 0`, ni `hidden`,
 * ni élément grisé — rien qui laisse un réglage inerte dans l'ordre de
 * tabulation ou dans ce que lit un lecteur d'écran.
 *
 * ### Un sélecteur distinct de `.t-acc`, et ce n'est pas un fork
 *
 * Les règles de l'accordéon s'écrivent `.t-acc[data-open="true"] .t-acc-panel`
 * — un combinateur de **descendance**. Un `.t-acc` ouvert posé autour de deux
 * `SelecteurCouleur`, qui sont eux-mêmes des `.t-acc`, ouvrirait donc leurs
 * grilles de couleurs en même temps que lui. D'où `.t-repli`, qui **reprend les
 * jetons `--acc-expand`, `--acc-collapse` et `--acc-ease` sans en créer un
 * seul** : c'est le vocabulaire du projet étendu, pas dupliqué.
 *
 * L'asymétrie des deux durées est celle de l'accordéon, et pour la même
 * raison : 240ms au dépli, là où le joueur découvre ce qui arrive, 170ms au
 * repli, qui n'est qu'une réponse du système à un choix déjà fait.
 */
export default function Repli({ visible, children }) {
  const [monte, setMonte] = useState(visible);
  // Séparé de `monte` : c'est ce qui permet de monter les enfants **fermés**,
  // puis de les ouvrir à l'image suivante. Monter et ouvrir dans le même rendu
  // ne produirait aucune transition — le navigateur n'aurait jamais peint
  // l'état de départ.
  const [ouvert, setOuvert] = useState(visible);

  useEffect(() => {
    if (visible) {
      setMonte(true);
      const image = requestAnimationFrame(() => setOuvert(true));
      return () => cancelAnimationFrame(image);
    }

    setOuvert(false);
    if (!monte) return undefined;

    // La durée est **lue dans la feuille compilée**, jamais recopiée ici : une
    // constante JavaScript et un jeton CSS divergent au premier ajustement, et
    // le symptôme serait discret — des enfants retirés une image trop tôt,
    // c'est-à-dire un repli qui se termine par un saut.
    const minuterie = setTimeout(
      () => setMonte(false),
      dureeCss("--acc-collapse", 170),
    );
    return () => clearTimeout(minuterie);
  }, [visible, monte]);

  if (!monte) return null;

  return (
    <div className="t-repli" data-open={ouvert ? "true" : "false"}>
      {/* Le rembourrage éventuel vit ICI, jamais sur la piste `.t-repli` :
          posé sur une rangée à `0fr`, il laisserait une bande résiduelle et le
          repli ne se fermerait jamais tout à fait. */}
      <div className="t-repli-inner">{children}</div>
    </div>
  );
}
