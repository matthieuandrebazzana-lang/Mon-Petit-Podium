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
 * quiconque lit le bundle voit ces libellés, et `config.js` documente pourquoi
 * le secret lui-même y voyage en clair. Le seul garde réel de
 * `POST /scraper/declencher` est `exiger_secret` côté backend, qui compare
 * `X-Admin-Secret` à temps constant et refuse tout le monde quand
 * `ADMIN_SECRET` n'est pas défini sur Railway.
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
 *
 * Le contrôle est une **rangée entière**, pas une pastille de 46px posée au
 * bout : la cible fait toute la largeur, et le libellé dit l'état plutôt que de
 * le laisser deviner à la couleur seule.
 */
export function BasculeModeAdmin({ actif, onBasculer, disabled = false }) {
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
        <span className="text-corps-sm text-texte font-medium">
          Mode admin actif
        </span>
        {/* L'état est dit, pas seulement peint : la couleur seule ne suffit ni
            au daltonien, ni à qui vient d'ouvrir l'écran. */}
        <span className="text-label-sm text-texte-doux normal-case">
          {actif
            ? "Les outils d'administration sont visibles."
            : "Tu vois l'app comme un membre ordinaire."}
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
  const { modeAdminActif, setModeAdminActif } = useAuth();
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
    }
    setModeAdminActif(!modeAdminActif);
  }

  return (
    <VueAdmin
      modeActif={modeAdminActif}
      onBasculerMode={basculerMode}
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
