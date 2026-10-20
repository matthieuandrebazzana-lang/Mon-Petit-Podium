-- =============================================================================
-- Championnat « Démo F1 » — 00 · CONTRÔLES (lecture seule)
-- =============================================================================
--
-- À exécuter AVANT l'étape 01, puis APRÈS chaque étape (01, 03, 04, 99).
-- N'écrit rien. Le §5 lève volontairement une erreur pour annuler sa
-- transaction : son résultat se lit dans le message.
--
-- **Le SQL Editor n'affiche que le résultat de la DERNIÈRE requête** :
-- sélectionner une section (§1 … §5), puis « Run selected ». Le §4 compte trois
-- petites requêtes, à lancer une par une.
--
-- Ce que l'on compare d'une exécution à l'autre :
--
--   §1 `empreinte_*` — doit rester IDENTIQUE avant et après chaque étape.
--      C'est la preuve que rien n'a touché aux vrais utilisateurs : leurs
--      profils, pronostics, podiums, adhésions, classements et statistiques.
--      Le reviewer en fait partie : il est un compte réel, et son adhésion au
--      championnat démo est exclue de l'empreinte (c'est la seule chose qui le
--      concerne qui change, à l'étape 01).
--   §2 l'état de la démo — ce qui a été créé.
--   §3 les Grands Prix exploitables pour l'étape 02.
--   §4 les pseudos et le code demandés — libres ou déjà pris par un tiers.
--   §5 la visibilité sous RLS — un vrai utilisateur ne voit RIEN de la démo.
--
-- Comptes démo : `raw_app_meta_data.demo = true` ET adresse
-- `demo-<pseudo>@greedf1.invalid`. Les deux conditions, jamais une seule.
-- Championnat démo : id `67dc7eb8-a039-43da-9b2f-d7b782e1b20e`, code `DEMOF1`.
-- =============================================================================


-- §1 — Empreinte des données RÉELLES ------------------------------------------
with demo as (
  select id from auth.users
  where raw_app_meta_data ->> 'demo' = 'true'
    and email like 'demo-%@greedf1.invalid'
),
ch_demo as (select '67dc7eb8-a039-43da-9b2f-d7b782e1b20e'::uuid as id)
select
  (select count(*) from public.profils where id not in (select id from demo))
    as profils_reels,
  (select count(*) from public.pronostics where profil_id not in (select id from demo))
    as pronostics_reels,
  (select md5(coalesce(string_agg(p::text, ',' order by p.id), ''))
     from public.profils p where p.id not in (select id from demo))
    as empreinte_profils,
  (select md5(coalesce(string_agg(p::text, ',' order by p.id), ''))
     from public.pronostics p where p.profil_id not in (select id from demo))
    as empreinte_pronostics,
  (select md5(coalesce(string_agg(pp::text, ',' order by pp.pronostic_id), ''))
     from public.pronostic_podium pp
     join public.pronostics p on p.id = pp.pronostic_id
     where p.profil_id not in (select id from demo))
    as empreinte_podiums,
  (select md5(coalesce(string_agg(m::text, ',' order by m.championnat_id, m.profil_id), ''))
     from public.membres_championnat m
     where m.championnat_id not in (select id from ch_demo))
    as empreinte_adhesions,
  (select md5(coalesce(string_agg(
            c.id::text || '=' || coalesce(public.classement_du_championnat(c.id)::text, ''),
            ',' order by c.id), ''))
     from public.championnats c where c.id not in (select id from ch_demo))
    as empreinte_classements,
  (select md5(coalesce(string_agg(
            p.id::text || '=' || coalesce(public.stats_du_profil(p.id, 2026)::text, ''),
            ',' order by p.id), ''))
     from public.profils p where p.id not in (select id from demo))
    as empreinte_stats_2026,
  (select md5(coalesce(string_agg(g::text, ',' order by g.id), ''))
     from public.grands_prix g)
    as empreinte_grands_prix,
  (select md5(coalesce(string_agg(r.gp_id::text || r.recupere_le::text || md5(r.donnees_brutes::text), ',' order by r.gp_id), ''))
     from public.resultats_gp r)
    as empreinte_resultats;


-- §2 — État de la démo ----------------------------------------------------------
-- Une ligne par membre du championnat démo, plus les comptes démo orphelins
-- (qui n'y seraient plus). `points` est lu dans `classement_du_championnat`,
-- la fonction que sert la route du classement : rien n'est recompté ici.
with demo as (
  select id, email, banned_until,
         (select count(*) from auth.identities i where i.user_id = u.id) as identites
  from auth.users u
  where raw_app_meta_data ->> 'demo' = 'true'
    and email like 'demo-%@greedf1.invalid'
),
classement as (
  select ligne
  from jsonb_array_elements(
    coalesce(public.classement_du_championnat('67dc7eb8-a039-43da-9b2f-d7b782e1b20e'), '[]'::jsonb)
  ) ligne
)
select
  pr.pseudo,
  case when d.id is not null then 'démo' else 'réel' end as nature,
  d.email,
  d.banned_until,
  d.identites,
  pr.couleur1, pr.couleur2, pr.couleur_texte, pr.numero, pr.livree_mode,
  (select count(*) from public.push_tokens t where t.user_id = pr.id) as jetons_push,
  (select count(*) from public.pronostics p where p.profil_id = pr.id) as pronostics,
  (select count(*) from public.pronostics p where p.profil_id = pr.id and p.points_gagnes is null)
    as pronostics_sans_points,
  (select (l.ligne ->> 'total_points')::int from classement l
     where (l.ligne ->> 'profil_id')::uuid = pr.id) as points,
  (select (l.ligne ->> 'rang')::int from classement l
     where (l.ligne ->> 'profil_id')::uuid = pr.id) as rang
from public.profils pr
left join demo d on d.id = pr.id
where pr.id in (select id from demo)
   or pr.id in (select profil_id from public.membres_championnat
                where championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e')
order by points desc nulls last, pr.pseudo;

select c.nom, c.code_invitation, c.cree_par, c.photo_url,
       (select count(*) from public.membres_championnat m where m.championnat_id = c.id) as membres
from public.championnats c
where c.id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e';


-- §3 — Grands Prix terminés exploitables, et le prochain -----------------------
select g.nom, g.date_course, g.statut, g.statut_resultats,
       (select count(*) from public.cotes c where c.gp_id = g.id) as cotes,
       (select count(*) from public.cotes c where c.gp_id = g.id and c.marche = 'vainqueur') as cotes_vainqueur,
       (select count(*) from public.cotes c where c.gp_id = g.id and c.marche = 'podium') as cotes_podium,
       exists (select 1 from public.resultats_gp r where r.gp_id = g.id) as resultats,
       public.pronostics_fermes(g.id) as fermes
from public.grands_prix g
where g.statut = 'termine'
   or g.id = (select id from public.grands_prix
              where statut <> 'termine' and date_course > now()
              order by date_course limit 1)
order by g.date_course;


-- §4 — Pseudos et code : libres, ou pris par un compte qui n'est PAS la démo ----
select v.pseudo,
       p.id as pris_par,
       (p.id is not null and p.id not in (
          select id from auth.users
          where raw_app_meta_data ->> 'demo' = 'true' and email like 'demo-%@greedf1.invalid'
       )) as conflit
from (values ('Alex'), ('Maya'), ('Leo'), ('Zoe'), ('Hugo'), ('Lina'), ('Noah'), ('Eva')) v(pseudo)
left join public.profils p on lower(p.pseudo) = lower(v.pseudo)
order by v.pseudo;

select code_invitation, id,
       id <> '67dc7eb8-a039-43da-9b2f-d7b782e1b20e' as conflit
from public.championnats where code_invitation = 'DEMOF1';

select id, email from auth.users
where lower(email) = 'matthieu.andre.bazzana+reviewer@gmail.com';


-- §5 — Visibilité sous RLS -------------------------------------------------------
-- Rejoue les lectures directes du frontend sous l'identité d'un VRAI utilisateur
-- qui ne partage rien avec la démo (le plus ancien profil non démo, hors
-- membres du championnat démo), puis sous celle du reviewer. Le bloc ne fait
-- que lire, et lève en fin de course pour que la transaction soit annulée
-- quoi qu'il arrive : le résultat se lit dans le MESSAGE de l'erreur.
--
-- Attendu : etranger → championnats 0, profils_demo 0, adhesions 0, pronostics_demo 0
--           reviewer → championnats 1, profils_demo 8, adhesions 9,
--                      pronostics_demo = ceux des GP déjà fermés seulement
do $$
declare
  demo_ids uuid[];
  ident    record;
  bilan    text := '';
  n_ch int; n_pr int; n_ad int; n_po int;
begin
  select coalesce(array_agg(id), '{}') into demo_ids
    from auth.users
   where raw_app_meta_data ->> 'demo' = 'true'
     and email like 'demo-%@greedf1.invalid';

  for ident in
    (select 'etranger' as nom, p.id
       from public.profils p
      where p.id <> all (demo_ids)
        and p.id not in (select profil_id from public.membres_championnat
                          where championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e')
      order by p.cree_le limit 1)
    union all
    (select 'reviewer', id from auth.users
      where lower(email) = 'matthieu.andre.bazzana+reviewer@gmail.com')
  loop
    perform set_config('request.jwt.claims',
                       json_build_object('sub', ident.id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', ident.id::text, true);
    set local role authenticated;

    select count(*) into n_ch from public.championnats
     where id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e';
    select count(*) into n_pr from public.profils where id = any (demo_ids);
    select count(*) into n_ad from public.membres_championnat
     where championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e';
    select count(*) into n_po from public.pronostics where profil_id = any (demo_ids);

    reset role;
    bilan := bilan || format('%s → championnats %s, profils_demo %s, adhesions %s, pronostics_demo %s | ',
                             ident.nom, n_ch, n_pr, n_ad, n_po);
  end loop;

  raise exception 'CONTRÔLE RLS (lecture seule, transaction annulée) : %', bilan;
end $$;
