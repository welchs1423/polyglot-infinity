import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';

// ---------------------------------------------------------------------------
// CORS / Proxy guide
// ---------------------------------------------------------------------------
// Problem: the browser blocks cross-origin requests when the SvelteKit dev
//   server (localhost:5173) calls the Go gateway (localhost:8080) without
//   CORS response headers on the backend.
//
// Solution A — backend CORS headers (recommended for production):
//   Add `Access-Control-Allow-Origin: *` (or the Vercel domain) to the Go
//   gateway's HTTP response headers.  No frontend change required.
//
// Solution B — Vite dev-server proxy (zero-backend-config for development):
//   Uncomment the `server.proxy` block below.  The Vite process forwards
//   /api/* requests to the gateway on behalf of the browser, so the browser
//   sees a same-origin response and no preflight is sent.
//   Set VITE_API_BASE_URL='' (empty) in .env when using this mode.
//
// Solution C — Vercel path rewrites (production, see vercel.json):
//   The `rewrites` rule in vercel.json proxies /api/* to YOUR_BACKEND_HOST
//   at the CDN edge. The browser sees same-origin responses; no CORS headers
//   needed on the backend and no extra round-trip latency.
// ---------------------------------------------------------------------------

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit()
	],

	// server block applies to the Vite dev server only; ignored by production builds.
	server: {
		// Solution B — uncomment to enable Vite proxy (dev CORS bypass):
		// proxy: {
		//   '/api': {
		//     target: 'http://localhost:8080',
		//     changeOrigin: true,
		//     // rewrite: (path) => path,  // path passthrough (no rewrite needed)
		//   },
		// },
	}
});
