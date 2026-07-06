// AWS Lambda Function URL handler for the shared entity-SSR surface.
//
// One HTML-only Lambda owning the four public /share/* entity paths, all
// routed here by CloudFront (see the share-entity behaviours in
// infra/modules/web-stack/main.tf):
//   - /share/event/<id>        public club event  → SportsEvent/Event JSON-LD
//   - /share/profile/<id>      public runner       → ProfilePage JSON-LD
//   - /share/club/<slug>       public club         → SportsOrganization JSON-LD
//   - /share/race/<id>         race-calendar entry → SportsEvent JSON-LD
//
// Each renders at request time so an entity created/edited after the last
// build still unfurls with the right per-entity <head> before a crawler or
// chat-app link-unfurler (which do not run the SPA's JS) can see it. Unlike
// share-run/route/badge/recap there is NO per-entity og:image PNG — the OG
// image is the branded card (or, for profiles/clubs, the avatar URL) — so
// this Lambda serves HTML only and needs no native rasteriser.
//
// Fail-open posture: a private / missing entity yields a 404 HTML with a
// noindex robots tag (a clean crawler signal), never a 5xx.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';

import { lookupSharedEvent } from '../../../src/lib/share/share_event_lookup';
import { lookupSharedProfile } from '../../../src/lib/share/share_profile_lookup';
import { lookupSharedClub } from '../../../src/lib/share/share_club_lookup';
import { lookupSharedRace } from '../../../src/lib/share/share_race_lookup';
import {
	buildShareEventHead,
	renderShareEventHeadTags,
} from '../../../src/lib/share/share_event_meta';
import {
	buildShareProfileHead,
	renderShareProfileHeadTags,
} from '../../../src/lib/share/share_profile_meta';
import {
	buildShareClubHead,
	renderShareClubHeadTags,
} from '../../../src/lib/share/share_club_meta';
import {
	buildShareRaceHead,
	renderShareRaceHeadTags,
} from '../../../src/lib/share/share_race_meta';
import { injectEntityHead } from '../../../src/lib/share/entity_spa_shell';

declare const __SPA_SHELL_HTML__: string;

const CACHE_CONTROL = 'public, max-age=300, s-maxage=300, stale-while-revalidate=60';

interface Config {
	supabaseUrl: string;
	supabaseAnonKey: string;
	siteUrl: string;
}

const ROUTES: Array<{
	re: RegExp;
	render: (key: string, config: Config) => Promise<string | null>;
}> = [
	{
		re: /^\/share\/event\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { event } = await lookupSharedEvent(id, c);
			if (!event) return null;
			return renderShareEventHeadTags(buildShareEventHead({ id, event, siteUrl: c.siteUrl }));
		},
	},
	{
		re: /^\/share\/profile\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { profile } = await lookupSharedProfile(id, c);
			if (!profile) return null;
			return renderShareProfileHeadTags(
				buildShareProfileHead({ id, profile, siteUrl: c.siteUrl }),
			);
		},
	},
	{
		re: /^\/share\/club\/([^/]+)\/?$/,
		render: async (slug, c) => {
			const { club } = await lookupSharedClub(slug, c);
			if (!club) return null;
			return renderShareClubHeadTags(buildShareClubHead({ slug, club, siteUrl: c.siteUrl }));
		},
	},
	{
		re: /^\/share\/race\/([^/]+)\/?$/,
		render: async (id, c) => {
			const { race } = await lookupSharedRace(id, c);
			if (!race) return null;
			return renderShareRaceHeadTags(buildShareRaceHead({ id, race, siteUrl: c.siteUrl }));
		},
	},
];

export const handler = async (
	event: LambdaFunctionURLEvent,
): Promise<LambdaFunctionURLResult> => {
	try {
		const config: Config = {
			supabaseUrl: process.env.PUBLIC_SUPABASE_URL ?? '',
			supabaseAnonKey: process.env.PUBLIC_SUPABASE_ANON_KEY ?? '',
			siteUrl: process.env.PUBLIC_SITE_URL ?? 'https://threkir.com',
		};
		const path = event.rawPath || '/';
		for (const route of ROUTES) {
			const match = path.match(route.re);
			if (!match) continue;
			const key = decodeURIComponent(match[1]);
			// A missing Supabase config or a private/missing entity both
			// resolve to the branded 404 (the render fn returns null).
			const headTags =
				config.supabaseUrl && config.supabaseAnonKey
					? await route.render(key, config)
					: null;
			if (!headTags) return html(404, notFoundHtml());
			return html(200, injectEntityHead(__SPA_SHELL_HTML__, headTags));
		}
		return json(404, { error: 'not found' });
	} catch (err) {
		console.error('[share-entity lambda] unhandled_error', {
			path: event.rawPath,
			message: err instanceof Error ? err.message : String(err),
			stack: err instanceof Error ? err.stack : undefined,
		});
		return json(503, { error: 'temporarily unavailable' });
	}
};

function html(statusCode: number, body: string): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': CACHE_CONTROL },
		body,
	};
}

function notFoundHtml(): string {
	return '<!doctype html><html><head><meta charset="utf-8"><title>Threkir</title><meta name="robots" content="noindex"></head><body><p>This link isn’t available.</p></body></html>';
}

function json(statusCode: number, body: unknown): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
	};
}
