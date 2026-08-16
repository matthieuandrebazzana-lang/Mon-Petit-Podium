import { useCallback, useState } from "react";
import { Link } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Pastille from "../composants/Pastille.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { Pave } from "../composants/Squelette.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import TraceCircuit, { traceDuGrandPrix } from "../composants/TraceCircuit.jsx";
import {
  IconeChevronDroit,
  IconeLien,
  IconeMembres,
  IconePlus,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { listerMesChampionnats } from "../lib/championnats.js";
import { couleurBloc, couleurChampionnat, tonalites } from "../lib/couleurs.js";
import {
  chargerAccueilGp,
  chargerGrandsPrixRestants,
  cleAccueilGp,
} from "../lib/pronostics.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";
import { APP_VERSION } from "../config.js";

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
 */
export function BlocProchainGp({ profilId }) {
  const chargeur = useCallback((signal) => chargerAccueilGp(profilId, signal), [profilId]);
  const { donnees, chargement } = useDonnees(
    profilId ? cleAccueilGp(profilId) : null,
    chargeur,
  );

  const gp = donnees?.gp ?? null;
  const etat = useFermeture(gp?.date_course);

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
          <div className="h-7 w-44 rounded-full bg-white/25" />
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
        {
          label: etat.ferme ? "Pronos" : "Fermeture dans",
          valeur: etat.ferme ? "Fermés" : (etat.texte ?? "À confirmer"),
        },
      ];

  return (
    <div className="rounded-bloc bg-primaire shadow-aplat relative overflow-hidden p-5">
      {/* Le tracé du circuit, posé en filigrane à droite. Il reprend le
          composant du calendrier (étape 9) : le Grand Prix qui a un vrai tracé
          montre le sien, les autres le tracé générique. À 8 % de blanc, il
          donne de la matière à l'aplat sans jamais concurrencer le texte — et
          l'aplat rouge reste seul en cas de repli, exactement comme demandé.
          `overflow-hidden` sur le bloc le laisse déborder par la droite plutôt
          que de le contraindre à tenir en entier, ce qui l'écraserait. */}
      <TraceCircuit
        trace={traceDuGrandPrix(gp.nom)}
        className="pointer-events-none absolute top-1/2 -right-8 h-[150%] w-[60%] -translate-y-1/2 text-white/8"
      />
      {/* La lumière spéculaire d'/apple-design §12 : un aplat plein est une
          surface morte, ce galbe très doux lui donne une source lumineuse. Il
          est posé par-dessus le tracé pour éclairer les deux ensemble. */}
      <div
        aria-hidden="true"
        className="lueur-haute pointer-events-none absolute inset-0"
      />

      <div className="relative">
        <div className="mb-3 flex items-center justify-between gap-3">
          <span className="text-label-sm rounded-full bg-white/20 px-2.5 py-1 text-white uppercase">
            {couru ? "Dernier GP" : "Prochain GP"}
          </span>
          <span className="shrink-0 text-[11px] text-white/70">
            {depart.courte ?? "Date à confirmer"}
          </span>
        </div>

        {/* Le nom du Grand Prix passe à l'échelle des titres de page : c'est ce
            qu'on vient lire, il doit être le plus gros élément de l'écran. */}
        <p className="text-titre-lg truncate text-white">{gp.nom}</p>

        <div className="mt-4 grid grid-cols-2 gap-2">
          {cases.map((donnee) => (
            <div
              key={donnee.label}
              className="rounded-champ bg-white/12 px-3.5 py-2.5"
            >
              <p className="text-label-sm truncate uppercase text-white/70">
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

        <Link
          to={destination}
          className="rounded-champ bg-surface text-primaire pressable min-h-tactile mt-2.5 flex items-center justify-center px-4 text-center text-[15px] font-medium"
        >
          {/* Le cache peut avoir servi l'état d'avant la dernière validation : le
              libellé change alors sous les yeux du joueur, une fois la lecture
              fraîche revenue. TexteEchange (transitions-dev 04) le remplace en
              place plutôt que de le laisser clignoter. */}
          <TexteEchange valeur={libelle} />
        </Link>
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
            là où c'est le réveil de Railway qui n'a pas encore répondu. */}
        {position && (
          <span className="shrink-0 text-right">
            <span
              className={`block text-[48px] leading-none font-medium ${ton.fantomeLisible}`}
            >
              {position.mon_rang}
            </span>
            <span
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
 * *Écart assumé sur la pastille d'icône.* La demande décrit « une icône en rouge
 * dans un cercle rouge » et « une icône de lien en amber ». Une icône ambre sur
 * une pastille ambre pâle tombe à 2,2:1 de contraste sur une carte blanche, très
 * en dessous du plancher de 3:1 exigé d'un élément graphique porteur de sens.
 * La pastille prend donc l'aplat plein et l'icône l'encre que `encreSurAplat`
 * calcule pour lui — blanche sur le bordeaux, foncée sur l'ambre. C'est le même
 * arbitrage, et le même seuil, que celui déjà tranché pour les blocs de bonus.
 */
export function CarteAction({ vers, couleur, icone, titre, sousTitre }) {
  const ton = tonalites(couleur.hex);

  return (
    <Link
      to={vers}
      className="rounded-carte bg-surface shadow-carte pressable-large flex min-h-[120px] items-center gap-3.5 p-4"
    >
      <span
        aria-hidden="true"
        className={`flex size-12 shrink-0 items-center justify-center rounded-full ${couleur.fond} ${ton.texte}`}
      >
        {icone}
      </span>

      <span className="min-w-0 flex-1">
        <span className="text-texte block truncate text-[17px] font-medium">
          {titre}
        </span>
        <span className="text-texte-doux mt-1 block text-[13px]">{sousTitre}</span>
      </span>

      <IconeChevronDroit className="text-texte-doux size-5 shrink-0" />
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
        couleur={couleurBloc("rouge")}
        icone={<IconePlus className="size-5" />}
        titre="Créer un championnat"
        sousTitre="Lance ton championnat 2026"
      />
      <CarteAction
        vers="/championnats/rejoindre"
        couleur={couleurBloc("amber")}
        icone={<IconeLien className="size-5" />}
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
 * **Rien ne s'affiche tant que le décompte n'est pas connu**, et rien non plus
 * si sa lecture échoue. Un bandeau qui annoncerait « 0 Grand Prix restant »
 * pendant le réveil de la base dirait le contraire de la vérité, sur le seul
 * élément de l'écran dont personne n'attend qu'il se corrige.
 *
 * Aucun aplat, aucune ombre : ce n'est pas un bloc. C'est la même graisse et le
 * même gris que la ligne de version, quelques pixels plus haut.
 */
export function BlocSaison() {
  const chargeur = useCallback((signal) => chargerGrandsPrixRestants(signal), []);
  const { donnees } = useDonnees("gp-restants", chargeur);

  if (typeof donnees !== "number") return null;

  const texte =
    donnees === 0
      ? "Saison 2026 terminée"
      : `Saison 2026 · ${donnees} Grand${donnees > 1 ? "s" : ""} Prix restant${
          donnees > 1 ? "s" : ""
        }`;

  return (
    <p className="text-texte-doux px-4 pt-1 text-center text-[13px]">{texte}</p>
  );
}

/** Maquette 04 — accueil connecté : mes championnats et les deux actions. */
export default function Accueil() {
  const { pseudo, utilisateur } = useAuth();

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
      <Pastille nom={pseudo} graine={utilisateur?.id ?? pseudo} taille="lg" />
    </Link>
  );

  return (
    <Ecran direction="avant">
      <EnTeteEcran
        titre={pseudo ? `Salut ${pseudo}` : "Mon Petit Podium"}
        sousTitre="Saison 2026 · Formule 1"
        action={avatar}
      />

      <div className="mt-3 flex flex-1 flex-col gap-3">
        <Bloc rang={1}>
          <BlocProchainGp profilId={utilisateur?.id ?? null} />
        </Bloc>

        <Bloc rang={2} className="flex flex-col gap-2.5">
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
