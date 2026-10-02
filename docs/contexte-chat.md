# CONTEXTE GREED F1 — OCTOBRE 2026

Ce fichier est à coller au début d'un nouveau chat Claude pour reprendre le travail là où on s'est arrêtés.

## QUI EST MATTHIEU

Étudiant ingénieur ING3 à l'ECE Paris, en échange universitaire à Baruch College New York (septembre–décembre 2026). Construit Greed F1 comme projet personnel combinant ambition produit et développement full-stack. Recherche un stage de 5 semaines à partir de janvier 2027.

## C'EST QUOI GREED F1

Application web (PWA) + app native iOS. Permet à des amis de créer des championnats privés, inviter des membres via un code à 6 caractères, faire des pronostics avant chaque Grand Prix F1 en utilisant les vraies cotes bookmaker Unibet, et gagner des points selon les résultats réels.

URL production web : https://greed-f1.com (alias de greed-f1.vercel.app)
Version web actuelle : 0.87.2
Version backend actuelle : 0.82.1
Version iOS actuelle : 0.46.5

## STACK TECHNIQUE

Frontend : React, Vite, Tailwind CSS v4 → Vercel (greed-f1.com + greed-f1.vercel.app)
Backend : FastAPI → Railway (mon-petit-podium-production.up.railway.app)
Base de données : Supabase/PostgreSQL (projet ID: ycsxcythvtcruiomrgvv)
Auth : Supabase Auth — email/password + Google OAuth actif
Emails : Resend via SMTP Supabase, domaine greed-f1.com vérifié
App iOS : Swift 5.0, SwiftUI, iOS 17.0+, Xcode 26.6, simulateur iPhone 17 Pro iOS 26.5
Bundle ID : com.bazzana.greedf1, SDK Supabase Swift 2.55.2
Repo GitHub : monorepo (frontend/ + backend/ + ios/ + docs/)

## MÉTHODE DE TRAVAIL

Deux chats : Claude (décisions + prompts) / Claude Code terminal (code + commits)
Chaque prompt commence par "Lis CLAUDE.md et ios/CLAUDE.md."
Migrations Supabase : toujours appliquées manuellement dans le SQL Editor
Docker non disponible → migrations testées en production directement
29 migrations appliquées (la 29 : `20261001120000_rattachement_par_date`)
Après chaque session, Claude Code met à jour docs/contexte-chat.md
Versions : web, backend et iOS sont indépendantes — chacune ne bouge que si son code change (`CLAUDE.md` §7). `CLAUDE.md` §8 suit la version web

## COMPTE REVIEWER APP STORE

Email : matthieu.andre.bazzana+reviewer@gmail.com
Pseudo : Reviewer
Membre de : Team Bazzana (données réelles saison 2026)
Mot de passe : à noter séparément

## CE QUI EST FAIT — VERSION WEB (0.87.2)

Authentification email/password + Google OAuth + onboarding pseudo
Championnats privés avec photo, code d'invitation, classement
Vue piste avec algorithme de positionnement géométrique + résolution collisions
Personnalisation voiture : couleurs, numéro, skin écurie (11 livrées)
Pronostics : marchés par catégorie, paris bonus, flip clock countdown
Tableau des cotes avec couleurs d'écurie
Résultats GP : mes résultats + classement 20 pilotes
Résultats par GP dans un championnat (accordion par membre, podium pilote par pilote)
Calendrier avec drapeaux pays + tracés circuits
Historique GP par membre
Profil membre avec stats et voiture
Mode admin : scraper, toggle prévisualisation, alertes libellés non reconnus
PWA installable
Emails fonctionnels via Resend (mot de passe oublié)
Pages greed-f1.com/privacy, /terms, /contact
Landing page publique sur greed-f1.com
Suppression de compte (conformité App Store 5.1.1(v))
Drapeau, tracé et croisement du calendrier par date de course (0.87.2) : `slugDuGp` (`lib/calendrier2026.js`), date à ±3 jours puis nom — corrige « GP Bahrein » couru à Sepang

## CE QUI EST FAIT — VERSION iOS (0.46.5)

Navigation TabView 4 onglets (Accueil, Championnats, Calendrier, Profil)
AccueilView : widget GP navigable avec drapeau + tracé circuit
ChampionnatsView + ChampionnatDetailView : classement, vue piste kerbs pleine hauteur, résultats par GP
CalendrierView : 12 GP avec drapeau + tracé, statuts, scroll auto
ProfilView : stats, livrée voiture, picker skin, suppression compte
ProfilMembreView + HistoriqueGPView + ResultatsGPView
CreerChampionnatView + RejoindreChampionnatView
CotesView + PronosView + RecapView : flux complet pronos
Google OAuth : bouton sur Landing + Connexion, OnboardingView pseudo
Recadrage photo avant upload
Toutes les données branchées sur l'API réelle
Mention "Provisoire" sur les résultats provisoires
Localisation français/anglais (0.46.0) : dictionnaires Swift `Localisation/Traductions{FR,EN}.swift`, `t("clé")` / `tp("clé", n)`, détection au 1er lancement (français si téléphone en français, sinon anglais), choix manuel persisté, toggle FR/EN sur Landing, Connexion et Profil > Paramètres, dates dans la langue choisie, fr + en déclarés (Info.plist + knownRegions)
Sélecteur de langue retravaillé (0.46.1) : drapeaux emoji 🇫🇷 / 🇬🇧, segment actif en pastille pleine `primaire` + encre blanche, segment inactif sur fond neutre avec drapeau atténué (40 %, désaturé) et texte à 80 % (pas plus bas : 4,5:1 mesuré), pastille qui glisse en 200 ms (fondu sous mouvement réduit). Vérifié au simulateur sur Landing, Connexion et Profil > Paramètres
Drapeau, tracé et croisement du calendrier par date de course (0.46.2) : `SlugCircuit.de(_:dateCourse:)` (`Models/GrandPrix.swift`), date à ±3 jours puis nom — utilisé par `GrandPrixEnBase`, `ProchainGP` et `GrandPrixJoue` ; deux lignes au même week-end, le calendrier garde celle qui a des cotes. Corrige le widget du prochain GP vide pour « GP Bahrein » couru à Sepang. Vérifié au simulateur en FR et EN (Accueil, Calendrier, Profil)
Noms de GP, pays et circuits traduits (0.46.3) : clés `gp.<slug>.{pays,nom,court,circuit}` dans les deux dictionnaires, lues par `GrandPrixSaison` (plus rien d'écrit en dur dans la liste statique). Anglais au format « Malaysian GP », « Singapore GP ». Le nom affiché vient toujours du calendrier statique — `GrandPrixSaison.nomAffiche(slug:repli:)`, exposé en `nomAffiche` sur `GrandPrixEnBase`, `ProchainGP`, `GrandPrixPronos`, `GrandPrixDuChampionnat` ; le nom de la base ne sert qu'au rattachement. L'accueil dit donc « GP Malaisie » / « Malaysian GP » le 4 octobre, comme le calendrier. Vérifié au simulateur en FR et EN (widget Accueil, Calendrier, carte et fiche du 4 octobre)
Sélecteur de langue plus visible (0.46.4) : les deux options en couleur pleine quelle que soit la langue active (plus de désaturation ni d'opacité réduite sur le drapeau, libellé inactif en `secondaire` plein — `encreSegmentInactif`, 8,18:1 sur le beige, 9,22:1 sur le blanc) ; l'état ne se lit qu'à la pastille `#800111`. Segments 80 × 40 (au lieu de 62 × 32), drapeau 20 pt, code en `Font.segment` (Helvetica Neue Medium 14, nouveau jeton) ; glissement de la pastille conservé. Vérifié au simulateur sur Landing, Connexion (bascule en direct) et le bloc Paramètres du Profil (reproduit à l'identique, faute de session au simulateur), en FR et EN
En-tête de ChampionnatDetailView retravaillé (0.46.5) : trois colonnes centrées sur l'axe vertical — titre + membres/saison à gauche à leur largeur naturelle, photo carrée 56 pt (hauteur du bloc titre, rayon `champ`) au milieu, ⋯ à droite. Deux `Spacer` égaux placent la photo à équidistance du texte et du glyphe ⋯ (retrait de 12 pt du cadre tactile, pour mesurer au glyphe). Sans photo — et pendant son chargement — `PhotoChampionnat` peint l'initiale blanche sur `primaire` `#800111` (10,88:1) : une seule mise en page. Vérifié au simulateur avec photo, sans photo et avec un nom sur deux lignes (écarts égaux à 1–2 pt près)

## ÉVALUATION DES PRONOSTICS

Registre d'évaluateurs par slug exact (18 marchés couverts)
Statut : en_attente / non_evaluable / gagne / perdu
Pipeline provisoire (à l'arrivée) → définitif (J+1)
192 tests de non-régression backend
Identifiants canoniques des issues au figeage
Alertes admin (libellés non reconnus, échecs OpenF1)

## DOMAINE ET EMAILS

greed-f1.com acheté sur Porkbun
Resend configuré (domaine vérifié, DKIM/SPF/DMARC)
Supabase branché sur Resend via SMTP
Google OAuth branding validé et publié sur Google Cloud

## CE QUI RESTE À FAIRE

Bloquants App Store :

Sign in with Apple (bloqué — en attente compte Apple Developer 99€/an)
Screenshots finaux (iPhone + iPad)
Test iPad (ouvrir chaque écran sur simulateur iPad)

Fonctionnalités prévues :

Notifications push
f1-ml : modèle de prédiction ML à intégrer

Bugs connus :

Google OAuth iOS non encore testé sur iPhone réel

## SCRAPER ET OPÉRATIONS

Rattachement d'un GP Unibet (backend 0.82.1, `docs/decisions.md` §24) : identifiant Unibet, puis date de course à ±3 jours, puis nom en repli. Aucun candidat → GP nouveau, ligne créée. Deux candidats ou plus (ou une ligne réelle du même week-end sous un autre identifiant) → rien créé, alerte admin `grand_prix_ambigu`.
Le 4 octobre 2026 est le GP de Bahreïn délocalisé à Sepang : ligne unique `16a9c686-392a-4ef0-a624-f112825106d9`, nom Unibet « GP Bahrein », drapeau et tracé de Sepang (slug `malaisie`). Doublon avec la ligne manuelle « GP Malaisie » résorbé le 1er octobre par `adopter_grand_prix`.

Scraper (avec figeage) :
curl -X POST "https://mon-petit-podium-production.up.railway.app/scraper/declencher" -H "X-Admin-Secret: monpetitpodium2026"

Recalcul définitif d'un GP :
curl -X POST "https://mon-petit-podium-production.up.railway.app/jobs/resultats/{gp_id}/recalcul?relire=true" -H "X-Admin-Secret: monpetitpodium2026"

## VOCABULAIRE CANONIQUE

"championnat" jamais "ligue" — "calendrier" jamais "historique" — "paris bonus" jamais "favoris" — "pronostic" jamais "pari" dans le code — points toujours en entiers

====================================
FIN DU CONTEXTE
