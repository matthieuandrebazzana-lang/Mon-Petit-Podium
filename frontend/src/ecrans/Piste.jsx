import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import Voiture from "../composants/Voiture.jsx";
import { IconeChevronGauche } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import { chargerChampionnat } from "../lib/championnats.js";
import { chargerClassement, cleClassement } from "../lib/classement.js";
import { livreePour } from "../lib/livrees.js";
import { useDonnees } from "../lib/useDonnees.js";

/**
 * Maquette 07b — la vue piste, écran signature de l'app.
 *
 * Une route occupe tout l'écran : asphalte sombre, bordures rouge et blanc sur
 * les deux côtés, ligne pointillée centrale, ligne d'arrivée en damier tout en
 * haut. Aucun fond beige n'est visible. Les voitures sont réparties
 * verticalement selon les points — le leader près de l'arrivée, le dernier en
 * bas — et le pseudo et le score s'affichent à droite de chacune.
 *
 * **Écart assumé par rapport à la maquette 07b**, et il vient de la demande
 * elle-même : la maquette garde l'en-tête du championnat et la bascule
 * Classement / Piste au-dessus de la route, ainsi que la barre de navigation
 * basse. Ici la route occupe l'écran entier, et un unique bouton de retour en
 * haut à gauche ramène au classement. C'est l'écran signature : lui laisser
 * 150px de chrome au-dessus reviendrait à en faire un widget de plus.
 *
 * Le bouton nomme sa destination (« Classement ») plutôt que d'afficher un
 * « Retour » générique : c'est le seul moyen de sortir d'ici, il doit dire où
 * il mène.
 */

// Largeur de la voiture, et hauteur qui s'en déduit du rapport du viewBox
// (275.12 × 332.75). Les deux sont fixes : c'est la piste qui s'adapte à
// l'écran, pas la voiture, dont le numéro deviendrait illisible en dessous.
const LARGEUR_VOITURE = 56;
const HAUTEUR_VOITURE = Math.round(LARGEUR_VOITURE * (332.75 / 275.12));

// Marge au-dessus de la première voiture et au-dessous de la dernière.
const MARGE_HAUTE = 16;
const MARGE_BASSE = 12;

// Écart vertical souhaité entre deux voitures. En dessous, elles se
// chevauchent ; au-delà, la piste se vide inutilement.
const ECART_SOUHAITE = Math.round(HAUTEUR_VOITURE * 0.78);

// Décalage d'entrée entre deux voitures — doit rester égal à --voiture-stagger.
const RETARD_ENTREE = 100;

/**
 * Position verticale (le centre) de chaque voiture, du leader au dernier.
 *
 * La hauteur est **proportionnelle aux points** : le leader se pose tout en
 * haut, quelqu'un à la moitié de ses points se pose à mi-piste. Si personne n'a
 * encore marqué, la fraction vaut zéro pour tout le monde et les voitures se
 * regroupent en bas — la grille de départ avant le premier Grand Prix.
 *
 * Deux passes de relaxation suivent le placement proportionnel, et elles ne
 * sont pas un ornement : sans elles, deux membres séparés de dix points
 * verraient leurs voitures se superposer, et la vue ne dirait plus rien. La
 * passe descendante impose l'écart minimal depuis le leader, la passe montante
 * rattrape ce qui a débordé en bas. L'écart minimal est plafonné à la place
 * réellement disponible, ce qui garantit que tout le monde tient à l'écran quel
 * que soit le nombre de membres (règle 4.5 : aucune limite).
 */
export function positionsDesVoitures(lignes, hauteur) {
  const nombre = lignes.length;
  if (nombre === 0 || hauteur <= 0) return [];

  const haut = MARGE_HAUTE + HAUTEUR_VOITURE / 2;
  const bas = Math.max(haut, hauteur - MARGE_BASSE - HAUTEUR_VOITURE / 2);
  const course = bas - haut;

  const maximum = Math.max(...lignes.map((ligne) => ligne.total_points ?? 0), 0);

  const positions = lignes.map((ligne) => {
    const fraction = maximum > 0 ? (ligne.total_points ?? 0) / maximum : 0;
    return bas - fraction * course;
  });

  const ecart = nombre > 1 ? Math.min(ECART_SOUHAITE, course / (nombre - 1)) : 0;

  for (let i = 1; i < nombre; i += 1) {
    positions[i] = Math.max(positions[i], positions[i - 1] + ecart);
  }
  positions[nombre - 1] = Math.min(positions[nombre - 1], bas);
  for (let i = nombre - 2; i >= 0; i -= 1) {
    positions[i] = Math.min(positions[i], positions[i + 1] - ecart);
  }

  return positions;
}

/**
 * Une voiture sur la piste, et sa légende.
 *
 * Voiture et légende vivent dans **une seule rangée** positionnée en absolu.
 * Deux éléments placés séparément, l'un au centre et l'autre à droite,
 * finiraient par se décaler d'un pixel ou deux ; ici l'alignement est une
 * conséquence de la structure, pas d'un calcul à tenir en double.
 *
 * Exporté nommément pour pouvoir être rendu hors navigateur : le composant
 * d'écran, lui, dépend de la session, qui ne se résout que dans un effet.
 */
export function LigneDePiste({ ligne, centre, hauteur, retard, estMoi }) {
  const livree = livreePour(ligne.ordre_inscription);

  return (
    <div
      className="t-voiture absolute inset-x-0"
      style={{
        top: `${centre - HAUTEUR_VOITURE / 2}px`,
        height: `${HAUTEUR_VOITURE}px`,
        // Chaque voiture part du bas de l'écran : la distance dépend de son
        // point d'arrivée, une valeur commune ferait démarrer le leader du
        // milieu de la piste.
        "--voiture-depart": `${hauteur - centre + HAUTEUR_VOITURE}px`,
        "--voiture-retard": `${retard}ms`,
      }}
    >
      <Voiture
        couleur1={livree.couleur1}
        couleur2={livree.couleur2}
        numero={ligne.rang}
        nom={ligne.pseudo}
        titre={`${ligne.rang}. ${ligne.pseudo}, ${ligne.total_points} points`}
        className="absolute left-1/2 h-full -translate-x-1/2"
      />

      {/* Légende alignée sur la voiture. L'ombre portée n'est pas décorative :
          ce texte passe tantôt sur l'asphalte, tantôt sur une bordure blanche,
          et doit rester lisible sur les deux. */}
      <div className="absolute top-1/2 right-7 -translate-y-1/2 text-right [text-shadow:0_1px_3px_rgba(0,0,0,0.8)]">
        <p className="text-[15px] leading-none font-medium text-white">
          {ligne.total_points}
        </p>
        <p className="text-label-sm mt-1 text-white/70">pts</p>
        <p
          className={`mt-1.5 max-w-[86px] truncate text-[11px] ${
            estMoi ? "font-medium text-white" : "text-white/70"
          }`}
        >
          {ligne.pseudo}
        </p>
      </div>
    </div>
  );
}

export default function Piste() {
  const { id } = useParams();
  const naviguer = useNavigate();
  const { utilisateur } = useAuth();

  const cleChamp = utilisateur ? `championnat:${utilisateur.id}:${id}` : null;
  const chargeurChamp = useCallback(
    (signal) => chargerChampionnat(id, signal),
    [id],
  );
  const { donnees: championnat } = useDonnees(cleChamp, chargeurChamp);

  const cle = utilisateur ? cleClassement(utilisateur.id, id) : null;
  const chargeur = useCallback((signal) => chargerClassement(id, signal), [id]);
  const { donnees, chargement } = useDonnees(cle, chargeur);

  const lignes = useMemo(() => donnees ?? [], [donnees]);

  // La hauteur de la piste dépend de l'écran, et sur iOS elle change quand la
  // barre d'adresse de Safari se rétracte. Elle est donc mesurée, pas devinée.
  const zone = useRef(null);
  const [hauteur, setHauteur] = useState(0);

  useEffect(() => {
    const element = zone.current;
    if (!element) return undefined;

    const observateur = new ResizeObserver(([entree]) => {
      setHauteur(entree.contentRect.height);
    });
    observateur.observe(element);
    return () => observateur.disconnect();
  }, []);

  // Les voitures montent une fois qu'elles ont une position à rejoindre :
  // les lancer avant la mesure les ferait converger vers zéro puis sauter.
  const [enPiste, setEnPiste] = useState(false);
  useEffect(() => {
    if (hauteur <= 0 || lignes.length === 0) return undefined;
    const image = requestAnimationFrame(() => setEnPiste(true));
    return () => cancelAnimationFrame(image);
  }, [hauteur, lignes.length]);

  const positions = useMemo(
    () => positionsDesVoitures(lignes, hauteur),
    [lignes, hauteur],
  );

  return (
    <main
      className={`piste-fond t-piste fixed inset-0 flex flex-col overflow-hidden ${
        enPiste ? "is-en-piste" : ""
      }`}
    >
      {/* Bordures et ligne médiane : posées sous tout le reste, sur toute la
          hauteur de l'écran, y compris derrière les zones sûres. Une piste qui
          s'arrêterait à la Dynamic Island se lirait comme un bandeau. */}
      <div
        aria-hidden="true"
        className="piste-kerb pointer-events-none absolute inset-y-0 left-0"
      />
      <div
        aria-hidden="true"
        className="piste-kerb pointer-events-none absolute inset-y-0 right-0"
      />
      <div
        aria-hidden="true"
        className="piste-axe pointer-events-none absolute inset-y-0 left-1/2 -translate-x-1/2"
      />

      <header
        className="relative z-10 shrink-0 px-7 pb-3"
        style={{
          // Le bouton ne doit pas venir se coller sous la Dynamic Island :
          // la zone sûre s'ajoute au rembourrage, elle ne le remplace pas.
          paddingTop: "calc(var(--spacing-safe-top) + 12px)",
        }}
      >
        <button
          type="button"
          onClick={() => naviguer(`/championnats/${id}`)}
          className="min-h-tactile pressable -mx-2 -my-2 flex items-center gap-1.5 px-2 py-2 text-[13px] font-medium text-white"
        >
          <IconeChevronGauche className="size-[15px] shrink-0" />
          <span className="truncate">Classement</span>
        </button>
      </header>

      {/* Ligne d'arrivée, immédiatement sous le bouton : c'est elle qui donne
          son sens à la hauteur des voitures. Sans elle, « en haut » ne
          voudrait rien dire. */}
      <div className="relative z-[5] shrink-0 px-5">
        <div aria-hidden="true" className="piste-arrivee h-[5px] w-full" />
        <p className="text-label-sm mt-1.5 uppercase text-white/70">Arrivée</p>
      </div>

      <div ref={zone} className="relative flex-1">
        {lignes.map((ligne, index) => (
          <LigneDePiste
            key={ligne.profil_id}
            ligne={ligne}
            centre={positions[index] ?? 0}
            hauteur={hauteur}
            retard={index * RETARD_ENTREE}
            estMoi={ligne.profil_id === utilisateur?.id}
          />
        ))}

        {lignes.length === 0 && (
          <p className="text-corps-sm absolute inset-x-10 top-1/2 -translate-y-1/2 text-center text-white/60">
            {chargement
              ? "Chargement du championnat…"
              : "Aucun membre à afficher sur la piste."}
          </p>
        )}
      </div>

      {/* Le nom du championnat ferme l'écran en bas, au-dessus du home
          indicator : il dit de quel championnat on regarde la piste, sans
          rajouter d'en-tête. */}
      <footer
        className="relative z-10 shrink-0 px-7 pt-2"
        style={{
          // `pb-safe-bottom` et `pb-3` écriraient la même propriété : la marge
          // du home indicator s'ajoute au rembourrage, elle ne le remplace pas.
          paddingBottom: "calc(var(--spacing-safe-bottom) + 12px)",
        }}
      >
        <p className="text-label truncate text-center uppercase text-white/50">
          {championnat?.nom ?? ""}
        </p>
      </footer>
    </main>
  );
}
