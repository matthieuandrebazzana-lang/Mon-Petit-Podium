/* global __APP_VERSION__ */

// Injecté par Vite depuis la version de package.json — source unique de vérité.
// À incrémenter à chaque commit qui modifie l'application (règle du CLAUDE.md).
export const APP_VERSION = __APP_VERSION__;

// En local, le backend FastAPI écoute sur le port 8000.
// En production, définir VITE_API_URL sur l'URL Railway.
export const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000";
