import { useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Champ from "../composants/Champ.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import { IconeAppareilPhoto } from "../composants/Icones.jsx";
import RecadragePhoto from "../composants/RecadragePhoto.jsx";
import { enFichier } from "../lib/image.js";
import {
  creerChampionnat,
  enregistrerPhotoChampionnat,
} from "../lib/championnats.js";
import {
  COMPARTIMENT_CHAMPIONNATS,
  deposerPhoto,
  refusDuFichier,
  TYPES_ACCEPTES_ATTRIBUT,
} from "../lib/stockage.js";
import { oublierCache } from "../lib/useDonnees.js";
import { useAuth } from "../auth/AuthContexte.jsx";

const LONGUEUR_MIN = 2;
const LONGUEUR_MAX = 40;

function validerNom(valeur) {
  const nom = valeur.trim();
  if (!nom) return "Donne un nom à ton championnat.";
  if (nom.length < LONGUEUR_MIN) {
    return `Le nom doit faire au moins ${LONGUEUR_MIN} caractères.`;
  }
  if (nom.length > LONGUEUR_MAX) {
    return `Le nom ne peut pas dépasser ${LONGUEUR_MAX} caractères.`;
  }
  return null;
}

/**
 * Maquette 05 — création d'un championnat.
 *
 * > ### La photo est choisie ici, mais déposée APRÈS la création
 * >
 * > Une photo de championnat vit sous `{championnat_id}/photo.{ext}`, donc sous
 * > un identifiant que seule la création rend. L'écran retient donc le fichier
 * > choisi, crée le championnat, puis dépose et enregistre — dans cet ordre. La
 * > déposer d'abord obligerait à lui trouver un chemin provisoire, puis à la
 * > déplacer, pour le même résultat en deux fois plus d'opérations.
 * >
 * > **Un échec de la photo n'annule jamais la création.** Le joueur arrive sur
 * > son championnat sans photo plutôt que sur un formulaire à refaire : le
 * > championnat est ce qu'il venait chercher, la photo est un ornement. Le
 * > champ est d'ailleurs facultatif de bout en bout — sans fichier choisi,
 * > `photo_url` reste `null` et tout se comporte exactement comme avant.
 */
export default function CreerChampionnat() {
  const naviguer = useNavigate();
  const { utilisateur } = useAuth();

  const [nom, setNom] = useState("");
  const [erreurNom, setErreurNom] = useState(null);
  const [alerte, setAlerte] = useState(null);
  const [envoi, setEnvoi] = useState(false);
  const [tentative, setTentative] = useState(0);

  // Le fichier retenu et son aperçu. L'aperçu est une URL d'objet locale : la
  // photo n'a encore été envoyée nulle part, et montrer autre chose que le
  // fichier réellement choisi serait une promesse fausse.
  const champFichier = useRef(null);
  const [photo, setPhoto] = useState(null);
  const [apercu, setApercu] = useState(null);
  // Le fichier choisi attend son recadrage. Il n'entre dans `photo` qu'une fois
  // recadré : ce qui est en `photo` est toujours ce qui partira, jamais ce qui
  // a été pointé dans la photothèque.
  const [aRecadrer, setARecadrer] = useState(null);

  function choisirPhoto(evenement) {
    const fichier = evenement.target.files?.[0];
    // Le champ est vidé tout de suite : sans cela, rechoisir LE MÊME fichier
    // après un refus ne déclencherait aucun `change`.
    evenement.target.value = "";
    if (!fichier) return;

    const refus = refusDuFichier(fichier);
    if (refus) {
      setAlerte(refus);
      setTentative((n) => n + 1);
      return;
    }

    setAlerte(null);
    setARecadrer(fichier);
  }

  /** Le recadrage est confirmé : le JPEG obtenu devient LA photo et l'aperçu. */
  function adopterPhoto(blob) {
    setARecadrer(null);

    // L'URL précédente est révoquée : chaque `createObjectURL` retient son
    // fichier en mémoire jusqu'à ce qu'on le relâche, et changer trois fois
    // d'avis en retiendrait trois.
    if (apercu) URL.revokeObjectURL(apercu);

    const fichier = enFichier(blob, "photo");
    setPhoto(fichier);
    // L'aperçu montre le fichier RECADRÉ, et c'est tout l'intérêt : le cadre de
    // 72px de l'écran affiche désormais exactement ce que la carte d'accueil
    // affichera, au recadrage près qui vient d'être choisi.
    setApercu(URL.createObjectURL(fichier));
  }

  function retirerPhoto() {
    if (apercu) URL.revokeObjectURL(apercu);
    setPhoto(null);
    setApercu(null);
  }

  /**
   * Dépose la photo et l'attache au championnat tout juste créé.
   *
   * **Rend le message d'échec, ou `null`.** Elle ne lève pas et n'interrompt pas
   * la navigation : c'est le même arbitrage que pour le rang d'une carte
   * d'accueil — une opération secondaire en panne ne fait jamais perdre la
   * principale, et le championnat est ce que le joueur venait chercher.
   *
   * > ### Mais l'échec ne se tait plus (version `0.51.0`)
   * >
   * > Jusqu'ici cette fonction rendait `undefined` dans tous les cas et son échec
   * > n'atteignait personne. C'est ce silence qui a laissé la version `0.50.0`
   * > entière convaincue que les photos de championnat marchaient, alors
   * > qu'**aucune** ne s'enregistrait : la contrainte `check` de la migration 16
   * > était incompilable et refusait toute écriture (`docs/bugs-connus.md` §18).
   * > Le message remonte donc maintenant jusqu'à l'écran d'arrivée, qui l'annonce
   * > une fois. Un échec qu'on choisit de ne pas bloquer doit quand même se dire.
   */
  async function attacherPhoto(championnatId) {
    const depot = await deposerPhoto({
      compartiment: COMPARTIMENT_CHAMPIONNATS,
      dossier: championnatId,
      base: "photo",
      fichier: photo,
    });
    if (!depot.ok) return depot.message;

    // L'URL n'est enregistrée qu'après un dépôt réussi : l'inverse laisserait en
    // base l'adresse d'un objet inexistant, donc une image cassée sur la carte
    // d'accueil de chaque membre.
    const enregistrement = await enregistrerPhotoChampionnat(
      championnatId,
      depot.donnees,
    );
    return enregistrement.ok ? null : enregistrement.message;
  }

  async function soumettre(evenement) {
    evenement.preventDefault();
    setTentative((n) => n + 1);

    const probleme = validerNom(nom);
    setErreurNom(probleme);
    if (probleme) {
      setAlerte(null);
      return;
    }

    setEnvoi(true);
    setAlerte(null);

    const resultat = await creerChampionnat(nom.trim());

    if (!resultat.ok) {
      setEnvoi(false);
      setAlerte(resultat.message);
      return;
    }

    const echecPhoto = photo ? await attacherPhoto(resultat.donnees.id) : null;

    setEnvoi(false);

    // La liste de l'accueil vient d'un cache : sans cette invalidation, le
    // championnat tout juste créé n'y apparaîtrait qu'au rafraîchissement
    // suivant, et le retour depuis l'écran du championnat semblerait l'avoir
    // perdu. L'effacement vient APRÈS la photo : fait avant, il laisserait une
    // liste rechargée sans elle.
    if (utilisateur) oublierCache(`championnats:${utilisateur.id}`);

    // `nouveau` fait mettre le code d'invitation en avant à l'arrivée, et
    // `replace` retire cet écran de l'historique : le geste de retour ramène
    // sur l'accueil, pas sur un formulaire déjà validé.
    naviguer(`/championnats/${resultat.donnees.id}`, {
      replace: true,
      state: { nouveau: true, echecPhoto },
    });
  }

  return (
    <Ecran direction="avant">
      {aRecadrer && (
        <RecadragePhoto
          source={aRecadrer}
          forme="carre"
          titre="La photo du championnat"
          onConfirmer={adopterPhoto}
          onAnnuler={() => setARecadrer(null)}
        />
      )}

      <Bloc rang={1}>
        <EnTete titre="Créer un championnat" retourVers="/accueil" />
      </Bloc>

      <form onSubmit={soumettre} className="flex flex-col gap-3" noValidate>
        <Bloc rang={2} className="rounded-bloc bg-surface shadow-bloc p-4.5">
          <Champ
            label="Nom du championnat"
            name="nom"
            type="text"
            autoComplete="off"
            placeholder="Les Potes F1"
            maxLength={LONGUEUR_MAX}
            value={nom}
            onChange={(evenement) => {
              setNom(evenement.target.value);
              if (erreurNom) setErreurNom(null);
              setAlerte(null);
            }}
            erreur={erreurNom}
            tentative={tentative}
          />

          {/* Le sélecteur de fichier natif, invisible mais dans le DOM : c'est
              le cadre ci-dessous qui l'ouvre. `hidden` et non un parent en
              `display:none` — un `<input type="file">` réellement retiré du
              rendu ne s'ouvre plus sur iOS. */}
          <input
            ref={champFichier}
            type="file"
            accept={TYPES_ACCEPTES_ATTRIBUT}
            onChange={choisirPhoto}
            className="hidden"
            tabIndex={-1}
            aria-hidden="true"
          />

          {/* **La photo suit le nom, et le libellé dit qu'elle est facultative.**
              Elle est sous le champ qu'elle complète, pas au-dessus : le nom est
              la seule chose obligatoire de cet écran, et rien ne doit passer
              devant lui.

              Le cadre est un carré de 72px, la taille exacte qu'aura la photo
              sur l'écran du championnat : ce qu'on choisit ici est montré à la
              taille où on le reverra. Un aperçu plus grand que la destination
              ferait paraître cadré ce qui ne l'est pas.

              **Sans photo, le cadre reste un cadre vide et cliquable** — et
              c'est le seul endroit de cette version où un emplacement vide est
              dessiné. Ailleurs, une photo absente n'affiche rien du tout ; ici
              le vide EST le contrôle, il faut bien qu'il ait une silhouette. Il
              est en `bg-fond` sans bordure : la section 5 proscrit les traits
              fins, et un aplat plus foncé que la carte blanche suffit à dire
              « ceci est une zone ». */}
          <div className="mt-4 flex items-center gap-3.5">
            <button
              type="button"
              onClick={() => champFichier.current?.click()}
              disabled={envoi}
              aria-label={
                photo ? "Changer la photo du championnat" : "Ajouter une photo"
              }
              className="rounded-widget bg-fond text-secondaire pressable relative flex size-[72px] shrink-0 items-center justify-center overflow-hidden"
            >
              {apercu ? (
                <img
                  src={apercu}
                  alt=""
                  draggable="false"
                  className="absolute inset-0 h-full w-full object-cover"
                />
              ) : (
                <IconeAppareilPhoto className="size-6" />
              )}
            </button>

            <div className="min-w-0 flex-1">
              {/* Le libellé n'est pas dans le cadre : à 72px, « Ajouter une
                  photo (optionnel) » n'y tiendrait qu'en quatre lignes de neuf
                  pixels. Posé à côté, il reste lisible et sert de seconde zone
                  de lecture pour un contrôle qui n'a pas d'étiquette propre. */}
              <p className="text-corps-sm text-texte font-medium">
                {photo ? "Photo du championnat" : "Ajouter une photo"}
              </p>
              <p className="text-texte-doux mt-0.5 text-[12px]">
                {photo
                  ? "Elle s'affichera sur la carte du championnat."
                  : "Optionnel · JPG, PNG ou WEBP, 2 Mo maximum"}
              </p>

              {/* Le retrait n'existe que quand il y a quelque chose à retirer.
                  Marron `secondaire` et non `texte-doux`, qui ne vaut que 2,0:1
                  sur blanc : c'est une action qu'on vient lire. */}
              {photo && (
                <button
                  type="button"
                  onClick={retirerPhoto}
                  disabled={envoi}
                  className="text-secondaire min-h-tactile pressable -my-2 -ml-1 px-1 py-2 text-[13px] font-medium disabled:opacity-50"
                >
                  Retirer
                </button>
              )}
            </div>
          </div>
        </Bloc>

        {/* Le code n'existe pas encore : il est tiré par le serveur à la
            création, et il serait malhonnête d'en afficher un avant qu'il soit
            réservé en base. Le bloc garde sa place et son rôle dans la
            composition de la maquette, et annonce ce qui va s'y inscrire. */}
        <Bloc rang={3} className="rounded-bloc bg-primaire shadow-bloc p-5">
          <p className="text-label uppercase text-white/60">Code d'invitation</p>
          <p
            aria-hidden="true"
            className="text-score mt-2 tracking-[6px] text-white/25"
          >
            ——————
          </p>
          <p className="text-corps-sm mt-1.5 text-white/50">
            Généré automatiquement à la création.
          </p>
        </Bloc>

        {alerte && (
          <Alerte ton="erreur" tentative={tentative}>
            {alerte}
          </Alerte>
        )}

        <Bloc rang={4}>
          <Bouton
            type="submit"
            variante="principal"
            occupe={envoi}
            libelleOccupe="Création…"
          >
            Créer le championnat
          </Bouton>
        </Bloc>
      </form>
    </Ecran>
  );
}
