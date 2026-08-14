-- =============================================================================
-- Étape 7 — Classement d'un championnat
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les six migrations précédentes : elle lit `public.membres_championnat`
-- et `public.profils` (étapes 2 et 3) ainsi que `public.pronostics.points_gagnes`
-- (étape 6). Elle ne crée aucune table.
--
-- La migration est idempotente : la rejouer ne casse rien et ne touche à aucune
-- donnée.
-- =============================================================================

-- --  1. L'index qui sert l'agrégation  ----------------------------------------

-- Le classement additionne les points de chaque membre. La requête est toujours
-- « les pronostics NOTÉS de ce profil » : un index partiel sur les seules lignes
-- déjà notées suffit, et il reste petit — la table contient aussi tous les
-- pronostics en attente, qui n'entrent jamais dans un classement.
--
-- Il complète, sans le remplacer, `pronostics_a_calculer_idx` de l'étape 6, qui
-- porte exactement sur les lignes inverses (`points_gagnes is null`).
create index if not exists pronostics_notes_par_profil_idx
  on public.pronostics (profil_id, points_gagnes)
  where points_gagnes is not null;

-- --  2. Le classement  --------------------------------------------------------

-- Renvoie une ligne par membre, déjà triée et déjà rangée. Agréger en base
-- plutôt que côté backend n'est pas un raffinement : sans cela, il faudrait
-- transporter tous les pronostics notés de tous les membres — une centaine de
-- lignes par personne sur une saison — pour n'en tirer que trois nombres.
--
-- **Les pronostics ne sont PAS rattachés à un championnat**, et c'est la règle
-- posée à l'étape 5 : un joueur remplit un pronostic par Grand Prix, qui compte
-- dans tous ses championnats à la fois. La somme porte donc sur tous ses
-- pronostics notés, et le championnat ne sert qu'à savoir QUI classer.
--
-- `security definer` : la fonction est paramétrée par un championnat, donc elle
-- lit forcément les pronostics d'autrui. Sous l'identité de l'appelant, la
-- politique RLS de l'étape 5 filtrerait les membres avec qui il ne partage rien
-- — ce qui est exactement ce qu'on veut protéger, mais qui rendrait ici un
-- classement silencieusement amputé au lieu d'un refus franc. C'est donc le
-- backend qui porte l'autorisation, en vérifiant l'appartenance AVANT d'appeler
-- (routes/championnats.py), et la fonction n'est accordée qu'à `service_role`.
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
        -- Le plus gros coup du membre : la plus forte cote qu'il ait touchée,
        -- en points (règle 4.1). Nulle tant qu'il n'a rien réussi — `0` dirait
        -- « son meilleur coup vaut zéro », ce qui n'est pas la même chose.
        'meilleure_cote',     x.meilleure_cote,
        'ordre_inscription',  x.ordre_inscription,
        'rang',               x.rang
      )
      order by x.rang
    ),
    '[]'::jsonb
  )
  from (
    select
      m.profil_id,
      -- Un profil manquant ne doit pas trouer le classement : la migration des
      -- profils peut ne pas avoir tourné sur ce projet.
      coalesce(p.pseudo, 'Pilote') as pseudo,
      coalesce(s.total, 0)         as total_points,
      coalesce(s.reussis, 0)       as pronostics_reussis,
      s.meilleure                  as meilleure_cote,
      -- Ordre d'adhésion, base du 3ᵉ critère de départage (règle 4.6) et de la
      -- livrée attribuée à chaque membre côté frontend. `profil_id` départage
      -- deux adhésions au même instant, sinon la numérotation serait instable
      -- d'un appel à l'autre — et deux membres échangeraient leurs couleurs.
      row_number() over (order by m.rejoint_le, m.profil_id) as ordre_inscription,
      -- Règle 4.6, dans l'ordre : points, puis pronostics réussis, puis
      -- meilleure cote réussie, puis ordre d'inscription. `row_number` et non
      -- `rank` : les quatre critères réunis départagent toujours, et deux
      -- membres ex æquo au premier rang afficheraient sinon « 1, 1, 3 ».
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
    -- `left join lateral` et non un `group by` sur une jointure : un membre qui
    -- n'a jamais pronostiqué doit apparaître au classement avec 0, pas
    -- disparaître de la liste des membres.
    left join lateral (
      select
        sum(pr.points_gagnes)                                as total,
        count(*) filter (where pr.points_gagnes > 0)         as reussis,
        max(pr.points_gagnes) filter (where pr.points_gagnes > 0) as meilleure
      from public.pronostics pr
      where pr.profil_id = m.profil_id
        and pr.points_gagnes is not null
    ) s on true
    where m.championnat_id = p_championnat
  ) x;
$$;

comment on function public.classement_du_championnat(uuid) is
  'Classement d''un championnat, trié selon les départages de la règle 4.6. Réservé au backend : l''appartenance est vérifiée avant l''appel.';

revoke all on function public.classement_du_championnat(uuid) from public;
revoke all on function public.classement_du_championnat(uuid) from anon;
revoke all on function public.classement_du_championnat(uuid) from authenticated;
grant execute on function public.classement_du_championnat(uuid) to service_role;
