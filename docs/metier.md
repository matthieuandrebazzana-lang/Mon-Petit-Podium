# Règles métier

Ce qui ne se déduit pas du code. Toute divergence entre ce document et
l'implémentation est un bug — dans l'un ou dans l'autre.

---

## 1. Le système de points — la règle centrale

> **Les points valent la cote Unibet × 10, arrondie à l'entier.**
> Une cote de 2,80 rapporte **28 points**. Une cote de 9,50 rapporte **95 points**.
>
> *Le diviseur était 100 jusqu'à la v0.44.0. Seul le multiplicateur a changé : les
> points restent des entiers, et rien d'autre de cette section n'est affecté.*

**Conséquence sur toute l'interface : on n'affiche JAMAIS une cote brute.** Nulle part on
n'écrit « ×2,80 » ou « cote 2,80 » — on écrit toujours « 28 pts ». Sans exception :
tableau des cotes, saisie, récapitulatif, résultats, profils, statistiques, calendrier.
Y compris pour une statistique comme la cote moyenne tentée, qui s'affiche « 31 » et non
« ×3,1 ».

**Rien en base ne stocke une cote.** `cotes.valeur` est déjà le nombre de points.
`lib/format.js` est le **seul** endroit qui habille un nombre de points.

Un pronostic raté rapporte **0**. Il n'y a pas de points négatifs (contrainte `check` en
base).

> Les maquettes 08 et 09 écrivent « ×2,80 » : le CLAUDE.md gagne. Des tests vérifient
> qu'aucun « ×N » ne sort des écrans.

**Une seule exception, et elle porte un autre nom.** `points_fia` sur l'écran de
résultats (25, 18, 15…) est le championnat du monde, pas des points de pronostic. Il
s'écrit « 25 pts » et **jamais** via `formaterPoints`.

> **Le mot « FIA » l'accompagnait jusqu'à la `0.63.0`, et c'est lui qui portait la
> distinction à l'écran.** Il est parti sur demande ; ne reste que le contexte, et
> l'interdiction de passer ce nombre par `formaterPoints` devient la seule moitié de la
> règle qui tienne encore. La section qui l'affiche ne montre aucun point de l'application,
> mais les deux unités cohabitent bien sur le même écran — écart signalé au CLAUDE.md.

## 2. Structure d'un pronostic

Pour chaque Grand Prix :

- **2 obligatoires** — le vainqueur, et le podium (2 pilotes à placer)
- **3 bonus au choix**, sélectionnés **parmi ses favoris**

> **Trois bonus est un maximum, pas un quota.** Zéro, un ou deux sont acceptés : le
> joueur peut enregistrer ses obligatoires et compléter plus tard, jusqu'à la fermeture.

> **Les deux pilotes du podium n'ont AUCUN ordre entre eux.** La validation demande
> « ces deux pilotes sont-ils sur le podium ? ».
>
> ### Chaque pilote est jugé pour son propre compte (v`0.54.0`)
>
> **Le podium n'est pas un pari en deux jambes solidaires : ce sont deux paris saisis
> dans le même bloc.** Un pilote qui monte sur le podium rapporte sa cote, que l'autre
> y monte ou non. Les deux, un seul, ou aucun. Un podium **entièrement** réussi rapporte
> donc la **somme** des deux cotes, qui n'est plus une règle à part mais le cas où les
> deux termes sont non nuls.
>
> *Jusqu'à la v`0.53.0`, une seule sélection fausse invalidait les deux.* Le raisonnement
> tenait — payer la seule cote de `pilote_1` ferait rapporter deux montants différents au
> même pari selon l'ordre de saisie — mais la conclusion tirée était la mauvaise sortie.
> **La bonne est de payer chaque cote à SON pilote** : c'est tout aussi
> ordre-indépendant, et cela n'aligne plus le joueur qui a vu juste à moitié sur celui
> qui s'est trompé sur les deux. Voir `bugs-connus.md` §22.
>
> **Une jambe non jugeable laisse le pronostic ENTIER à `NULL`.** La ligne ne porte qu'un
> seul `points_gagnes` et `attribuer_points` n'écrit que les `NULL` : payer la seule
> jambe connue figerait un total partiel que le rattrapage ne corrigerait plus jamais.
>
> **Le total POTENTIEL ne change pas** — il reste la somme des deux cotes, parce que
> c'est toujours le maximum atteignable. La même règle vaut partout où un podium est
> chiffré *avant* la course : total potentiel, cote moyenne tentée, récapitulatif.

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

> ### Un bonus ne reprend pas la même issue du même marché (v`0.77.0`, resserré en `0.78.0`)
> La route d'enregistrement refuse **deux cas seulement**, avec un message en français que
> le web et l'app iOS affichent tels quels :
>
> | Bonus | Refusé si son pilote est… |
> |---|---|
> | marché `vainqueur` | le vainqueur choisi |
> | marché `podium` | l'un des deux pilotes choisis au podium |
>
> Sans cette règle, un joueur se faisait payer deux fois le même événement (Pays-Bas,
> Espagne 2026 : `audit-evaluation.md` C4). La comparaison porte sur le **libellé** et non
> sur l'identifiant, pour la même raison que l'exclusion croisée : un même pilote change
> d'identifiant d'un marché à l'autre.
>
> **Les marchés ne sont plus croisés depuis la `0.78.0`.** Un bonus « Antonelli
> vainqueur » est de nouveau **accepté** pour qui a Antonelli au podium, et un bonus
> « Russell sur le podium » pour qui a Russell vainqueur : gagner et monter sur le podium
> sont deux paris distincts (Bakou 2026, `32b03d07`). Un bonus sur un autre marché
> (« Antonelli dans le top 6 ») reste libre.
>
> Les pronostics déjà payés deux fois (Pays-Bas) ne sont pas modifiés.

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
| **Dimanche, au départ** | Fermeture. Plus aucune modification. |
| **Dimanche, départ + 1h30** | Job de résultats : `/session_result` toutes les 5 min, puis calcul et attribution. Le statut passe à `termine`. |
| **Dès `termine`** | Le widget de l'accueil bascule sur le **Grand Prix suivant**. Le Grand Prix couru se consulte sur son écran de résultats. |

> ### Un Grand Prix terminé n'est plus le prochain (v`0.57.0`)
> Le Grand Prix couru gardait la place du widget d'accueil **jusqu'à minuit, heure du
> téléphone** — une lecture supplémentaire ramenait le `termine` du jour et le servait
> avant les autres. **La règle est retirée.** Elle laissait l'accueil sur un Grand Prix
> fini bien après qu'il l'était, et le défaut ne venait pas de son implémentation mais de
> son principe : **le seul état qui dise « c'est fini » est le statut, pas l'heure qu'il
> est.**
>
> Dès qu'un Grand Prix passe à `termine`, le suivant prend sa place — `a_venir` ou
> `cotes_figees`, le plus proche. Il n'y a donc plus de fenêtre pendant laquelle l'accueil
> annonce une course déjà courue, et plus rien à coudre entre deux règles :
> `chargerProchainGp` n'en porte plus qu'une.
>
> **Rien ne change entre l'arrivée et le passage à `termine`** : le Grand Prix est encore
> `cotes_figees`, donc il reste servi comme le plus proche à venir, avec un compte à
> rebours à zéro et des pronostics fermés — ce qui est exact.

> ### Le compte à rebours a DEUX échéances, pas une (v`0.57.0`)
> Il annonçait toujours « Fermeture dans », y compris sur un Grand Prix dont les
> pronostics n'étaient pas encore ouverts : il annonçait la fermeture d'une chose qui
> n'avait pas commencé, et promettait treize jours pour agir là où il n'y avait rien à
> faire.
>
> | Phase | Échéance décomptée | Ce qui est écrit |
> |---|---|---|
> | Avant le relevé des cotes | `date_qualifications` + 2h | « Ouverture dans » |
> | Pronostics ouverts | `date_course` | « Fermeture dans » |
> | Après la fermeture | — | « Pronostics / Fermés » |
>
> **C'est `cotesArretees` qui départage les deux phases, jamais le statut brut**, et c'est
> ce qui fait tenir l'ensemble : le bouton de pronostics du bloc d'accueil s'affiche sur
> exactement la même condition. Les deux ne peuvent donc pas se contredire — une case
> « Fermeture dans » au-dessus d'un bloc **sans bouton** serait un décompte vers une
> fermeture que rien n'ouvrira.
>
> **« Pas encore ouverts » exige les trois à la fois** : cotes non arrêtées, heure de
> fermeture pas encore passée, et Grand Prix non `termine`. Le premier test suffit un
> samedi matin ; il ne suffit pas le dimanche soir, où un Grand Prix couru le passe aussi —
> et l'écran de saisie aurait déverrouillé son formulaire sur une course déjà courue.
>
> **Les deux heures après les qualifications sont une PRÉVISION, pas une garantie**
> (`DELAI_OUVERTURE_MS`, `lib/format.js`) : c'est le délai du job du samedi, qui peut
> prendre du retard. Le décompte se tait dès que l'heure prévue est passée sans que le
> statut ait bougé — « Ouverture / À confirmer ». Mieux vaut ne plus rien promettre que
> promettre une ouverture déjà en retard.
>
> Une seule source, `etatPronostics` (`lib/calendrier.js`), pour les **quatre** surfaces
> qui portent un décompte : les deux cases du bloc d'accueil, l'horloge de l'écran de
> saisie, celle du récapitulatif. Le titre, la phrase et le mot de remplacement en
> viennent tous — l'horloge ne décide plus de ce qu'elle annonce.

Figer les cotes après les qualifications garantit que **tous les joueurs pronostiquent
avec exactement les mêmes cotes, sur une grille déjà définitive.**

> ### Les pronostics se ferment au moment du départ de la course (v`0.72.0`)
> Le seuil est `date_course`, sans marge d'avance. **Une marge de cinq minutes tenait ce
> rôle jusqu'à la `0.71.0`** — `MARGE_FERMETURE_MS` dans `lib/format.js`,
> `MARGE_FERMETURE` dans la route, `interval '5 minutes'` dans la fonction SQL. Les trois
> sont retirées ensemble : c'est une seule règle à trois étages, et un étage laissé en
> arrière aurait ouvert le formulaire sur une écriture que la base refuse.

> ### La fermeture est vérifiée deux fois, et ce n'est pas une redondance
> La route refuse en `423` avant de solliciter la base ; la fonction SQL revérifie au
> moment d'écrire. Entre les deux, quelques dizaines de millisecondes — et c'est
> précisément dans les dernières secondes avant le départ que la course aux derniers
> pronostics a lieu. **C'est la vérification en base qui fait foi** ; celle de la route
> évite un aller-retour et donne le message.

Le seuil est `date_course` lui-même, lu par `instantFermeture` (`lib/format.js`) côté
frontend, et partagé par les trois étages. **Aucune constante ne porte plus de marge** :
laissée en place sans emploi, elle aurait été une seconde réponse à la question « quand
est-ce que ça ferme ? ».

> ### Un GP dont l'heure de départ est INCONNUE reste OUVERT
> Aux trois étages : base, backend, frontend. Refuser tout le monde parce qu'Unibet n'a
> pas annoncé l'horaire serait le mauvais sens du doute.

> ### « Cotes arrêtées » exige DEUX conditions
> Statut `cotes_figees` **et** fermeture pas encore passée — `date_course` devant nous.
> Rien d'autre, et surtout pas `date_qualifications` (v`0.65.0`).
>
> Le statut n'est pas une supposition : `jobs/scraper.py` ne le pose qu'après un scraping
> dont **au moins une cote a été écrite**. Il y a donc quelque chose à pronostiquer, ce qui
> est toute la question que pose ce test.
>
> `cotesArretees()` vit dans `lib/calendrier.js` **et nulle part ailleurs** : quatre
> surfaces portent un bouton de pronostics (accueil, calendrier de la saison, calendrier
> d'un championnat, fiche d'un Grand Prix).
>
> **Un Grand Prix dont l'heure de départ est inconnue reste OUVERT**, comme aux trois
> étages ci-dessus : `date_course` absente → pas de fermeture à opposer.
>
> ### Ce que la règle exigeait en plus, et pourquoi elle ne l'exige plus
>
> La version `0.38.0` demandait une `date_qualifications` **datée et passée**, contre un
> `POST /scraper/declencher` lancé un mardi : un `curl` avance le statut, il n'avance pas
> l'heure des qualifications. Le raisonnement tenait, la donnée non. Depuis le retrait du
> repli `date_course − 22h` (v`0.57.0`), cette heure ne vient plus que de la migration 20
> ou du programme d'Unibet — **et Unibet n'expose aucun événement de qualification** dans
> le régime constaté sur le terrain (`scraper.md` §5). Toute ligne née du scraper était
> donc sans heure, et **sans bouton de pronostics sur les quatre surfaces à la fois**,
> sans un mot à l'écran.
>
> **« On se ferme sur une donnée qu'on n'a pas » vaut quand la donnée absente est celle
> qui AUTORISE.** Ici elle était celle qui interdisait, et son absence était le régime
> normal : la garde ne protégeait plus à la marge, elle fermait l'application. Le cas
> qu'elle visait se traite là où il naît — `?figer=false` au scraper, explicite et
> documenté. Voir `bugs-connus.md` §30.

## 4. Validation des pronostics

Tous les marchés se valident **automatiquement**, sans intervention humaine.

**Via `session_result`** : vainqueur (`position == 1`), podium (`position <= 3`), top 6 et
top 10, **les 2 voitures d'une écurie dans le top 10**, duels, écurie gagnante, double
podium d'écurie, les deux pilotes dans les points, abandon (`dnf == true`), nombre de
classés, dernier, **écart du gagnant**, classement exact, trio gagnant, mieux classé d'un
groupe.

> ### L'écart du gagnant — le seul marché dont l'issue est un intervalle
> Tous les autres marchés proposent un pilote, une écurie, ou un oui/non. Celui-ci propose
> **une plage de secondes** (« moins de 5 », « 5 - 10 », « plus de 10 »), et se juge sur
> `gap_to_leader` **de la ligne du DEUXIÈME** — le champ dit « de combien ce pilote est
> derrière le leader », donc il vaut `null` sur la ligne du leader, ce qui est correct.
>
> Les bornes sont **`[bas, haut[`** : les issues forment une partition, et deux bornes
> inclusives feraient gagner *deux* paris à un écart de très exactement 5,000 s.
>
> Implémenté en v`0.54.0`. Il ne l'était pas, et ce n'était pas une comparaison qui
> échouait : le champ n'était lu nulle part et le marché n'était pas reconnu — voir
> `bugs-connus.md` §23.
> ### La nationalité du vainqueur ne se lit PAS dans les résultats
> C'est le second marché dont l'issue n'est ni un pilote, ni une écurie, ni un oui/non :
> elle nomme **un peuple ou un pays**. Et la donnée n'est nulle part dans `session_result` :
> `country_code` de `/drivers` est **déprécié et disparaît fin 2026**. La nationalité vient
> donc d'une **table statique**, `app/calcul/pilotes.py`, sous le même garde-fou de saison
> que les alias — numéro **et** nom de famille doivent concorder, sans quoi rien n'est rendu
> et le pronostic reste non jugé. **À mettre à jour à chaque saison**, comme la grille.
>
> Les deux formes sont acceptées (« Néerlandais » et « Pays-Bas »), rien ne disant laquelle
> Unibet écrit. **Aucune n'a été confrontée à un vrai marché** : une issue inconnue est
> journalisée en toutes lettres et laisse `NULL`. Implémenté en v`0.55.0`.
>
> ### « Autres » se juge contre les issues sœurs, jamais seule (v`0.56.0`)
>
> Toutes les autres issues du système se jugent **seules** : « Néerlandais » est vrai ou
> faux sans qu'on sache ce que le marché proposait à côté. **« Autres » n'est pas une
> valeur, c'est un complémentaire** — « une nationalité qu'Unibet n'a pas listée ce
> jour-là » — et la liste change à chaque Grand Prix.
>
> Elle se juge donc contre **les libellés des autres issues du même marché et du même GP**,
> lus dans les cotes déjà en base. Réussie si la nationalité du vainqueur n'est dans aucune,
> ratée si elle est dans l'une. Rien n'est écrit en dur : la règle vaut pour tous les Grands
> Prix à venir.
>
> **Une option sœur illisible ne fait pas gagner « Autres »** — elle pourrait être celle du
> vainqueur, et conclure « pas listée » sur une liste à moitié lue inventerait un gain. Elle
> ne l'empêche pas de **perdre** : si la nationalité du vainqueur figure parmi les options
> comprises, le verdict est acquis. Détail dans `bugs-connus.md` §25.

> ### « Les 2 voitures dans le top 10 » — une famille de marchés, un par écurie
> Le slug porte **le sujet du pari** : `ferrari-les-2-voitures-dans-le-top-10` nomme
> l'écurie *et* le rang, là où tous les autres marchés se nomment d'un slug fixe et
> laissent l'issue désigner le sujet. L'issue, elle, n'est qu'un « Oui » ou un « Non ».
> Les deux sont exactement complémentaires — « Oui » si les deux voitures sont classées au
> rang demandé ou mieux, « Non » dans tous les autres cas — et se jugent donc d'une seule
> comparaison. Onze marchés au GP Italie 2026, six au GP Espagne : c'est le tiers des
> marchés d'un Grand Prix.
>
> **La paire de pilotes se lit dans les résultats, jamais dans la grille statique.** Les
> baquets bougent en cours de saison et `calcul/pilotes.py` ne le sait pas : au GP
> d'Espagne, la grille aurait opposé Hadjar à Red Bull là où Lawson y a fini sixième, et
> répondu « Non » à un marché que la course gagne. Un pronostic déclaré raté vaut `0`, qui
> **ne se rattrape jamais** — l'erreur aurait été définitive. `Course.voitures_de` compte
> donc les voitures de l'écurie **parmi les pilotes ayant une ligne de classement**, et
> laisse le pronostic non jugé si elles ne sont pas exactement deux.
>
> Le nom d'écurie du slug se rapproche par la même inclusion que « écurie vainqueur », qui
> couvre les onze variantes d'Unibet sans qu'aucune soit écrite en dur. Implémenté en
> v`0.73.0` ; détail et commandes de rattrapage dans `bugs-connus.md` §34.

**Via `race_control`** : safety car, drapeau rouge.
**Via `laps`** : meilleur tour (minimum de `lap_duration`).
**Via les qualifications** (`donnees_brutes.qualification`) : pole position.

> ### Les marchés ajoutés en v`0.77.0`
>
> | Marché | Règle |
> |---|---|
> | **Marge du vainqueur** | même marché que l'écart du gagnant, renommé par Unibet : même règle |
> | **Tour le plus rapide** (pilote) | le pilote du meilleur tour |
> | **Écurie / voiture réalisant le tour le plus rapide** | l'écurie de ce pilote ; « voiture » accepte un pilote ou une écurie |
> | **Vainqueur course, qualification et tour le plus rapide** | « Oui » si un même pilote signe la pole, la victoire et le meilleur tour. Sans qualifications, en attente |
> | **Les 2 voitures sur le podium** | l'écurie désignée place ses deux voitures dans le top 3 |
> | **Face-à-face** | voir « Duel » plus bas |
> | **Écurie qui marque le plus de points** | somme des points FIA de chaque écurie ; égalité → partage |
>
> ### L'égalité se paie à partage (règle des bookmakers)
> Quand plusieurs écuries finissent à égalité en tête, l'issue de chacune est **gagnante
> à partage** : ses points sont divisés par le nombre d'écuries ex æquo, **arrondis à
> l'entier** (un demi vers le haut). Aux Pays-Bas 2026, McLaren et Mercedes finissent à
> 33 points : « Mercedes » à 30 pts aurait rapporté 15, « McLaren » à 20 pts, 10.
>
> *Jusqu'à la `0.77.0`, ce marché était jugé « écurie du vainqueur »* : son slug commençait
> par `ecurie`. Les verdicts écrits étaient justes par coïncidence (`audit-evaluation.md` C3).

> ### Safety Car vs Virtual Safety Car — le seul parsing de texte du système
> Les deux remontent avec `category=SafetyCar` ; seul le `message` les distingue.
> **Trois précautions :** le test du VSC passe **avant** celui du safety car
> ordinaire (la chaîne « SAFETY CAR » est contenue dans « VIRTUAL SAFETY CAR ») ;
> **seuls les messages `DEPLOYED` comptent** — la séquence complète est DEPLOYED,
> IN THIS LAP, ENDING, et compter les trois ferait croire à trois interventions ; et
> **OpenF1 écrit le VSC en abrégé**, `VSC DEPLOYED` / `VSC ENDING`. Les deux formes sont
> reconnues depuis la `0.77.0` — avant, le VSC n'était jamais détecté (audit C6).
> Tout message non reconnu est journalisé.

**Premier abandon** — `session_result` ne donne pas l'heure mais donne `number_of_laps` :
l'abandonné avec le moins de tours a abandonné en premier. Gérer l'égalité.
**Volontairement NON implémenté** tant que la règle d'égalité n'est pas écrite.

**Duel (face-à-face)** — le pilote le mieux classé gagne. Si un seul des deux est classé,
il gagne. Si aucun ne l'est, celui qui a bouclé le plus de tours gagne ; **à tours égaux,
les deux issues gagnent à partage** : la cote est divisée par deux, avec le même arrondi
que l'égalité entre écuries (entier le plus proche, demi vers le haut : 25 → 13), depuis
la `0.78.0`. Deux pilotes tous deux absents du classement ne sont pas une égalité mais
une donnée manquante : le pronostic reste en attente. « Classé » veut dire une position au
classement : un pilote peut abandonner et rester classé. Les deux adversaires se lisent
dans les **deux issues du marché**, le slug ne se découpant pas sûrement en deux noms.

> ### Un marché se désigne par son slug exact, jamais par un morceau (v`0.77.0`)
> Chaque marché évaluable est inscrit dans un **registre** (`calcul/points.py`) : slug
> exact, ou famille déclarée en entier (`top-N`, `{écurie}-les-2-voitures-dans-le-top-N`,
> `face-a-face-{a}-{b}`). Un slug que le registre ne connaît pas **n'est jugé par aucun
> évaluateur voisin**. La reconnaissance par préfixe ou sous-chaîne est retirée : elle
> laissait passer les marchés renommés et jugeait « l'écurie qui marque le plus de
> points » comme « l'écurie du vainqueur ».
>
> **Le même registre filtre le scraping** : un marché non évaluable n'est plus enregistré,
> donc plus jamais proposé aux joueurs (`scraper.md` §7).

> ### Quatre statuts, et `NULL` ≠ `0` tient toujours
> Chaque pronostic porte un `statut_evaluation` distinct de `points_gagnes`
> (`database.md`, migration 24) :
>
> | Statut | `points_gagnes` | Sens |
> |---|---|---|
> | `en_attente` | `NULL` | une donnée manque (pilote non rapproché, qualifications absentes…) — rattrapable au prochain passage |
> | `non_evaluable` | `NULL` | aucun évaluateur pour ce marché — rattrapable par une livraison de code |
> | `gagne` | `> 0` | réussi, y compris à partage |
> | `perdu` | `0` | raté |
>
> Un marché qu'on ne sait pas juger ne vaut **jamais** `0`. Ce qui change : il ne faut
> plus relire les logs pour distinguer « pas encore » de « jamais ». **Relire quand même
> les avertissements `[points]` après chaque Grand Prix** — c'est ce filet qui a caché
> l'écart du gagnant pendant six versions.

> ### Le filet ne protège que ce qu'il n'a pas jugé
> `NULL` se rattrape ; `0` **ne se rattrape pas**. `attribuer_points` ne réécrit que les
> `NULL`, si bien qu'un validateur corrigé après coup rattrape les marchés qu'il ne
> reconnaissait pas — et **jamais** ceux qu'il jugeait mal. Un demi-podium noté `0` par
> l'ancienne règle est resté `0` après la `0.54.0` : le correctif était juste, la valeur
> était figée (`bugs-connus.md` §24).
>
> C'est la règle du **calcul provisoire** seulement. Le **définitif** (ci-dessous) et le
> recalcul admin réécrivent tout le GP.

### Résultats provisoires, puis définitifs à J+1 (v`0.78.0`)

Le classement publié à l'arrivée précède les décisions des commissaires : à Bakou 2026,
Bortoleto est 13ᵉ à l'arrivée, **15ᵉ** après une pénalité de 10 s. Un GP passe donc par
deux calculs, et son état est `grands_prix.statut_resultats` :

| Étape | Quand | Ce qui est écrit | Statut |
|---|---|---|---|
| **Provisoire** | publication du classement (départ + 1h30 au plus tôt) | les verdicts des pronostics encore à `NULL` | `provisoire` |
| **Définitif** | **24 h après `date_course`** | OpenF1 relue (classement, tours, direction de course, qualifications), `resultats_gp` remplacé, **tous** les verdicts du GP recalculés, y compris ceux déjà écrits, **dans une seule transaction** | `definitif` |

- **Les points provisoires comptent immédiatement, partout** : classements, piste,
  résultats, calendrier, historique. Ils peuvent bouger une fois, au définitif.
- Les écrans portent une mention discrète « **Provisoire** » sur les résultats d'un GP
  provisoire (widget d'accueil, résultats du GP, résultats par Grand Prix, « Mes / Ses
  Grands Prix ») et sur le classement d'un championnat **tant que le dernier GP couru est
  provisoire**.
- 24 h et non « le lundi » : Bakou 2026 se court un samedi.
- **Après le définitif, plus aucun recalcul automatique.** Défaire un verdict définitif
  demande une décision explicite : `POST /jobs/resultats/{gp_id}/recalcul` (secret
  d'admin), avec la même écriture transactionnelle. Elle remplace `?forcer=true`, dont la
  remise à `NULL` puis la réécriture en deux appels pouvaient laisser tout un GP « en
  attente » (risque R5 de l'audit).
- Un pronostic `non_evaluable` s'affiche comme tel (tiret, « Non évaluable »), jamais
  comme « en attente ».

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
deux couleurs, une **couleur de texte**, un numéro libre, son nom sur l'aileron arrière.
Modifiable depuis le profil.

> ### Le numéro se lit du DESSUS, pas de l'avant (version `0.53.0`)
>
> La planche l'écrivait sous `rotate(180)` — la convention d'un vrai museau de Formule 1,
> qui se lit depuis la voiture qu'on double. **Toutes les vues de l'app sont des vues de
> dessus** : le numéro y sortait tête-bêche, sur les douze livrées.
>
> Retirer la rotation ne suffisait pas : elle renversait aussi la position des glyphes
> autour de leur ligne de base. Celle-ci descend donc d'exactement une **hauteur de
> capitale** (0,717 em), ce qui fait retrouver au numéro le pixel qu'il occupait. Calculé,
> jamais relevé à l'œil : douze `yNumero` mesurés séparément auraient demandé douze
> corrections, et la première retouchée aurait démenti les onze autres.

> ### `couleur_texte` — `NULL` veut dire « pas de choix », jamais « pas de couleur »
>
> Elle peint **le numéro du museau et le pseudo de l'aileron**, les deux ensemble : c'est
> une seule décision du membre. Sans choix, chaque texte reprend l'**encre calculée** qui
> contraste avec l'aplat qui lui est propre — et les deux aplats diffèrent sur neuf des
> onze livrées d'écurie.
>
> C'est pourquoi la migration 18 ne remplit pas rétroactivement la colonne : un `#FFFFFF`
> posé d'office aurait rendu le numéro invisible pour tout membre à coque blanche, argent,
> beige ou jaune. **Le défaut de colonne ne vaut que pour les profils créés après elle**,
> qui naissent avec la coque bordeaux, où le blanc tient 10,88:1.
>
> **La couleur ne part au serveur que si elle a été CHOISIE.** La saisie du profil porte
> toujours une couleur — à défaut l'encre calculée — donc l'envoyer inconditionnellement
> figerait cette encre en base au premier enregistrement, y compris quand le membre n'a fait
> que repeindre sa coque : il repartirait avec un numéro blanc sur une coque devenue
> blanche, sans avoir rien demandé. Tant qu'aucun choix n'est fait, la colonne reste `NULL`
> et l'encre continue de suivre l'aplat.
>
> **Le contraste se mesure et se signale, il ne se refuse pas.** L'écran de profil compare
> la couleur choisie à l'aplat du museau de la livrée en cours et le dit sous les 3:1 d'un
> grand texte porteur de sens. Il ne bloque pas l'enregistrement : la voiture appartient au
> membre, et la base ne peut pas trancher la question sans connaître la livrée active.

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
