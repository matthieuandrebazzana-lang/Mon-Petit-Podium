-- =============================================================================
-- Migration 26 — identifiants canoniques des issues, alertes d'administration
-- =============================================================================
--
-- `docs/audit-evaluation.md` §5.1. Jusqu'ici `cotes` ne portait qu'un libellé
-- (« AK.Antonelli », « Red Bull ») et tout le rapprochement avec OpenF1 se
-- faisait le soir de la course. Un libellé non reconnu ne se voyait qu'alors.
--
-- Désormais le rapprochement est fait AU FIGEAGE des cotes (qualifications
-- + 2 h, l'ouverture des pronostics), contre les engagés de la session de
-- qualification d'OpenF1 :
--
--   1. `cotes.numero_pilote` et `cotes.ecurie_id` — l'engagé que désigne une
--      issue « pilote » ou « écurie ». `NULL` pour les issues qui n'en
--      désignent pas (oui/non, tranches d'écart, nationalités), pour les cotes
--      d'avant cette migration, et pour les issues non reconnues. Le calcul
--      retombe alors sur le libellé ;
--   2. `alertes_admin` — ce que le profil admin doit voir sans lire les logs :
--      libellé non reconnu au figeage, rattachement impossible (OpenF1 muette
--      au figeage), calcul définitif en échec répété (`roadmap.md` §3.17) ;
--   3. `rattacher_issues` — pose les identifiants d'un GP et remplace ses
--      alertes de libellé, une transaction ;
--   4. `noter_echec_definitif` — incrémente le compteur d'échecs du définitif.
--
-- **À appliquer AVANT de déployer le backend 0.79.0.** Le backend tolère son
-- absence (figeage non bloqué, calcul par libellé, alertes vides), mais n'écrit
-- alors aucun identifiant. Ne remplace aucune fonction existante : aucun
-- conflit d'ordre.
--
-- Idempotente : colonnes, table et contraintes sous garde, fonctions remplacées.
-- =============================================================================


-- --  1. Identifiants sur les cotes  ------------------------------------------

alter table public.cotes add column if not exists numero_pilote integer;
alter table public.cotes add column if not exists ecurie_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'cotes_numero_pilote_valide'
  ) then
    alter table public.cotes
      add constraint cotes_numero_pilote_valide
      check (numero_pilote is null or numero_pilote between 1 and 99);
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'cotes_ecurie_id_valide'
  ) then
    alter table public.cotes
      add constraint cotes_ecurie_id_valide
      check (ecurie_id is null or char_length(ecurie_id) between 1 and 64);
  end if;
end
$$;

comment on column public.cotes.numero_pilote is
  'Numéro OpenF1 du pilote que désigne l''issue, posé au figeage. NULL : pas une issue pilote, cote antérieure, ou libellé non reconnu.';
comment on column public.cotes.ecurie_id is
  'Nom OpenF1 de l''écurie en slug (« red-bull-racing »), posé au figeage. NULL : pas une issue écurie, cote antérieure, ou libellé non reconnu.';


-- --  2. Alertes d'administration  ---------------------------------------------

create table if not exists public.alertes_admin (
  id              uuid primary key default gen_random_uuid(),
  gp_id           uuid not null references public.grands_prix (id) on delete cascade,
  type            text not null,
  -- Ce qui distingue deux alertes du même type sur un GP : l'issue pour un
  -- libellé non reconnu, vide pour les autres.
  cle             text not null default '',
  marche          text,
  libelle         text,
  tentatives      integer not null default 1,
  derniere_erreur text,
  cree_le         timestamptz not null default now(),
  modifie_le      timestamptz not null default now(),
  constraint alertes_admin_unique unique (gp_id, type, cle)
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'alertes_admin_type_valide'
  ) then
    alter table public.alertes_admin
      add constraint alertes_admin_type_valide
      check (type in ('libelle_non_reconnu', 'rattachement_impossible', 'definitif_en_echec'));
  end if;
end
$$;

-- Service seul : aucune politique, et la table n'est lue que par le backend
-- (`GET /admin/alertes`, garde `exiger_admin`).
alter table public.alertes_admin enable row level security;
revoke all on table public.alertes_admin from anon, authenticated;


-- --  3. rattacher_issues  -----------------------------------------------------

-- `p_rattachements` : [{id_outcome_unibet, numero_pilote, ecurie_id}, …]
-- `p_non_reconnus`  : [{id_outcome_unibet, marche, libelle}, …]
--
-- Les identifiants des issues absentes de `p_rattachements` repassent à NULL :
-- un second rattachement du même GP remplace le premier, il ne s'y ajoute pas.
-- Les alertes de libellé et de rattachement du GP sont remplacées de même.
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

  insert into public.alertes_admin (gp_id, type, cle, marche, libelle)
  select distinct on (e ->> 'id_outcome_unibet')
         p_gp,
         'libelle_non_reconnu',
         coalesce(e ->> 'id_outcome_unibet', ''),
         e ->> 'marche',
         e ->> 'libelle'
    from jsonb_array_elements(coalesce(p_non_reconnus, '[]'::jsonb)) e;

  get diagnostics v_non_reconnues = row_count;

  return jsonb_build_object('rattachees', v_rattachees, 'non_reconnues', v_non_reconnues);
end;
$$;

revoke all on function public.rattacher_issues(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.rattacher_issues(uuid, jsonb, jsonb) to service_role;


-- --  4. noter_echec_definitif  ------------------------------------------------

-- Rend le nombre d'échecs consécutifs. Le succès du définitif supprime la ligne
-- (le backend, par PostgREST) : le compteur repart de zéro.
create or replace function public.noter_echec_definitif(p_gp uuid, p_erreur text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tentatives integer;
begin
  insert into public.alertes_admin (gp_id, type, cle, tentatives, derniere_erreur)
  values (p_gp, 'definitif_en_echec', '', 1, left(p_erreur, 1000))
  on conflict (gp_id, type, cle) do update
     set tentatives      = public.alertes_admin.tentatives + 1,
         derniere_erreur = excluded.derniere_erreur,
         modifie_le      = now()
  returning tentatives into v_tentatives;
  return v_tentatives;
end;
$$;

revoke all on function public.noter_echec_definitif(uuid, text) from public, anon, authenticated;
grant execute on function public.noter_echec_definitif(uuid, text) to service_role;


-- --  5. Contrôle  -------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cotes' and column_name = 'numero_pilote'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'cotes' and column_name = 'ecurie_id'
  ) then
    raise exception 'Migration 26 : colonnes d''identifiant absentes de public.cotes.';
  end if;
  if exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'alertes_admin'
  ) then
    raise exception 'Migration 26 : alertes_admin ne doit porter aucune politique RLS.';
  end if;
end
$$;
