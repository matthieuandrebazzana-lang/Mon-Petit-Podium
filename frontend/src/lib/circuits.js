/**
 * Les douze circuits de la fin de saison 2026 — **la fiche de l'écran
 * « Détail GP », et rien d'autre.**
 *
 * ## Pourquoi une table de plus, à côté de `GP_2026`
 *
 * `calendrier2026.js` répond à « quand, et où ». Ce module répond à « à quoi
 * ressemble cette course » : la longueur du tracé, le nombre de tours, le
 * record du tour, les derniers vainqueurs. Ce sont deux questions, et la
 * première est lue par quatre écrans quand la seconde ne l'est que par un seul.
 * Les fondre aurait fait voyager quinze lignes d'histoire dans chaque carte du
 * calendrier, pour un écran qui ne les demande pas.
 *
 * **La clé est le `slug` de `slugCircuit`, la même que partout ailleurs.** Cinq
 * tables la partagent désormais — `GP_2026`, `TRACES`, `DRAPEAUX`, `IDENTITES`
 * et celle-ci — et c'est elle qui garantit qu'une fiche, un drapeau et un tracé
 * décrivent le même Grand Prix. Un contrôle le vérifie (voir le bloc en fin de
 * fichier).
 *
 * ## Ce que ces chiffres sont, et ce qu'ils ne sont pas
 *
 * > ### Écart signalé (CLAUDE.md §6) : rien ici n'est vérifié par le code
 * >
 * > Longueurs, nombres de tours, records et palmarès sont une **donnée de
 * > référence saisie à la main**, au même titre que la grille de
 * > `backend/app/calcul/pilotes.py` ou les onze écuries de `lib/ecuries.js`.
 * > Aucune route ne les sert, aucun test ne peut les démentir : ils se
 * > relisent sur les fiches officielles de la FIA, **une fois par saison**, en
 * > même temps que `GP_2026`.
 * >
 * > Une table périmée ne fait ici aucun dégât silencieux — un vainqueur
 * > manquant se voit tout de suite, contrairement à une moyenne fausse. C'est
 * > l'arbitrage déjà retenu pour le calendrier d'un championnat
 * > (`calendrier.md` §9).
 *
 * **Deux circuits demandent une lecture attentive.**
 *
 * - **Madrid n'a jamais couru.** `premier_gp` vaut 2026 et `record_tour` vaut
 *   `null` : il n'y a pas de record d'un tour que personne n'a bouclé, et
 *   `nombre_tours` est **prévisionnel** — c'est le premier entier qui porte la
 *   course au-dessus des 305 km réglementaires. L'écran affiche « — » là où la
 *   valeur manque, jamais un zéro.
 * - **`derniers_vainqueurs` liste le GRAND PRIX, pas le circuit.** Les cinq
 *   derniers vainqueurs du GP d'Espagne ont gagné à Barcelone, pas à Madrid ;
 *   ceux du GP de Malaisie datent de 2013–2017, la course ayant disparu du
 *   calendrier entre-temps. C'est le palmarès que l'on vient chercher, et le
 *   restreindre au tracé aurait laissé deux blocs vides. Le millésime de chaque
 *   carte le dit.
 *
 * **Les listes ne font pas toutes cinq entrées**, et on ne les complète pas :
 * Las Vegas n'a couru que trois fois, le Qatar quatre (2022 manque à l'appel).
 * Inventer une sixième ligne pour tenir un gabarit serait une donnée fausse ;
 * la rangée défile, elle n'a pas de longueur à respecter.
 *
 * ## Le pilote, sa voiture et son drapeau
 *
 * `ecurie` est un slug de `lib/livrees.js` — c'est lui qui donne la livrée
 * dessinée par `VoituresEcuries.jsx`. `nationalite` est une clé de
 * `NATIONALITES` (`DrapeauxGP.jsx`), qui donne le gentilé **et** le drapeau.
 * Aucune couleur, aucun nom d'écurie et aucun nom de pays n'est écrit ici : ce
 * module ne porte que des clés, et les trois tables qu'il référence restent
 * seules propriétaires de ce qu'elles décrivent.
 *
 * `numero` est celui que le pilote portait **cette année-là**, pas celui de sa
 * carrière : Verstappen court sous le 33 en 2021 et sous le 1 à partir de 2022,
 * Vettel sous le 1 en 2013. C'est un palmarès, il dit ce qui s'est passé.
 */

import { NATIONALITES } from "../composants/DrapeauxGP.jsx";
import { aUneLivree } from "../composants/VoituresEcuries.jsx";
import { GP_2026 } from "./calendrier2026.js";

export const CIRCUITS = {
  "pays-bas": {
    longueur_km: 4.259,
    nombre_tours: 72,
    distance_km: 306.587,
    premier_gp: 1952,
    record_tour: { temps: "1:11.097", pilote: "Lewis Hamilton", annee: 2021 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Oscar Piastri", numero: 81, ecurie: "mclaren", nationalite: "australienne" },
      { annee: 2024, pilote: "Lando Norris", numero: 4, ecurie: "mclaren", nationalite: "britannique" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2022, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Max Verstappen", numero: 33, ecurie: "red-bull", nationalite: "neerlandaise" },
    ],
  },

  italie: {
    longueur_km: 5.793,
    nombre_tours: 53,
    distance_km: 306.72,
    premier_gp: 1950,
    record_tour: { temps: "1:21.046", pilote: "Rubens Barrichello", annee: 2004 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2024, pilote: "Charles Leclerc", numero: 16, ecurie: "ferrari", nationalite: "monegasque" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2022, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Daniel Ricciardo", numero: 3, ecurie: "mclaren", nationalite: "australienne" },
    ],
  },

  // Madring, premier Grand Prix. Voir l'en-tête : le nombre de tours est
  // prévisionnel et le record n'existe pas.
  espagne: {
    longueur_km: 5.474,
    nombre_tours: 56,
    distance_km: 306.544,
    premier_gp: 2026,
    record_tour: null,
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Oscar Piastri", numero: 81, ecurie: "mclaren", nationalite: "australienne" },
      { annee: 2024, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2022, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Lewis Hamilton", numero: 44, ecurie: "mercedes", nationalite: "britannique" },
    ],
  },

  azerbaidjan: {
    longueur_km: 6.003,
    nombre_tours: 51,
    distance_km: 306.049,
    premier_gp: 2016,
    record_tour: { temps: "1:43.009", pilote: "Charles Leclerc", annee: 2019 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2024, pilote: "Oscar Piastri", numero: 81, ecurie: "mclaren", nationalite: "australienne" },
      { annee: 2023, pilote: "Sergio Pérez", numero: 11, ecurie: "red-bull", nationalite: "mexicaine" },
      { annee: 2022, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Sergio Pérez", numero: 11, ecurie: "red-bull", nationalite: "mexicaine" },
    ],
  },

  // Le Grand Prix a disparu du calendrier après 2017 : son palmarès s'arrête
  // là, et c'est ce que les millésimes disent.
  malaisie: {
    longueur_km: 5.543,
    nombre_tours: 56,
    distance_km: 310.408,
    premier_gp: 1999,
    record_tour: { temps: "1:34.080", pilote: "Sebastian Vettel", annee: 2017 },
    derniers_vainqueurs: [
      { annee: 2017, pilote: "Max Verstappen", numero: 33, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2016, pilote: "Daniel Ricciardo", numero: 3, ecurie: "red-bull", nationalite: "australienne" },
      { annee: 2015, pilote: "Sebastian Vettel", numero: 5, ecurie: "ferrari", nationalite: "allemande" },
      { annee: 2014, pilote: "Lewis Hamilton", numero: 44, ecurie: "mercedes", nationalite: "britannique" },
      { annee: 2013, pilote: "Sebastian Vettel", numero: 1, ecurie: "red-bull", nationalite: "allemande" },
    ],
  },

  // 2020 et 2021 n'ont pas eu lieu : le cinquième vainqueur remonte à 2019.
  singapour: {
    longueur_km: 4.94,
    nombre_tours: 62,
    distance_km: 306.143,
    premier_gp: 2008,
    record_tour: { temps: "1:34.486", pilote: "Daniel Ricciardo", annee: 2024 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "George Russell", numero: 63, ecurie: "mercedes", nationalite: "britannique" },
      { annee: 2024, pilote: "Lando Norris", numero: 4, ecurie: "mclaren", nationalite: "britannique" },
      { annee: 2023, pilote: "Carlos Sainz", numero: 55, ecurie: "ferrari", nationalite: "espagnole" },
      { annee: 2022, pilote: "Sergio Pérez", numero: 11, ecurie: "red-bull", nationalite: "mexicaine" },
      { annee: 2019, pilote: "Sebastian Vettel", numero: 5, ecurie: "ferrari", nationalite: "allemande" },
    ],
  },

  "etats-unis": {
    longueur_km: 5.513,
    nombre_tours: 56,
    distance_km: 308.405,
    premier_gp: 2012,
    record_tour: { temps: "1:36.169", pilote: "Charles Leclerc", annee: 2019 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2024, pilote: "Charles Leclerc", numero: 16, ecurie: "ferrari", nationalite: "monegasque" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2022, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Max Verstappen", numero: 33, ecurie: "red-bull", nationalite: "neerlandaise" },
    ],
  },

  mexique: {
    longueur_km: 4.304,
    nombre_tours: 71,
    distance_km: 305.354,
    premier_gp: 1963,
    record_tour: { temps: "1:17.774", pilote: "Valtteri Bottas", annee: 2021 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Lando Norris", numero: 4, ecurie: "mclaren", nationalite: "britannique" },
      { annee: 2024, pilote: "Carlos Sainz", numero: 55, ecurie: "ferrari", nationalite: "espagnole" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2022, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Max Verstappen", numero: 33, ecurie: "red-bull", nationalite: "neerlandaise" },
    ],
  },

  bresil: {
    longueur_km: 4.309,
    nombre_tours: 71,
    distance_km: 305.879,
    premier_gp: 1973,
    record_tour: { temps: "1:10.540", pilote: "Valtteri Bottas", annee: 2018 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Lando Norris", numero: 4, ecurie: "mclaren", nationalite: "britannique" },
      { annee: 2024, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2022, pilote: "George Russell", numero: 63, ecurie: "mercedes", nationalite: "britannique" },
      { annee: 2021, pilote: "Lewis Hamilton", numero: 44, ecurie: "mercedes", nationalite: "britannique" },
    ],
  },

  // Trois éditions seulement. On ne complète pas à cinq.
  "las-vegas": {
    longueur_km: 6.201,
    nombre_tours: 50,
    distance_km: 310.05,
    premier_gp: 2023,
    record_tour: { temps: "1:34.876", pilote: "Lando Norris", annee: 2024 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2024, pilote: "George Russell", numero: 63, ecurie: "mercedes", nationalite: "britannique" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
    ],
  },

  // 2022 n'a pas eu lieu : quatre éditions, quatre cartes.
  qatar: {
    longueur_km: 5.419,
    nombre_tours: 57,
    distance_km: 308.611,
    premier_gp: 2021,
    record_tour: { temps: "1:23.196", pilote: "Max Verstappen", annee: 2021 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2024, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Lewis Hamilton", numero: 44, ecurie: "mercedes", nationalite: "britannique" },
    ],
  },

  "abu-dhabi": {
    longueur_km: 5.281,
    nombre_tours: 58,
    distance_km: 306.183,
    premier_gp: 2009,
    record_tour: { temps: "1:26.103", pilote: "Max Verstappen", annee: 2021 },
    derniers_vainqueurs: [
      { annee: 2025, pilote: "Lando Norris", numero: 4, ecurie: "mclaren", nationalite: "britannique" },
      { annee: 2024, pilote: "Lando Norris", numero: 4, ecurie: "mclaren", nationalite: "britannique" },
      { annee: 2023, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2022, pilote: "Max Verstappen", numero: 1, ecurie: "red-bull", nationalite: "neerlandaise" },
      { annee: 2021, pilote: "Max Verstappen", numero: 33, ecurie: "red-bull", nationalite: "neerlandaise" },
    ],
  },
};

/**
 * La fiche d'un circuit, ou `null`.
 *
 * Un slug sans fiche n'est pas une panne : c'est le cas normal d'un Grand Prix
 * ajouté à `GP_2026` avant que sa fiche soit écrite. L'écran retire alors le
 * bloc entier plutôt que d'afficher quatre tirets — c'est la même règle que
 * `aUnTrace` pour les tracés.
 */
export function ficheCircuit(slug) {
  return CIRCUITS[slug] ?? null;
}

/**
 * Le nom écrit sur l'aileron de la voiture d'un vainqueur : son nom de famille,
 * en capitales.
 *
 * **Dérivé, jamais saisi.** `pilote` porte déjà le nom complet, et un second
 * champ l'aurait répété — deux textes écrits séparément divergent au premier
 * ajustement (CLAUDE.md §6). Le dernier mot est le nom de famille pour les
 * quarante-huit entrées de la table.
 *
 * `Voiture` raccourcit lui-même à dix caractères, ce qui est exactement la
 * longueur de « VERSTAPPEN ».
 */
export function nomSurLaVoiture(pilote) {
  const mots = String(pilote ?? "").trim().split(/\s+/);
  return (mots[mots.length - 1] ?? "").toUpperCase();
}

/* --------------------------------------------------------------------------
   Contrôle de cohérence — il s'exécute au chargement du module, en
   développement seulement.

   Trois tables voisines doivent porter les mêmes clés, et rien dans le code ne
   les y oblige : un slug de circuit mal orthographié retirerait silencieusement
   le bloc, une écurie inconnue rendrait une voiture personnalisable à la place
   d'une livrée, une nationalité absente retirerait le drapeau. Les trois
   symptômes sont discrets, et c'est précisément la sorte de faute que ce projet
   attrape par un contrôle plutôt que par une relecture (la leçon de la
   migration 17).

   `import.meta.env.DEV` le retire du build : c'est une vérification de table
   statique, elle n'a rien à faire dans le bundle d'un téléphone.
   -------------------------------------------------------------------------- */
if (import.meta.env?.DEV) {
  const manquants = GP_2026.filter((gp) => !CIRCUITS[gp.slug]).map((gp) => gp.slug);
  if (manquants.length) {
    console.warn(`circuits.js : aucune fiche pour ${manquants.join(", ")}`);
  }

  const orphelins = Object.keys(CIRCUITS).filter(
    (slug) => !GP_2026.some((gp) => gp.slug === slug),
  );
  if (orphelins.length) {
    console.warn(`circuits.js : fiche sans Grand Prix pour ${orphelins.join(", ")}`);
  }

  for (const [slug, fiche] of Object.entries(CIRCUITS)) {
    for (const vainqueur of fiche.derniers_vainqueurs) {
      if (!aUneLivree(vainqueur.ecurie)) {
        console.warn(`circuits.js : ${slug} ${vainqueur.annee} — écurie inconnue « ${vainqueur.ecurie} »`);
      }
      if (!NATIONALITES[vainqueur.nationalite]) {
        console.warn(`circuits.js : ${slug} ${vainqueur.annee} — nationalité inconnue « ${vainqueur.nationalite} »`);
      }
    }
  }
}
