<script lang="ts">
	let displayName = $state('Jared Howard');
	let parkrunNumber = $state('A123456');
	let preferredUnit = $state<'km' | 'mi'>('km');
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
		<button class="btn btn-primary btn-save">Save Changes</button>
	</section>

	<!-- Preferences -->
	<section class="card">
		<h2>Preferences</h2>
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
	</section>

	<!-- Data -->
	<section class="card">
		<h2>Data Export</h2>
		<p class="section-desc">Download all your data. Available as GPX (routes + GPS traces) or CSV (run history).</p>
		<div class="export-buttons">
			<button class="btn btn-outline">
				<span class="material-symbols">download</span>
				Export as GPX
			</button>
			<button class="btn btn-outline">
				<span class="material-symbols">download</span>
				Export as CSV
			</button>
		</div>
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
</style>
