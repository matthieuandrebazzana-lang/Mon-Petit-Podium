-- =============================================================================
-- Diviseur 10 : remise à zéro des points déjà calculés
-- =============================================================================
-- À exécuter dans le SQL Editor du tableau de bord Supabase, ou via la CLI,
-- APRÈS les quatorze migrations précédentes.
--
-- Depuis la v0.45.0, les points valent **la cote × 10** et non plus × 100 : une
-- cote de 2,80 rapporte 28 points, pas 280. La règle « les points sont des
-- entiers » ne bouge pas, seul le multiplicateur change (`en_points()` dans
-- `backend/app/scraper/unibet.py`, et lui seul).
--
-- Cette migration ne convertit RIEN. Elle efface ce qui a été calculé sur
-- l'ancienne échelle, pour que le scraper et `attribuer_points` le
-- reconstruisent sur la nouvelle. Aucun vrai Grand Prix n'ayant encore été
-- joué, il n'y a pas de score de saison à préserver — et une division par dix
-- appliquée deux fois par mégarde donnerait des points cent fois trop petits,
-- sans que rien ne le signale.
--
-- Elle ne crée aucune table, ne remplace AUCUNE fonction et ne touche à AUCUNE
-- politique. Ne remplaçant aucune fonction, elle ne peut pas entrer en conflit
-- d'ordre avec une migration antérieure rejouée par-dessus.
--
-- **Elle est idempotente au sens fort** : chacune des trois opérations est un
-- effacement ou un retour à un état, jamais un calcul sur la valeur courante.
-- La rejouer dix fois donne exactement le même résultat qu'une fois.
-- =============================================================================


-- --  1. Les points attribués repassent à `NULL`, jamais à `0`  ---------------

-- **`NULL` et `0` ne se confondent JAMAIS** (voir `docs/metier.md` §1 et
-- `docs/database.md` §1). `0` veut dire « pronostic raté », et un `update`
-- à `0` marquerait ratés des pronostics que personne n'a jugés : le joueur
-- verrait un mauvais bilan au lieu d'une attente.
--
-- `NULL` veut dire « pas encore jugé ». C'est aussi exactement la condition
-- que `attribuer_points` exige pour écrire (`where points_gagnes is null`) :
-- remettre `NULL` est donc la seule valeur qui rende un nouveau calcul
-- possible. Un `0` bloquerait le rattrapage pour toujours.
update public.pronostics
   set points_gagnes = null
 where points_gagnes is not null;

update public.pronostic_podium
   set points_gagnes = null
 where points_gagnes is not null;


-- --  2. Les cotes en base sont des points, elles aussi  ----------------------

-- `cotes.valeur` **est déjà un nombre de points** — rien en base ne stocke une
-- cote (`docs/database.md` §1). Toutes les lignes présentes ont donc été
-- écrites en × 100, et les laisser en place ferait payer les pronostics à
-- l'ancienne échelle au prochain `attribuer_points`, sans qu'aucune erreur
-- n'apparaisse nulle part.
--
-- On les efface plutôt que de les diviser : la contrainte `valeur > 0`
-- interdit la remise à zéro, et une division ne serait pas rejouable. Le
-- scraper les réécrit intégralement au prochain passage, sur la nouvelle
-- échelle, avec les mêmes `id_outcome_unibet`.
--
-- **Les pronostics et les favoris survivent** : ni l'un ni l'autre n'a de clé
-- étrangère vers `public.cotes`, précisément pour ce genre de réécriture. Le
-- rapprochement se refait à la lecture, et une issue momentanément absente est
-- servie sans points au lieu d'être effacée.
delete from public.cotes;


-- --  3. Rouvrir les Grands Prix figés, sinon le scraper ne réécrira rien  ----

-- Le scraper **ne touche jamais** aux cotes d'un GP dont le statut est
-- `cotes_figees` : c'est ce qui garantit que tout le monde pronostique sur les
-- mêmes cotes une fois les qualifications passées. Après l'effacement du §2, un
-- GP resté figé serait donc un GP sans aucune cote, définitivement — plus
-- personne ne pourrait y pronostiquer.
--
-- Les GP `termine` ne sont pas touchés : leur course a eu lieu, il n'y a rien à
-- rescraper. Le job de `app/jobs/scraper.py` refigera les autres tout seul deux
-- heures après leurs qualifications.
update public.grands_prix
   set statut = 'a_venir'
 where statut = 'cotes_figees';


-- --  4. Après cette migration  -----------------------------------------------

-- 1. Déclencher un scraping (`POST /scraper/declencher`, ou le bouton de la
--    section Administration) pour réécrire les cotes sur la nouvelle échelle.
-- 2. Pour un GP déjà couru dont `resultats_gp` porte les données brutes,
--    rejouer le calcul : `attribuer_points` écrira sur les `NULL` du §1 avec
--    les cotes du §2. Rien à récupérer chez OpenF1.
