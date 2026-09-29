import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useLocation, useNavigate, useParams } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTeteEcran from "../composants/EnTeteEcran.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import Pastille from "../composants/Pastille.jsx";
import MentionProvisoire from "../composants/MentionProvisoire.jsx";
import TexteEchange from "../composants/TexteEchange.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import RecadragePhoto from "../composants/RecadragePhoto.jsx";
import { Pave } from "../composants/Squelette.jsx";
import TuileDrapeau from "../composants/TuileDrapeau.jsx";
import {
  IconeChevronDroit,
  IconeCoche,
  IconeCopie,
  IconeSortie,
} from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerChampionnat,
  enregistrerPhotoChampionnat,
  quitterChampionnat,
} from "../lib/championnats.js";
import { enFichier } from "../lib/image.js";
import {
  COMPARTIMENT_CHAMPIONNATS,
  deposerPhoto,
  refusDuFichier,
  supprimerPhoto,
  TYPES_ACCEPTES_ATTRIBUT,
} from "../lib/stockage.js";
import {
  chargerClassement,
  cleClassement,
  saisonCommencee,
} from "../lib/classement.js";
import { formaterPoints } from "../lib/format.js";
import { couleurChampionnat, tonalites } from "../lib/couleurs.js";
import { couleurLisible, encreSur } from "../lib/palette.js";
import { modifierCache, oublierCache, useDonnees } from "../lib/useDonnees.js";

const DUREE_CONFIRMATION = 2000;

/**
 * En-tête coloré du championnat, désormais rétractable.
 *
 * La barre de retour est collée en haut et porte la couleur du championnat en
 * permanence ; le nom, lui, vit dans l'aplat juste dessous et glisse sous la
 * barre au défilement, où il se replace en petit. C'est la barre de navigation
 * teintée d'iOS, et c'est `EnTeteEcran` qui en porte toute la mécanique — la
 * couleur passe derrière la Dynamic Island, jamais le texte.
 *
 * Le tracé du circuit n'y figure pas : un championnat n'est pas un Grand Prix.
 * L'aplat porte en revanche sa lumière spéculaire, comme les cartes de
 * l'accueil, pour que les deux écrans se répondent.
 */
function heroChampionnat(couleur) {
  return { hex: couleur.hex, fond: couleur.fond, ton: tonalites(couleur.hex) };
}

/**
 * Bloc du code d'invitation.
 *
 * *Écart assumé par rapport à l'état antérieur* : il était un aplat rouge, il
 * devient une carte blanche dont seul le code prend la couleur du championnat.
 * Deux aplats de couleur pleine à la suite — l'en-tête puis le code — se
 * seraient disputé le même écran, et le rouge de la marque sous un en-tête
 * violet aurait donné deux couleurs concurrentes sur une même page. Une seule
 * couleur par écran, portée par l'en-tête : c'est aussi ce que demande le
 * verrou de cohérence du skill Taste.
 */
function BlocCode({ code, couleur, miseEnAvant }) {
  const [copie, setCopie] = useState(false);
  const [echec, setEchec] = useState(false);
  const ton = tonalites(couleur.hex);

  useEffect(() => {
    if (!copie) return undefined;
    const minuterie = setTimeout(() => setCopie(false), DUREE_CONFIRMATION);
    return () => clearTimeout(minuterie);
  }, [copie]);

  async function copier() {
    try {
      // `navigator.clipboard` n'existe qu'en contexte sécurisé. En HTTP simple
      // — un test depuis le réseau local, par exemple — l'appel n'existe pas :
      // on le dit au lieu de laisser un bouton qui ne fait rien.
      if (!navigator.clipboard) throw new Error("presse-papiers indisponible");
      await navigator.clipboard.writeText(code);
      setEchec(false);
      setCopie(true);
    } catch {
      setEchec(true);
    }
  }

  return (
    <div className="rounded-carte bg-surface shadow-carte flex items-center gap-3 p-4">
      <div className="min-w-0 flex-1">
        <p className="text-label text-texte-doux uppercase">Code d'invitation</p>
        <p
          className="mt-1 text-[26px] leading-none font-medium tracking-[5px]"
          style={{ color: couleur.hex }}
        >
          {code}
        </p>
        {/* Le retour de création reste dit à l'arrivée sur l'écran : sans lui,
            valider « Créer » débouche sur un écran qui ne confirme rien. */}
        {miseEnAvant && !echec && (
          <p className="text-corps-sm text-texte-doux mt-1.5">
            Championnat créé. Partage ce code pour inviter tes amis.
          </p>
        )}
        {echec && (
          <p role="alert" className="text-corps-sm text-texte-doux mt-2">
            Copie impossible sur cet appareil. Note le code : {code}
          </p>
        )}
      </div>

      <button
        type="button"
        onClick={copier}
        className={`rounded-champ pressable min-h-tactile flex shrink-0 items-center gap-2 px-3.5 text-[13px] font-medium ${couleur.fond} ${ton.texte}`}
      >
        {copie ? (
          <IconeCoche className="size-3.5" />
        ) : (
          <IconeCopie className="size-3.5" />
        )}
        <TexteEchange valeur={copie ? "Copié" : "Copier"} />
      </button>
    </div>
  );
}

/**
 * Une ligne du classement — carte blanche à filet coloré, refonte de la
 * maquette 07. Exportée nommément pour pouvoir être rendue hors navigateur : le
 * composant d'écran dépend de la session, qui ne se résout que dans un effet.
 *
 * Le filet de 4px porte la couleur de la **voiture du membre**, pas celle du
 * championnat : c'est la personne qu'on cherche à reconnaître dans une liste, et
 * c'est la même couleur qu'elle porte sur la vue piste et sur son profil. Ce
 * n'est pas une bordure au sens de la section 5 — la section proscrit les traits
 * fins qui cernent un bloc ; celui-ci est un aplat posé à l'intérieur, et il
 * remplace justement la pastille d'initiale qui tenait ce rôle avant.
 */
export function LigneClassement({
  ligne,
  estMoi,
  estCreateur,
  aDesPoints,
  avecPhotos = false,
}) {
  const podium = ligne.rang <= 3;

  // Sous-ligne : les deux critères qui départagent avant l'ordre d'inscription
  // (règle 4.6). La maquette y répète le total, déjà affiché à droite ; dire ce
  // qui sépare deux joueurs à égalité de points est plus utile.
  const detail = aDesPoints
    ? [
        `${ligne.pronostics_reussis} ${
          ligne.pronostics_reussis > 1 ? "réussis" : "réussi"
        }`,
        ligne.meilleure_cote
          ? `meilleur coup ${formaterPoints(ligne.meilleure_cote)}`
          : null,
      ]
        .filter(Boolean)
        .join(" · ")
    : "En attente du premier Grand Prix";

  const teinteVoiture = couleurLisible(ligne);

  return (
    <li>
      <Link
        to={`/profils/${ligne.profil_id}`}
        className="rounded-carte bg-surface shadow-carte pressable-large min-h-tactile relative flex items-center gap-3 overflow-hidden py-3 pr-4 pl-4"
      >
        <span
          aria-hidden="true"
          className="absolute inset-y-0 left-0 w-1"
          style={{ backgroundColor: teinteVoiture }}
        />

        {/* Le rang des trois premiers est posé dans une pastille à la couleur de
            la voiture du membre, les autres restent en chiffre nu. Le podium
            doit se repérer sans lire les nombres — c'est la hiérarchie visuelle
            du §16 d'/apple-design : le plus important est aussi le plus
            évident. L'encre de la pastille est calculée pour rester lisible
            quelle que soit la livrée choisie. */}
        {podium ? (
          <span
            className="flex size-8 shrink-0 items-center justify-center rounded-full text-[15px] leading-none font-medium"
            style={{
              backgroundColor: teinteVoiture,
              color: encreSur(teinteVoiture),
            }}
          >
            {ligne.rang}
          </span>
        ) : (
          <span className="text-texte-doux flex size-8 shrink-0 items-center justify-center text-[17px] leading-none font-medium">
            {ligne.rang}
          </span>
        )}

        {/* La pastille d'identité, collée au pseudo qu'elle illustre — pas au
            rang, qui dit autre chose. C'est la règle de proximité
            d'/apple-design §16 : un élément se pose à côté de ce qu'il décrit.

            **Elle n'apparaît QUE si quelqu'un, dans ce championnat, a une
            photo** (`avecPhotos`). Sans cette condition, un championnat où
            personne n'en a gagnerait une colonne d'initiales posées à côté du
            pseudo qu'elles abrègent — la même information deux fois, et
            quarante-huit pixels pris au seul texte de la rangée. Avec elle, la
            colonne est soit absente, soit alignée pour tout le monde : ceux qui
            n'ont pas de photo y gardent leurs initiales, et la liste ne
            s'ébrèche pas. */}
        {avecPhotos && (
          <Pastille
            nom={ligne.pseudo}
            graine={ligne.profil_id}
            photo={ligne.avatar_url}
            couleur={teinteVoiture}
          />
        )}

        <div className="min-w-0 flex-1">
          <p className="text-corps-sm text-texte truncate font-medium">
            {ligne.pseudo}
            {estMoi && <span className="text-primaire"> · Toi</span>}
            {estCreateur && <span className="text-texte-doux"> · Créateur</span>}
          </p>
          <p className="text-texte-doux mt-0.5 truncate text-[12px]">{detail}</p>
        </div>

        <div className="shrink-0 text-right">
          <p className="text-primaire text-[22px] leading-none font-medium tracking-[-0.02em]">
            {ligne.total_points}
          </p>
          <p className="text-label-sm text-texte-doux mt-1 uppercase">pts</p>
        </div>
      </Link>
    </li>
  );
}

function SqueletteChampionnat() {
  return (
    <div className="flex flex-col gap-3">
      <Pave className="h-[86px]" arrondi="rounded-carte" />
      <div className="flex flex-col gap-2">
        {[0, 1, 2].map((rang) => (
          <Pave key={rang} className="h-[70px]" arrondi="rounded-carte" />
        ))}
      </div>
    </div>
  );
}

/** Maquette 07 — vue d'un championnat : en-tête coloré, code, classement. */
export default function Championnat() {
  const { id } = useParams();
  const naviguer = useNavigate();
  const emplacement = useLocation();
  const { utilisateur } = useAuth();

  const nouveau = Boolean(emplacement.state?.nouveau);
  /**
   * Tout ce qui peut mal tourner avec la photo — **un seul état, deux sources**.
   *
   * Il naît de l'écran de création, qui n'attend pas la photo : le joueur est
   * envoyé sur son championnat quoi qu'il arrive (`CreerChampionnat`), et cet
   * écran est le premier endroit où le lui dire. Depuis la version `0.75.0` il
   * porte aussi les échecs de la modification faite ICI — refus du fichier,
   * dépôt impossible, enregistrement refusé.
   *
   * **Deux états auraient été deux messages au même endroit**, et le second
   * aurait fini par s'afficher sous le premier : c'est la même phrase, au même
   * emplacement, pour la même chose. Il est effacé au premier appui — un message
   * d'échec n'est pas un état du championnat et ne doit pas revenir à chaque
   * retour sur l'écran.
   */
  const [echecPhoto, setEchecPhoto] = useState(
    emplacement.state?.echecPhoto ?? null,
  );

  // Comme pour l'accueil, la clé de cache porte le compte : un championnat lu
  // par quelqu'un d'autre sur le même appareil ne doit pas ressortir ici.
  const cle = utilisateur ? `championnat:${utilisateur.id}:${id}` : null;
  const chargeur = useCallback((signal) => chargerChampionnat(id, signal), [id]);
  const { donnees, chargement, echec, recharger, remplacer } = useDonnees(
    cle,
    chargeur,
  );

  // Le classement suit son propre chemin : il passe par l'API, là où le détail
  // du championnat se lit directement dans Supabase. Les deux chargements sont
  // donc indépendants — et c'est voulu. Si Railway se réveille lentement, ou
  // même s'il échoue, le championnat et ses membres restent affichés.
  const cleRang = utilisateur ? cleClassement(utilisateur.id, id) : null;
  const chargeurRang = useCallback(
    (signal) => chargerClassement(id, signal),
    [id],
  );
  const {
    donnees: classement,
    chargement: chargementRang,
    echec: echecRang,
    recharger: rechargerRang,
  } = useDonnees(cleRang, chargeurRang);

  // ---- Photo du championnat -----------------------------------------------
  // Réservée au créateur, et c'est la ROUTE qui le vérifie : `PATCH
  // /championnats/{id}` relit `cree_par` à partir de l'identifiant du jeton et
  // refuse en `403` (`docs/architecture.md` §12). Ce que l'écran décide ici
  // n'est donc pas une autorisation, c'est l'affichage d'un contrôle qui
  // n'aboutirait pour personne d'autre.
  const champFichier = useRef(null);
  const [envoiPhoto, setEnvoiPhoto] = useState(false);
  const [tentativePhoto, setTentativePhoto] = useState(0);
  /**
   * Ce que le recadrage doit ouvrir : un fichier tout juste choisi, ou l'URL de
   * la photo en place. `null` quand le recadrage est fermé.
   */
  const [aRecadrer, setARecadrer] = useState(null);

  /**
   * Écrit la nouvelle photo partout où elle s'affiche, **sans recharger quoi que
   * ce soit**.
   *
   * Trois endroits la montrent : l'en-tête de cet écran, la carte de l'accueil
   * et la liste des championnats. Les deux derniers partagent une seule entrée
   * de cache (`championnats:{profil}`) — c'est le même chargement, donc la même
   * clé, et il n'y a qu'un endroit à retoucher pour les deux.
   *
   * **On retouche, on ne périme pas.** `oublierCache` marcherait, mais l'accueil
   * repartirait alors sans rien à montrer et attendrait le réveil de Railway
   * pour une photo de soixante-douze pixels (`lib/useDonnees.js`). Seule la
   * colonne qui a changé est réécrite, sur la seule ligne concernée : le reste
   * de la liste — rangs, effectifs, prochain Grand Prix — reste ce qu'il était,
   * et la prochaine revalidation confirmera.
   */
  const adopterPhoto = useCallback(
    (url) => {
      // `remplacer` et non `setDonnees` : ce dernier ne touche que l'état React,
      // et le cache relu au montage suivant ressortirait l'ancienne photo.
      if (donnees) remplacer({ ...donnees, photo_url: url });
      if (!utilisateur) return;
      modifierCache(`championnats:${utilisateur.id}`, (liste) =>
        Array.isArray(liste)
          ? liste.map((championnat) =>
              championnat.id === id
                ? { ...championnat, photo_url: url }
                : championnat,
            )
          : undefined,
      );
    },
    [donnees, id, remplacer, utilisateur],
  );

  /**
   * Le geste d'entrée dans le flux, et **il dépend de ce qui existe déjà**.
   *
   * Sans photo, il n'y a rien à recadrer : on ouvre la photothèque. Avec une
   * photo, le recadrage s'ouvre sur **elle** — c'est son point de départ naturel,
   * et refaire son cadrage est le geste le plus fréquent une fois la photo
   * posée. La photothèque reste à un doigt, dans le recadrage lui-même.
   */
  function ouvrirPhoto() {
    setTentativePhoto((n) => n + 1);
    setEchecPhoto(null);
    if (donnees?.photo_url) {
      setARecadrer(donnees.photo_url);
      return;
    }
    champFichier.current?.click();
  }

  function choisirPhoto(evenement) {
    const fichier = evenement.target.files?.[0];
    // Le champ est vidé tout de suite : sans cela, rechoisir LE MÊME fichier
    // après un refus ne déclencherait aucun `change`, et l'écran resterait muet
    // sur un geste que le joueur vient pourtant de refaire.
    evenement.target.value = "";
    if (!fichier) return;

    setTentativePhoto((n) => n + 1);

    // Le refus local d'abord : une image que le navigateur ne saura pas décoder
    // n'a rien à faire dans un recadrage qui n'aurait alors rien à montrer.
    const refus = refusDuFichier(fichier);
    if (refus) {
      setARecadrer(null);
      setEchecPhoto(refus);
      return;
    }

    setEchecPhoto(null);
    setARecadrer(fichier);
  }

  /**
   * Dépose la photo recadrée, puis attache son URL au championnat.
   *
   * Elle reçoit un `Blob` sorti du canvas, jamais le fichier de la photothèque :
   * la taille, le format et la qualité ont un propriétaire (`lib/image.js`), et
   * ce n'est pas cet écran. Même enchaînement qu'au profil, dans le même ordre.
   */
  async function envoyerPhoto(blob) {
    setARecadrer(null);
    setTentativePhoto((n) => n + 1);
    setEnvoiPhoto(true);
    setEchecPhoto(null);

    const depot = await deposerPhoto({
      compartiment: COMPARTIMENT_CHAMPIONNATS,
      dossier: id,
      base: "photo",
      fichier: enFichier(blob, "photo"),
    });

    if (!depot.ok) {
      setEnvoiPhoto(false);
      setEchecPhoto(depot.message);
      return;
    }

    // L'URL n'est enregistrée qu'APRÈS un dépôt réussi : l'inverse laisserait en
    // base l'adresse d'un objet qui n'existe pas, donc une image cassée sur
    // l'écran de tous les membres du championnat.
    const enregistrement = await enregistrerPhotoChampionnat(id, depot.donnees);
    setEnvoiPhoto(false);

    if (!enregistrement.ok) {
      setEchecPhoto(enregistrement.message);
      return;
    }

    adopterPhoto(enregistrement.donnees.photo_url ?? depot.donnees);
  }

  async function retirerPhoto() {
    setTentativePhoto((n) => n + 1);
    setEnvoiPhoto(true);
    setEchecPhoto(null);

    // La base d'abord, le stockage ensuite : c'est la colonne qui décide de ce
    // qui s'affiche. Un objet resté en stockage sans être référencé n'est plus
    // visible nulle part ; une colonne qui garderait l'URL d'un objet supprimé
    // afficherait une image cassée partout (`lib/stockage.js`).
    const enregistrement = await enregistrerPhotoChampionnat(id, null);

    if (!enregistrement.ok) {
      setEnvoiPhoto(false);
      setEchecPhoto(enregistrement.message);
      return;
    }

    await supprimerPhoto({
      compartiment: COMPARTIMENT_CHAMPIONNATS,
      dossier: id,
      base: "photo",
    });

    setEnvoiPhoto(false);
    adopterPhoto(null);
  }

  const [confirmation, setConfirmation] = useState(false);
  const [depart, setDepart] = useState(false);
  const [erreurDepart, setErreurDepart] = useState(null);
  const [tentative, setTentative] = useState(0);
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayer() {
    setTentativeChargement((n) => n + 1);
    recharger();
    rechargerRang();
  }

  async function quitter() {
    setDepart(true);
    setErreurDepart(null);
    setTentative((n) => n + 1);

    const resultat = await quitterChampionnat(id);

    if (!resultat.ok) {
      setDepart(false);
      setConfirmation(false);
      setErreurDepart(resultat.message);
      return;
    }

    if (cle) oublierCache(cle);
    if (utilisateur) oublierCache(`championnats:${utilisateur.id}`);
    naviguer("/accueil", { replace: true });
  }

  // La couleur est calculée sur ce qu'on sait déjà : l'identifiant de l'URL
  // suffit, elle ne dépend donc pas du chargement. L'en-tête est peint dès la
  // première image, et ne change pas de teinte quand les données arrivent.
  const couleur = couleurChampionnat({ id, ...(donnees ?? {}) });

  const teinte = heroChampionnat(couleur);

  // Sortie de secours : sans championnat lisible, il n'y a rien à afficher, et
  // l'écran ne doit surtout pas être un cul-de-sac.
  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <EnTeteEcran
          titre="Championnat"
          sousTitre="Saison 2026"
          retourVers="/accueil"
          libelleRetour="Accueil"
          teinte={teinte}
        />
        <Bloc rang={1} className="mt-3">
          <BlocErreur
            echec={echec}
            onReessayer={reessayer}
            tentative={tentativeChargement}
          />
        </Bloc>
      </Ecran>
    );
  }

  const membres = donnees?.membres ?? [];
  const lignes = classement ?? [];
  // L'effectif vient du classement dès qu'il est là : c'est la seule des deux
  // sources qui compte les membres sans dépendre de la RLS.
  const effectif = lignes.length || membres.length;
  const aDesPoints = saisonCommencee(lignes);
  // **Une seule question, posée une fois pour toute la liste** : ce championnat
  // compte-t-il au moins une photo ? Elle décide de la présence de la colonne de
  // pastilles, pas de son contenu — voir `LigneClassement`. Posée ligne par
  // ligne, elle donnerait une liste ébréchée, certaines rangées portant une
  // pastille et d'autres non.
  const avecPhotos = lignes.some((ligne) => Boolean(ligne.avatar_url));
  // **La photo ne se modifie que par son créateur**, et c'est la seule question
  // que l'écran pose ici. Tant que le championnat n'est pas lu, la réponse est
  // « non » : afficher le contrôle sur la foi de rien le ferait apparaître puis
  // disparaître chez un membre ordinaire.
  const estCreateur = Boolean(
    donnees?.cree_par && utilisateur?.id && donnees.cree_par === utilisateur.id,
  );

  return (
    <Ecran direction="avant">
      {/* Le recadrage est un portail vers `document.body` : monté ici dans le
          JSX pour que sa place dans le code dise à quel geste il appartient,
          rendu ailleurs pour échapper au `transform` d'`Ecran`.

          `onChoisirAutre` n'est offert que lorsque la source EST la photo en
          place : quand elle est le fichier qu'on vient de choisir, « choisir une
          autre photo » ne remplacerait rien qui ait été enregistré. */}
      {aRecadrer && (
        <RecadragePhoto
          source={aRecadrer}
          forme="carre"
          titre="La photo du championnat"
          occupe={envoiPhoto}
          onConfirmer={envoyerPhoto}
          onAnnuler={() => setARecadrer(null)}
          onChoisirAutre={
            typeof aRecadrer === "string"
              ? () => champFichier.current?.click()
              : null
          }
        />
      )}

      {/* Le sélecteur de fichier natif, invisible mais dans le DOM : c'est la
          photo de l'en-tête qui l'ouvre. `hidden` et non un parent en
          `display:none` — un `<input type="file">` réellement retiré du rendu ne
          s'ouvre plus sur iOS. Ni `capture` ni `multiple` : le premier forcerait
          l'appareil photo et retirerait l'accès à la photothèque, le second
          n'aurait aucun sens pour une image qui en remplace une autre. */}
      {estCreateur && (
        <input
          ref={champFichier}
          type="file"
          accept={TYPES_ACCEPTES_ATTRIBUT}
          onChange={choisirPhoto}
          className="hidden"
          tabIndex={-1}
          aria-hidden="true"
        />
      )}

      <EnTeteEcran
        titre={donnees?.nom ?? "Championnat"}
        sousTitre={
          chargement && !donnees
            ? "Chargement…"
            : `${effectif} ${effectif > 1 ? "membres" : "membre"} · Saison 2026`
        }
        retourVers="/accueil"
        libelleRetour="Accueil"
        teinte={teinte}
        photo={donnees?.photo_url}
        onPhoto={estCreateur ? ouvrirPhoto : null}
        envoiPhoto={envoiPhoto}
      />

      <div className="mt-3 flex flex-1 flex-col gap-3">
        {/* Le message d'échec de la photo — celui rapporté de la création, et
            ceux de la modification faite ici. Il se masque d'un appui : un
            échec n'est pas un état du championnat et ne doit pas revenir à
            chaque retour sur l'écran. Le bouton porte son propre libellé
            accessible : le `role="alert"` du bloc annonce déjà le texte, le
            répéter en nom de bouton le ferait entendre deux fois. La cible fait
            toute la largeur du bloc, donc bien au-delà des 44 px de la règle
            iOS. */}
        {echecPhoto && (
          <Bloc rang={1}>
            <button
              type="button"
              onClick={() => setEchecPhoto(null)}
              aria-label="Masquer ce message"
              className="pressable-large block w-full text-left"
            >
              <Alerte ton="erreur" tentative={tentativePhoto}>
                {echecPhoto}
              </Alerte>
            </button>
          </Bloc>
        )}

        {/* **Le retrait n'existe que quand il y a quelque chose à retirer** — un
            « Supprimer la photo » toujours présent laisserait croire qu'il en
            existe une. Il est posé sous l'en-tête, juste sous la photo qu'il
            efface : un contrôle se place à côté de ce qu'il modifie
            (/apple-design §16).

            En texte et non en bouton plein : l'action principale de cet écran
            n'est pas la photo, et un bouton de plein poids l'aurait fait passer
            devant le code d'invitation. Marron `secondaire` et non
            `texte-doux`, qui ne vaut que 2,0:1 sur le beige — c'est une phrase
            qu'on vient lire, et de plus une action qui efface. */}
        {estCreateur && donnees?.photo_url && (
          <Bloc rang={1}>
            <div className="-mt-1 flex">
              <button
                type="button"
                onClick={retirerPhoto}
                disabled={envoiPhoto}
                className="text-secondaire min-h-tactile pressable -my-2 px-1 py-2 text-[13px] font-medium disabled:opacity-50"
              >
                Supprimer la photo
              </button>
            </div>
          </Bloc>
        )}

        <Bloc rang={1}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteChampionnat />}
          >
            {donnees && (
              <div className="flex flex-col gap-3">
                <BlocCode
                  code={donnees.code_invitation}
                  couleur={couleur}
                  miseEnAvant={nouveau}
                />

                <div className="flex flex-col gap-2">
                  {/* La mention « Provisoire » vit tant que le dernier Grand
                      Prix couru n'a pas son calcul définitif (24 h après la
                      course) : le classement peut encore bouger. Le serveur la
                      porte sur chaque ligne, la première suffit. */}
                  <div className="flex items-baseline justify-between gap-3 px-1">
                    <p className="text-label text-texte-doux uppercase">
                      {lignes.length > 0 ? "Classement" : "Membres"}
                    </p>
                    {lignes[0]?.resultats_provisoires === true && <MentionProvisoire />}
                  </div>

                  {/* Le classement remplace la liste des membres dès qu'il est
                      là. Tant qu'il n'est pas revenu — Railway se réveille — la
                      liste lue sous RLS tient sa place : elle porte les mêmes
                      personnes, sans les points. Un bloc vide serait pire. */}
                  {lignes.length > 0 ? (
                    <ul className="flex flex-col gap-2">
                      {lignes.map((ligne) => (
                        <LigneClassement
                          key={ligne.profil_id}
                          ligne={ligne}
                          estMoi={ligne.profil_id === utilisateur?.id}
                          estCreateur={ligne.profil_id === donnees.cree_par}
                          aDesPoints={aDesPoints}
                          avecPhotos={avecPhotos}
                        />
                      ))}
                    </ul>
                  ) : (
                    <ul className="flex flex-col gap-2">
                      {membres.map((membre) => (
                        <li key={membre.id}>
                          <Link
                            to={`/profils/${membre.id}`}
                            className="rounded-carte bg-surface shadow-carte pressable-large min-h-tactile flex items-center gap-3 p-4"
                          >
                            <Pastille
                              nom={membre.pseudo}
                              graine={membre.id}
                              photo={membre.avatarUrl}
                            />
                            <span className="text-corps-sm text-texte min-w-0 flex-1 truncate font-medium">
                              {membre.pseudo}
                            </span>
                            {membre.id === donnees.cree_par && (
                              <span className="text-label-sm text-texte-doux uppercase">
                                Créateur
                              </span>
                            )}
                            {membre.id === utilisateur?.id && (
                              <span className="text-label-sm text-primaire uppercase">
                                Toi
                              </span>
                            )}
                          </Link>
                        </li>
                      ))}
                    </ul>
                  )}

                  {lignes.length === 0 && chargementRang && (
                    <p className="text-texte-doux mt-1 px-1 text-[12px]">
                      <span
                        className="t-shimmer"
                        data-text="Classement en cours de chargement…"
                      >
                        Classement en cours de chargement…
                      </span>
                    </p>
                  )}

                  {/* Le classement a échoué mais les membres sont là : on le
                      dit sous la liste, sans emporter l'écran. C'est le même
                      arbitrage que depuis l'étape 7 — deux chargements
                      indépendants, et celui qui tient debout reste affiché. */}
                  {lignes.length === 0 && !chargementRang && echecRang && (
                    <div className="mt-2">
                      <BlocErreur
                        echec={echecRang}
                        onReessayer={reessayer}
                        tentative={tentativeChargement}
                      />
                    </div>
                  )}
                </div>

                {/* **Les résultats par Grand Prix remplacent le calendrier.**
                    La saison Grand Prix par Grand Prix est déjà l'onglet
                    Calendrier de la barre basse, à deux touches d'ici ; ce que
                    personne ne montrait, c'est ce que les autres ont joué. Le
                    libellé nomme sa destination, ce que le wayfinding demande
                    (/apple-design §16), et l'icône change avec lui : un
                    calendrier annoncerait encore des dates. C'est le drapeau
                    de « Ses Grands Prix », au même habillage (`TuileDrapeau`) :
                    les deux cellules ouvrent des Grands Prix.

                    L'écran `Calendrier` reste atteignable par son URL — c'est du
                    code éprouvé, gardé pour le jour où il redevient la bonne
                    réponse (CLAUDE.md §6). */}
                <Link
                  to={`/championnats/${id}/resultats`}
                  className="rounded-carte bg-surface shadow-carte pressable-large min-h-tactile flex items-center gap-3.5 p-4"
                >
                  <TuileDrapeau />
                  <span className="min-w-0 flex-1">
                    <span className="text-corps text-texte block font-medium">
                      Résultats par Grand Prix
                    </span>
                    <span className="text-texte-doux mt-0.5 block text-[12px]">
                      Les paris de chaque membre, course par course
                    </span>
                  </span>
                  <IconeChevronDroit className="text-texte-doux size-4 shrink-0" />
                </Link>
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />

        {erreurDepart && (
          <Alerte ton="erreur" tentative={tentative}>
            {erreurDepart}
          </Alerte>
        )}

        {/* La vue piste passe de la bascule segmentée à un bouton pleine
            largeur, comme demandé. Les deux ensemble auraient offert deux
            chemins vers le même écran, à trois centimètres l'un de l'autre.
            L'écran de piste, lui, ramène ici par son propre bouton de retour :
            l'aller-retour reste symétrique. */}
        {/* Le conteneur flex vit A L'INTERIEUR du `Bloc` : pose sur lui, le
            `gap` serait inerte (`.t-stagger-line` est en `display: block` hors
            de toute couche Tailwind). C'est le cas que le CLAUDE.md signalait
            au « Reste a faire » depuis la version `0.21.1`, ici referme en meme
            temps que celui de l'accueil. */}
        <Bloc rang={2}>
          <div className="flex flex-col gap-2.5">
          {confirmation ? (
            <>
              <Bouton
                variante="principal"
                onClick={quitter}
                occupe={depart}
                libelleOccupe="Départ…"
                icone={<IconeSortie className="size-4" />}
              >
                Confirmer mon départ
              </Bouton>
              <button
                type="button"
                onClick={() => setConfirmation(false)}
                disabled={depart}
                className="text-texte-doux min-h-tactile pressable py-2 text-center text-[13px] font-medium"
              >
                Annuler
              </button>
            </>
          ) : (
            <>
              {/* **L'icône a quitté ce bouton en version `0.48.0`.** Le
                  dessin d'`IconeVoiture` est une cabine et une caisse posées
                  sur deux roues — un camion, pas une monoplace, et un camion
                  ne dit rien d'une vue piste. Le libellé, lui, nomme sa
                  destination, ce que le wayfinding demande ; l'icône ne faisait
                  que décentrer ce libellé pour rien.

                  Le damier reste, à ses 15 % habituels : sur le bordeaux
                  `primaire` il ramène le fond à #7B0F1D, où le blanc tient
                  encore **10,89:1**. Le texte redevient centré, seul dans le
                  bouton. */}
              <Bouton
                variante="principal"
                damier
                onClick={() => naviguer(`/championnats/${id}/piste`)}
              >
                Vue piste
              </Bouton>
              {/* **Quarante-deux pixels séparent les deux boutons**, contre dix
                  auparavant — le `gap-2.5` du conteneur plus ces `mt-8`.

                  Ce n'est pas de la respiration, c'est une garde. Quitter un
                  championnat est **irréversible pour le classement** : les
                  pronostics du membre sont effacés dès qu'il ne lui reste aucune
                  adhésion (règle 4.6), et il ne peut revenir qu'avec le code
                  d'invitation, que lui seul ne possède plus. Le pouce qui vise
                  « Vue piste » ne doit pas pouvoir manquer sa cible et tomber
                  sur celle-là. C'est la « forgiveness » d'/apple-design §16 :
                  l'action destructrice garde sa confirmation en deux temps, et
                  elle gagne la distance qui empêche d'y arriver par accident. */}
              <button
                type="button"
                onClick={() => setConfirmation(true)}
                disabled={!donnees}
                className="text-texte-doux min-h-tactile pressable mt-8 py-2 text-center text-[13px] font-medium disabled:opacity-50"
              >
                Quitter le championnat
              </button>
            </>
          )}
          </div>
        </Bloc>
      </div>
    </Ecran>
  );
}
