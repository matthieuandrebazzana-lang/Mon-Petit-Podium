/* global __APP_VERSION__ */

// Injecté par Vite depuis la version de package.json — source unique de vérité.
// À incrémenter à chaque commit qui modifie l'application (règle du CLAUDE.md).
export const APP_VERSION = __APP_VERSION__;

// En local, le backend FastAPI écoute sur le port 8000.
// En production, définir VITE_API_URL sur l'URL Railway.
export const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000";

// **Aucun secret n'est exporté ici, et il ne faut pas en réintroduire.**
//
// `VITE_ADMIN_SECRET` a vécu à cette place jusqu'à la version `0.64.0`. Vite
// remplace `import.meta.env.VITE_*` par sa valeur littérale **à la
// construction** : toute valeur nommée `VITE_` part donc en clair dans le
// bundle JavaScript public, lisible par quiconque ouvre les outils de
// développement. Ce n'était pas un réglage à durcir, c'était un secret à
// retirer.
//
// Les actions d'administration passent désormais par `POST /admin/action`,
// fermée par le **jeton Supabase** du membre et une relecture de `is_admin` en
// base côté serveur (`lib/admin.js`). Le secret partagé existe toujours, mais
// il ne quitte plus jamais Railway.
//
// Les trois variables restantes sont publiques **par conception** :
// `VITE_SUPABASE_URL` et `VITE_SUPABASE_ANON_KEY` sont faites pour être
// exposées — c'est la RLS qui protège, jamais l'obscurité de la clé — et
// `VITE_API_URL` est l'adresse publique du backend. Rien d'autre ne doit
// prendre ce préfixe.
