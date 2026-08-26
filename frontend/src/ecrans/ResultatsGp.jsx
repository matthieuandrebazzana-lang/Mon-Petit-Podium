import { useCallback, useState } from "react";
import { useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import Pastille from "../composants/Pastille.jsx";
import Voiture from "../composants/Voiture.jsx";
import DrapeauPays from "../composants/DrapeauxPilotes.jsx";
import { livreeDuMembre } from "../lib/palette.js";
import { livreeDeLEcurie } from "../lib/livrees.js";
import { nationaliteDuPilote } from "../lib/nationalites.js";
import { Barre, Carte, Pave, Rangee } from "../composants/Squelette.jsx";
import {
  IconeChevronAccordeon,
  IconeCoche,
  IconeHorloge,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerResultatsGp,
  classerLesMembres,
  cleResultats,
} from "../lib/calendrier.js";
import { useDonnees } from "../lib/useDonnees.js";
import { choixDuPronostic } from "../lib/pronostics.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";

/**
 * Maquette 11 — les résultats d'un Grand Prix couru.
 *
 * **Deux blocs, deux régimes d'accès, et la frontière est celle de la route**
 * (`GET /grands-prix/{id}/resultats`, étape 6) :
 *
 * - le **classement de la course** est public. Un résultat de Formule 1 l'est
 *   partout ailleurs, et l'écran s'affiche sans session — c'est pour cela que sa
 *   route vit hors des groupes public et protégé de `App.jsx`, comme
 *   `/nouveau-mot-de-passe` ;
 * - les **pronostics des membres** n'apparaissent qu'avec un `championnat_id`,
 *   donc uniquement quand on arrive ici depuis un championnat dont on est
 *   membre. La route exige le jeton et vérifie l'appartenance ; l'écran ne
 *   décide rien, il affiche ce qu'on lui sert.
 *
 * **Les pronostics de l'appelant, eux, ne passent plus par là quand il n'y a
 * pas de championnat** (version `0.63.0`) : ils sont lus directement sous RLS
 * et arrivent sous `mes_pronostics`. Le partage est décrit dans
 * `chargerResultatsGp`, et il tient en une phrase — un pronostic appartient à
 * un joueur et à un Grand Prix, jamais à un championnat.
 *
 * **Un Grand Prix non couru n'est pas une erreur.** La route rend
 * `disponible: false` plutôt qu'un `404` (étape 6), et l'écran le dit avec la
 * date et l'heure du départ. Un écran vide laisserait croire à une panne.
 *
 * ## La refonte en sections (version `0.62.0`)
 *
 * L'écran répondait à deux questions dans un ordre qui n'était pas celui où on
 * se les pose. Il ouvre maintenant sur **« Mes résultats »** — ce que *j'ai*
 * marqué, pronostic par pronostic — puis sur **« Résultats du GP »**, le
 * classement complet de la course. Les deux sections portent le même en-tête,
 * un titre et un filet bordeaux, pour se lire comme deux pairs et non comme un
 * bloc et son annexe.
 *
 * > **Écart signalé (CLAUDE.md §6) : il y a une TROISIÈME section, et elle est
 * > conservée.** La demande décrit deux sections et ne dit rien du classement
 * > des membres du championnat — ni de le garder, ni de le retirer. Le retirer
 * > aurait supprimé la seule surface où l'on voit ce que ses amis ont
 * > pronostiqué sur ce Grand Prix, avec son accordéon et ses photos, sur la foi
 * > d'un silence. « Mes résultats » répond à « qu'ai-je marqué », pas à « qui a
 * > gagné entre nous » : les deux questions coexistaient déjà, elles coexistent
 * > toujours, sous un titre de section comme les deux autres.
 *
 * > **Second écart (§6) : « les 20 pilotes ».** La grille 2026 en compte
 * > **vingt-deux**, et un classement peut en porter plus encore (un pilote de
 * > remplacement dans le week-end). L'écran rend **toutes** les lignes que la
 * > course a publiées plutôt qu'un nombre écrit en dur : couper à vingt aurait
 * > fait disparaître les deux derniers classés, et compléter à vingt aurait
 * > inventé des lignes. C'est le refus déjà opposé aux palmarès courts de Las
 * > Vegas et du Qatar en version `0.60.0`.
 *
 * > **Troisième écart (§6) : les points du championnat du monde ne sont pas
 * > calculés depuis la position.** La demande donne le barème (25-18-15-12-10-8-6-4-2-1-0) ;
 * > `points_fia` arrive déjà d'OpenF1, qui sait ce que la position seule ne dit
 * > pas — le point du sprint, une pénalité appliquée après l'arrivée, une
 * > disqualification. Poser le barème par-dessus aurait remplacé un fait par
 * > une règle, et la règle aurait eu tort d'abord sur le week-end sprint de
 * > Singapour.
 */

/* -------------------------------------------------------------------------- */
/*  L'en-tête d'une section                                                   */
/* -------------------------------------------------------------------------- */

/**
 * Le titre d'une section, et le séparateur qui la détache de la précédente.
 *
 * **Le séparateur n'est pas un trait.** Le design system proscrit les bordures
 * fines (§3) et n'en excepte que le **filet de 4px** d'une ligne de classement,
 * qui est un aplat posé à l'intérieur et non un trait qui cerne. C'est ce filet
 * qui est repris ici, en bordeaux, à côté d'un titre en 19px — la hiérarchie
 * passe donc par **la taille, la graisse et l'espace**, comme partout ailleurs,
 * et le filet ne fait que donner à l'œil un point d'accroche à gauche.
 *
 * Un `<h2>` et non un `<p>` : trois sections sur un écran forment un plan, et
 * un lecteur d'écran doit pouvoir sauter de l'une à l'autre.
 */
function TitreSection({ titre, sousTitre }) {
  return (
    <div className="flex items-center gap-2.5 px-1">
      <span
        aria-hidden="true"
        className="bg-primaire h-6 w-1 shrink-0 rounded-full"
      />
      <div className="min-w-0">
        <h2 className="text-texte text-[19px] leading-tight font-medium tracking-[-0.01em]">
          {titre}
        </h2>
        {sousTitre && (
          <p className="text-secondaire mt-0.5 truncate text-[12px]">{sousTitre}</p>
        )}
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Section 1 — Mes résultats                                                 */
/* -------------------------------------------------------------------------- */

/** Verdict d'un pronostic. Repris de la maquette 13, mêmes trois états.
 *
 *  Exporté depuis la version `0.53.0` : l'écran « Résultats par Grand Prix »
 *  affiche les mêmes trois états sur les mêmes pronostics. Deux pastilles
 *  écrites séparément auraient fini par dire « raté » d'un côté et « en
 *  attente » de l'autre sur la même ligne — la distinction entre `null` et `0`
 *  est justement celle qu'aucun écran n'a le droit de perdre (règle 4.1).
 *
 *  > ### Le succès passe à l'ambre au vert sauge (version `0.54.0`)
 *  >
 *  > La coche vivait sur un aplat ambre à 20 %, en encre marron — la palette de
 *  > la maquette. Ce n'était pas *rouge*, mais ce n'était pas non plus
 *  > distinguable au premier coup d'œil du bordeaux de l'échec : deux chauds
 *  > côte à côte dans une colonne de vingt lignes. La couleur du succès est
 *  > maintenant celle que le design system emploie déjà pour dire « c'est
 *  > acquis » — le vert sauge du bloc « pronostics enregistrés » et de la
 *  > pastille « Terminé » du calendrier. **Aucune teinte nouvelle n'entre.**
 *  >
 *  > Mesuré sur carte blanche : coche vert sauge sur vert sauge à 15 % →
 *  > **4,01:1**, au-dessus des 3:1 d'un élément graphique porteur de sens. La
 *  > croix bordeaux sur bordeaux à 10 % tient 8,94:1 et ne bouge pas. */
export function Verdict({ pointsGagnes }) {
  if (pointsGagnes === null || pointsGagnes === undefined) {
    return (
      <span
        aria-label="En attente de validation"
        className="bg-fond flex size-[22px] shrink-0 items-center justify-center rounded-full"
      >
        <IconeHorloge className="text-texte-doux size-2.5" />
      </span>
    );
  }

  const reussi = pointsGagnes > 0;
  return (
    <span
      aria-label={reussi ? "Pronostic réussi" : "Pronostic raté"}
      className={`flex size-[22px] shrink-0 items-center justify-center rounded-full ${
        reussi ? "bg-vert-sauge/15" : "bg-primaire/10"
      }`}
    >
      {reussi ? (
        <IconeCoche className="text-vert-sauge size-2.5 [stroke-width:3]" />
      ) : (
        <span aria-hidden="true" className="text-primaire text-[12px] font-medium">
          ×
        </span>
      )}
    </span>
  );
}

/**
 * Ce qu'un pronostic rapporte, et la couleur qui dit s'il l'a rapporté.
 *
 * **Trois états, jamais deux.** La pastille disait le contraire de ce qu'elle
 * montrait : un pronostic réussi prenait l'aplat bordeaux plein, un pronostic
 * raté **et** un pronostic pas encore jugé prenaient tous deux le même bordeaux
 * sur beige. Toute la colonne était donc rouge, le succès y était l'état le plus
 * sombre, et `null` était indistinguable de `0` — la seule distinction que la
 * règle 4.1 interdit de perdre. La `Verdict` voisine la tenait, seule.
 *
 * | État | Aplat | Encre | Contraste |
 * |---|---|---|---|
 * | réussi (`> 0`) | vert sauge | blanc | **4,86:1** |
 * | raté (`0`) | bordeaux | blanc | **10,88:1** |
 * | en attente (`null`) | beige | marron | **9,32:1** |
 *
 * Le beige de l'attente n'est pas un troisième verdict : c'est l'absence de
 * verdict. Il porte le nombre de points **potentiels**, et le peindre en rouge
 * annoncerait un échec qui n'a pas eu lieu — c'est le même arbitrage que le
 * « en jeu / gagnés » de la ligne au-dessus.
 *
 * > **Un seul propriétaire pour les deux écrans.** Les deux accordéons de
 * > pronostics — celui des résultats d'un Grand Prix et celui des résultats par
 * > Grand Prix — portaient ce bloc **recopié à l'identique**. C'est exactement
 * > ce qui est arrivé à `Verdict` une version plus tôt, et pour la même raison :
 * > les deux listes affichent la même donnée et doivent la dire pareil.
 */
export function PastillePoints({ pointsGagnes, points }) {
  const juge = pointsGagnes !== null && pointsGagnes !== undefined;
  const reussi = juge && pointsGagnes > 0;

  return (
    <span
      className={`rounded-[10px] px-2 py-1 text-[12px] font-medium ${
        !juge
          ? "bg-fond text-secondaire"
          : reussi
            ? "bg-vert-sauge text-white"
            : "bg-primaire text-white"
      }`}
    >
      {/* Après la course, ce que le pari a rapporté ; avant, ce qu'il peut
          rapporter. Jamais une cote brute — la valeur en base EST un nombre de
          points (règle 4.1), et `formaterPoints` en reste le seul habilleur. */}
      {formaterPoints(juge ? pointsGagnes : points)}
    </span>
  );
}

/**
 * Un pronostic, en widget.
 *
 * Trois choses, dans l'ordre où on les lit : **le marché** (« Vainqueur »), **la
 * sélection** (« M.Verstappen »), **le verdict**. Le marché est en label parce
 * qu'il classe ; la sélection est ce qu'on vient lire, elle est donc la plus
 * grosse et la seule en encre pleine.
 *
 * La pastille et la coche disent la même chose de deux façons — un nombre coloré
 * et un pictogramme — et c'est délibéré : la couleur seule ne porte jamais une
 * information (WCAG 1.4.1), et `Verdict` porte l'`aria-label` qui la nomme.
 */
function WidgetPronostic({ pronostic }) {
  return (
    <li className="rounded-widget bg-surface shadow-carte flex items-center gap-3 px-3.5 py-2.5">
      <span className="min-w-0 flex-1">
        <span className="text-label-sm text-secondaire block truncate uppercase">
          {pronostic.libelle ?? pronostic.type}
        </span>
        <span className="text-texte mt-0.5 block truncate text-[14px] font-medium">
          {choixDuPronostic(pronostic)}
        </span>
      </span>

      <span className="flex shrink-0 items-center gap-2">
        <PastillePoints
          pointsGagnes={pronostic.points_gagnes}
          points={pronostic.points}
        />
        <Verdict pointsGagnes={pronostic.points_gagnes} />
      </span>
    </li>
  );
}

/** Une absence, dite en deux phrases. Les quatre cas de `MesResultats` ne
 *  diffèrent que par leur texte : leur composition, elle, n'a aucune raison
 *  d'être écrite quatre fois. */
function Absence({ titre, detail }) {
  return (
    <div className="rounded-carte bg-surface shadow-carte px-5 py-6 text-center">
      <p className="text-corps text-texte font-medium">{titre}</p>
      <p className="text-corps-sm text-secondaire mx-auto mt-1 max-w-[32ch]">
        {detail}
      </p>
    </div>
  );
}

/**
 * La fiche récapitulative du joueur connecté.
 *
 * **Elle ne dépend pas de `disponible`**, et c'est le seul vrai changement de
 * comportement de la refonte. La route sert les pronostics des membres qu'un
 * classement de course ait été récupéré ou non : avant la course, la section
 * affiche donc les pronostics déjà posés, tous en attente, avec leurs points
 * **potentiels**. L'ancien écran les cachait derrière `disponible` et laissait
 * le joueur sans aucune trace de ce qu'il avait validé.
 *
 * > ### Elle ne dépend plus d'un championnat non plus (version `0.63.0`)
 * >
 * > Elle affichait « ouvre ce Grand Prix depuis un championnat » dès qu'on
 * > arrivait par le calendrier — soit par le chemin le plus court vers un Grand
 * > Prix couru. Le message était exact et sans remède, et il posait la mauvaise
 * > question : **un pronostic n'appartient pas à un championnat.** Il est saisi
 * > pour un couple `(joueur, Grand Prix)` et vaut pour tous les championnats à
 * > la fois ; le championnat ne décide que de *qui d'autre* a le droit de le
 * > voir. Pour se le montrer à soi-même, il n'a jamais eu son mot à dire.
 * >
 * > Les pronostics arrivent donc de deux sources selon la porte d'entrée, et
 * > l'écran ne le sait pas : il reçoit dans les deux cas une ligne passée par
 * > `classerLesMembres`, qui reste le seul propriétaire du total, du nombre de
 * > jugés et du « a joué ».
 *
 * **Le rang, lui, ne suit pas.** Il n'a de sens qu'entre membres : hors
 * championnat il n'y a personne devant ni derrière, et afficher « 1er ce GP »
 * pour un joueur seul serait une distinction inventée. La pastille disparaît
 * plutôt que de mentir — c'est le refus déjà opposé aux palmarès courts.
 *
 * Quatre absences, quatre messages, parce qu'elles ne veulent pas dire la même
 * chose : personne n'est connecté, la lecture a échoué, le joueur n'a rien
 * joué, ou il a joué sans que rien ne soit encore jugé.
 */
function MesResultats({ moi, avecRang, connecte, echec }) {
  if (!connecte) {
    return (
      <Absence
        titre="Tes pronostics"
        detail="Connecte-toi pour retrouver ce que tu as validé sur ce Grand Prix."
      />
    );
  }

  if (echec) {
    return (
      <Absence
        titre="Pronostics indisponibles"
        detail="Tes pronostics n'ont pas pu être chargés. Le classement de la course, lui, est à jour."
      />
    );
  }

  if (!moi || !moi.aJoue) {
    return (
      <Absence
        titre="Aucun pronostic sur ce Grand Prix"
        detail="Tu n'as rien validé pour cette course."
      />
    );
  }

  const juge = moi.total !== null && moi.total !== undefined;

  return (
    <div className="flex flex-col gap-2.5">
      {/* Le bloc rouge de la maquette : le total du joueur sur ce GP, et son
          rang parmi les membres. `total` nul ne vaut pas zéro — c'est « rien
          n'est encore jugé », et l'écrire « 0 » annoncerait un échec qui n'a
          pas eu lieu (règle 4.1). */}
      <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-3 p-5">
        <div className="min-w-0">
          <p className="text-label-sm uppercase text-white/60">Mes points ce GP</p>
          <p className="text-score-lg mt-1.5 text-white">
            {juge ? moi.total : "—"}
          </p>
          <p className="mt-1 text-[11px] text-white/50">
            {juge
              ? `${moi.reussis} prono${moi.reussis > 1 ? "s" : ""} réussi${moi.reussis > 1 ? "s" : ""} sur ${moi.juges}`
              : `${moi.pronostics.length} pronostic${moi.pronostics.length > 1 ? "s" : ""} en attente de validation`}
          </p>
        </div>

        {/* Le rang n'existe qu'entre membres d'un championnat. Sans eux la
            pastille disparaît, et le bloc rouge se referme sur son total —
            `justify-between` n'a alors plus qu'un enfant à pousser. */}
        {avecRang && (
          <div className="rounded-champ shrink-0 bg-white/15 px-4 py-2.5 text-center">
            <p className="text-[26px] leading-none font-medium text-white">
              {moi.rang}
              <span className="text-[15px]">e</span>
            </p>
            <p className="text-label-sm mt-1 text-white/50 uppercase">ce GP</p>
          </div>
        )}
      </div>

      <ul className="flex flex-col gap-2">
        {moi.pronostics.map((pronostic) => (
          <WidgetPronostic key={pronostic.id} pronostic={pronostic} />
        ))}
      </ul>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Section 2 — Résultats du GP                                               */
/* -------------------------------------------------------------------------- */

/**
 * Opacité du drapeau en fond d'une ligne.
 *
 * Mesuré sur les seize drapeaux de la grille 2026, couleur par couleur : le
 * pire substrat est le noir (bande allemande, champ de l'Union Jack), qui
 * compose `#EBEBEB` sur blanc. L'encre `texte` y vaut **14,60:1**, le marron
 * `secondaire` **8,86:1**, le bordeaux `primaire` **9,13:1**.
 *
 * > **`texte-doux` n'y tient pas — 2,39:1.** Aucun texte de ces lignes ne prend
 * > donc le gris. C'est le défaut que le design system §5 signale déjà deux
 * > fois, et une ligne de classement est exactement « une phrase qu'on vient
 * > lire ».
 */
const OPACITE_DRAPEAU = 0.08;

/** Hauteur de la voiture. La planche donne 141,11 × 288,09, soit un rapport de
 *  0,49 : à 42px de haut elle fait 21px de large. Les deux dimensions sont
 *  fixées, donc `boiteLibre` n'a rien à faire ici — `Voiture` ne pose pas
 *  d'`aspect-ratio`, contrairement à `TracesCircuits`. */
const HAUTEUR_VOITURE = "h-[42px] w-[21px]";

/**
 * Le nom d'un pilote, coupé en prénom et nom de famille.
 *
 * **OpenF1 écrit son `full_name` avec le nom de famille en capitales** — « Max
 * VERSTAPPEN ». Le reste de l'application écrit les noms en casse ordinaire, et
 * une colonne de vingt-deux capitales se lit comme un cri. Le nom est donc
 * ramené à l'initiale majuscule **seulement s'il est entièrement en
 * capitales** : un nom déjà bien casé ressort intact, et « Sainz Jr » ne devient
 * pas « Sainz jr ». Chaque morceau séparé par un espace ou un trait d'union est
 * traité à part, sans quoi « Hulkenberg-Schumacher » perdrait sa seconde
 * majuscule.
 */
function couperLeNom(nom) {
  const mots = String(nom ?? "").trim().split(/\s+/).filter(Boolean);
  if (mots.length === 0) return { prenom: "", famille: "" };

  const brut = mots[mots.length - 1];
  const famille = /[a-zà-ÿ]/.test(brut)
    ? brut
    : brut
        .toLocaleLowerCase("fr-FR")
        .replace(/(^|[\s-])(\p{L})/gu, (_, avant, lettre) =>
          avant + lettre.toLocaleUpperCase("fr-FR"),
        );

  return { prenom: mots.slice(0, -1).join(" "), famille };
}

/**
 * Une ligne du classement.
 *
 * De gauche à droite : la position, la voiture de l'écurie, le pilote, les
 * points du championnat du monde. Le drapeau du pilote est en fond, à 8 %.
 *
 * `points_fia` est le seul nombre de l'application qui ne soit pas des points au
 * sens de la règle 4.1 : ce sont les points du championnat du monde (25, 18,
 * 15…). Il s'écrit **« 25 pts »**, sans le mot « FIA », et **jamais avec
 * `formaterPoints`** — c'est cette seconde moitié qui compte maintenant que les
 * deux libellés se ressemblent. `formaterPoints` est le seul habilleur des
 * points de l'app (règle 4.1) ; lui confier ce nombre-ci le ferait entrer dans
 * le vocabulaire des pronostics, et un ajustement futur de l'unité se
 * propagerait ici sans que rien ne le dise.
 *
 * > **Écart signalé (CLAUDE.md §6) : « pts » ne distingue plus les deux
 * > sortes de points, et c'est le contexte seul qui les sépare.** Le mot
 * > « FIA » était ce qui empêchait de lire « 25 pts » comme un gain de
 * > pronostic. La section « Résultats du GP » n'affiche aucun point de
 * > l'application — ni pastille de pari, ni total — donc rien n'y prête à
 * > confusion ; mais les deux unités cohabitent bien sur le même écran, à deux
 * > sections d'écart. Le repli n'est pas gratuit, il est accepté.
 *
 * Le pluriel est porté par la valeur et non écrit en dur : la dixième place
 * rapporte **un** point, et « 1 pts » se serait lu sur chaque Grand Prix.
 *
 * **Un zéro et une absence de classement ne s'écrivent pas pareil.** Un pilote
 * classé qui ne marque pas porte « 0 pt » en encre marron, sans aplat : c'est un
 * fait, et il vaut la peine d'être lu. Un pilote **non classé** — `position`
 * nulle, l'abandon précoce — n'a pas de résultat du tout, et porte un tiret. La
 * même distinction que `NULL` et `0` ailleurs dans l'application.
 */
function LigneClassement({ ligne }) {
  const classe = ligne.position !== null && ligne.position !== undefined;
  const nationalite = nationaliteDuPilote(ligne.driver_number, ligne.pilote);
  const livree = livreeDeLEcurie(ligne.equipe);
  const { prenom, famille } = couperLeNom(ligne.pilote);

  // Trois états, un seul mot. Ils ne peuvent pas se cumuler à l'écran, et
  // l'ordre est celui de la gravité : un disqualifié a d'abord été classé.
  const mention = ligne.disqualifie
    ? "Disqualifié"
    : ligne.non_partant
      ? "Non partant"
      : ligne.abandon
        ? "Abandon"
        : null;

  return (
    <li>
      <article className="rounded-widget bg-surface shadow-carte relative overflow-hidden">
        {/* Le lavis. `absolute inset-0` plutôt qu'un pseudo-élément, comme
            `lueur-haute` et les cartes de vainqueur : un pseudo-élément
            obligerait l'appelant à poser `relative` et `overflow-hidden`
            lui-même. AUCUN `fill` ni `color` ici — la bande noire du drapeau
            allemand n'a pas d'attribut `fill` et l'hériterait. */}
        {nationalite && (
          <span
            aria-hidden="true"
            className="pointer-events-none absolute inset-0"
            style={{ opacity: OPACITE_DRAPEAU }}
          >
            <DrapeauPays code={nationalite.code} className="size-full" />
          </span>
        )}

        <div className="relative flex items-center gap-2.5 px-3 py-2">
          <span
            className={`w-6 shrink-0 text-center text-[16px] font-medium ${
              classe && ligne.position <= 3 ? "text-primaire" : "text-texte"
            }`}
          >
            {classe ? ligne.position : "—"}
          </span>

          {/* La vraie livrée de l'écurie, tirée du nom que sert OpenF1. Un
              libellé inconnu retombe sur la voiture personnalisable plutôt que
              de laisser un trou — la règle de `livreeDuMembre`. */}
          <Voiture
            mode="ecurie"
            ecurie={livree}
            numero={ligne.driver_number ?? ""}
            titre={`Voiture de ${ligne.pilote}`}
            className={`shrink-0 ${HAUTEUR_VOITURE}`}
          />

          <span className="min-w-0 flex-1">
            {prenom && (
              <span className="text-secondaire block truncate text-[11px]">
                {prenom}
              </span>
            )}
            {/* Le nom de famille porte la reconnaissance : plus gros et plus
                gras que le prénom, la hiérarchie par la taille et la graisse
                plutôt que par une couleur de plus. */}
            <span className="text-texte block truncate text-[15px] leading-tight font-medium">
              {famille}
            </span>
            <span className="text-secondaire block truncate text-[11px]">
              {[ligne.equipe, mention].filter(Boolean).join(" · ") || " "}
            </span>
          </span>

          {ligne.points_fia > 0 ? (
            <span className="bg-fond text-secondaire shrink-0 rounded-[10px] px-2 py-1 text-[12px] font-medium">
              {ligne.points_fia} pt{ligne.points_fia > 1 ? "s" : ""}
            </span>
          ) : (
            <span className="text-secondaire shrink-0 text-[12px]">
              {classe ? "0 pt" : "—"}
            </span>
          )}
        </div>
      </article>
    </li>
  );
}

/**
 * Le classement complet de la course, une ligne par pilote, dans l'ordre
 * d'arrivée.
 *
 * **Rien n'est replié.** L'ancien écran mettait le podium en vedette et cachait
 * les vingt autres lignes dans un accordéon, pour ne pas noyer ce qu'on venait
 * lire en premier. La section a maintenant son propre titre et son propre
 * territoire : elle **est** ce qu'on vient lire, et un accordéon fermé sur sa
 * propre section serait une porte devant une pièce vide. Le podium n'a pas non
 * plus de traitement à part — les trois premières positions sont en bordeaux,
 * ce qui suffit à les trouver d'un coup d'œil dans une colonne.
 */
function ClassementCourse({ classement }) {
  if (!classement?.length) {
    return (
      <div className="rounded-carte bg-surface shadow-carte px-5 py-6 text-center">
        <p className="text-corps text-texte font-medium">Classement vide</p>
        <p className="text-corps-sm text-secondaire mx-auto mt-1 max-w-[32ch]">
          La course est enregistrée mais son classement ne comporte encore aucune
          position.
        </p>
      </div>
    );
  }

  return (
    <ul className="flex flex-col gap-2">
      {classement.map((ligne) => (
        <LigneClassement
          key={ligne.driver_number ?? `${ligne.position}-${ligne.pilote}`}
          ligne={ligne}
        />
      ))}
    </ul>
  );
}

/* -------------------------------------------------------------------------- */
/*  Section 3 — Le classement du championnat                                  */
/* -------------------------------------------------------------------------- */

/**
 * Une rangée de membre, dépliable sur ses pronostics.
 *
 * La maquette pose un chevron au bout de la ligne sans dire ce qu'il ouvre. Il
 * déplie ici les pronostics **sous** la ligne, comme le sélecteur de pilote de
 * l'étape 5 : le joueur garde le reste du classement sous les yeux, et le geste
 * de retour ne se fait pas voler par une couche qui s'interpose.
 */
function LigneMembre({ ligne, estMoi, avecPhotos = false }) {
  const [ouvert, setOuvert] = useState(false);

  return (
    <li className="t-acc" data-open={ouvert}>
      <button
        type="button"
        onClick={() => setOuvert((etat) => !etat)}
        aria-expanded={ouvert}
        className="pressable min-h-tactile flex w-full items-center gap-3 py-2 text-left"
      >
        <span
          className={`w-5 shrink-0 text-center text-[14px] font-medium ${
            ligne.rang <= 3 ? "text-primaire" : "text-texte-doux"
          }`}
        >
          {ligne.rang}
        </span>

        {/* La vraie voiture du membre (étape 8), servie par la route depuis
            l'étape 9, livrée d'écurie comprise. La largeur suit la boîte
            englobante du dessin : l'ancienne `viewBox` portait sa moitié en
            marge vide, et 28px n'en montraient que 14. */}
        <Voiture
          {...livreeDuMembre(ligne)}
          numero={ligne.numero ?? ""}
          titre={`Voiture de ${ligne.pseudo}`}
          className="h-[34px] w-[17px] shrink-0"
        />

        {/* La pastille d'identité, collée au pseudo. Elle est en `xs` — 28px —
            parce que cette rangée porte déjà cinq choses : un rang, une voiture,
            un nom, un score et un chevron. À 36px elle prendrait sa place sur le
            seul élément qui en manque, le pseudo.

            Même règle qu'au classement du championnat : la colonne n'apparaît
            que si quelqu'un, dans ce Grand Prix, a une photo — sinon la rangée
            reste exactement celle d'avant cette version. */}
        {avecPhotos && (
          <Pastille
            nom={ligne.pseudo}
            graine={ligne.profil_id}
            photo={ligne.avatar_url}
            taille="xs"
          />
        )}

        <span className="min-w-0 flex-1">
          <span className="text-texte block truncate text-[14px] font-medium">
            {ligne.pseudo}
            {estMoi && <span className="text-primaire"> · Toi</span>}
          </span>
          <span className="text-texte-doux block truncate text-[11px]">
            {ligne.aJoue
              ? `${ligne.reussis} réussi${ligne.reussis > 1 ? "s" : ""} sur ${ligne.juges}`
              : "Pas de pronostic sur ce GP"}
          </span>
        </span>

        <span className="text-primaire shrink-0 text-[15px] font-medium">
          {ligne.total === null || ligne.total === undefined
            ? "En attente"
            : formaterPoints(ligne.total)}
        </span>

        <IconeChevronAccordeon className="t-acc-chevron text-texte-doux size-4 shrink-0" />
      </button>

      <div className="t-acc-panel">
        <div className="t-acc-panel-inner">
          {ligne.aJoue ? (
            <ul className="mb-1 ml-8 flex flex-col">
              {ligne.pronostics.map((pronostic) => (
                <li
                  key={pronostic.id}
                  className="flex items-center justify-between gap-2 py-1.5"
                >
                  <span className="min-w-0">
                    <span className="text-texte-doux block truncate text-[10px] font-medium tracking-[0.3px] uppercase">
                      {pronostic.libelle ?? pronostic.type}
                    </span>
                    <span className="text-texte block truncate text-[13px]">
                      {choixDuPronostic(pronostic)}
                    </span>
                  </span>

                  <span className="flex shrink-0 items-center gap-2">
                    <PastillePoints
                      pointsGagnes={pronostic.points_gagnes}
                      points={pronostic.points}
                    />
                    <Verdict pointsGagnes={pronostic.points_gagnes} />
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-texte-doux mb-1 ml-8 py-1.5 text-[13px]">
              Ce membre n'a rien pronostiqué sur ce Grand Prix.
            </p>
          )}
        </div>
      </div>
    </li>
  );
}

/* -------------------------------------------------------------------------- */
/*  Squelette                                                                 */
/* -------------------------------------------------------------------------- */

/** La silhouette suit la hauteur réelle de ce qui arrive (§8 du design
 *  system) : un en-tête de section, le bloc rouge, deux widgets de pronostic,
 *  puis quatre rangées de classement. Sans quoi l'écran sursaute à l'arrivée
 *  des données. */
function SqueletteResultats() {
  return (
    <div className="flex flex-col gap-3">
      <Barre largeur="w-1/3" hauteur="h-4" />

      {/* Le bloc rouge garde sa couleur : c'est la surface, pas le contenu, et
          la voir changer au moment de la révélation ferait clignoter l'écran. */}
      <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-3 p-5">
        <div className="flex-1">
          <div className="h-2.5 w-24 rounded-full bg-white/25" />
          <div className="rounded-champ mt-3 h-9 w-20 bg-white/25" />
          <div className="mt-2.5 h-2.5 w-32 rounded-full bg-white/20" />
        </div>
        <div className="rounded-champ h-14 w-16 bg-white/15" />
      </div>

      <Pave className="h-[54px]" arrondi="rounded-widget" />
      <Pave className="h-[54px]" arrondi="rounded-widget" />

      <Barre largeur="w-2/5" hauteur="h-4" />

      <Carte>
        {[0, 1, 2, 3].map((rang) => (
          <Rangee key={rang} />
        ))}
      </Carte>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  L'écran                                                                   */
/* -------------------------------------------------------------------------- */

export default function ResultatsGp() {
  const { id: championnatId, gpId } = useParams();
  const { utilisateur } = useAuth();

  const [tentative, setTentative] = useState(0);

  const cle = utilisateur
    ? cleResultats(utilisateur.id, gpId, championnatId)
    : null;
  const chargeur = useCallback(
    (signal) => chargerResultatsGp(gpId, championnatId, utilisateur?.id, signal),
    [gpId, championnatId, utilisateur?.id],
  );
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const gp = donnees?.grand_prix ?? null;
  const depart = formaterDepart(gp?.date_course);
  const retour = championnatId ? `/championnats/${championnatId}` : "/accueil";

  const membres = classerLesMembres(donnees?.membres);
  // Une seule question pour toute la liste, la même qu'au classement du
  // championnat et qu'à la vue piste : quelqu'un a-t-il une photo ?
  const avecPhotos = membres.some((ligne) => Boolean(ligne.avatar_url));
  // `null` veut dire « pas demandé » (aucun championnat dans l'URL), jamais
  // « championnat vide » — la convention de la route, tenue par l'écran.
  const avecChampionnat =
    donnees?.membres !== null && donnees?.membres !== undefined;

  /* « Mes résultats » a deux sources selon la porte d'entrée, et **une seule
     mise en forme**. Avec un championnat, ma ligne est déjà dans le classement
     des membres. Sans, elle est fabriquée à partir des seuls pronostics lus
     sous RLS — et passe par le MÊME `classerLesMembres`, qui reste le seul
     propriétaire du total, du nombre de jugés, du nombre de réussis et du
     « a joué ». Deux calculs écrits séparément auraient fini par annoncer deux
     totaux différents pour le même joueur sur le même Grand Prix. */
  const moi = avecChampionnat
    ? (membres.find((ligne) => ligne.profil_id === utilisateur?.id) ?? null)
    : donnees?.mes_pronostics
      ? (classerLesMembres([
          { profil_id: utilisateur?.id, pronostics: donnees.mes_pronostics },
        ])[0] ?? null)
      : null;

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  // Sortie de secours : sans résultats lisibles, l'écran ne doit surtout pas
  // être un cul-de-sac. Le cache déjà servi l'emporte sur l'échec.
  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Résultats" retourVers={retour} />
        </Bloc>
        <Bloc rang={2}>
          <BlocErreur echec={echec} onReessayer={reessayer} tentative={tentative} />
        </Bloc>
      </Ecran>
    );
  }

  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete
          titre={gp?.nom ?? "Résultats"}
          retourVers={retour}
          libelleRetour={championnatId ? "Championnat" : "Accueil"}
          sousTitre={
            gp
              ? [donnees?.disponible ? "Terminé" : "À venir", depart.courte]
                  .filter(Boolean)
                  .join(" · ")
              : null
          }
        />
      </Bloc>

      <div className="mt-1 flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteResultats />}
          >
            {donnees && (
              <div className="flex flex-col gap-3">
                {/* ---- Section 1 : Mes résultats ---- */}
                <TitreSection
                  titre="Mes résultats"
                  sousTitre="Ce que tes pronostics ont rapporté"
                />
                <MesResultats
                  moi={moi}
                  avecRang={avecChampionnat}
                  connecte={Boolean(utilisateur)}
                  echec={Boolean(donnees.mes_pronostics_echec)}
                />

                {/* ---- Section 2 : Résultats du GP ----
                    `mt-3` s'ajoute au `gap-3` du conteneur : 24px au lieu de 12
                    au-dessus d'un changement de sujet. L'espace est la moitié
                    du séparateur, le filet du titre est l'autre. */}
                <div className="mt-3">
                  <TitreSection
                    titre="Résultats du GP"
                    sousTitre={
                      donnees.disponible
                        ? "Classement officiel de la course"
                        : "Classement pas encore publié"
                    }
                  />
                </div>

                {donnees.disponible ? (
                  <ClassementCourse classement={donnees.classement} />
                ) : (
                  /* Données manquantes, pas une erreur : la course n'a pas
                     encore de classement publié. Le message dit quand revenir
                     plutôt que de laisser l'écran vide. */
                  <div className="rounded-bloc bg-primaire shadow-bloc p-5">
                    <p className="text-label-sm uppercase text-white/60">
                      Résultats
                    </p>
                    <p className="mt-2 text-[20px] font-medium text-white">
                      Résultats pas encore disponibles
                    </p>
                    <p className="text-corps-sm mt-1.5 text-white/60">
                      {depart.heure
                        ? `Départ ${depart.jour.toLowerCase()} à ${depart.heure}. Les points sont attribués dans les deux heures qui suivent.`
                        : "L'horaire de la course n'est pas encore annoncé. Les points sont attribués dans les deux heures qui suivent le départ."}
                    </p>
                  </div>
                )}

                {/* ---- Section 3 : le championnat ----
                    Conservée, et signalée en tête de fichier : la demande ne
                    demandait pas de la retirer. */}
                {avecChampionnat && (
                  <>
                    <div className="mt-3">
                      <TitreSection
                        titre="Classement ce GP"
                        sousTitre="Ce que chaque membre y a marqué"
                      />
                    </div>
                    <div className="rounded-carte bg-surface shadow-carte px-4 py-2">
                      <ul>
                        {membres.map((ligne) => (
                          <LigneMembre
                            key={ligne.profil_id}
                            ligne={ligne}
                            estMoi={ligne.profil_id === utilisateur?.id}
                            avecPhotos={avecPhotos}
                          />
                        ))}
                      </ul>
                    </div>
                  </>
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        {/* Un échec survenu alors que le cache avait déjà quelque chose : le
            contenu reste, l'échec s'ajoute dessous avec son bouton. */}
        {echec && donnees && (
          <Bloc rang={3}>
            <BlocErreur
              echec={echec}
              onReessayer={reessayer}
              tentative={tentative}
            />
          </Bloc>
        )}

        <div className="min-h-3 flex-1" />
      </div>
    </Ecran>
  );
}
