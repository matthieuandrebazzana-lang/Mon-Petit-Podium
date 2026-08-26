import { useCallback, useState } from "react";
import { Link } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Pastille from "../composants/Pastille.jsx";
import PhotoChampionnat from "../composants/PhotoChampionnat.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { Pave } from "../composants/Squelette.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import TraceCircuitGp, {
  aUnTrace,
  slugCircuit,
} from "../composants/TracesCircuits.jsx";
import {
  APPARENCE_REPLI,
  drapeauDuGp,
  FondDrapeau,
  VoileDrapeau,
} from "../composants/DrapeauxGP.jsx";
import { IconeChevronDroit, IconeMembres } from "../composants/Icones.jsx";
import IconeCreer from "../composants/icones/IconeCreer.jsx";
import IconeRejoindre from "../composants/icones/IconeRejoindre.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { listerMesChampionnats } from "../lib/championnats.js";
import { couleurChampionnat, tonalites } from "../lib/couleurs.js";
import { chargerAccueilGp, cleAccueilGp } from "../lib/pronostics.js";
import { useDonnees } from "../lib/useDonnees.js";
import { useIdentiteCourante } from "../lib/usePseudo.js";
import { cotesArretees } from "../lib/calendrier.js";
import { formaterDepart } from "../lib/format.js";
import { useEtatPronostics } from "../lib/useFermeture.js";
import { APP_VERSION } from "../config.js";

/**
 * Grands Prix restants dans la saison 2026, du GP des Pays-Bas à Abu Dhabi.
 *
 * En dur, et pour une raison précise : Unibet n'expose que le Grand Prix
 * suivant (section 3.1), donc `public.grands_prix` ne contient que ce que le
 * scraper a rencontré — un seul GP à ce jour. Le décompte lu en base annonçait
 * donc « 1 Grand Prix restant » au milieu d'une saison qui en compte douze.
 *
 * TODO: dynamique quand tous les GP sont en base.
 */
const GP_RESTANTS = 12;

/**
 * Hauteur de la bande du tracé de circuit, en pixels.
 *
 * **Écrite une fois et partagée avec le squelette**, jamais recopiée aux deux
 * endroits. Sans cela l'accueil sursauterait de la différence à l'arrivée des
 * données — c'est exactement le défaut corrigé sur les cartes de championnat en
 * version `0.14.0`, où la silhouette a dû suivre la carte à 120px.
 */
const HAUTEUR_TRACE = 160;

/**
 * Bloc rouge « PROCHAIN GP » de la maquette 04.
 *
 * Le GP et les pronostics du joueur sont lus **directement dans Supabase**,
 * sous les politiques de lecture des étapes 4 et 5, et non par l'API :
 * l'accueil est le premier écran de l'app, et lui faire attendre le réveil de
 * Railway pour afficher son bloc principal serait le pire endroit où payer ce
 * délai. Les deux lectures partagent le même passage dans le cache
 * *stale-while-revalidate* — aucun appel réseau supplémentaire ne bloque
 * l'affichage.
 *
 * **La clé de cache porte l'identifiant du compte.** Le prochain Grand Prix est
 * le même pour tout le monde, mais l'état des pronostics ne l'est pas : deux
 * personnes qui se relaient sur le même téléphone ne doivent jamais hériter du
 * bouton de l'autre, fût-ce le temps d'un rafraîchissement.
 *
 * **`previsualisation` arrive par prop et non par `useAuth`, et ce n'est pas un
 * détour.** Ce composant est exporté nommément précisément pour être rendu hors
 * navigateur, sans monter `AuthProvider` ; `useAuth` lève dès qu'il ne trouve
 * pas de contexte, et l'appeler ici rendrait ce rendu impossible. Le drapeau est
 * donc lu par `Accueil`, qui vit déjà dans le contexte, et descend comme une
 * donnée ordinaire — par défaut `false`, c'est-à-dire la règle ordinaire.
 */
export function BlocProchainGp({ profilId, previsualisation = false }) {
  const chargeur = useCallback((signal) => chargerAccueilGp(profilId, signal), [profilId]);
  const { donnees, chargement } = useDonnees(
    profilId ? cleAccueilGp(profilId) : null,
    chargeur,
  );

  const gp = donnees?.gp ?? null;
  const etat = useEtatPronostics(gp);

  if (chargement && !gp) {
    // Le squelette garde l'aplat rouge du bloc et n'en griser que le contenu :
    // c'est le seul aplat de couleur de l'accueil, et le voir passer au gris
    // puis revenir au rouge ferait clignoter l'écran d'entrée de l'app.
    return (
      <div
        className="rounded-bloc bg-primaire shadow-aplat relative overflow-hidden p-5"
        aria-hidden="true"
      >
        <div className="lueur-haute pointer-events-none absolute inset-0" />
        <div className="relative">
          <div className="mb-3 flex items-center justify-between gap-3">
            <div className="h-6 w-24 rounded-full bg-white/25" />
            <div className="h-3 w-20 rounded-full bg-white/20" />
          </div>
          {/* Le nom du Grand Prix est centré : sa silhouette l'est aussi, sinon
              l'écran se recale latéralement à l'arrivée des données. */}
          <div className="mx-auto h-8 w-48 rounded-full bg-white/25" />
          {/* La bande du tracé, à sa hauteur réelle. C'est la moitié du bloc :
              l'omettre ferait sauter l'accueil de 160px au moment précis où le
              joueur le regarde.

              Elle n'est plus assombrie : le bloc chargé n'assombrit plus sa
              bande non plus, et un rectangle sombre ici annoncerait une rupture
              que la surface d'arrivée n'a pas. Elle garde une silhouette claire,
              comme les autres formes du squelette. */}
          <div
            className="mt-4 -mx-5 bg-white/10"
            style={{ height: `${HAUTEUR_TRACE}px` }}
          />
          <div className="mt-4 grid grid-cols-2 gap-2">
            <div className="rounded-champ h-[54px] bg-white/12" />
            <div className="rounded-champ h-[54px] bg-white/12" />
          </div>
          <div className="rounded-champ mt-2.5 h-tactile w-full bg-white/15" />
        </div>
      </div>
    );
  }

  // Aucun GP en base : le scraper n'a pas encore tourné, ou la saison est
  // terminée. Le bloc garde sa place dans la composition plutôt que de laisser
  // l'accueil s'effondrer d'un cran à chaque intersaison.
  if (!gp) {
    return (
      <div className="rounded-bloc bg-primaire shadow-aplat relative overflow-hidden p-5">
        <div className="lueur-haute pointer-events-none absolute inset-0" />
        <div className="relative">
          <p className="text-label-sm uppercase text-white/60">Saison 2026</p>
          <p className="text-titre mt-2 text-white">Pronostics F1 entre amis</p>
          <p className="text-corps-sm mt-1 text-white/70">
            Aucun Grand Prix ouvert aux pronostics pour l'instant. Les cotes sont
            relevées le samedi, après les qualifications.
          </p>
        </div>
      </div>
    );
  }

  const depart = formaterDepart(gp.date_course);

  // **Trois destinations pour un même bouton**, et le libellé suit toujours la
  // destination : un bouton nommé « Pronostiquer » qui ouvre autre chose serait
  // une promesse fausse.
  //
  // - Grand Prix **couru** (étape 9) — les résultats. Il n'y a plus de
  //   pronostics à saisir, et c'est l'écran que tout le monde ouvre le dimanche
  //   soir. C'est aussi le seul cas où le bloc n'annonce pas un GP à venir : le
  //   libellé du bandeau change avec lui.
  // - Pronostics déjà enregistrés, ou fermeture passée — le récapitulatif.
  // - Sinon — le tableau des cotes.
  const couru = donnees?.couru === true;
  const versRecap = !couru && (etat.ferme || donnees?.aPronostique === true);

  // **Le bouton des pronostics exige DEUX conditions réunies** : des cotes
  // figées, et des qualifications déjà courues. `cotesArretees` porte la règle
  // pour les trois surfaces qui l'appliquent — voir `lib/calendrier.js`.
  //
  // Tant qu'un Grand Prix est en `a_venir`, le scraper n'a rien relevé : le
  // tableau des cotes est vide et le récapitulatif n'a rien à récapituler. Et
  // tant que les qualifications ne sont pas courues, la grille de départ n'est
  // pas définitive : des cotes figées trop tôt par un déclenchement manuel du
  // scraper ne valent rien (règle 4.3). Dans les deux cas le bouton serait une
  // promesse fausse, celle-là même que le libellé variable de ce bloc cherche à
  // éviter depuis la version `0.5.1`.
  //
  // Il est donc **retiré, pas grisé et pas remplacé** : le widget garde sa
  // place, son drapeau, son tracé, sa date et son compte à rebours — tout ce
  // qu'il dit reste vrai avant les qualifications, et c'est bien à ce moment-là
  // qu'on vient voir quand part la course.
  //
  // Les deux champs viennent de `donnees.gp`, déjà chargé pour ce bloc : aucune
  // lecture supplémentaire, et surtout aucune seconde source qui pourrait
  // diverger.
  //
  // **Le bouton des résultats, lui, n'est pas concerné.** Un Grand Prix couru
  // porte le statut `termine`, jamais `cotes_figees` : lui appliquer la règle
  // fermerait l'accès aux résultats le dimanche soir, c'est-à-dire au moment où
  // tout le monde ouvre l'application.
  //
  // **Le mode prévisualisation lève cette condition, et lui seul.** Il vaut
  // `false` pour tout le monde sauf un administrateur qui a allumé ses deux
  // interrupteurs dans la session courante : la règle ci-dessus reste donc
  // entière pour les membres, le statut en base n'est pas touché, et le job du
  // samedi continue de le faire basculer normalement. La pastille
  // « Prévisualisation » est ce qui empêche de prendre ce bouton pour le vrai.
  const avecBouton = couru || cotesArretees(gp) || previsualisation;

  const destination = couru
    ? `/grands-prix/${gp.id}/resultats`
    : `/grands-prix/${gp.id}/${versRecap ? "recap" : "cotes"}`;
  const libelle = couru
    ? "Voir les résultats"
    : versRecap
      ? "Voir mes pronos"
      : "Pronostiquer";

  // Le bloc est la pièce maîtresse de l'écran d'entrée : il porte donc deux
  // cases de statut plutôt qu'une phrase. Un chiffre posé sous son label se lit
  // d'un coup d'œil, là où « Pronos ouverts · Fermeture dans 2j 14h 32min »
  // demande de lire une ligne entière pour en extraire la même information.
  const cases = couru
    ? [
        { label: "Course", valeur: "Terminée" },
        { label: "Points", valeur: "Attribués" },
      ]
    : [
        { label: "Départ", valeur: depart.heure ?? "À confirmer" },
        // **La seconde case ne choisit plus son échéance.** Elle disait
        // « Fermeture dans » sur tous les Grands Prix, y compris ceux dont les
        // pronostics n'étaient pas encore ouverts : elle annonçait la fermeture
        // d'une chose qui n'avait pas commencé, et treize jours de délai pour
        // agir là où il n'y avait rien à faire. Le libellé et la valeur
        // viennent maintenant d'`etatPronostics`, qui porte les deux échéances
        // du week-end et sert aussi les trois horloges — voir
        // `lib/calendrier.js`.
        //
        // **C'est la même condition que le bouton juste dessous** : les deux
        // lisent `cotesArretees`. Une case « Fermeture dans » au-dessus d'un
        // bloc sans bouton de pronostics serait une contradiction visible d'un
        // coup d'œil.
        { label: etat.label, valeur: etat.texte ?? etat.substitut },
      ];

  // Le pays hôte donne à la fois le tracé du circuit et les couleurs du bloc.
  // Une seule normalisation du nom pour les deux : ils partagent la même clé, et
  // la faire deux fois laisserait les deux tables se désynchroniser sur un
  // libellé qu'Unibet aurait renommé.
  const slug = slugCircuit(gp.nom);
  const drapeau = drapeauDuGp(slug) ?? APPARENCE_REPLI;
  // La bande du tracé n'existe que s'il y a un tracé à y mettre. Sans ce test,
  // un Grand Prix hors planche laisserait 160px de fond assombri au milieu du
  // bloc — un trou, là où le filigrane d'avant se contentait de disparaître.
  const trace = aUnTrace(slug);

  return (
    <div
      className={`rounded-bloc shadow-aplat relative overflow-hidden p-5 ${
        drapeau.fond ? "" : "bg-primaire"
      }`}
      style={drapeau.fond ? { background: drapeau.fond } : undefined}
    >
      {/* Le drapeau dessiné, quand le pays en a un — **le calque le plus bas**.
          Tout ce qui suit doit le recouvrir : la lumière spéculaire, le voile et
          l'assombrissement. Posé plus haut, il ramènerait ses bandes claires
          par-dessus le voile et le texte y retomberait sous les 3:1. */}
      <FondDrapeau apparence={drapeau} />

      {/* La lumière spéculaire d'/apple-design §12 : un aplat plein est une
          surface morte, ce galbe très doux lui donne une source lumineuse. */}
      <div
        aria-hidden="true"
        className="lueur-haute pointer-events-none absolute inset-0"
      />
      {/* Le voile, **par-dessus tout ce qui éclaircit** et sous le seul contenu.
          C'est ce qui rend la garantie de 3:1 inconditionnelle sur le texte : la
          lumière spéculaire passe dessous, donc elle ne peut pas remonter la
          luminance là où le texte la croise. Son opacité est calculée par
          drapeau, jamais choisie.

          Le tracé, lui, est passé **au-dessus** de ce voile en devenant un
          élément de la composition. Ce n'est pas un contournement de la garantie
          mais sa conséquence : le tracé occupe désormais sa propre bande, il ne
          croise plus aucun texte, et le risque que la version `0.15.0` décrivait
          (ses 15 % de blanc faisant retomber une bande voilée à 2,71:1 sous le
          nom du Grand Prix) n'a plus de support. Le voile continue de peindre la
          bande du tracé, et c'est ce qui rend le trait blanc lisible sur les
          drapeaux clairs. */}
      <VoileDrapeau voile={drapeau.voile} />

      {/* L'assombrissement de 15 %, **sur tout le bloc et non sur la seule bande
          du tracé**, où il vivait jusqu'ici.

          C'est la correction de cette version. Sur un drapeau à bande répétée —
          les Pays-Bas en sont le cas d'école, rouge / blanc / bleu / rouge — une
          bande assombrie sur 160px au milieu du bloc coupait la surface en deux :
          la bande rouge du haut paraissait plus vive que celle du bas, et l'œil
          lisait un défaut de calage plutôt qu'une intention. Une seule surcouche
          uniforme fait disparaître la rupture, le drapeau reste d'une seule
          pièce, et chaque couleur garde exactement la même valeur du haut au bas
          du bloc.

          Elle est posée **au-dessus du voile et sous le contenu**, à la place
          exacte qu'occupait celle de la bande : elle ne fait donc qu'assombrir
          davantage le substrat du texte, et la garantie de 3:1 de la version
          `0.15.0` en sort renforcée, jamais entamée.

          **Elle ne s'applique qu'aux blocs peints par un drapeau.** Le repli
          bordeaux n'a ni bande ni rupture à corriger, et le CLAUDE.md demande
          qu'il garde exactement l'aspect qu'il avait — le voiler d'un cran de
          plus l'éteindrait pour rien. Table des drapeaux et table des tracés
          portant les mêmes douze slugs, « peint par un drapeau » et « a un
          tracé » désignent le même ensemble. */}
      {drapeau.fond && (
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-black/15"
        />
      )}

      <div className="relative">
        {/* Zone 1 — l'en-tête, inchangé. */}
        <div className="mb-3 flex items-center justify-between gap-3">
          <span
            className={`text-label-sm rounded-full px-2.5 py-1 uppercase ${drapeau.pastille} ${drapeau.texte}`}
          >
            {couru ? "Dernier GP" : "Prochain GP"}
          </span>
          <span
            className={`shrink-0 text-[11px] ${drapeau.texteDoux} ${drapeau.ombreTexte}`}
          >
            {depart.courte ?? "Date à confirmer"}
          </span>
        </div>

        {/* Zone 2 — le nom du Grand Prix, centré au-dessus de son circuit. Les
            deux se lisent alors comme un seul objet, titre et illustration, ce
            qu'un nom aligné à gauche au-dessus d'un dessin centré ne donnerait
            pas.

            26px est la taille demandée. Elle n'a pas de jeton : l'échelle de la
            section 5 passe de 15px (corps) à 28px (titre de page), et celui-ci
            n'est pas un titre de page — l'écran en a déjà un. Le crénage négatif
            est celui qu'/apple-design §15 impose au-delà de 24px : sans lui, les
            lettres d'un titre s'éloignent à mesure qu'il grandit.

            Sur un drapeau à bandes, le nom en traverse la couture — d'où l'ombre
            portée, qui lui garde son contour des deux côtés. */}
        <p
          className={`truncate text-center text-[26px] leading-tight font-medium tracking-[-0.02em] ${drapeau.texte} ${drapeau.ombreTexte}`}
        >
          {gp.nom}
        </p>

        {/* Zone 3 — le circuit, et non plus un filigrane. C'est le vrai tracé du
            pays hôte (`assets/traces.svg`) : Zandvoort pour les Pays-Bas, Monza
            pour l'Italie.

            Trois points de mise en œuvre :

            - `-mx-5` annule le rembourrage du bloc : la bande touche les deux
              bords, ce qui en fait un registre horizontal de la composition
              plutôt qu'une image posée dans une marge. `overflow-hidden` sur le
              bloc lui rend ses coins arrondis.
            - **La bande n'a plus son propre assombrissement** : les 15 % sont
              passés sur le conteneur du bloc (voir plus haut), où ils rendent
              exactement le même service au trait blanc — le substrat sous le
              tracé est assombri de la même quantité qu'avant, simplement sans
              couper le drapeau en deux. Un trait blanc à 60 % sur la bande
              blanche du drapeau néerlandais, déjà voilée, reste donc à 2,70:1,
              et à 3,80:1 sous `prefers-contrast: more`. Sur les drapeaux
              sombres (Las Vegas, Abu Dhabi) il est à 7:1 et plus.
            - `boiteLibre` coupe le rapport de forme que le composant pose en
              ligne, parce que la bande fixe ici les **deux** dimensions.
              `xMidYMid meet` met alors chaque circuit à l'échelle dans cette
              boîte et le centre : Bakou, 3,4 fois plus large que haut, remplit
              la largeur ; Zandvoort, presque carré, remplit la hauteur. Chacun
              garde sa vraie forme au lieu d'être étiré pour occuper la même
              surface que son voisin.

            L'épaisseur passe de 2,5 à 3px : à cette taille, le trait d'un
            filigrane paraîtrait un cheveu. Elle reste en pixels d'écran
            (`non-scaling-stroke`), donc identique d'un circuit à l'autre. */}
        {trace && (
          <div
            className="pointer-events-none -mx-5 mt-4"
            style={{ height: `${HAUTEUR_TRACE}px` }}
          >
            <TraceCircuitGp
              slug={slug}
              epaisseur={3}
              boiteLibre
              className="h-full w-full text-white/60"
            />
          </div>
        )}

        {/* Zone 4 — les deux cases de statut, inchangées. */}
        <div className="mt-4 grid grid-cols-2 gap-2">
          {cases.map((donnee) => (
            <div
              key={donnee.label}
              className={`rounded-champ px-3.5 py-2.5 ${drapeau.surface}`}
            >
              <p
                className={`text-label-sm truncate uppercase ${drapeau.texteDoux}`}
              >
                {donnee.label}
              </p>
              <p className="mt-1 truncate text-[15px] font-medium text-white">
                {/* Le compte à rebours change toutes les secondes dans la
                    dernière heure : l'échange en place évite le clignotement
                    que donnerait un simple remplacement de texte. */}
                <TexteEchange valeur={donnee.valeur} />
              </p>
            </div>
          ))}
        </div>

        {/* Zone 5 — le bouton, conditionné aux cotes figées (voir plus haut).
            Absent, il ne laisse rien derrière lui : la marge est portée par le
            bouton et non par la zone au-dessus, donc le bloc se referme de
            lui-même sur les cases de statut. */}
        {avecBouton && (
          <Link
            to={destination}
            className="rounded-champ bg-surface text-primaire pressable min-h-tactile mt-2.5 flex items-center justify-center px-4 text-center text-[15px] font-medium"
          >
            {/* Le cache peut avoir servi l'état d'avant la dernière validation :
                le libellé change alors sous les yeux du joueur, une fois la
                lecture fraîche revenue. TexteEchange (transitions-dev 04) le
                remplace en place plutôt que de le laisser clignoter. */}
            <TexteEchange valeur={libelle} />
          </Link>
        )}
      </div>
    </div>
  );
}

/** Carte de championnat de la maquette 04, refondue en aplat de couleur.
 *
 * Exportée depuis l'étape 10 : l'écran de l'onglet Championnats sert la même
 * liste, et deux cartes dessinées séparément auraient divergé au premier
 * ajustement. C'est aussi ce qui fait qu'un championnat se reconnaît d'un écran
 * à l'autre — d'autant plus depuis qu'il porte une couleur.
 *
 * La couleur vient de `couleurChampionnat` et **jamais du rang** : elle doit
 * rester la même quand le championnat change de place dans la liste, sans quoi
 * deux voisins échangeraient leurs couleurs à la première adhésion. C'est la
 * règle déjà tenue par les livrées de voiture depuis l'étape 7.
 *
 * **Le chiffre affiché est désormais le vrai rang du membre dans ce
 * championnat**, et non plus la position de la carte dans la liste. C'est le
 * point que la version `0.12.0` laissait ouvert : le rang existait depuis
 * l'étape 7 mais coûtait un appel Railway par championnat. `GET
 * /championnats/moi` le sert maintenant lui-même, en une seule réponse.
 *
 * La jauge du bas dit la même chose autrement : où en est le membre par rapport
 * au leader. Elle est vide avant le premier Grand Prix, quand tout le monde est
 * encore à zéro — ce qui est exact, et bien plus honnête qu'une barre à moitié
 * pleine posée là pour faire joli.
 *
 * Le code d'invitation quitte la carte au profit de la saison : il reste sur
 * l'écran du championnat, où l'on va quand on veut le partager, et cette
 * sous-ligne devait laisser la place à ce que la carte est venue dire.
 */
export function CarteChampionnat({ championnat }) {
  const couleur = couleurChampionnat(championnat);
  const ton = tonalites(couleur.hex);

  const membres = championnat.nombre_membres ?? 0;
  const position = championnat.position ?? null;

  // La fraction du leader. Trois cas, et le troisième est le plus fréquent en
  // début de saison : personne n'a marqué, la jauge reste vide pour tout le
  // monde. La division n'a alors jamais lieu.
  const leader = position?.points_leader ?? 0;
  const fraction =
    leader > 0 ? Math.min(1, Math.max(0, (position?.mes_points ?? 0) / leader)) : 0;

  return (
    <Link
      to={`/championnats/${championnat.id}`}
      className={`rounded-carte shadow-aplat pressable-large relative flex min-h-[120px] flex-col justify-between gap-3 overflow-hidden p-4 ${couleur.fond}`}
    >
      {/* Le damier d'abord, la lueur par-dessus : la lueur est un galbe de
          lumiere qui doit porter sur la surface FINIE, texture comprise. Les
          deux sont decoratifs et hors du chemin du doigt. */}
      <span
        aria-hidden="true"
        className="motif-damier pointer-events-none absolute inset-0"
      />
      <span
        aria-hidden="true"
        className="lueur-haute pointer-events-none absolute inset-0"
      />

      <span className="relative flex items-start justify-between gap-3">
        <span className="min-w-0 flex-1">
          <span
            className={`block truncate text-[20px] leading-tight font-medium ${ton.texte}`}
          >
            {championnat.nom}
          </span>
          <span className={`mt-1.5 block text-[12px] ${ton.texteDoux}`}>
            {membres} {membres > 1 ? "membres" : "membre"} · Saison 2026
          </span>
        </span>

        {/* Le rang, en très grand et en retrait. Il n'est rendu que s'il est
            connu : un tiret sous le mot « classement » ne dirait rien de plus
            que la colonne absente, et laisserait croire à une donnée manquante
            là où c'est le réveil de Railway qui n'a pas encore répondu.

            **Format position/total depuis la version `0.48.0`** — « 1/3 » et
            non plus « 1 ». Un rang seul ne dit pas s'il est bon : premier sur
            trois et premier sur douze ne valent pas la même chose, et c'est
            l'effectif qui fait la différence. Il était déjà sur la carte, dans
            la sous-ligne « N membres », mais à douze pixels et à l'autre bout
            de la rangée — trop loin du chiffre pour être lu avec lui.

            **Les deux nombres ne sont pas de la même taille, et c'est la
            hiérarchie qui le décide** : 48px pour la position, qui est la
            réponse, 24px pour le total, qui est le contexte. Deux chiffres de
            même corps se liraient comme une date. C'est aussi ce que prescrit
            la règle de vibrance du design system — la hiérarchie passe par la
            taille et la graisse, jamais par l'opacité seule.

            Le total emprunte l'encre secondaire `texteDoux`, mesurée : sur le
            plus clair des six aplats (terreau), sous le damier et la lueur,
            elle tient **4,97:1** — au-dessus du plancher AA d'un texte
            ordinaire, et le total est ici du grand texte (3:1). */}
        {/* La photo, entre le nom et le rang — la « zone milieu-droite » de la
            demande. Elle est **centrée sur la rangée** (`self-center`) alors que
            le nom et le rang s'alignent par le haut : un carré de cinquante-six
            pixels calé sur la ligne de base d'un nom de vingt paraîtrait tomber.

            Le composant s'efface tout seul sans photo, et la carte retrouve
            alors exactement la composition d'avant cette version : rien ne
            réserve sa place, aucune gouttière ne subsiste. */}
        <PhotoChampionnat
          url={championnat.photo_url}
          nom={championnat.nom}
          taille={56}
          className="self-center"
        />

        {position && (
          <span className="shrink-0 text-right">
            <span
              aria-hidden="true"
              className="flex items-baseline justify-end"
            >
              <span
                className={`text-[48px] leading-none font-medium ${ton.fantomeLisible}`}
              >
                {position.mon_rang}
              </span>
              <span
                className={`text-[24px] leading-none font-medium ${ton.texteDoux}`}
              >
                /{membres}
              </span>
            </span>
            {/* Le lecteur d'écran reçoit la phrase, pas la fraction : « 1/3 »
                s'annonce « un barre oblique trois », qui ne veut rien dire.
                Même motif que les nombres rendus deux fois ailleurs — la forme
                visible est `aria-hidden`, la forme lue vit à côté. */}
            <span className="sr-only">
              Classement : {position.mon_rang}
              {position.mon_rang === 1 ? "er" : "e"} sur {membres}
            </span>
            <span
              aria-hidden="true"
              className={`text-label-sm mt-1 block uppercase ${ton.texteDoux}`}
            >
              classement
            </span>
          </span>
        )}
      </span>

      {/* La jauge. `overflow-hidden` sur la piste, parce que le remplissage est
          mis à l'échelle : sans lui, un arrondi mis à l'échelle déborderait des
          coins de la piste. */}
      <span
        aria-hidden="true"
        className={`relative h-1 w-full overflow-hidden rounded-full ${ton.jaugePiste}`}
      >
        <span
          className={`t-jauge block h-full w-full rounded-full ${ton.jaugePleine}`}
          style={{ "--jauge": fraction }}
        />
      </span>
    </Link>
  );
}

/** Silhouette des cartes pendant le réveil du backend.
 *
 * La carte réelle est un aplat plein : sa silhouette est donc un aplat plein
 * elle aussi, à la hauteur exacte de la carte, et non une carte blanche avec des
 * barres dedans. La couleur, elle, ne peut pas être devinée — on ne sait pas
 * encore quels championnats vont arriver — et le gris des squelettes reste la
 * seule réponse honnête. */
export function SqueletteChampionnats() {
  return (
    <div className="flex flex-col gap-2.5">
      {[0, 1].map((rang) => (
        <Pave key={rang} className="h-[120px]" arrondi="rounded-carte" />
      ))}
    </div>
  );
}

function AucunChampionnat() {
  return (
    <div className="rounded-carte bg-surface shadow-carte flex flex-col items-center gap-2 px-5 py-8 text-center">
      <span
        aria-hidden="true"
        className="bg-fond text-texte-doux mb-1 flex size-12 items-center justify-center rounded-champ"
      >
        <IconeMembres className="size-5" />
      </span>
      <p className="text-corps text-texte font-medium">Aucun championnat pour l'instant</p>
      <p className="text-corps-sm text-texte-doux max-w-[26ch]">
        Crée le tien et partage son code, ou rejoins celui d'un ami.
      </p>
    </div>
  );
}

/**
 * Carte d'action — « Créer » et « Rejoindre », désormais **dans le flux** de la
 * liste plutôt que dans une grille collée au bas de l'écran.
 *
 * Elles adoptent la hauteur et la forme des cartes de championnat, et s'en
 * distinguent par leur surface blanche : la liste se lit alors d'un seul
 * mouvement du pouce, du dernier championnat aux deux façons d'en avoir un de
 * plus, au lieu de sauter par-dessus un blanc de plusieurs centimètres.
 *
 * **La pastille de couleur a cédé la place au logo de la marque** (version
 * `0.28.0`) : les deux dessins de `assets/logo.svg`, à 40px, dans leur couleur
 * propre. Un logo enfermé dans un disque de la même teinte se serait dessiné
 * en négatif, c'est-à-dire pas du tout.
 *
 * *Conséquence à connaître.* L'ambre `#E8A020` sur le blanc de la carte ne vaut
 * que 2,2:1, sous le plancher de 3:1 d'un élément graphique porteur de sens.
 * C'était rédhibitoire tant que l'icône était le seul marqueur au centre d'une
 * pastille ; ça ne l'est plus ici, où le logo est **décoratif** (`aria-hidden`)
 * et où c'est le titre de la carte, à 17px et 12,6:1, qui porte le sens. Si le
 * logo doit redevenir lisible à distance, c'est la teinte qu'il faut reprendre,
 * pas la composition.
 */
export function CarteAction({ vers, icone, titre, sousTitre }) {
  return (
    <Link
      to={vers}
      className="rounded-carte bg-surface shadow-carte pressable-large relative flex min-h-[120px] items-center gap-3.5 overflow-hidden p-4"
    >
      {/* `relative` + `overflow-hidden` sont ajoutes pour le damier : sans le
          second, le motif deborderait des coins arrondis de la carte.

          **`motif-damier-doux` le ramene de 15 a 7,5 %** (version `0.48.0`).
          Ces deux cartes sont les seules a poser le damier sur du BLANC, ou il
          ne se lit pas comme une texture mais comme un gris sale : a 15 % le
          fond tombe a #E7E7E7, assez fonce pour que le motif dispute le regard
          au logo et au titre. A 7,5 % (#F3F3F3) il est encore la, sans
          dominer. Les aplats colores gardent les 15 % : sur eux le meme motif
          ne retire au pire qu'un point de contraste. */}
      <span
        aria-hidden="true"
        className="motif-damier motif-damier-doux pointer-events-none absolute inset-0"
      />

      <span className="relative flex size-10 shrink-0 items-center justify-center" aria-hidden="true">
        {icone}
      </span>

      <span className="relative min-w-0 flex-1">
        <span className="text-texte block truncate text-[17px] font-medium">
          {titre}
        </span>
        {/* Le sous-titre quitte le gris `texte-doux` pour le marron
            `secondaire`. Ce n'est pas un choix de style : sur le fond ramene a
            #E7E7E7 par le damier, `#999999` tombe a 2,30:1 — il etait deja sous
            le seuil AA a 2,85:1 sur blanc — quand le marron tient 8,54:1. Meme
            correction qu'au bandeau de saison a la version `0.14.1`. */}
        <span className="text-secondaire mt-1 block text-[13px]">{sousTitre}</span>
      </span>

      <IconeChevronDroit className="text-secondaire relative size-5 shrink-0" />
    </Link>
  );
}

/** Les deux cartes d'action, ensemble : elles ne vont jamais l'une sans
 *  l'autre, et les trois écrans qui les portent ne doivent pas avoir à se
 *  souvenir de leurs libellés. */
export function ActionsChampionnat() {
  return (
    <div className="flex flex-col gap-2.5">
      <CarteAction
        vers="/championnats/creer"
        icone={<IconeCreer couleur="#800111" className="size-10" />}
        titre="Créer un championnat"
        sousTitre="Lance ton championnat 2026"
      />
      <CarteAction
        vers="/championnats/rejoindre"
        icone={<IconeRejoindre couleur="#E8A020" className="size-10" />}
        titre="Rejoindre un championnat"
        sousTitre="Entre un code à 6 caractères"
      />
    </div>
  );
}

/**
 * Le bandeau qui ferme l'écran : « Saison 2026 · N Grands Prix restants ».
 *
 * Il répond à un vrai défaut de composition — sous une liste d'un ou deux
 * championnats, le bas de l'écran restait vide sur toute sa moitié. Le remplir
 * d'un ornement aurait été pire ; ce décompte, lui, dit quelque chose, et il se
 * vide de lui-même à mesure que la saison avance.
 *
 * **Le décompte est une constante, pas une lecture.** `public.grands_prix` ne
 * contient que les Grands Prix déjà scrapés, et Unibet n'expose jamais que le
 * suivant (section 3.1) : compter les lignes en base annonçait « 1 Grand Prix
 * restant » au milieu d'une saison qui en compte douze. Un décompte faux est
 * pire qu'un décompte figé — c'est la seule ligne de l'écran dont personne
 * n'attend qu'elle se corrige.
 *
 * TODO: dynamique quand tous les GP sont en base. `chargerGrandsPrixRestants`
 * (lib/pronostics.js) fait déjà exactement cette lecture et reste en place :
 * le jour où le calendrier complet est enregistré, il n'y a qu'à la rebrancher
 * ici, avec le repli « rien tant que le décompte est inconnu » qu'elle servait.
 *
 * Aucun aplat, aucune ombre : ce n'est pas un bloc. Mais le gris des lignes de
 * version le rendait illisible sur le beige ; il porte donc le marron
 * `secondaire` du design system, en graisse 500.
 */
export function BlocSaison() {
  const texte =
    GP_RESTANTS === 0
      ? "Saison 2026 terminée"
      : `Saison 2026 · ${GP_RESTANTS} Grand${GP_RESTANTS > 1 ? "s" : ""} Prix restant${
          GP_RESTANTS > 1 ? "s" : ""
        }`;

  return (
    <p className="text-secondaire px-4 pt-1 text-center text-[13px] font-medium">
      {texte}
    </p>
  );
}

/** Maquette 04 — accueil connecté : mes championnats et les deux actions. */
export default function Accueil() {
  const { pseudo: pseudoJeton, utilisateur, modePrevisualisation } = useAuth();

  // Le pseudo affiché est relu **en base à chaque montage**, jamais pris dans
  // le jeton. `useAuth().pseudo` ne lit pas `public.profils` : il lit
  // `user_metadata`, une copie figée à l'inscription qu'un renommage direct en
  // base ne touche pas. Le jeton reste le repli — pendant la lecture, et si
  // elle échoue. Voir `lib/usePseudo.js` pour les trois décisions.
  const { pseudo, avatarUrl } = useIdentiteCourante(
    utilisateur?.id ?? null,
    pseudoJeton,
  );

  // La clé porte l'identifiant du compte : deux personnes qui se relaient sur
  // le même téléphone ne doivent jamais voir la liste de l'autre, même une
  // fraction de seconde avant le rafraîchissement.
  const cle = utilisateur ? `championnats:${utilisateur.id}` : null;
  const chargeur = useCallback((signal) => listerMesChampionnats(signal), []);
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  const [tentative, setTentative] = useState(0);

  function reessayer() {
    setTentative((n) => n + 1);
    recharger();
  }

  const championnats = donnees ?? [];

  // La pastille mène au profil (maquette 14). C'est l'endroit où l'attend
  // quelqu'un qui vient d'iOS, et c'est déjà la place que la maquette 04 lui
  // donne — elle n'y était simplement reliée à rien. Depuis la passe
  // `/apple-design`, elle vit dans la barre collante : c'est le seul élément
  // qui doit rester atteignable quel que soit le défilement.
  const avatar = (
    <Link
      to="/profil"
      aria-label="Mon profil"
      className="pressable size-tactile -m-0.5 flex shrink-0 items-center justify-center"
    >
      {/* La photo du compte connecté, quand il en a une — sinon l'initiale sur
          sa teinte, exactement comme avant. Elle vient de l'état déjà chargé
          par `useIdentiteCourante`, dans la même requête que le pseudo : la
          barre d'accueil ne coûte pas un aller-retour de plus. Même diamètre
          dans les deux cas, `Pastille` ne changeant que ce qu'il y a dedans. */}
      <Pastille
        nom={pseudo}
        graine={utilisateur?.id ?? pseudo}
        photo={avatarUrl}
        taille="lg"
      />
    </Link>
  );

  return (
    <Ecran direction="avant">
      <EnTeteEcran
        titre={pseudo ? `Salut ${pseudo}` : "Greed F1"}
        sousTitre="Saison 2026 · Formule 1"
        action={avatar}
      />

      <div className="mt-3 flex flex-1 flex-col gap-3">
        <Bloc rang={1}>
          <BlocProchainGp
            profilId={utilisateur?.id ?? null}
            previsualisation={modePrevisualisation}
          />
        </Bloc>

        {/* **Le conteneur flex vit A L'INTERIEUR du `Bloc`, jamais sur lui.**
            `.t-stagger-line` declare `display: block` hors de toute couche
            Tailwind, et une regle non affectee a une couche l'emporte sur
            toutes les regles empilees, quelle que soit leur specificite : un
            `flex flex-col gap-2.5` pose sur le `Bloc` etait donc INERTE, et
            rien dans le JSX ne le laissait voir. Les cartes de championnat se
            retrouvaient collees a la carte « Creer un championnat », a 0 px.
            C'est le piege deja documente a la version `0.21.1` pour le
            calendrier et a la `0.34.0` pour le logo de la page publique. */}
        <Bloc rang={2}>
          <div className="flex flex-col gap-2.5">
          <p className="text-label text-texte-doux px-1 pt-1 uppercase">
            Mes championnats
          </p>

          {/* Le cache a peut-être déjà servi la liste : l'échec s'ajoute alors
              sous les cartes plutôt que de les remplacer. Le bouton relance
              l'appel, ce qui est exactement le geste attendu quand Railway se
              réveille encore. */}
          {echec && (
            <BlocErreur
              echec={echec}
              onReessayer={reessayer}
              tentative={tentative}
            />
          )}

          <ZoneChargement chargement={chargement} squelette={<SqueletteChampionnats />}>
            {championnats.length === 0 ? (
              <AucunChampionnat />
            ) : (
              <div className="flex flex-col gap-2.5">
                {championnats.map((championnat) => (
                  <CarteChampionnat
                    key={championnat.id}
                    championnat={championnat}
                  />
                ))}
              </div>
            )}
          </ZoneChargement>

          {/* Les deux actions suivent les championnats **dans le même bloc**,
              et non dans une grille collée au bas de l'écran : elles sont la
              suite naturelle de la liste, pas un pied de page. */}
          <ActionsChampionnat />
          </div>
        </Bloc>

        <Bloc rang={3}>
          <BlocSaison />
        </Bloc>

        <div className="min-h-3 flex-1" />
      </div>

      <footer className="flex flex-col items-center gap-3 pt-5">
        {/* La déconnexion a quitté ce pied de page pour le profil (étape 8),
            comme l'annonçait l'étape 3 : c'est sa place définitive, et la
            garder ici en double aurait donné deux endroits à corriger. */}
        <span className="text-label-sm text-texte-doux uppercase">
          Version {APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
