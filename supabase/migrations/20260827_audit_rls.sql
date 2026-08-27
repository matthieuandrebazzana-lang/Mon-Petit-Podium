-- =============================================================================
-- Étape 21 — Audit des politiques RLS : correctifs
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, **après les vingt
-- précédentes**. Elle ne crée ni table, ni colonne, ni fonction : elle remplace
-- trois politiques `select`, retire deux politiques `insert` devenues sans
-- emploi, et resserre des droits de table et de colonne.
--
-- Elle suppose appliquées la 1, la 2, la 3, la 5, la 8, la 12, la 14 et la 20.
-- Elle ne touche **aucune fonction `security definer`** : `est_membre`,
-- `creer_championnat`, `pronostics_du_championnat`, `attribuer_points` et les
-- autres restent exactement ce qu'elles sont (`database.md` §3). Elle les
-- réutilise, elle ne les réécrit pas.
--
-- > ### Ce que cette migration NE fait pas, et pourquoi il faut le savoir
-- >
-- > Toutes les écritures de l'application passent par FastAPI avec la **clé de
-- > service**, qui contourne la RLS (`CLAUDE.md` §3.4). Aucune politique
-- > resserrée ici ne change donc ce que l'application fait : elle change ce
-- > qu'un porteur de la clé publique peut faire **en dehors** d'elle, avec un
-- > client Supabase à lui. C'est exactement la surface qu'un audit RLS couvre,
-- > et c'est la seule.
-- >
-- > **Corollaire pour l'étape 3 ci-dessous** : la fenêtre de fermeture posée
-- > sur `public.pronostics` ne rend PAS les pronostics privés dans l'app. Le
-- > tableau des résultats est servi par `pronostics_du_championnat`, fonction
-- > `security definer` réservée à `service_role`, dont l'autorisation est
-- > portée par la route. La règle métier « visibles dès leur saisie »
-- > (`metier.md`, samedi soir → dimanche) reste donc en vigueur côté écran.
-- > **L'écart est signalé, pas tranché** : le refermer vraiment demanderait de
-- > toucher à cette fonction et à la route, ce que l'audit s'interdit.
--
-- La migration est idempotente : chaque politique est `drop`ée avant d'être
-- recréée, chaque `revoke` porte sur un droit déjà retiré au second passage.
-- Le bloc de contrôle final la vérifie et lève si l'état obtenu n'est pas
-- l'état voulu.
--
-- > ### Conflits d'ordre introduits — quatre, tous du même genre
-- >
-- > | Si vous rejouez… | …vous perdez | Remède |
-- > |---|---|---|
-- > | **1**, **8** ou **12** après **21** | la lecture des profils redevient ouverte à toute l'application | rejouer 21 |
-- > | **5** après **21** | la fenêtre de fermeture sur les pronostics | rejouer 21 |
-- > | **2** après **21** | l'adhésion et la création libres, de nouveau | rejouer 21 |
-- > | **3** après **21** | les cotes redeviennent lisibles sans session | rejouer 21 |
-- >
-- > Ces quatre migrations recréent, sous leur ancien nom, la politique que
-- > celle-ci remplace. Deux politiques `select` permissives sur une même table
-- > se combinent par **OU** : la plus large gagne, sans bruit. C'est pour cela
-- > que l'étape correspondante commence toujours par `drop policy if exists`
-- > sur **l'ancien nom**, et que rejouer la 21 suffit à réparer.
-- =============================================================================


-- --  1. `public.profils` — la lecture cesse d'être ouverte à tout le monde  ----

-- ÉTAT AUDITÉ. Migrations 1, 8 et 12, toutes trois avec le même texte :
--
--     on public.profils for select to authenticated using (true)
--
-- Autrement dit : **n'importe quel compte lit la table des profils entière**.
-- Pseudo, couleurs, numéro, livrée, `avatar_url`, `is_admin`, dates — de tous
-- les inscrits, y compris ceux avec qui l'appelant ne partage rien. L'app étant
-- ouverte au public (`CLAUDE.md` §1), une inscription suffit pour énumérer sa
-- population entière. Le commentaire de la migration 1 dit le besoin réel :
-- « les classements et les listes de membres d'un championnat ont besoin des
-- pseudos des AUTRES » — des autres membres, pas des autres inscrits.
--
-- CE QUI EST DEMANDÉ. `avatar_url`, `couleur1`, `couleur2`, `numero` et
-- `livree_mode` doivent rester lisibles par les membres d'un championnat
-- commun : la voiture se peint sur l'écran de quelqu'un d'autre. C'est le
-- périmètre exact retenu ci-dessous.
--
-- COMPATIBILITÉ VÉRIFIÉE. Les quatre seules lectures directes de `profils` sous
-- RLS y survivent toutes, aucune n'ayant jamais demandé plus :
--
--   | Appelant | Ce qu'il lit |
--   |---|---|
--   | `lib/profils.js` `chargerIdentite`   | sa propre ligne |
--   | `lib/profils.js` `chargerEstAdmin`   | sa propre ligne |
--   | `lib/profils.js` `chargerNumerosPris`| les profils de ses co-membres |
--   | `lib/championnats.js`                | les profils des membres du championnat affiché |
--
-- Le backend, lui, lit avec la clé de service et ne voit pas cette politique.
--
-- PAS DE RÉCURSION. La sous-requête porte sur `membres_championnat`, dont la
-- propre politique appelle `est_membre` — `security definer`, donc lisant sans
-- repasser par les politiques. Rien ne revient sur `public.profils`. C'est la
-- forme déjà employée par la politique de lecture des pronostics (§2 de
-- `database.md`), reprise à l'identique plutôt que réinventée.
drop policy if exists "Profils lisibles par les membres connectes" on public.profils;
drop policy if exists "Profils lisibles par les membres partages"  on public.profils;
create policy "Profils lisibles par les membres partages"
  on public.profils for select
  to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.membres_championnat m
      where m.profil_id = profils.id
        and public.est_membre(m.championnat_id)
    )
  );


-- --  2. `public.profils` — `is_admin` cesse d'être modifiable depuis un client  -

-- ÉTAT AUDITÉ. La politique d'écriture est juste sur la LIGNE et aveugle sur la
-- COLONNE :
--
--     for update to authenticated using (auth.uid() = id) with check (auth.uid() = id)
--
-- `database.md` §5 le documente comme sans conséquence, et il a raison sur le
-- fond : `is_admin` ne garde rien, `POST /scraper/declencher` est fermée par
-- `X-Admin-Secret`. Mais « sans conséquence aujourd'hui » n'est pas « correct » :
-- le jour où `is_admin` gardera quelque chose, le trou sera déjà là. Le §5
-- annonce d'ailleurs le remède exact — « une politique `with check` par colonne,
-- ou une route backend qui exige le jeton ». La RLS de PostgreSQL ne sait pas
-- filtrer par colonne ; le **droit de colonne**, lui, le sait, et il est
-- antérieur à toute politique.
--
-- MÉTHODE. Un droit `update` de TABLE vaut pour toutes les colonnes, y compris
-- celles ajoutées ensuite : le resserrer demande de le retirer, puis de le
-- redonner colonne par colonne. Les huit colonnes ci-dessous sont exactement
-- celles que `PATCH /profils/moi` accepte ; `id`, `cree_le`, `modifie_le` et
-- `is_admin` en sont exclues.
--
-- `modifie_le` reste écrite par son trigger : les droits de colonne portent sur
-- les colonnes NOMMÉES par l'ordre `update`, jamais sur ce qu'un trigger pose
-- dans `NEW`.
--
-- CE QUE CELA NE FAIT PAS, ET C'EST SIGNALÉ. `is_admin` reste **lisible** par
-- les co-membres, l'étape 1 ne l'ayant retirée qu'aux inconnus. La rendre
-- invisible aux autres demanderait `revoke select (is_admin)`, qui fermerait
-- aussi la lecture de SA PROPRE ligne — donc `lib/profils.js chargerEstAdmin`,
-- donc la section Administration. Le correctif complet est une ligne de SQL et
-- une ligne de frontend, et le frontend est hors du périmètre de cet audit.
revoke insert, update, delete on public.profils from anon, authenticated;

grant update (
  pseudo,
  couleur1,
  couleur2,
  numero,
  livree_mode,
  livree_ecurie,
  avatar_url,
  couleur_texte
) on public.profils to authenticated;

-- `insert` et `delete` sont retirés pour la raison que la migration 1 énonçait
-- déjà sans la doubler d'un droit : « un profil naît avec son compte via le
-- trigger, et meurt avec lui par cascade ». Aucune politique ne les autorisait,
-- donc rien ne change ; c'est le second verrou des tables publiques
-- (`database.md` §2), que `public.profils` était seule à ne pas avoir.
-- Le trigger d'inscription est `security definer` : il n'est pas concerné.


-- --  3. `public.pronostics` — la lecture des autres attend la fermeture  -------

-- ÉTAT AUDITÉ. La politique de la migration 5 cadre correctement QUI, et ne dit
-- rien de QUAND :
--
--     profil_id = auth.uid()
--     or exists (… membres_championnat m … est_membre(m.championnat_id))
--
-- Le cadrage par championnat partagé est juste et n'est pas retouché. Ce qui
-- manque est la fenêtre : un membre peut lire, depuis un client Supabase, les
-- pronostics d'un co-membre **avant** que la saisie ne ferme, et jouer ensuite
-- sur cette information. `public.pronostics_fermes(uuid)` répond exactement à
-- la question, existe déjà, est `stable`, `security invoker`, et ouverte à
-- `authenticated` : elle est réutilisée telle quelle.
--
-- ORDRE DES TERMES. `pronostics_fermes` d'abord : c'est une lecture sur la clé
-- primaire de `grands_prix`, moins chère que le `exists` sur
-- `membres_championnat` qu'elle évite quand elle rend faux.
--
-- PAS DE RÉCURSION. `pronostics_fermes` lit `public.grands_prix`, dont la
-- politique ne renvoie sur rien. Le premier terme reste indispensable : un
-- joueur sans championnat doit relire ses propres pronostics, fermés ou non —
-- c'est ce que font `chargerMesPronostics` et `chargerMesGpPronostiques`.
drop policy if exists "Pronostics visibles entre membres"        on public.pronostics;
drop policy if exists "Pronostics visibles apres la fermeture"   on public.pronostics;
create policy "Pronostics visibles apres la fermeture"
  on public.pronostics for select
  to authenticated
  using (
    profil_id = (select auth.uid())
    or (
      public.pronostics_fermes(gp_id)
      and exists (
        select 1
        from public.membres_championnat m
        where m.profil_id = pronostics.profil_id
          and public.est_membre(m.championnat_id)
      )
    )
  );

-- `public.pronostic_podium` n'est PAS retouchée, et c'est le point de sa
-- conception. Sa politique de lecture ne teste que l'existence du pronostic
-- parent ; cette sous-requête est elle-même filtrée par la politique ci-dessus.
-- La fenêtre de fermeture s'y propage donc seule. Redire la condition ici
-- créerait les deux textes à maintenir en parallèle que `database.md` §2
-- interdit.


-- --  4. `public.membres_championnat` — l'adhésion cesse d'être libre  ----------

-- ÉTAT AUDITÉ, LECTURE : `using (public.est_membre(championnat_id))`. **Correct
-- et non réécrit.** On ne voit les membres que des championnats dont on fait
-- partie ; un championnat étranger ne rend aucune ligne.
--
-- ÉTAT AUDITÉ, SUPPRESSION : `using (profil_id = auth.uid())`. **Correct et non
-- réécrit.** Chacun ne retire que lui-même.
--
-- ÉTAT AUDITÉ, INSERTION — le défaut :
--
--     for insert to authenticated with check (auth.uid() is not null)
--
-- « Être connecté » n'est pas une autorisation. Cette clause laisse insérer
-- **n'importe quel couple** `(championnat_id, profil_id)` : s'ajouter à un
-- championnat dont on connaît l'identifiant **sans en avoir le code
-- d'invitation** — l'identifiant circule dans une URL partagée —, ou y ajouter
-- **quelqu'un d'autre**, dont on lit l'identifiant sur n'importe quelle ligne de
-- `profils`. La politique de lecture, elle, cadrait bien : c'est l'écriture qui
-- ouvrait la porte que la lecture gardait.
--
-- REMÈDE : le retrait, pas le resserrement. L'adhésion se fait par
-- `POST /championnats/rejoindre`, qui cherche le championnat PAR SON CODE puis
-- insère avec la clé de service — donc hors RLS. Aucun écran n'insère dans
-- cette table depuis le client (le frontend n'appelle `.insert()` nulle part).
-- La politique ne servait donc rien, et sous RLS ce qu'aucune politique
-- n'autorise est refusé. Un `with check (profil_id = auth.uid())` aurait laissé
-- subsister le premier des deux abus.
drop policy if exists "Adhesion reservee aux connectes" on public.membres_championnat;
revoke insert on public.membres_championnat from anon, authenticated;


-- --  5. `public.championnats` — la création cesse d'être libre  ----------------

-- ÉTAT AUDITÉ, LECTURE : `using (public.est_membre(id))`. **Correct et non
-- réécrit.** Un non-membre ne lit ni le nom, ni le code d'invitation, ni la
-- photo d'un championnat. La recherche par code, elle, se fait côté backend
-- avec la clé de service, comme il se doit.
--
-- ÉTAT AUDITÉ, MODIFICATION et SUPPRESSION : `cree_par = auth.uid()` en `using`
-- ET en `with check`. **Correct et non réécrit** — le `with check` interdit de
-- se donner un championnat dont on n'est pas le créateur.
--
-- ÉTAT AUDITÉ, INSERTION — le même défaut qu'à l'étape 4 :
--
--     for insert to authenticated with check (auth.uid() is not null)
--
-- Elle laisse insérer une ligne portant **le `cree_par` de quelqu'un d'autre**,
-- et surtout **le `code_invitation` de son choix** : `code_invitation` est
-- unique, donc réserver les codes courts revient à empêcher leur attribution
-- aux vrais championnats — la boucle de génération de `championnats.py` en
-- tirerait un autre, mais l'espace se pollue à coût nul. La ligne posée est par
-- ailleurs invisible de son insérant, qui n'en est pas membre.
--
-- REMÈDE, identique et pour la même raison : la création passe par
-- `creer_championnat`, `security definer` réservée à `service_role`, qui pose
-- le championnat ET son premier membre dans une transaction. La politique
-- client ne sert rien.
drop policy if exists "Creation reservee aux connectes" on public.championnats;
revoke insert on public.championnats from anon, authenticated;


-- --  6. `public.cotes` — réservées aux comptes connectés  ---------------------

-- ÉTAT AUDITÉ : `to anon, authenticated using (true)`, doublé d'un
-- `grant select … to anon`. Aucune politique d'écriture, aucun droit
-- d'écriture : **cette moitié-là est correcte et n'est pas touchée.**
--
-- CE QUI CHANGE, ET C'EST LE SEUL EFFET VISIBLE DE CETTE MIGRATION. La lecture
-- publique de la migration 3 couvre trois tables d'un même geste, avec un motif
-- qui n'en concerne que deux : « la landing doit pouvoir annoncer le prochain
-- GP sans session ». C'est vrai de `grands_prix`, dont `chargerProchainGp` lit
-- une ligne, et de `resultats_gp`, que l'écran public de résultats affiche.
-- **Ce n'est pas vrai des cotes** : les trois écrans qui les lisent — saisie,
-- récapitulatif, mes résultats — sont tous derrière `RouteProtegee`, et
-- `chargerCotesEnBase` sert le calendrier, protégé lui aussi. La grille des
-- points d'un Grand Prix est le contenu de jeu ; rien n'oblige à la servir sans
-- session.
--
-- `grands_prix` et `resultats_gp` restent donc publics, délibérément.
--
-- `cotes_du_grand_prix(uuid)` est `security invoker` : elle lit sous les
-- politiques de l'appelant et suit ce resserrement sans qu'on la touche — ce
-- qui est précisément ce qu'on attend d'elle. Son `grant … to anon` devient
-- sans objet mais n'est pas retiré : la fonction n'ouvre rien que la table
-- n'ouvre déjà.
drop policy if exists "Cotes lisibles par tous"         on public.cotes;
drop policy if exists "Cotes lisibles par les connectes" on public.cotes;
create policy "Cotes lisibles par les connectes"
  on public.cotes for select
  to authenticated
  using (true);

revoke select on public.cotes from anon;


-- --  7. Ce qui a été audité et laissé tel quel  --------------------------------

-- Rien de ce qui suit n'est réécrit. Le noter explicitement est le but d'un
-- audit autant que les correctifs ci-dessus : une politique juste réécrite pour
-- la forme devient une politique de plus à relire.
--
--   | Table / objet | Politique | Verdict |
--   |---|---|---|
--   | `favoris` | `for all` sur `profil_id = auth.uid()` | juste — brouillons strictement privés, lecture ET écriture |
--   | `pronostics` | `insert` / `update` / `delete` sur `profil_id = auth.uid()` | juste — `using` et `with check` tous deux posés sur l'`update` |
--   | `pronostic_podium` | `select` par existence du parent, `for all` par l'auteur du parent | juste — hérite de l'étape 3 sans la redire |
--   | `membres_championnat` | `select` par `est_membre`, `delete` pour soi | juste |
--   | `championnats` | `select` par `est_membre`, `update` / `delete` par le créateur | juste |
--   | `grands_prix`, `resultats_gp` | lecture `anon` + `authenticated`, aucune écriture | juste — voir l'étape 6 |
--   | `storage.objects` | six politiques d'écriture, deux compartiments | juste — le premier segment du chemin EST l'autorisation |
--   | fonctions `security definer` | `revoke … from public` puis `grant … to service_role` | hors périmètre, et intactes |
--
-- `public.pronostics_favoris` **n'existe pas** : la table des favoris s'appelle
-- `public.favoris` (migration 5), et c'est elle qui est auditée ci-dessus.
--
-- OBSERVATION À TRANCHER PLUS TARD, PAS ICI. Le frontend n'écrit dans AUCUNE
-- table Supabase directement — il n'appelle ni `.insert()`, ni `.update()`, ni
-- `.upsert()`, ni `.delete()` : toute écriture passe par FastAPI et la clé de
-- service. Les politiques d'écriture restantes (`favoris`, `pronostics`,
-- `pronostic_podium`, `championnats`, `membres_championnat`) sont donc du
-- second verrou, jamais un chemin emprunté. Les retirer serait cohérent ; les
-- garder l'est aussi, elles sont correctes et gardent une porte si un écran
-- venait à écrire en direct. **Le choix appartient au projet, pas à l'audit.**


-- --  8. Contrôle — la migration s'éprouve elle-même  ---------------------------

-- La leçon des migrations 17 et 19 appliquée à des politiques : jouer la
-- migration doit suffire à savoir qu'elle a produit l'état voulu. Une politique
-- mal écrite ne lève rien à la création — elle se contente de ne rien filtrer,
-- ou de tout filtrer, et le symptôme est silencieux dans les deux sens.
do $$
declare
  manquant text;
begin
  -- 8.1 — profils : une seule politique de lecture, et c'est la nouvelle.
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profils' and cmd = 'SELECT'
      and policyname <> 'Profils lisibles par les membres partages'
  ) then
    select string_agg(policyname, ', ') into manquant
    from pg_policies
    where schemaname = 'public' and tablename = 'profils' and cmd = 'SELECT'
      and policyname <> 'Profils lisibles par les membres partages';
    raise exception 'Profils : une politique de lecture permissive subsiste (%). Deux politiques select se combinent par OU.', manquant;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profils'
      and policyname = 'Profils lisibles par les membres partages'
  ) then
    raise exception 'Profils : la nouvelle politique de lecture est absente.';
  end if;

  -- 8.2 — pronostics : la fenêtre de fermeture est bien dans le texte.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pronostics' and cmd = 'SELECT'
      and qual like '%pronostics_fermes%'
  ) then
    raise exception 'Pronostics : la politique de lecture ne mentionne pas pronostics_fermes.';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pronostics' and cmd = 'SELECT'
      and policyname = 'Pronostics visibles entre membres'
  ) then
    raise exception 'Pronostics : l''ancienne politique sans fenêtre subsiste.';
  end if;

  -- 8.3 — plus aucune politique d'insertion côté client sur les deux tables
  --       de championnat.
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename in ('championnats', 'membres_championnat')
      and cmd = 'INSERT'
  ) then
    raise exception 'Championnats : une politique d''insertion client subsiste.';
  end if;

  -- 8.4 — droits de colonne sur profils. Le rôle `authenticated` n'existe que
  --       sur Supabase : sur une base jetable, le contrôle est sauté plutôt que
  --       de faire échouer la migration sur une absence attendue.
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    if has_column_privilege('authenticated', 'public.profils', 'is_admin', 'update') then
      raise exception 'Profils : is_admin reste modifiable par le rôle authenticated.';
    end if;
    if has_column_privilege('authenticated', 'public.profils', 'id', 'update') then
      raise exception 'Profils : id reste modifiable par le rôle authenticated.';
    end if;
    if not has_column_privilege('authenticated', 'public.profils', 'pseudo', 'update') then
      raise exception 'Profils : pseudo n''est plus modifiable — le grant par colonne a été perdu.';
    end if;
    if not has_column_privilege('authenticated', 'public.profils', 'couleur_texte', 'update') then
      raise exception 'Profils : couleur_texte n''est plus modifiable — le grant par colonne a été perdu.';
    end if;
    if has_table_privilege('authenticated', 'public.profils', 'insert') then
      raise exception 'Profils : le droit d''insertion client subsiste.';
    end if;
    if has_table_privilege('authenticated', 'public.membres_championnat', 'insert') then
      raise exception 'Membres : le droit d''insertion client subsiste.';
    end if;
    if not has_table_privilege('authenticated', 'public.cotes', 'select') then
      raise exception 'Cotes : le droit de lecture des connectés a été perdu.';
    end if;
  end if;

  if exists (select 1 from pg_roles where rolname = 'anon') then
    if has_table_privilege('anon', 'public.cotes', 'select') then
      raise exception 'Cotes : anon lit toujours la table.';
    end if;
    if not has_table_privilege('anon', 'public.grands_prix', 'select') then
      raise exception 'Grands prix : la lecture publique a été perdue — la landing en dépend.';
    end if;
    if not has_table_privilege('anon', 'public.resultats_gp', 'select') then
      raise exception 'Résultats : la lecture publique a été perdue — l''écran public de résultats en dépend.';
    end if;
  end if;

  raise notice 'Audit RLS : les six correctifs sont en place, les lectures publiques voulues sont intactes.';
end $$;
