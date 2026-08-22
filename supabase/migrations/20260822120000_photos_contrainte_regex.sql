-- =============================================================================
-- Correctif : les deux contraintes de format d'URL de photo étaient INAPPLICABLES
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, APRÈS la migration
-- `20260821180000_photos_profil_championnat`, dont elle remplace les deux
-- contraintes `check`.
--
-- Idempotente. Ne touche à aucune donnée : elle ne fait que remplacer deux
-- contraintes par deux contraintes de MÊME sémantique, écrites autrement.
--
-- -----------------------------------------------------------------------------
-- LE DÉFAUT
-- -----------------------------------------------------------------------------
-- La migration 16 posait, sur `profils.avatar_url` et `championnats.photo_url` :
--
--     check (colonne is null or colonne ~ '^https://[^[:space:]]{10,505}$')
--
-- **Le moteur d'expressions régulières de PostgreSQL plafonne un compteur de
-- répétition `{m,n}` à 255** (`RE_DUP_MAX`). `{10,505}` dépasse ce plafond, et
-- l'expression n'est donc PAS compilable. Elle n'échoue pas à la création de la
-- contrainte — un `check` n'est évalué qu'à l'écriture d'une ligne, et aucune
-- ligne ne portait encore de photo. Elle échoue à la PREMIÈRE écriture :
--
--     ERROR 2201B: invalid regular expression: invalid repetition count(s)
--
-- Conséquence, mesurée sur la base de production le 22/08/2026 : **aucune photo
-- n'a jamais pu être enregistrée**, ni celle d'un joueur ni celle d'un
-- championnat. Le fichier partait bien dans Supabase Storage — les compartiments
-- et leurs politiques, eux, sont corrects — mais l'écriture de son URL en base
-- retombait en `422` sur les deux routes concernées :
--
--   * `PATCH /profils/moi`        → « Enregistrement de ta voiture : impossible »
--     (le message parlait de la voiture parce que c'est la même route ; c'est ce
--     qui a rendu le défaut si difficile à rattacher à sa cause)
--   * `PATCH /championnats/{id}`  → « Enregistrement de la photo du championnat »
--     avalé en silence par l'écran de création, qui laisse partir le joueur vers
--     son championnat quoi qu'il arrive.
--
-- -----------------------------------------------------------------------------
-- LE CORRECTIF
-- -----------------------------------------------------------------------------
-- La borne de longueur sort de l'expression régulière et devient un
-- `char_length`. **La sémantique est identique**, à la lettre :
--
--     '^https://[^[:space:]]{10,505}$'   ⇔   commence par « https:// »,
--                                            aucun blanc ensuite,
--                                            18 ≤ longueur totale ≤ 513
--
-- Le `+` ne porte plus aucun compteur, donc plus aucun plafond. Et une borne de
-- longueur exprimée par `char_length` est de toute façon ce qu'elle est : une
-- borne de longueur. La coder dans le quantificateur d'une classe de caractères
-- mélangeait deux questions dans une seule expression, et c'est précisément ce
-- mélange qui a fait franchir le plafond sans que personne ne le voie.
--
-- Le reste de la doctrine de la migration 16 est **inchangé** : la forme seule
-- est contrainte en base, jamais le nom d'hôte du projet — y coder l'URL Supabase
-- figerait la base sur un projet, et une restauration ailleurs refuserait toutes
-- les photos existantes. Le rattachement au projet reste jugé par le backend
-- (`app/api/stockage.py`), qui connaît `SUPABASE_URL`.
-- =============================================================================


-- --  1. Profils  --------------------------------------------------------------

alter table public.profils
  drop constraint if exists profils_avatar_url_format;

alter table public.profils
  add constraint profils_avatar_url_format
  check (
    avatar_url is null
    or (
      avatar_url ~ '^https://[^[:space:]]+$'
      and char_length(avatar_url) between 18 and 513
    )
  );

comment on constraint profils_avatar_url_format on public.profils is
  'URL de photo de profil : https, sans blanc, 18 à 513 caractères. La longueur est portée par char_length et non par un quantificateur — PostgreSQL plafonne {m,n} à 255.';


-- --  2. Championnats  ---------------------------------------------------------

alter table public.championnats
  drop constraint if exists championnats_photo_url_format;

alter table public.championnats
  add constraint championnats_photo_url_format
  check (
    photo_url is null
    or (
      photo_url ~ '^https://[^[:space:]]+$'
      and char_length(photo_url) between 18 and 513
    )
  );

comment on constraint championnats_photo_url_format on public.championnats is
  'URL de photo de championnat : https, sans blanc, 18 à 513 caractères. Même remarque que profils_avatar_url_format sur le plafond de {m,n}.';


-- --  3. Contrôle  -------------------------------------------------------------

-- Les deux contraintes sont éprouvées ici même, sur une valeur jetable : une
-- contrainte `check` n'étant évaluée qu'à l'écriture, c'est le seul moyen de
-- savoir en jouant la migration qu'elle est bien compilable. C'est exactement
-- ce qui manquait à la migration 16.
do $$
declare
  echantillon text := 'https://exemple.supabase.co/storage/v1/object/public/avatars/00000000-0000-0000-0000-000000000000/avatar.jpg?v=1';
begin
  if not (echantillon ~ '^https://[^[:space:]]+$'
          and char_length(echantillon) between 18 and 513) then
    raise exception 'Contrainte de format : une URL de photo légitime est refusée.';
  end if;

  if ('https://exemple.supabase.co/a b.jpg' ~ '^https://[^[:space:]]+$') then
    raise exception 'Contrainte de format : une URL contenant un blanc est acceptée.';
  end if;

  raise notice 'Contraintes de format d''URL de photo : compilables et correctes.';
end $$;
