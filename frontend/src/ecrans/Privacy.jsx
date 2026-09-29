import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";

/**
 * Politique de confidentialité — publique, hors des deux groupes de routage
 * (voir `App.jsx`) : un membre connecté doit pouvoir la relire, et Google ou
 * l'App Store doivent pouvoir l'atteindre sans session.
 *
 * Le retour pointe vers « / » : c'est le seul endroit de l'app qui y renvoie
 * (le lien discret de `Landing.jsx`), et c'est aussi la bonne destination pour
 * un visiteur non connecté qui l'ouvrirait en lien direct.
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

export default function Privacy() {
  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Politique de confidentialité" retourVers="/" />
      </Bloc>

      <div className="flex flex-col gap-3 pb-4">
        <Bloc rang={2}>
          <Section titre="Éditeur">
            <p>
              Greed F1 est éditée par Matthieu André-Bazzana. Contact :{" "}
              <a href="mailto:noreply@greed-f1.com" className="text-primaire">
                noreply@greed-f1.com
              </a>
              .
            </p>
          </Section>
        </Bloc>

        <Bloc rang={3}>
          <Section titre="Données collectées">
            <p>Créer un compte et jouer sur Greed F1 suppose de nous confier :</p>
            <ul className="list-disc pl-5">
              <li>ton adresse email, pour l'authentification ;</li>
              <li>ton pseudo, visible des membres de tes championnats ;</li>
              <li>ta photo de profil, si tu choisis d'en ajouter une ;</li>
              <li>tes pronostics, GP par GP ;</li>
              <li>
                la configuration de ta voiture (couleurs, numéro, livrée), que
                tu personnalises depuis ton profil.
              </li>
            </ul>
          </Section>
        </Bloc>

        <Bloc rang={4}>
          <Section titre="Utilisation des données">
            <p>
              Ces données servent uniquement à t'authentifier et à afficher ton
              profil, tes pronostics et ton classement aux membres des
              championnats que tu rejoins. Aucune n'est utilisée à des fins
              publicitaires.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={5}>
          <Section titre="Stockage">
            <p>
              Les données sont hébergées chez Supabase, sur des serveurs situés
              en Europe.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={6}>
          <Section titre="Partage">
            <p>
              Aucune donnée n'est vendue ni partagée avec des tiers à des fins
              commerciales.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={7}>
          <Section titre="Suppression de ton compte">
            <p>
              Tu peux supprimer ton compte et tes données à tout moment, depuis
              l'application : onglet Profil, puis « Supprimer mon compte ».
              La suppression est définitive.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={8}>
          <Section titre="Contact">
            <p>
              Pour toute question sur tes données, écris à{" "}
              <a href="mailto:noreply@greed-f1.com" className="text-primaire">
                noreply@greed-f1.com
              </a>
              .
            </p>
          </Section>
        </Bloc>
      </div>
    </Ecran>
  );
}
