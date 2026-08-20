# Règles métier

Ce qui ne se déduit pas du code. Toute divergence entre ce document et
l'implémentation est un bug — dans l'un ou dans l'autre.

---

## 1. Le système de points — la règle centrale

> **Les points valent la cote Unibet × 100, arrondie à l'entier.**
> Une cote de 2,80 rapporte **280 points**. Une cote de 9,50 rapporte **950 points**.

**Conséquence sur toute l'interface : on n'affiche JAMAIS une cote brute.** Nulle part on
n'écrit « ×2,80 » ou « cote 2,80 » — on écrit toujours « 280 pts ». Sans exception :
tableau des cotes, saisie, récapitulatif, résultats, profils, statistiques, calendrier.
Y compris pour une statistique comme la cote moyenne tentée, qui s'affiche « 310 » et non
« ×3,1 ».

**Rien en base ne stocke une cote.** `cotes.valeur` est déjà le nombre de points.
`lib/format.js` est le **seul** endroit qui habille un nombre de points.

Un pronostic raté rapporte **0**. Il n'y a pas de points négatifs (contrainte `check` en
base).

> Les maquettes 08 et 09 écrivent « ×2,80 » : le CLAUDE.md gagne. Des tests vérifient
> qu'aucun « ×N » ne sort des écrans.

**Une seule exception, et elle porte un autre nom.** `points_fia` sur l'écran de
résultats (25, 18, 15…) est le championnat du monde, pas des points de pronostic. Il
s'écrit « 25 pts FIA » et **jamais** via `formaterPoints`.

## 2. Structure d'un pronostic

Pour chaque Grand Prix :

- **2 obligatoires** — le vainqueur, et le podium (2 pilotes à placer)
- **3 bonus au choix**, sélectionnés **parmi ses favoris**

> **Trois bonus est un maximum, pas un quota.** Zéro, un ou deux sont acceptés : le
> joueur peut enregistrer ses obligatoires et compléter plus tard, jusqu'à la fermeture.

> **Les deux pilotes du podium n'ont AUCUN ordre entre eux.** La validation demande
> « ces deux pilotes sont-ils sur le podium ? ».
>
> **D'où : un podium réussi rapporte la SOMME des deux cotes.** Payer la seule cote de
> `pilote_1` ferait rapporter deux montants différents au même pari selon l'ordre de
> saisie. Les deux pilotes doivent être sur le podium — un seul des deux ne rapporte
> rien, ce n'est pas un demi-pronostic mais un pronostic raté.
>
> La même règle vaut partout où un podium est chiffré : total potentiel, cote moyenne
> tentée, récapitulatif.

**Le vainqueur est déjà sur le podium**, donc le bloc de saisie s'intitule
« 2e et 3e du podium » et un pilote choisi comme vainqueur **disparaît** des deux
emplacements suivants (exclusion croisée).

> **L'exclusion se compare sur le LIBELLÉ du pilote, jamais sur `id_outcome_unibet`.**
> Un même pilote ne porte pas le même identifiant d'issue selon le marché — Antonelli
> vaut `o701093319` au marché « Vainqueur » et `o701094802` au marché « Podium » du même
> GP. Un filtre par identifiant marche entre les deux emplacements du podium et
> **n'exclut jamais le vainqueur**.

> **L'exclusion est réactive et non destructive.** Changer de vainqueur rend aussitôt
> l'ancien aux listes, **sans vider les sélections déjà faites**. Une sélection devenue
> conflictuelle reste affichée et la validation la nomme.

**Le contrôle des marchés obligatoires est strict** : le vainqueur doit venir du marché
`vainqueur`, les deux pilotes du podium du marché `podium`. Un pronostic « vainqueur »
désignant en réalité une écurie serait impossible à valider, et le joueur ne le
découvrirait qu'après la course. Constantes `MARCHE_VAINQUEUR` / `MARCHE_PODIUM`,
**présentes côté backend ET côté frontend : elles doivent bouger ensemble.**

## 3. Le calendrier d'un week-end

| Moment | Ce qui se passe |
|---|---|
| **Samedi, qualifications + 2h** | Scraping Unibet. Pénalités confirmées, grille définitive. **Les cotes sont figées.** |
| Samedi soir → dimanche | Les joueurs pronostiquent librement. **Les pronostics sont visibles par les autres membres dès leur saisie.** |
| **Dimanche, départ − 5 min** | Fermeture. Plus aucune modification. |
| **Dimanche, départ + 1h30** | Job de résultats : `/session_result` toutes les 5 min, puis calcul et attribution. |

Figer les cotes après les qualifications garantit que **tous les joueurs pronostiquent
avec exactement les mêmes cotes, sur une grille déjà définitive.**

> ### La fermeture est vérifiée deux fois, et ce n'est pas une redondance
> La route refuse en `423` avant de solliciter la base ; la fonction SQL revérifie au
> moment d'écrire. Entre les deux, quelques dizaines de millisecondes — et c'est
> précisément à cinq minutes du départ que la course aux dernières secondes a lieu.
> **C'est la vérification en base qui fait foi** ; celle de la route évite un
> aller-retour et donne le message.

La marge est `MARGE_FERMETURE_MS = 5 min` (`lib/format.js`), partagée par les trois
étages.

> ### Un GP dont l'heure de départ est INCONNUE reste OUVERT
> Aux trois étages : base, backend, frontend. Refuser tout le monde parce qu'Unibet n'a
> pas annoncé l'horaire serait le mauvais sens du doute.

> ### « Cotes arrêtées » exige DEUX conditions
> Statut `cotes_figees` **et** `date_qualifications` dans le passé. Le statut seul ne
> suffit pas : un `POST /scraper/declencher` passé à la main sans `?figer=false` le pose
> n'importe quand. Le second test ne se contourne pas de la même façon — un `curl`
> avance le statut, il n'avance pas l'heure des qualifications.
>
> `cotesArretees()` vit dans `lib/calendrier.js` **et nulle part ailleurs** : trois
> surfaces portent un bouton de pronostics (accueil, calendrier de la saison, calendrier
> d'un championnat).
>
> **On se ferme sur une donnée qu'on n'a pas, jamais l'inverse.** `date_qualifications`
> absente → `false`, donc pas de bouton.

## 4. Validation des pronostics

Tous les marchés se valident **automatiquement**, sans intervention humaine.

**Via `session_result`** : vainqueur (`position == 1`), podium (`position <= 3`), top 6 et
top 10, duels, écurie gagnante, double podium d'écurie, les deux pilotes dans les points,
abandon (`dnf == true`), nombre de classés, dernier, marge de victoire, classement exact,
trio gagnant, mieux classé d'un groupe.
**Via `race_control`** : safety car, drapeau rouge.
**Via `laps`** : meilleur tour (minimum de `lap_duration`).

> ### Safety Car vs Virtual Safety Car — le seul parsing de texte du système
> Les deux remontent avec `category=SafetyCar` ; seul le `message` les distingue.
> **Deux précautions :** le test « VIRTUAL » passe **avant** celui du safety car
> ordinaire (la chaîne « SAFETY CAR » est contenue dans « VIRTUAL SAFETY CAR ») ; et
> **seuls les messages `DEPLOYED` comptent** — la séquence complète est DEPLOYED,
> IN THIS LAP, ENDING, et compter les trois ferait croire à trois interventions.
> Tout message non reconnu est journalisé.

**Premier abandon** — `session_result` ne donne pas l'heure mais donne `number_of_laps` :
l'abandonné avec le moins de tours a abandonné en premier. Gérer l'égalité.
**Volontairement NON implémenté** tant que la règle d'égalité n'est pas écrite.

**Duel avec abandon** — un pilote classé bat toujours un abandonné. Si les deux
abandonnent, celui qui a parcouru le plus de tours l'emporte.

> ### Un marché non reconnu laisse `NULL`, jamais `0`
> Les marchés Unibet varient d'un GP à l'autre : ce cas n'est pas une hypothèse d'école.
> Seuls **vainqueur, podium et ecurie-vainqueur** ont été confrontés à de vrais libellés ;
> les six autres familles sont écrites d'après cette section et **restent à vérifier**.

## 5. Championnats

- Code d'invitation : **6 caractères alphanumériques, sans séparateur** (`F1X7K2`).
- **Aucune limite** de membres.
- Un utilisateur peut appartenir à plusieurs championnats.

> **Le créateur rejoint automatiquement son championnat** — `creer_championnat` insère les
> deux lignes dans la même transaction. Sinon le championnat serait invisible de tous,
> y compris de lui, et impossible à rejoindre.

> **Le championnat survit à son créateur.** `cree_par` passe à `NULL` à la suppression du
> compte. **Conséquence assumée** : plus personne ne peut le supprimer depuis le
> frontend — un membre ordinaire n'a pas à emporter le championnat des autres.

> **Un championnat vidé de ses membres est supprimé automatiquement** (trigger). Sans
> cela il devenait un fantôme : invisible de tous, mais toujours rejoignable par son code.

**Le générateur de code écarte les caractères non conformes plutôt que de passer le jeton
en majuscules** : « a » et « A » tomberaient sur la même lettre, et les lettres
sortiraient deux fois plus souvent que les chiffres. 5 tentatives en cas de collision
(`23505`), puis échec franc.

L'adhésion en double est refusée par **la clé primaire**, pas par une lecture préalable
qui laisserait passer deux appels simultanés.

## 6. Points cloisonnés ? Non — et c'est la règle à connaître

> **Un joueur remplit UN pronostic par Grand Prix, qui compte dans TOUS ses championnats
> à la fois.**
>
> Le championnat dit **qui** classer, pas quels pronostics compter. La somme porte sur
> tous les pronostics notés du joueur.

**Conséquence sur le départ d'un championnat** : les pronostics ne sont effacés que
**lorsqu'il ne reste au joueur aucune adhésion**. Les effacer au départ d'un seul
détruirait son classement dans les autres. `quitter_championnat` porte cette règle,
atomiquement.

## 7. Départage des égalités

Dans l'ordre :

1. Le plus grand **nombre de pronostics réussis**
2. La **meilleure cote réussie** (le plus gros coup)
3. L'**ordre d'inscription** au championnat (`rejoint_le`)
4. `profil_id` — à `rejoint_le` égal, sans quoi la numérotation serait instable d'un
   appel à l'autre, **et deux membres échangeraient leurs couleurs entre deux
   rafraîchissements**

`classement_du_championnat` sert le rang de départage sous le nom **`ordre_inscription`**.

Les quatre réunis départagent **toujours** — d'où `row_number` et non `rank` sur le
classement de saison.

> **Sur le classement d'UN Grand Prix, c'est `rank`.** La règle 7 régit le classement
> général, pas une course isolée : avant le départ tout le monde est à zéro, et
> `row_number` inventerait un premier et un dernier. **Les ex æquo s'affichent comme tels.**

## 8. Grand Prix annulé ou reporté

Les pronostics enregistrés sont **effacés**. Aucun point n'est attribué. Si le GP est
reporté, les joueurs refont leurs pronostics avec de nouvelles cotes.

> **NON IMPLÉMENTÉ.** Le statut `annule` n'existe pas dans la contrainte `check`, et
> aucun code ne l'applique. Demi-pas en place : OpenF1 expose `is_cancelled`, et
> `session_de_course()` le **journalise** — le cas se verra dans les logs au lieu de
> passer pour une course sans résultat. Voir `roadmap.md`.

## 9. Statistiques d'un profil

| Champ | Calcul |
|---|---|
| `paris_gagnes_pct` | réussis ÷ pronostics **notés**, en pourcentage entier |
| `pts_moyen_gp` | somme des `points_gagnes` ÷ nombre de **GP joués** |
| `meilleur_coup` | plus fort `points_gagnes` sur un seul pronostic |
| `cote_moy_tentee` | moyenne des cotes tentées, **tous GP confondus, jugés ou non** |

Un podium compte pour la **somme** de ses deux cotes (§2). Une cote retirée par Unibet
depuis la saisie est **écartée de la moyenne, jamais comptée zéro** : le joueur n'a rien
tenté de tel.

Trois compteurs servis en plus (`pronostics_notes`, `gp_joues`, `total_points`) : ils
disent à l'interface **si la saison a commencé**. Sans eux, « meilleur coup 0 » et
« 0 % » s'afficheraient avant le premier GP, ce qui se lit comme un mauvais bilan alors
qu'il n'y a pas encore de bilan.

Un GP sans horaire n'appartient à **aucune** saison et n'entre dans aucune statistique.

> **C'est l'inverse du choix fait pour le calendrier**, où un GP sans date est servi
> quand même. La raison : **une moyenne fausse ne se voit pas, un Grand Prix manquant
> dans un calendrier se voit tout de suite.**

## 10. La voiture

Chaque utilisateur possède **une seule voiture, identique dans tous ses championnats** :
deux couleurs, un numéro libre, son nom sur l'aileron arrière. Modifiable depuis le profil.

> **`retirer_numero` est un drapeau EXPLICITE dans `PATCH /profils/moi`, et il n'est pas
> décoratif.** Les trois champs du corps étant facultatifs, `numero: null` serait
> indiscernable de « champ non transmis » : sans ce drapeau, un membre ne pourrait **plus
> jamais** revenir à l'état sans numéro une fois qu'il en a choisi un.
>
> **La comparaison des deux couleurs porte sur le couple RÉSULTANT, pas sur ce qui a été
> transmis.** N'envoyer que `couleur1`, égale à la `couleur2` déjà en base, produirait
> sinon une voiture monochrome sans que rien ne soit refusé.

> **C'est parce qu'elle est unique que le numéro ne peut pas être rendu unique par
> championnat** : le bloquer dans l'un le rendrait impossible à choisir dans un autre.
> L'avertissement est indicatif.

Chaque profil naît avec une **livrée distincte**, attribuée par ordre d'inscription
global (`livree_par_indice`, dix livrées, cyclique). Le membre l'écrase dès qu'il
personnalise.

> **Le rang est compté AVANT l'insertion** : le nouveau profil est le (N+1)ᵉ quand la
> table en compte N, donc son indice est `N % 10`. Compter après décalerait tout le monde.

## 11. Vocabulaire et voiture sur la piste

La vue piste identifie chacun par sa **livrée** et son **numéro**, et par le **pseudo
peint sur l'aileron arrière** — la légende de droite n'affiche que le score, sans aucun
libellé. C'est pour cela que les skins `matti.svg` (pastilles carrées) ne remplacent pas
les voitures : une pastille n'a nulle part où écrire le pseudo.

Voir `glossary.md` pour le vocabulaire imposé.
