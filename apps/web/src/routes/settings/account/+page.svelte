<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';
	import { downloadFile } from '$lib/gpx';
	import { fetchRuns } from '$lib/data';
	import {
		loadSettings,
		updateUniversal,
		effective,
		type LoadedSettings,
	} from '$lib/settings';
	import {
		createBackup,
		restoreBackup,
		type BackupProgress,
		type RestoreProgress,
		type RestoreResult,
	} from '$lib/backup';

	let displayName = $state(auth.user?.display_name ?? '');
	let parkrunNumber = $state(auth.user?.parkrun_number ?? '');
	let preferredUnit = $state<'km' | 'mi'>(auth.user?.preferred_unit ?? 'km');
	let saving = $state(false);
	let saved = $state(false);
	let exporting = $state(false);

	let settings = $state<LoadedSettings | null>(null);
	let backingUp = $state(false);
	let backupProgress = $state<BackupProgress | null>(null);
	let restoring = $state(false);
	let restoreProgress = $state<RestoreProgress | null>(null);
	let restoreResult = $state<RestoreResult | null>(null);
	let restoreError = $state<string | null>(null);
	let restoreFileInput: HTMLInputElement;
	let defaultActivityType = $state<'run' | 'walk' | 'hike' | 'cycle'>('run');
	let weekStartDay = $state<'monday' | 'sunday'>('monday');
	let prefsSaving = $state(false);
	let prefsSaved = $state(false);

	onMount(async () => {
		if (!auth.user) return;
		try {
			settings = await loadSettings(auth.user.id);
			defaultActivityType =
				effective<'run' | 'walk' | 'hike' | 'cycle'>(
					settings,
					'default_activity_type',
					'run'
				) ?? 'run';
			weekStartDay =
				effective<'monday' | 'sunday'>(settings, 'week_start_day', 'monday') ??
				'monday';
			// Universal bag is source-of-truth for preferred_unit going
			// forward; fall back to the profile column for existing users.
			const fromBag = effective<'km' | 'mi'>(settings, 'preferred_unit');
			if (fromBag) preferredUnit = fromBag;
		} catch (e) {
			console.warn('Settings load failed', e);
		}
	});

	// Password management. Lets a user who signed up with Google / Apple
	// add a password so they can also sign in via email+password on the
	// Wear OS app (whose sign-in form uses Supabase's password grant).
	let newPassword = $state('');
	let confirmPassword = $state('');
	let passwordSaving = $state(false);
	let passwordStatus = $state<string | null>(null);
	let passwordError = $state<string | null>(null);

	async function handleSavePassword() {
		if (newPassword.length < 6) {
			passwordError = 'Password must be at least 6 characters.';
			return;
		}
		if (newPassword !== confirmPassword) {
			passwordError = 'Passwords do not match.';
			return;
		}
		passwordSaving = true;
		passwordError = null;
		passwordStatus = null;
		const { error } = await supabase.auth.updateUser({ password: newPassword });
		passwordSaving = false;
		if (error) {
			passwordError = error.message;
		} else {
			passwordStatus = 'Password saved. You can now sign in with your email on any device.';
			newPassword = '';
			confirmPassword = '';
			setTimeout(() => (passwordStatus = null), 5000);
		}
	}

	async function handleSave() {
		if (!auth.user) return;
		saving = true;
		saved = false;
		// Dual-write `preferred_unit` — profile column stays canonical for
		// legacy reads (web, older mobile builds); the jsonb bag is what
		// newer clients pull on sign-in. Next migration removes the column.
		await Promise.all([
			supabase.from('user_profiles').update({
				display_name: displayName || null,
				parkrun_number: parkrunNumber || null,
				preferred_unit: preferredUnit,
			}).eq('id', auth.user.id),
			updateUniversal(auth.user.id, { preferred_unit: preferredUnit }),
		]);
		saved = true;
		saving = false;
		setTimeout(() => (saved = false), 2000);
	}

	async function handleSavePrefs() {
		if (!auth.user) return;
		prefsSaving = true;
		prefsSaved = false;
		await updateUniversal(auth.user.id, {
			default_activity_type: defaultActivityType,
			week_start_day: weekStartDay,
		});
		prefsSaved = true;
		prefsSaving = false;
		setTimeout(() => (prefsSaved = false), 2000);
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
		} finally {
			exporting = false;
		}
	}

	async function handleBackup() {
		backingUp = true;
		backupProgress = null;
		try {
			const blob = await createBackup((p) => (backupProgress = p));
			const url = URL.createObjectURL(blob);
			const a = document.createElement('a');
			const ts = new Date().toISOString().replace(/[:.]/g, '-');
			a.href = url;
			a.download = `run-app-backup-${ts}.zip`;
			document.body.appendChild(a);
			a.click();
			a.remove();
			URL.revokeObjectURL(url);
		} catch (e) {
			console.error(e);
			alert(`Backup failed: ${(e as Error).message}`);
		} finally {
			backingUp = false;
			backupProgress = null;
		}
	}

	async function handleRestoreFile(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;
		if (!confirm(
			`Restore from "${file.name}"?\n\n` +
				'This adds or overwrites runs and routes matching IDs in the backup. ' +
				'It will not delete runs or routes that aren\'t in the backup.'
		)) {
			input.value = '';
			return;
		}
		restoring = true;
		restoreProgress = null;
		restoreResult = null;
		restoreError = null;
		try {
			const res = await restoreBackup(file, {
				onProgress: (p) => (restoreProgress = p),
			});
			restoreResult = res;
		} catch (err) {
			restoreError = (err as Error).message;
		} finally {
			restoring = false;
			restoreProgress = null;
			input.value = '';
		}
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
				<span class="label-text">parkrun Athlete Number</span>
				<input type="text" bind:value={parkrunNumber} placeholder="A123456" />
			</label>
		</div>
		<button class="btn btn-primary btn-save" onclick={handleSave} disabled={saving}>
		{saving ? 'Saving...' : saved ? 'Saved!' : 'Save Changes'}
	</button>
	</section>

	<!-- Preferences -->
	<section class="card">
		<h2>Preferences</h2>
		<p class="section-desc">
			These settings sync to every device you sign into. Per-device overrides live in each
			app's settings screen.
		</p>
		<label>
			<span class="label-text">Distance Unit</span>
			<div class="unit-toggle">
				<button
					class="unit-btn"
					class:active={preferredUnit === 'km'}
					onclick={() => (preferredUnit = 'km')}
				>
					Kilometres
				</button>
				<button
					class="unit-btn"
					class:active={preferredUnit === 'mi'}
					onclick={() => (preferredUnit = 'mi')}
				>
					Miles
				</button>
			</div>
		</label>
		<label>
			<span class="label-text">Default activity</span>
			<select bind:value={defaultActivityType}>
				<option value="run">Run</option>
				<option value="walk">Walk</option>
				<option value="hike">Hike</option>
				<option value="cycle">Cycle</option>
			</select>
		</label>
		<label>
			<span class="label-text">Week starts on</span>
			<select bind:value={weekStartDay}>
				<option value="monday">Monday</option>
				<option value="sunday">Sunday</option>
			</select>
		</label>
		<button
			class="btn btn-primary btn-save"
			onclick={handleSavePrefs}
			disabled={prefsSaving}
		>
			{prefsSaving ? 'Saving...' : prefsSaved ? 'Saved!' : 'Save Preferences'}
		</button>
	</section>

	<!-- Sign-in password -->
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
				<input
					type="password"
					autocomplete="new-password"
					bind:value={newPassword}
					placeholder="At least 6 characters"
				/>
			</label>
			<label>
				<span class="label-text">Confirm Password</span>
				<input
					type="password"
					autocomplete="new-password"
					bind:value={confirmPassword}
				/>
			</label>
		</div>
		{#if passwordError}
			<p class="password-error">{passwordError}</p>
		{/if}
		{#if passwordStatus}
			<p class="password-ok">{passwordStatus}</p>
		{/if}
		<button
			class="btn btn-primary btn-save"
			onclick={handleSavePassword}
			disabled={passwordSaving || !newPassword || !confirmPassword}
		>
			{passwordSaving ? 'Saving...' : 'Save Password'}
		</button>
	</section>

	<!-- Data -->
	<section class="card">
		<h2>Backup & Restore</h2>
		<p class="section-desc">
			Full backup includes every run with its GPS trace, your routes, profile, and preferences —
			a lossless archive you can restore on this account or a fresh one.
		</p>
		<div class="backup-row">
			<button class="btn btn-primary" onclick={handleBackup} disabled={backingUp || restoring}>
				<span class="material-symbols">archive</span>
				{backingUp
					? backupProgress
						? `${backupProgress.stage}… (${backupProgress.current}/${backupProgress.total})`
						: 'Backing up…'
					: 'Download full backup'}
			</button>
			<button
				class="btn btn-outline"
				onclick={() => restoreFileInput.click()}
				disabled={backingUp || restoring}
			>
				<span class="material-symbols">unarchive</span>
				{restoring
					? restoreProgress
						? `${restoreProgress.stage}… (${restoreProgress.current}/${restoreProgress.total})`
						: 'Restoring…'
					: 'Restore from backup'}
			</button>
			<input
				bind:this={restoreFileInput}
				type="file"
				accept=".zip,application/zip"
				onchange={handleRestoreFile}
				style="display: none"
			/>
		</div>
		{#if restoreResult}
			<p class="restore-ok">
				Restored {restoreResult.runsImported} runs · {restoreResult.tracksUploaded} tracks ·
				{restoreResult.routesImported} routes{#if restoreResult.profileRestored} · profile{/if}.
				{#if restoreResult.warnings.length > 0}
					<br /><small>{restoreResult.warnings.length} warnings (see console).</small>
				{/if}
			</p>
		{/if}
		{#if restoreError}
			<p class="password-error">Restore failed: {restoreError}</p>
		{/if}
	</section>

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
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 40rem;
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		margin-bottom: var(--space-lg);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}

	.card-danger {
		border-color: rgba(229, 57, 53, 0.3);
	}

	.password-error {
		color: #ef5350;
		font-size: 0.85rem;
		margin-top: var(--space-sm);
	}

	.password-ok {
		color: #66bb6a;
		font-size: 0.85rem;
		margin-top: var(--space-sm);
	}

	.form-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-md);
		margin-bottom: var(--space-lg);
	}

	.label-text {
		display: block;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xs);
	}

	input {
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		background: var(--color-bg);
		transition: border-color var(--transition-fast);
	}

	input:focus {
		outline: none;
		border-color: var(--color-primary);
	}

	.unit-toggle {
		display: flex;
		gap: var(--space-sm);
	}

	.unit-btn {
		flex: 1;
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
	}

	.unit-btn:hover {
		border-color: var(--color-primary);
	}

	.unit-btn.active {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.section-desc {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-md);
		line-height: 1.5;
	}

	.export-buttons {
		display: flex;
		gap: var(--space-sm);
	}

	.btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		font-weight: 600;
		transition: all var(--transition-fast);
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
	}

	.btn-outline {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-outline:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.btn-danger {
		background: transparent;
		border: 1.5px solid rgba(229, 57, 53, 0.3);
		color: var(--color-danger);
	}

	.btn-danger:hover {
		background: var(--color-danger-light);
	}

	.btn-save {
		width: auto;
	}

	.danger-heading {
		color: var(--color-danger);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}

	.backup-row {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.restore-ok {
		margin-top: var(--space-md);
		color: #2e7d32;
		font-size: 0.85rem;
	}
</style>
