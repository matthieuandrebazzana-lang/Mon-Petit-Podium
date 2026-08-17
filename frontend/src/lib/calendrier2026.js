import { appelApi } from "./api.js";
import { ETATS_GP } from "./calendrier.js";
import { slugCircuit } from "../composants/TracesCircuits.jsx";
import { etatFermeture } from "./format.js";

/**
 * Les douze Grands Prix restants de la saison 2026 — **la source de vérité de
 * l'onglet Calendrier.**
 *
 * ## Pourquoi une liste statique, et non la base
 *
 * `public.grands_prix` ne contient que ce que le scraper a rencontré, et
 * **Unibet n'expose jamais que le Grand Prix suivant** (CLAUDE.md section 3.1) :
 * la table ne porte donc qu'une seule course à ce jour. Un calendrier lu en base
 * afficherait un unique Grand Prix au milieu d'une saison qui en compte douze.
 * C'est exactement le défaut qui a figé le bandeau « Grands Prix restants » à la
 * version `0.14.1`, ici poussé à sa conclusion : le calendrier de la Formule 1
 * est une donnée publique et stable, elle n'a pas à être découverte chez un
 * bookmaker.
 *
 * La base garde ce qu'elle seule sait : **l'identifiant du Grand Prix, son
 * statut et l'existence de ses cotes**. C'est le rôle de `enrichir` ci-dessous.
 *
 * ## Le jour et le mois sont écrits, pas dérivés
 *
 * `date` est une date nue (`2026-08-23`), donc **minuit UTC** une fois analysée
 * par `new Date`. En dériver le quantième avec `getDate()` rendrait « 22 » pour
 * tout lecteur situé à l'ouest de Greenwich : le calendrier afficherait la
 * veille de chaque course sur la moitié de la planète. Le champ `mois` est donc
 * écrit ici, et le quantième est lu dans la chaîne elle-même (`jourDe`), jamais
 * calculé dans le fuseau du téléphone.
 *
 * `date` reste utilisée pour l'ordre et pour les comparaisons ; l'**heure** de
 * départ, elle, ne vient jamais d'ici — seule la base la connaît, et c'est elle
 * qui décide de la fermeture des pronostics (règle 4.3).
 *
 * ## À mettre à jour
 *
 * Comme `backend/app/calcul/pilotes.py`, cette table décrit **une saison**. Elle
 * se relit sur le calendrier officiel de la FIA. Les `slug` doivent rester ceux
 * de `slugCircuit` : ce sont eux qui donnent le drapeau (`DrapeauxGP`) et le
 * tracé (`TracesCircuits`), et un slug inconnu ferait retomber la carte sur le
 * bordeaux de la marque, sans circuit.
 */
export const GP_2026 = [
  { slug: "pays-bas", nom: "GP Pays-Bas", pays: "Pays-Bas", circuit: "Zandvoort", date: "2026-08-23", mois: "AOÛT" },
  { slug: "italie", nom: "GP Italie", pays: "Italie", circuit: "Monza", date: "2026-09-06", mois: "SEPT" },
  { slug: "espagne", nom: "GP Espagne", pays: "Espagne", circuit: "Madrid", date: "2026-09-13", mois: "SEPT" },
  { slug: "azerbaidjan", nom: "GP Azerbaïdjan", pays: "Azerbaïdjan", circuit: "Bakou", date: "2026-09-26", mois: "SEPT" },
  { slug: "malaisie", nom: "GP Malaisie", pays: "Malaisie", circuit: "Sepang", date: "2026-10-04", mois: "OCT" },
  { slug: "singapour", nom: "GP Singapour", pays: "Singapour", circuit: "Singapour", date: "2026-10-11", mois: "OCT" },
  { slug: "etats-unis", nom: "GP États-Unis", pays: "États-Unis", circuit: "Austin", date: "2026-10-25", mois: "OCT" },
  { slug: "mexique", nom: "GP Mexique", pays: "Mexique", circuit: "Hermanos Rodríguez", date: "2026-11-01", mois: "NOV" },
  { slug: "bresil", nom: "GP Brésil", pays: "Brésil", circuit: "Interlagos", date: "2026-11-15", mois: "NOV" },
  { slug: "las-vegas", nom: "GP Las Vegas", pays: "États-Unis", circuit: "Las Vegas", date: "2026-11-21", mois: "NOV" },
  { slug: "qatar", nom: "GP Qatar", pays: "Qatar", circuit: "Lusail", date: "2026-11-29", mois: "NOV" },
  { slug: "abu-dhabi", nom: "GP Abu Dhabi", pays: "Abu Dhabi", circuit: "Yas Marina", date: "2026-12-06", mois: "DÉC" },
];

/**
 * Le quantième, lu dans la chaîne de date plutôt que calculé.
 *
 * Voir l'en-tête : `new Date("2026-08-23").getDate()` vaut 22 dès qu'on lit
 * l'app depuis un fuseau négatif. La chaîne, elle, dit toujours la même chose.
 */
export function jourDe(date) {
  const jour = String(date ?? "").split("-")[2];
  // Le zéro de tête n'a pas sa place sous un chiffre de 48px : « 04 » se lit
  // comme un numéro de série, « 4 » comme une date.
  return jour ? String(Number(jour)) : null;
}

/**
 * Les Grands Prix déjà en base, avec leur identifiant, leur statut et leurs
 * cotes.
 *
 * C'est la route publique de l'étape 4, celle qui sert déjà le tableau des
 * cotes. Elle rend **toutes** les cotes de tous les Grands Prix ; le calendrier
 * n'en retient que trois champs et l'existence d'au moins un marché. C'est
 * plus que nécessaire, et c'est assumé tant que la base ne porte qu'une poignée
 * de courses : une route dédiée à ce seul besoin serait du code backend à
 * maintenir pour trois booléens.
 */
export function chargerCotesEnBase(signal) {
  return appelApi("/scraper/cotes", { signal });
}

/**
 * La liste statique croisée avec ce que la base sait.
 *
 * **Le rapprochement se fait sur le slug de circuit, jamais sur le nom.** Unibet
 * écrit « GP Pays Bas » cette semaine et « GP Pays-Bas » la suivante — c'est
 * déjà la raison pour laquelle `grands_prix` se rapproche par `id_unibet` et non
 * par le nom (étape 4). `slugCircuit` ramène les deux à la même clé, alias
 * compris (« GP Sepang » → `malaisie`).
 *
 * **Un Grand Prix absent de la base reste servi**, sans identifiant ni statut :
 * c'est le cas normal de toute la saison à venir, pas une panne. C'est aussi ce
 * qui fait que l'écran affiche ses douze cartes même quand Railway dort.
 *
 * Le nom affiché reste celui de la table statique et non celui de la base : le
 * calendrier doit se lire pareil d'une semaine à l'autre, y compris quand le
 * bookmaker change l'orthographe d'un pays.
 */
export function enrichir(grandsPrix = GP_2026, enBase = null) {
  const parSlug = new Map(
    (enBase ?? []).map((gp) => [slugCircuit(gp.nom), gp]),
  );

  return grandsPrix.map((gp) => {
    const trouve = parSlug.get(gp.slug) ?? null;
    return {
      ...gp,
      gp_id: trouve?.id ?? null,
      statut: trouve?.statut ?? null,
      // L'heure exacte du départ n'existe qu'en base : elle seule permet de
      // savoir si les pronostics sont fermés (règle 4.3).
      date_course: trouve?.date_course ?? null,
      cotes_disponibles: (trouve?.marches?.length ?? 0) > 0,
      en_base: Boolean(trouve),
    };
  });
}

/**
 * L'état d'un Grand Prix de la saison, et la pastille qui le dit.
 *
 * Les quatre états et leurs couleurs viennent de `ETATS_GP` (`lib/calendrier.js`),
 * partagés avec le calendrier d'un championnat : les deux écrans disent le même
 * mot avec la même couleur, et il n'y a qu'un endroit à corriger.
 *
 * **Un Grand Prix absent de la base est « à venir », toujours.** On ne sait ni
 * si ses cotes existent, ni à quelle heure il part : le déclarer fermé sur la
 * foi d'une date sans heure fermerait la carte dès minuit UTC le jour de la
 * course, et « terminé » supposerait des résultats que personne n'a lus. C'est
 * le bon sens du doute, et c'est exactement ce que la demande prescrit.
 *
 * L'ordre des tests compte : une course courue est terminée quoi qu'il arrive,
 * et une fermeture passée l'emporte sur des cotes encore affichées.
 */
export function etatDuGpSaison(gp, maintenant = Date.now()) {
  if (!gp.en_base) return ETATS_GP.a_venir;
  if (gp.statut === "termine") return ETATS_GP.termine;

  const { ferme } = etatFermeture(gp.date_course, maintenant);
  if (ferme) return ETATS_GP.ferme;
  if (gp.cotes_disponibles) return ETATS_GP.ouvert;
  return ETATS_GP.a_venir;
}

/**
 * Ce que le bouton de la carte doit faire, ou `null` s'il n'y a rien à faire.
 *
 * Un Grand Prix à venir n'a pas encore de cotes, un Grand Prix fermé n'accepte
 * plus rien : dans les deux cas, un bouton mènerait à un écran vide. Les deux
 * états qui en portent un exigent tous deux un identifiant venu de la base —
 * il ne peut donc jamais être `null` ici.
 */
export function actionDuGp(gp, etat) {
  if (!gp.gp_id) return null;

  if (etat.cle === "termine") {
    return {
      vers: `/grands-prix/${gp.gp_id}/resultats`,
      libelle: "Voir les résultats",
      // Consultation : le bordeaux sur le beige du fond, pas un aplat plein.
      // Douze cartes terminées feraient sinon douze barres rouges, et l'urgence
      // ne se distinguerait plus de l'archive.
      style: "bg-fond text-primaire",
    };
  }
  if (etat.cle === "ouvert") {
    return {
      vers: `/grands-prix/${gp.gp_id}/cotes`,
      libelle: "Pronostiquer",
      style: "bg-primaire text-white",
    };
  }
  return null;
}
