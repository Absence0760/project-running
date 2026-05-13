<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchRunGear, fetchMyGear, setRunGear, type Gear, type GearWithDistance } from '$lib/data';
	import Modal from '$lib/components/Modal.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	interface Props {
		runId: string;
		runOwnerId: string;
	}
	let { runId, runOwnerId }: Props = $props();

	let assigned = $state<Gear[]>([]);
	let loading = $state(true);
	let editing = $state(false);
	let myGear = $state<GearWithDistance[]>([]);
	let selected = $state<Set<string>>(new Set());
	let saving = $state(false);

	const canManage = $derived(auth.user?.id === runOwnerId);

	onMount(async () => {
		assigned = await fetchRunGear(runId);
		loading = false;
	});

	async function openEditor() {
		if (myGear.length === 0) {
			myGear = await fetchMyGear();
		}
		selected = new Set(assigned.map((g) => g.id));
		editing = true;
	}

	async function save() {
		saving = true;
		try {
			await setRunGear(runId, Array.from(selected));
			assigned = await fetchRunGear(runId);
			editing = false;
		} catch (e) {
			showToast(`Save failed: ${(e as Error).message}`, 'error');
		} finally {
			saving = false;
		}
	}

	function toggle(id: string) {
		const next = new Set(selected);
		if (next.has(id)) next.delete(id);
		else next.add(id);
		selected = next;
	}
</script>

{#if loading}
	<!-- silent — gear is decorative -->
{:else if assigned.length > 0 || canManage}
	<div class="gear-strip">
		{#each assigned as g (g.id)}
			<span class="gear-chip">
				<span class="material-symbols">
					{g.kind === 'bike' ? 'directions_bike' : 'directions_run'}
				</span>
				{g.name}
			</span>
		{/each}
		{#if canManage}
			<button class="edit-btn" onclick={openEditor}>
				{assigned.length === 0 ? '+ Tag gear' : 'Edit'}
			</button>
		{/if}
	</div>
{/if}

<Modal open={editing} onclose={() => (editing = false)} title="Tag gear used on this run">
	{#if myGear.length === 0}
		<p class="muted">
			You haven't registered any gear yet. Add some on the <a href="/settings/gear">Gear settings page</a>.
		</p>
	{:else}
		<ul class="picker">
			{#each myGear.filter((g) => !g.retired_at) as g (g.id)}
				<li>
					<label>
						<input
							type="checkbox"
							checked={selected.has(g.id)}
							onchange={() => toggle(g.id)}
						/>
						<span class="material-symbols">
							{g.kind === 'bike' ? 'directions_bike' : 'directions_run'}
						</span>
						<span>{g.name}</span>
						{#if g.brand || g.model}
							<span class="muted">{[g.brand, g.model].filter(Boolean).join(' ')}</span>
						{/if}
					</label>
				</li>
			{/each}
		</ul>
	{/if}
	<footer class="footer">
		<button class="btn-outline" onclick={() => (editing = false)}>Cancel</button>
		<button class="btn-primary" onclick={save} disabled={saving}>
			{saving ? 'Saving…' : 'Save'}
		</button>
	</footer>
</Modal>

<style>
	.gear-strip {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		flex-wrap: wrap;
		padding: var(--space-sm) 0;
	}
	.gear-chip {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.25rem 0.6rem;
		background: var(--color-bg-tertiary);
		border-radius: 999px;
		font-size: 0.82rem;
		color: var(--color-text);
	}
	.gear-chip .material-symbols { font-size: 0.95em; opacity: 0.7; }
	.edit-btn {
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		padding: 0.2rem 0.7rem;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.edit-btn:hover { color: var(--color-text); border-color: var(--color-text-tertiary); }
	.picker {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		max-height: 50vh;
		overflow-y: auto;
	}
	.picker label {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.5rem;
		border-radius: var(--radius-sm);
		cursor: pointer;
	}
	.picker label:hover { background: var(--color-bg-tertiary); }
	.muted { color: var(--color-text-tertiary); font-size: 0.85rem; }
	.footer {
		display: flex;
		gap: 0.5rem;
		justify-content: flex-end;
		margin-top: var(--space-md);
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
	}
</style>
