import adapter from '@sveltejs/adapter-vercel';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	kit: {
		// adapter-vercel emits Vercel serverless functions and static assets.
		// CI/CD: push to a Vercel-connected Git branch; no manual deploy step needed.
		adapter: adapter({
			// runtime: 'nodejs22.x',  // optional: pin Node.js runtime version
			// isr: { expiration: 60 } // optional: Incremental Static Regeneration
		})
	}
};

export default config;
