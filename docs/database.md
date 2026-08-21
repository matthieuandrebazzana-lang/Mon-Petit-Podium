# Base de données

Schéma PostgreSQL (Supabase), politiques RLS, fonctions et migrations.

> **Les migrations s'appliquent À LA MAIN dans le SQL Editor de Supabase**, dans
> l'ordre, une par une. Aucune CI ne les joue. Toutes sont idempotentes : les rejouer
> ne casse rien — mais **l'ordre compte**, voir §6.

---

## 1. Les neuf tables

```
auth.users
    │ 1─1 (cascade)
    ▼
public.profils ──────────┐
    │                    │
    │ (cree_par, SET NULL)
    ▼                    │
public.championnats      │
    │ 1─N (cascade)      │
    ▼                    │
public.membres_championnat ◄─┘

public.grands_prix
    │ 1─N (cascade)          1─1 (cascade, unique)
    ├──► public.cotes        └──► public.resultats_gp
    ├──► public.favoris
    └──► public.pronostics ──1─1(cascade)──► public.pronostic_podium
```

### `public.profils`

| Colonne | Type | Note |
|---|---|---|
| `id` | uuid PK | → `auth.users`, cascade |
| `pseudo` | text | **index unique sur `lower(pseudo)`** |
| `cree_le`, `modifie_le` | timestamptz | `modifie_le` par trigger |
| `couleur1` | text, défaut `#800111` | coque de la voiture |
| `couleur2` | text, défaut `#FFFFFF` | ailerons |
| `numero` | integer, **nullable** | 1 à 99 |
| `livree_mode` | text, défaut `perso` | `perso` \| `ecurie` |
| `livree_ecurie` | text, nullable | slug (`^[a-z0-9-]{2,32}$`) |
| `is_admin` | boolean, **not null** défaut `false` | affichage seul, voir §5 |
| `avatar_url` | text, **nullable** | URL publique Storage, jamais de base64 |

Contraintes : `pseudo` 2–20 caractères ; `numero` entre 1 et 99 ; couleurs au format
`#RRGGBB` ; **couleurs distinctes à la casse près** ; `livree_ecurie` obligatoire si
`livree_mode = 'ecurie'`.

> **L'unicité du pseudo est un index sur `lower(pseudo)`, pas un `unique` nu.** Un UNIQUE
> ordinaire laisserait coexister « MaxV33 » et « maxv33 », que tout le monde lirait comme
> la même personne. **L'extension `citext` ferait le même travail** au prix d'une extension
> à gérer ; un index fonctionnel l'évite.

> **`numero` n'a AUCUNE contrainte d'unicité, et c'est délibéré.** Une voiture étant
> identique dans tous les championnats de son propriétaire, un numéro unique globalement
> voudrait dire **99 comptes maximum sur toute l'application**. L'unicité est indicative,
> jugée à l'affichage : le frontend avertit, il ne bloque jamais.

> **Deux colonnes de livrée plutôt qu'une nullable** : un membre qui essaie une livrée
> puis revient à ses couleurs garde son dernier choix d'écurie et le retrouve s'il
> rebascule.

> **`livree_ecurie` est contrainte par son FORMAT, jamais par une liste des onze écuries.**
> Une énumération en base figerait la grille — les onze voitures sont un actif du
> frontend qui se relit chaque saison.

> **`avatar_url` ne porte QUE l'URL** (migration 16). Une image de 2 Mo en base64 pèserait
> 2,7 Mo dans une colonne `text`, serait relue à chaque classement et traverserait le
> réseau à chaque affichage. La contrainte `profils_avatar_url_format` ne vérifie que la
> **forme** (`https://`, ≤ 512 caractères) : y coder l'URL du projet Supabase figerait la
> base sur un projet, et une restauration ailleurs refuserait toutes les photos
> existantes. **Le rattachement au projet se juge côté backend**, dans
> `app/api/stockage.py`, seul endroit qui connaisse `SUPABASE_URL` — voir §9.

### `public.championnats`

| Colonne | Type | Note |
|---|---|---|
| `id` | uuid PK | |
| `nom` | text | 2–40 caractères |
| `code_invitation` | text **unique** | `^[A-Z0-9]{6}$` |
| `cree_par` | uuid **nullable** | → `auth.users`, **`on delete set null`** |
| `cree_le` | timestamptz | |
| `photo_url` | text, **nullable** | URL publique Storage, mêmes règles qu'`avatar_url` |

> **`cree_par` est nullable et ne cascade pas.** Supprimer le compte du créateur ne doit
> pas emporter le championnat de tous les autres membres : il survit, sans créateur.
> **Conséquence assumée** : sur un championnat orphelin, la politique « Seul le createur
> supprime » ne vaut jamais vrai, donc plus personne ne peut le supprimer depuis le
> frontend. Il disparaîtra de lui-même au départ du dernier membre (§4).

### `public.membres_championnat`

PK `(championnat_id, profil_id)`, cascade sur les deux références, `rejoint_le`
(4ᵉ critère de départage). Index supplémentaire sur `profil_id` : la PK couvre les
recherches par championnat, mais « mes championnats » part du profil et balaierait
toute la table sans lui.

### `public.grands_prix`

| Colonne | Type | Note |
|---|---|---|
| `id_unibet` | text **unique** | **clé de rapprochement du scraper** |
| `nom` | text | orthographe changeante — jamais une clé |
| `date_course` | timestamptz, nullable | **en UTC** |
| `date_qualifications` | timestamptz, nullable | migration 11 |
| `statut` | text | `a_venir` \| `cotes_figees` \| `termine` |

> **Le rapprochement se fait sur `id_unibet`, JAMAIS sur le nom.** Unibet écrit
> « GP Pays Bas » cette semaine et « GP Pays-Bas » la suivante.

> **`statut` est une contrainte `check`, pas un type `enum`.** Ajouter une valeur à un
> enum PostgreSQL est une migration à part entière.

> **`date_qualifications` est nullable, et pas seulement par prudence.** Unibet publie
> parfois un GP avant d'en annoncer le programme ; un `not null` obligerait le scraper à
> inventer une date ou à ne pas écrire la ligne — donc à faire disparaître le GP de
> l'accueil et du calendrier.

### `public.cotes`

`id`, `gp_id` (cascade), `marche` (slug), `libelle_marche` (libellé du bookmaker),
`pilote`, `valeur` (**integer > 0**), `id_outcome_unibet` (**not null**), `cree_le`.

> **`valeur` est déjà le nombre de points** — cote × 10 arrondie. **Rien en base ne
> stocke « 2,80 »** (voir `metier.md` §1).

> **`id_outcome_unibet` est `not null`, et c'est ce qui fait tenir l'idempotence.** Sous
> PostgreSQL, deux `NULL` sont distincts : un index unique sur une colonne nullable
> n'empêcherait plus rien. Une issue sans identifiant est **ignorée** plutôt qu'insérée.

Index : `cotes_gp_outcome_idx` **unique** sur `(gp_id, id_outcome_unibet)` — il porte
seul l'idempotence du scraper ; `cotes_gp_marche_idx` sur `(gp_id, marche)`.

> **`libelle_marche` est un ajout assumé.** Sans lui, l'interface reconstituerait un nom
> depuis le slug et afficherait « Ecurie vainqueur » au mieux, « Top x » au pire. Le
> bookmaker est la seule source légitime du nom d'un marché.

### `public.favoris`

PK `(profil_id, gp_id, id_outcome_unibet)`, cascade, `cree_le`.

> **Aucune clé étrangère vers `public.cotes`, et c'est délibéré.** Le scraper réécrit les
> cotes tant qu'elles ne sont pas figées ; une issue qu'Unibet retire ferait échouer son
> upsert, ou emporterait les favoris des joueurs par cascade. Le rapprochement se fait à
> la lecture — **un favori orphelin est servi sans points plutôt qu'effacé.**

### `public.pronostics`

`id`, `profil_id`, `gp_id`, `id_outcome_unibet`, `type` (`vainqueur`|`podium`|`bonus`),
`points_gagnes` (integer **nullable**, `>= 0`), `cree_le`, `modifie_le`.

**Trois index PARTIELS, pas un index unique sur `(profil_id, gp_id, type)`** — celui-ci
interdirait aussi d'avoir plus d'un bonus, alors que la règle en demande trois :

| Index | Portée |
|---|---|
| `pronostics_un_vainqueur_idx` | `where type = 'vainqueur'` |
| `pronostics_un_podium_idx` | `where type = 'podium'` |
| `pronostics_bonus_distincts_idx` | `(profil_id, gp_id, id_outcome_unibet) where type = 'bonus'` |

Le maximum de trois bonus **ne peut pas** s'écrire en `check` (la contrainte porte sur
plusieurs lignes) : c'est le trigger `pronostics_max_trois_bonus`.

> ### `points_gagnes` — trois états, et `NULL` ≠ `0`
>
> | Valeur | Sens |
> |---|---|
> | `NULL` | résultat inconnu, **ou marché que le calcul n'a pas su valider** |
> | `0` | pronostic raté |
> | `> 0` | pronostic réussi |
>
> **C'est la convention la plus structurante du projet, et elle est tenue partout.**
> Marquer « raté » un pronostic qu'on n'a pas su valider volerait le joueur en silence.
> `NULL` se voit dans les logs, s'affiche « en attente », et se rattrape par un second
> passage.

### `public.pronostic_podium`

`pronostic_id` (PK, cascade), `pilote_1`, `pilote_2`, `points_gagnes`.
`check (pilote_1 <> pilote_2)`.

> **Aucun ordre entre les deux pilotes.** La validation demande « ces deux pilotes
> sont-ils sur le podium ? », jamais « lequel devant ». `pilote_1` et `pilote_2` ne sont
> que des emplacements — d'où le paiement à la **somme** des deux cotes (`metier.md` §2).

La redondance avec `pronostics.id_outcome_unibet` (qui porte `pilote_1`) est tenue par
**deux triggers, pas par une convention** : `pronostic_podium_coherent` refuse un détail
dont `pilote_1` diverge du parent, et `attribuer_points` dérive systématiquement
`points_gagnes` de la colonne parente. **Ne jamais l'écrire depuis le code applicatif.**

### `public.resultats_gp`

`id`, `gp_id` (**unique**, cascade), `recupere_le`, `donnees_brutes` (jsonb).

> **`donnees_brutes` n'est pas un cache de confort** : c'est ce qui permet de **rejouer
> le calcul sans rappeler OpenF1**, donc de corriger un validateur ou d'en ajouter un
> pour un marché resté à `NULL`, des semaines après la course.

Objet `{ session, session_result, drivers, race_control, laps, starting_grid, pilotes }`.
**`laps` est réduit au meilleur tour par pilote** — la réponse complète pèse 654 Ko par GP.

---

## 2. RLS — le piège de la récursion, et sa sortie

**Toutes les tables ont la RLS activée.**

> ### `42P17` — la règle à ne jamais défaire
>
> Les politiques de lecture se formulent « il existe une ligne dans
> `membres_championnat` avec ce `championnat_id` et `profil_id = auth.uid()` ». Écrite
> telle quelle dans une politique **de** `membres_championnat`, la condition interroge la
> table que la politique protège : PostgreSQL détecte la récursion et **refuse la
> requête** (`42P17`). La politique de `championnats` tombe dans le même piège.
>
> **`public.est_membre(uuid)`, en `security definer`, casse la boucle** en lisant sans
> repasser par les politiques. La sémantique est exactement celle voulue ; seule
> l'écriture change. **Ne jamais réinsérer la sous-requête littérale dans ces politiques.**

| Table | Lecture | Écriture |
|---|---|---|
| `profils` | tout membre **connecté** | son propre profil |
| `championnats` | ses membres (`est_membre`) | créateur seul modifie/supprime |
| `membres_championnat` | entre membres | adhésion et départ pour soi-même |
| `grands_prix`, `cotes`, `resultats_gp` | **tous, `anon` compris** | **aucune politique** |
| `favoris` | **strictement privés** | soi-même |
| `pronostics` | les siens, **ou** ceux d'un membre d'un championnat partagé | soi-même |
| `pronostic_podium` | via l'existence du pronostic parent | son auteur |
| `storage.objects` (2 compartiments) | **tous, `anon` compris** | le propriétaire du dossier (§9) |

> **Lecture publique des GP, cotes et résultats** : ils sont affichés tels quels chez le
> bookmaker, et la landing doit pouvoir annoncer le prochain GP sans session.
> **Aucune politique d'écriture n'est créée** — sous RLS, ce qu'aucune politique
> n'autorise est refusé. Aucun droit d'écriture n'est accordé à `anon` ni
> `authenticated` non plus : double verrou.

> **Les favoris sont privés parce que ce sont des brouillons.** Les laisser lire
> reviendrait à annoncer ses pronostics avant de les avoir saisis.

> **`pronostic_podium` NE REDIT PAS la condition** : sa politique ne teste que
> l'existence du parent, dont la sous-requête est elle-même filtrée. Écrire la règle
> deux fois créerait deux textes à maintenir en parallèle.

---

## 3. Les fonctions

### Réservées à `service_role` (révoquées pour `public`, `anon`, `authenticated`)

| Fonction | Rôle |
|---|---|
| `creer_championnat(nom, code, createur)` | championnat **+** son créateur, une transaction |
| `mes_championnats(profil)` | championnats + effectif + photo, une requête |
| `quitter_championnat(profil, championnat)` | retrait **+** effacement conditionnel, atomiques |
| `enregistrer_pronostics(...)` | efface le jeu précédent et écrit le nouveau, une transaction |
| `pronostics_du_joueur(profil, gp)` | pronostics rapprochés des cotes (`left join`) |
| `pronostics_du_championnat(championnat, gp)` | tous les membres, voiture et total |
| `attribuer_points(gp, jsonb)` | **la fonction la plus sensible du projet** |
| `classement_du_championnat(championnat)` | classement trié et rangé, avatars compris |
| `stats_du_profil(profil, saison)` | les quatre chiffres de la grille 2×2 |
| `calendrier_du_championnat(championnat, profil, saison)` | une ligne par GP |
| `classement_du_grand_prix(gp)` | classement de la course |

> **Pourquoi `security definer` + `service_role` sur les fonctions de lecture agrégée.**
> Paramétrées par un championnat ou un profil, elles lisent forcément les pronostics
> d'autrui. Sous l'identité de l'appelant, la politique RLS filtrerait les membres avec
> qui il ne partage rien — exactement ce qu'il faut protéger, mais qui rendrait un
> classement **silencieusement amputé** au lieu d'un refus franc. **L'autorisation est
> donc portée par la route, qui vérifie l'appartenance AVANT l'appel.**

> **`creer_championnat` est atomique pour une raison précise** : deux appels REST séparés
> laisseraient, en cas d'échec du second, un championnat sans aucun membre — invisible de
> tous, y compris de son créateur, et impossible à rejoindre.

> **`attribuer_points` n'écrit QUE les pronostics dont `points_gagnes` est encore `NULL`.**
> C'est la base qui porte l'idempotence, pas le code appelant : appelée dix fois avec des
> valeurs différentes, elle n'attribue rien deux fois. Ouverte à `authenticated`, elle
> laisserait n'importe qui s'attribuer le score de son choix.

### Ouvertes

| Fonction | Portée |
|---|---|
| `est_membre(uuid)` | `security definer` — casse la récursion RLS |
| `pseudo_disponible(text)` | **appelable sans être connecté** |
| `cotes_du_grand_prix(uuid)` | `security invoker` — lit sous les politiques publiques |
| `pronostics_fermes(uuid)` | `security invoker`, `authenticated` |
| `livree_par_indice(integer)` | `immutable`, les dix livrées initiales |

> **`pseudo_disponible` révèle qu'un pseudo est pris, sans dire par qui.** C'est le
> compromis normal d'un champ de pseudo, ceux-ci étant de toute façon affichés dans les
> classements. **À ne jamais transposer aux emails.** Si l'appel échoue, la réponse est
> « disponible » et l'inscription continue — la garantie reste l'index en base.

### Triggers

| Trigger | Sur | Rôle |
|---|---|---|
| `on_auth_user_created` | `auth.users` | crée le profil **et sa livrée initiale** |
| `profils_modifie_le`, `pronostics_modifie_le` | | horodatage |
| `membres_championnat_supprime_vide` | `membres_championnat` | supprime un championnat vidé |
| `pronostics_max_trois_bonus` | `pronostics` | maximum de 3 bonus |
| `pronostic_podium_coherent` | `pronostic_podium` | invariant `pilote_1` = parent |

> **`gerer_nouvel_utilisateur` a deux comportements distincts, délibérément :**
> un **pseudo choisi explicitement** n'est jamais remplacé en douce — s'il est pris,
> l'inscription entière échoue (renommer discrètement quelqu'un serait pire qu'un refus) ;
> **aucun pseudo transmis** (Google, Apple) → `pilote-xxxxxxxxxx` fabriqué avec
> incrémentation. Une inscription OAuth ne doit jamais échouer pour cette raison.
>
> Le message « Ce pseudo est déjà pris » repose sur le fait que **ce trigger est le seul
> posé sur `auth.users`** — en ajouter un autre obligera à revoir la traduction dans
> `lib/erreurs.js`.

> **`membres_championnat_supprime_vide` — quatre points à ne pas défaire :**
> `security definer` (le dernier membre n'est pas toujours le créateur, la politique
> l'empêcherait d'effacer la ligne) ; **`after`, jamais `before`** (un `before` compterait
> les membres avant le retrait, le dernier départ trouverait toujours quelqu'un) ;
> `for each row` (une suppression peut porter sur plusieurs championnats) ; **aucun garde
> `pg_trigger_depth()`** — la récursion s'arrête d'elle-même.

---

## 4. Conventions de nommage

- **Tout en français, en minuscules, avec des underscores.**
- Tables au pluriel (`profils`, `cotes`), sauf `pronostic_podium` — une ligne de détail
  pour un pronostic, jamais une collection.
- Clés étrangères : `<table_au_singulier>_id` (`gp_id`, `profil_id`, `championnat_id`).
- Horodatages : `cree_le`, `modifie_le`, `rejoint_le`, `recupere_le`.
- Fonctions : verbe à l'infinitif pour une action (`creer_championnat`,
  `attribuer_points`), nom de ce qui est rendu pour une lecture (`mes_championnats`,
  `classement_du_championnat`).
- Index : `<table>_<colonnes>_idx`, suffixé du critère pour un index partiel
  (`pronostics_a_calculer_idx`).
- Contraintes : `<table>_<ce_qu_elle_garantit>` (`profils_couleurs_distinctes`).

---

## 5. `is_admin` décide d'un affichage, jamais d'un droit

Trois raisons le rendent **structurellement incapable** de garder quoi que ce soit :

1. `POST /scraper/declencher` ne le connaît pas — elle est fermée par `X-Admin-Secret`.
2. **Le secret voyage en clair dans le bundle** (`architecture.md` §5).
3. **La politique « Chacun modifie son profil » porte sur la LIGNE, pas sur la colonne** :
   un membre peut écrire son propre `is_admin` via un client Supabase. Sans conséquence —
   il verrait deux boutons, et rien de plus, tant qu'il n'a pas le secret.

Le premier administrateur se désigne **à la main** — un `update` qui promouvrait
« le plus ancien compte » se tromperait de personne après une restauration :

```sql
update public.profils set is_admin = true where pseudo = '<ton pseudo>';
```

Le jour où `is_admin` doit vraiment garder quelque chose : une politique `with check` par
colonne, ou une route backend qui exige le **jeton** du membre — **pas un contrôle
applicatif de plus**.

---

## 6. Les seize migrations

| # | Fichier | Ce qu'elle fait | Dépend de |
|---|---|---|---|
| 1 | `20260809191018_profils_pseudo_unique` | `profils`, unicité, trigger d'inscription | — |
| 2 | `20260810163435_championnats` | `championnats`, `membres_championnat`, `est_membre` | — |
| 3 | `20260813174500_grands_prix_cotes` | `grands_prix`, `cotes` | — |
| 4 | `20260813182331_createur_nullable_championnat_vide` | `cree_par` nullable, trigger de suppression | 2 |
| 5 | `20260813183636_favoris_pronostics` | `favoris`, `pronostics`, `pronostic_podium` | 2, 3, 4 |
| 6 | `20260813205200_resultats_points` | `points_gagnes`, `resultats_gp`, `attribuer_points` | 3, 5 |
| 7 | `20260814103000_classement_championnat` | `classement_du_championnat` | 2, 5, 6 |
| 8 | `20260814162200_profil_voiture_stats` | voiture sur `profils`, `stats_du_profil` | 1, 5, 6, 7 |
| 9 | `20260814183000_livree_automatique` | livrée initiale à l'inscription | 1, 8 |
| 10 | `20260814213000_calendrier_championnat` | `calendrier_du_championnat` | 3, 5, 6, 8 |
| 11 | `20260816120000_date_qualifications` | `date_qualifications` | 3 |
| 12 | `20260819124500_livree_ecurie` | `livree_mode`, `livree_ecurie` | 1, 8, 10 |
| 13 | `20260820120000_calendrier_date_qualifications` | ajoute le champ au calendrier | 10, 11 |
| 14 | `20260820150000_profil_is_admin` | `is_admin` | 1 |
| 15 | `20260821143000_points_diviseur_10` | remise à zéro des points (diviseur 10) | 3, 5, 6 |
| 16 | `20260821180000_photos_profil_championnat` | `avatar_url`, `photo_url`, 2 compartiments Storage | 1, 2, 12 |

### Le piège d'ordre — la seule chose à surveiller

**Les migrations sont idempotentes chacune pour elle-même, PAS dans le désordre.**
Plusieurs `create or replace function` la même fonction : rejouer une migration
**antérieure** par-dessus restaure sa version d'avant.

| Si vous rejouez… | …vous perdez | Remède |
|---|---|---|
| **1** après **9** | la livrée automatique à l'inscription | rejouer 9 |
| **7** après **8** ou **12** | les champs de voiture au classement | rejouer 8 puis 12 |
| **5** après **10** ou **12** | voiture + total au tableau des résultats | rejouer 10 puis 12 |
| **8** ou **10** après **12** | la livrée d'écurie | rejouer 12 |
| **10** après **13** | `date_qualifications` au calendrier | rejouer 13 |
| **2**, **8**, **10** ou **12** après **16** | les photos aux cartes, classements et résultats | rejouer 16 |

**Les migrations 11, 14 et 15 ne remplacent aucune fonction** : elles ne peuvent pas
entrer en conflit d'ordre.

> **La 16 est la seule qui SUPPRIME une fonction avant de la recréer.** `mes_championnats`
> déclare un `returns table (…)`, et PostgreSQL refuse de remplacer une fonction dont le
> type de retour change (`42P13`) — ajouter `photo_url` au tableau EST un changement de
> type. D'où un `drop function if exists` suivi d'un `create`, et surtout **les `revoke`
> et le `grant` reposés juste après** : `drop` emporte les droits avec la fonction, et une
> fonction recréée est exécutable par `public` par défaut. Les oublier l'ouvrirait à
> `anon`, donc à quiconque détient la clé publique du frontend.
>
> Elle remplace par ailleurs `classement_du_championnat` et `pronostics_du_championnat`,
> comme la 12 avant elle. Rejouer la 2, la 8, la 10 ou la 12 par-dessus fait disparaître
> les photos des cartes, des classements et du tableau des résultats — sans rien casser
> d'autre, le frontend retombant sur les initiales.

> **La 15 est la seule qui touche aux DONNÉES et non au schéma.** Elle vide
> `public.cotes`, repasse à `NULL` les deux colonnes `points_gagnes` et rouvre les GP
> `cotes_figees` — le multiplicateur des points est passé de 100 à 10 (`metier.md` §1),
> et tout ce qui avait été calculé l'avait été sur l'ancienne échelle. **Elle n'a rien
> converti** : diviser par dix une seconde fois par mégarde ne se verrait pas. Chacune
> de ses trois opérations est un retour à un état, donc rejouable telle quelle.
>
> **Après l'avoir jouée, déclencher un scraping** : sans cotes, aucun GP n'est
> pronosticable.

### Non éprouvées sur un PostgreSQL jetable

Les migrations **12, 13 et 14** n'ont pas été jouées contre un Docker (démon indisponible
au moment de leur écriture), contrairement aux onze premières. La 13 a été comparée ligne
à ligne à la 10 : trois lignes de différence, toutes attendues. **À surveiller au premier
passage dans le SQL Editor.**

---

## 7. Pièges connus

> **La comparaison d'instant se calcule en Python, en UTC, pas en SQL.** Un `now`
> interprété par PostgreSQL dépendrait du fuseau de la session. Le suffixe `Z` est
> préféré à `+00:00`, dont le `+` se confond avec une espace une fois la requête encodée.

> **`nullslast` / `nullsFirst: false` n'est jamais cosmétique.** PostgreSQL place les
> `NULL` en tête : sans cette clause, un GP dont l'horaire n'est pas annoncé passerait
> devant la course de dimanche.

> **La saison est l'année civile du GP, lue en UTC** (`at time zone 'UTC'` explicite),
> sans quoi le résultat dépendrait du fuseau de la session.

> **Un commentaire périmé subsiste dans la migration 3** : il annonce que `date_course`
> est convertie depuis l'heure de Paris. C'est faux depuis la v0.40.0 (voir
> `bugs-connus.md`). Les migrations sont historiques et ne sont pas réécrites.

> **`row_number` vs `rank`** — le classement de saison emploie `row_number` (les quatre
> critères départagent toujours) ; le classement d'**un** GP emploie `rank`, parce qu'il
> n'a aucun critère de départage : avant le départ, tout le monde est à zéro et
> `row_number` inventerait un premier et un dernier.

> **`left join lateral`, jamais un `group by`** dans les classements : un membre qui n'a
> jamais pronostiqué doit apparaître avec 0 point, pas disparaître de la liste.

> **`meilleure_cote` vaut `NULL`, jamais `0`**, pour qui n'a rien réussi. Le tri, lui,
> ramène le `NULL` à `0`.

---

## 8. Codes d'erreur — les reconnaître dans les logs

Depuis la v0.9.0 ils ne quittent plus le serveur : **il faut ouvrir les logs Railway.**

| Code | Sens | Cause typique |
|---|---|---|
| `42P01` | relation inexistante | **migration non appliquée** |
| `42703` | colonne inexistante | migration partiellement appliquée, ou rejouée dans le désordre |
| `42883` | fonction inexistante | migration non appliquée |
| `42501` | droits insuffisants | fonction `service_role` appelée sous une autre identité |
| `42P17` | **récursion de politique** | sous-requête littérale réinsérée dans une politique RLS (§2) |
| `23505` | violation d'unicité | collision de code d'invitation, ou favori déjà épinglé |
| `23503` | violation de clé étrangère | référence vers une ligne supprimée |

**Codes applicatifs levés par les fonctions SQL :**

| Code | Levé par | Sens |
|---|---|---|
| `PT423` | `enregistrer_pronostics` | pronostics **fermés** — la vérification qui fait foi |
| `PT403` | `enregistrer_pronostics` | plus de **trois bonus** |

> **`23505` sur la bascule d'un favori n'est PAS une erreur** : c'est l'état demandé,
> atteint par un appel concurrent. La bascule est une suppression puis, si rien n'a été
> supprimé, une insertion — **c'est la base qui tranche**, jamais une lecture préalable qui
> laisserait deux appuis rapprochés retomber du même côté.

> **`PT423` prouve que le refus est atomique** : la fonction commence par effacer le jeu
> précédent, et lève ensuite si la fermeture est passée — **la transaction annule le
> `delete`**. Un test le vérifie explicitement.

---

## 9. Supabase Storage — deux compartiments, et où vit l'autorisation

Migration 16. Les images ne sont **jamais** en base : `profils.avatar_url` et
`championnats.photo_url` ne portent que des URL publiques (§1).

| Compartiment | Chemin d'un objet | Qui écrit |
|---|---|---|
| `avatars` | `{profil_id}/avatar.{ext}` | le profil lui-même (`auth.uid()`) |
| `championnats` | `{championnat_id}/photo.{ext}` | le **créateur** du championnat |

Les deux sont **publics**, plafonnés à **2 Mo**, et n'acceptent que `image/jpeg`,
`image/png` et `image/webp`.

> **Le premier segment du chemin EST l'autorisation.** La politique compare
> `(storage.foldername(name))[1]` à `auth.uid()` pour un avatar, et remonte à
> `championnats.cree_par` pour une photo de championnat. Personne ne peut donc écrire dans
> le dossier d'un autre, quel que soit le client utilisé — c'est la base qui refuse, pas le
> code de l'écran. **Aucune récursion à craindre** ici : la sous-requête porte sur
> `public.championnats`, pas sur `storage.objects` que la politique protège (§2).

> **Trois politiques d'écriture par compartiment, et il en faut bien trois** : `insert`
> pose la première photo, `update` écrase la suivante — le chemin est stable —, `delete`
> sert au bouton « Supprimer la photo ». Sous RLS, ce qu'aucune politique n'autorise est
> refusé : en oublier une fermerait silencieusement un des trois gestes.

> **Compartiments publics, et c'est un arbitrage.** Une photo de profil s'affiche sur la
> carte d'un autre joueur, dans un classement partagé, sur la piste. Un compartiment privé
> obligerait à signer une URL par image et par affichage, donc un aller-retour réseau par
> vignette d'un classement de douze. Même raisonnement que la lecture publique des GP et
> des cotes (§2).

> **Le plafond et la liste des types vivent dans le COMPARTIMENT, pas dans le client.**
> `frontend/src/lib/stockage.js` fait la même vérification, mais pour dire non tout de
> suite — 2 Mo montés sur un réseau mobile avant d'être refusés seraient 2 Mo perdus. Le
> `heic` d'un iPhone n'est pas dans la liste et n'a pas à y être : Safari convertit en JPEG
> à la sélection d'un fichier.

> ### L'URL enregistrée en base est vérifiée par le backend, et il faut que ce soit là
>
> Le chemin d'écriture est celui de `docs/architecture.md` §3 : **le fichier va
> directement à Supabase** (la RLS Storage décrit exactement le cas), **l'URL passe par
> FastAPI** (c'est une écriture en base). `app/api/stockage.py` confronte alors l'URL reçue
> à `SUPABASE_URL` : elle doit désigner **notre** projet et **le bon compartiment**.
>
> Sans cette vérification, une URL libre en base deviendrait un **pixel espion posé sur
> l'écran des autres joueurs** — sa photo s'affiche au classement, sur la piste, au résumé
> d'un Grand Prix, et chaque affichage révélerait l'IP et le `User-Agent` de ces joueurs au
> serveur choisi par l'auteur de l'URL. L'app est ouverte au public : ce n'est pas une
> hypothèse d'école.
>
> **Sans `SUPABASE_URL`, tout est refusé** (`503`) plutôt que tout accepté. Le service
> démarre sans les clés pour garder `/health` joignable (`architecture.md` §5) ; dans cet
> état, laisser passer serait l'inverse du sens du doute voulu ici.

> **Le chemin d'un objet est stable, donc son URL publique aussi** — et c'est ce qui oblige
> à un horodatage. Sans le `?v=…` que `lib/stockage.js` ajoute, remplacer sa photo ne
> changerait **rien** : ni le navigateur, ni le CDN de Supabase, ni la colonne en base. Le
> paramètre périme le cache et fait changer la colonne, deux effets pour un.

> **Changer de format laisse un orphelin, et c'est traité.** Remplacer un PNG par un JPEG
> écrit `photo.jpg` **à côté** de `photo.png` : la base ne pointe plus que sur le nouveau,
> l'ancien resterait indéfiniment. `lib/stockage.js` efface les autres extensions **après**
> le dépôt — effacer d'abord laisserait quelqu'un sans photo si l'envoi échouait ensuite.
