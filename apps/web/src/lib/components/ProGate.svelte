<script lang="ts">
	import { featureLabel, featureDescription } from '$lib/features';

	interface Props {
		feature: string;
	}

	let { feature }: Props = $props();
</script>

<div class="pro-gate">
	<div class="pro-icon">
		<span class="material-symbols">lock</span>
	</div>
	<h3>{featureLabel(feature)}</h3>
	<p class="desc">{featureDescription(feature)}</p>
	<span class="pro-badge">PRO</span>
	<p class="cta">Upgrade to Pro to unlock this feature.</p>
	<a href="/settings/upgrade" class="btn-upgrade">
		<span class="material-symbols">star</span>
		Upgrade
	</a>
</div>

<style>
	.pro-gate {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.6rem;
		padding: 2rem 1.5rem;
		text-align: center;
		background: var(--color-surface);
		border: 1.5px dashed var(--color-border);
		border-radius: var(--radius-lg);
	}
	.pro-icon {
		width: 3rem;
		height: 3rem;
		border-radius: 50%;
		background: rgba(79, 70, 229, 0.08);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.pro-icon .material-symbols {
		font-size: 1.5rem;
		color: var(--color-primary);
	}
	h3 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0;
	}
	.desc {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		max-width: 28rem;
		line-height: 1.5;
	}
	.pro-badge {
		display: inline-block;
		background: var(--color-primary);
		color: white;
		font-size: 0.65rem;
		font-weight: 800;
		letter-spacing: 0.08em;
		padding: 0.15rem 0.6rem;
		border-radius: 9999px;
	}
	.cta {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
	.btn-upgrade {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.5rem 1.2rem;
		background: var(--color-primary);
		color: white;
		border: none;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
		font-weight: 600;
		text-decoration: none;
		transition: background var(--transition-fast);
	}
	.btn-upgrade:hover {
		background: var(--color-primary-hover);
	}
	.btn-upgrade .material-symbols {
		font-size: 1rem;
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		display: inline-block;
		line-height: 1;
	}
</style>
