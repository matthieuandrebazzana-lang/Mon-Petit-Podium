-- =============================================================================
-- Championnat « Démo F1 » — 01 · COMPTES DÉMO, VOITURES, CHAMPIONNAT, MEMBRES
-- =============================================================================
--
-- Ce n'est PAS une migration : à ne jamais copier dans `supabase/migrations/`.
-- Sert uniquement aux captures de la fiche App Store. Procédure complète :
-- `docs/contexte-chat.md`, section « CHAMPIONNAT DÉMO ».
--
-- Exécuter `00_controles.sql` AVANT (§1, §4) et APRÈS (§1, §2, §5).
-- Idempotent : rejoué, il ne crée rien de plus et repose les mêmes voitures.
-- Tout tient dans une transaction : un garde-fou qui lève annule tout.
--
-- Ce que crée ce script :
--   · 8 comptes `auth.users` — Alex, Maya, Leo, Zoe, Hugo, Lina, Noah, Eva —
--     et leurs profils (par le trigger d'inscription, comme une vraie
--     inscription) ;
--   · le championnat « Démo F1 », code `DEMOF1`, créé par Alex ;
--   · 9 adhésions : les 8 comptes démo et le reviewer.
--
-- Pourquoi les comptes ne sont PAS connectables, par quatre verrous :
--   1. adresse `demo-<pseudo>@greedf1.invalid` — `.invalid` est réservé par la
--      RFC 2606 : aucun e-mail (confirmation, lien magique, réinitialisation)
--      ne peut y arriver ;
--   2. mot de passe : un hachage bcrypt de deux UUID tirés DANS la base, jamais
--      affiché, jamais écrit nulle part — personne ne le connaît ;
--   3. aucune ligne `auth.identities` : aucun fournisseur (e-mail, Google,
--      Apple) n'est rattaché au compte ;
--   4. `banned_until` en l'an 2999 : GoTrue refuse toute ouverture de session.
-- Et `email_confirmed_at` posé : un `insert` SQL n'envoie JAMAIS d'e-mail —
-- seul GoTrue en envoie, et il n'est pas sollicité ici.
--
-- Marquage : `raw_app_meta_data.demo = true`. `app_metadata` n'est modifiable
-- que par la clé de service — un utilisateur ne peut ni se l'attribuer ni se
-- le retirer. `profils` n'a pas de colonne pour cela, et on n'en ajoute pas.
--
-- Les jetons `*_token` valent '' et non NULL : GoTrue lit ces colonnes comme
-- des chaînes, et un NULL fait échouer la liste des utilisateurs du dashboard.
-- =============================================================================

begin;

-- -- Garde-fous -----------------------------------------------------------------
do $$
declare
  conflits text;
begin
  if (select count(*) from auth.users
       where lower(email) = 'matthieu.andre.bazzana+reviewer@gmail.com') <> 1 then
    raise exception 'Compte reviewer introuvable (ou en double) : rien n''est créé.';
  end if;

  -- Un pseudo pris par un compte qui n'est pas la démo ferait échouer le
  -- trigger d'inscription. On le dit en clair avant.
  select string_agg(p.pseudo, ', ') into conflits
    from public.profils p
   where lower(p.pseudo) in ('alex', 'maya', 'leo', 'zoe', 'hugo', 'lina', 'noah', 'eva')
     and p.id not in (
       'f3b1a516-f030-4887-a2db-4172e5afa9e4', 'e0bdb4a9-6089-4ac0-b8ce-52b9134d957c',
       '3c155460-a37b-4d63-80ed-fcf4dd80e996', '64810a82-4ac1-41a4-b403-3efe89675090',
       '41e08303-868d-476e-941f-34268d5569af', '436330e9-96e6-45b1-8c41-c66692c785e1',
       '7a9ee9af-1cac-464b-a157-dd2c1efea49d', '9907a658-2bc7-4a4c-8a83-aebac1654538');
  if conflits is not null then
    raise exception 'Pseudos déjà pris par de vrais comptes : %. Rien n''est créé.', conflits;
  end if;

  if exists (select 1 from public.championnats
              where code_invitation = 'DEMOF1'
                and id <> '67dc7eb8-a039-43da-9b2f-d7b782e1b20e') then
    raise exception 'Le code DEMOF1 appartient déjà à un vrai championnat. Rien n''est créé.';
  end if;

  -- Un identifiant démo déjà porté par un compte NON marqué démo : jamais
  -- censé arriver, et surtout jamais à écraser.
  if exists (select 1 from auth.users
              where id in (
                'f3b1a516-f030-4887-a2db-4172e5afa9e4', 'e0bdb4a9-6089-4ac0-b8ce-52b9134d957c',
                '3c155460-a37b-4d63-80ed-fcf4dd80e996', '64810a82-4ac1-41a4-b403-3efe89675090',
                '41e08303-868d-476e-941f-34268d5569af', '436330e9-96e6-45b1-8c41-c66692c785e1',
                '7a9ee9af-1cac-464b-a157-dd2c1efea49d', '9907a658-2bc7-4a4c-8a83-aebac1654538')
                and (raw_app_meta_data ->> 'demo' is distinct from 'true'
                     or email not like 'demo-%@greedf1.invalid')) then
    raise exception 'Un identifiant démo est porté par un compte non démo. Rien n''est créé.';
  end if;
end $$;


-- -- Les huit comptes ------------------------------------------------------------
-- `instance_id` et `aud` sont recopiés du compte reviewer : la valeur que
-- GoTrue a lui-même écrite sur ce projet, plutôt qu'une constante supposée.
with comptes (id, pseudo) as (
  values
    ('f3b1a516-f030-4887-a2db-4172e5afa9e4'::uuid, 'Alex'),
    ('e0bdb4a9-6089-4ac0-b8ce-52b9134d957c'::uuid, 'Maya'),
    ('3c155460-a37b-4d63-80ed-fcf4dd80e996'::uuid, 'Leo'),
    ('64810a82-4ac1-41a4-b403-3efe89675090'::uuid, 'Zoe'),
    ('41e08303-868d-476e-941f-34268d5569af'::uuid, 'Hugo'),
    ('436330e9-96e6-45b1-8c41-c66692c785e1'::uuid, 'Lina'),
    ('7a9ee9af-1cac-464b-a157-dd2c1efea49d'::uuid, 'Noah'),
    ('9907a658-2bc7-4a4c-8a83-aebac1654538'::uuid, 'Eva')
),
modele as (
  select instance_id, aud from auth.users
   where lower(email) = 'matthieu.andre.bazzana+reviewer@gmail.com'
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, banned_until,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  m.instance_id, c.id, m.aud, 'authenticated',
  'demo-' || lower(c.pseudo) || '@greedf1.invalid',
  extensions.crypt(gen_random_uuid()::text || gen_random_uuid()::text, extensions.gen_salt('bf')),
  now(), '2999-12-31 00:00:00+00',
  jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'demo', true),
  jsonb_build_object('pseudo', c.pseudo),
  now(), now(),
  '', '', '', ''
from comptes c cross join modele m
on conflict (id) do nothing;


-- -- Les voitures ----------------------------------------------------------------
-- Huit livrées `perso`, huit couples de couleurs de la palette
-- (`frontend/src/lib/palette.js`), huit encres, huit numéros. En livrée perso,
-- le numéro ET le pseudo sont peints sur `couleur1` : chaque encre y a été
-- MESURÉE, au-dessus de 4,5:1 (le grand texte n'en demande que 3) —
--   Alex 11,85 · Maya 4,73 · Leo 7,10 · Zoe 5,47 · Hugo 14,97 · Lina 6,18 ·
--   Noah 4,65 · Eva 7,76.
update public.profils p
   set couleur1      = v.couleur1,
       couleur2      = v.couleur2,
       couleur_texte = v.couleur_texte,
       numero        = v.numero,
       livree_mode   = 'perso',
       livree_ecurie = null,
       avatar_url    = null
  from (values
    ('f3b1a516-f030-4887-a2db-4172e5afa9e4'::uuid, '#003087', '#FFD700', '#FFFFFF',  7),
    ('e0bdb4a9-6089-4ac0-b8ce-52b9134d957c'::uuid, '#E8027B', '#000000', '#000000', 21),
    ('3c155460-a37b-4d63-80ed-fcf4dd80e996'::uuid, '#005C43', '#F5F0EB', '#F5F0EB', 14),
    ('64810a82-4ac1-41a4-b403-3efe89675090'::uuid, '#FF8000', '#2D2D2D', '#2D2D2D', 33),
    ('41e08303-868d-476e-941f-34268d5569af'::uuid, '#000000', '#CC0000', '#FFD700',  5),
    ('436330e9-96e6-45b1-8c41-c66692c785e1'::uuid, '#00D2BE', '#FFFFFF', '#003087', 18),
    ('7a9ee9af-1cac-464b-a157-dd2c1efea49d'::uuid, '#960064', '#C0C0C0', '#C0C0C0',  9),
    ('9907a658-2bc7-4a4c-8a83-aebac1654538'::uuid, '#FFD700', '#003087', '#800111', 42)
  ) v (id, couleur1, couleur2, couleur_texte, numero)
 where p.id = v.id;


-- -- Le championnat ----------------------------------------------------------------
-- Créé par Alex, un compte démo : le reviewer ne peut donc ni le renommer ni
-- le supprimer depuis l'app (« Seul le createur modifie »). Pas de photo.
insert into public.championnats (id, nom, code_invitation, cree_par, cree_le)
values ('67dc7eb8-a039-43da-9b2f-d7b782e1b20e', 'Démo F1', 'DEMOF1',
        'f3b1a516-f030-4887-a2db-4172e5afa9e4', '2026-08-01 18:00:00+00')
on conflict (id) do nothing;

-- `rejoint_le` étalé : c'est le 3ᵉ critère de départage (`metier.md` §7), et
-- des dates distinctes rendent l'ordre lisible plutôt que dû à `profil_id`.
insert into public.membres_championnat (championnat_id, profil_id, rejoint_le)
select '67dc7eb8-a039-43da-9b2f-d7b782e1b20e'::uuid, v.profil_id, v.rejoint_le
  from (values
    ('f3b1a516-f030-4887-a2db-4172e5afa9e4'::uuid, '2026-08-01 18:00:00+00'::timestamptz),
    ('e0bdb4a9-6089-4ac0-b8ce-52b9134d957c'::uuid, '2026-08-01 19:12:00+00'),
    ('3c155460-a37b-4d63-80ed-fcf4dd80e996'::uuid, '2026-08-01 20:40:00+00'),
    ('64810a82-4ac1-41a4-b403-3efe89675090'::uuid, '2026-08-02 08:05:00+00'),
    ('41e08303-868d-476e-941f-34268d5569af'::uuid, '2026-08-02 12:31:00+00'),
    ('436330e9-96e6-45b1-8c41-c66692c785e1'::uuid, '2026-08-02 17:48:00+00'),
    ('7a9ee9af-1cac-464b-a157-dd2c1efea49d'::uuid, '2026-08-03 09:20:00+00'),
    ('9907a658-2bc7-4a4c-8a83-aebac1654538'::uuid, '2026-08-03 21:02:00+00')
  ) v (profil_id, rejoint_le)
union all
select '67dc7eb8-a039-43da-9b2f-d7b782e1b20e'::uuid, id, '2026-08-04 10:00:00+00'::timestamptz
  from auth.users
 where lower(email) = 'matthieu.andre.bazzana+reviewer@gmail.com'
on conflict do nothing;


-- -- Contrôle final : lève, et annule tout, si l'état n'est pas celui attendu ------
do $$
declare
  demo_ids uuid[];
begin
  select array_agg(id) into demo_ids from auth.users
   where raw_app_meta_data ->> 'demo' = 'true' and email like 'demo-%@greedf1.invalid';

  if coalesce(array_length(demo_ids, 1), 0) <> 8 then
    raise exception 'Attendu 8 comptes démo, trouvé %.', coalesce(array_length(demo_ids, 1), 0);
  end if;
  if (select count(*) from public.profils where id = any (demo_ids)) <> 8 then
    raise exception 'Un compte démo n''a pas de profil.';
  end if;
  if exists (select 1 from auth.identities where user_id = any (demo_ids)) then
    raise exception 'Un compte démo porte une identité : il serait connectable.';
  end if;
  if exists (select 1 from auth.users where id = any (demo_ids)
              and (banned_until is null or banned_until < '2999-01-01')) then
    raise exception 'Un compte démo n''est pas banni.';
  end if;
  if exists (select 1 from public.push_tokens where user_id = any (demo_ids)) then
    raise exception 'Un compte démo porte un jeton de notification.';
  end if;
  if (select count(*) from public.membres_championnat
       where championnat_id = '67dc7eb8-a039-43da-9b2f-d7b782e1b20e') <> 9 then
    raise exception 'Le championnat démo ne compte pas 9 membres.';
  end if;
  if exists (select 1 from public.membres_championnat
              where profil_id = any (demo_ids)
                and championnat_id <> '67dc7eb8-a039-43da-9b2f-d7b782e1b20e') then
    raise exception 'Un compte démo est membre d''un autre championnat.';
  end if;
end $$;

commit;
