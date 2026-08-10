/**
 * Pastille d'initiale, reprise des maquettes 04 et 07.
 *
 * Les couleurs sont tirées de la palette de la section 5 — aucune teinte
 * nouvelle n'entre par cette porte. Le choix est déterministe : la même
 * personne garde la même couleur d'un écran à l'autre et d'une session à
 * l'autre, sinon la liste des membres changerait de couleurs à chaque
 * rafraîchissement, ce qui empêche de reconnaître quelqu'un du coin de l'œil.
 *
 * Cette pastille est provisoire : l'étape 8 la remplacera par la voiture
 * personnalisée de chaque membre.
 */

const COULEURS = ["bg-primaire", "bg-accent", "bg-secondaire", "bg-primaire-fonce"];

/** Somme des codes de caractères : suffisant pour répartir, et stable. */
function couleurPour(graine) {
  let total = 0;
  for (let i = 0; i < graine.length; i += 1) total += graine.charCodeAt(i);
  return COULEURS[total % COULEURS.length];
}

export default function Pastille({ nom = "", graine, taille = "md" }) {
  const initiale = nom.trim().charAt(0).toUpperCase() || "?";
  const dimensions =
    taille === "lg"
      ? "size-[42px] text-[16px]"
      : taille === "sm"
        ? "size-9 text-corps-sm"
        : "size-9 text-corps-sm";

  return (
    <span
      aria-hidden="true"
      className={`${dimensions} ${couleurPour(graine || nom)} flex shrink-0 items-center justify-center rounded-full font-medium text-white`}
    >
      {initiale}
    </span>
  );
}
