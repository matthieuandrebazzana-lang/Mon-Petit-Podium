/**
 * Les briques des squelettes de chargement — étape 9.
 *
 * **Un squelette n'est pas un écran d'attente, c'est l'écran à venir en creux.**
 * La règle tenue partout dans l'app : un squelette de carte ressemble à une
 * carte, un squelette de voiture ressemble à une voiture, une barre a la
 * largeur du texte qu'elle remplace. Aucun disque qui tourne, aucun
 * « Chargement… » : rien de tout cela ne dit ce qui arrive, et les deux
 * imposent un saut de mise en page quand les données arrivent enfin.
 *
 * Les trois primitives ci-dessous portent toutes `t-skel-bar`, qui peint le gris
 * `#E8E0D8` et y fait passer la bande de lumière (voir `index.css`). Les écrans
 * n'écrivent donc jamais cette couleur eux-mêmes : elle vit à un seul endroit.
 *
 * Ces blocs sont posés sous `aria-hidden` par `ZoneChargement` : un lecteur
 * d'écran n'a rien à annoncer d'une silhouette.
 */

/** Une barre de texte. `largeur` prend une classe de largeur Tailwind. */
export function Barre({ largeur = "w-1/2", hauteur = "h-3.5", className = "" }) {
  return (
    <div className={`t-skel-bar rounded-full ${largeur} ${hauteur} ${className}`} />
  );
}

/** Un aplat : pastille, vignette, bloc de score. */
export function Pave({ className = "", arrondi = "rounded-champ" }) {
  return <div className={`t-skel-bar ${arrondi} ${className}`} />;
}

/**
 * Une carte entière : la surface blanche est conservée, seuls les contenus sont
 * en gris. C'est ce qui fait qu'un écran ne change pas de couleur au moment de
 * la révélation — seule la matière à l'intérieur des blocs se remplace.
 */
export function Carte({ className = "", children }) {
  return (
    <div className={`rounded-carte bg-surface shadow-carte p-4 ${className}`}>{children}</div>
  );
}

/** Rangée « pastille + deux lignes », la silhouette la plus fréquente de l'app. */
export function Rangee({ avecFin = true }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      <Pave className="size-9 shrink-0" arrondi="rounded-full" />
      <div className="min-w-0 flex-1">
        <Barre largeur="w-1/3" />
        <Barre largeur="w-1/2" hauteur="h-2.5" className="mt-2" />
      </div>
      {avecFin && <Pave className="h-6 w-12 shrink-0" arrondi="rounded-[10px]" />}
    </div>
  );
}
