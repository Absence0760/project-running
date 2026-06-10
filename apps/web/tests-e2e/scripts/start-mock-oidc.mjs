#!/usr/bin/env node
//
// Mock OIDC provider for the SSO e2e lane (apps/web, tests-e2e/sso).
//
// GoTrue accepts a generic `keycloak` external provider with a custom
// `url`, but it special-cases `google`/`apple` against the real Google/
// Apple — so the mock must masquerade as Keycloak. GoTrue's keycloak
// provider HARDCODES the endpoint paths off the configured url:
//   {url}/protocol/openid-connect/auth      (browser authorize redirect)
//   {url}/protocol/openid-connect/token     (server-side code exchange)
//   {url}/protocol/openid-connect/userinfo  (server-side identity fetch)
// oauth2-mock-server instead serves /authorize, /token, /userinfo. This
// launcher fronts the mock with a thin http server that rewrites the
// Keycloak path prefix onto the mock's paths, then delegates to the
// mock's request handler. Everything else (PKCE verification, the
// auto-redirect authorize, the signed token, the userinfo response) is
// the mock's own, unmodified.
//
// Networking: GoTrue runs inside the Supabase auth container and reaches
// the host via host.docker.internal (mapped to the host gateway). The
// browser (Chromium on the host) is sent to the SAME url by GoTrue's
// authorize redirect, so the SSO Playwright config launches Chromium
// with `--host-resolver-rules=MAP host.docker.internal 127.0.0.1`. The
// server therefore binds 0.0.0.0 and the configured url is
// http://host.docker.internal:PORT.
//
// The identity the mock issues starts from SSO_MOCK_OIDC_SUB /
// SSO_MOCK_OIDC_EMAIL and is switchable per-spec at runtime via
// POST /__identity (new-user vs returning-user cases need distinct subs).

import http from 'node:http';

import { OAuth2Server } from 'oauth2-mock-server';

const PORT = Number(process.env.SSO_MOCK_OIDC_PORT ?? '9888');

// The identity the mock issues. Mutable at runtime via POST /__identity
// so one mock instance can serve both the new-user and returning-user
// specs (each picks a distinct sub/email before initiating sign-in).
const identity = {
	sub: process.env.SSO_MOCK_OIDC_SUB ?? 'sso-e2e-default-sub',
	email: process.env.SSO_MOCK_OIDC_EMAIL ?? 'sso-e2e@example.com',
};

// The issuer URL GoTrue is configured with (config.toml keycloak `url`).
// host.docker.internal because GoTrue reaches the host from inside the
// auth container; the browser is sent here too and resolves it via the
// Chromium host-resolver-rules the SSO Playwright config sets. The mock
// stamps this as the `iss` claim and validates token requests against
// it, so it MUST equal what GoTrue calls — otherwise the token exchange
// fails with "Unknown issuer url".
const ISSUER = process.env.SSO_MOCK_OIDC_URL ?? `http://host.docker.internal:${PORT}`;

// GoTrue's keycloak provider prefixes every endpoint with this.
const KC_PREFIX = '/protocol/openid-connect';
const PATH_MAP = {
	[`${KC_PREFIX}/auth`]: '/authorize',
	[`${KC_PREFIX}/token`]: '/token',
	[`${KC_PREFIX}/userinfo`]: '/userinfo',
	[`${KC_PREFIX}/certs`]: '/jwks',
	[`${KC_PREFIX}/logout`]: '/endsession',
};

const server = new OAuth2Server();

await server.issuer.keys.generate('RS256');

// Front the mock with our own listener (below) instead of server.start(),
// so the issuer url is never auto-derived from the listen address — pin
// it to the value GoTrue uses.
server.issuer.url = ISSUER;

// Stamp the userinfo + token payload with the identity GoTrue will turn
// into a Supabase user. GoTrue's keycloak provider reads sub/email/
// email_verified/name off the userinfo response.
server.service.on('beforeUserinfo', (userInfoResponse) => {
	userInfoResponse.body = {
		sub: identity.sub,
		email: identity.email,
		email_verified: true,
		name: 'SSO E2E User',
	};
	userInfoResponse.statusCode = 200;
});

server.service.on('beforeTokenSigning', (token) => {
	token.payload.sub = identity.sub;
	token.payload.email = identity.email;
	token.payload.email_verified = true;
});

const mockHandler = server.service.requestHandler;

const front = http.createServer((req, res) => {
	const [path, query] = (req.url ?? '/').split('?');

	// Test-control endpoint: switch the issued identity between specs.
	if (path === '/__identity' && req.method === 'POST') {
		let raw = '';
		req.on('data', (c) => (raw += c));
		req.on('end', () => {
			try {
				const next = JSON.parse(raw || '{}');
				if (typeof next.sub === 'string') identity.sub = next.sub;
				if (typeof next.email === 'string') identity.email = next.email;
				res.writeHead(200, { 'content-type': 'application/json' });
				res.end(JSON.stringify(identity));
			} catch {
				res.writeHead(400).end('bad json');
			}
		});
		return;
	}

	const mapped = PATH_MAP[path];
	if (mapped) {
		req.url = query ? `${mapped}?${query}` : mapped;
	}
	mockHandler(req, res);
});

await new Promise((resolve) => front.listen(PORT, '0.0.0.0', resolve));

// eslint-disable-next-line no-console
console.log(`mock-oidc: listening on 0.0.0.0:${PORT} (sub=${identity.sub} email=${identity.email})`);

for (const sig of ['SIGINT', 'SIGTERM']) {
	process.on(sig, () => {
		front.close();
		server.stop().finally(() => process.exit(0));
	});
}
