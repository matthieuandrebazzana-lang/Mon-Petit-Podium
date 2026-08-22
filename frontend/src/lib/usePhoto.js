import { useCallback, useEffect, useState } from "react";

/**
 * L'état de chargement d'une photo — le même pour la pastille et pour la carte.
 *
 * > ### Pourquoi ce n'est pas simplement `onLoad`
 * >
 * > Une image **déjà en cache** est décodée par le navigateur avant que React
 * > n'ait posé son gestionnaire : l'événement `load` part dans le vide, `onLoad`
 * > n'est jamais appelé, et la photo reste à `opacity: 0` **indéfiniment**. Ce
 * > n'est pas un cas de bord — c'est le cas ORDINAIRE dès la deuxième visite
 * > d'un écran, donc la quasi-totalité des affichages.
 * >
 * > Le remède est la fonction de référence ci-dessous : React l'appelle au
 * > moment où l'élément entre dans le DOM, et `naturalWidth > 0` dit alors si le
 * > pixel est déjà là. `complete` seul ne suffirait pas : il vaut aussi `true`
 * > pour une image en échec, qu'on marquerait chargée.
 *
 * **L'URL est retenue dans l'état, et c'est ce qui rend le remplacement
 * visible.** Changer de photo change l'URL (elle porte un horodatage, voir
 * `lib/stockage.js`) : sans cette comparaison, la nouvelle image hériterait du
 * `chargee` de l'ancienne et apparaîtrait d'un coup, sans fondu — et une
 * nouvelle image en échec hériterait de son succès.
 *
 * @returns {{chargee: boolean, cassee: boolean, aLImage: (element: HTMLImageElement|null) => void, auChargement: () => void, aLEchec: () => void}}
 */
export function usePhoto(url) {
  const [etat, setEtat] = useState({ url, chargee: false, cassee: false });

  // Réinitialisation **pendant le rendu** plutôt que dans un effet : un effet
  // laisserait passer une image affichée avec l'état de la précédente, donc un
  // clignotement d'une image à l'écran.
  if (etat.url !== url) {
    setEtat({ url, chargee: false, cassee: false });
  }

  const aLImage = useCallback((element) => {
    // `naturalWidth` et non `complete` : une image en échec est « complete »
    // elle aussi, et on la marquerait chargée alors qu'il n'y a rien à montrer.
    if (element?.complete && element.naturalWidth > 0) {
      setEtat((precedent) => ({ ...precedent, chargee: true }));
    }
  }, []);

  const auChargement = useCallback(
    () => setEtat((precedent) => ({ ...precedent, chargee: true })),
    [],
  );

  const aLEchec = useCallback(
    () => setEtat((precedent) => ({ ...precedent, cassee: true })),
    [],
  );

  return {
    chargee: etat.url === url && etat.chargee,
    cassee: etat.url === url && etat.cassee,
    aLImage,
    auChargement,
    aLEchec,
  };
}

/**
 * Le même état, mais **sans élément dans le DOM** — pour une image SVG.
 *
 * > ### Pourquoi le hook ci-dessus ne convient pas au cockpit
 * >
 * > `usePhoto` repose sur `complete` et `naturalWidth`, deux propriétés d'un
 * > `HTMLImageElement`. Un `<image>` SVG est un `SVGImageElement` : il n'en a
 * > **aucune des deux**, et il n'existe donc aucun moyen de lui demander « le
 * > pixel est-il déjà là ? ». Sur une image servie par le cache — le cas
 * > ORDINAIRE dès la deuxième visite — on resterait suspendu à un événement
 * > `load` qu'on ne peut pas savoir passé, et la photo tiendrait `opacity: 0`
 * > indéfiniment. C'est exactement le défaut que `usePhoto` a été écrit pour
 * > corriger, sous une autre forme.
 *
 * **La question est donc posée à un élément détaché**, jamais rendu : le
 * navigateur sert la même URL depuis le même cache, et l'objet, lui, répond à
 * `complete`. Aucun second téléchargement — c'est la mécanique de préchargement
 * que `<link rel="preload">` fait à l'échelle du document.
 *
 * Il rend le même couple `chargee` / `cassee`, et **pour la même raison** :
 * `cassee` couvre l'URL en base dont l'objet a disparu du stockage, où le
 * cockpit doit redevenir ce qu'il est sans photo plutôt qu'un disque vide.
 */
export function usePhotoDetachee(url) {
  const [etat, setEtat] = useState({ url, chargee: false, cassee: false });

  // Réinitialisation pendant le rendu, même règle que ci-dessus : un effet
  // laisserait passer une image affichée avec l'état de la précédente.
  if (etat.url !== url) {
    setEtat({ url, chargee: false, cassee: false });
  }

  useEffect(() => {
    if (!url) return undefined;

    let actif = true;
    const image = new Image();

    const conclure = () => {
      if (!actif) return;
      // `naturalWidth` et non `complete` : une image en échec est « complete »
      // elle aussi. Même juge que dans `usePhoto`.
      const reussi = image.naturalWidth > 0;
      setEtat({ url, chargee: reussi, cassee: !reussi });
    };

    image.onload = conclure;
    image.onerror = conclure;
    image.src = url;

    // Servie par le cache, l'image est **déjà** complète : aucun événement ne
    // viendra, et l'attendre reviendrait à ne jamais montrer la photo.
    if (image.complete) conclure();

    return () => {
      actif = false;
      image.onload = null;
      image.onerror = null;
    };
  }, [url]);

  return {
    chargee: etat.url === url && etat.chargee,
    cassee: etat.url === url && etat.cassee,
  };
}
