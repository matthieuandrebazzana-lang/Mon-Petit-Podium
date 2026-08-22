/**
 * Traitement d'une photo AVANT son dépôt — décodage, recadrage, encodage.
 *
 * **Le seul endroit qui décide de ce qu'on envoie.** Trois questions n'ont
 * qu'une réponse dans le projet, et elle est ici : à quelle taille, dans quel
 * format, à quelle qualité. Écrites dans les deux écrans qui déposent une photo,
 * elles auraient divergé au premier ajustement — et l'écart se serait lu « ma
 * photo de championnat est plus nette que ma photo de profil ».
 *
 * > ### Ce que le compartiment reçoit n'est plus jamais le fichier choisi
 * >
 * > Depuis la version `0.51.0`, aucun fichier de la photothèque ne part tel quel :
 * > il est décodé, recadré au carré, ramené à **800 px de côté au plus** et
 * > réencodé en **JPEG qualité 0,85**. Une photo d'iPhone de quatre mégaoctets en
 * > pèse alors moins de deux cents kilo-octets.
 * >
 * > **Deux plafonds coexistent donc, et ils ne mesurent pas la même chose** :
 * > `TAILLE_MAXIMALE` (5 Mo, `lib/stockage.js`) borne ce que le joueur a le droit
 * > de CHOISIR, et le plafond du compartiment (2 Mo, migration 16) borne ce qu'on
 * > DÉPOSE. Le second n'est plus jamais atteint, et c'est ce qui permet au premier
 * > d'être si large.
 *
 * **Rien ici ne touche au réseau.** Le module travaille sur un `File` et rend un
 * `Blob` ; c'est `lib/stockage.js` qui dépose, et lui seul.
 */

/** Côté maximum de l'image déposée, en pixels. */
export const COTE_MAXIMUM = 800;

/**
 * Qualité de l'encodage JPEG.
 *
 * 0,85 est le point où l'œil cesse de distinguer l'original sur une photo
 * ordinaire, et où le poids a déjà chuté d'un ordre de grandeur. Au-dessus, on
 * paie des kilo-octets pour du bruit de capteur ; en dessous, les aplats de ciel
 * se mettent à baver, ce qui se voit sur une photo de groupe.
 */
export const QUALITE_JPEG = 0.85;

/**
 * Format de dépôt — **toujours** JPEG, quel que soit le fichier choisi.
 *
 * Un PNG de photographie pèse cinq à dix fois son équivalent JPEG sans rien
 * apporter, et la transparence qu'il sait porter n'a aucun sens ici : la photo
 * est recadrée dans un rond ou un carré plein. Un WEBP serait plus léger encore,
 * mais `canvas.toBlob` retombe silencieusement sur PNG quand un navigateur ne
 * sait pas l'encoder — et un repli silencieux qui multiplie le poids par huit est
 * exactement ce qu'on cherche à éviter.
 */
export const TYPE_DEPOSE = "image/jpeg";

/** Extension correspondante — le chemin de stockage la porte. */
export const EXTENSION_DEPOSEE = "jpg";

const DECODAGE_IMPOSSIBLE =
  "Cette image n'a pas pu être ouverte. Choisis-en une autre.";
const ENCODAGE_IMPOSSIBLE =
  "Cette image n'a pas pu être préparée. Réessaie dans quelques instants.";

/** Échec de traitement, porteur d'un message déjà écrit en français. */
export class ErreurImage extends Error {}

/**
 * Décode un fichier en image utilisable, et rend aussi ses dimensions.
 *
 * **L'URL d'objet est révoquée dans tous les cas**, y compris en échec : chaque
 * `createObjectURL` retient son fichier en mémoire jusqu'à ce qu'on le relâche,
 * et quelqu'un qui change trois fois d'avis en retiendrait trois.
 *
 * `decode()` est préféré à l'événement `load` : il attend que le pixel soit
 * réellement décodé, là où `load` se contente de l'avoir reçu. Dessiner une image
 * chargée mais non décodée dans un canvas rendrait un carré vide sur Safari. Le
 * repli sur `load` couvre les navigateurs qui ne l'exposent pas.
 */
export function chargerImage(fichier) {
  return new Promise((resoudre, rejeter) => {
    const url = URL.createObjectURL(fichier);
    const image = new Image();
    // La photo vient d'un `blob:` de même origine : le canvas ne sera pas
    // marqué « altéré », et `toBlob` restera donc autorisé.
    image.decoding = "async";

    const finir = (action) => {
      URL.revokeObjectURL(url);
      action();
    };

    image.onerror = () =>
      finir(() => rejeter(new ErreurImage(DECODAGE_IMPOSSIBLE)));

    image.onload = () => {
      const pret = image.decode
        ? image.decode().catch(() => undefined)
        : Promise.resolve();
      pret.then(() =>
        finir(() => {
          if (!image.naturalWidth || !image.naturalHeight) {
            rejeter(new ErreurImage(DECODAGE_IMPOSSIBLE));
            return;
          }
          resoudre(image);
        }),
      );
    };

    image.src = url;
  });
}

/**
 * Encode un canvas en JPEG. **Le seul appel à `toBlob` du projet.**
 *
 * `toBlob` rend `null` plutôt que de lever quand l'encodage échoue — sur un
 * canvas trop grand pour la mémoire d'un iPhone, par exemple. Ce `null` est
 * traité comme l'échec qu'il est : sans ce test, `deposerPhoto` recevrait `null`
 * et le compartiment répondrait par une erreur technique.
 */
function encoder(canvas) {
  return new Promise((resoudre, rejeter) => {
    canvas.toBlob(
      (blob) =>
        blob ? resoudre(blob) : rejeter(new ErreurImage(ENCODAGE_IMPOSSIBLE)),
      TYPE_DEPOSE,
      QUALITE_JPEG,
    );
  });
}

/**
 * Prépare un canvas de dessin lissé.
 *
 * `imageSmoothingQuality: "high"` n'est pas décoratif : une photo de 4032 px
 * ramenée à 800 en une seule passe de `drawImage` crêne ses contours si le
 * navigateur échantillonne au plus proche. Safari honore ce réglage.
 */
function canvasDe(cote) {
  const canvas = document.createElement("canvas");
  canvas.width = cote;
  canvas.height = cote;
  const contexte = canvas.getContext("2d");
  if (!contexte) throw new ErreurImage(ENCODAGE_IMPOSSIBLE);
  contexte.imageSmoothingEnabled = true;
  contexte.imageSmoothingQuality = "high";
  return { canvas, contexte };
}

/**
 * L'échelle minimale qui couvre entièrement un cadre carré.
 *
 * **Elle appartient à ce module et non à l'écran de recadrage**, parce que
 * l'écran de recadrage et l'export doivent en avoir exactement la même idée : si
 * l'un laissait descendre l'échelle d'un centième sous l'autre, l'export tirerait
 * quelques pixels hors de l'image et le bord du rond partirait en noir.
 */
export function echelleMinimale(largeur, hauteur, cote) {
  return cote / Math.min(largeur, hauteur);
}

/**
 * Borne un décalage pour que l'image couvre toujours le cadre.
 *
 * Le décalage est mesuré en pixels d'écran, depuis le centre du cadre vers le
 * centre de l'image. **La borne est appliquée en continu pendant le geste**, pas
 * seulement au relâchement : une image qu'on laisserait sortir puis qu'on
 * ramènerait d'un coup ferait apparaître un trou dans le masque, c'est-à-dire
 * exactement ce que le recadrage promet de ne jamais montrer. Elle ne rebondit
 * pas non plus — le caoutchouc d'iOS a sa place sur un défilement, pas sur une
 * découpe dont le résultat serait faux.
 */
export function bornerDecalage(decalage, etendue) {
  const limite = Math.max(0, etendue / 2);
  return Math.min(limite, Math.max(-limite, decalage));
}

/**
 * Le carré de l'image, en pixels d'IMAGE, que le cadre laisse voir.
 *
 * Sortie du composant de recadrage pour être éprouvable seule : c'est une
 * fonction pure de quatre nombres, là où la vérifier dans le composant
 * demanderait de monter un DOM et de rejouer des appuis — ce que le projet
 * n'outille pas (`docs/composants.md` §5, même motif que `lib/pronostics.js`).
 *
 * @param {object} vue
 * @param {number} vue.largeur   largeur naturelle de l'image
 * @param {number} vue.hauteur   hauteur naturelle de l'image
 * @param {number} vue.echelle   facteur d'affichage à l'écran
 * @param {number} vue.decalageX centre de l'image, depuis le centre du cadre
 * @param {number} vue.decalageY idem, en vertical
 * @param {number} vue.cote      côté du cadre, en pixels d'écran
 */
export function carreVisible({
  largeur,
  hauteur,
  echelle,
  decalageX,
  decalageY,
  cote,
}) {
  const coteSource = cote / echelle;
  return {
    x: largeur / 2 - (decalageX + cote / 2) / echelle,
    y: hauteur / 2 - (decalageY + cote / 2) / echelle,
    cote: coteSource,
  };
}

/**
 * Recadre une image selon la vue du composant de recadrage, et l'encode.
 *
 * **La sortie ne dépasse jamais 800 px, et ne remonte jamais au-dessus de la
 * source.** Exporter à 800 un carré qui n'en fait que 300 dans le fichier
 * d'origine produirait une image plus lourde ET plus floue que celle qu'on a :
 * l'agrandissement n'invente aucun détail, il n'invente que des octets.
 */
export async function recadrerImage(image, vue) {
  const carre = carreVisible({
    largeur: image.naturalWidth,
    hauteur: image.naturalHeight,
    ...vue,
  });

  const sortie = Math.max(1, Math.min(COTE_MAXIMUM, Math.round(carre.cote)));
  const { canvas, contexte } = canvasDe(sortie);

  contexte.drawImage(
    image,
    carre.x,
    carre.y,
    carre.cote,
    carre.cote,
    0,
    0,
    sortie,
    sortie,
  );

  return encoder(canvas);
}

/**
 * Ramène une image dans un carré de 800 px, sans la recadrer, et l'encode.
 *
 * **Ce n'est pas le chemin ordinaire** — depuis la version `0.51.0` toute photo
 * passe par le recadrage, qui produit déjà un carré. La fonction existe parce que
 * la question « à quelle taille et dans quel format une photo part-elle ? » doit
 * avoir une réponse indépendante du geste de recadrage : c'est elle qui la porte,
 * et `recadrerImage` en applique les mêmes constantes. Sans elle, la règle des
 * 800 px et de la qualité 0,85 n'existerait que comme effet de bord d'un
 * composant d'interface.
 *
 * Le fond est peint en blanc avant le dessin : une image d'origine transparente
 * (un PNG à fond vide) donnerait en JPEG un fond NOIR, le format n'ayant pas de
 * canal alpha et le canvas rendant `rgba(0,0,0,0)` sur un aplat noir.
 */
export async function compresserImage(image) {
  const { naturalWidth: largeur, naturalHeight: hauteur } = image;
  const facteur = Math.min(1, COTE_MAXIMUM / Math.max(largeur, hauteur));
  const cible = {
    largeur: Math.max(1, Math.round(largeur * facteur)),
    hauteur: Math.max(1, Math.round(hauteur * facteur)),
  };

  const canvas = document.createElement("canvas");
  canvas.width = cible.largeur;
  canvas.height = cible.hauteur;
  const contexte = canvas.getContext("2d");
  if (!contexte) throw new ErreurImage(ENCODAGE_IMPOSSIBLE);
  contexte.imageSmoothingEnabled = true;
  contexte.imageSmoothingQuality = "high";
  contexte.fillStyle = "#FFFFFF";
  contexte.fillRect(0, 0, cible.largeur, cible.hauteur);
  contexte.drawImage(image, 0, 0, cible.largeur, cible.hauteur);

  return encoder(canvas);
}

/**
 * Habille un `Blob` en `File`, pour que le dépôt garde un nom lisible.
 *
 * Supabase Storage ne lit pas ce nom — le chemin est fabriqué par
 * `lib/stockage.js` — mais un `File` nommé se relit dans les outils de
 * développement, et c'est gratuit.
 */
export function enFichier(blob, base) {
  return new File([blob], `${base}.${EXTENSION_DEPOSEE}`, {
    type: TYPE_DEPOSE,
    lastModified: Date.now(),
  });
}
