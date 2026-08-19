import { teinteLivree } from "./livrees.js";

/**
 * Palette des voitures — étape 8.
 *
 * Vingt couleurs, exactement celles arrêtées dans le chat principal. C'est un
 * choix fermé : les deux sélecteurs du profil ne proposent que ces vingt-là, et
 * le backend n'accepte de toute façon qu'un `#RRGGBB` valide.
 *
 * **Écart assumé par rapport à la section 5 du CLAUDE.md**, le même qu'à
 * l'étape 7 pour les livrées : la palette de l'app compte sept couleurs, vingt
 * teintes distinctes n'en sortiraient pas. Celles-ci ne sont pas des couleurs
 * d'interface — elles ne peignent **que les voitures**, jamais un fond, un
 * bouton ou un texte d'écran. Quatre d'entre elles reprennent d'ailleurs le
 * design system plutôt que d'inventer un ton de plus : bordeaux `#800111`
 * (primaire), marron `#543925` (secondaire), amber `#E8A020` (accent) et beige
 * `#F5F0EB` (fond).
 *
 * Les livrées attribuées par ordre d'inscription (`lib/livrees.js`, étape 7)
 * disparaissent avec ce module : elles n'avaient de raison d'être que tant que
 * rien ne permettait de choisir. Les trois helpers de couleur qu'elles
 * portaient (`encreSur`, `couleurLisible`, la luminance) vivent désormais ici.
 */

export const PALETTE = [
  { nom: "Rouge", hex: "#CC0000" },
  { nom: "Blanc", hex: "#FFFFFF" },
  { nom: "Noir", hex: "#000000" },
  { nom: "Gris", hex: "#8A8A8A" },
  { nom: "Argent", hex: "#C0C0C0" },
  { nom: "Bleu foncé", hex: "#003087" },
  { nom: "Bleu clair", hex: "#0090D4" },
  { nom: "Turquoise", hex: "#00A19C" },
  { nom: "Vert foncé", hex: "#005C43" },
  { nom: "Vert clair", hex: "#00D2BE" },
  { nom: "Orange", hex: "#FF8000" },
  { nom: "Jaune", hex: "#FFD700" },
  { nom: "Rose", hex: "#E8027B" },
  { nom: "Violet", hex: "#960064" },
  { nom: "Bordeaux", hex: "#800111" },
  { nom: "Marron", hex: "#543925" },
  { nom: "Amber", hex: "#E8A020" },
  { nom: "Beige", hex: "#F5F0EB" },
  { nom: "Or", hex: "#B8860B" },
  { nom: "Anthracite", hex: "#2D2D2D" },
];

/** Les défauts de la colonne, répétés ici pour que le rendu n'attende personne. */
export const COULEUR1_DEFAUT = "#800111";
export const COULEUR2_DEFAUT = "#FFFFFF";

/** Nom lisible d'une couleur de la palette, pour l'étiquette du sélecteur. */
export function nomDeLaCouleur(hex) {
  const propre = String(hex ?? "").toUpperCase();
  return PALETTE.find((couleur) => couleur.hex.toUpperCase() === propre)?.nom ?? "Personnalisée";
}

/**
 * Les deux couleurs d'un membre, quelle que soit la forme de la ligne reçue.
 *
 * Le classement, le profil et le cache d'une version antérieure ne portent pas
 * forcément les mêmes champs : une ligne sans couleur retombe sur les défauts
 * plutôt que de peindre une voiture en transparent.
 */
export function couleursDuMembre(ligne) {
  return {
    couleur1: ligne?.couleur1 || COULEUR1_DEFAUT,
    couleur2: ligne?.couleur2 || COULEUR2_DEFAUT,
  };
}

/**
 * Luminance relative (WCAG) d'une couleur `#rrggbb`.
 *
 * Exportée depuis la refonte visuelle : `lib/couleurs.js` en a besoin pour
 * choisir l'encre d'un aplat de bloc. Une seconde implémentation du même calcul
 * finirait par diverger de celle-ci, et deux textes de la même app ne seraient
 * plus jugés lisibles selon la même règle.
 */
export function luminance(hex) {
  const canal = (paire) => {
    const valeur = parseInt(paire, 16) / 255;
    return valeur <= 0.03928
      ? valeur / 12.92
      : ((valeur + 0.055) / 1.055) ** 2.4;
  };
  const propre = String(hex ?? "").replace("#", "");
  if (propre.length !== 6) return 0;
  return (
    0.2126 * canal(propre.slice(0, 2)) +
    0.7152 * canal(propre.slice(2, 4)) +
    0.0722 * canal(propre.slice(4, 6))
  );
}

/**
 * Encre lisible sur un aplat : le texte du design system ou le blanc.
 *
 * Un numéro de voiture blanc sur une livrée blanche serait invisible, et le
 * numéro est la seule chose qui identifie une voiture à cette taille. La
 * palette compte désormais du blanc, de l'argent, du beige et du jaune : le
 * cas n'est plus théorique.
 */
export function encreSur(fond) {
  return luminance(fond) > 0.45 ? "#1A1A1A" : "#FFFFFF";
}

/**
 * La livrée d'un membre, quelle que soit la forme de la ligne reçue.
 *
 * **C'est le seul endroit qui décide de ce que porte une voiture**, et tous les
 * écrans qui en affichent une y passent : le profil, le classement, la vue
 * piste, le tableau des résultats. Sans lui, chaque écran relirait `livree_mode`
 * à sa façon, et un membre pourrait apparaître en livrée Ferrari au classement
 * et aux couleurs de son choix sur la piste.
 *
 * Une ligne sans mode — cache d'une version antérieure, backend déployé avant la
 * migration, profil manquant — retombe sur `perso`, donc sur les couleurs, qui
 * ont elles-mêmes leurs défauts de colonne. Le repli n'est jamais une voiture
 * transparente.
 */
export function livreeDuMembre(ligne) {
  const { couleur1, couleur2 } = couleursDuMembre(ligne);
  const ecurie = ligne?.livree_ecurie ?? null;
  return {
    mode: ligne?.livree_mode === "ecurie" && ecurie ? "ecurie" : "perso",
    ecurie,
    couleur1,
    couleur2,
  };
}

/**
 * Celle des deux couleurs qui se voit sur une carte blanche.
 *
 * Elle porte la pastille du classement et le filet des lignes : c'est ce qui
 * permet de reconnaître la même personne du même coup d'œil au classement, sur
 * la piste et sur son profil. **Une livrée d'écurie rend donc la teinte de son
 * écurie**, pas les couleurs personnelles du membre, qui ne peignent alors plus
 * rien à l'écran.
 *
 * Cinq couleurs de la palette sont trop claires pour une pastille posée sur le
 * fond `surface` — blanc, argent, beige, jaune, vert clair. On prend alors la
 * seconde, qui diffère de la première par construction (contrainte
 * `profils_couleurs_distinctes`). Si les deux sont claires, la première reste :
 * mieux vaut une pastille pâle que pas de pastille du tout.
 */
export function couleurLisible(voiture) {
  const livree = livreeDuMembre(voiture);
  if (livree.mode === "ecurie") {
    const teinte = teinteLivree(livree.ecurie);
    if (teinte) return teinte;
  }

  const { couleur1, couleur2 } = livree;
  return luminance(couleur1) > 0.75 && luminance(couleur2) <= 0.75
    ? couleur2
    : couleur1;
}
