import { Fragment } from "react";
import Compteur from "./Compteur.jsx";
import TexteEchange from "./TexteEchange.jsx";
import { blocsRestant } from "../lib/format.js";

/**
 * Le compte à rebours de fermeture, en horloge à trois tuiles.
 *
 * **Extrait de l'écran récapitulatif (version `0.18.0`) parce qu'un deuxième
 * écran le demande.** Deux compositions écrites séparément auraient divergé au
 * premier ajustement, et le symptôme aurait été discret : le même Grand Prix
 * affichant deux fois le même temps restant de deux façons différentes, à un
 * écran d'écart. C'est la règle déjà tenue pour `ETATS_GP` (version `0.20.0`)
 * et pour les couleurs de marché, partagées entre les cotes et le récap.
 *
 * Deux tailles, et c'est le seul paramètre d'apparence :
 *
 * - `compacte` — l'écran récapitulatif, tel qu'il était : 30px de chiffre,
 *   rayon de 12px. **Rendu inchangé au pixel près**, l'extraction n'est pour
 *   lui qu'un déplacement de code.
 * - `grande` — l'écran de saisie : 48px de chiffre, rayon `widget` (16px).
 *   L'horloge y est le premier bloc de l'écran et n'a rien au-dessus d'elle ;
 *   au récap elle vient après un hero pleine largeur, où la même taille
 *   écraserait la carte de statut qui la précède.
 *
 * Le rayon de 12px de la variante compacte n'est pas dans l'échelle de la
 * section 5 (14px est le plus petit) ; celui de la grande l'est
 * (`--radius-widget`). Les deux restent dans l'esprit de la section : plus
 * l'élément est petit, plus son rayon l'est.
 */

const TAILLES = {
  compacte: {
    tuile: "gap-1.5 rounded-[12px] py-3.5",
    chiffre: "text-[30px]",
    colonne: "pt-4 text-[22px]",
    ecart: "gap-2",
  },
  grande: {
    tuile: "gap-2 rounded-widget py-4",
    chiffre: "text-[48px]",
    colonne: "pt-6 text-[26px]",
    ecart: "gap-2.5",
  },
};

/**
 * Une tuile : le nombre, son unité dessous.
 *
 * **Écart assumé sur la graisse** — la section 5 réserve la graisse 700 aux
 * numéros de voiture ; ces chiffres l'emploient, sur demande explicite. C'est
 * la seule dérogation, et elle est bornée à ces trois tuiles.
 *
 * Contrastes mesurés sur `#1A1A1A` : chiffre blanc plein 17,4:1, libellé à
 * 60 % 6,6:1 — les deux largement au-dessus des planchers.
 */
function Tuile({ valeur, label, anime, taille }) {
  return (
    <div
      className={`bg-texte shadow-carte flex flex-1 flex-col items-center ${taille.tuile}`}
    >
      <span
        className={`${taille.chiffre} leading-none font-bold tracking-[-0.02em] text-white tabular-nums`}
      >
        {/* Le nombre se remet en place à chaque changement (transitions-dev 02,
            déjà installé pour le compteur de bonus). Les secondes en sont
            exclues : une animation par seconde n'accuse plus rien, elle tourne
            en boucle.

            C'est aussi la raison pour laquelle il n'y a **pas** de bascule 3D
            façon calendrier mécanique, que la demande donnait pour facultative.
            Une vraie bascule demande `transform-style: preserve-3d` et
            `backface-visibility`, et chaque bloc de l'app vit sous
            `.t-stagger-line`, qui porte `will-change: transform` en permanence :
            c'est précisément la configuration où Safari iOS — la cible — aplatit
            ou fait clignoter les faces. La composition prime, elle est ici
            entière ; le mouvement reste celui, éprouvé, du snippet 02. */}
        {anime ? <Compteur valeur={valeur} /> : valeur}
      </span>
      <span className="text-label-sm text-white/60 uppercase">{label}</span>
    </div>
  );
}

export default function Horloge({
  etat,
  taille = "compacte",
  avecSecondes = true,
}) {
  const style = TAILLES[taille] ?? TAILLES.compacte;

  // Trois états, et ils ne disent pas la même chose. Un Grand Prix dont Unibet
  // n'a pas annoncé l'horaire **reste ouvert** — c'est la règle tenue aux trois
  // étages depuis l'étape 5 — mais il n'a aucun décompte à afficher : écrire
  // « 0s » serait faux dans les deux sens.
  const inconnue = !etat.ferme && !etat.texte;
  const label = etat.ferme ? "Pronostics" : inconnue ? "Départ" : "Fermeture dans";
  const blocs = etat.ferme ? null : blocsRestant(etat.restant, { avecSecondes });

  return (
    <>
      <p className="text-label text-texte-doux text-center uppercase">{label}</p>

      {blocs ? (
        <div className={`mt-3 flex items-start justify-center ${style.ecart}`}>
          {blocs.map((bloc, rang) => (
            <Fragment key={bloc.cle}>
              {rang > 0 && (
                <span
                  aria-hidden="true"
                  className={`text-texte-doux ${style.colonne} leading-none font-medium`}
                >
                  :
                </span>
              )}
              <Tuile
                valeur={bloc.valeur}
                label={bloc.label}
                anime={bloc.anime}
                taille={style}
              />
            </Fragment>
          ))}
        </div>
      ) : (
        <p className="text-score text-primaire mt-2 text-center">
          {/* Les deux états sans décompte gardent l'échange en place
              (transitions-dev 04) : le passage de l'horloge à « Fermés » se
              produit sous les yeux du joueur, à cinq minutes du départ. */}
          <TexteEchange valeur={etat.ferme ? "Fermés" : "À confirmer"} />
        </p>
      )}
    </>
  );
}
