-- =============================================================================
--  Migration 35 — GP du Mexique 2026 : « Hirakawa, Ryo » rattaché au n°50
-- =============================================================================
--
-- Symptôme : un pronostic « Top 10 — Hirakawa, Ryo » reste « En attente » après
-- le calcul définitif. Ryo Hirakawa remplaçait Esteban Ocon chez Haas pour ce
-- seul week-end ; il finit 10ᵉ.
--
-- Cause : Unibet a écrit le remplaçant « Nom, Prénom » (« Hirakawa, Ryo »),
-- forme qu'aucune des clés de rapprochement du backend 0.87.2 ne produit
-- (« ryohirakawa », « rhirakawa », « hirakawa », « hir »… mais jamais
-- « hirakawaryo »). Au figeage, l'issue n'a reçu aucun `numero_pilote` ; au
-- calcul, le repli par libellé n'a rien trouvé non plus (`bugs-connus.md` §44).
--
-- Correction : poser sur les cinq cotes de ce libellé le numéro que lui donne
-- OpenF1 — n°50, « Ryo HIRAKAWA », Haas F1 Team, dans `/drivers` de la
-- qualification (session 11400) et de la course (11404). Le calcul consulte ce
-- numéro AVANT le libellé (`points.rattacher_identifiants`) : le backend déjà
-- déployé juge donc ces pronostics dès le recalcul, sans livraison de code.
--
-- Garde : seules les cotes du GP du Mexique portant EXACTEMENT ce libellé et
-- encore sans numéro sont touchées. Idempotente. Aucune fonction remplacée :
-- aucun conflit d'ordre.
--
-- Ensuite, recalcul définitif :
--   curl -X POST "https://mon-petit-podium-production.up.railway.app/jobs/resultats/6cbac282-10ac-45c9-a382-05f4a4e05fa4/recalcul?relire=true" \
--     -H "X-Admin-Secret: <valeur>"
-- =============================================================================

update public.cotes
   set numero_pilote = 50
 where gp_id = '6cbac282-10ac-45c9-a382-05f4a4e05fa4'
   and pilote = 'Hirakawa, Ryo'
   and numero_pilote is null;

do $$
begin
  if exists (
    select 1 from public.cotes
     where gp_id = '6cbac282-10ac-45c9-a382-05f4a4e05fa4'
       and pilote = 'Hirakawa, Ryo'
       and numero_pilote is distinct from 50
  ) then
    raise exception 'GP du Mexique : une cote « Hirakawa, Ryo » ne porte pas le n°50';
  end if;
end
$$;
