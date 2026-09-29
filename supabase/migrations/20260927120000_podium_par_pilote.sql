-- =============================================================================
-- Migration 27 — le podium jugé pilote par pilote, conservé tel quel
-- =============================================================================
--
-- Depuis la 0.54.0, le backend juge chaque pilote du podium pour son propre
-- compte (`metier.md` §2) : l'un peut rapporter sa cote et l'autre zéro. Mais
-- la base n'en gardait que la SOMME (`pronostics.points_gagnes`) : les écrans
-- ne pouvaient montrer qu'une ligne « Norris + Hadjar — 54 pts », sans dire
-- lequel des deux avait rapporté.
--
-- Cette migration :
--
--   1. ajoute `pronostic_podium.points_gagnes_1` et `points_gagnes_2` — ce que
--      `pilote_1` et `pilote_2` ont rapporté. `NULL` tant que le pronostic
--      n'est pas jugé. Leur somme vaut toujours `pronostics.points_gagnes` ;
--   2. remplace `attribuer_points` (24) et `remplacer_verdicts` (25) : chaque
--      attribution de podium porte désormais `"podium": [g1, g2]`, écrit ici
--      dans la même transaction que le total. Une attribution sans cette clé
--      (backend antérieur à 0.80.0) laisse les deux colonnes à `NULL` ;
--   3. remplace `pronostics_du_joueur` (25) : l'objet `podium` sert les deux
--      gains, que `pronostics_du_championnat` hérite sans être remplacée ;
--   4. rattrape les podiums déjà jugés, à partir de leur total et des deux
--      cotes. Le total est celui que le backend a écrit : la déduction ne juge
--      rien, elle le répartit. Elle n'est ambiguë que si les deux cotes sont
--      égales et qu'un seul pilote a rapporté — ces lignes restent à `NULL` (les
--      écrans les disent « en attente ») jusqu'au prochain `remplacer_verdicts`
--      du GP. Aucune ligne de ce genre dans les quatre GP courus au 2026-09-26.
--
-- **Conflits d'ordre** : rejouer la 24 après celle-ci restaure un
-- `attribuer_points` qui n'écrit plus les gains par pilote ; rejouer la 25
-- restaure `remplacer_verdicts` et `pronostics_du_joueur` sans eux. Remède :
-- rejouer la 27.
--
-- Idempotente : colonnes et contraintes sous garde, fonctions remplacées,
-- rattrapage limité aux lignes encore à `NULL`.
-- =============================================================================


-- --  1. Les gains par pilote  --------------------------------------------------

alter table public.pronostic_podium add column if not exists points_gagnes_1 integer;
alter table public.pronostic_podium add column if not exists points_gagnes_2 integer;

comment on column public.pronostic_podium.points_gagnes_1 is
  'Ce que pilote_1 a rapporté. Écrit par attribuer_points / remplacer_verdicts, depuis le calcul du backend. NULL tant que le pronostic n''est pas jugé.';
comment on column public.pronostic_podium.points_gagnes_2 is
  'Ce que pilote_2 a rapporté. Même règle que points_gagnes_1.';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pronostic_podium_gains_positifs'
  ) then
    alter table public.pronostic_podium
      add constraint pronostic_podium_gains_positifs
      check (points_gagnes_1 >= 0 and points_gagnes_2 >= 0);
  end if;
end
$$;


-- --  2. `attribuer_points` — le provisoire  -------------------------------------

-- Corps de la 24, plus l'écriture des gains par pilote. Même règle que pour le
-- total : un podium déjà détaillé n'est jamais réécrit ici.
create or replace function public.attribuer_points(p_gp uuid, p_attributions jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attribues      integer;
  restants       integer;
  non_evaluables integer;
begin
  update public.pronostics p
     set points_gagnes = d.points
    from (
      select (a->>'pronostic_id')::uuid as id,
             (a->>'points')::integer    as points
      from jsonb_array_elements(coalesce(p_attributions, '[]'::jsonb)) a
      where a->>'points' is not null
    ) d
   where p.id           = d.id
     and p.gp_id        = p_gp   -- un appel ne peut noter que le GP annoncé
     and p.points_gagnes is null;

  get diagnostics attribues = row_count;

  update public.pronostics p
     set statut_evaluation = d.statut
    from (
      select (a->>'pronostic_id')::uuid as id,
             a->>'statut'               as statut
      from jsonb_array_elements(coalesce(p_attributions, '[]'::jsonb)) a
      where a->>'points' is null
        and a->>'statut' in ('en_attente', 'non_evaluable')
    ) d
   where p.id                = d.id
     and p.gp_id             = p_gp
     and p.points_gagnes     is null
     and p.statut_evaluation is distinct from d.statut;

  -- Le détail du podium DÉRIVE du pronostic parent (inchangé depuis la 6).
  update public.pronostic_podium pp
     set points_gagnes = p.points_gagnes
    from public.pronostics p
   where p.id    = pp.pronostic_id
     and p.gp_id = p_gp
     and p.type  = 'podium'
     and p.points_gagnes is not null
     and pp.points_gagnes is distinct from p.points_gagnes;

  -- Ajout de la 27 : les gains par pilote, seulement s'ils somment au total
  -- écrit — un détail qui contredirait le total ne s'écrit pas.
  update public.pronostic_podium pp
     set points_gagnes_1 = d.g1,
         points_gagnes_2 = d.g2
    from (
      select (a->>'pronostic_id')::uuid    as id,
             (a->'podium'->>0)::integer    as g1,
             (a->'podium'->>1)::integer    as g2
      from jsonb_array_elements(coalesce(p_attributions, '[]'::jsonb)) a
      where jsonb_typeof(a->'podium') = 'array'
    ) d,
    public.pronostics p
   where pp.pronostic_id = d.id
     and p.id            = d.id
     and p.gp_id         = p_gp
     and p.type          = 'podium'
     and p.points_gagnes = d.g1 + d.g2
     and pp.points_gagnes_1 is null
     and pp.points_gagnes_2 is null;

  select count(*) filter (where p.statut_evaluation = 'en_attente'),
         count(*) filter (where p.statut_evaluation = 'non_evaluable')
    into restants, non_evaluables
  from public.pronostics p
  where p.gp_id = p_gp and p.points_gagnes is null;

  return jsonb_build_object(
    'attribues', attribues,
    'restants', restants,
    'non_evaluables', non_evaluables
  );
end;
$$;

comment on function public.attribuer_points(uuid, jsonb) is
  'Écrit les points d''un GP sans jamais réécrire un pronostic déjà noté, le statut en_attente / non_evaluable des autres, et les gains par pilote des podiums. Réservée au backend.';

revoke all on function public.attribuer_points(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.attribuer_points(uuid, jsonb) to service_role;


-- --  3. `remplacer_verdicts` — le définitif et le recalcul  --------------------

-- Corps de la 25, plus les gains par pilote. Comme le total, ils sont
-- RÉÉCRITS : un podium du GP sans détail cohérent dans `p_attributions`
-- repasse à NULL plutôt que de garder un détail d'un calcul précédent.
create or replace function public.remplacer_verdicts(
  p_gp uuid,
  p_attributions jsonb,
  p_donnees jsonb default null,
  p_statut_resultats text default 'definitif'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  modifies       integer;
  attribues      integer;
  restants       integer;
  non_evaluables integer;
begin
  if p_statut_resultats not in ('provisoire', 'definitif') then
    raise exception 'Statut de résultats inconnu : %', p_statut_resultats;
  end if;

  if not exists (select 1 from public.grands_prix where id = p_gp) then
    raise exception 'Grand Prix inconnu : %', p_gp;
  end if;

  if p_donnees is not null then
    insert into public.resultats_gp (gp_id, donnees_brutes, recupere_le)
    values (p_gp, p_donnees, now())
    on conflict (gp_id) do update
      set donnees_brutes = excluded.donnees_brutes,
          recupere_le    = excluded.recupere_le;
  elsif not exists (select 1 from public.resultats_gp where gp_id = p_gp) then
    raise exception 'Aucun résultat en base pour le Grand Prix %', p_gp;
  end if;

  with verdicts as (
    select (a->>'pronostic_id')::uuid as id,
           (a->>'points')::integer    as points,
           a->>'statut'               as statut
    from jsonb_array_elements(coalesce(p_attributions, '[]'::jsonb)) a
  ),
  cibles as (
    select p.id,
           v.points,
           case
             when v.points is not null then case when v.points > 0 then 'gagne' else 'perdu' end
             when v.statut = 'non_evaluable' then 'non_evaluable'
             else 'en_attente'
           end as statut
    from public.pronostics p
    left join verdicts v on v.id = p.id
    where p.gp_id = p_gp   -- un appel ne réécrit que le GP annoncé
  )
  update public.pronostics p
     set points_gagnes     = c.points,
         statut_evaluation = c.statut
    from cibles c
   where p.id = c.id
     and (p.points_gagnes is distinct from c.points
          or p.statut_evaluation is distinct from c.statut);

  get diagnostics modifies = row_count;

  -- Le détail du podium DÉRIVE du parent, y compris quand il repasse à NULL.
  -- Ajout de la 27 : les gains par pilote, seulement s'ils somment au total.
  with details as (
    select (a->>'pronostic_id')::uuid    as id,
           (a->'podium'->>0)::integer    as g1,
           (a->'podium'->>1)::integer    as g2
    from jsonb_array_elements(coalesce(p_attributions, '[]'::jsonb)) a
    where jsonb_typeof(a->'podium') = 'array'
  ),
  cibles as (
    select p.id,
           p.points_gagnes,
           case when p.points_gagnes = d.g1 + d.g2 then d.g1 end as g1,
           case when p.points_gagnes = d.g1 + d.g2 then d.g2 end as g2
    from public.pronostics p
    left join details d on d.id = p.id
    where p.gp_id = p_gp
      and p.type  = 'podium'
  )
  update public.pronostic_podium pp
     set points_gagnes   = c.points_gagnes,
         points_gagnes_1 = c.g1,
         points_gagnes_2 = c.g2
    from cibles c
   where pp.pronostic_id = c.id
     and (pp.points_gagnes   is distinct from c.points_gagnes
          or pp.points_gagnes_1 is distinct from c.g1
          or pp.points_gagnes_2 is distinct from c.g2);

  update public.grands_prix
     set statut           = 'termine',
         statut_resultats = p_statut_resultats
   where id = p_gp;

  select count(*) filter (where p.points_gagnes is not null),
         count(*) filter (where p.statut_evaluation = 'en_attente'),
         count(*) filter (where p.statut_evaluation = 'non_evaluable')
    into attribues, restants, non_evaluables
  from public.pronostics p
  where p.gp_id = p_gp;

  return jsonb_build_object(
    'modifies', modifies,
    'attribues', attribues,
    'restants', restants,
    'non_evaluables', non_evaluables
  );
end;
$$;

comment on function public.remplacer_verdicts(uuid, jsonb, jsonb, text) is
  'Remplace, dans une seule transaction, les résultats et TOUS les verdicts d''un GP (gains par pilote des podiums compris), puis pose son statut de résultats. Calcul définitif à J+1 et recalcul admin. Réservée au backend.';

revoke all on function public.remplacer_verdicts(uuid, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.remplacer_verdicts(uuid, jsonb, jsonb, text) to service_role;


-- --  4. `pronostics_du_joueur` sert les gains par pilote  -----------------------

-- Corps de la 25, à deux champs près dans l'objet `podium`.
-- `pronostics_du_championnat` (18) l'appelle pour chaque membre et en hérite.
create or replace function public.pronostics_du_joueur(p_profil uuid, p_gp uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',      x.id,
        'type',    x.type,
        'outcome', x.id_outcome_unibet,
        'pilote',  x.pilote,
        'marche',  x.marche,
        'libelle', x.libelle_marche,
        'points',  x.points,
        'points_gagnes', x.points_gagnes,
        'statut_evaluation', x.statut_evaluation,
        'podium',  x.podium
      )
      order by
        case x.type when 'vainqueur' then 1 when 'podium' then 2 else 3 end,
        x.pilote
    ),
    '[]'::jsonb
  )
  from (
    select
      p.id,
      p.type,
      p.id_outcome_unibet,
      p.points_gagnes,
      p.statut_evaluation,
      c.pilote,
      c.marche,
      c.libelle_marche,
      c.valeur as points,
      case
        when p.type = 'podium' then jsonb_build_object(
          'pilote_1', pp.pilote_1,
          'pilote_2', pp.pilote_2,
          'nom_1',    c.pilote,
          'nom_2',    c2.pilote,
          'points_2', c2.valeur,
          -- Ajout de la 27.
          'points_gagnes_1', pp.points_gagnes_1,
          'points_gagnes_2', pp.points_gagnes_2
        )
      end as podium
    from public.pronostics p
    left join public.cotes c
      on c.gp_id = p.gp_id and c.id_outcome_unibet = p.id_outcome_unibet
    left join public.pronostic_podium pp
      on pp.pronostic_id = p.id
    left join public.cotes c2
      on c2.gp_id = p.gp_id and c2.id_outcome_unibet = pp.pilote_2
    where p.profil_id = p_profil
      and p.gp_id     = p_gp
  ) x;
$$;

comment on function public.pronostics_du_joueur(uuid, uuid) is
  'Pronostics d''un joueur sur un GP, rapprochés des cotes, avec points gagnés, statut d''évaluation et gains par pilote du podium. Réservée au backend.';

revoke all on function public.pronostics_du_joueur(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pronostics_du_joueur(uuid, uuid) to service_role;


-- --  5. Rattrapage des podiums déjà jugés  -------------------------------------

-- Le total a été écrit par le backend ; chaque gain vaut la cote de son pilote
-- ou zéro. Le total désigne donc les gains sans ambiguïté, sauf si les deux
-- cotes sont égales et qu'un seul pilote a rapporté — laissé à NULL.
update public.pronostic_podium pp
   set points_gagnes_1 = x.g1,
       points_gagnes_2 = x.g2
  from (
    select pp2.pronostic_id,
           case
             when p.points_gagnes = 0                         then 0
             when p.points_gagnes = c1.valeur + c2.valeur     then c1.valeur
             when c1.valeur <> c2.valeur
                  and p.points_gagnes = c1.valeur             then c1.valeur
             when c1.valeur <> c2.valeur
                  and p.points_gagnes = c2.valeur             then 0
           end as g1,
           case
             when p.points_gagnes = 0                         then 0
             when p.points_gagnes = c1.valeur + c2.valeur     then c2.valeur
             when c1.valeur <> c2.valeur
                  and p.points_gagnes = c1.valeur             then 0
             when c1.valeur <> c2.valeur
                  and p.points_gagnes = c2.valeur             then c2.valeur
           end as g2
    from public.pronostic_podium pp2
    join public.pronostics p
      on p.id = pp2.pronostic_id
    join public.cotes c1
      on c1.gp_id = p.gp_id and c1.id_outcome_unibet = pp2.pilote_1
    join public.cotes c2
      on c2.gp_id = p.gp_id and c2.id_outcome_unibet = pp2.pilote_2
    where p.type = 'podium'
      and p.points_gagnes is not null
  ) x
 where pp.pronostic_id = x.pronostic_id
   and x.g1 is not null
   and x.g2 is not null
   and pp.points_gagnes_1 is null
   and pp.points_gagnes_2 is null;


-- --  6. Contrôle  --------------------------------------------------------------

do $$
declare
  incoherents integer;
  detailles   integer;
  sans_detail integer;
begin
  select count(*) into incoherents
  from public.pronostic_podium pp
  join public.pronostics p on p.id = pp.pronostic_id
  where pp.points_gagnes_1 is not null
    and (p.points_gagnes is null
         or pp.points_gagnes_2 is null
         or pp.points_gagnes_1 + pp.points_gagnes_2 <> p.points_gagnes);
  if incoherents > 0 then
    raise exception '% podium(s) dont les gains par pilote contredisent le total.', incoherents;
  end if;

  select count(*) filter (where pp.points_gagnes_1 is not null),
         count(*) filter (where pp.points_gagnes_1 is null)
    into detailles, sans_detail
  from public.pronostic_podium pp
  join public.pronostics p on p.id = pp.pronostic_id
  where p.points_gagnes is not null;

  raise notice 'Podiums jugés : % détaillé(s) pilote par pilote, % sans détail.',
    detailles, sans_detail;
end
$$;

select g.nom,
       count(*) filter (where pp.points_gagnes_1 is not null) as podiums_detailles,
       count(*) filter (where p.points_gagnes is not null
                          and pp.points_gagnes_1 is null)     as podiums_sans_detail
from public.pronostic_podium pp
join public.pronostics p on p.id = pp.pronostic_id
join public.grands_prix g on g.id = p.gp_id
group by g.nom, g.date_course
order by g.date_course;
