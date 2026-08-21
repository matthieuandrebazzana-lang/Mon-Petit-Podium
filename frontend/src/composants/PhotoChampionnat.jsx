import { usePhoto } from "../lib/usePhoto.js";

/**
 * La photo d'un championnat — carrée, arrondie, ou rien du tout.
 *
 * **Elle rend `null` quand il n'y a pas de photo, et c'est tout le composant.**
 * La demande est explicite sur ce point : sans `photo_url`, l'interface se
 * comporte *exactement* comme avant. Pas de cadre vide, pas d'image de
 * remplacement, pas de gouttière réservée — un emplacement vide sur une carte
 * annoncerait une donnée manquante là où il n'y a que l'absence d'un
 * enrichissement facultatif. Les appelants n'ont donc aucune condition à écrire :
 * ils posent le composant, il s'efface de lui-même.
 *
 * **Une seule question, un seul propriétaire** (CLAUDE.md §6). Les deux
 * emplacements — la carte de l'accueil et l'en-tête de l'écran du championnat —
 * ne diffèrent que par leur taille et leur rayon. Deux `<img>` écrits séparément
 * auraient divergé au premier ajustement : l'un aurait gardé son fondu, l'autre
 * son repli sur objet disparu.
 *
 * > ### Écart assumé sur le rayon, et il est signalé
 * >
 * > La demande prescrit `border-radius: 12px` sur la carte et `16px` dans
 * > l'en-tête. L'échelle des formes du design system ne connaît pas le 12 : elle
 * > va de 24 (bloc) à 14 (`rounded-champ`, « champs et petits éléments »), et
 * > « tout écran puise dans ces jetons, jamais dans des valeurs en dur ». La
 * > carte prend donc `rounded-champ`, à deux pixels de la valeur demandée ;
 * > l'en-tête prend `rounded-widget`, qui vaut exactement les 16 demandés.
 * > Écrire un `rounded-[12px]` aurait ouvert une sixième valeur de rayon dans un
 * > projet qui en compte cinq, pour un écart invisible à cette taille.
 */
export default function PhotoChampionnat({
  url,
  nom,
  taille,
  arrondi = "rounded-champ",
  className = "",
}) {
  // Une URL en base dont l'objet a disparu du stockage ne doit pas laisser un
  // carré gris sur la carte : le composant redevient alors ce qu'il est sans
  // photo, c'est-à-dire rien. Même repli, et même mécanique de chargement, que
  // la pastille d'un joueur — `usePhoto` les porte pour les deux.
  const { chargee, cassee, aLImage, auChargement, aLEchec } = usePhoto(url);

  if (!url || cassee) return null;

  return (
    // Le fond `squelette` tient la place pendant le chargement du pixel : sans
    // lui, le fondu partirait du fond de la carte — un aplat de couleur — et se
    // lirait comme une image qui s'éclaircit.
    <span
      aria-hidden="true"
      className={`bg-squelette relative block shrink-0 overflow-hidden select-none ${arrondi} ${className}`}
      style={{ width: `${taille}px`, height: `${taille}px` }}
    >
      <img
        src={url}
        // Décorative : le nom du championnat est écrit juste à côté, en toutes
        // lettres. Un `alt` qui le répéterait ferait entendre deux fois la même
        // chose à un lecteur d'écran.
        alt=""
        decoding="async"
        loading="lazy"
        draggable="false"
        title={nom || undefined}
        ref={aLImage}
        onLoad={auChargement}
        onError={aLEchec}
        data-chargee={chargee ? "true" : "false"}
        className="t-photo absolute inset-0 h-full w-full object-cover"
      />
    </span>
  );
}
