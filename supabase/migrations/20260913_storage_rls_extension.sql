-- =============================================================================
-- Storage : le nom du fichier doit être une image (migration 22)
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, APRÈS la migration
-- 16 (`20260821180000_photos_profil_championnat`), dont elle **resserre quatre
-- politiques sans les recréer**. Elle suppose donc :
--   - les deux compartiments `avatars` et `championnats` ;
--   - les quatre politiques d'écriture que la 16 a posées sur `storage.objects`.
--
-- Elle ne crée aucune table, aucune colonne, aucune contrainte : **une fonction
-- et quatre `alter policy`**. Elle est idempotente — rejouer un `alter policy`
-- qui pose la même expression ne change rien.
--
-- -----------------------------------------------------------------------------
-- Contexte : le résidu laissé ouvert par l'audit des dépôts (`0.62.0`)
-- -----------------------------------------------------------------------------
-- L'audit de `bugs-connus.md` §32 a fermé côté backend la possibilité
-- d'ENREGISTRER `avatars/{son propre id}/page.html` comme photo. Il laissait
-- ouverte celle de le DÉPOSER : la politique de la 16 ne compare que le PREMIER
-- segment du chemin (`storage.foldername(name)[1]`) à `auth.uid()`, et la liste
-- `allowed_mime_types` du compartiment porte sur l'en-tête `Content-Type`
-- annoncé — jamais sur le nom, jamais sur les octets. Sous son propre dossier,
-- n'importe quel nom était déposable.
--
-- Le résidu n'était pas une prise sur l'application : l'objet étant servi sous
-- le type annoncé, forcément l'un des trois types d'image, il ne s'exécute ni
-- dans un `<img>` ni en navigation directe. C'était un abus d'hébergement — 2 Mo
-- par dossier — et surtout **la couche qui manquait sous le contrôle backend**.
-- Une liste `allowed_mime_types` élargie un jour à `image/svg+xml` aurait suffi à
-- rendre ce trou dangereux, dans deux compartiments publics.
--
-- -----------------------------------------------------------------------------
-- ATTENTION À L'ORDRE — le piège est du même genre que celui de la 17
-- -----------------------------------------------------------------------------
-- **Rejouer la 16 APRÈS celle-ci rouvre le résidu.** La 16 fait
-- `drop policy if exists` puis `create policy` : elle repose les quatre
-- politiques dans leur version SANS contrainte de nom. Aucune erreur, aucune
-- trace — les dépôts redeviennent simplement libres sur le nom du fichier. Si la
-- 16 est rejouée pour une raison quelconque, **rejouer celle-ci derrière**, comme
-- on rejoue la 17 derrière la 16.
--
-- C'est la contrepartie assumée d'`alter policy` : la migration ne possède pas
-- les politiques, elle les amende. Voir `docs/database.md` §6.
-- =============================================================================


-- --  1. Le motif, écrit une seule fois  ---------------------------------------

-- **Quatre politiques posent la même question ; elle a un seul propriétaire.**
-- Inliner le motif quatre fois le ferait diverger au premier ajustement, et la
-- copie qu'on aurait oublié de resserrer serait devenue la porte d'entrée — même
-- raison que pour `url_de_photo_valide`, qui sert les deux domaines du backend.
--
-- **Le motif a malgré tout DEUX propriétaires, et c'est inévitable** : celui-ci
-- et `NOM_DE_FICHIER` dans `backend/app/api/stockage.py`. Deux moteurs de regex,
-- deux langages, un seul motif — ils doivent bouger ensemble. Le bloc de contrôle
-- final (§3) éprouve exactement les mêmes échantillons que le test du backend,
-- ce qui est le seul garde-fou possible contre leur dérive.
--
-- Ce que le motif INTERDIT est l'essentiel : pas de `/` après le dernier
-- séparateur, pas de `%` (donc aucune séquence encodée qu'un intermédiaire
-- décoderait autrement que nous), pas de point ailleurs que devant l'extension —
-- donc ni `page.html`, ni `avatar.jpg.svg`, ni `x.js`. **`svg` est exclu comme
-- les autres** : c'est la seule image qui porte du script, et les deux
-- compartiments sont publics.
--
-- `~*` et non `~` : la casse est ignorée sur l'extension, exactement comme le
-- backend l'ignore (`re.IGNORECASE`) et comme la 16 l'ignore sur le dossier. Un
-- objet déposé `AVATAR.JPG` est une image, et refuser la majuscule ferait échouer
-- un client légitime.
--
-- `{1,64}` tient très largement sous `RE_DUP_MAX` (255), le plafond de compteur
-- qui rendait incompilable l'expression de la 16 (`docs/database.md` §6, piège de
-- la 17). Le bloc §3 le prouve en jouant l'expression au lieu de le supposer :
-- une regex n'est compilée qu'à la première évaluation.
create or replace function public.nom_de_photo_valide(chemin text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  -- Le DERNIER segment du chemin, quel que soit le nombre de séparateurs.
  -- `regexp_replace` plutôt que `storage.filename()` : la fonction n'a alors
  -- aucune dépendance au schéma `storage`, dont les fonctions utilitaires
  -- appartiennent à `supabase_storage_admin` et pourraient être remplacées par
  -- une mise à jour de la plateforme.
  select chemin is not null
     and regexp_replace(chemin, '^.*/', '')
         ~* '^[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$';
$$;

comment on function public.nom_de_photo_valide(text) is
  'Le dernier segment de ce chemin est-il un nom de fichier image acceptable (jpg, jpeg, png, webp) ? Même motif que NOM_DE_FICHIER dans backend/app/api/stockage.py : les deux doivent bouger ensemble.';

-- **La seule fonction du projet que `authenticated` doive exécuter.** Toutes les
-- autres sont révoquées pour lui et réservées à `service_role` (§3 de
-- `docs/database.md`). Celle-ci est différente par construction : une expression
-- de politique RLS est évaluée avec les droits de l'appelant, donc un `revoke`
-- pour `authenticated` ferait échouer **tout dépôt de photo** en `42501` au lieu
-- de le filtrer. Elle ne lit aucune table et ne rend qu'un booléen : l'ouvrir ne
-- divulgue rien.
revoke all on function public.nom_de_photo_valide(text) from public;
grant execute on function public.nom_de_photo_valide(text) to authenticated;
grant execute on function public.nom_de_photo_valide(text) to service_role;


-- --  2. Les quatre politiques amendées  ---------------------------------------

-- **`alter policy`, et non `drop` + `create`.** La politique garde son nom, son
-- verbe, ses rôles et — pour les deux `update` — sa clause `using`, que l'on ne
-- mentionne pas : PostgreSQL laisse inchangée toute clause absente d'un
-- `alter policy`. Seule l'expression `with check` est réécrite.
--
-- **Il faut néanmoins la réécrire EN ENTIER**, et ce n'est pas un choix :
-- PostgreSQL ne sait pas ajouter un terme à une expression de politique
-- existante. Les deux premiers termes sont donc recopiés de la 16 à l'identique,
-- `(select auth.uid())` compris — l'enveloppe en sous-requête est l'idiome de
-- performance de Supabase, elle fait évaluer l'appel une fois pour la requête et
-- non une fois par ligne. C'est cette recopie qui crée le piège d'ordre décrit en
-- tête de fichier.
--
-- Un préalable, avant d'amender : si l'une des quatre manque, la 16 n'a pas été
-- jouée, et `alter policy` échouerait sur un `42704` qui ne dirait pas pourquoi.
do $$
declare
  attendues text[] := array[
    'Chacun depose son avatar',
    'Chacun remplace son avatar',
    'Le createur depose la photo du championnat',
    'Le createur remplace la photo du championnat'
  ];
  manquante text;
begin
  foreach manquante in array attendues loop
    if not exists (
      select 1 from pg_policies
      where schemaname = 'storage'
        and tablename  = 'objects'
        and policyname = manquante
    ) then
      raise exception
        'Politique « % » absente de storage.objects : jouer d''abord la migration 20260821180000_photos_profil_championnat.',
        manquante;
    end if;
  end loop;
end $$;

-- Avatars — dépôt de la première photo.
alter policy "Chacun depose son avatar" on storage.objects
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.nom_de_photo_valide(name)
  );

-- Avatars — remplacement. **`using` n'est pas touchée, et c'est délibéré** :
-- elle décide quelles lignes EXISTANTES sont modifiables, alors que la question
-- posée ici porte sur le nom de la NOUVELLE. Y ajouter le motif rendrait
-- immuable un objet mal nommé déposé avant cette migration — impossible à
-- écraser, donc impossible à réparer autrement qu'en le supprimant.
alter policy "Chacun remplace son avatar" on storage.objects
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.nom_de_photo_valide(name)
  );

-- Championnats — dépôt. La remontée à `championnats.cree_par` est recopiée telle
-- quelle : aucune récursion à craindre, la sous-requête porte sur
-- `public.championnats` et non sur `storage.objects` que la politique protège
-- (piège `42P17` de `docs/database.md` §2).
alter policy "Le createur depose la photo du championnat" on storage.objects
  with check (
    bucket_id = 'championnats'
    and exists (
      select 1 from public.championnats c
      where c.id::text = (storage.foldername(name))[1]
        and c.cree_par = (select auth.uid())
    )
    and public.nom_de_photo_valide(name)
  );

-- Championnats — remplacement. `using` intacte, même raison qu'aux avatars.
alter policy "Le createur remplace la photo du championnat" on storage.objects
  with check (
    bucket_id = 'championnats'
    and exists (
      select 1 from public.championnats c
      where c.id::text = (storage.foldername(name))[1]
        and c.cree_par = (select auth.uid())
    )
    and public.nom_de_photo_valide(name)
  );

-- **`select` et `delete` ne sont PAS touchées, et il faut que ce soit ainsi.**
-- `select` est la lecture publique, contrepartie assumée d'un compartiment public
-- (§9) : un objet déjà déposé doit rester lisible, y compris s'il est mal nommé —
-- sans quoi une photo d'avant cette migration disparaîtrait des écrans.
-- `delete` sert au bouton « Supprimer la photo », et c'est **le seul geste qui
-- répare** un objet mal nommé déjà en place : le filtrer le rendrait
-- indéfiniment ineffaçable. Un contrôle de nom sur un retrait protégerait le
-- déchet, pas les joueurs.


-- --  3. La migration s'éprouve elle-même  -------------------------------------

-- Règle du §6 de `docs/database.md`, tirée du piège de la 17 : **une expression
-- régulière n'est compilée qu'à la première évaluation**, et une migration qui
-- en pose une doit donc la jouer avant de rendre la main. La 16 avait posé un
-- `check` accepté à la création et incompilable à l'écriture ; aucune photo n'a
-- pu être enregistrée pendant deux migrations.
--
-- Les échantillons sont **exactement ceux du test du backend** (`bugs-connus.md`
-- §32) : c'est ce qui rend visible une dérive entre les deux motifs.
do $$
declare
  d text := '00000000-0000-0000-0000-000000000000';
  acceptes text[] := array[
    d || '/avatar.jpg',
    d || '/avatar.jpeg',
    d || '/avatar.png',
    d || '/avatar.webp',
    d || '/photo.jpg',
    d || '/AVATAR.JPG'
  ];
  refuses text[] := array[
    d || '/page.html',          -- HTML déguisé : le défaut du §32
    d || '/x.svg',              -- la seule image qui porte du script
    d || '/x.js',
    d || '/avatar.jpg.svg',     -- double extension
    d || '/avatar.jpg?v=1',     -- le péremptoire de cache vit dans l'URL, JAMAIS
                                -- dans la clé de l'objet : le voir ici serait le
                                -- signe qu'on valide la mauvaise chaîne
    d || '/%2e%2e%2fautre.jpg', -- séquence encodée
    d || '/',                   -- dossier nu
    d || '/avatar.',            -- extension vide
    d || '/.jpg'                -- nom vide
  ];
  echantillon text;
begin
  foreach echantillon in array acceptes loop
    if not public.nom_de_photo_valide(echantillon) then
      raise exception 'nom_de_photo_valide refuse un nom légitime : %', echantillon;
    end if;
  end loop;

  foreach echantillon in array refuses loop
    if public.nom_de_photo_valide(echantillon) then
      raise exception 'nom_de_photo_valide accepte un nom à refuser : %', echantillon;
    end if;
  end loop;

  -- Le motif porte sur le DERNIER segment seulement : un sous-dossier passe, et
  -- c'est assumé. `{dossier}/sous/avatar.jpg` reste une image sous le dossier du
  -- propriétaire, donc sans danger ; le backend le refuse de son côté, ce qui
  -- suffit à ce qu'il ne devienne jamais une photo enregistrée.
  if not public.nom_de_photo_valide(d || '/sous/avatar.jpg') then
    raise exception 'Le motif ne devrait porter que sur le dernier segment.';
  end if;
end $$;

-- Le contrôle d'état : les quatre `with check` portent bien le nouveau terme, et
-- les deux `using` des politiques `update` ont bien SURVÉCU à l'`alter policy`.
-- Ce second point est le seul que la migration ne peut pas supposer : toute la
-- méthode repose sur le fait qu'une clause absente d'un `alter policy` reste
-- inchangée, et une régression le viderait **sans erreur** — les dépôts
-- continueraient de marcher, mais n'importe qui pourrait écraser la photo de
-- n'importe qui. C'est exactement la nature du défaut du §28.
do $$
declare
  sans_motif integer;
  sans_using integer;
begin
  select count(*) into sans_motif
  from pg_policies
  where schemaname = 'storage'
    and tablename  = 'objects'
    and policyname in (
      'Chacun depose son avatar',
      'Chacun remplace son avatar',
      'Le createur depose la photo du championnat',
      'Le createur remplace la photo du championnat'
    )
    and (with_check is null or with_check not like '%nom_de_photo_valide%');

  if sans_motif > 0 then
    raise exception
      '% politique(s) d''écriture sans contrainte de nom : l''alter policy n''a pas pris.',
      sans_motif;
  end if;

  select count(*) into sans_using
  from pg_policies
  where schemaname = 'storage'
    and tablename  = 'objects'
    and policyname in (
      'Chacun remplace son avatar',
      'Le createur remplace la photo du championnat'
    )
    and (qual is null or qual not like '%foldername%');

  if sans_using > 0 then
    raise exception
      'La clause using d''% politique(s) update a été perdue : rejouer la migration 20260821180000.',
      sans_using;
  end if;
end $$;
