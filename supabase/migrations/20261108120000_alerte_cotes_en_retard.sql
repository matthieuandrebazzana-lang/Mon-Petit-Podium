-- =============================================================================
--  Migration 37 — Type d'alerte `cotes_en_retard`
-- =============================================================================
--
-- `scraper.md` §8, backend 0.88.2. Le 7 novembre 2026, les cotes du GP du
-- Brésil n'étaient pas en base à la fin de la fenêtre fixe de quatre heures du
-- job de scraping, et rien ne l'a signalé : elles n'ont été récupérées que par
-- un `POST /scraper/declencher` passé à la main.
--
-- Le job réessaie désormais jusqu'au départ de la course, et UNE HEURE après
-- l'heure prévue (qualifications + 2 h) il écrit une alerte `cotes_en_retard`
-- (`cle` vide, une par GP) et envoie une notification push aux administrateurs.
-- La création de la ligne tient lieu de réservation : seul le tour qui la crée
-- notifie. Elle est effacée au figeage, automatique ou manuel.
--
-- Seule la contrainte de type change : la liste de la 36, plus le nouveau.
--
-- **Conflit d'ordre** : la contrainte `alertes_admin_type_valide` est
-- remplacée. Rejouer la 26, la 29 ou la 36 après celle-ci retire le type —
-- l'alerte est alors refusée par la base, seuls le journal et la notification
-- (envoyée une fois par processus) la gardent. Remède : rejouer la 37.
--
-- À appliquer AVANT ou APRÈS le backend 0.88.2, indifféremment. Idempotente.
-- =============================================================================

alter table public.alertes_admin
  drop constraint if exists alertes_admin_type_valide;

alter table public.alertes_admin
  add constraint alertes_admin_type_valide
  check (type in (
    'libelle_non_reconnu',
    'rattachement_impossible',
    'definitif_en_echec',
    'grand_prix_ambigu',
    'pronostics_en_attente',
    'cotes_en_retard'
  ));
