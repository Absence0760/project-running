<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import { afterNavigate } from '$app/navigation';
	import { page } from '$app/stores';
	import {
		fetchPlan,
		fetchMyClubs,
		fetchRuns,
		publishPlanAsTemplate,
		updatePlanWorkout,
		updatePlanWeek,
		updatePlanMeta,
		duplicatePlanWeek,
	} from '$lib/core/data';
	import { shiftIsoDate, recoveryWorkoutPatch, recoveryWeekVolume } from '$lib/training/plan_bulk_ops';
	import { replanRemaining, type ReplanChange, type ReplanWeek } from '$lib/training/plan_replan';
	import {
		adaptiveReplanRemaining,
		type AdaptiveReason,
		type AdaptiveConfidence
	} from '$lib/training/plan_adaptive_replan';
	import WorkoutEditor from '$lib/components/WorkoutEditor.svelte';
	import PlanMetaEditor from '$lib/components/PlanMetaEditor.svelte';
	import PlanCalendar from '$lib/components/PlanCalendar.svelte';
	import RaceDayPanel from '$lib/components/RaceDayPanel.svelte';
	import { daysUntilRace } from '$lib/runs/race_day';
	import type { Run } from '$lib/types';
	import { showToast } from '$lib/stores/toast.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		addDays,
		fmtHms,
		isWorkoutCompleted,
		parseISO,
		todayISO
	} from '$lib/training/training';
	import { weeklyDrift, missedWorkoutAdvice } from '$lib/training/plan_adherence';
	import { orderedPlanPhases, longestCompletedLongRunMetres } from '$lib/training/plan_progress';
	import { planToMarkdown, planToJson, type ExportPlan } from '$lib/training/plan_serialize';
	import { workoutKindLabel, planPhaseLabel } from '$lib/training/workout_labels';
	import { fmtKm, fmtPace } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { loadSettings, effective } from '$lib/settings/settings';
	import type { WeekStart } from '$lib/format/calendar';
	import type { TrainingPlan, PlanWeek, PlanWorkout, ClubWithMeta } from '$lib/types';

	let id = $derived($page.params.id as string);
	let plan = $state<TrainingPlan | null>(null);
	let weeks = $state<PlanWeek[]>([]);
	let workouts = $state<PlanWorkout[]>([]);
	let loading = $state(true);
	let editing = $state<PlanWorkout | null>(null);

	let adminClubs = $state<ClubWithMeta[]>([]);
	let publishingTo = $state('');
	let editingPlanMeta = $state(false);
	let recentRuns = $state<Run[]>([]);
	let weekStart = $state<WeekStart>('monday');

	let isOwner = $derived(plan != null && plan.user_id === auth.user?.id);

	let showRaceDay = $derived.by(() => {
		if (!plan) return false;
		const days = daysUntilRace(plan.end_date, new Date());
		// Show within 21 days of race day (Strava's "race week" surface
		// is +/-14; we widen it slightly to cover a proper taper).
		return days >= 0 && days <= 21;
	});

	/// The user usually arrives here from /dashboard's plan-hero CTA or
	/// /plans. Honour the back-snapshot pattern so the parent's scroll +
	/// filter state survives a round trip. Captured on first afterNavigate
	/// so SvelteKit's own forward navigations inside this page don't
	/// overwrite the source.
	let backHref = $state('/plans');
	let backLabel = $state(m('planDetail.backAllPlans'));
	let cameFromKnownParent = $state(false);
	// /dashboard + /plans restore via history.back() (preserves the parent's
	// scroll + filter snapshot). The club Templates tab can't: history.back()
	// from a template chain can land on an unrelated surface (e.g. /runs), so
	// we navigate to the captured club URL explicitly instead.
	let backViaHistory = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromKnownParent || !from) return;
		if (from.url.pathname === '/dashboard') {
			backHref = '/dashboard';
			backLabel = m('planDetail.backDashboard');
			backViaHistory = true;
			cameFromKnownParent = true;
		} else if (from.url.pathname === '/plans') {
			backHref = '/plans';
			backLabel = m('planDetail.backAllPlans');
			backViaHistory = true;
			cameFromKnownParent = true;
		} else if (
			from.url.pathname.startsWith('/clubs/') &&
			from.url.searchParams.get('tab') === 'templates'
		) {
			backHref = from.url.pathname + from.url.search;
			backLabel = m('planDetail.backClubTemplates');
			cameFromKnownParent = true;
		}
	});

	/// Flatten the loaded plan + weeks + workouts into the export shape.
	function buildExport(): ExportPlan | null {
		if (!plan) return null;
		const weekIndexById = new Map<string, number>();
		for (const w of weeks) weekIndexById.set(w.id, w.week_index);
		return {
			name: plan.name,
			goalEvent: plan.goal_event,
			goalDistanceM: plan.goal_distance_m,
			goalTimeSec: plan.goal_time_seconds,
			startDate: plan.start_date,
			workouts: workouts.map((w) => ({
				week_index: weekIndexById.get(w.week_id) ?? 0,
				scheduled_date: w.scheduled_date,
				kind: w.kind,
				target_distance_m: w.target_distance_m,
				target_pace_sec_per_km: w.target_pace_sec_per_km,
				notes: w.notes,
			})),
		};
	}

	function planSlug(): string {
		return (
			(plan?.name ?? 'plan')
				.toLowerCase()
				.replace(/[^a-z0-9]+/g, '-')
				.replace(/^-|-$/g, '') || 'plan'
		);
	}

	function downloadFile(content: string, filename: string, type: string): void {
		const blob = new Blob([content], { type });
		const url = URL.createObjectURL(blob);
		const a = document.createElement('a');
		a.href = url;
		a.download = filename;
		a.click();
		URL.revokeObjectURL(url);
	}

	async function copyMarkdown(): Promise<void> {
		const e = buildExport();
		if (!e) return;
		try {
			await navigator.clipboard.writeText(planToMarkdown(e));
			showToast(m('planDetail.exportCopied'));
		} catch {
			// Clipboard blocked (insecure context / permission) — fall back
			// to a download so the export is never a dead end.
			downloadFile(planToMarkdown(e), `${planSlug()}.md`, 'text/markdown');
		}
	}

	function downloadMarkdown(): void {
		const e = buildExport();
		if (e) downloadFile(planToMarkdown(e), `${planSlug()}.md`, 'text/markdown');
	}

	function downloadJson(): void {
		const e = buildExport();
		if (e) downloadFile(planToJson(e), `${planSlug()}.json`, 'application/json');
	}

	// ─── Bulk editor ops (owner-only) ───
	let shiftDays = $state(7);
	let bulkBusy = $state(false);

	/// Move every workout + the plan's start/end by ±N days (race moved,
	/// runner started a week late, …). Orchestrated client-side: one
	/// update per workout then the plan meta; on partial failure the
	/// reload surfaces the real server state.
	async function shiftPlan(): Promise<void> {
		if (!plan || bulkBusy || !shiftDays) return;
		bulkBusy = true;
		try {
			await Promise.all(
				workouts.map((w) =>
					updatePlanWorkout(w.id, { scheduled_date: shiftIsoDate(w.scheduled_date, shiftDays) }),
				),
			);
			await updatePlanMeta(plan.id, {
				start_date: shiftIsoDate(plan.start_date, shiftDays),
				end_date: shiftIsoDate(plan.end_date, shiftDays),
			});
			showToast(m('planDetail.shiftDone', { n: Math.abs(shiftDays) }));
			await load();
		} catch (e) {
			showToast(m('planDetail.bulkFailed', { error: String(e) }), 'error');
		} finally {
			bulkBusy = false;
		}
	}

	/// Turn a week into a recovery / step-back week: scale its volume +
	/// every non-rest/non-race workout to ~60% and convert quality
	/// sessions to easy recovery runs.
	async function markWeekRecovery(week: PlanWeek): Promise<void> {
		if (bulkBusy) return;
		bulkBusy = true;
		try {
			const weekWorkouts = workoutsByWeek.get(week.id) ?? [];
			await Promise.all(
				weekWorkouts.map((w) => {
					const patch = recoveryWorkoutPatch(w);
					return patch ? updatePlanWorkout(w.id, patch) : Promise.resolve();
				}),
			);
			await updatePlanWeek(week.id, { target_volume_m: recoveryWeekVolume(week.target_volume_m) });
			showToast(m('planDetail.recoveryDone'));
			await load();
		} catch (e) {
			showToast(m('planDetail.bulkFailed', { error: String(e) }), 'error');
		} finally {
			bulkBusy = false;
		}
	}

	/// Duplicate a week: insert a copy right after it, pushing every later
	/// week + the plan end date back by 7 days. The (plan_id, week_index)
	/// re-index is atomic server-side (duplicate_plan_week RPC) — a
	/// client-side multi-update would transiently break the unique index.
	async function duplicateWeek(week: PlanWeek): Promise<void> {
		if (bulkBusy) return;
		bulkBusy = true;
		try {
			await duplicatePlanWeek(plan!.id, week.week_index);
			showToast(m('planDetail.duplicateWeekDone', { n: week.week_index + 1 }));
			await load();
		} catch (e) {
			showToast(m('planDetail.bulkFailed', { error: String(e) }), 'error');
		} finally {
			bulkBusy = false;
		}
	}

	// ─── Re-plan around missed sessions (owner-only) ───
	let replanPreview = $state<ReplanChange[] | null>(null);
	// Set only when the CURRENT preview came from the adaptive (trend-based)
	// path, so its header can explain the multi-week reason + confidence.
	let adaptiveInfo = $state<{ reason: AdaptiveReason; confidence: AdaptiveConfidence } | null>(null);

	/// Assemble the pure engine's input from the loaded plan + the runs
	/// window. Per-week planned volume, actual mileage (runs dated in the
	/// week), completion + past flags.
	function buildReplanInput(): ReplanWeek[] {
		if (!plan) return [];
		const todayD = parseISO(today);
		return weeks.map((w) => {
			const weekWorkouts = workoutsByWeek.get(w.id) ?? [];
			let planned = w.target_volume_m ?? 0;
			if (!(planned > 0)) {
				planned = weekWorkouts.reduce(
					(s, x) => s + (x.kind !== 'rest' ? (x.target_distance_m ?? 0) : 0),
					0,
				);
			}
			const weekStartD = addDays(parseISO(plan!.start_date), w.week_index * 7);
			const weekEndD = addDays(weekStartD, 7);
			let actual = 0;
			for (const r of recentRuns) {
				const t = new Date(r.started_at);
				if (t >= weekStartD && t < weekEndD) actual += r.distance_m ?? 0;
			}
			return {
				weekIndex: w.week_index,
				phase: w.phase,
				plannedMetres: planned,
				actualMetres: actual,
				isComplete: weekEndD <= todayD,
				workouts: weekWorkouts.map((x) => ({
					id: x.id,
					scheduledDate: x.scheduled_date,
					kind: x.kind,
					targetDistanceM: x.target_distance_m,
					completed: isWorkoutCompleted(x),
					isPast: x.scheduled_date < today,
				})),
			};
		});
	}

	function proposeReplan(): void {
		if (!plan || !isOwner || bulkBusy) return;
		const { changes, onTrack } = replanRemaining({ weeks: buildReplanInput(), today });
		if (onTrack || changes.length === 0) {
			showToast(m('planDetail.replanOnTrack'));
			replanPreview = null;
			adaptiveInfo = null;
			return;
		}
		adaptiveInfo = null;
		replanPreview = changes;
	}

	/// Adaptive (trend-based) re-plan: only proposes when the last few
	/// completed weeks show a sustained drift, suppressing single-week noise.
	function proposeAdaptiveReplan(): void {
		if (!plan || !isOwner || bulkBusy) return;
		const r = adaptiveReplanRemaining({ weeks: buildReplanInput(), today });
		if (r.reason === 'on_track') {
			showToast(m('planDetail.adaptiveOnTrack'));
			replanPreview = null;
			adaptiveInfo = null;
			return;
		}
		if (r.changes.length === 0) {
			// A real multi-week trend, but the conservative rules prescribe no
			// safe change (e.g. under-running easy volume is never crammed).
			showToast(m('planDetail.adaptiveNoSafeChange'));
			replanPreview = null;
			adaptiveInfo = null;
			return;
		}
		adaptiveInfo = { reason: r.reason, confidence: r.confidence };
		replanPreview = r.changes;
	}

	function adaptiveBadgeText(info: { reason: AdaptiveReason; confidence: AdaptiveConfidence }): string {
		const reason =
			info.reason === 'trend_underfitness'
				? m('planDetail.adaptiveReasonUnder')
				: m('planDetail.adaptiveReasonOver');
		const confidence =
			info.confidence === 'high'
				? m('planDetail.adaptiveConfidenceHigh')
				: m('planDetail.adaptiveConfidenceMedium');
		return m('planDetail.adaptiveBadge', { reason, confidence });
	}

	async function applyReplan(): Promise<void> {
		if (!replanPreview || bulkBusy) return;
		bulkBusy = true;
		try {
			await Promise.all(
				replanPreview.map((c) =>
					updatePlanWorkout(c.workoutId, { target_distance_m: c.toMetres }),
				),
			);
			showToast(m('planDetail.replanApplied', { n: replanPreview.length }));
			replanPreview = null;
			adaptiveInfo = null;
			await load();
		} catch (e) {
			showToast(m('planDetail.bulkFailed', { error: String(e) }), 'error');
		} finally {
			bulkBusy = false;
		}
	}

	/// Human label for a proposed change row in the preview.
	function replanChangeLabel(c: ReplanChange): string {
		const from = fmtKm(c.fromMetres);
		const to = fmtKm(c.toMetres);
		return c.reason === 'make_up_long'
			? m('planDetail.replanMakeUp', { from, to })
			: m('planDetail.replanEase', { from, to });
	}

	function handleBack(e: MouseEvent): void {
		if (cameFromKnownParent && backViaHistory) {
			e.preventDefault();
			history.back();
		}
	}

	async function load() {
		loading = true;
		const res = await fetchPlan(id);
		plan = res.plan;
		weeks = res.weeks;
		workouts = res.workouts;
		loading = false;
		if (plan != null && plan.user_id === auth.user?.id) {
			// Owner-only: the recent runs feed both the Race Day Riegel
			// projection (within 21 days) and the current-week adherence
			// drift flag (any time). 50 covers a heavy week comfortably.
			recentRuns = await fetchRuns({ limit: 50 });
		}
	}

	onMount(async () => {
		// Same poll-for-auth shape as /runs/[id], /routes/[id], etc.
		// auth-store flips loading=false before fetchUser resolves, so
		// the publish-as-template gate below must wait for `auth.user`
		// to actually be set or the admin-clubs fetch silently no-ops
		// for the plan owner.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
		// Calendar week-start follows the user's preference (W-5/W-14).
		if (auth.user?.id) {
			try {
				const settings = await loadSettings(auth.user.id);
				const wsd = effective<string>(settings, 'week_start_day');
				if (wsd === 'sunday' || wsd === 'monday') weekStart = wsd;
			} catch (_) {
				/* default Monday */
			}
		}
		// Only owners-of-this-plan see the publish-as-template control,
		// and only when they have at least one club they admin.
		if (auth.user?.id && plan?.user_id === auth.user.id) {
			const clubs = await fetchMyClubs();
			adminClubs = clubs.filter(
				(c) => c.viewer_role === 'owner' || c.viewer_role === 'admin'
			);
		}
	});

	async function publishAsTemplate() {
		if (!plan || !publishingTo) return;
		try {
			await publishPlanAsTemplate(plan.id, publishingTo);
			showToast(m('planDetail.publishSuccess'));
			publishingTo = '';
			// No reload needed — the source plan stayed put. The new
			// template lives on the club's Templates tab.
		} catch (e) {
			showToast(m('planDetail.publishFailed', { error: String(e) }), 'error');
		}
	}

	let workoutsByWeek = $derived.by(() => {
		const m = new Map<string, PlanWorkout[]>();
		for (const w of workouts) {
			const list = m.get(w.week_id) ?? [];
			list.push(w);
			m.set(w.week_id, list);
		}
		return m;
	});

	let today = $derived(todayISO());

	let todayWorkout = $derived(
		workouts.find((w) => w.scheduled_date === today) ?? null
	);

	/// When today is between plans (rest day or pre-start), fall back to
	/// the next scheduled non-rest workout so the primary card always
	/// answers "what's next?" instead of silently vanishing.
	let nextWorkout = $derived.by(() => {
		if (todayWorkout) return null;
		return workouts.find((w) => w.scheduled_date > today && w.kind !== 'rest') ?? null;
	});

	let currentWeekIndex = $derived.by(() => {
		if (!plan) return null;
		const dayIndex = Math.floor(
			(parseISO(today).getTime() - parseISO(plan.start_date).getTime()) /
				(1000 * 60 * 60 * 24)
		);
		if (dayIndex < 0) return 0;
		return Math.min(weeks.length - 1, Math.floor(dayIndex / 7));
	});

	/// Race-date relation derived from start/end in the plan's local-date
	/// frame. Mirrors the dashboard plan-hero so the two surfaces agree.
	let planPosition = $derived.by(() => {
		if (!plan) return null;
		const start = parseISO(plan.start_date);
		const end = parseISO(plan.end_date);
		const t = parseISO(today);
		const dayMs = 86_400_000;
		const totalWeeks = weeks.length > 0 ? weeks.length : 1;
		const weekIndex = (currentWeekIndex ?? 0) + 1;
		const totalDays = Math.max(1, Math.round((end.getTime() - start.getTime()) / dayMs) + 1);
		let calendarPct: number;
		if (t <= start) calendarPct = 0;
		else if (t >= end) calendarPct = 100;
		else calendarPct = Math.round(((t.getTime() - start.getTime()) / (end.getTime() - start.getTime())) * 100);
		let relation: string;
		let raceState: 'upcoming' | 'today' | 'past';
		if (t < start) {
			const d = Math.round((start.getTime() - t.getTime()) / dayMs);
			relation = d === 1 ? m('planDetail.startsTomorrow') : m('planDetail.startsInDays', { d });
			raceState = 'upcoming';
		} else if (t > end) {
			relation = m('planDetail.raceDayPast');
			raceState = 'past';
		} else {
			const d = Math.round((end.getTime() - t.getTime()) / dayMs);
			if (d === 0) {
				relation = m('planDetail.raceDay');
				raceState = 'today';
			} else if (d === 1) {
				relation = m('planDetail.raceTomorrow');
				raceState = 'upcoming';
			} else {
				relation = m('planDetail.raceInDays', { d });
				raceState = 'upcoming';
			}
		}
		return { weekIndex, totalWeeks, totalDays, calendarPct, relation, raceState };
	});

	let completed = $derived(workouts.filter(isWorkoutCompleted).length);
	let totalActive = $derived(workouts.filter((w) => w.kind !== 'rest').length);
	let pct = $derived(totalActive === 0 ? 0 : Math.round((completed / totalActive) * 100));

	let currentWeek = $derived(
		currentWeekIndex != null ? (weeks[currentWeekIndex] ?? null) : null
	);

	/// Overall phase arc (base→build→peak→taper→race) the plan moves
	/// through + which one the current week sits in.
	let orderedPhases = $derived(orderedPlanPhases(weeks));
	let currentPhase = $derived(currentWeek?.phase ?? null);

	/// Longest long run completed so far — actual distance when the
	/// linked run is in the recent window, else the planned target.
	let longestLongRunMetres = $derived.by(() => {
		const actualById = new Map<string, number>();
		for (const r of recentRuns) actualById.set(r.id, r.distance_m ?? 0);
		return longestCompletedLongRunMetres(workouts, actualById);
	});

	/// Current-week mileage drift vs plan. Owner-only (needs the runs
	/// list). Planned volume is the week's target, falling back to the
	/// sum of its non-rest workouts' distances; actual is every run dated
	/// inside the week window. Null unless the drift trips the flag.
	let currentWeekDrift = $derived.by(() => {
		if (!plan || !isOwner || currentWeek == null || currentWeekIndex == null) return null;
		const weekWorkouts = workoutsByWeek.get(currentWeek.id) ?? [];
		let planned = currentWeek.target_volume_m ?? 0;
		if (!(planned > 0)) {
			planned = weekWorkouts.reduce(
				(s, w) => s + (w.kind !== 'rest' ? (w.target_distance_m ?? 0) : 0),
				0
			);
		}
		const weekStartD = addDays(parseISO(plan.start_date), currentWeekIndex * 7);
		const weekEndD = addDays(weekStartD, 7);
		let actual = 0;
		for (const r of recentRuns) {
			const t = new Date(r.started_at);
			if (t >= weekStartD && t < weekEndD) actual += r.distance_m ?? 0;
		}
		const d = weeklyDrift(planned, actual);
		return d.flagged ? d : null;
	});

	/// A long run in the current week that's already in the past and
	/// still uncompleted → a make-up / skip recommendation driven by
	/// phase + whether a step-back week (a >15% volume drop next week) is
	/// about to absorb the deficit.
	let missedLongRun = $derived.by(() => {
		if (!plan || !isOwner || currentWeek == null || currentWeekIndex == null) return null;
		const weekWorkouts = workoutsByWeek.get(currentWeek.id) ?? [];
		const missed = weekWorkouts.find(
			(w) => w.kind === 'long' && w.scheduled_date < today && !isWorkoutCompleted(w)
		);
		if (!missed) return null;
		const nextWeek = weeks[currentWeekIndex + 1] ?? null;
		const recoveryWeekImminent =
			nextWeek != null &&
			nextWeek.target_volume_m != null &&
			currentWeek.target_volume_m != null &&
			nextWeek.target_volume_m < currentWeek.target_volume_m * 0.85;
		return missedWorkoutAdvice({
			kind: 'long',
			isTaper: currentWeek.phase === 'taper' || currentWeek.phase === 'race',
			recoveryWeekImminent,
		});
	});

	/// Pre-compute the conic-gradient stop so the progress ring renders
	/// as a real fill, not a static border. The static `5px` border was
	/// indistinguishable from a chrome flourish.
	let progressGradient = $derived(
		`conic-gradient(var(--color-primary) ${pct * 3.6}deg, color-mix(in srgb, var(--color-primary) 14%, var(--color-border)) 0deg)`
	);

	const kindColor: Record<string, string> = {
		easy: 'var(--color-text-secondary)',
		long: 'var(--color-primary)',
		recovery: 'var(--color-text-tertiary)',
		tempo: '#C98ECF',
		interval: '#D97A54',
		marathon_pace: '#E6A96B',
		race: 'var(--color-primary)',
		rest: 'var(--color-border)'
	};

	function dayOfWeek(iso: string): string {
		const keys = [
			'planDetail.dowSun',
			'planDetail.dowMon',
			'planDetail.dowTue',
			'planDetail.dowWed',
			'planDetail.dowThu',
			'planDetail.dowFri',
			'planDetail.dowSat'
		] as const;
		return m(keys[parseISO(iso).getDay()]);
	}

	function fmtRaceDate(iso: string): string {
		const [y, m, d] = iso.split('-').map(Number);
		const dt = new Date(y, (m ?? 1) - 1, d ?? 1);
		return dt.toLocaleDateString(activeFormatLocale(), { day: 'numeric', month: 'short', year: 'numeric' });
	}

	function workoutAriaLabel(wo: PlanWorkout): string {
		const dow = dayOfWeek(wo.scheduled_date);
		const kind = workoutKindLabel(wo.kind);
		const dist = wo.target_distance_m != null ? `, ${fmtKm(wo.target_distance_m)}` : '';
		const done = isWorkoutCompleted(wo) ? m('planDetail.ariaCompletedSuffix') : '';
		return `${dow}: ${kind}${dist}${done}`;
	}
</script>

{#if loading}
	<div class="page" aria-busy="true" aria-label={m('planDetail.loadingPlan')}>
		<div class="back-skel skeleton-shimmer"></div>
		<div class="hero-skel skeleton-shimmer"></div>
		<div class="today-skel skeleton-shimmer"></div>
		<div class="week-skel skeleton-shimmer"></div>
		<div class="week-skel skeleton-shimmer"></div>
		<div class="week-skel skeleton-shimmer"></div>
	</div>
{:else if !plan}
	<div class="page">
		<a class="back" href={backHref} onclick={handleBack}>
			<span class="material-symbols">arrow_back</span>
			{backLabel}
		</a>
		<div class="empty">
			<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
			<h3>{m('planDetail.notFoundTitle')}</h3>
			<p>{m('planDetail.notFoundBody')}</p>
			<a href="/plans" class="btn btn-primary">{m('planDetail.backToYourPlans')}</a>
		</div>
	</div>
{:else}
	<div class="page">
		<a class="back" href={backHref} onclick={handleBack}>
			<span class="material-symbols">arrow_back</span>
			{backLabel}
		</a>

		<header class="hero" class:race-today={planPosition?.raceState === 'today'}>
			<div class="hero-body">
				<span class="hero-eyebrow">{m('planDetail.heroEyebrow')}</span>
				<div class="hero-title-row">
					<h1>{plan.name}</h1>
					{#if isOwner && !plan.is_template}
						<button
							type="button"
							class="btn btn-outline btn-sm hero-edit"
							aria-label={m('planDetail.editPlanAria')}
							onclick={() => (editingPlanMeta = true)}
						>
							<span class="material-symbols">edit</span>
							{m('planDetail.editPlan')}
						</button>
					{/if}
					{#if isOwner && workouts.length > 0}
						<details class="export-menu">
							<summary class="btn btn-outline btn-sm">
								<span class="material-symbols">ios_share</span>
								{m('planDetail.export')}
							</summary>
							<div class="export-actions" role="menu">
								<button type="button" role="menuitem" onclick={copyMarkdown}>
									{m('planDetail.exportCopyMarkdown')}
								</button>
								<button type="button" role="menuitem" onclick={downloadMarkdown}>
									{m('planDetail.exportDownloadMarkdown')}
								</button>
								<button type="button" role="menuitem" onclick={downloadJson}>
									{m('planDetail.exportDownloadJson')}
								</button>
							</div>
						</details>
					{/if}
				</div>
				<div class="hero-chips">
					{#if plan.parent_template_id}
						<a class="chip chip-link" href="/plans/{plan.parent_template_id}">
							<span class="material-symbols">link</span>
							{m('planDetail.clonedFromTemplate')}
						</a>
					{/if}
					{#if plan.is_template && plan.club_id}
						<span class="chip">
							<span class="material-symbols">groups</span>
							{m('planDetail.clubTemplate')}
						</span>
					{/if}
				</div>
				<div class="meta">
					<span>
						<span class="material-symbols">flag</span>
						{fmtKm(plan.goal_distance_m, 1)}
					</span>
					{#if plan.goal_time_seconds}
						<span>
							<span class="material-symbols">timer</span>
							{fmtHms(plan.goal_time_seconds)}
						</span>
					{/if}
					{#if plan.vdot}
						<span>
							<span class="material-symbols">trending_up</span>
							VDOT {Number(plan.vdot).toFixed(1)}
						</span>
					{/if}
					{#if planPosition}
						<span>
							<span class="material-symbols">event</span>
							{fmtRaceDate(plan.end_date)}
						</span>
					{/if}
				</div>
			</div>
			<div class="hero-position">
				{#if planPosition}
					<span class="week-pill">
						{m('planDetail.weekPillPrefix', { n: planPosition.weekIndex })} <em>{m('planDetail.weekPillOf', { total: planPosition.totalWeeks })}</em>
					</span>
					<span
						class="relation-pill"
						class:race-today={planPosition.raceState === 'today'}
						class:race-past={planPosition.raceState === 'past'}
					>
						{planPosition.relation}
					</span>
				{/if}
				<div
					class="progress-ring"
					style="background: {progressGradient}"
					role="progressbar"
					aria-label={m('planDetail.workoutCompletionAria')}
					aria-valuemin="0"
					aria-valuemax="100"
					aria-valuenow={pct}
				>
					<div class="progress-inner">
						<span class="pct">{pct}%</span>
						<span class="done">{completed} / {totalActive}</span>
					</div>
				</div>
			</div>
		</header>

		{#if planPosition}
			<div class="calendar-bar" aria-hidden="true">
				<span
					class="calendar-fill"
					style="width: {planPosition.calendarPct}%"
				></span>
			</div>
		{/if}

		{#if orderedPhases.length > 1 || longestLongRunMetres != null}
			<section class="plan-progress">
				{#if orderedPhases.length > 1}
					<ol class="phase-marker" aria-label={m('planDetail.phaseMarkerAria')}>
						{#each orderedPhases as ph (ph)}
							<li class="phase-step" class:active={ph === currentPhase}>
								{planPhaseLabel(ph)}
							</li>
						{/each}
					</ol>
				{/if}
				{#if longestLongRunMetres != null}
					<div class="longest-long" title={m('planDetail.longestLongRun')}>
						<span class="material-symbols">trending_up</span>
						<span class="longest-label">{m('planDetail.longestLongRun')}</span>
						<span class="longest-value">{fmtKm(longestLongRunMetres)}</span>
					</div>
				{/if}
			</section>
		{/if}

		{#if currentWeekDrift || missedLongRun}
			<section class="adherence" aria-label={m('planDetail.adherenceAria')}>
				{#if currentWeekDrift}
					<p class="adherence-flag drift-{currentWeekDrift.direction}">
						<span class="material-symbols">monitoring</span>
						{currentWeekDrift.direction === 'over'
							? m('planDetail.driftOverFlag', {
									pct: Math.round(currentWeekDrift.driftFraction * 100)
								})
							: m('planDetail.driftUnderFlag', {
									pct: Math.round(Math.abs(currentWeekDrift.driftFraction) * 100)
								})}
					</p>
				{/if}
				{#if missedLongRun}
					<p class="adherence-flag missed-{missedLongRun.recommendation}">
						<span class="material-symbols">event_busy</span>
						{missedLongRun.reason === 'taper'
							? m('planDetail.missedLongTaper')
							: missedLongRun.reason === 'recovery_soon'
								? m('planDetail.missedLongRecovery')
								: m('planDetail.missedLongMakeUp')}
					</p>
				{/if}
			</section>
		{/if}

		{#if Array.isArray(plan.rules) && plan.rules.length > 0}
			<aside class="rules-card">
				<h3>{m('planDetail.rulesTitle')}</h3>
				<ul>
					{#each plan.rules as r}
						<li>{r}</li>
					{/each}
				</ul>
			</aside>
		{/if}

		{#if showRaceDay && plan != null}
			<RaceDayPanel
				raceDate={plan.end_date}
				distanceM={plan.goal_distance_m}
				goalTimeSec={plan.goal_time_seconds}
				{recentRuns}
			/>
		{/if}

		{#if todayWorkout}
			<section class="today">
				<button
					class="today-link"
					type="button"
					aria-label={m('planDetail.editTodayWorkoutAria', { kind: workoutKindLabel(todayWorkout.kind) })}
					onclick={() => (editing = todayWorkout)}
				>
					<div class="today-icon" class:done={isWorkoutCompleted(todayWorkout)}>
						{#if isWorkoutCompleted(todayWorkout)}
							<span class="material-symbols">check_circle</span>
						{:else if todayWorkout.kind === 'rest'}
							<span class="material-symbols">self_improvement</span>
						{:else}
							<span class="material-symbols">directions_run</span>
						{/if}
					</div>
					<div class="today-body">
						<span class="today-label">{m('planDetail.today')}</span>
						<span class="today-kind">
							{workoutKindLabel(todayWorkout.kind)}
						</span>
						<div class="today-meta">
							{#if todayWorkout.target_distance_m != null}
								<span>{fmtKm(todayWorkout.target_distance_m)}</span>
							{/if}
							{#if todayWorkout.target_pace_sec_per_km}
								<span>@ {fmtPace(todayWorkout.target_pace_sec_per_km)}</span>
							{/if}
							{#if isWorkoutCompleted(todayWorkout)}
								<span class="today-done">{m('planDetail.completed')}</span>
							{/if}
						</div>
						{#if todayWorkout.notes}
							<p class="today-notes">{todayWorkout.notes}</p>
						{/if}
					</div>
					<span class="material-symbols today-arrow">chevron_right</span>
				</button>
			</section>
		{:else if nextWorkout}
			<section class="today">
				<button
					class="today-link"
					type="button"
					aria-label={m('planDetail.editNextWorkoutAria')}
					onclick={() => (editing = nextWorkout)}
				>
					<div class="today-icon">
						<span class="material-symbols">event_upcoming</span>
					</div>
					<div class="today-body">
						<span class="today-label">{m('planDetail.nextUp')}</span>
						<span class="today-kind">
							{workoutKindLabel(nextWorkout.kind)}
						</span>
						<div class="today-meta">
							<span>{dayOfWeek(nextWorkout.scheduled_date)} · {nextWorkout.scheduled_date}</span>
							{#if nextWorkout.target_distance_m != null}
								<span>{fmtKm(nextWorkout.target_distance_m)}</span>
							{/if}
							{#if nextWorkout.target_pace_sec_per_km}
								<span>@ {fmtPace(nextWorkout.target_pace_sec_per_km)}</span>
							{/if}
						</div>
					</div>
					<span class="material-symbols today-arrow">chevron_right</span>
				</button>
			</section>
		{:else if planPosition?.raceState === 'today'}
			<section class="today">
				<div class="today-link today-static">
					<div class="today-icon">
						<span class="material-symbols">emoji_events</span>
					</div>
					<div class="today-body">
						<span class="today-label">{m('planDetail.raceDay')}</span>
						<span class="today-kind">{m('planDetail.goAndRunIt')}</span>
					</div>
				</div>
			</section>
		{:else}
			<section class="today">
				<div class="today-link today-static">
					<div class="today-icon">
						<span class="material-symbols">self_improvement</span>
					</div>
					<div class="today-body">
						<span class="today-label">{m('planDetail.today')}</span>
						<span class="today-kind">{m('planDetail.restDay')}</span>
						<div class="today-meta">
							<span>{m('planDetail.restDayHint')}</span>
						</div>
					</div>
				</div>
			</section>
		{/if}

		{#if !plan.is_template && adminClubs.length > 0 && plan.user_id === auth.user?.id}
			<section class="publish-row">
				<span class="publish-label">{m('planDetail.publishLabel')}</span>
				<select bind:value={publishingTo} aria-label={m('planDetail.clubToPublishAria')}>
					<option value="">{m('planDetail.pickAClub')}</option>
					{#each adminClubs as c (c.id)}
						<option value={c.id}>{c.name}</option>
					{/each}
				</select>
				<button
					class="btn btn-outline"
					type="button"
					disabled={!publishingTo}
					onclick={publishAsTemplate}
				>
					{m('planDetail.publish')}
				</button>
			</section>
		{/if}

		<section class="calendar-section">
			<h2 class="section-title">{m('planDetail.calendar')}</h2>
			<PlanCalendar
				startDate={plan.start_date}
				endDate={plan.end_date}
				{workouts}
				planId={plan.id}
				{weekStart}
				onSelect={(wo) => (editing = wo)}
			/>
		</section>

		{#if isOwner && !plan.is_template}
			<section class="plan-tools">
				<span class="tools-label">{m('planDetail.shiftPlanLabel')}</span>
				<div class="shift-control">
					<input
						type="number"
						bind:value={shiftDays}
						step="1"
						aria-label={m('planDetail.shiftDaysAria')}
						disabled={bulkBusy}
					/>
					<span class="shift-unit">{m('planDetail.days')}</span>
					<button
						type="button"
						class="btn btn-outline btn-sm"
						onclick={shiftPlan}
						disabled={bulkBusy || !shiftDays}
					>
						{m('planDetail.shiftApply')}
					</button>
				</div>
				<div class="replan-buttons">
					<button
						type="button"
						class="btn btn-outline btn-sm replan-btn"
						onclick={proposeReplan}
						disabled={bulkBusy}
					>
						<span class="material-symbols">auto_fix_high</span>
						{m('planDetail.replan')}
					</button>
					<button
						type="button"
						class="btn btn-outline btn-sm replan-btn"
						onclick={proposeAdaptiveReplan}
						disabled={bulkBusy}
						title={m('planDetail.adaptiveReplanHint')}
					>
						<span class="material-symbols">trending_up</span>
						{m('planDetail.adaptiveReplan')}
					</button>
				</div>
			</section>

			{#if replanPreview}
				<section class="replan-preview" aria-label={m('planDetail.replanPreviewAria')}>
					<h3>{m('planDetail.replanPreviewTitle')}</h3>
					{#if adaptiveInfo}
						<p class="replan-adaptive-badge">{adaptiveBadgeText(adaptiveInfo)}</p>
					{/if}
					<ul>
						{#each replanPreview as c (c.workoutId)}
							<li>
								<span class="replan-date">{c.scheduledDate}</span>
								<span class="replan-change">{replanChangeLabel(c)}</span>
							</li>
						{/each}
					</ul>
					<div class="replan-actions">
						<button type="button" class="btn btn-secondary btn-sm" onclick={() => { replanPreview = null; adaptiveInfo = null; }} disabled={bulkBusy}>
							{m('planDetail.replanCancel')}
						</button>
						<button type="button" class="btn btn-primary btn-sm" onclick={applyReplan} disabled={bulkBusy}>
							{m('planDetail.replanApply')}
						</button>
					</div>
				</section>
			{/if}
		{/if}

		<section class="weeks">
			<h2 class="section-title">{m('planDetail.weekByWeek')}</h2>
			{#each weeks as w (w.id)}
				{@const weekWorkouts = workoutsByWeek.get(w.id) ?? []}
				{@const weekActive = weekWorkouts.filter((x) => x.kind !== 'rest')}
				{@const weekDone = weekWorkouts.filter(isWorkoutCompleted).length}
				{@const isPast = w.week_index < (currentWeekIndex ?? -1)}
				{@const isFuture = w.week_index > (currentWeekIndex ?? -1)}
				<article
					class="week"
					class:current={w.week_index === currentWeekIndex}
					class:past={isPast}
					class:future={isFuture}
				>
					<header class="week-header">
						<div class="week-ident">
							<span class="week-num">{m('planDetail.weekNum', { n: w.week_index + 1 })}</span>
							<span class="week-phase">
								{planPhaseLabel(w.phase)}
							</span>
						</div>
						<div class="week-stats">
							<span class="week-progress">
								{weekDone}<em> / {weekActive.length}</em> {m('planDetail.done')}
							</span>
							<span class="week-volume">{fmtKm(w.target_volume_m, 0)}</span>
							{#if isOwner && !plan.is_template && w.phase !== 'race'}
								<button
									type="button"
									class="week-recovery-btn"
									onclick={() => markWeekRecovery(w)}
									disabled={bulkBusy}
									title={m('planDetail.markRecovery')}
								>
									<span class="material-symbols">trending_down</span>
									{m('planDetail.markRecovery')}
								</button>
							{/if}
							{#if isOwner && !plan.is_template}
								<button
									type="button"
									class="week-recovery-btn"
									onclick={() => duplicateWeek(w)}
									disabled={bulkBusy}
									title={m('planDetail.duplicateWeek')}
								>
									<span class="material-symbols">content_copy</span>
									{m('planDetail.duplicateWeek')}
								</button>
							{/if}
						</div>
					</header>
					{#if w.notes}
						<p class="week-note">{w.notes}</p>
					{/if}
					<div class="day-grid">
						{#each weekWorkouts as wo (wo.id)}
							<div
								class="day"
								class:today={wo.scheduled_date === today}
								class:completed={isWorkoutCompleted(wo)}
								class:rest={wo.kind === 'rest'}
								class:past={wo.scheduled_date < today}
								style="--kind-color: {kindColor[wo.kind] ?? 'var(--color-text-secondary)'}"
							>
								<button
									class="day-link"
									type="button"
									aria-label={workoutAriaLabel(wo)}
									onclick={() => (editing = wo)}
								>
									<span class="dow">{dayOfWeek(wo.scheduled_date)}</span>
									<span class="kind">
										{workoutKindLabel(wo.kind)}
									</span>
									{#if wo.target_distance_m != null && wo.kind !== 'rest'}
										<span class="dist">{fmtKm(wo.target_distance_m, 1)}</span>
									{/if}
									{#if isWorkoutCompleted(wo)}
										<span class="material-symbols check" aria-hidden="true">check_circle</span>
									{/if}
								</button>
							</div>
						{/each}
					</div>
				</article>
			{/each}
		</section>

		<a class="coach-link" href="/coach?plan={plan.id}">
			<span class="material-symbols">sports</span>
			<div class="coach-link-body">
				<strong>{m('planDetail.coachLinkTitle')}</strong>
				<span>{m('planDetail.coachLinkSubtitle')}</span>
			</div>
			<span class="material-symbols arrow">chevron_right</span>
		</a>
	</div>
{/if}

{#if editing}
	<WorkoutEditor
		workout={editing}
		onClose={() => (editing = null)}
		onSaved={async () => {
			editing = null;
			await load();
		}}
	/>
{/if}

{#if editingPlanMeta && plan}
	<PlanMetaEditor
		{plan}
		onClose={() => (editingPlanMeta = false)}
		onSaved={async () => {
			editingPlanMeta = false;
			await load();
		}}
	/>
{/if}

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		text-decoration: none;
	}
	.back:hover { color: var(--color-primary); }
	.back .material-symbols { font-size: 1.05rem; }

	.hero {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-lg);
		padding: var(--space-lg) var(--space-xl);
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 14%, var(--color-surface)) 0%,
			var(--color-surface) 70%
		);
		border: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-sm);
		flex-wrap: wrap;
	}
	.hero.race-today {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}
	.hero-body {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.hero-eyebrow {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	h1 {
		font-size: 1.65rem;
		font-weight: 700;
		margin: 0;
		line-height: 1.15;
	}
	.hero-title-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.hero-edit {
		flex-shrink: 0;
	}
	.hero-edit .material-symbols {
		font-size: 1rem;
		vertical-align: -2px;
		margin-inline-end: 0.2rem;
	}
	.export-menu {
		position: relative;
		flex-shrink: 0;
	}
	.export-menu summary {
		list-style: none;
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
	}
	.export-menu summary::-webkit-details-marker {
		display: none;
	}
	.export-menu summary .material-symbols {
		font-size: 1rem;
		vertical-align: -2px;
	}
	.export-actions {
		position: absolute;
		z-index: 20;
		top: calc(100% + 0.3rem);
		inset-inline-end: 0;
		display: flex;
		flex-direction: column;
		min-width: 13rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md, 0 6px 20px rgba(0, 0, 0, 0.15));
		overflow: hidden;
	}
	.export-actions button {
		text-align: start;
		padding: 0.6rem 0.9rem;
		background: transparent;
		border: none;
		color: inherit;
		font: inherit;
		cursor: pointer;
	}
	.export-actions button:hover {
		background: var(--color-bg-secondary);
	}
	.hero-chips {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2xs);
	}
	.chip,
	.chip-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.15rem 0.55rem;
		border-radius: 9999px;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		text-decoration: none;
	}
	.chip-link:hover { color: var(--color-primary); }
	.chip .material-symbols,
	.chip-link .material-symbols { font-size: 0.95rem; }

	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md);
		margin-top: var(--space-xs);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-variant-numeric: tabular-nums;
	}
	.meta span {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}
	.meta .material-symbols {
		font-size: 1.05rem;
		color: var(--color-text-tertiary);
	}

	.hero-position {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-sm);
		flex-shrink: 0;
		min-width: 9rem;
	}
	.week-pill {
		font-size: 1.05rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.week-pill em {
		font-style: normal;
		font-weight: 500;
		color: var(--color-text-tertiary);
	}
	.relation-pill {
		display: inline-flex;
		align-items: center;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: 9999px;
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		color: var(--color-primary);
		font-size: 0.8rem;
		font-weight: 600;
		white-space: nowrap;
	}
	.relation-pill.race-today {
		background: var(--color-primary);
		color: var(--color-surface);
	}
	.relation-pill.race-past {
		background: color-mix(in srgb, var(--color-text-tertiary) 18%, transparent);
		color: var(--color-text-tertiary);
	}
	.progress-ring {
		width: 5rem;
		height: 5rem;
		border-radius: 50%;
		padding: 5px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.progress-inner {
		width: 100%;
		height: 100%;
		background: var(--color-surface);
		border-radius: 50%;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
	}
	.pct {
		font-size: 1.2rem;
		font-weight: 700;
		line-height: 1;
	}
	.done {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		margin-top: 0.15rem;
	}

	.calendar-bar {
		height: 0.4rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		overflow: hidden;
		margin: var(--space-sm) 0 var(--space-md);
	}
	.calendar-fill {
		display: block;
		height: 100%;
		background: linear-gradient(
			90deg,
			var(--color-primary),
			color-mix(in srgb, var(--color-primary) 70%, var(--color-accent-orange, var(--color-primary)))
		);
		transition: width var(--transition-base);
	}

	.plan-progress {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.phase-marker {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		list-style: none;
		margin: 0;
		padding: 0;
	}
	.phase-step {
		padding: 0.2rem 0.7rem;
		border-radius: 999px;
		font-size: 0.78rem;
		font-weight: 600;
		background: var(--color-bg-tertiary);
		color: var(--color-text-tertiary);
		border: 1px solid var(--color-border);
	}
	.phase-step.active {
		background: var(--color-primary);
		color: white;
		border-color: var(--color-primary);
	}
	.longest-long {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.longest-long .material-symbols {
		font-size: 1.1rem;
		color: var(--color-primary);
	}
	.longest-value {
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.adherence {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.adherence-flag {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		margin: 0;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		font-weight: 600;
		line-height: 1.4;
		border: 1px solid transparent;
	}
	.adherence-flag .material-symbols {
		font-size: 1.2rem;
		flex-shrink: 0;
	}
	.drift-over,
	.missed-make_up {
		background: color-mix(in srgb, var(--color-warning, #B45309) 12%, var(--color-bg));
		border-color: color-mix(in srgb, var(--color-warning, #B45309) 35%, transparent);
		color: var(--color-warning, #B45309);
	}
	.drift-under {
		background: color-mix(in srgb, var(--color-primary) 10%, var(--color-bg));
		border-color: color-mix(in srgb, var(--color-primary) 30%, transparent);
		color: var(--color-primary);
	}
	.missed-skip {
		background: var(--color-bg-tertiary);
		border-color: var(--color-border);
		color: var(--color-text-secondary);
	}

	.publish-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
		padding: var(--space-md) var(--space-lg);
		margin: var(--space-md) 0;
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md);
	}
	.plan-tools {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
		margin: var(--space-md) 0;
	}
	.tools-label {
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.shift-control {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	.shift-control input {
		width: 4.5rem;
		padding: 0.4rem 0.5rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: inherit;
		font: inherit;
	}
	.shift-unit {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.week-recovery-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		padding: 0.2rem 0.5rem;
		font-size: 0.74rem;
		font-weight: 600;
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.week-recovery-btn:hover:not(:disabled) {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.week-recovery-btn:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.week-recovery-btn .material-symbols {
		font-size: 0.95rem;
	}
	.replan-btn {
		align-self: flex-start;
	}
	.replan-btn .material-symbols {
		font-size: 1rem;
		vertical-align: -2px;
		margin-inline-end: 0.2rem;
	}
	.replan-buttons {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
	.replan-preview {
		margin: 0 0 var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-primary);
		border-radius: var(--radius-md);
	}
	.replan-preview h3 {
		margin: 0 0 var(--space-sm);
		font-size: 0.95rem;
	}
	.replan-adaptive-badge {
		margin: 0 0 var(--space-sm);
		font-size: 0.82rem;
		font-weight: 600;
		color: var(--color-primary);
	}
	.replan-preview ul {
		list-style: none;
		margin: 0 0 var(--space-md);
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}
	.replan-preview li {
		display: flex;
		gap: var(--space-sm);
		font-size: 0.88rem;
	}
	.replan-date {
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		flex-shrink: 0;
	}
	.replan-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
	.publish-label {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.publish-row select {
		padding: 0.4rem 0.7rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.9rem;
	}

	.today {
		margin-bottom: var(--space-md);
	}
	.today-link {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		width: 100%;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		color: inherit;
		font: inherit;
		text-align: start;
		cursor: pointer;
		transition: transform var(--transition-base), box-shadow var(--transition-base), border-color var(--transition-base);
	}
	button.today-link:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-sm);
		border-color: var(--color-primary);
	}
	.today-static {
		cursor: default;
		background: color-mix(in srgb, var(--color-text-tertiary) 4%, var(--color-surface));
	}
	.today-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.75rem;
		height: 2.75rem;
		border-radius: 50%;
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
		color: var(--color-primary);
		flex-shrink: 0;
	}
	.today-icon.done {
		background: color-mix(in srgb, var(--color-success) 18%, transparent);
		color: var(--color-success);
	}
	.today-icon .material-symbols { font-size: 1.5rem; }
	.today-static .today-icon {
		background: color-mix(in srgb, var(--color-text-tertiary) 14%, transparent);
		color: var(--color-text-tertiary);
	}
	.today-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.today-label {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.08em;
		text-transform: uppercase;
		font-weight: 700;
		color: var(--color-text-tertiary);
	}
	.today-kind {
		font-size: 1.15rem;
		font-weight: 700;
		color: var(--color-text);
		line-height: 1.2;
	}
	.today-meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-variant-numeric: tabular-nums;
	}
	.today-done {
		color: var(--color-success);
		font-weight: 600;
	}
	.today-notes {
		color: var(--color-text-secondary);
		margin: 0.3rem 0 0;
		font-size: 0.9rem;
	}
	.today-arrow {
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}

	.week {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-sm);
		transition: opacity var(--transition-base);
	}
	.week.past { opacity: 0.62; }
	.week.future { opacity: 0.85; }
	.week.current {
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--color-primary) 35%, transparent);
		opacity: 1;
	}
	.week-header {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-md);
		margin-bottom: 0.5rem;
		flex-wrap: wrap;
	}
	.week-ident {
		display: inline-flex;
		align-items: baseline;
		gap: var(--space-sm);
		min-width: 0;
	}
	.week-num {
		font-weight: 700;
		font-size: 1rem;
	}
	.week-phase {
		font-size: 0.78rem;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-primary);
	}
	.week-stats {
		display: inline-flex;
		align-items: baseline;
		gap: var(--space-md);
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.week-progress {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}
	.week-progress em {
		font-style: normal;
		color: var(--color-text-tertiary);
	}
	.week-volume {
		font-weight: 600;
	}
	.week-note {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin-bottom: 0.6rem;
	}
	.day-grid {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		gap: 0.4rem;
	}
	/* On narrow viewports stay one column wide per day so the
	   day-of-week order remains scannable top-to-bottom. Two columns
	   broke the weekly progression; the previous code paired Sun+Mon,
	   Tue+Wed which reads like a random grid. */
	@media (max-width: 40rem) {
		.day-grid {
			grid-template-columns: 1fr;
		}
	}
	.day {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		padding: 0.5rem 0.55rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		border: 1px solid var(--color-border);
		color: inherit;
		font-size: 0.8rem;
		border-top: 3px solid var(--kind-color, var(--color-border));
		position: relative;
		min-height: 4.5rem;
	}
	.day:hover {
		border-color: var(--color-primary);
	}
	.day-link {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		color: inherit;
		width: 100%;
		min-height: 2.75rem;
		text-align: start;
		background: transparent;
		border: none;
		padding: 0;
		font: inherit;
		cursor: pointer;
	}
	.day.rest {
		opacity: 0.55;
	}
	.day.past {
		opacity: 0.7;
	}
	.day.past.completed,
	.day.today {
		opacity: 1;
	}
	.day.today {
		background: color-mix(in srgb, var(--color-primary) 14%, var(--color-surface));
		border-color: var(--color-primary);
		box-shadow: 0 0 0 1px color-mix(in srgb, var(--color-primary) 30%, transparent);
	}
	.day.completed {
		background: color-mix(in srgb, var(--color-success) 12%, var(--color-surface));
	}
	.day .dow {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		letter-spacing: 0.05em;
		text-transform: uppercase;
	}
	.day .kind {
		font-weight: 700;
		color: var(--kind-color, var(--color-text));
	}
	.day .dist {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.day .check {
		position: absolute;
		top: 0.3rem;
		inset-inline-end: 0.3rem;
		color: var(--color-success);
		font-size: 1rem;
	}
	.coach-link {
		display: flex;
		align-items: center;
		gap: 1rem;
		margin-top: var(--space-xl);
		padding: 0.9rem 1.25rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		color: inherit;
		text-decoration: none;
		transition: border-color 0.15s ease, background 0.15s ease;
	}
	.coach-link:hover {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 4%, var(--color-surface));
	}
	.coach-link > .material-symbols {
		color: var(--color-primary);
		font-size: 1.5rem;
	}
	.coach-link-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
	}
	.coach-link-body span {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.coach-link .arrow {
		color: var(--color-text-tertiary);
	}
	.calendar-section {
		margin: var(--space-md) 0;
	}
	.section-title {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm) 0;
	}
	.weeks .section-title {
		margin-top: var(--space-lg);
	}
	.rules-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.rules-card h3 {
		font-size: 0.78rem;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
		margin-bottom: 0.4rem;
	}
	.rules-card ul {
		margin: 0;
		padding-inline-start: 1.1rem;
	}
	.rules-card li {
		margin-bottom: 0.2rem;
		font-size: 0.92rem;
	}

	/* Skeleton placeholders replace the silent "Loading..." paragraph
	   so the page rhythm is visible before data lands. */
	.back-skel,
	.hero-skel,
	.today-skel,
	.week-skel {
		background: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-lg);
		animation: plan-skeleton-shimmer 1.6s ease-in-out infinite;
	}
	.back-skel {
		height: 1rem;
		width: 8rem;
		margin-bottom: var(--space-md);
		border-radius: var(--radius-sm);
	}
	.hero-skel { height: 9rem; margin-bottom: var(--space-md); }
	.today-skel { height: 5.5rem; margin-bottom: var(--space-md); }
	.week-skel { height: 6rem; margin-bottom: var(--space-sm); }
	@keyframes plan-skeleton-shimmer {
		0% { background-position: 100% 0; }
		100% { background-position: -100% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.back-skel,
		.hero-skel,
		.today-skel,
		.week-skel { animation: none; }
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		text-align: center;
		max-width: 28rem;
		margin: 0 auto;
	}
	.empty-mark {
		opacity: 0.85;
		border-radius: var(--radius-md);
	}
	.empty h3 {
		font-size: 1.15rem;
		font-weight: 700;
		margin: 0;
	}
	.empty p {
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
		font-size: 0.95rem;
	}

	@media (max-width: 48rem) {
		.page {
			padding: var(--space-lg) var(--space-md);
		}
		.hero {
			padding: var(--space-md);
			gap: var(--space-md);
		}
		.hero-position {
			flex-direction: row;
			align-items: center;
			align-self: stretch;
			justify-content: space-between;
			min-width: 0;
		}
		h1 {
			font-size: 1.35rem;
		}
		.today-link {
			padding: var(--space-md);
		}
	}
</style>
