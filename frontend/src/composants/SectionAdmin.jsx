import { useState } from "react";
import Bouton from "./Bouton.jsx";
import Alerte from "./Alerte.jsx";
import { declencherScraper } from "../lib/admin.js";
import { useAuth } from "../auth/AuthContexte.jsx";

/**
 * Section « Administration » du profil — visible du seul porteur d'`is_admin`.
 *
 * **Ce composant ne garde rien, et il ne faut pas le croire.** Il est monté
 * sous condition, mais un affichage conditionnel n'est pas une autorisation :
 * quiconque lit le bundle voit ces libellés. Le garde réel est
 * `POST /admin/action` côté backend, qui exige le jeton Supabase de l'appelant
 * puis relit `profils.is_admin` **en base** avec la clé de service (version
 * `0.64.0`). Ce que le bundle ne contient plus, en revanche, c'est le secret :
 * `VITE_ADMIN_SECRET` y voyageait en clair jusque-là — voir `config.js`.
 *
 * Pas de route dédiée, pas de garde de navigation : la demande veut un
 * affichage conditionnel dans le profil, et c'est aussi le choix juste — une
 * route `/admin` protégée par un drapeau lu côté client donnerait l'illusion
 * d'une frontière là où il n'y en a pas.
 *
 * **L'affichage est séparé de l'état**, et c'est la convention posée à la
 * version `0.29.0` pour `optionsDisponibles` et `bonusEpingles` : le rendu
 * statique n'exécute aucun effet et ne rejoue aucun appui, donc les quatre
 * phases ne seraient vérifiables qu'en montant un DOM. `VueAdmin` est une
 * fonction pure de ses props, éprouvable telle quelle.
 */

/**
 * La rangée d'interrupteur — la forme, écrite **une seule fois**.
 *
 * La section en porte deux, et elles doivent être indiscernables : « things
 * that look the same must behave the same » (/apple-design §16.4). Deux
 * rangées écrites séparément auraient divergé au premier ajustement — une
 * hauteur de piste, un poids de libellé, une couleur mesurée retouchée d'un
 * côté seulement — et le second interrupteur aurait cessé de se lire comme un
 * interrupteur.
 *
 * Le contrôle est une **rangée entière**, pas une pastille de 46px posée au
 * bout : la cible fait toute la largeur, et le libellé dit l'état plutôt que de
 * le laisser deviner à la couleur seule.
 */
export function Bascule({
  libelle,
  description,
  actif,
  onBasculer,
  disabled = false,
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={actif}
      onClick={onBasculer}
      disabled={disabled}
      className="min-h-tactile -my-1 flex w-full items-center justify-between gap-4 py-1 text-left disabled:opacity-50"
    >
      <span className="flex flex-col gap-0.5">
        <span className="text-corps-sm text-texte font-medium">{libelle}</span>
        {/* L'état est dit, pas seulement peint : la couleur seule ne suffit ni
            au daltonien, ni à qui vient d'ouvrir l'écran. */}
        <span className="text-label-sm text-texte-doux normal-case">
          {description}
        </span>
      </span>

      {/* La piste et le pouce sont décoratifs : `role="switch"` et
          `aria-checked` portent déjà l'état pour le lecteur d'écran, et le
          libellé ci-dessus le porte pour tout le monde.

          Les deux couleurs sont mesurées, pas choisies. Le pouce blanc doit se
          détacher de sa piste (WCAG 1.4.11, 3:1 pour un élément graphique
          porteur de sens) : `secondaire/60` le pose à 3,41:1 — la valeur même
          qu'a déjà l'étoile de favori au repos — et `primaire` à 10,88:1. Le
          gris `texte-doux` du design system n'aurait donné que 2,85:1, et
          `squelette` ne peint jamais autre chose qu'une silhouette. */}
      <span
        aria-hidden="true"
        className={`t-bascule relative flex h-7 w-[46px] shrink-0 items-center rounded-full p-0.5 ${
          actif ? "bg-primaire" : "bg-secondaire/60"
        }`}
      >
        <span
          className={`t-bascule-pouce shadow-carte size-6 rounded-full bg-white ${
            actif ? "translate-x-[18px]" : "translate-x-0"
          }`}
        />
      </span>
    </button>
  );
}

/**
 * L'interrupteur « Mode admin actif ».
 *
 * **Un interrupteur qui se démet lui-même**, et c'est ce qui gouverne sa
 * composition. Éteint, l'administrateur voit l'application exactement comme la
 * voient les autres : plus aucune surface d'administration nulle part, et les
 * conditions ordinaires — `cotesArretees` et les autres — s'appliquent sans
 * exception. C'est la seule façon de vérifier ce que voit un membre sans se
 * créer un second compte.
 *
 * **Il est posé en tête de la section, avant ce qu'il gouverne**, et c'est la
 * règle de mapping d'`/apple-design` §16 : un contrôle vit près de ce qu'il
 * commande. Il est aussi le seul élément de la section à ne jamais disparaître —
 * s'il s'éteignait avec le reste, il n'y aurait plus rien pour le rallumer.
 *
 * **Neutralisé pendant un envoi.** Sans cela, s'éteindre à mi-course laisserait
 * une requête en vol dont le résultat s'afficherait au retour, des minutes plus
 * tard, comme s'il venait d'arriver. Les deux boutons sont déjà neutralisés à
 * ce moment-là ; l'interrupteur les rejoint.
 */
export function BasculeModeAdmin({ actif, onBasculer, disabled = false }) {
  return (
    <Bascule
      libelle="Mode admin actif"
      description={
        actif
          ? "Les outils d'administration sont visibles."
          : "Tu vois l'app comme un membre ordinaire."
      }
      actif={actif}
      onBasculer={onBasculer}
      disabled={disabled}
    />
  );
}

/**
 * L'interrupteur « Mode prévisualisation ».
 *
 * **Il ne touche à rien, et sa description doit le dire.** Le voisin immédiat
 * de cette rangée est « Figer les cotes », un bouton qui écrit en base et dont
 * personne ne sait revenir en arrière sans un `update` à la main. Deux
 * commandes voisines dont l'une est réversible et l'autre non doivent se
 * distinguer par leur texte, pas par la mémoire de celui qui appuie : la
 * description dit donc « rien n'est modifié en base » à l'état allumé, là où
 * l'interrupteur d'au-dessus se contente de dire ce qu'il montre.
 *
 * **Subordonné au mode admin, donc posé sous lui et à l'intérieur de ce qu'il
 * commande** (/apple-design §16, mapping). Il ne s'affiche jamais mode admin
 * éteint : ce serait offrir de fausser l'affichage à quelqu'un qui vient
 * justement de demander à voir l'application telle qu'elle est.
 *
 * **Neutralisé pendant un envoi**, comme son voisin et pour la même raison —
 * changer ce qu'on regarde pendant qu'une requête est en vol brouille la
 * lecture de son résultat.
 */
export function BasculePrevisualisation({ actif, onBasculer, disabled = false }) {
  return (
    <Bascule
      libelle="Mode prévisualisation"
      description={
        actif
          ? "Tu vois les Grands Prix comme s'ils étaient ouverts. Rien n'est modifié en base."
          : "Voir l'app comme si les cotes étaient déjà figées."
      }
      actif={actif}
      onBasculer={onBasculer}
      disabled={disabled}
    />
  );
}

/** Les quatre phases de l'indicateur de statut. */
export const REPOS = "repos";
export const EN_COURS = "encours";
export const SUCCES = "succes";
export const ECHEC = "echec";

/**
 * Le rendu, fonction pure de son état.
 *
 * `etat` porte la phase **et** le mode demandé (`figer`) : deux drapeaux
 * séparés finiraient par afficher « en cours » et « réussi » en même temps, et
 * un message de succès ne saurait pas dire s'il annonce un figeage.
 */
export function VueAdmin({
  modeActif = false,
  onBasculerMode,
  previsualisationActive = false,
  onBasculerPrevisualisation,
  confirmation = false,
  etat = { phase: REPOS },
  tentative = 0,
  onDemanderFigeage,
  onFiger,
  onSansFiger,
  onAnnuler,
}) {
  const enCours = etat.phase === EN_COURS;

  return (
    <div className="rounded-carte bg-surface shadow-carte p-4">
      <p className="text-label text-texte-doux mb-3 uppercase">
        Administration
      </p>

      <BasculeModeAdmin
        actif={modeActif}
        onBasculer={onBasculerMode}
        disabled={enCours}
      />

      {/* Tout ce qui suit est un outil d'administration, donc tout ce qui suit
          s'éteint avec l'interrupteur. Rien n'est grisé ni laissé en place :
          « voir l'app comme un membre » ne veut rien dire s'il reste deux
          boutons désactivés que personne d'autre n'a. */}
      {!modeActif ? (
        <p className="text-label-sm text-texte-doux mt-3 normal-case">
          Rallume le mode pour retrouver les outils. Il repart éteint à chaque
          rechargement.
        </p>
      ) : (
        <>
          {/* La prévisualisation est posée **juste sous** l'interrupteur qui la
              gouverne, avant les boutons du scraper : c'est la seule autre
              commande de la section qui agisse sur ce que l'écran montre, et
              non sur ce que la base contient. Le filet la sépare de ce qui
              suit, qui écrit pour de bon. */}
          <div className="border-squelette mt-3 border-t pt-3">
            <BasculePrevisualisation
              actif={previsualisationActive}
              onBasculer={onBasculerPrevisualisation}
              disabled={enCours}
            />
          </div>

          <p className="text-corps-sm text-secondaire mt-3.5">
            Le scraping tourne déjà tout seul, deux heures après les
            qualifications. Ces deux boutons servent à le forcer entre-temps.
          </p>

          <div className="mt-3.5 flex flex-col gap-2.5">
            {confirmation ? (
              <>
                {/* La conséquence est écrite AVANT l'appui, pas après : c'est
                    le seul moment où elle peut encore changer la décision. */}
                <p className="text-corps-sm text-secondaire">
                  Les cotes des Grands Prix scrapés seront{" "}
                  <strong>figées</strong> : plus personne ne les verra bouger,
                  et seule une intervention en base pourra les rouvrir. À ne
                  faire qu'après les qualifications.
                </p>
                <Bouton variante="principal" onClick={onFiger}>
                  Figer les cotes
                </Bouton>
                <button
                  type="button"
                  onClick={onAnnuler}
                  className="text-texte-doux min-h-tactile pressable py-2 text-center text-[13px] font-medium"
                >
                  Annuler
                </button>
              </>
            ) : (
              <>
                <Bouton
                  variante="principal"
                  onClick={onDemanderFigeage}
                  occupe={enCours && etat.figer}
                  libelleOccupe="Envoi…"
                  disabled={enCours}
                >
                  Déclencher le scraper
                </Bouton>
                <Bouton
                  variante="secondaire"
                  onClick={onSansFiger}
                  occupe={enCours && !etat.figer}
                  libelleOccupe="Envoi…"
                  disabled={enCours}
                >
                  Scraper sans figer
                </Bouton>
              </>
            )}
          </div>

          {/* L'indicateur de statut. `role="status"` pour l'attente — elle
              s'annonce sans voler le focus — et `Alerte`, qui porte déjà
              `role="alert"`, pour les deux issues. */}
          {enCours && (
            <p role="status" className="text-corps-sm text-secondaire mt-3">
              {etat.figer
                ? "Scraping demandé, avec figeage des cotes…"
                : "Scraping demandé, sans figeage…"}
            </p>
          )}

          {etat.phase === SUCCES && (
            <div className="mt-3">
              {/* « Accepté », jamais « terminé » : la route rend `202` sans
                  attendre, le scraping dure plusieurs secondes derrière, et son
                  compte rendu — Grands Prix traités, cotes écrites, refus —
                  part dans les logs Railway. Annoncer « cotes mises à jour »
                  serait une promesse que cette réponse ne porte pas. */}
              <Alerte ton="succes">
                {etat.figer
                  ? "Scraping lancé. Les cotes seront figées si tout se passe bien — le compte rendu est dans les logs Railway."
                  : "Scraping lancé sans figeage. Le compte rendu est dans les logs Railway."}
              </Alerte>
            </div>
          )}

          {etat.phase === ECHEC && (
            <div className="mt-3">
              <Alerte ton="erreur" tentative={tentative}>
                {etat.message}
              </Alerte>
            </div>
          )}
        </>
      )}
    </div>
  );
}

/**
 * Confirmation sur place pour le figeage, jamais en boîte de dialogue.
 *
 * **Le figeage est l'action difficile à défaire de cet écran, et c'est constaté
 * plutôt que supposé** : un scraping passé avant les qualifications arrête les
 * cotes sur une grille qui n'existe pas encore (règle 4.3), et rien dans
 * l'application ne sait revenir en arrière — il faut un `update` à la main dans
 * le SQL Editor. C'est très exactement ce qui est arrivé au GP des Pays-Bas
 * (version `0.38.0`), avec un `curl` au lieu d'un bouton. Un bouton rend le
 * geste plus facile, donc l'accident plus probable.
 *
 * La confirmation est posée sur place et non dans une modale, comme « Quitter
 * le championnat » depuis l'étape 3 : le geste de retour d'iOS l'annule, et
 * aucune couche ne s'interpose. « Scraper sans figer » n'en demande aucune —
 * il n'écrit que des cotes, sur des Grands Prix qui ne sont pas encore arrêtés.
 */
export default function SectionAdmin() {
  const {
    modeAdminActif,
    setModeAdminActif,
    modePrevisualisationActif,
    setModePrevisualisationActif,
  } = useAuth();
  const [confirmation, setConfirmation] = useState(false);
  const [etat, setEtat] = useState({ phase: REPOS });
  // Rejoue la secousse d'`Alerte` à chaque tentative : sans elle, réessayer et
  // retomber sur le même message donnerait l'impression que rien n'est parti.
  const [tentative, setTentative] = useState(0);

  async function lancer(figer) {
    setConfirmation(false);
    setTentative((n) => n + 1);
    setEtat({ phase: EN_COURS, figer });

    const resultat = await declencherScraper({ figer });

    setEtat(
      resultat.ok
        ? { phase: SUCCES, figer }
        : { phase: ECHEC, figer, message: resultat.message },
    );
  }

  /**
   * Éteindre remet la section à son point de départ.
   *
   * Une confirmation restée ouverte ou un message de succès vieux de dix
   * minutes n'ont plus rien à dire au retour — pire, ils raconteraient un
   * envoi qu'on croirait tout juste parti. L'interrupteur étant neutralisé
   * pendant un envoi (`disabled={enCours}`), il n'y a jamais de requête en vol
   * à abandonner ici : ce qu'on efface est toujours une issue déjà lue.
   */
  function basculerMode() {
    if (modeAdminActif) {
      setConfirmation(false);
      setEtat({ phase: REPOS });
      // **La prévisualisation s'éteint avec le mode qui la porte.** Le drapeau
      // dérivé du contexte suffirait à la neutraliser — il conjugue les trois
      // termes — mais l'interrupteur brut resterait allumé sous la surface, et
      // se rallumerait tout seul au prochain « Mode admin actif ». Un
      // interrupteur qu'on n'a pas touché et qui revient allumé est un
      // interrupteur auquel on cesse de se fier.
      setModePrevisualisationActif(false);
    }
    setModeAdminActif(!modeAdminActif);
  }

  return (
    <VueAdmin
      modeActif={modeAdminActif}
      onBasculerMode={basculerMode}
      previsualisationActive={modePrevisualisationActif}
      onBasculerPrevisualisation={() =>
        setModePrevisualisationActif(!modePrevisualisationActif)
      }
      confirmation={confirmation}
      etat={etat}
      tentative={tentative}
      onDemanderFigeage={() => setConfirmation(true)}
      onFiger={() => lancer(true)}
      onSansFiger={() => lancer(false)}
      onAnnuler={() => setConfirmation(false)}
    />
  );
}
