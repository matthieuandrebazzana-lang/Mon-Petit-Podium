import { Link } from "react-router-dom";
import TraceCircuitGp, { aUnTrace } from "./TracesCircuits.jsx";
import { APPARENCE_REPLI, VoileDrapeau, drapeauDuGp } from "./DrapeauxGP.jsx";
import { actionDuGp, etatDuGpSaison, jourDe } from "../lib/calendrier2026.js";

/**
 * La carte d'un Grand Prix de la saison — l'unité de l'onglet Calendrier.
 *
 * Le fichier de référence est `assets/calendrier.svg`, qui dessine les douze
 * widgets de la fin de saison : le pays en haut à gauche, le quantième en très
 * grand sous lui, le circuit à droite, et le tracé posé sur l'aplat de couleur.
 *
 * **Deux zones.** En haut le drapeau du pays hôte et le tracé de son circuit ;
 * en bas les informations, sur fond blanc. La zone haute reprend **exactement
 * le mécanisme de couleur du bloc de l'accueil** — même clé (`slugCircuit`),
 * même table de drapeaux, même voile calculé, même surcouche uniforme. Un Grand
 * Prix se reconnaît donc à ses couleurs d'un écran à l'autre, ce qui n'arriverait
 * pas si le calendrier se peignait tout seul.
 *
 * **La carte n'est pas pleine largeur**, contrairement à celles du calendrier
 * d'un championnat : elle garde les 16px de marge latérale d'`ecran` et les 24px
 * de rayon du design system sur ses quatre coins. C'est ce qui la met à la
 * largeur des autres widgets de l'application — cartes de championnat, blocs de
 * l'accueil — au lieu d'en faire un bandeau à part.
 */

/** Hauteur de la zone du drapeau. Écrite une fois : le squelette la reprend,
 *  sans quoi la liste sauterait de 180px par carte à l'arrivée des données. */
export const HAUTEUR_DRAPEAU = 180;

export default function CarteGpSaison({ gp, chargement = false }) {
  const etat = etatDuGpSaison(gp);
  const action = actionDuGp(gp, etat);
  const jour = jourDe(gp.date);

  // Le pays hôte donne à la fois les couleurs de la carte et le tracé du
  // circuit. Une seule clé pour les deux : la faire deux fois laisserait les
  // deux tables se désynchroniser sur un libellé retouché.
  const drapeau = drapeauDuGp(gp.slug) ?? APPARENCE_REPLI;
  const trace = aUnTrace(gp.slug);

  return (
    <article className="rounded-bloc bg-surface shadow-carte overflow-hidden">
      {/* ------------------------------------------------------------------
          Zone haute — le drapeau et le tracé.

          La pile de calques est celle du bloc de l'accueil, dans le même
          ordre : lumière spéculaire, voile calculé du drapeau, surcouche
          uniforme de 15 %, puis le tracé.

          **Les 15 % ne suffisent pas seuls, et c'est mesuré.** Sur la bande
          blanche d'un drapeau néerlandais, un trait blanc à 60 % posé sur du
          blanc à peine assombri reste invisible. Le voile calculé par drapeau
          (version `0.15.0`) est donc conservé dessous : il ramène cette bande
          au gris moyen, et le trait y tient alors 2,70:1. Aucun texte ne
          traverse cette zone — la garantie de 3:1 de l'accueil n'a rien à y
          protéger, elle sert ici le seul tracé.
          ------------------------------------------------------------------ */}
      <div
        className={`relative ${drapeau.fond ? "" : "bg-primaire"}`}
        style={{
          height: `${HAUTEUR_DRAPEAU}px`,
          ...(drapeau.fond ? { background: drapeau.fond } : {}),
        }}
      >
        <div
          aria-hidden="true"
          className="lueur-haute pointer-events-none absolute inset-0"
        />
        <VoileDrapeau voile={drapeau.voile} />
        {drapeau.fond && (
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 bg-black/15"
          />
        )}

        {/* `boiteLibre` coupe le rapport de forme que le composant pose en
            ligne : la bande fixe ici les deux dimensions, et c'est le travail
            de `xMidYMid meet` de mettre chaque circuit à l'échelle dedans.
            Bakou, 3,4 fois plus large que haut, remplit la largeur ;
            Zandvoort, presque carré, remplit la hauteur. Chacun garde sa vraie
            forme au lieu d'être étiré pour occuper la même surface.

            Sans tracé, la zone reste le drapeau seul : un motif de repli
            laisserait croire que ce Grand Prix se court sur cette forme-là. */}
        {trace && (
          <TraceCircuitGp
            slug={gp.slug}
            epaisseur={3}
            boiteLibre
            className="pointer-events-none absolute inset-0 h-full w-full px-6 py-5 text-white/60"
          />
        )}
      </div>

      {/* ------------------------------------------------------------------
          Zone basse — deux colonnes, comme la planche de référence.

          `items-baseline` et non `items-start` : le pays et le nom du Grand
          Prix n'ont pas la même taille, et deux colonnes calées par le haut
          feraient partir leurs premières lignes sur deux lignes de base
          distinctes, à quelques pixels l'une de l'autre. C'est le genre
          d'écart qu'on ne nomme pas mais qu'on voit.
          ------------------------------------------------------------------ */}
      <div className="p-4">
        <div className="flex items-baseline justify-between gap-4">
          <div className="shrink-0">
            <p className="text-texte-doux text-[11px]">{gp.pays}</p>
            {/* Le quantième est le repère de la carte : c'est par lui qu'on
                cherche « le prochain ». Graisse 700 et 48px sont demandés, et
                s'écartent de la section 5 du CLAUDE.md, qui réserve le 700 aux
                numéros de voiture — écart assumé et borné à ce chiffre.
                Le crénage négatif suit /apple-design §15 : un chiffre n'a ni
                jambage ni hampe, rien ne vient remplir l'espace entre deux
                caractères. */}
            <p className="text-primaire mt-1 text-[48px] leading-none font-bold tracking-[-0.03em]">
              {jour ?? "—"}
            </p>
            <p className="text-texte-doux text-label-sm mt-1.5">{gp.mois}</p>
          </div>

          <div className="min-w-0 flex-1 text-right">
            <h2 className="text-texte truncate text-[18px] font-medium">
              {gp.nom}
            </h2>
            <p className="text-texte-doux mt-0.5 truncate text-[11px]">
              {gp.circuit}
            </p>

            {/* Tant que la base n'a pas répondu, l'état est **inconnu** : une
                pastille « À venir » posée par défaut se corrigerait en « Pronos
                ouverts » sous les yeux du joueur, et lui aurait menti l'instant
                d'avant. Une silhouette dit la même chose sans rien affirmer. */}
            {chargement && !gp.en_base ? (
              <span
                aria-hidden="true"
                className="t-skel-bar mt-2.5 inline-block h-[22px] w-24 rounded-[10px] align-middle"
              />
            ) : (
              <span
                className={`mt-2.5 inline-block rounded-[10px] px-2.5 py-1 text-[11px] font-medium ${etat.pastille}`}
              >
                {etat.libelle}
              </span>
            )}
          </div>
        </div>

        {/* Le bouton n'existe que là où il y a quelque chose à faire. Un Grand
            Prix à venir n'a pas encore de cotes ; un Grand Prix fermé n'accepte
            plus rien, et le mener quelque part serait une promesse creuse. */}
        {action && (
          <Link
            to={action.vers}
            className={`rounded-carte-sm pressable min-h-tactile mt-4 flex w-full items-center justify-center px-5 py-3.5 text-center text-[15px] font-medium ${action.style}`}
          >
            {action.libelle}
          </Link>
        )}
      </div>
    </article>
  );
}
