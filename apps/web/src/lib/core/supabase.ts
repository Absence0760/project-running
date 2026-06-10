import { createBrowserClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

export const supabase = createBrowserClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY);

// Dev-only test seam for the SSO e2e lane (tests-e2e/sso). The OAuth
// login path can only be driven against a mock OIDC provider, and the
// app UI has no Keycloak button (the mock provider stands in for Google,
// which GoTrue special-cases against real Google). Exposing the client
// lets the lane call signInWithOAuth({ provider: 'keycloak' }) against
// the real running app. `import.meta.env.DEV` is statically false in the
// adapter-static prod build, so the whole block — and the window
// reference — is tree-shaken out of anything shipped.
if (import.meta.env.DEV && typeof window !== 'undefined') {
	(window as unknown as { __supabase?: typeof supabase }).__supabase = supabase;
}
