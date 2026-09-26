-- =============================================================================
-- Migration 25 — résultats provisoires, puis définitifs à J+1
-- =============================================================================
--
-- Le classement capturé à l'arrivée est figé avant les décisions des
-- commissaires : à Bakou, Bortoleto est stocké 13ᵉ, OpenF1 le place ensuite 15ᵉ
-- après une pénalité de 10 s (`docs/audit-evaluation.md` §3, C5). Le job ne
-- relisait jamais OpenF1, et `attribuer_points` n'écrit que les `NULL` : un
-- verdict faux restait faux.
--
-- Désormais :
--
--   | Étape | Moment | Écriture | `statut_resultats` |
--   |---|---|---|---|
--   | provisoire | publication du classement | `attribuer_points` (les `NULL` seuls) | `provisoire` |
--   | définitif  | `date_course + 24 h`      | `remplacer_verdicts` (tout le GP)      | `definitif`  |
--   | recalcul   | route admin, volontaire   | `remplacer_verdicts` (tout le GP)      | `definitif`  |
--
-- Cette migration :
--
--   1. ajoute `grands_prix.statut_resultats` (`NULL` | `provisoire` | `definitif`) ;
--   2. marque les quatre GP déjà courus : Pays-Bas, Italie, Espagne `definitif`,
--      Azerbaïdjan `provisoire` (son calcul définitif part au prochain passage
--      du backend `0.78.0`) ;
--   3. crée `remplacer_verdicts`, l'écriture transactionnelle qui remplace à la
--      fois `resultats_gp` et TOUS les verdicts d'un GP — elle rend
--      `?forcer=true` inutile et supprime le risque R5 ;
--   4. remplace `pronostics_du_joueur` pour servir `statut_evaluation`.
--      `pronostics_du_championnat` l'appelle et en hérite sans être touchée.
--
-- **À appliquer AVANT de déployer le backend 0.78.0**, qui lit et écrit
-- `statut_resultats` et appelle `remplacer_verdicts`. Dépend de la 24
-- (`statut_evaluation`).
--
-- Idempotente : colonne et contrainte sous garde, fonctions remplacées, les
-- statuts ne sont posés que sur des GP qui n'en ont pas encore (Bakou n'est
-- jamais ramené de `definitif` à `provisoire`).
--
-- > ### Conflit d'ordre introduit
-- >
-- > | Si vous rejouez… | …vous perdez | Remède |
-- > |---|---|---|
-- > | **5** ou **6** après **25** | `statut_evaluation` dans les pronostics servis (un `non_evaluable` redevient « en attente » à l'écran) | rejouer 25 |
-- =============================================================================


-- --  0. Prérequis  ------------------------------------------------------------

-- `pronostics_du_joueur` (§4) lit `statut_evaluation` : sans la 24, sa création
-- échouerait sur un message moins clair que celui-ci.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'pronostics'
      and column_name = 'statut_evaluation'
  ) then
    raise exception 'Migration 24 absente : appliquer 20260926120000_statut_evaluation d''abord.';
  end if;
end
$$;


-- --  1. La colonne  ------------------------------------------------------------

alter table public.grands_prix
  add column if not exists statut_resultats text;

comment on column public.grands_prix.statut_resultats is
  'NULL (pas encore de résultats) | provisoire (classement de l''arrivée, points déjà comptés) | definitif (relu chez OpenF1 à J+1, plus recalculé automatiquement).';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'grands_prix_statut_resultats_valide'
  ) then
    alter table public.grands_prix
      add constraint grands_prix_statut_resultats_valide
      check (statut_resultats is null or statut_resultats in ('provisoire', 'definitif'));
  end if;
end
$$;


-- --  2. Les quatre GP déjà courus  ---------------------------------------------

-- Par identifiant d'abord, par slug de nom en repli (une base dont les lignes
-- auraient été recréées). Les trois premiers ont été relus chez OpenF1 et
-- rejugés à la main par l'audit : ils sont définitifs.
update public.grands_prix
   set statut_resultats = 'definitif'
 where statut_resultats is distinct from 'definitif'
   and (
        id in (
          '33b835cc-5c17-40f7-a41f-3e95fc14885a',  -- Pays-Bas
          'e4e6f2ab-9ea6-4191-ab6c-d61a61f1ef4f',  -- Italie
          'b327866c-9479-4e59-bdde-5f0e6ec513aa'   -- Espagne
        )
     or (
          public.slug_gp(nom) in ('pays-bas', 'italie', 'espagne')
          and date_course >= timestamptz '2026-01-01'
          and date_course <  timestamptz '2027-01-01'
        )
   );

-- Bakou : provisoire, **seulement s'il n'a encore aucun statut**. Rejouer la
-- migration après son calcul définitif ne doit pas le rouvrir.
update public.grands_prix
   set statut_resultats = 'provisoire'
 where statut_resultats is null
   and (
        id = '3bf1ef36-f97c-446c-a8c6-e605f9750cd4'
     or (
          public.slug_gp(nom) = 'azerbaidjan'
          and date_course >= timestamptz '2026-01-01'
          and date_course <  timestamptz '2027-01-01'
        )
   );


-- --  3. `remplacer_verdicts` — l'écriture du définitif et du recalcul  ---------

-- Reçoit :
--   p_gp              le Grand Prix ;
--   p_attributions    `[{"pronostic_id": "...", "points": 28, "statut": "gagne"}, ...]`,
--                     le verdict de CHAQUE pronostic du GP ;
--   p_donnees         le nouveau `donnees_brutes`, ou NULL pour garder celui en base
--                     (recalcul sans relecture d'OpenF1) ;
--   p_statut_resultats `definitif` (seule valeur employée aujourd'hui).
--
-- Tout se fait dans la transaction de l'appel : résultats, verdicts, podiums,
-- statut du GP. Un échec n'écrit RIEN — le GP garde ses verdicts précédents,
-- jamais un état intermédiaire « tout en attente » (risque R5 de l'audit).
--
-- **Contrairement à `attribuer_points`, elle réécrit les verdicts déjà
-- posés.** C'est son rôle. Un pronostic du GP absent de `p_attributions` repart
-- `en_attente` (points NULL) : le calcul n'a pas su le juger sur les nouvelles
-- données, et garder l'ancien verdict ferait coexister deux classements.
--
-- `gagne` / `perdu` restent dérivés de `points_gagnes` par le trigger de la 24.
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
  update public.pronostic_podium pp
     set points_gagnes = p.points_gagnes
    from public.pronostics p
   where p.id    = pp.pronostic_id
     and p.gp_id = p_gp
     and p.type  = 'podium'
     and pp.points_gagnes is distinct from p.points_gagnes;

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
  'Remplace, dans une seule transaction, les résultats et TOUS les verdicts d''un GP, puis pose son statut de résultats. Calcul définitif à J+1 et recalcul admin. Réservée au backend.';

revoke all on function public.remplacer_verdicts(uuid, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.remplacer_verdicts(uuid, jsonb, jsonb, text) to service_role;


-- --  4. `pronostics_du_joueur` sert `statut_evaluation`  -----------------------

-- Corps de la migration 6, à un champ près. `pronostics_du_championnat` (18)
-- l'appelle pour chaque membre et en hérite sans être remplacée : aucun conflit
-- d'ordre avec la 18.
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
        -- Ajout de la 25 : `non_evaluable` ne se lit pas dans `points_gagnes`,
        -- NULL dans les deux cas.
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
          'points_2', c2.valeur
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
  'Pronostics d''un joueur sur un GP, rapprochés des cotes, avec points gagnés et statut d''évaluation. Réservée au backend.';

revoke all on function public.pronostics_du_joueur(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pronostics_du_joueur(uuid, uuid) to service_role;


-- --  5. Contrôle  --------------------------------------------------------------

do $$
declare
  provisoires integer;
  definitifs  integer;
begin
  if not exists (
    select 1 from pg_proc where proname = 'remplacer_verdicts'
  ) then
    raise exception 'Fonction remplacer_verdicts absente.';
  end if;

  select count(*) filter (where statut_resultats = 'provisoire'),
         count(*) filter (where statut_resultats = 'definitif')
    into provisoires, definitifs
  from public.grands_prix;

  raise notice 'Résultats : % GP définitif(s), % provisoire(s).', definitifs, provisoires;
end
$$;

select nom, date_course, statut, statut_resultats
from public.grands_prix
where statut_resultats is not null
order by date_course;
