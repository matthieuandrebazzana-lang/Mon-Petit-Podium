-- =============================================================================
--  Migration 36 — Choix de l'administrateur pour un libellé non reconnu
-- =============================================================================
--
-- `bugs-connus.md` §44, `decisions.md` §31. Le backend 0.88.0 reconnaît seul un
-- remplaçant d'un week-end (engagés d'OpenF1, « Nom, Prénom », initiales…). Ce
-- qui reste introuvable ou ambigu devient une alerte que l'administrateur
-- résout dans l'app en choisissant l'engagé ; le GP est alors recalculé.
--
--   1. `correspondances_manuelles` — le choix, par GP et par libellé normalisé
--      (`points.normaliser`). Un rattachement rejoué le relit : il ne l'efface
--      pas, contrairement aux identifiants des cotes qu'il réécrit ;
--   2. le type d'alerte `pronostics_en_attente` — les pronostics restés en
--      attente pour une autre raison qu'un libellé (qualifications absentes,
--      écart illisible…) : plus aucun ne reste en attente sans signal ;
--   3. `rattacher_issues` remplacée : l'alerte de libellé garde sa raison
--      (« Ambigu : n°… », « Pilote non engagé ce week-end… ») dans
--      `derniere_erreur`.
--
-- **Conflit d'ordre** : `rattacher_issues` (migration 26) est remplacée.
-- Rejouer la 26 après celle-ci perd la raison des alertes — rejouer la 36.
--
-- À appliquer AVANT ou APRÈS le backend 0.88.0 : sans elle, la résolution
-- répond 503, l'alerte `pronostics_en_attente` est refusée par la base (seul
-- le journal la garde) et le reste fonctionne.
--
-- Idempotente.
-- =============================================================================


-- --  1. Les choix de l'administrateur  ----------------------------------------

create table if not exists public.correspondances_manuelles (
  gp_id         uuid not null references public.grands_prix (id) on delete cascade,
  -- Le libellé Unibet normalisé : minuscules, lettres et chiffres sans accents.
  cle           text not null,
  libelle       text not null,
  numero_pilote integer,
  ecurie_id     text,
  choisi_par    uuid references public.profils (id) on delete set null,
  choisi_le     timestamptz not null default now(),
  primary key (gp_id, cle),
  constraint correspondances_manuelles_un_choix
    check ((numero_pilote is null) <> (ecurie_id is null)),
  constraint correspondances_manuelles_numero_valide
    check (numero_pilote is null or numero_pilote between 1 and 99)
);

comment on table public.correspondances_manuelles is
  'Libellé Unibet non reconnu → engagé choisi par un administrateur, pour un GP. Lu par le rattachement des issues avant la règle de noms.';

-- Service seul, comme `alertes_admin` : écrite et lue par le backend.
alter table public.correspondances_manuelles enable row level security;
revoke all on table public.correspondances_manuelles from anon, authenticated;
grant select, insert, update, delete on table public.correspondances_manuelles to service_role;


-- --  2. Le nouveau type d'alerte  ---------------------------------------------

alter table public.alertes_admin
  drop constraint if exists alertes_admin_type_valide;

alter table public.alertes_admin
  add constraint alertes_admin_type_valide
  check (type in (
    'libelle_non_reconnu',
    'rattachement_impossible',
    'definitif_en_echec',
    'grand_prix_ambigu',
    'pronostics_en_attente'
  ));


-- --  3. rattacher_issues garde la raison  --------------------------------------

create or replace function public.rattacher_issues(
  p_gp uuid,
  p_rattachements jsonb,
  p_non_reconnus jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rattachees integer;
  v_non_reconnues integer;
begin
  update public.cotes c
     set numero_pilote = r.numero_pilote,
         ecurie_id     = r.ecurie_id
    from (
      select c2.id,
             (e ->> 'numero_pilote')::integer as numero_pilote,
             nullif(e ->> 'ecurie_id', '')    as ecurie_id
        from public.cotes c2
        left join jsonb_array_elements(coalesce(p_rattachements, '[]'::jsonb)) e
          on e ->> 'id_outcome_unibet' = c2.id_outcome_unibet
       where c2.gp_id = p_gp
    ) r
   where c.id = r.id;

  select count(*) into v_rattachees
    from public.cotes
   where gp_id = p_gp and (numero_pilote is not null or ecurie_id is not null);

  delete from public.alertes_admin
   where gp_id = p_gp
     and type in ('libelle_non_reconnu', 'rattachement_impossible');

  insert into public.alertes_admin (gp_id, type, cle, marche, libelle, derniere_erreur)
  select distinct on (e ->> 'id_outcome_unibet')
         p_gp,
         'libelle_non_reconnu',
         coalesce(e ->> 'id_outcome_unibet', ''),
         e ->> 'marche',
         e ->> 'libelle',
         left(e ->> 'raison', 1000)
    from jsonb_array_elements(coalesce(p_non_reconnus, '[]'::jsonb)) e;

  get diagnostics v_non_reconnues = row_count;

  return jsonb_build_object('rattachees', v_rattachees, 'non_reconnues', v_non_reconnues);
end;
$$;

revoke all on function public.rattacher_issues(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.rattacher_issues(uuid, jsonb, jsonb) to service_role;


-- --  4. Contrôle  -------------------------------------------------------------

do $$
begin
  if to_regclass('public.correspondances_manuelles') is null then
    raise exception 'Migration 36 : table correspondances_manuelles absente.';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'correspondances_manuelles'
  ) then
    raise exception 'Migration 36 : correspondances_manuelles ne doit porter aucune politique RLS.';
  end if;
end
$$;
