-- =============================================================================
-- Compte administrateur : un drapeau `is_admin` sur `public.profils`
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les treize migrations précédentes. Elle ne crée AUCUNE table, ne
-- remplace AUCUNE fonction et ne touche à AUCUNE politique : une colonne, et
-- rien d'autre.
--
-- Elle suppose appliquée la 1 (`20260809191018`), qui crée `public.profils`.
-- Ne remplaçant aucune fonction, elle ne peut pas entrer en conflit d'ordre
-- avec une migration antérieure rejouée par-dessus — contrairement aux pièges
-- déjà documentés (« rejouer la 7 après la 8 », « rejouer la 5 après la 10 »).
--
-- La migration est idempotente : la rejouer ne casse rien et ne promeut
-- personne.
-- =============================================================================


-- --  1. La colonne  -----------------------------------------------------------

-- `not null default false` : **l'absence de réponse est un refus**. Une colonne
-- nullable ferait de `NULL` un troisième état, que chaque lecteur devrait
-- interpréter — et un `NULL` traité comme vrai par mégarde ouvrirait la section
-- d'administration à tout le monde. Ici il n'y a que deux valeurs, et le défaut
-- est le moins privilégié des deux.
--
-- Les comptes déjà en base reçoivent donc `false` : **la promotion du premier
-- administrateur se fait à la main**, dans le SQL Editor, et c'est voulu. Un
-- `update` de reprise qui promouvrait « le plus ancien compte » se tromperait
-- de personne le jour où la base est restaurée depuis une sauvegarde, et
-- personne ne s'en apercevrait.
--
--     update public.profils set is_admin = true where pseudo = '<ton pseudo>';
alter table public.profils
  add column if not exists is_admin boolean not null default false;

comment on column public.profils.is_admin is
  'Drapeau d''administration. Ne gouverne QUE l''affichage de la section d''administration du profil : le backend, lui, ne connaît que le secret X-Admin-Secret. Ne jamais l''exposer à une écriture par le membre lui-même.';


-- --  2. Ce que cette migration ne fait PAS, et pourquoi  ----------------------

-- **Aucune politique RLS n'est ajoutée ni modifiée.** Les deux politiques de la
-- migration 1 couvrent déjà exactement ce cas :
--   - « Profils lisibles par les membres connectés » sert la nouvelle colonne
--     comme les autres, donc chacun lit son propre drapeau ;
--   - « Chacun modifie son profil » porte sur la LIGNE, pas sur la colonne :
--     un membre peut donc techniquement écrire `is_admin` en passant
--     directement par un client Supabase.
--
-- Ce second point est une limite connue et assumée, et il ne se corrige pas
-- ici : ce drapeau ne garde rien. Il ne fait qu'AFFICHER une section ; le seul
-- garde réel de `POST /scraper/declencher` est le secret `X-Admin-Secret`
-- vérifié côté backend par `exiger_secret`, à temps constant. Quelqu'un qui se
-- promeut lui-même voit deux boutons, et rien de plus, tant qu'il n'a pas le
-- secret.
--
-- Le jour où `is_admin` devra vraiment garder quelque chose, c'est une
-- politique `with check` par colonne — ou le retrait pur et simple du droit
-- d'`update` sur cette colonne à `authenticated` — qu'il faudra écrire, PAS un
-- contrôle applicatif de plus.
