/**
 * La grille de statistiques 2×2 des maquettes 12 et 14.
 *
 * Un seul composant pour les deux écrans : « mon profil » et « profil d'un
 * membre » affichent exactement les mêmes quatre chiffres, servis par la même
 * route. Deux copies auraient fini par diverger, et deux profils côte à côte ne
 * se compareraient plus.
 *
 * **Règle 4.1 : tous les chiffres sont entiers, aucune décimale nulle part.**
 * `cote_moy_tentee` en particulier s'affiche « 310 », jamais « ×3,1 » — c'est
 * le cas que le CLAUDE.md cite nommément. Le backend ne sert d'ailleurs que des
 * entiers : rien ici n'a à arrondir quoi que ce soit.
 *
 * Avant le premier Grand Prix jugé, trois cases sur quatre affichent « — » et
 * non « 0 ». « Meilleur coup 0 » et « 0 % de paris gagnés » se lisent comme un
 * mauvais bilan, alors qu'il n'y a pas encore de bilan du tout. C'est à cela que
 * servent les compteurs `pronostics_notes` et `gp_joues` servis avec les stats.
 */

const ABSENT = "—";

function Case({ valeur, libelle }) {
  return (
    <div className="rounded-carte-sm bg-surface shadow-carte px-3 py-3.5 text-center">
      <p className="text-primaire text-[20px] leading-none font-medium">
        {valeur}
      </p>
      <p className="text-label-sm text-texte-doux mt-1.5">{libelle}</p>
    </div>
  );
}

export default function GrilleStats({ stats }) {
  // Les statistiques sont le seul morceau de ces deux écrans qui puisse manquer
  // à lui seul : la route peut refuser (aucun championnat partagé) ou Railway
  // se réveiller trop lentement, sans que le profil lui-même échoue. On le dit
  // en une ligne plutôt que d'afficher quatre cases à zéro, qui se liraient
  // comme un bilan alors qu'aucun chiffre n'a été calculé.
  if (!stats) {
    return (
      <div className="rounded-carte bg-surface shadow-carte px-4 py-5 text-center">
        <p className="text-corps-sm text-texte-doux">
          Statistiques indisponibles pour l'instant.
        </p>
      </div>
    );
  }

  // Les trois premières cases dépendent de pronostics déjà jugés ; la
  // quatrième, non — une cote moyenne tentée existe dès le premier pronostic
  // saisi, avant même que la course soit courue.
  const juge = (stats.pronostics_notes ?? 0) > 0;

  return (
    <div className="grid grid-cols-2 gap-2.5">
      <Case
        valeur={juge ? `${stats.paris_gagnes_pct}%` : ABSENT}
        libelle="Paris gagnés"
      />
      <Case
        valeur={juge ? stats.pts_moyen_gp : ABSENT}
        libelle="Pts moy. / GP"
      />
      <Case
        valeur={juge ? stats.meilleur_coup : ABSENT}
        libelle="Meilleur coup"
      />
      <Case
        valeur={stats.cote_moy_tentee > 0 ? stats.cote_moy_tentee : ABSENT}
        libelle="Cote moy. tentée"
      />
    </div>
  );
}
