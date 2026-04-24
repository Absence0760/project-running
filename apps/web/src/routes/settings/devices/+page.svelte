<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';
	import { getDeviceId } from '$lib/settings';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';

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

	onMount(async () => {
		if (!auth.user) return;
		currentDeviceId = getDeviceId();
		const { data } = await supabase
			.from('user_device_settings')
			.select('device_id, platform, label, last_seen_at, prefs, updated_at')
			.eq('user_id', auth.user.id)
			.order('last_seen_at', { ascending: false });
		devices = (data as DeviceRow[]) ?? [];
		loading = false;
	});

	async function removeDevice(deviceId: string) {
		if (!auth.user) return;
		const isSelf = deviceId === currentDeviceId;
		const { error } = await supabase
			.from('user_device_settings')
			.delete()
			.eq('user_id', auth.user.id)
			.eq('device_id', deviceId);
		if (error) return;
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
		return new Date(iso).toLocaleDateString(undefined, {
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
		if (typeof v === 'boolean') return v ? 'on' : 'off';
		if (typeof v === 'object') return JSON.stringify(v);
		return String(v);
	}

	/// Drop a single override key from a device. The rest of the row
	/// stays. Mutates the in-memory list optimistically — the next
	/// reload re-reads from the server so a failure would be caught on
	/// next open.
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
		if (error) return;
		devices = devices.map((d) =>
			d.device_id === deviceId ? { ...d, prefs: rest } : d,
		);
	}

	/// Key-level editor. The catalogue below mirrors the D-scope and
	/// UD-overridable keys from `docs/settings.md`. Each entry carries
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

	const overridableKeys: KeyEditor[] = [
		// Device-scope (D) — per-browser / per-device only.
		{ key: 'voice_feedback_enabled', label: 'Voice feedback (TTS)', shape: { kind: 'bool' } },
		{
			key: 'voice_feedback_interval_km',
			label: 'Voice interval',
			shape: { kind: 'number', min: 0.1, max: 10, step: 0.1, unit: 'km' },
		},
		{ key: 'haptic_feedback_enabled', label: 'Haptic feedback', shape: { kind: 'bool' } },
		{ key: 'keep_screen_on', label: 'Keep screen on', shape: { kind: 'bool' } },
		// Universal-with-device-override (UD).
		{
			key: 'preferred_unit',
			label: 'Preferred unit',
			shape: {
				kind: 'enum',
				options: [
					{ value: 'km', label: 'Kilometres' },
					{ value: 'mi', label: 'Miles' },
				],
			},
		},
		{
			key: 'default_activity_type',
			label: 'Default activity',
			shape: {
				kind: 'enum',
				options: [
					{ value: 'run', label: 'Run' },
					{ value: 'walk', label: 'Walk' },
					{ value: 'hike', label: 'Hike' },
					{ value: 'cycle', label: 'Cycle' },
				],
			},
		},
		{
			key: 'map_style',
			label: 'Map style',
			shape: {
				kind: 'enum',
				options: [
					{ value: 'streets', label: 'Streets' },
					{ value: 'satellite', label: 'Satellite' },
					{ value: 'outdoors', label: 'Outdoors' },
					{ value: 'dark', label: 'Dark' },
				],
			},
		},
		{
			key: 'units_pace_format',
			label: 'Pace format',
			shape: {
				kind: 'enum',
				options: [
					{ value: 'min_per_km', label: 'Minutes per km' },
					{ value: 'min_per_mi', label: 'Minutes per mile' },
					{ value: 'kph', label: 'km/h' },
					{ value: 'mph', label: 'mph' },
				],
			},
		},
		{ key: 'auto_pause_enabled', label: 'Auto-pause', shape: { kind: 'bool' } },
		{
			key: 'auto_pause_speed_mps',
			label: 'Auto-pause threshold',
			shape: { kind: 'number', min: 0.1, max: 3, step: 0.1, unit: 'm/s' },
		},
	];

	let addingForDevice = $state<string | null>(null);
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

		const next = { ...device.prefs, [addKey]: value };
		const { error } = await supabase
			.from('user_device_settings')
			.update({ prefs: next, updated_at: new Date().toISOString() })
			.eq('user_id', auth.user.id)
			.eq('device_id', addingForDevice);
		if (error) return;
		devices = devices.map((d) =>
			d.device_id === addingForDevice ? { ...d, prefs: next } : d,
		);
		addingForDevice = null;
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Devices</h1>
		<p class="subtitle">Every app and browser that has signed into your account.</p>
	</header>

	{#if loading}
		<p class="muted">Loading...</p>
	{:else if devices.length === 0}
		<section class="card">
			<p class="muted">No devices registered yet. Each app or browser session registers itself on first sign-in.</p>
		</section>
	{:else}
		<div class="device-list">
			{#each devices as d (d.device_id)}
				<div class="device" class:current={d.device_id === currentDeviceId}>
					<span class="material-symbols device-icon">{platformIcon(d.platform)}</span>
					<div class="device-info">
						<div class="device-name">
							<strong>{d.label || platformLabel(d.platform)}</strong>
							{#if d.device_id === currentDeviceId}
								<span class="current-badge">This device</span>
							{/if}
						</div>
						<div class="device-meta">
							<span>{platformLabel(d.platform)}</span>
							<span class="sep">&middot;</span>
							<span>Last seen {formatDate(d.last_seen_at)}</span>
							<span class="sep">&middot;</span>
							<button
								type="button"
								class="override-link"
								onclick={() => toggleExpand(d.device_id)}
							>
								{overrideCount(d.prefs)} pref override{overrideCount(d.prefs) === 1 ? '' : 's'}
								<span class="material-symbols chev">
									{expanded === d.device_id ? 'expand_less' : 'expand_more'}
								</span>
							</button>
						</div>
						{#if expanded === d.device_id}
							<ul class="overrides">
								{#each Object.entries(d.prefs) as [k, v]}
									<li>
										<code>{k}</code>
										<span class="override-value">{formatPrefValue(v)}</span>
										<button
											type="button"
											class="override-clear"
											title="Clear this override"
											onclick={() => clearOverride(d.device_id, k)}
										>
											Clear
										</button>
									</li>
								{/each}
								<li class="override-add-row">
									<button
										type="button"
										class="override-add-btn"
										onclick={() => openAddDialog(d.device_id)}
									>
										+ Add override
									</button>
								</li>
							</ul>
						{/if}
					</div>
					<button
						class="remove-btn"
						onclick={() => (confirmingRemove = d.device_id)}
						title={d.device_id === currentDeviceId
							? 'Reset this device (wipes local cache and re-registers)'
							: 'Remove device'}
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
	title={confirmingRemove === currentDeviceId ? 'Reset this device?' : 'Remove device'}
	message={confirmingRemove === currentDeviceId
		? 'Wipes the per-device preferences for this browser, clears the local device id, and reloads. Universal preferences stay put.'
		: 'Remove this device and its per-device preferences? This cannot be undone.'}
	confirmLabel={confirmingRemove === currentDeviceId ? 'Reset' : 'Remove'}
	danger
	onconfirm={() => { if (confirmingRemove) removeDevice(confirmingRemove); }}
	oncancel={() => (confirmingRemove = null)}
/>

{#if addingForDevice}
	{@const ed = currentEditor()}
	<div class="backdrop" onclick={() => (addingForDevice = null)} role="presentation"></div>
	<div class="add-dialog" role="dialog" aria-label="Add device override">
		<h3>Add override</h3>
		<label class="field">
			<span class="field-label">Key</span>
			<select bind:value={addKey} class="input">
				{#each overridableKeys as k}
					<option value={k.key}>{k.label} — <code>{k.key}</code></option>
				{/each}
			</select>
		</label>
		<label class="field">
			<span class="field-label">Value</span>
			{#if ed.shape.kind === 'bool'}
				<div class="toggle-row">
					<button type="button" class="toggle-btn" class:active={addValueBool === true}
						onclick={() => (addValueBool = true)}>On</button>
					<button type="button" class="toggle-btn" class:active={addValueBool === false}
						onclick={() => (addValueBool = false)}>Off</button>
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
			Writes to <code>user_device_settings.prefs.{addKey}</code>. On mobile
			clients this value will override the universal setting for this device only.
		</p>
		<div class="dialog-actions">
			<button type="button" class="btn-secondary" onclick={() => (addingForDevice = null)}>
				Cancel
			</button>
			<button type="button" class="btn-primary" onclick={commitAddOverride}>Save</button>
		</div>
	</div>
{/if}

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 44rem; }
	.page-header { margin-bottom: var(--space-xl); }
	h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: var(--space-xs); }
	.subtitle { font-size: 0.88rem; color: var(--color-text-secondary); }
	.card { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-lg); }
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

	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		z-index: 100;
	}
	.add-dialog {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
		width: min(92vw, 22rem);
		z-index: 101;
		display: grid;
		gap: 0.9rem;
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4);
	}
	.add-dialog h3 {
		margin: 0;
		font-size: 1rem;
		font-weight: 700;
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
	.btn-primary,
	.btn-secondary {
		padding: 0.5rem 1rem;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
		font-weight: 600;
		cursor: pointer;
		border: 1px solid transparent;
	}
	.btn-primary { background: var(--color-primary); color: white; }
	.btn-secondary {
		background: transparent;
		color: var(--color-text-secondary);
		border-color: var(--color-border);
	}
</style>
