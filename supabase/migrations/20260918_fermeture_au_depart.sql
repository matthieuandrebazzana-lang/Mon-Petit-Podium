-- =============================================================================
-- Fermeture des pronostics AU DÉPART, sans marge (migration 23)
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, APRÈS la migration
-- 5 (`20260813183636_favoris_pronostics`), dont elle **remplace la fonction**
-- `public.pronostics_fermes(uuid)`. Elle ne crée aucune table, aucune colonne,
-- aucune politique : **une seule fonction remplacée**, et elle est idempotente.
--
-- Rien d'autre n'est touché. La signature ne change pas, donc ni la politique de
-- lecture des pronostics posée par la 21 — qui appelle
-- `public.pronostics_fermes(gp_id)` — ni `enregistrer_pronostics` de la 5, qui
-- l'appelle aussi, n'ont besoin d'être recréées : les deux voient le nouveau
-- corps au prochain appel.
--
-- -----------------------------------------------------------------------------
-- La règle change : les pronostics ferment au départ, pas cinq minutes avant
-- -----------------------------------------------------------------------------
-- La règle 4.3 portait une marge de cinq minutes — `date_course - interval
-- '5 minutes'` ici, `MARGE_FERMETURE = timedelta(minutes=5)` dans la route,
-- `MARGE_FERMETURE_MS` dans `lib/format.js`. **Elle est retirée aux trois
-- étages** : la fermeture se déclenche quand `date_course` est atteinte.
--
-- Un GP sans `date_course` connue reste ouvert, et ce point ne change pas :
-- refuser tout le monde parce qu'Unibet n'a pas encore annoncé l'heure serait le
-- mauvais sens du doute. C'est ce que porte le `coalesce(..., false)`.
--
-- -----------------------------------------------------------------------------
-- ATTENTION À L'ORDRE — le piège est celui, classique, d'une fonction remplacée
-- -----------------------------------------------------------------------------
-- **Rejouer la 5 APRÈS celle-ci restaure la marge de cinq minutes en base**, et
-- le symptôme serait discret : le frontend afficherait les pronostics ouverts et
-- la route les accepterait pendant les cinq dernières minutes, mais l'écriture
-- serait refusée en `PT423` par `enregistrer_pronostics`. Un joueur verrait un
-- formulaire ouvert et une erreur au moment de valider. Si la 5 est rejouée pour
-- une raison quelconque, **rejouer celle-ci derrière**. Voir `docs/database.md`
-- §6.
-- =============================================================================

-- --  1. La fonction de fermeture, sans marge  ---------------------------------

create or replace function public.pronostics_fermes(p_gp uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (
      select now() >= g.date_course
      from public.grands_prix g
      where g.id = p_gp
    ),
    false
  );
$$;

comment on function public.pronostics_fermes(uuid) is
  'Vrai si les pronostics de ce GP sont fermés (la course est partie, règle 4.3).';

revoke all on function public.pronostics_fermes(uuid) from public;
grant execute on function public.pronostics_fermes(uuid) to authenticated, service_role;

-- --  2. Contrôle  -------------------------------------------------------------

-- La marge retirée ne se voit pas dans un `select` de résultat : on relit donc
-- le corps de la fonction. Une base restée sur la version de la 5 lèverait ici
-- au lieu de laisser croire que la migration a pris.
do $$
begin
  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'pronostics_fermes'
      and pg_catalog.pg_get_functiondef(p.oid) like '%interval%'
  ) then
    raise exception
      'pronostics_fermes porte encore une marge : la migration 5 a-t-elle été rejouée après la 23 ?';
  end if;
end;
$$;
