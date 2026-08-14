import { useCallback, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Onglets from "../composants/Onglets.jsx";
import EtoileFavori from "../composants/EtoileFavori.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { Barre, Carte, Pave } from "../composants/Squelette.jsx";
import { IconeEtoile } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { basculerFavori, chargerTableauCotes } from "../lib/pronostics.js";
import { oublierCache, useDonnees } from "../lib/useDonnees.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";

function SqueletteCotes() {
  return (
    <div className="flex flex-col gap-3">
      {/* La piste des onglets garde sa surface blanche : elle a la même forme
          pleine que le contrôle segmenté qui la remplace. */}
      <div className="bg-surface h-[52px] rounded-full" />
      <Carte className="flex flex-col gap-4">
        {[0, 1, 2, 3, 4].map((rang) => (
          <div key={rang} className="flex items-center justify-between gap-3">
            <Barre largeur="w-1/3" />
            <Pave className="h-6 w-20" arrondi="rounded-[10px]" />
          </div>
        ))}
      </Carte>
    </div>
  );
}

/** Rangée de pastilles « MES FAVORIS », défilant à l'horizontale. */
function RangeeFavoris({ favoris }) {
  return (
    <div className="-mx-4 flex gap-2 overflow-x-auto px-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {favoris.map((favori) => (
        <span
          key={favori.id_outcome_unibet}
          className="rounded-champ bg-surface flex shrink-0 items-center gap-1.5 px-3 py-2"
        >
          <IconeEtoile pleine className="text-accent size-3.5" />
          <span className="text-texte text-[13px] font-medium">
            {favori.pilote ?? "Cote retirée"}
          </span>
          {favori.points !== null && favori.points !== undefined && (
            <span className="text-primaire text-[12px] font-medium">
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

  // Seul le choix explicite du joueur est mémorisé ; le marché affiché s'en
  // déduit. Le poser dans un effet ferait rendre une première image sans
  // aucune cote, puis la liste d'un coup — un sursaut à chaque arrivée sur
  // l'écran, y compris quand le cache a déjà tout ce qu'il faut.
  //
  // Le choix est ignoré si le marché a disparu d'un rafraîchissement, et
  // conservé sinon : remettre le premier onglet sous le doigt du joueur parce
  // que les cotes se sont rafraîchies lui ferait perdre sa place.
  const [choixMarche, setChoixMarche] = useState(null);
  const [erreurFavori, setErreurFavori] = useState(null);
  const [tentative, setTentative] = useState(0);
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayerChargement() {
    setTentativeChargement((n) => n + 1);
    recharger();
  }

  const { ferme } = useFermeture(gp?.date_course);

  const affiche =
    marches.find((marche) => marche.marche === choixMarche) ?? marches[0] ?? null;
  const marcheActif = affiche?.marche ?? null;
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
        <Bloc rang={1}>
          <EnTete titre="Les cotes" retourVers="/accueil" />
        </Bloc>
        <Bloc rang={2}>
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
      <Bloc rang={1}>
        <EnTete
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
      </Bloc>

      <div className="mt-2 flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteCotes />}
          >
            {gp && (
              <div className="flex flex-col gap-3">
                {ferme && (
                  <p className="rounded-carte bg-surface text-texte-doux text-corps-sm px-4 py-3">
                    Les pronostics sont fermés. Les cotes restent consultables.
                  </p>
                )}

                {marches.length === 0 ? (
                  <div className="rounded-carte bg-surface px-5 py-8 text-center">
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
                    <Onglets
                      etiquette="Marchés de paris"
                      options={marches.map((marche) => ({
                        cle: marche.marche,
                        libelle: marche.libelle,
                      }))}
                      valeur={marcheActif}
                      onChange={setChoixMarche}
                    />

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

                    {affiche && (
                      <div className="rounded-carte bg-surface px-4 py-3.5">
                        <p className="text-primaire mb-1 text-[12px] font-medium tracking-[0.5px] uppercase">
                          {affiche.libelle}
                        </p>
                        <ul>
                          {affiche.cotes.map((cote) => (
                            <li
                              key={cote.id}
                              className="flex items-center justify-between gap-3 py-2.5"
                            >
                              <span className="text-texte min-w-0 flex-1 truncate text-[14px] font-medium">
                                {cote.pilote}
                              </span>
                              <span className="flex items-center gap-2.5">
                                <span className="bg-fond text-secondaire rounded-[10px] px-2.5 py-1.5 text-[13px] font-medium">
                                  {formaterPoints(cote.points)}
                                </span>
                                {!ferme && (
                                  <EtoileFavori
                                    nom={cote.pilote}
                                    favori={epingles.has(cote.id)}
                                    onClick={() => basculer(cote, affiche)}
                                  />
                                )}
                              </span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </>
                )}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {/* Le bouton reste actif même sans favori : la maquette 09 accepte
            zéro bonus, et un joueur peut vouloir n'entrer que ses deux
            pronostics obligatoires. Un bouton grisé ne dirait pas pourquoi. */}
        <Bloc rang={3}>
          <Bouton
            variante="principal"
            onClick={() => naviguer(`/grands-prix/${gpId}/pronostics`)}
            disabled={!gp || marches.length === 0}
          >
            {ferme ? "Voir mes pronos" : "Valider mes favoris"}
          </Bouton>
        </Bloc>
      </div>
    </Ecran>
  );
}
