-- =============================================================================
-- Le calendrier d'un championnat sert l'heure des qualifications
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les douze migrations précédentes. Elle ne crée AUCUNE table, n'ajoute
-- AUCUNE colonne et ne touche à AUCUNE donnée : elle remplace une fonction pour
-- lui faire servir un champ de plus.
--
-- Elle suppose appliquées :
--   - la 10 (`calendrier_du_championnat`, qu'elle remplace),
--   - la 11 (`grands_prix.date_qualifications`, qu'elle lit).
--
-- ATTENTION À L'ORDRE. Rejouer la 10 après celle-ci restaurerait sa version
-- d'avant, et le calendrier d'un championnat perdrait `date_qualifications` —
-- sans rien casser d'autre : le frontend se ferme sur un champ absent, donc le
-- bouton « Pronostiquer » disparaîtrait au lieu d'apparaître à tort. Si la 10
-- est rejouée pour une raison quelconque, rejouer celle-ci derrière. C'est le
-- même piège que « rejouer la 5 après la 10 », déjà documenté au CLAUDE.md.
--
-- La migration est idempotente : la rejouer ne casse rien.
--
--
-- POURQUOI CE CHAMP
--
-- L'écran de calendrier (maquette 15) ne propose « Pronostiquer » que sur un
-- Grand Prix dont les cotes sont **arrêtées**, et cela demande DEUX conditions
-- réunies : le statut vaut `cotes_figees`, et les qualifications sont passées.
--
-- Le statut seul ne suffit pas. `POST /scraper/declencher` fige les cotes des
-- Grands Prix scrapés avec succès (étape 11) et peut être appelé n'importe
-- quand : un essai passé un mardi, sans `?figer=false`, arrête les cotes sur une
-- grille de départ qui n'existe pas encore. C'est exactement ce qui s'est
-- produit sur le GP des Pays-Bas, constaté en base à la version `0.38.0` —
-- statut `cotes_figees` deux jours avant des qualifications annoncées au 22 août.
-- L'heure des qualifications, elle, ne se laisse pas avancer par un `curl` :
-- elle vient du programme d'Unibet, ou du repli `date_course - 22h` du scraper.
--
-- C'est la règle 4.3 lue jusqu'au bout : tout le monde pronostique avec les
-- mêmes cotes, sur une grille déjà définitive.
--
--
-- CE QUI CHANGE, ET CE QUI NE CHANGE PAS
--
-- **Un seul champ s'ajoute au JSON servi. Aucun ne part, et le corps de la
-- fonction est inchangé par ailleurs** — les trois décisions documentées par la
-- migration 10 tiennent toutes :
--
--   1. le rang d'un Grand Prix se calcule avec `rank` et non `row_number` ;
--   2. un Grand Prix sans date annoncée est servi quand même, en fin de liste ;
--   3. `mes_points` vaut NULL, jamais `0`, quand rien n'a été noté.
--
-- La signature ne bouge pas non plus : ni le nom, ni les paramètres, ni le type
-- de retour. Les droits n'ont donc pas à être réaccordés — un `create or replace`
-- les conserve — mais ils sont réaffirmés en fin de fichier pour que la migration
-- décrive complètement l'état qu'elle laisse.
--
-- `date_qualifications` est nullable en base (migration 11), et le reste ici :
-- Unibet publie parfois un Grand Prix avant d'en annoncer le programme. Le
-- frontend traite l'absence comme « pas encore arrêté » et retire le bouton —
-- on se ferme sur une donnée qu'on n'a pas, on ne s'ouvre jamais.
-- =============================================================================


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
  --
  -- `date_qualifications` voyage avec elle. Elle ne participe à AUCUN filtre ni
  -- à aucun tri : un Grand Prix dont le programme n'est pas annoncé reste servi,
  -- exactement comme un Grand Prix sans date de course (point 2 de la migration
  -- 10). Un Grand Prix manquant dans un calendrier se voit tout de suite.
  gps as (
    select g.id, g.nom, g.date_course, g.date_qualifications, g.statut
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
        -- LE SEUL CHAMP AJOUTÉ PAR CETTE MIGRATION. Le frontend le lit avec le
        -- statut : les deux ensemble disent si les cotes sont vraiment arrêtées.
        'date_qualifications', g.date_qualifications,
        'statut',      g.statut,
        -- « Cotes disponibles » se lit dans `cotes`, jamais dans le statut : un
        -- GP peut parfaitement avoir ses cotes en base en étant resté `a_venir`,
        -- et l'inverse — figé sans que le programme soit couru — est précisément
        -- ce que `date_qualifications` permet désormais de distinguer.
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
        -- et « zéro » ne se disent pas pareil.
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
      -- Les Grands Prix sans horaire annoncé ferment la marche.
      order by g.date_course asc nulls last, g.nom asc
    ),
    '[]'::jsonb
  )
  from gps g
  left join tetes t on t.gp_id = g.id;
$$;

comment on function public.calendrier_du_championnat(uuid, uuid, integer) is
  'Grands Prix d''une saison avec, pour chacun, ce que le championnat y a marqué. Porte l''heure des qualifications. Réservée au backend.';

revoke all on function public.calendrier_du_championnat(uuid, uuid, integer) from public;
revoke all on function public.calendrier_du_championnat(uuid, uuid, integer) from anon;
revoke all on function public.calendrier_du_championnat(uuid, uuid, integer) from authenticated;
grant execute on function public.calendrier_du_championnat(uuid, uuid, integer) to service_role;
