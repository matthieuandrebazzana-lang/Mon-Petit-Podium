import { appelApi } from "./api.js";
import { cotesArretees, ETATS_GP } from "./calendrier.js";
import { slugCircuit } from "../composants/TracesCircuits.jsx";
import { etatFermeture } from "./format.js";
import { chargerMesGpPronostiques } from "./pronostics.js";

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
 * ## `seances` : ce champ contredit le paragraphe ci-dessus, et voici la limite
 *
 * > ### Écart signalé (CLAUDE.md §6)
 * >
 * > L'écran « Détail GP » affiche les séances du week-end — essais libres,
 * > qualifications, course, et sur un week-end sprint la qualification du
 * > sprint et le sprint lui-même — et **la base n'en connaît que deux** :
 * > `date_course` et `date_qualifications`. Les essais libres et les deux
 * > séances de sprint n'existent nulle part côté serveur, et rien ne les y fera
 * > entrer : ni Unibet ni OpenF1 ne les servent. Sans table statique, le bloc
 * > n'aurait pas pu exister.
 * >
 * > **La règle « seule la base connaît l'heure » n'est donc pas levée, elle est
 * > bornée** : elle continue de valoir pour les deux séances que la base porte.
 * > `seancesDuGp` ci-dessous écrase les valeurs statiques des qualifications et
 * > de la course par celles de la base dès qu'elles existent, et la fermeture
 * > des pronostics ne lit toujours QUE `gp.date_course`. Rien de ce qui décide
 * > n'a changé de propriétaire ; seul l'affichage a gagné les trois lignes que
 * > la base ne saura jamais dire.
 * >
 * > **Ces heures sont prévisionnelles**, au sens où le scraper les remplace
 * > dès qu'Unibet publie son programme. Elles sont écrites en **instants UTC
 * > complets** et non en heures locales : un `Intl.DateTimeFormat` rend ensuite
 * > l'heure du téléphone, où qu'il soit. C'est aussi ce qui fait tomber juste le
 * > cas de Las Vegas, dont la course part le samedi 20h locale, c'est-à-dire le
 * > **dimanche** en UTC.
 * >
 * > **Les onze heures de QUALIFICATIONS, elles, sont relevées et non devinées**
 * > (v`0.61.0`), et les mêmes instants sont écrits en base par les migrations 19
 * > et 20 — trois tables qui se relisent ensemble, une fois par saison. C'est ce
 * > qui manquait : `seancesDuGp` préfère l'heure de la base à celle d'ici, et la
 * > base portait `date_course − 22h`. La fiche du GP d'Italie annonçait donc
 * > 17h00 pour des qualifications à 16h00 — **une heure devinée chassait une
 * > heure relevée**, et corriger cette table seule n'y aurait rien changé.
 * >
 * > **Aucune de ces heures ne se dérive d'une autre.** L'écart entre les
 * > qualifications et le départ vaut 23 h sur huit week-ends, 22 h sur deux,
 * > 24 h au Brésil et 26 h à Las Vegas, dont les qualifications se courent le
 * > vendredi soir : toute constante appliquée aux douze en manque neuf.
 * >
 * > **Le nombre de séances n'est pas fixe** : `seances` porte les clés du
 * > week-end réel, et c'est leur PRÉSENCE qui décide des rangées affichées.
 * > Singapour est le seul week-end **sprint** des douze, donc le seul à porter
 * > `qualifications_sprint` et `sprint` — et le seul à ne porter ni `el2` ni
 * > `el3`, qui ne sont pas des heures manquantes mais des séances qui n'ont pas
 * > lieu. Voir `SEANCES`, qui déclare l'ordre des sept clés possibles.
 * >
 * > **Une divergence à signaler, sans la corriger ici** : la date de
 * > l'Azerbaïdjan (`2026-09-26`) tombe un samedi, quand toutes les autres
 * > courses de la table tombent un dimanche. Les séances de Bakou suivent la
 * > date de CETTE table plutôt que le calendrier de la FIA — le contraire ferait
 * > afficher une course le lendemain de son propre quantième. La date est à
 * > relire en même temps que le reste de la table.
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
  {
    slug: "pays-bas", nom: "GP Pays-Bas", pays: "Pays-Bas", circuit: "Zandvoort",
    date: "2026-08-23", mois: "AOÛT",
    seances: {
      el1: "2026-08-21T11:30:00Z",
      el2: "2026-08-21T15:00:00Z",
      el3: "2026-08-22T10:30:00Z",
      qualifications: "2026-08-22T14:00:00Z",
      course: "2026-08-23T13:00:00Z",
    },
  },
  {
    slug: "italie", nom: "GP Italie", pays: "Italie", circuit: "Monza",
    date: "2026-09-06", mois: "SEPT",
    seances: {
      el1: "2026-09-04T10:30:00Z",
      el2: "2026-09-04T14:00:00Z",
      el3: "2026-09-05T10:30:00Z",
      qualifications: "2026-09-05T14:00:00Z",
      course: "2026-09-06T13:00:00Z",
    },
  },
  {
    slug: "espagne", nom: "GP Espagne", pays: "Espagne", circuit: "Madrid",
    date: "2026-09-13", mois: "SEPT",
    seances: {
      el1: "2026-09-11T11:30:00Z",
      el2: "2026-09-11T15:00:00Z",
      el3: "2026-09-12T10:30:00Z",
      qualifications: "2026-09-12T14:00:00Z",
      course: "2026-09-13T13:00:00Z",
    },
  },
  {
    slug: "azerbaidjan", nom: "GP Azerbaïdjan", pays: "Azerbaïdjan", circuit: "Bakou",
    date: "2026-09-26", mois: "SEPT",
    seances: {
      el1: "2026-09-24T08:30:00Z",
      el2: "2026-09-24T12:00:00Z",
      el3: "2026-09-25T08:30:00Z",
      qualifications: "2026-09-25T12:00:00Z",
      course: "2026-09-26T11:00:00Z",
    },
  },
  {
    slug: "malaisie", nom: "GP Malaisie", pays: "Malaisie", circuit: "Sepang",
    date: "2026-10-04", mois: "OCT",
    seances: {
      el1: "2026-10-02T04:30:00Z",
      el2: "2026-10-02T08:30:00Z",
      el3: "2026-10-03T04:30:00Z",
      qualifications: "2026-10-03T08:00:00Z",
      course: "2026-10-04T07:00:00Z",
    },
  },
  // **Le seul week-end SPRINT des douze** (voir `SEANCES`) : une seule séance
  // d'essais libres, la qualification du sprint le vendredi, le sprint puis la
  // qualification de la course le samedi. Les clés `el2` et `el3` sont donc
  // absentes — ce ne sont pas des heures manquantes, ce sont des séances qui
  // n'ont pas lieu.
  {
    slug: "singapour", nom: "GP Singapour", pays: "Singapour", circuit: "Singapour",
    date: "2026-10-11", mois: "OCT",
    seances: {
      el1: "2026-10-09T08:30:00Z",
      qualifications_sprint: "2026-10-09T12:30:00Z",
      sprint: "2026-10-10T09:00:00Z",
      qualifications: "2026-10-10T13:00:00Z",
      course: "2026-10-11T12:00:00Z",
    },
  },
  {
    slug: "etats-unis", nom: "GP États-Unis", pays: "États-Unis", circuit: "Austin",
    date: "2026-10-25", mois: "OCT",
    seances: {
      el1: "2026-10-23T17:30:00Z",
      el2: "2026-10-23T21:00:00Z",
      el3: "2026-10-24T17:30:00Z",
      qualifications: "2026-10-24T22:00:00Z",
      course: "2026-10-25T19:00:00Z",
    },
  },
  {
    slug: "mexique", nom: "GP Mexique", pays: "Mexique", circuit: "Hermanos Rodríguez",
    date: "2026-11-01", mois: "NOV",
    seances: {
      el1: "2026-10-30T18:30:00Z",
      el2: "2026-10-30T22:00:00Z",
      el3: "2026-10-31T17:30:00Z",
      qualifications: "2026-10-31T23:00:00Z",
      course: "2026-11-01T21:00:00Z",
    },
  },
  {
    slug: "bresil", nom: "GP Brésil", pays: "Brésil", circuit: "Interlagos",
    date: "2026-11-15", mois: "NOV",
    seances: {
      el1: "2026-11-13T14:30:00Z",
      el2: "2026-11-13T19:00:00Z",
      el3: "2026-11-14T14:30:00Z",
      qualifications: "2026-11-14T18:00:00Z",
      course: "2026-11-15T17:00:00Z",
    },
  },
  {
    slug: "las-vegas", nom: "GP Las Vegas", pays: "États-Unis", circuit: "Las Vegas",
    date: "2026-11-21", mois: "NOV",
    seances: {
      el1: "2026-11-20T00:30:00Z",
      el2: "2026-11-20T04:00:00Z",
      el3: "2026-11-21T00:30:00Z",
      qualifications: "2026-11-21T04:00:00Z",
      course: "2026-11-22T04:00:00Z",
    },
  },
  {
    slug: "qatar", nom: "GP Qatar", pays: "Qatar", circuit: "Lusail",
    date: "2026-11-29", mois: "NOV",
    seances: {
      el1: "2026-11-27T13:30:00Z",
      el2: "2026-11-27T17:00:00Z",
      el3: "2026-11-28T14:30:00Z",
      qualifications: "2026-11-28T18:00:00Z",
      course: "2026-11-29T16:00:00Z",
    },
  },
  {
    slug: "abu-dhabi", nom: "GP Abu Dhabi", pays: "Abu Dhabi", circuit: "Yas Marina",
    date: "2026-12-06", mois: "DÉC",
    seances: {
      el1: "2026-12-04T09:30:00Z",
      el2: "2026-12-04T13:00:00Z",
      el3: "2026-12-05T10:30:00Z",
      qualifications: "2026-12-05T14:00:00Z",
      course: "2026-12-06T13:00:00Z",
    },
  },
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
      // Celle des qualifications non plus, et elle sert au compte à rebours
      // d'ouverture (`etatPronostics`), qui annonce le relevé des cotes deux
      // heures après. **Elle ne conditionne plus le bouton de pronostics** :
      // `cotesArretees` ne la lit plus depuis la version `0.65.0`.
      date_qualifications: trouve?.date_qualifications ?? null,
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
 * Un Grand Prix appartient-il au passé ?
 *
 * **Une seule question, un seul propriétaire.** Deux surfaces en dépendent et
 * elles doivent répondre pareil : la carte, qui pâlit ce qui est derrière nous,
 * et l'écran, qui fait démarrer le défilement sur la première carte qui ne l'est
 * pas. Écrites séparément, elles auraient divergé au premier ajustement — et le
 * symptôme aurait été discret : un calendrier ouvert sur une carte pâle, ou une
 * carte vive hors de l'écran.
 *
 * C'est **le statut qui tranche, pas la date**, et c'est la conséquence directe
 * d'`etatDuGpSaison` : un Grand Prix absent de la base est « à venir » même si
 * sa date est passée. `public.grands_prix` ne contient que ce que le scraper a
 * rencontré, et Unibet n'expose jamais que le Grand Prix suivant (CLAUDE.md
 * §3.1) — un Grand Prix couru mais jamais scrapé reste donc vif. On ne pâlit
 * que ce dont on sait qu'il est joué.
 */
export function estGpPasse(gp, maintenant = Date.now()) {
  return etatDuGpSaison(gp, maintenant).cle === "termine";
}

/**
 * Le rang du premier Grand Prix qui n'est pas derrière nous, `-1` s'il n'y en a
 * plus.
 *
 * La liste arrive dans l'ordre de la saison (`GP_2026`), donc « le premier non
 * terminé » est bien le prochain à courir. `-1` en fin de saison, et l'écran
 * n'a alors rien à faire : le défilement reste en haut, sur le premier Grand
 * Prix de l'année, ce qui est le seul repère qui reste.
 */
export function indexProchainGpSaison(grandsPrix, maintenant = Date.now()) {
  return grandsPrix.findIndex((gp) => !estGpPasse(gp, maintenant));
}

/**
 * Ce que le bouton de la carte doit faire, ou `null` s'il n'y a rien à faire.
 *
 * Un Grand Prix à venir n'a pas encore de cotes, un Grand Prix fermé n'accepte
 * plus rien : dans les deux cas, un bouton mènerait à un écran vide. Les deux
 * états qui en portent un exigent tous deux un identifiant venu de la base —
 * il ne peut donc jamais être `null` ici.
 *
 * **La bande est blanche dans les deux cas, la couleur est portée par l'encre.**
 * Elle est posée sur le drapeau du pays hôte, qui change à chaque carte : un
 * aplat bordeaux sur un drapeau bordeaux ne se verrait pas, et deux aplats
 * colonnes l'un sur l'autre feraient deux couleurs concurrentes par carte. C'est
 * l'encre qui distingue l'urgence de l'archive, comme le faisaient les deux
 * styles d'avant.
 *
 * **La surface est opaque, et c'est mesuré**, pour la raison exacte de la
 * pastille (voir `ETATS_GP`) : sur le noir de Las Vegas, une bande blanche à
 * 85 % poserait le vert sauge à 3,45:1. Il faut 97 % pour tenir 4,5:1.
 */
export function actionDuGp(gp, etat, previsualisation = false, aPronostique = false) {
  if (!gp.gp_id) return null;

  if (etat.cle === "termine") {
    return {
      vers: `/grands-prix/${gp.gp_id}/resultats`,
      libelle: "Voir les résultats",
      // Consultation. Vert sauge sur blanc : 4,86:1.
      style: "bg-white text-vert-sauge",
    };
  }
  // **Pronostiquer exige des cotes arrêtées, pas seulement des cotes visibles.**
  // Deux conditions réunies (`cotesArretees`) : le statut `cotes_figees`, et une
  // fermeture pas encore passée. Tant que le Grand Prix est en `a_venir`, le
  // scraper n'a rien arrêté ; passé `date_course`, plus rien ne
  // s'enregistre (règle 4.3). Dans les deux cas le bouton est retiré — ni grisé,
  // ni remplacé par un message.
  //
  // **L'heure des qualifications n'entre plus dans ce test** depuis la version
  // `0.65.0` : `NULL` sur toute ligne qu'Unibet n'a pas programmée, elle retirait
  // le bouton d'un Grand Prix dont les cotes étaient pourtant en base et le
  // statut figé (`bugs-connus.md`).
  //
  // La pastille, elle, continue de dire l'état que les données décrivent : les
  // deux calendriers la calculent sans jamais la déduire du statut, et ce n'est
  // pas un bouton qui doit renverser cette règle. Le geste proposé est donc plus
  // exigeant que le mot affiché, ce qui est le bon sens du doute.
  //
  // **`previsualisation` lève la condition de statut, jamais l'état de la
  // carte.** Le mode montre l'application comme si les cotes étaient arrêtées ;
  // il ne prétend pas qu'un Grand Prix sans cotes en base en ait. `etat.cle` est
  // lu dans les données, pas dans le statut — ouvrir un tableau de cotes vide ne
  // montrerait rien de ce que le mode existe pour montrer.
  if (etat.cle === "ouvert" && (cotesArretees(gp) || previsualisation)) {
    // **Le libellé suit la destination, toujours.** Un bouton « Pronostiquer »
    // qui rouvre le tableau des cotes alors que la saisie est déjà enregistrée
    // promet une chose et en fait une autre : le joueur cherche à relire ce
    // qu'il a joué, pas à recommencer. C'est l'arbitrage que le widget de
    // l'accueil applique depuis la version `0.5.1`, et les trois surfaces qui
    // portent un bouton de pronostics disent maintenant la même chose.
    //
    // La condition d'EXISTENCE du bouton ne bouge pas : elle reste
    // `cotesArretees`. Ce sont deux questions distinctes — « y a-t-il quelque
    // chose à ouvrir ? » puis « quoi ouvrir ? ».
    if (aPronostique) {
      return {
        vers: `/grands-prix/${gp.gp_id}/recap`,
        libelle: "Voir mes pronos",
        // Même aplat, même contraste : c'est le libellé qui distingue les deux
        // gestes, pas la couleur. Douze cartes de la saison portent déjà quatre
        // pastilles d'état ; une cinquième teinte de bouton ferait du bruit là
        // où le mot suffit.
        style: "bg-white text-primaire",
      };
    }
    return {
      vers: `/grands-prix/${gp.gp_id}/cotes`,
      libelle: "Pronostiquer",
      // Action. Bordeaux sur blanc : 10,88:1.
      style: "bg-white text-primaire",
    };
  }
  return null;
}

/* -------------------------------------------------------------------------- */
/*  Les séances d'un week-end                                                 */
/* -------------------------------------------------------------------------- */

/**
 * Les sept séances possibles d'un week-end, dans l'ordre où elles se courent.
 *
 * **L'ordre est déclaré, pas trié.** Un week-end de Formule 1 se déroule
 * toujours ainsi, et trier sur l'instant ferait dépendre la structure du
 * week-end de deux heures venues de la base : une `date_qualifications`
 * aberrante réordonnerait l'écran au lieu de sauter aux yeux à sa place.
 *
 * ## Sept clés déclarées, cinq rangées affichées
 *
 * Aucun week-end ne les court toutes les sept — **c'est la présence de la clé
 * dans `gp.seances` qui décide**, et les deux formats en tirent chacun cinq
 * séances de cette même liste :
 *
 * | Format | Vendredi | Samedi | Dimanche |
 * |---|---|---|---|
 * | ordinaire | EL1, EL2 | EL3, qualifications | course |
 * | **sprint** | EL1, qualif. sprint | sprint, qualifications | course |
 *
 * L'ordre déclaré ci-dessous est donc **la fusion des deux**, et le filtre en
 * tire l'ordre juste dans les deux cas. Deux listes écrites séparément — une
 * par format — auraient divergé au premier libellé retouché, exactement comme
 * les deux libellés de `Horloge` en `0.57.0` (CLAUDE.md §6).
 *
 * ## Les libellés sont écrits en toutes lettres (v`0.60.0`)
 *
 * « EL1 » était l'abréviation du paddock, retenue parce qu'une rangée d'iPhone
 * ne paraissait pas pouvoir porter « Essais Libres 1 ». **Elle le peut** : la
 * rangée réserve sa colonne de droite à l'heure et laisse tout le reste au
 * libellé, et « Qualifications » — le plus long des sept — s'y écrivait déjà en
 * entier. Un écran de consultation ouvert par quelqu'un qui découvre la Formule
 * 1 n'a aucune raison de lui demander de décoder trois lettres.
 */
export const SEANCES = [
  { cle: "el1", libelle: "Essais Libres 1" },
  { cle: "el2", libelle: "Essais Libres 2" },
  { cle: "qualifications_sprint", libelle: "Qualifications Sprint" },
  { cle: "el3", libelle: "Essais Libres 3" },
  { cle: "sprint", libelle: "Sprint" },
  { cle: "qualifications", libelle: "Qualifications" },
  { cle: "course", libelle: "Course" },
];

/**
 * Le week-end d'un Grand Prix dont on ne sait rien : le format ordinaire.
 *
 * C'est le repli de `seancesDuGp` quand la table statique n'a pas d'entrée —
 * un Grand Prix ajouté à `GP_2026` avant que ses horaires soient écrits, ou
 * l'écran monté sans Grand Prix du tout. **Cinq noms sans leurs heures valent
 * mieux qu'un bloc vide** : le programme d'un week-end de Formule 1 est vrai
 * sans la base, exactement comme les douze cartes du calendrier
 * (`calendrier.md` §1). Le format sprint, lui, ne se devine pas — il ne
 * s'affiche que là où la table le déclare.
 */
const SEANCES_ORDINAIRE = ["el1", "el2", "el3", "qualifications", "course"];

export const SEUIL_IMMINENT_MS = 24 * 60 * 60 * 1000;

/**
 * Les séances d'un Grand Prix, datées, avec leur état.
 *
 * **Le format du week-end vient de la table, jamais d'un réglage.** Les clés
 * présentes dans `gp.seances` disent quelles séances se courent ; `SEANCES`
 * dit dans quel ordre. Un week-end sprint n'a donc rien à déclarer d'autre que
 * ses heures — pas de drapeau `sprint: true` à tenir en accord avec elles, et
 * pas de second endroit à corriger quand la FIA déplace un sprint.
 *
 * **La base l'emporte sur la table statique partout où elle a une réponse.**
 * Deux séances sont en base — les qualifications et la course — et ce sont les
 * deux seules dont l'heure engage quelque chose : la première ouvre les
 * pronostics, la seconde les ferme. Les afficher depuis la table statique alors
 * que la base dit autre chose ferait mentir l'écran à côté d'un compte à rebours
 * juste, et c'est exactement le défaut que `etatPronostics` a corrigé en
 * `0.57.0` — un libellé écrit deux fois finit par dire deux choses.
 *
 * Les essais libres et les deux séances de sprint n'ont pas d'équivalent en
 * base : elles restent prévisionnelles, et l'en-tête du module le dit.
 *
 * **Cette préférence suppose que la base dise vrai, et c'est ce qui a manqué.**
 * Jusqu'à la `0.61.0` la base portait `date_course − 22h` pour les onze Grands
 * Prix posés par la migration 19 : la substitution ci-dessous remplaçait donc
 * l'heure juste de `GP_2026` par une heure dérivée, et la fiche de l'Italie
 * annonçait 17h00 au lieu de 16h00. La règle n'était pas en cause — les deux
 * sources écrivent maintenant les mêmes instants, et le scraper ne dérive plus
 * rien. **Corriger la table statique seule n'aurait rien corrigé du tout.**
 *
 * Une séance dont l'instant est illisible est **rendue quand même**, sans date :
 * une rangée manquante ferait croire que le week-end n'a pas d'EL3, là qu'un
 * « — » dit qu'on ne connaît pas encore son heure. C'est la règle des douze
 * cartes du calendrier, appliquée aux rangées d'un week-end.
 */
export function seancesDuGp(gp, maintenant = Date.now()) {
  const statiques = gp?.seances ?? {};
  // Les deux seules substitutions, écrites une fois. Un `??` sur une chaîne
  // vide passerait — d'où le test de vérité, la base servant `null` et non `""`.
  const enBase = {
    qualifications: gp?.date_qualifications || null,
    course: gp?.date_course || null,
  };

  // **La présence décide, pas la valeur.** Une heure que la base seule connaît
  // fait exister sa rangée même si la table statique se tait ; un `el2` absent
  // de la table d'un week-end sprint ne fait apparaître aucune rangée vide.
  // Sans aucune clé du tout, on retombe sur le format ordinaire.
  const cles = new Set([
    ...Object.keys(statiques),
    ...Object.keys(enBase).filter((cle) => enBase[cle]),
  ]);
  const retenues = cles.size ? cles : new Set(SEANCES_ORDINAIRE);

  const datees = SEANCES.filter((seance) => retenues.has(seance.cle)).map(
    (seance) => {
      const iso = enBase[seance.cle] ?? statiques[seance.cle] ?? null;
      const instant = iso ? Date.parse(iso) : NaN;
      const date = Number.isFinite(instant) ? instant : null;

      return {
        ...seance,
        iso,
        instant: date,
        // La source est exposée pour que l'écran puisse le dire :
        // « prévisionnel » n'a pas le même poids qu'une heure confirmée par le
        // programme d'Unibet.
        confirmee: Boolean(enBase[seance.cle]),
        passee: date !== null && date <= maintenant,
        imminente: false,
      };
    },
  );

  // **Une seule mise en avant, et c'est la PROCHAINE.** Le rang tranche, le
  // délai ne fait que l'autoriser — voir `SEUIL_IMMINENT_MS`. Une séance dont
  // l'heure est inconnue n'est ni passée ni prochaine : elle ne peut pas prendre
  // la place, mais elle ne bloque pas non plus celle d'après, sans quoi un EL3
  // sans horaire éteindrait la mise en avant de la course.
  const prochaine = datees.find(
    (seance) => seance.instant !== null && !seance.passee,
  );
  if (
    prochaine &&
    prochaine.instant - maintenant <= SEUIL_IMMINENT_MS
  ) {
    prochaine.imminente = true;
  }

  return datees;
}

/**
 * Le Grand Prix de la saison qui porte ce slug, ou `null`.
 *
 * Exporté plutôt que laissé à un `find` chez l'appelant : l'écran de détail
 * arrive par une URL, donc par une chaîne que personne n'a validée, et c'est ce
 * module qui sait ce qu'est un slug valide.
 */
export function gpParSlug(slug) {
  return GP_2026.find((gp) => gp.slug === slug) ?? null;
}

/**
 * Le chargeur de la saison : les cotes en base **et** les Grands Prix que
 * j'ai déjà joués, en un seul aller-retour.
 *
 * **Deux écrans le partagent** — l'onglet Calendrier et l'écran de détail d'un
 * Grand Prix — et ils partagent avec lui la clé de cache `cleSaison`. C'est ce
 * qui rend l'ouverture du détail instantanée : la réponse est déjà là, et le
 * *stale-while-revalidate* la rafraîchit derrière. Deux chargeurs écrits
 * séparément auraient produit deux entrées de cache sous la même clé, donc deux
 * formes de données pour un seul nom — le genre de faute dont le symptôme
 * n'apparaît qu'au second écran.
 *
 * **Les deux lectures partent ensemble.** Les cotes disent quels Grands Prix
 * sont ouverts, les pronostics disent ce que le bouton doit proposer sur
 * ceux-là. Enchaînées, elles auraient additionné un aller-retour Supabase au
 * réveil de Railway.
 *
 * **La seconde ne peut pas faire échouer la première** :
 * `chargerMesGpPronostiques` rend toujours `ok` (voir sa note). Le calendrier
 * s'affiche donc entier même si elle échoue, et ses boutons retombent sur
 * « Pronostiquer », qui reste vrai.
 */
export async function chargerSaison(profilId, signal) {
  const [cotes, joues] = await Promise.all([
    chargerCotesEnBase(signal),
    chargerMesGpPronostiques(profilId, signal),
  ]);
  if (!cotes.ok) return cotes;
  return {
    ok: true,
    message: null,
    donnees: { cotes: cotes.donnees, joues: [...joues.donnees] },
  };
}

/**
 * Où mène le CORPS d'une carte de Grand Prix — sa zone d'informations, par
 * opposition à sa bande d'action (`actionDuGp`).
 *
 * **Deux destinations, et c'est l'état qui tranche.** Un Grand Prix couru ouvre
 * ses **résultats** : la question qu'on se pose devant une course passée est
 * « qui a gagné, et combien j'ai marqué ». Tous les autres ouvrent leur
 * **fiche** : le programme du week-end, le circuit, le palmarès.
 *
 * **Le départage passe par `etatDuGpSaison`, jamais par le statut brut** — c'est
 * la fonction qui décide déjà de la pastille et de la pâleur de la carte, et une
 * seconde lecture du statut aurait pu envoyer vers les résultats une carte
 * affichée « À venir ». Un seul propriétaire pour « ce Grand Prix est-il
 * derrière nous ? ».
 *
 * **La fiche est indexée par le slug, jamais par l'identifiant en base**, et
 * c'est structurel : onze des douze Grands Prix de la saison n'ont pas encore
 * d'identifiant, et ce sont précisément ceux dont on vient lire la fiche. Les
 * résultats, eux, n'existent pas sans la base — d'où le repli sur la fiche si
 * l'identifiant manquait, plutôt qu'un lien mort.
 *
 * Contrairement à `actionDuGp`, cette fonction **rend toujours une
 * destination** : la carte est tapable sur les douze, y compris quand la base
 * dort. C'est ce qui rend le geste apprenable — une carte sur deux qui ne
 * réagit pas ne s'essaie pas deux fois.
 */
export function destinationDuGp(gp, etat) {
  if (etat.cle === "termine" && gp.gp_id) {
    return `/grands-prix/${gp.gp_id}/resultats`;
  }
  return `/calendrier/${gp.slug}`;
}
