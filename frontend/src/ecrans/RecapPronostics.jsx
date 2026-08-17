import { useCallback, useMemo, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import Bouton from "../composants/Bouton.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import { Barre, Pave } from "../composants/Squelette.jsx";
import {
  APPARENCE_REPLI,
  drapeauDuGp,
  VoileDrapeau,
} from "../composants/DrapeauxGP.jsx";
import { slugCircuit } from "../composants/TracesCircuits.jsx";
import {
  IconeAlerte,
  IconeChevronGauche,
  IconeCoche,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerRecap,
  indexerCotes,
  MARCHE_PODIUM,
  MARCHE_VAINQUEUR,
  organiserPronostics,
} from "../lib/pronostics.js";
import { couleurBloc, couleurMarche, tonalites } from "../lib/couleurs.js";
import { useDonnees } from "../lib/useDonnees.js";
import { formaterDepart, formaterPoints } from "../lib/format.js";
import { useFermeture } from "../lib/useFermeture.js";

/* --------------------------------------------------------------------------
   Zone 1 — le hero.

   Il porte le drapeau du pays hôte, exactement comme le bloc du prochain Grand
   Prix de l'accueil : même table (`DrapeauxGP`), même clé (`slugCircuit`), même
   voile calculé, et la même surcouche uniforme de 15 % introduite en version
   `0.16.1`. Le récap et l'accueil parlent alors du même Grand Prix avec les
   mêmes couleurs, et la reconnaissance se fait avant d'avoir lu le nom.

   **Le hero est aussi la barre de navigation de l'écran.** Le bouton de retour
   vit dedans plutôt qu'au-dessus : un en-tête beige portant « Récap » posé sur
   un hero qui nomme déjà le Grand Prix aurait donné deux titres empilés pour un
   seul écran, et 150px de chrome avant le premier contenu utile. C'est le même
   arbitrage qu'à l'en-tête teinté d'un championnat, à ceci près que la teinte y
   est une couleur unie et ici un drapeau — d'où un hero écrit sur place plutôt
   qu'un `EnTeteEcran` teinté.

   `pleine-largeur` + `coiffe-ecran` laissent la couleur courir jusqu'aux deux
   bords et derrière la Dynamic Island, sans jamais y pousser de texte.
   -------------------------------------------------------------------------- */
function Hero({ gp, onRetour }) {
  // Un Grand Prix pas encore chargé garde le bordeaux de la marque : c'est le
  // repli documenté de `DrapeauxGP`, et il passe par le même calcul de voile
  // que les drapeaux plutôt que d'être décrété conforme.
  const drapeau = (gp ? drapeauDuGp(slugCircuit(gp.nom)) : null) ?? APPARENCE_REPLI;
  const depart = formaterDepart(gp?.date_course);

  return (
    <div
      className={`pleine-largeur coiffe-ecran rounded-b-bloc shadow-aplat relative overflow-hidden px-4 pb-6 ${
        drapeau.fond ? "" : "bg-primaire"
      }`}
      style={drapeau.fond ? { background: drapeau.fond } : undefined}
    >
      {/* La lumière spéculaire d'/apple-design §12 : un aplat plein est une
          surface morte, ce galbe très doux lui donne une source lumineuse. */}
      <span
        aria-hidden="true"
        className="lueur-haute pointer-events-none absolute inset-0"
      />
      {/* Le voile, par-dessus tout ce qui éclaircit et sous le seul contenu :
          c'est ce qui rend la garantie de 3:1 inconditionnelle sur le texte
          blanc. Son opacité est calculée par drapeau, jamais choisie. */}
      <VoileDrapeau voile={drapeau.voile} />
      {/* La surcouche uniforme de la version `0.16.1`, à la même place et pour
          la même raison : sur un drapeau à bande répétée, un assombrissement
          partiel couperait la surface en deux. Elle ne s'applique qu'aux blocs
          peints par un drapeau — le repli bordeaux n'a aucune rupture à
          corriger et doit garder exactement l'aspect qu'il a ailleurs. */}
      {drapeau.fond && (
        <span
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-black/15"
        />
      )}

      <div className="relative">
        {/* La rangée de retour : c'est la seule sortie de l'écran, elle doit
            donc nommer sa destination (/apple-design §16). Les marges
            négatives lui rendent ses 44px sans décaler son calage visuel. */}
        <button
          type="button"
          onClick={onRetour}
          className={`pressable min-h-tactile -ml-2 flex items-center gap-1.5 py-3 pl-2 text-[13px] font-medium ${drapeau.texte} ${drapeau.ombreTexte}`}
        >
          <IconeChevronGauche className="size-[15px] shrink-0" />
          Accueil
        </button>

        <p
          className={`text-label-sm mt-1 inline-block rounded-full px-2.5 py-1 uppercase ${drapeau.pastille} ${drapeau.texte}`}
        >
          Récap
        </p>

        {/* Le nom du Grand Prix est le titre de la page : il prend l'échelle
            des titres de la section 5, et son crénage négatif avec.

            Sur un drapeau à bandes, il en traverse la couture — d'où l'ombre
            portée, qui lui garde son contour des deux côtés. Un aplat uni n'en
            reçoit aucune : `ombreTexte` est vide pour lui. */}
        <h1
          className={`text-titre-lg mt-3 line-clamp-2 text-center ${drapeau.texte} ${drapeau.ombreTexte}`}
        >
          {gp?.nom ?? "Grand Prix"}
        </h1>
        <p
          className={`mt-1.5 text-center text-[13px] ${drapeau.texteDoux} ${drapeau.ombreTexte}`}
        >
          {depart.heure ? `${depart.jour} · Départ ${depart.heure}` : depart.jour}
        </p>
      </div>
    </div>
  );
}

/* --------------------------------------------------------------------------
   Zone 2 — le statut.

   **Écart assumé sur l'encre, et c'est le même arbitrage qu'en version
   `0.12.0`.** La demande écrit « texte en blanc » pour les deux variantes de
   cette carte. Sur le vert sauge `#4A7C59`, le blanc tient 4,7:1 et il est
   conservé. Sur l'amber `#E8A020`, il tombe à **2,2:1** — sous le plancher AA
   des grands textes — quand l'encre `#1A1A1A` monte à 7,7:1. `tonalites()`
   porte ce seuil une fois pour toutes : l'écran ne choisit jamais `text-white`
   lui-même, il lit l'objet. C'est ce qui empêche une carte amber de recevoir du
   texte blanc parce qu'un écran l'a écrit de mémoire.
   -------------------------------------------------------------------------- */
function CarteStatut({ aPronostique, juste, ferme }) {
  const couleur = couleurBloc(aPronostique ? "vert-sauge" : "amber");
  const ton = tonalites(couleur.hex);
  const Icone = aPronostique ? IconeCoche : IconeAlerte;

  const titre = aPronostique
    ? juste
      ? "Pronos enregistrés !"
      : "Tes pronos sont en place"
    : "Tu n'as pas encore pronostiqué";

  // Le sous-titre dit le geste possible, pas l'état déjà lu dans le titre.
  // Une fois la fermeture passée, il n'y a plus de geste : il dit alors ce qui
  // a changé plutôt que d'inviter à une modification impossible.
  const sousTitre = aPronostique
    ? ferme
      ? "Les pronostics sont fermés."
      : "Tu peux les modifier jusqu'au départ."
    : ferme
      ? "Ce Grand Prix ne rapportera aucun point."
      : "Il est encore temps de choisir ton vainqueur.";

  return (
    <div
      className={`rounded-bloc shadow-aplat relative flex items-center gap-4 overflow-hidden p-5 ${couleur.fond}`}
    >
      <span
        aria-hidden="true"
        className="lueur-haute pointer-events-none absolute inset-0"
      />
      <span
        aria-hidden="true"
        className={`relative flex size-12 shrink-0 items-center justify-center rounded-full ${ton.surfaceForte}`}
      >
        <Icone
          className="size-6 [stroke-width:2.5]"
          style={{ color: ton.encre }}
        />
      </span>
      <span className="relative min-w-0">
        <span className={`block text-[17px] font-medium ${ton.texte}`}>
          {titre}
        </span>
        <span className={`mt-0.5 block text-[12px] ${ton.texteDoux}`}>
          {sousTitre}
        </span>
      </span>
    </div>
  );
}

/* --------------------------------------------------------------------------
   Zone 3 — le compte à rebours de fermeture (règle 4.3).
   -------------------------------------------------------------------------- */
function CarteFermeture({ etat, aPronostique, onModifier }) {
  // Trois états, et ils ne disent pas la même chose. Un Grand Prix dont Unibet
  // n'a pas annoncé l'horaire **reste ouvert** — c'est la règle tenue aux trois
  // étages depuis l'étape 5 — mais il n'a aucun décompte à afficher : écrire
  // « 0s » serait faux dans les deux sens.
  const inconnue = !etat.ferme && !etat.texte;
  const label = etat.ferme ? "Pronostics" : inconnue ? "Départ" : "Fermeture dans";
  const valeur = etat.ferme ? "Fermés" : inconnue ? "À confirmer" : etat.texte;

  return (
    <div className="rounded-bloc bg-surface shadow-bloc p-5">
      <p className="text-label text-texte-doux text-center uppercase">{label}</p>
      <p className="text-score text-primaire mt-2 text-center">
        {/* Le décompte change toutes les secondes dans la dernière heure :
            l'échange en place (transitions-dev 04) évite le clignotement que
            donnerait un simple remplacement de texte. */}
        <TexteEchange valeur={valeur} />
      </p>

      {!etat.ferme && (
        <Bouton variante="principal" className="mt-4" onClick={onModifier}>
          {aPronostique ? "Modifier mes pronos" : "Faire mes pronos"}
        </Bouton>
      )}
    </div>
  );
}

/* --------------------------------------------------------------------------
   Zone 4 — les pronostics, dans une seule carte.

   Les deux étiquettes « Obligatoire » et « Bonus » qui suivaient chaque ligne
   sont supprimées : elles répétaient mot pour mot le titre de la section juste
   au-dessus. C'est la couleur de la pastille de points qui porte désormais le
   marché, et elle est **prise à la même source que les en-têtes du tableau des
   cotes** (`couleurMarche`) — le rouge du vainqueur est donc exactement le
   rouge de sa section là-bas, et les deux ne peuvent pas diverger.
   -------------------------------------------------------------------------- */
function Ligne({ marche, choix, couleur }) {
  const ton = tonalites(couleur.hex);

  return (
    <li className="flex items-center justify-between gap-3 py-2.5">
      <span className="min-w-0">
        <span className="text-texte-doux block truncate text-[10px] font-medium tracking-[0.3px] uppercase">
          {marche}
        </span>
        <span className="text-texte mt-0.5 block truncate text-[14px] font-medium">
          {choix.pilote ?? "Cote retirée par le bookmaker"}
        </span>
      </span>

      {/* Les points affichés sont ceux que ce pronostic rapportera **s'il
          tombe** (règle 4.1). Rien n'est acquis avant la course. */}
      <span
        className={`shrink-0 rounded-[10px] px-2.5 py-1.5 text-[13px] font-medium ${couleur.fond} ${ton.texte}`}
      >
        {formaterPoints(choix.points)}
      </span>
    </li>
  );
}

function Separateur() {
  return <div aria-hidden="true" className="bg-fond my-2.5 h-px" />;
}

function TitreSection({ children }) {
  return (
    <p className="text-label-sm text-texte-doux mb-1 uppercase">{children}</p>
  );
}

/* --------------------------------------------------------------------------
   Squelette — les quatre zones à leur hauteur réelle.

   Le hero garde son aplat et n'en grise que le contenu : c'est un aplat de
   couleur, et le voir passer au gris puis revenir à sa teinte ferait clignoter
   l'écran. Même règle qu'à l'accueil.
   -------------------------------------------------------------------------- */
function SqueletteRecap() {
  return (
    <div className="flex flex-col gap-3">
      {/* La carte de statut garde son aplat vert : c'est un aplat de couleur,
          et le voir passer au gris puis revenir à sa teinte ferait clignoter
          l'écran. Seule la matière qu'il contient est grisée, en blanc
          translucide — le gris des squelettes s'y lirait comme une tache. */}
      <div className="rounded-bloc bg-vert-sauge shadow-aplat relative overflow-hidden p-5">
        <span className="lueur-haute pointer-events-none absolute inset-0" />
        <div className="relative flex items-center gap-4">
          <div className="size-12 shrink-0 rounded-full bg-white/25" />
          <div className="min-w-0 flex-1">
            <div className="h-4 w-40 max-w-full rounded-full bg-white/25" />
            <div className="mt-2 h-3 w-52 max-w-full rounded-full bg-white/20" />
          </div>
        </div>
      </div>

      {/* Les deux cartes blanches, elles, prennent les primitives partagées :
          la couleur des squelettes ne s'écrit qu'à un seul endroit. Le bouton
          garde sa hauteur tactile, sans quoi l'écran sauterait de 44px. */}
      <div className="rounded-bloc bg-surface shadow-bloc p-5">
        <Barre largeur="w-24" hauteur="h-2.5" className="mx-auto" />
        <Barre largeur="w-40" hauteur="h-7" className="mx-auto mt-3" />
        <Pave className="h-tactile mt-4 w-full" arrondi="rounded-carte-sm" />
      </div>

      <div className="rounded-bloc bg-surface shadow-bloc p-4">
        {[0, 1, 2, 3].map((rang) => (
          <div key={rang} className="flex items-center justify-between gap-3 py-2.5">
            <div className="min-w-0 flex-1">
              <Barre largeur="w-16" hauteur="h-2" />
              <Barre largeur="w-28" className="mt-1.5" />
            </div>
            <Pave className="h-7 w-20 shrink-0" arrondi="rounded-[10px]" />
          </div>
        ))}
      </div>
    </div>
  );
}

/** Maquette 10 — récapitulatif des pronostics du joueur pour un GP. */
export default function RecapPronostics() {
  const { gpId } = useParams();
  const naviguer = useNavigate();
  const emplacement = useLocation();
  const { utilisateur } = useAuth();

  // Vrai seulement au retour de l'écran de saisie : la maquette 10 est le
  // « récap après validation », mais l'écran doit aussi tenir debout quand on
  // y arrive à froid, sans rien célébrer.
  const juste = Boolean(emplacement.state?.enregistre);

  const cle = utilisateur ? `recap:${utilisateur.id}:${gpId}` : null;
  const chargeur = useCallback(
    (signal) => chargerRecap(gpId, utilisateur?.id, signal),
    [gpId, utilisateur?.id],
  );
  const { donnees, chargement, echec, recharger } = useDonnees(cle, chargeur);
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayerChargement() {
    setTentativeChargement((n) => n + 1);
    recharger();
  }

  const gp = donnees?.gp ?? null;
  const index = useMemo(() => indexerCotes(gp), [gp]);
  const pronostics = useMemo(
    () => organiserPronostics(donnees?.pronostics, index),
    [donnees, index],
  );

  const etat = useFermeture(gp?.date_course);
  const aPronostique = Boolean(gp) && !pronostics.vide;

  const obligatoires = [
    ...(pronostics.vainqueur
      ? [
          {
            marche: pronostics.vainqueur.libelle ?? "Vainqueur",
            choix: pronostics.vainqueur,
            couleur: couleurMarche(MARCHE_VAINQUEUR),
          },
        ]
      : []),
    ...pronostics.podium.map((choix) => ({
      marche: choix.libelle ?? "Podium",
      choix,
      couleur: couleurMarche(MARCHE_PODIUM),
    })),
  ];

  // Somme de ce que le joueur peut décrocher sur ce GP, tous pronostics
  // réussis. Absent de la maquette, mais c'est la question que tout le monde se
  // pose devant un récapitulatif, et la règle 4.1 la rend calculable.
  const potentiel = [...obligatoires.map((l) => l.choix), ...pronostics.bonus]
    .map((choix) => choix.points ?? 0)
    .reduce((total, points) => total + points, 0);

  const retour = () => naviguer("/accueil");
  const versSaisie = () =>
    naviguer(`/grands-prix/${gpId}/${aPronostique ? "pronostics" : "cotes"}`);

  // L'ambre du bonus est le seul aplat de la série dont l'encre bascule au
  // foncé : `tonalites` le décide, l'écran ne le suppose pas.
  const couleurBonus = couleurBloc("amber");

  return (
    <Ecran direction="avant">
      {/* Le hero est rendu même en attente et même en erreur : c'est la seule
          sortie de l'écran, et une barre de retour qui disparaîtrait pendant le
          réveil de Supabase enfermerait le joueur. */}
      <Bloc rang={1}>
        <Hero gp={gp} onRetour={retour} />
      </Bloc>

      <div className="mt-3 flex flex-1 flex-col gap-3">
        {echec && !donnees ? (
          <Bloc rang={2}>
            <BlocErreur
              echec={echec}
              onReessayer={reessayerChargement}
              tentative={tentativeChargement}
            />
          </Bloc>
        ) : (
          <Bloc rang={2}>
            <ZoneChargement
              chargement={chargement && !donnees}
              squelette={<SqueletteRecap />}
            >
              {gp && (
                <div className="flex flex-col gap-3">
                  <CarteStatut
                    aPronostique={aPronostique}
                    juste={juste}
                    ferme={etat.ferme}
                  />

                  <CarteFermeture
                    etat={etat}
                    aPronostique={aPronostique}
                    onModifier={versSaisie}
                  />

                  {aPronostique ? (
                    <div className="rounded-bloc bg-surface shadow-bloc p-4">
                      <TitreSection>Obligatoires</TitreSection>
                      <ul>
                        {obligatoires.map((ligne, rang) => (
                          <Ligne
                            key={`${ligne.choix.outcome}-${rang}`}
                            marche={ligne.marche}
                            choix={ligne.choix}
                            couleur={ligne.couleur}
                          />
                        ))}
                      </ul>

                      {pronostics.bonus.length > 0 && (
                        <>
                          <Separateur />
                          <TitreSection>Bonus</TitreSection>
                          <ul>
                            {pronostics.bonus.map((choix) => (
                              <Ligne
                                key={choix.outcome}
                                marche={choix.libelle ?? "Bonus"}
                                choix={choix}
                                couleur={couleurBonus}
                              />
                            ))}
                          </ul>
                        </>
                      )}

                      <Separateur />
                      <div className="flex items-baseline justify-between gap-3 pt-0.5">
                        <span className="text-label text-texte-doux uppercase">
                          Total si tout tombe
                        </span>
                        <span className="text-score text-primaire">
                          {formaterPoints(potentiel)}
                        </span>
                      </div>
                    </div>
                  ) : (
                    <div className="rounded-bloc bg-surface shadow-bloc px-5 py-9 text-center">
                      <p className="text-corps text-texte font-medium">
                        Aucun pronostic pour ce Grand Prix
                      </p>
                      <p className="text-corps-sm text-texte-doux mx-auto mt-1 max-w-[30ch]">
                        {etat.ferme
                          ? "Les pronostics sont fermés : ce Grand Prix ne rapportera aucun point."
                          : "Choisis ton vainqueur et ton podium, puis jusqu'à trois bonus."}
                      </p>
                    </div>
                  )}
                </div>
              )}
            </ZoneChargement>
          </Bloc>
        )}

        <div className="min-h-3 flex-1" />
      </div>
    </Ecran>
  );
}
