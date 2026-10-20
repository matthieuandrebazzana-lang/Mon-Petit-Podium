-- =============================================================================
-- Championnat « Démo F1 » — 02 · EXPORT DES GRANDS PRIX TERMINÉS (lecture seule)
-- =============================================================================
--
-- À exécuter APRÈS l'étape 01. N'écrit rien.
--
-- Rend une ligne `membres` (les huit comptes démo) puis une ligne par Grand
-- Prix terminé qui a des cotes ET des résultats. Exporter le résultat en CSV
-- (« Export » → « Download CSV ») HORS du dépôt, puis le passer au générateur :
--
--   cd backend
--   .venv/bin/python scripts/demo_pronostics.py ~/Downloads/<export>.csv \
--       > ../supabase/demo/03_pronostics_gp_termines.sql
--
-- Le générateur fait juger chaque pronostic par `app.calcul.points.calculer`,
-- la fonction même du job de résultats, sur ces données-là. Les empreintes
-- `md5` voyagent avec : l'étape 03 refuse de s'exécuter si les cotes ou les
-- résultats d'un GP ont changé depuis l'export — ses verdicts seraient faux.
--
-- Les empreintes sont calculées ICI et recalculées par l'étape 03 avec la même
-- expression : c'est la base qui se compare à elle-même, jamais à Python.
-- =============================================================================

select 'membres' as nature,
       jsonb_agg(jsonb_build_object('id', u.id, 'pseudo', p.pseudo) order by p.pseudo)::text as contenu
  from auth.users u
  join public.profils p on p.id = u.id
 where u.raw_app_meta_data ->> 'demo' = 'true'
   and u.email like 'demo-%@greedf1.invalid'

union all

select 'gp',
       jsonb_build_object(
         'id',                g.id,
         'nom',               g.nom,
         'date_course',       g.date_course,
         'statut_resultats',  g.statut_resultats,
         'empreinte_donnees', md5(r.donnees_brutes::text),
         'empreinte_cotes',   (select md5(string_agg(c.id_outcome_unibet || ':' || c.marche || ':'
                                                    || c.pilote || ':' || c.valeur || ':'
                                                    || coalesce(c.numero_pilote::text, '') || ':'
                                                    || coalesce(c.ecurie_id, ''),
                                                    ',' order by c.id_outcome_unibet))
                                 from public.cotes c where c.gp_id = g.id),
         'cotes',             (select jsonb_agg(to_jsonb(c) order by c.id_outcome_unibet)
                                 from public.cotes c where c.gp_id = g.id),
         'donnees',           r.donnees_brutes
       )::text
  from public.grands_prix g
  join public.resultats_gp r on r.gp_id = g.id
 where g.statut = 'termine'
   and exists (select 1 from public.cotes c where c.gp_id = g.id);
