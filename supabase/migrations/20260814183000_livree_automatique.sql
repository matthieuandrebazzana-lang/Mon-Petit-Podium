-- =============================================================================
-- Livrée automatique distincte à la création du profil
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les huit migrations précédentes. Elle suppose :
--   - `public.profils` et le trigger `on_auth_user_created` (migration
--     20260809191018) : elle REMPLACE la fonction qu'il appelle ;
--   - `public.profils.couleur1` et `couleur2` (migration 20260814162200) : elle
--     les écrit.
--
-- Contexte : l'étape 8 a retiré les livrées attribuées par ordre d'inscription
-- (`frontend/src/lib/livrees.js`) au profit des vraies couleurs du membre. Mais
-- les défauts de colonne sont les MÊMES pour tout le monde (#800111 / #FFFFFF) :
-- tant que personne n'a personnalisé sa voiture, la vue piste d'un championnat
-- neuf montre N voitures identiques, et seul le pseudo écrit sur l'aileron
-- arrière les distingue.
--
-- Le correctif est pris là où l'étape 8 disait qu'il devait l'être : sur le
-- DÉFAUT, à la création du profil, et non dans le code des écrans — qui lit déjà
-- les vraies couleurs et n'a donc rien à changer. Aucun fichier frontend ni
-- backend n'est touché par cette migration.
--
-- La migration est idempotente : la rejouer ne casse rien et ne retouche aucun
-- profil déjà personnalisé.
-- =============================================================================

-- --  1. Les dix livrées  ------------------------------------------------------

-- Les couleurs sont celles des dix écuries de la grille. Elles ne peignent QUE
-- les voitures — jamais un fond, un bouton ou un texte d'écran —, exactement
-- comme les vingt teintes du sélecteur de l'étape 8 (`frontend/src/lib/
-- palette.js`) : la palette de la section 5 compte sept couleurs, dix livrées
-- distinctes n'en sortiraient pas.
--
-- La table est portée par une fonction et non par une table SQL : ces dix
-- couples ne sont ni administrables ni interrogeables par l'application, ils
-- sont une constante du schéma. Une table demanderait des droits, une politique
-- RLS et une migration de plus pour chaque retouche.
--
-- `immutable` : le résultat ne dépend que de l'argument. C'est ce qui permet au
-- planificateur de l'évaluer une seule fois dans la mise à jour rétroactive du
-- point 3.
create or replace function public.livree_par_indice(
  p_indice  integer,
  out couleur1 text,
  out couleur2 text
)
language sql
immutable
set search_path = ''
as $$
  select l.c1, l.c2
  from (values
    (0, '#CC0000', '#FFFFFF'),  -- Ferrari
    (1, '#000000', '#00A19C'),  -- Mercedes
    (2, '#FF8000', '#000000'),  -- McLaren
    (3, '#003087', '#FFD700'),  -- Renault
    (4, '#003087', '#CC0000'),  -- Red Bull
    (5, '#005C43', '#FFD700'),  -- Aston Martin
    (6, '#FFFFFF', '#003087'),  -- Williams
    (7, '#FFFFFF', '#CC0000'),  -- Haas
    (8, '#003087', '#FFFFFF'),  -- Racing Bulls
    (9, '#005C43', '#000000')   -- Audi
  ) as l(i, c1, c2)
  -- Le modulo est ramené dans [0, 9] par cette double opération : en PostgreSQL,
  -- `(-1) % 10` vaut -1, et l'indice tomberait alors à côté de la table. Les
  -- appels du schéma ne passent jamais de négatif, mais une fonction qui rend
  -- NULL en silence est exactement le genre de défaut qu'on ne voit qu'une fois
  -- la voiture affichée sans couleur.
  where l.i = ((p_indice % 10) + 10) % 10;
$$;

comment on function public.livree_par_indice(integer) is
  'Livrée (couleur de coque, couleur des ailerons) pour un rang d''inscription donné. Dix livrées, cycliques.';

-- --  2. Attribution à la création du profil  ----------------------------------

-- Même fonction qu'à la migration 20260809191018, à la livrée près. Le reste du
-- corps est inchangé, et ses deux comportements distincts sont conservés tels
-- quels :
--   - pseudo choisi explicitement : jamais remplacé en douce, l'inscription
--     échoue s'il est pris ;
--   - aucun pseudo transmis (Google, Apple) : un pseudo est fabriqué, avec
--     incrémentation en cas de collision, une inscription OAuth ne devant jamais
--     échouer pour cette raison.
--
-- **Le rang est compté AVANT l'insertion**, et c'est ce qui rend l'attribution
-- juste : le nouveau profil est le (N+1)ᵉ quand la table en compte N, donc son
-- indice de livrée est N modulo 10 — le premier inscrit prend la première
-- livrée, le onzième reboucle dessus. Compter après l'insertion décalerait tout
-- le monde d'un cran et le premier inscrit porterait la livrée Mercedes.
--
-- Le compte est fait une seule fois, hors de la boucle de collision de pseudo :
-- la livrée d'un membre ne dépend pas du nombre d'essais qu'il a fallu pour lui
-- trouver un pseudo libre.
--
-- **Ce trigger ne se déclenche qu'à la création** (`after insert on auth.users`,
-- inchangé) : un membre qui personnalise sa voiture depuis « Mon profil » ne la
-- voit jamais réécrite. C'est la raison pour laquelle la livrée est posée ici et
-- non par un `default` de colonne calculé, qui ne saurait pas compter les
-- profils existants.
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
  rang            int;
  livree          record;
begin
  pseudo_souhaite := nullif(trim(new.raw_user_meta_data ->> 'pseudo'), '');

  select count(*) into rang from public.profils;
  select * into livree from public.livree_par_indice(rang);

  if pseudo_souhaite is not null then
    -- Pseudo choisi explicitement à l'inscription : on ne le remplace jamais en
    -- douce. S'il est déjà pris, l'insertion échoue et l'inscription entière est
    -- annulée. Le frontend vérifie la disponibilité en amont (voir
    -- `public.pseudo_disponible`), ce chemin ne sert que si deux personnes
    -- valident le même pseudo à quelques millisecondes d'intervalle.
    insert into public.profils (id, pseudo, couleur1, couleur2)
      values (new.id, pseudo_souhaite, livree.couleur1, livree.couleur2);
    return new;
  end if;

  -- Aucun pseudo fourni : c'est une inscription via Google ou Apple, qui n'en
  -- transmettent pas. On en fabrique un. Ici la collision est improbable mais
  -- ne doit surtout pas faire échouer l'inscription : on incrémente jusqu'à
  -- trouver un pseudo libre.
  candidat := 'pilote-' || substr(replace(new.id::text, '-', ''), 1, 10);
  loop
    begin
      insert into public.profils (id, pseudo, couleur1, couleur2)
        values (new.id, candidat, livree.couleur1, livree.couleur2);
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
  'Crée le profil à l''inscription : pseudo issu des métadonnées, livrée attribuée par ordre d''inscription global.';

-- Le trigger est recréé à l'identique. `create or replace function` suffirait —
-- le trigger pointe sur la fonction par son nom — mais le redéclarer ici rend
-- la migration lisible seule : on voit à quoi la fonction ci-dessus est
-- attachée sans avoir à ouvrir la migration de l'étape 2.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.gerer_nouvel_utilisateur();

-- --  3. Reprise de l'existant  ------------------------------------------------

-- Les profils créés avant cette migration portent tous les défauts de colonne.
-- On leur attribue une livrée rétroactivement, par ordre de `cree_le`.
--
-- **Le rang est calculé sur TOUS les profils, pas seulement sur ceux à
-- reprendre.** C'est ce qui donne exactement la répartition que le trigger
-- aurait produite si la livrée avait existé depuis le début : un membre qui a
-- déjà personnalisé sa voiture occupe son rang, il ne le libère pas. Ranger les
-- seuls profils par défaut donnerait deux livrées identiques à deux voisins dès
-- qu'un troisième s'est personnalisé entre eux.
--
-- `id` départage à `cree_le` égal : deux profils créés au même instant
-- donneraient sinon une numérotation instable d'un rejeu à l'autre, et deux
-- membres échangeraient leurs couleurs.
--
-- Le critère de reprise est la paire de couleurs par défaut, comme demandé. Sa
-- limite est assumée : un membre qui aurait délibérément choisi le bordeaux de
-- la marque sur coque blanche est indiscernable d'un membre qui n'a rien
-- touché, et se verrait attribuer une livrée. C'est le prix de ne rien avoir en
-- base qui distingue « valeur par défaut » de « valeur choisie » ; le cas est
-- sans gravité (deux couleurs re-choisissables en deux appuis) et disparaît dès
-- ce premier passage — les rejeux suivants ne trouvent plus personne.
--
-- La comparaison est faite en majuscules : `profils_couleurs_hex` accepte les
-- deux casses, et `PATCH /profils/moi` normalise en majuscules, mais un client
-- Supabase écrivant en direct pourrait poser du minuscule.
with classement as (
  select
    id,
    row_number() over (order by cree_le, id) - 1 as rang
  from public.profils
)
update public.profils p
set couleur1 = l.couleur1,
    couleur2 = l.couleur2
from classement c,
     lateral public.livree_par_indice(c.rang::int) l
where p.id = c.id
  and upper(p.couleur1) = '#800111'
  and upper(p.couleur2) = '#FFFFFF';

do $$
declare
  restants int;
begin
  select count(*) into restants
  from public.profils
  where upper(couleur1) = '#800111' and upper(couleur2) = '#FFFFFF';

  if restants > 0 then
    raise warning 'Livrées : % profil(s) portent encore les couleurs par défaut.', restants;
  end if;
end
$$;

-- Les défauts de colonne (#800111 / #FFFFFF) sont volontairement laissés en
-- place. Ils ne servent plus qu'à deux choses, toutes deux hors du chemin
-- d'inscription : le repli de `classement_du_championnat` pour un membre sans
-- profil, et une éventuelle insertion directe en base. Les remplacer par une
-- livrée fixe ferait apparaître cette livrée-là deux fois dans un championnat.
