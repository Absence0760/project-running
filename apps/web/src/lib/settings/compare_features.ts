/**
 * Static feature comparison data for the /compare page. Kept in a
 * pure module (no DOM, no async) so unit tests can pin its shape and
 * catch silent regressions (e.g. someone changing a "yes" to a "no"
 * by mistake during a refactor).
 *
 * Source: Strava's published Pro / Free split as of mid-2026 plus our
 * own shipped feature set (see roadmap.md + parity.md). Update both
 * sides if either product changes its pricing.
 */

export type FeatureSupport = 'yes' | 'no' | 'partial';

export interface CompareRow {
	name: string;
	/** Our support level — almost everything should be "yes". */
	ours: FeatureSupport;
	stravaFree: FeatureSupport;
	stravaPro: FeatureSupport;
	/** Optional clarification line that renders under the row name. */
	note?: string;
}

export interface CompareSection {
	title: string;
	rows: CompareRow[];
}

export const COMPARE_SECTIONS: CompareSection[] = [
	{
		title: 'Recording + privacy',
		rows: [
			{ name: 'GPS run recording with auto-pause', ours: 'yes', stravaFree: 'yes', stravaPro: 'yes' },
			{
				name: 'Privacy zones (hide start / end of public tracks)',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
				note: 'Server-side clipping via SECURITY DEFINER RPC so zones never leave the database.',
			},
			{
				name: 'Live spectator tracking',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
				note: 'Strava paywalls Beacon. Free for us, always.',
			},
		],
	},
	{
		title: 'Analysis',
		rows: [
			{
				name: 'Heart-rate zones with time-in-zone breakdown',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Pace heatmap on the run map',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
				note: 'NRC-style pace-coloured polyline with age-band fade.',
			},
			{
				name: 'Best-effort detection (1k / 5k / 10k / HM / FM in a single run)',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Interactive elevation + pace chart',
				ours: 'yes',
				stravaFree: 'partial',
				stravaPro: 'yes',
			},
			{
				name: 'Personal-best route comparison',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Year-in-running recap',
				ours: 'yes',
				stravaFree: 'partial',
				stravaPro: 'yes',
				note: 'Strava ships an annual one. We ship a year-in-running page you can open any time.',
			},
		],
	},
	{
		title: 'Segments + leaderboards',
		rows: [
			{
				name: 'Segment leaderboards',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
			{
				name: 'Gender + age-band tiered leaderboards (KOM/QOM tiers)',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'KOM/QOM crowns on rank-1',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
		],
	},
	{
		title: 'Training',
		rows: [
			{
				name: 'AI-generated training plans',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Structured-workout execution (interval runner)',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Adherence feedback (planned vs actual)',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Fitness / Fatigue / Form (Training-load curves)',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Readiness-to-run score',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'no',
				note: 'Garmin and Whoop have this; Strava doesn’t.',
			},
		],
	},
	{
		title: 'Discovery + social',
		rows: [
			{
				name: 'Public route library + search',
				ours: 'yes',
				stravaFree: 'partial',
				stravaPro: 'yes',
			},
			{
				name: 'Popular-route heatmap',
				ours: 'yes',
				stravaFree: 'no',
				stravaPro: 'yes',
			},
			{
				name: 'Activity feed (people you follow)',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
			{
				name: 'Kudos + threaded comments',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
			{
				name: 'Clubs (browse + create + events + threaded posts)',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
		],
	},
	{
		title: 'Integration + data ownership',
		rows: [
			{
				name: 'Strava OAuth sync (in + out)',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
			{
				name: 'HealthKit / Health Connect import',
				ours: 'yes',
				stravaFree: 'partial',
				stravaPro: 'yes',
			},
			{
				name: 'Bulk export of everything (runs / routes / photos / plans)',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
			{
				name: 'Account deletion + data purge',
				ours: 'yes',
				stravaFree: 'yes',
				stravaPro: 'yes',
			},
		],
	},
];

export const COMPARE_HEADLINE = {
	usPrice: 'Free',
	stravaFreePrice: 'Free (limited)',
	// Strava's published US pricing; their prices vary by country and we
	// don't track them per-region, so it's explicitly labelled US to avoid
	// implying a localized figure. audit-findings 2026-05-30 Medium [regional].
	stravaProPrice: '$11.99/mo or $79.99/yr (US)',
} as const;
