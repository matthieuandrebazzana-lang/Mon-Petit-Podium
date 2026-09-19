import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import Bouton from "./Bouton.jsx";
import { IconeCroix } from "./Icones.jsx";
import { dureeCss } from "../lib/secousse.js";
import {
  bornerDecalage,
  chargerImage,
  chargerImageDepuisUrl,
  echelleMinimale,
  ErreurImage,
  recadrerImage,
} from "../lib/image.js";

/**
 * Recadrage d'une photo avant son envoi — glisser pour placer, pincer pour zoomer.
 *
 * **Un seul composant pour les deux formes.** Le profil découpe un rond, le
 * championnat un carré arrondi : c'est la même question — « quel carré de cette
 * image garde-t-on ? » — posée deux fois. Seul le masque diffère, et il ne change
 * rien au calcul : **le cadre est carré dans les deux cas**, le rond n'étant
 * qu'un masque posé dessus. Deux composants auraient divergé au premier
 * ajustement de geste, et celui qu'on aurait oublié de corriger serait devenu le
 * mauvais.
 *
 * > ### Pourquoi un portail, et pas un bloc dans l'écran
 * >
 * > `Ecran` porte un `transform` en permanence. Un `position: fixed` posé à
 * > l'intérieur se positionnerait par rapport à lui **au lieu de la fenêtre**, et
 * > le recadrage défilerait avec la page. C'est le piège déjà documenté pour
 * > `NavBarre` et `BandeauPrevisualisation` (`docs/composants.md` §2), et il vaut
 * > même pour un `translateX(0)`. La surface est donc montée dans `document.body`.
 *
 * > ### Pourquoi le canvas, et pas une `<img>` transformée en CSS
 * >
 * > Une image posée en CSS suivrait le doigt sur le compositeur, ce qui serait
 * > plus économe. Mais il faudrait alors **deux** géométries : celle qui affiche
 * > et celle qui découpe, tenues d'accord à la main. Le canvas dessine
 * > exactement ce que l'export découpera — `carreVisible` sert les deux — et
 * > l'écart entre l'aperçu et le résultat devient structurellement impossible.
 * > Le coût est un `drawImage` par image d'animation, sur une surface de la
 * > taille de l'écran : c'est une seule copie de bitmap, accélérée par le GPU sur
 * > Safari iOS.
 *
 * **Le dessin est réclamé par `requestAnimationFrame`, jamais fait dans le
 * gestionnaire de pointeur.** Safari émet plusieurs `pointermove` par image sur
 * un écran à 120 Hz ; dessiner à chacun ferait deux à trois copies pour un seul
 * affichage.
 *
 * > ### La source est un FICHIER ou une URL, et le composant n'en sait rien
 * >
 * > Depuis la version `0.75.0`, une photo de championnat déjà déposée se
 * > **re-recadre** sans repasser par la photothèque : le recadrage s'ouvre alors
 * > sur l'image en place, qui est son point de départ naturel. Tout ce qui suit
 * > le décodage est identique — le cadre, les gestes, l'export — parce que la
 * > seule chose qui change est *d'où vient le pixel*. C'est `lib/image.js` qui
 * > porte les deux décodages et la question du CORS que le second pose ; ici, on
 * > choisit une fonction, et rien de plus.
 *
 * @param {File|string} source   le fichier choisi, ou l'URL d'une photo déposée
 * @param {"cercle"|"carre"} forme le masque, et lui seul
 * @param {string}   titre        ce que le joueur est en train de faire
 * @param {boolean}  occupe       un envoi est déjà parti — verrouille « Confirmer »
 * @param {(blob: Blob) => void} onConfirmer  reçoit le JPEG recadré
 * @param {() => void}           onAnnuler    referme sans rien envoyer
 * @param {(() => void)|null}    onChoisirAutre ouvre la photothèque, si l'appelant
 *   en offre la possibilité — il n'y a rien à remplacer quand la source EST le
 *   fichier qu'on vient de choisir
 */
export default function RecadragePhoto({
  source,
  forme = "cercle",
  titre = "Recadrer la photo",
  occupe = false,
  onConfirmer,
  onAnnuler,
  onChoisirAutre = null,
}) {
  const scene = useRef(null);
  const canvas = useRef(null);
  const image = useRef(null);
  const trame = useRef(0);
  // La vue vit dans une référence et non dans un état : elle change à chaque
  // `pointermove`, et un rendu React par image de geste ferait retomber le
  // déplacement sous les 60 images par seconde sur un iPhone. Le seul
  // consommateur est le dessin, qui la lit dans la boucle d'animation.
  const vue = useRef({ echelle: 1, decalageX: 0, decalageY: 0, cote: 0 });
  // Taille CSS de la scène et rapport de pixels retenu, écrits par `mesurer` et
  // lus par `dessiner`.
  const mesures = useRef({ largeur: 0, hauteur: 0, dpr: 1 });
  const pointeurs = useRef(new Map());
  const pince = useRef(null);
  const minuterie = useRef(0);

  const [pret, setPret] = useState(false);
  const [echec, setEchec] = useState(null);
  const [travail, setTravail] = useState(false);
  // La surface monte FERMÉE puis s'ouvre à l'image suivante : ouvrir dès le
  // premier rendu ne transitionnerait pas, le navigateur n'ayant jamais peint
  // l'état de départ. Même mécanique que `Repli` (`docs/composants.md` §5).
  const [ouvert, setOuvert] = useState(false);

  useEffect(() => {
    const trameOuverture = requestAnimationFrame(() => setOuvert(true));
    return () => cancelAnimationFrame(trameOuverture);
  }, []);

  /**
   * Referme la surface, PUIS rend la main.
   *
   * La sortie emprunte le chemin de l'entrée — c'est ce qui fait qu'un
   * recadrage abandonné se lit comme un retour et non comme une disparition. Le
   * délai est lu dans la feuille compilée, jamais recopié en constante : une
   * constante JavaScript et un jeton CSS divergent au premier ajustement, et le
   * symptôme serait discret (une surface retirée une image trop tôt, donc une
   * fermeture qui se termine par un saut).
   */
  const fermer = useCallback((action) => {
    setOuvert(false);
    minuterie.current = setTimeout(action, dureeCss("--duration-quick", 150));
  }, []);

  // La minuterie de fermeture est annulée au démontage : elle rendrait la main à
  // un écran qui n'est plus là si le joueur quitte la page pendant les cent
  // cinquante millisecondes de sortie.
  useEffect(() => () => clearTimeout(minuterie.current), []);

  // --------------------------------------------------------------------- //
  //  Dessin
  // --------------------------------------------------------------------- //

  const dessiner = useCallback(() => {
    trame.current = 0;
    const surface = canvas.current;
    // `pixels` et non `source` : la prop du même nom désigne l'ORIGINE de
    // l'image (un fichier ou une URL), celle-ci l'image déjà décodée.
    const pixels = image.current;
    if (!surface || !pixels) return;

    const contexte = surface.getContext("2d");
    if (!contexte) return;

    const { largeur, hauteur, dpr } = mesures.current;
    if (!largeur || !hauteur) return;

    const { echelle, decalageX, decalageY, cote } = vue.current;
    contexte.setTransform(dpr, 0, 0, dpr, 0, 0);
    contexte.clearRect(0, 0, largeur, hauteur);

    const affichee = {
      largeur: pixels.naturalWidth * echelle,
      hauteur: pixels.naturalHeight * echelle,
    };
    const gauche = largeur / 2 + decalageX - affichee.largeur / 2;
    const haut = hauteur / 2 + decalageY - affichee.hauteur / 2;

    // Ce qui sera COUPÉ reste visible, en sourdine. Un cadre posé sur du noir
    // demanderait au joueur de deviner ce qu'il écarte ; en le montrant, le
    // geste de placement devient un geste de composition. L'opacité est basse
    // pour que la frontière du masque reste franche.
    contexte.globalAlpha = 0.28;
    contexte.drawImage(pixels, gauche, haut, affichee.largeur, affichee.hauteur);
    contexte.globalAlpha = 1;

    // Puis le même dessin, à pleine lumière, découpé par le masque final.
    contexte.save();
    contexte.beginPath();
    tracerMasque(contexte, {
      x: (largeur - cote) / 2,
      y: (hauteur - cote) / 2,
      cote,
      forme,
    });
    contexte.clip();
    contexte.drawImage(pixels, gauche, haut, affichee.largeur, affichee.hauteur);
    contexte.restore();
  }, [forme]);

  const redessiner = useCallback(() => {
    if (trame.current) return;
    trame.current = requestAnimationFrame(dessiner);
  }, [dessiner]);

  /** Applique les bornes de couverture, puis demande une image. */
  const recadrer = useCallback(
    (suivante) => {
      const pixels = image.current;
      if (!pixels) return;

      const { cote } = vue.current;
      const minimale = echelleMinimale(
        pixels.naturalWidth,
        pixels.naturalHeight,
        cote,
      );
      const echelle = Math.min(
        minimale * ZOOM_MAXIMUM,
        Math.max(minimale, suivante.echelle),
      );

      vue.current = {
        cote,
        echelle,
        decalageX: bornerDecalage(
          suivante.decalageX,
          pixels.naturalWidth * echelle - cote,
        ),
        decalageY: bornerDecalage(
          suivante.decalageY,
          pixels.naturalHeight * echelle - cote,
        ),
      };
      redessiner();
    },
    [redessiner],
  );

  // --------------------------------------------------------------------- //
  //  Mesure de la scène — la seule chose qui dépende de la taille de l'écran
  // --------------------------------------------------------------------- //

  const mesurer = useCallback(() => {
    const boite = scene.current;
    const surface = canvas.current;
    if (!boite || !surface) return;

    // **`clientWidth` et non `getBoundingClientRect`**, et ce n'est pas
    // interchangeable ici : la surface monte sous un `transform: scale(0.96)`
    // le temps de son ouverture, et une boîte mesurée à travers un `transform`
    // rend la taille RENDUE, pas la taille de disposition. Le canvas aurait
    // alors une réserve de pixels 4 % trop petite, étirée pour tenir — donc une
    // image légèrement floue — et le côté du cadre serait faux de la même
    // fraction, ce qui décalerait la découpe exportée.
    const largeur = boite.clientWidth;
    const hauteur = boite.clientHeight;
    if (!largeur || !hauteur) return;

    // Le rapport de pixels est plafonné à 2. Les iPhone récents rendent à 3 :
    // une surface de la taille de l'écran y coûterait deux fois plus de pixels à
    // recopier par image de geste, pour un aperçu que personne ne compare à
    // l'original.
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    surface.width = Math.round(largeur * dpr);
    surface.height = Math.round(hauteur * dpr);
    mesures.current = { largeur, hauteur, dpr };

    // Le cadre occupe la scène en laissant respirer ses bords, et reste carré.
    const cote = Math.round(Math.min(largeur, hauteur) - MARGE_CADRE * 2);
    const ancienne = vue.current.cote;
    vue.current.cote = Math.max(64, cote);
    // Le liseré du cadre est peint en CSS et lit ce côté. La variable ne change
    // qu'à la mesure — jamais pendant un geste —, donc le recalcul de style
    // qu'elle déclenche chez ses enfants ne coûte rien ici.
    boite.style.setProperty("--recadrage-cote", `${vue.current.cote}px`);

    // Une rotation d'écran ne doit pas rejeter le cadrage : l'échelle et le
    // décalage suivent proportionnellement le changement de côté. Sans cela, un
    // passage en paysage reviendrait au cadrage initial, effaçant le geste.
    if (ancienne > 0) {
      const facteur = vue.current.cote / ancienne;
      recadrer({
        echelle: vue.current.echelle * facteur,
        decalageX: vue.current.decalageX * facteur,
        decalageY: vue.current.decalageY * facteur,
      });
    }
  }, [recadrer]);

  // --------------------------------------------------------------------- //
  //  Chargement du fichier
  // --------------------------------------------------------------------- //

  useEffect(() => {
    let vivant = true;
    setPret(false);
    setEchec(null);

    // Une chaîne est une URL déjà déposée, tout le reste est un fichier de la
    // photothèque. Le test porte sur le TYPE et non sur un drapeau que
    // l'appelant passerait à côté : deux sources et un booléen finissent
    // toujours par se contredire.
    const decodage =
      typeof source === "string" ? chargerImageDepuisUrl(source) : chargerImage(source);

    decodage
      .then((chargee) => {
        if (!vivant) return;
        image.current = chargee;
        mesurer();
        // Cadrage d'arrivée : l'image remplit tout juste le cadre, centrée.
        // C'est le cadrage que le joueur attend d'une photo qu'il vient de
        // choisir, et il est déjà valide — il n'y a rien à corriger pour
        // confirmer tout de suite.
        recadrer({
          echelle: echelleMinimale(
            chargee.naturalWidth,
            chargee.naturalHeight,
            vue.current.cote,
          ),
          decalageX: 0,
          decalageY: 0,
        });
        setPret(true);
      })
      .catch((erreur) => {
        if (!vivant) return;
        setEchec(
          erreur instanceof ErreurImage
            ? erreur.message
            : "Cette image n'a pas pu être ouverte. Choisis-en une autre.",
        );
      });

    return () => {
      vivant = false;
      image.current = null;
    };
  }, [source, mesurer, recadrer]);

  useEffect(() => {
    window.addEventListener("resize", mesurer);
    window.addEventListener("orientationchange", mesurer);
    return () => {
      window.removeEventListener("resize", mesurer);
      window.removeEventListener("orientationchange", mesurer);
      if (trame.current) cancelAnimationFrame(trame.current);
    };
  }, [mesurer]);

  // --------------------------------------------------------------------- //
  //  Gestes
  // --------------------------------------------------------------------- //

  // Safari iOS garde SES propres gestes de zoom (`gesturestart`) en plus des
  // événements de pointeur, et deux doigts sur la scène feraient alors zoomer la
  // page entière sous le recadrage. `touch-action: none` ne les couvre pas :
  // ils se refusent explicitement, et par un écouteur natif — React ne connaît
  // pas ces trois noms d'événements.
  useEffect(() => {
    const boite = scene.current;
    if (!boite) return;
    const refuser = (evenement) => evenement.preventDefault();
    const noms = ["gesturestart", "gesturechange", "gestureend"];
    noms.forEach((nom) => boite.addEventListener(nom, refuser));
    return () => noms.forEach((nom) => boite.removeEventListener(nom, refuser));
  }, []);

  function auPointeurBas(evenement) {
    if (!pret || pointeurs.current.size >= 2) return;
    evenement.currentTarget.setPointerCapture(evenement.pointerId);
    pointeurs.current.set(evenement.pointerId, {
      x: evenement.clientX,
      y: evenement.clientY,
    });
    if (pointeurs.current.size === 2) demarrerPince();
  }

  function demarrerPince() {
    const [un, deux] = [...pointeurs.current.values()];
    // La boîte de la scène est mesurée UNE FOIS, à la prise : la relire à
    // chaque `pointermove` forcerait un calcul de disposition par image de
    // geste, et elle ne bouge pas pendant un pincement.
    const boite = scene.current.getBoundingClientRect();
    pince.current = {
      ecart: Math.hypot(deux.x - un.x, deux.y - un.y) || 1,
      ancre: {
        x: (un.x + deux.x) / 2 - (boite.left + boite.width / 2),
        y: (un.y + deux.y) / 2 - (boite.top + boite.height / 2),
      },
      depart: { ...vue.current },
    };
  }

  function auPointeurDeplace(evenement) {
    const precedent = pointeurs.current.get(evenement.pointerId);
    if (!precedent) return;

    const courant = { x: evenement.clientX, y: evenement.clientY };
    pointeurs.current.set(evenement.pointerId, courant);

    if (pointeurs.current.size === 1) {
      // Un doigt : suivi 1:1. Le décalage s'ajoute à celui qu'on avait, ce qui
      // respecte l'endroit où le doigt a saisi l'image — la ramener sous le
      // doigt casserait l'illusion dès la première prise.
      recadrer({
        echelle: vue.current.echelle,
        decalageX: vue.current.decalageX + (courant.x - precedent.x),
        decalageY: vue.current.decalageY + (courant.y - precedent.y),
      });
      return;
    }

    if (pointeurs.current.size === 2 && pince.current) {
      const [un, deux] = [...pointeurs.current.values()];
      const ecart = Math.hypot(deux.x - un.x, deux.y - un.y) || 1;
      const facteur = ecart / pince.current.ecart;
      const depart = pince.current.depart;

      // **Le zoom est ancré sur le milieu des deux doigts, pas sur le centre du
      // cadre.** Ancré au centre, l'image glisserait sous les doigts dès que le
      // milieu de la pince n'y est pas — c'est le défaut qui fait qu'un zoom
      // « ne suit pas ». Le point de l'image sous le milieu doit rester sous le
      // milieu : son décalage au centre est donc multiplié par le facteur.
      const ancre = pince.current.ancre;

      recadrer({
        echelle: depart.echelle * facteur,
        decalageX: ancre.x + (depart.decalageX - ancre.x) * facteur,
        decalageY: ancre.y + (depart.decalageY - ancre.y) * facteur,
      });
    }
  }

  function auPointeurHaut(evenement) {
    pointeurs.current.delete(evenement.pointerId);
    // Le doigt restant reprend la main sur un déplacement simple, sans saut :
    // sa position vient d'être réécrite à chaque `pointermove`, donc le prochain
    // delta part de là où il est vraiment. Sans cette remise à zéro de la pince,
    // l'image bondirait au relâchement du second doigt.
    pince.current = null;
    if (pointeurs.current.size === 1) return;
    pointeurs.current.clear();
  }

  // --------------------------------------------------------------------- //
  //  Sortie
  // --------------------------------------------------------------------- //

  async function confirmer() {
    if (!pret || !image.current || travail) return;
    setTravail(true);
    setEchec(null);
    try {
      const blob = await recadrerImage(image.current, vue.current);
      fermer(() => onConfirmer(blob));
    } catch (erreur) {
      setTravail(false);
      setEchec(
        erreur instanceof ErreurImage
          ? erreur.message
          : "Cette image n'a pas pu être préparée. Réessaie dans quelques instants.",
      );
    }
  }

  // Échap referme, comme toute surface modale. Le clavier est rare sur la cible
  // iOS, mais un recadrage ouvert sans issue au clavier serait un cul-de-sac.
  useEffect(() => {
    const auClavier = (evenement) => {
      if (evenement.key === "Escape" && !occupe && !travail) fermer(onAnnuler);
    };
    window.addEventListener("keydown", auClavier);
    return () => window.removeEventListener("keydown", auClavier);
  }, [occupe, travail, onAnnuler, fermer]);

  // Le défilement du document est suspendu pendant le recadrage : sans cela, un
  // geste qui déborde de la scène ferait défiler l'écran de profil DERRIÈRE la
  // surface, et le retour laisserait la page ailleurs qu'où on l'avait quittée.
  useEffect(() => {
    const precedent = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = precedent;
    };
  }, []);

  const verrouille = occupe || travail;
  const annuler = () => fermer(onAnnuler);

  return createPortal(
    <div
      className="t-recadrage fixed inset-0 z-50 flex flex-col"
      data-ouvert={ouvert ? "true" : "false"}
      role="dialog"
      aria-modal="true"
      aria-label={titre}
    >
      <span aria-hidden="true" className="t-recadrage-voile absolute inset-0" />

      <header className="relative flex shrink-0 items-center gap-3 px-4 pt-3 pb-2">
        <button
          type="button"
          onClick={annuler}
          disabled={verrouille}
          aria-label="Annuler le recadrage"
          className="pressable min-h-tactile min-w-tactile -ml-2 flex items-center justify-center rounded-full text-white disabled:opacity-50"
        >
          <IconeCroix className="size-5" />
        </button>
        <p className="text-corps min-w-0 flex-1 truncate font-medium text-white">
          {titre}
        </p>
      </header>

      <div
        ref={scene}
        onPointerDown={auPointeurBas}
        onPointerMove={auPointeurDeplace}
        onPointerUp={auPointeurHaut}
        onPointerCancel={auPointeurHaut}
        className="t-recadrage-scene relative min-h-0 flex-1 touch-none overscroll-contain select-none"
      >
        <canvas ref={canvas} className="block h-full w-full" />

        {/* Le liseré du cadre est peint en CSS et non dans le canvas : il doit
            rester net quel que soit le rapport de pixels, et il ne fait pas
            partie de l'image. Il ne cerne pas un bloc — c'est la découpe
            elle-même qu'il rend lisible, ce que la règle des traits fins du
            design system vise à protéger, pas à interdire. */}
        <span
          aria-hidden="true"
          className={`t-recadrage-cadre pointer-events-none absolute ${
            forme === "cercle" ? "rounded-full" : "rounded-bloc"
          }`}
        />

        {!pret && !echec && (
          <span className="text-corps-sm absolute inset-0 flex items-center justify-center text-white/80">
            Ouverture de la photo…
          </span>
        )}
      </div>

      <div className="relative flex shrink-0 flex-col gap-2.5 px-4 pt-2 pb-3">
        {echec ? (
          <p
            role="alert"
            className="text-corps-sm rounded-carte bg-primaire px-4 py-3.5 text-center text-white"
          >
            {echec}
          </p>
        ) : (
          <p className="text-corps-sm text-center text-white/70">
            Glisse pour placer, pince pour zoomer.
          </p>
        )}

        <Bouton
          onClick={confirmer}
          occupe={verrouille}
          libelleOccupe="Envoi…"
          disabled={!pret || Boolean(echec)}
        >
          Confirmer
        </Bouton>
        {/* **Le remplacement vit DANS le recadrage, pas avant lui.** Ouvrir la
            photothèque d'abord obligerait à choisir un fichier pour découvrir
            qu'on voulait seulement recadrer celui qui est déjà là ; ouvert sur
            la photo en place, le recadrage montre le point de départ et laisse
            la photothèque à un doigt. Le bouton est en texte et non en
            `Bouton` : trois boutons pleins à la suite auraient donné trois
            actions de même poids là où il n'y en a qu'une principale. */}
        {onChoisirAutre && (
          <button
            type="button"
            onClick={onChoisirAutre}
            disabled={verrouille}
            className="pressable min-h-tactile text-corps-sm py-2 text-center font-medium text-white/70 disabled:opacity-50"
          >
            Choisir une autre photo
          </button>
        )}

        <Bouton variante="secondaire" onClick={annuler} disabled={verrouille}>
          Annuler
        </Bouton>
      </div>
    </div>,
    document.body,
  );
}

/** Marge minimale entre le cadre et le bord de la scène, en pixels. */
const MARGE_CADRE = 24;

/**
 * Facteur d'agrandissement maximal, relatif à l'échelle qui couvre le cadre.
 *
 * Six fois, et non « autant qu'on veut » : au-delà, le carré retenu fait moins
 * de 150 px dans le fichier d'origine, et l'export l'agrandit sans rien inventer
 * — le joueur croirait avoir zoomé alors qu'il n'a fait que flouter.
 */
const ZOOM_MAXIMUM = 6;

/**
 * Trace le masque final dans le contexte : un rond, ou un carré arrondi.
 *
 * Les arcs sont tracés à la main plutôt que par `roundRect`, absent des Safari
 * antérieurs à la version 16 — encore installés sur des iPhone que l'app vise.
 * Un masque manquant ne dégraderait pas le rendu : il le rendrait FAUX, l'aperçu
 * ne montrant plus la découpe que l'export applique quand même.
 */
function tracerMasque(contexte, { x, y, cote, forme }) {
  if (forme === "cercle") {
    contexte.arc(x + cote / 2, y + cote / 2, cote / 2, 0, Math.PI * 2);
    return;
  }

  // 24px sur un cadre de la taille de l'écran, c'est `rounded-bloc` — le plus
  // grand rayon de l'échelle des formes. Le masque dit « carré aux angles
  // adoucis », il ne prétend pas prévisualiser le rayon final de la carte, qui
  // vaut 14px sur 56 et paraîtrait énorme rapporté ici.
  const rayon = Math.min(24, cote / 2);
  contexte.moveTo(x + rayon, y);
  contexte.arcTo(x + cote, y, x + cote, y + cote, rayon);
  contexte.arcTo(x + cote, y + cote, x, y + cote, rayon);
  contexte.arcTo(x, y + cote, x, y, rayon);
  contexte.arcTo(x, y, x + cote, y, rayon);
  contexte.closePath();
}
