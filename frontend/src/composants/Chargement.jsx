/**
 * Écran d'attente pendant la résolution de la session.
 *
 * Une étiquette qui scintille plutôt qu'une roue qui tourne : elle dit que
 * quelque chose avance sans promettre une durée. Le fond reste celui de l'app,
 * donc aucun flash blanc au lancement de la PWA.
 */
export default function Chargement({ libelle = "Chargement" }) {
  return (
    <main className="ecran bg-fond flex min-h-dvh items-center justify-center">
      <span className="t-shimmer text-corps font-medium" data-text={libelle}>
        {libelle}
      </span>
    </main>
  );
}
