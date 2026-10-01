# CONTEXTE GREED F1 — OCTOBRE 2026

Ce fichier est à coller au début d'un nouveau chat Claude pour reprendre le travail là où on s'est arrêtés.

## QUI EST MATTHIEU

Étudiant ingénieur ING3 à l'ECE Paris, en échange universitaire à Baruch College New York (septembre–décembre 2026). Construit Greed F1 comme projet personnel combinant ambition produit et développement full-stack. Recherche un stage de 5 semaines à partir de janvier 2027.

## C'EST QUOI GREED F1

Application web (PWA) + app native iOS. Permet à des amis de créer des championnats privés, inviter des membres via un code à 6 caractères, faire des pronostics avant chaque Grand Prix F1 en utilisant les vraies cotes bookmaker Unibet, et gagner des points selon les résultats réels.

URL production web : https://greed-f1.com (alias de greed-f1.vercel.app)
Version web actuelle : 0.87.2
Version iOS actuelle : 0.45.3

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
27 migrations appliquées
Après chaque session, Claude Code met à jour docs/contexte-chat.md

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

## CE QUI EST FAIT — VERSION iOS (0.45.3)

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

## ÉVALUATION DES PRONOSTICS

Registre d'évaluateurs par slug exact (18 marchés couverts)
Statut : en_attente / non_evaluable / gagne / perdu
Pipeline provisoire (à l'arrivée) → définitif (J+1)
169 tests de non-régression backend
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

Localisation français/anglais
Notifications push
f1-ml : modèle de prédiction ML à intégrer

Bugs connus :

Photo de championnat dans le header ChampionnatDetailView (layout à revoir)
"1 réussi" → accord au pluriel
Google OAuth iOS non encore testé sur iPhone réel

## SCRAPER ET OPÉRATIONS

Scraper (avec figeage) :
curl -X POST "https://mon-petit-podium-production.up.railway.app/scraper/declencher" -H "X-Admin-Secret: monpetitpodium2026"

Recalcul définitif d'un GP :
curl -X POST "https://mon-petit-podium-production.up.railway.app/jobs/resultats/{gp_id}/recalcul?relire=true" -H "X-Admin-Secret: monpetitpodium2026"

## VOCABULAIRE CANONIQUE

"championnat" jamais "ligue" — "calendrier" jamais "historique" — "paris bonus" jamais "favoris" — "pronostic" jamais "pari" dans le code — points toujours en entiers

====================================
FIN DU CONTEXTE
