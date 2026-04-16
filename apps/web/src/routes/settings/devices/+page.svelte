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
		const { error } = await supabase
			.from('user_device_settings')
			.delete()
			.eq('user_id', auth.user.id)
			.eq('device_id', deviceId);
		if (error) return;
		devices = devices.filter((d) => d.device_id !== deviceId);
		confirmingRemove = null;
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
							{#if overrideCount(d.prefs) > 0}
								<span class="sep">&middot;</span>
								<span>{overrideCount(d.prefs)} pref override{overrideCount(d.prefs) === 1 ? '' : 's'}</span>
							{/if}
						</div>
					</div>
					{#if d.device_id !== currentDeviceId}
						<button class="remove-btn" onclick={() => (confirmingRemove = d.device_id)} title="Remove device">
							<span class="material-symbols">close</span>
						</button>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</div>

<ConfirmDialog
	open={confirmingRemove !== null}
	title="Remove device"
	message="Remove this device and its per-device preferences? This cannot be undone."
	confirmLabel="Remove"
	danger
	onconfirm={() => { if (confirmingRemove) removeDevice(confirmingRemove); }}
	oncancel={() => (confirmingRemove = null)}
/>

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
</style>
