# Mon Petit Podium

PWA de pronostics Formule 1 entre amis.
Le contexte complet du projet — règles métier, design system, sources de données — est dans [CLAUDE.md](CLAUDE.md).

## Structure

| Dossier | Contenu |
|---|---|
| `frontend/` | React + Vite + Tailwind CSS, PWA — déployé sur Vercel |
| `backend/` | FastAPI — déployé sur Railway |
| `maquettes/` | Les 15 écrans de la v1, en HTML autonome |
| `assets/` | `voiture.svg` et `gp-cards.svg` |

## Lancer en local

Les deux serveurs tournent en parallèle, dans deux terminaux.

**Backend** — http://localhost:8000 (documentation sur `/docs`)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

**Frontend** — http://localhost:5173

```bash
cd frontend
npm install
npm run dev
```

L'accueil affiche l'état du backend : « En ligne » confirme que les deux se parlent.

## Variables d'environnement

Aucune n'est requise en local, les valeurs par défaut suffisent.

| Variable | Où | Rôle |
|---|---|---|
| `VITE_API_URL` | frontend, Vercel | URL de l'API Railway |
| `CORS_ORIGINS` | backend, Railway | Origines autorisées, dont l'URL Vercel |
| `ENVIRONMENT` | backend, Railway | `production` — masque aussi `/docs` |

Voir `backend/.env.example`. Les fichiers `.env` ne sont jamais versionnés.

## Version

Le numéro de version s'affiche en bas de l'écran d'accueil. Il vient de `frontend/package.json`
et doit être incrémenté à chaque commit qui modifie l'application, afin de vérifier
d'un coup d'œil qu'un déploiement Vercel est bien passé. Le miroir côté API est
`VERSION` dans `backend/app/config.py`.
