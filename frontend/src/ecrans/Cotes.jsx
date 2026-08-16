import { useCallback, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import EtoileFavori from "../composants/EtoileFavori.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { Barre, Pave } from "../composants/Squelette.jsx";
import { IconeEtoile } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { couleurMarche, tonalites } from "../lib/couleurs.js";
import { basculerFavori, chargerTableauCotes } from "../lib/pronostics.js";
import { oublierCache, useDonnees } from "../lib/useDonnees.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";

function SqueletteCotes() {
  return (
    <div className="flex flex-col gap-3">
      {[0, 1].map((section) => (
        <div key={section} className="rounded-carte bg-surface shadow-carte overflow-hidden">
          {/* L'en-tête garde son aplat de couleur, seul son contenu est grisé :
              le voir virer au gris puis revenir ferait clignoter l'écran au
              lieu de le remplir. C'est la règle tenue depuis l'étape 9. */}
          <div className="bg-primaire px-4 py-3">
            <div className="h-3 w-28 rounded-full bg-white/25" />
          </div>
          <div className="flex flex-col gap-4 p-4">
            {[0, 1, 2].map((rang) => (
              <div key={rang} className="flex items-center justify-between gap-3">
                <Barre largeur="w-1/3" />
                <Pave className="h-7 w-24" arrondi="rounded-[10px]" />
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

/**
 * Une section de marché : en-tête coloré **collant**, puis ses cotes.
 *
 * Les trois marchés du noyau ont chacun leur couleur nommée (`lib/couleurs.js`),
 * les marchés que le scraper découvre en prennent une parmi les trois qui
 * restent. Le libellé affiché est celui d'Unibet, jamais un slug reconstitué :
 * le bookmaker est la seule source légitime du nom d'un marché (étape 4).
 *
 * **L'en-tête est `sticky`**, et c'est le vrai apport de cette passe sur cet
 * écran. Un marché aligne vingt-deux pilotes : à mi-liste, plus rien ne disait
 * ce qu'on était en train de lire, et il fallait remonter pour le savoir. C'est
 * la liste groupée d'iOS, et le §16 d'/apple-design sur le « où suis-je ».
 * Le décalage `top` est celui de la barre de navigation d'écran, sans quoi
 * l'en-tête de marché viendrait se coller par-dessus.
 *
 * Le nombre de pilotes cède la place au **nombre de favoris épinglés dans ce
 * marché** dès qu'il y en a : « 22 » ne dit rien qu'on ne voie en défilant,
 * « 3 en favoris » dit où en est le joueur de sa sélection.
 */
function SectionMarche({ marche, rang, epingles, ferme, onBasculer }) {
  const couleur = couleurMarche(marche.marche, rang);
  const ton = tonalites(couleur.hex);
  const epinglesIci = marche.cotes.filter((cote) => epingles.has(cote.id)).length;

  return (
    <section className="rounded-carte bg-surface shadow-carte overflow-hidden">
      <header
        className={`section-collante flex items-center justify-between gap-3 px-4 py-3 ${couleur.fond}`}
      >
        <h2
          className={`min-w-0 truncate text-[13px] font-medium tracking-[0.5px] uppercase ${ton.texte}`}
        >
          {marche.libelle}
        </h2>
        <span
          className={`shrink-0 rounded-full px-2 py-0.5 text-[11px] font-medium ${
            epinglesIci > 0
              ? `${ton.surfaceForte} ${ton.texte}`
              : ton.texteDoux
          }`}
        >
          {epinglesIci > 0
            ? `${epinglesIci} en favoris`
            : `${marche.cotes.length} pilotes`}
        </span>
      </header>

      {/* Les rangées sont séparées par leur seul rythme vertical, jamais par un
          filet : la section 5 proscrit les traits fins, et une liste de
          vingt-deux lignes soulignées serait un tableau, pas un widget. */}
      <ul className="px-4 py-1">
        {marche.cotes.map((cote) => {
          const epingle = epingles.has(cote.id);
          return (
            <li
              key={cote.id}
              className="flex items-center justify-between gap-3 py-2"
            >
              <span className="text-texte min-w-0 flex-1 truncate text-[15px] font-medium">
                {cote.pilote}
              </span>
              <span className="flex items-center gap-2.5">
                {/* La case de points passe à l'ambre du bloc dès que la cote est
                    épinglée : la ligne entière dit alors « retenue », et pas
                    seulement l'étoile de 18px posée au bout. */}
                <span
                  className={`rounded-[10px] px-2.5 py-1.5 text-[14px] font-medium ${
                    epingle ? "bg-accent/15 text-texte" : "bg-fond text-texte"
                  }`}
                >
                  {formaterPoints(cote.points)}
                </span>
                {!ferme && (
                  <EtoileFavori
                    nom={cote.pilote}
                    favori={epingle}
                    onClick={() => onBasculer(cote, marche)}
                  />
                )}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/**
 * Rangée de pastilles « MES FAVORIS », défilant à l'horizontale.
 *
 * Le défilement est calé sur les pastilles (`snap-x`) : un doigt qui pousse la
 * rangée la laisse en place sur une pastille entière, jamais coupée en deux.
 * C'est la seule surface de l'app qui défile à l'horizontale, et c'est ce qui la
 * distingue d'un débordement accidentel.
 */
function RangeeFavoris({ favoris }) {
  return (
    <div className="-mx-4 flex snap-x snap-mandatory gap-2 overflow-x-auto px-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {favoris.map((favori) => (
        <span
          key={favori.id_outcome_unibet}
          className="rounded-champ bg-surface shadow-carte flex shrink-0 snap-start items-center gap-1.5 py-2 pr-2.5 pl-2.5"
        >
          <IconeEtoile pleine className="text-accent size-3.5 shrink-0" />
          <span className="text-texte text-[13px] font-medium">
            {favori.pilote ?? "Cote retirée"}
          </span>
          {favori.points !== null && favori.points !== undefined && (
            <span className="bg-accent/15 text-texte rounded-md px-1.5 py-0.5 text-[11px] font-medium">
              {formaterPoints(favori.points)}
            </span>
          )}
        </span>
      ))}
    </div>
  );
}

/** Maquette 08 — tableau des cotes du prochain GP, et mise en favori. */
export default function Cotes() {
  const { gpId } = useParams();
  const naviguer = useNavigate();
  const { utilisateur } = useAuth();

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

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <EnTeteEcran titre="Les cotes" retourVers="/accueil" libelleRetour="Accueil" />
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
        retourVers="/accueil"
        libelleRetour={gp?.nom ?? "Accueil"}
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
              <div className="flex flex-col gap-3">
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
                    {favoris.length > 0 && (
                      <div className="flex flex-col gap-2">
                        <p className="text-label text-texte-doux px-1 uppercase">
                          Mes favoris
                        </p>
                        <RangeeFavoris favoris={favoris} />
                      </div>
                    )}

                    {erreurFavori && (
                      <Alerte ton="erreur" tentative={tentative}>
                        {erreurFavori}
                      </Alerte>
                    )}

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
            tout le tableau après chaque étoile épinglée. Elle rend elle-même la
            zone sûre du home indicator (voir `barre-collee` dans index.css) et
            n'est pas enveloppée dans un `Bloc` : `t-stagger-line` porte un
            `transform`, et un ancêtre transformé casse le collage. */}
        <div className="barre-collee pleine-largeur px-4">
          <Bouton
            variante="principal"
            onClick={() => naviguer(`/grands-prix/${gpId}/pronostics`)}
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
