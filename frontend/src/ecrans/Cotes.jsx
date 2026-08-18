import { useCallback, useMemo, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Compteur from "../composants/Compteur.jsx";
import EtoileFavori from "../composants/EtoileFavori.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { Barre, Pave } from "../composants/Squelette.jsx";
import { IconeCroix, IconeEtoile } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { couleurMarche, encreSurBlanc, tonalites } from "../lib/couleurs.js";
import { basculerFavori, chargerTableauCotes } from "../lib/pronostics.js";
import { oublierCache, useDonnees } from "../lib/useDonnees.js";
import {
  decouperPoints,
  formaterDepart,
  formaterPilote,
} from "../lib/format.js";
import { origineRetour } from "../lib/navigation.js";
import { useFermeture } from "../lib/useFermeture.js";

/* Hauteur d'un widget de cote. Écrite une fois et partagée avec le squelette :
   sans hauteur commune, la grille sauterait de 90px par rangée à l'arrivée des
   données — le défaut déjà corrigé sur les cartes de championnat en version
   `0.14.0`. */
const HAUTEUR_WIDGET = 90;

/**
 * Un widget de cote — la brique de la grille à deux colonnes.
 *
 * **Hauteur fixe, et c'est ce qui fait la grille.** Deux widgets d'une même
 * rangée doivent finir à la même ligne quel que soit le nom qu'ils portent :
 * une hauteur libre donnerait des rangées en dents de scie dès qu'un pilote a
 * un nom plus long que son voisin. Le nom est donc sur **une seule ligne**, et
 * tronqué au-delà.
 *
 * L'étoile est posée en absolu dans le coin plutôt que dans le flux : sa zone
 * tactile de 44px est plus haute que la ligne des points, et la mettre dans le
 * flux ferait grandir le widget de 20px pour rien. Elle chevauche le
 * rembourrage, jamais le texte — les points lui laissent la place à droite.
 */
function WidgetCote({ cote, epingle, ferme, onBasculer }) {
  const points = decouperPoints(cote.points);
  const nom = formaterPilote(cote.pilote);

  return (
    <li
      className="rounded-widget bg-surface shadow-carte relative"
      style={{ height: `${HAUTEUR_WIDGET}px` }}
    >
      <div className="flex h-full flex-col justify-between p-3">
        <p className="text-texte truncate text-[14px] font-medium">{nom}</p>

        {points.retiree ? (
          <p className="text-texte-doux truncate pr-8 text-[12px]">
            Cote retirée
          </p>
        ) : (
          /* Le rouge de la marque sur le blanc du widget : 10,9:1. La graisse
             700 est un écart assumé à la section 5, qui la réserve aux numéros
             de voiture — il est borné à ce seul chiffre, comme les tuiles du
             compte à rebours (version `0.18.0`) et le quantième des cartes de
             Grand Prix (version `0.20.0`). C'est le nombre qu'on vient lire. */
          <p className="text-primaire flex items-baseline gap-1 pr-8 font-bold">
            <span className="text-[18px] tracking-[-0.01em]">
              {points.valeur}
            </span>
            <span className="text-[11px] font-medium">{points.unite}</span>
          </p>
        )}
      </div>

      {!ferme && (
        <EtoileFavori
          nom={nom}
          favori={epingle}
          onClick={onBasculer}
          className="absolute right-0.5 bottom-0.5"
        />
      )}
    </li>
  );
}

/**
 * Une pastille de la rangée « MES FAVORIS ».
 *
 * **Les points sont un aplat ambre à encre foncée, jamais du texte ambre.**
 * `#E8A020` écrit sur le blanc de la pastille ne vaut que 2,2:1 ; le même ambre
 * en aplat avec l'encre `#1A1A1A` du design system monte à 7,9:1. C'est le
 * même arbitrage qu'aux versions `0.12.0`, `0.17.0` et `0.19.0`, et il donne
 * bien le repère ambre que la demande cherche.
 *
 * Le bouton de retrait fait ses 44px alors que la croix n'en occupe que 14 :
 * dans une rangée qui défile sous le pouce, une cible étroite se rate.
 */
function ChipFavori({ favori, ferme, onRetirer }) {
  const points = decouperPoints(favori.points);
  const nom = favori.pilote ? formaterPilote(favori.pilote) : "Cote retirée";

  return (
    <li className="rounded-full bg-surface shadow-carte min-h-tactile flex shrink-0 snap-start items-center gap-2 pl-3.5">
      <span className="text-texte text-[13px] font-medium whitespace-nowrap">
        {nom}
      </span>

      {!points.retiree && (
        <span className="bg-accent text-texte rounded-full px-2 py-0.5 text-[12px] font-bold">
          {points.valeur}
          <span className="ml-0.5 text-[10px] font-medium">{points.unite}</span>
        </span>
      )}

      {ferme ? (
        <span aria-hidden="true" className="w-3.5" />
      ) : (
        <button
          type="button"
          onClick={onRetirer}
          aria-label={`Retirer ${nom} des favoris`}
          className="pressable size-tactile text-secondaire/70 flex shrink-0 items-center justify-center"
        >
          <IconeCroix className="size-3.5" />
        </button>
      )}
    </li>
  );
}

/**
 * La section « MES FAVORIS », en tête d'écran.
 *
 * C'est le panier du joueur : ce qu'il a mis de côté, et ce dans quoi il
 * choisira ses trois bonus à l'écran suivant. Il est donc en haut, avant le
 * catalogue, et non relégué sous vingt-deux widgets.
 *
 * **Le libellé de section quitte le gris `texte-doux` du design system.** Sur
 * le beige `#F5F0EB`, `#999999` ne vaut que 2,0:1 : c'était tenable pour une
 * étiquette qu'on ne lit pas, pas pour celle que la demande veut « bien
 * visible ». Le marron `secondaire` du design system le porte à 9,4:1, sans
 * introduire de couleur nouvelle. Même correction qu'au bandeau de saison en
 * version `0.14.1`.
 *
 * La rangée défile à l'horizontale, calée sur les pastilles (`snap-x`) : un
 * doigt qui la pousse la laisse sur une pastille entière, jamais coupée en
 * deux. C'est ce qui la distingue d'un débordement accidentel.
 */
function SectionFavoris({ favoris, ferme, onRetirer }) {
  return (
    <section className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between gap-3 px-1">
        <h2 className="text-label text-secondaire uppercase">Mes favoris</h2>
        {favoris.length > 0 && (
          <span className="text-texte-doux text-[12px]">
            {favoris.length} {favoris.length > 1 ? "cotes" : "cote"}
          </span>
        )}
      </div>

      {favoris.length === 0 ? (
        <div className="rounded-carte bg-surface shadow-carte px-5 py-7 text-center">
          <IconeEtoile
            className="text-accent mx-auto size-6"
            aria-hidden="true"
          />
          <p className="text-texte-doux text-corps-sm mx-auto mt-2.5 max-w-[30ch]">
            Épingle tes cotes favorites ci-dessous pour construire tes bonus.
          </p>
        </div>
      ) : (
        <ul className="-mx-4 flex snap-x snap-mandatory gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {favoris.map((favori) => (
            <ChipFavori
              key={favori.id_outcome_unibet}
              favori={favori}
              ferme={ferme}
              onRetirer={() => onRetirer(favori)}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

/**
 * Le mode d'emploi, entre les favoris et les marchés.
 *
 * Trois gestes, dans l'ordre où on les fait, à l'endroit exact où on passe de
 * « ce que j'ai retenu » à « ce que le bookmaker propose ». Sans lui, rien à
 * l'écran ne dit qu'épingler une cote sert à quelque chose plus tard.
 *
 * **Deux écarts au design system, tous deux demandés explicitement.** La
 * section 5 proscrit les bordures fines : celle-ci est réclamée par la demande,
 * et elle fait un vrai travail — sur un fond ambre très pâle posé sur du beige,
 * c'est le trait qui dit où commence l'encadré. Et `#FDF3E0` est une teinte
 * nouvelle : elle est écrite en valeur littérale plutôt qu'ajoutée aux jetons
 * du thème, parce qu'elle **ne peint que cet encadré** et rien d'autre — un
 * jeton inviterait à la réutiliser ailleurs.
 *
 * Contraste mesuré : `#543925` sur `#FDF3E0` vaut 9,0:1.
 */
function ModeEmploi() {
  const etapes = [
    <>
      Épingle tes cotes favorites avec{" "}
      <IconeEtoile
        pleine
        aria-hidden="true"
        className="inline-block size-3.5 translate-y-px"
      />
    </>,
    <>
      Choisis tes 2 pronostics obligatoires (Vainqueur + Podium) depuis l'écran
      suivant
    </>,
    <>Sélectionne 3 bonus parmi tes favoris</>,
  ];

  return (
    <ol className="rounded-carte border-accent text-secondaire flex flex-col gap-2.5 border bg-[#FDF3E0] px-4 py-3.5 text-[13px] leading-snug">
      {etapes.map((etape, rang) => (
        <li key={rang} className="flex items-start gap-2.5">
          {/* Encre foncée sur l'ambre : 7,9:1. Le blanc y tomberait à 2,2:1. */}
          <span
            aria-hidden="true"
            className="bg-accent text-texte mt-px flex size-5 shrink-0 items-center justify-center rounded-full text-[11px] font-medium"
          >
            {rang + 1}
          </span>
          <span className="min-w-0">{etape}</span>
        </li>
      ))}
    </ol>
  );
}

/**
 * Un marché : en-tête coloré **collant**, puis ses cotes en grille de deux.
 *
 * Les trois marchés du noyau ont chacun leur couleur nommée (`lib/couleurs.js`),
 * les marchés que le scraper découvre en prennent une parmi les trois qui
 * restent. Le libellé affiché est celui d'Unibet, jamais un slug reconstitué :
 * le bookmaker est la seule source légitime du nom d'un marché (étape 4).
 *
 * **L'en-tête est `sticky`.** Un marché aligne vingt-deux pilotes, soit onze
 * rangées de widgets : à mi-liste, plus rien ne dirait ce qu'on est en train de
 * lire, et il faudrait remonter pour le savoir. C'est la liste groupée d'iOS, et
 * le §16 d'/apple-design sur le « où suis-je ». Le décalage `top` est celui de
 * la barre d'écran (`--entete-hauteur`), sans quoi les deux se recouvriraient.
 *
 * La pastille de droite est **toujours rendue**, y compris à zéro : une pastille
 * qui apparaîtrait au premier favori ferait sauter un en-tête collant sous le
 * doigt qui vient d'épingler.
 */
function SectionMarche({ marche, rang, epingles, ferme, onBasculer }) {
  const couleur = couleurMarche(marche.marche, rang);
  const ton = tonalites(couleur.hex);
  const encreCompteur = encreSurBlanc(couleur);
  const epinglesIci = marche.cotes.filter((cote) => epingles.has(cote.id)).length;

  return (
    <section className="flex flex-col gap-3">
      <header
        className={`section-collante rounded-carte shadow-carte relative flex items-center justify-between gap-3 overflow-hidden px-4 py-2.5 ${couleur.fond}`}
      >
        <span
          aria-hidden="true"
          className="lueur-haute pointer-events-none absolute inset-0"
        />
        <h2
          className={`relative min-w-0 truncate text-[13px] font-medium tracking-[0.5px] uppercase ${ton.texte}`}
        >
          {marche.libelle}
        </h2>
        <span
          className={`relative flex shrink-0 items-center gap-1 rounded-full bg-white px-2.5 py-1 text-[12px] font-medium ${encreCompteur}`}
        >
          <IconeEtoile pleine aria-hidden="true" className="size-3" />
          <span className="sr-only">Favoris épinglés dans ce marché :</span>
          <Compteur valeur={epinglesIci} />
        </span>
      </header>

      {/* Deux colonnes, 12px de gouttière. Les 16px de marge latérale viennent
          d'`ecran`, qui les applique déjà à tout l'écran : les redéclarer ici
          les doublerait. */}
      <ul className="grid grid-cols-2 gap-3">
        {marche.cotes.map((cote) => (
          <WidgetCote
            key={cote.id}
            cote={cote}
            epingle={epingles.has(cote.id)}
            ferme={ferme}
            onBasculer={() => onBasculer(cote, marche)}
          />
        ))}
      </ul>
    </section>
  );
}

/** La silhouette de l'écran : la rangée de favoris, puis deux marchés. */
function SqueletteCotes() {
  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-2.5">
        <Barre largeur="w-24" hauteur="h-2.5" className="ml-1" />
        <div className="flex gap-2">
          {[0, 1, 2].map((rang) => (
            <Pave key={rang} className="h-11 w-32 shrink-0" arrondi="rounded-full" />
          ))}
        </div>
      </div>

      {[0, 1].map((section) => (
        <div key={section} className="flex flex-col gap-3">
          {/* L'en-tête garde son aplat de couleur, seul son contenu est grisé :
              le voir virer au gris puis revenir ferait clignoter l'écran au
              lieu de le remplir. C'est la règle tenue depuis l'étape 9. */}
          <div className="rounded-carte bg-primaire shadow-carte px-4 py-2.5">
            <div className="h-3.5 w-28 rounded-full bg-white/25" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            {[0, 1, 2, 3].map((cellule) => (
              <Pave
                key={cellule}
                arrondi="rounded-widget"
                style={{ height: `${HAUTEUR_WIDGET}px` }}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

/** Maquette 08 — tableau des cotes du prochain GP, et mise en favori. */
export default function Cotes() {
  const { gpId } = useParams();
  const naviguer = useNavigate();
  const { state } = useLocation();
  const { utilisateur } = useAuth();

  // D'où l'on vient. L'accueil reste la destination par défaut : c'est de là
  // que l'écran s'ouvre quand rien n'est précisé, et un lien direct ne doit
  // jamais laisser le bouton de retour sans destination.
  const retour = origineRetour(state, { vers: "/accueil", libelle: "Accueil" });

  const cle = utilisateur ? `cotes:${utilisateur.id}:${gpId}` : null;
  const chargeur = useCallback(
    (signal) => chargerTableauCotes(gpId, signal),
    [gpId],
  );
  const { donnees, chargement, echec, recharger, setDonnees } = useDonnees(
    cle,
    chargeur,
  );

  const gp = donnees?.gp ?? null;
  const marches = useMemo(() => gp?.marches ?? [], [gp]);

  const [erreurFavori, setErreurFavori] = useState(null);
  const [tentative, setTentative] = useState(0);
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayerChargement() {
    setTentativeChargement((n) => n + 1);
    recharger();
  }

  const { ferme } = useFermeture(gp?.date_course);

  const favoris = donnees?.favoris ?? [];
  const epingles = useMemo(
    () => new Set(favoris.map((favori) => favori.id_outcome_unibet)),
    [favoris],
  );

  async function basculer(cote, marche) {
    setErreurFavori(null);

    // Mise à jour optimiste : l'étoile bascule à l'appui, pas au retour du
    // serveur. Sur le plan gratuit de Railway, attendre la réponse donnerait
    // une étoile qui met une seconde à réagir.
    const etaitEpingle = epingles.has(cote.id);
    const suivant = etaitEpingle
      ? favoris.filter((favori) => favori.id_outcome_unibet !== cote.id)
      : [
          ...favoris,
          {
            id_outcome_unibet: cote.id,
            pilote: cote.pilote,
            points: cote.points,
            marche: marche.marche,
            libelle: marche.libelle,
          },
        ];
    setDonnees({ ...donnees, favoris: suivant });

    const resultat = await basculerFavori(gpId, cote.id);

    if (!resultat.ok) {
      // Retour à l'état d'avant : une étoile qui ment est pire qu'une étoile
      // qui n'a pas bougé.
      setDonnees({ ...donnees, favoris });
      setTentative((n) => n + 1);
      setErreurFavori(resultat.message);
      return;
    }

    // L'écran de saisie lit les mêmes favoris : son cache n'a plus cours.
    if (utilisateur) oublierCache(`saisie:${utilisateur.id}:${gpId}`);
  }

  // La croix d'une pastille passe par le même chemin que l'étoile du widget :
  // c'est la même bascule, vue de l'autre bout. Deux chemins d'écriture
  // séparés auraient fini par diverger sur la mise à jour optimiste.
  function retirerFavori(favori) {
    return basculer(
      {
        id: favori.id_outcome_unibet,
        pilote: favori.pilote,
        points: favori.points,
      },
      { marche: favori.marche, libelle: favori.libelle },
    );
  }

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <EnTeteEcran
          titre="Les cotes"
          retourVers={retour.vers}
          libelleRetour={retour.libelle}
        />
        <Bloc rang={1} className="mt-3">
          <BlocErreur
            echec={echec}
            onReessayer={reessayerChargement}
            tentative={tentativeChargement}
          />
        </Bloc>
      </Ecran>
    );
  }

  const depart = formaterDepart(gp?.date_course);

  return (
    <Ecran direction="avant">
      <EnTeteEcran
        titre="Fais tes paris"
        retourVers={retour.vers}
        libelleRetour={gp?.nom ?? retour.libelle}
        retourEtat={state?.origine ? { retour: state.origine } : null}
        sousTitre={
          gp
            ? depart.heure
              ? `${depart.jour} · Départ ${depart.heure}`
              : depart.jour
            : null
        }
      />

      <div className="mt-3 flex flex-1 flex-col gap-3">
        <Bloc rang={1}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteCotes />}
          >
            {gp && (
              /* 20px entre les grands ensembles — favoris, mode d'emploi,
                 marchés — contre 12px à l'intérieur de chacun. C'est le « vrai
                 espacement » que la demande réclame autour des favoris : ce qui
                 sépare deux ensembles doit être visiblement plus large que ce
                 qui sépare deux éléments d'un même ensemble. */
              <div className="flex flex-col gap-5">
                {ferme && (
                  <p className="rounded-carte bg-surface shadow-carte text-texte-doux text-corps-sm px-4 py-3">
                    Les pronostics sont fermés. Les cotes restent consultables.
                  </p>
                )}

                {marches.length === 0 ? (
                  <div className="rounded-carte bg-surface shadow-carte px-5 py-8 text-center">
                    <p className="text-corps text-texte font-medium">
                      Aucune cote pour ce Grand Prix
                    </p>
                    <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[28ch]">
                      Les cotes sont relevées le samedi, après les
                      qualifications. Reviens à ce moment-là.
                    </p>
                  </div>
                ) : (
                  <>
                    <SectionFavoris
                      favoris={favoris}
                      ferme={ferme}
                      onRetirer={retirerFavori}
                    />

                    {erreurFavori && (
                      <Alerte ton="erreur" tentative={tentative}>
                        {erreurFavori}
                      </Alerte>
                    )}

                    {!ferme && <ModeEmploi />}

                    {/* Tous les marchés sont empilés, chacun sous son en-tête
                        coloré, au lieu d'un seul marché derrière des onglets.
                        Le joueur voit d'un seul défilement tout ce que le
                        bookmaker propose. */}
                    {marches.map((marche, rang) => (
                      <SectionMarche
                        key={marche.marche}
                        marche={marche}
                        rang={rang}
                        epingles={epingles}
                        ferme={ferme}
                        onBasculer={basculer}
                      />
                    ))}
                  </>
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {/* Le bouton reste actif même sans favori : la maquette 09 accepte
            zéro bonus, et un joueur peut vouloir n'entrer que ses deux
            pronostics obligatoires. Un bouton grisé ne dirait pas pourquoi — son
            libellé change donc plutôt que son état.

            La barre est collée en bas : sur un écran qui empile trois marchés de
            vingt-deux pilotes, un bouton en fin de page obligerait à redescendre
            toute la grille après chaque étoile épinglée. Elle rend elle-même la
            zone sûre du home indicator (voir `barre-collee` dans index.css) et
            n'est pas enveloppée dans un `Bloc` : `t-stagger-line` porte un
            `transform`, et un ancêtre transformé casse le collage. */}
        <div className="barre-collee pleine-largeur px-4">
          <Bouton
            variante="principal"
            // L'écran de saisie revient ici par son bouton de retour ; il
            // emporte donc notre propre origine pour nous la rendre, sans quoi
            // le second passage sur cet écran retomberait sur l'accueil.
            onClick={() =>
              naviguer(`/grands-prix/${gpId}/pronostics`, {
                state: { origine: retour.vers },
              })
            }
            disabled={!gp || marches.length === 0}
          >
            {ferme
              ? "Voir mes pronos"
              : favoris.length > 0
                ? `Continuer · ${favoris.length} ${favoris.length > 1 ? "favoris" : "favori"}`
                : "Passer aux pronos"}
          </Bouton>
        </div>
      </div>
    </Ecran>
  );
}
