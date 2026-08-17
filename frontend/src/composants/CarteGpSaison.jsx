import { Link } from "react-router-dom";
import TraceCircuitGp, { aUnTrace } from "./TracesCircuits.jsx";
import { APPARENCE_REPLI, VoileDrapeau, drapeauDuGp } from "./DrapeauxGP.jsx";
import { actionDuGp, etatDuGpSaison, jourDe } from "../lib/calendrier2026.js";

/**
 * La carte d'un Grand Prix de la saison — l'unité de l'onglet Calendrier.
 *
 * Le fichier de référence est `assets/calendrier.svg`, et la carte le suit
 * désormais à la lettre : **le drapeau couvre toute la carte**, il n'y a plus de
 * zone blanche séparée en bas, et tout le contenu est posé par-dessus en blanc.
 * La planche dessine exactement cela — un aplat plein aux coins arrondis, le
 * pays en haut à gauche, le quantième en très grand en bas à gauche, le circuit
 * en bas à droite, et le tracé du circuit posé à travers toute la surface.
 *
 * ## Une seule pile de calques, celle du bloc de l'accueil
 *
 * Fond du drapeau, lumière spéculaire, **voile calculé** du drapeau, surcouche
 * uniforme de 15 %, tracé, puis le contenu. C'est l'ordre exact du bloc
 * « Prochain GP » depuis la version `0.16.1`, et il n'est pas indifférent : le
 * voile est ce qui garantit que du texte blanc tient 3:1 sur les sept drapeaux à
 * bande claire, et tout ce qui éclaircit la surface doit donc passer **dessous**.
 *
 * La surcouche est posée sur **toute la carte** et non sur une bande : c'est la
 * correction de la version `0.16.1`, où assombrir une zone seulement coupait un
 * drapeau à bande répétée en deux et faisait paraître le rouge du haut plus vif
 * que celui du bas.
 *
 * ## Ce qui change par rapport à la version `0.20.0`
 *
 * La carte était en deux zones : 180px de drapeau en haut, informations sur fond
 * blanc en bas. Le drapeau n'était donc qu'une vignette. Ici il **est** la carte,
 * et c'est ce que la planche montre.
 *
 * Conséquence directe : le texte croise le tracé du circuit, ce qui n'arrivait
 * pas quand celui-ci avait sa propre zone. D'où l'ombre portée, appliquée à tout
 * le texte de la carte et non aux seuls drapeaux à plusieurs bandes — c'est le
 * traitement que la vue piste applique déjà à sa légende, qui passe tantôt sur
 * l'asphalte et tantôt sur une bordure blanche.
 */

/** Hauteur de la carte. Écrite une fois : le tracé, la bande d'action et le
 *  squelette la partagent, sans quoi la liste sauterait à l'arrivée des données.
 *  La planche donne 810 × 400 unités, soit très exactement ce rapport une fois
 *  ramenée à la largeur d'un iPhone. */
export const HAUTEUR_CARTE = 200;

/** Hauteur de la bande d'action. Elle est **retranchée** de la carte plutôt
 *  qu'ajoutée dessous : les douze cartes gardent la même hauteur, qu'elles
 *  portent un bouton ou non, comme sur la planche. */
const HAUTEUR_BANDE = 46;

/** L'ombre portée du texte.
 *
 *  Le tracé du circuit traverse maintenant toute la carte, et une lettre blanche
 *  posée pile sur un trait blanc à 60 % perd son contour. `apparence()` ne pose
 *  son ombre que sur les drapeaux à plusieurs bandes, parce que la couture était
 *  jusqu'ici la seule chose qu'un texte pouvait croiser ; ici le tracé en est une
 *  seconde, et il existe sur les douze cartes. L'ombre est donc inconditionnelle
 *  — même valeur, pour que les deux écrans ne divergent pas. */
const OMBRE_TEXTE = "[text-shadow:0_1px_3px_rgba(0,0,0,0.45)]";

export default function CarteGpSaison({ gp, chargement = false, retour = null }) {
  const etat = etatDuGpSaison(gp);
  const action = actionDuGp(gp, etat);
  const jour = jourDe(gp.date);

  // Le pays hôte donne à la fois les couleurs de la carte et le tracé du
  // circuit. Une seule clé pour les deux : la faire deux fois laisserait les
  // deux tables se désynchroniser sur un libellé retouché.
  const drapeau = drapeauDuGp(gp.slug) ?? APPARENCE_REPLI;
  const trace = aUnTrace(gp.slug);

  return (
    <article
      className={`rounded-bloc shadow-aplat relative overflow-hidden ${
        drapeau.fond ? "" : "bg-primaire"
      }`}
      style={{
        height: `${HAUTEUR_CARTE}px`,
        ...(drapeau.fond ? { background: drapeau.fond } : {}),
      }}
    >
      {/* --- Les calques, dans l'ordre du bloc de l'accueil ---------------- */}
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

      {/* --- Le contenu, posé par-dessus ---------------------------------- */}
      <div className="relative flex h-full flex-col">
        <div className="relative min-h-0 flex-1">
          {/* Le tracé est borné à la zone d'informations et ne court pas sous
              la bande d'action : celle-ci est opaque, et un circuit qui
              passerait dessous se lirait comme un trait coupé net.

              `boiteLibre` coupe le rapport de forme que le composant pose en
              ligne. La zone fixe ici les deux dimensions, et c'est le travail
              de `xMidYMid meet` de mettre chaque circuit à l'échelle dedans :
              Bakou, 3,4 fois plus large que haut, remplit la largeur ;
              Zandvoort, presque carré, remplit la hauteur. Chacun garde sa
              vraie forme au lieu d'être étiré pour occuper la même surface.

              Sans tracé — tout le début de saison, qui n'est pas dans la
              planche — la carte reste le drapeau seul : un motif de repli
              laisserait croire que ce Grand Prix se court sur cette forme-là. */}
          {trace && (
            <TraceCircuitGp
              slug={gp.slug}
              epaisseur={3}
              boiteLibre
              className="pointer-events-none absolute inset-0 h-full w-full px-8 py-5 text-white/60"
            />
          )}

          <div
            className={`relative flex h-full flex-col justify-between p-5 ${drapeau.texte} ${OMBRE_TEXTE}`}
          >
            {/* Rangée haute — le pays à gauche, l'état à droite. */}
            <div className="flex items-start justify-between gap-3">
              <p className={`text-[12px] ${drapeau.texteDoux}`}>{gp.pays}</p>

              {/* Tant que la base n'a pas répondu, l'état est **inconnu** : une
                  pastille « À venir » posée par défaut se corrigerait en
                  « Pronos ouverts » sous les yeux du joueur, et lui aurait menti
                  l'instant d'avant. Une silhouette dit la même chose sans rien
                  affirmer. Elle est en blanc translucide et non dans le gris des
                  autres squelettes : sur un drapeau, un beige clair se lirait
                  comme une vraie pastille (règle de l'étape 9). */}
              {chargement && !gp.en_base ? (
                <span
                  aria-hidden="true"
                  className="t-skel-bar h-[22px] w-24 shrink-0 rounded-[10px]"
                  // `.t-skel-bar` peint elle-même `--color-squelette`, et cette
                  // règle n'est pas dans une couche Tailwind : une classe
                  // utilitaire ne la battrait pas. Le style en ligne, si.
                  style={{ backgroundColor: "rgb(255 255 255 / 0.25)" }}
                />
              ) : (
                <span
                  className={`shrink-0 rounded-[10px] px-2.5 py-1 text-[11px] font-medium ${etat.pastilleSurDrapeau}`}
                >
                  {etat.libelle}
                </span>
              )}
            </div>

            {/* Rangée basse — la date à gauche, le Grand Prix à droite. */}
            <div className="flex items-end justify-between gap-3">
              <div className="shrink-0">
                {/* Le quantième est le repère de la carte : c'est par lui qu'on
                    cherche « le prochain », et la planche le dessine en très
                    grand. Graisse 700 et 64px s'écartent de la section 5 du
                    CLAUDE.md, qui réserve le 700 aux numéros de voiture et dont
                    l'échelle s'arrête à 44px — écart assumé et borné à ce seul
                    chiffre, comme il l'était déjà à 48px en version `0.20.0`.
                    Le crénage négatif suit /apple-design §15 : un chiffre n'a ni
                    jambage ni hampe, rien ne vient remplir l'espace entre deux
                    caractères.

                    L'interlignage reste à `leading-none` et non plus serré :
                    à 0,85 les chiffres ronds débordent leur boîte par le bas et
                    le « 13 » de l'Espagne comme le « 26 » de l'Azerbaïdjan
                    venaient toucher le mois. Un chiffre plat comme le « 1 » ne
                    le montrait pas — c'est le genre de défaut qu'on ne voit que
                    sur la bonne date. */}
                <p className="text-[64px] leading-none font-bold tracking-[-0.03em]">
                  {jour ?? "—"}
                </p>
                <p className={`text-label-sm mt-1.5 ${drapeau.texteDoux}`}>
                  {gp.mois}
                </p>
              </div>

              <div className="min-w-0 flex-1 text-right">
                <h2 className="truncate text-[16px] font-medium">{gp.nom}</h2>
                <p
                  className={`mt-0.5 truncate text-[12px] ${drapeau.texteDoux}`}
                >
                  {gp.circuit}
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* La bande n'existe que là où il y a quelque chose à faire. Un Grand
            Prix à venir n'a pas encore de cotes ; un Grand Prix fermé n'accepte
            plus rien, et le mener quelque part serait une promesse creuse.

            Elle est blanche et opaque, la couleur étant portée par l'encre :
            posée sur douze drapeaux différents, un aplat coloré se disputerait
            la surface avec celui de la carte, et une bande translucide
            laisserait le vert sauge à 3,45:1 sur le noir de Las Vegas. */}
        {action && (
          <Link
            to={action.vers}
            // L'origine voyage avec la navigation : l'écran d'arrivée en tire
            // la destination de son bouton de retour, plutôt que de ramener
            // toujours à l'accueil. La carte ne la fabrique pas — c'est
            // l'écran qui la monte qui sait d'où l'on part.
            state={retour ? { retour } : undefined}
            style={{ height: `${HAUTEUR_BANDE}px` }}
            className={`pressable-large relative flex w-full shrink-0 items-center justify-center text-[15px] font-medium ${action.style}`}
          >
            {action.libelle}
          </Link>
        )}
      </div>
    </article>
  );
}
