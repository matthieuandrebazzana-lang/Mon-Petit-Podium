import { useCallback, useEffect, useState } from "react";
import { Link, useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Pastille from "../composants/Pastille.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import { Pave } from "../composants/Squelette.jsx";
import {
  IconeCalendrier,
  IconeChevronDroit,
  IconeCoche,
  IconeCopie,
  IconeSortie,
  IconeVoiture,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerChampionnat, quitterChampionnat } from "../lib/championnats.js";
import {
  chargerClassement,
  cleClassement,
  saisonCommencee,
} from "../lib/classement.js";
import { formaterPoints } from "../lib/format.js";
import { couleurChampionnat, tonalites } from "../lib/couleurs.js";
import { couleurLisible, encreSur } from "../lib/palette.js";
import { oublierCache, useDonnees } from "../lib/useDonnees.js";

const DUREE_CONFIRMATION = 2000;

/**
 * En-tête coloré du championnat, désormais rétractable.
 *
 * La barre de retour est collée en haut et porte la couleur du championnat en
 * permanence ; le nom, lui, vit dans l'aplat juste dessous et glisse sous la
 * barre au défilement, où il se replace en petit. C'est la barre de navigation
 * teintée d'iOS, et c'est `EnTeteEcran` qui en porte toute la mécanique — la
 * couleur passe derrière la Dynamic Island, jamais le texte.
 *
 * Le tracé du circuit n'y figure pas : un championnat n'est pas un Grand Prix.
 * L'aplat porte en revanche sa lumière spéculaire, comme les cartes de
 * l'accueil, pour que les deux écrans se répondent.
 */
function heroChampionnat(couleur) {
  return { hex: couleur.hex, fond: couleur.fond, ton: tonalites(couleur.hex) };
}

/**
 * Bloc du code d'invitation.
 *
 * *Écart assumé par rapport à l'état antérieur* : il était un aplat rouge, il
 * devient une carte blanche dont seul le code prend la couleur du championnat.
 * Deux aplats de couleur pleine à la suite — l'en-tête puis le code — se
 * seraient disputé le même écran, et le rouge de la marque sous un en-tête
 * violet aurait donné deux couleurs concurrentes sur une même page. Une seule
 * couleur par écran, portée par l'en-tête : c'est aussi ce que demande le
 * verrou de cohérence du skill Taste.
 */
function BlocCode({ code, couleur, miseEnAvant }) {
  const [copie, setCopie] = useState(false);
  const [echec, setEchec] = useState(false);
  const ton = tonalites(couleur.hex);

  useEffect(() => {
    if (!copie) return undefined;
    const minuterie = setTimeout(() => setCopie(false), DUREE_CONFIRMATION);
    return () => clearTimeout(minuterie);
  }, [copie]);

  async function copier() {
    try {
      // `navigator.clipboard` n'existe qu'en contexte sécurisé. En HTTP simple
      // — un test depuis le réseau local, par exemple — l'appel n'existe pas :
      // on le dit au lieu de laisser un bouton qui ne fait rien.
      if (!navigator.clipboard) throw new Error("presse-papiers indisponible");
      await navigator.clipboard.writeText(code);
      setEchec(false);
      setCopie(true);
    } catch {
      setEchec(true);
    }
  }

  return (
    <div className="rounded-carte bg-surface shadow-carte flex items-center gap-3 p-4">
      <div className="min-w-0 flex-1">
        <p className="text-label text-texte-doux uppercase">Code d'invitation</p>
        <p
          className="mt-1 text-[26px] leading-none font-medium tracking-[5px]"
          style={{ color: couleur.hex }}
        >
          {code}
        </p>
        {/* Le retour de création reste dit à l'arrivée sur l'écran : sans lui,
            valider « Créer » débouche sur un écran qui ne confirme rien. */}
        {miseEnAvant && !echec && (
          <p className="text-corps-sm text-texte-doux mt-1.5">
            Championnat créé. Partage ce code pour inviter tes amis.
          </p>
        )}
        {echec && (
          <p role="alert" className="text-corps-sm text-texte-doux mt-2">
            Copie impossible sur cet appareil. Note le code : {code}
          </p>
        )}
      </div>

      <button
        type="button"
        onClick={copier}
        className={`rounded-champ pressable min-h-tactile flex shrink-0 items-center gap-2 px-3.5 text-[13px] font-medium ${couleur.fond} ${ton.texte}`}
      >
        {copie ? (
          <IconeCoche className="size-3.5" />
        ) : (
          <IconeCopie className="size-3.5" />
        )}
        <TexteEchange valeur={copie ? "Copié" : "Copier"} />
      </button>
    </div>
  );
}

/**
 * Une ligne du classement — carte blanche à filet coloré, refonte de la
 * maquette 07. Exportée nommément pour pouvoir être rendue hors navigateur : le
 * composant d'écran dépend de la session, qui ne se résout que dans un effet.
 *
 * Le filet de 4px porte la couleur de la **voiture du membre**, pas celle du
 * championnat : c'est la personne qu'on cherche à reconnaître dans une liste, et
 * c'est la même couleur qu'elle porte sur la vue piste et sur son profil. Ce
 * n'est pas une bordure au sens de la section 5 — la section proscrit les traits
 * fins qui cernent un bloc ; celui-ci est un aplat posé à l'intérieur, et il
 * remplace justement la pastille d'initiale qui tenait ce rôle avant.
 */
export function LigneClassement({ ligne, estMoi, estCreateur, aDesPoints }) {
  const podium = ligne.rang <= 3;

  // Sous-ligne : les deux critères qui départagent avant l'ordre d'inscription
  // (règle 4.6). La maquette y répète le total, déjà affiché à droite ; dire ce
  // qui sépare deux joueurs à égalité de points est plus utile.
  const detail = aDesPoints
    ? [
        `${ligne.pronostics_reussis} ${
          ligne.pronostics_reussis > 1 ? "réussis" : "réussi"
        }`,
        ligne.meilleure_cote
          ? `meilleur coup ${formaterPoints(ligne.meilleure_cote)}`
          : null,
      ]
        .filter(Boolean)
        .join(" · ")
    : "En attente du premier Grand Prix";

  const teinteVoiture = couleurLisible(ligne);

  return (
    <li>
      <Link
        to={`/profils/${ligne.profil_id}`}
        className="rounded-carte bg-surface shadow-carte pressable-large min-h-tactile relative flex items-center gap-3 overflow-hidden py-3 pr-4 pl-4"
      >
        <span
          aria-hidden="true"
          className="absolute inset-y-0 left-0 w-1"
          style={{ backgroundColor: teinteVoiture }}
        />

        {/* Le rang des trois premiers est posé dans une pastille à la couleur de
            la voiture du membre, les autres restent en chiffre nu. Le podium
            doit se repérer sans lire les nombres — c'est la hiérarchie visuelle
            du §16 d'/apple-design : le plus important est aussi le plus
            évident. L'encre de la pastille est calculée pour rester lisible
            quelle que soit la livrée choisie. */}
        {podium ? (
          <span
            className="flex size-8 shrink-0 items-center justify-center rounded-full text-[15px] leading-none font-medium"
            style={{
              backgroundColor: teinteVoiture,
              color: encreSur(teinteVoiture),
            }}
          >
            {ligne.rang}
          </span>
        ) : (
          <span className="text-texte-doux flex size-8 shrink-0 items-center justify-center text-[17px] leading-none font-medium">
            {ligne.rang}
          </span>
        )}

        <div className="min-w-0 flex-1">
          <p className="text-corps-sm text-texte truncate font-medium">
            {ligne.pseudo}
            {estMoi && <span className="text-primaire"> · Toi</span>}
            {estCreateur && <span className="text-texte-doux"> · Créateur</span>}
          </p>
          <p className="text-texte-doux mt-0.5 truncate text-[12px]">{detail}</p>
        </div>

        <div className="shrink-0 text-right">
          <p className="text-primaire text-[22px] leading-none font-medium tracking-[-0.02em]">
            {ligne.total_points}
          </p>
          <p className="text-label-sm text-texte-doux mt-1 uppercase">pts</p>
        </div>
      </Link>
    </li>
  );
}

function SqueletteChampionnat() {
  return (
    <div className="flex flex-col gap-3">
      <Pave className="h-[86px]" arrondi="rounded-carte" />
      <div className="flex flex-col gap-2">
        {[0, 1, 2].map((rang) => (
          <Pave key={rang} className="h-[70px]" arrondi="rounded-carte" />
        ))}
      </div>
    </div>
  );
}

/** Maquette 07 — vue d'un championnat : en-tête coloré, code, classement. */
export default function Championnat() {
  const { id } = useParams();
  const naviguer = useNavigate();
  const emplacement = useLocation();
  const { utilisateur } = useAuth();

  const nouveau = Boolean(emplacement.state?.nouveau);

  // Comme pour l'accueil, la clé de cache porte le compte : un championnat lu
  // par quelqu'un d'autre sur le même appareil ne doit pas ressortir ici.
  const cle = utilisateur ? `championnat:${utilisateur.id}:${id}` : null;
  const chargeur = useCallback((signal) => chargerChampionnat(id, signal), [id]);
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);

  // Le classement suit son propre chemin : il passe par l'API, là où le détail
  // du championnat se lit directement dans Supabase. Les deux chargements sont
  // donc indépendants — et c'est voulu. Si Railway se réveille lentement, ou
  // même s'il échoue, le championnat et ses membres restent affichés.
  const cleRang = utilisateur ? cleClassement(utilisateur.id, id) : null;
  const chargeurRang = useCallback(
    (signal) => chargerClassement(id, signal),
    [id],
  );
  const {
    donnees: classement,
    chargement: chargementRang,
    echec: echecRang,
    recharger: rechargerRang,
  } = useDonnees(cleRang, chargeurRang);

  const [confirmation, setConfirmation] = useState(false);
  const [depart, setDepart] = useState(false);
  const [erreurDepart, setErreurDepart] = useState(null);
  const [tentative, setTentative] = useState(0);
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayer() {
    setTentativeChargement((n) => n + 1);
    recharger();
    rechargerRang();
  }

  async function quitter() {
    setDepart(true);
    setErreurDepart(null);
    setTentative((n) => n + 1);

    const resultat = await quitterChampionnat(id);

    if (!resultat.ok) {
      setDepart(false);
      setConfirmation(false);
      setErreurDepart(resultat.message);
      return;
    }

    if (cle) oublierCache(cle);
    if (utilisateur) oublierCache(`championnats:${utilisateur.id}`);
    naviguer("/accueil", { replace: true });
  }

  // La couleur est calculée sur ce qu'on sait déjà : l'identifiant de l'URL
  // suffit, elle ne dépend donc pas du chargement. L'en-tête est peint dès la
  // première image, et ne change pas de teinte quand les données arrivent.
  const couleur = couleurChampionnat({ id, ...(donnees ?? {}) });

  const teinte = heroChampionnat(couleur);

  // Sortie de secours : sans championnat lisible, il n'y a rien à afficher, et
  // l'écran ne doit surtout pas être un cul-de-sac.
  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <EnTeteEcran
          titre="Championnat"
          sousTitre="Saison 2026"
          retourVers="/accueil"
          libelleRetour="Accueil"
          teinte={teinte}
        />
        <Bloc rang={1} className="mt-3">
          <BlocErreur
            echec={echec}
            onReessayer={reessayer}
            tentative={tentativeChargement}
          />
        </Bloc>
      </Ecran>
    );
  }

  const membres = donnees?.membres ?? [];
  const lignes = classement ?? [];
  // L'effectif vient du classement dès qu'il est là : c'est la seule des deux
  // sources qui compte les membres sans dépendre de la RLS.
  const effectif = lignes.length || membres.length;
  const aDesPoints = saisonCommencee(lignes);

  return (
    <Ecran direction="avant">
      <EnTeteEcran
        titre={donnees?.nom ?? "Championnat"}
        sousTitre={
          chargement && !donnees
            ? "Chargement…"
            : `${effectif} ${effectif > 1 ? "membres" : "membre"} · Saison 2026`
        }
        retourVers="/accueil"
        libelleRetour="Accueil"
        teinte={teinte}
      />

      <div className="mt-3 flex flex-1 flex-col gap-3">
        <Bloc rang={1}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteChampionnat />}
          >
            {donnees && (
              <div className="flex flex-col gap-3">
                <BlocCode
                  code={donnees.code_invitation}
                  couleur={couleur}
                  miseEnAvant={nouveau}
                />

                <div className="flex flex-col gap-2">
                  <p className="text-label text-texte-doux px-1 uppercase">
                    {lignes.length > 0 ? "Classement" : "Membres"}
                  </p>

                  {/* Le classement remplace la liste des membres dès qu'il est
                      là. Tant qu'il n'est pas revenu — Railway se réveille — la
                      liste lue sous RLS tient sa place : elle porte les mêmes
                      personnes, sans les points. Un bloc vide serait pire. */}
                  {lignes.length > 0 ? (
                    <ul className="flex flex-col gap-2">
                      {lignes.map((ligne) => (
                        <LigneClassement
                          key={ligne.profil_id}
                          ligne={ligne}
                          estMoi={ligne.profil_id === utilisateur?.id}
                          estCreateur={ligne.profil_id === donnees.cree_par}
                          aDesPoints={aDesPoints}
                        />
                      ))}
                    </ul>
                  ) : (
                    <ul className="flex flex-col gap-2">
                      {membres.map((membre) => (
                        <li key={membre.id}>
                          <Link
                            to={`/profils/${membre.id}`}
                            className="rounded-carte bg-surface shadow-carte pressable-large min-h-tactile flex items-center gap-3 p-4"
                          >
                            <Pastille nom={membre.pseudo} graine={membre.id} />
                            <span className="text-corps-sm text-texte min-w-0 flex-1 truncate font-medium">
                              {membre.pseudo}
                            </span>
                            {membre.id === donnees.cree_par && (
                              <span className="text-label-sm text-texte-doux uppercase">
                                Créateur
                              </span>
                            )}
                            {membre.id === utilisateur?.id && (
                              <span className="text-label-sm text-primaire uppercase">
                                Toi
                              </span>
                            )}
                          </Link>
                        </li>
                      ))}
                    </ul>
                  )}

                  {lignes.length === 0 && chargementRang && (
                    <p className="text-texte-doux mt-1 px-1 text-[12px]">
                      <span
                        className="t-shimmer"
                        data-text="Classement en cours de chargement…"
                      >
                        Classement en cours de chargement…
                      </span>
                    </p>
                  )}

                  {/* Le classement a échoué mais les membres sont là : on le
                      dit sous la liste, sans emporter l'écran. C'est le même
                      arbitrage que depuis l'étape 7 — deux chargements
                      indépendants, et celui qui tient debout reste affiché. */}
                  {lignes.length === 0 && !chargementRang && echecRang && (
                    <div className="mt-2">
                      <BlocErreur
                        echec={echecRang}
                        onReessayer={reessayer}
                        tentative={tentativeChargement}
                      />
                    </div>
                  )}
                </div>

                {/* Le calendrier du championnat (maquette 15). */}
                <Link
                  to={`/championnats/${id}/calendrier`}
                  className="rounded-carte bg-surface shadow-carte pressable-large min-h-tactile flex items-center gap-3 p-4"
                >
                  <span
                    aria-hidden="true"
                    className="bg-fond rounded-champ flex size-10 shrink-0 items-center justify-center"
                    style={{ color: couleur.hex }}
                  >
                    <IconeCalendrier className="size-[18px]" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="text-corps text-texte block font-medium">
                      Calendrier
                    </span>
                    <span className="text-texte-doux mt-0.5 block text-[12px]">
                      Les Grands Prix de la saison, un par un
                    </span>
                  </span>
                  <IconeChevronDroit className="text-texte-doux size-4 shrink-0" />
                </Link>
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {erreurDepart && (
          <Alerte ton="erreur" tentative={tentative}>
            {erreurDepart}
          </Alerte>
        )}

        {/* La vue piste passe de la bascule segmentée à un bouton pleine
            largeur, comme demandé. Les deux ensemble auraient offert deux
            chemins vers le même écran, à trois centimètres l'un de l'autre.
            L'écran de piste, lui, ramène ici par son propre bouton de retour :
            l'aller-retour reste symétrique. */}
        <Bloc rang={2} className="flex flex-col gap-2.5">
          {confirmation ? (
            <>
              <Bouton
                variante="principal"
                onClick={quitter}
                occupe={depart}
                libelleOccupe="Départ…"
                icone={<IconeSortie className="size-4" />}
              >
                Confirmer mon départ
              </Bouton>
              <button
                type="button"
                onClick={() => setConfirmation(false)}
                disabled={depart}
                className="text-texte-doux min-h-tactile pressable py-2 text-center text-[13px] font-medium"
              >
                Annuler
              </button>
            </>
          ) : (
            <>
              <Bouton
                variante="principal"
                onClick={() => naviguer(`/championnats/${id}/piste`)}
                icone={<IconeVoiture className="size-5" />}
              >
                Vue piste
              </Bouton>
              <button
                type="button"
                onClick={() => setConfirmation(true)}
                disabled={!donnees}
                className="text-texte-doux min-h-tactile pressable py-2 text-center text-[13px] font-medium disabled:opacity-50"
              >
                Quitter le championnat
              </button>
            </>
          )}
        </Bloc>
      </div>
    </Ecran>
  );
}
