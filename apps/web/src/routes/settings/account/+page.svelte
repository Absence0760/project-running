<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';
	import { downloadFile } from '$lib/gpx';
	import { fetchRuns } from '$lib/data';
	import {
		createBackup,
		restoreBackup,
		type BackupProgress,
		type RestoreProgress,
		type RestoreResult,
	} from '$lib/backup';

	let displayName = $state(auth.user?.display_name ?? '');
	let parkrunNumber = $state(auth.user?.parkrun_number ?? '');
	let dateOfBirth = $state('');
	let restingHr = $state('');
	let maxHr = $state('');
	let saving = $state(false);
	let saved = $state(false);
	let exporting = $state(false);

	let backingUp = $state(false);
	let backupProgress = $state<BackupProgress | null>(null);
	let restoring = $state(false);
	let restoreProgress = $state<RestoreProgress | null>(null);
	let restoreResult = $state<RestoreResult | null>(null);
	let restoreError = $state<string | null>(null);
	let restoreFileInput: HTMLInputElement;

	let newPassword = $state('');
	let confirmPassword = $state('');
	let passwordSaving = $state(false);
	let passwordStatus = $state<string | null>(null);
	let passwordError = $state<string | null>(null);

	onMount(async () => {
		if (!auth.user) return;
		// Load settings bag for DOB / HR fields.
		const { data } = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', auth.user.id)
			.maybeSingle();
		if (data?.prefs && typeof data.prefs === 'object') {
			const p = data.prefs as Record<string, unknown>;
			dateOfBirth = (p.date_of_birth as string) ?? '';
			restingHr = (p.resting_hr_bpm as number)?.toString() ?? '';
			maxHr = (p.max_hr_bpm as number)?.toString() ?? '';
		}
	});

	async function handleSave() {
		if (!auth.user) return;
		saving = true;
		saved = false;
		await supabase.from('user_profiles').update({
			display_name: displayName || null,
			parkrun_number: parkrunNumber || null,
		}).eq('id', auth.user.id);

		// Persist DOB + HR into user_settings.prefs.
		const prefs: Record<string, unknown> = {};
		if (dateOfBirth) prefs.date_of_birth = dateOfBirth;
		if (restingHr) prefs.resting_hr_bpm = parseInt(restingHr, 10) || null;
		if (maxHr) prefs.max_hr_bpm = parseInt(maxHr, 10) || null;
		if (Object.keys(prefs).length > 0) {
			const { data } = await supabase
				.from('user_settings')
				.select('prefs')
				.eq('user_id', auth.user.id)
				.maybeSingle();
			const merged = { ...((data?.prefs as Record<string, unknown>) ?? {}), ...prefs };
			await supabase.from('user_settings').upsert({
				user_id: auth.user.id,
				prefs: merged,
				updated_at: new Date().toISOString(),
			});
		}
		saved = true;
		saving = false;
		setTimeout(() => (saved = false), 2000);
	}

	async function handleSavePassword() {
		if (newPassword.length < 6) { passwordError = 'Password must be at least 6 characters.'; return; }
		if (newPassword !== confirmPassword) { passwordError = 'Passwords do not match.'; return; }
		passwordSaving = true; passwordError = null; passwordStatus = null;
		const { error } = await supabase.auth.updateUser({ password: newPassword });
		passwordSaving = false;
		if (error) { passwordError = error.message; }
		else {
			passwordStatus = 'Password saved. You can now sign in with your email on any device.';
			newPassword = ''; confirmPassword = '';
			setTimeout(() => (passwordStatus = null), 5000);
		}
	}

	async function handleExportCsv() {
		exporting = true;
		try {
			const runs = await fetchRuns();
			const header = 'date,distance_m,duration_s,pace_s_per_km,source\n';
			const rows = runs.map((r) => {
				const pace = r.distance_m > 0 ? Math.round(r.duration_s / (r.distance_m / 1000)) : 0;
				return `${r.started_at},${r.distance_m},${r.duration_s},${pace},${r.source}`;
			}).join('\n');
			downloadFile(header + rows, 'runs_export.csv', 'text/csv');
		} finally { exporting = false; }
	}

	async function handleBackup() {
		backingUp = true; backupProgress = null;
		try {
			const blob = await createBackup((p) => (backupProgress = p));
			const url = URL.createObjectURL(blob);
			const a = document.createElement('a');
			const ts = new Date().toISOString().replace(/[:.]/g, '-');
			a.href = url; a.download = `run-app-backup-${ts}.zip`;
			document.body.appendChild(a); a.click(); a.remove();
			URL.revokeObjectURL(url);
		} catch (e) { alert(`Backup failed: ${(e as Error).message}`); }
		finally { backingUp = false; backupProgress = null; }
	}

	async function handleRestoreFile(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0]; if (!file) return;
		if (!confirm(`Restore from "${file.name}"?\n\nThis adds or overwrites runs matching IDs in the backup.`)) { input.value = ''; return; }
		restoring = true; restoreProgress = null; restoreResult = null; restoreError = null;
		try {
			const res = await restoreBackup(file, { onProgress: (p) => (restoreProgress = p) });
			restoreResult = res;
		} catch (err) { restoreError = (err as Error).message; }
		finally { restoring = false; restoreProgress = null; input.value = ''; }
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Account</h1>
	</header>

	<!-- Profile -->
	<section class="card">
		<h2>Profile</h2>
		<div class="form-grid">
			<label>
				<span class="label-text">Display Name</span>
				<input type="text" bind:value={displayName} />
			</label>
			<label>
				<span class="label-text">Email</span>
				<input type="email" value={auth.user?.email ?? ''} disabled />
			</label>
			<label>
				<span class="label-text">parkrun Athlete Number</span>
				<input type="text" bind:value={parkrunNumber} placeholder="A123456" />
			</label>
			<label>
				<span class="label-text">Date of Birth</span>
				<input type="date" bind:value={dateOfBirth} />
			</label>
			<label>
				<span class="label-text">Resting HR (bpm)</span>
				<input type="number" bind:value={restingHr} placeholder="e.g. 52" min="30" max="120" />
			</label>
			<label>
				<span class="label-text">Max HR (bpm)</span>
				<input type="number" bind:value={maxHr} placeholder="e.g. 190 (or leave blank for 220-age)" min="100" max="230" />
			</label>
		</div>
		<button class="btn btn-primary btn-save" onclick={handleSave} disabled={saving}>
			{saving ? 'Saving...' : saved ? 'Saved!' : 'Save Profile'}
		</button>
	</section>

	<!-- Password -->
	<section class="card">
		<h2>Sign-in Password</h2>
		<p class="section-desc">
			Set or change the password for signing in with your email. If you signed up via Google
			or Apple, set one here to enable email+password sign-in on devices that don't support
			social login (e.g. the Wear OS watch app).
		</p>
		<div class="form-grid">
			<label>
				<span class="label-text">New Password</span>
				<input type="password" autocomplete="new-password" bind:value={newPassword} placeholder="At least 6 characters" />
			</label>
			<label>
				<span class="label-text">Confirm Password</span>
				<input type="password" autocomplete="new-password" bind:value={confirmPassword} />
			</label>
		</div>
		{#if passwordError}<p class="error-text">{passwordError}</p>{/if}
		{#if passwordStatus}<p class="ok-text">{passwordStatus}</p>{/if}
		<button class="btn btn-primary btn-save" onclick={handleSavePassword} disabled={passwordSaving || !newPassword || !confirmPassword}>
			{passwordSaving ? 'Saving...' : 'Save Password'}
		</button>
	</section>

	<!-- Backup & Restore -->
	<section class="card">
		<h2>Backup & Restore</h2>
		<p class="section-desc">
			Full backup includes every run with its GPS trace, your routes, profile, and preferences.
		</p>
		<div class="btn-row">
			<button class="btn btn-primary" onclick={handleBackup} disabled={backingUp || restoring}>
				<span class="material-symbols">archive</span>
				{backingUp ? (backupProgress ? `${backupProgress.stage}...` : 'Backing up...') : 'Download full backup'}
			</button>
			<button class="btn btn-outline" onclick={() => restoreFileInput.click()} disabled={backingUp || restoring}>
				<span class="material-symbols">unarchive</span>
				{restoring ? (restoreProgress ? `${restoreProgress.stage}...` : 'Restoring...') : 'Restore from backup'}
			</button>
			<input bind:this={restoreFileInput} type="file" accept=".zip" onchange={handleRestoreFile} style="display: none" />
		</div>
		{#if restoreResult}
			<p class="ok-text">
				Restored {restoreResult.runsImported} runs, {restoreResult.tracksUploaded} tracks, {restoreResult.routesImported} routes.
				{#if restoreResult.warnings.length > 0}<br /><small>{restoreResult.warnings.length} warnings (see console).</small>{/if}
			</p>
		{/if}
		{#if restoreError}<p class="error-text">Restore failed: {restoreError}</p>{/if}
	</section>

	<!-- Data Export (CSV) -->
	<section class="card">
		<h2>Data Export (CSV)</h2>
		<p class="section-desc">Summary CSV for spreadsheet analysis. No GPS traces — use Full backup for a lossless copy.</p>
		<button class="btn btn-outline" onclick={handleExportCsv} disabled={exporting}>
			<span class="material-symbols">download</span>
			{exporting ? 'Exporting...' : 'Export All Runs (CSV)'}
		</button>
	</section>

	<!-- Danger zone -->
	<section class="card card-danger">
		<h2 class="danger-heading">Danger Zone</h2>
		<p class="section-desc">Permanently delete your account and all associated data. This cannot be undone.</p>
		<button class="btn btn-danger">Delete Account</button>
	</section>
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 44rem; }
	.page-header { margin-bottom: var(--space-xl); }
	h1 { font-size: 1.5rem; font-weight: 700; }
	h2 { font-size: 0.9rem; font-weight: 600; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: var(--space-lg); }
	.card { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-lg); margin-bottom: var(--space-xl); }
	.card-danger { border-color: rgba(229, 57, 53, 0.3); }
	.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-md); margin-bottom: var(--space-lg); }
	.label-text { display: block; font-size: 0.8rem; font-weight: 600; color: var(--color-text-secondary); margin-bottom: var(--space-xs); }
	input { width: 100%; padding: var(--space-sm) var(--space-md); border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.9rem; background: var(--color-bg); }
	input:focus { outline: none; border-color: var(--color-primary); }
	input:disabled { opacity: 0.6; cursor: not-allowed; }
	.section-desc { font-size: 0.85rem; color: var(--color-text-secondary); margin-bottom: var(--space-md); line-height: 1.5; }
	.btn { display: inline-flex; align-items: center; gap: var(--space-sm); padding: var(--space-sm) var(--space-lg); border-radius: var(--radius-md); font-size: 0.85rem; font-weight: 600; transition: all var(--transition-fast); cursor: pointer; }
	.btn-primary { background: var(--color-primary); color: white; border: none; }
	.btn-primary:hover { background: var(--color-primary-hover); }
	.btn-outline { background: transparent; border: 1.5px solid var(--color-border); color: var(--color-text); }
	.btn-outline:hover { border-color: var(--color-primary); color: var(--color-primary); }
	.btn-danger { background: transparent; border: 1.5px solid rgba(229, 57, 53, 0.3); color: var(--color-danger); }
	.btn-danger:hover { background: var(--color-danger-light); }
	.btn-save { width: auto; }
	.btn-row { display: flex; gap: var(--space-sm); flex-wrap: wrap; }
	.error-text { color: #ef5350; font-size: 0.85rem; margin-top: var(--space-sm); }
	.ok-text { color: #66bb6a; font-size: 0.85rem; margin-top: var(--space-sm); }
	.danger-heading { color: var(--color-danger); }
	.material-symbols { font-family: 'Material Symbols Outlined'; font-size: 1.1rem; }
</style>
