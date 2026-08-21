import { useCallback, useState } from "react";

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
