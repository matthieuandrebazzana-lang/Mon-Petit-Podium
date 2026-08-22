/**
 * Pastille d'identité d'un membre — sa photo, ou ses initiales.
 *
 * Les couleurs sont tirées de la palette de la section 5 — aucune teinte
 * nouvelle n'entre par cette porte. Le choix est déterministe : la même
 * personne garde la même couleur d'un écran à l'autre et d'une session à
 * l'autre, sinon la liste des membres changerait de couleurs à chaque
 * rafraîchissement, ce qui empêche de reconnaître quelqu'un du coin de l'œil.
 *
 * > ### Pourquoi la photo entre ICI et non dans un composant à côté
 * >
 * > « Comment représente-t-on un membre dans un rond ? » est **une** question,
 * > posée par l'accueil, le classement, les deux écrans de profil et le résumé
 * > d'un Grand Prix. Elle doit donc avoir **un** propriétaire (CLAUDE.md §6).
 * > Un `Avatar` posé à côté aurait laissé cinq appelants à convertir un par un,
 * > et celui qu'on aurait oublié serait resté aux initiales sans que rien ne le
 * > signale. Avec la photo ici, tout appelant qui transmet `photo` l'obtient, et
 * > tout appelant qui l'ignore garde exactement le comportement d'avant.
 *
 * **`photo` absente n'est pas un cas dégradé.** C'est l'état par défaut de tout
 * compte, et les initiales sur teinte dérivée du pseudo sont une réponse
 * complète : elles distinguent, elles sont stables, elles se lisent en 36px. La
 * photo est un enrichissement, jamais un prérequis.
 *
 * **La table des teintes est sortie d'ici** (version `0.52.0`) vers
 * `lib/couleurs.js` : la vue piste pose désormais la même question en SVG, où
 * il faut un `#rrggbb` et non une classe. Rien d'autre n'a bougé — c'est la
 * même répartition, au même endroit du cycle.
 */

import { encreSurAplat, teinteMembre } from "../lib/couleurs.js";
import { usePhoto } from "../lib/usePhoto.js";

const DIMENSIONS = {
  // 28px — la rangée d'un membre au résumé d'un Grand Prix, qui porte déjà un
  // rang, une voiture, un score et un chevron. La pastille y est un repère de
  // reconnaissance, pas le sujet : à 36px elle prendrait la place du pseudo.
  xs: "size-7 text-[12px]",
  sm: "size-9 text-corps-sm",
  md: "size-9 text-corps-sm",
  lg: "size-[42px] text-[16px]",
  // Ajoutée avec les photos : la pastille des deux écrans de profil devient le
  // sujet de son bloc et non plus une vignette à côté d'un nom. **56px et non
  // 48 :** sur « Mon profil » elle est tactile, et la règle iOS du CLAUDE.md
  // §3.5 impose 44 × 44 au minimum — 48px moins l'anneau de 2px n'en laisserait
  // que 44 tout juste, sans marge d'erreur pour un doigt.
  xl: "size-[56px] text-[21px]",
};

/**
 * @param {string} [couleur] livrée du membre (étape 7), en `#rrggbb`. Quand elle
 *   est fournie, la pastille prend la couleur de sa voiture : la même personne
 *   se reconnaît alors du même coup d'œil au classement et sur la vue piste.
 *   Sans elle, on retombe sur la teinte déterministe ci-dessus.
 * @param {string} [photo] URL publique de sa photo (migration
 *   `20260821180000`). Absente, ce sont les initiales — l'affichage d'origine.
 * @param {number} [taillePx] diamètre exact, en pixels, quand aucune taille de
 *   l'échelle ne convient. **Un seul appelant l'emploie, la vue piste**, et pour
 *   une raison qui lui est propre : la taille d'une voiture y est calculée à
 *   l'exécution, elle ne peut donc pas sortir d'une échelle fixe. Partout
 *   ailleurs, `taille` est la bonne porte — une échelle qu'on contourne à la
 *   première difficulté cesse d'être une échelle.
 */
export default function Pastille({
  nom = "",
  graine,
  taille = "md",
  couleur,
  photo,
  taillePx,
}) {
  const initiale = nom.trim().charAt(0).toUpperCase() || "?";
  const teinte = teinteMembre(graine || nom);
  // Le diamètre explicite l'emporte, et emporte alors AUSSI la taille de
  // caractère : une initiale de 14px dans un rond de 20 déborde.
  const dimensions = taillePx ? "" : (DIMENSIONS[taille] ?? DIMENSIONS.md);
  const mesures = taillePx
    ? {
        width: `${taillePx}px`,
        height: `${taillePx}px`,
        fontSize: `${Math.max(9, Math.round(taillePx * 0.44))}px`,
        lineHeight: 1,
      }
    : null;

  // **L'image se révèle une fois chargée, elle ne clignote pas.** L'URL arrive
  // avec les données, le pixel arrive plus tard : sans cet état, la photo
  // apparaîtrait d'un coup au milieu d'un écran déjà peint. Les initiales
  // tiennent la place jusque-là — elles ont la bonne taille et la bonne forme,
  // ce qui fait de l'arrivée un fondu et non un saut.
  //
  // `cassee` couvre le cas d'une URL en base dont l'objet a disparu du
  // stockage : la pastille redevient alors ce qu'elle est sans photo, plutôt
  // qu'un rond vide. Toute la mécanique — cache du navigateur compris — vit dans
  // `usePhoto`, partagée avec la photo d'un championnat.
  const { chargee, cassee, aLImage, auChargement, aLEchec } = usePhoto(photo);
  const affichable = Boolean(photo) && !cassee;

  // **L'encre de l'initiale est mesurée, jamais écrite en dur.** La pastille
  // portait `text-white` en toutes lettres : sur l'amber de la palette — une
  // teinte sur quatre — le blanc ne vaut que **2,22:1**, quand `#1A1A1A` y monte
  // à 7,86:1. Une initiale sur six y était donc illisible depuis toujours.
  //
  // **`encreSurAplat` et non `encreSur`**, et l'écart n'est pas cosmétique : le
  // second compare une luminance à 0,45, or l'amber vaut 0,424 — il passe donc
  // juste sous le seuil et rend du blanc. Le premier mesure le CONTRASTE et
  // garde le blanc tant qu'il tient 3:1. C'est la règle du design system §5,
  // « le contraste se mesure, il ne se choisit pas ».
  const encre = encreSurAplat(couleur ?? teinte.hex);

  return (
    <span
      aria-hidden="true"
      style={{
        ...(couleur ? { backgroundColor: couleur } : null),
        color: encre,
        ...mesures,
      }}
      className={`${dimensions} ${
        couleur || affichable ? "" : teinte.fond
      } relative flex shrink-0 items-center justify-center overflow-hidden rounded-full font-medium select-none ${
        affichable ? "bg-squelette" : ""
      }`}
    >
      {/* L'initiale reste sous la photo tant qu'elle n'est pas chargée, et
          disparaît une fois qu'elle l'est : la garder dessous coûterait un
          glyphe qui transparaîtrait au travers d'un PNG à fond transparent. */}
      {!chargee && <span>{initiale}</span>}

      {affichable && (
        <img
          src={photo}
          alt=""
          // `decoding="async"` évite que le décodage d'une image de deux
          // mégaoctets ne bloque la peinture d'une liste de douze membres.
          decoding="async"
          loading="lazy"
          draggable="false"
          ref={aLImage}
          onLoad={auChargement}
          onError={aLEchec}
          data-chargee={chargee ? "true" : "false"}
          className="t-photo absolute inset-0 h-full w-full object-cover"
        />
      )}
    </span>
  );
}
