# Bugs connus et résolus

Un bug par section : **symptôme**, **cause réelle**, **correctif**, **ce qu'il ne faut pas
refaire**.

> **Ce document contient surtout des bugs RÉSOLUS**, et c'est délibéré : ceux dont la cause
> n'était pas celle qu'on croyait sont les plus coûteux à redécouvrir. Les défauts encore
> ouverts sont marqués **⚠️ OUVERT**.

---

## 1. `position: relative` bat `sticky` par ordre d'émission dans `@layer utilities`

**Symptôme.** Sur le tableau des cotes, l'en-tête « ECURIE VAINQUEUR » recouvrait Ferrari
et Mercedes **dès le chargement**, sans qu'on ait défilé.

**Cause réelle.** Un `sticky` non défilé ne recouvre rien : il reste dans le flux. Le
défaut était ailleurs. L'en-tête portait
`section-collante rounded-carte shadow-carte relative`. Les deux classes de position ont
**la même spécificité (0,1,0)** et vivent dans la **même couche** `utilities` : c'est donc
**l'ordre d'émission dans la feuille compilée** qui tranche, jamais l'ordre écrit dans
l'attribut `class`.

Vérifié sur le CSS de production : `.section-collante` était émis à l'octet 10216,
`.relative` à 10482. **`position: relative` gagnait.**

Et un élément *relatif* n'ignore pas son `top` — **il s'en décale**. L'en-tête était donc
poussé vers le bas de `--entete-hauteur`, soit **~107 px** sur un iPhone à encoche : pile
la hauteur de la première rangée de widgets, qu'il venait recouvrir en permanence. Le
`z-index: 20` s'appliquait normalement, d'où un recouvrement franc.

**Correctif, en deux temps.** `relative` retiré du JSX (redondant : `sticky` établit déjà
le bloc conteneur) **et** `.section-collante` sortie de `@utility` pour devenir une règle
**hors de toute couche** — elle l'emporte alors sur toutes les règles empilées.

**Ne pas refaire.** Le second point seul aurait réparé l'écran jusqu'à ce que quelqu'un
remette `relative`. **Devant un comportement de mise en page inexplicable, regarder le CSS
compilé** (`grep -o '\.ma-classe{[^}]*}' dist/assets/*.css`), pas le JSX.

---

## 2. `gap` inerte sous `display: block` hors couche Tailwind

**Symptôme.** Les douze cartes de l'onglet Calendrier se touchaient. Plus tard : les cartes
de championnat collées à « Créer un championnat » sur l'accueil.

**Cause réelle.** Le `gap-3` était **bien écrit** — et c'est précisément ce qui rendait le
défaut illisible : **la classe était là, elle ne s'appliquait pas.**

`.t-stagger-line` pose `display: block`, déclaré **hors de toute couche Tailwind**. Une
règle non affectée à une couche l'emporte sur **toutes** les règles empilées, quelle que
soit leur spécificité : `.flex` vit dans `@layer utilities`, elle perd. Le `<Bloc>` restait
en `display: block`, **où `gap` n'a aucun effet**.

**Correctif.** Le conteneur flex passe **à l'intérieur** du bloc. **Rien n'est touché à
`index.css`** : déplacer `.t-stagger-line` dans une couche changerait la précédence de
toutes les transitions de l'app d'un coup, pour réparer une gouttière.

**Ne pas refaire.** **Jamais de `flex`, `gap` ou `justify-*` sur un `<Bloc>`.** Trois
occurrences ont été corrigées (accueil, liste des championnats, championnat). La même
mécanique vaut pour `.t-skel-bar`, qui peint sa couleur hors couche — d'où le style **en
ligne** obligatoire pour la battre.

**Variante attrapée par un aperçu rendu** : la même cause avait laissé l'**icône du logo
calée à gauche** sur la page publique. Le `flex flex-col items-center` était bien écrit, sur
un `Bloc`.

---

## 3. `viewBox` prescrites fausses — cinq fois

**Symptôme.** Dessins décentrés, rognés, ou flottant dans du vide.

**Cause réelle.** Les tranches arithmétiques d'une planche supposent que les dessins sont
jointifs, de même taille et régulièrement espacés. **Ils ne le sont jamais.**

| Planche | Prescrit | Réel |
|---|---|---|
| `flags.svg` | 6 tranches de 463 | hauteurs de 305 à 417, non jointives |
| `logo.svg` | `0 0 133.55 120` / `0 121 …` | 2ᵉ logo à y=154,50, 38 unités de vide horizontal |
| `matti.svg` | 4179,74 / 11 = 379,98 | 124 unités de vide sous chaque tuile |
| `VOITUREs_am.svg` | moitiés (0–391, 391–782) | 29,39–317,48 et 459,01–747,10 |
| `voiture.svg` | — | ~2× la largeur du dessin en marge vide |

**Correctif.** **Les vraies boîtes englobantes**, mesurées en échantillonnant les courbes
de Bézier. **Aucune coordonnée n'est réécrite : c'est le cadrage qui bouge.**

**Ne pas refaire.** **Toujours mesurer, jamais diviser.** Et **ne pas serrer chaque
cadrage indépendamment** quand les dessins vivent dans le même système de coordonnées :
leurs tailles relatives sont voulues. Les icônes de la barre partagent un carré de 74
unités **centré sur chaque boîte** — les serrer les ramènerait toutes à la même taille
apparente.

*Effet de bord du dernier cas* : la `viewBox` de `voiture.svg` portait tant de vide qu'à
hauteur CSS égale la nouvelle voiture paraissait plus grande. **Deux appelants ont dû être
ajustés** (vue piste 56×68 → 29×59, résultats `w-[28px]` → `w-[17px]`).

---

## 4. Double conversion UTC de `date_course` — deux heures d'avance

**Symptôme.** Le widget de l'accueil annonçait 13 h pour un départ à 15 h.

**Cause réelle.** Le champ `start` d'Unibet est **déjà en UTC**. Le scraper le lisait
**comme de l'heure de Paris**, le convertissait une seconde fois, et enregistrait deux
heures trop tôt. La conclusion contraire, posée à l'étape 4, était **fausse** — OpenF1,
source autorisée en UTC, concorde à la minute près sur les quatre séances du week-end.

> **Ce n'était PAS un défaut d'affichage.** `date_course` gouverne la fermeture des
> pronostics (départ − 5 min) et le job de résultats (départ + 1h30, fenêtre 3 h). Avec
> deux heures d'avance, les pronostics se fermaient à 12h55 pour une course à 15h00, et le
> job interrogeait OpenF1 de 12h30 à 15h30 — **il épuisait sa fenêtre pendant que la course
> se courait.**

**Correctif.** `FUSEAU_UNIBET = ZoneInfo("UTC")`, avec le relevé des quatre séances en
commentaire.

**Ne pas refaire.** **Deux commentaires PÉRIMÉS annoncent encore la conversion depuis
Paris** : celui de la migration 3 (`grands_prix.date_course`) et celui de `tzdata` dans
`requirements.txt`. Les migrations sont historiques et ne sont pas réécrites — **s'y fier
referait le bug**. La vérité est dans `app/scraper/unibet.py` et dans `scraper.md` §4.

⚠️ **La ligne du GP des Pays-Bas est encore fausse en base** — voir §11.

---

## 5. `chargerProchainGp` filtrait sur `a_venir` seul

**Symptôme.** Dès que le job du samedi figeait les cotes, l'accueil annonçait le GP de la
semaine **précédente** — « Dernier GP », bouton « Voir les résultats » — **pendant tout le
week-end de course**, c'est-à-dire précisément quand il faut pronostiquer.

**Cause réelle.** La lecture filtrait `.eq("statut", "a_venir")`. Un GP figé quitte cette
liste : la lecture ne trouvait plus rien et `chargerAccueilGp` retombait sur
`chargerDernierGpCouru`.

**Correctif.** Retenir les **deux statuts non courus**, `a_venir` **et** `cotes_figees` —
le filtre qu'appliquaient déjà `GET /championnats/moi` et `chargerGrandsPrixRestants`.

**Ne pas refaire.** Le défaut a été découvert en voulant conditionner le bouton à
`cotes_figees` : dans un bloc qui ne pouvait afficher que des GP `a_venir`, la condition
aurait donné du **code mort**. **Trois lectures doivent dire la même chose** sur les
statuts non courus.

---

## 6. Les modèles Pydantic filtraient `livree_mode` et `livree_ecurie`

**Symptôme.** Aucun skin d'écurie ne s'affichait — ni sur la piste, ni au classement, ni
au tableau des résultats.

**Cause réelle.** La migration 12 faisait bien servir les deux colonnes par
`classement_du_championnat` et `pronostics_du_championnat`, et `livreeDuMembre` savait les
lire. **Entre les deux, les modèles Pydantic ne les déclaraient pas.** Le `response_model`
de FastAPI **ne laisse passer que les champs du modèle** : les colonnes étaient filtrées
**avant d'atteindre le client**. `livreeDuMembre` retombait sur `perso`, son repli
volontaire, et **aucun skin n'a jamais pu s'afficher.**

**Correctif.** Champs ajoutés à `LigneClassement` et au modèle des membres, **avec des
valeurs par défaut** — sinon un backend déployé avant la migration rendrait **toute** la
réponse en `500`.

**Ne pas refaire.** **Une colonne ajoutée en base ne suffit pas** : la chaîne complète est
`migration → fonction SQL → COLONNES_* → modèle Pydantic → frontend`. Le maillon Pydantic
échoue **silencieusement**. Même piège : `is_admin` (traité au moment de l'ajout).

*Effet de bord* : les lignes déjà en `localStorage` avaient été écrites par le backend qui
filtrait. La clé de cache a dû être **versionnée** (`classement:{profil}:v2:{championnat}`),
le marqueur placé **après** l'identifiant du compte pour que `oublierCachePrefixe`
continue de tout balayer.

---

## 7. Transition sur `transform` alors que Tailwind 4 compile vers `translate`

**Symptôme.** Aucun — **et c'est le pire**. Le pouce de l'interrupteur aurait sauté d'un
bout à l'autre de sa piste, **et le JSX aurait eu exactement la même tête.**

**Cause réelle.** La règle transitionnait `transform`. Or **Tailwind 4 compile
`translate-x-*` vers la propriété indépendante `translate`** :
`.translate-x-\[18px\]{--tw-translate-x:18px;translate:var(--tw-translate-x) var(--tw-translate-y)}`.
La transition ne portait donc **sur rien du tout**.

**Correctif.** Transitionner `translate`. Les deux propriétés se composent aussi bien sur
le GPU — c'est le **nom** qui devait suivre l'utilitaire.

**Ne pas refaire.** Un test **lit la règle de l'utilitaire dans le CSS compilé**, en extrait
la propriété réellement écrite, et vérifie que c'est bien celle qui est transitionnée.
Éprouvé dans les deux sens.

---

## 8. `setDonnees` n'écrit pas le cache — les couleurs qui réapparaissent

**Symptôme.** Enregistrer une couleur la posait sur la vue piste, mais **revenir sur le
profil ressortait l'ancienne**.

**Cause réelle — DEUX causes, et les corriger toutes les deux était nécessaire.**

1. **`setDonnees` ne touche que l'état React.** `useDonnees` relit le `localStorage` **au
   montage**, dans l'initialiseur de `useState` : le cache gardait la version d'avant, et
   c'est **lui** qui était servi au retour.
2. **L'état de saisie ne suivait jamais le serveur.** L'effet s'écrivait
   `setCouleur1((actuelle) => actuelle ?? profil.couleur1)` : il n'initialisait qu'une
   fois. Le garde-fou était voulu — sans lui, la revalidation effacerait une couleur en
   cours de choix — mais il **figeait aussi la valeur périmée du cache définitivement**.

**Correctif.** `remplacer(valeur)` ajouté à `useDonnees` (état **et** cache). Un drapeau
`edite` remplace le `??` : tant que le membre n'a rien touché, la saisie suit le profil
servi ; dès qu'il touche à quelque chose, elle se fige.

**Ne pas refaire.** **`setDonnees` ne sert qu'aux mises à jour optimistes que la réponse
serveur confirmera de toute façon.** Toute écriture durable passe par `remplacer`.

*Troisième défaut trouvé en rendant l'écran avec la feuille compilée* : le numéro était lu
dans `saisie` et non dans le repli `saisie ?? saisieDepuis(profil)`. **Tout ce que l'écran
lit passe désormais par `voiture`, jamais par `saisie`.**

---

## 9. Le pseudo de l'accueil venait du jeton, pas de la base

**Symptôme.** Renommer quelqu'un dans `public.profils` ne changeait rien à l'écran, quel
que soit le nombre de rechargements.

**Cause réelle.** `useAuth().pseudo` lit `user_metadata.pseudo`, **une copie déposée à
l'inscription** qui vit dans le jeton. Elle n'est réécrite que par `auth.updateUser` : un
`update` SQL ou un trigger la laissent intacte. **Et une session Supabase se rafraîchit
indéfiniment.**

**Correctif.** `chargerIdentite` + `useIdentiteCourante` (nommés `chargerPseudo` et
`usePseudoCourant` jusqu'à la version `0.52.0`), qui lisent la base **à chaque montage**,
**sans cache**, avec **repli sur le jeton**.

**Ne pas refaire.** `AuthContexte.jsx` documente désormais que son `pseudo` est une copie
figée. Le défaut était borné à l'accueil — vérifié : `pseudo` n'est déstructuré de
`useAuth()` **qu'à un seul endroit**.

---

## 10. Exclusion croisée filtrée par `id_outcome_unibet`

**Symptôme.** Un pilote choisi comme vainqueur restait proposé aux emplacements du podium.

**Cause réelle.** Le filtre portait sur `id_outcome_unibet`. **Un même pilote ne porte pas
le même identifiant selon le marché** — Antonelli vaut `o701093319` au marché « Vainqueur »
et `o701094802` au marché « Podium » du **même GP**. Le filtre marchait entre les deux
emplacements du podium (tirés du même marché), et **n'excluait donc jamais le vainqueur** :
il donnait l'illusion de fonctionner.

**Correctif.** Comparer sur le **libellé** normalisé (`clePilote`).

**Ne pas refaire.** **`id_outcome_unibet` n'identifie jamais une personne, seulement une
issue.** Un test démontre qu'un filtre par identifiant laisse les trois pilotes.

---

## 11. ⚠️ OUVERT — GP des Pays-Bas figé prématurément, et sa date fausse

**Symptôme.** `statut = 'cotes_figees'` sur `33b835cc-5c17-40f7-a41f-3e95fc14885a` alors
que les qualifications sont annoncées au **22 août 2026 à 12h00 UTC** — le job ne se
déclenche qu'à qualifs + 2 h.

**Cause réelle.** Un `POST /scraper/declencher` passé à la main **sans `?figer=false`**.
C'est le piège que le paramètre a précisément été créé pour éviter. `date_course` est
fausse en plus (§4).

**Correctif du symptôme visible : déjà fait.** Les trois surfaces exigent désormais
`cotesArretees` (statut **et** qualifications passées) : aucun bouton ne s'affiche avant
l'heure.

**La DONNÉE reste à corriger.** Le job du samedi ne la refigera pas — il ne traite que les
GP en `a_venir` :

```sql
update public.grands_prix set statut = 'a_venir'
 where id = '33b835cc-5c17-40f7-a41f-3e95fc14885a' and statut = 'cotes_figees';
```

Puis `POST /scraper/declencher?figer=false`, qui réécrit `date_course` et
`date_qualifications` **même pour un GP figé** — les deux se remettent d'aplomb en une fois.

**Ne pas refaire.** **Tout essai de scraper d'ici là doit porter `?figer=false`.**

---

## 12. ⚠️ OUVERT — Bandeau « Grands Prix restants » figé à 12

**Symptôme.** L'accueil affichera « 12 Grands Prix restants » même après le GP des Pays-Bas.

**Cause réelle.** `chargerGrandsPrixRestants` comptait les lignes de `public.grands_prix` —
c'est-à-dire **une seule course**, Unibet n'exposant que le GP suivant. La constante
`GP_RESTANTS = 12` a été posée pour avoir un nombre juste plutôt qu'un nombre faux.

**Correctif disponible.** `lib/calendrier2026.js` existe maintenant, et l'onglet Calendrier
en tire déjà un décompte **qui exclut les courses terminées**. Il suffit de compter
`GP_2026` filtré par `etatDuGpSaison`.

**Ne pas refaire.** **Sans cela, les deux écrans se contrediront dès la première course
courue.** `chargerGrandsPrixRestants` reste en place — elle redevient la bonne réponse le
jour où le calendrier complet est en base.

---

## 13. Le voile calculé démasque une déclaration incomplète

**Symptôme.** Aucun — **le calcul de contraste a fait son travail**, et c'est pour cela que
le cas est ici.

**Cause réelle potentielle.** `voileNecessaire` dérive l'opacité de la **bande la plus
claire** déclarée dans `couleurs`. Tant que les États-Unis et le Brésil étaient déclarés
`complexe` avec une seule dominante (`#B22234`, `#009C3B`), le calcul concluait qu'aucun
voile — ou presque — n'était nécessaire. **Le dessin, lui, peint treize bandes blanches** :
servi sous l'ancienne déclaration, il aurait porté du texte blanc sur du blanc pur.

**Correctif.** `couleurs` porte **toutes** les teintes que le SVG peint. Le voile s'est
ajusté seul : 0,00 → 0,45.

**Ne pas refaire.** **Toute forme peinte par le SVG doit avoir sa teinte dans `couleurs`.**
Un test compare les deux tables forme par forme.

*Corollaire mesuré* : la règle n'est pas « une bande blanche ⇒ un voile », c'est **« le
calcul tranche »**. Le vert du Brésil est assez clair pour demander 0,05 alors qu'il n'a
aucune bande blanche. Un test éprouvait initialement la mauvaise règle et échouait sur le
Brésil — **c'est l'assertion qui était fausse, pas le code.**

---

## 14. `window.Container` — un garde toujours faux

**Symptôme.** Un test d'effet visuel (Liquid Glass, retiré) retombait **en permanence** sur
son repli, librairie chargée ou non, **sans que rien ne le signale**.

**Cause réelle — deux, indépendantes.**

1. `Container` et `Button` sont des déclarations `class` au premier niveau d'un script
   classique : elles créent une liaison dans l'environnement **lexical** global, **jamais
   une propriété de l'objet global** — seuls `var` et les déclarations de fonction le font.
   Un garde `window.Container` est donc **faux en permanence**.
2. Vite hisse le script de module dans le `<head>` ; les scripts de la librairie vivent en
   fin de `<body>`. Tous différés, **React rend avant que `Container` existe**.

**Correctif (si l'effet est retenté).** `typeof Container !== "undefined"` — une référence
nue lèverait `ReferenceError`. Et attendre `window.load`, seul signal qui suit tous les
scripts différés **et qui est émis même quand l'un d'eux échoue**.

**Ne pas refaire.** Le code a été **retiré**, pas neutralisé. La réserve qui reste :
`Container.pageSnapshot` est **statique et capturé une seule fois** — le verre aurait
réfracté l'écran du premier montage.

---

## 15. `git revert` bloqué par un commit intercalé

**Symptôme.** Le `git revert` annoncé pour retirer le test Liquid Glass se serait arrêté en
conflit.

**Cause réelle.** Le commit n'était plus en tête : une version (drapeaux SVG) avait atterri
par-dessus, et les deux touchaient **les deux mêmes fichiers** (`CLAUDE.md`,
`package.json`). Résoudre à la main aurait risqué d'emporter la version intercalée.

**Correctif.** Restauration **ciblée** :
`git checkout <commit>^ -- <fichiers précis>`, suppression des fichiers ajoutés, puis
reprise à la main de la version et du CLAUDE.md. Vérifié : la version intercalée ne
touchait aucun des fichiers restaurés.

**Ne pas refaire.** **Avant un `revert`, vérifier le recouvrement** avec ce qui a atterri
depuis. Sans recouvrement, la restauration ciblée est plus sûre.

---

## 16. Le rendu HTML seul ne suffit pas — six fois

**Symptôme.** Six défauts sont passés à travers les contrôles textuels et n'ont été trouvés
qu'en **rendant l'écran avec la feuille CSS compilée**.

| # | Défaut |
|---|---|
| 1 | Numéro lu dans `saisie` au lieu du repli — première image sans numéro |
| 2 | Icône du logo calée à gauche (`items-center` sur un `Bloc`, §2) |
| 3 | Légendes de la vue piste se recouvrant dès que les voitures se resserrent |
| 4 | Interlignage `0.85` : les chiffres ronds débordaient (le « 1 » ne le montrait pas) |
| 5 | Transition sur `transform` au lieu de `translate` (§7) |
| 6 | `gap` inerte sur un `Bloc` (§2) |

**Ne pas refaire.** **Un rendu HTML vérifie la structure et le contenu, jamais la mise en
page.** Deux classes de défauts lui échappent par construction : les règles CSS qui ne
s'appliquent pas (§1, §2, §7) et tout ce qui tient à la géométrie (§3, §4).

**Le réflexe** : rendre l'écran avec la vraie feuille compilée, à 390 px de large, et
regarder. C'est ce qui a attrapé les six.

---

## 17. Ordre de peinture perdu à l'extraction — Mercedes et Alpine barrées de gris

**Symptôme.** Sur les deux seules livrées venues de `VOITUREs_am.svg`, un **aplat gris
sombre** (`#3C3C3B`) couvrait les deux tiers arrière de la voiture. Alpine y perdait tout
son rose, Mercedes son modelé gris clair et ses accents turquoise autour du cockpit.

**Cause réelle — ce n'était PAS une collision de classes CSS.** L'hypothèse naturelle est
que deux planches inlinées dans le même document se disputent leurs `.cls-N`. Elle est
fausse ici, et elle ne peut pas être vraie : **le frontend ne contient ni une seule classe
`cls-N`, ni une seule balise `<style>`** — la règle 3 d'extraction (`composants.md` §4) les
a toutes converties en attributs `fill` dès l'origine. Un `grep` de trois secondes le dit.

Le vrai défaut est l'**ordre de peinture**. Dans la planche, le polygone `#3C3C3B` — le
fond plat, qui doit rester **sous** la carrosserie — est le **premier élément du
document**, pour les deux voitures. Le découpage l'avait recopié au rang 13 (Mercedes) et
16 (Alpine) : mêmes formes, mêmes couleurs, même cadrage, **mais peint par-dessus**.

Un contrôle forme par forme le confirmait sans ambiguïté : 21 formes pour Mercedes,
24 pour Alpine, **exactement les mêmes des deux côtés, dans un ordre différent**. Et
les neuf livrées de `voitures_ecuries.svg` étaient, elles, dans le bon ordre — Cadillac
ouvre bien son fragment par son `#3C3C3B`.

**Correctif.** Les deux fragments **régénérés par script** depuis la planche, en ordre de
document. Aucune coordonnée réécrite ; seule la séquence change. Le rendu du fragment JSX
et celui de la planche cadrée sont désormais superposables.

**Ne pas refaire.**

- **Devant une zone de couleur fausse dans un SVG extrait, comparer l'ORDRE avant les
  couleurs.** Les couleurs étaient justes au code hexadécimal près, et les chemins exacts
  au caractère près : les deux contrôles habituels passaient.
- **Un SVG n'a pas de `z-index`.** L'ordre de document est le seul empilement qui existe ;
  le déplacer est une modification du dessin, pas une mise en forme.
- **Le contrôle qui attrape ce défaut est le rendu comparé** — fragment extrait contre
  planche cadrée, côte à côte. Un décompte des formes ou des `fill` ne le voit pas :
  ils sont identiques.

---

## 18. Les photos ne s'enregistraient PAS — une contrainte `check` incompilable

**Symptôme.** Deux symptômes en apparence sans rapport, livrés ensemble par la version
`0.50.0` :

- au profil, choisir une photo affichait **« Enregistrement de ta voiture : impossible
  pour le moment »** — un message qui parle de la voiture alors qu'on vient de toucher à
  une photo ;
- au championnat, la photo choisie à la création **n'apparaissait nulle part** : ni sur la
  carte d'accueil, ni dans la liste des championnats, ni dans l'en-tête de l'écran du
  championnat. Et **sans le moindre message**.

**Cause réelle — une seule, en base, pour les deux.** La migration 16 posait sur
`profils.avatar_url` et `championnats.photo_url` la même contrainte :

```sql
check (colonne is null or colonne ~ '^https://[^[:space:]]{10,505}$')
```

**Le moteur d'expressions régulières de PostgreSQL plafonne un compteur de répétition
`{m,n}` à 255** (`RE_DUP_MAX`). `{10,505}` dépasse ce plafond : l'expression n'est pas
compilable. Toute écriture d'une URL de photo retombait donc en

```
ERROR 2201B: invalid regular expression: invalid repetition count(s)
```

et **aucune photo n'a jamais pu être enregistrée depuis l'origine de la fonctionnalité.**
Vérifié sur la base de production le 22/08/2026, sur les deux colonnes.

**Ce qui n'était PAS en cause, et qu'on a écarté un par un.** Le diagnostic a été fait
contre la base réelle, pas par lecture — c'est ce qui l'a rendu court :

| Soupçon | Verdict |
|---|---|
| Migration 16 non appliquée | **Non.** Les deux colonnes existent (`select=photo_url` rend `[]` et non `42703`) |
| Compartiments Storage absents | **Non.** `avatars` et `championnats` rendent `NoSuchKey`, un compartiment inconnu rend `NoSuchBucket` |
| Politiques `storage.objects` trop strictes | **Non.** Les deux dépôts réussissent en `200` |
| `mes_championnats` en retard sur la migration | **Non.** `GET /championnats/moi` sert bien `photo_url` |
| La route `PATCH` ou son autorisation | **Non.** `url_de_photo_valide` passe, et le `403` créateur ne se déclenche pas |

Tout marchait **sauf** l'écriture de la colonne.

**Deux amplificateurs, et ce sont eux qui ont fait durer le défaut une version entière.**

1. **Le contexte du décorateur nommait la mauvaise chose.** `PATCH /profils/moi` sert la
   voiture, le numéro, la livrée **et** la photo, mais `journaliser_echecs` portait
   « Enregistrement de ta voiture ». Un échec de photo s'annonçait donc comme un échec de
   voiture, et envoyait chercher la cause du côté des couleurs. **Un contexte qui nomme la
   mauvaise chose est pire qu'un contexte vague.**
2. **L'échec de la photo d'un championnat était avalé en silence.** `attacherPhoto`
   rendait `undefined` dans tous les cas, par application de la règle « l'échec d'une
   opération secondaire n'emporte jamais la principale ». La règle est bonne ; sa mise en
   œuvre ne l'était pas. **Ne pas bloquer sur un échec n'autorise pas à le taire.**

**Correctif (version `0.51.0`).**

- **Migration 17** — la borne de longueur sort de l'expression régulière et devient un
  `char_length` : `~ '^https://[^[:space:]]+$' and char_length(...) between 18 and 513`.
  Sémantique identique à la lettre, plus aucun compteur, donc plus aucun plafond.
- La migration **s'éprouve elle-même** en fin de fichier, sur une URL jetable : une
  contrainte `check` n'étant évaluée qu'à l'écriture, c'est le seul moyen de savoir en la
  jouant qu'elle est compilable. C'est exactement ce qui manquait à la 16.
- Le contexte de `PATCH /profils/moi` devient **« Enregistrement de ton profil »**.
- `attacherPhoto` **rend son message d'échec**, que l'écran du championnat annonce à
  l'arrivée. La création n'est toujours pas bloquée.

**Ne pas refaire.**

- **Un compteur de répétition d'une expression régulière PostgreSQL ne dépasse jamais
  255.** Une borne de longueur se dit `char_length`, jamais dans le quantificateur d'une
  classe de caractères — mélanger les deux questions dans une seule expression est
  précisément ce qui a fait franchir le plafond sans que personne ne le voie.
- **Une contrainte `check` ajoutée sur une colonne vide n'est jamais éprouvée par sa propre
  migration.** Elle est acceptée à la création et n'échoue qu'à la première écriture, qui
  peut arriver des semaines plus tard. Toute migration qui pose un `check` non trivial doit
  l'exercer sur une valeur d'exemple dans un bloc `do $$`.
- **Le contexte d'un `journaliser_echecs` doit nommer la ROUTE, pas l'un de ses usages.**
  Une route de modification partielle en sert plusieurs par construction.
- **Devant un défaut de bout en bout, éprouver la chaîne segment par segment contre le
  service réel**, et non la relire. Colonne, compartiment, politique, fonction SQL, route :
  ici, quatre segments sur cinq étaient corrects, et aucune lecture du code ne pouvait
  désigner le cinquième — la contrainte est en base, elle n'apparaît que dans une migration
  déjà jouée.

---

## 19. L'initiale d'une pastille sur quatre était illisible

**Symptôme.** Sur certains comptes — et sur eux seulement — l'initiale de la pastille se
lisait mal sur son rond. Aucun écran n'était en cause : la même personne était illisible
partout, une autre lisible partout.

**Cause réelle.** `Pastille` écrivait `text-white` **en toutes lettres**, et sa table
distribue quatre teintes. L'une d'elles est l'amber `#E8A020` du design system, où le blanc
ne vaut que **2,22:1** quand `#1A1A1A` y monte à 7,86:1. Une graine sur quatre tombait
dessus, ce qui explique que le défaut ait paru aléatoire : il dépendait de l'identifiant du
compte, pas de l'écran.

C'est exactement le cas d'école que `docs/design-system.md` §5 décrit — « toute surface
amber prend l'encre foncée, sans exception » — et la pastille était le seul aplat de l'app
à ne pas passer par un helper.

**Correctif (version `0.52.0`).** `encreSurAplat(couleur ?? teinte.hex)`, calculé une fois
et posé en style en ligne. Mesuré après correction : 10,88 · **7,86** · 10,56 · 14,58:1.

**Ne pas refaire.**

- **Les deux helpers d'encre ne sont pas interchangeables, et l'amber les départage.**
  `encreSur` (`lib/palette.js`) compare une **luminance** à 0,45 ; l'amber vaut **0,424**,
  il passe donc juste sous le seuil et rend du blanc. `encreSurAplat` (`lib/couleurs.js`)
  mesure le **contraste** et bascule à 3:1. Devant la question « quelle encre sur cet
  aplat », c'est le second. Le premier reste juste là où il est employé — les deux textes
  peints sur une carrosserie, qui ne rencontrent jamais l'amber.
- **Un `text-white` écrit en dur sur un fond calculé est toujours un défaut en attente.**
  La couleur du fond vient d'une table ; l'encre doit venir du même endroit.
- **Un défaut qui « touche certains comptes » n'est pas intermittent** : c'est une fonction
  de hachage quelque part. Le chercher dans les écrans a coûté du temps ; il était dans la
  table.

---

## 20. Le numéro peint sur le museau était tête-bêche — depuis l'origine

**Symptôme.** Sur les quatre écrans qui dessinent une voiture, le numéro du museau se lit à
l'envers. Toutes les livrées, toutes les tailles, depuis la première version qui affiche une
voiture.

**Cause réelle.** Le fichier source. `assets/voitures_perso.svg` écrit le numéro sous
`transform="… rotate(180)"`, et l'extraction l'a repris tel quel — comme elle doit reprendre
tout le reste. **Ce n'est pas une faute de la planche** : sur une vraie monoplace, le numéro
du museau se lit depuis l'avant, c'est-à-dire depuis la voiture qu'on double. La planche
dessine la convention réelle.

Le défaut est dans le **contexte** : toutes les vues de l'app sont des vues **de dessus**.
Le commentaire du code disait d'ailleurs la chose exacte — « le numéro se lit depuis l'avant
de la voiture, comme en Formule 1 » — et l'a fait passer pour une intention pendant douze
versions.

**Correctif (version `0.53.0`).** La rotation part, et la ligne de base descend d'une
**hauteur de capitale** (`0,717 em`, métrique d'Helvetica).

**Ne pas refaire.**

- **Retirer la rotation seule aurait déplacé le numéro.** `rotate(180)` ne renverse pas
  seulement les glyphes : il renverse leur position autour de la ligne de base. Sous
  rotation, les chiffres occupent `[yNumero, yNumero + 0,717 em]` ; à l'endroit,
  `[y − 0,717 em, y]`. Sans la compensation, le numéro remontait de quinze unités sur le
  museau — un déplacement assez petit pour passer inaperçu à la relecture du diff, et assez
  grand pour se voir à l'écran.
- **Le décalage est calculé, pas relevé.** Les douze `yNumero` sont mesurés séparément
  (`VoituresEcuries.jsx`) ; douze corrections posées à l'œil auraient été démenties par la
  première livrée retouchée.
- **Un commentaire qui explique un comportement ne prouve pas qu'il est voulu ICI.** Celui-là
  était vrai — de la Formule 1 — et faux de l'application.
- **Vérifié par rendu comparé**, ancien et nouveau côte à côte : le numéro occupe le même
  rectangle, à l'endroit. Le calcul seul aurait laissé passer une erreur de signe.

---

## 21. « Pronostiquer » proposé sur un Grand Prix déjà joué

**Symptôme.** Dans les deux calendriers, un Grand Prix aux cotes arrêtées porte toujours
« Pronostiquer », et le bouton ouvre le **tableau des cotes** — l'écran de saisie des
favoris — même quand la saisie est enregistrée depuis longtemps. Le joueur qui veut relire
ce qu'il a joué se retrouve au début du parcours.

**Cause réelle.** Le widget de l'accueil arbitre sur **trois** destinations depuis la
version `0.5.1` (`couru` → résultats, `aPronostique` ou fermé → récap, sinon → cotes). Les
deux calendriers, eux, n'en connaissaient que deux. La règle avait un propriétaire pour la
condition d'**existence** du bouton — `cotesArretees`, partagée par les trois surfaces — et
aucun pour le choix de la **destination**.

**Correctif (version `0.53.0`).** Les deux calendriers testent à leur tour « ai-je déjà
joué ce Grand Prix ? ». Le calendrier d'un championnat lit `mes_pronostics`, **déjà servi**
par sa route et déjà lu par la même carte quelques lignes plus bas ; le calendrier de la
saison charge la liste de ses propres `gp_id` en une lecture RLS, en parallèle des cotes.

**Ne pas refaire.**

- **Deux questions, pas une.** « Y a-t-il quelque chose à ouvrir ? » (`cotesArretees`, règle
  4.3, inchangée) et « quoi ouvrir ? » sont distinctes. Les fondre aurait fait porter au
  mode prévisualisation une décision qui ne le concerne pas.
- **L'échec de la lecture ne se propage pas.** `chargerMesGpPronostiques` rend toujours `ok`
  avec un ensemble vide : le calendrier retombe alors sur « Pronostiquer », qui reste vrai —
  on peut rouvrir sa saisie jusqu'à la fermeture. **Le sens du doute va vers le libellé qui
  ne ment jamais.**
- **Le cache pouvait réintroduire le défaut à lui seul.** Quatre surfaces décident de leur
  libellé sur cette donnée et lisent toutes un cache *stale-while-revalidate*.
  `oublierMesPronostics` les balaie ensemble après un enregistrement ; l'accueil, seul
  balayé jusqu'ici, aurait laissé les trois autres en arrière.
- **La clé du calendrier de la saison porte `:v2:`.** Son entrée ne contient plus la même
  chose ; servie telle quelle, un cache d'une version antérieure aurait rendu douze cartes
  sans état ni bouton le temps d'un aller-retour.

---

## 22. Un demi-podium ne rapportait rien — sur le pari le mieux doté de la grille

**Symptôme.** Un joueur plaçait Norris sur le podium, se trompait sur le second nom, et
finissait avec **zéro point** — à égalité exacte avec celui qui s'était trompé sur les
deux. Sur le marché qui peut rapporter le plus.

**Cause réelle.** Ce n'était **pas un bug de calcul** : le code faisait exactement ce que
la règle métier prescrivait, et la règle était mauvaise. `points_du_podium` testait
`all(resultats)` — les deux pilotes ou rien — et `metier.md` §2 l'écrivait noir sur blanc :
« un seul des deux ne rapporte rien, ce n'est pas un demi-pronostic mais un pronostic
raté ». Trois surfaces la répétaient, le code, le document, et le commentaire de la
fonction. **Un défaut défendu par sa documentation ne se voit pas en relisant le code.**

Le raisonnement d'origine tenait pourtant : payer la seule cote de `pilote_1` ferait
rapporter deux montants différents au même pari selon l'ordre de saisie, puisque les deux
emplacements n'ont aucun ordre entre eux (règle 4.2). La conclusion tirée — tout ou rien —
était la mauvaise sortie. **La bonne est de payer chaque cote à SON pilote** : la somme
reste ordre-indépendante, et un demi-podium rapporte la même chose quel que soit
l'emplacement où le bon nom a été saisi.

**Correctif (version `0.54.0`).** Chaque sélection est jugée pour son propre compte, et
`points` est la somme des cotes gagnées — deux, une, ou zéro. `reussi` suit les points,
comme partout ailleurs.

**Ne pas refaire.**

- **Une jambe non jugeable laisse le pronostic ENTIER à `NULL`**, même si l'autre est
  décidée. La ligne ne porte qu'un seul `points_gagnes`, et `attribuer_points` n'écrit que
  les `NULL` (`scraper.md` §12) : payer la seule jambe connue figerait un total partiel que
  le rattrapage **ne corrigerait plus jamais**. Attendre est réversible, écrire ne l'est
  pas — c'est la même asymétrie que « un marché non reconnu vaut `NULL`, jamais `0` ».
- **Le total POTENTIEL ne change pas** : il reste la somme des deux cotes (`metier.md` §9),
  parce que c'est toujours le maximum atteignable. Seule la validation a changé. Toucher au
  potentiel aurait déplacé la cote moyenne tentée de toute la base.
- **`metier.md` §2 a été réécrit dans le même commit que le code.** La laisser dire le
  contraire aurait rendu le correctif indiscernable d'une régression à la relecture
  suivante — et c'est cette divergence-là qui a fait vivre le défaut.

---

## 23. « Écart du gagnant » : le champ n'était pas mal lu, il n'était pas lu

**Symptôme.** Le marché « écart du gagnant » restait « en attente » indéfiniment, y compris
quand le bon intervalle avait été pronostiqué. Un déclenchement manuel de
`POST /jobs/resultats/{gp_id}` ne le rattrapait pas non plus.

**Cause réelle — et ce n'est pas celle qu'on cherche.** On cherche naturellement une
comparaison qui échoue : un intervalle mal lu, une virgule française, un écart en
millisecondes. **Il n'y avait aucune comparaison.** Deux maillons manquaient, tous les deux
dans `app/calcul/points.py` :

1. **`gap_to_leader` n'entrait jamais dans `Ligne`.** `analyser()` lisait `position`,
   `number_of_laps`, `points`, `dnf`, `dns`, `dsq` — et pas lui. Sa propre docstring le
   disait, en le présentant comme une décision : « `gap_to_leader` de type mixte (jamais lu
   — aucun marché validé aujourd'hui n'en dépend) ». C'était vrai à l'écriture, et c'est ce
   qui a fait passer l'oubli pour une intention pendant six versions.
2. **`validateur()` ne reconnaissait pas le slug.** Le marché tombait donc dans le filet
   « marché non reconnu », qui rend `None` — et `None` veut dire `NULL`, pas `0`. **Le
   pronostic n'était pas jugé perdant : il n'était pas jugé.** C'est exactement ce que ce
   filet existe pour faire, et c'est pour cela que le défaut est resté silencieux.

**`app/scraper/openf1.py` n'était pas en cause et n'a pas été touché.** Il conserve les
lignes de `session_result` **telles quelles** dans `donnees_brutes` : `gap_to_leader` était
donc déjà en base, sur tous les Grands Prix déjà courus. C'est le contrat du module —
« tout ce dont le calcul a besoin » — et c'est ce qui rend le rattrapage possible **sans
rappeler OpenF1** sur les courses passées.

**Correctif (version `0.54.0`).** `Ligne.ecart_leader`, alimenté par `_secondes()` ;
`Course.ecart_du_vainqueur()` ; `_intervalle_secondes()` ; `_ecart_du_gagnant()` ; le slug
reconnu sur « ecart » ou « marge » + « victoire ».

**Ne pas refaire.**

- **L'écart se lit sur la ligne du DEUXIÈME, pas du premier.** `gap_to_leader` dit « de
  combien ce pilote est derrière le leader » : sur la ligne du leader il vaut `null`, ce
  qui est correct et n'est pas une donnée manquante. Le lire là aurait donné un marché
  éternellement non jugé — le symptôme exact qu'on venait de corriger.
- **Le champ a quatre types, pas trois.** Nombre (`11.536`), chaîne numérique
  (`"+11.536"`), chaîne de tour (`"+1 LAP"`), `null` — et la liste (`[0.0, 0.0, 0.0]`) sur
  une ligne de qualification. `_secondes()` les absorbe tous. **Un pilote doublé vaut
  `math.inf`, jamais `None`** : ce n'est pas un écart illisible, c'est un écart plus grand
  que la borne haute de n'importe quel intervalle.
- **Les bornes sont `[bas, haut[`.** Les issues d'Unibet forment une partition (« moins de
  5 », « 5 - 10 », « plus de 10 ») : deux bornes inclusives feraient gagner *deux* paris à
  un écart de 5,000 s exactement, deux exclusives n'en feraient gagner aucun. Le cas ne se
  produira jamais au millième près — raison de plus pour que la règle soit décidée une fois
  ici plutôt que découverte le jour où il se produit.
- **Aucun vrai libellé Unibet n'a encore été vu pour ce marché.** Les formes reconnues sont
  écrites d'après les tournures usuelles ; une issue non reconnue est **journalisée** et
  laisse le pronostic à `NULL`. `POST /jobs/resultats/{gp_id}/test` les confronte sans rien
  écrire (`scraper.md` §13) — c'est par là qu'il faut passer avant le premier vrai Grand
  Prix, pas par la vraie route.
- **Le commentaire qui défendait l'absence a été réécrit.** Même leçon qu'au §20 et au §22 :
  un manque qui s'explique dans une docstring cesse d'être cherché.

---

## 24. Le calcul était déjà bon — c'est l'idempotence qui gardait le mauvais verdict

**Symptôme.** Au GP des Pays-Bas, le podium obligatoire « C.Leclerc + AK.Antonelli »
affiche **0 pts** alors qu'Antonelli est bien monté sur le podium ; les pronostics
« écart du gagnant » restent **en attente**. Les deux correctifs de la version `0.54.0`
paraissent donc n'avoir servi à rien.

**Cause réelle — et ce n'est ni le podium ni l'écart.** Les deux validateurs sont justes,
et rejouer le calcul à la main sur les données du GP le montre en une commande :
le demi-podium rend 28 pts, « Entre 5 et 10 secondes » rend sa cote. **Le code n'a jamais
été en cause.**

Ce qui l'était, c'est la **chronologie**. Le job de résultats a tourné à `départ + 1h30`,
avec le backend d'**avant** la `0.54.0` — le podium était encore tout-ou-rien, l'écart
encore non reconnu. Il a écrit `0` sur le podium et laissé `NULL` sur l'écart. Le correctif
a été livré le soir même, **après**. Et `attribuer_points` n'écrit **que** les
`points_gagnes` encore `NULL` (`scraper.md` §12) :

| État écrit par l'ancien code | Ce que le rattrapage peut faire |
|---|---|
| `NULL` (écart du gagnant, marché non reconnu) | **rattrapable** — un simple `POST /jobs/resultats/{gp_id}` suffit |
| `0` (demi-podium jugé perdant) | **définitivement figé** — plus aucun appel ne le réécrit |

**C'est le filet de `NULL ≠ 0` vu depuis l'autre côté.** La règle protège d'un verdict
inventé ; elle ne protège pas d'un verdict **faux mais assumé**. Un `0` est une décision,
et l'idempotence défend les décisions — y compris celles d'un validateur qu'on vient de
corriger. **Les deux symptômes n'avaient donc pas la même gravité**, alors qu'ils se
présentaient identiques à l'écran.

**Correctif (version `0.55.0`).** `POST /jobs/resultats/{gp_id}?forcer=true` :
`reinitialiser_points()` rend les `points_gagnes` du GP à `NULL`, puis le calcul reprend
normalement. Défaut `false`, secret d'admin exigé, **jamais appelé par le scheduler** — le
job automatique reste strictement idempotent.

**Ne pas refaire.**

- **On remet à `NULL`, jamais à `0`.** C'était la formulation spontanée de la demande
  (« mettre à zéro `points_gagnes` »), et elle aurait produit **exactement le bug qu'elle
  cherchait à corriger** : `0` veut dire « raté », `attribuer_points` ne réécrit que les
  `NULL`, donc le GP serait ressorti avec les mêmes zéros, définitivement. Le seul état
  depuis lequel un calcul peut reprendre est `NULL`.
- **`pronostic_podium.points_gagnes` se remet à `NULL` avec son parent.** Il en *dérive*
  et `attribuer_points` le resynchronise — mais seulement pour les podiums qui reçoivent
  une attribution. Un podium resté non jugé garderait sinon son ancien total à côté d'un
  parent vide : les deux colonnes divergeraient, ce que le trigger d'origine avait
  précisément pour but d'empêcher.
- **OpenF1 n'est pas rappelée.** `resultats_gp` n'est pas touché ; le calcul rejoue le JSON
  conservé. C'est exactement ce à quoi sert `donnees_brutes`, et ce qui rend l'opération
  sans risque sur un Grand Prix vieux de plusieurs semaines.
- **Vérifier le calcul AVANT de conclure à un bug de calcul.** Trois lignes de Python sur
  les données du GP ont suffi à écarter deux des trois pistes. Sans cette vérification, on
  aurait « corrigé » deux validateurs déjà justes — et le vrai défaut, qui est une
  chronologie de déploiement, serait resté entier.
- **Un correctif de validateur livré après le job ne s'applique à rien tout seul.** Il
  demande toujours un rattrapage explicite, et un rattrapage **forcé** dès que l'ancien
  code a écrit autre chose que `NULL`. À se rappeler pour les huit familles de marchés
  encore jamais confrontées à de vrais libellés.

---

## 25. « Autres » n'est pas une nationalité — c'est le complémentaire des autres issues

**Symptôme.** Au GP des Pays-Bas, les pronostics « nationalité du vainqueur » posés sur
l'issue **« Autres »** restent **en attente**, indéfiniment. Les autres issues du même
marché, elles, sont notées normalement. Dans les logs, une ligne par pronostic :

```
[points] Nationalité du vainqueur : l'issue « Autres » ne correspond à
aucune nationalité connue. Pronostic laissé non jugé.
```

**Fausse piste immédiate.** Le message invite à ajouter « Autres » à `NATIONALITES`, et la
table est justement écrite à l'aveugle (`roadmap.md` §3.15) : le réflexe est d'y voir une
quinzième forme manquante. **Il n'y a aucune entrée à ajouter.** Sous quel code l'aurait-on
rangée ? « Autres » ne nomme aucun peuple ni aucun pays.

**Cause réelle.** Toutes les issues du système se jugent **seules**. « Néerlandais » est
vrai ou faux sans qu'on ait besoin de savoir ce que le marché proposait à côté ; « Entre 5
et 10 secondes » aussi ; « Oui » aussi. **« Autres » est la première issue qui n'est pas une
valeur mais un complémentaire** : elle veut dire « une nationalité qu'Unibet n'a pas listée
ce jour-là ». Sa vérité dépend donc d'une chose que le validateur n'avait pas — **la liste
des issues sœurs du même marché** — et cette liste change d'un Grand Prix à l'autre, Unibet
n'ouvrant jamais deux fois le même jeu d'options.

Le validateur recevait `(course, libelle)`. Avec ces deux seuls arguments, « Autres » est
**indécidable** — et le filet a fait exactement son travail : `None`, jamais `0`.

**Correctif (version `0.56.0`).** `validateur(marche, options)` reçoit désormais les
libellés de **toutes** les issues du marché pour ce Grand Prix, et le validateur de la
nationalité devient une fabrique qui les capture — même idiome que `_top(rang)`, déjà en
place. `points_du_pronostic` les tire de `issues_du_marche(cotes, marche)`, c'est-à-dire du
dictionnaire de cotes **déjà chargé** : aucune lecture de plus, et la liste est celle que le
scraper a réellement enregistrée ce jour-là.

Le verdict se lit alors en trois tests, et **leur ordre porte tout le raisonnement** :

| Situation | Verdict | Pourquoi |
|---|---|---|
| La nationalité du vainqueur est parmi les options **lues** | **raté**, `0` | définitif : aucun libellé restant ne peut la faire disparaître de la liste |
| Sinon, une option sœur est **illisible** | **non jugé**, `NULL` | elle pouvait être précisément celle du vainqueur |
| Sinon | **réussi**, la cote | la nationalité du vainqueur n'était listée nulle part |

Le paramètre est facultatif et vide par défaut : un appelant qui l'ignore retrouve
exactement le comportement d'avant — « Autres » non jugé, plutôt que mal jugé.

**Ne pas refaire.**

- **Ne pas ranger « Autres » dans `NATIONALITES`.** Le message d'erreur y pousse, et sous
  n'importe quel code la table rendrait alors ce code pour « Autres » : le pronostic serait
  jugé sur la nationalité d'un pays choisi au hasard. Un `0` ou une cote inventés, tous deux
  définitifs.
- **Ne pas écrire la liste des options en dur.** Elle vient des cotes du Grand Prix
  **traité**, jamais d'une liste de pays écrite à l'avance : c'est ce qui fait tenir la règle
  pour tous les Grands Prix futurs, dont les options seront autres.
- **Une option illisible ne fait pas gagner « Autres ».** « Je ne trouve pas la nationalité
  du vainqueur dans une liste que je ne sais pas lire en entier » n'est pas « elle n'y est
  pas ». Elle ne l'empêche pas de **perdre**, en revanche : c'est la même asymétrie que
  partout ailleurs dans le module — on refuse d'inventer un gain, pas de constater un fait.
- **Le rattrapage suffit, sans `?forcer=true`.** Ces pronostics sont restés à `NULL` : ils
  n'ont jamais été jugés, donc rien n'est figé (§24). Le GP des Pays-Bas est tout de même
  rejoué en forçant, parce que la commande couvre au passage tout ce qu'un ancien code
  aurait pu écrire en dur :

  ```
  curl -X POST "https://<railway>/jobs/resultats/33b835cc-5c17-40f7-a41f-3e95fc14885a?forcer=true" \
       -H "X-Admin-Secret: <valeur>"
  ```

  **À relancer une fois la `0.56.0` déployée sur Railway**, pas avant : un rejeu sur
  l'ancien backend reproduirait le même `NULL`. Lire `en_attente` dans la réponse — c'est
  elle qui dira si « Autres » est enfin jugé, ou si une option sœur reste illisible.

---

## 26. Le widget d'accueil restait sur un Grand Prix fini, et comptait la fermeture de pronostics jamais ouverts

**Symptôme.** Deux défauts sur le même bloc, celui que tout le monde voit en premier.

1. Le GP des Pays-Bas, en statut `termine`, occupait encore la place du prochain Grand
   Prix — longtemps après le dimanche de la course.
2. Sur un Grand Prix `a_venir`, la seconde case de statut annonçait « Fermeture dans » et
   décomptait treize jours. Les pronostics n'étaient pas ouverts, aucun bouton ne s'affichait
   sous elle, et rien ne disait quand ils le seraient.

**Cause réelle — les deux, et elles ne sont pas les mêmes.**

Pour le premier, la règle « le dimanche soir appartient encore au Grand Prix du jour »
(version `0.53.0`) : `chargerProchainGp` lançait d'abord `chargerGpDuJour`, une lecture des
`termine` de la journée civile locale, et la servait avant tout le reste. **Le défaut ne
venait pas de son implémentation — elle faisait exactement ce qui était écrit — mais de son
principe** : elle faisait dépendre « ce Grand Prix est-il fini ? » de l'heure qu'il est, là
où le statut le dit déjà, seul et sans ambiguïté.

Pour le second, un libellé écrit en dur **à deux endroits séparés** : dans `Horloge.jsx`
(`etat.ferme ? "Pronostics" : inconnue ? "Départ" : "Fermeture dans"`) et une seconde fois
dans les cases de statut du bloc d'accueil. Ni l'un ni l'autre ne connaissait la première
échéance du week-end — le relevé des cotes. `useFermeture` ne recevait que `date_course` :
avec cette seule donnée, **l'ouverture était indécidable**, et le seul décompte possible
était celui de la fermeture.

**Correctif (version `0.57.0`).**

`chargerGpDuJour` et `debutDuJourLocal` sont supprimés ; `chargerProchainGp` ne fait plus
qu'une lecture, sur les deux statuts non courus. Un Grand Prix `termine` n'en sort jamais.

Le compte à rebours reçoit une source unique, `etatPronostics` (`lib/calendrier.js`), qui
prend le **Grand Prix entier** et rend `{ phase, ferme, restant, texte, label, substitut }`.
Elle tranche sur `cotesArretees` — la fonction qui décide déjà du bouton de pronostics — et
décompte `date_qualifications + 2h` avant l'ouverture, `date_course − 5 min` après.
`useEtatPronostics` l'anime ; `Horloge` n'affiche plus que ce qu'on lui donne. Règle métier
complète dans `metier.md` §3.

**Ne pas refaire.**

- **Ne pas remettre une fenêtre de grâce après `termine`.** Ni minuit, ni « six heures
  après », ni aucune durée : le statut est la seule réponse à « est-ce fini ? », et le
  dimanche soir se lit sur l'écran de résultats, qui est fait pour ça. Ce que l'ancienne
  règle voulait éviter — un compte à rebours de treize jours à l'ouverture de l'app — est
  précisément ce que le second correctif règle, et sans mentir sur ce qui est fini.
- **Ne pas trancher les phases sur `gp.statut === "cotes_figees"`.** C'est `cotesArretees`
  qui décide, statut **et** qualifications passées (règle 4.3), parce que c'est elle qui
  décide du bouton. Un `POST /scraper/declencher` lancé un mardi ferait sinon annoncer
  « Fermeture dans » au-dessus d'un bloc sans bouton — un décompte vers une fermeture que
  rien n'ouvrira. C'est exactement le défaut constaté en `0.38.0`, vu depuis le texte.
- **La phase d'ouverture est celle qui PRÉCÈDE, jamais celle qui suit.** Tester les seules
  cotes non arrêtées y ferait retomber tout Grand Prix couru — et `ferme` étant ce qui tient
  le formulaire de saisie verrouillé, l'écran de saisie se serait rouvert sur une course
  déjà courue. Les trois conditions vont ensemble : cotes non arrêtées, fermeture pas encore
  passée, statut différent de `termine`.
- **Les deux heures après les qualifications sont une prévision, pas une garantie.** Le job
  du samedi peut prendre du retard. Passée l'heure prévue sans que le statut ait bougé, le
  décompte se tait — « Ouverture / À confirmer » — au lieu d'afficher un délai négatif ou de
  promettre une ouverture en retard.
- **Ne pas mettre l'objet `gp` en dépendance de l'effet du hook.** `useDonnees` sert un
  objet neuf à chaque revalidation en arrière-plan, même identique : la minuterie serait
  détruite et réarmée sans fin. Les trois champs sont mis en dépendance un par un.
- **Un libellé partagé se partage aussi.** `Horloge` avait été extraite en `0.18.0`
  précisément pour qu'une composition ne soit pas écrite deux fois — mais son **texte**,
  lui, était resté dupliqué avec celui de l'accueil, et les deux ont dit la même chose
  fausse pendant onze versions. Le partage d'un composant ne couvre que ce qu'on lui a
  confié.

---

## 27. Les qualifications s'affichaient une heure trop tard — et la table statique était juste

**Symptôme.** Sur la fiche d'un Grand Prix (`/calendrier/:slug`), la rangée
« Qualifications » annonce une heure fausse. Le GP d'Italie affiche **17h00** pour des
qualifications qui se courent à **16h00**. Neuf des onze Grands Prix restants sont touchés,
de une à quatre heures d'écart ; Austin et le Mexique tombent juste.

**La cause n'est pas dans `GP_2026`.** La table statique portait déjà les bonnes heures —
la `0.60.0` les avait relevées sur le calendrier officiel. **Les corriger n'aurait rien
corrigé** : `seancesDuGp` **préfère l'heure de la base** à celle de la table statique, pour
les deux séances que la base connaît. C'est la règle voulue, posée en `0.59.0` — « la base
l'emporte partout où elle a une réponse » — et elle suppose que la base dise vrai.

Elle disait faux, et par **deux chemins qui se renforçaient** :

1. **La migration 19** insérait `date_qualifications = date_course − 22 heures` pour les
   onze lignes manuelles ;
2. **le scraper** réappliquait le même calcul (`REPLI_QUALIFICATIONS`) à chaque passage où
   Unibet n'annonce pas d'événement de qualification — c'est-à-dire, d'après le constat de
   terrain d'août 2026, **le régime normal et non l'exception** (`scraper.md` §5).

Corriger l'un sans l'autre ne suffisait donc pas : la base seule aurait été réécrite au
premier scraping, le scraper seul aurait laissé les onze lignes en place.

**22 h ne pouvait pas marcher.** L'écart entre les qualifications et le départ n'est pas une
constante : 23 h sur huit week-ends, 22 h sur deux (Austin et le Mexique, dont la course
part deux heures plus tôt en heure locale), 24 h au Brésil, et **26 h à Las Vegas**, dont
les qualifications se courent le vendredi soir. Une constante appliquée aux douze en manque
neuf.

**Correctif.** L'heure des qualifications est **écrite**, jamais dérivée. La migration 20
pose les onze instants, les mêmes que `GP_2026.seances.qualifications` ; le repli du
scraper est retiré (`0.57.0`), et quand Unibet se tait la clé n'est simplement pas écrite
dans l'upsert — la valeur en base survit.

### Ce qu'il ne faut pas refaire

- **Ne pas corriger la source qu'on regarde sans vérifier qui gagne.** La table statique
  était juste et sous les yeux ; la valeur affichée venait d'ailleurs. Quand deux sources
  répondent à la même question, la question à se poser d'abord est « laquelle l'emporte ? ».
- **Une constante de temps n'est pas une source unique, c'est une supposition.** Le motif
  d'origine était bon — la migration 19 réutilisait exprès le repli du scraper pour n'avoir
  qu'une règle et un propriétaire. **Le motif était bon, la règle était fausse** : partager
  une valeur fausse la propage au lieu de la corriger.
- **Un repli qui s'applique tout le temps n'est plus un repli.** Il était écrit pour le cas
  rare et journalisé en `warning` ; il était en fait le cas normal. Un `warning` qui sort à
  chaque passage ne se lit plus comme une alerte.
- **Deviner une donnée l'écrase.** Le vrai dommage n'était pas la devinette, c'était
  l'écriture : une heure relevée à la main était remplacée par un calcul à chaque scraping.
  Ne rien écrire laisse la donnée juste en place — c'est « on se ferme sur une donnée qu'on
  n'a pas » appliqué à l'écriture.
- **Le prix du retrait est assumé, et il est réel.** Une ligne neuve dont Unibet ne publie
  pas le programme n'a plus d'horaire de qualifications, donc pas de figeage automatique ni
  de bouton de pronostics. Le cas concret est une **ligne manuelle jamais adoptée**. Une
  heure manquante se voit dans les logs ; une heure fausse ne se voyait pas.
- **La migration 19 n'a pas été réécrite.** Les migrations de ce dépôt sont historiques
  (`database.md` §7). La 20 corrige derrière elle, et l'ordre 19 → 20 devient un piège
  d'ordre à part entière — le premier qui porte sur des **données** et non sur une fonction
  remplacée.

---

## 28. La photo d'un autre pouvait devenir la sienne — l'URL était vérifiée, pas le dossier

**Symptôme.** Aucun. C'est un défaut d'autorisation, et il ne se voit qu'au moment où
quelqu'un s'en sert : un joueur portant le visage d'un autre membre au classement, sur la
piste et au résumé d'un Grand Prix, sans qu'aucune trace ne dise comment.

Trouvé par un **audit IDOR** de l'ensemble des vingt-et-un endpoints FastAPI, pas par un
rapport d'utilisateur.

### Les deux endpoints concernés

| Endpoint | Ce qu'il acceptait |
|---|---|
| `PATCH /profils/moi` | `avatar_url` désignant `avatars/{id de n'importe qui}/avatar.jpg` |
| `PATCH /championnats/{id}` | `photo_url` désignant `championnats/{tout autre championnat}/photo.jpg` |

### Cause réelle

**`url_de_photo_valide` répondait à une question, et il y en avait deux.** Elle vérifiait
que l'URL désigne bien **notre projet Supabase** et **le bon compartiment** — la protection
du « pixel espion » de la migration 16, qui marchait exactement comme prévu. Mais elle ne
regardait pas le **premier segment du chemin**, celui qui porte l'identifiant du
propriétaire.

Or c'est précisément sur ce segment que porte l'autorisation en base :
`(storage.foldername(name))[1] = auth.uid()` pour un avatar, et une remontée à
`championnats.cree_par` pour une photo de championnat (`database.md` §9).

**La RLS Storage ne pouvait rien y faire, et c'est le point à retenir.** Elle garde le
**dépôt du fichier** — chemin (B) de `architecture.md` §3, où le client parle à Supabase
sous son propre jeton. L'**écriture de l'URL en base** est le chemin (A) : elle passe par
FastAPI, qui écrit avec la clé de service, laquelle **contourne la RLS**. Personne ne
pouvait déposer un fichier dans le dossier d'un autre ; tout le monde pouvait enregistrer
comme sienne l'adresse d'un fichier déjà déposé par un autre.

Les deux compartiments étant **publics** (§9), il n'y avait aucune fuite de donnée : la
photo était déjà lisible de tous. Le défaut est une **usurpation d'apparence**, pas une
divulgation.

### Correctif — backend `0.58.0`

`app/api/stockage.py` prend un quatrième argument **obligatoire**, `proprietaire`, et exige
que le premier segment du chemin lui corresponde, à la casse près (un UUID y est
insensible). Le chemin doit en outre porter un objet après le dossier — un dossier nu n'est
pas une image.

- `PATCH /profils/moi` passe **l'identifiant du jeton**, jamais une valeur reçue ;
- `PATCH /championnats/{id}` passe **l'identifiant du chemin**, déjà filtré par le contrôle
  de créateur qui le précède.

Les deux seuls appelants du frontend déposent déjà sous `dossier = profilId` et
`dossier = championnatId` (`lib/stockage.js`) : rien de légitime ne change de comportement.

### Ce qu'il ne faut pas refaire

- **Une vérification qui porte le bon nom n'est pas pour autant complète.** « L'URL de la
  photo est-elle valide ? » a reçu une réponse juste et partielle pendant sept versions.
  La question utile n'était pas « d'où vient cette image ? » mais « à qui est-elle ? » —
  deux questions dans une même fonction, dont une seule était écrite.
- **Ne jamais déduire d'une politique RLS que le backend est couvert.** La règle du dossier
  existait en base, correcte, testée, et documentée. Elle protégeait **l'autre chemin**. Dès
  qu'une écriture passe par la clé de service, la RLS n'est plus un filet — c'est la route
  qui porte l'autorisation, et elle doit redire la règle en entier.
- **Un argument d'autorisation ne prend pas de valeur par défaut.** `proprietaire` est
  positionnel et obligatoire : un `None` par défaut aurait rendu le contrôle silencieusement
  facultatif, et le premier appelant qui l'oublie aurait rouvert la porte sans que rien ne
  le signale. C'est le même sens du doute que « secret non configuré ferme la route »
  (`api/deps.py`).
- **Chercher le défaut là où la donnée est écrite, pas là où elle s'affiche.** Le symptôme
  serait apparu au classement, dans un composant qui n'a jamais eu tort.

---

## 29. Toute la population de l'app était lisible par n'importe quel inscrit

**Symptôme.** Aucun, comme au §28 : un défaut d'autorisation ne se voit qu'au moment où
quelqu'un s'en sert, et celui-ci ne laisse pas plus de trace qu'une lecture ordinaire.

Trouvé par un **audit des politiques RLS** des sept tables les plus sensibles, dans la
foulée de l'audit IDOR du §28. Cinq défauts en sont sortis, tous de la même famille : une
politique qui vérifie **qu'on est connecté** là où il fallait vérifier **qui on est**.

### Les cinq défauts

| Table | Ce que la politique disait | Ce qu'elle laissait faire |
|---|---|---|
| `profils` | `for select using (true)` | lire pseudo, couleurs, numéro, livrée, `avatar_url` et `is_admin` de **tous les inscrits** |
| `profils` | `for update` sur la LIGNE | écrire son propre `is_admin` depuis un client Supabase |
| `pronostics` | co-membre, sans condition de temps | lire les pronostics d'un co-membre **avant** la fermeture, et jouer dessus |
| `membres_championnat` | `with check (auth.uid() is not null)` | s'ajouter à un championnat **sans son code**, ou y ajouter quelqu'un d'autre |
| `championnats` | `with check (auth.uid() is not null)` | poser des lignes au `cree_par` d'autrui et **squatter des `code_invitation`** |

### Cause réelle

**`auth.uid() is not null` n'est pas une autorisation, c'est une authentification.** Les
deux clauses `insert` fautives disent « être connecté » ; il n'y a pas de troisième
lecture possible de ce texte. Elles ont été écrites à un moment où l'adhésion et la
création passaient encore par le client, avant que `creer_championnat` et
`POST /championnats/rejoindre` ne prennent le relais avec la clé de service. **Le chemin a
changé, la politique est restée.**

Pour `profils`, la cause est différente et plus instructive : le commentaire de la
migration 1 énonce le besoin réel — « les classements et les listes de membres d'un
championnat ont besoin des pseudos des **autres** ». Des autres **membres**. `using (true)`
répond à la question « qui a besoin de lire ? » par « tout le monde », alors que les quatre
lectures directes qui existent dans le frontend ne demandent, toutes les quatre, que
soi-même ou ses co-membres. **La politique était plus large que son unique appelant.**

### Correctif

Migration 21, `20260827_audit_rls.sql`. Six correctifs, aucune fonction touchée :

- lecture de `profils` bornée à **soi-même ou un membre d'un championnat partagé**, par la
  forme déjà employée pour les pronostics (`est_membre`, qui casse la récursion) ;
- `revoke update` sur la table `profils`, puis `grant update` sur les **huit colonnes**
  que `PATCH /profils/moi` accepte — la RLS ne sait pas filtrer par colonne, le droit si ;
- `public.pronostics_fermes(gp_id)` ajouté à la branche « co-membre » de la politique de
  lecture des pronostics ;
- les deux politiques `insert` retirées, et le droit de table avec elles ;
- lecture des `cotes` réservée aux comptes connectés.

### Ce qu'il ne faut pas refaire

**Ne pas croire qu'un audit RLS mesure ce que l'app montre.** Il ne mesure que ce qu'un
porteur de la clé publique peut faire **en dehors** d'elle. Toutes les écritures et la
plupart des lectures agrégées passent par FastAPI avec la clé de service, qui contourne la
RLS : la fenêtre de fermeture posée sur `pronostics` **ne rend pas les pronostics privés à
l'écran**, `pronostics_du_championnat` restant `security definer`. C'est un écart signalé,
pas un correctif à moitié.

**Ne pas recréer une politique permissive à côté d'une politique resserrée.** Deux
politiques `select` se combinent par **OU** : la seconde ne remplace pas la première, elle
la désarme, sans erreur ni ligne manquante. C'est le conflit d'ordre du §6 de
`database.md`, et le bloc de contrôle de la 21 existe pour le rendre bruyant.

**Ne pas oublier le `grant update (…)` en ajoutant une colonne à `profils`.** Depuis la 21,
une colonne neuve naît non-modifiable depuis un client. Sans effet sur l'app, qui écrit
avec la clé de service — mais le jour où un écran écrira en direct, le symptôme sera un
`42501` sur une colonne qu'on croira bien déclarée.

---

## 30. Le bouton « Pronostiquer » ne s'affichait jamais — une heure absente fermait ce qu'un statut ouvrait

**Symptôme.** Un Grand Prix scrapé sans le moindre incident — cotes en base, statut
`cotes_figees`, compte à rebours à l'écran — n'offrait **aucun bouton de pronostics**. Ni
sur le bloc de l'accueil, ni sur le calendrier de la saison, ni sur celui d'un championnat,
ni sur la fiche du Grand Prix. Les quatre surfaces se taisaient ensemble, et l'écran
n'affichait aucun message : le bouton était simplement absent, comme sur un Grand Prix
encore à venir.

**Cause réelle.** Ce n'est pas le bouton qui était cassé, c'est sa condition.
`cotesArretees` (`lib/calendrier.js`) exigeait **deux** choses : le statut `cotes_figees`,
et une `date_qualifications` **datée et passée**. La seconde venait de la version `0.38.0`
et visait un cas réel — `POST /scraper/declencher` lancé un mardi fige des cotes sur une
grille de départ qui n'existe pas encore, et le statut seul ne sait pas s'en défendre.

**Mais `date_qualifications` est `NULL` bien plus souvent qu'on ne le croyait.** Le repli
`date_course − 22h` a été retiré du scraper en `0.57.0`, à juste titre : il écrasait
l'heure relevée sur le calendrier officiel par une constante fausse sur neuf Grands Prix de
douze. Depuis, l'heure ne peut venir que de deux endroits — la migration 20, ou le
programme publié par Unibet. Or **Unibet n'expose aucun événement de qualification** dans
le régime constaté sur le terrain (`scraper.md` §5, août 2026 : un seul événement
« Course » au nœud racine, vérifié aussi dans le bloc SSR). Et la migration 20 ne couvre que
les onze lignes qu'elle a posées.

Une ligne née du scraper — un Grand Prix qu'aucune migration n'a écrit, ou une ligne
manuelle jamais adoptée, dont le scraper avait créé le doublon (§ ci-dessous) — n'avait
donc **jamais** d'heure de qualifications. La condition de garde ne se déclenchait pas à la
marge : elle était le **régime normal**, et elle fermait les pronostics de tout le monde.

> **`NULL` rendait `false`, et c'était écrit comme une vertu** — « on se ferme sur une
> donnée qu'on n'a pas, jamais l'inverse ». La formule est juste quand la donnée absente est
> ce qui **autorise**. Ici elle était ce qui **interdisait** : son absence ne laissait pas
> le doute, elle le tranchait contre le joueur, sur un Grand Prix dont tout le reste disait
> qu'il était prêt.

**Correctif** (version `0.65.0`). `cotesArretees` ne lit plus que deux choses, et
`date_qualifications` n'en est pas :

```js
statut === "cotes_figees"  ET  date_course − 5 min > maintenant
```

Le statut n'est pas une supposition : `jobs/scraper.py` ne le pose qu'après un scraping
dont **au moins une cote a été écrite**. Il y a donc quelque chose à pronostiquer, ce qui
est toute la question. La fermeture, elle, reste vérifiée — par `etatFermeture`, le calcul
déjà partagé par les trois étages de la règle 4.3, jamais un second écrit à côté. Un Grand
Prix dont l'heure de départ est inconnue **reste ouvert**, comme le veulent la base et le
backend.

**Ce qu'il ne faut pas refaire.**

**Ne pas remettre `date_qualifications` dans une condition d'affichage.** Elle reste lue
pour le compte à rebours d'**ouverture** (« Ouverture dans », `etatPronostics`), et c'est sa
place : là, son absence fait taire une prévision, elle ne retire rien. Une prévision muette
ne coûte rien ; un bouton absent coûte le week-end de course.

**Ne pas confondre « se fermer sur une donnée qu'on n'a pas » avec « se fermer sur une
donnée qu'on n'a jamais ».** La règle suppose que la donnée arrive d'ordinaire et manque par
accident. Quand c'est l'inverse — elle manque par construction, et n'arrive que par
exception — la garde n'est plus une précaution, c'est un interrupteur en position ouverte.
**Le test à faire est celui-là : sur combien de lignes réelles cette colonne est-elle
remplie aujourd'hui ?**

**Le cas que la garde visait n'a pas disparu, et il se traite ailleurs.** Un figeage passé
un mardi reste possible ; la porte de sortie est `POST /scraper/declencher?figer=false`,
explicite et documentée (`scraper.md` §9), et le job automatique, lui, ne se déclenche
jamais avant `date_qualifications + 2h`. Le défaut d'origine était d'avoir gardé contre un
geste d'administration **au prix du régime normal de tous les joueurs.**

---

## 31. Le scraper créait un doublon plutôt que de reconnaître une ligne posée à la main

**Symptôme.** Deux lignes pour le même Grand Prix dans `public.grands_prix`. Celle du
scraper portait les cotes et un statut qui avançait ; la ligne manuelle gardait l'ancien
UUID, ses pronostics, ses favoris — et restait éternellement `a_venir`. Selon la ligne sur
laquelle un écran tombait, le même Grand Prix s'annonçait « à venir » ou « pronos ouverts ».
Le job de scraping, lui, ne figeait rien : il visait un `gp_id`, le scraper en rendait un
autre, `_resultat_du_gp` ne trouvait pas le Grand Prix attendu et la fenêtre de quatre
heures s'épuisait sur cette erreur.

**Cause réelle.** Les onze Grands Prix de la fin de saison sont posés en base par la
migration 19, **avant** qu'Unibet n'ouvre leur page : leur `id_unibet` est donc inventé
(`manuel-<slug>-2026`). Le scraper se rapproche sur `id_unibet` et sur rien d'autre — c'est
délibéré, le nom change d'orthographe d'une semaine à l'autre (« GP Pays Bas », « GP
Pays-Bas ») — donc il ne reconnaissait pas la ligne et son upsert en insérait une seconde.

Le geste correctif existait : `select public.adopter_grand_prix('manuel-italie-2026', '<id
réel>');`, à jouer dans le SQL Editor **le vendredi ou le samedi matin** de chaque week-end
de course. C'est-à-dire douze fois dans la saison, dans une fenêtre de quelques heures,
avec un identifiant à relever dans les logs. **Un rendez-vous manuel hebdomadaire n'est pas
un correctif, c'est un défaut avec un mode d'emploi.**

**Correctif** (version `0.65.0`). `unibet._adopter`, appelé en tête de `_enregistrer`.
Avant toute écriture, le scraper cherche une ligne dont l'`id_unibet` commence par
`manuel-` et dont le **nom** correspond au sien — comparaison par `slug()`, insensible à la
casse, aux accents et aux séparateurs. S'il en trouve une, il lui fait porter le vrai
`id_unibet` par un simple `update`. **L'UUID ne bouge pas** : tout ce qui pend à la ligne
reste attaché, et l'upsert qui suit y écrit `date_course`, `date_qualifications` et les
cotes comme sur n'importe quelle autre.

Trois refus délibérés, chacun journalisé :

- **deux lignes manuelles de même nom** → aucune adoption. Choisir la première venue
  attacherait les pronostics d'un Grand Prix à un autre ; le doublon se voit, une adoption
  fausse ne se voit pas. C'est la règle du rapprochement des pilotes (`scraper.md` §11) ;
- **le doublon est déjà constitué** (une ligne porte déjà le vrai identifiant) → aucune
  fusion, un `warning` qui écrit la commande `adopter_grand_prix` toute faite. Seule la
  fonction SQL sait compter les quatre tables filles avant de supprimer quoi que ce soit ;
- **zéro ligne touchée par l'`update`** → quelqu'un a adopté entre la lecture et
  l'écriture. Le filtre porte sur le placeholder autant que sur l'identifiant, exactement
  comme le `PATCH` de figeage : l'état voulu, atteint par un autre, n'est pas une panne.

**Ce qu'il ne faut pas refaire.**

**Ne pas rapprocher par le nom ailleurs que là.** Le nom reste un mauvais identifiant, et
c'est toute la raison d'être d'`id_unibet`. Il n'est utilisé ici que parce que c'est
littéralement la seule chose que les deux lignes partagent — s'il y avait un identifiant
commun, il n'y aurait rien à adopter. Le rapprochement avec OpenF1 continue de se faire sur
la **date** (`scraper.md` §10), et le job de scraping sur le `gp_id`.

**Ne pas supprimer la ligne manuelle pour « nettoyer ».** Les quatre tables filles sont en
`on delete cascade` (migrations 3 et 5) : un `delete` aveugle emporte des pronostics sans
un mot. Mieux vaut un doublon visible qu'un pronostic effacé en silence — c'est déjà ce que
dit `adopter_grand_prix`, et l'adoption automatique ne fait rien d'autre.

**Ne pas croire que `adopter_grand_prix` est devenue inutile.** Elle reste la seule voie
pour le cas que l'automatique refuse : le doublon déjà constitué, et les deux lignes
manuelles homonymes.

---

## 32. Une page HTML pouvait devenir un avatar — le dossier était vérifié, pas le nom du fichier

**Symptôme.** Aucun, comme aux §28 et §29 : c'est un défaut de validation, et il ne se voit
qu'au moment où quelqu'un s'en sert.

Trouvé par un **audit des dépôts de photos** portant sur cinq questions : type MIME, taille,
segment de dossier, traversée de chemin, et type servi à l'affichage. **Un seul défaut en
est sorti** — les quatre autres points étaient déjà couverts, et par où ils l'étaient
compte autant que le correctif.

### Ce que l'audit a d'abord dû rétablir : il n'y a pas d'upload backend

La demande visait « la validation du type MIME dans `backend/app/api/stockage.py`, avant
l'upload vers Supabase Storage ». **Ce chemin n'existe pas.** `app/api/stockage.py` ne reçoit
jamais de fichier : il ne valide qu'une **URL**, et FastAPI n'a aucune route `UploadFile` —
`grep -rn "UploadFile" backend/app` ne rend rien, et `python-multipart` n'est pas installé.

Le fichier va **directement du navigateur à Supabase Storage** (chemin (B) d'`architecture.md`
§3). Conséquence pour tout audit futur : **« côté serveur » ne veut pas dire « dans FastAPI »**.
Pour un dépôt de photo, le serveur qui garde, c'est **le compartiment Supabase** — sa liste
`allowed_mime_types`, son `file_size_limit`, et les politiques de `storage.objects`. Un
contrôle ajouté dans FastAPI n'aurait gardé rien du tout : il aurait été du théâtre sur un
chemin que le fichier n'emprunte pas.

### Les quatre points sans défaut, et où ils sont gardés

| Point | Verdict | Ce qui garde, côté serveur |
|---|---|---|
| **Type MIME** | **Sain** | `allowed_mime_types = ['image/jpeg','image/png','image/webp']` sur les deux compartiments (migration 16 §3). Supabase refuse en `415` — un client modifié n'y change rien. |
| **Taille** | **Sain** | `file_size_limit = 2 097 152` sur les deux compartiments. Le plafond de 5 Mo de `lib/stockage.js` ne juge, lui, que ce qu'on accepte de **choisir** ; les deux ne mesurent pas la même chose (voir `composants.md`, version `0.51.0`). |
| **Traversée de chemin** | **Sain** | `url_de_photo_valide` refuse `..`, et surtout **compare le dossier par égalité stricte** : rien de smuggé dans ce segment ne peut y survivre, pas même une séquence encodée (`%2e%2e`), qui casse l'égalité au lieu de la contourner. |
| **Type servi à l'affichage** | **Sain** | Supabase sert l'objet sous le `Content-Type` du dépôt, et ce type est **forcément** l'un des trois : c'est `allowed_mime_types` qui l'impose, pas le `contentType: TYPE_DEPOSE` du frontend. **`image/svg+xml` est absent de la liste** — c'est la seule image qui porte du script, et les deux compartiments sont publics. Ni `text/html` ni `application/javascript` ne peuvent donc être servis. |

**La nuance qui vaut d'être retenue sur le type MIME** : `allowed_mime_types` porte sur
l'**en-tête `Content-Type` annoncé**, jamais sur les octets du fichier. Un attaquant peut
déposer du HTML en l'annonçant `image/jpeg`. Ce n'est pas une faille, précisément parce que
c'est ce même type annoncé qui sera **servi** : le navigateur reçoit du HTML étiqueté
`image/jpeg`, ce qu'il n'exécute pas. L'incohérence contenu / type est sans effet ; c'est le
type servi qui décide, et il est sous clé.

### Cause réelle du seul défaut : le nom du fichier n'était contrôlé nulle part

Le correctif du §28 avait ajouté le contrôle du **premier segment** du chemin. Rien ne
regardait ce qui suit — ni en base, ni dans le backend :

- la politique `storage.objects` ne compare que `(storage.foldername(name))[1]` (`database.md`
  §9) : sous son propre dossier, **n'importe quel nom est déposable** ;
- `url_de_photo_valide` exigeait un objet **non vide** après le dossier, et rien de plus.

Un joueur pouvait donc déposer `avatars/{son propre id}/page.html` — son dossier, donc la
RLS passe ; annoncé `image/jpeg`, donc le compartiment passe — puis l'enregistrer comme son
avatar par `PATCH /profils/moi`, où les quatre contrôles passaient aussi. L'URL partait
ensuite dans un `src` sur l'écran de tous les autres membres.

**Portée réelle : faible, et il faut le dire.** L'objet étant servi en `image/jpeg`, il ne
s'exécute ni dans un `<img>`, ni en navigation directe. Le défaut n'était pas un XSS stocké ;
c'était l'**absence de la ceinture** qui, seule, tenait encore si le harnais lâchait — une
liste `allowed_mime_types` élargie un jour à `image/svg+xml` aurait suffi à transformer ce
même trou en XSS stocké sur l'écran de tout un championnat.

### Correctif — backend `0.62.0`

`url_de_photo_valide` prend une **cinquième condition** : ce qui suit le dossier doit être un
nom simple portant une extension d'image.

- `NOM_DE_FICHIER` = `^[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$`, casse ignorée sur
  l'extension comme elle l'est déjà sur le dossier. Ce que le motif **interdit** est
  l'essentiel : pas de `/` (donc aucun sous-dossier), pas de `%` (donc aucune séquence
  encodée qu'un intermédiaire décoderait autrement que nous), pas de point ailleurs que
  devant l'extension (donc ni `page.html`, ni `avatar.jpg.svg`).
- `PARAMETRE_DE_CACHE` = `^v=\d{1,20}$` : le péremptoire de cache que `deposerPhoto` ajoute à
  chaque dépôt est légitime et devait rester admis, mais lui seul — il finit dans un attribut
  `src`.

Vérifié sur treize variantes d'attaque (`.html`, `.svg`, `.js`, double extension,
sous-dossier, traversée brute et encodée, dossier d'autrui, mauvais compartiment, projet
tiers, injection dans le `src`, fragment, dossier nu) : toutes refusées en `422`. Et sur six
URL légitimes, extensions `png` / `webp` / `jpeg` d'avant la `0.51.0` et dossier en
majuscules compris : toutes acceptées.

**Rien de légitime ne change.** Les deux seuls appelants déposent sous une `base` constante —
`"avatar"` et `"photo"` (`MonProfil.jsx`, `CreerChampionnat.jsx`).

### Le résidu est fermé — migration 22 (`20260913_storage_rls_extension`)

Le correctif backend empêchait d'**enregistrer** `{son propre id}/page.html` comme photo ;
il laissait ouverte la possibilité de le **déposer**, la politique de la 16 ne comparant que
le premier segment du chemin. Ce résidu avait été signalé plutôt que tranché seul, faute de
pouvoir jouer une migration automatiquement (CLAUDE.md §3.3). **La migration 22 le referme :
le dépôt lui-même est désormais refusé.**

Elle amende les **quatre** politiques d'écriture — `insert` et `update` des deux
compartiments — par un troisième terme, `public.nom_de_photo_valide(name)`, qui exige du
dernier segment du chemin le **même motif que le backend**.

Trois décisions valent d'être retenues, parce qu'elles ont chacune failli être prises à
l'envers :

- **`alter policy`, pas `drop` + `create`.** La politique garde son nom, son verbe, ses
  rôles, et surtout la clause `using` des deux `update` — PostgreSQL laisse inchangée toute
  clause absente d'un `alter policy`. L'expression `with check` doit néanmoins être
  **réécrite en entier** : il n'existe aucun moyen d'ajouter un terme à une expression de
  politique. C'est cette recopie qui crée le piège d'ordre (voir ci-dessous).
- **Le motif ne va PAS dans le `using` des `update`.** `using` décide quelles lignes
  **existantes** sont modifiables ; la question posée porte sur le nom de la **nouvelle**.
  L'y ajouter aurait rendu un objet mal nommé déposé avant la migration **impossible à
  écraser**, donc irréparable autrement qu'en le supprimant. Éprouvé : remplacer un
  `legacy.html` par un `avatar.jpg` fonctionne, et c'était le but.
- **Ni `select` ni `delete` ne sont touchées.** `select` est la lecture publique : un objet
  déjà déposé doit rester lisible, sans quoi une photo d'avant la migration disparaîtrait
  des écrans. `delete` est **le seul geste qui répare** un objet mal nommé déjà en place ; le
  filtrer l'aurait rendu indéfiniment ineffaçable. Un contrôle de nom sur un retrait
  protégerait le déchet, pas les joueurs.

**Nouveau piège d'ordre** : rejouer la **16** après la **22** repose les quatre politiques
sans leur contrainte de nom, sans erreur ni trace — exactement comme rejouer la 16 après la
17 rouvrait le refus de toute photo. Remède : rejouer la 22 derrière. Entré au tableau de
`database.md` §6.

**Éprouvée sur un PostgreSQL 16 jetable**, seule migration du projet à l'avoir été
(`database.md` §6). Le harnais rejoue les sept politiques de la 16, puis la 22, puis dépose
sous le rôle `authenticated` : les trois noms légitimes passent, les sept mauvais sont
refusés par la RLS, l'`upsert` normal et la réparation d'un legacy fonctionnent, l'écrasement
de la photo d'un autre reste refusé, la suppression marche. Trois rejeux d'affilée ne
changent rien, le garde-fou d'absence lève un message clair si la 16 n'a pas été jouée, et le
contrôle d'état final détecte l'état dégradé du piège ci-dessus.

> **Le harnais a d'abord menti, et la leçon vaut mieux que le résultat.** Sa première version
> omettait les politiques `select` et `delete` de la 16 : **tous** les `update` ressortaient
> refusés, y compris l'`upsert` légitime. La cause n'était pas la migration mais PostgreSQL —
> **un `update` dont le `where` lit une colonne applique AUSSI les politiques `select`**. Sans
> politique de lecture, la ligne est introuvable et le `with check` n'est jamais atteint. Un
> banc d'essai incomplet accuse le code qu'il éprouve.

### Ce qu'il ne faut pas refaire

- **Ne pas confondre « côté serveur » et « dans FastAPI ».** Le projet a deux serveurs
  (`architecture.md` §3). Chercher la validation d'un dépôt dans le backend, c'est la chercher
  sur un chemin que le fichier n'emprunte pas — et risquer d'y ajouter un contrôle décoratif
  en croyant avoir fermé quelque chose.
- **Ne pas déduire d'un `Content-Type` fourni qu'il a été vérifié contre le contenu.**
  `allowed_mime_types` lit l'en-tête, pas les octets. Ce qui sauve, c'est que le type annoncé
  est aussi le type servi ; le raisonnement doit passer par là, sinon on conclut juste par
  hasard.
- **Une extension n'est pas une vérification de contenu, et ce n'est pas une raison de s'en
  passer.** Elle ne prouve rien sur les octets ; elle empêche une URL manifestement fausse
  d'entrer en base, et c'est la couche qui reste quand la liste des types change sous nous.
- **Un correctif d'autorisation ne couvre pas le segment voisin.** Le §28 a vérifié le
  dossier, entièrement et correctement — et a laissé le nom tel quel pendant quatre versions.
  Un chemin se valide par segment, pas par intention.

---

## 33. L'escalier de la vue piste : le groupe comptait ses membres, pas ses voies

**Symptôme.** Sur la vue piste, les voitures descendaient en **escalier diagonal** du coin
haut-gauche au coin bas-droit, au lieu de se tenir sur l'axe. Elles étaient en prime
**réduites de moitié** sans raison visible. Le correctif `0.69.0`, qui avait supprimé la
résolution verticale des collisions, n'y avait rien changé.

**Cause réelle.** Elle n'est **pas** dans `repartitionLaterale`, qui fait exactement ce
qu'elle annonce, ni dans un résidu de l'ancienne version — la feuille de style ne décale
aucune voiture horizontalement, `.t-place` est posée à `left-1/2` et `.t-voiture` n'anime
qu'un `translateY`.

Elle est à la jointure des deux passes. `regrouperParChevauchement` propage **en cascade** :
si A chevauche B et B chevauche C, les trois forment un groupe **même si A et C ne se
touchent pas**. C'est correct — le groupe dit qui doit être résolu ensemble.
`dispositionDesVoitures` en tirait ensuite une conclusion fausse : **une place latérale par
membre**, distribuée dans l'ordre du classement.

Le seuil vaut 122px (`HAUTEUR_VOITURE` 106 + `HAUTEUR_LEGENDE` 16). Sur une piste de 700px
la zone de jeu en fait 542 : **à partir de sept membres**, l'écart moyen passe sous le
seuil et la cascade réunit **tout le plateau en un seul groupe**. Huit membres recevaient
donc huit abscisses réparties d'un kerb à l'autre, attribuées par rang — l'abscisse montait
avec le rang exactement comme la hauteur. C'est la définition d'un escalier. Et huit
cellules sur 354px font 44px, d'où les voitures à 32px.

Mesuré avant correctif, scores `280 · 255 · 231 · 204 · 180 · 150 · 120 · 90` :

```
#0 y=73  x=-154.9   #2 y=213 x=-66.4   #4 y=358 x=+22.1   #6 y=529 x=+110.6
#1 y=144 x=-110.6   #3 y=290 x=-22.1   #5 y=444 x=+66.4   #7 y=615 x=+154.9
```

**Correctif — frontend `0.70.0`.** Une passe s'intercale, `voiesDuGroupe`, qui place chaque
voiture **dans la première voie dont la dernière occupante est à plus d'un seuil**.
`repartitionLaterale` reçoit alors un **nombre de voies** et non un nombre de membres. Les
huit voitures ci-dessus n'ouvrent que **deux** voies, à ±32px, et gardent leurs 52px.

Le placement au premier libre est **optimal** ici, et pas seulement raisonnable : les
hauteurs arrivent triées, le graphe des conflits est donc un graphe d'intervalles, dont le
nombre chromatique égale la plus grande clique. Vérifié sur le module compilé — le nombre
de voies ouvertes égale la plus grande pile de voitures en conflit **deux à deux**.

**Ne pas refaire.**

- **Un groupe dit qui se résout ensemble, jamais combien de places il faut.** La cascade
  réunit par construction des voitures qui ne se touchent pas ; leur compter une abscisse
  chacune est le défaut lui-même.
- **Ne pas chercher un résidu quand la géométrie suffit à expliquer.** Le symptôme
  ressemblait à de l'ancien code oublié. Il n'y en avait pas : deux passes justes prises
  séparément se contredisaient à la jointure.
- **Compter les voisines d'un élément n'est pas compter une clique.** Le premier jeu de
  tests a rejeté le bon correctif pour cette raison : `#2` et `#4` sont chacune en conflit
  avec `#3` sans l'être entre elles, et deux voies leur suffisent. La mesure était fausse,
  pas le code.
- **Un escalier, c'est `x` ET `y` qui montent ensemble.** Une rangée d'ex æquo partage une
  hauteur et étale ses abscisses : c'est une grille de départ, et elle est voulue.

### Suite — l'escalier résiduel : les voies étaient numérotées d'un kerb à l'autre (`0.71.0`)

**Symptôme.** Le correctif ci-dessus avait supprimé la rampe qui traversait la piste
entière, mais un **petit escalier** subsistait, redessiné à chaque tour du cycle des voies.

**Cause réelle.** Elle n'est plus dans le comptage — `voiesDuGroupe` ouvrait bien le bon
nombre de voies — mais dans **l'ordre des abscisses**. `repartitionLaterale` numérotait les
voies **de gauche à droite** : voie `0` contre le kerb gauche, dernière voie contre le kerb
droit. Or le remplissage au premier libre fait tourner les voies dans l'ordre du classement
`0, 1, 2, 0, 1, 2…` : trois voitures consécutives descendaient donc **gauche, milieu,
droite**, soit `x` et `y` qui montent ensemble sur trois voitures d'affilée. C'est un
escalier, plus court que le précédent mais de même nature.

**Correctif.** `repartitionLaterale` dispose les voies **en éventail autour de l'axe** : la
voie `0` est l'axe de la piste (`x = 0`), la `1` part à gauche, la `2` à droite, la `3` plus
à gauche, la `4` plus à droite. Les lignes arrivant triées par points décroissants, la
**meilleure voiture de chaque groupe ouvre toujours la voie `0`** et se pose sur l'axe.

Le pas entre deux voies vaut une voiture pleine plus une gouttière tant que la piste le
permet, et se réduit ensuite pour que le groupe tienne entre les kerbs. La symétrie coûte
un nombre **impair** de cellules : `rangMaximal` de chaque côté, plus l'axe. Six voies en
réclament donc sept, la septième restant vide à droite.

Mesuré après correctif sur les mêmes scores `280 · 255 · 231 · 204 · 180 · 150 · 120 · 90` :

```
#0 y=73  x=0     #2 y=213 x=0     #4 y=358 x=0     #6 y=529 x=0
#1 y=144 x=-64   #3 y=290 x=-64   #5 y=444 x=-64   #7 y=615 x=-64
```

Les huit gardent leurs 52px, et la suite des abscisses n'est monotone sur aucun segment.
Sur une piste de 354px, cinq voies tiennent encore à taille pleine (5 × 64 = 320) ; le
plancher mord à douze voies, et le recouvrement — un pixel — n'apparaît qu'à vingt.

**Ne pas refaire.**

- **Compter juste ne suffit pas : l'ordre d'attribution dessine aussi.** Le nombre de voies
  était correct depuis la `0.70.0` ; c'est leur numérotation qui continuait à produire la
  figure. Un placement se vérifie sur la **suite** des abscisses, pas sur leur nombre.
- **Un cycle de voies n'est pas un défaut, un cycle orienté si.** Trois voitures qui se
  chevauchent mutuellement doivent occuper trois abscisses distinctes ; ce qui se corrige,
  c'est qu'elles les prennent toujours dans le même sens.
- **Tenir l'axe a un prix, et il est assumé.** Un groupe de deux voies pose la meilleure
  voiture sur l'axe et l'autre à sa gauche : le groupe n'est plus centré sur la piste. La
  règle « la meilleure au milieu » l'emporte sur le centrage du groupe — c'est la hauteur
  qui dit les points, l'abscisse ne sert qu'à éviter un recouvrement.

---

## 34. Onze marchés par Grand Prix n'étaient pas reconnus — et la grille statique aurait mal jugé deux d'entre eux

**Symptôme.** Après les GP Italie et Espagne 2026, les pronostics posés sur
« *{écurie}* / Les 2 voitures dans le top 10 » restaient **sans points**, avec une ligne
`[points] … laissé(s) sans points` par pronostic. Onze marchés de cette famille au GP
Italie, six au GP Espagne : c'est le tiers des marchés ouverts.

**Cause réelle.** Le filet a fait son travail — `validateur()` ne reconnaissait pas le slug,
le pronostic restait à `NULL`, rien n'était mal jugé. Mais la famille est la **première dont
le slug porte le sujet du pari** : `ferrari-les-2-voitures-dans-le-top-10` nomme l'écurie
*et* le rang, là où tous les autres marchés se nomment d'un slug fixe et laissent l'issue
désigner le sujet. Aucun des tests de `validateur()` ne pouvait la prendre : le `fullmatch`
du « top N » exige que le slug ne soit **qu'**un rang, et le préfixe `ecurie` du bas ne
regarde que le début du slug.

**Correctif** (version `0.73.0`, backend `0.65.0`). `_DEUX_VOITURES` lit le nom de l'écurie et le rang dans le
slug ; `_les_deux_voitures_dans_le_top` juge un oui/non sur « les deux voitures sont-elles
classées à ce rang ou mieux ? ». Le rapprochement du nom d'écurie passe par
`equipe_du_libelle`, déjà en place pour « écurie vainqueur » : il couvre les **onze
variantes** relevées sur les vrais marchés — `alpine`, `aston-martin`, `audi-f1-team`,
`cadillac`, `ferrari`, `haas`, `mclaren`, `mercedes-amg`, `racing-bulls-team`, `red-bull`,
`williams` — sans qu'aucune soit écrite en dur.

Le test est placé **entre** le « top N » et le préfixe `ecurie`, et le préfixe d'écurie est
**obligatoire** dans le motif : `les-2-voitures-sur-le-podium` est un autre marché, dont les
issues sont des noms d'écurie et non un oui/non. Il reste non reconnu, donc à `NULL`.

### Ce que les vraies données ont démenti : la paire de pilotes ne vient PAS de la grille

Le réflexe est de demander ses deux pilotes à `calcul/pilotes.py`, qui tient la grille de la
saison. **Sur les deux Grands Prix à rattraper, cette lecture se serait trompée deux fois :**

| Marché | Grille statique | Ce qu'OpenF1 a enregistré | Verdict |
|---|---|---|---|
| Espagne, `red-bull` | Verstappen + **Hadjar** | Verstappen P2 + **Lawson P6** | grille « Non » · course **« Oui »** |
| Italie, `racing-bulls-team` | **Lawson** + Lindblad | **Tsunoda P10** + Lindblad P8 | grille « Non » · course **« Oui »** |

Les baquets ont bougé en cours de saison ; la grille ne le sait pas. Et un pronostic déclaré
raté vaut **`0`, qui ne se rattrape jamais** (`metier.md` §4) : l'erreur aurait été
définitive, sur le marché même qu'on venait réparer.

`Course.voitures_de(equipe)` lit donc la paire **dans les résultats du Grand Prix**, parmi
les seuls pilotes ayant une ligne de classement. Une écurie qui n'en compte pas exactement
deux laisse le pronostic non jugé, avec un avertissement nommant l'écurie.

**Ne pas refaire.**

- **Un marché non reconnu ne crie pas.** Onze marchés sur trente-quatre sont passés à
  travers deux Grands Prix sans autre trace que les avertissements de fin de calcul. La
  consigne de `metier.md` §4 — *relire les `[points] … laissé(s) sans points` après chaque
  Grand Prix* — est la seule chose qui les rende visibles.
- **Ne jamais dériver la composition d'une écurie d'une table écrite à la main** quand la
  donnée de course la porte. La table dit qui *devait* courir, les résultats disent qui a
  couru — et c'est la seconde question que pose le marché.
- **La grille de `calcul/pilotes.py` est périmée sur 2026** : Lawson y court pour Racing
  Bulls et Tsunoda (#22) en est absent. Rien de ce qui précède n'en dépend, mais les alias
  Unibet et le marché « nationalité du vainqueur », eux, en dépendent — un vainqueur Tsunoda
  laisserait tous ses pronostics de nationalité à `NULL`. **À corriger séparément**, en
  relevant la grille réelle, pas en recopiant ce tableau.

### Rattrapage : les deux Grands Prix à recalculer

À lancer **à la main après le déploiement Railway**, une commande après l'autre. `forcer=true`
remet les `points_gagnes` du Grand Prix à `NULL` avant de recalculer — c'est la seule
écriture du système qui efface un point, et le scheduler ne l'appelle jamais.

```bash
# GP Italie — 2026-09-06
curl -X POST "https://mon-petit-podium-production.up.railway.app/jobs/resultats/e4e6f2ab-9ea6-4191-ab6c-d61a61f1ef4f?forcer=true" \
  -H "X-Admin-Secret: monpetitpodium2026"

# GP Espagne — 2026-09-13
curl -X POST "https://mon-petit-podium-production.up.railway.app/jobs/resultats/b327866c-9479-4e59-bdde-5f0e6ec513aa?forcer=true" \
  -H "X-Admin-Secret: monpetitpodium2026"
```

**`forcer=true` est ici indispensable et ne suffit pas à tout réparer.** Il rend leurs points
aux pronostics de cette famille, restés à `NULL` ; il **ne corrige pas** un pronostic que le
code aurait noté `0` à tort — ceux-là n'existent pas dans ce cas précis, justement parce que
le marché n'était pas reconnu.

Vérification attendue dans les logs Railway : plus aucune ligne
`marché « …-les-2-voitures-dans-le-top-10 » non reconnu`.

## 35. iOS — les zones de tap étaient décalées d'une carte sur l'autre (`ios 0.29.0`)

**Symptôme.** Dans l'app native, taper une carte déclenchait **celle du dessous** :
« Créer un championnat » ouvrait « Rejoindre », un championnat en ouvrait un autre, et un
Grand Prix du calendrier ouvrait son voisin.

**Cause réelle.** Ni une `ZStack` mal ordonnée, ni un lien imbriqué, ni un décalage de
`ScrollView`. Les fonds des cartes posent une image en `scaledToFill` — le ``Damier`` des
cartes de championnat et d'action, le drapeau des cartes du calendrier et du widget GP.
Dans une `ZStack`, un `scaledToFill` impose sa **taille de remplissage** : le damier
(542 × 420) réclamait 280 pt de haut dans une carte de 120, soit 80 pt de débord au-dessus
et en dessous ; un drapeau 3:2 réclamait ~241 pt dans une carte de 200. Le `clipShape`
de la carte rognait ce débord **à l'œil, pas au doigt** — `clipShape` et `clipped()` ne
touchent pas au hit-testing. La carte suivante étant peinte par-dessus la précédente, son
débord supérieur captait les taps du bas de sa voisine.

C'est le même mécanisme que celui déjà mesuré sur le bandeau de `VuePisteView` — qui
l'avait corrigé localement, sans que la leçon remonte au ``Damier`` lui-même.

**Correctif.**
- ``Damier`` pose son motif en `overlay` sur un `Color.clear`, rogné par `clipped()` : il
  prend exactement la place qu'on lui propose, quel que soit son hôte.
- `contentShape` de la forme visible sur chaque surface dont le fond porte un
  `scaledToFill` : `CarteChampionnat`, `CarteAction`, la carte du calendrier, le widget GP
  de l'accueil, et les deux pastilles photo (`Avatar`, `PastilleProfil`).

### Ce qu'il ne faut pas refaire

- **Un `clipShape` ne définit pas la cible.** Toute surface tappable dont le fond peut
  déborder de son cadre porte une `contentShape` de sa forme visible.
- **Jamais de `scaledToFill` nu dans une `ZStack` de fond** : l'`overlay` sur une couleur,
  ou un `Color.clear`, ne change pas la taille de son hôte.

---

## 36. iOS — la voiture modifiée dans le Profil ne changeait pas sur la piste (`ios 0.30.0`)

**Symptôme.** Nouvelles couleurs ou nouveau numéro choisis dans l'onglet Profil : la vue
piste du championnat continuait de peindre l'ancienne voiture.

**Cause réelle.** Pas seulement un classement non rechargé. **Le bouton « Enregistrer ma
voiture » n'envoyait rien** : `PATCH /profils/moi` n'était pas branché, et le bouton ne
faisait que recopier l'état de l'écran dans son propre « enregistré ». Rien n'arrivait en
base, ni dans `AuthViewModel.profil`. Par-dessus, la piste peignait la voiture de chaque
membre depuis `GET /championnats/{id}/classement` — y compris la sienne, servie avant
toute modification.

**Correctif.**
- `AuthViewModel.enregistrerVoiture(_:)` envoie le `PATCH`, puis relit le profil par
  `chargerProfil(id:)`, son seul lecteur. `ProfilView` affiche le refus sous le bouton.
- **Une seule source pour sa propre voiture** : `BarreNavigation` descend le profil par
  l'environnement (`\.monProfil`), et `ChampionnatDetailView` remplace la voiture de la
  ligne du compte connecté par celle du profil (`Membre.avecVoiture(de:)`) avant de
  donner le tableau au classement, à la piste et au profil d'un membre. Points et rang
  restent ceux du serveur.

### Ce qu'il ne faut pas refaire

- **Un bouton d'enregistrement qui se contente de l'écran ment** : il affiche « enregistré »
  sans écrire. Tant que la route n'est pas branchée, il reste éteint.
- La voiture du compte connecté ne se lit **jamais** dans une ligne de classement.

---

## 37. iOS — les photos de profil n'apparaissaient pas dans le cockpit sur la piste (`ios 0.30.1`)

**Symptôme.** Vue Piste d'un championnat : chaque cockpit montrait l'initiale sur la
teinte du membre, même quand celui-ci a une photo de profil.

**Cause réelle.** Ni l'URL ni le chargement. `GET /championnats/{id}/classement` sert bien
`avatar_url`, `Membre` le décode, et `VueVoiture` sait découper la photo dans le cockpit
(disque teinté + initiale dessous, `AsyncImage` par-dessus, placeholder transparent qui
laisse l'initiale visible pendant le chargement et en cas d'erreur). **`VuePisteView` ne
passait simplement pas `photo:`** à `VueVoiture` — paramètre facultatif, donc aucune
erreur de compilation.

**Correctif.** `VuePisteView` passe `photo: placement.membre.avatarUrl`. Et
`Membre.avecVoiture(de:)` prend aussi la photo **du profil** pour la ligne du compte
connecté, comme le reste de sa voiture (§36).

### Ce qu'il ne faut pas refaire

- Un paramètre facultatif d'un composant partagé se vérifie **à chaque site d'appel** :
  l'oublier ne casse rien, ça éteint une fonction en silence.

---

## 38. Le podium en deux lignes restait gris, sans coche ni croix (`0.80.0`, `ios 0.42.0`)

**Symptôme.** Dans « Résultats par Grand Prix » (GP Azerbaïdjan, Team Bazzana), chaque
pilote du podium affichait ses points sur l'aplat beige de l'attente, là où les autres
pronostics du même membre étaient verts ou bordeaux.

**Cause réelle — deux, indépendantes.**

1. **La migration 27 n'était pas appliquée.** Le verdict de chaque pilote vient de
   `pronostic_podium.points_gagnes_1/2` ; la colonne n'existait pas en production
   (`42703` sur un `select` à la clé anonyme). Un podium jugé sans détail passe
   délibérément « en attente » (`metier.md` §2) — les écrans ne redéduisent jamais le
   verdict du total. Le code était juste, la base en retard.
2. **iOS n'avait pas de pictogramme dans cet écran.** `RangeePronostic` ne portait que la
   pastille de points ; le web y pose `Verdict` depuis longtemps. Aucun pronostic n'y avait
   donc de coche, podium ou non.

**Correctif.** Appliquer la migration 27 **avant** de déployer le backend `0.80.0` ; iOS
monte ``Verdict`` à côté de la pastille, comme ``ResultatsGPView`` et « Mes Grands Prix ».

### Ce qu'il ne faut pas refaire

- Devant un verdict « en attente » sur un pronostic jugé, **vérifier la colonne en base**
  avant de toucher au rendu : ajouter une déduction côté écran masquerait la migration
  manquante et créerait un second propriétaire du verdict.

## 39. `permission denied for table push_tokens` / `notifications_envoyees` (`0.84.0`)

**Symptôme.** Dans les logs Railway, le job de notifications échoue à chaque tour sur
`notifications_envoyees`, et `POST /push/token` sur `push_tokens` — `code 42501`. L'app
iOS reçoit `422`.

**Cause supposée, fausse : la clé anonyme.** Le backend appelle PostgREST avec la clé de
service sur toutes les tables (`supabase_client._entetes_service`) ; le job et la route ne
font pas exception. Le `422` n'est pas non plus un corps invalide : l'app envoie
`{"token": "<hex>", "langue": "fr"|"en"}`, conforme à `JetonPush` ; c'est le statut par
lequel `journaliser_echecs` transporte **toute** panne Supabase.

**Cause réelle.** `service_role` a `bypassrls`, **pas** les privilèges de table. La
migration 30 n'accordait rien à `service_role`, et ces deux tables n'ont pas reçu les
privilèges par défaut dont bénéficient les tables plus anciennes. `42501 permission
denied for table` est un refus de `grant`, pas de RLS.

**Correctif.** Migration 31 : `grant select, insert, update, delete … to service_role`
sur les deux tables.

### Ce qu'il ne faut pas refaire

- Créer une table sans `grant` explicite à `service_role` : ne pas compter sur les
  privilèges par défaut du projet.
- Lire un `422` d'une route décorée par `journaliser_echecs` comme une erreur de
  validation : la cause est dans les logs Railway, pas dans le corps envoyé.


## 40. « Réussis » du classement inférieur à « Mes Grands Prix » (migration 32)

**Symptôme.** Pour le même membre, le classement d'un championnat affiche « 8 réussis »
et « Mes Grands Prix » (iOS) davantage de pronos réussis.

**Causes supposées, fausses : le périmètre, ou un doublon de jointure.** Les deux comptent
les pronostics jugés du membre, tous championnats confondus (`metier.md` §6) ; le
classement ne joint rien qui puisse dupliquer une ligne, et « Mes Grands Prix » ne lit que
des GP pourvus de résultats, seuls à porter des points.

**Cause réelle : l'unité.** Le classement comptait les lignes de `pronostics` à
`points_gagnes > 0` — un podium valait 1. L'écran compte des lignes d'affichage
(`PronosticMembre.paris`) — depuis la migration 27, un podium détaillé en fait deux, une
par pilote. L'écart vaut exactement le nombre de podiums **entièrement** réussis.

**Correctif.** `reussites_du_pronostic(points, gain 1, gain 2)`, seule propriétaire de la
règle, lue par `classement_du_championnat`. Points inchangés ; à points égaux, le 2e
critère de départage peut réordonner deux membres.

### Ce qu'il ne faut pas refaire

- Recompter « réussis » ailleurs (`count(*) filter …`) : appeler la fonction.
- Changer l'unité de `GrandPrixJoue.reussis` sans toucher à la fonction, ou l'inverse.
- Rejouer la 18 (ou la 7, 8, 12, 16) après la 32 : le compteur par ligne revient.

## 41. iOS — carrousel « Mes Grands Prix » décentré avec un seul GP (`ios 0.57.4`)

**Symptôme.** Un seul GP joué : la carte est décalée de 80 pt vers la droite et sort de
l'écran ; un point de pagination seul sous elle. Deux GP ou plus : correct.

**Cause réelle.** `defaultScrollAnchor(.trailing)` est résolu au premier tour de mise en
page, quand `largeur` vaut encore 0 : le contenu ne fait que les 2 × 40 pt de marges, et
l'ancre de fin le colle à droite. Avec plusieurs cartes, `scrollPosition` recale ensuite ;
avec une seule, rien ne bouge. Prouvé au simulateur : sans l'ancre, la carte se centre.

**Correctif.** Une carte seule est posée hors de tout `ScrollView`, centrée, sans points de
pagination (masqués sous deux pages). Mesuré : 40 pt de chaque côté, tap → détail → retour.

### Ce qu'il ne faut pas refaire

- Tester un carrousel avec plusieurs éléments seulement : 0 et 1 sont des cas à part.

## 42. GP du Mexique 2026 : qualifications +2 h, course +1 h (migration 33)

**Symptôme.** Heures affichées 2 h trop tard pour les qualifications, 1 h pour la course.

**Cause supposée, fausse : le fuseau ou le changement d'heure.** Le Mexique est à UTC−6
toute l'année depuis 2022 (OpenF1 `gmt_offset -06:00`) ; l'affichage formate un instant
absolu dans le fuseau du téléphone, changement d'heure américain du 1ᵉʳ novembre compris.

**Cause réelle : deux heures LOCALES fausses**, recopiées en base et dans les deux tables
statiques — course à 15h00 (migration 19, « prévisionnelle ») au lieu de 14h00,
qualifications à 17h00 (migration 20, crue relevée) au lieu de 15h00. Instants officiels :
qualifications `2026-10-31T21:00Z`, course `2026-11-01T20:00Z`. Gravité : les pronostics
ferment à `date_course`, ils seraient restés ouverts pendant la première heure de course.

**Correctif.** Migration 33 (les deux instants faux exacts, rien d'autre) ;
`GP_2026` et `FichesGrandPrix.horaires`. Le scraper ne réécrit pas l'erreur : il n'écrit
les qualifications que si Unibet les publie, et la course depuis l'heure d'Unibet.
`test_horaires_2026.py` garde la concordance iOS = web et les heures locales.

### Ce qu'il ne faut pas refaire

- Prendre une heure « relevée » d'une migration pour acquise : la confronter à OpenF1
  (`/v1/sessions?year=…`), qui sert les instants officiels de toute la saison.

> **Brésil corrigé le 2026-10-29 (migration 34, web 0.87.5, iOS 0.57.5)** : week-end posé
> une semaine trop tard (13–15 novembre) partout, EL1 à 11h30 locale au lieu de 12h30 dans
> les deux tables statiques, course à 15h00 locale au lieu de 14h00 en base. Instants
> OpenF1 (meeting 1299) : EL1 `06T15:30Z`, EL2 `06T19:00Z`, EL3 `07T14:30Z`, qualifications
> `07T18:00Z`, course `08T17:00Z` ; UTC−3 sans heure d'été. **La migration doit passer
> avant qu'Unibet ouvre la page du GP** : le scraper rattache une ligne manuelle par date
> à ±3 jours (`FENETRE_WEEK_END`), puis par nom — à 7 jours d'écart et sous le nom
> « São Paulo », il créerait un doublon.
>
> **Écarts restants, relevés le 2026-10-27 contre OpenF1, NON corrigés** : Las Vegas,
> course `04:00Z`, en base `06:00Z` ; Qatar, course `16:00Z`, en base `17:00Z`. Les deux
> tables statiques ont déjà les bonnes heures pour ces deux GP.
