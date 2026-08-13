-- =============================================================================
-- Correctif — survie d'un championnat à son créateur, et suppression d'un
-- championnat resté sans membre
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- comme les trois migrations précédentes.
--
-- Deux règles métier tranchées après l'étape 4, et laissées ouvertes jusqu'ici
-- par la migration `20260810163435_championnats.sql` :
--
--   1. Supprimer un compte ne dissout plus les championnats qu'il a créés. Le
--      championnat survit, son `cree_par` passe à NULL.
--   2. Un championnat que son dernier membre quitte est supprimé
--      automatiquement, au lieu de rester en base — inaccessible à tous, mais
--      toujours rejoignable par son code.
--
-- Rien d'autre ne change : aucune colonne ajoutée, aucune politique RLS
-- retouchée, aucun appel du backend modifié.
--
-- La migration est idempotente : la rejouer ne casse rien.
-- =============================================================================

-- --  1. Le créateur peut disparaître, pas le championnat  --------------------

-- La migration de l'étape 3 déclarait `cree_par` en `not null` et sans clause
-- `on delete`, donc en RESTRICT implicite : supprimer le compte du créateur
-- échouait, purement et simplement. C'était un garde-fou volontaire — mieux
-- valait un refus franc qu'une cascade emportant le championnat de tous les
-- autres membres — en attendant la règle. La voici : le championnat survit et
-- perd son créateur.
--
-- L'ordre compte. `on delete set null` sur une colonne restée `not null` est
-- accepté à la création de la contrainte, mais fait échouer la suppression du
-- compte le jour venu : la contrainte ne peut pas écrire le NULL qu'elle
-- promet. On lève donc le `not null` d'abord.
alter table public.championnats
  alter column cree_par drop not null;

comment on column public.championnats.cree_par is
  'Créateur du championnat. NULL si le compte a été supprimé : le championnat survit à son créateur.';

-- La contrainte de clé étrangère a été posée en ligne (`references auth.users`)
-- et porte donc un nom attribué par PostgreSQL. On ne le suppose pas : on
-- retrouve la contrainte par la colonne qu'elle porte, quel que soit son nom.
-- Celle qui a déjà la bonne règle (`confdeltype = 'n'`, SET NULL) est laissée
-- en place — c'est ce qui rend cette section rejouable sans rien reconstruire.
do $$
declare
  colonne   smallint;
  existante record;
begin
  select attnum into colonne
  from pg_attribute
  where attrelid = 'public.championnats'::regclass
    and attname = 'cree_par'
    and not attisdropped;

  for existante in
    select conname, confdeltype
    from pg_constraint
    where conrelid = 'public.championnats'::regclass
      and contype = 'f'
      and colonne = any (conkey)
  loop
    if existante.confdeltype = 'n' then
      -- Déjà en ON DELETE SET NULL : migration déjà appliquée, rien à faire.
      continue;
    end if;

    execute format(
      'alter table public.championnats drop constraint %I', existante.conname
    );
    raise notice 'Contrainte % retirée (ancienne règle de suppression).',
      existante.conname;
  end loop;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.championnats'::regclass
      and contype = 'f'
      and colonne = any (conkey)
  ) then
    alter table public.championnats
      add constraint championnats_cree_par_fkey
      foreign key (cree_par) references auth.users (id)
      on delete set null;
  end if;
end;
$$;

-- Note sur la RLS : la politique « Seul le createur supprime » compare
-- `cree_par` à `auth.uid()`. Sur un championnat orphelin, `cree_par` vaut NULL,
-- la comparaison ne vaut jamais vrai, et plus personne ne peut supprimer le
-- championnat depuis le frontend. C'est le comportement voulu — un membre
-- ordinaire n'a pas à emporter le championnat des autres. Le championnat
-- disparaîtra de lui-même quand son dernier membre partira, par le trigger
-- ci-dessous.

-- --  2. Un championnat sans membre est supprimé  -----------------------------

-- Le départ du dernier membre laissait jusqu'ici un championnat fantôme : plus
-- personne ne le voyait (la politique de lecture exige d'en être membre), mais
-- son code d'invitation restait valide et le rendait rejoignable.
--
-- `security definer` est indispensable : le trigger s'exécute sous l'identité
-- de celui qui quitte le championnat, et la politique « Seul le createur
-- supprime » l'empêcherait d'en effacer la ligne. La fonction appartient au
-- rôle qui joue la migration (`postgres`, propriétaire des tables), lequel
-- n'est pas soumis à la RLS. Le nettoyage n'ouvre aucun droit nouveau : il ne
-- supprime qu'un championnat déjà vide, et seulement en réaction à un départ.
create or replace function public.supprimer_championnat_vide()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.membres_championnat m
    where m.championnat_id = old.championnat_id
  ) then
    delete from public.championnats c
    where c.id = old.championnat_id;
  end if;

  -- Trigger AFTER : la valeur de retour est ignorée par PostgreSQL.
  return null;
end;
$$;

comment on function public.supprimer_championnat_vide() is
  'Supprime le championnat dont la dernière ligne de membres_championnat vient de disparaître.';

-- Un trigger n'exige l'autorisation d'exécuter sa fonction qu'au moment où on
-- le crée, jamais à chaque déclenchement : la révocation ci-dessous ne le gêne
-- pas, et ferme la fonction à un appel direct.
revoke all on function public.supprimer_championnat_vide() from public;

drop trigger if exists membres_championnat_supprime_vide on public.membres_championnat;
create trigger membres_championnat_supprime_vide
  after delete on public.membres_championnat
  for each row
  execute function public.supprimer_championnat_vide();

-- Pourquoi AFTER et FOR EACH ROW, et pourquoi aucun garde-fou de profondeur :
--
--   * AFTER — un trigger BEFORE compterait les membres avant que la ligne ne
--     soit retirée : le dernier départ trouverait toujours un membre restant,
--     et le championnat ne serait jamais supprimé.
--   * FOR EACH ROW — la suppression peut porter sur plusieurs lignes à la fois
--     (compte supprimé, membre de plusieurs championnats). Chaque championnat
--     concerné doit être examiné pour lui-même.
--   * Aucun `pg_trigger_depth()` — la suppression d'un compte fait cascader
--     `membres_championnat` puis déclenche ce trigger au niveau 1. Le brider
--     sur la profondeur empêcherait précisément le cas qui l'a motivé.
--
-- La récursion, elle, s'arrête d'elle-même : supprimer le championnat fait
-- cascader ses lignes de membres, le trigger se redéclenche, et son `delete`
-- ne trouve plus la ligne — déjà effacée par la commande en cours. Zéro ligne
-- touchée, la chaîne s'arrête là.

-- --  3. Reprise de l'existant  -----------------------------------------------

-- Les championnats déjà vidés de leurs membres avant l'arrivée du trigger : la
-- règle leur est appliquée une fois, à la main. Ils ne sont lisibles par
-- personne, seul leur code d'invitation les gardait accessibles.
do $$
declare
  supprimes integer;
begin
  delete from public.championnats c
  where not exists (
    select 1
    from public.membres_championnat m
    where m.championnat_id = c.id
  );

  get diagnostics supprimes = row_count;

  if supprimes > 0 then
    raise notice 'Championnats sans aucun membre supprimés : %', supprimes;
  end if;
end;
$$;
