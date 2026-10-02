-- =============================================================================
--  Migration 29 — Rattachement d'un Grand Prix par sa date de course
-- =============================================================================
--
-- Le 1er octobre 2026, Unibet a publié « GP Bahrein » au 4 octobre : la course
-- de Bahreïn, délocalisée à Sepang, à la place de la ligne manuelle « GP
-- Malaisie » (migration 19). Le scraper rapprochait les lignes manuelles par le
-- NOM : il n'a rien reconnu et a inséré une seconde ligne pour le même
-- week-end. Le doublon a été résorbé à la main par `adopter_grand_prix`.
--
-- Le backend `0.82.1` rapproche désormais par la DATE de course — une seule
-- course par week-end —, le nom ne servant plus que de repli. Quand le cas
-- reste ambigu (deux candidats ou plus), il ne crée rien et remonte une alerte
-- admin. Cette alerte n'a, par construction, aucun Grand Prix auquel se
-- rattacher. D'où cette migration :
--
--   1. `alertes_admin.gp_id` devient nullable ;
--   2. l'unicité `(gp_id, type, cle)` passe en `nulls not distinct`, sans quoi
--      deux alertes sans GP ne se rencontreraient jamais et l'upsert du
--      backend en empilerait une par passage du scraper ;
--   3. le type `grand_prix_ambigu` entre dans la liste fermée ;
--   4. `adopter_grand_prix` compte aussi `alertes_admin` avant de supprimer la
--      ligne manuelle — c'était la cinquième table fille, oubliée.
--
-- **Conflit d'ordre** : `adopter_grand_prix` est remplacée. Rejouer la 19
-- après celle-ci restaure le comptage à quatre tables — rejouer la 29.
--
-- Idempotente. À appliquer AVANT ou APRÈS le backend `0.82.1`, indifféremment :
-- tant qu'elle manque, l'écriture de l'alerte échoue et seul le journal la
-- garde (`unibet._alerter` est best effort) ; le refus de créer une ligne,
-- lui, ne dépend pas de la base.
-- =============================================================================


-- --  1. gp_id nullable  ---------------------------------------------------------

alter table public.alertes_admin
  alter column gp_id drop not null;

comment on column public.alertes_admin.gp_id is
  'Grand Prix concerné. NULL pour une alerte grand_prix_ambigu : le scraper a refusé de créer la ligne, plusieurs candidats, il n''y a rien à désigner.';


-- --  2. Unicité, NULL compris  ------------------------------------------------

alter table public.alertes_admin
  drop constraint if exists alertes_admin_unique;

alter table public.alertes_admin
  add constraint alertes_admin_unique unique nulls not distinct (gp_id, type, cle);


-- --  3. Le nouveau type  ------------------------------------------------------

alter table public.alertes_admin
  drop constraint if exists alertes_admin_type_valide;

alter table public.alertes_admin
  add constraint alertes_admin_type_valide
  check (type in (
    'libelle_non_reconnu',
    'rattachement_impossible',
    'definitif_en_echec',
    'grand_prix_ambigu'
  ));


-- --  4. adopter_grand_prix compte les cinq tables filles  --------------------

create or replace function public.adopter_grand_prix(
  p_placeholder text,
  p_id_unibet   text
)
returns text
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  l_manuel   uuid;
  l_reel     uuid;
  l_attaches integer;
begin
  if coalesce(trim(p_placeholder), '') = '' or coalesce(trim(p_id_unibet), '') = '' then
    raise exception 'adopter_grand_prix : les deux arguments sont obligatoires.';
  end if;

  if p_placeholder = p_id_unibet then
    raise exception 'adopter_grand_prix : le placeholder et l''identifiant Unibet sont identiques (« % »).', p_placeholder;
  end if;

  select id into l_manuel from public.grands_prix where id_unibet = p_placeholder;
  select id into l_reel   from public.grands_prix where id_unibet = p_id_unibet;

  -- Rien à adopter, et rien d'anormal : l'adoption a déjà eu lieu.
  if l_manuel is null and l_reel is not null then
    return format('Déjà adopté : « %s » porte l''identifiant Unibet « %s ».', p_id_unibet, p_id_unibet);
  end if;

  if l_manuel is null then
    raise exception 'adopter_grand_prix : aucune ligne ne porte le placeholder « % ».', p_placeholder;
  end if;

  -- Cas simple : le placeholder est seul, il prend le vrai identifiant.
  if l_reel is null then
    update public.grands_prix
       set id_unibet = p_id_unibet
     where id = l_manuel;

    return format('Adopté : la ligne manuelle « %s » porte désormais « %s ». Le prochain scraping la mettra à jour.', p_placeholder, p_id_unibet);
  end if;

  -- Cas du doublon : le scraper est arrivé avant l'adoption. On garde SA ligne,
  -- qui porte les cotes, et on retire la nôtre — si et seulement si elle est
  -- vide. Les CINQ tables filles de `grands_prix` sont comptées (toutes en
  -- `on delete cascade`), aucune n'est supposée vide d'avance.
  select
      (select count(*) from public.cotes         where gp_id = l_manuel)
    + (select count(*) from public.pronostics    where gp_id = l_manuel)
    + (select count(*) from public.favoris       where gp_id = l_manuel)
    + (select count(*) from public.resultats_gp  where gp_id = l_manuel)
    + (select count(*) from public.alertes_admin where gp_id = l_manuel)
  into l_attaches;

  if l_attaches > 0 then
    raise exception
      'adopter_grand_prix : « % » et « % » désignent le même Grand Prix, mais % ligne(s) pendent à la ligne manuelle. Elle n''est pas supprimée — la supprimer les emporterait en cascade. À reprendre à la main.',
      p_placeholder, p_id_unibet, l_attaches;
  end if;

  delete from public.grands_prix where id = l_manuel;

  return format('Doublon résorbé : la ligne manuelle « %s » était vide et a été supprimée. La ligne du scraper « %s » est conservée.', p_placeholder, p_id_unibet);
end
$$;

comment on function public.adopter_grand_prix(text, text) is
  'Fait porter à une ligne posée à la main le vrai id_unibet, pour que le scraper la mette à jour au lieu d''en créer une seconde. Résorbe le doublon si le scraper est arrivé le premier, et seulement si la ligne manuelle est vide (cinq tables filles comptées, migration 29).';

revoke all on function public.adopter_grand_prix(text, text) from public;
grant execute on function public.adopter_grand_prix(text, text) to service_role;


-- --  5. Contrôle  -------------------------------------------------------------

do $$
declare
  l_nullable text;
  l_corps    text;
begin
  select is_nullable into l_nullable
    from information_schema.columns
   where table_schema = 'public' and table_name = 'alertes_admin' and column_name = 'gp_id';

  if l_nullable <> 'YES' then
    raise exception 'Migration 29 : alertes_admin.gp_id est toujours NOT NULL.';
  end if;

  select pg_get_functiondef('public.adopter_grand_prix(text, text)'::regprocedure) into l_corps;
  if position('alertes_admin' in l_corps) = 0 then
    raise exception 'Migration 29 : adopter_grand_prix ne compte pas alertes_admin.';
  end if;

  raise notice 'Migration 29 appliquée : gp_id nullable, type grand_prix_ambigu, adopter_grand_prix à cinq tables.';
end
$$;
