import Alerte from "./Alerte.jsx";
import { estRejouable, messageDeChargement } from "../lib/erreurs.js";

/**
 * Échec de chargement d'un écran — étape 9.
 *
 * Trois situations, trois messages, un seul composant (voir `lib/erreurs.js`) :
 *
 * - **réseau / réveil de Railway** — « Connexion au serveur en cours… ». Sur le
 *   plan gratuit, le service dort après quelques minutes d'inactivité et le
 *   premier appel met plusieurs secondes, parfois échoue franchement. Dire
 *   « erreur » là où il n'y a qu'une attente ferait fermer l'app à quelqu'un
 *   qui n'avait qu'à toucher un bouton ;
 * - **Supabase** — « Une erreur est survenue. Réessaie. » ;
 * - **donnée absente ou session expirée** — le bouton disparaît. Rejouer le
 *   même appel rendrait le même refus, et un bouton qui ne répare rien est
 *   pire que pas de bouton.
 *
 * Le message technique n'arrive jamais jusqu'ici : le backend garde la cause
 * dans ses logs depuis l'étape 9 (`app/api/journal.py`), et `lib/api.js` filtre
 * ce qui viendrait d'ailleurs.
 *
 * `role="alert"` est porté par `Alerte` : VoiceOver annonce le message dès son
 * apparition sans déplacer le focus.
 */
export default function BlocErreur({ echec, onReessayer, tentative = 0 }) {
  const message = messageDeChargement(echec);
  const rejouable = estRejouable(echec) && typeof onReessayer === "function";

  if (!message) return null;

  return (
    <div className="flex flex-col gap-2.5">
      {/* `tentative` rejoue la secousse d'`Alerte` (transitions-dev 12) : sans
          elle, réessayer et retomber sur le même message donnerait
          l'impression que le bouton n'a rien fait. La secousse vit dans
          `Alerte`, jamais en double ici. */}
      <Alerte ton="erreur" tentative={tentative}>
        {message}
      </Alerte>

      {rejouable && (
        <button
          type="button"
          onClick={onReessayer}
          className="rounded-champ bg-surface text-primaire pressable min-h-tactile flex items-center justify-center px-4 text-[14px] font-medium"
        >
          Réessayer
        </button>
      )}
    </div>
  );
}
