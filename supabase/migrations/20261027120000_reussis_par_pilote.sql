-- =============================================================================
--  Migration 32 — « réussis » du classement compté pilote par pilote
-- =============================================================================
--
-- Symptôme : au classement d'un championnat, « 8 réussis » ; dans « Mes Grands
-- Prix » (iOS), pour le même membre, davantage de pronos réussis.
--
-- **Ce n'était ni le périmètre ni un doublon de jointure.** Les deux comptent
-- les pronostics jugés du membre, quel que soit le championnat (`metier.md`
-- §6). Ils divergent sur l'UNITÉ :
--
--   - le classement compte des LIGNES de `pronostics` dont `points_gagnes > 0`
--     — un podium y vaut 1, qu'un pilote ou les deux soient sur le podium ;
--   - « Mes Grands Prix » compte des LIGNES D'AFFICHAGE (`PronosticMembre.paris`,
--     iOS) — depuis la migration 27, un podium détaillé s'y affiche en deux
--     lignes, une par pilote, chacune jugée pour son compte.
--
-- Un podium à deux bons pilotes : 1 réussi au classement, 2 dans « Mes Grands
-- Prix ». Un podium sans aucun bon pilote : 0 des deux côtés. L'écart vaut donc
-- exactement le nombre de podiums entièrement réussis.
--
-- Le classement s'aligne sur l'écran : une seule fonction,
-- `public.reussites_du_pronostic`, dit combien de réussites vaut UN pronostic,
-- avec la règle exacte de `PronosticMembre.paris` :
--
--   - pas encore jugé (`points_gagnes` NULL)          → 0 ;
--   - pronostic entier, ou podium jugé sans détail
--     (`points_gagnes_1` ou `_2` NULL)                → 1 si `points_gagnes > 0` ;
--   - podium détaillé                                 → un par pilote gagnant.
--
-- **Les points ne bougent pas** : `total_points` et `meilleure_cote` sont
-- calculés comme avant, sur `pronostics.points_gagnes`. La jointure à
-- `pronostic_podium` est 1-1 (clé primaire `pronostic_id`) : elle ne duplique
-- aucune ligne. Seul `pronostics_reussis` change — donc, à points égaux, le
-- 2e critère de départage (`metier.md` §7) peut réordonner deux membres.
--
-- **Conflits d'ordre** : remplace `classement_du_championnat`, dans sa version
-- de la migration 18 à ce compteur près. Rejouer la 7, la 8, la 12, la 16 ou la
-- 18 APRÈS celle-ci restaure l'ancien compteur (et, pour les quatre premières,
-- perd aussi ce que la 18 apportait). Remède : rejouer la 18 si besoin, puis
-- celle-ci.
--
-- Idempotente : `create or replace`, aucune donnée écrite. Bloc d'épreuve à la
-- fin (leçon de la 17) : il lève si la règle ou le remplacement a échoué.
-- =============================================================================


-- --  1. La règle, à un seul endroit  ------------------------------------------

create or replace function public.reussites_du_pronostic(
  p_points_gagnes integer,
  p_gagnes_1      integer,
  p_gagnes_2      integer
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when p_points_gagnes is null then 0
    when p_gagnes_1 is null or p_gagnes_2 is null
      then (p_points_gagnes > 0)::integer
    else (p_gagnes_1 > 0)::integer + (p_gagnes_2 > 0)::integer
  end;
$$;
comment on function public.reussites_du_pronostic(integer, integer, integer) is
  'Réussites d''UN pronostic, comptées comme « Mes Grands Prix » les affiche (PronosticMembre.paris, iOS) : un podium détaillé vaut un par pilote gagnant, tout autre pronostic jugé vaut 1 s''il a rapporté. Migration 32.';

revoke all on function public.reussites_du_pronostic(integer, integer, integer) from public;
revoke all on function public.reussites_du_pronostic(integer, integer, integer) from anon;
revoke all on function public.reussites_du_pronostic(integer, integer, integer) from authenticated;
grant execute on function public.reussites_du_pronostic(integer, integer, integer) to service_role;


-- --  2. Le classement, qui la lit  ---------------------------------------------

-- Corps de la migration 18, à la sous-requête `s` près.
create or replace function public.classement_du_championnat(p_championnat uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profil_id',          x.profil_id,
        'pseudo',             x.pseudo,
        'total_points',       x.total_points,
        'pronostics_reussis', x.pronostics_reussis,
        'meilleure_cote',     x.meilleure_cote,
        'ordre_inscription',  x.ordre_inscription,
        'rang',               x.rang,
        'couleur1',           x.couleur1,
        'couleur2',           x.couleur2,
        'couleur_texte',      x.couleur_texte,
        'numero',             x.numero,
        'livree_mode',        x.livree_mode,
        'livree_ecurie',      x.livree_ecurie,
        'avatar_url',         x.avatar_url
      )
      order by x.rang
    ),
    '[]'::jsonb
  )
  from (
    select
      m.profil_id,
      coalesce(p.pseudo, 'Pilote') as pseudo,
      coalesce(s.total, 0)         as total_points,
      coalesce(s.reussis, 0)       as pronostics_reussis,
      s.meilleure                  as meilleure_cote,
      coalesce(p.couleur1, '#800111') as couleur1,
      coalesce(p.couleur2, '#FFFFFF') as couleur2,
      p.couleur_texte              as couleur_texte,
      p.numero                     as numero,
      coalesce(p.livree_mode, 'perso') as livree_mode,
      p.livree_ecurie              as livree_ecurie,
      p.avatar_url                 as avatar_url,
      row_number() over (order by m.rejoint_le, m.profil_id) as ordre_inscription,
      row_number() over (
        order by
          coalesce(s.total, 0)     desc,
          coalesce(s.reussis, 0)   desc,
          coalesce(s.meilleure, 0) desc,
          m.rejoint_le             asc,
          m.profil_id              asc
      ) as rang
    from public.membres_championnat m
    left join public.profils p on p.id = m.profil_id
    left join lateral (
      select
        sum(pr.points_gagnes)                                     as total,
        sum(public.reussites_du_pronostic(
              pr.points_gagnes, pp.points_gagnes_1, pp.points_gagnes_2
            ))::integer                                           as reussis,
        max(pr.points_gagnes) filter (where pr.points_gagnes > 0) as meilleure
      from public.pronostics pr
      -- 1-1 par la clé primaire de `pronostic_podium` : aucune ligne dupliquée.
      left join public.pronostic_podium pp on pp.pronostic_id = pr.id
      where pr.profil_id = m.profil_id
        and pr.points_gagnes is not null
    ) s on true
    where m.championnat_id = p_championnat
  ) x;
$$;
comment on function public.classement_du_championnat(uuid) is
  'Classement d''un championnat, trié selon les départages de la règle 4.6, voitures, livrées, avatars et couleur de texte compris. Réussis comptés par reussites_du_pronostic (migration 32). Réservé au backend : l''appartenance est vérifiée avant l''appel.';

revoke all on function public.classement_du_championnat(uuid) from public;
revoke all on function public.classement_du_championnat(uuid) from anon;
revoke all on function public.classement_du_championnat(uuid) from authenticated;
grant execute on function public.classement_du_championnat(uuid) to service_role;


-- --  3. Épreuve  ----------------------------------------------------------------

do $$
declare
  cas record;
begin
  for cas in
    select * from (values
      -- points, gain 1, gain 2, attendu
      (null::int, null::int, null::int, 0),  -- pas encore jugé
      (null,      10,        20,        0),  -- jugé sans total : jamais compté
      (28,        null,      null,      1),  -- pronostic entier gagné
      (0,         null,      null,      0),  -- pronostic entier perdu
      (54,        24,        30,        2),  -- podium : deux bons pilotes
      (24,        24,        0,         1),  -- podium : un seul
      (0,         0,         0,         0),  -- podium : aucun
      (54,        null,      null,      1),  -- podium jugé sans détail
      (54,        24,        null,      1)   -- détail incomplet
    ) as t(points, g1, g2, attendu)
  loop
    if public.reussites_du_pronostic(cas.points, cas.g1, cas.g2) <> cas.attendu then
      raise exception 'reussites_du_pronostic(%, %, %) <> %',
        cas.points, cas.g1, cas.g2, cas.attendu;
    end if;
  end loop;

  if position('reussites_du_pronostic' in
      pg_get_functiondef('public.classement_du_championnat(uuid)'::regprocedure)) = 0 then
    raise exception 'classement_du_championnat ne lit pas reussites_du_pronostic';
  end if;
end
$$;
