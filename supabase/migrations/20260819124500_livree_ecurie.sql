-- =============================================================================
-- Livrée d'écurie : deux colonnes sur `public.profils`, et les fonctions
-- de lecture qui les servent
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les onze migrations précédentes. Elle suppose :
--   - `public.profils` (migration 20260809191018) : elle l'altère ;
--   - `public.profils.couleur1` / `couleur2` / `numero` et
--     `public.classement_du_championnat` (migration 20260814162200) : elle
--     REMPLACE cette fonction ;
--   - `public.pronostics_du_championnat` (migration 20260814213000) : elle
--     REMPLACE également cette fonction.
--
-- Contexte : jusqu'ici une voiture ne pouvait porter que deux couleurs choisies
-- parmi vingt (étape 8). Le membre peut désormais lui préférer l'une des onze
-- livrées d'écurie de `assets/voitures_ecuries.svg`, dont les couleurs sont
-- fixes. Le choix vit sur le PROFIL et non sur l'adhésion à un championnat :
-- la section 5 du CLAUDE.md dit « une seule voiture, identique dans tous ses
-- championnats », et la poser sur `membres_championnat` autoriserait exactement
-- ce qu'elle exclut.
--
-- La migration ne crée AUCUNE table : deux colonnes, deux contraintes, deux
-- fonctions remplacées. Elle est idempotente : la rejouer ne casse rien et ne
-- retouche aucun profil.
--
-- ATTENTION À L'ORDRE, comme pour les migrations 8, 9 et 10 : cette migration
-- remplace `classement_du_championnat` (créée par la 8) et
-- `pronostics_du_championnat` (créée par la 10). Rejouer l'une de ces deux
-- migrations APRÈS celle-ci restaurerait leur version d'avant, et les voitures
-- des classements comme du tableau des résultats retomberaient toutes en mode
-- personnalisé — sans rien casser d'autre, le frontend repliant sur les
-- couleurs (`livreeDuMembre`). Si l'une des deux est rejouée pour une raison
-- quelconque, rejouer celle-ci derrière.
-- =============================================================================


-- --  1. Les deux colonnes  ----------------------------------------------------

-- `livree_mode` porte le mode et `livree_ecurie` le slug de la livrée choisie.
-- Deux colonnes plutôt qu'une seule nullable (« le slug, ou NULL pour le mode
-- personnalisé ») : un membre qui essaie une livrée puis revient à ses couleurs
-- garde ainsi son dernier choix d'écurie, et le retrouve s'il rebascule. Une
-- colonne unique le lui ferait ressaisir à chaque aller-retour.
alter table public.profils
  add column if not exists livree_mode   text not null default 'perso',
  add column if not exists livree_ecurie text;

comment on column public.profils.livree_mode is
  'perso = les deux couleurs choisies, ecurie = une livrée fixe (livree_ecurie).';
comment on column public.profils.livree_ecurie is
  'Slug de la livrée, tel que frontend/src/lib/livrees.js le nomme. Peut rester renseigné en mode perso : c''est le dernier choix, gardé pour le retour.';


-- --  2. Les deux contraintes  -------------------------------------------------

-- Le mode est une contrainte `check` et non un type `enum`, pour la raison déjà
-- retenue au statut des Grands Prix (étape 4) : ajouter une valeur à un enum est
-- une migration à part entière, alors que les modes d'affichage d'une voiture ne
-- sont pas encore tous arrêtés.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profils'::regclass
      and conname  = 'profils_livree_mode_valide'
  ) then
    alter table public.profils
      add constraint profils_livree_mode_valide
      check (livree_mode in ('perso', 'ecurie'));
  end if;
end $$;

-- Le mode `ecurie` exige un slug. Sans cette contrainte, un profil pourrait se
-- déclarer en livrée d'écurie sans dire laquelle, et le frontend n'aurait rien
-- d'autre à afficher qu'un repli silencieux.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profils'::regclass
      and conname  = 'profils_livree_ecurie_requise'
  ) then
    alter table public.profils
      add constraint profils_livree_ecurie_requise
      check (livree_mode <> 'ecurie' or livree_ecurie is not null);
  end if;
end $$;

-- Le slug est contraint par son FORMAT, jamais par une liste des onze écuries.
-- Une énumération en base figerait la grille : ajouter une livrée demanderait
-- une migration, alors que les onze voitures sont un actif du frontend qui se
-- relit à chaque saison (comme `lib/ecuries.js` et `lib/calendrier2026.js`).
-- Un slug inconnu du frontend n'est pas une panne : `livreeDuMembre` retombe
-- sur les couleurs personnalisées, ce qui se voit à l'écran au lieu de planter.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profils'::regclass
      and conname  = 'profils_livree_ecurie_format'
  ) then
    alter table public.profils
      add constraint profils_livree_ecurie_format
      check (livree_ecurie is null or livree_ecurie ~ '^[a-z0-9-]{2,32}$');
  end if;
end $$;


-- --  3. RLS  ------------------------------------------------------------------

-- Les deux politiques existent depuis la migration 20260809191018 et couvrent
-- exactement ce cas : lecture par tout membre connecté (les classements et la
-- vue piste ont besoin de savoir quelle voiture peindre), écriture réservée au
-- propriétaire de la ligne. Elles sont réaffirmées ici, à l'identique, pour que
-- cette migration décrive complètement l'état qu'elle suppose.
--
-- Conséquence, la même qu'à l'étape 8 : la politique d'écriture porte sur la
-- LIGNE, pas sur la colonne. Un membre peut donc écrire `livree_mode` et
-- `livree_ecurie` depuis n'importe quel client Supabase, sans passer par
-- `PATCH /profils/moi`. C'est pour cela que les contraintes ci-dessus vivent en
-- base et pas seulement dans la route.
alter table public.profils enable row level security;

drop policy if exists "Profils lisibles par les membres connectes" on public.profils;
create policy "Profils lisibles par les membres connectes"
  on public.profils for select
  to authenticated
  using (true);

drop policy if exists "Chacun modifie son profil" on public.profils;
create policy "Chacun modifie son profil"
  on public.profils for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);


-- --  4. Le classement porte la livrée  ----------------------------------------

-- Même fonction qu'à l'étape 8, à deux champs près : `livree_mode` et
-- `livree_ecurie`. La vue liste et la vue piste doivent peindre la voiture que
-- le membre a réellement choisie ; sans ces deux champs, un membre en livrée
-- Ferrari apparaîtrait sur la piste avec ses couleurs personnelles, c'est-à-dire
-- pas comme sur son profil.
--
-- Le reste du corps est INCHANGÉ : règle 4.6, `row_number` et non `rank`,
-- `left join lateral` pour ne pas faire disparaître un membre sans pronostic,
-- `ordre_inscription` conservé (4ᵉ critère de départage). Voir les migrations
-- 20260814103000 et 20260814162200 pour le détail de ces choix.
--
-- Le `coalesce` sur le mode n'est pas décoratif : un membre sans profil
-- (`left join` non résolu) rendrait `null`, et le frontend afficherait alors une
-- voiture sans mode. `perso` est le repli, comme le défaut de la colonne.
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
        'numero',             x.numero,
        'livree_mode',        x.livree_mode,
        'livree_ecurie',      x.livree_ecurie
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
      p.numero                     as numero,
      coalesce(p.livree_mode, 'perso') as livree_mode,
      p.livree_ecurie              as livree_ecurie,
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
  'Classement d''un championnat, trié selon les départages de la règle 4.6, voitures et livrées comprises. Réservé au backend : l''appartenance est vérifiée avant l''appel.';

revoke all on function public.classement_du_championnat(uuid) from public;
revoke all on function public.classement_du_championnat(uuid) from anon;
revoke all on function public.classement_du_championnat(uuid) from authenticated;
grant execute on function public.classement_du_championnat(uuid) to service_role;


-- --  5. Le tableau des résultats porte la livrée  -----------------------------

-- Même fonction qu'à la migration 20260814213000, à deux champs près, et pour
-- la même raison qu'au classement : le tableau des résultats (maquette 11)
-- affiche la voiture de chaque membre, elle doit être celle qu'il a choisie.
--
-- Le reste du corps est INCHANGÉ, y compris l'ordre par `rejoint_le` et l'appel
-- à `pronostics_du_joueur`. `total_points` reste calculé en base : la somme doit
-- compter `0` pour un raté et IGNORER un pronostic non jugé, jamais le compter
-- zéro (convention de l'étape 6).
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
        -- La voiture du membre. Les couleurs ne sont jamais nulles : un profil
        -- manquant retombe sur les défauts de la colonne, sans quoi le SVG
        -- afficherait des aplats transparents (même `coalesce` qu'à l'étape 8).
        'couleur1',   coalesce(pr.couleur1, '#800111'),
        'couleur2',   coalesce(pr.couleur2, '#FFFFFF'),
        'numero',     pr.numero,
        -- La livrée choisie. Même repli que sur les couleurs : un profil
        -- manquant vaut `perso`, jamais un mode nul que le frontend devrait
        -- interpréter.
        'livree_mode',   coalesce(pr.livree_mode, 'perso'),
        'livree_ecurie', pr.livree_ecurie,
        -- Ce que le membre a marqué sur CE Grand Prix. NULL tant qu'aucun de
        -- ses pronostics n'a été noté — convention de l'étape 6.
        'total_points', (
          select case when count(p.points_gagnes) > 0
                      then coalesce(sum(p.points_gagnes), 0)::integer end
          from public.pronostics p
          where p.profil_id = m.profil_id and p.gp_id = p_gp
        ),
        'pronostics', public.pronostics_du_joueur(m.profil_id, p_gp)
      )
      -- L'ordre d'inscription : c'est le 3ᵉ critère de départage de la règle
      -- 4.6, et le seul ordre stable dont on dispose avant l'étape 7.
      order by m.rejoint_le
    ),
    '[]'::jsonb
  )
  from public.membres_championnat m
  left join public.profils pr on pr.id = m.profil_id
  where m.championnat_id = p_championnat;
$$;

comment on function public.pronostics_du_championnat(uuid, uuid) is
  'Pronostics de tous les membres d''un championnat pour un GP, avec leur voiture, leur livrée et leur total. Réservée au backend.';

revoke all on function public.pronostics_du_championnat(uuid, uuid) from public;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from anon;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from authenticated;
grant execute on function public.pronostics_du_championnat(uuid, uuid) to service_role;
