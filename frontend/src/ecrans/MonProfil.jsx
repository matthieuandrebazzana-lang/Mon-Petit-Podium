import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import Ecran, { Bloc } from "../composants/Ecran.jsx";
import EnTete from "../composants/EnTete.jsx";
import Bouton from "../composants/Bouton.jsx";
import Alerte from "../composants/Alerte.jsx";
import Voiture, {
  aplatDuNumero,
  encreParDefaut,
} from "../composants/Voiture.jsx";
import Pastille from "../composants/Pastille.jsx";
import GrilleStats from "../composants/GrilleStats.jsx";
import SelecteurCouleur from "../composants/SelecteurCouleur.jsx";
import ZoneChargement from "../composants/ZoneChargement.jsx";
import BlocErreur from "../composants/BlocErreur.jsx";
import { Barre, Carte, Pave } from "../composants/Squelette.jsx";
import SelecteurSkin from "../composants/SelecteurSkin.jsx";
import Repli from "../composants/Repli.jsx";
import SectionAdmin from "../composants/SectionAdmin.jsx";
import RecadragePhoto from "../composants/RecadragePhoto.jsx";
import { IconeAppareilPhoto } from "../composants/Icones.jsx";
import { useAuth } from "../auth/AuthContexte.jsx";
import {
  chargerNumerosPris,
  chargerProfilComplet,
  cleProfil,
  enregistrerAvatar,
  enregistrerVoiture,
  porteurDuNumero,
} from "../lib/profils.js";
import {
  COMPARTIMENT_AVATARS,
  deposerPhoto,
  refusDuFichier,
  supprimerPhoto,
  TYPES_ACCEPTES_ATTRIBUT,
} from "../lib/stockage.js";
import { enFichier } from "../lib/image.js";
import { contraste, teinteMembre } from "../lib/couleurs.js";
import { livreeDuMembre, nomDeLaCouleur } from "../lib/palette.js";
import { oublierCachePrefixe, useDonnees } from "../lib/useDonnees.js";
import { APP_VERSION } from "../config.js";

/**
 * Maquette 14 — mon profil : ma voiture, mes statistiques, ma personnalisation.
 *
 * **Une seule section « Ma livrée », et quatre rangées ordonnées par portée.**
 * Le mode n'est plus choisi dans un contrôle segmenté : il se déduit du skin
 * retenu, `null` valant « ma livrée » — les deux ne peuvent donc plus se
 * contredire. Le choix vit sur le profil (`livree_mode`, `livree_ecurie`), donc
 * il est le même dans tous les championnats du membre, ce que demande la
 * section 5.
 *
 * L'ordre des rangées est **Numéro, Skin, Coque, Ailerons**, et il se lit :
 *
 * | Rangée | Portée |
 * |---|---|
 * | Numéro | s'écrit sur le museau **quelle que soit** la livrée |
 * | Skin | commande les deux suivantes |
 * | Coque · Ailerons | ne peignent que sous « Ma livrée » |
 *
 * **Coque et Ailerons quittent le DOM quand un skin d'écurie est actif** — ni
 * grisés, ni transparents, ni `hidden` : sous une livrée fixe ils ne peignent
 * plus rien, et un réglage sans effet qui reste tabulable est pire qu'un
 * réglage absent. Ils partent par un repli (`composants/Repli.jsx`), sans quoi
 * la carte perdrait quatre-vingt-dix pixels d'un coup et le bouton
 * d'enregistrement sauterait sous le doigt.
 *
 * **La version `0.40.0` les gardait visibles**, au motif qu'un membre ayant
 * essayé un skin devait voir vers quoi il revenait. Ce service est désormais
 * rendu par la case « Ma livrée » du sélecteur, qui montre les deux couleurs en
 * diagonale : la question n'est pas restée sans réponse, elle a changé de
 * propriétaire (`docs/decisions.md` §17).
 *
 * **« Ma livrée » est ce que voit un nouveau joueur**, sans avoir rien à
 * choisir : `livree_mode` vaut `perso` par défaut de colonne (migration 12), et
 * `livreeDuMembre` rend `perso` pour toute ligne qui ne dit pas autre chose.
 * Coque et Ailerons sont donc visibles au premier montage.
 *
 * **Écarts assumés par rapport à la maquette**, tous documentés dans le
 * CLAUDE.md :
 *
 * 1. La rangée « Mes Grands Prix » est retirée. La maquette dessinait une
 *    grille de cartes illustrées par `assets/gp-cards.svg` ; l'écran qu'elle
 *    ouvrait (maquette 13) reste en place et atteignable par son URL, seule
 *    l'entrée depuis le profil disparaît.
 * 2. Les vignettes du sélecteur de skin sont les **pastilles carrées** de
 *    `assets/matti.svg`, pas des voitures : elles n'ont ni roues ni ailerons,
 *    donc aucun endroit où écrire un numéro. La voiture réellement dessinée —
 *    ici l'aperçu, ailleurs la vue piste — reste celle de
 *    `composants/VoituresEcuries.jsx`, seule à porter le pseudo sur son aileron
 *    arrière, qui est le seul identifiant d'un membre sur la piste depuis la
 *    version `0.39.0`.
 */

const NUMERO_MAXIMUM = 99;

/**
 * Le plancher de contraste du numéro sur le museau.
 *
 * **3:1, et il est mesuré, pas choisi** (CLAUDE.md §6). Le numéro est un grand
 * texte porteur de sens : c'est le seuil AA qui le régit, le même que celui
 * d'`encreSurAplat`. En dessous, l'écran le dit — il ne refuse pas, parce que le
 * membre a le droit de peindre sa voiture comme il l'entend et que rien en base
 * ne peut trancher la question sans connaître la livrée active (voir le §2 de la
 * migration 18).
 */
const CONTRASTE_MINIMUM = 3;

/** Ne garde que des chiffres, et jamais plus de deux (numéro de 1 à 99). */
function nettoyerNumero(saisi) {
  return String(saisi ?? "").replace(/\D/g, "").slice(0, 2);
}

/**
 * L'état de saisie tel qu'il découle d'un profil servi.
 *
 * Écrit une seule fois : la remise à zéro après enregistrement et le suivi du
 * profil frais doivent produire exactement le même état, sinon les deux
 * chemins divergent au premier champ ajouté.
 */
function saisieDepuis(profil) {
  const livree = livreeDuMembre(profil);
  return {
    couleur1: livree.couleur1,
    couleur2: livree.couleur2,
    mode: livree.mode,
    // Le dernier slug choisi est conservé même en mode perso : c'est ce que la
    // colonne garde en base, et c'est ce que le membre retrouve s'il rebascule.
    ecurie: profil?.livree_ecurie ?? null,
    numero: profil?.numero == null ? "" : String(profil.numero),
    // **Sans choix en base, la saisie part de l'encre CALCULÉE**, celle que la
    // voiture dessine déjà. Poser `#FFFFFF` par défaut ferait mentir la rangée
    // pour tout profil antérieur à la migration 18 — elle annoncerait « Blanc »
    // pendant que le numéro s'affiche en presque-noir sur une coque claire — et
    // le premier enregistrement aurait alors rendu ce numéro invisible sans que
    // personne n'ait rien demandé.
    couleurTexte:
      profil?.couleur_texte ?? encreParDefaut(livree),
  };
}

function SqueletteProfil() {
  return (
    <div className="flex flex-col gap-3">
      {/* L'en-tête garde son aplat rouge et le bloc de personnalisation sa
          surface blanche : ce sont les formes de l'écran, seul leur contenu est
          encore inconnu. */}
      <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-4 p-5">
        <div className="flex flex-1 items-center gap-3.5">
          {/* 56px, la taille réelle de la pastille depuis qu'elle porte une
              photo : une silhouette qui mentirait de quatorze pixels ferait
              sauter le pseudo à l'arrivée des données. */}
          <div className="size-[56px] shrink-0 rounded-full bg-white/25" />
          <div className="min-w-0 flex-1">
            <div className="h-4 w-28 rounded-full bg-white/25" />
            <div className="mt-2 h-2.5 w-20 rounded-full bg-white/20" />
          </div>
        </div>
        <div className="h-12 w-9 rounded-champ bg-white/15" />
      </div>
      <div className="grid grid-cols-2 gap-2.5">
        {[0, 1, 2, 3].map((rang) => (
          <Carte key={rang} className="rounded-carte-sm h-[68px] p-3.5">
            <Barre largeur="w-14" hauteur="h-2.5" />
            <Barre largeur="w-10" hauteur="h-5" className="mt-2.5" />
          </Carte>
        ))}
      </div>
      {/* La silhouette suit la vraie hauteur du bloc : l'aperçu fait 140px, et
          les quatre rangées 44px chacune — la zone tactile minimale, que
          `min-h-tactile` impose. Elles sont **quatre** et non trois : c'est
          l'état par défaut, « Ma livrée », donc Coque et Ailerons compris. Sans
          elles, l'écran sauterait de deux cents pixels à l'arrivée des
          données. */}
      <Carte className="flex flex-col gap-3">
        <Barre largeur="w-24" hauteur="h-2.5" />
        <Pave className="mx-auto h-[140px] w-[70px]" />
        <Pave className="h-[44px]" />
        <Pave className="h-[44px]" />
        <Pave className="h-[44px]" />
        <Pave className="h-[44px]" />
      </Carte>
    </div>
  );
}

/**
 * Bloc rouge d'en-tête : photo, pseudo, voiture et numéro (maquettes 12 et 14).
 *
 * `voiture` reçoit la ligne complète — profil ou ligne de classement — et
 * `livreeDuMembre` en tire ce qu'il faut peindre. Passer les deux couleurs
 * séparément ferait perdre la livrée d'écurie en chemin.
 *
 * > ### La pastille passe de 42 à 56px, sur les DEUX profils
 * >
 * > `ProfilMembre` rend ce même composant, et c'est ce qui fait tout l'intérêt
 * > des deux écrans : « deux profils qui ne se liraient pas de la même façon ne
 * > se compareraient plus ». La photo qui arrive ici arrive donc aux deux, à la
 * > même taille — et 56px est la taille imposée par le seul des deux qui soit
 * > tactile, la règle iOS des 44 × 44 (CLAUDE.md §3.5) ne laissant pas le choix.
 * > Rendre la mienne plus grande que celle des autres aurait cassé la
 * > comparaison pour un pixel de vanité.
 *
 * **`onPhoto` fait de la pastille un bouton, et c'est le seul écart entre les
 * deux écrans.** Sans lui — le profil d'un autre membre — elle reste un
 * `<span>` : rien n'y est modifiable, et un bouton qui n'agit pas serait un
 * bouton de trop dans l'ordre de tabulation.
 */
export function HeroProfil({
  pseudo,
  voiture,
  numero,
  action,
  avatarUrl,
  onPhoto,
  envoiPhoto = false,
}) {
  const livree = livreeDuMembre(voiture);

  const pastille = (
    <Pastille nom={pseudo} graine={pseudo} taille="xl" photo={avatarUrl} />
  );

  return (
    <div className="rounded-bloc bg-primaire shadow-bloc flex items-center justify-between gap-4 p-5">
      <div className="flex min-w-0 items-center gap-3.5">
        {onPhoto ? (
          <button
            type="button"
            onClick={onPhoto}
            disabled={envoiPhoto}
            /* Le libellé porte l'action ET son état courant : la pastille
               elle-même est `aria-hidden`, c'est donc la seule chose qui soit
               annoncée. « Changer » plutôt que « Ajouter » quand il y a déjà une
               photo — un libellé qui décrit mal ce qui va se passer est pire
               qu'un libellé générique. */
            aria-label={
              avatarUrl ? "Changer ma photo de profil" : "Ajouter une photo de profil"
            }
            className="pressable relative shrink-0 rounded-full"
          >
            <span className={envoiPhoto ? "t-photo-envoi block" : "block"}>
              {pastille}
            </span>
            {/* L'appareil photo dit ce que le rond fait, et il le dit sans
                libellé — c'est le seul endroit de l'écran où une pastille est
                cliquable, et rien d'autre ne l'annoncerait. Blanc sur bordeaux,
                l'icône y tient 10,88:1, très au-dessus des 3:1 qu'un élément
                graphique porteur de sens demande. */}
            <span
              aria-hidden="true"
              className="bg-surface text-primaire shadow-carte absolute -right-0.5 -bottom-0.5 flex size-[22px] items-center justify-center rounded-full"
            >
              <IconeAppareilPhoto className="size-[13px]" />
            </span>
          </button>
        ) : (
          pastille
        )}
        <div className="min-w-0">
          <p className="truncate text-[22px] font-medium text-white">
            {pseudo || "Pilote"}
          </p>
          {action && (
            <p className="mt-0.5 text-[12px] text-white/50">{action}</p>
          )}
        </div>
      </div>

      <div className="flex shrink-0 items-center gap-2.5">
        <Voiture
          {...livree}
          numero={numero ?? ""}
          nom={pseudo}
          titre={`Voiture de ${pseudo || "ce membre"}`}
          className="h-[58px] w-auto"
        />
        {/* Le numéro est la seule graisse 700 autorisée hors de la voiture
            (section 5). Sans numéro choisi, rien ne s'écrit : « #— » serait un
            numéro inventé. */}
        {numero != null && (
          <span className="text-[30px] leading-none font-bold text-white/30">
            #{numero}
          </span>
        )}
      </div>
    </div>
  );
}

export default function MonProfil() {
  const { utilisateur, estAdmin, deconnecter } = useAuth();
  const naviguer = useNavigate();

  const profilId = utilisateur?.id ?? null;

  const cle = profilId ? cleProfil(profilId, profilId) : null;
  const chargeur = useCallback(
    (signal) => chargerProfilComplet(profilId, signal),
    [profilId],
  );
  const { donnees, chargement, echec, recharger, remplacer } = useDonnees(
    cle,
    chargeur,
  );
  const [tentativeChargement, setTentativeChargement] = useState(0);

  function reessayerChargement() {
    setTentativeChargement((n) => n + 1);
    recharger();
  }

  const profil = donnees?.profil ?? null;

  // ---- Saisie ------------------------------------------------------------
  // L'état de saisie **suit le profil servi tant que le membre n'a rien
  // touché**, et se fige dès qu'il touche à quelque chose.
  //
  // Les deux moitiés comptent, et c'est le défaut corrigé ici. Le cache
  // *stale-while-revalidate* affiche d'abord ce qu'il savait : sans le suivi,
  // la réponse fraîche arrivait bien mais la saisie gardait la valeur périmée,
  // et l'ancienne couleur restait à l'écran indéfiniment. Sans le figeage, la
  // revalidation en arrière-plan effacerait une couleur en cours de choix.
  const [saisie, setSaisie] = useState(null);
  const [edite, setEdite] = useState(false);
  const [ouvert, setOuvert] = useState(null);
  const [enregistre, setEnregistre] = useState(false);

  useEffect(() => {
    if (!profil || edite) return;
    setSaisie(saisieDepuis(profil));
  }, [profil, edite]);

  /** Modifie un champ de la saisie et fige le suivi du serveur. */
  const modifier = useCallback((champs) => {
    setEdite(true);
    setEnregistre(false);
    setSaisie((precedente) => ({ ...precedente, ...champs }));
  }, []);

  // ---- Photo de profil ----------------------------------------------------
  // Trois états séparés de ceux de la voiture, et volontairement : les deux
  // enregistrements empruntent la même route (`PATCH /profils/moi`) mais ne
  // partent pas ensemble — la photo part au moment où le fichier est choisi, la
  // voiture au moment où l'on appuie sur « Enregistrer ». Un état commun ferait
  // apparaître le message d'échec de l'un sous le bouton de l'autre.
  const champFichier = useRef(null);
  const [envoiPhoto, setEnvoiPhoto] = useState(false);
  const [echecPhoto, setEchecPhoto] = useState(null);
  const [tentativePhoto, setTentativePhoto] = useState(0);

  /**
   * Périme tout ce qui peint CE membre chez les autres.
   *
   * Sa voiture et sa photo s'affichent aux classements (vue liste et vue piste)
   * et au résumé de chaque Grand Prix. Ces écrans lisent un cache
   * *stale-while-revalidate* : sans effacement, ils garderaient l'ancienne image
   * jusqu'au prochain chargement complet. Tous ses championnats sont concernés —
   * sa voiture et sa photo sont les mêmes partout (section 5) — et l'écran ne
   * les connaît pas, d'où l'effacement par préfixe.
   *
   * **Une seule fonction pour les deux enregistrements.** Écrite deux fois, elle
   * aurait fini par oublier un préfixe d'un côté, et le symptôme — une photo
   * périmée sur un seul des deux écrans — serait resté invisible longtemps.
   */
  const oublierMesApparitions = useCallback(() => {
    oublierCachePrefixe(`classement:${profilId}:`);
    oublierCachePrefixe(`resultats:${profilId}:`);
  }, [profilId]);

  /** Écrit le profil frais partout où l'écran le lit — état, cache, saisie. */
  const adopterProfil = useCallback(
    (frais) => {
      remplacer({ ...donnees, profil: frais });
      oublierMesApparitions();
    },
    [donnees, oublierMesApparitions, remplacer],
  );

  /**
   * Le fichier choisi attend son recadrage — il n'est PAS encore parti.
   *
   * Depuis la version `0.51.0`, choisir un fichier n'envoie plus rien : ça ouvre
   * le recadrage. C'est le seul changement de sens du geste, et il est
   * volontaire — une photo de profil est carrée et découpée en rond, donc une
   * photo prise en portrait perdait auparavant son sujet sans que personne ne
   * puisse rien y faire (`object-fit: cover` centre, il ne compose pas).
   */
  const [aRecadrer, setARecadrer] = useState(null);

  function choisirPhoto(evenement) {
    const fichier = evenement.target.files?.[0];
    // Le champ est vidé tout de suite : sans cela, rechoisir LE MÊME fichier
    // après un refus ne déclencherait aucun `change`, et l'écran resterait muet
    // sur un geste que le joueur vient pourtant de refaire.
    evenement.target.value = "";
    if (!fichier) return;

    setTentativePhoto((n) => n + 1);

    // Le refus local d'abord : cinq mégaoctets montés sur un réseau mobile avant
    // d'être refusés par le compartiment seraient cinq mégaoctets perdus — et
    // surtout, une image que le navigateur ne saura pas décoder n'a rien à faire
    // dans un recadrage qui n'aurait alors rien à montrer.
    const refus = refusDuFichier(fichier);
    if (refus) {
      setEchecPhoto(refus);
      return;
    }

    setEchecPhoto(null);
    setARecadrer(fichier);
  }

  /**
   * Dépose la photo recadrée, puis attache son URL au profil.
   *
   * Elle reçoit un `Blob` sorti du canvas, jamais le fichier de la photothèque :
   * la taille, le format et la qualité ont un propriétaire (`lib/image.js`), et
   * ce n'est pas cet écran.
   */
  async function envoyerPhoto(blob) {
    setARecadrer(null);
    setTentativePhoto((n) => n + 1);
    setEnvoiPhoto(true);
    setEchecPhoto(null);

    const depot = await deposerPhoto({
      compartiment: COMPARTIMENT_AVATARS,
      dossier: profilId,
      base: "avatar",
      fichier: enFichier(blob, "avatar"),
    });

    if (!depot.ok) {
      setEnvoiPhoto(false);
      setEchecPhoto(depot.message);
      return;
    }

    // L'URL n'est enregistrée qu'APRÈS le dépôt réussi : l'inverse laisserait en
    // base l'adresse d'un objet qui n'existe pas, donc une image cassée sur
    // l'écran de tous les membres du championnat.
    const enregistrement = await enregistrerAvatar(depot.donnees);
    setEnvoiPhoto(false);

    if (!enregistrement.ok) {
      setEchecPhoto(enregistrement.message);
      return;
    }

    adopterProfil(enregistrement.donnees);
  }

  async function retirerPhoto() {
    setTentativePhoto((n) => n + 1);
    setEnvoiPhoto(true);
    setEchecPhoto(null);

    // La base d'abord, le stockage ensuite : c'est la colonne qui décide de ce
    // qui s'affiche. Un objet resté en stockage sans être référencé n'est plus
    // visible nulle part ; une colonne qui garderait l'URL d'un objet supprimé
    // afficherait une image cassée partout (`lib/stockage.js`).
    const enregistrement = await enregistrerAvatar(null);

    if (!enregistrement.ok) {
      setEnvoiPhoto(false);
      setEchecPhoto(enregistrement.message);
      return;
    }

    await supprimerPhoto({
      compartiment: COMPARTIMENT_AVATARS,
      dossier: profilId,
      base: "avatar",
    });

    setEnvoiPhoto(false);
    adopterProfil(enregistrement.donnees);
  }

  const [envoi, setEnvoi] = useState(false);
  // Échec de l'ENREGISTREMENT, à ne pas confondre avec celui du chargement
  // rendu par `useDonnees` : l'un est un message de refus métier posé sous le
  // bouton, l'autre remplace l'écran.
  const [echecEnvoi, setEchecEnvoi] = useState(null);
  const [tentative, setTentative] = useState(0);

  // Les numéros déjà pris sont chargés **une seule fois** : la vérification à
  // chaque frappe se fait ensuite en mémoire. Un appel réseau par caractère
  // saisi serait le pire compromis possible pour un avertissement qui ne bloque
  // rien (l'unicité du numéro est indicative, voir la migration).
  const [pris, setPris] = useState([]);
  useEffect(() => {
    if (!profilId) return undefined;
    const controleur = new AbortController();
    let actif = true;

    (async () => {
      try {
        const resultat = await chargerNumerosPris(profilId, controleur.signal);
        if (actif && resultat.ok) setPris(resultat.donnees);
      } catch {
        // L'avertissement est un confort : son échec ne doit rien empêcher.
      }
    })();

    return () => {
      actif = false;
      controleur.abort();
    };
  }, [profilId]);

  // `voiture` est la saisie si elle existe, le profil servi sinon. Ce repli
  // n'est pas théorique : l'effet de synchronisation ne tourne qu'APRÈS le
  // premier rendu, et sans lui la première image afficherait une voiture aux
  // couleurs par défaut et un numéro vide alors que le cache les connaît déjà.
  // Tout ce que l'écran lit passe donc par `voiture`, jamais par `saisie`.
  const voiture = saisie ?? saisieDepuis(profil);
  const numero = voiture.numero;
  const numeroSaisi = numero ? Number(numero) : null;
  // **Une seule question, un seul juge.** « Un skin est-il actif ? » commande
  // désormais trois choses — le message d'explication, la valeur passée au
  // sélecteur, et la présence même de Coque et Ailerons. Trois conditions
  // écrites séparément auraient divergé au premier ajustement. Le slug est
  // exigé avec le mode, comme le fait `livreeDuMembre` : un mode `ecurie` sans
  // livrée ne peint rien.
  const skinActif = voiture.mode === "ecurie" && Boolean(voiture.ecurie);

  const porteur = useMemo(() => porteurDuNumero(pris, numero), [pris, numero]);

  // **Le contraste du numéro se mesure, il ne se choisit pas** (CLAUDE.md §6).
  // L'aplat est celui du museau de la livrée EN COURS DE SAISIE — la coque sous
  // « Ma livrée », la couleur du museau de l'écurie sous un skin — et il vient
  // de `Voiture`, seul propriétaire de cette question. Le couple se recalcule
  // donc quand la couleur du texte change, mais aussi quand la coque ou le skin
  // changent sous elle.
  const contrasteTexte = contraste(voiture.couleurTexte, aplatDuNumero(voiture));

  /**
   * La couleur de texte **telle qu'elle est à l'écran avant toute retouche**.
   *
   * Ce n'est pas `profil.couleur_texte` : celui-ci vaut `null` pour tout compte
   * qui n'a jamais choisi, et la voiture dessine alors l'encre calculée. Comparer
   * la saisie au `null` de la base aurait rendu `modifie` vrai **dès l'arrivée
   * sur l'écran** — le bouton « Enregistrer ma voiture » se serait allumé sans
   * que personne n'ait rien touché.
   *
   * C'est aussi ce qui décide si la couleur part au serveur (voir `enregistrer`).
   */
  const couleurTexteEnBase =
    profil?.couleur_texte ?? encreParDefaut(livreeDuMembre(profil));
  const couleurTexteChoisie = voiture.couleurTexte !== couleurTexteEnBase;

  const modifie =
    Boolean(profil) &&
    (voiture.couleur1 !== profil.couleur1 ||
      voiture.couleur2 !== profil.couleur2 ||
      voiture.mode !== livreeDuMembre(profil).mode ||
      voiture.ecurie !== (profil.livree_ecurie ?? null) ||
      couleurTexteChoisie ||
      (numeroSaisi ?? null) !== (profil.numero ?? null));

  async function enregistrer() {
    setEnvoi(true);
    setEchecEnvoi(null);
    setEnregistre(false);
    setTentative((n) => n + 1);

    const resultat = await enregistrerVoiture({
      couleur1: voiture.couleur1,
      couleur2: voiture.couleur2,
      // **Transmise seulement si elle a été CHOISIE**, et c'est ce qui protège
      // la règle de la migration 18. La saisie porte toujours une couleur — à
      // défaut l'encre calculée — donc l'envoyer inconditionnellement figerait
      // cette encre en base au premier enregistrement, y compris quand le membre
      // n'a fait que repeindre sa coque. Il partirait alors avec un numéro blanc
      // sur une coque devenue blanche, sans avoir rien demandé.
      //
      // Tant qu'elle n'est pas choisie, la colonne reste `NULL` et l'encre
      // continue de suivre l'aplat. C'est aussi ce qui permet à
      // `PATCH /profils/moi` de se passer d'un drapeau de retrait, là où le
      // numéro et la photo en ont besoin.
      ...(couleurTexteChoisie ? { couleur_texte: voiture.couleurTexte } : {}),
      livree_mode: voiture.mode,
      // Le slug n'est transmis que s'il existe : `null` serait refusé par le
      // format en base, et il n'y a rien à écrire tant qu'aucune livrée n'a
      // jamais été choisie.
      ...(voiture.ecurie ? { livree_ecurie: voiture.ecurie } : {}),
      // `retirer_numero` est un drapeau explicite : un `numero: null` serait
      // indiscernable d'un champ non transmis côté backend, et personne ne
      // pourrait plus revenir à l'état sans numéro.
      ...(numeroSaisi ? { numero: numeroSaisi } : { retirer_numero: true }),
    });

    setEnvoi(false);

    if (!resultat.ok) {
      setEchecEnvoi(resultat.message);
      return;
    }

    setEnregistre(true);

    // **`adopterProfil` et non `setDonnees` : le cache doit suivre.**
    // `setDonnees` ne touche que l'état React ; le cache `localStorage` gardait
    // alors la version d'avant, et c'est lui qui est relu au montage suivant.
    // C'est précisément ce qui faisait réapparaître l'ancienne couleur en
    // revenant sur le profil. Il périme au passage tout ce qui peint ce membre
    // ailleurs — c'est le même besoin que pour la photo, donc la même fonction.
    adopterProfil(resultat.donnees);

    // Le profil rendu par la route fait foi : il porte les valeurs normalisées
    // par le backend (couleurs en majuscules), pas celles de la saisie. La
    // saisie repart de lui, et redevient suiveuse du serveur.
    setSaisie(saisieDepuis(resultat.donnees));
    setEdite(false);
  }

  async function seDeconnecter() {
    const resultat = await deconnecter();
    if (resultat.ok) naviguer("/", { replace: true });
  }

  if (echec && !donnees) {
    return (
      <Ecran direction="avant">
        <Bloc rang={1}>
          <EnTete titre="Mon profil" retourVers="/accueil" />
        </Bloc>
        <Bloc rang={2}>
          <BlocErreur
            echec={echec}
            onReessayer={reessayerChargement}
            tentative={tentativeChargement}
          />
        </Bloc>
      </Ecran>
    );
  }

  return (
    <Ecran direction="avant">
      {/* Le recadrage est un portail vers `document.body` : monté ici dans le
          JSX pour que sa place dans le code dise à quel geste il appartient,
          rendu ailleurs pour échapper au `transform` d'`Ecran`. */}
      {aRecadrer && (
        <RecadragePhoto
          fichier={aRecadrer}
          forme="cercle"
          titre="Ta photo de profil"
          occupe={envoiPhoto}
          onConfirmer={envoyerPhoto}
          onAnnuler={() => setARecadrer(null)}
        />
      )}

      <Bloc rang={1}>
        <EnTete titre="Mon profil" retourVers="/accueil" />
      </Bloc>

      <div className="flex flex-1 flex-col gap-3">
        <Bloc rang={2}>
          <ZoneChargement
            chargement={chargement && !donnees}
            squelette={<SqueletteProfil />}
          >
            {profil && (
              <div className="flex flex-col gap-3">
                {/* Le sélecteur de fichier natif, invisible mais dans le DOM :
                    c'est la pastille du bloc rouge qui l'ouvre. `hidden` et non
                    `display:none` sur un parent — un `<input type="file">`
                    réellement retiré du rendu ne s'ouvre plus sur iOS.

                    Il n'a **ni `capture` ni `multiple`** : `capture` forcerait
                    l'appareil photo et retirerait l'accès à la photothèque, qui
                    est d'où viennent presque toutes les photos de profil ; une
                    sélection multiple n'aurait aucun sens pour une image qui en
                    remplace une autre. */}
                <input
                  ref={champFichier}
                  type="file"
                  accept={TYPES_ACCEPTES_ATTRIBUT}
                  onChange={choisirPhoto}
                  className="hidden"
                  tabIndex={-1}
                  aria-hidden="true"
                />

                <HeroProfil
                  pseudo={profil.pseudo}
                  voiture={{
                    couleur1: voiture.couleur1,
                    couleur2: voiture.couleur2,
                    livree_mode: voiture.mode,
                    livree_ecurie: voiture.ecurie,
                  }}
                  numero={numeroSaisi}
                  action="Saison 2026"
                  avatarUrl={profil.avatar_url}
                  onPhoto={() => champFichier.current?.click()}
                  envoiPhoto={envoiPhoto}
                />

                {/* Ce que la photo a besoin de dire, et rien de plus. Le refus
                    d'un fichier est un message posé sous le bloc qu'il concerne,
                    jamais une alerte qui remplacerait l'écran — la photo est un
                    enrichissement, son échec ne doit rien emporter.

                    Le retrait n'existe **que quand il y a quelque chose à
                    retirer** : un bouton « Supprimer la photo » toujours présent
                    laisserait croire qu'il en existe une. Il est écrit en marron
                    `secondaire` et non en `texte-doux`, qui ne vaut que 2,0:1
                    sur le beige — c'est une phrase qu'on vient lire, et de plus
                    une action qui efface. */}
                {echecPhoto && (
                  <Alerte ton="erreur" tentative={tentativePhoto}>
                    {echecPhoto}
                  </Alerte>
                )}

                {profil.avatar_url && (
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
                )}

                <GrilleStats stats={donnees?.stats} />

                <div className="rounded-carte bg-surface shadow-carte p-4">
                  <p className="text-label text-texte-doux mb-3 uppercase">
                    Ma livrée
                  </p>

                  {/* L'aperçu est au-dessus des réglages et centré : c'est le
                      sujet de l'écran, et il reste sous les yeux pendant qu'on
                      règle les couleurs comme pendant qu'on essaie un skin. */}
                  <Voiture
                    mode={voiture.mode}
                    ecurie={voiture.ecurie}
                    couleur1={voiture.couleur1}
                    couleur2={voiture.couleur2}
                    couleurTexte={voiture.couleurTexte}
                    numero={numeroSaisi ?? ""}
                    nom={profil.pseudo}
                    /* Le cockpit porte la photo du membre, comme sur la vue
                       piste — même mécanique, même `clipPath`, même repli sur
                       l'initiale posée sur la teinte de sa pastille. C'est le
                       seul écran où l'on règle sa voiture : il n'y avait aucune
                       raison qu'il soit le seul à la montrer sans son pilote.
                       La teinte vient de la même graine qu'ailleurs (`profilId`,
                       à défaut le pseudo), donc le rond est exactement celui du
                       classement. */
                    photo={profil.avatar_url}
                    teintePilote={
                      teinteMembre(profilId || profil.pseudo).hex
                    }
                    titre="Aperçu de ta voiture"
                    className="mx-auto h-[140px] w-auto"
                  />

                  {/* **L'ordre suit la portée de chaque réglage.** Le numéro
                      s'écrit sur le museau quelle que soit la livrée : il est
                      donc au-dessus, hors de tout ce que le skin commande.
                      Vient le skin, puis — seulement s'il vaut « Ma livrée » —
                      les deux couleurs qu'il commande. Un contrôle est posé
                      juste au-dessus de ce qu'il modifie ; posé en dessous, il
                      faudrait un libellé pour dire ce qu'il gouverne. */}
                  <div className="mt-1.5 flex min-h-tactile items-center justify-between gap-3 py-1.5">
                    <label
                      htmlFor="numero-voiture"
                      className="text-corps-sm text-texte-doux"
                    >
                      Numéro
                    </label>
                    <div className="rounded-champ bg-fond flex items-center">
                      <span
                        aria-hidden="true"
                        className="text-texte-doux pl-3 text-[15px]"
                      >
                        #
                      </span>
                      <input
                        id="numero-voiture"
                        // `inputMode` plutôt que `type="number"` : sur iOS le
                        // second ouvre un clavier à flèches, accepte les signes
                        // et le « e », et affiche des incrémenteurs dont
                        // personne n'a besoin pour deux chiffres.
                        inputMode="numeric"
                        autoComplete="off"
                        maxLength={2}
                        placeholder="—"
                        value={numero}
                        onChange={(evenement) =>
                          modifier({
                            numero: nettoyerNumero(evenement.target.value),
                          })
                        }
                        className="text-texte w-[46px] bg-transparent py-2 pr-3 pl-0.5 text-[15px] font-medium outline-none"
                      />
                    </div>
                  </div>

                  {/* Le skin n'est pas un second mode : `null` vaut « ma
                      livrée », et c'est la valeur d'un nouveau joueur — celle du
                      défaut de colonne (`livree_mode` vaut `perso`) comme celle
                      que rend `livreeDuMembre` quand il ne trouve rien. `mode`
                      s'en déduit, il n'est plus choisi à la main, donc les deux
                      ne peuvent plus se contredire. */}
                  <SelecteurSkin
                    valeur={skinActif ? voiture.ecurie : null}
                    couleur1={voiture.couleur1}
                    couleur2={voiture.couleur2}
                    ouvert={ouvert === 3}
                    onOuvrir={() => setOuvert(ouvert === 3 ? null : 3)}
                    onChange={(slug) => {
                      modifier(
                        slug
                          ? { mode: "ecurie", ecurie: slug }
                          : { mode: "perso" },
                      );
                      setOuvert(null);
                    }}
                  />

                  {/* **Coque et Ailerons quittent le DOM sous un skin d'écurie**,
                      ils ne sont ni grisés ni transparents : sous une livrée
                      fixe ils ne peignent plus rien, et un réglage sans effet
                      qui reste tabulable et lisible au lecteur d'écran est pire
                      qu'un réglage absent.

                      Ce qu'ils rendaient — voir vers quoi on revient — est
                      repris par la case « Ma livrée » du sélecteur ci-dessus,
                      qui montre les deux couleurs en diagonale. La question
                      n'est donc pas restée sans réponse, elle a changé de
                      propriétaire.

                      Le repli sert le retour autant que le départ : les deux
                      rangées reviennent en poussant le bouton d'enregistrement
                      vers le bas au lieu de le faire apparaître dessous. */}
                  <Repli visible={!skinActif}>
                    <SelecteurCouleur
                      libelle="Coque"
                      valeur={voiture.couleur1}
                      interdite={voiture.couleur2}
                      ouvert={ouvert === 1}
                      onOuvrir={() => setOuvert(ouvert === 1 ? null : 1)}
                      onChange={(hex) => {
                        modifier({ couleur1: hex });
                        setOuvert(null);
                      }}
                    />
                    <SelecteurCouleur
                      libelle="Ailerons"
                      valeur={voiture.couleur2}
                      interdite={voiture.couleur1}
                      ouvert={ouvert === 2}
                      onOuvrir={() => setOuvert(ouvert === 2 ? null : 2)}
                      onChange={(hex) => {
                        modifier({ couleur2: hex });
                        setOuvert(null);
                      }}
                    />
                  </Repli>

                  {/* **La couleur du texte est HORS du repli, et c'est la même
                      règle d'ordre que le numéro.** Elle peint le numéro et le
                      pseudo, qui s'écrivent sur la voiture quelle que soit la
                      livrée : un réglage qui survit au skin n'a rien à faire
                      dans la région que le skin escamote. Elle est posée sous
                      Coque et Ailerons parce qu'elle est la seule des trois qui
                      concerne l'encre et non la carrosserie, et parce qu'elle
                      dépend d'elles — c'est sur leur aplat que son contraste se
                      mesure.

                      Aucune couleur interdite : `interdite` sert à empêcher une
                      voiture monochrome, or le texte est POSÉ SUR la coque, il
                      n'est pas une seconde surface. Un texte de la couleur des
                      ailerons sur une coque foncée est parfaitement lisible. */}
                  <SelecteurCouleur
                    libelle="Couleur du texte"
                    valeur={voiture.couleurTexte}
                    ouvert={ouvert === 4}
                    onOuvrir={() => setOuvert(ouvert === 4 ? null : 4)}
                    onChange={(hex) => {
                      modifier({ couleurTexte: hex });
                      setOuvert(null);
                    }}
                  />

                  {/* **On mesure, on signale, on ne bloque pas.** Le plancher
                      est celui d'un grand texte porteur de sens (3:1), le même
                      qui décide déjà des encres d'aplat. En dessous, le numéro
                      cesse d'identifier la voiture — ce qui est la seule chose
                      qu'il ait à faire sur une piste où seize voitures tiennent
                      dans un écran.

                      L'avertissement ne grise ni ne refuse rien : la voiture
                      appartient au membre, et l'écran de profil est le seul
                      endroit où il la voit en grand avant de l'enregistrer. Même
                      arbitrage que l'avertissement de numéro déjà porté. */}
                  {contrasteTexte < CONTRASTE_MINIMUM && (
                    <p className="text-corps-sm text-secondaire mt-3">
                      {nomDeLaCouleur(voiture.couleurTexte)} ne se détache pas
                      assez de l'aplat sous le numéro
                      {" ("}
                      {contrasteTexte.toFixed(1).replace(".", ",")}:1 pour un
                      minimum de {CONTRASTE_MINIMUM}:1). Ton numéro sera
                      difficile à lire sur la piste.
                    </p>
                  )}

                  {/* La phrase prend la place que les deux rangées viennent de
                      libérer, et c'est elle qui dit où elles sont parties. Le
                      marron `secondaire` et non `texte-doux` : 9,4:1 sur blanc
                      contre 2,0:1, et c'est une phrase qu'on vient lire. */}
                  {skinActif && (
                    <p className="text-corps-sm text-secondaire mt-2">
                      Le skin remplace ta livrée sur la piste et dans les
                      classements. Choisis « Ma livrée » pour retrouver la coque
                      et les ailerons.
                    </p>
                  )}

                  {/* L'avertissement ne bloque jamais l'enregistrement :
                      l'unicité du numéro est indicative, et deux membres qui
                      tiennent au 44 doivent pouvoir le garder. */}
                  {porteur && (
                    <p className="text-corps-sm text-secondaire mt-3">
                      Le {numeroSaisi} est déjà porté par {porteur} dans un de tes
                      championnats. Tu peux quand même le garder.
                    </p>
                  )}

                  {numero === "0" && (
                    <p className="text-corps-sm text-secondaire mt-3">
                      Le numéro va de 1 à {NUMERO_MAXIMUM}. Laisse le champ vide
                      pour ne pas en porter.
                    </p>
                  )}

                  {echecEnvoi && (
                    <div className="mt-3">
                      <Alerte ton="erreur" tentative={tentative}>
                        {echecEnvoi}
                      </Alerte>
                    </div>
                  )}

                  <div className="mt-3.5">
                    <Bouton
                      variante="principal"
                      onClick={enregistrer}
                      occupe={envoi}
                      libelleOccupe="Enregistrement…"
                      disabled={!modifie && !echecEnvoi}
                    >
                      {enregistre && !modifie
                        ? "Voiture enregistrée"
                        : "Enregistrer ma voiture"}
                    </Bouton>
                  </div>
                </div>

                {/* La section n'existe que pour un administrateur. Elle est
                    posée en dernier, sous la personnalisation : c'est un outil
                    d'exploitation, pas une partie du profil, et il n'a aucune
                    raison de passer devant la voiture ni devant les
                    statistiques.

                    **C'est le seul endroit de l'app qui lise `estAdmin` et non
                    `modeAdmin`, et ce n'est pas un oubli** : la section porte
                    l'interrupteur, elle doit donc rester visible interrupteur
                    éteint — sinon il n'y aurait plus rien pour le rallumer, et
                    il faudrait se déconnecter pour sortir du mode membre.
                    Toute AUTRE surface d'administration se conditionne à
                    `modeAdmin`. */}
                {estAdmin && <SectionAdmin />}
              </div>
            )}
          </ZoneChargement>
        </Bloc>

        <div className="min-h-3 flex-1" />
      </div>

      <footer className="flex flex-col items-center gap-3 pt-5">
        <button
          type="button"
          onClick={seDeconnecter}
          className="text-texte-doux min-h-tactile pressable -my-2 px-3 py-2 text-[13px] font-medium"
        >
          Se déconnecter
        </button>
        <span className="text-label-sm text-texte-doux uppercase">
          Version {APP_VERSION}
        </span>
      </footer>
    </Ecran>
  );
}
