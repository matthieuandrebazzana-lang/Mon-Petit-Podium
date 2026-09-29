import { useState } from "react";
import Bouton from "./Bouton.jsx";
import { IconeApple, IconeGoogle } from "./Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";

/**
 * Google et Apple s'activent **indépendamment**, un drapeau par fournisseur :
 * les clés Google sont renseignées dans le tableau de bord Supabase, celles
 * d'Apple viendront une fois le compte développeur Apple configuré. Un bouton
 * qui échoue systématiquement vaut moins que pas de bouton du tout.
 *
 * Rien n'est supprimé — repasser `APPLE_ACTIF` à `true` réaffiche son bouton
 * sans autre modification ailleurs.
 */
const GOOGLE_ACTIF = true;
const APPLE_ACTIF = false;

/** Le séparateur « ou continuer avec », seul sans les boutons qu'il annonce. */
function Separateur() {
  return (
    <div className="flex items-center gap-2.5 py-1">
      <div className="bg-texte/10 h-px flex-1" />
      <span className="text-corps-sm text-texte-doux">ou continuer avec</span>
      <div className="bg-texte/10 h-px flex-1" />
    </div>
  );
}

/**
 * Séparateur puis Google et Apple, comme sur les maquettes 02 et 03.
 *
 * `signInWithOAuth` renvoie une erreur explicite si le fournisseur n'est
 * finalement pas configuré côté Supabase : le bouton reste vivant et dit
 * pourquoi il ne marche pas, au lieu de ne rien faire.
 *
 * `separateurApres` inverse l'ordre pour Landing (étape « connexion Google »
 * — bouton d'abord, séparateur ensuite, avant les deux boutons « Créer un
 * compte » / « J'ai déjà un compte »). Connexion et Inscription gardent
 * l'ordre par défaut : le séparateur annonce ces boutons-ci, posés après le
 * formulaire email/mot de passe.
 */
export default function BoutonsOAuth({ onErreur, separateurApres = false }) {
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

  // Après les hooks, jamais avant : les règles de React interdisent un retour
  // anticipé qui les court-circuiterait. Le parent enveloppe l'appel dans un
  // conteneur `flex gap` — ne rien rendre y referme l'espacement de lui-même.
  if (!GOOGLE_ACTIF && !APPLE_ACTIF) return null;

  const boutons = (
    <div className="flex flex-col gap-2.5">
      {GOOGLE_ACTIF && (
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
      )}

      {APPLE_ACTIF && (
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
      )}
    </div>
  );

  if (separateurApres) {
    return (
      <>
        {boutons}
        <Separateur />
      </>
    );
  }

  return (
    <>
      <Separateur />
      {boutons}
    </>
  );
}
