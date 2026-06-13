<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { getDeviceId } from '$lib/settings/settings';
	import {
		isPushSupported,
		pushPermission,
		subscribeToPush,
		unsubscribeFromPush,
		getCurrentSubscription,
	} from '$lib/util/push';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import Modal from '$lib/components/Modal.svelte';

	interface DeviceRow {
		device_id: string;
		platform: string;
		label: string | null;
		last_seen_at: string;
		prefs: Record<string, unknown>;
		updated_at: string;
	}

	let devices = $state<DeviceRow[]>([]);
	let loading = $state(true);
	let currentDeviceId = $state('');
	let confirmingRemove = $state<string | null>(null);

	let pushSupported = $state(false);
	let pushPermissionState = $state<NotificationPermission | 'unsupported'>('default');
	let pushSubscribed = $state(false);
	let pushBusy = $state(false);

	onMount(async () => {
		// Same auth-race fix as /settings/account + /settings/preferences:
		// loading=false flips before fetchUser resolves, so a hard reload
		// can land here with auth.user still null. Poll briefly so the
		// devices list actually loads instead of stalling on "Loading…".
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		currentDeviceId = getDeviceId();
		const { data } = await supabase
			.from('user_device_settings')
			.select('device_id, platform, label, last_seen_at, prefs, updated_at')
			.eq('user_id', auth.user.id)
			.order('last_seen_at', { ascending: false });
		devices = (data as DeviceRow[]) ?? [];
		loading = false;

		pushSupported = isPushSupported();
		await refreshPushState();
	});

	async function refreshPushState() {
		pushPermissionState = pushPermission();
		if (!pushSupported) return;
		pushSubscribed = !!(await getCurrentSubscription());
	}

	async function handleEnablePush() {
		pushBusy = true;
		try {
			await subscribeToPush();
			await refreshPushState();
			await refreshCurrentDeviceRow();
			showToast(m('settingsDevices.pushEnabledToast'), 'success');
		} catch (e) {
			showToast(m('settingsDevices.pushEnableFailedToast', { message: (e as Error).message }), 'error');
		} finally {
			pushBusy = false;
		}
	}

	async function handleDisablePush() {
		pushBusy = true;
		try {
			await unsubscribeFromPush();
			await refreshPushState();
			await refreshCurrentDeviceRow();
			showToast(m('settingsDevices.pushDisabledToast'), 'success');
		} finally {
			pushBusy = false;
		}
	}

	async function refreshCurrentDeviceRow() {
		if (!auth.user || !currentDeviceId) return;
		const { data } = await supabase
			.from('user_device_settings')
			.select('prefs')
			.eq('user_id', auth.user.id)
			.eq('device_id', currentDeviceId)
			.maybeSingle();
		if (!data) return;
		devices = devices.map((d) =>
			d.device_id === currentDeviceId
				? { ...d, prefs: (data.prefs as Record<string, unknown>) ?? {} }
				: d,
		);
	}

	function hasPushSubscription(prefs: Record<string, unknown>): boolean {
		return prefs && typeof prefs === 'object' && 'push_subscription' in prefs;
	}

	async function renameDevice(deviceId: string, nextLabel: string) {
		if (!auth.user) return;
		const device = devices.find((d) => d.device_id === deviceId);
		if (!device) return;
		const trimmed = nextLabel.trim();
		const current = device.label ?? '';
		if (trimmed === current) return;
		const { error } = await supabase
			.from('user_device_settings')
			.update({ label: trimmed || null, updated_at: new Date().toISOString() })
			.eq('user_id', auth.user.id)
			.eq('device_id', deviceId);
		if (error) {
			showToast(m('settingsDevices.renameFailedToast', { message: error.message }), 'error');
			return;
		}
		devices = devices.map((d) =>
			d.device_id === deviceId ? { ...d, label: trimmed || null } : d,
		);
	}

	async function removeDevice(deviceId: string) {
		if (!auth.user) return;
		const isSelf = deviceId === currentDeviceId;
		const { error } = await supabase
			.from('user_device_settings')
			.delete()
			.eq('user_id', auth.user.id)
			.eq('device_id', deviceId);
		if (error) {
			showToast(m('settingsDevices.removeDeviceFailedToast', { message: error.message }), 'error');
			return;
		}
		devices = devices.filter((d) => d.device_id !== deviceId);
		confirmingRemove = null;

		// When the user resets *this* browser, also clear the local
		// device-id + any in-flight settings caches. Previously the
		// row was deleted server-side but the browser kept its minted
		// device id, so the next write re-created the empty row.
		if (isSelf && typeof localStorage !== 'undefined') {
			try {
				localStorage.removeItem('run_app.device_id');
			} catch (_) {
				/* quota / access denied — noop */
			}
			// Force a full reload so stores are re-initialised with
			// a fresh device id.
			window.location.reload();
		}
	}

	function platformIcon(p: string): string {
		if (p.includes('android')) return 'phone_android';
		if (p.includes('ios') || p.includes('mac')) return 'phone_iphone';
		if (p.includes('wear')) return 'watch';
		if (p.includes('watch')) return 'watch';
		if (p.includes('web')) return 'language';
		if (p.includes('windows')) return 'desktop_windows';
		if (p.includes('linux')) return 'computer';
		return 'devices_other';
	}

	function platformLabel(p: string): string {
		const m: Record<string, string> = {
			android: 'Android',
			ios: 'iOS',
			wear_os: 'Wear OS',
			watch_os: 'Apple Watch',
			web: 'Web',
			'web-mac': 'Web (Mac)',
			'web-windows': 'Web (Windows)',
			'web-linux': 'Web (Linux)',
			'web-android': 'Web (Android)',
			'web-ios': 'Web (iOS)',
		};
		return m[p] ?? p;
	}

	function formatDate(iso: string): string {
		return new Date(iso).toLocaleDateString(activeFormatLocale(), {
			year: 'numeric', month: 'short', day: 'numeric',
			hour: '2-digit', minute: '2-digit',
		});
	}

	function overrideCount(prefs: Record<string, unknown>): number {
		return Object.keys(prefs).length;
	}

	let expanded = $state<string | null>(null);

	function toggleExpand(deviceId: string) {
		expanded = expanded === deviceId ? null : deviceId;
	}

	function formatPrefValue(v: unknown): string {
		if (v === null || v === undefined) return '—';
		if (typeof v === 'boolean') return v ? m('settingsDevices.valueOn') : m('settingsDevices.valueOff');
		if (typeof v === 'object') return JSON.stringify(v);
		return String(v);
	}

	/// Drop a single override key from a device. The rest of the row
	/// stays. A failure surfaces as an error toast — silently returning
	/// left the value on screen with no explanation of why the Clear did
	/// nothing.
	async function clearOverride(deviceId: string, key: string) {
		if (!auth.user) return;
		const device = devices.find((d) => d.device_id === deviceId);
		if (!device) return;
		const { [key]: _dropped, ...rest } = device.prefs;
		const { error } = await supabase
			.from('user_device_settings')
			.update({ prefs: rest, updated_at: new Date().toISOString() })
			.eq('user_id', auth.user.id)
			.eq('device_id', deviceId);
		if (error) {
			showToast(m('settingsDevices.clearOverrideFailedToast', { message: error.message }), 'error');
			return;
		}
		devices = devices.map((d) =>
			d.device_id === deviceId ? { ...d, prefs: rest } : d,
		);
	}

	/// Key-level editor. The catalogue below mirrors the D-scope and
	/// UD-overridable keys from `docs/backend/settings.md`. Each entry carries
	/// a typed value-editor shape the dialog renders into. U-scope
	/// keys are deliberately excluded — you can't override a universal
	/// value on a single device, so offering to do so would be a lie.
	interface KeyEditor {
		key: string;
		label: string;
		shape:
			| { kind: 'bool' }
			| { kind: 'number'; min?: number; max?: number; step?: number; unit?: string }
			| { kind: 'enum'; options: Array<{ value: string; label: string }> };
	}

	const overridableKeys = $derived<KeyEditor[]>([
		// Device-scope (D) — per-browser / per-device only.
		{ key: 'voice_feedback_enabled', label: m('settingsDevices.keyVoiceFeedback'), shape: { kind: 'bool' } },
		{
			key: 'voice_feedback_interval_km',
			label: m('settingsDevices.keyVoiceInterval'),
			shape: { kind: 'number', min: 0.1, max: 10, step: 0.1, unit: 'km' },
		},
		{ key: 'haptic_feedback_enabled', label: m('settingsDevices.keyHapticFeedback'), shape: { kind: 'bool' } },
		{ key: 'keep_screen_on', label: m('settingsDevices.keyKeepScreenOn'), shape: { kind: 'bool' } },
		// Universal-with-device-override (UD).
		{
			key: 'preferred_unit',
			label: m('settingsDevices.keyPreferredUnit'),
			shape: {
				kind: 'enum',
				options: [
					{ value: 'km', label: m('settingsDevices.unitKilometres') },
					{ value: 'mi', label: m('settingsDevices.unitMiles') },
				],
			},
		},
		{
			key: 'default_activity_type',
			label: m('settingsDevices.keyDefaultActivity'),
			shape: {
				kind: 'enum',
				options: [
					{ value: 'run', label: m('settingsDevices.activityRun') },
					{ value: 'walk', label: m('settingsDevices.activityWalk') },
					{ value: 'hike', label: m('settingsDevices.activityHike') },
					{ value: 'cycle', label: m('settingsDevices.activityCycle') },
				],
			},
		},
		{
			key: 'map_style',
			label: m('settingsDevices.keyMapStyle'),
			shape: {
				kind: 'enum',
				options: [
					{ value: 'streets', label: m('settingsDevices.mapStreets') },
					{ value: 'satellite', label: m('settingsDevices.mapSatellite') },
					{ value: 'outdoors', label: m('settingsDevices.mapOutdoors') },
					{ value: 'dark', label: m('settingsDevices.mapDark') },
				],
			},
		},
		{
			key: 'units_pace_format',
			label: m('settingsDevices.keyPaceFormat'),
			shape: {
				kind: 'enum',
				options: [
					{ value: 'min_per_km', label: m('settingsDevices.paceMinPerKm') },
					{ value: 'min_per_mi', label: m('settingsDevices.paceMinPerMi') },
					{ value: 'kph', label: 'km/h' },
					{ value: 'mph', label: 'mph' },
				],
			},
		},
	]);

	let addingForDevice = $state<string | null>(null);
	let addBusy = $state(false);
	let addKey = $state<string>('voice_feedback_enabled');
	let addValueBool = $state<boolean>(false);
	let addValueNumber = $state<string>('');
	let addValueEnum = $state<string>('');

	function currentEditor(): KeyEditor {
		return overridableKeys.find((k) => k.key === addKey) ?? overridableKeys[0];
	}

	function openAddDialog(deviceId: string) {
		addingForDevice = deviceId;
		const device = devices.find((d) => d.device_id === deviceId);
		const existing = device?.prefs ?? {};
		// Default to the first key that's not already overridden; fall
		// back to the first key if every key is set (the user will
		// just overwrite).
		const firstMissing =
			overridableKeys.find((k) => !(k.key in existing))?.key ??
			overridableKeys[0].key;
		addKey = firstMissing;
		resetAddValues();
	}

	function resetAddValues() {
		const ed = currentEditor();
		if (ed.shape.kind === 'bool') addValueBool = true;
		else if (ed.shape.kind === 'number') addValueNumber = '';
		else if (ed.shape.kind === 'enum') addValueEnum = ed.shape.options[0].value;
	}

	$effect(() => {
		// Reset input state whenever the key changes — otherwise a
		// stale value from a prior key bleeds across.
		addKey;
		resetAddValues();
	});

	async function commitAddOverride() {
		if (!auth.user || !addingForDevice) return;
		const device = devices.find((d) => d.device_id === addingForDevice);
		if (!device) return;
		const ed = currentEditor();
		let value: unknown;
		if (ed.shape.kind === 'bool') value = addValueBool;
		else if (ed.shape.kind === 'number') {
			const n = parseFloat(addValueNumber);
			if (!Number.isFinite(n)) return;
			value = n;
		} else if (ed.shape.kind === 'enum') value = addValueEnum;

		if (addBusy) return;
		addBusy = true;
		const next = { ...device.prefs, [addKey]: value };
		const { error } = await supabase
			.from('user_device_settings')
			.update({ prefs: next, updated_at: new Date().toISOString() })
			.eq('user_id', auth.user.id)
			.eq('device_id', addingForDevice);
		addBusy = false;
		if (error) {
			showToast(m('settingsDevices.addOverrideFailedToast', { message: error.message }), 'error');
			return;
		}
		devices = devices.map((d) =>
			d.device_id === addingForDevice ? { ...d, prefs: next } : d,
		);
		addingForDevice = null;
	}
</script>

<div class="page">
	<header class="page-head">
		<p class="kicker">{m('shell.settings')}</p>
		<h1>{m('settingsDevices.title')}</h1>
		<p class="tagline">
			{m('settingsDevices.tagline')}
		</p>
	</header>

	{#if loading}
		<div class="skeleton-stack" aria-hidden="true">
			{#each Array(3) as _, i (i)}
				<div class="skel-row">
					<span class="skel skel-icon"></span>
					<div class="skel-info">
						<span class="skel skel-line skel-w-40"></span>
						<span class="skel skel-line skel-w-60"></span>
					</div>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{m('settingsDevices.loadingDevices')}</p>
	{:else if devices.length === 0}
		<section class="card empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">devices_other</span>
			<h3>{m('settingsDevices.emptyTitle')}</h3>
			<p class="empty-text">
				{m('settingsDevices.emptyText')}
			</p>
		</section>
	{:else}
		<div class="device-list">
			{#each devices as d (d.device_id)}
				<div
					class="device"
					class:current={d.device_id === currentDeviceId}
					data-device-id={d.device_id}
					data-device-label={d.label ?? ''}
				>
					<span class="material-symbols device-icon">{platformIcon(d.platform)}</span>
					<div class="device-info">
						<div class="device-name">
							<input
								type="text"
								class="device-label-input"
								aria-label={m('settingsDevices.deviceLabelAria')}
								value={d.label ?? ''}
								placeholder={platformLabel(d.platform)}
								onblur={(e) => renameDevice(d.device_id, (e.currentTarget as HTMLInputElement).value)}
								onkeydown={(e) => {
									if (e.key === 'Enter') (e.currentTarget as HTMLInputElement).blur();
								}}
							/>
							{#if d.device_id === currentDeviceId}
								<span class="current-badge">{m('settingsDevices.thisDevice')}</span>
							{/if}
						</div>
						<div class="device-meta">
							<span>{platformLabel(d.platform)}</span>
							<span class="sep">&middot;</span>
							<span>{m('settingsDevices.lastSeen', { date: formatDate(d.last_seen_at) })}</span>
							<span class="sep">&middot;</span>
							<button
								type="button"
								class="override-link"
								onclick={() => toggleExpand(d.device_id)}
							>
								{overrideCount(d.prefs) === 1
									? m('settingsDevices.overrideCountOne', { count: overrideCount(d.prefs) })
									: m('settingsDevices.overrideCountOther', { count: overrideCount(d.prefs) })}
								<span class="material-symbols chev">
									{expanded === d.device_id ? 'expand_less' : 'expand_more'}
								</span>
							</button>
							{#if d.device_id !== currentDeviceId && hasPushSubscription(d.prefs)}
								<span class="sep">&middot;</span>
								<span class="push-state" title={m('settingsDevices.pushOnTitle')}>
									<span class="material-symbols">notifications_active</span>
									{m('settingsDevices.pushOn')}
								</span>
							{/if}
						</div>
						{#if d.device_id === currentDeviceId}
							<div class="device-push" data-testid="device-push-row">
								{#if !pushSupported}
									<span class="push-hint">{m('settingsDevices.pushNotSupported')}</span>
								{:else if pushPermissionState === 'denied'}
									<span class="push-hint">{m('settingsDevices.pushBlocked')}</span>
								{:else if pushSubscribed}
									<button
										type="button"
										class="btn btn-outline btn-sm"
										onclick={handleDisablePush}
										disabled={pushBusy}
									>
										<span class="material-symbols">notifications_off</span>
										{pushBusy ? m('settingsDevices.pushUpdating') : m('settingsDevices.disablePush')}
									</button>
								{:else}
									<button
										type="button"
										class="btn btn-primary btn-sm"
										onclick={handleEnablePush}
										disabled={pushBusy}
									>
										<span class="material-symbols">notifications_active</span>
										{pushBusy ? m('settingsDevices.pushEnabling') : m('settingsDevices.enablePush')}
									</button>
								{/if}
							</div>
						{/if}
						{#if expanded === d.device_id}
							<ul class="overrides">
								{#each Object.entries(d.prefs) as [k, v]}
									<li>
										<code>{k}</code>
										<span class="override-value">{formatPrefValue(v)}</span>
										<button
											type="button"
											class="override-clear"
											title={m('settingsDevices.clearOverrideTitle')}
											onclick={() => clearOverride(d.device_id, k)}
										>
											{m('settingsDevices.clear')}
										</button>
									</li>
								{/each}
								<li class="override-add-row">
									<button
										type="button"
										class="override-add-btn"
										onclick={() => openAddDialog(d.device_id)}
									>
										+ {m('settingsDevices.addOverride')}
									</button>
								</li>
							</ul>
						{/if}
					</div>
					<button
						class="remove-btn"
						onclick={() => (confirmingRemove = d.device_id)}
						title={d.device_id === currentDeviceId
							? m('settingsDevices.resetDeviceTitle')
							: m('settingsDevices.removeDeviceTitle')}
					>
						<span class="material-symbols">
							{d.device_id === currentDeviceId ? 'refresh' : 'close'}
						</span>
					</button>
				</div>
			{/each}
		</div>
	{/if}
</div>

<ConfirmDialog
	open={confirmingRemove !== null}
	title={confirmingRemove === currentDeviceId ? m('settingsDevices.resetConfirmTitle') : m('settingsDevices.removeConfirmTitle')}
	message={confirmingRemove === currentDeviceId
		? m('settingsDevices.resetConfirmMessage')
		: m('settingsDevices.removeConfirmMessage')}
	confirmLabel={confirmingRemove === currentDeviceId ? m('settingsDevices.resetConfirmLabel') : m('settingsDevices.removeConfirmLabel')}
	danger
	onconfirm={() => { if (confirmingRemove) removeDevice(confirmingRemove); }}
	oncancel={() => (confirmingRemove = null)}
/>

<Modal
	open={addingForDevice != null}
	title={m('settingsDevices.addOverride')}
	narrow
	onclose={() => (addingForDevice = null)}
	bodyClass="add-dialog-body"
>
	{#if addingForDevice}
		{@const ed = currentEditor()}
			<label class="field">
				<span class="field-label">{m('settingsDevices.fieldKey')}</span>
				<select bind:value={addKey} class="input">
					{#each overridableKeys as k}
						<option value={k.key}>{k.label} — {k.key}</option>
					{/each}
				</select>
			</label>
			<label class="field">
				<span class="field-label">{m('settingsDevices.fieldValue')}</span>
				{#if ed.shape.kind === 'bool'}
					<div class="toggle-row">
						<button type="button" class="toggle-btn" class:active={addValueBool === true}
							onclick={() => (addValueBool = true)}>{m('settingsDevices.toggleOn')}</button>
						<button type="button" class="toggle-btn" class:active={addValueBool === false}
							onclick={() => (addValueBool = false)}>{m('settingsDevices.toggleOff')}</button>
					</div>
				{:else if ed.shape.kind === 'number'}
					<div class="unit-row">
						<input
							type="number"
							class="input"
							bind:value={addValueNumber}
							min={ed.shape.min}
							max={ed.shape.max}
							step={ed.shape.step ?? 0.1}
						/>
						{#if ed.shape.unit}<span class="unit">{ed.shape.unit}</span>{/if}
					</div>
				{:else}
					<select bind:value={addValueEnum} class="input">
						{#each ed.shape.options as opt}
							<option value={opt.value}>{opt.label}</option>
						{/each}
					</select>
				{/if}
			</label>
			<p class="dialog-hint">
				{m('settingsDevices.dialogHintPrefix')}<code>user_device_settings.prefs.{addKey}</code>{m('settingsDevices.dialogHintSuffix')}
			</p>
			<div class="dialog-actions">
				<button type="button" class="btn btn-outline btn-sm" onclick={() => (addingForDevice = null)}>
					{m('settingsDevices.cancel')}
				</button>
				<button type="button" class="btn btn-primary btn-sm" disabled={addBusy} onclick={commitAddOverride}>{m('settingsDevices.save')}</button>
			</div>
	{/if}
</Modal>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 64rem; }
	.page-head { margin-bottom: var(--space-xl); }
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	h1 { font-size: 1.6rem; font-weight: 700; margin: 0 0 var(--space-xs); }
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 44rem;
	}
	.card { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-lg); }

	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		text-align: center;
	}
	.empty-card h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.empty-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}

	.skeleton-stack { display: flex; flex-direction: column; gap: 0.5rem; }
	.skel-row {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 1rem 1.25rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		pointer-events: none;
	}
	.skel-icon { width: 1.5rem; height: 1.5rem; border-radius: 50%; flex-shrink: 0; }
	.skel-info { flex: 1; display: flex; flex-direction: column; gap: 0.4rem; }
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line { height: 0.85rem; }
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
	.device-list { display: flex; flex-direction: column; gap: 0.5rem; }
	.device {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 1rem 1.25rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.device.current { border-color: var(--color-primary); background: var(--color-primary-light); }
	.device-icon { font-size: 1.5rem; color: var(--color-text-secondary); }
	.device.current .device-icon { color: var(--color-primary); }
	.device-info { flex: 1; min-width: 0; }
	.device-name {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		overflow: hidden;
	}
	.device-name strong {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.device-label-input {
		font: inherit;
		font-weight: 700;
		color: var(--color-text);
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-sm);
		padding: 0.15rem 0.4rem;
		margin: -0.15rem -0.4rem;
		min-width: 8rem;
		max-width: 22rem;
		flex: 0 1 auto;
	}
	.device-label-input:hover {
		border-color: var(--color-border);
	}
	.device-label-input:focus {
		outline: none;
		border-color: var(--color-primary);
		background: var(--color-bg);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	.device-label-input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.push-state {
		color: var(--color-text-secondary);
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
	}
	.push-state .material-symbols { font-size: 0.95rem; }
	.device-push {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		margin-top: 0.4rem;
	}
	.device-push .material-symbols { font-size: 1.05rem; }
	.push-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.current-badge {
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-primary);
		background: rgba(79, 70, 229, 0.12);
		padding: 0.1rem 0.4rem;
		border-radius: 9999px;
		letter-spacing: 0.03em;
	}
	.device-meta {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		margin-top: 0.2rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.sep { margin: 0 0.3rem; }
	.remove-btn {
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0.25rem;
		border-radius: var(--radius-sm);
	}
	.remove-btn:hover { color: var(--color-danger); background: rgba(229, 57, 53, 0.08); }
	.muted { color: var(--color-text-tertiary); }
	.material-symbols { font-family: 'Material Symbols Outlined', system-ui; font-weight: normal; display: inline-block; line-height: 1; }

	.override-link {
		background: none;
		border: none;
		color: var(--color-primary);
		cursor: pointer;
		padding: 0;
		font: inherit;
		font-size: inherit;
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
	}
	.override-link .chev { font-size: 1rem; }
	.overrides {
		list-style: none;
		margin: 0.5rem 0 0;
		padding: 0.5rem 0.75rem;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
		display: grid;
		gap: 0.35rem;
	}
	.overrides li {
		display: grid;
		grid-template-columns: minmax(8rem, 1fr) auto auto;
		align-items: center;
		gap: 0.8rem;
		font-size: 0.82rem;
	}
	.overrides code {
		font-family: ui-monospace, monospace;
		color: var(--color-text-secondary);
	}
	.override-value {
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.override-clear {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text-tertiary);
		border-radius: var(--radius-sm);
		padding: 0.2rem 0.6rem;
		font-size: 0.75rem;
		cursor: pointer;
	}
	.override-clear:hover {
		color: var(--color-danger);
		border-color: var(--color-danger);
	}
	.override-add-row {
		grid-template-columns: 1fr !important;
	}
	.override-add-btn {
		background: transparent;
		border: 1px dashed var(--color-border);
		color: var(--color-primary);
		border-radius: var(--radius-sm);
		padding: 0.35rem 0.8rem;
		font-size: 0.8rem;
		cursor: pointer;
		text-align: center;
	}
	.override-add-btn:hover {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
	}

	/* Add-override reuses canonical .modal-* classes from app.css. */
	.add-dialog-body {
		display: grid;
		gap: 0.9rem;
	}
	.field { display: grid; gap: 0.3rem; }
	.field-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.input {
		padding: 0.5rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.9rem;
		font-family: inherit;
	}
	.toggle-row { display: flex; gap: 0.3rem; }
	.toggle-btn {
		padding: 0.4rem 0.9rem;
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
	}
	.toggle-btn.active {
		background: var(--color-primary);
		color: white;
		border-color: var(--color-primary);
	}
	.unit-row { display: flex; align-items: center; gap: 0.4rem; }
	.unit { color: var(--color-text-tertiary); font-size: 0.85rem; }
	.dialog-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		margin: 0;
	}
	.dialog-hint code {
		font-family: ui-monospace, monospace;
		background: var(--color-bg-tertiary);
		padding: 0.1rem 0.3rem;
		border-radius: var(--radius-sm);
	}
	.dialog-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.4rem;
	}
</style>
