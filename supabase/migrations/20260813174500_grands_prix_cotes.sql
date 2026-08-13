-- =============================================================================
-- Étape 4 — Grands Prix et cotes Unibet
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- comme les deux migrations précédentes.
--
-- La migration est idempotente : la rejouer ne casse rien et ne touche à
-- aucune donnée déjà enregistrée.
-- =============================================================================

-- --  1. Les Grands Prix  -----------------------------------------------------

create table if not exists public.grands_prix (
  id          uuid primary key default gen_random_uuid(),

  -- Identifiant du nœud Unibet du GP (préfixe `p`, ex : « p59405525 »). C'est
  -- la clé de rapprochement du scraper : elle seule permet de retrouver un GP
  -- déjà connu sans se fier à son nom, qui peut changer d'orthographe d'une
  -- semaine à l'autre (« GP Pays Bas », « GP Pays-Bas »…).
  id_unibet   text        not null unique,

  nom         text        not null,
  date_course timestamptz,

  -- a_venir      : découvert, les cotes peuvent encore bouger
  -- cotes_figees : cotes arrêtées après les qualifications (règle 4.3). Le
  --                scraper refuse alors d'y toucher — voir la note ci-dessous.
  -- termine      : course courue, points attribués
  statut      text        not null default 'a_venir',

  cree_le     timestamptz not null default now(),

  constraint grands_prix_statut_valide
    check (statut in ('a_venir', 'cotes_figees', 'termine'))
);

comment on table public.grands_prix is
  'Un Grand Prix découvert chez Unibet. `id_unibet` est la clé de rapprochement du scraper.';
comment on column public.grands_prix.statut is
  'a_venir | cotes_figees | termine. Un GP figé n''est plus re-scrapé (règle 4.3).';
comment on column public.grands_prix.date_course is
  'Heure de départ, en UTC. Unibet la donne en heure de Paris : la conversion est faite par le scraper.';

-- Le statut est écrit en clair plutôt qu'en type `enum` : ajouter une valeur à
-- un enum PostgreSQL est une migration à part entière, alors que les états d'un
-- week-end de course ne sont pas encore tous arrêtés (étapes 5 et 6). La
-- contrainte `check` donne la même garantie et se modifie sans cérémonie.

-- --  2. Les cotes  -----------------------------------------------------------

create table if not exists public.cotes (
  id                uuid primary key default gen_random_uuid(),
  gp_id             uuid not null references public.grands_prix (id) on delete cascade,

  -- Marché normalisé (« vainqueur », « podium », « ecurie-vainqueur »…) : c'est
  -- lui qui sert de clé de regroupement dans l'API et l'interface.
  marche            text not null,

  -- Libellé d'origine du marché, tel qu'Unibet l'écrit (« Ecurie Vainqueur »).
  -- Ajout par rapport au strict nécessaire, et assumé : sans lui, l'interface
  -- devrait reconstituer un libellé lisible à partir du slug, ce qui redonne
  -- « Ecurie vainqueur » au mieux et « Top x » au pire. Le bookmaker est la
  -- seule source légitime du nom d'un marché.
  libelle_marche    text not null,

  -- Nom tel que retourné par Unibet (« M.Verstappen », ou une écurie pour les
  -- marchés d'écurie). Aucune normalisation ici : le rapprochement avec les
  -- pilotes OpenF1 relèvera de l'étape 6, et réécrire le nom maintenant
  -- reviendrait à perdre la donnée d'origine.
  pilote            text not null,

  -- La cote multipliée par 100, arrondie (règle 4.1) : 2,80 → 280. C'est déjà
  -- le nombre de points, jamais une cote. Rien dans la base ne stocke « 2,80 ».
  valeur            integer not null,

  -- Identifiant de l'issue chez Unibet (préfixe `o`). Porte l'idempotence du
  -- scraper : rejouer un scraping met à jour la ligne au lieu d'en créer une.
  id_outcome_unibet text not null,

  cree_le           timestamptz not null default now(),

  constraint cotes_valeur_positive check (valeur > 0)
);

comment on table public.cotes is
  'Cotes Unibet d''un GP, déjà converties en points (règle 4.1). Une ligne par issue.';
comment on column public.cotes.valeur is
  'Points rapportés = cote × 100 arrondie. Ne jamais afficher de cote brute (règle 4.1).';

-- L'idempotence du scraper repose entièrement sur cet index : sans lui, chaque
-- exécution ajouterait une ligne de plus par issue.
--
-- `id_outcome_unibet` est `not null` pour cette raison précise : une colonne
-- nullable laisserait PostgreSQL considérer deux NULL comme distincts, et
-- l'index n'empêcherait plus rien. Le scraper a toujours cet identifiant sous
-- la main ; une issue qui en serait dépourvue serait ignorée plutôt qu'insérée.
create unique index if not exists cotes_gp_outcome_idx
  on public.cotes (gp_id, id_outcome_unibet);

-- Le tableau des cotes (étape 5) lit toujours « toutes les cotes d'un GP,
-- groupées par marché ». Sans cet index, chaque affichage balaie la table.
create index if not exists cotes_gp_marche_idx
  on public.cotes (gp_id, marche);

-- --  3. Droits sur les tables  -----------------------------------------------

-- Lecture publique : les cotes d'un GP ne sont un secret pour personne, elles
-- sont affichées telles quelles sur le site du bookmaker. Les laisser lisibles
-- sans authentification permet à la landing d'annoncer le prochain GP sans
-- session ouverte, et évite un aller-retour d'authentification pour une donnée
-- identique pour tout le monde.
--
-- Aucun droit d'écriture n'est accordé, ni à `anon` ni à `authenticated` : ces
-- tables ne sont alimentées que par le scraper, qui parle avec la clé de
-- service. C'est un droit de table, donc antérieur à toute politique RLS — même
-- une politique d'écriture ajoutée par erreur ne rendrait pas l'écriture
-- possible depuis le client.
grant select on public.grands_prix, public.cotes to anon, authenticated;
grant all    on public.grands_prix, public.cotes to service_role;

-- --  4. Sécurité au niveau des lignes  ---------------------------------------

alter table public.grands_prix enable row level security;
alter table public.cotes       enable row level security;

-- Lecture ouverte à tous, y compris non connectés.
drop policy if exists "Grands prix lisibles par tous" on public.grands_prix;
create policy "Grands prix lisibles par tous"
  on public.grands_prix for select
  to anon, authenticated
  using (true);

drop policy if exists "Cotes lisibles par tous" on public.cotes;
create policy "Cotes lisibles par tous"
  on public.cotes for select
  to anon, authenticated
  using (true);

-- Aucune politique d'insertion, de modification ni de suppression n'est créée,
-- et c'est délibéré : sous RLS, ce qu'aucune politique n'autorise est refusé.
-- Le client ne peut donc pas écrire, quand bien même un droit de table lui
-- serait accordé un jour par inadvertance. `service_role` contourne la RLS et
-- reste seul à écrire.

-- --  5. Lecture groupée des cotes d'un GP  -----------------------------------

-- Renvoie les cotes d'un GP déjà regroupées par marché, sous forme de JSON.
-- Regrouper en base plutôt que dans le backend évite de transporter une ligne
-- par issue (une cinquantaine par GP, davantage une fois la grille définitive)
-- pour les réassembler côté Python.
--
-- `stable` et non `volatile` : la fonction ne fait que lire, PostgreSQL peut
-- donc l'évaluer une seule fois par requête.
create or replace function public.cotes_du_grand_prix(p_gp uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'marche',  m.marche,
        'libelle', m.libelle_marche,
        'cotes',   m.cotes
      )
      order by m.libelle_marche
    ),
    '[]'::jsonb
  )
  from (
    select
      c.marche,
      min(c.libelle_marche) as libelle_marche,
      jsonb_agg(
        jsonb_build_object(
          'pilote', c.pilote,
          'points', c.valeur,
          'id',     c.id_outcome_unibet
        )
        -- Du plus probable au plus improbable : c'est l'ordre du tableau des
        -- cotes chez Unibet, et celui que l'interface affichera.
        order by c.valeur, c.pilote
      ) as cotes
    from public.cotes c
    where c.gp_id = p_gp
    group by c.marche
  ) m;
$$;

comment on function public.cotes_du_grand_prix(uuid) is
  'Cotes d''un GP groupées par marché, en JSON. Lecture seule, ouverte à tous.';

-- `security invoker` : la fonction lit sous l'identité de l'appelant, donc sous
-- les politiques ci-dessus. Elle n'ouvre aucun accès que la RLS n'accorde déjà,
-- contrairement aux fonctions `security definer` de l'étape 3, qui devaient
-- justement contourner les politiques.
revoke all on function public.cotes_du_grand_prix(uuid) from public;
grant execute on function public.cotes_du_grand_prix(uuid) to anon, authenticated, service_role;
