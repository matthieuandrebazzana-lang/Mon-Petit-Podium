-- =============================================================================
-- Étape 9 — Calendrier du championnat, et voiture au tableau des résultats
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les neuf migrations précédentes. Elle ne crée AUCUNE table : une
-- fonction nouvelle, une fonction remplacée, un index.
--
-- Elle suppose appliquées :
--   - la 3 (`grands_prix`, `cotes`),
--   - la 5 (`pronostics`, et `pronostics_du_joueur` qu'elle remplace ici),
--   - la 6 (`resultats_gp`, `pronostics.points_gagnes`),
--   - la 8 (`profils.couleur1 / couleur2 / numero`).
--
-- ATTENTION À L'ORDRE. Cette migration **remplace**
-- `public.pronostics_du_championnat`, créée par la 5. Rejouer la 5 après
-- celle-ci restaurerait sa version d'avant, et le tableau des résultats
-- (maquette 11) perdrait les voitures des membres — sans rien casser d'autre,
-- le backend retombant sur les défauts. C'est le même piège que « rejouer la 7
-- après la 8 », déjà documenté au CLAUDE.md : les migrations sont idempotentes
-- chacune pour elle-même, pas dans le désordre.
--
-- La migration est idempotente : la rejouer ne casse rien et ne touche à
-- aucune donnée.
-- =============================================================================


-- --  1. L'index qui sert le calendrier  ---------------------------------------

-- Le calendrier lit « les Grands Prix de la saison, par date ». Sans index, le
-- tri force un balayage complet de `grands_prix` à chaque ouverture de l'écran.
-- La table restera petite (une vingtaine de lignes par saison), mais cet index
-- sert aussi la lecture du prochain GP par l'accueil (étape 5), qui est le
-- chemin le plus emprunté de l'application.
create index if not exists grands_prix_date_idx
  on public.grands_prix (date_course);


-- --  2. Le calendrier d'un championnat  ---------------------------------------

-- Une ligne par Grand Prix de la saison, avec pour chacun ce que le championnat
-- y a marqué. Tout est agrégé en base, pour la même raison qu'au classement de
-- l'étape 7 : sans cela il faudrait rapatrier tous les pronostics notés de tous
-- les membres, sur toute la saison, pour n'en tirer qu'un score et un rang par
-- Grand Prix.
--
-- `security definer`, et réservée à `service_role` : paramétrée par un
-- championnat, elle lit forcément les pronostics d'autrui. Sous l'identité de
-- l'appelant, la politique RLS de l'étape 5 filtrerait les membres avec qui il
-- ne partage rien, et rendrait un calendrier **silencieusement faux** au lieu
-- d'un refus franc. L'autorisation est donc portée par la route, qui vérifie
-- l'appartenance AVANT d'appeler. Exactement le raisonnement de l'étape 7.
--
-- TROIS DÉCISIONS À NE PAS DÉFAIRE :
--
-- 1. **Le rang d'un Grand Prix se calcule avec `rank`, pas `row_number`.**
--    L'étape 7 avait tranché l'inverse pour le classement de la saison, parce
--    que les quatre critères de la règle 4.6 réunis départagent toujours. Ici
--    il n'y a pas de critère de départage : la règle 4.6 régit le classement
--    général, pas un Grand Prix isolé. Avant la course, tout le monde est à
--    zéro — `row_number` inventerait un 1ᵉʳ et un dernier là où il n'y en a pas.
--    Les ex æquo sont donc affichés comme tels.
--
-- 2. **Un Grand Prix sans date annoncée est servi quand même**, en fin de
--    liste. Il appartient à la saison courante par défaut : Unibet publie
--    parfois un GP avant d'en annoncer l'horaire (étape 4), et l'écarter du
--    calendrier le rendrait invisible jusqu'au samedi des qualifications.
--    C'est l'inverse du choix fait pour les statistiques de l'étape 8, et pour
--    une raison précise : une moyenne fausse ne se voit pas, un Grand Prix
--    manquant dans un calendrier se voit tout de suite.
--
-- 3. **`mes_points` vaut NULL quand aucun pronostic du membre n'a été noté**,
--    jamais `0`. C'est la convention posée à l'étape 6 et tenue depuis :
--    « pas encore jugé » et « raté » ne se confondent jamais. L'écran affiche
--    l'un « en attente », l'autre « 0 pts ».
create or replace function public.calendrier_du_championnat(
  p_championnat uuid,
  p_profil      uuid,
  p_saison      integer
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with membres as (
    select m.profil_id
    from public.membres_championnat m
    where m.championnat_id = p_championnat
  ),
  -- Les Grands Prix de la saison. La date est ancrée en UTC : elle est stockée
  -- en UTC depuis l'étape 4, et laisser le fuseau de la session PostgreSQL
  -- décider ferait basculer d'année un GP du 1ᵉʳ janvier.
  gps as (
    select g.id, g.nom, g.date_course, g.statut
    from public.grands_prix g
    where g.date_course is null
       or extract(year from (g.date_course at time zone 'UTC')) = p_saison
  ),
  -- Ce que chaque membre a marqué sur chaque Grand Prix. `count(points_gagnes)`
  -- ne compte que les lignes notées : c'est lui qui distingue « rien joué » de
  -- « joué et raté ».
  scores as (
    select
      p.gp_id,
      p.profil_id,
      coalesce(sum(p.points_gagnes), 0)::integer as points,
      count(p.points_gagnes)::integer            as notes,
      count(*)::integer                          as saisis
    from public.pronostics p
    join membres mb on mb.profil_id = p.profil_id
    group by p.gp_id, p.profil_id
  ),
  -- Le rang de chacun sur chaque Grand Prix. Tous les membres sont classés, y
  -- compris ceux qui n'ont pas joué : les faire disparaître donnerait un rang
  -- « 2 sur 2 » dans un championnat de huit.
  rangs as (
    select
      g.id as gp_id,
      mb.profil_id,
      coalesce(s.points, 0) as points,
      coalesce(s.notes, 0)  as notes,
      coalesce(s.saisis, 0) as saisis,
      rank() over (
        partition by g.id
        order by coalesce(s.points, 0) desc
      ) as rang
    from gps g
    cross join membres mb
    left join scores s on s.gp_id = g.id and s.profil_id = mb.profil_id
  ),
  -- Le classement du Grand Prix, limité aux trois premiers : c'est ce que la
  -- maquette 15 dessine sous l'en-tête de chaque carte. En servir davantage
  -- ferait transporter tout le championnat pour chacun des vingt-quatre Grands
  -- Prix de la saison.
  tetes as (
    select
      r.gp_id,
      jsonb_agg(
        jsonb_build_object(
          'profil_id', r.profil_id,
          'pseudo',    coalesce(pr.pseudo, 'Pilote'),
          'points',    r.points,
          'rang',      r.rang,
          'couleur1',  coalesce(pr.couleur1, '#800111'),
          'couleur2',  coalesce(pr.couleur2, '#FFFFFF')
        )
        order by r.rang, coalesce(pr.pseudo, 'Pilote')
      ) as classement
    from (
      select *, row_number() over (
        partition by gp_id order by rang, profil_id
      ) as place
      from rangs
    ) r
    left join public.profils pr on pr.id = r.profil_id
    where r.place <= 3
    group by r.gp_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'gp_id',       g.id,
        'nom',         g.nom,
        'date_course', g.date_course,
        'statut',      g.statut,
        -- « Cotes disponibles » se lit dans `cotes`, jamais dans le statut : le
        -- statut `cotes_figees` n'est posé par aucun code aujourd'hui (voir le
        -- « Reste à faire » du CLAUDE.md), et un GP peut parfaitement avoir ses
        -- cotes en base en étant resté `a_venir`.
        'cotes_disponibles', exists (
          select 1 from public.cotes c where c.gp_id = g.id
        ),
        -- De même : la présence des résultats se lit dans `resultats_gp`, pas
        -- dans le statut. Le job passe le GP à `termine` même s'il reste des
        -- pronostics sans points (étape 6) ; l'inverse — un GP couru dont le
        -- statut n'a pas bougé — reste possible tant que le job n'a pas tourné.
        'resultats_disponibles', exists (
          select 1 from public.resultats_gp r where r.gp_id = g.id
        ),
        'vainqueur', (
          select r.donnees_brutes->'pilotes'->(l->>'driver_number')->>'nom'
          from public.resultats_gp r,
               jsonb_array_elements(
                 coalesce(r.donnees_brutes->'session_result', '[]'::jsonb)
               ) l
          where r.gp_id = g.id
            and (l->>'position')::integer = 1
          limit 1
        ),
        -- NULL tant qu'aucun pronostic du membre n'a été noté : « en attente »
        -- et « zéro » ne se disent pas pareil (point 3 ci-dessus).
        'mes_points', (
          select case when x.notes > 0 then x.points end
          from rangs x where x.gp_id = g.id and x.profil_id = p_profil
        ),
        'mon_rang', (
          select case when x.notes > 0 then x.rang end
          from rangs x where x.gp_id = g.id and x.profil_id = p_profil
        ),
        'mes_pronostics', coalesce(
          (select x.saisis from rangs x
           where x.gp_id = g.id and x.profil_id = p_profil),
          0
        ),
        'classement', coalesce(t.classement, '[]'::jsonb)
      )
      -- Les Grands Prix sans horaire annoncé ferment la marche (point 2).
      order by g.date_course asc nulls last, g.nom asc
    ),
    '[]'::jsonb
  )
  from gps g
  left join tetes t on t.gp_id = g.id;
$$;

comment on function public.calendrier_du_championnat(uuid, uuid, integer) is
  'Grands Prix d''une saison avec, pour chacun, ce que le championnat y a marqué. Réservée au backend.';

revoke all on function public.calendrier_du_championnat(uuid, uuid, integer) from public;
revoke all on function public.calendrier_du_championnat(uuid, uuid, integer) from anon;
revoke all on function public.calendrier_du_championnat(uuid, uuid, integer) from authenticated;
grant execute on function public.calendrier_du_championnat(uuid, uuid, integer) to service_role;


-- --  3. Les pronostics d'un championnat portent désormais la voiture  ---------

-- La maquette 11 place une voiture miniature devant chaque membre. Elle vient
-- du profil (étape 8), et `pronostics_du_championnat` ne la servait pas : la
-- route des résultats aurait dû faire une seconde lecture des profils pour
-- l'obtenir, alors que la fonction joint déjà `public.profils` pour le pseudo.
--
-- **Le reste du corps est inchangé**, y compris l'ordre par `rejoint_le` et
-- l'appel à `pronostics_du_joueur`. Quatre champs s'ajoutent, aucun ne part.
--
-- `total_points` est calculé ici plutôt que additionné côté frontend pour une
-- raison de convention, pas de performance : la somme doit compter `0` pour un
-- pronostic raté et **ignorer** un pronostic non jugé, jamais le compter zéro.
-- Écrire cette règle en base une fois vaut mieux que la réécrire dans chaque
-- écran qui affiche un total.
create or replace function public.pronostics_du_championnat(p_championnat uuid, p_gp uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profil_id',  m.profil_id,
        'pseudo',     coalesce(pr.pseudo, 'Pilote'),
        'rejoint_le', m.rejoint_le,
        -- La voiture du membre. Les couleurs ne sont jamais nulles : un profil
        -- manquant retombe sur les défauts de la colonne, sans quoi le SVG
        -- afficherait des aplats transparents (même `coalesce` qu'à l'étape 8).
        'couleur1',   coalesce(pr.couleur1, '#800111'),
        'couleur2',   coalesce(pr.couleur2, '#FFFFFF'),
        'numero',     pr.numero,
        -- Ce que le membre a marqué sur CE Grand Prix. NULL tant qu'aucun de
        -- ses pronostics n'a été noté — convention de l'étape 6.
        'total_points', (
          select case when count(p.points_gagnes) > 0
                      then coalesce(sum(p.points_gagnes), 0)::integer end
          from public.pronostics p
          where p.profil_id = m.profil_id and p.gp_id = p_gp
        ),
        'pronostics', public.pronostics_du_joueur(m.profil_id, p_gp)
      )
      -- L'ordre d'inscription : c'est le 3ᵉ critère de départage de la règle
      -- 4.6, et le seul ordre stable dont on dispose avant l'étape 7.
      order by m.rejoint_le
    ),
    '[]'::jsonb
  )
  from public.membres_championnat m
  left join public.profils pr on pr.id = m.profil_id
  where m.championnat_id = p_championnat;
$$;

comment on function public.pronostics_du_championnat(uuid, uuid) is
  'Pronostics de tous les membres d''un championnat pour un GP, avec leur voiture et leur total. Réservée au backend.';

revoke all on function public.pronostics_du_championnat(uuid, uuid) from public;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from anon;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from authenticated;
grant execute on function public.pronostics_du_championnat(uuid, uuid) to service_role;
