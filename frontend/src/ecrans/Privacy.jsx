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
 *
 * **Étoffée en septembre 2026** après un rejet Google (vérification OAuth) qui
 * jugeait la version précédente insuffisante. Chaque section répond à une
 * question précise plutôt que de rester générale, dans le même esprit que la
 * règle « une source unique par question » du CLAUDE.md.
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
              . Dernière mise à jour : 29 septembre 2026.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={3}>
          <Section titre="Quelles données sont collectées">
            <p>Créer un compte et jouer sur Greed F1 suppose de nous confier :</p>
            <ul className="list-disc pl-5">
              <li>
                <strong>ton adresse email</strong>, pour t'authentifier et te
                contacter si besoin (réinitialisation de mot de passe,
                confirmation d'inscription) ;
              </li>
              <li>
                <strong>ton pseudo</strong>, choisi à l'inscription et visible
                des membres des championnats que tu rejoins ;
              </li>
              <li>
                <strong>ta photo de profil</strong>, si tu choisis d'en ajouter
                une — elle est facultative et reste supprimable à tout moment ;
              </li>
              <li>
                <strong>tes pronostics</strong>, Grand Prix par Grand Prix :
                positions pronostiquées, sans commentaire ni donnée annexe ;
              </li>
              <li>
                <strong>la configuration de ta voiture</strong> — couleurs,
                numéro de course, livrée et écurie — que tu personnalises
                depuis ton profil ;
              </li>
              <li>
                <strong>tes scores</strong>, calculés automatiquement à partir
                de tes pronostics après chaque course.
              </li>
            </ul>
            <p>
              Si tu te connectes avec Google ou Apple plutôt qu'avec un mot de
              passe, ces fournisseurs nous transmettent ton adresse email et,
              selon le fournisseur, ton nom. Nous ne recevons rien d'autre de
              leur part — ni contacts, ni photos, ni données de navigation.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={4}>
          <Section titre="Comment elles sont collectées">
            <p>
              Chaque donnée est saisie directement par toi, au moment où tu en
              as l'usage — jamais suivie en arrière-plan :
            </p>
            <ul className="list-disc pl-5">
              <li>
                <strong>à l'inscription</strong> : email, mot de passe (ou
                connexion Google/Apple) et pseudo ;
              </li>
              <li>
                <strong>lors de la saisie de tes pronostics</strong>, avant
                chaque Grand Prix ;
              </li>
              <li>
                <strong>lors de la personnalisation de ta voiture</strong>,
                depuis l'écran Profil (couleurs, numéro, livrée) ;
              </li>
              <li>
                <strong>lors de l'ajout d'une photo de profil</strong>, un
                geste explicite et facultatif.
              </li>
            </ul>
            <p>
              Nous n'utilisons aucun cookie publicitaire ni traceur tiers.
              L'application conserve uniquement, dans le stockage local de ton
              navigateur ou de ton appareil, le jeton technique qui te maintient
              connecté — il ne quitte jamais ton appareil et n'est lu par
              personne d'autre que l'application elle-même.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={5}>
          <Section titre="Pourquoi elles sont collectées">
            <ul className="list-disc pl-5">
              <li>
                <strong>l'email</strong> sert exclusivement à
                l'authentification et, si tu perds ton mot de passe, à te
                l'envoyer ;
              </li>
              <li>
                <strong>le pseudo et la photo</strong> servent à t'identifier
                auprès des membres de tes championnats ;
              </li>
              <li>
                <strong>la configuration de ta voiture</strong> sert à
                t'afficher dans le classement et sur la piste sous ta propre
                identité visuelle ;
              </li>
              <li>
                <strong>tes pronostics</strong> servent au calcul de tes
                scores, seule finalité pour laquelle ils sont utilisés ;
              </li>
              <li>
                <strong>tes scores</strong> servent à établir le classement de
                chaque championnat.
              </li>
            </ul>
            <p>
              Aucune donnée n'est utilisée à des fins publicitaires, de
              profilage ou revendue sous quelque forme que ce soit.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={6}>
          <Section titre="Qui y a accès">
            <p>
              Les membres d'un même championnat voient ton pseudo, ta photo de
              profil, ta configuration de voiture et tes scores dans ce
              championnat — c'est la raison d'être de l'application. Ils ne
              voient jamais ton adresse email ni tes pronostics avant que la
              course n'ait commencé.
            </p>
            <p>
              Personne d'autre n'y a accès : ni les membres d'un championnat
              que tu n'as pas rejoint, ni un visiteur non connecté. Seul
              l'éditeur de l'application peut, en cas de nécessité technique
              (support, correction d'un bug), accéder aux données via
              l'interface d'administration de Supabase — jamais à des fins
              commerciales.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={7}>
          <Section titre="Où elles sont stockées">
            <p>
              Toutes les données sont hébergées chez Supabase, sur des serveurs
              situés en Europe (Francfort, Allemagne). Les échanges entre
              l'application et le serveur sont chiffrés (HTTPS). L'écriture des
              données passe par un serveur qui ne travaille qu'avec
              l'identifiant issu de ton jeton de connexion vérifié — le contenu
              d'une requête ne peut jamais se faire passer pour quelqu'un
              d'autre.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={8}>
          <Section titre="Combien de temps">
            <p>
              Tes données sont conservées tant que ton compte existe. Elles ne
              sont ni archivées ni conservées au-delà : la suppression de ton
              compte entraîne la suppression immédiate de tes données, décrite
              ci-dessous.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={9}>
          <Section titre="Comment les supprimer">
            <p>
              Depuis l'application : onglet <strong>Profil</strong>, puis{" "}
              <strong>« Supprimer mon compte »</strong>. La suppression est{" "}
              <strong>immédiate et définitive</strong> : tes pronostics, tes
              favoris et tes adhésions aux championnats sont effacés, ta photo
              de profil est retirée du stockage, et ton compte
              d'authentification est supprimé. Un championnat que tu as créé
              n'est pas supprimé avec toi : il est transféré à un autre membre,
              pour que les personnes qui y jouent ne perdent pas leurs
              scores déjà enregistrés.
            </p>
            <p>
              Tu peux aussi nous écrire à{" "}
              <a href="mailto:noreply@greed-f1.com" className="text-primaire">
                noreply@greed-f1.com
              </a>{" "}
              pour exercer tes droits d'accès, de rectification ou
              d'opposition sur tes données.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={10}>
          <Section titre="Partage avec des tiers">
            <p>
              Aucune donnée n'est vendue, louée ou partagée à des fins
              commerciales ou publicitaires. <strong>Supabase</strong> est le
              seul sous-traitant : il héberge la base de données et gère
              l'authentification, sous contrat et conformément au RGPD. Si tu
              choisis de te connecter avec Google ou Apple, ces fournisseurs
              interviennent uniquement comme intermédiaires de connexion, selon
              leurs propres conditions.
            </p>
          </Section>
        </Bloc>

        <Bloc rang={11}>
          <Section titre="Contact">
            <p>
              Pour toute question sur tes données, ou pour exercer tes droits,
              écris à{" "}
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
