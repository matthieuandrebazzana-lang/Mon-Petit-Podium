import { Link } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";

/**
 * Conditions générales d'utilisation — même statut de routage que
 * `Privacy.jsx` : publique, hors des deux groupes de `App.jsx`.
 */
function Section({ titre, children }) {
  return (
    <div className="rounded-bloc bg-surface shadow-bloc p-4.5">
      <h2 className="text-corps text-texte mb-2 font-medium">{titre}</h2>
      <div className="text-corps-sm text-texte flex flex-col gap-2">
        {children}
      </div>
    </div>
  );
}

export default function Terms() {
  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Conditions générales d'utilisation" retourVers="/" />
      </Bloc>

      <div className="flex flex-col gap-3 pb-4">
        <Bloc rang={2}>
          <Section titre="Une application gratuite">
            <p>
              Greed F1 est gratuite. Aucun achat, aucun abonnement n'est
              proposé dans l'application.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={3}>
          <Section titre="Des pronostics fictifs">
            <p>
              Les pronostics et les points qu'ils rapportent sont fictifs et
              n'ont aucune valeur financière réelle. Greed F1 n'est ni un site
              de paris, ni un opérateur de jeux d'argent : c'est un jeu amical
              entre les membres d'un même championnat.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={4}>
          <Section titre="Ton compte">
            <p>
              Tu es responsable des identifiants de ton compte et de l'usage
              qui en est fait. Signale-nous toute utilisation non autorisée à{" "}
              <a href="mailto:noreply@greed-f1.com" className="text-primaire">
                noreply@greed-f1.com
              </a>
              .
            </p>
          </Section>
        </Bloc>

        <Bloc rang={5}>
          <Section titre="Éditeur">
            <p>
              Greed F1 est éditée par Matthieu André-Bazzana. Contact :{" "}
              <a href="mailto:noreply@greed-f1.com" className="text-primaire">
                noreply@greed-f1.com
              </a>
              . Voir aussi la{" "}
              <Link to="/privacy" className="text-primaire">
                politique de confidentialité
              </Link>
              .
            </p>
          </Section>
        </Bloc>
      </div>
    </Ecran>
  );
}
