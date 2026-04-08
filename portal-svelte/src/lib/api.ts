// Shared backend API base URL.
//
// Resolution order:
//   1. VITE_API_BASE_URL env variable (set in .env or .env.production)
//   2. Empty string — relies on Vite dev-server proxy (see vite.config.ts)
//      or Vercel rewrites (see vercel.json) to forward /api/* requests.
//
// Dev:        VITE_API_BASE_URL=http://localhost:8080  (.env)
//             All fetch calls resolve to http://localhost:8080/api/...
//
// Production: VITE_API_BASE_URL=                       (.env.production)
//             All fetch calls use a relative /api/... path;
//             Vercel rewrites proxy them to the deployed Go gateway.
export const API_BASE: string = import.meta.env.VITE_API_BASE_URL ?? '';
