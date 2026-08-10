-- =============================================================================
-- Étape 3 — Championnats : tables, RLS, et fonctions appelées par le backend
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI.
-- La clé anonyme ne suffit pas : cette migration référence le schéma `auth`.
--
-- La migration est idempotente : la rejouer ne casse rien.
-- =============================================================================

-- --  1. Les tables  ----------------------------------------------------------

create table if not exists public.championnats (
  id              uuid primary key default gen_random_uuid(),
  nom             text        not null,
  code_invitation text        not null unique,
  cree_par        uuid        not null references auth.users (id),
  cree_le         timestamptz not null default now(),

  -- Mêmes bornes que le contrôle de saisie du frontend : celui-ci peut être
  -- contourné, pas la base.
  constraint championnats_nom_longueur
    check (char_length(trim(nom)) between 2 and 40),

  -- 6 caractères alphanumériques majuscules, sans tiret ni séparateur
  -- (règle métier 4.5). La contrainte interdit qu'un code mal formé entre en
  -- base par un autre chemin que le générateur du backend.
  constraint championnats_code_format
    check (code_invitation ~ '^[A-Z0-9]{6}$')
);

comment on table public.championnats is
  'Un championnat de pronostics. Le code d''invitation sert à le rejoindre.';
comment on column public.championnats.code_invitation is
  '6 caractères alphanumériques majuscules, unique. Généré par le backend.';

-- `cree_par` ne cascade volontairement pas : supprimer le compte du créateur ne
-- doit pas emporter le championnat de tous les autres membres. La suppression
-- d'un compte ayant créé un championnat échouera donc tant que ce cas n'aura
-- pas de règle explicite — il n'en a pas encore.

create table if not exists public.membres_championnat (
  championnat_id uuid        not null references public.championnats (id) on delete cascade,
  profil_id      uuid        not null references auth.users (id) on delete cascade,
  rejoint_le     timestamptz not null default now(),

  primary key (championnat_id, profil_id)
);

comment on table public.membres_championnat is
  'Appartenance d''un membre à un championnat. `rejoint_le` sert au départage des égalités (règle 4.6).';

-- La clé primaire indexe déjà (championnat_id, profil_id) : elle couvre les
-- recherches par championnat. « Mes championnats » part du profil, d'où ce
-- second index — sans lui, chaque affichage de l'accueil balaie toute la table.
create index if not exists membres_championnat_profil_idx
  on public.membres_championnat (profil_id);

-- --  2. Droits sur les tables  -----------------------------------------------

-- Supabase accorde d'ordinaire ces droits automatiquement aux nouvelles tables
-- du schéma `public`, via ses privilèges par défaut. On les écrit quand même :
-- la migration reste alors correcte si elle est rejouée sur une base où ces
-- privilèges par défaut ne sont pas en place.
--
-- Ce sont des droits de table, pas des droits de ligne : c'est la RLS de la
-- section 3 qui décide, ligne par ligne, ce que chacun voit et modifie. `anon`
-- n'est jamais servi — rien ici n'est public.
grant select, insert, update, delete on public.championnats to authenticated;
grant select, insert, delete on public.membres_championnat to authenticated;
grant all on public.championnats, public.membres_championnat to service_role;

-- --  3. Test d'appartenance, sans récursion  ---------------------------------

-- Les deux politiques de lecture demandées se formulent « il existe une ligne
-- dans membres_championnat avec ce championnat_id et profil_id = auth.uid() ».
-- Écrite telle quelle dans une politique DE membres_championnat, la condition
-- interroge la table que la politique protège : PostgreSQL détecte la récursion
-- et refuse la requête (42P17). La politique de `championnats` tomberait dans le
-- même piège, puisqu'une sous-requête sur `membres_championnat` déclenche à son
-- tour la politique de cette table.
--
-- `security definer` casse la boucle : la fonction lit la table sans repasser
-- par les politiques. La sémantique reste exactement celle demandée.
create or replace function public.est_membre(p_championnat uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.membres_championnat m
    where m.championnat_id = p_championnat
      and m.profil_id = (select auth.uid())
  );
$$;

comment on function public.est_membre(uuid) is
  'Vrai si l''utilisateur courant est membre du championnat. Utilisée par les politiques RLS.';

revoke all on function public.est_membre(uuid) from public;
grant execute on function public.est_membre(uuid) to authenticated;

-- --  4. Sécurité au niveau des lignes  ---------------------------------------

alter table public.championnats enable row level security;
alter table public.membres_championnat enable row level security;

-- championnats — lecture réservée aux membres.
drop policy if exists "Championnats lisibles par leurs membres" on public.championnats;
create policy "Championnats lisibles par leurs membres"
  on public.championnats for select
  to authenticated
  using (public.est_membre(id));

drop policy if exists "Creation reservee aux connectes" on public.championnats;
create policy "Creation reservee aux connectes"
  on public.championnats for insert
  to authenticated
  with check ((select auth.uid()) is not null);

drop policy if exists "Seul le createur modifie" on public.championnats;
create policy "Seul le createur modifie"
  on public.championnats for update
  to authenticated
  using (cree_par = (select auth.uid()))
  with check (cree_par = (select auth.uid()));

drop policy if exists "Seul le createur supprime" on public.championnats;
create policy "Seul le createur supprime"
  on public.championnats for delete
  to authenticated
  using (cree_par = (select auth.uid()));

-- membres_championnat — on ne voit que les membres des championnats partagés.
drop policy if exists "Membres visibles entre membres" on public.membres_championnat;
create policy "Membres visibles entre membres"
  on public.membres_championnat for select
  to authenticated
  using (public.est_membre(championnat_id));

drop policy if exists "Adhesion reservee aux connectes" on public.membres_championnat;
create policy "Adhesion reservee aux connectes"
  on public.membres_championnat for insert
  to authenticated
  with check ((select auth.uid()) is not null);

drop policy if exists "Chacun quitte pour lui-meme" on public.membres_championnat;
create policy "Chacun quitte pour lui-meme"
  on public.membres_championnat for delete
  to authenticated
  using (profil_id = (select auth.uid()));

-- --  5. Création atomique d'un championnat  ----------------------------------

-- Créer un championnat, c'est insérer deux lignes : le championnat lui-même, et
-- son créateur comme premier membre. Deux appels REST séparés laisseraient, en
-- cas d'échec du second, un championnat sans aucun membre — donc invisible pour
-- tout le monde, y compris son créateur, et impossible à rejoindre puisque
-- personne ne connaît son code. Le corps d'une fonction s'exécute dans une
-- seule transaction : les deux insertions passent ou aucune.
--
-- La collision de code d'invitation remonte telle quelle (unique_violation) :
-- c'est le backend qui retente avec un nouveau code.
create or replace function public.creer_championnat(
  p_nom      text,
  p_code     text,
  p_createur uuid
)
returns public.championnats
language plpgsql
security definer
set search_path = ''
as $$
declare
  cree public.championnats;
begin
  insert into public.championnats (nom, code_invitation, cree_par)
  values (trim(p_nom), upper(trim(p_code)), p_createur)
  returning * into cree;

  insert into public.membres_championnat (championnat_id, profil_id)
  values (cree.id, p_createur);

  return cree;
end;
$$;

comment on function public.creer_championnat(text, text, uuid) is
  'Crée un championnat et y inscrit son créateur, dans la même transaction. Réservée au backend.';

-- `p_createur` est un paramètre : appelable par un client authentifié, cette
-- fonction `security definer` permettrait de créer un championnat au nom de
-- quelqu'un d'autre. Seul le backend, qui a vérifié le jeton, y a droit.
revoke all on function public.creer_championnat(text, text, uuid) from public;
grant execute on function public.creer_championnat(text, text, uuid) to service_role;

-- --  6. Liste des championnats d'un membre, avec leur nombre de membres  -----

create or replace function public.mes_championnats(p_profil uuid)
returns table (
  id              uuid,
  nom             text,
  code_invitation text,
  cree_par        uuid,
  cree_le         timestamptz,
  rejoint_le      timestamptz,
  nombre_membres  bigint
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
    ) as nombre_membres
  from public.membres_championnat m
  join public.championnats c on c.id = m.championnat_id
  where m.profil_id = p_profil
  order by m.rejoint_le;
$$;

comment on function public.mes_championnats(uuid) is
  'Championnats dont le profil est membre, avec leur effectif. Réservée au backend.';

revoke all on function public.mes_championnats(uuid) from public;
grant execute on function public.mes_championnats(uuid) to service_role;
