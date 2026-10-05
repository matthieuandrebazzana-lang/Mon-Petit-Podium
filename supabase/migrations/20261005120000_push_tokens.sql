-- =============================================================================
--  Migration 30 — Notifications push : jetons APNs et envois déjà faits
-- =============================================================================
--
-- Les notifications sont envoyées par le backend via APNs, jamais programmées
-- localement par l'app (`docs/decisions.md` §25). Deux tables :
--
--   1. `push_tokens` — un jeton APNs par appareil, rattaché au compte connecté
--      et à la langue de son interface (`fr` | `en`) : le texte envoyé est
--      celui de cette langue. Enregistré par `POST /push/token` à la
--      connexion, supprimé par `DELETE /push/token` à la déconnexion ; la
--      suppression de compte l'emporte par cascade depuis `auth.users`.
--
--      **Le jeton est la clé primaire, pas le couple (compte, jeton).** Un
--      jeton désigne un appareil : si un autre compte se connecte sur le même
--      iPhone, la ligne change de propriétaire au lieu d'en créer une seconde
--      — sinon l'ancien compte continuerait de recevoir ses notifications sur
--      un téléphone qui n'est plus le sien. Ce transfert passe par le backend
--      (clé de service) : la RLS, elle, ne laisse un compte toucher qu'à ses
--      propres lignes.
--
--   2. `notifications_envoyees` — une ligne par (Grand Prix, événement) déjà
--      envoyé. La clé primaire est la garantie « jamais deux fois » : le job
--      réserve la ligne AVANT d'envoyer (`insert … on conflict do nothing`),
--      et n'envoie que s'il l'a obtenue. Aucune politique : seul le backend
--      la lit et l'écrit.
--
-- **Amorçage.** Les Grands Prix déjà `termine` reçoivent leur ligne
-- `resultats` : sans elle, le premier passage du job annoncerait les résultats
-- de toute la saison écoulée.
--
-- Idempotente. À appliquer AVANT le backend qui l'utilise : tant qu'elle
-- manque, `POST /push/token` rend une erreur et le job journalise sans rien
-- envoyer.
-- =============================================================================


-- --  1. push_tokens  ----------------------------------------------------------

create table if not exists public.push_tokens (
  token          text        primary key,
  user_id        uuid        not null references auth.users (id) on delete cascade,
  plateforme     text        not null default 'ios',
  langue         text        not null default 'fr',
  cree_le        timestamptz not null default now(),
  mis_a_jour_le  timestamptz not null default now(),
  constraint push_tokens_plateforme_valide check (plateforme in ('ios')),
  constraint push_tokens_langue_valide     check (langue in ('fr', 'en')),
  constraint push_tokens_token_non_vide    check (length(token) between 1 and 200)
);

create index if not exists push_tokens_user_id_idx
  on public.push_tokens (user_id);

comment on table public.push_tokens is
  'Jetons APNs, un par appareil. Écrits par le backend (POST/DELETE /push/token), supprimés sur réponse 410/BadDeviceToken d''APNs et par cascade à la suppression du compte.';
comment on column public.push_tokens.langue is
  'Langue de l''interface au moment de l''enregistrement : la notification part dans cette langue.';

alter table public.push_tokens enable row level security;

drop policy if exists "Jetons push lisibles par leur proprietaire"   on public.push_tokens;
drop policy if exists "Jetons push inserables par leur proprietaire" on public.push_tokens;
drop policy if exists "Jetons push modifiables par leur proprietaire" on public.push_tokens;
drop policy if exists "Jetons push supprimables par leur proprietaire" on public.push_tokens;

create policy "Jetons push lisibles par leur proprietaire"
  on public.push_tokens for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Jetons push inserables par leur proprietaire"
  on public.push_tokens for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "Jetons push modifiables par leur proprietaire"
  on public.push_tokens for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "Jetons push supprimables par leur proprietaire"
  on public.push_tokens for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.push_tokens from anon;
grant select, insert, update, delete on public.push_tokens to authenticated;


-- --  2. notifications_envoyees  ----------------------------------------------

create table if not exists public.notifications_envoyees (
  gp_id       uuid        not null references public.grands_prix (id) on delete cascade,
  evenement   text        not null,
  envoyee_le  timestamptz not null default now(),
  primary key (gp_id, evenement),
  constraint notifications_envoyees_evenement_valide check (evenement in (
    'ouverture_24h',     -- date_qualifications − 25 h
    'ouverture',         -- date_qualifications − 1 h
    'derniere_chance',   -- date_course − 1 h
    'resultats'          -- statut passé à termine
  ))
);

comment on table public.notifications_envoyees is
  'Une ligne par (GP, événement) déjà notifié. Réservée par le job AVANT l''envoi : la clé primaire interdit le doublon.';

alter table public.notifications_envoyees enable row level security;
revoke all on public.notifications_envoyees from anon, authenticated;


-- --  3. Amorçage : les résultats déjà publiés ne se renotifient pas  ----------

insert into public.notifications_envoyees (gp_id, evenement)
select id, 'resultats'
from public.grands_prix
where statut = 'termine'
on conflict do nothing;
