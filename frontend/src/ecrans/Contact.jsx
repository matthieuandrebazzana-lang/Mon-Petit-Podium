import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";

export default function Contact() {
  return (
    <Ecran direction="avant">
      <Bloc rang={1}>
        <EnTete titre="Nous contacter" retourVers="/" />
      </Bloc>

      <div className="flex flex-col gap-3 pb-4">
        <Bloc rang={2}>
          <div className="rounded-bloc bg-surface shadow-bloc p-4.5">
            <div className="text-corps-sm text-texte flex flex-col gap-2">
              <p>
                Pour toute question concernant Greed F1, contacte-nous par
                email.
              </p>
              <p>
                <a href="mailto:noreply@greed-f1.com" className="text-primaire">
                  noreply@greed-f1.com
                </a>
              </p>
            </div>
          </div>
        </Bloc>
      </div>
    </Ecran>
  );
}
