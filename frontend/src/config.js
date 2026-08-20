/* global __APP_VERSION__ */

// Injecté par Vite depuis la version de package.json — source unique de vérité.
// À incrémenter à chaque commit qui modifie l'application (règle du CLAUDE.md).
export const APP_VERSION = __APP_VERSION__;

// En local, le backend FastAPI écoute sur le port 8000.
// En production, définir VITE_API_URL sur l'URL Railway.
export const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000";

// Secret partagé de l'en-tête `X-Admin-Secret`, attendu par les routes
// d'administration du backend (`POST /scraper/declencher`, `POST /jobs/...`).
//
// **Il n'est pas secret vis-à-vis du navigateur, et c'est structurel.** Vite
// remplace `import.meta.env.VITE_*` par sa valeur littérale **à la
// construction** : la chaîne part donc en clair dans le bundle JavaScript
// public, lisible par quiconque ouvre les outils de développement — que la
// section d'administration lui soit affichée ou non. `is_admin` ne referme rien
// de tout cela : il décide d'un affichage, pas d'un droit.
//
// Ce que cela protège encore : un passant qui ne lit pas le bundle, et les
// autres origines (le CORS du backend n'autorise que les nôtres). Ce que cela
// ne protège plus : un déclenchement de scraper par quelqu'un de déterminé.
// Le vrai remède, le jour où c'est inacceptable, est une route backend qui
// exige le JETON du membre et vérifie `is_admin` en base — le secret ne
// quitterait alors jamais Railway.
//
// Vide quand la variable n'est pas définie : l'écran le dit et n'envoie rien,
// plutôt que de partir chercher un 401.
export const ADMIN_SECRET = import.meta.env.VITE_ADMIN_SECRET ?? "";
