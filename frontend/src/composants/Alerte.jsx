import { useSecousse } from "../lib/secousse.js";

const TONS = {
  // Aplats pleins, pas de bordure : l'erreur est un bloc du système, pas une
  // décoration posée sur un autre bloc.
  erreur: "bg-primaire text-white",
  succes: "bg-accent text-texte",
};

/**
 * Message d'authentification renvoyé par Supabase, rendu dans l'interface.
 *
 * Règle du projet : une erreur ne part jamais dans la console. Ce bloc est le
 * point d'arrivée de tout ce qui remonte du serveur, traduit en français par
 * `lib/erreurs.js`.
 *
 * `role="alert"` fait annoncer le message par VoiceOver dès son apparition,
 * sans déplacer le focus de l'utilisateur.
 */
export default function Alerte({ ton = "erreur", tentative = 0, children }) {
  const bloc = useSecousse(ton === "erreur" ? children : null, tentative);

  if (!children) return null;

  return (
    <div
      ref={bloc}
      role="alert"
      className={`t-input rounded-carte text-corps-sm px-4 py-3.5 ${TONS[ton]}`}
    >
      {children}
    </div>
  );
}
