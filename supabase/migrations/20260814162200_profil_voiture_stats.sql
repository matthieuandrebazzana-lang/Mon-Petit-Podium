-- =============================================================================
-- Étape 8 — Profils : voiture personnalisée et statistiques
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les sept migrations précédentes. Elle suppose :
--   - `public.profils`   (migration 20260809191018) : elle l'ALTÈRE, ne la crée pas ;
--   - `public.pronostics.points_gagnes` et `public.cotes` (étapes 5 et 6) : la
--     fonction de statistiques les lit ;
--   - `public.classement_du_championnat` (étape 7) : elle la remplace.
--
-- La migration est idempotente : la rejouer ne casse rien et ne touche à aucune
-- donnée.
-- =============================================================================

-- --  1. La voiture, sur le profil  ---------------------------------------------

-- Section 5 du CLAUDE.md : « Chaque utilisateur possède UNE SEULE voiture,
-- identique dans tous ses championnats ». Ces trois colonnes vivent donc sur le
-- profil et non sur l'adhésion à un championnat — les y mettre autoriserait la
-- même personne à changer de voiture d'un championnat à l'autre, ce que la
-- section 5 exclut explicitement.
alter table public.profils
  add column if not exists couleur1 text    not null default '#800111',
  add column if not exists couleur2 text    not null default '#FFFFFF',
  add column if not exists numero   integer;

comment on column public.profils.couleur1 is
  'Couleur de la coque de la voiture, en #RRGGBB. Défaut : le rouge de la marque.';
comment on column public.profils.couleur2 is
  'Couleur des ailerons, en #RRGGBB. Toujours différente de couleur1.';
comment on column public.profils.numero is
  'Numéro libre choisi par le membre, 1 à 99. NULL tant qu''il n''en a pas choisi : le rang au classement prend alors sa place sur la voiture.';

-- LA contrainte demandée : 1 à 99, comme un vrai numéro de Formule 1.
-- `not valid` n'est pas utilisé : la colonne vient d'être ajoutée, toutes les
-- lignes existantes y valent NULL, et un `check` laisse passer NULL.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profils'::regclass
      and conname  = 'profils_numero_valide'
  ) then
    alter table public.profils
      add constraint profils_numero_valide check (numero between 1 and 99);
  end if;
end
$$;

-- Format des couleurs. Ajout par rapport aux colonnes demandées, et assumé :
-- ces deux valeurs partent telles quelles dans l'attribut `fill` d'un SVG côté
-- frontend. Le contrôle de saisie du backend peut être contourné (la RLS
-- autorise un membre à modifier son propre profil, donc à écrire ces colonnes
-- depuis n'importe quel client) ; la base, non.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profils'::regclass
      and conname  = 'profils_couleurs_hex'
  ) then
    alter table public.profils
      add constraint profils_couleurs_hex check (
        couleur1 ~ '^#[0-9A-Fa-f]{6}$' and couleur2 ~ '^#[0-9A-Fa-f]{6}$'
      );
  end if;
end
$$;

-- Les deux couleurs doivent être différentes. Ce n'est pas du confort : la
-- seconde peint les ailerons, seuls éléments dont la forme reste lisible à
-- 56px de large sur la vue piste. Une voiture monochrome n'a plus d'ailerons,
-- et le nom écrit sur l'aileron arrière perd son fond.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profils'::regclass
      and conname  = 'profils_couleurs_distinctes'
  ) then
    alter table public.profils
      add constraint profils_couleurs_distinctes check (upper(couleur1) <> upper(couleur2));
  end if;
end
$$;

-- **Aucune contrainte d'unicité sur `numero`**, et c'est délibéré. Une voiture
-- est identique dans tous les championnats de son propriétaire (section 5) :
-- un numéro unique globalement voudrait dire 99 comptes maximum sur toute
-- l'application, ce qui est absurde pour une app ouverte au public (section 1).
-- L'unicité se juge par championnat, à l'affichage, et reste **indicative** :
-- le frontend avertit, il ne bloque pas.

-- --  2. Sécurité au niveau des lignes  -----------------------------------------

-- Les deux politiques demandées existent depuis la migration 20260809191018 et
-- couvrent exactement ce que l'étape 8 réclame. Elles sont réaffirmées ici, à
-- l'identique, pour que cette migration décrive complètement l'état qu'elle
-- suppose : les trois colonnes ci-dessus sont lues par tous les membres
-- connectés (classements, vue piste, profil d'un autre membre) et écrites par
-- leur seul propriétaire.
--
-- Conséquence à ne pas perdre de vue : la politique d'écriture porte sur la
-- LIGNE, pas sur la colonne. Un membre peut donc écrire `couleur1`, `couleur2`
-- et `numero` depuis n'importe quel client Supabase, sans passer par
-- `PATCH /profils/moi`. C'est pour cela que les contraintes ci-dessus vivent
-- en base et pas seulement dans la route.
alter table public.profils enable row level security;

drop policy if exists "Profils lisibles par les membres connectes" on public.profils;
create policy "Profils lisibles par les membres connectes"
  on public.profils for select
  to authenticated
  using (true);

drop policy if exists "Chacun modifie son profil" on public.profils;
create policy "Chacun modifie son profil"
  on public.profils for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- --  3. Statistiques d'un membre sur une saison  -------------------------------

-- Les quatre chiffres de la grille 2×2 des maquettes 12 et 14, calculés en base
-- pour la même raison que le classement de l'étape 7 : sans cela il faudrait
-- transporter tous les pronostics d'une saison — une centaine de lignes, plus
-- les cotes correspondantes — pour n'en tirer que quatre entiers.
--
-- **La saison est l'année civile du Grand Prix**, lue en UTC. `date_course` est
-- stockée en UTC depuis l'étape 4 ; l'ancrer explicitement évite que le
-- résultat dépende du fuseau de la session PostgreSQL. Un GP dont l'horaire
-- n'est pas encore annoncé (`date_course` nulle) n'appartient à aucune saison
-- et n'entre donc dans aucune statistique — le rattacher à l'année courante
-- serait une supposition.
--
-- `security definer` : la fonction est paramétrée par un profil, donc elle lit
-- les pronostics d'autrui. Sous l'identité de l'appelant, la politique RLS de
-- l'étape 5 filtrerait silencieusement les lignes des membres avec qui il ne
-- partage aucun championnat, et la moyenne renvoyée serait fausse sans que rien
-- ne le dise. C'est donc la route qui porte l'autorisation, en vérifiant AVANT
-- l'appel que le demandeur est le membre lui-même ou partage un championnat
-- avec lui (routes/profils.py), et la fonction n'est accordée qu'à
-- `service_role`.
create or replace function public.stats_du_profil(p_profil uuid, p_saison integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with tentatives as (
    select
      pr.gp_id,
      pr.points_gagnes,
      -- Ce que le pronostic POUVAIT rapporter, en points (règle 4.1). Pour un
      -- podium, la SOMME des deux cotes : c'est la règle tranchée à l'étape 6
      -- pour `points_gagnes`, et comparer une moyenne de cotes tentées à des
      -- points gagnés calculés autrement n'aurait aucun sens.
      coalesce(c1.valeur, 0) + coalesce(c2.valeur, 0) as valeur_tentee,
      -- Une cote retirée par Unibet depuis la saisie ne vaut pas zéro : elle
      -- est inconnue. La compter à 0 tirerait la moyenne vers le bas sans que
      -- le joueur ait rien tenté de tel.
      (
        c1.valeur is not null
        and (pr.type <> 'podium' or c2.valeur is not null)
      ) as cote_connue
    from public.pronostics pr
    join public.grands_prix g on g.id = pr.gp_id
    left join public.pronostic_podium pp on pp.pronostic_id = pr.id
    left join public.cotes c1
      on c1.gp_id = pr.gp_id and c1.id_outcome_unibet = pr.id_outcome_unibet
    left join public.cotes c2
      on c2.gp_id = pr.gp_id and c2.id_outcome_unibet = pp.pilote_2
    where pr.profil_id = p_profil
      and g.date_course is not null
      and extract(year from (g.date_course at time zone 'UTC')) = p_saison
  ),
  compte as (
    select
      count(*) filter (where points_gagnes is not null)        as notes,
      count(*) filter (where points_gagnes > 0)                as reussis,
      count(distinct gp_id) filter (where points_gagnes is not null) as gp_joues,
      coalesce(sum(points_gagnes), 0)                          as total,
      coalesce(max(points_gagnes), 0)                          as meilleur,
      count(*) filter (where cote_connue)                      as tentees,
      coalesce(sum(valeur_tentee) filter (where cote_connue), 0) as somme_tentee
    from tentatives
  )
  select jsonb_build_object(
    -- Les quatre chiffres de la grille 2×2. **Tous entiers, jamais de
    -- décimale** : un pourcentage de paris gagnés à 52,38 % et une cote moyenne
    -- à « ×3,1 » sont l'un comme l'autre proscrits (règle 4.1 pour la seconde).
    'paris_gagnes_pct', case when notes = 0 then 0
                             else round(100.0 * reussis / notes)::int end,
    'pts_moyen_gp',     case when gp_joues = 0 then 0
                             else round(total::numeric / gp_joues)::int end,
    'meilleur_coup',    meilleur::int,
    'cote_moy_tentee',  case when tentees = 0 then 0
                             else round(somme_tentee::numeric / tentees)::int end,
    -- Trois compteurs en plus des quatre demandés. Ils ne s'affichent pas tels
    -- quels : ils disent à l'interface si la saison a commencé pour ce membre.
    -- Sans eux, « meilleur coup 0 » et « 0 % de paris gagnés » s'afficheraient
    -- avant le premier Grand Prix, ce qui se lit comme un mauvais bilan alors
    -- qu'il n'y a pas encore de bilan du tout.
    'pronostics_notes', notes::int,
    'gp_joues',         gp_joues::int,
    'total_points',     total::int
  )
  from compte;
$$;

comment on function public.stats_du_profil(uuid, integer) is
  'Statistiques d''un membre sur une saison (année civile du GP, en UTC). Réservée au backend : l''autorisation est vérifiée avant l''appel.';

revoke all on function public.stats_du_profil(uuid, integer) from public;
revoke all on function public.stats_du_profil(uuid, integer) from anon;
revoke all on function public.stats_du_profil(uuid, integer) from authenticated;
grant execute on function public.stats_du_profil(uuid, integer) to service_role;

-- Aucun index nouveau. Les deux index partiels de `public.pronostics` posés aux
-- étapes 6 et 7 (`points_gagnes is null` et `points_gagnes is not null`) portent
-- ensemble sur toutes les lignes de la table et commencent tous deux par
-- `profil_id` : la lecture « tous les pronostics de ce profil » est déjà servie.

-- --  4. Le classement porte désormais la voiture  ------------------------------

-- Même fonction qu'à l'étape 7, à trois champs près : `couleur1`, `couleur2` et
-- `numero`. La vue liste et la vue piste peignent les voitures avec les vraies
-- couleurs de chaque membre, à la place des livrées attribuées par ordre
-- d'inscription — qui n'avaient de raison d'être que tant que rien ne
-- permettait de choisir.
--
-- `ordre_inscription` reste servi : il est le 4ᵉ critère de départage de la
-- règle 4.6, ce que la personnalisation ne change pas.
--
-- Le reste du corps est inchangé (règle 4.6, `row_number` et non `rank`,
-- `left join lateral` pour ne pas faire disparaître un membre sans pronostic) :
-- voir la migration 20260814103000 pour le détail de ces trois choix.
create or replace function public.classement_du_championnat(p_championnat uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profil_id',          x.profil_id,
        'pseudo',             x.pseudo,
        'total_points',       x.total_points,
        'pronostics_reussis', x.pronostics_reussis,
        'meilleure_cote',     x.meilleure_cote,
        'ordre_inscription',  x.ordre_inscription,
        'rang',               x.rang,
        'couleur1',           x.couleur1,
        'couleur2',           x.couleur2,
        'numero',             x.numero
      )
      order by x.rang
    ),
    '[]'::jsonb
  )
  from (
    select
      m.profil_id,
      coalesce(p.pseudo, 'Pilote') as pseudo,
      coalesce(s.total, 0)         as total_points,
      coalesce(s.reussis, 0)       as pronostics_reussis,
      s.meilleure                  as meilleure_cote,
      -- Un profil manquant ne doit pas rendre une voiture sans couleur : le
      -- SVG afficherait des aplats transparents. On retombe sur les défauts de
      -- la colonne, les mêmes que ceux d'un membre qui n'a rien personnalisé.
      coalesce(p.couleur1, '#800111') as couleur1,
      coalesce(p.couleur2, '#FFFFFF') as couleur2,
      -- Nul tant que le membre n'a pas choisi : c'est alors son rang qui
      -- s'affiche sur la voiture, comme à l'étape 7.
      p.numero                     as numero,
      row_number() over (order by m.rejoint_le, m.profil_id) as ordre_inscription,
      row_number() over (
        order by
          coalesce(s.total, 0)     desc,
          coalesce(s.reussis, 0)   desc,
          coalesce(s.meilleure, 0) desc,
          m.rejoint_le             asc,
          m.profil_id              asc
      ) as rang
    from public.membres_championnat m
    left join public.profils p on p.id = m.profil_id
    left join lateral (
      select
        sum(pr.points_gagnes)                                as total,
        count(*) filter (where pr.points_gagnes > 0)         as reussis,
        max(pr.points_gagnes) filter (where pr.points_gagnes > 0) as meilleure
      from public.pronostics pr
      where pr.profil_id = m.profil_id
        and pr.points_gagnes is not null
    ) s on true
    where m.championnat_id = p_championnat
  ) x;
$$;

comment on function public.classement_du_championnat(uuid) is
  'Classement d''un championnat, trié selon les départages de la règle 4.6, voitures comprises. Réservé au backend : l''appartenance est vérifiée avant l''appel.';

revoke all on function public.classement_du_championnat(uuid) from public;
revoke all on function public.classement_du_championnat(uuid) from anon;
revoke all on function public.classement_du_championnat(uuid) from authenticated;
grant execute on function public.classement_du_championnat(uuid) to service_role;
