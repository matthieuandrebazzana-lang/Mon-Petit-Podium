-- =============================================================================
-- Table des profils + unicité du pseudo
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI.
-- La clé anonyme ne suffit pas : cette migration touche au schéma `auth`.
--
-- Contexte : avant cette migration, le pseudo n'existait que dans
-- `auth.users.raw_user_meta_data`, un simple JSON sans aucune contrainte. Deux
-- membres pouvaient donc porter le même pseudo, ce qui rend un classement
-- illisible et une invitation ambiguë.
--
-- Le pseudo devient une colonne à part entière, unique et insensible à la
-- casse. Le reste du schéma (championnats, pronostics, cotes) relève de
-- l'étape 3 et n'est volontairement pas abordé ici.
--
-- La migration est idempotente : la rejouer ne casse rien.
-- =============================================================================

-- --  1. La table  ------------------------------------------------------------

create table if not exists public.profils (
  id         uuid primary key references auth.users (id) on delete cascade,
  pseudo     text        not null,
  cree_le    timestamptz not null default now(),
  modifie_le timestamptz not null default now(),

  -- Mêmes bornes que le contrôle de saisie du frontend (`lib/validation.js`).
  -- Le frontend peut être contourné, pas la base.
  constraint profils_pseudo_longueur check (char_length(trim(pseudo)) between 2 and 20)
);

comment on table public.profils is
  'Profil public d''un membre. Une ligne par utilisateur, créée automatiquement à l''inscription.';
comment on column public.profils.pseudo is
  'Nom affiché. Unique sans tenir compte de la casse : MaxV33 et maxv33 sont le même pseudo.';

-- --  2. LA contrainte demandée  ----------------------------------------------

-- Index unique sur `lower(pseudo)` plutôt qu'un simple `unique` sur la colonne.
-- Un UNIQUE nu laisserait coexister « MaxV33 » et « maxv33 », que tout le monde
-- lirait comme la même personne. L'extension citext ferait le même travail,
-- mais un index fonctionnel évite d'avoir une extension à gérer.
create unique index if not exists profils_pseudo_unique_idx
  on public.profils (lower(pseudo));

-- --  3. Reprise de l'existant  -----------------------------------------------

-- Les comptes créés avant cette migration n'ont pas de profil. On les rattrape
-- en dédoublonnant : si deux comptes portaient déjà le même pseudo dans leurs
-- métadonnées, le plus ancien le garde et les suivants sont suffixés. Sans
-- cela, l'index unique ferait échouer toute la migration.
insert into public.profils (id, pseudo)
select
  u.id,
  case
    when p.rang = 1 then p.pseudo_souhaite
    else left(p.pseudo_souhaite, 20 - length(p.rang::text) - 1) || '-' || p.rang
  end
from auth.users u
join (
  select
    id,
    pseudo_souhaite,
    row_number() over (
      partition by lower(pseudo_souhaite)
      order by created_at
    ) as rang
  from (
    select
      id,
      created_at,
      coalesce(
        nullif(trim(raw_user_meta_data ->> 'pseudo'), ''),
        'pilote-' || substr(replace(id::text, '-', ''), 1, 10)
      ) as pseudo_souhaite
    from auth.users
  ) base
) p on p.id = u.id
where not exists (select 1 from public.profils existant where existant.id = u.id)
on conflict (id) do nothing;

-- --  4. Création automatique à chaque inscription  ---------------------------

create or replace function public.gerer_nouvel_utilisateur()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pseudo_souhaite text;
  candidat        text;
  suffixe         int := 0;
begin
  pseudo_souhaite := nullif(trim(new.raw_user_meta_data ->> 'pseudo'), '');

  if pseudo_souhaite is not null then
    -- Pseudo choisi explicitement à l'inscription : on ne le remplace jamais en
    -- douce. S'il est déjà pris, l'insertion échoue et l'inscription entière est
    -- annulée. Le frontend vérifie la disponibilité en amont (voir
    -- `public.pseudo_disponible`), ce chemin ne sert que si deux personnes
    -- valident le même pseudo à quelques millisecondes d'intervalle.
    insert into public.profils (id, pseudo) values (new.id, pseudo_souhaite);
    return new;
  end if;

  -- Aucun pseudo fourni : c'est une inscription via Google ou Apple, qui n'en
  -- transmettent pas. On en fabrique un. Ici la collision est improbable mais
  -- ne doit surtout pas faire échouer l'inscription : on incrémente jusqu'à
  -- trouver un pseudo libre.
  candidat := 'pilote-' || substr(replace(new.id::text, '-', ''), 1, 10);
  loop
    begin
      insert into public.profils (id, pseudo) values (new.id, candidat);
      return new;
    exception when unique_violation then
      suffixe := suffixe + 1;
      if suffixe > 50 then
        raise;
      end if;
      candidat := 'pilote-' || substr(replace(new.id::text, '-', ''), 1, 6) || suffixe;
    end;
  end loop;
end;
$$;

comment on function public.gerer_nouvel_utilisateur() is
  'Crée le profil au moment de l''inscription, à partir du pseudo des métadonnées.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.gerer_nouvel_utilisateur();

-- --  5. Horodatage des modifications  ----------------------------------------

create or replace function public.marquer_modification()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.modifie_le := now();
  return new;
end;
$$;

drop trigger if exists profils_modifie_le on public.profils;
create trigger profils_modifie_le
  before update on public.profils
  for each row execute function public.marquer_modification();

-- --  6. Vérification de disponibilité, appelable avant l'inscription  --------

-- Le frontend doit pouvoir dire « ce pseudo est déjà pris » AVANT d'envoyer
-- l'inscription, sinon l'utilisateur découvre le problème après coup, une fois
-- son mot de passe saisi. La fonction est `security definer` parce que l'appel
-- vient d'un visiteur non connecté, qui n'a aucun droit de lecture sur la table.
--
-- Elle révèle qu'un pseudo est utilisé, sans dire par qui : c'est le compromis
-- normal d'un champ de pseudo, et ces pseudos sont de toute façon affichés
-- publiquement dans les classements. À ne surtout pas transposer aux emails,
-- eux ne doivent jamais être testables de l'extérieur.
create or replace function public.pseudo_disponible(pseudo_a_tester text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select not exists (
    select 1
    from public.profils
    where lower(pseudo) = lower(trim(pseudo_a_tester))
  );
$$;

comment on function public.pseudo_disponible(text) is
  'Vrai si le pseudo est libre. Appelable sans être connecté, pour le formulaire d''inscription.';

revoke all on function public.pseudo_disponible(text) from public;
grant execute on function public.pseudo_disponible(text) to anon, authenticated;

-- --  7. Sécurité au niveau des lignes  ---------------------------------------

alter table public.profils enable row level security;

-- Lecture ouverte aux membres connectés : les classements et les listes de
-- membres d'un championnat ont besoin des pseudos des autres.
drop policy if exists "Profils lisibles par les membres connectes" on public.profils;
create policy "Profils lisibles par les membres connectes"
  on public.profils for select
  to authenticated
  using (true);

-- Chacun ne modifie que son propre profil. L'unicité du pseudo reste garantie
-- par l'index : un renommage vers un pseudo pris échoue.
drop policy if exists "Chacun modifie son profil" on public.profils;
create policy "Chacun modifie son profil"
  on public.profils for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Aucune politique d'insertion ni de suppression, volontairement : un profil
-- naît avec son compte via le trigger, et meurt avec lui par cascade. Le
-- trigger étant `security definer`, il n'est pas soumis à ces politiques.
