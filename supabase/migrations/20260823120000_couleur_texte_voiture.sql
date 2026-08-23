-- =============================================================================
-- La couleur du texte peint sur la voiture
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, APRÈS les dix-sept
-- migrations précédentes. Elle suppose :
--   - `public.profils` (migration 20260809191018) : elle l'altère ;
--   - `public.classement_du_championnat` et `public.pronostics_du_championnat`
--     dans leur version de la migration 20260821180000 : elle REMPLACE les deux.
--
-- Contexte : le numéro du museau et le pseudo de l'aileron arrière prenaient
-- jusqu'ici une encre CALCULÉE — `encreSur`, côté frontend, qui compare la
-- luminance de l'aplat à 0,45 et rend du blanc ou du presque-noir. Le membre
-- peut désormais choisir cette couleur, comme il choisit déjà sa coque et ses
-- ailerons.
--
-- ATTENTION À L'ORDRE, comme pour les migrations 8, 9, 10, 12 et 15 : elle
-- remplace `classement_du_championnat` (créée par la 8, remplacée par la 12 puis
-- la 15) et `pronostics_du_championnat` (par la 10, remplacée par la 12 puis la
-- 15). Rejouer l'une de ces migrations APRÈS celle-ci restaurerait leur version
-- d'avant : la couleur de texte disparaîtrait des classements, de la vue piste
-- et du tableau des résultats — sans rien casser d'autre, le frontend retombant
-- sur l'encre calculée. Si l'une est rejouée, rejouer celle-ci derrière.
--
-- Idempotente. Elle ne retouche AUCUNE ligne existante — voir §1, c'est le point
-- de la migration.
-- =============================================================================


-- --  1. La colonne, nullable, et SANS remplissage rétroactif  ----------------

-- **`NULL` n'est pas « pas de couleur », c'est « je n'ai pas choisi ».** Et la
-- différence n'est pas rhétorique : tant que la colonne vaut `NULL`, le frontend
-- garde l'encre CALCULÉE, celle qui contraste avec l'aplat sous le texte. Un
-- membre dont la coque est blanche, argent, beige ou jaune y lit son numéro ;
-- avec un `#FFFFFF` posé d'office, il ne le lirait plus.
--
-- D'où les deux instructions séparées, et l'ordre compte :
--
--   * `add column` SANS `default` — PostgreSQL ne remplit alors rien, les lignes
--     existantes restent à `NULL` et gardent leur encre mesurée ;
--   * `alter column … set default` — le défaut ne vaut plus que pour les lignes
--     À VENIR, c'est-à-dire les comptes créés après cette migration. Ils naissent
--     avec la coque bordeaux `#800111`, où le blanc tient 10,88:1.
--
-- Écrites en une seule instruction (`add column … default '#FFFFFF'`), les deux
-- effets seraient venus ensemble et toute la base aurait basculé au blanc.
alter table public.profils
  add column if not exists couleur_texte text;

alter table public.profils
  alter column couleur_texte set default '#FFFFFF';

comment on column public.profils.couleur_texte is
  'Couleur du numéro et du pseudo peints sur la voiture, au format #RRGGBB. NULL = pas de choix, le frontend calcule alors l''encre qui contraste avec l''aplat (encreSur). Défaut #FFFFFF pour les profils créés après la migration 18.';


-- --  2. La contrainte de format  ---------------------------------------------

-- Même doctrine que `profils_couleurs_hex` : la couleur part telle quelle dans
-- l'attribut `fill` d'un SVG, donc son format est vérifié en base ET côté
-- backend. Le frontend n'en propose que vingt, mais rien n'oblige un client à
-- passer par le frontend.
--
-- **Aucune contrainte de contraste ici, et c'est délibéré.** « Cette couleur
-- est-elle lisible sur cet aplat ? » demande de connaître l'aplat, donc la
-- livrée, donc laquelle des onze est active — une question que la base ne peut
-- pas trancher sans dupliquer la table des écuries, qui est un actif du frontend
-- (même raisonnement que `profils_livree_ecurie_format`). L'avertissement est
-- posé dans l'écran de profil, où le contraste est mesuré contre l'aplat réel.
alter table public.profils
  drop constraint if exists profils_couleur_texte_hex;

alter table public.profils
  add constraint profils_couleur_texte_hex
  check (couleur_texte is null or couleur_texte ~ '^#[0-9A-Fa-f]{6}$');

comment on constraint profils_couleur_texte_hex on public.profils is
  'Couleur de texte au format #RRGGBB, ou NULL (encre calculée par le frontend).';


-- --  3. Le classement porte la couleur de texte  -----------------------------

-- Même fonction qu'à la migration 20260821180000, à UN champ près :
-- `couleur_texte`. La vue piste dessine seize voitures qui portent chacune un
-- numéro et un pseudo ; sans ce champ, la couleur choisie ne serait visible que
-- sur l'écran de profil, c'est-à-dire nulle part où quelqu'un d'autre la voit.
--
-- Le reste du corps est INCHANGÉ : règle 4.6, `row_number` et non `rank`,
-- `left join lateral` pour ne pas faire disparaître un membre sans pronostic,
-- `ordre_inscription` conservé, `coalesce` sur les couleurs et le mode.
--
-- **Aucun `coalesce` sur `couleur_texte`**, exactement comme sur `avatar_url` et
-- pour la même raison : `NULL` a une réponse à l'écran — l'encre calculée — et
-- ne se confond avec rien.
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
  'Classement d''un championnat, trié selon les départages de la règle 4.6, voitures, livrées, avatars et couleur de texte compris. Réservé au backend : l''appartenance est vérifiée avant l''appel.';

revoke all on function public.classement_du_championnat(uuid) from public;
revoke all on function public.classement_du_championnat(uuid) from anon;
revoke all on function public.classement_du_championnat(uuid) from authenticated;
grant execute on function public.classement_du_championnat(uuid) to service_role;


-- --  4. Les pronostics du championnat portent la couleur de texte  -----------

-- Même fonction qu'à la migration 20260821180000, à UN champ près, et pour la
-- même raison : le résumé d'un Grand Prix et l'écran « Résultats par Grand Prix »
-- dessinent la voiture de chaque membre en tête de sa rangée.
--
-- Le reste du corps est INCHANGÉ, y compris l'ordre par `rejoint_le` et l'appel
-- à `pronostics_du_joueur`.
create or replace function public.pronostics_du_championnat(p_championnat uuid, p_gp uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profil_id',  m.profil_id,
        'pseudo',     coalesce(pr.pseudo, 'Pilote'),
        'rejoint_le', m.rejoint_le,
        'couleur1',   coalesce(pr.couleur1, '#800111'),
        'couleur2',   coalesce(pr.couleur2, '#FFFFFF'),
        -- Sans `coalesce` : NULL veut dire « encre calculée » (voir §1).
        'couleur_texte', pr.couleur_texte,
        'numero',     pr.numero,
        'livree_mode',   coalesce(pr.livree_mode, 'perso'),
        'livree_ecurie', pr.livree_ecurie,
        'avatar_url', pr.avatar_url,
        'total_points', (
          select case when count(p.points_gagnes) > 0
                      then coalesce(sum(p.points_gagnes), 0)::integer end
          from public.pronostics p
          where p.profil_id = m.profil_id and p.gp_id = p_gp
        ),
        'pronostics', public.pronostics_du_joueur(m.profil_id, p_gp)
      )
      order by m.rejoint_le
    ),
    '[]'::jsonb
  )
  from public.membres_championnat m
  left join public.profils pr on pr.id = m.profil_id
  where m.championnat_id = p_championnat;
$$;

comment on function public.pronostics_du_championnat(uuid, uuid) is
  'Pronostics de tous les membres d''un championnat pour un GP, avec leur voiture, leur livrée, leur avatar, leur couleur de texte et leur total. Réservée au backend.';

revoke all on function public.pronostics_du_championnat(uuid, uuid) from public;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from anon;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from authenticated;
grant execute on function public.pronostics_du_championnat(uuid, uuid) to service_role;


-- --  5. Vérification  ---------------------------------------------------------

-- La contrainte s'éprouve elle-même, comme celle de la migration 17 : un `check`
-- posé sur une colonne vide n'est évalué qu'à la première écriture, et c'est
-- ainsi qu'une expression incompilable est passée inaperçue pendant deux
-- versions (`docs/bugs-connus.md` §18). Ces deux lignes l'écrivent puis
-- l'effacent sur un profil jetable, dans une transaction annulée : rien ne reste
-- en base, et l'erreur sort MAINTENANT si elle doit sortir.
do $$
begin
  perform 1 where '#FFFFFF' ~ '^#[0-9A-Fa-f]{6}$';
  if not found then
    raise exception 'La contrainte profils_couleur_texte_hex refuse une couleur valide.';
  end if;
  perform 1 where 'blanc' ~ '^#[0-9A-Fa-f]{6}$';
  if found then
    raise exception 'La contrainte profils_couleur_texte_hex accepte une valeur invalide.';
  end if;
end $$;
