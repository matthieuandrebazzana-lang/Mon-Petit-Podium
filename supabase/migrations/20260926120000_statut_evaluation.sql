-- =============================================================================
-- Migration 24 — statut d'évaluation des pronostics
-- =============================================================================
--
-- `points_gagnes = NULL` confondait deux états : « pas encore jugé, une donnée
-- manque » (rattrapable au prochain passage du job) et « aucun évaluateur ne
-- porte ce marché » (rattrapable seulement par une livraison de code). Il
-- fallait relire les logs pour les distinguer (`docs/audit-evaluation.md` §5.2).
--
-- Cette migration ajoute `pronostics.statut_evaluation`, distinct de
-- `points_gagnes` :
--
--   | Statut          | `points_gagnes` | Sens                                   |
--   |-----------------|-----------------|----------------------------------------|
--   | `en_attente`    | NULL            | donnée manquante, rattrapable          |
--   | `non_evaluable` | NULL            | aucun évaluateur pour ce marché        |
--   | `gagne`         | > 0             | réussi                                 |
--   | `perdu`         | 0               | raté                                   |
--
-- **`gagne` et `perdu` ne s'écrivent jamais : ils se DÉRIVENT de
-- `points_gagnes`**, par le trigger `pronostics_statut_derive`. Un seul
-- propriétaire pour une seule question : un code qui remet les points à NULL
-- (`?forcer=true`, migration 15 rejouée) ramène le statut à `en_attente` sans
-- avoir à le savoir. Seul `non_evaluable` est posé explicitement, par
-- `attribuer_points`.
--
-- **À appliquer AVANT de déployer le backend 0.77.0**, qui envoie un `statut`
-- à `attribuer_points`. Dans l'ordre inverse rien ne casse — l'ancienne
-- fonction ignore la clé — mais aucun pronostic n'est marqué `non_evaluable`.
--
-- Idempotente : colonne, contrainte et trigger sont posés sous garde, la
-- fonction est remplacée, le rattrapage des statuts ne touche que les lignes
-- incohérentes.
--
-- > ### Conflit d'ordre introduit
-- >
-- > | Si vous rejouez… | …vous perdez | Remède |
-- > |---|---|---|
-- > | **6** après **24** | l'écriture du statut `non_evaluable` par `attribuer_points` | rejouer 24 |
-- >
-- > Rien d'autre : `gagne`, `perdu` et `en_attente` restent tenus par le
-- > trigger, que la 6 ne connaît pas.
-- =============================================================================


-- --  1. La colonne  ------------------------------------------------------------

alter table public.pronostics
  add column if not exists statut_evaluation text not null default 'en_attente';

comment on column public.pronostics.statut_evaluation is
  'en_attente | non_evaluable | gagne | perdu. gagne et perdu sont dérivés de points_gagnes par trigger ; seul non_evaluable est écrit, par attribuer_points.';


-- --  2. Les lignes existantes  -------------------------------------------------

-- Dérivé des points déjà écrits. `non_evaluable` n'est pas deviné ici : le
-- prochain passage du job le pose sur les pronostics concernés.
update public.pronostics
   set statut_evaluation = case
         when points_gagnes > 0 then 'gagne'
         when points_gagnes = 0 then 'perdu'
         else 'en_attente'
       end
 where statut_evaluation is distinct from case
         when points_gagnes > 0 then 'gagne'
         when points_gagnes = 0 then 'perdu'
         else 'en_attente'
       end
   and not (points_gagnes is null and statut_evaluation = 'non_evaluable');


-- --  3. Le trigger de dérivation  ----------------------------------------------

create or replace function public.pronostics_statut_derive()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.points_gagnes is not null then
    new.statut_evaluation := case when new.points_gagnes > 0 then 'gagne' else 'perdu' end;
  elsif new.statut_evaluation is null or new.statut_evaluation in ('gagne', 'perdu') then
    -- Points remis à NULL : le verdict tombe, le pronostic redevient à juger.
    new.statut_evaluation := 'en_attente';
  end if;
  return new;
end;
$$;

drop trigger if exists pronostics_statut_derive on public.pronostics;
create trigger pronostics_statut_derive
  before insert or update of points_gagnes, statut_evaluation on public.pronostics
  for each row execute function public.pronostics_statut_derive();


-- --  4. La contrainte  ---------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pronostics_statut_evaluation_coherent'
  ) then
    alter table public.pronostics
      add constraint pronostics_statut_evaluation_coherent check (
           (statut_evaluation = 'gagne' and points_gagnes > 0)
        or (statut_evaluation = 'perdu' and points_gagnes = 0)
        or (statut_evaluation in ('en_attente', 'non_evaluable') and points_gagnes is null)
      );
  end if;
end
$$;


-- --  5. `attribuer_points` écrit aussi `non_evaluable` et `en_attente`  ---------

-- Reçoit `[{"pronostic_id": "...", "points": 28, "statut": "gagne"}, ...]`.
--
-- - `points` non nul : écrit sur un pronostic encore à NULL, comme avant. Le
--   statut `gagne` / `perdu` suit par le trigger — celui transmis est ignoré.
-- - `points` nul : seul `statut` est lu, `en_attente` ou `non_evaluable`, et
--   n'est posé que sur un pronostic encore à NULL. C'est ce qui permet à un
--   pronostic `non_evaluable` de repasser `en_attente` quand son évaluateur
--   arrive mais que la donnée manque encore.
--
-- L'idempotence ne change pas : un pronostic noté n'est jamais réécrit.
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
  'Écrit les points d''un GP sans jamais réécrire un pronostic déjà noté, et le statut en_attente / non_evaluable des autres. Réservée au backend.';

revoke all on function public.attribuer_points(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.attribuer_points(uuid, jsonb) to service_role;


-- --  6. Contrôle  --------------------------------------------------------------

do $$
declare
  incoherents integer;
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'pronostics_statut_derive'
      and tgrelid = 'public.pronostics'::regclass
  ) then
    raise exception 'Trigger pronostics_statut_derive absent.';
  end if;

  select count(*) into incoherents
  from public.pronostics
  where not (
       (statut_evaluation = 'gagne' and points_gagnes > 0)
    or (statut_evaluation = 'perdu' and points_gagnes = 0)
    or (statut_evaluation in ('en_attente', 'non_evaluable') and points_gagnes is null)
  );
  if incoherents > 0 then
    raise exception '% pronostic(s) au statut incohérent avec points_gagnes.', incoherents;
  end if;
end
$$;
