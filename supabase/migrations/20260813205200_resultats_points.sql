-- =============================================================================
-- Étape 6 — Résultats OpenF1 et points attribués
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les cinq migrations précédentes : elle modifie `public.pronostics` et
-- `public.pronostic_podium` (étape 5), et référence `public.grands_prix`
-- (étape 4) ainsi que `public.est_membre(uuid)` (étape 3).
--
-- La migration est idempotente : la rejouer ne casse rien, ne touche à aucune
-- donnée déjà enregistrée, et surtout n'efface aucun point déjà attribué.
-- =============================================================================

-- --  1. Les points gagnés  ----------------------------------------------------

-- Trois états, et le troisième est le seul qui demande une convention :
--
--   NULL  le résultat n'est pas connu, ou ce marché n'a pas su être validé
--   0     le pronostic est raté (règle 4.1 : jamais de points négatifs)
--   > 0   le pronostic est réussi, et rapporte la valeur de sa cote en points
--
-- NULL et 0 ne doivent jamais être confondus. Un marché que le calcul ne sait
-- pas valider reste à NULL plutôt que d'être mis à 0 : marquer « raté » un
-- pronostic qu'on n'a pas su juger volerait le joueur en silence, et rien dans
-- l'interface ne permettrait de s'en apercevoir. C'est aussi ce qui rend le
-- rattrapage possible — un second passage ne réécrit que les NULL.
alter table public.pronostics
  add column if not exists points_gagnes integer;

comment on column public.pronostics.points_gagnes is
  'Points rapportés : NULL tant que le résultat est inconnu ou non validable, 0 si raté, la cote sinon (règle 4.1).';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pronostics_points_positifs'
  ) then
    alter table public.pronostics
      add constraint pronostics_points_positifs check (points_gagnes >= 0);
  end if;
end
$$;

-- Même colonne sur le détail du podium. Elle est **redondante** avec celle du
-- pronostic parent, et c'est assumé : elle est demandée pour que le détail d'un
-- podium se suffise à lui-même. La redondance est tenue par la base et non par
-- une convention — `public.attribuer_points` dérive systématiquement cette
-- colonne de celle du parent, dans la même transaction. Ne jamais l'écrire
-- depuis le code applicatif, elle divergerait au premier oubli.
alter table public.pronostic_podium
  add column if not exists points_gagnes integer;

comment on column public.pronostic_podium.points_gagnes is
  'Copie des points du pronostic parent, dérivée par public.attribuer_points. Ne jamais l''écrire directement.';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pronostic_podium_points_positifs'
  ) then
    alter table public.pronostic_podium
      add constraint pronostic_podium_points_positifs check (points_gagnes >= 0);
  end if;
end
$$;

-- Le job de résultats cherche toujours « les pronostics de ce GP qui n'ont pas
-- encore de points ». Index partiel : il ne porte que sur les lignes en attente,
-- et se vide de lui-même à mesure que les points sont attribués.
create index if not exists pronostics_a_calculer_idx
  on public.pronostics (gp_id)
  where points_gagnes is null;

-- --  2. Les résultats bruts d'un Grand Prix  ----------------------------------

-- `donnees_brutes` conserve la réponse d'OpenF1 telle qu'elle est arrivée. Ce
-- n'est pas un cache de confort : c'est ce qui permet de **rejouer le calcul
-- sans rappeler l'API**, donc de corriger un validateur ou d'en ajouter un pour
-- un marché resté à NULL, des semaines après la course. OpenF1 est gratuite et
-- sans clé, mais rien ne garantit qu'elle servira encore la saison 2026 dans
-- deux ans, ni qu'elle ne réécrira pas une donnée entre-temps.
create table if not exists public.resultats_gp (
  id            uuid        primary key default gen_random_uuid(),

  -- `unique` : un seul jeu de résultats par GP. C'est cette contrainte qui
  -- porte l'idempotence de la récupération — le job upserte dessus, et
  -- n'appelle OpenF1 que si aucune ligne n'existe encore.
  gp_id         uuid        not null unique references public.grands_prix (id) on delete cascade,

  recupere_le   timestamptz not null default now(),
  donnees_brutes jsonb      not null
);

comment on table public.resultats_gp is
  'Réponse OpenF1 d''un GP, conservée telle quelle pour rejouer le calcul des points sans rappeler l''API.';
comment on column public.resultats_gp.donnees_brutes is
  'Objet { session, session_result, drivers, race_control, laps, starting_grid }. `laps` est réduit au meilleur tour par pilote (voir app/scraper/openf1.py).';

-- --  3. Droits sur les tables  ------------------------------------------------

-- Lecture publique, comme `grands_prix` et `cotes` à l'étape 4 : un résultat de
-- course n'est un secret pour personne, il est public partout ailleurs, et
-- l'écran de résultats doit pouvoir s'afficher sans session ouverte.
--
-- Aucun droit d'écriture n'est accordé à `anon` ni à `authenticated`. C'est un
-- droit de table, donc antérieur à toute politique RLS : même une politique
-- d'écriture ajoutée par erreur ne rendrait pas l'écriture possible depuis le
-- client. Réécrire un résultat de course, c'est réécrire le classement.
grant select on public.resultats_gp to anon, authenticated;
grant all    on public.resultats_gp to service_role;

-- --  4. Sécurité au niveau des lignes  ----------------------------------------

alter table public.resultats_gp enable row level security;

drop policy if exists "Resultats lisibles par tous" on public.resultats_gp;
create policy "Resultats lisibles par tous"
  on public.resultats_gp for select
  to anon, authenticated
  using (true);

-- Aucune politique d'écriture n'est créée : sous RLS, ce qu'aucune politique
-- n'autorise est refusé. `service_role` contourne la RLS et reste seul à écrire.

-- --  5. Attribution des points, atomique et idempotente  ----------------------

-- Reçoit `[{"pronostic_id": "...", "points": 280}, ...]` et écrit les points.
--
-- L'idempotence est portée par la base, et non par le code appelant : la clause
-- `points_gagnes is null` fait qu'un pronostic déjà noté n'est **jamais**
-- réécrit. Le job de résultats tourne toutes les cinq minutes (section 9) et
-- peut donc repasser sur un GP déjà traité sans rien doubler. Un rattrapage
-- ultérieur — validateur corrigé, marché nouvellement reconnu — ne remplit que
-- les NULL restants, sans toucher aux points déjà acquis.
--
-- Tout se joue dans une seule transaction : ou bien tout le GP est noté, ou
-- bien rien ne l'est. Un classement à moitié calculé serait pire qu'un
-- classement en attente, parce que rien ne le distinguerait d'un classement
-- complet.
create or replace function public.attribuer_points(p_gp uuid, p_attributions jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attribues integer;
  restants  integer;
begin
  update public.pronostics p
     set points_gagnes = d.points
    from (
      select (a->>'pronostic_id')::uuid as id,
             (a->>'points')::integer    as points
      from jsonb_array_elements(coalesce(p_attributions, '[]'::jsonb)) a
    ) d
   where p.id           = d.id
     and p.gp_id        = p_gp   -- un appel ne peut noter que le GP annoncé
     and p.points_gagnes is null;

  get diagnostics attribues = row_count;

  -- Le détail du podium ne reçoit jamais de valeur propre : il la DÉRIVE du
  -- pronostic parent. C'est ce qui empêche les deux colonnes de diverger, sans
  -- avoir à faire confiance au code appelant.
  update public.pronostic_podium pp
     set points_gagnes = p.points_gagnes
    from public.pronostics p
   where p.id    = pp.pronostic_id
     and p.gp_id = p_gp
     and p.type  = 'podium'
     and p.points_gagnes is not null
     and pp.points_gagnes is distinct from p.points_gagnes;

  select count(*) into restants
  from public.pronostics p
  where p.gp_id = p_gp and p.points_gagnes is null;

  return jsonb_build_object('attribues', attribues, 'restants', restants);
end;
$$;

comment on function public.attribuer_points(uuid, jsonb) is
  'Écrit les points d''un GP sans jamais réécrire un pronostic déjà noté. Réservée au backend.';

-- Réservée au backend : `p_points` est fourni par l'appelant. Ouverte à
-- `authenticated`, elle laisserait n'importe qui s'attribuer le score de son
-- choix — c'est la fonction la plus sensible du projet.
revoke all on function public.attribuer_points(uuid, jsonb) from public;
grant execute on function public.attribuer_points(uuid, jsonb) to service_role;

-- --  6. Lecture des pronostics, points compris  --------------------------------

-- `public.pronostics_du_joueur` de l'étape 5 est remplacée pour porter aussi
-- `points_gagnes`. Le corps est celui de l'étape 5, à ce seul champ près.
-- `public.pronostics_du_championnat` l'appelle et en hérite sans être touchée,
-- comme les routes de l'étape 5 qui la servent déjà.
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
        -- Ajout de l'étape 6. `points` reste ce que le pronostic PEUT rapporter
        -- (la cote), `points_gagnes` ce qu'il a rapporté. Les confondre ferait
        -- afficher un score avant la course.
        'points_gagnes', x.points_gagnes,
        'podium',  x.podium
      )
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
      p.points_gagnes,
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

revoke all on function public.pronostics_du_joueur(uuid, uuid) from public;
grant execute on function public.pronostics_du_joueur(uuid, uuid) to service_role;

-- --  7. Classement des pilotes d'un GP  ----------------------------------------

-- Le classement servi par `GET /grands-prix/{id}/resultats`, tiré du JSON brut
-- plutôt que d'une table dédiée : les résultats ne sont lus que pour être
-- affichés, et une table de plus à tenir cohérente avec `donnees_brutes`
-- n'apporterait rien.
--
-- `security invoker` : la fonction lit sous l'identité de l'appelant, donc sous
-- la politique de lecture publique ci-dessus. Elle n'ouvre aucun accès que la
-- RLS n'accorde déjà — contrairement aux fonctions `security definer` du
-- fichier, qui doivent justement la contourner.
create or replace function public.classement_du_grand_prix(p_gp uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'recupere_le', r.recupere_le,
        'classement', coalesce(
          (
            select jsonb_agg(ligne order by rang)
            from (
              select
                jsonb_build_object(
                  'position',       (l->>'position')::integer,
                  'driver_number',  (l->>'driver_number')::integer,
                  -- `pilotes` est l'index { numéro → { nom, equipe } } construit
                  -- au moment de la récupération (app/scraper/openf1.py). Sans
                  -- lui il faudrait parcourir le tableau `drivers` à chaque
                  -- ligne du classement.
                  'pilote',         coalesce(
                                      r.donnees_brutes->'pilotes'->(l->>'driver_number')->>'nom',
                                      'Pilote #' || (l->>'driver_number')
                                    ),
                  'equipe',         r.donnees_brutes->'pilotes'->(l->>'driver_number')->>'equipe',
                  -- OpenF1 rend les points FIA en flottant (25.0). Ce sont les
                  -- points du championnat du monde, jamais ceux de l'app.
                  'points_fia',     round(coalesce((l->>'points')::numeric, 0))::integer,
                  'nombre_de_tours',(l->>'number_of_laps')::integer,
                  'abandon',        coalesce((l->>'dnf')::boolean, false),
                  'non_partant',    coalesce((l->>'dns')::boolean, false),
                  'disqualifie',    coalesce((l->>'dsq')::boolean, false)
                ) as ligne,
                -- Les abandons non classés (`position` nulle) ferment la
                -- marche. Sans ce `coalesce`, `order by` les placerait en tête :
                -- PostgreSQL trie les NULL en dernier en ordre croissant, mais
                -- `jsonb_agg` reçoit ici un tri explicite qu'il vaut mieux ne
                -- pas laisser dépendre de cette subtilité.
                coalesce((l->>'position')::integer, 9999) as rang
              from jsonb_array_elements(
                     coalesce(r.donnees_brutes->'session_result', '[]'::jsonb)
                   ) l
            ) t
          ),
          '[]'::jsonb
        )
      )
      from public.resultats_gp r
      where r.gp_id = p_gp
    ),
    'null'::jsonb
  );
$$;

comment on function public.classement_du_grand_prix(uuid) is
  'Classement d''un GP tiré des données brutes OpenF1, ou null s''il n''est pas encore récupéré.';

revoke all on function public.classement_du_grand_prix(uuid) from public;
grant execute on function public.classement_du_grand_prix(uuid) to anon, authenticated, service_role;
