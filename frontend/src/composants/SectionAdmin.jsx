import { useState } from "react";
import Bouton from "./Bouton.jsx";
import Alerte from "./Alerte.jsx";
import { declencherScraper } from "../lib/admin.js";

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
      <p className="text-label text-texte-doux mb-3 uppercase">Administration</p>

      <p className="text-corps-sm text-secondaire">
        Le scraping tourne déjà tout seul, deux heures après les qualifications.
        Ces deux boutons servent à le forcer entre-temps.
      </p>

      <div className="mt-3.5 flex flex-col gap-2.5">
        {confirmation ? (
          <>
            {/* La conséquence est écrite AVANT l'appui, pas après : c'est le
                seul moment où elle peut encore changer la décision. */}
            <p className="text-corps-sm text-secondaire">
              Les cotes des Grands Prix scrapés seront <strong>figées</strong> :
              plus personne ne les verra bouger, et seule une intervention en
              base pourra les rouvrir. À ne faire qu'après les qualifications.
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
              compte rendu — Grands Prix traités, cotes écrites, refus — part
              dans les logs Railway. Annoncer « cotes mises à jour » serait une
              promesse que cette réponse ne porte pas. */}
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

  return (
    <VueAdmin
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
