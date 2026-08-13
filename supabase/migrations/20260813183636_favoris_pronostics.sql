-- =============================================================================
-- Étape 5 — Favoris et pronostics
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les quatre migrations précédentes : elle référence `auth.users`,
-- `public.grands_prix`, `public.cotes`, `public.membres_championnat` et la
-- fonction `public.est_membre(uuid)` de l'étape 3.
--
-- La migration est idempotente : la rejouer ne casse rien et ne touche à
-- aucune donnée déjà enregistrée.
-- =============================================================================

-- --  1. Les favoris  ----------------------------------------------------------

-- Un favori est une cote qu'un joueur a épinglée pour un GP donné (règle 4.2 :
-- il explore les cotes, met en favori ce qui l'intéresse, puis choisit ses trois
-- bonus dans cette sélection).
--
-- La cote n'est PAS référencée par une clé étrangère vers `public.cotes`, et
-- c'est délibéré : le scraper réécrit les cotes d'un GP tant qu'elles ne sont
-- pas figées, et une issue qu'Unibet retire (un pilote forfait, un marché fermé)
-- ferait alors échouer l'upsert du scraper, ou emporterait les favoris des
-- joueurs par cascade. Le rapprochement se fait sur `(gp_id, id_outcome_unibet)`
-- au moment de la lecture ; un favori devenu orphelin est simplement ignoré.
create table if not exists public.favoris (
  profil_id         uuid        not null references auth.users (id) on delete cascade,
  gp_id             uuid        not null references public.grands_prix (id) on delete cascade,
  id_outcome_unibet text        not null,

  -- Ajout par rapport au strict nécessaire : la rangée de pastilles « MES
  -- FAVORIS » de la maquette 08 se lit dans l'ordre où le joueur les a
  -- épinglées, pas dans un ordre arbitraire décidé par PostgreSQL.
  cree_le           timestamptz not null default now(),

  primary key (profil_id, gp_id, id_outcome_unibet)
);

comment on table public.favoris is
  'Cotes épinglées par un joueur pour un GP. Les bonus se choisissent parmi elles (règle 4.2).';

-- La clé primaire commence par `profil_id` : elle couvre déjà « les favoris de
-- ce joueur pour ce GP », la seule lecture qui existe. Aucun index de plus.

-- --  2. Les pronostics  -------------------------------------------------------

create table if not exists public.pronostics (
  id                uuid        primary key default gen_random_uuid(),
  profil_id         uuid        not null references auth.users (id) on delete cascade,
  gp_id             uuid        not null references public.grands_prix (id) on delete cascade,

  -- Issue Unibet pronostiquée (préfixe `o`). Pour un pronostic de podium, cette
  -- colonne porte le premier des deux pilotes : elle est `not null`, il faut
  -- bien y mettre quelque chose. C'est `public.pronostic_podium` qui fait foi
  -- pour la paire, et un trigger garantit que les deux ne divergent jamais.
  id_outcome_unibet text        not null,

  -- vainqueur | podium | bonus (règle 4.2 : deux pronostics obligatoires, le
  -- vainqueur et le podium, plus trois bonus au choix).
  type              text        not null,

  cree_le           timestamptz not null default now(),
  modifie_le        timestamptz not null default now(),

  constraint pronostics_type_valide
    check (type in ('vainqueur', 'podium', 'bonus'))
);

comment on table public.pronostics is
  'Pronostics d''un joueur pour un GP : un vainqueur, un podium, jusqu''à trois bonus (règle 4.2).';
comment on column public.pronostics.id_outcome_unibet is
  'Issue Unibet pronostiquée. Pour un podium, vaut pilote_1 de public.pronostic_podium.';

-- Un joueur n'a qu'un vainqueur et qu'un podium par GP. Des index PARTIELS, et
-- non un index unique sur (profil_id, gp_id, type) : celui-ci interdirait aussi
-- d'avoir plus d'un bonus, alors que la règle 4.2 en demande trois.
create unique index if not exists pronostics_un_vainqueur_idx
  on public.pronostics (profil_id, gp_id)
  where type = 'vainqueur';

create unique index if not exists pronostics_un_podium_idx
  on public.pronostics (profil_id, gp_id)
  where type = 'podium';

-- Les trois bonus doivent être trois cotes différentes : sans cet index, un
-- joueur pourrait miser trois fois la même issue et tripler ses points sur un
-- seul événement.
create unique index if not exists pronostics_bonus_distincts_idx
  on public.pronostics (profil_id, gp_id, id_outcome_unibet)
  where type = 'bonus';

-- « Les pronostics de tous les membres du championnat pour ce GP » part du GP,
-- pas du profil : sans cet index, chaque affichage balaie la table.
create index if not exists pronostics_gp_profil_idx
  on public.pronostics (gp_id, profil_id);

-- --  3. Le détail d'un pronostic de podium  -----------------------------------

-- Deux pilotes, sans ordre entre eux : la validation de l'étape 6 demandera
-- « ces deux pilotes sont-ils sur le podium ? », jamais « lequel devant ».
-- Les noms `pilote_1` et `pilote_2` ne sont donc que des emplacements.
create table if not exists public.pronostic_podium (
  pronostic_id uuid primary key references public.pronostics (id) on delete cascade,
  pilote_1     text not null,
  pilote_2     text not null,

  -- Miser deux fois le même pilote reviendrait à ne remplir qu'une moitié du
  -- pronostic tout en encaissant deux fois la cote.
  constraint pronostic_podium_pilotes_distincts check (pilote_1 <> pilote_2)
);

comment on table public.pronostic_podium is
  'Les deux pilotes d''un pronostic de podium. Aucun ordre entre eux : les deux sont équivalents.';

-- --  4. Horodatage et invariants  ---------------------------------------------

-- `public.marquer_modification()` vient de la migration des profils
-- (20260809191018) : elle est réutilisée telle quelle plutôt que dupliquée.
drop trigger if exists pronostics_modifie_le on public.pronostics;
create trigger pronostics_modifie_le
  before update on public.pronostics
  for each row execute function public.marquer_modification();

-- Trois bonus au maximum (règle 4.2). La contrainte ne peut pas s'écrire en
-- `check` — elle porte sur plusieurs lignes — d'où ce trigger. Il compte les
-- bonus déjà présents pour ce couple (profil, GP) : la fonction
-- `enregistrer_pronostics` efface tout avant de réinsérer, elle voit donc
-- 0, 1 puis 2 et passe ; un quatrième bonus inséré par un autre chemin est
-- refusé.
create or replace function public.pronostics_limiter_bonus()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.type <> 'bonus' then
    return new;
  end if;

  if (
    select count(*)
    from public.pronostics p
    where p.profil_id = new.profil_id
      and p.gp_id     = new.gp_id
      and p.type      = 'bonus'
      and p.id       <> new.id
  ) >= 3 then
    raise exception 'Trois pronostics bonus au maximum par Grand Prix.'
      using errcode = 'PT403';
  end if;

  return new;
end;
$$;

drop trigger if exists pronostics_max_trois_bonus on public.pronostics;
create trigger pronostics_max_trois_bonus
  before insert or update on public.pronostics
  for each row execute function public.pronostics_limiter_bonus();

-- `public.pronostics.id_outcome_unibet` et `pronostic_podium.pilote_1` portent
-- la même information : l'un est `not null` et doit bien valoir quelque chose,
-- l'autre fait foi. Plutôt que de laisser cette redondance à une convention,
-- ce trigger en fait un invariant vérifié — et refuse au passage d'accrocher un
-- détail de podium à un pronostic qui n'en est pas un.
create or replace function public.pronostic_podium_coherent()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  parent public.pronostics;
begin
  select * into parent from public.pronostics p where p.id = new.pronostic_id;

  if parent.type <> 'podium' then
    raise exception 'Un détail de podium ne se rattache qu''à un pronostic de type podium (reçu : %).',
      parent.type using errcode = 'PT422';
  end if;

  if parent.id_outcome_unibet <> new.pilote_1 then
    raise exception 'pilote_1 (%) doit valoir id_outcome_unibet du pronostic (%).',
      new.pilote_1, parent.id_outcome_unibet using errcode = 'PT422';
  end if;

  return new;
end;
$$;

drop trigger if exists pronostic_podium_coherent on public.pronostic_podium;
create trigger pronostic_podium_coherent
  before insert or update on public.pronostic_podium
  for each row execute function public.pronostic_podium_coherent();

-- --  5. Droits sur les tables  -------------------------------------------------

-- Écrits explicitement plutôt que laissés aux privilèges par défaut de Supabase,
-- comme à l'étape 3 : la migration reste correcte sur une base où ces privilèges
-- ne sont pas en place. `anon` n'est jamais servi — rien ici n'est public.
grant select, insert, delete            on public.favoris          to authenticated;
grant select, insert, update, delete    on public.pronostics       to authenticated;
grant select, insert, update, delete    on public.pronostic_podium to authenticated;
grant all on public.favoris, public.pronostics, public.pronostic_podium to service_role;

-- --  6. Sécurité au niveau des lignes  ----------------------------------------

alter table public.favoris          enable row level security;
alter table public.pronostics       enable row level security;
alter table public.pronostic_podium enable row level security;

-- favoris — strictement privés. Ce sont les brouillons d'un joueur, pas une
-- information de jeu : la maquette 08 les intitule « MES FAVORIS », et laisser
-- les autres membres les lire reviendrait à annoncer ses pronostics avant de
-- les avoir saisis. Une seule politique, pour toutes les opérations.
drop policy if exists "Favoris strictement prives" on public.favoris;
create policy "Favoris strictement prives"
  on public.favoris for all
  to authenticated
  using      (profil_id = (select auth.uid()))
  with check (profil_id = (select auth.uid()));

-- pronostics — lecture par les membres des championnats partagés (règle 4.3 :
-- les pronostics sont visibles par les autres membres dès leur saisie).
--
-- `public.est_membre(uuid)` de l'étape 3 est réutilisée telle quelle : c'est
-- elle qui casse la récursion. La sous-requête ci-dessous porte sur
-- `membres_championnat`, dont la propre politique appelle `est_membre` — une
-- fonction `security definer`, qui lit sans repasser par les politiques. Ne
-- jamais remplacer cet appel par la sous-requête littérale : PostgreSQL
-- refuserait la requête entière (42P17).
--
-- Le premier terme n'est pas redondant : un joueur qui n'appartient encore à
-- aucun championnat doit pouvoir relire ses propres pronostics.
drop policy if exists "Pronostics visibles entre membres" on public.pronostics;
create policy "Pronostics visibles entre membres"
  on public.pronostics for select
  to authenticated
  using (
    profil_id = (select auth.uid())
    or exists (
      select 1
      from public.membres_championnat m
      where m.profil_id = pronostics.profil_id
        and public.est_membre(m.championnat_id)
    )
  );

-- Écriture, modification, suppression : chacun pour soi, jamais pour un autre.
-- `using` et `with check` sont tous deux nécessaires — le premier décide quelles
-- lignes sont visibles à l'opération, le second ce qu'elles ont le droit de
-- devenir. Sans `with check` sur l'update, on pourrait réattribuer son
-- pronostic à quelqu'un d'autre.
drop policy if exists "Chacun pronostique pour lui-meme" on public.pronostics;
create policy "Chacun pronostique pour lui-meme"
  on public.pronostics for insert
  to authenticated
  with check (profil_id = (select auth.uid()));

drop policy if exists "Chacun modifie ses pronostics" on public.pronostics;
create policy "Chacun modifie ses pronostics"
  on public.pronostics for update
  to authenticated
  using      (profil_id = (select auth.uid()))
  with check (profil_id = (select auth.uid()));

drop policy if exists "Chacun supprime ses pronostics" on public.pronostics;
create policy "Chacun supprime ses pronostics"
  on public.pronostics for delete
  to authenticated
  using (profil_id = (select auth.uid()));

-- pronostic_podium — la visibilité suit celle du pronostic parent, sans la
-- redire : la sous-requête sur `public.pronostics` est elle-même filtrée par la
-- politique ci-dessus. Écrire ici la condition « membre d'un championnat
-- partagé » une seconde fois créerait deux règles à maintenir en parallèle.
drop policy if exists "Podium visible comme son pronostic" on public.pronostic_podium;
create policy "Podium visible comme son pronostic"
  on public.pronostic_podium for select
  to authenticated
  using (
    exists (
      select 1 from public.pronostics p
      where p.id = pronostic_podium.pronostic_id
    )
  );

drop policy if exists "Podium ecrit par son auteur" on public.pronostic_podium;
create policy "Podium ecrit par son auteur"
  on public.pronostic_podium for all
  to authenticated
  using (
    exists (
      select 1 from public.pronostics p
      where p.id = pronostic_podium.pronostic_id
        and p.profil_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.pronostics p
      where p.id = pronostic_podium.pronostic_id
        and p.profil_id = (select auth.uid())
    )
  );

-- --  7. Fermeture des pronostics  ----------------------------------------------

-- Règle 4.3 : plus aucune modification cinq minutes avant le départ.
--
-- Un GP sans `date_course` connue reste ouvert : refuser tout le monde parce
-- qu'Unibet n'a pas encore annoncé l'heure serait le mauvais sens du doute.
create or replace function public.pronostics_fermes(p_gp uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (
      select now() >= g.date_course - interval '5 minutes'
      from public.grands_prix g
      where g.id = p_gp
    ),
    false
  );
$$;

comment on function public.pronostics_fermes(uuid) is
  'Vrai si les pronostics de ce GP sont fermés (départ dans moins de 5 minutes, règle 4.3).';

revoke all on function public.pronostics_fermes(uuid) from public;
grant execute on function public.pronostics_fermes(uuid) to authenticated, service_role;

-- --  8. Enregistrement atomique d'un jeu de pronostics  ------------------------

-- Enregistrer un pronostic, c'est effacer le précédent et en écrire cinq lignes
-- (le vainqueur, le podium et son détail, trois bonus). Enchaîner des appels
-- REST séparés laisserait, au premier échec, un joueur avec un pronostic à
-- moitié effacé — pire que l'ancien, qui au moins était complet. Le corps d'une
-- fonction s'exécute dans une seule transaction : tout passe, ou rien.
--
-- La fermeture est revérifiée ICI, et pas seulement dans le backend : entre le
-- contrôle du backend et l'écriture, quelques dizaines de millisecondes passent,
-- et c'est précisément à cinq minutes du départ que la course aux dernières
-- secondes a lieu. C'est cette vérification-ci qui fait foi.
create or replace function public.enregistrer_pronostics(
  p_profil   uuid,
  p_gp       uuid,
  p_vainqueur text,
  p_podium_1  text,
  p_podium_2  text,
  p_bonus     text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  podium_id uuid;
  bonus     text;
begin
  if public.pronostics_fermes(p_gp) then
    raise exception 'Les pronostics de ce Grand Prix sont fermés.'
      using errcode = 'PT423';
  end if;

  -- Effacement puis réécriture, plutôt qu'une mise à jour ligne à ligne : le
  -- joueur peut passer de trois bonus à trois autres, l'ancien jeu n'a aucune
  -- ligne en commun avec le nouveau. `pronostic_podium` suit par cascade.
  delete from public.pronostics
  where profil_id = p_profil and gp_id = p_gp;

  insert into public.pronostics (profil_id, gp_id, id_outcome_unibet, type)
  values (p_profil, p_gp, p_vainqueur, 'vainqueur');

  insert into public.pronostics (profil_id, gp_id, id_outcome_unibet, type)
  values (p_profil, p_gp, p_podium_1, 'podium')
  returning id into podium_id;

  insert into public.pronostic_podium (pronostic_id, pilote_1, pilote_2)
  values (podium_id, p_podium_1, p_podium_2);

  foreach bonus in array coalesce(p_bonus, array[]::text[]) loop
    insert into public.pronostics (profil_id, gp_id, id_outcome_unibet, type)
    values (p_profil, p_gp, bonus, 'bonus');
  end loop;

  return public.pronostics_du_joueur(p_profil, p_gp);
end;
$$;

comment on function public.enregistrer_pronostics(uuid, uuid, text, text, text, text[]) is
  'Remplace les pronostics d''un joueur pour un GP, dans une seule transaction. Réservée au backend.';

-- `p_profil` est un paramètre : appelable par un client authentifié, cette
-- fonction `security definer` permettrait de pronostiquer au nom de quelqu'un
-- d'autre. Seul le backend, qui a vérifié le jeton, y a droit.
revoke all on function public.enregistrer_pronostics(uuid, uuid, text, text, text, text[]) from public;
grant execute on function public.enregistrer_pronostics(uuid, uuid, text, text, text, text[]) to service_role;

-- --  9. Lecture des pronostics  ------------------------------------------------

-- Les pronostics d'un joueur pour un GP, déjà rapprochés des cotes : le nom de
-- l'issue, son marché et surtout ses points (règle 4.1 — jamais une cote brute).
--
-- Le rapprochement se fait en `left join` : une issue retirée par Unibet depuis
-- la saisie laisse le pronostic visible, sans points plutôt qu'absent.
create or replace function public.pronostics_du_joueur(p_profil uuid, p_gp uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',      x.id,
        'type',    x.type,
        'outcome', x.id_outcome_unibet,
        'pilote',  x.pilote,
        'marche',  x.marche,
        'libelle', x.libelle_marche,
        'points',  x.points,
        'podium',  x.podium
      )
      -- Le vainqueur, puis le podium, puis les bonus : l'ordre des maquettes
      -- 09 et 10, obtenu en base pour que tous les écrans le partagent.
      order by
        case x.type when 'vainqueur' then 1 when 'podium' then 2 else 3 end,
        x.pilote
    ),
    '[]'::jsonb
  )
  from (
    select
      p.id,
      p.type,
      p.id_outcome_unibet,
      c.pilote,
      c.marche,
      c.libelle_marche,
      c.valeur as points,
      case
        when p.type = 'podium' then jsonb_build_object(
          'pilote_1', pp.pilote_1,
          'pilote_2', pp.pilote_2,
          'nom_1',    c.pilote,
          'nom_2',    c2.pilote,
          'points_2', c2.valeur
        )
      end as podium
    from public.pronostics p
    left join public.cotes c
      on c.gp_id = p.gp_id and c.id_outcome_unibet = p.id_outcome_unibet
    left join public.pronostic_podium pp
      on pp.pronostic_id = p.id
    left join public.cotes c2
      on c2.gp_id = p.gp_id and c2.id_outcome_unibet = pp.pilote_2
    where p.profil_id = p_profil
      and p.gp_id     = p_gp
  ) x;
$$;

comment on function public.pronostics_du_joueur(uuid, uuid) is
  'Pronostics d''un joueur pour un GP, avec pilote, marché et points. Réservée au backend.';

revoke all on function public.pronostics_du_joueur(uuid, uuid) from public;
grant execute on function public.pronostics_du_joueur(uuid, uuid) to service_role;

-- Les pronostics de tous les membres d'un championnat pour un GP, en un appel.
--
-- Une requête par membre serait un aller-retour PostgREST par membre, et le
-- championnat n'a aucune limite de taille (règle 4.5). Les membres sont tous
-- renvoyés, y compris ceux qui n'ont pas encore pronostiqué : l'interface doit
-- pouvoir montrer qui manque à l'appel.
--
-- L'appartenance de l'appelant N'EST PAS vérifiée ici : la fonction est
-- réservée à `service_role`, et c'est la route FastAPI qui contrôle, à partir
-- de l'identifiant du jeton vérifié, que le demandeur est bien membre.
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
  'Pronostics de tous les membres d''un championnat pour un GP. Réservée au backend.';

revoke all on function public.pronostics_du_championnat(uuid, uuid) from public;
grant execute on function public.pronostics_du_championnat(uuid, uuid) to service_role;

-- --  10. Départ d'un championnat, pronostics compris  --------------------------

-- Le `TODO` posé à l'étape 3 dans `DELETE /championnats/{id}/quitter` demandait
-- d'effacer les pronostics du membre qui s'en va, « dans la même transaction que
-- le retrait ». D'où cette fonction : deux appels REST séparés laisseraient, en
-- cas d'échec du second, un membre sorti dont les pronostics continueraient
-- d'alimenter le classement.
--
-- MAIS les pronostics ne sont pas rattachés à un championnat : un joueur remplit
-- UN pronostic par Grand Prix, qui compte dans TOUS ses championnats à la fois.
-- Les effacer au départ d'un seul championnat détruirait son classement dans les
-- autres. Ils ne sont donc effacés que lorsqu'il ne reste aucune adhésion —
-- l'intention du TODO (aucun pronostic orphelin ne survit à un départ) sans le
-- dommage collatéral.
--
-- Le trigger `membres_championnat_supprime_vide` (migration 20260813182331)
-- s'occupe derrière du championnat devenu vide.
create or replace function public.quitter_championnat(p_profil uuid, p_championnat uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- `row_count` est un entier : le lire dans une variable booléenne échouerait
  -- à l'exécution, pas à la création de la fonction.
  retires integer;
begin
  delete from public.membres_championnat
  where championnat_id = p_championnat
    and profil_id      = p_profil;

  get diagnostics retires = row_count;
  if retires = 0 then
    -- Pas membre : rien n'est effacé, surtout pas des pronostics. La route
    -- traduit ce `false` en 404.
    return false;
  end if;

  if not exists (
    select 1 from public.membres_championnat m where m.profil_id = p_profil
  ) then
    -- `pronostic_podium` suit par cascade.
    delete from public.pronostics where profil_id = p_profil;
    delete from public.favoris    where profil_id = p_profil;
  end if;

  return true;
end;
$$;

comment on function public.quitter_championnat(uuid, uuid) is
  'Retire un membre d''un championnat, et efface ses pronostics s''il ne lui reste aucune adhésion. Réservée au backend.';

revoke all on function public.quitter_championnat(uuid, uuid) from public;
grant execute on function public.quitter_championnat(uuid, uuid) to service_role;
