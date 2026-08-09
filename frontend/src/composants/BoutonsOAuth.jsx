import { useState } from "react";
import Bouton from "./Bouton.jsx";
import { IconeApple, IconeGoogle } from "./Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";

/**
 * Séparateur puis Google et Apple, comme sur les maquettes 02 et 03.
 *
 * Les clés OAuth seront renseignées à la main dans le tableau de bord Supabase.
 * En attendant, `signInWithOAuth` renvoie une erreur explicite que l'on remonte
 * à l'appelant : le bouton reste vivant et dit pourquoi il ne marche pas encore,
 * au lieu de ne rien faire.
 */
export default function BoutonsOAuth({ onErreur }) {
  const { connecterAvec } = useAuth();
  const [enCours, setEnCours] = useState(null);

  async function lancer(fournisseur) {
    setEnCours(fournisseur);
    onErreur(null);
    const resultat = await connecterAvec(fournisseur);
    if (!resultat.ok) {
      onErreur(resultat.message);
      setEnCours(null);
      return;
    }
    // En cas de succès le navigateur part chez le fournisseur : on laisse
    // volontairement le bouton occupé jusqu'à la redirection.
  }

  return (
    <>
      <div className="flex items-center gap-2.5 py-1">
        <div className="bg-texte/10 h-px flex-1" />
        <span className="text-corps-sm text-texte-doux">ou continuer avec</span>
        <div className="bg-texte/10 h-px flex-1" />
      </div>

      <div className="flex flex-col gap-2.5">
        <Bouton
          variante="social"
          onClick={() => lancer("google")}
          occupe={enCours === "google"}
          libelleOccupe="Ouverture de Google…"
          disabled={Boolean(enCours)}
          className="text-corps py-4"
          icone={<IconeGoogle className="size-5 shrink-0" />}
        >
          Continuer avec Google
        </Bouton>

        <Bouton
          variante="social"
          onClick={() => lancer("apple")}
          occupe={enCours === "apple"}
          libelleOccupe="Ouverture d'Apple…"
          disabled={Boolean(enCours)}
          className="text-corps py-4"
          icone={<IconeApple className="size-5 shrink-0" />}
        >
          Continuer avec Apple
        </Bouton>
      </div>
    </>
  );
}
