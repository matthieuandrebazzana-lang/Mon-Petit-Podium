-- =============================================================================
-- Photos : avatar d'un joueur, photo d'un championnat
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, APRÈS les quinze
-- migrations précédentes. Elle suppose :
--   - `public.profils`      (migration 20260809191018) : elle l'altère ;
--   - `public.championnats` (migration 20260810163435) : elle l'altère, et elle
--     REMPLACE `public.mes_championnats`, qu'elle doit d'abord SUPPRIMER (voir
--     la note §5) ;
--   - `public.classement_du_championnat` et `public.pronostics_du_championnat`
--     dans leur version de la migration 20260819124500 : elle REMPLACE les deux.
--
-- Contexte : jusqu'ici un joueur ne se reconnaissait qu'à sa voiture et à son
-- pseudo. Il peut désormais poser une photo, et un championnat aussi. Les deux
-- colonnes ajoutées ici ne portent qu'une **URL publique de Supabase Storage** :
-- rien n'est stocké en base64, ni dans PostgreSQL. Une image de 2 Mo en base64
-- pèserait 2,7 Mo dans une colonne `text`, serait relue à chaque classement et
-- traverserait le réseau à chaque affichage.
--
-- La migration ne crée AUCUNE table : deux colonnes, deux contraintes, deux
-- compartiments de stockage avec leurs politiques, trois fonctions remplacées.
-- Elle est idempotente : la rejouer ne casse rien et ne retouche aucune photo.
--
-- ATTENTION À L'ORDRE, comme pour les migrations 8, 9, 10 et 12 : elle remplace
-- `mes_championnats` (créée par la 2), `classement_du_championnat` (par la 8,
-- remplacée par la 12) et `pronostics_du_championnat` (par la 10, remplacée par
-- la 12). Rejouer l'une de ces trois migrations APRÈS celle-ci restaurerait leur
-- version d'avant : les photos disparaîtraient des cartes de l'accueil, des
-- classements et du tableau des résultats — sans rien casser d'autre, le
-- frontend retombant sur les initiales. Si l'une des trois est rejouée pour une
-- raison quelconque, rejouer celle-ci derrière.
-- =============================================================================


-- --  1. Les deux colonnes  ----------------------------------------------------

-- `avatar_url` sur le joueur, `photo_url` sur le championnat. Toutes deux
-- nullables, et c'est l'état par défaut : ni l'inscription ni la création d'un
-- championnat ne demandent de photo, et l'interface se comporte exactement comme
-- avant tant qu'elles valent `null`. Aucun défaut de colonne n'est posé — une
-- URL par défaut serait une photo que personne n'a choisie.
alter table public.profils
  add column if not exists avatar_url text;

alter table public.championnats
  add column if not exists photo_url text;

comment on column public.profils.avatar_url is
  'URL publique Supabase Storage de la photo de profil (compartiment « avatars »), ou NULL. Jamais de base64.';
comment on column public.championnats.photo_url is
  'URL publique Supabase Storage de la photo du championnat (compartiment « championnats »), ou NULL. Jamais de base64.';


-- --  2. Les deux contraintes  -------------------------------------------------

-- Les URL sont contraintes par leur FORME, jamais par le nom d'hôte du projet.
-- C'est la même doctrine que `profils_livree_ecurie_format` : coder ici l'URL du
-- projet Supabase figerait la base sur un projet, et une restauration dans un
-- projet neuf refuserait alors toutes les photos existantes. Le rattachement au
-- projet est vérifié côté backend (`app/api/stockage.py`), qui connaît
-- `SUPABASE_URL` — c'est LUI qui empêche d'enregistrer l'URL d'un tiers.
--
-- `https` et non `http` : la valeur part telle quelle dans un attribut `src`, et
-- une image en clair sur une page servie en HTTPS est bloquée par le navigateur.
-- Le plafond de 512 caractères borne ce qu'une colonne relue à chaque classement
-- peut peser ; un chemin `{uuid}/avatar.webp` en fait moins de cent cinquante.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profils'::regclass
      and conname  = 'profils_avatar_url_format'
  ) then
    alter table public.profils
      add constraint profils_avatar_url_format
      check (avatar_url is null or avatar_url ~ '^https://[^[:space:]]{10,505}$');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.championnats'::regclass
      and conname  = 'championnats_photo_url_format'
  ) then
    alter table public.championnats
      add constraint championnats_photo_url_format
      check (photo_url is null or photo_url ~ '^https://[^[:space:]]{10,505}$');
  end if;
end $$;


-- --  3. Les deux compartiments de stockage  -----------------------------------

-- Publics tous les deux : une photo de profil s'affiche sur la carte d'un autre
-- joueur, dans un classement partagé, sur la piste — et une photo de championnat
-- sur la carte d'accueil de chacun de ses membres. Un compartiment privé
-- obligerait à signer une URL par image et par affichage, donc un aller-retour
-- réseau par vignette d'un classement de douze.
--
-- **Le plafond de taille et la liste des types vivent ICI, pas dans le client.**
-- Un client peut mentir sur les deux : c'est le compartiment qui refuse. Le
-- frontend fait la même vérification avant l'envoi, mais pour dire non tout de
-- suite plutôt que pour garder quoi que ce soit — 2 Mo montés sur un réseau
-- mobile avant d'être refusés seraient deux Mo perdus.
--
-- 2 Mo = 2 097 152 octets. Trois types acceptés : jpeg, png, webp. Le `heic` de
-- l'appareil photo d'un iPhone n'y est pas, et c'est sans conséquence : Safari
-- convertit en jpeg à la sélection d'un fichier dans un `<input type="file">`.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 2097152,
   array['image/jpeg', 'image/png', 'image/webp']),
  ('championnats', 'championnats', true, 2097152,
   array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public            = excluded.public,
      file_size_limit   = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- --  4. Les politiques de stockage  -------------------------------------------

-- `storage.objects` porte sa propre RLS, et Supabase l'active par défaut. La
-- réaffirmer ici ne coûte rien et décrit complètement l'état supposé.
alter table storage.objects enable row level security;

-- **Lecture publique, `anon` compris.** C'est la contrepartie d'un compartiment
-- public, et le même arbitrage que pour `grands_prix` et `cotes` : ces images
-- s'affichent de toute façon sur des écrans qu'un membre partage.
drop policy if exists "Photos lisibles par tous" on storage.objects;
create policy "Photos lisibles par tous"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id in ('avatars', 'championnats'));

-- **Écriture : le premier segment du chemin EST l'autorisation.** Un avatar vit
-- sous `{profil_id}/avatar.{ext}` ; la politique compare ce segment à
-- `auth.uid()`. Personne ne peut donc écrire dans le dossier d'un autre, quel
-- que soit le client utilisé — c'est la base qui refuse, pas le code de l'écran.
--
-- Les trois verbes sont couverts séparément, et il en faut bien trois :
-- `insert` pose la première photo, `update` écrase la suivante (le chemin est
-- stable, voir §3 de `docs/database.md`), `delete` sert au bouton « Supprimer
-- la photo ». Sous RLS, ce qu'aucune politique n'autorise est refusé : en
-- oublier un fermerait silencieusement une des trois.
drop policy if exists "Chacun depose son avatar" on storage.objects;
create policy "Chacun depose son avatar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Chacun remplace son avatar" on storage.objects;
create policy "Chacun remplace son avatar"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Chacun supprime son avatar" on storage.objects;
create policy "Chacun supprime son avatar"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- **La photo d'un championnat appartient à son créateur.** Le premier segment du
-- chemin est l'identifiant du championnat, et la politique remonte à
-- `championnats.cree_par`. Aucune récursion à craindre ici : la sous-requête
-- porte sur `public.championnats`, pas sur `storage.objects` que la politique
-- protège — le piège `42P17` de `docs/database.md` §2 ne s'applique pas.
--
-- Conséquence assumée, la même qu'à la migration 4 : sur un championnat dont le
-- créateur a supprimé son compte, `cree_par` vaut `null` et plus personne ne
-- peut changer la photo. Elle reste affichée, ce qui est le comportement voulu —
-- le championnat survit à son créateur.
drop policy if exists "Le createur depose la photo du championnat" on storage.objects;
create policy "Le createur depose la photo du championnat"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'championnats'
    and exists (
      select 1 from public.championnats c
      where c.id::text = (storage.foldername(name))[1]
        and c.cree_par = (select auth.uid())
    )
  );

drop policy if exists "Le createur remplace la photo du championnat" on storage.objects;
create policy "Le createur remplace la photo du championnat"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'championnats'
    and exists (
      select 1 from public.championnats c
      where c.id::text = (storage.foldername(name))[1]
        and c.cree_par = (select auth.uid())
    )
  )
  with check (
    bucket_id = 'championnats'
    and exists (
      select 1 from public.championnats c
      where c.id::text = (storage.foldername(name))[1]
        and c.cree_par = (select auth.uid())
    )
  );

drop policy if exists "Le createur supprime la photo du championnat" on storage.objects;
create policy "Le createur supprime la photo du championnat"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'championnats'
    and exists (
      select 1 from public.championnats c
      where c.id::text = (storage.foldername(name))[1]
        and c.cree_par = (select auth.uid())
    )
  );


-- --  5. La liste des championnats porte la photo  -----------------------------

-- **`drop function` puis `create`, et non `create or replace`.** C'est la seule
-- migration du projet à devoir le faire : `mes_championnats` déclare un
-- `returns table (…)`, et PostgreSQL refuse de remplacer une fonction dont le
-- type de retour change (`42P13 : cannot change return type of existing
-- function`). Ajouter une colonne au tableau EST un changement de type.
--
-- La suppression est sans risque : rien ne dépend de cette fonction en base — ni
-- vue, ni trigger, ni contrainte — seul le backend l'appelle. Le `if exists`
-- rend l'opération rejouable sur une base où elle n'existerait pas encore.
--
-- Les droits sont reposés juste après : `drop` les emporte avec la fonction, et
-- une fonction recréée est exécutable par `public` par défaut. Les oublier
-- l'ouvrirait à `anon`, c'est-à-dire à n'importe qui muni de la clé publique du
-- frontend — qui pourrait alors lire les championnats de n'importe quel profil.
drop function if exists public.mes_championnats(uuid);

create function public.mes_championnats(p_profil uuid)
returns table (
  id              uuid,
  nom             text,
  code_invitation text,
  cree_par        uuid,
  cree_le         timestamptz,
  rejoint_le      timestamptz,
  nombre_membres  bigint,
  photo_url       text
)
language sql
security definer
stable
set search_path = ''
as $$
  select
    c.id,
    c.nom,
    c.code_invitation,
    c.cree_par,
    c.cree_le,
    m.rejoint_le,
    (
      select count(*)
      from public.membres_championnat compte
      where compte.championnat_id = c.id
    ) as nombre_membres,
    c.photo_url
  from public.membres_championnat m
  join public.championnats c on c.id = m.championnat_id
  where m.profil_id = p_profil
  order by m.rejoint_le;
$$;

comment on function public.mes_championnats(uuid) is
  'Championnats dont le profil est membre, avec leur effectif et leur photo. Réservée au backend.';

revoke all on function public.mes_championnats(uuid) from public;
revoke all on function public.mes_championnats(uuid) from anon;
revoke all on function public.mes_championnats(uuid) from authenticated;
grant execute on function public.mes_championnats(uuid) to service_role;


-- --  6. Le classement porte l'avatar  -----------------------------------------

-- Même fonction qu'à la migration 20260819124500, à UN champ près :
-- `avatar_url`. Le classement d'un championnat et la vue piste sont les deux
-- écrans où l'on cherche quelqu'un dans une liste ; c'est là que la photo sert
-- le plus, et il n'y a aucune raison de la relire profil par profil quand cette
-- fonction lit déjà la table.
--
-- Le reste du corps est INCHANGÉ : règle 4.6, `row_number` et non `rank`,
-- `left join lateral` pour ne pas faire disparaître un membre sans pronostic,
-- `ordre_inscription` conservé, `coalesce` sur les couleurs et le mode.
--
-- **Aucun `coalesce` sur `avatar_url`, et c'est délibéré.** Les couleurs ont un
-- défaut parce qu'un SVG sans `fill` peint du transparent ; une photo absente,
-- elle, a une réponse à l'écran — les initiales sur fond dérivé du pseudo, qui
-- sont l'affichage d'origine. `null` est donc la valeur juste, et « pas de
-- photo » ne se confond avec rien.
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
  'Classement d''un championnat, trié selon les départages de la règle 4.6, voitures, livrées et avatars compris. Réservé au backend : l''appartenance est vérifiée avant l''appel.';

revoke all on function public.classement_du_championnat(uuid) from public;
revoke all on function public.classement_du_championnat(uuid) from anon;
revoke all on function public.classement_du_championnat(uuid) from authenticated;
grant execute on function public.classement_du_championnat(uuid) to service_role;


-- --  7. Le tableau des résultats porte l'avatar  ------------------------------

-- Même fonction qu'à la migration 20260819124500, à UN champ près, et pour la
-- même raison qu'au classement : le résumé d'un Grand Prix (maquette 11) est une
-- liste de membres, et on y cherche quelqu'un.
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
        -- La photo, sans repli : « pas de photo » se dit `null` et s'affiche en
        -- initiales (voir §6).
        'avatar_url', pr.avatar_url,
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
  'Pronostics de tous les membres d''un championnat pour un GP, avec leur voiture, leur livrée, leur avatar et leur total. Réservée au backend.';

revoke all on function public.pronostics_du_championnat(uuid, uuid) from public;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from anon;
revoke all on function public.pronostics_du_championnat(uuid, uuid) from authenticated;
grant execute on function public.pronostics_du_championnat(uuid, uuid) to service_role;
